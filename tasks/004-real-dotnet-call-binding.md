# Task 004: Real .NET Call Binding

Priority: P0.

Make common .NET API calls, LINQ chains, lambdas, and signature help trustworthy as one authoring experience. This task intentionally crosses overload resolution, generic inference, lambda contextual typing, LINQ return types, diagnostics, and tooling output.

## User Outcome

A developer should be able to write representative .NET code using overloads, optional parameters, `params`, generics, extension methods, LINQ, lambdas, and expression-tree callbacks. Analyzer diagnostics, hover, signature help, query type, generated code, and IL execution should agree on the selected method and resulting type.

## Scope

- Finish overload scoring for optional parameters, `params`, numeric conversions, nullable conversions, generic methods, extension methods, named arguments, default arguments, and ambiguity diagnostics.
- Broaden generic inference using receiver, argument, lambda parameter, lambda return, return-target, and generic constraint information.
- Broaden lambda contextual typing for delegates, expression trees, extension methods, N# functions, LINQ, event handlers, and task continuations.
- Make LINQ return types correct for arrays, lists, dictionaries, `IEnumerable<T>`, `IQueryable<T>`, projections, and nullable element types.
- Make signature help and hover show the same selected overload the analyzer uses.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `src/NSharpLang.LanguageServer/Handlers/SignatureHelpHandler.cs`
- `tests/AnalyzerTests.cs`
- `tests/ILCompilerTests.cs`
- `tests/QueryIntegrationTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- Representative BCL and LINQ fixtures bind the correct overload and infer correct return types.
- Query type, hover, signature help, diagnostics, and runtime IL behavior agree.
- Ambiguous or invalid calls produce precise diagnostics at the bad call site.
- Tests cover real APIs rather than only synthetic examples.

## Verification

- Run focused analyzer, query, language-server, and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify hover and signature help for representative calls in VS Code.
