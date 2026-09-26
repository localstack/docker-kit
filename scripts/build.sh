#!/usr/bin/env bash
# Builds the LocalStack mixin and the per-agent kit sets, and pushes them.
#
# Usage: scripts/build.sh [--registry HOST] [--platform LIST] [--allow-overwrite]
#
# The default registry is docker.io. For local tests, use
# --registry localhost:5055 --platform linux/arm64 (or linux/amd64).
# On docker.io, the build stops if a tag exists, unless --allow-overwrite is
# given. Published tags must not change under the people who use them.
#
# Kits must be built with a docker-container builder. The docker driver with
# the classic image store pushes Docker v2 manifests, which drop the OCI
# annotation that carries the kit descriptor.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
readonly BUILDER=lskit
readonly NAMESPACE=localstack
readonly CANONICAL_REGISTRY=docker.io

registry="$CANONICAL_REGISTRY"
platform=linux/amd64,linux/arm64
allow_overwrite=false
work_root=""

main() {
  parse_args "$@"
  check_versions_match
  work_root="$(mktemp -d)"
  trap 'rm -rf "$work_root"' EXIT
  ensure_builder
  build_kit "$REPO_ROOT/kits/localstack" sbx-kit-localstack
  build_set localstack-claude sbx-localstack-claude
  build_set localstack-codex sbx-localstack-codex
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --registry) registry="$2"; shift 2 ;;
      --platform) platform="$2"; shift 2 ;;
      --allow-overwrite) allow_overwrite=true; shift ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
  done
}

usage() {
  sed -n '2,9s/^# \{0,1\}//p' "$0"
}

ensure_builder() {
  if docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
    return 0
  fi
  docker buildx create --name "$BUILDER" --driver docker-container \
    --driver-opt network=host \
    --buildkitd-config "$REPO_ROOT/scripts/buildkitd.toml" --bootstrap
}

build_kit() {
  local kit_dir="$1" image="$2" descriptor ref
  descriptor="$kit_dir/$(basename "$kit_dir").yaml"
  ref="$registry/$NAMESPACE/$image:$(descriptor_version "$descriptor")"
  refuse_published_tag "$ref"
  echo "==> $ref"
  docker buildx build --builder "$BUILDER" --platform "$platform" \
    --file "$descriptor" --tag "$ref" --push "$kit_dir"
}

build_set() {
  local name="$1" image="$2"
  cp -R "$REPO_ROOT/kits/$name" "$work_root/$name"
  point_components_at_registry "$work_root/$name/$name.yaml"
  build_kit "$work_root/$name" "$image"
}

# Sets can only list published kits. For a local registry, the LocalStack
# component refs move to that registry. Docker's agent kits stay on docker.io.
point_components_at_registry() {
  local descriptor="$1"
  if [[ "$registry" == "$CANONICAL_REGISTRY" ]]; then
    return 0
  fi
  sed -i.orig "s#ref: $CANONICAL_REGISTRY/$NAMESPACE/#ref: $registry/$NAMESPACE/#" "$descriptor"
  rm -f "$descriptor.orig"
}

refuse_published_tag() {
  if [[ "$registry" != "$CANONICAL_REGISTRY" || "$allow_overwrite" == true ]]; then
    return 0
  fi
  if docker buildx imagetools inspect "$1" >/dev/null 2>&1; then
    echo "$1 exists. Increase the version (make bump VERSION=...), or pass --allow-overwrite." >&2
    exit 1
  fi
}

# The mixin, the sets, and the mixin tag in each set must have one version.
check_versions_match() {
  local version set_descriptor
  version="$(descriptor_version "$REPO_ROOT/kits/localstack/localstack.yaml")"
  for set_descriptor in "$REPO_ROOT"/kits/localstack-*/localstack-*.yaml; do
    if [[ "$(descriptor_version "$set_descriptor")" != "$version" ]] \
      || ! grep -q "ref: $CANONICAL_REGISTRY/$NAMESPACE/sbx-kit-localstack:$version$" "$set_descriptor"; then
      echo "$set_descriptor does not match mixin version $version. Run make bump VERSION=$version." >&2
      exit 1
    fi
  done
}

descriptor_version() {
  sed -n 's/^version: "\(.*\)"$/\1/p' "$1"
}

main "$@"
