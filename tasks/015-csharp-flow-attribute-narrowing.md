# Task 015: C# Flow Attribute Narrowing

Priority: P2.

Teach N# flow analysis to consume C# conditional nullability attributes after metadata import. Task 008 surfaces `NotNullWhen` in reflected signatures, but the analyzer should also use those attributes to narrow variables after calls such as `TryGet([NotNullWhen(true)] out value)`.

## User Outcome

When N# calls idiomatic C# `Try*` APIs, the compiler should understand the post-condition and let developers use the out value safely inside the guarded branch without redundant checks.

## Scope

- Preserve imported parameter flow attributes in semantic call binding.
- Narrow `out` and `ref` variables for `NotNullWhen(true)`, `NotNullWhen(false)`, `MaybeNullWhen`, and `NotNullIfNotNull` where applicable.
- Apply the facts through `if`, `&&`, `||`, early return, and negated conditions.
- Surface the inferred post-call null state through `nlc query type` and LSP hover.
- Add diagnostics/code actions that point to the C# contract when a call result is ignored.

## Acceptance

- `if TryGet(out value) { value.Length }` treats `value` as non-null when the C# parameter has `[NotNullWhen(true)]`.
- The inverse branch works for `[NotNullWhen(false)]`.
- Facts are invalidated on reassignment.
- Query and hover agree with analyzer null-state facts.

## Verification

- Add analyzer, query, and language-server tests with a C# fixture assembly.
- Run focused tests while developing.
- Run `./scripts/test-all.sh` before committing.
