#!/usr/bin/env bash
# Runs shellcheck on every shell script that git tracks. A file counts as a
# shell script when its first line is a sh or bash shebang or a shellcheck
# shell directive.
#
# Usage: scripts/lint.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
readonly SHELLCHECK_IMAGE=koalaman/shellcheck:stable

main() {
  cd "$REPO_ROOT"
  shell_scripts | xargs docker run --rm -v "$REPO_ROOT:/mnt" -w /mnt "$SHELLCHECK_IMAGE" -x
  echo "shellcheck: no findings"
}

shell_scripts() {
  git ls-files | while IFS= read -r file; do
    if [[ -f "$file" && ! -L "$file" ]] && head -n 1 "$file" | grep -q -E '^#!.*(bash|/sh)$|^# shellcheck shell='; then
      echo "$file"
    fi
  done
}

main "$@"
