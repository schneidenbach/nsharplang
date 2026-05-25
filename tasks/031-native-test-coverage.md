# Task 031: Add Native Test Coverage Reporting Or Document Its Absence

Priority: P2 CLI quality.

Work in the N# repository and resolve the `nlc test --coverage` story. The command currently reports that coverage is unavailable; either implement it or make the unsupported state explicit and consistent.

## Scope

- Audit `nlc test --coverage`, help text, JSON output, docs, website docs, and tests.
- Decide whether coverage implementation is in scope now.
- If implemented, support the xUnit-backed runner with clear output and artifacts.
- If deferred, make help/docs/JSON/exit codes explicit and consistent.

## Likely Files

- `src/NSharpLang.Cli/Program.Testing.cs`
- `src/NSharpLang.Cli`
- `docs`
- `website/docs`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`

## Acceptance

- Either coverage collection/reporting works for the xUnit-backed runner, or help/docs clearly state coverage is planned/unavailable.
- CLI exit codes and JSON output remain clear when coverage is requested before support exists.
- Docs and help text agree.
- Tests lock down the chosen behavior.

## Verification

- Run focused CLI test command tests while developing.
- Run `./scripts/test-all.sh` before committing.
