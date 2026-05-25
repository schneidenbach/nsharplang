# Task 012: Polish Auto-Import Completion Ranking And Coverage

Priority: P1 IDE tooling.

Work in the N# repository and make auto-import completion feel product-grade. Auto-import completion exists, but ranking and symbol coverage need polish so suggestions are useful without being noisy or corrupting imports.

## Scope

- Audit completion ranking, local/in-scope symbols, project symbols, external symbols, and duplicate label behavior.
- Ensure local and in-scope symbols rank before importable symbols.
- Broaden coverage for useful project and external symbols without flooding completion lists.
- Verify `additionalTextEdits` insert imports consistently after package/import declarations and do not corrupt files.

## Likely Files

- `src/NSharpLang.LanguageServer/Handlers/CompletionHandler.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `tests/LanguageServerAutoImportTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- Completion ranks local/in-scope symbols before importable symbols.
- Auto-import covers project symbols and relevant external symbols without noisy or duplicate suggestions.
- `additionalTextEdits` place imports consistently and do not corrupt existing imports/packages.
- Tests cover duplicate names and same-name symbols from different namespaces.

## Verification

- Run focused completion and auto-import tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify ranking and import insertion in VS Code.
