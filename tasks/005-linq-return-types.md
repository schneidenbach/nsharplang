# Task 005: Make LINQ Return Types Fully Trustworthy

Priority: P0 semantic correctness.

Work in the N# repository and make LINQ chains report and use correct types everywhere. Common `Where`, `Select`, and `ToList` chains are improved, but LINQ correctness still depends on incomplete overload resolution, generic inference, lambda typing, and collection type construction.

## Scope

- Audit representative LINQ chains over arrays, `IEnumerable<T>`, `IQueryable<T>`, lists, dictionaries, nullable element types, and projection-like shapes.
- Ensure selected overloads, inferred generic arguments, lambda parameter types, lambda return types, and final return types are represented consistently.
- Keep query type, hover, completions, signature help, diagnostics, C# export, and IL compiler behavior aligned.
- Add diagnostics at the bad call site for incorrect chains.

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

- Query type, hover, completions, and signature help report the same types across representative LINQ chains.
- `IEnumerable<T>`, `IQueryable<T>`, arrays, lists, dictionaries, projections, and nullable element types are covered.
- Incorrect chains produce precise diagnostics at the bad call site.
- Runtime IL execution works for representative valid chains.

## Verification

- Run focused analyzer, query, language server, and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
- If hover/completion/signature help changes, run `./scripts/reload-vscode-extension.sh` and visually verify representative LINQ chains in VS Code.
