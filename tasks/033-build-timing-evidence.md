# Task 033: Add Built-In Build Timing Evidence Or Avoid Timing Claims

Priority: P2 evidence and docs.

Work in the N# repository and make timing/performance claims evidence-based. Do not make Go/Rust-speed claims without measurements.

## Scope

- Audit docs, website, README, talk materials, and CLI output for timing/performance claims.
- Decide whether to expose reliable build/check timing output now.
- If implemented, test timing output shape without making tests brittle.
- If not implemented, remove or soften public timing claims.

## Likely Files

- `src/NSharpLang.Cli`
- `docs`
- `website/docs`
- `docs/talk`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`

## Acceptance

- Either reliable build/check timing output exists and is tested, or timing claims are kept out of public docs.
- Benchmark and launch docs cite current measured artifacts.
- Static or unsupported performance claims are removed.
- Tests lock down any new CLI timing output contract.

## Verification

- Run focused CLI/docs tests while developing.
- Run docs/website build if docs or website change.
- Run `./scripts/test-all.sh` before committing if code changes.
