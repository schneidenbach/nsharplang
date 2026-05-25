# Task 036: Keep CLI JSON Contracts Authoritative

Priority: P2 CLI and LLM-first tooling.

Work in the N# repository and keep CLI JSON contracts stable, documented, and tested. The CLI JSON contract is central to the LLM-first story and must not drift across docs, help text, completions, and tests.

## Scope

- Treat `memory/components/cli-toolchain.md` as the canonical CLI contract reference.
- Audit `docs/guide/cli-reference.md`, website docs, command help, completion metadata, JSON output tests, and examples for drift.
- Version any breaking JSON changes and include migration notes.
- Keep error envelopes, success envelopes, schema versions, and field names consistent.

## Likely Files

- `memory/components/cli-toolchain.md`
- `docs/guide/cli-reference.md`
- `website/docs`
- `src/NSharpLang.Cli`
- `tests/CodeIntelligenceOutputTests.cs`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`

## Acceptance

- `memory/components/cli-toolchain.md` remains the canonical contract reference.
- `docs/guide/cli-reference.md`, website docs, help text, completions, and tests stay in sync.
- Breaking JSON changes increment schema versions and include migration notes.
- JSON contract tests cover representative command outputs.

## Verification

- Run focused CLI JSON contract and parity tests while developing.
- Run docs/website checks if docs change.
- Run `./scripts/test-all.sh` before committing if code changes.
