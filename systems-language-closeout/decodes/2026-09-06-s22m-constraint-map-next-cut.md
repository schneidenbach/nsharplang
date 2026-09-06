# S2.2(m): constrained-call map production

**Superseded execution scope:** the compiler-only contract selected the complete generic-constraint
application/declaration/map ownership area with its safe-array dependency. See
[the current ownership record](2026-09-06-generic-constraint-ownership.md). The map semantics below
remain review evidence; the map-only stopping point and mandatory repeated corpus work are historical.
Use the active task contract and risk-appropriate verification.

This source-reviewed cut follows accepted S2.2(l); it is not an implementation or capability verdict. Tasks 015/021/022/023 remain open. Revalidate the current source and the verified l1 SDK before editing.

Move the complete `BuildGenericInterfaceConstraintMap` producer into the existing N# `ColumnarGenericConstraintPlanner`, where `ResolveCallConstraints` already consumes its exact/weak/reflection lookup policy. At product `070ad0a49a08715fb9274c71a77f260f6aae1c6d`, the C# method occupies `ColumnarIlEmitter.cs:16710–16725`, plus its trailing blank (17 lines /705 bytes, SHA `b72fa01143629626154c2766b7d5b6da2aa336c19e467c53cc47b5ad6c5af46e`); the sole production call is at 3891–3893. Re-measure exact bytes and net shrink after routing. Delete the C# policy helper and call the N# producer directly. No decision callback or fallback remains for map production.

Pass the caller's exact `s_noGenericInterfaceConstraints` instance to the N# producer as a third argument. Preserve:

- Argument evaluation and left-to-right short circuit: an empty type-parameter array bypasses a null constraint array; a nonempty one reaches its Length read.
- Math.Min truncation to the shorter outer array and original per-row reads in their order.
- Empty constraint rows skip even a null key; a reached null row throws at Length before dictionary creation.
- Lazy allocation of a Dictionary using its existing default Type comparer, original constraint-array identity, and later duplicate-key overwrite.
- The exact caller-supplied shared empty map for an initially empty dimension or an all-empty scan.

Use the exact `Type[]`, `Type[][]`, `IReadOnlyDictionary<Type, Type[]>` and Dictionary types. Existing `ColumnarCodePlan` already uses Type[][] fields and a direct grow helper, but this producer's complete declaration/body must compile against the accepted seed before the C# move. Preserve actual source, argv, exit and output if any capability boundary appears; do not substitute a collection shape or add C# to bypass it.

Add canonical controls for the short-circuit/null matrix, shorter-array truncation, empty rows, default comparer, duplicate overwrite and shared output/row identity. Exercise the consumed map through existing `ResolveCallConstraints` exact/weak routes and retain native generic constraint/interface call behavior. Match old exception and partial-progress boundaries. All new behavior and tests are N#.

Rederive the emitter metrics and the existing AddType census (currently 36 sites /12 files /22 keyed /14 handle-only; this producer does not add a plan type row). Compare the accepted fixed 94-image corpus and native execution, map same-source strict diagnostics, lower only the observed C# ownership row and both head keys, commit focused-green source, and run the fresh gate required by actual scope. Pure emission ownership normally uses the backend gate and retains the verified SDK; only a measured new prerequisite justifies republishing.

Constrained interface selection and emission remain separate debt. The old tail receives an already-emitted receiver, declares/spills/addresses it before argument emission, and retains partial IL/local changes on argument failure. Whole-plan rollback is not an equivalent replacement. The selector also calls C# argument-admission logic, so an immutable descriptor alone does not prove sole N# ownership. The missing `OpCodes.Constrained` field/plan support is relevant only when that emission tail is taken; no such prerequisite is required for this map producer. The three DirectCallPlanner conversion rows are unrelated to this routed producer and stay open, along with remaining call/local/maxstack, S2.3–S2.6, NativeAOT and final audit. The adjacent CreateType/save block belongs to later writer work.
