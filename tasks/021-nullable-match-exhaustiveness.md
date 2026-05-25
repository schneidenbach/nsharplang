# Task 021: Add Nullable `match` Exhaustiveness And Narrowing

Priority: P1 nullability.

Work in the N# repository and make nullable values first-class in `match`. Nullable values should narrow through `match`, and missing null coverage in expression contexts should produce helpful diagnostics.

## Scope

- Support null patterns in match exhaustiveness for nullable reference and nullable value types.
- Narrow non-null binding arms to `T` for `T?`.
- Preserve existing union exhaustiveness behavior.
- Add diagnostics for missing null coverage where match expression totality matters.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/Parser.cs` if syntax gaps exist
- `tests/AnalyzerTests.cs`
- `tests/ParserTests.cs`
- `tests/ILCompilerTests.cs` if runtime behavior is affected

## Acceptance

- `match name { null => ..., value => ... }` narrows `value` to non-null `T`.
- Missing null coverage in expression contexts produces a helpful exhaustiveness diagnostic.
- Value-type nullable and reference nullable cases are both tested.
- Existing union exhaustiveness remains intact.

## Verification

- Run focused parser, analyzer, and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
