#!/usr/bin/env bash
# Creates a sandbox from a per-agent kit set and checks the LocalStack setup
# without an agent prompt, so it uses no model credits.
#
# The sandbox uses a kit argument and a LOCALSTACK_* variable, so the run
# also checks that both reach LocalStack.
#
# Usage: scripts/smoke.sh claude|codex [--registry HOST] [--keep]
#
# LOCALSTACK_AUTH_TOKEN must be set in the calling shell.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
# shellcheck source=scripts/lib/sandbox.sh
source "$REPO_ROOT/scripts/lib/sandbox.sh"

# The same digest as the default tag, so the pull costs nothing extra, but a
# different name, so the check can see that the argument applied.
readonly KIT_ARG_IMAGE=localstack/localstack-pro:2026.8
readonly PROXY_DENIED_URLS=(
  http://localhost.localstack.cloud:4566/_localstack/health
  http://s3.localhost.localstack.cloud:4566/_localstack/health
  http://localhost:4566/_localstack/health
  http://127.0.0.1:4566/_localstack/health
  http://host.docker.internal:4566/_localstack/health
)

main() {
  parse_sandbox_args "$@"
  require_auth_token
  create_sandbox "smoke" "$(new_workspace smoke)" \
    -e LOCALSTACK_DEBUG=1 --kit-arg "localstack_image=$KIT_ARG_IMAGE"
  check_localstack
  check_isolation
  check_tools
  check_mcp
  check_restart
  report_results
}

check_localstack() {
  run_check "LocalStack is running" wait_for_localstack
  run_check "The localstack_image kit argument selects the image" in_sandbox \
    "docker ps --format '{{.Image}}' | grep -qx $KIT_ARG_IMAGE"
  run_check "LOCALSTACK_* variables reach LocalStack" in_sandbox \
    "docker inspect \"\$(cat /tmp/localstack-kit/container-name)\" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -qx LOCALSTACK_DEBUG=1"
  run_check "AWS CLI reaches LocalStack" in_sandbox \
    'aws s3 mb s3://lskit-smoke >/dev/null && aws s3 ls | grep -q lskit-smoke'
  run_check "A snapshot saves and loads LocalStack state" check_snapshot
}

# Resets LocalStack between the save and the load, so the bucket comes back
# only from the snapshot.
check_snapshot() {
  in_sandbox 'lstk snapshot save ./smoke.snapshot >/dev/null \
    && lstk reset --force >/dev/null && ! aws s3 ls | grep -q lskit-smoke \
    && lstk snapshot load ./smoke.snapshot >/dev/null && aws s3 ls | grep -q lskit-smoke'
}

check_isolation() {
  local url
  run_check "LocalStack hostnames reach the sandbox emulator" in_sandbox \
    'aws --endpoint-url http://localhost.localstack.cloud:4566 s3 ls | grep -q lskit-smoke'
  for url in "${PROXY_DENIED_URLS[@]}"; do
    run_check "The proxy refuses $url" check_proxy_refuses "$url"
  done
}

# --noproxy '' makes curl use the proxy even for names in NO_PROXY.
check_proxy_refuses() {
  local status
  status="$(in_sandbox "curl -s -o /dev/null -w '%{http_code}' --noproxy '' $1")"
  echo "proxy status: $status"
  [[ "$status" == 403 ]]
}

check_tools() {
  run_check "tflocal runs Terraform through lstk" in_sandbox 'tflocal version'
  run_check "Docker pulls an AWS Lambda base image" in_sandbox \
    'docker pull -q public.ecr.aws/lambda/python:3.12'
}

check_mcp() {
  run_check "MCP server lists LocalStack tools" check_mcp_tools
  run_check "MCP server is registered with $agent" check_mcp_registration
  if [[ "$agent" == codex ]]; then
    run_check "MCP server works with the variables that Codex passes" check_mcp_with_codex_env
  fi
}

check_mcp_tools() {
  local tool_count
  tool_count="$(in_sandbox "$(mcp_request_command tools/list '{}')" | grep -o '"name":"localstack-[a-z-]*"' | sort -u | wc -l)"
  echo "tools: $tool_count"
  ((tool_count >= 10))
}

check_mcp_registration() {
  case "$agent" in
    claude) in_sandbox 'claude mcp list' | grep -q '^localstack:' ;;
    codex) in_sandbox 'codex mcp list' | grep -q 'localstack' ;;
  esac
}

# Codex starts a stdio MCP server with a short list of variables and the
# names in env_vars. This check starts the server with the same variables.
check_mcp_with_codex_env() {
  local request
  request="$(mcp_request_command tools/call '{"name":"localstack-management","arguments":{"action":"status"}}')"
  in_sandbox 'grep -q "^env_vars = \[\"LOCALSTACK_AUTH_TOKEN\"" ~/.codex/config.toml' || return 1
  in_sandbox "env -i HOME=\"\$HOME\" PATH=\"\$PATH\" USER=\"\$USER\" LOCALSTACK_AUTH_TOKEN=\"\$LOCALSTACK_AUTH_TOKEN\" bash -c $(printf %q "$request")" \
    | grep -q 'currently running'
}

check_restart() {
  run_check "LocalStack starts again after the sandbox restarts" restart_sandbox
  run_check "LocalStack answers after the restart" in_sandbox \
    'curl -s -m 5 -o /dev/null -w "%{http_code}" http://localhost:4566/_localstack/health | grep -qx 200'
}

restart_sandbox() {
  stop_keepalive_session
  sbx stop "$sandbox_name" >/dev/null
  start_keepalive_session
  wait_for_localstack
}

main "$@"
