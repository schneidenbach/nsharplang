# Task 018: Format And Fix Automation

Priority: P2.

Make `nlc format` and `nlc fix` a dependable machine-driven editing loop. This is a vertical CLI automation task: formatter gate, fix catalog, dry-run JSON, safety metadata, and round-trip tests belong together.

## User Outcome

Humans and agents can run formatting and safe fixes over examples or projects, inspect planned edits as stable JSON, and apply them without corrupting code or losing formatting.

## Scope

- Audit examples, templates, and representative fixtures with `nlc format --check`.
- Fix unstable or ugly formatter output with regression tests.
- Add a CI or `./scripts/test-all.sh` formatting gate if the repo is expected to stay formatted.
- Expand `nlc fix` only for high-confidence diagnostics with accurate safe/review-needed/suggestion-only classification.
- Keep dry-run JSON stable and complete enough for automation.

## Likely Files

- `src/NSharpLang.Compiler/Formatter.cs`
- `src/NSharpLang.Compiler/CodeFixes`
- `src/NSharpLang.Cli/Commands/FixCommand.cs`
- `src/NSharpLang.Cli`
- `examples`
- `templates`
- `tests/FormatterTests.cs`
- `tests/CodeFixTests.cs`
- `tests/FixCommandTests.cs`
- `tests/CliParityAuditTests.cs`
- `scripts/test-all.sh`

## Acceptance

- Examples/templates/representative fixtures have a documented formatting audit or gate.
- New formatter behavior has focused tests for any changed layout.
- More diagnostics provide safe or review-needed fixes where edits are reliable.
- `nlc fix --dry-run --json` exposes stable edit and safety metadata.
- Applied fixes preserve parser/formatter round-tripping.

## Verification

- Run focused formatter, code fix, fix command, and CLI parity tests while developing.
- Run the chosen formatting gate.
- Run `./scripts/test-all.sh` before committing.
