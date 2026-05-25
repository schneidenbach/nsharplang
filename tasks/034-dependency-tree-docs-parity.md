# Task 034: Audit Dependency Tree Command And Docs Parity

Priority: P2 CLI and docs parity.

Work in the N# repository and make `nlc tree` docs match implemented behavior. The CLI has `nlc tree`, but docs still contain stale future-work wording around dependency tree visualization.

## Scope

- Audit `nlc tree` implementation, help text, JSON/text output, completion metadata, docs, website docs, and tests.
- Update docs to describe what exists today.
- Name any missing dependency-tree capability precisely instead of saying the whole feature is absent.
- Add parity tests to catch future drift.

## Likely Files

- `src/NSharpLang.Cli`
- `docs/guide/cli-reference.md`
- `website/docs`
- `memory/components/cli-toolchain.md`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`

## Acceptance

- `nlc tree` behavior, help, JSON/text output, and docs agree.
- Any missing dependency-tree capability is named precisely instead of saying the whole feature is absent.
- Parity tests catch future drift.
- CLI JSON contract documentation is updated if output changes.

## Verification

- Run focused CLI parity and docs tests while developing.
- Run `./scripts/test-all.sh` before committing if code changes.
