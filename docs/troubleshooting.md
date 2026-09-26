# Troubleshooting

## Check the LocalStack start

The kit starts LocalStack in a startup hook and writes its state to
`/tmp/localstack-kit/status`. Read the state and the log from the host:

```console
$ sbx exec ls-claude bash -lc 'cat /tmp/localstack-kit/status; tail -n 40 /tmp/localstack-kit/start.log'
```

| State | Meaning |
| --- | --- |
| `starting` | lstk is pulling the image or starting the container. The first pull takes some minutes. |
| `running` | LocalStack is ready. |
| `missing-token` | The sandbox has no `LOCALSTACK_AUTH_TOKEN`. Create the sandbox again with `-e LOCALSTACK_AUTH_TOKEN`. |
| `docker-unavailable` | Docker in the sandbox did not start in 180 seconds. |
| `failed` | lstk start failed. Read the log. |

To start LocalStack again, run `lstk start` in the sandbox.

## The kit source is not in your allowlist

```text
cannot be installed — its source is not in your allowlist
```

`sbx` loads kits from `docker.io/` only by default. The published kits are on
Docker Hub. If you use another registry, add its prefix:

```console
$ sbx settings set kit.allowedSources '["docker.io/","registry.example.com/localstack/"]'
```

## License validation failed

```text
License validation failed ... invalid, inactive, or expired authentication token
```

Make sure that `LOCALSTACK_AUTH_TOKEN` holds the token itself. On macOS, the
keychain entry of `lstk login` holds an encoded value
(`go-keyring-base64:...`), not the token. To decode it:

```console
$ security find-generic-password -s lstk -a lstk.auth-token -w \
    | sed 's/^go-keyring-base64://' | base64 -d
```

## SyntaxError: source code string cannot contain null bytes

LocalStack fails at start with this error when its image files contain
zeros. This occurs when the host disk is full while the sandbox pulls the
image: the sandbox disk grows on the host, and the writes fail. The sandbox
log then shows `I/O error, dev vdd`.

1. Make free space on the host disk.
2. Remove the damaged image in the sandbox and start again:

   ```console
   $ sbx exec ls-claude bash -lc 'docker rm -f localstack-main; docker rmi localstack/localstack-pro:2026.8.4; lstk start'
   ```

## LocalStack has no resources after I come back

`sbx` 0.45 stops a local sandbox 30 seconds after the last session ends.
LocalStack starts again with no resources on the next session. Save a
snapshot before you leave, and load it when you come back:

```console
$ lstk snapshot save ./localstack.snapshot
$ lstk snapshot load ./localstack.snapshot
```

## lstk refuses start, stop, or logs

```text
start does not support AWS_ENDPOINT_URL
```

lstk reads `AWS_ENDPOINT_URL` as an instruction to use a remote emulator. The
`lstk` command of the kit (`/opt/localstack-kit/bin/lstk`) removes the
variable before it runs lstk. This error occurs only if you run the lstk
binary directly.

## Port 4566 is in use on the host

If LocalStack also runs on your host, `-p 4566:4566` cannot publish the
port. Use a different host port, for example `-p 4567:4566`. In the sandbox,
LocalStack stays on port 4566.

## The agent credential is not used

```text
no binding authorizes anthropic — the credential was not injected
```

These kits are third-party kits for `sbx`, so you must approve the agent
credential one time. `sbx` asks for approval only in an interactive
terminal. Run the kit one time with `sbx run` in a terminal. After that,
unattended runs such as `sbx create` or `sbx run -d` use the approval.

## A request is blocked

Under the `balanced` or `deny-all` policy, run `sbx policy log` to see which
host was blocked and by which rule. Add a rule for one sandbox:

```console
$ sbx policy allow network --sandbox ls-claude example.com:443
```

## A local kit build fails with the docker driver

```text
OCI exporter is not supported for the docker driver
```

`sbx run --kit ./kits/localstack` builds the kit with your default Docker
Buildx builder. The `docker` driver without the containerd image store
(for example on OrbStack) cannot export OCI images. Use a
`docker-container` builder:

```console
$ docker buildx create --name lskit --driver docker-container --bootstrap
$ BUILDX_BUILDER=lskit sbx run -e LOCALSTACK_AUTH_TOKEN \
    docker.io/docker/sbx-kit-claude:2.1.278 --kit ./kits/localstack .
```
