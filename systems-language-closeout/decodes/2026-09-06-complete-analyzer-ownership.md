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
exact Runtime type execution, generated-props compatibility and deduplication. Seed publication
and the BSS project.yml dependency remain pending the coherent compiler prerequisites and fresh
integration verification. This does not accept Analyzer or the broader independent SDK backlog.
