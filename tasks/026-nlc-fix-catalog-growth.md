# Task 026: Grow `nlc fix` Into A Broader Machine-Drivable Tool

Priority: P2 CLI quality and automation.

Work in the N# repository and expand `nlc fix` without weakening safety or JSON contracts. The command exists, but the fix catalog is still narrow.

## Scope

- Audit current diagnostics and identify high-confidence fixes.
- Add fix providers only where edits can be represented accurately and safely.
- Preserve dry-run JSON stability and include enough edit/safety metadata for automation.
- Ensure applied fixes preserve formatting and parser round-tripping.

## Likely Files

- `src/NSharpLang.Compiler/CodeFixes`
- `src/NSharpLang.Cli/Commands/FixCommand.cs`
- `src/NSharpLang.Compiler/Linter.cs`
- `tests/CodeFixTests.cs`
- `tests/FixCommandTests.cs`
- `tests/CliCommandTests.cs`

## Acceptance

- More high-confidence compiler/lint diagnostics provide safe or review-needed fixes.
- Dry-run JSON remains stable and includes enough edit/safety metadata for automation.
- Applied fixes preserve formatting and are covered by parser/formatter round-trip tests.
- Help text and docs match the implemented safety model.

## Verification

- Run focused code fix and fix command tests while developing.
- Run `./scripts/test-all.sh` before committing.
