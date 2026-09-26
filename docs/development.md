# Development

## Layout

```text
kits/
  localstack/            the mixin (sbx-kit-localstack)
    localstack.yaml      kit descriptor: args, network rules, hooks, context
    localstack.dockerfile  tools under /opt/localstack-kit
    context.md           instructions for the agent
    files/bin/           lstk wrapper, startup hook, MCP launcher, shims
    files/etc/           shell snippet that keeps LocalStack names off the proxy
  localstack-claude/     set: Docker's Claude Code kit and the mixin
  localstack-codex/      set: Docker's Codex kit and the mixin
scripts/
  build.sh               build and push the mixin and the sets
  local-registry.sh      HTTPS registry for local tests
  smoke.sh               checks without an agent prompt
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

5. Run the checks. `smoke` uses no model credits. `e2e` gives the agent a
   task and uses model credits.

   ```console
   $ make smoke AGENT=claude
   $ make e2e AGENT=claude
   ```

Approve the agent credential for the set one time in an interactive
`sbx run` before you run `e2e`. The scripts create sandboxes without a
terminal, so `sbx` cannot ask.

The builds use a `docker-container` Buildx builder named `lskit`. The
`docker` driver with the classic image store drops the OCI annotation that
holds the kit descriptor. The builder cache can grow to about 10 GB. Remove
it with `docker buildx prune --builder lskit --all`.

## Release

Build both platforms and push to Docker Hub. You need push access to the
`localstack` namespace.

```console
$ docker login
$ make release
```

The build pushes the mixin first, because the sets pull it from the registry.
Increase the `version:` field in each descriptor for a new release, and
update the mixin tag in the `kits:` list of each set.

To sign the images, use `sbx kit sign` or cosign after the push. Users can
then verify them with `sbx kit verify`.
