GOAL: remove legacy ownership from the N# compiler and N# tooling.

Definition of done:
- Compiler parser, binder, analyzer, semantic model, diagnostics, IL lowering, codegen, and CLI/tooling command logic are implemented in N#.
- No product path depends on legacy compiler-core fallback, legacy emitter behavior, Roslyn-as-backend, or `*DogfoodAdapter` indirection.
- Remaining legacy code is deletion debt unless it is a hard external host boundary that does not own compiler/tooling behavior.

Operating rule:
- Do not add legacy compiler/tooling logic.
- Do not do CLI text/message/help/option churn unless it deletes compiler/tooling ownership.
- Do not preserve parity-only work, docs-only progress, adapter movement, or fallback/legacy emitter behavior as architecture.
- Prefer slices that delete an old owner after an N# replacement is in the product path.

Authoritative sources:
1. Current code.
2. Recent git history.
3. Tests that prove product behavior.
4. Documentation only when it matches the code and commit evidence.

Docs that described the old route-with-fallback dogfood plan were deleted because they trained agents to keep
legacy fallback/legacy emitter paths alive. Do not recreate them.
