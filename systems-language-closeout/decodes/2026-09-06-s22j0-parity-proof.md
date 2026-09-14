# S2.2(j0): accepted iterator continuation binding prerequisite

The N# binding owner now admits exactly `OpCodes.Ldftn` in its existing call-and-compute
family. Product `74e0c908a4ed006aede51b4da69aa8a275f721d2` integrates Sol `329cda75`;
wording-only `9be5346d4` integrates `b2acfd718`, and native controls `b57676617` integrate
Terra `27dd4ec97`. The complete gated source is **`b576766171d1563d82d9f4f45ecff82d7cf858a7`**.
No C# changed and no iterator realization owner moved in this prerequisite. The emitter remains
19,264 lines / 18,300 nonblank / 1,007,405 bytes, ratchet `head-v1:aa711599f6919ff9`, and
AddType consumers remain 36 / 12 files / 6 keyed / 30 handle-only.

The initial constructor probe used inferred MethodBuilder/FieldBuilder operands. Its outer Emit
decline did not isolate field binding, and zero tests ran. The corrected same-handle MethodInfo and
FieldInfo views still declined at the Ldftn expression under the accepted old seed. The native old/new
pair uses those exact operand types. Old `baseline-decline-03` has the expected compile decline and
zero execution; candidate `candidate-native-01` runs 6/6. Prefix instructions are not claimed executed
on the refused source. The invalid whole-project CLI test route encountered inherited strict lint;
its zero-test output is retained as a non-verdict.

Two new canonical tests prove short/qualified exact BCL field selection, opcode value identity,
the existing Emit(OpCode, MethodInfo) plan, actual static-field plan execution and source shadow
rollback. Together with the retained negative boundary test, the exact focused run passes 3/3.
Ldarg_S, Ldarga_S, Starg, Starg_S and Ldvirtftn remain unsupported, and Byte remains outside
Emit operand policy. Starg has InlineVar encoding; it is not a byte operand.

The independent native fixture defines and bakes a real type, emits its constructor using the BCL
Ldftn field, stores an Action, invokes it and observes core field mutation. It requires the Action's
bound target to be the machine. Its independently decoded actual constructor contains one Ldftn;
Module.ResolveMethod identifies the baked MoveNextCore by owner, name and token. Numeric opcode
bytes occur only in the test decoder; there is no reflected/numeric opcode emission fallback.
The exact helper/test hashes are `0c495013c10b63acb641cab6cfd85ef94fdc93baac53ca78c2f398ddc5c05255` and
`8ddba2e317d15807344379b814b34ee81534d64d976c00afd5ef5a5a0725a4f1`.

Immutable proof directory `H = /private/tmp/nsharp-023-s22j0-proof-20260906` retains the accepted i compiler and a clean product `74e0c908a` archive.
Both 14-file CLI and 77-file support manifests are verified. The fixed corpus remains
`f54385d5d6b32efb0cb47e5761931bb63af707f4`: 75 targets, 73 successes, 94 normalized PE images and
2,184 native passes per arm, with zero image/set/normalized-outcome differences. The same two
NL402 template refusals remain. Strict pre/post checks on the same product source have byte-identical
JSON and all 258 ordered findings unchanged across 433 files. Later test comments and native controls
are covered by the final gate; they do not change the immutable product comparison.

The fresh exclusive backend gate passed in **455s**: 593 unit / 7,796 canonical / 107 native
declarations / 6 Reflection.Emit bootstrap / 15 records / 18 ownership tests, 52 native projects and
68 IL-verified assemblies. Benchmark correctness passed; timing unjudged because of host load. Raw log, archive identity,
verdict and the three retained isolated diagnostics are under `/private/tmp/gate-20260906-goal-s22j0-r1`. The final Markdown-only
acceptance commit is separately compared with the tested source and its remote revision is recorded
in acceptance.json after push. No gate is attributed to an untested product revision.

After the gate, the coordinator ran `./scripts/setup-local.sh --skip-vscode --no-path-update`
from the clean committed tested source. Attempt 1 failed before new SDK/toolset publication;
bootstrap runtime packing had already completed. The installer removes the installed feed/cache,
then inherited NuGet configuration restored the obsolete secondary-feed SDK
(Compiler e35165a1, BSS 99f77241). It refused the already-used TryFindWeakCallConstraints parameter.
The attempt/log/cache and overwritten secondary SDK are preserved. The coordinator restored only the
byte-verified accepted g1 SDK package in that feed, then the unchanged setup succeeded. This is an
operational seed repair, not a compiler or installer source fix. After successful setup, all four new
package names were synchronized to both actual local feeds with before/after hashes and backups. Installed SDK 0.1.0 package SHA256:
`ca839fc7c95c078145f9b2abe1dd07c47eb8ab0f2d5030d220493a73e36f637d`. Packaged Compiler.dll SHA256 `a39839c4bf8e2960e6d3460cd3001f8ef096c0990e53b4db791ee303d757332b`;
BootstrapServices SHA256 `63315663fb6ed1d0e5d4a10c833e87961a44bfe66b8ecc3cca52624a2fa1994d`. All 10 tool files match the actual
setup Release artifacts, and all 12 SDK/tool entries match the live NuGet cache before/after a
standalone minimal SDK-project build. Four old g1 DLLs differed from the new package; their cache was
preserved in `seed-repin/stale-sdk-cache` and only the SDK 0.1.0 cache was refreshed.
Build diagnostics prove the actual NuGet SDK resolution and
EmitIlAssembly task load from that cache. The two unchanged native source files pass **1/1** through
that installed SDK; emitted fixture IL has the real BCL Ldftn field read followed by the typed
ILGenerator.Emit(OpCode, MethodInfo) call. Emitted DLL `0db13be218140c332105d61cb55b69dd766af2cfd123cb77942c76da837f1742`.
Seed acceptance: `/private/tmp/gate-20260906-goal-s22j0-r1/seed-repin/acceptance.json`, SHA256 `ce707e2f5061b74b7a8fc62d1bc42f6501e217c57df3877fadc6435b2da22dff`.
Existing legacy validation remains enabled bootstrap debt; this repin does not retire it.

Astra independently reviewed candidate source/control semantics, producer linkage, immutable corpus
and strict evidence, and installed SDK provenance. Review roots: `/private/tmp/nsharp-s22j-review/j0/`
(candidate, immutable-post, packaged-live-seed). Producer handoff SHA256
`a3329420ea1566253de0abf6331ffcb2774c20d0f61ed4049d7e0b9682c9151f` at
`/private/tmp/nsharp-s22j-executor-logs/j0/handoff-receipt.json`. Native old and candidate receipts
remain under `/private/tmp/nsharp-s22j-controls-logs/ldftn-continuation/`.

Next is the [connected j realization cut](2026-09-05-s22j-iterator-next-cut.md), first proving the
direct declaration surface and actual machine/factory rebased field companions with this seed.
Real source T captures are admitted; source T[] capture preserves its measured refusal. T[] handle
controls are internal identity probes, not new language admission. The j native control commit
`86405783` remains separate and unintegrated. All 015/021/022/023 terminal boxes and goal.md remain open.
