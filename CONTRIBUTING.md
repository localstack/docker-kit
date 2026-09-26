# Contributing

Read [AGENTS.md](AGENTS.md) first. It has the rules for code, commits, and
docs, and the lessons from the work on the kits so far.

## Change a kit

1. Change the files under `kits/`. [docs/development.md](docs/development.md)
   describes the layout.
2. Run `make lint`.
3. Build the kits into the local registry, and run the sandbox tests on your
   machine:

   ```console
   $ make build-local
   $ make smoke AGENT=claude
   $ make project-config AGENT=claude
   $ make e2e AGENT=claude
   ```

   Run them for `AGENT=codex` too when the change affects both sets.
   `make e2e` uses model credits.

## Commits

Use one line in the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
format, and put one logical change in each commit. Use the scopes `kit`,
`scripts`, or `docs` where they fit.

## Pull requests

CI must pass. In the description, tell which sandbox tests you ran, for
which agents, and on which platform.
