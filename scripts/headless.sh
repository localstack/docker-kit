#!/usr/bin/env bash
# Gives an agent a fixed task in a new sandbox, then checks the result from
# outside the agent. The task deploys an S3 bucket and a Lambda function to
# LocalStack with Terraform. Each run uses model credits.
#
# Usage: scripts/headless.sh claude|codex [--registry HOST] [--keep]
#
# LOCALSTACK_AUTH_TOKEN must be set in the calling shell, and sbx must have
# the agent credential (anthropic for claude, openai for codex).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
# shellcheck source=scripts/lib/sandbox.sh
source "$REPO_ROOT/scripts/lib/sandbox.sh"

readonly BUCKET=lskit-e2e-uploads
readonly FUNCTION=lskit-e2e-writer
readonly TASK="In the current directory, write Terraform that creates an S3 bucket named $BUCKET \
and a Python 3.12 Lambda function named $FUNCTION. The function writes an object with key \
hello.txt and body 'hello from lambda' to that bucket. Deploy it to LocalStack with tflocal, \
then invoke the function one time. Stop when the object is in the bucket."

workspace=""

main() {
  parse_sandbox_args "$@"
  require_auth_token
  workspace="$(new_workspace e2e)"
  create_sandbox "e2e" "$workspace"
  run_check "LocalStack is running" wait_for_localstack
  run_check "$agent completes the task" run_agent_task
  run_check "Terraform files are in the workspace" compgen -G "$workspace/*.tf"
  run_check "Lambda function exists" in_sandbox \
    "aws lambda get-function --function-name $FUNCTION >/dev/null"
  run_check "Lambda wrote the object" in_sandbox \
    "aws s3api head-object --bucket $BUCKET --key hello.txt >/dev/null"
  report_results
}

run_agent_task() {
  local log="$workspace/agent.log"
  echo "==> $agent is working, log: $log"
  in_sandbox "cd $(printf %q "$workspace") && $(agent_command)" >"$log" 2>&1
}

agent_command() {
  case "$agent" in
    claude) echo "claude --dangerously-skip-permissions -p $(printf %q "$TASK")" ;;
    codex) echo "codex exec --skip-git-repo-check $(printf %q "$TASK")" ;;
  esac
}

main "$@"
