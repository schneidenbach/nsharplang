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

## Catch-all prerequisite review

Complete-source r6 compiled with the accepted SDK, including generic reference enumeration. IL review
found that old C# bare catches use System.Object while the initial N# owner emitted System.Exception.
Explicit object-catch r7 was compiled and declined. Typed object catches also violate the analyzer's
Exception-derived rule, so the prerequisite preserves that rule and moves complete bare-versus-typed
catch-type selection into N#. The C# emitter now calls the N# selector mechanically. Bare catch uses
System.Object; typed catch retains its original exception allowlist and false/null contract.

Integrated `2aca8ca55` (worker `836ba083`): fresh focused canonical selector 1/1, standalone native
metadata/execution 1/1, root dev build green, ownership audit 18/18. The native N# assertion reads
ExceptionHandlingClause.CatchType and distinguishes Object, Exception, and ArgumentException. An
optional raw-object dynamic throw fixture hit an emission refusal and was preserved as evidence,
without adding test-only compiler capability. Exact handler metadata and ordinary execution pass.

Only the emitter ratchet row decreases: 18001/17113 to 17993/17105 lines/nonblank,
`text-v1:8e0fe647c6e1b72a`, reviewed head `head-v1:0b91501506ad7b37`. All 380 other rows and
epoch values are unchanged. Fresh seed gate and normal packaged verification are pending.

Seed accepted after fresh gate `eb445771f`: 445s, 590 unit / 7,869 canonical / 52 native
projects / 12 throughput / 68 IL assemblies. The exact new native source fails against the pinned
baseline compiler and passes against the candidate. Official setup and normal installed-SDK probe
pass 2/2, with Object/Exception/ArgumentException handler metadata independently verified. SDK SHA
`a817ac58eb2b51c692ab6624e7dc9194088e449b8df55dd010a774891e82fbe8`; all 10 Release tool
payloads and 12 SDK/cache payloads match, and both local feeds carry the identical package. The
probe's initial missing global.json version mapping was corrected and restore/build/test rerun;
the failed fixture attempt is retained. Acceptance: evidence root `seed/acceptance.json`.

The seed completes only this demonstrated prerequisite. The full resolver ownership area continues.

## Complete resolver integration review

Integrated owner `c938be178` and canonical controls `f3fabaacf` (worker `ff3e4793` and `fa9257cc1`).
All five old C# methods disappear. Fourteen sites route directly to N#: two framework, five referenced,
five ASP.NET reference, and two HttpContext calls. Surviving C# integration only passes the existing
reference-path list, names and out Type slot; lookup decisions, enumeration, helpers and ordered tiers
are solely N#-owned. No new C# behavior, tests, helpers, adapters or callbacks were added.

The four canonical N# controls pass after fresh emission with the accepted seed. They cover filename
filtering/out reset/failure continuation; unfiltered dynamic assembly lookup; loaded framework lookup
and exact terminal error including dynamic exclusion; and ASP.NET reference/context tiers and alias.
No live C# canonical assertion belongs to the five former private heads. Existing native coverage is
reused with pinned source hashes: xUnit example 6/6, minimal ASP.NET example builds, native declaration
coverage 121/121; analyzer-only web rows are explicitly not counted as resolver evidence.

Independent final emitted-class review matches the original reviewed candidate after RVA normalization
and exactly three Exception-to-Object catch changes. Enumerator acquisition remains before try; generic
Current and nongeneric MoveNext remain outside narrow load catches; early returns use leave/finally
and null-guarded IDisposable disposal. Filtered versus unfiltered snapshots, reference/name order,
supported-type checks outside catch and exact short-circuit tiers remain intact. Evidence root:
`root-final-owner.il`, `root-owner-review.json`, `final-owner/`, `native-coverage-reuse.json`.

Cumulative emitter decrease including the prerequisite: 18,001→17,860 lines, 17,113→16,982 nonblank;
resolver alone removes a net 133 lines. Fingerprint `text-v1:c43a4c9e9edd7632`; reviewed head
`head-v1:d8969a2f61263284`. All 380 other rows and epoch ceilings are unchanged.
Final fresh integrated product gate remains pending; the compiler-wide objective remains active.

Root integrated dev build and ownership audit 18/18 pass; compiler payloads pinned in `integrated-compiler.json`.

## Acceptance

Final fresh backend gate at `8ec4b0781dfbf286779b2b03dfb4fe34006ca6e5` passes in 452s:
590 unit / 7,873 canonical / 52 native projects / 12 throughput / 68 IL assemblies, with SDK,
templates and examples green. The installed prerequisite seed remains unchanged in both feeds and
all 12 cache payloads after the isolated gate. Receipts: `gate-receipt.json` and
`post-gate-seed-check.json` under the evidence root.

This completes the selected compiler reference-resolution area. The compiler-only goal remains
active; substantial compiler ownership debt remains. Next candidate is complete structural-interface
conformance and registration with its connected return-shape dependency, subject to dependency review.
Broader CLI/editor/runtime/NativeAOT and conditional writer work remains in the separate branch backlog.
