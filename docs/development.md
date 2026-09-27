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
  local-registry.sh      HTTPS registry for local tests
  smoke.sh               checks without an agent prompt
  project-config.sh      checks for a project lstk config and LSKIT_LSTK_CONFIG
  headless.sh            agent task with checks from outside the agent
```

## Versions

The mixin pins each tool with an argument in `kits/localstack/localstack.yaml`.
To change a version, change the default of its argument. The sets pin
Docker's agent kits by tag in their `kits:` lists.

| Argument | Tool |
| --- | --- |
| `lstk_version` | lstk |
| `mcp_server_version` | `@localstack/localstack-mcp-server` |
| `node_version` | Node.js, for the MCP server and AWS CDK |
| `terraform_version` | Terraform |
| `cdk_version` | AWS CDK CLI |
| `aws_cli_version` | AWS CLI v2 |
| `sam_version` | AWS SAM CLI |
| `localstack_image` | LocalStack image (set when the sandbox is created) |

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

The sandbox tests need KVM or Apple silicon, so run `make smoke`,
`make project-config`, and `make e2e` on your machine before a release.

## Release

1. Set the new version on all kits, and add an entry to `CHANGELOG.md`:

   ```console
   $ make bump VERSION=0.2.0
   ```

2. Run the sandbox tests against a local build (see above).
3. Commit, then push a tag that matches the version:

   ```console
   $ git tag v0.2.0
   $ git push origin v0.2.0
   ```

   `.github/workflows/release.yaml` builds both platforms, pushes the kits
   to `docker.io/localstack`, and signs them with the GitHub OIDC token
   (keyless). It needs the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`
   secrets in the `release` environment. This workflow has not run yet.

`scripts/build.sh` stops if the versions of the kits do not match, and if a
tag already exists on Docker Hub. Published tags must not change.

To release by hand, you need push access to the `localstack` namespace:

```console
$ docker login
$ make release
$ sbx kit sign docker.io/localstack/sbx-kit-localstack:0.2.0
```

Without `--key`, `sbx kit sign` signs keyless and opens a browser login.
With `--key key.pem`, it signs with an unencrypted PEM key.

Users verify a keyless signature from the release workflow like this:

```console
$ sbx kit verify docker.io/localstack/sbx-localstack-claude:0.2.0 \
    --certificate-identity 'https://github.com/localstack/docker-kit/.github/workflows/release.yaml@refs/tags/v0.2.0' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

For a key-based signature, they pass `--key cosign.pub` instead.
