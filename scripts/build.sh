#!/usr/bin/env bash
# Builds the LocalStack mixin and the per-agent kit sets, and pushes them.
#
# Usage: scripts/build.sh [--registry HOST] [--platform LIST]
#
# The default registry is docker.io. For local tests, use
# --registry localhost:5055 --platform linux/arm64 (or linux/amd64).
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
work_root=""

main() {
  parse_args "$@"
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
      -h | --help) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
  done
}

usage() {
  sed -n '2,7s/^# \{0,1\}//p' "$0"
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

descriptor_version() {
  sed -n 's/^version: "\(.*\)"$/\1/p' "$1"
}

main "$@"
