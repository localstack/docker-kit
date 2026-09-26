LOCAL_REGISTRY ?= localhost:5055
LOCAL_PLATFORM ?= linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

.PHONY: registry build-local release sbx-allow-local

# Starts an HTTPS registry for kit tests. Kit sets can only list published
# kits, so local builds push the mixin here first.
registry:
	scripts/local-registry.sh

build-local: registry
	scripts/build.sh --registry $(LOCAL_REGISTRY) --platform $(LOCAL_PLATFORM)

release:
	scripts/build.sh

# Lets sbx load kits from the local registry. The default allows docker.io only.
sbx-allow-local:
	sbx settings set kit.allowedSources '["docker.io/","$(LOCAL_REGISTRY)/localstack/"]'
