# Task 019: Implement `must` Explicit Unwrap

Priority: P1 nullability.

Work in the N# repository and implement explicit nullable unwrap/assertion syntax. The planned `must expr` syntax is missing and must lower to explicit runtime behavior, not C# null-forgiving syntax.

## Scope

- Add lexer, parser, AST, analyzer, formatter, C# export, and IL backend support for `must expr`.
- Type `must T?` as `T`.
- Diagnose redundant `must` on values proven non-null.
- Define and implement explicit throw behavior for null values.
- Decide whether assertion messages are in scope; if deferred, document the deferral in code/docs/tests.

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

- Parser, AST, analyzer, formatter, C# export, and IL backend support `must expr`.
- `must T?` has type `T`.
- Redundant `must` on proven non-null values reports a diagnostic.
- Lowering uses explicit throw behavior, not C# null-forgiving syntax.
- Optional assertion messages are either implemented or explicitly deferred.

## Verification

- Run focused parser, analyzer, formatter, transpiler, and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
