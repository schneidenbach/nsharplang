# Task 020: Add Nullable Value Idiom Diagnostics And Fixes

Priority: P1 nullability and migration ergonomics.

Work in the N# repository and add semantic guidance for nullable value idioms. Migration lints catch blind `.Value` and null-forgiving artifacts syntactically, but semantic nullable-value guidance is incomplete.

## Scope

- Recognize `Nullable<T>.HasValue` and `.Value` semantically.
- Detect unguarded `.Value` access.
- Recognize guarded `.Value` patterns and suggest safer idioms where possible.
- Add code fixes with accurate safety classifications: safe, review-needed, or suggestion-only.
- Ensure fixes preserve formatting and round-trip through parser/formatter.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/Linter.cs`
- `src/NSharpLang.Compiler/CodeFixes`
- `src/NSharpLang.Cli/Commands/FixCommand.cs`
- `tests/AnalyzerTests.cs`
- `tests/LinterTests.cs`
- `tests/CodeFixTests.cs`
- `tests/FixCommandTests.cs`

## Acceptance

- `Nullable<T>.HasValue` and `.Value` are recognized semantically.
- Guarded `.Value` can suggest an `is T value` pattern.
- Unguarded `.Value` reports an unsafe access diagnostic.
- Fixes are marked safe, review-needed, or suggestion-only and round-trip through parser/formatter.
- CLI dry-run JSON exposes fix safety and edit metadata consistently.

## Verification

- Run focused analyzer, linter, code fix, and fix command tests while developing.
- Run `./scripts/test-all.sh` before committing.
