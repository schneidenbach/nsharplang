# Task 007: Improve SemanticModel Scope And Lookup Completeness

Priority: P0 semantic correctness.

Work in the N# repository and make SemanticModel strong enough for editor-grade tooling. The model records more expression types now, but scope-aware identifier lookup is still too flat for completions, hover, rename, references, inlay hints, and query commands.

## Scope

- Audit current SemanticModel data structures, analyzer recording sites, and consumers that still re-walk ASTs independently.
- Add source-position-aware lookup for locals, parameters, members, imported symbols, shadowed names, nested functions, lambdas, blocks, and pattern bindings.
- Keep the model shared by CLI and LSP consumers instead of adding handler-local logic.
- Preserve deterministic behavior across multi-file projects and unsaved buffers.

## Likely Files

- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.LanguageServer`
- `tests/AnalyzerSemanticModelTests.cs`
- `tests/QueryIntegrationTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- Local variables, parameters, members, imported symbols, shadowed names, and nested scopes can be queried by source position.
- Completion, hover, rename, references, inlay hints, and query commands consume this shared model instead of re-walking ASTs differently.
- Tests cover shadowing, nested functions/lambdas, blocks, pattern bindings, and imported names.
- Existing query JSON contracts remain stable unless intentionally versioned.

## Verification

- Run focused SemanticModel, analyzer, query, and language server tests while developing.
- Run `./scripts/test-all.sh` before committing.
- If language server behavior changes, run `./scripts/reload-vscode-extension.sh` and visually verify affected editor features.
