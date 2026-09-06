# Generic-constraint application ownership

The selected compiler area replaces the complete C# `TryApplyGenericParameterConstraints`,
`TryApplyDeclaredTypeConstraints`, `BuildGenericInterfaceConstraintMap` and necessary
`IsSafeSzArrayType` dependency. `ColumnarGenericConstraintPlanner.nl` owns the first three;
`ColumnarTypeEquivalenceFacts.nl` owns the narrow array predicate. Production routes directly to
these existing N# owners. The integrated focused checks pass; the fresh final product gate is required before push.

The boundary includes attribute application, canonical constraint resolution, base/interface
classification, owner-parameter matching, metadata writes, circularity refusal, declared-name builder
lifting and the constrained-call map producer. Preserve partial out columns and metadata mutations,
reflection failure phases, interface ordering, delayed map allocation and the caller's exact shared
empty map. C# retains mechanical calls supplying existing inputs and the pre-existing shared empty
map; no new callback, adapter, fallback, helper or decision is introduced. The surrounding emitter
still owns other compiler decisions and remains deletion debt.

Existing native declarations cover constrained classes, structs, records, interfaces, unions with
nested cases and constrained interface dispatch. Reuse them without rewriting their assertions.
New canonical N# controls cover missing failure/identity/ordering gaps in the direct owner. The
cycle fixture must register its actual generic owner with the structural table, as production does;
the initial unregistered fixture failure was not evidence of a short-circuit compiler defect.

## Necessary SDK seed

Actual proposed source showed that `GenericTypeParameterBuilder.SetInterfaceConstraints(Type[])`
needed an N# external-binding admission. Attribute and base setters already compiled with local
receivers. Only that exact setter signature was added in `eb750c4fa`, with canonical signature tests
and a native control that calls it directly, bakes the owner and checks interface identities/order.
The declared-map cast uses an object-typed reference local before `castclass`, preserving invalid-cast
and null behavior. No C# prerequisite was added.

Fresh prerequisite gate `/private/tmp/gate-20260906-constraint-seed-r1` passed at `eb750c4fa`:
593 unit tests, 7,822 canonical tests, 52 native projects and 68 IL assemblies. Setup completed with
`--skip-vscode --no-path-update`; both actual local feeds were synchronized and the measured stale
SDK cache was preserved then refreshed. Normal SDK resolution compiled and executed the packaged
probe: 9/9 tests, zero skips. All 12 package/cache SDK/tool payloads match; all 10 packaged tool
payloads match the Release build. SDK package SHA-256:
`3fb4fd53a4c19cd2a8fc6faa4c7dd6b7b09a3b0cd97c43f9c627f78900cd8e96`.
Receipt: `/private/tmp/nsharp-constraint-ownership-20260906/seed-acceptance.json`.
Legacy SDK validation remains compiler migration debt; the packaged probe confirms it was enabled.

## Integration evidence

Fresh main-checkout `./scripts/dev.sh --build-only` passed. The actual integrated canonical assembly
was freshly emitted by the installed SDK and passed 56/56 `Constraint|SafeSzArray` tests, zero skips.
The unchanged native declaration suite passed 115/115 with identical test names/outcomes to the
immutable baseline. Eleven new canonical blocks cover application, declared lifting, map and the
safe-array failure boundary; existing assertions remain N#-owned.

The C# diff is +16/-123, entirely direct call changes and four deleted method definitions:
18,883 → 18,776 lines, 17,947 → 17,844 nonblank, 983,112 → 978,084 bytes. The audit moved from
17/18 to 18/18 after lowering only the observed emitter row; the other 380 rows and all epoch ceilings
are unchanged. Emitter fingerprint `text-v1:7fe90f9be0cf06f0`, reviewed head
`head-v1:3afdea3c46557608`. No AddType site changed.

Source and emitted-IL review confirm ordered output allocation, the nonparameter observation guard,
base write before output update, interface output before setter, cycle detection after all writes,
exact castclass and the safe-array catch boundary. Review receipts are `ownership-final-review.json`
and `integrated-focused-review.json` under the evidence directory. Root formatting added whitespace
only after the worker snapshot. The fresh final backend gate remains pending before push.
The accepted baseline is preserved in `/private/tmp/nsharp-constraint-ownership-20260906`:
`baseline-compiler.json` pins immutable compiler payloads, and `native-baseline.json` records the
unchanged declaration suite at 115/115. Broader CLI/editor/SDK branch work is separate in
`tasks/BRANCH-BACKLOG.md` and is not part of this checkpoint.
