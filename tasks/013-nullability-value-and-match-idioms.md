# Task 013: Nullable Value And Match Idioms

Priority: P1.

Make nullable values pleasant and safe in idiomatic N# code. This task combines semantic handling for `Nullable<T>.HasValue` / `.Value`, code fixes, nullable `match` narrowing, and exhaustiveness.

## User Outcome

Developers should get guidance away from unsafe `.Value`, should be able to use guarded value patterns naturally, and should be able to cover nullable cases in `match` with precise narrowing.

## Scope

- Recognize `Nullable<T>.HasValue` and `.Value` semantically.
- Report unguarded `.Value` as unsafe and offer safe or review-needed alternatives.
- Support `match name { null => ..., value => ... }` with `value` narrowed to non-null `T`.
- Report missing null coverage in expression contexts.
- Preserve existing union exhaustiveness behavior.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/Linter.cs`
- `src/NSharpLang.Compiler/CodeFixes`
- `src/NSharpLang.Cli/Commands/FixCommand.cs`
- `tests/AnalyzerTests.cs`
- `tests/LinterTests.cs`
- `tests/CodeFixTests.cs`
- `tests/FixCommandTests.cs`
- `tests/ILCompilerTests.cs`

## Acceptance

- Guarded `.Value` can suggest an `is T value` or equivalent safer pattern.
- Unguarded `.Value` reports an unsafe access diagnostic.
- Nullable `match` narrows non-null arms correctly for reference and value nullable types.
- Missing null coverage produces a helpful exhaustiveness diagnostic where needed.
- Fixes preserve formatting and expose accurate safety metadata in dry-run JSON.

## Verification

- Run focused analyzer, linter, code fix, fix command, and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
