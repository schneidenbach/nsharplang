# Complete SystemsAnalyzer ownership

Compiler-only boundary: replace the whole 1,156-line / 1,061-nonblank C# SystemsAnalyzer class at
`a207ee13bcfa0feb90696264d0abca56c561d914`, including all five nested state types. Keep the already
accepted N# Systems* policies. Move state/initialization, declaration registration and semantic site
resolution, visible-file projection, recursive traversal and effect propagation, guard/allow/unsafe/
allocation state, finding transport, and report construction into the sole N# owner. MultiFileCompiler
must consume that type directly; no C# wrapper, decision callback or fallback survives.

Preserve AST reference-keyed caches, DeclarationSite component value equality (including null
containing type), recursive cache/visiting/emitted ordering, fresh-versus-shared report collections,
complete visible-candidate enumeration and conservative ambiguity, expression/statement evaluation
order, exact finding metadata and meaningful failure state. Existing scope push/walk/pop calls do
not use finally; do not silently add cleanup on exceptions. Normalized duplicate source paths must
still fail rather than overwrite entries. Keep existing AOT report fields without expanding into
NativeAOT or runtime reimplementation.

Sol Max owns the complete class replacement in an isolated worktree; Terra Max inventories canonical
assertions and adds N# regressions only for uncovered behavior. Astra owns review, integration,
shared ratchets, gates, any necessary SDK publication and push. Compile the complete proposed source
to prove blockers; implement necessary prerequisites in N#, grouping related capabilities. No new
C# compiler behavior, tests, helpers, adapters or fallback implementations. Use focused dev/native
checks for commits and reserve a fresh integration gate for the completed area/SDK checkpoints.

Evidence: `/private/tmp/nsharp-systems-analyzer-owner-20260907`. Baseline C# SHA256
`7f2a7ef455eba43607499d5bf089d781b499d5186f8ce43ba5e0c1d29ddbf780`. The previous complete Analyzer
migration remains accepted: fresh backend gate 481s, 574 C# / 7,928 canonical / 53 native projects /
12 throughput / 68 IL assemblies, installed self-host 7,928 and Analyzer corpus 1,088. Accepted SDK
SHA256 `d43d021038063adf04322c9964cfec81d50a22593b903a5abf78541d15416430`. Frozen source,
ratchet and production compiler payloads are retained. The compiler-wide objective stays open;
CLI/editor and older SDK branches remain held in the separate branch backlog.
