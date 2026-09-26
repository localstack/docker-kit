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

