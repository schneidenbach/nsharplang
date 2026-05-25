# Task 007: Nullable Unwrap And Match Idioms

Priority: P1.

Make nullable values pleasant and safe in idiomatic N# code. This combines explicit `must` unwrap, `Nullable<T>.HasValue` / `.Value` handling, nullable `match` narrowing, code fixes, formatter behavior, and backend lowering because they are the same developer-facing nullable value workflow.

## User Outcome

A developer can write `must value` when they intentionally assert a nullable value is present. The expression has the non-null inner type and throws explicitly at runtime if the value is null. Developers also get guidance away from unsafe `.Value`, can use guarded value patterns naturally, and can cover nullable cases in `match` with precise narrowing.

## Scope

- Add lexer, parser, AST, analyzer, formatter, C# export, and IL backend support for `must expr`.
- Type `must T?` as `T`.
- Lower null failure to explicit throw behavior, not C# null-forgiving syntax.
- Diagnose redundant `must` when flow facts already prove non-null.
- Recognize `Nullable<T>.HasValue` and `.Value` semantically.
- Report unguarded `.Value` as unsafe and offer safe or review-needed alternatives.
- Support `match name { null => ..., value => ... }` with `value` narrowed to non-null `T`.
- Report missing null coverage in expression contexts.
- Preserve existing union exhaustiveness behavior.

## Likely Files

- `src/NSharpLang.Compiler/Lexer.cs`
- `src/NSharpLang.Compiler/Parser.cs`
- `src/NSharpLang.Compiler/Ast.cs`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/Linter.cs`
- `src/NSharpLang.Compiler/Formatter.cs`
- `src/NSharpLang.Compiler/Transpiler.cs`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `src/NSharpLang.Compiler/CodeFixes`
- `src/NSharpLang.Cli/Commands/FixCommand.cs`
- `tests/ParserTests.cs`
- `tests/AnalyzerTests.cs`
- `tests/LinterTests.cs`
- `tests/FormatterTests.cs`
- `tests/TranspilerTests.cs`
- `tests/CodeFixTests.cs`
- `tests/FixCommandTests.cs`
- `tests/ILCompilerTests.cs`

## Acceptance

- `must expr` works through parser, analyzer, formatter, C# export, and IL backend.
- `must T?` has type `T`.
- Redundant `must` on proven non-null values reports a diagnostic.
- Runtime null behavior is explicit and tested.
- Guarded `.Value` can suggest an `is T value` or equivalent safer pattern.
- Unguarded `.Value` reports an unsafe access diagnostic.
- Nullable `match` narrows non-null arms correctly for reference and value nullable types.
- Missing null coverage produces a helpful exhaustiveness diagnostic where needed.
- Fixes preserve formatting and expose accurate safety metadata in dry-run JSON.
- Optional assertion messages are either implemented or deliberately deferred in docs/tests.

## Verification

- Run focused parser, analyzer, linter, formatter, transpiler, code fix, fix command, and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
