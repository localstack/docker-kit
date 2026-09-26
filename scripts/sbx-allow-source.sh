#!/usr/bin/env bash
# Adds a prefix to the kit sources that sbx allows, and keeps the other
# prefixes in the list. Needs jq.
#
# Usage: scripts/sbx-allow-source.sh PREFIX
set -euo pipefail

main() {
  local prefix="${1:?usage: $0 PREFIX}" current updated
  current="$(sbx settings get kit.allowedSources)"
  updated="$(jq -c --arg prefix "$prefix" 'if index($prefix) then . else . + [$prefix] end' <<<"$current")"
  if [[ "$updated" == "$(jq -c . <<<"$current")" ]]; then
    echo "sbx already allows $prefix"
    return 0
  fi
  sbx settings set kit.allowedSources "$updated"
}

main "$@"
