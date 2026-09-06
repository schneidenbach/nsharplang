# Complete compiler closure binding and mutation analysis ownership

Selected from clean/pushed `98a708b6c33f114706b70a8b5ccd2fef27974f56`: move the complete
binding/capture mutation analysis used by closure lowering, with its necessary source-member
lookup dependencies. This is compiler-only work. The broader lambda body/display-class emitter
remains explicit compiler migration debt; this area must not claim that emitter is migrated.

The connected analysis boundary includes structural binding collection, live binding visibility
and snapshots, enclosing-member reference detection, lifted-candidate computation, nested lambda
parameter binding and unbound-name scans, bare/structural/any-write scans, opaque capture-node
classification, and liftable-type/StrongBox metadata helpers. Move necessary helpers and original
state with their callers. Shared field/method/interface-base/static-field/static-property chain
lookups used by the enclosing-member scan must become N#-owned too; route every remaining caller
directly and remove the replaced C# methods. Preserve overload and nearest-declaration ordering,
recursive interface traversal, set comparers, null state, lazy mutation, evaluation and failure order.

Astra plans/reviews/integrates, Sol Max implements the complete production area, Terra Max migrates
canonical programs and reviews/adds focused N# assertions for real gaps. Migrate the complete
Task.Run captured-action and interpolated Select-lambda programs and their original assertions.
Reuse accepted native lambda coverage and add focused scan/mutation regressions after the API is
concrete. No new C# compiler behavior, tests, helper, adapter, decision callback or fallback.

Compile the actual complete proposed N# source before declaring a capability blocker. The accepted
SDK SHA `9deb7b3f33b01cf7811449cc6bd8f4d12d6a1c9c91a1fb459b741fd3a4000ddd` stays pinned unless
proven source requires a coherent N# prerequisite; any publication requires the fresh prescribed
gate and ordinary packaged verification. No C# projections substituting for original live state.

Evidence: `/private/tmp/nsharp-closure-analysis-ownership-20260906`. Previous accepted gate:
449s, 585 unit / 7,888 canonical / 52 native projects / 12 throughput / 68 IL assemblies.
Use focused dev/native tests while implementing; commit coherent green pieces, complete the entire
selected area, then run the fresh backend integration gate and push. CLI/LSP/editor/runtime/NativeAOT
and broader branch initiatives stay in `tasks/BRANCH-BACKLOG.md`.

Canonical programs integrated as `43ce0170a` (worker `80d12c255`): both exact Program.nl byte
sequences and all six assertions independently verified; native focused 2/2, remaining C# backend
72/72. Focused runtime gaps integrated as `451cd42ea`/`3f137b6dc`: shared parent/lambda lifted writes
produce 12; contextual read-only capture produces 1, while the paired member-write capture declines.
The positive counterpart prevents vacuous negative coverage. Final contextual selection 3/3.
C# tests shrink by 118 lines / 99 nonblank / eight markers, to 3,745 / 3,221 / 363; audit 18/18,
ratchet `head-v1:5723ac77c54ad150`, original epochs unchanged. Production ownership remains open.

The exact full-source compile proved four connected collection gaps: HashSet copy/comparer
construction, live Dictionary key-view argument flow, and both SortedSet comparer constructor
forms. Prerequisite `42ef49df7` (worker `79a4e0a7608d4ea790a998e77254e9554aa59d89`) changes only
six existing N# compiler owners plus N# tests. Exact key-result identity and enumerable conversion,
constructor selection and SortedSet type resolution are N#-owned; unrelated shapes remain refused.
Private candidate SDK `67d04fd2c94239c0976a730c7b5077dbe117c413dfaa0e83190c9555be90cfa9`
compiles the hash-identical restored owner with zero warnings/errors. Focused BSS 5/5, private
packaged native 2/2, existing Columnar slice 12/12 pass. Required fresh gate/publication remain open.

StrongBox needed no syntax extension: fixed `typeof(StrongBox<int>).GetGenericTypeDefinition()`
yields the exact open CLR type, and an explicit Type[1] preserves original params-array lowering.
Root emitted-IL review confirms identity, MakeGenericType/GetField failure semantics, original
collection constructors/key-view order, unboxed enumerators/finally and lazy ref-state mutation.
The member arity helper assigns a local out slot before publishing a success, preserving the original
outer slot when a later base lookup throws. All discovery substitutions are removed from owner source.

The first fresh seed gate at `6bb61b9e` completed in 417s with one bootstrap-order failure:
canonical BSS runtime tests used the new HashSet copy constructor before the seed was installed.
No seed was published. Preserve that failure receipt; move all three runtime tests and their
necessary helpers into native emission coverage, keeping the two compiler decision controls in
BSS. Old-seed BSS 2/2 and candidate-packaged native 5/5 pass; every assertion is retained and
unused helpers are removed. The next gate must be fresh and use this corrected test placement.

Corrected seed gate `ccfdaaacf` passes fresh in 452s: 583 unit / 7,890 canonical /
52 native projects / 12 throughput / 68 IL assemblies. Standard setup publishes SDK
`66215414a61939140ef0fd429c54d23f53380415eed893104d812ba21fd30872`; ordinary installed-package probe passes 6/6.
Both feeds, ten packaged Release payloads and twelve SDK cache payloads are verified.
Exact source and emitted-IL review confirm the collection forms, live views and concrete
enumerator disposal. This accepts only the prerequisite; complete closure-owner integration follows.

Complete production owners integrate as `22bc5991b`, direct controls as `59325fb57`.
Twenty-two C# definitions across nineteen names disappear; sixty-six remaining sites route directly
to N#. No C# decision callback or replacement helper is added. The emitter shrinks 17,415→16,983
lines / 16,562→16,149 nonblank. Together with canonical migration, exactly two ratchet rows change;
379 other rows and all epochs are unchanged, head `head-v1:f71fdf545a0d283a`.

Integrated focused evidence: dev Columnar 12/12, seven exact discovered direct controls 7/7,
extension-call programs 17/17, ownership audit 18/18. Both owner classes emit identical reviewed
IL after method-address normalization. Preserve no-test/wrong-entrypoint attempts separately;
only the corrected exact seven-test result is accepted. Final fresh backend integration gate
and push remain open. Remaining recursive lambda body/display-class lowering is C# compiler debt.

The first complete-owner gate at `d9a666316` exposed only a test-source formatting issue:
three ref argument lists used multiline layout. Existing `FormatterWalk.ArgumentsCanBeginLines`
and `FormatterSourceText` require ref-bearing calls on one line; this is resolved by the
layout-only `86d50ad13` (worker `2c2dc004`), without a parser/formatter/production change.
Formatting and fresh accepted-SDK direct controls pass 7/7; the affected test method retains
all 204 emitted instructions, including the original three ldloca ref calls. Preserve the
failed gate receipt and run the final corrected source through a fresh gate.
