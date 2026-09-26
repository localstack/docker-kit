# Security policy

## Report a vulnerability

Do not open a public issue for a vulnerability. Use the private
vulnerability reporting of GitHub: open the **Security** tab of this
repository, and select **Report a vulnerability**.

Give this information:

- The kit version and the `sbx` version (`sbx version`).
- The steps that show the problem.
- The effect, for example which secret or which host a sandbox can reach.

Maintainers: turn on private vulnerability reporting in the settings of the
repository.

## Scope

This repository covers the kit descriptors, the scripts, and the docs.
Report a problem in LocalStack, lstk, the LocalStack MCP server, or Docker
Sandboxes to that project.

## Security model

[docs/security.md](docs/security.md) tells you what the kit isolates, what
it does not isolate, and why.
