# Complete compiler constructor declaration, validation and chain ownership

Selected from clean/pushed `656f7c7ea853b1a8cff544baf8e747e33f0aafed`. The previous goal turn
made verified progress by accepting the complete closure ownership area. The compiler-wide goal
remains active; broader CLI/LSP/editor/runtime/NativeAOT initiatives stay separate.

Move the whole constructor declaration phase (Pass 0c/0d): user constructor signatures/defaults/
parameter metadata, synthesized initializer classification, original field-initializer state,
mutable helper declaration, reference default-constructor eligibility/depth ordering and all three
deferred job queues. This phase has a real production boundary before any body emission begins;
its decisions and state must be solely N#-owned, with C# consumers reading the resulting jobs.

Move the connected complete helper group too: ResolveParameterlessCtor,
IsZeroParamSynthesizedInitializer, HasCallableConstructor, EmitCtorBaseChain,
ResolveExactBaseConstructor, EmitInstanceInitializerCall, IsValidReferenceCtorBody and
EmitChainedConstructorCall. Route every remaining caller directly. Preserve original declaration,
lookup, validation, mutation, diagnostic and IL evaluation/failure order, including partial emission.
The chained-call dependency also moves the complete EmitLoadArgument/EmitStoreArgument/
EmitLoadArgumentAddress group and routes all remaining callers; do not duplicate their opcode
decisions in N# while retaining the C# definitions. Move necessary helpers with these callers;
add no C# compiler behavior, tests, helper, adapter,
decision callback or fallback. Existing N# field-init/default/type/coercion owners stay authoritative.

General recursive body emission and Pass 2 body orchestration remain explicit compiler debt.
This selected phase/validation/chain boundary does not claim full constructor-body realization.
Do not introduce callbacks into the body emitter or describe its remaining decisions as mechanical.

Astra reviews/integrates; Sol Max implements production; Terra Max migrates five exact canonical
programs and their compile/exit/stdout assertions: readonly class fields, explicit instance field
initializers, double field initializer, struct primary constructor and record primary constructor.
Reuse the accepted 18 native readonly-init controls and constructor-chain coercion coverage.
Add direct N# controls only for actual gaps once the production API is concrete.

Compile the actual complete proposed N# owner to establish prerequisites. Accepted SDK seed
`66215414a61939140ef0fd429c54d23f53380415eed893104d812ba21fd30872` stays pinned unless source
proves a necessary coherent N# prerequisite. Any seed publication requires the prescribed fresh
gate and ordinary installed-package verification. Use focused dev/tests during implementation,
commit coherent green pieces, then complete the selected area through fresh backend gate and push.

Evidence: `/private/tmp/nsharp-constructor-declaration-ownership-20260906`. Baseline source and ten
CLI payloads are preserved and verified against previous acceptance. Prior accepted gate: 449s,
583 unit / 7,897 canonical / 52 native projects / 12 throughput / 68 IL assemblies. Do not restart
accepted migrations or use a prerequisite/tiny helper extraction as the selected area's endpoint.

Canonical migration integrates as `f774570b3` (worker `bd6c213678cdf331cd5f51df902602c2aaae03f1`):
five exact Program.nl byte sequences and all fifteen assertions independently verified, including
the record program's original Contains check. Focused native 5/5, remaining C# backend 67/67,
and ownership audit 18/18 pass. C# test estate shrinks 251 lines / 218 nonblank / twenty markers
to 3,494 / 3,003 / 343. Only its ratchet row changes so far, original epochs unchanged;
intermediate head `head-v1:d8b0c5c706add810`. Production ownership remains open.

Full-source probing has restored all original operations and isolated argument emission admission:
Ldarg_S/Starg_S/Ldarga_S/Starg and the exact ILGenerator.Emit(OpCode, byte) overload. Other source
spelling issues use equivalent CLR operations (explicit optional defaults and identity upcasts);
no discovery substitute belongs in the final owner. Preserve exact-source r10 and earlier probes.

Dependency review requires the complete ColumnarDeclineTrace class and its two ThreadStatic fields
to move to N# too: old declaration decline tracing executes before constructor-enumerator disposal,
which a result-to-C# diagnostic handoff reverses if disposal throws. Record inside N# before
return/finally and remove the C# trace owner; add no callback or ThreadLocal replacement. Preserve
empty Array.Empty identity, independent snapshots, source-id capture and thread isolation. Compile
the actual proposed N# trace source to prove any further prerequisite before grouping a seed update.

The validator's node-text dependency must also have one N# owner: consolidate its synthetic-equals
rule with the existing catch-text rule, remove C# Text and route all original callers directly.
Do not leave a duplicated C# decision while claiming the connected helper is migrated.

Exact trace source now proves two further prerequisites. The r3 full-source compile rejects
`System.Array.Empty<ColumnarDeclineReason>()` with `emit.call.generic-unresolved`. The r4 discovery
build substitutes only that call and the already-proven argument operations; inspecting its emitted
fields proves both lack ThreadStatic metadata despite accepting the source attribute. Preserve
`trace-probe/decline-trace-exact-r4.nl`, both compile logs and `decline-trace-r4-metadata.log`.
Discovery builds are not acceptance evidence. Resolve attribute transport/emission under N#
ownership and retain runtime thread-isolation and trace-before-throwing-disposal controls.
