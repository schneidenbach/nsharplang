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
