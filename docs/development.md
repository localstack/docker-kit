# Development

## Layout

```text
kits/
  localstack/            the mixin (sbx-kit-localstack)
    localstack.yaml      kit descriptor: args, network rules, hooks, context
    localstack.dockerfile  tools under /opt/localstack-kit
    context.md           instructions for the agent
    files/bin/           lstk wrapper, startup hook (lskit-start), boot state
                         (lskit-status), MCP launcher and registration, shims
    files/etc/           shell snippet that keeps LocalStack names off the proxy
    files/usr-local-bin/ dockerd wrapper that lets Docker pull Lambda images
  localstack-claude/     set: Docker's Claude Code kit and the mixin
  localstack-codex/      set: Docker's Codex kit and the mixin
scripts/
  build.sh               build and push the mixin and the sets
  release.sh             plan a release, and write its notes
  tool-releases.sh       current releases of lstk and the MCP server
  local-registry.sh      HTTPS registry for local tests
  smoke.sh               checks without an agent prompt
  project-config.sh      checks for a project lstk config and LSKIT_LSTK_CONFIG
  headless.sh            agent task with checks from outside the agent
```

## Versions

Each tool has an argument in `kits/localstack/localstack.yaml`. LocalStack,
lstk, and the LocalStack MCP server follow their latest releases. The other
tools are pinned. To change a tool, change the default of its argument. The
sets pin Docker's agent kits by tag in their `kits:` lists.

| Argument | Tool | Default |
| --- | --- | --- |
| `localstack_image` | LocalStack image (set when the sandbox is created) | `localstack/localstack-pro:latest` |
| `lstk_version` | lstk | `latest` |
| `mcp_server_version` | `@localstack/localstack-mcp-server` | `latest` |
| `node_version` | Node.js, for the MCP server and AWS CDK | pinned |
| `terraform_version` | Terraform | pinned |
| `cdk_version` | AWS CDK CLI | pinned |
| `aws_cli_version` | AWS CLI v2 | pinned |
| `sam_version` | AWS SAM CLI | pinned |
| `toml_parser_version` | smol-toml, for `lskit-check-config` | pinned |

For `latest`, `scripts/build.sh` finds the current lstk and MCP server
releases and passes their numbers to the build. BuildKit caches a step by
its text, so without the numbers, a new release would not rebuild the step.
A sandbox pulls the LocalStack image when it starts.

## Build and test locally

You need Docker with Buildx, `sbx`, and a LocalStack auth token. The test
scripts use `LOCALSTACK_AUTH_TOKEN`. On macOS, they also read the token from
the keychain entry of `lstk login`.

A kit set can list only published kits. For local tests, the build pushes to
an HTTPS registry on `localhost:5055`, because `sbx` pulls kits over HTTPS
only.

1. Start the registry. The first run creates a self-signed certificate for
   `localhost` in `.work/registry-tls/`:

   ```console
   $ make registry
   ```

2. Trust the certificate one time. The header of
   `scripts/local-registry.sh` has the command, and the command to remove
   the trust.

3. Let `sbx` load kits from the registry:

   ```console
   $ make sbx-allow-local
   ```

4. Build the mixin and the sets for your platform:

   ```console
   $ make build-local
   ```

5. Run the checks. `smoke` and `project-config` use no model credits. `e2e`
   gives the agent a task and uses model credits.

   ```console
   $ make smoke AGENT=claude
   $ make project-config AGENT=claude
   $ make e2e AGENT=claude
   ```

To test the kits that CI publishes from `main`, use Docker Hub and the tag
`latest`:

```console
$ make smoke AGENT=claude REGISTRY=docker.io TAG=latest
```

Approve the agent credential for the set one time in an interactive
`sbx run` before you run `e2e`. The scripts create sandboxes without a
terminal, so `sbx` cannot ask.

The builds use a `docker-container` Buildx builder named `lskit`. The
`docker` driver with the classic image store drops the OCI annotation that
holds the kit descriptor. The builder cache can grow to about 10 GB. Remove
it with `docker buildx prune --builder lskit --all`.

## CI

`.github/workflows/ci.yaml` runs on each push to `main` and on each pull
request:

- `scripts/lint.sh`: shellcheck on every shell script, and actionlint on the
  workflows.
- A build of the mixin and the sets for `linux/amd64` and `linux/arm64`
  through a local registry, as in `make build-local`.

On a push to `main`, when these jobs pass, the `publish` job pushes the kits
to `docker.io/localstack` with the tag `latest` (`scripts/build.sh --latest`).
In this build, the sets list the mixin with the tag `latest`. The job uses the
`docker-push` environment, which holds the `DOCKERHUB_USERNAME` and
`DOCKER_PUSH_TOKEN` secrets and accepts only `main`. The token can push to
many repositories in the `localstack` namespace.

Rulesets protect `main` and the `v*` tags. A change to `main` needs a pull
request with one approval. Only repository admins and deploy keys can create,
move, or delete a `v*` tag. Admins can bypass these rules.

The sandbox tests need KVM or Apple silicon, so they do not run in CI. Run
them on your machine.

## Release

Anyone with write access can release. Open the **Actions** tab, select
**Release**, and select **Run workflow** on `main`. Keep the bump at `auto`,
or choose `patch`, `minor`, or `major`.

`.github/workflows/release.yaml` does these steps:

1. `scripts/release.sh plan` finds the last `vX.Y.Z` tag and the next
   version. With `auto`, the commit types since the last release give the
   bump: a breaking change (`feat!:` or a `BREAKING CHANGE:` footer) gives
   major, `feat` gives minor, and other types give patch. Before 1.0.0, a
   breaking change gives minor. The first release is 0.1.0.
2. `auto` stops when `main` has no new commits, and lstk and the LocalStack
   MCP server have no new release. The notes of each release record the lstk
   and MCP server versions, so the plan can compare them.
3. CI runs: lint, and a build for both platforms.
4. `scripts/build.sh --version X.Y.Z` builds the kits with the lstk and MCP
   server versions of the plan, writes the version into each descriptor, and
   pushes the kits to `docker.io/localstack`. In git, the descriptors have the
   version 0.0.0.
5. The kits are signed with the GitHub OIDC token (keyless). If signing
   fails, the release continues. Run the `Sign kits` job again.
6. The workflow pushes the tag `vX.Y.Z` and creates the GitHub release. The
   notes list the images, the lstk and MCP server versions, and the commits
   since the last release, grouped by type.

The tag comes last, so a failed run leaves no tag. Run the failed jobs again.
The build replaces Docker Hub tags of a version that has no git tag.

The tag ruleset does not let `GITHUB_TOKEN` create `v*` tags, and a repository
ruleset cannot list the GitHub Actions app as a bypass. So the workflow pushes
the tag over SSH with a deploy key. The `release` environment holds the
private key as `RELEASE_TAG_DEPLOY_KEY` and accepts only `main`. To replace
the key, add a new deploy key with write access, store its private key in
that secret, and remove the old deploy key.

The sandbox tests do not run in the workflow. Before you release, run them on
the `latest` kits, which have the same code as `main`:

```console
$ make smoke AGENT=claude REGISTRY=docker.io TAG=latest
$ make smoke AGENT=codex REGISTRY=docker.io TAG=latest
```

Users verify the signature of a release like this:

```console
$ sbx kit verify docker.io/localstack/sbx-localstack-claude:0.2.0 \
    --certificate-identity 'https://github.com/localstack/docker-kit/.github/workflows/release.yaml@refs/heads/main' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
