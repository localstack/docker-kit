#!/usr/bin/env bash
# Plans a release and writes its notes. The release workflow runs both.
#
# Usage: scripts/release.sh plan [auto|patch|minor|major]
#        scripts/release.sh notes VERSION LSTK_VERSION MCP_SERVER_VERSION
#
# plan prints NAME=VALUE lines for GITHUB_OUTPUT: release (true or false),
# version, lstk_version, and mcp_server_version. With auto, the commit types
# since the last release tag give the bump: a breaking change gives major
# (minor before 1.0.0), feat gives minor, and other types give patch. auto
# skips the release when main has no new commits and lstk and the MCP server
# have no new release. The first release is 0.1.0.
#
# notes prints the Markdown notes of the release. They record the lstk and MCP
# server versions, and plan reads these back from the last release.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
readonly FIRST_VERSION=0.1.0
readonly RELEASE_TAG_PATTERN='^v[0-9]+\.[0-9]+\.[0-9]+$'
readonly LSTK_NOTE='- lstk '
readonly MCP_SERVER_NOTE='- LocalStack MCP server '

main() {
  cd "$REPO_ROOT"
  case "${1:-}" in
    plan) plan "${2:-auto}" ;;
    notes) shift; notes "$@" ;;
    *) usage >&2; exit 2 ;;
  esac
}

usage() {
  sed -n '2,15s/^# \{0,1\}//p' "$0"
}

plan() {
  local bump="$1" tools last_tag
  require_bump "$bump"
  tools="$("$REPO_ROOT/scripts/tool-releases.sh")"
  last_tag="$(last_release_tag)"
  if [[ -z "$last_tag" ]]; then
    print_plan "$FIRST_VERSION" "$tools"
  elif [[ "$bump" != auto ]]; then
    print_plan "$(next_version "$last_tag" "$bump")" "$tools"
  elif has_changes "$last_tag" "$tools"; then
    print_plan "$(next_version "$last_tag" "$(bump_from_commits "$last_tag")")" "$tools"
  else
    echo "Nothing to release since $last_tag." >&2
    echo "release=false"
  fi
}

require_bump() {
  case "$1" in
    auto | patch | minor | major) ;;
    *) echo "unknown bump: $1" >&2; exit 2 ;;
  esac
}

print_plan() {
  echo "release=true"
  echo "version=$1"
  echo "$2"
}

last_release_tag() {
  release_tags | head -n 1
}

release_tags() {
  git tag --list 'v*' --sort=-v:refname | grep -E "$RELEASE_TAG_PATTERN" || true
}

has_changes() {
  local last_tag="$1" tools="$2"
  if [[ -n "$(git log --format=%h "$last_tag..HEAD")" ]]; then
    echo "main has new commits since $last_tag." >&2
    return 0
  fi
  if [[ "$tools" != "$(released_tools "$last_tag")" ]]; then
    echo "lstk or the MCP server has a new release since $last_tag." >&2
    return 0
  fi
  return 1
}

# Reads the versions that notes recorded for a release. A release without the
# record gives empty versions, which count as a change.
released_tools() {
  local body
  body="$(gh release view "$1" --json body --jq .body 2>/dev/null | tr -d '\r' || true)"
  echo "lstk_version=$(sed -n "s/^$LSTK_NOTE//p" <<<"$body")"
  echo "mcp_server_version=$(sed -n "s/^$MCP_SERVER_NOTE//p" <<<"$body")"
}

bump_from_commits() {
  local messages
  messages="$(git log --format=%B "$1..HEAD")"
  if grep -qE '^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE:' <<<"$messages"; then
    breaking_bump "$1"
  elif grep -qE '^feat(\([^)]*\))?:' <<<"$messages"; then
    echo minor
  else
    echo patch
  fi
}

# Before 1.0.0, a breaking change increases the minor version.
breaking_bump() {
  if [[ "$1" == v0.* ]]; then
    echo minor
  else
    echo major
  fi
}

next_version() {
  local major minor patch
  IFS=. read -r major minor patch <<<"${1#v}"
  case "$2" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
  esac
}

notes() {
  if (($# != 3)); then
    usage >&2
    exit 2
  fi
  print_images "$1"
  print_tools "$2" "$3"
  print_changes "$(previous_release_tag "v$1")"
}

# A run again after the tag push already has the tag of this release.
previous_release_tag() {
  release_tags | grep -vxF "$1" | head -n 1 || true
}

print_images() {
  cat <<EOF
## Kits

| Kit | Image |
| --- | --- |
| Claude Code set | \`docker.io/localstack/sbx-localstack-claude:$1\` |
| Codex set | \`docker.io/localstack/sbx-localstack-codex:$1\` |
| LocalStack mixin | \`docker.io/localstack/sbx-kit-localstack:$1\` |

EOF
}

print_tools() {
  printf '## Bundled tools\n\n%s%s\n%s%s\n\n' "$LSTK_NOTE" "$1" "$MCP_SERVER_NOTE" "$2"
  printf 'The sandbox pulls the latest LocalStack image when it starts.\n\n'
}

print_changes() {
  local last_tag="$1" commits
  if [[ -z "$last_tag" ]]; then
    printf '## Changes\n\nThe first release.\n'
    return 0
  fi
  printf '## Changes since %s\n\n' "$last_tag"
  commits="$(git log --format='%s (%h)' "$last_tag..HEAD")"
  if [[ -z "$commits" ]]; then
    echo "No changes in this repository. The release updates the bundled tools."
    return 0
  fi
  print_group Features "$(grep -E '^feat[(!:]' <<<"$commits" || true)"
  print_group Fixes "$(grep -E '^fix[(!:]' <<<"$commits" || true)"
  print_group 'Other changes' "$(grep -vE '^(feat|fix)[(!:]' <<<"$commits" || true)"
}

print_group() {
  if [[ -z "$2" ]]; then
    return 0
  fi
  printf '### %s\n\n' "$1"
  sed 's/^/- /' <<<"$2"
  echo
}

main "$@"
