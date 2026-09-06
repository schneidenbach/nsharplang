# Complete compiler reference coercion and boxing ownership

Selected from clean/pushed `3012dd10e`: move the complete source/external interface and object
conversion eligibility/emission methods plus reference-test boxing from ColumnarIlEmitter into N#.
The seven methods are CanUseInterfaceUpcast, TryEmitInterfaceUpcast, CanUseExternalInterfaceUpcast,
TryEmitExternalInterfaceUpcast, CanUseObjectConversion, TryEmitObjectConversion and
RequiresBoxBeforeReferenceTest. Remove the mechanical FindDefByBuilder forwarding method and
route all its remaining callers directly to the existing N# source-definition resolver.

This connected area decides reference coercion and emits required boxing at value-flow and is/as
boundaries. Pass original IReadOnlyDictionary<string,ColumnarStructDef> and ILGenerator directly;
preserve lazy Values acquisition at each lookup, repeated eligibility and external enumeration,
TypeBuilder-only source rules, inherited external assignability, unknown-builder pass-through,
source enum/value/generic boxing and the reference-constrained generic exception. Preserve the
NotSupportedException-only catch and all other reflection failures. No new C# behavior, helpers,
tests, callbacks or fallback owner. Every migrated production route calls N# directly.

Astra reviews/integrates; Sol Max implements complete methods and dependencies; Terra Max
inventories canonical assertions, migrates complete relevant C# tests and adds N# controls for real
gaps. Existing native evidence is reused. Actual full proposed N# source must demonstrate any
capability prerequisite; accepted SDK SHA
`9deb7b3f33b01cf7811449cc6bd8f4d12d6a1c9c91a1fb459b741fd3a4000ddd` remains the seed unless
a demonstrated need requires a verified update. Focused dev/native while implementing, fresh
backend gate at integration, coherent commits and push. Numeric/operator/anonymous-union
conversion remains separate unless it is an actual dependency. Broader branch backlog stays in
tasks/BRANCH-BACKLOG.md.

Evidence `/private/tmp/nsharp-reference-coercion-ownership-20260906` pins original emitter, ratchet
and accepted compiler payload. Previous gate: 448s, 587 unit / 7,884 canonical / 52 native projects /
12 throughput / 68 IL assemblies. This selected area and the compiler-wide objective remain open
until sole ownership, canonical coverage, required checks and push are verified.
