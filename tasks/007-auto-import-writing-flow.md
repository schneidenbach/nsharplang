# Task 007: Auto-Import Writing Flow

Priority: P1.

Make completion help developers write code by offering useful local symbols first and importable symbols when needed. This task owns the complete auto-import experience: ranking, coverage, import edits, diagnostics around duplicate names, tests, and real VS Code verification.

## User Outcome

When a developer types `Console`, `List`, or a project-defined type that is not imported, completion should offer the right symbol, insert the import cleanly, and avoid drowning local symbols in imported suggestions. Existing imports and package declarations must remain intact.

## Scope

- Rank local and in-scope symbols ahead of importable symbols.
- Broaden importable project and external symbol coverage without noisy duplicates.
- Place `additionalTextEdits` consistently after package/import declarations.
- Handle duplicate names from multiple namespaces without corrupting code or hiding the distinction.

## Likely Files

- `src/NSharpLang.LanguageServer/Handlers/CompletionHandler.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `tests/LanguageServerAutoImportTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- Completion ranking favors local/in-scope symbols before importable symbols.
- Auto-import covers project symbols and relevant external symbols without noisy duplicate suggestions.
- Import edits preserve existing package/import layout.
- Tests cover duplicate names, already-imported namespaces, no-import-needed cases, and insertion after existing imports.

## Verification

- Run focused completion and auto-import tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify completion ranking and import insertion in VS Code.
