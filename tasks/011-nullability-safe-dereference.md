# Task 011: Nullability Safe Dereference Workflow

Priority: P1.

Implement the end-to-end workflow for preventing maybe-null dereferences. This task intentionally combines null-state data structures, flow narrowing, diagnostics, query output, LSP diagnostics, and code actions because users experience it as one feature.

## User Outcome

N# should reject or warn when a maybe-null value is dereferenced, passed to a non-nullable parameter, returned as non-nullable, or assigned to a non-nullable target without proof. Guards, early returns, boolean chains, and stable member-path checks should narrow values correctly.

## Scope

- Add null states: `Unknown`, `Null`, `MaybeNull`, `NotNull`, and `Oblivious`.
- Track flow facts for variables and stable member paths.
- Support narrowing through direct guards, early returns, assignment invalidation, `&&`, `||`, `is` patterns, loops, and nested scopes.
- Report possible-null diagnostics with stable codes and suggestions for `?.`, `??`, a guard, or explicit assertion.
- Expose nullability through `nlc query type` / `inspect` and LSP diagnostics/actions.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/ErrorReporting.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Compiler/CodeFixes`
- `src/NSharpLang.Cli`
- `src/NSharpLang.LanguageServer`
- `tests/AnalyzerTests.cs`
- `tests/AnalyzerSemanticModelTests.cs`
- `tests/QueryIntegrationTests.cs`
- `tests/CodeFixTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- `if x == null { return } x.Member` is accepted, and assignment to `x` invalidates prior facts.
- Maybe-null member/index/call access produces a stable diagnostic with useful suggestions.
- Passing, returning, or assigning `T?` as `T` without proof is rejected or reported according to policy.
- Query JSON, terminal diagnostics, and LSP diagnostics agree.
- VS Code exposes relevant code actions and distinguishes safe edits from review-needed suggestions.

## Verification

- Run focused analyzer, semantic model, query, code fix, CLI, and LSP tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify nullability diagnostics/actions in VS Code.
