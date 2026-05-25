# Task 022: Test Coverage And Publish Scope Truth

Priority: P2.

Make `nlc test --coverage`, `nlc build --release`, `nlc publish`, and target-platform support honest and tested. These are adjacent command-truth issues: users need exact behavior, clear unsupported messages, and docs that match.

## User Outcome

A user knows whether native coverage is supported, what release builds do, which publish targets work, and what cross-compilation scenarios are unsupported. Unsupported scenarios fail with useful guidance.

## Scope

- Audit `nlc test --coverage`, `nlc build --release`, `nlc publish`, target-runtime options, docs, website docs, templates, and tests.
- Either implement coverage for the xUnit-backed runner or make unavailable coverage explicit in help/docs/JSON/exit codes.
- Define exactly what target-platform workflows are supported today.
- Add scenario tests for supported publish paths and helpful failures for unsupported paths.

## Likely Files

- `src/NSharpLang.Cli/Program.Testing.cs`
- `src/NSharpLang.Cli`
- `src/NSharpLang.Sdk`
- `docs`
- `website/docs`
- `tests/CompilationBackendTests.cs`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`

## Acceptance

- Coverage behavior is either implemented or consistently documented as unavailable/planned.
- CLI exit codes and JSON output are clear when unsupported coverage is requested.
- Product docs state exactly what release build, publish, and target-platform workflows support today.
- Unsupported target scenarios fail with clear guidance.
- Supported publish paths have scenario tests.

## Verification

- Run focused test/publish CLI and SDK tests while developing.
- Run docs/website checks if docs change.
- Run `./scripts/test-all.sh` before committing if code changes.
