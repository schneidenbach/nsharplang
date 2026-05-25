# Prompt: Nullability Initiative

Last updated: 2026-05-25

Copy this into a fresh agent/dev session.

```text
You are working in the N# repository. Your goal is to implement the nullability initiative as a coherent language/tooling feature, not as isolated lints.

Read `tasks/CURRENT.md` first. Focus on these current issues:
- 15. Add explicit null-state and flow-fact data structures
- 16. Complete nullable flow narrowing
- 17. Add possible-null diagnostics
- 18. Implement `must` explicit unwrap/assertion
- 19. Add nullable value idiom diagnostics and fixes
- 20. Add nullable `match` exhaustiveness and narrowing
- 21. Import and emit C# nullable metadata
- 22. Surface nullability through query, fixes, and LSP

Expected approach:
1. Start by designing the analyzer/SemanticModel null-state model. Do not begin with syntax or lints until the semantic facts have a home.
2. Implement flow facts for variables and stable member paths, including direct guards, early returns, assignment invalidation, boolean chains, `is` patterns, `match`, loops, and nested scopes.
3. Add possible-null diagnostics with Elm-style suggestions and stable JSON/LSP representation.
4. Implement `must` across lexer/parser/AST/analyzer/formatter/C# export/IL backend only after the core flow model can prove when it is needed or redundant.
5. Add semantic nullable-value diagnostics/fixes for `.HasValue` and `.Value`.
6. Decode and emit C# nullable metadata at interop boundaries.
7. Expose nullable and null-state information through query commands and VS Code code actions.

Acceptance:
- Analyzer can distinguish `Unknown`, `Null`, `MaybeNull`, `NotNull`, and `Oblivious`.
- `T?` to `T` requires proof, coalesce, throw, or explicit assertion.
- `must expr` lowers to explicit throw behavior and is diagnosed when redundant.
- Nullable `match` narrows correctly and reports missing null coverage.
- C# nullable metadata maps accurately into N# and generated public C# preserves N# nullability.
- Query JSON, fixes, and LSP diagnostics/actions expose the feature coherently.

Verification:
- Add extensive analyzer, parser, formatter, transpiler, IL compiler, interop, query JSON, fix, and LSP tests.
- Run focused tests continuously; this feature touches many subsystems.
- Run `./scripts/test-all.sh` before committing.
- Because this affects IDE diagnostics/actions, run `./scripts/reload-vscode-extension.sh` and visually verify representative nullability diagnostics and code actions in VS Code.
```
