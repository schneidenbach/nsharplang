# Compiler reference type-resolution ownership

Selected from clean/pushed `07562c26e`: move complete `ResolveTestFrameworkType`,
`TryResolveReferencedType`, `TryResolveLoadedExternalType`, `TryResolveAspNetReferencedType`, and
`TryResolveAspNetHttpContextType`, including necessary helpers/state. All production callers route
directly to N# and all five old C# definitions disappear. No C# decision callback, helper, adapter,
canonical assertion or legacy fallback owner is added.

Preserve the resolution tiers and their distinct semantics. Test-framework lookup scans the filtered
`ExternalAssemblyScan.Loaded` snapshot, eligible resolved reference paths, then known assembly names,
with the original terminal exception. Referenced-type lookup filters exact simple names and catches
only the original load/type-lookup scope. Loaded-external lookup scans unfiltered AppDomain assemblies
and applies its supported-type check. ASP.NET/context callers retain their ordered composition.
Keep case comparisons, path/read order, out slots, exception boundaries and meaningful failures.
IReadOnlyList reference paths retain foreach enumerator/disposal behavior; Count/index substitution
would change observable behavior for caller-provided lists. Array snapshots retain original ordering.

Sol Max owns production and native canonical migration; Terra Max inventories assertions and direct
N# controls; Astra reviews/integrates/ratchets/gates/pushes. Reuse valid native/reference fixtures and
compile complete proposed N# source to prove prerequisites. Seed changes only for demonstrated
compiler dependencies, with required fresh verification before publication. Broader CLI/editor,
runtime and NativeAOT initiatives remain in `tasks/BRANCH-BACKLOG.md`.

Evidence root `/private/tmp/nsharp-compiler-reference-ownership-20260906` pins the clean baseline,
verified immutable compiler payloads, original emitter and ratchet. Prior fresh accepted gate: 446s,
590 unit / 7,868 canonical / 52 native projects / 12 throughput / 68 IL assemblies. The selected
area and compiler-wide objective remain open until direct ownership, canonical assertions, checks
and push are complete.
