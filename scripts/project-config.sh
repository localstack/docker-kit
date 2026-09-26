#!/usr/bin/env bash
# Checks that the kit starts LocalStack with a project lstk config. One
# workspace holds two configs, and the run creates two sandboxes from it:
#
#   1. .lstk/config.toml, found by the kit. It binds all interfaces, so the
#      run also checks that sbx -p publishes LocalStack to the host.
#   2. lstk/explicit.toml, named by -e LSKIT_LSTK_CONFIG. It must win over
#      .lstk/config.toml. It binds loopback, so the start log must have a hint.
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

main() {
  local workspace
  parse_sandbox_args "$@"
  require_auth_token
  workspace="$(new_workspace project-config)"
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
  report_results
}

write_project_config() {
  local path="$1" container="$2" gateway="$3"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
[[containers]]
type = "aws"
image = "localstack/localstack-pro:2026.8.4"
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
