# Generic-call binding and return-substitution ownership

Selected from clean/pushed `c3f7b5109`: complete `TryUnifyTypeParam`,
`TryUnifyGenericCallArgument`, `TryUnifyGenericContainer`, `TrySubstituteReturnType`,
`IsDictionaryLikeCollectionDefinition`, `IsReadOnlyDictionaryCollectionDefinition` and
`IsAnyDictionaryCollectionDefinition`. These seven C# methods disappear and all production callers
route directly to N#. The collection helpers are included because return substitution consumes them;
their additional indexer, conversion and mutation callers route to the same N# owner.

This is the complete mutable type-binding/return-shape decision group. Its expression/IL emission
callers carry other compiler state and remain separately open ownership work. No callback, adapter,
C# behavior/helper/test or fallback may replace that dependency boundary. General argument-type
substitution is already N#-owned and intentionally has different semantics; do not merge it into
return substitution or silently widen either operation.

Canonical inventory found three remaining C# end-to-end methods in `CompilationBackendTests.cs`:
`MultiFileCompiler_EmitsGenericParamsArrayInference`, `MultiFileCompiler_EmitsExplicitNullableGenericCall`
and `MultiFileCompiler_EmitsGenericExpandedParamsArrayCall`. Their exact source programs and
success/zero-exit/normalized-stdout assertions migrate to N# before pure deletion of the three
C# methods. Adjacent N# argument-substitution controls do not replace these contracts.

Preserve first parameter identity, repeat binding equality, partial binding mutation on later
container failure, direct versus composed source-builder admission, reflection read order, null/out
slots and construction exceptions. Probe actual proposed N# source before declaring a capability
blocker. Canonical N# assertions reuse existing native production coverage and add controls for real
gaps. Sol Max implements; Terra Max supplies controls; Astra reviews/integrates/ratchets/gates/pushes.

Evidence root: `/private/tmp/nsharp-generic-binding-ownership-20260906`. `baseline.json` pins the
previous accepted gate and verified immutable `baseline-cli` payloads; `emitter-before.cs` and
`ratchet-before.json` retain source/ownership baselines. The previous checkpoint passed 593 unit,
7,843 canonical, 52 native projects, 12 throughput cells and 68 IL assemblies in 449s.
The selected area and compiler-wide goal remain open until implementation and verification pass.
Broader CLI/editor/runtime/AOT work remains in `tasks/BRANCH-BACKLOG.md`.

Actual complete routed source compiles under the accepted live SDK: `proposed-r3/build.log`, zero
warnings/errors. Direct indexed `out` source declined at argument four (`proposed-r2/build.log`);
the equivalent local-result/store spelling is accepted for the fresh private arrays. Their slots
start null, bounds follow local lengths, and neither array escapes before final construction, so
failure/exception observability is retained. No seed update is necessary. Fifteen external C# routes
now call N# (two inference, two return substitution and eleven collection classifiers); the seven
C# definitions are removed in the isolated worktree. Canonical/native migration and review remain.

## Integrated verification

Owner `3949eb515` (worker `f1defb9b`) contains the complete seven-method N# replacement and six
canonical controls. Post-format fresh emission passes 6/6 (`direct-controls-post-format-6.log`).
IL review preserves two IsGenericParameter reads, first binding writes before later failure,
ReferenceEquals versus Type.op_Equality, cleared out slots and original return branch/reflection
order. Integrated CLI builds in 22s without warnings/errors.

Assertion migration `14f6c4f3b` (worker `237de832`) removes exactly the three C# methods, byte-verified
as pure deletion. All three source strings remain verbatim (`canonical-source-parity.json`). The
existing native extension-call fixture compiles each executable through production MultiFileCompiler
with original false/true validation defaults, writes its normal runtime config, invokes the N#
DotnetRunner and asserts success, zero exit and exact normalized stdout. The runner invocation uses
mechanical reflection for its four-parameter signature because direct native invocation declined;
its argument values retain the original defaults, including boxed nullable timeout. This is test
integration, not a compiler decision callback. No new native project or SDK seed is added.
Accepted baseline `native-baseline-r7/test.log` and integrated `integrated-native-generic-calls.json`
both pass 7/7. Native declarations pass 118/118 with identical baseline names/outcomes. Audit 18/18.

Emitter 18,621→18,447 lines, 17,699→17,532 nonblank; text `text-v1:07be8c6d939243ba`.
C# tests 4,330→4,178 lines, 3,714→3,584 nonblank, markers 404→392;
text `text-v1:363b1171f6048912`. Only those two ratchet rows change; all 379 other rows and all
epoch ceilings remain unchanged. Reviewed head `head-v1:521fa39bbd79c444`.
Fresh backend product gate is the remaining checkpoint requirement.
