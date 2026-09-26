#!/usr/bin/env bash
# Starts the local test registry on https://localhost:5055.
#
# sbx pulls kits over HTTPS only. The registry uses a self-signed certificate
# for localhost. It is a leaf certificate (not a CA), valid for 90 days, and
# only for server authentication. Trust it one time in the login keychain:
#
#   security add-trusted-cert -r trustRoot -p ssl \
#     -k ~/Library/Keychains/login.keychain-db .work/registry-tls/localhost.crt
#
# To remove the trust later:
#
#   security remove-trusted-cert .work/registry-tls/localhost.crt
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
readonly TLS_DIR="$REPO_ROOT/.work/registry-tls"
readonly CONTAINER=lskit-registry
readonly DATA_VOLUME=lskit-registry-data
readonly PORT=5055

main() {
  ensure_certificate
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$CONTAINER" --restart unless-stopped \
    -p "127.0.0.1:$PORT:5000" \
    -v "$DATA_VOLUME:/var/lib/registry" \
    -v "$TLS_DIR:/certs:ro" \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/localhost.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/localhost.key \
    registry:2 >/dev/null
  echo "registry: https://localhost:$PORT"
}

ensure_certificate() {
  if [[ -f "$TLS_DIR/localhost.crt" ]]; then
    return 0
  fi
  mkdir -p "$TLS_DIR"
  openssl req -x509 -newkey rsa:2048 -nodes -days 90 -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth" \
    -keyout "$TLS_DIR/localhost.key" -out "$TLS_DIR/localhost.crt" 2>/dev/null
  echo "created $TLS_DIR/localhost.crt. Trust it with the command in $0."
}

main "$@"
