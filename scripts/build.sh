#!/usr/bin/env bash
# Builds the LocalStack mixin and the per-agent kit sets, and pushes them.
#
# Usage: scripts/build.sh [--registry HOST] [--platform LIST] [--allow-overwrite]
#                         [--latest]
#
# The default registry is docker.io. For local tests, use
# --registry localhost:5055 --platform linux/arm64 (or linux/amd64).
# On docker.io, the build stops if a tag exists, unless --allow-overwrite is
# given. Published tags must not change under the people who use them.
#
# --latest pushes each kit with the tag latest, not with its version, and
# the sets list the latest mixin. The latest tag moves, so the build does not
# stop if it exists. CI does this on each push to main.
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
push_latest=false
work_root=""

main() {
  parse_args "$@"
  check_versions_match
  work_root="$(mktemp -d)"
  trap 'rm -rf "$work_root"' EXIT
  ensure_builder
  build_mixin
  build_set localstack-claude sbx-localstack-claude
  build_set localstack-codex sbx-localstack-codex
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --registry) registry="$2"; shift 2 ;;
      --platform) platform="$2"; shift 2 ;;
      --allow-overwrite) allow_overwrite=true; shift ;;
      --latest) push_latest=true; shift ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
  done
}

usage() {
  sed -n '2,14s/^# \{0,1\}//p' "$0"
}

ensure_builder() {
  if docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
    return 0
  fi
  docker buildx create --name "$BUILDER" --driver docker-container \
    --driver-opt network=host \
    --buildkitd-config "$REPO_ROOT/scripts/buildkitd.toml" --bootstrap
}

build_mixin() {
  local release_args=() arg
  while IFS= read -r arg; do
    release_args+=("$arg")
  done < <(latest_release_args "$REPO_ROOT/kits/localstack/localstack.yaml")
  build_kit "$REPO_ROOT/kits/localstack" sbx-kit-localstack ${release_args[@]+"${release_args[@]}"}
}

# Arguments after the image name go to docker buildx build.
build_kit() {
  local kit_dir="$1" image="$2" descriptor ref
  shift 2
  descriptor="$kit_dir/$(basename "$kit_dir").yaml"
  ref="$registry/$NAMESPACE/$image:$(kit_tag "$descriptor")"
  refuse_published_tag "$ref"
  echo "==> $ref"
  docker buildx build --builder "$BUILDER" --platform "$platform" "$@" \
    --file "$descriptor" --tag "$ref" --push "$kit_dir"
}

kit_tag() {
  if [[ "$push_latest" == true ]]; then
    echo latest
  else
    descriptor_version "$1"
  fi
}

# BuildKit caches a step by its text, and "latest" stays the same text when a
# new release comes out. So for each tool whose default is latest, the build
# passes the number of the current release, and a new release rebuilds it.
latest_release_args() {
  local descriptor="$1" lstk mcp_server
  if [[ "$(arg_default "$descriptor" lstk_version)" == latest ]]; then
    lstk="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/localstack/lstk/releases/latest | sed 's#.*/tag/v##')"
    echo "==> lstk $lstk" >&2
    printf '%s\n' --build-arg "lstk_version=$lstk"
  fi
  if [[ "$(arg_default "$descriptor" mcp_server_version)" == latest ]]; then
    mcp_server="$(npm view @localstack/localstack-mcp-server version)"
    echo "==> LocalStack MCP server $mcp_server" >&2
    printf '%s\n' --build-arg "mcp_server_version=$mcp_server"
  fi
}

arg_default() {
  sed -n "/^  $2:/,/^    default:/s/^    default: \"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$1" | head -n 1
}

build_set() {
  local name="$1" image="$2" descriptor
  cp -R "$REPO_ROOT/kits/$name" "$work_root/$name"
  descriptor="$work_root/$name/$name.yaml"
  point_components_at_registry "$descriptor"
  point_mixin_at_latest "$descriptor"
  build_kit "$work_root/$name" "$image"
}

# Sets can only list published kits. For a local registry, the LocalStack
# component refs move to that registry. Docker's agent kits stay on docker.io.
point_components_at_registry() {
  if [[ "$registry" == "$CANONICAL_REGISTRY" ]]; then
    return 0
  fi
  edit_in_place "$1" "s#ref: $CANONICAL_REGISTRY/$NAMESPACE/#ref: $registry/$NAMESPACE/#"
}

point_mixin_at_latest() {
  if [[ "$push_latest" != true ]]; then
    return 0
  fi
  edit_in_place "$1" "s#\(/$NAMESPACE/sbx-kit-localstack:\).*#\1latest#"
}

edit_in_place() {
  sed -i.orig "$2" "$1"
  rm -f "$1.orig"
}

refuse_published_tag() {
  if [[ "$registry" != "$CANONICAL_REGISTRY" || "$allow_overwrite" == true \
    || "$push_latest" == true ]]; then
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
