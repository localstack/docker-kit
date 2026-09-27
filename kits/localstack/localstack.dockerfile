# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# The AWS keys below are the fixed "test" values that LocalStack accepts.
# Each tool installs under /opt/localstack-kit in its own stage. The final
# stage starts from scratch, so the mixin adds only that tree to the workload
# and does not depend on the tools that the workload ships.

FROM debian:trixie-slim AS base
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
ENV KIT_HOME=/opt/localstack-kit
WORKDIR /tmp/build

FROM base AS lstk
ARG TARGETARCH
ARG LSTK_VERSION
RUN mkdir -p "$KIT_HOME/lstk" \
 && curl -fsSL "https://github.com/localstack/lstk/releases/download/v${LSTK_VERSION}/lstk_${LSTK_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C "$KIT_HOME/lstk" lstk bundled-extensions lstk-extensions.toml

FROM base AS node
ARG TARGETARCH
ARG NODE_VERSION
ARG MCP_SERVER_VERSION
ARG CDK_VERSION
ARG SMOL_TOML_VERSION
RUN case "$TARGETARCH" in amd64) arch=x64 ;; arm64) arch=arm64 ;; *) exit 1 ;; esac \
 && mkdir -p "$KIT_HOME/node" \
 && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${arch}.tar.xz" \
    | tar -xJ --strip-components=1 -C "$KIT_HOME/node" \
 && PATH="$KIT_HOME/node/bin:$PATH" npm install --global --no-fund --no-audit \
    "@localstack/localstack-mcp-server@${MCP_SERVER_VERSION}" "aws-cdk@${CDK_VERSION}" \
 && PATH="$KIT_HOME/node/bin:$PATH" npm install --prefix "$KIT_HOME/lib/config-check" \
    --no-save --no-package-lock --no-fund --no-audit "smol-toml@${SMOL_TOML_VERSION}"

FROM base AS terraform
ARG TARGETARCH
ARG TERRAFORM_VERSION
RUN curl -fsSLo terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
 && unzip -q terraform.zip terraform \
 && install -D -m 0755 terraform "$KIT_HOME/bin/terraform"

FROM base AS awscli
ARG TARGETARCH
ARG AWS_CLI_VERSION
RUN case "$TARGETARCH" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) exit 1 ;; esac \
 && curl -fsSLo awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-${arch}-${AWS_CLI_VERSION}.zip" \
 && unzip -q awscli.zip \
 && ./aws/install --install-dir "$KIT_HOME/aws-cli" --bin-dir "$KIT_HOME/bin"

FROM base AS sam
ARG TARGETARCH
ARG SAM_VERSION
RUN case "$TARGETARCH" in amd64) arch=x86_64 ;; arm64) arch=arm64 ;; *) exit 1 ;; esac \
 && curl -fsSLo sam.zip "https://github.com/aws/aws-sam-cli/releases/download/v${SAM_VERSION}/aws-sam-cli-linux-${arch}.zip" \
 && unzip -q sam.zip -d sam-installation \
 && ./sam-installation/install --install-dir "$KIT_HOME/sam-cli" --bin-dir "$KIT_HOME/bin"

FROM scratch
COPY --from=lstk /opt/localstack-kit/ /opt/localstack-kit/
COPY --from=node /opt/localstack-kit/ /opt/localstack-kit/
COPY --from=terraform /opt/localstack-kit/ /opt/localstack-kit/
COPY --from=awscli /opt/localstack-kit/ /opt/localstack-kit/
COPY --from=sam /opt/localstack-kit/ /opt/localstack-kit/
COPY files/bin/ /opt/localstack-kit/bin/
COPY files/etc/ /opt/localstack-kit/etc/
COPY files/lib/ /opt/localstack-kit/lib/config-check/
COPY files/usr-local-bin/dockerd /usr/local/bin/dockerd
ENV PATH=/opt/localstack-kit/bin:/opt/localstack-kit/node/bin \
    AWS_ENDPOINT_URL=http://localhost:4566 \
    AWS_ACCESS_KEY_ID=test \
    AWS_SECRET_ACCESS_KEY=test \
    AWS_DEFAULT_REGION=us-east-1 \
    AWS_REGION=us-east-1 \
    LSTK_KEYRING=file
