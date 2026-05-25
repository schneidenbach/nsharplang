# Task 006: Finish Semantic Reference Parity In LSP And CLI

Priority: P0 semantic correctness.

Work in the N# repository and make references semantic and consistent across CLI query commands and the language server. Definition and rename prefer project-semantic snapshots when available, but references and degraded fallbacks still need hardening.

## Scope

- Audit `nlc query references`, LSP references, BindingMap construction, project snapshots, and open-buffer overlays.
- Make LSP references and CLI references consume the same semantic project reference engine where practical.
- Ensure open unsaved buffers override disk text in semantic snapshots.
- Remove or explicitly degrade unsafe simple-name fallbacks that return precise-looking text results.

## Likely Files

- `src/NSharpLang.Compiler/BindingMap.cs`
- `src/NSharpLang.Compiler/MultiFileCompiler.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Cli`
- `src/NSharpLang.LanguageServer`
- `tests/BindingMapTests.cs`
- `tests/QueryIntegrationTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- LSP references and `nlc query references` use the same semantic project reference engine.
- Open unsaved buffers override disk text in semantic snapshots.
- Duplicate simple names in different scopes/files are not conflated.
- If a semantic snapshot cannot be built, the tool reports an explicit degraded state instead of returning a precise-looking text result.

## Verification

- Run focused BindingMap, query, and LanguageServer reference tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify references in VS Code, including an unsaved cross-file change.
