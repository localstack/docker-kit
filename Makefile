LOCAL_REGISTRY ?= localhost:5055
LOCAL_PLATFORM ?= linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
REGISTRY ?= $(LOCAL_REGISTRY)
AGENT ?= claude

.PHONY: registry build-local release sbx-allow-local smoke e2e project-config

# Starts an HTTPS registry for kit tests. Kit sets can only list published
# kits, so local builds push the mixin here first.
registry:
	scripts/local-registry.sh

build-local: registry
	scripts/build.sh --registry $(LOCAL_REGISTRY) --platform $(LOCAL_PLATFORM)

release:
	scripts/build.sh

# Lets sbx load kits from the local registry. The default allows docker.io
# only. Other allowed sources stay in the list.
sbx-allow-local:
	scripts/sbx-allow-source.sh $(LOCAL_REGISTRY)/localstack/

# Checks a set without an agent prompt. Uses no model credits.
smoke:
	scripts/smoke.sh $(AGENT) --registry $(REGISTRY)

# Gives the agent a Terraform task and checks the result. Uses model credits.
e2e:
	scripts/headless.sh $(AGENT) --registry $(REGISTRY)

# Checks that the kit starts LocalStack with a project lstk config.
project-config:
	scripts/project-config.sh $(AGENT) --registry $(REGISTRY)
