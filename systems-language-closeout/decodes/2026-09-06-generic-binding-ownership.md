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
