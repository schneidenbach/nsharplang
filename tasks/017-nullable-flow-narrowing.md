# Task 017: Complete Nullable Flow Narrowing

Priority: P1 nullability.

Work in the N# repository and make nullable flow narrowing sound enough for normal code. Direct null-check branch narrowing exists, but early returns, assignment invalidation, member paths, boolean chains, patterns, matches, loops, and nested scopes still need work.

## Scope

- Build on the explicit null-state and flow-fact model.
- Support early-return narrowing, assignment invalidation, stable member paths, `&&`, `||`, `is` patterns, `match`, loops, and nested scopes.
- Preserve only sound facts across branches and loops.
- Keep diagnostics clear when facts are not strong enough to prove non-null.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `tests/AnalyzerTests.cs`
- `tests/AnalyzerSemanticModelTests.cs`

## Acceptance

- `if x == null { return } x.Member` is accepted.
- Assigning to `x` invalidates prior facts.
- `&&`, `||`, `is` patterns, `match`, loops, and nested scopes preserve only sound facts.
- Stable member paths such as `user.Address != null` can narrow inside the guarded region.
- Tests cover both accepted and rejected narrowing cases.

## Verification

- Run focused analyzer and SemanticModel tests while developing.
- Run `./scripts/test-all.sh` before committing.
