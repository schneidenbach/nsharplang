# Task 005: Semantic References And Rename

Priority: P0.

Make references and rename semantic across projects, files, scopes, and unsaved buffers. The product bar is that an LLM using `nlc query references` and a human using VS Code see the same trustworthy answer.

## User Outcome

When symbols share a simple name in different files, scopes, or receiver types, references and rename should target exactly the bound symbol. Open unsaved buffers must participate in the semantic project snapshot.

## Scope

- Make LSP references and `nlc query references` consume the same semantic project reference engine.
- Ensure open unsaved buffers override disk text in project snapshots.
- Remove or explicitly degrade unsafe text/name fallbacks that return precise-looking results.
- Cover locals, parameters, members, imported symbols, shadowed names, nested functions/lambdas, blocks, pattern bindings, and imported names.

## Likely Files

- `src/NSharpLang.Compiler/BindingMap.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/MultiFileCompiler.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Cli`
- `src/NSharpLang.LanguageServer`
- `tests/BindingMapTests.cs`
- `tests/AnalyzerSemanticModelTests.cs`
- `tests/QueryIntegrationTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- CLI references and LSP references agree for representative fixtures.
- Duplicate simple names in different scopes/files are not conflated.
- Unsaved cross-file edits affect references and rename before saving.
- Degraded states are explicit and do not look like precise semantic answers.

## Verification

- Run focused BindingMap, SemanticModel, query, and language-server tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify references/rename with unsaved buffers in VS Code.
