# Security

This page tells you what the kit isolates, what it does not isolate, and why.

## Summary

| Asset | Protected | How |
| --- | --- | --- |
| Your host files and processes | Yes | The Docker Sandboxes microVM. The agent sees only the workspace that you mount. |
| Your AWS accounts | Partly | The sandbox gets no AWS credentials. The AWS tools point at LocalStack. The kit does not block AWS endpoints. |
| A LocalStack or other service on your host | Partly | The kit denies loopback names at the sandbox proxy. Under the `allow-all` policy, another name that resolves to `127.0.0.1` still reaches the host. |
| Your agent credentials | Yes | Docker Sandboxes keeps them on the host. The sandbox gets a placeholder. |
| Your LocalStack auth token | No | The token must be in the sandbox. The agent can read it. |

## LocalStack auth token

The agent can read the LocalStack auth token. The kit cannot prevent this.

Docker Sandboxes can keep a credential on the host and add it to outgoing
requests as an HTTP header. This does not work for LocalStack, for two
reasons:

1. LocalStack sends the token in the JSON body of the license request to
   `api.localstack.cloud`, not in a header.
2. LocalStack also uses the token in the container. It uses the token to
   check the cached license and to decrypt LocalStack code. A placeholder
   value fails these steps.

The token gets into the sandbox from `sbx run -e LOCALSTACK_AUTH_TOKEN`.
`sbx` stores it with the sandbox. The agent runs with `sudo` and Docker
access in the sandbox, so it can read the variable, the container
environment, or the process list.

Do these steps to limit the risk:

- Use a token that you can revoke without effect on your other work.
- Revoke the token if you think that it was exposed, for example in a commit
  or a log.
- Do not give the agent tasks that print or upload environment variables.
- Keep the network policy strict (see below). With a strict policy, the agent
  can send data only to the hosts that the kits allow.

The agent context tells the agent not to print, log, or commit the token.
This is an instruction, not a control.

## AWS accounts

The kit sets `AWS_ACCESS_KEY_ID=test`, `AWS_SECRET_ACCESS_KEY=test`, and
`AWS_ENDPOINT_URL=http://localhost:4566`. The AWS CLI, the AWS SDKs,
Terraform, AWS CDK, and AWS SAM send requests to LocalStack.

The kit does not deny AWS endpoints, so that you can decide. With the
`allow-all` policy, the agent can connect to AWS endpoints, but it has no
valid credentials. If your workspace contains AWS credentials, for example in
a `.env` file, the agent can read them.

To block AWS endpoints for one sandbox, add deny rules:

```console
$ sbx policy deny network --sandbox ls-claude '**.amazonaws.com'
$ sbx policy deny network --sandbox ls-claude '**.aws.amazon.com'
```

## Services on the host

Through the sandbox proxy, loopback is the host. The host can run its own
LocalStack or other local services. `localhost.localstack.cloud` and its
subdomains resolve to `127.0.0.1`, so a client that sends these names to the
proxy reaches the host.

The kit does two things:

- It adds the LocalStack names to `NO_PROXY` and to the Java proxy bypass
  list, for agent shells, lstk, and the MCP server. These clients connect
  directly to the LocalStack in the sandbox.
- It denies `localhost`, `127.0.0.0/8`, `::1`, `host.docker.internal`,
  `localhost.localstack.cloud`, and `**.localhost.localstack.cloud` at the
  proxy. A request for these names through the proxy gets HTTP 403.

This stops accidental access. It does not stop an agent that tries on
purpose: the proxy rules match names, so under the `allow-all` policy, any
other name that resolves to `127.0.0.1`, such as `127.0.0.1.nip.io`, still
reaches the host. The `balanced` and `deny-all` policies refuse names that no
rule allows, so they close this path.

## Docker daemon setting

The sandbox template starts Docker with `GODEBUG=tarinsecurepath=0`. With
this setting, Go rejects a tar entry whose name is not a local path. The AWS
Lambda base images on `public.ecr.aws` have a directory entry with an empty
name, so Docker cannot pull them, and LocalStack cannot run Lambda functions.

The kit adds `/usr/local/bin/dockerd`, a small script that starts
`/usr/bin/dockerd` with `tarinsecurepath=1`. The change applies to the Docker
daemon only. Other programs in the sandbox keep the template setting. Docker
still keeps each path of a layer inside the layer root.

## Network rules

The mixin allows these hosts on port 443. The agent kit adds the hosts that
the agent needs.

| Hosts | Used by |
| --- | --- |
| `api.localstack.cloud`, `analytics.localstack.cloud` | License activation and product events |
| `registry-1.docker.io`, `auth.docker.io`, `index.docker.io`, `production.cloudflare.docker.com`, `production.cloudfront.docker.com` | LocalStack image pulls |
| `public.ecr.aws`, `d2glxqk2uabbnd.cloudfront.net` | Lambda runtime images |
| `registry.terraform.io`, `releases.hashicorp.com` | Terraform providers and modules |
| `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org` | Packages for CDK apps, Lambda code, and tests |
| `github.com`, `api.github.com`, `codeload.github.com`, `objects.githubusercontent.com`, `raw.githubusercontent.com` | Source downloads and Terraform modules |
| `wings.crawlchat.app`, `us.i.posthog.com` | LocalStack MCP server: documentation search and analytics |

Kit allow rules add to your policy. Under the `allow-all` policy, they have
no effect. Under `balanced` or `deny-all`, they are the hosts that the
sandbox can reach. Organization policy can override them. Kit deny rules
(see [Services on the host](#services-on-the-host)) apply under every policy.
To see which requests the policy blocked, run `sbx policy log`.

## Telemetry

LocalStack, lstk, and the LocalStack MCP server send usage events by default.
To turn them off for a sandbox, pass these variables when you create it:

```console
$ sbx run -e LOCALSTACK_AUTH_TOKEN -e LOCALSTACK_DISABLE_EVENTS=1 \
    -e MCP_ANALYTICS_DISABLED=1 ...
```

Some LocalStack plans require telemetry. On these plans, LocalStack ignores
`DISABLE_EVENTS`.
