# Task 018: Add Possible-Null Diagnostics

Priority: P1 nullability.

Work in the N# repository and report unsafe nullable usage with helpful diagnostics. N# should catch member, index, and call access on maybe-null values, plus assignments from nullable to non-nullable without proof.

## Scope

- Use null-state facts to detect maybe-null dereference and unsafe nullable-to-non-nullable assignment, return, and argument passing.
- Add stable diagnostic codes and Elm-style messages.
- Provide concrete suggestions such as `?.`, `??`, a guard, or explicit assertion.
- Expose the same diagnostic information through terminal, JSON, and LSP surfaces.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/ErrorReporting.cs`
- `src/NSharpLang.Cli`
- `src/NSharpLang.LanguageServer`
- `tests/AnalyzerTests.cs`
- `tests/ErrorReportingTests.cs`
- `tests/CliCommandTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- Maybe-null dereference produces a stable diagnostic with suggestions for `?.`, `??`, a guard, or explicit assertion.
- Assigning, returning, or passing `T?` to `T` without proof is rejected or reported according to the chosen severity policy.
- JSON diagnostics, LSP diagnostics, and terminal output expose the same stable code and suggestion fields.
- Diagnostics avoid cascades after the first useful nullability error where possible.

## Verification

- Run focused analyzer, error reporting, CLI, and LSP diagnostics tests while developing.
- Run `./scripts/test-all.sh` before committing.
- If LSP diagnostics change, run `./scripts/reload-vscode-extension.sh` and visually verify in VS Code.
