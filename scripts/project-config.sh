#!/usr/bin/env bash
# Checks that the kit starts LocalStack with a project lstk config, and that
# it guards against an untrusted one. The run creates four sandboxes:
#
#   1. .lstk/config.toml, found by the kit. It binds all interfaces, so the
#      run also checks that sbx -p publishes LocalStack to the host.
#   2. lstk/explicit.toml, named by -e LSKIT_LSTK_CONFIG. It must win over
#      .lstk/config.toml. It binds loopback, so the start log must have a hint.
#   3. A config that starts an image outside localstack/. The kit must refuse
#      to start it.
#   4. The same config with -e LSKIT_IGNORE_PROJECT_CONFIG=1. The kit must use
#      its own config.
#
# The run uses no model credits.
#
# Usage: scripts/project-config.sh claude|codex [--registry HOST] [--keep]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
# shellcheck source=scripts/lib/sandbox.sh
source "$REPO_ROOT/scripts/lib/sandbox.sh"

readonly HOST_PORT=$((45000 + RANDOM % 1000))
readonly LOCALSTACK_IMAGE=localstack/localstack-pro:2026.8.4
readonly FOREIGN_IMAGE=busybox:latest

main() {
  parse_sandbox_args "$@"
  require_auth_token
  check_found_and_explicit_configs "$(new_workspace project-config)"
  check_untrusted_config "$(new_workspace untrusted-config)"
  report_results
}

check_found_and_explicit_configs() {
  local workspace="$1"
  write_project_config "$workspace/.lstk/config.toml" lskit-project '"0.0.0.0:4566,0.0.0.0:443"'
  write_project_config "$workspace/lstk/explicit.toml" lskit-explicit '":4566,:443"'

  create_sandbox "project" "$workspace" -p "$HOST_PORT:4566"
  check_project_config lskit-project
  run_check "sbx -p publishes LocalStack to the host" check_host_port
  remove_sandbox

  create_sandbox "explicit" "$workspace" -e LSKIT_LSTK_CONFIG=lstk/explicit.toml
  check_project_config lskit-explicit
  run_check "The start log explains why host publishing is off" in_sandbox \
    'grep -q "sbx -p cannot publish" /tmp/localstack-kit/start.log'
  remove_sandbox
}

check_untrusted_config() {
  local workspace="$1"
  write_project_config "$workspace/.lstk/config.toml" lskit-untrusted '":4566,:443"' "$FOREIGN_IMAGE"

  create_sandbox "rejected" "$workspace"
  run_check "The kit refuses a project config with a foreign image" check_boot_state config-rejected
  run_check "No container runs the foreign image" in_sandbox \
    "! docker ps -a --format '{{.Image}}' | grep -qx $FOREIGN_IMAGE"
  remove_sandbox

  create_sandbox "ignored" "$workspace" -e LSKIT_IGNORE_PROJECT_CONFIG=1
  run_check "LocalStack is running" wait_for_localstack
  # $HOME must expand in the sandbox, not here.
  # shellcheck disable=SC2016
  run_check "LSKIT_IGNORE_PROJECT_CONFIG makes the kit use its own config" in_sandbox \
    'grep -qx "$HOME/.config/lstk/config.toml" /tmp/localstack-kit/config-path'
  remove_sandbox
}

write_project_config() {
  local path="$1" container="$2" gateway="$3" image="${4:-$LOCALSTACK_IMAGE}"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
[[containers]]
type = "aws"
image = "$image"
port = "4566"
container_name = "$container"
env = ["project"]

[env.project]
DEBUG = "1"
GATEWAY_LISTEN = $gateway
EOF
}

check_project_config() {
  local container="$1"
  run_check "LocalStack is running" wait_for_localstack
  run_check "LocalStack runs as $container" in_sandbox \
    "docker ps --format '{{.Names}}' | grep -qx $container"
  run_check "Profile variables reach LocalStack" container_env_has "$container" DEBUG=1
  run_check "Kit defaults fill settings that the config leaves out" \
    container_env_has "$container" LOCALSTACK_LAMBDA_IGNORE_ARCHITECTURE=1
  run_check "lstk outside the project root uses the same config" in_sandbox \
    "cd /tmp && lstk status --json | grep -q '\"name\":\"$container\"'"
  run_check "The MCP server reports LocalStack as running" check_mcp_status
  run_check "AWS CLI reaches LocalStack" in_sandbox \
    'aws s3 mb s3://lskit-project-config >/dev/null && aws s3 ls | grep -q lskit-project-config'
}

check_boot_state() {
  local state
  state="$(wait_for_boot_state)"
  echo "boot state: $state"
  [[ "$state" == "$1" ]]
}

container_env_has() {
  local container="$1" variable="$2"
  in_sandbox "docker inspect $container --format '{{range .Config.Env}}{{println .}}{{end}}'" \
    | grep -qx "$variable"
}

check_mcp_status() {
  in_sandbox "$(mcp_request_command tools/call '{"name":"localstack-management","arguments":{"action":"status"}}')" \
    | grep -q 'currently running'
}

check_host_port() {
  local status
  status="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://localhost:$HOST_PORT/_localstack/health")"
  echo "host port $HOST_PORT: $status"
  [[ "$status" == 200 ]]
}

main "$@"
