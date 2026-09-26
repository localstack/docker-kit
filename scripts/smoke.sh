#!/usr/bin/env bash
# Creates a sandbox from a per-agent kit set and checks the LocalStack setup
# without an agent prompt, so it uses no model credits.
#
# Usage: scripts/smoke.sh claude|codex [--registry HOST] [--keep]
#
# LOCALSTACK_AUTH_TOKEN must be set in the calling shell.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
# shellcheck source=scripts/lib/sandbox.sh
source "$REPO_ROOT/scripts/lib/sandbox.sh"

main() {
  parse_sandbox_args "$@"
  require_auth_token
  create_sandbox "smoke" "$(new_workspace smoke)"
  run_check "LocalStack is running" wait_for_localstack
  run_check "AWS CLI reaches LocalStack" in_sandbox \
    'aws s3 mb s3://lskit-smoke >/dev/null && aws s3 ls | grep -q lskit-smoke'
  run_check "LocalStack hostnames reach the sandbox emulator" in_sandbox \
    'aws --endpoint-url http://localhost.localstack.cloud:4566 s3 ls | grep -q lskit-smoke'
  run_check "The proxy refuses LocalStack hostnames" check_proxy_refuses_localstack_host
  run_check "tflocal runs Terraform through lstk" in_sandbox 'tflocal version'
  run_check "Docker pulls an AWS Lambda base image" in_sandbox \
    'docker pull -q public.ecr.aws/lambda/python:3.12'
  run_check "MCP server lists LocalStack tools" check_mcp_tools
  run_check "MCP server is registered with $agent" check_mcp_registration
  report_results
}

# --noproxy '' makes curl use the proxy even for names in NO_PROXY.
check_proxy_refuses_localstack_host() {
  local status
  status="$(in_sandbox "curl -s -o /dev/null -w '%{http_code}' --noproxy '' http://localhost.localstack.cloud:4566/_localstack/health")"
  echo "proxy status: $status"
  [[ "$status" == 403 ]]
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

main "$@"
