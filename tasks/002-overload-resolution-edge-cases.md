# Task 002: Finish Overload Resolution Edge Cases

Priority: P0 semantic correctness.

Work in the N# repository and make reflection-backed overload resolution trustworthy for real .NET APIs. The current binder is materially better than arity matching, but overload scoring is not complete enough to trust every method call, hover, signature help result, query type result, or emitted call.

## Scope

- Audit reflection-backed call binding and any separate N# function/method overload path.
- Align candidate filtering and scoring across analyzer, query, LSP, C# export, and IL backend expectations.
- Handle optional parameters, `params`, numeric conversions, nullable conversions, generic methods, extension methods, named arguments, default arguments, and ambiguity diagnostics consistently.
- Avoid special-casing individual BCL APIs except as regression fixtures.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `src/NSharpLang.LanguageServer/Handlers/SignatureHelpHandler.cs`
- `tests/AnalyzerTests.cs`
- `tests/ILCompilerTests.cs`
- `tests/QueryIntegrationTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- Candidate scoring handles optional parameters, `params`, numeric conversions, nullable conversions, generic methods, extension methods, and ambiguity diagnostics consistently.
- Wrong overload selection has regression tests using real BCL APIs.
- Hover, signature help, query type, diagnostics, and generated/compiled code agree on the selected overload.
- Ambiguous calls produce precise diagnostics instead of silently picking an arbitrary candidate.

## Verification

- Run focused analyzer, query, signature help, and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
- If language server behavior changes, run `./scripts/reload-vscode-extension.sh` and visually verify representative overload signature help/hover in VS Code.
