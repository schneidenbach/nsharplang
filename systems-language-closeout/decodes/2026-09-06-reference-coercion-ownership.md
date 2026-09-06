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

Production integrated as `3b998bf50` (worker `afb7bba5613c2ed033a09497571092ef1696c4c1`):
seven complete methods and the C# lookup forwarder are removed. Sixty-eight coercion calls route
directly to N#; twenty-two remaining wrapper callers route directly to the existing source resolver.
All original lookup arguments were simple locals/pattern bindings, preserving expression order.
Full actual source compiles using the accepted SDK. Enum bitmask syntax required only an explicit
integer view with the original bit-4 mask, not a seed or semantic change. Root candidate clean
rebuilds pass as-boxing 16/16 and external-base-interface 18/18; integrated dev build passes.
Root emitted IL exactly matches the reviewed candidate after RVA normalization, preserving lazy
lookup, repeated external scans, disposal, boxing and the NotSupported-only generic-attribute catch.

Canonical migration `553621fba` plus framing correction `7e247040e` moves the complete constructor
chain and LINQ/object-boxing programs into N#. Both Program.nl contents and all six assertions
match the former C# tests. Native suite 12/12, remaining CompilationBackendTests 74/74; final
source-framing correction focused 2/2. No new C# test/helper was added.

Ratchet: emitter 17,530→17,415 lines / 16,668→16,562 nonblank; C# tests 4,014→3,863 lines /
3,445→3,320 nonblank / 379→371 markers. Current head `head-v1:bec1ef649672705e`; root ownership
audit 18/18. Additional direct N# controls and final fresh backend integration gate remain open.
