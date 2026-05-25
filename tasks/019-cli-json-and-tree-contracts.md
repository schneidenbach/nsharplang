# Task 019: CLI JSON And Dependency Tree Contracts

Priority: P2.

Keep CLI JSON contracts authoritative and make `nlc tree` docs match reality. This task owns the LLM-facing contract surface: help text, JSON schemas, docs, completions, parity tests, and dependency tree behavior.

## User Outcome

An LLM or script using `nlc` gets stable, versioned JSON and accurate documentation. `nlc tree` should not be documented as future work if it exists, and any missing behavior should be named precisely.

## Scope

- Treat `memory/components/cli-toolchain.md` as the canonical CLI contract reference.
- Audit CLI JSON outputs, help text, completion metadata, `docs/guide/cli-reference.md`, website docs, and tests.
- Version any breaking JSON changes and include migration notes.
- Audit `nlc tree` text/JSON output and docs parity.

## Likely Files

- `memory/components/cli-toolchain.md`
- `docs/guide/cli-reference.md`
- `website/docs`
- `src/NSharpLang.Cli`
- `tests/CodeIntelligenceOutputTests.cs`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`

## Acceptance

- CLI JSON envelopes, schema versions, error shapes, and field names are documented and tested.
- `nlc tree` behavior, help, JSON/text output, and docs agree.
- Missing dependency-tree capabilities are named precisely instead of saying the whole feature is absent.
- Breaking JSON changes increment schema versions.

## Verification

- Run focused CLI JSON contract and parity tests while developing.
- Run docs/website checks if docs change.
- Run `./scripts/test-all.sh` before committing if code changes.
