# shellcheck shell=bash
# Shared helpers for the sandbox test scripts. Source this file after you set
# REPO_ROOT.

readonly KIT_NAMESPACE=localstack
readonly LOCALSTACK_WAIT_SECONDS=420

agent=""
registry=docker.io
keep_sandbox=false
sandbox_name=""
keepalive_pid=""
failed_checks=0

parse_sandbox_args() {
  agent="${1:-}"
  case "$agent" in
    claude | codex) shift ;;
    *)
      echo "usage: $(basename "$0") claude|codex [--registry HOST] [--keep]" >&2
      exit 2
      ;;
  esac
  parse_sandbox_options "$@"
}

parse_sandbox_options() {
  while (($# > 0)); do
    case "$1" in
      --registry) registry="$2"; shift 2 ;;
      --keep) keep_sandbox=true; shift ;;
      *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
  done
}

# Uses LOCALSTACK_AUTH_TOKEN from the shell. On macOS, falls back to the token
# that lstk keeps in the keychain after lstk login.
require_auth_token() {
  if [[ -z "${LOCALSTACK_AUTH_TOKEN:-}" ]]; then
    LOCALSTACK_AUTH_TOKEN="$(lstk_keychain_token)"
    export LOCALSTACK_AUTH_TOKEN
    if [[ -n "$LOCALSTACK_AUTH_TOKEN" ]]; then
      echo "==> using the LocalStack token of lstk login from the keychain" >&2
    fi
  fi
  if [[ -z "$LOCALSTACK_AUTH_TOKEN" ]]; then
    echo "LOCALSTACK_AUTH_TOKEN is not set, and lstk has no token in the keychain" >&2
    exit 2
  fi
}

# lstk stores the token through go-keyring, which writes the value as
# "go-keyring-base64:" followed by the base64 of the token.
lstk_keychain_token() {
  local stored
  stored="$(security find-generic-password -s lstk -a lstk.auth-token -w 2>/dev/null)" || return 0
  if [[ "$stored" == go-keyring-base64:* ]]; then
    printf '%s' "${stored#go-keyring-base64:}" | base64 -d
  else
    printf '%s' "$stored"
  fi
}

# Workspaces live in the repo, not in the macOS temporary directory, so the
# path that sbx mounts is short and easy to find after a run.
new_workspace() {
  local purpose="$1" dir
  dir="$REPO_ROOT/.work/$purpose-$agent-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  echo "$dir"
}

kit_set_ref() {
  local descriptor="$REPO_ROOT/kits/localstack-$agent/localstack-$agent.yaml"
  echo "$registry/$KIT_NAMESPACE/sbx-localstack-$agent:$(sed -n 's/^version: "\(.*\)"$/\1/p' "$descriptor")"
}

# Creates the sandbox without attaching to it. A bare -e name copies the
# token from this shell, so the value does not show in the process list.
# Arguments after the workspace go to sbx create as flags.
create_sandbox() {
  local purpose="$1" workspace="$2"
  shift 2
  sandbox_name="lskit-$purpose-$agent-$RANDOM"
  trap remove_sandbox EXIT
  echo "==> creating $sandbox_name from $(kit_set_ref)"
  sbx create --name "$sandbox_name" -e LOCALSTACK_AUTH_TOKEN "$@" "$(kit_set_ref)" "$workspace"
  start_keepalive_session
}

# sbx 0.45 stops a local sandbox 30 seconds after its last session ends, and
# LocalStack then restarts empty. An idle exec session keeps the sandbox up
# for the whole test.
start_keepalive_session() {
  sbx exec "$sandbox_name" sleep 86400 >/dev/null 2>&1 &
  keepalive_pid=$!
}

stop_keepalive_session() {
  if [[ -n "$keepalive_pid" ]]; then
    kill "$keepalive_pid" 2>/dev/null || true
    keepalive_pid=""
  fi
}

remove_sandbox() {
  stop_keepalive_session
  if [[ "$keep_sandbox" == true ]]; then
    echo "==> kept $sandbox_name"
    return 0
  fi
  sbx rm --force "$sandbox_name" >/dev/null 2>&1 || true
}

in_sandbox() {
  sbx exec "$sandbox_name" bash -lc "$1"
}

wait_for_localstack() {
  local waited_seconds=0 status
  while ((waited_seconds < LOCALSTACK_WAIT_SECONDS)); do
    status="$(in_sandbox 'lskit-status' || true)"
    case "$status" in
      running) return 0 ;;
      failed | missing-token | config-missing | docker-unavailable) break ;;
    esac
    sleep 5
    waited_seconds=$((waited_seconds + 5))
  done
  in_sandbox 'tail -n 40 /tmp/localstack-kit/start.log' >&2 || true
  return 1
}

# Prints a pipeline that sends the MCP handshake and one request to the
# LocalStack MCP server over stdio. The sleep holds stdin open so that the
# server answers before it sees end of input.
mcp_request_command() {
  local method="$1" params="$2"
  cat <<EOF
{
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"lskit-test","version":"0"}}}'
  echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  echo '{"jsonrpc":"2.0","id":2,"method":"$method","params":$params}'
  sleep 20
} | timeout 40 lskit-mcp 2>/dev/null
EOF
}

run_check() {
  local description="$1"
  shift
  if "$@"; then
    echo "PASS  $description"
  else
    echo "FAIL  $description"
    failed_checks=$((failed_checks + 1))
  fi
}

report_results() {
  if ((failed_checks > 0)); then
    echo "$failed_checks check(s) failed"
    exit 1
  fi
  echo "all checks passed"
}
