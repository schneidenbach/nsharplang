# Task 009: Harden Parser Recovery Beyond The Current Baseline

Priority: P1 parser and diagnostics.

Work in the N# repository and harden parser recovery. Current recovery already reports multiple useful errors and returns partial ASTs; this task is a hardening pass for malformed real-world editing and migration input, not a rewrite.

## Scope

- Audit parser synchronization, no-progress protections, partial AST shape, analyzer behavior after parse errors, formatter behavior on bad input, query command behavior, and LSP diagnostics.
- Add malformed fixtures that represent real editing and migration failures.
- Fix crashes, no-progress loops, missing high-signal diagnostics, and excessive cascades.
- Preserve valid-code parsing and existing AST shapes unless a change is required and tested.

## Likely Files

- `src/NSharpLang.Compiler/Parser.cs`
- `src/NSharpLang.Compiler/ErrorReporting.cs`
- `src/NSharpLang.Compiler/MultiFileCompiler.cs`
- `src/NSharpLang.LanguageServer`
- `tests/ParserErrorTests.cs`
- `tests/ErrorRecoveryPipelineTests.cs`
- `tests/DiagnosticGoldenTests.cs`

## Acceptance

- Fuzzed and hand-curated malformed files do not crash the parser, analyzer, LSP, formatter, or query commands.
- Recovery resumes at useful declaration and statement boundaries without excessive cascades.
- VS Code Problems shows all high-signal diagnostics for a malformed file.
- Golden or snapshot tests lock down representative recovery behavior.

## Verification

- Run focused parser, recovery pipeline, diagnostic golden, formatter, and LSP diagnostic tests while developing.
- Run `./scripts/test-all.sh` before committing.
- If LSP diagnostics change, run `./scripts/reload-vscode-extension.sh` and visually verify malformed-file diagnostics in VS Code.
