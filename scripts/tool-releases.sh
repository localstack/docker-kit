#!/usr/bin/env bash
# Prints the current releases of the tools that the mixin follows, as
# NAME=VERSION lines. The names are the kit arguments, and the format suits
# GITHUB_OUTPUT.
#
# Usage: scripts/tool-releases.sh
set -euo pipefail

main() {
  print_release lstk_version "$(lstk_release)"
  print_release mcp_server_version "$(mcp_server_release)"
}

# The latest-release page of GitHub redirects to the page of its tag.
lstk_release() {
  curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/localstack/lstk/releases/latest \
    | sed 's#.*/tag/v##'
}

mcp_server_release() {
  npm view @localstack/localstack-mcp-server version
}

print_release() {
  if [[ ! "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "cannot find the current release for $1 (got '$2')" >&2
    exit 1
  fi
  echo "$1=$2"
}

main "$@"
