#!/usr/bin/env bash
# Sets one version on the mixin, on the sets, and on the mixin tag that each
# set lists.
#
# Usage: scripts/bump-version.sh MAJOR.MINOR.PATCH
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
readonly VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

main() {
  local version="${1:-}" set_descriptor
  if [[ ! "$version" =~ $VERSION_PATTERN ]]; then
    echo "usage: $0 MAJOR.MINOR.PATCH" >&2
    exit 2
  fi
  set_descriptor_version "$REPO_ROOT/kits/localstack/localstack.yaml" "$version"
  for set_descriptor in "$REPO_ROOT"/kits/localstack-*/localstack-*.yaml; do
    set_descriptor_version "$set_descriptor" "$version"
    edit_in_place "$set_descriptor" "s#(ref: docker\.io/localstack/sbx-kit-localstack:)[^[:space:]]+#\1$version#"
  done
  echo "Version is $version. Add an entry to CHANGELOG.md, then commit."
}

set_descriptor_version() {
  edit_in_place "$1" "s/^version: \"[^\"]*\"$/version: \"$2\"/"
}

edit_in_place() {
  sed -i.orig -E "$2" "$1"
  rm -f "$1.orig"
}

main "$@"
