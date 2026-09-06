# Sibling-call constraint validation ownership

Selected boundary: complete `TryValidateGenericSiblingConstraints`,
`HasPublicParameterlessConstructorForConstraint`, `BoundSatisfiesBaseConstraint`,
`BoundSatisfiesInterfaceConstraint`, `TrySubstituteGenericTypeArguments`,
`InterfaceEqualsOrExtends` and `AnyInterfaceEqualsOrExtends`. Their replacement belongs to the
existing N# `ColumnarGenericConstraintPlanner`; all production callers must route directly and the
seven C# decision methods must disappear. The existing definition-lookup forwarding wrapper is
mechanical; new N# code calls its existing N# owner while retaining lazy registry.Values access.

The pending source preserves positional constraint columns, class/struct/new requirements, source
constructor/interface state, first-hit identity, recursive array/byref/generic substitution, raw
reflection failures and enumeration disposal. Canonical controls are N#; no C# behavior, tests,
helpers, decision callback or fallback is added. Existing native declarations/dispatch remain the
baseline, with no new native project. This area is not yet accepted: seed verification and complete
owner integration are still required.

## Proven prerequisite

The actual full proposed source declined on `List<ColumnarStructDef>.Enumerator` local storage.
Preserved source and log: `/private/tmp/nsharp-sibling-constraint-ownership-20260906/r5-source/`
and `actual-source-build-r5-enumerators.log`. A separate actual `List<Type>.Enumerator` source
compiled against the accepted SDK and emitted unboxed/addressed calls with finally, so no general
enumerator or method-call prerequisite is justified. Source `for` had compiled but its IL omitted
protected disposal on early return; the replacement therefore uses explicit enumerators and
try/finally. General loop lowering remains compiler debt, recorded in STATUS.md.

Prerequisite `7f929aeb2` (worker `0376bde3`) extends only the builder-bound arm of the existing N#
type admission. It accepts the exact genuine closed BCL nested List enumerator and reuses existing
list-element admission. Canonical controls reject the foreign same-name definition, open shapes,
rank-two element arrays and inadmissible source-generic elements. The candidate CLI passed all
118 native declaration tests, including three controls for early return, bounded repeated advances
and mutation invalidation. Two canonical tests pass; formatting/source review is clean. Native IL
shows concrete value locals, addressed MoveNext/Current/Dispose and finally, with no boxing.
Receipt: `/private/tmp/nsharp-sibling-constraint-ownership-20260906/seed/prerequisite-review.json`.
Fresh seed gate and packaged SDK acceptance remain pending.

## Evidence and remaining work

Baseline is clean/pushed `087d6d9e1`, with the prior verified compiler immutable under
`/private/tmp/nsharp-sibling-constraint-ownership-20260906/baseline-cli`. `baseline.json` pins its
payloads and prior green gate. `original-seven-methods.il` preserves the actual former C# methods.
The source draft is preserved in isolated `codex/sibling-constraint-owner`; canonical controls are
staged there while prerequisite source is isolated in `codex/sibling-enumerator-seed`.
The broader compiler-only objective remains open. CLI/editor/runtime/AOT initiatives remain separate
in `tasks/BRANCH-BACKLOG.md`.
