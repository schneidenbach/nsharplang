# Task 012: `must` Explicit Nullable Unwrap

Priority: P1.

Implement explicit nullable unwrap/assertion as a full language feature. `must expr` must be parsed, analyzed, formatted, exported, compiled, diagnosed, and surfaced consistently.

## User Outcome

A developer can write `must value` when they intentionally assert a nullable value is present. The expression has the non-null inner type and throws explicitly at runtime if the value is null. Redundant `must` on proven non-null values should be diagnosed.

## Scope

- Add lexer, parser, AST, analyzer, formatter, C# export, and IL backend support for `must expr`.
- Type `must T?` as `T`.
- Lower null failure to explicit throw behavior, not C# null-forgiving syntax.
- Diagnose redundant `must` when flow facts already prove non-null.
- Expose diagnostics and code actions where useful.

## Likely Files

- `src/NSharpLang.Compiler/Lexer.cs`
- `src/NSharpLang.Compiler/Parser.cs`
- `src/NSharpLang.Compiler/Ast.cs`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/Formatter.cs`
- `src/NSharpLang.Compiler/Transpiler.cs`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `tests/ParserTests.cs`
- `tests/AnalyzerTests.cs`
- `tests/FormatterTests.cs`
- `tests/TranspilerTests.cs`
- `tests/ILCompilerTests.cs`

## Acceptance

- `must expr` works through parser, analyzer, formatter, C# export, and IL backend.
- `must T?` has type `T`.
- Redundant `must` on proven non-null values reports a diagnostic.
- Runtime null behavior is explicit and tested.
- Optional assertion messages are either implemented or deliberately deferred in docs/tests.

## Verification

- Run focused parser, analyzer, formatter, transpiler, and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
