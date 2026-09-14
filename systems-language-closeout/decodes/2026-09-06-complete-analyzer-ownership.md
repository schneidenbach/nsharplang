# Complete Analyzer ownership

Compiler-only scope: replace the entire `src/NSharpLang.Compiler/Analyzer.cs` class (2,357 lines /
2,223 nonblank at `3d9222aeb`) with its sole N# owner. Move every field and initializer, constructor,
collaborator factory, public entry point, recursive dispatcher/driver and necessary helper together.
The already accepted N# semantic families remain accepted; do not restart their implementations or
leave the C# analyzer shell required as a callback, validation or fallback owner.

The connected behavior includes analysis-lifetime resets and shared collection identities; source
and declaration context setup; import/signature/declaration ordering; all expression, statement and
pattern dispatch; scope/model/binding publication; expected-type and ambient try/finally brackets;
metadata open/load/rebuild/dispose order; and public Analyze overloads, reference-loading and editor
type-catalog access. Preserve the API and behavior while moving its assembly ownership to N#
BootstrapServices. The editor catalog call is existing compiler metadata integration, not an editor
feature initiative. If a real IDE behavior change becomes necessary, retain required IDE verification.

C# that disappears: the complete Analyzer class, all three SoaRecordNullConditionalTests cases and
their now-unneeded C# helpers/class, plus Analyzer_CollectsMultipleSemanticErrors and its sole-use
ParseAndAnalyze helper from ErrorRecoveryPipelineTests. Preserve exact source bytes, parser success,
Single/count/code/message/suggestion assertions, environment restoration and multi-error evidence.
Unrelated CLI/query/MultiFile pipeline tests stay separately scoped. All existing canonical analyzer
fixture assembly/type/member lookups must target the sole new owner without a legacy fallback.

Astra plans/reviews/integrates. Sol Max implements the complete owner; Terra Max migrates canonical
assertions and reviews coverage before adding focused lifecycle/reset/failure regressions. Use
isolated worktrees and preserve in-flight work. Private backing names may change with all internal
references where needed to retain explicit private metadata under the existing formatter; inventory
reflection consumers first. Preserve meaningful initialization and failure order, not merely results.

Compile the actual complete proposed N# source before claiming a capability blocker. Any necessary
prerequisites belong in N#, grouped coherently where feasible, with the required fresh gate and
ordinary installed-package probe before seed publication. No C# compiler behavior, helper, adapter,
decision callback or fallback may be added. Focused dev/native checks precede coherent commits; a
fresh integration gate and push close the complete area. Do not stop at a prerequisite or driver.

Evidence: `/private/tmp/nsharp-analyzer-owner-20260906`. The previous turn was verified progress:
complete constructor ownership accepted and pushed at `3d9222aeb`, fresh gate 450s, 578 unit /
7,918 canonical / 52 native / 12 throughput / 68 IL assemblies. The accepted SDK SHA256 is
`357ad95faf90a34f7ce7be426be4600bd89b48d87f7607aa725e752813877724`; its ordinary probe passed 8/8.
The source baselines and ten verified compiler payloads are preserved. Compiler-wide completion
remains open; CLI/editor features, runtime reimplementation, NativeAOT and broader branch initiatives
remain in `tasks/BRANCH-BACKLOG.md`. No new metadata-writer objective is inferred.

SDK prerequisite reviewed (2026-09-07): `12c0e7f34` / `12e8d7406` project the complete SDK
package/framework/project reference boundary in N#. `LoadProjectReferences` retains only MSBuild
item/metadata transport and exception logging; its selection/version decisions are deleted. The
shared project configuration target now loads references before restore/build graph traversal.
The separate duplicate reference target is removed. C# shrinks 63→47 lines and SDK targets
206→203; only those two ownership rows change, all epochs preserved, audit 18/18. Focused N#
projection tests 3/3 and private-package native integration 1/1 pass, including clean restore/build,
exact Runtime type execution, generated-props compatibility and deduplication. The generic SDK prerequisite is integrated; the older independent SDK backlog remains separate.

