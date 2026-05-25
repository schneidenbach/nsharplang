# Task 010: Keep Diagnostic Quality From Regressing

Priority: P1 parser and diagnostics.

Work in the N# repository and keep Elm-style diagnostic quality high as features evolve. Diagnostic infrastructure and top diagnostic goldens exist, but new diagnostics can still regress clarity, source spans, suggestions, JSON fields, or VS Code presentation.

## Scope

- Audit recently added diagnostics across compiler, CLI, linter, fixes, and language server surfaces.
- Ensure common diagnostics include source snippets, explanations, concrete suggestions, stable codes, and docs links where appropriate.
- Keep terminal, JSON, and LSP diagnostic outputs aligned.
- Refresh golden tests only when behavior changes intentionally.

## Likely Files

- `src/NSharpLang.Compiler/ErrorReporting.cs`
- `src/NSharpLang.Compiler/Diagnostic*`
- `src/NSharpLang.Cli`
- `src/NSharpLang.LanguageServer`
- `tests/DiagnosticGoldenTests.cs`
- `tests/ErrorReportingTests.cs`
- `tests/CliCommandTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- New common diagnostics include source snippets, explanations, concrete suggestions, stable codes, and docs links.
- The top diagnostic golden suite is refreshed when diagnostics change intentionally.
- LSP/VS Code squiggles and quick fixes are visually verified for IDE-facing diagnostic changes.
- JSON diagnostic contracts remain stable unless intentionally versioned.

## Verification

- Run focused error reporting, diagnostic golden, CLI, and LSP tests while developing.
- Run `./scripts/test-all.sh` before committing.
- If IDE-facing diagnostics change, run `./scripts/reload-vscode-extension.sh` and visually verify squiggles, Problems entries, hover text, and quick fixes in VS Code.
