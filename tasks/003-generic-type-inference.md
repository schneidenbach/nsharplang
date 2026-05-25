# Task 003: Broaden Generic Type Inference

Priority: P0 semantic correctness.

Work in the N# repository and make generic inference reliable for broader .NET and N# APIs. Common paths work, but the binder still loses type information in broader generic APIs, chained calls, constrained generics, and callback-heavy signatures.

## Scope

- Audit generic inference in reflection-backed calls, N# function calls, extension methods, LINQ-style chains, and local/user-defined generic functions.
- Use receiver, argument, lambda parameter, lambda return, return-target, and generic constraint information where applicable.
- Keep inference failures explicit and diagnosable; do not silently fall back to `unknown` when the result is observable.
- Ensure inferred types flow into SemanticModel, query commands, hover, completions, signature help, and IL emission.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `tests/AnalyzerTests.cs`
- `tests/ILCompilerTests.cs`
- `tests/QueryIntegrationTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- Inference uses receiver, argument, lambda parameter, lambda return, return-target, and generic constraint information where applicable.
- Failed inference produces a useful diagnostic instead of silently falling back to `unknown`.
- Tests cover multi-parameter generic methods, chained generic APIs, nested generic collections, constrained generic calls, and generic extension methods.
- Query type, hover, completions, signature help, and runtime behavior agree for representative generic calls.

## Verification

- Run focused analyzer, query, language server, and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
- If language server output changes, run `./scripts/reload-vscode-extension.sh` and visually verify generic hover/completion/signature help in VS Code.