Integrated owner (2026-09-07): `ec8814c01` replaces all 2,357 C# lines with the complete 1,896-line
N# Analyzer. The final compatible Runtime dependency is recorded below. `fa79a93b3` routes all thirteen canonical fixture
lookups directly to BootstrapServices. Four canonical C# cases and their original assertions are
already migrated; three focused lifecycle controls cover copy isolation, retained identities and
per-analysis reset. Public API parity includes eight methods and one constructor, with all 87 fields
private, 55 readonly, and all 63 helpers private. No Analyzer wrapper, type forwarder, decision
callback, legacy validation or fallback survives. Existing Compiler/Build.Tasks consumers reference
the N# type directly; SDK item/metadata wrapping remains mechanical transport. The actual Runtime
subscription types remain direct typeof identities. The public type's assembly change is intentional.

The grouped N# prerequisites own method visibility/access (including protected instance receiver
constraints), exact dictionary-copy construction and exception-safe key/value enumeration. The
fresh seed gate at `1dac18cff` passes in 490s: 574 C# / 7,928 N# canonical / 53 native projects /
12 throughput / 68 IL assemblies. Official setup and ordinary installed-package tests pass 6/6.
SDK SHA256 `b591625df7c0261b18e6226512e7b36165518845d86df7c58d201e76f66a3fcc` matches both feeds,
ten release payloads and twelve loaded cache files. Both candidate and installed-owner corpora pass 1,088/1,088, with exact public API/field metadata
parity. Ownership audit passes 18/18. The final fresh integration verdict is recorded below. The Analyzer ratchet
row is retired with all epochs and 380 other rows preserved, head `head-v1:fab5ec0b0db9ca18`.
Compiler-wide ownership remains open.

Final integration corrections: `317beb1af` explicitly binds the two `this.DriveImports` calls, avoiding
collision with the unchanged canonical free helper. Full test-inclusive compilation passes 7,928/7,928;
normalized emitted calls are identical. `ef8502db8` uses the real `NSharpLang.Runtime` 0.1.0 package in
project.yml and removes the SDK's BSS-specific `ExcludeAssets=all` item. This supersedes the initial
.csproj edge, which MSBuild accepted but the native CLI correctly rejected before compilation. Both
build paths now retain their behavior, with exact Runtime assembly/type identity and both typeof
sites unchanged. SDK props shrinks 52→48 lines / 43→40 nonblank; only that row changes, epochs and
380 other rows fixed, audit 18/18, head `head-v1:ecbbc4855234c4dc`. Private bootstrap changes only
Sdk.props atop the accepted SDK; no live SDK publication precedes the fresh corrected gate. The
first final gate and all three failures remain preserved in `final-gate-r1-failure-receipt.json`.

Accepted: fresh final backend gate at `d4dac34b628f216b3c39e01c7b55c470c6ddedbf` passes in
481s, with 574 C# tests, 7,928 canonical N# tests, 53 native projects, 12 throughput cells and 68 IL
assemblies. The corrected gate starts from a preserved private stage-0 SDK copy; its only difference
from the accepted package is source Sdk.props. Official setup then publishes the actual complete SDK,
SHA256 `d43d021038063adf04322c9964cfec81d50a22593b903a5abf78541d15416430`. Ordinary package tests
pass 6/6; both feeds and twelve loaded cache payloads match. A clean ordinary installed-SDK rebuild
self-hosts all 7,928 canonical tests, then dev Columnar passes 12/12 and all six Analyzer projects
pass 1,088/1,088 with exact public API/87-field metadata parity. No cache or SDK-path override is used
for that final installed verification. Receipts: `accepted-final-gate.json`, `seed-final/`,
`final-ordinary-selfhost-r1/receipt.json`, and `final-loaded-sdk-audit.json` under the evidence root.

The aggregate ownership audit removes 2,498 C# lines / 2,340 nonblank across exactly six rows,
leaving 375 rows and all epochs unchanged. Audit 18/18 passes. The selected area is complete;
compiler-wide ownership and the separately recorded broader branch backlog remain open.
