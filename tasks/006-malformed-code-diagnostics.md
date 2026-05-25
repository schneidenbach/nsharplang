# Task 006: Malformed Code Diagnostics

Priority: P0.

Make malformed code survivable and helpful across parser, analyzer, formatter, CLI query, and VS Code Problems. This is an editing workflow task, not a parser-only task.

## User Outcome

While a developer is halfway through typing broken code, N# should not crash, hang, lose the rest of the file, or flood them with useless cascades. The terminal and VS Code should show high-signal diagnostics with useful locations and suggestions.

## Scope

- Harden parser recovery around declaration and statement boundaries.
- Prevent no-progress loops and excessive diagnostic cascades.
- Ensure analyzer, formatter, query commands, and language server tolerate partial ASTs.
- Keep diagnostic text concrete, actionable, and stable.
- Refresh goldens only for intentional diagnostic changes.

## Likely Files

- `src/NSharpLang.Compiler/Parser.cs`
- `src/NSharpLang.Compiler/ErrorReporting.cs`
- `src/NSharpLang.Compiler/MultiFileCompiler.cs`
- `src/NSharpLang.Cli`
- `src/NSharpLang.LanguageServer`
- `tests/ParserErrorTests.cs`
- `tests/ErrorRecoveryPipelineTests.cs`
- `tests/DiagnosticGoldenTests.cs`
- `tests/LanguageServerDiagnosticsTests.cs`

## Acceptance

- Fuzzed and hand-curated malformed files do not crash parser, analyzer, formatter, LSP, or query commands.
- Recovery resumes at useful boundaries without excessive cascades.
- Terminal, JSON, and LSP diagnostics include stable codes, useful spans, explanations, and suggestions where appropriate.
- VS Code Problems shows all high-signal diagnostics for a malformed file.

## Verification

- Run focused parser recovery, diagnostic golden, formatter bad-input, CLI, and LSP diagnostic tests while developing.
- Run `./scripts/test-all.sh` before committing.
- If LSP diagnostics change, run `./scripts/reload-vscode-extension.sh` and visually verify malformed-code diagnostics in VS Code.
