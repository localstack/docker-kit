# LocalStack kit for Docker Sandboxes

This repository has [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
kits that run a coding agent with LocalStack in the same sandbox. The agent
can build, deploy, and test AWS applications against LocalStack. It does not
get AWS credentials.

When the sandbox boots, lstk starts LocalStack. The kit also adds the
LocalStack MCP server, Terraform, AWS CDK, AWS SAM CLI, and AWS CLI v2, and
points them at `http://localhost:4566`.

| Kit | Image | Use |
| --- | --- | --- |
| Claude Code set | `docker.io/localstack/sbx-localstack-claude` | `sbx run` |
| Codex set | `docker.io/localstack/sbx-localstack-codex` | `sbx run` |
| LocalStack mixin | `docker.io/localstack/sbx-kit-localstack` | `--kit` on a v3 workload |

The sets combine Docker's agent kit with the LocalStack mixin, and register
the LocalStack MCP server with the agent.

## Requirements

- `sbx` 0.45 or later, signed in with `sbx login`. See
  [Install Docker Sandboxes](https://docs.docker.com/ai/sandboxes/install/).
  Local sandboxes need macOS 14 or later on Apple silicon, Windows 11 with
  Windows Hypervisor Platform, or Ubuntu 24.04 or later with KVM.
- A LocalStack auth token. Read [Security](docs/security.md) before you
  choose which token to use.
- An agent login:
  - Claude Code: a Claude subscription (use `/login` in the sandbox) or an
    Anthropic API key (`sbx secret set anthropic`).
  - Codex: a ChatGPT login (`sbx secret set openai --oauth`) or an OpenAI API
    key (`sbx secret set openai`).
- About 5 GB of free disk space for each sandbox.

## Quick start

> [!IMPORTANT]
> The images are not on Docker Hub yet. Until the first release, the
> `docker.io/localstack/...` references fail with `401 unauthorized`, because
> Docker Hub reports a missing repository that way. To use the kits before
> the release, build them into a local registry (see
> [Development](docs/development.md)) and replace `docker.io` with
> `localhost:5055` in the commands below.

Put the token in your shell. The `-e` flag copies it into the sandbox.

```console
$ export LOCALSTACK_AUTH_TOKEN=<your-token>
```

Start Claude Code with LocalStack in the current directory:

```console
$ sbx run --name ls-claude -e LOCALSTACK_AUTH_TOKEN -p 4566:4566 \
    docker.io/localstack/sbx-localstack-claude:0.1.0 .
```

Start Codex with LocalStack:

```console
$ sbx run --name ls-codex -e LOCALSTACK_AUTH_TOKEN -p 4566:4566 \
    docker.io/localstack/sbx-localstack-codex:0.1.0 .
```

On the first run, `sbx` asks you to approve the agent credential for this
kit. The first start also pulls the kit and the LocalStack image, so it can
take some minutes.

`-p 4566:4566` makes LocalStack available on your host, for example for the
[LocalStack Web App](https://app.localstack.cloud). If LocalStack already runs
on your host, use a different host port, such as `-p 4567:4566`.

To go back to a sandbox later, give only its name:

```console
$ sbx run --name ls-claude
```

## Use LocalStack in the sandbox

The agent gets instructions for LocalStack in its context file (`CLAUDE.md`
or `AGENTS.md`). In short:

- `lstk status` shows if LocalStack runs. `lstk start` starts it.
- `lskit-status` shows how the start at boot went, for example `running`,
  `failed`, or `missing-token`. The log is `/tmp/localstack-kit/start.log`.
- `AWS_ENDPOINT_URL=http://localhost:4566` and the `test` credentials are
  set, so the AWS CLI and the AWS SDKs use LocalStack.
- `tflocal`, `cdklocal`, `samlocal`, and `awslocal` run Terraform, AWS CDK,
  AWS SAM, and the AWS CLI through lstk.
- The `localstack` MCP server gives tools for deployment, logs, IAM policy
  analysis, fault injection, and state.

### Keep state

`sbx` stops a local sandbox 30 seconds after the last session ends. When the
sandbox starts again, LocalStack starts with no resources. To keep resources,
save a snapshot in the workspace before you leave the session:

```console
$ lstk snapshot save ./localstack.snapshot
$ lstk snapshot load ./localstack.snapshot
```

### Configure LocalStack

lstk sends each `LOCALSTACK_*` variable to the LocalStack container without
the prefix. Set the variables when you create the sandbox. For example, this
turns on debug logs and IAM enforcement:

```console
$ sbx run --name ls-claude -e LOCALSTACK_AUTH_TOKEN \
    -e LOCALSTACK_DEBUG=1 -e LOCALSTACK_ENFORCE_IAM=1 \
    docker.io/localstack/sbx-localstack-claude:0.1.0 .
```

The values apply at each start, also when the agent runs `lstk start` or
`lstk restart`. See the
[LocalStack configuration reference](https://docs.localstack.cloud/references/configuration/)
for the variables.

At boot, these values reach lstk because `sbx` 0.45 gives startup hooks the
whole sandbox environment. The kit specification lets a runtime give a hook
only the variables that the kit names, and the kit cannot name every
`LOCALSTACK_*` variable. For settings that must apply at boot on every
runtime, put them in an env profile of an lstk config (see the next section).

### Use the lstk config of your project

If the workspace has `.lstk/config.toml`, the kit starts LocalStack with that
file instead of its own config. To use a different file, name it with
`LSKIT_LSTK_CONFIG`. The path is absolute or relative to the workspace:

```console
$ sbx run --name ls-claude -e LOCALSTACK_AUTH_TOKEN \
    -e LSKIT_LSTK_CONFIG=config/lstk-sandbox.toml \
    docker.io/localstack/sbx-localstack-claude:0.1.0 .
```

The file controls the emulator, the image, the container name, and the env
profiles. For example, this file starts the Snowflake emulator. Use
`type = "azure"` for the Azure emulator:

```toml
[[containers]]
type = "snowflake"
port = "4566"
env = ["sandbox"]

[env.sandbox]
GATEWAY_LISTEN = "0.0.0.0:4566,0.0.0.0:443"
```

Some rules apply:

- `GATEWAY_LISTEN` with `0.0.0.0` is necessary if you publish LocalStack to
  the host with `-p`. Without it, lstk binds LocalStack to loopback in the
  sandbox, and the start log has a note.
- The kit adds `LAMBDA_IGNORE_ARCHITECTURE=1` and `SKIP_SSL_CERT_DOWNLOAD=1`
  if the file does not set them.
- The `localstack_image` kit argument applies only to the kit config.
- A project config can start only LocalStack images, unless you set
  `-e LSKIT_ALLOW_ANY_IMAGE=1`. The kit reads the file as TOML for this
  check, and it refuses a file that is not valid TOML. To ignore
  `.lstk/config.toml`, for example in a repository that you do not trust,
  set `-e LSKIT_IGNORE_PROJECT_CONFIG=1`. See
  [Security](docs/security.md#project-lstk-config).
- After a change to the file, run `lstk restart` in the sandbox.
- The AWS endpoint, credentials, and tools of the kit are for the AWS
  emulator.

### Choose the LocalStack version

The kit pins the LocalStack image. To use another image, set the
`localstack_image` argument when you create the sandbox:

```console
$ sbx run --name ls-claude -e LOCALSTACK_AUTH_TOKEN \
    --kit-arg localstack_image=localstack/localstack-pro:2026.8 \
    docker.io/localstack/sbx-localstack-claude:0.1.0 .
```

### Add the mixin to another v3 workload

You can add the mixin to a v3 workload yourself. The built-in shortcuts, such
as `sbx run claude`, use v2 kits and do not accept v3 mixins.

```console
$ sbx run -e LOCALSTACK_AUTH_TOKEN docker.io/docker/sbx-kit-claude:2.1.278 \
    --kit docker.io/localstack/sbx-kit-localstack:0.1.0 .
```

The sets register the MCP server. With your own combination, register it one
time in the sandbox with `lskit-register-mcp claude` or
`lskit-register-mcp codex`.

## Limits

- The kit supports local sandboxes. Docker Cloud Sandboxes are not
  supported.
- The agent can read the LocalStack auth token. See [Security](docs/security.md).
- `sbx` 0.45 ignores the kit's request to keep the sandbox running, so
  LocalStack stops when you leave the agent.
- The `--kit` and `--kit-arg` flags are experimental in `sbx` 0.45.

## Documentation

- [Security](docs/security.md): token handling, network rules, and telemetry.
- [Troubleshooting](docs/troubleshooting.md): known problems and fixes.
- [Development](docs/development.md): build and test the kits.

## License

Apache License 2.0. See [LICENSE](LICENSE).
