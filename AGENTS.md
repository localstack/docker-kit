Working guidance for agents in this workspace. Read this before making changes, and keep it current: when a convention changes or a lesson emerges, edit this file in the same session so the next run inherits it.

## Commits

- Use Conventional Commits (https://www.conventionalcommits.org/en/v1.0.0/): type(scope): summary. Common types: feat, fix, docs, refactor, test, chore, build, ci.
- One line only. No body, no bullet lists, no closing notes.
- No attribution or tool footers. Do not add "Generated with" lines or Co-Authored-By trailers.
- One logical change per commit. Use a scope that maps to a repo area when it helps (harness, tasks, bench_assert, scaffold, docs, ci).
- Keep internal references out of messages: no TODO/milestone IDs (e.g. M02-T01) and no SPEC section numbers. The public history should read cleanly on its own.

Examples:

- feat(harness): boot sibling-container topology
- fix(bench_assert): honor deadline in poll_until
- docs: add endpoint-injection ADR
- chore: scaffold python project with uv

## Code

Follow Clean Code (Robert C. Martin). The rules that apply here:

Names
- Reveal intent: elapsed_seconds, not t.
- Do not mislead. Do not call something a list when it is a map.
- Classes are nouns; methods are verbs. Avoid Manager, Data, Info as class names.
- Keep them searchable and pronounceable.

Functions
- Small. Aim under 20 lines.
- Do one thing, at one level of abstraction.
- Zero to two arguments. Three or more needs a real reason.
- No hidden changes to global state.

Comments
- Make the code clear instead of commenting it. A good name beats a comment.
- No verbose or redundant comments, and no line-by-line narration.
- Fine to keep: legal headers, the intent behind a regex or wire format, a genuine warning, a TODO.
- No banner separators, and no comment that just repeats the function name.

Structure
- Newspaper order: high-level code first, details below.
- Declare variables near first use; keep related lines together.

Errors and data
- Raise exceptions rather than returning error codes.
- Do not use null or None as a normal signal, in or out.
- Hide implementation behind small interfaces. Respect the Law of Demeter: avoid a.get_b().get_c().do().

## Writing style

This applies to code, comments, commit messages, and prose. The aim is that nothing reads as machine-generated.

- No em dashes. Use commas, parentheses, or separate sentences.
- No marketing or filler. Drop words like seamless, powerful, robust, leverage, delve, and phrases like "it is worth noting".
- Be concrete. Say what a thing does, not how good it is.
- Avoid the patterns in Wikipedia's "Signs of AI writing" (https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing): inflated importance, padded hedging, everything in threes, "not only X but also Y", heavy signposting.
- Vary sentence length. Do not start consecutive list items with the same word.
- Prefer plain words over grand ones.

Always follow ASD-STE100 Simplified Technical English for writing comments or documentation.


## Kits

Lessons from building the kits in this repo. Scopes for commits here: kit, scripts, docs.

- Build kits with the lskit docker-container builder (scripts/build.sh). The docker driver with the classic image store (OrbStack, older Docker Desktop) pushes Docker v2 manifests. These drop the OCI annotation that holds the kit descriptor, so sbx does not see a kit.
- A kit set can only list published kits. Test sets against the local registry (make registry, make build-local).
- The local registry uses port 5055 and HTTPS. sbx pulls kits over HTTPS only, and on macOS AirPlay Receiver holds port 5000.
- A set cannot re-export a kit arg that has env:. Put create-time values in lifecycle files instead, then read the file.
- sbx kit validate cannot check a v3 source directory without the kit builder. A docker buildx build of the descriptor runs the same validation.
- Startup hooks must exit 0. A failed hook stops the sandbox boot.
- Codex passes only a short list of variables to stdio MCP servers. Name the others in env_vars.
- sbx builds a local kit directory (--kit ./kits/localstack) with the default Buildx builder. On OrbStack, set BUILDX_BUILDER=lskit.
- Kits from a third-party publisher need an approved credential binding. sbx asks only in a terminal, so approve once with an interactive sbx run before unattended tests.
- sbx 0.45 stops a local sandbox 30 seconds after the last session and ignores long-running@1. Tests keep an idle sbx exec session open.
- lstk treats AWS_ENDPOINT_URL as a remote emulator and refuses local commands. The kit's lstk wrapper removes it.
- localhost.localstack.cloud goes through the sandbox proxy unless it is in NO_PROXY, and the proxy resolves it on the host. Never remove the kit's NO_PROXY snippet or deny rules.
- The sandbox template sets GODEBUG=tarinsecurepath=0, which breaks AWS Lambda base image pulls. The kit's dockerd wrapper relaxes it for dockerd only.
- Zero-filled files in a pulled image mean the host disk was full (the sandbox log shows I/O errors on vdd). Check df before long test runs, and prune the lskit builder cache after builds.
- A set can only list kits whose descriptor is the same on every platform. docker/sbx-kit-codex 0.155.1 lists extra packages on arm64 and breaks multi-platform set builds. Check both platforms before you change a pinned agent kit.
- A project lstk config (.lstk/config.toml or LSKIT_LSTK_CONFIG) belongs to the user. Never rewrite it. The kit adds its defaults as LOCALSTACK_* variables, and only for keys the file does not set.
- sbx network rules match names, not resolved addresses. A deny for localhost does not stop another name that resolves to 127.0.0.1. Say so in the docs when a rule is a partial control.
- The first login shell of a new sandbox prints the template banner on stdout. Test helpers use bash -c, not bash -lc, when they read command output.
