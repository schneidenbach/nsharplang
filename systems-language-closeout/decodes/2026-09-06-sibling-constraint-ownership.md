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
baseline, with no new native project. The prerequisite is accepted and the complete owner is integrated at `244c0998a` (worker
`a0442b4dd`); its fresh checkpoint gate remains required.

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
Fresh seed gate at `dd4d945edb63dbce548ce280bede17d85a08f792` passed in 452s: 593 unit,
7,835 canonical, 52 native projects, 12 throughput cells and 68 IL assemblies, with SDK/template/example
checks green. Gate receipt: `/private/tmp/gate-20260906-sibling-enumerator-seed-r1/gate-result.json`.
Official setup and both-feed publication completed; the measured stale SDK cache was preserved and
refreshed. Normal SDK resolution compiled and ran the exact committed native source plus an integer
control: 4/4 tests, zero skips, legacy validation enabled. All 12 SDK/cache payloads match, and all
10 packaged tool payloads match Release. Package SHA-256:
`5bd1bb159e750db1d7dbcef3f39a8e0ddd3be2d05a9c767a7196dca4a644c9f7`.
Acceptance: `/private/tmp/nsharp-sibling-constraint-ownership-20260906/seed/acceptance.json`.
Post-seed actual owner compilation passed. All eight new canonical N# controls pass, plus the
existing generic-sibling control (9/9); the related constraint/substitution family passes 65/65.
The controls pin lazy column/registry reads, reflection failure phases, source constructor/interface
state, recursive substitution and disposal on early success or traversal failure. An actual CLR
probe established that builder-derived byref SymbolType reports both IsSZArray and IsByRef: the
legacy SZ-first branch produces string[], which is retained; a separate runtime byref control
produces string&. No production change was made to satisfy an incorrect initial expectation.
Receipts: `owner-generic-sibling-tests-r4.log` and `owner-related-constraint-family-r4.log`
under the evidence directory below.

## Evidence and remaining work

Baseline is clean/pushed `087d6d9e1`, with the prior verified compiler immutable under
`/private/tmp/nsharp-sibling-constraint-ownership-20260906/baseline-cli`. `baseline.json` pins its
payloads and prior green gate. `original-seven-methods.il` preserves the actual former C# methods.
The reviewed owner deletes all seven C# methods and has six direct production routes. All three
enumerations have protected finally disposal; both concrete list enumerators retain unboxed,
addressed mutable state. The integrated CLI builds without warnings/errors. Native declarations
pass 118/118 with identical accepted-seed names/outcomes; ownership audit passes 18/18.
Emitter lines shrink 18,776→18,621 and nonblank 17,844→17,699. Only its ratchet row changes;
380 other rows and all epoch ceilings remain unchanged. Text `text-v1:bc34a37b67a4b67c`,
reviewed head `head-v1:48e3b004160cfd2c`. Evidence: `integrated-dev-build.log`,
`integrated-native.json`, `native-parity.json`, `integrated-ownership.json`, `ratchet-review.json`.
The final gate is pending.
The broader compiler-only objective remains open. CLI/editor/runtime/AOT initiatives remain separate
in `tasks/BRANCH-BACKLOG.md`.
