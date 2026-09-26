LOCAL_REGISTRY ?= localhost:5055
LOCAL_PLATFORM ?= linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
REGISTRY ?= $(LOCAL_REGISTRY)
AGENT ?= claude

.PHONY: lint registry build-local release bump sbx-allow-local smoke e2e project-config

# Runs shellcheck on every shell script.
lint:
	scripts/lint.sh

# Starts an HTTPS registry for kit tests. Kit sets can only list published
# kits, so local builds push the mixin here first.
registry:
	scripts/local-registry.sh

build-local: registry
	scripts/build.sh --registry $(LOCAL_REGISTRY) --platform $(LOCAL_PLATFORM)

release:
	scripts/build.sh

# Sets one version on all kits, for example: make bump VERSION=0.2.0
bump:
	scripts/bump-version.sh $(VERSION)

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
