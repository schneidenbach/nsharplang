# Task 023: Surface Nullability Through Query, Fixes, And LSP

Priority: P1 nullability and tooling.

Work in the N# repository and make nullability visible to tools, not just analyzer internals. Query commands, code fixes, and VS Code diagnostics/actions should expose nullable and null-state information coherently.

## Scope

- Extend `nlc query type` and `nlc query inspect` with nullable/null-state information under versioned JSON contracts.
- Add code actions for nullability diagnostics where safe or review-needed edits exist.
- Make VS Code distinguish safe fixes from review-needed migration suggestions.
- Keep terminal, JSON, and LSP behavior aligned.

## Likely Files

- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Cli`
- `src/NSharpLang.LanguageServer`
- `src/NSharpLang.Compiler/CodeFixes`
- `tests/QueryIntegrationTests.cs`
- `tests/CodeIntelligenceOutputTests.cs`
- `tests/CodeFixTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- `nlc query type` and `inspect` expose nullable/null-state information under a versioned JSON contract.
- Code actions are available for nullability diagnostics where a safe or review-needed edit exists.
- VS Code distinguishes safe fixes from review-needed migration suggestions.
- JSON schema tests cover the new contract fields.

## Verification

- Run focused query JSON, code fix, and language server tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify representative nullability diagnostics and code actions in VS Code.
