# Task 004: Broaden Lambda Contextual Typing

Priority: P0 semantic correctness.

Work in the N# repository and make lambda typing reliable across delegate and expression-tree contexts. Common delegate/lambda calls work, but callback-heavy code and generic delegate flows still lose parameter and return type information.

## Scope

- Audit lambda analysis for reflection-backed calls, N# functions, extension methods, generic methods, expression trees, events, task continuations, and LINQ.
- Propagate expected delegate or expression-tree types into lambda parameter and return analysis.
- Preserve semantic type information for nested lambdas and callback positions.
- Ensure diagnostics are useful when a lambda cannot match the expected delegate.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `tests/AnalyzerTests.cs`
- `tests/ILCompilerTests.cs`
- `tests/QueryIntegrationTests.cs`

## Acceptance

- Lambda parameters and return types are inferred from delegate, expression tree, extension method, and generic method contexts.
- Nested lambdas and method-group-like callback positions do not lose semantic type information.
- LINQ, event handlers, task continuations, and BCL callback APIs have regression coverage.
- Lambda mismatch diagnostics identify the bad parameter or return expression.

## Verification

- Run focused analyzer and IL compiler lambda tests while developing.
- Run query/LSP tests if SemanticModel-visible lambda types change.
- Run `./scripts/test-all.sh` before committing.
