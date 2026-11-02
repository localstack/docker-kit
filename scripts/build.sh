#!/usr/bin/env bash
# Builds the LocalStack mixin and the per-agent kit sets, and pushes them.
#
# Usage: scripts/build.sh [--registry HOST] [--platform LIST] [--allow-overwrite]
#                         [--version X.Y.Z | --latest]
#                         [--lstk-version X.Y.Z] [--mcp-server-version X.Y.Z]
#
# The default registry is docker.io. For local tests, use
# --registry localhost:5055 --platform linux/arm64 (or linux/amd64).
# On docker.io, the build stops if a tag exists, unless --allow-overwrite is
# given. Published tags must not change under the people who use them.
#
# --version writes the version into each descriptor and pushes each kit with
# the version as its tag. The release workflow gives the release version. The
# default is the version in git, 0.0.0, which the local tests use.
# --latest pushes each kit with the tag latest. The latest tag moves, so the
# build does not stop if it exists. CI does this on each push to main.
#
# lstk and the MCP server follow their latest releases. --lstk-version and
# --mcp-server-version build the given release instead.
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
readonly VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

registry="$CANONICAL_REGISTRY"
platform=linux/amd64,linux/arm64
allow_overwrite=false
kit_version=""
kit_tag=""
lstk_release=""
mcp_server_release=""
work_root=""

main() {
  parse_args "$@"
  work_root="$(mktemp -d)"
  trap 'rm -rf "$work_root"' EXIT
  ensure_builder
  build_mixin
  build_kit localstack-claude sbx-localstack-claude
  build_kit localstack-codex sbx-localstack-codex
}

parse_args() {
  local push_latest=false
  kit_version="$(descriptor_version "$REPO_ROOT/kits/localstack/localstack.yaml")"
  while (($# > 0)); do
    case "$1" in
      --registry) registry="$2"; shift 2 ;;
      --platform) platform="$2"; shift 2 ;;
      --allow-overwrite) allow_overwrite=true; shift ;;
      --version) kit_version="$(require_version "$2")"; shift 2 ;;
      --latest) push_latest=true; shift ;;
      --lstk-version) lstk_release="$(require_version "$2")"; shift 2 ;;
      --mcp-server-version) mcp_server_release="$(require_version "$2")"; shift 2 ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  kit_tag="$kit_version"
  if [[ "$push_latest" == true ]]; then
    kit_tag=latest
  fi
}

require_version() {
  if [[ ! "$1" =~ $VERSION_PATTERN ]]; then
    echo "not a version (MAJOR.MINOR.PATCH): $1" >&2
    exit 2
  fi
  echo "$1"
}

usage() {
  sed -n '2,20s/^# \{0,1\}//p' "$0"
}

ensure_builder() {
  if docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
    return 0
  fi
  docker buildx create --name "$BUILDER" --driver docker-container \
    --driver-opt network=host \
    --buildkitd-config "$REPO_ROOT/scripts/buildkitd.toml" --bootstrap
}

# BuildKit caches a step by its text, and "latest" stays the same text when a
# new release comes out. So for each tool whose default is latest, the build
# passes a release number: the one from the command line, or the current one.
build_mixin() {
  local descriptor="$REPO_ROOT/kits/localstack/localstack.yaml" release_args=() lstk mcp_server
  if follows_latest "$descriptor" lstk_version; then
    lstk="${lstk_release:-$(current_release lstk_version)}"
    echo "==> lstk $lstk"
    release_args+=(--build-arg "lstk_version=$lstk")
  fi
  if follows_latest "$descriptor" mcp_server_version; then
    mcp_server="${mcp_server_release:-$(current_release mcp_server_version)}"
    echo "==> LocalStack MCP server $mcp_server"
    release_args+=(--build-arg "mcp_server_version=$mcp_server")
  fi
  build_kit localstack sbx-kit-localstack ${release_args[@]+"${release_args[@]}"}
}

follows_latest() {
  [[ "$(arg_default "$1" "$2")" == latest ]]
}

arg_default() {
  sed -n "/^  $2:/,/^    default:/s/^    default: \"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$1" | head -n 1
}

current_release() {
  "$REPO_ROOT/scripts/tool-releases.sh" | sed -n "s/^$1=//p"
}

# Arguments after the image name go to docker buildx build.
build_kit() {
  local name="$1" image="$2" ref
  shift 2
  stage_kit "$name"
  ref="$registry/$NAMESPACE/$image:$kit_tag"
  refuse_published_tag "$ref"
  echo "==> $ref"
  docker buildx build --builder "$BUILDER" --platform "$platform" "$@" \
    --file "$work_root/$name/$name.yaml" --tag "$ref" --push "$work_root/$name"
}

# Copies a kit and writes the version into its descriptor. A set lists the
# mixin from the same registry and with the same tag as the set. Sets can only
# list published kits, so for a local registry the mixin must come from there.
# Docker's agent kits stay on docker.io.
stage_kit() {
  local descriptor="$work_root/$1/$1.yaml"
  cp -R "$REPO_ROOT/kits/$1" "$work_root/$1"
  edit_in_place "$descriptor" "s/^version: \".*\"$/version: \"$kit_version\"/"
  edit_in_place "$descriptor" \
    "s#ref: $CANONICAL_REGISTRY/$NAMESPACE/sbx-kit-localstack:.*#ref: $registry/$NAMESPACE/sbx-kit-localstack:$kit_tag#"
}

edit_in_place() {
  sed -i.orig "$2" "$1"
  rm -f "$1.orig"
}

refuse_published_tag() {
  if [[ "$registry" != "$CANONICAL_REGISTRY" || "$allow_overwrite" == true \
    || "$kit_tag" == latest ]]; then
    return 0
  fi
  if docker buildx imagetools inspect "$1" >/dev/null 2>&1; then
    echo "$1 exists. Release a new version, or pass --allow-overwrite." >&2
    exit 1
  fi
}

descriptor_version() {
  sed -n 's/^version: "\(.*\)"$/\1/p' "$1"
}

main "$@"
