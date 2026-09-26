# shellcheck shell=sh
# Sends LocalStack hostnames directly to the LocalStack in this sandbox.
# localhost.localstack.cloud resolves to 127.0.0.1. Through the sandbox proxy,
# that address is the host, so a request could reach a LocalStack that runs on
# the host. The kit also denies these names at the proxy.
case ",${NO_PROXY:-}," in
  *",.localhost.localstack.cloud,"*) ;;
  *) NO_PROXY="${NO_PROXY:+$NO_PROXY,}localhost.localstack.cloud,.localhost.localstack.cloud" ;;
esac
no_proxy="$NO_PROXY"
export NO_PROXY no_proxy
