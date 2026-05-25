# Task 015: Query And Package Completion Parity

Priority: P1.

Bring the non-VS Code completion surfaces up to the same writing quality as the LSP auto-import flow, and make package-reference types discoverable by completion.

## User Outcome

An LLM using `nlc query completions` and a developer using VS Code should see the same semantic writing affordances: local symbols first, importable project/package/framework symbols when useful, clear duplicate-name disambiguation, and machine-readable import edits.

## Scope

- Add ranking metadata and import-edit metadata to `nlc query completions` without breaking the existing JSON contract; use a new schema/versioned field if needed.
- Share the project-symbol and external-type candidate logic between LSP completion and CLI query completion instead of maintaining separate behavior.
- Load completion candidates from project/package references declared in `project.yml`, not only framework assemblies already loaded by the LSP `TypeResolver`.
- Preserve duplicate-name UX: same simple names from different namespaces must remain distinguishable, while exact duplicate metadata candidates are collapsed.
- Add parity tests that compare representative LSP and `nlc query completions` results for local, project importable, framework importable, and package-reference symbols.

## Likely Files

- `src/NSharpLang.Compiler/CodeIntelligence/CompletionEngine.cs`
- `src/NSharpLang.Compiler/CodeIntelligence/CodeIntelligenceService.cs`
- `src/NSharpLang.LanguageServer/Handlers/CompletionHandler.cs`
- `src/NSharpLang.LanguageServer/Services/TypeResolver.cs`
- `tests/CodeIntelligenceTests.cs`
- `tests/QueryIntegrationTests.cs`
- `tests/LanguageServerAutoImportTests.cs`

## Acceptance

- `nlc query completions` exposes stable ranking/import-edit data for identifier completions.
- VS Code/LSP and CLI query completion agree on project symbols and common external symbols for the same project snapshot.
- Completion includes relevant package-reference types after project restore/reference loading.
- Duplicate simple names are disambiguated without emitting noisy exact duplicates.
- Tests cover schema compatibility, package-reference discovery, duplicate names, and already-imported/no-import-needed cases.

## Verification

- Run focused code-intelligence, query, and language-server completion tests while developing.
- Run `./scripts/test-all.sh` before committing.
- For LSP changes, run `./scripts/reload-vscode-extension.sh` and visually verify completion in VS Code.
