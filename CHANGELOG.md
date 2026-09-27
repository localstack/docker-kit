# Changelog

This file lists the changes in each release of the kits.

## 0.1.0 (not released)

The first version.

### Added

- The LocalStack mixin, `sbx-kit-localstack`. It starts LocalStack with lstk
  when the sandbox boots, and adds the LocalStack MCP server, Terraform,
  AWS CDK, AWS SAM CLI, and AWS CLI v2 under `/opt/localstack-kit`.
- The Claude Code set, `sbx-localstack-claude`, and the Codex set,
  `sbx-localstack-codex`. Each set registers the MCP server with its agent.
- Support for the project config of lstk (`.lstk/config.toml`) and for
  `LSKIT_LSTK_CONFIG`. The config selects the emulator, the image, and the
  LocalStack variables.
- `lskit-status`, which shows the state of the start at boot.
- `lskit-check-config`, which reads a project config as TOML and refuses it
  when it starts an image outside `localstack/`.
- Network rules for LocalStack, Docker Hub, Lambda images, and package
  registries. Deny rules keep loopback names off the sandbox proxy.
- Test scripts (`make smoke`, `make project-config`, `make e2e`), CI, and a
  release workflow.

### Known limits

- The agent can read the LocalStack auth token. See `docs/security.md`.
- `sbx` 0.45 stops a local sandbox 30 seconds after the last session, so
  LocalStack starts again with no resources.
- Docker Cloud Sandboxes are not supported.
