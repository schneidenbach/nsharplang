# Task 025: Add Formatter Repo And Example Audit With CI Gate

Priority: P2 CLI quality.

Work in the N# repository and make `nlc format` trustworthy as a repo and examples gate. The command exists with check, diff, and stdin support, but examples and CI are not currently gated by formatting.

## Scope

- Audit current examples, templates, and representative fixtures with `nlc format --check`.
- Fix ugly or unstable formatter output with focused formatter changes and regression tests.
- Decide where formatting should be enforced: CI, `./scripts/test-all.sh`, or a documented release-gate command.
- Keep formatter output opinionated and stable; do not bikeshed style in docs.

## Likely Files

- `src/NSharpLang.Compiler/Formatter.cs`
- `src/NSharpLang.Cli`
- `examples`
- `templates`
- `tests/FormatterTests.cs`
- `tests/CliParityAuditTests.cs`
- `scripts/test-all.sh`
- `.github/workflows`

## Acceptance

- Current examples, templates, and representative fixtures have been audited with `nlc format --check`.
- Any ugly or unstable formatter output has focused regression tests.
- CI or `./scripts/test-all.sh` includes a formatting gate if the repo is expected to stay formatted.
- Documentation explains the supported formatting workflow.

## Verification

- Run focused formatter and CLI tests while developing.
- Run the chosen formatting gate.
- Run `./scripts/test-all.sh` before committing.
