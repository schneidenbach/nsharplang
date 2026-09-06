# Complete compiler interface realization ownership

Selected from clean/pushed `f0a527d69`: move the complete inheritance-depth computation, structural
(duck) interface registration pass, member-completeness validation pass, and ordered interface
finalization pass from ColumnarIlEmitter into N#. Move InterfaceDepthOrMinusOne, both structural
matching methods and ParamTypesMatch, together with their necessary async return-shape and supported
parameter-type dependencies. All callers of the migrated helpers route directly into N#.

This is a connected declaration-realization area: infer and register actual CLR interface metadata,
validate implemented member contracts, and finalize interfaces in their established order. Preserve
source method order, default-method skipping, generic/async signature handling, failed-resolution
versus nonmatching-candidate distinctions, inherited requirement enumeration, closed generic and
external interface checks, duplicate builder suppression, partial mutations and CLR failure behavior.
Depth memoization/cycle handling and depth-then-declaration finalization order remain observable.
Move necessary state with the passes or pass existing records/lists/registries directly; surviving
C# routing must be mechanical, with no new decisions, callbacks, helpers, adapters or fallback owner.

Sol Max implements in the interface-realization-owner worktree; Terra Max inventories and migrates
canonical assertions and adds focused N# controls for real gaps; Astra plans, reviews, integrates,
ratchets, runs required gates and pushes. Compile complete proposed N# to prove prerequisites and
preserve accepted SDK verification rules. Use focused dev/native checks while implementing, then a
fresh backend product gate at integration. Existing native coverage and valid baseline evidence are
reused. Interface upcast value-flow operations remain compiler backlog for a later connected area
unless actual dependencies require them here. Broader branch work remains in tasks/BRANCH-BACKLOG.md.

Evidence root `/private/tmp/nsharp-interface-realization-ownership-20260906` pins the clean baseline,
immutable compiler payloads, original emitter and ratchet. Previous accepted fresh gate: 452s,
590 unit / 7,873 canonical / 52 native projects / 12 throughput / 68 IL assemblies. Current accepted
SDK seed SHA `a817ac58eb2b51c692ab6624e7dc9194088e449b8df55dd010a774891e82fbe8`.
The selected area and compiler-wide objective remain open until sole ownership, canonical coverage,
required verification and push are complete.

Canonical full-program migration integrated as `cc19ab499` (worker `3d3983752`): three complete
C# tests for user-struct interface returns, async executable entrypoints and namespace-qualified
interface/implementer metadata now execute in N#. Original source-file contents and ten assertions
are retained; namespace inspection uses a collectible load context and unloads before cleanup.
Focused evidence: native extension-calls 10/10, remaining CompilationBackendTests 76/76, formatter
clean. C# test row shrinks to 4,014 lines / 3,445 nonblank / 379 markers (three test attributes plus
ten assertion markers removed). All other rows and epochs remain unchanged; ratchet
`head-v1:4b4e382fa477a0d8`, root native ownership audit 18/18.

Complete-source probes prove typed source-reference dictionary/set keys, live Dictionary.Values
views and concrete Dictionary enumerators are necessary. Discovery-only substitutions are not
accepted implementation: final ownership must compile with the original types and live views.
Native prerequisite probes also prove the connected reference-conversion and KeyValuePair
recognition owners must move completely into N# with all C# callers routed directly. The seed
remains unpublished pending exact full-source compilation and required fresh integration checks.
