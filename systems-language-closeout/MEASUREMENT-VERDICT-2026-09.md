# Measurement verdict, 2026-09 — nlc compile time and the remaining price of task 015

This file answers two questions with numbers: how fast the N# compiler is today, and what finishing
task 015 (deleting `ColumnarIlEmitter.cs`) still costs. It does not make the call; §7 lays the two
options side by side so the user can.

Everything here was measured on 2026-09-01 on one idle machine (Apple M4, 10 logical cores, macOS
15.6 / Darwin 24.6.0, .NET SDK 10.0.105) with a CLI built from `systems-language` tip `8cf40128a`
(the harness commit adds only the harness, its baseline, docs and these results; the compiler under
test is `8cf40128a`). The harness is `tests/native/compile-time-bench`; its raw output is committed
under `artifacts/compile-time/2026-09-01/` (`runs.csv`, `compile-time.csv`, `compile-time.md`, the
C# reference sweep under `csharp-reference-5fce5896f/`, and the SDK emit-only logs under
`sdk-emit-only/`).

## 1. What was measured, and how

- **Corpus:** the 68 projects with a `project.yml` under `examples/`, `tests/` and `templates/` — the
  set the 015-B slices call "the corpus". 27 of them hold only `.tests.nl` files, which `nlc build` and
  `nlc check` do not compile (they are compiled by `nlc test` in the gate's Step 3a), so 41 corpus
  projects are measured, 7,049 lines between them. Plus the large-project case,
  `src/NSharpLang.Compiler.BootstrapServices`: 403 non-test `.nl` files / 172,653 lines (690 files /
  331,400 lines with the `.tests.nl` estate that `nlc build` does not compile).
- **Commands:** `nlc build --project <dir> --timings -o <fresh temp dir>` and
  `nlc check --project <dir> --json`, each spawned as a real process under `/usr/bin/time -l`, five
  runs per project per command, median reported (lower middle for an even count). `nlc build` has no
  incremental cache and `nlc check` has no daemon on this path, so every run is cold; the harness
  proves after every build that the project directory was not written to.
- **Lines per second** = the `\n`-terminated lines of the files the command actually compiles
  (replicated from `ProjectConfig.GetSourceFiles(includeTests: false)` and cross-checked against
  `checkedFiles` in every `nlc check --json` envelope; zero disagreements) divided by the median wall
  clock, which includes the `dotnet` host start of roughly 200 ms.
- **The SDK emit-only path** (the way the product actually builds the compiler, §3) was measured by
  hand beside the harness: five `dotnet build … -t:Rebuild -m:1 -nr:false --disable-build-servers
  -clp:PerformanceSummary` runs of the BootstrapServices csproj under `/usr/bin/time -l`, reading the
  `EmitIlAssembly` task time out of MSBuild's own performance summary, plus one plain `dotnet build`
  of the already-built project. Method and all six logs are in `artifacts/compile-time/2026-09-01/sdk-emit-only/`.
- **Idle machine:** the run started only after four other Claude sessions on this machine confirmed a
  hold on builds, tests and gates, and a watcher saw 60 s with no build/test/gate process above 5 %
  CPU; a guard watched the whole window for foreign builds and saw none (§8).

## 2. Results

### 2.1 The large-project case, `src/NSharpLang.Compiler.BootstrapServices` (403 files / 172,653 lines)

| command | what it covers today (§3) | exit | median | spread (5 runs) | peak RSS | lines/s |
|---|---|---:|---:|---|---:|---:|
| `nlc build` (tip CLI) | parse + strict lint, stops there | 1 | **7,868 ms** | 7,668–8,079 ms | 172 MB | **21,944** |
| `nlc check --json` (tip CLI) | parse + analysis, 243 error results | 1 | **26,997 ms** | 26,517–27,319 ms | 683 MB | **6,395** |
| SDK path, emit-only (`EmitIlAssembly` task, packaged compiler from `b57c661a0`) | parse + IL emit of the same 403 files, no analyzer, no lint | 0 | **132,644 ms** | 131,453–133,409 ms | 611 MB (591–631) | **1,302** |

MSBuild's own overhead around the task is 0.6 s (real 133.2 s vs task 132.6 s). The sixth run, a
plain `dotnet build` with nothing changed, emitted again for 132.3 s: **the SDK build of an N#
project has no incremental skip**, so every `dotnet build` of the compiler pays the full emit.

### 2.2 The corpus (41 measured projects, 7,049 lines, tip CLI)

| command | scope | projects | lines | sum of median wall | aggregate lines/s |
|---|---|---:|---:|---:|---:|
| `nlc build` | all measured | 41 | 7,049 | 17,099 ms | 412.2 |
| `nlc build` | compiled (exit 0) | 39 | 6,991 | 16,704 ms | 418.5 |
| `nlc check` | all measured | 41 | 7,049 | 18,426 ms | 382.6 |
| `nlc check` | compiled (exit 0) | 39 | 6,991 | 18,010 ms | 388.2 |

Per-project `nlc build` lines/s: median 176, from 12.8 (`templates/nsharp-console`, 3 lines, 235 ms)
to 1,620 (`tests/native/ownership-audit`, 1,406 lines, 868 ms). A 3-line project costs 235 ms and a
20-line one 296 ms, so the corpus numbers are the process floor, not the compiler: the `dotnet` host
plus CLI start-up is about 200 ms and dominates every project under ~200 lines. The two projects that
fail are the shipped `templates/nsharp-systems-cli` and `templates/nsharp-systems-lib` (NL402 on
`Slice`, NSYS050), a template defect the sweep surfaced. Peak RSS on the corpus is 86–227 MB.

### 2.3 What the numbers say

- The N# front end parses and lints **172,653 lines in 7.9 s (~22 K lines/s)** in 172 MB. Parse
  plus analysis takes **27.0 s (~6.4 K lines/s)** in 683 MB, so analysis is 3.4× the front end.
- **Emit is the long pole, and it has regressed.** The only end-to-end parse + emit figure for the
  large project is the SDK path: **132.6 s for 172,653 lines (1.3 K lines/s)**, 17× the front end.
  On 2026-07-08 (`2e1286d99`, the retained-table fix) the same task on the same project took 3.4 s
  for 233 files / 63,689 lines (18.7 K lines/s, 533 MB). The source grew 2.7×; the emit time grew
  39×; per line the emit-only path is **14× slower than in July**. The July note recorded that the
  three `ColumnarProgramInputBuilder.TryParseColumnar*` functions still allocated per-member scratch
  arrays sized by the whole file's token count — an O(members × tokens) shape — as "a follow-up if
  emit RSS matters again"; a superlinear growth of exactly this kind fits 2.7× lines → 39× time,
  but that is a hypothesis to be measured, not a finding of this sweep.
- The emit-only path is `ColumnarProgramInputBuilder.TryBuildMultiFile` (the N# parser kernels
  behind a C# builder) followed by `ColumnarIlEmitter.TryEmitColumnarAssembly` (the C# host that
  task 015 is porting, plus its N# planners). The 125 s between the front end's 7.9 s and the emit
  path's 132.6 s is spent in exactly the code the 015 arc moves byte-for-byte.
- The corpus is startup-bound: 39 projects compile in 16.7 s total, 0.43 s each on average, with the
  host start as the floor. No corpus project is large enough to show throughput.

## 3. The finding the benchmark forced into the open: `nlc` cannot build its own compiler

`nlc build` runs `CompileToIlAssembly(validateStrictLint: true)`. On
`src/NSharpLang.Compiler.BootstrapServices` strict lint reports 45 findings (NL012 ×20, NL011 ×17,
NL010 ×7, NL002 ×1) and `RunLegacyValidationPipeline` returns before `AnalyzeAllFiles()`, so the
build exits 1 after parse + lint and never reaches analysis or emit. `nlc check --json` on the same
tree reports **243 error-severity results** (NL202 ×85, NL402 ×65, NL905 ×26, NL012 ×20, NL011 ×17,
NL301 ×16, NL010 ×7, NL303 ×3, NL412 ×3, NL002 ×1) and exits 1. STATUS.md records the 243 and
classes the NL402 family as pre-existing false positives; the other families are unclassified in the
ledger. The code they flag compiles and passes the 7,190-block `.tests.nl` estate, so they are
analyzer defects, not source defects, until proven otherwise one family at a time.

The product builds the compiler anyway because `src/NSharpLang.Sdk/Sdk/Sdk.targets:16` switches
legacy analysis OFF for the one project named `NSharpLang.Compiler.BootstrapServices`, so the MSBuild
path emits with no analyzer and no lint. Consequences:

- The `nlc build` number for BootstrapServices is a **front-end** number (parse + strict lint). The
  `nlc check` number is **front-end + analysis**. Only the SDK row includes emit, and it runs the
  packaged compiler four sub-slices behind tip, not the tip CLI.
- The compile-time gate (`tests/native/compile-time-bench`, Step 3a) therefore pins `nlc build` on
  BootstrapServices at **exit 1, front-end stage**: the baseline's `expectedExitCode` and `stage`
  fields say so, and a run that exits 0 fails the gate on purpose ("re-measure the baseline"),
  because what is measured will have changed. Until the 45 lint findings and the 198 analysis errors
  are fixed on the compiler's own sources, emit speed on the large project is not gated — and §2.3
  shows emit is where the time is.
- The 198 analysis errors live in the analyzer's external type model (the MetadataLoadContext
  quarantine in `Analyzer.cs`, the AOT type-model task). The 015 deletion arc does not touch them.
- A user who runs `nlc build` on a project shaped like the compiler's own sources gets these
  diagnostics. That is a launch-facing defect that no 015 sub-slice addresses.

## 4. The C# reference point

The last commit whose production compiler could be forced onto the C# ILCompiler path is
`5fce5896f` (2026-06-23, "Require NSharp project source filtering"): its successor `018793a6f`
deleted the `NSHARP_COLUMNAR_BACKEND=0` escape hatch and `1cef0d16e` deleted the ILCompiler itself.
At `5fce5896f` the front end was still the C# `Parser.cs`/`Analyzer.cs` (tasks 016/017 deleted them
later), so `NSHARP_COLUMNAR_BACKEND=0 nlc build` there is the whole June-23 C# pipeline: C# parser,
C# analyzer, C# emitter.

`5fce5896f` **builds under the current SDK** (59 s, exit 0) in a second worktree, removed after
the sweep. What it can and cannot compile:

- `src/NSharpLang.Compiler.BootstrapServices` at tip: **cannot** — 777 NL101 parse errors (the
  language moved after June 23), so **there is no C# reference for the large project**, and the
  head-to-head that matters most cannot be run.
- The tip corpus, same harness, same five-run medians, C# path forced
  (`artifacts/compile-time/2026-09-01/csharp-reference-5fce5896f/`): 37 of 41 measured projects
  compile (`templates/nsharp-systems-lib`, `tests/fixtures/external-static-package`,
  `tests/native/construction-arrays` and `tests/native/direct-calls` use syntax it does not know).
  Paired over the **36 projects both compilers compile** (6,114 lines):

| command | tip (N# pipeline, `8cf40128a`) | June-23 C# pipeline (`5fce5896f`) | tip / C# |
|---|---:|---:|---:|
| `nlc build`, sum of medians | 15,361 ms (398 lines/s), mean peak RSS 112.5 MB | 15,437 ms (396 lines/s), mean peak RSS 96.2 MB | **0.995** |
| `nlc check`, sum of medians | 16,567 ms (369 lines/s), mean peak RSS 121.9 MB | 17,272 ms (354 lines/s), mean peak RSS 105.7 MB | **0.959** |

So on everything the June compiler can still parse, the all-N# pipeline is a tie on build, 4 %
faster on check, and uses ~16 % more peak memory — with the caveat that these projects are
startup-bound (§2.2), so the comparison is of two ~250 ms processes, not of two compilers under
load. The only project that would separate them is the one the reference cannot parse.

The two prior head-to-heads, both pre-016/017 and cited as the only earlier evidence: the Phase C
never-slower benchmark (`9779a3c44`, 2026-06-08, `benchmarks/ColumnarBackendEmitBenchmarks.cs`,
log under `benchmarks/BenchmarkDotNet.Artifacts/`) — in-process `CompileToIlAssembly` with parse +
analyze shared, C# emit 3.963 ms vs columnar 3.947 ms on a 2-function program and 21.520 ms vs
21.193 ms on a 40-function one, a tie; and the parser front-end measurement of 2026-06-06
(`benchmarks/CompilationUnitRoutingBenchmarks.cs`, slice 26) — the pooled columnar parser at 0.41×
the C# parser's time (2.4× faster), with materialization into the C# AST costing 5.5×.

## 5. Native comparison

`artifacts/native-comparison/2026-09-01/results.md` exists on the `measure/native-comparison` branch
(worktree `/tmp/nsharp-native-bench`, measured 22:54 on the same idle machine, minutes before this
sweep, by the native-comparison session). Its N#/best-native table, quoted:

| Workload | Size | N# ns | best-native ns | N#/best-native | June N#/best-native | today/June N# |
|---|---:|---:|---:|---:|---:|---:|
| checksum-sum | 64 | 5.491 | 2.159 (C) | 2.54× | 1.87× | 1.30× **regressed** |
| checksum-sum | 4096 | 297.304 | 116.624 (Rust) | 2.55× | 2.02× | 1.34× **regressed** |
| count-ascii | 64 | 6.842 | 3.426 (C) | 2.00× | 1.57× | 1.29× **regressed** |
| count-ascii | 4096 | 348.382 | 189.349 (Rust) | 1.84× | 1.63× | 1.17× **regressed** |
| count-transitions | 64 | 13.261 | 7.127 (C) | 1.86× | 1.70× | 1.17× **regressed** |
| count-transitions | 4096 | 577.534 | 252.660 (C) | 2.29× | 1.97× | 1.21× **regressed** |
| rolling-hash | 64 | 42.157 | 30.960 (Rust) | 1.36× | 1.42× | 1.00× |
| rolling-hash | 4096 | 4687.854 | 2953.767 (Rust) | 1.59× | 1.62× | 1.00× |
| min-max-delta | 64 | 12.573 | 4.739 (Rust) | 2.65× | 2.49× | 1.13× |
| min-max-delta | 4096 | 309.500 | 154.880 (C) | 2.00× | 1.67× | 1.22× **regressed** |
| parse-eight-digits | 64 | 3.339 | 1.546 (Rust) | 2.16× | 1.80× | 1.20× **regressed** |
| parse-eight-digits | 4096 | 3.331 | 1.544 (Rust) | 2.16× | 1.80× | 1.20× **regressed** |

Read beside the June table (`git show 9372d0c78:docs/design/systems-vs-native.md`): the native
columns are unchanged within noise, and every vectorized N# kernel is 1.17–1.34× slower than in
June while the non-vectorized ones are flat. The systems-language performance objective has moved
backwards since June, and nothing in the 015 arc measures it — the B-arc acceptance bar is byte
identity of the emitted IL for the claimed kinds, so the regression sits in a path the arc does not
own. That branch's own verdict is the place for the root cause; here it is a data point for §7.

## 6. The remaining price of task 015, as the queue itself records it

- **Where the B arc stands (STATUS.md §1, tip `40e0cc20e`):** the method-body door claims 2 of 21
  statement kinds (kind-24 `:=` declarations and `return`) and 10 of 27 expression kinds after 15
  sub-slices (B1–B15). The emitter is 20,784 lines (epoch 21,723). C# deletion lands only at the end
  of B; STATUS.md's own words: "Continue the B-arc to full statement/expression coverage (C# host: 21
  statement kinds / 27 expression kinds; N# door growing)."
- **After B:** 015-C is folded into B (the typing answer lives in the body planner); then 015-D (real
  async lowering, retiring the blocking-await model); then 015-E — the declaration host
  `TryEmitColumnarAssembly` (2,024 lines / 41 decline sites / 57 sentences) is ruled NOT a 015 target
  and "retires with the AOT metadata writer", a `MetadataBuilder` executor over the same plan rows,
  i.e. a second backend; then the AOT type-model task (replace the analyzer's MetadataLoadContext;
  `MetadataReader` is unreachable from N# at emit); then 021's closing decision.
- **Observed pace (commit dates):** 015 reopened at `6fcb41f64` on 2026-08-27; A1–A6 landed
  2026-08-27/28; B1–B15 landed 2026-08-30 → 2026-09-01. That is 21 sub-slices in six calendar days
  (3.5 per day) and 12 claimed kinds in 15 B sub-slices (0.8 kinds per sub-slice). The emitter moved
  21,723 → 20,784 lines over those 21 sub-slices (−45 lines per sub-slice); by design the line count
  barely moves until the door covers everything and the C# host is deleted whole.
- **Estimate at that pace:** 36 remaining kinds ÷ 0.8 ≈ 45 more B sub-slices ≈ 13 calendar days IF
  the pace holds. It will not hold flat: the kinds left are the composed ones (composed receivers,
  `try`/`foreach`/`match`, iterator and async statements, the interpolation paths), each of which
  STATUS.md says has overturned its brief on decode. A 2× slowdown puts B at about four weeks. D is
  unsized in the ledger; E plus the MetadataBuilder writer is a second backend and at the arc's own
  rate is weeks, not days; the MLC quarantine is a further task with its own decode. **Range: roughly
  6 to 12 weeks of the current one-slice-per-goal-turn cadence before `ColumnarIlEmitter.cs` is
  deleted**, with the last three stages resting on rulings, not measurements.

## 7. Recommendation, presented so the user can make the call

**Option (a): continue 015 to deletion.** Serves the *ownership* objective: the compiler becomes
N# to the last file, the closing contract of 021 is met without a reviewed exception, and the AOT
metadata writer (a real product need — `System.Reflection.Emit` cannot ship in a native image) is
built on the plan rows the B arc is producing. What it does NOT serve, by the numbers in §2–§5:
compile speed or systems performance. Every B sub-slice is accepted on byte-identical output
(`IL_DIFFS=0`), so the arc is designed to leave both unchanged; the 132.6 s emit in §2.1 is in the
code being ported and the port carries it across as is; the front-end finding in §3 and the native
regression in §5 are untouched by it. Cost: §6.

**Option (b): declare `ColumnarIlEmitter.cs` a reviewed mechanical host** — its 144 user-facing
sentences pinned by native contracts (the `columnar-emit-facts` estate already carries 38 blocks
and the 021 audit holds the sentence census), non-growing under the ratchet, with the door kept as
the N# owner of everything it has claimed — and redirect the effort to (1) the emit-path
regression in §2.3 (172 K lines in 132.6 s, 14× slower per line than July; the July note's
per-member scratch-array shape is the first thing to measure), (2) making `nlc build`/`nlc check`
pass on the compiler's own sources (the 45 lint findings, then the 198 analysis errors in the MLC
type model) so the gate covers emit, (3) the native-kernel regression in §5, (4) AOT/native image
(the MetadataBuilder writer and the type-model task, which both options need), and (5) an
incremental skip in the SDK build. Serves the *measurably fast compiler* objective directly and the
*AOT* objective sooner; leaves one C# file in the compiler with a documented exception, which is the
outcome 021 was written to refuse.

**What would flip the call.**
- Toward (a): a B sub-slice that deletes C# materially faster than −45 lines per sub-slice, or
  evidence that the plan-row executor is faster than the C# host on the large project (today it is
  byte-identical by construction, so no speed case exists either way), or a measurement showing the
  132.6 s lives in the N# input builder rather than in the C# host (then porting the host is not
  where the time is, but neither is it where the fix is).
- Toward (b): the SDK-path number in §2.1 being the number a user's build actually sees and the
  only end-to-end figure for 172 K lines; the 14× per-line regression since July having happened
  while the arc's acceptance bar was byte identity; the C# reference being unrecoverable for the
  large project (§4); the front-end finding (§3) and the native regression (§5) being launch-facing
  and owned by nothing in the 015 queue.

## 8. Waits, skips and deviations from the brief

- **Waits for other sessions (idle rule):** the first wait began 20:30 with two other sessions'
  `dotnet test tests/Tests.csproj` runs, a BootstrapServices estate run and MSBuild nodes at load
  13–17; checked at 20:47, 21:08 (eight concurrent `dotnet build`s from other sessions), 21:29
  (another session's full gate plus six builds), 21:49 (four BootstrapServices estate runs) and, after
  a session resume, 22:53 (idle). Total: 2 h 23 min. The native-comparison session then measured
  first by agreement (22:54–22:55). A first start at 22:57 was aborted and its artifacts discarded
  when a chip-worktree build from the 015-B session began during the BootstrapServices runs; all four
  other interactive sessions (nsharplang-bb, nsharplang-c6, nsharplang-3b, the IDE-verify session)
  then confirmed a hold, the chip agents were paused, and the sweep ran 23:03:44–23:25:55 with a
  guard that saw no foreign build. VS Code was open throughout with its N# language servers idle
  (0.1 % CPU) — a deviation from the brief's letter ("never while VS Code is running"), recorded here
  because the IDE session could not close it and its CPU share was measured, not assumed.
- **`scripts/bench-compile-time.sh` was not created and `scripts/compile-time-baseline.json` was not
  created:** the ownership ratchet (`tests/native/ownership-audit`, OWN003) refuses every new non-N#
  file under `scripts/`, `tests/` and the other product-adjacent trees, and the two gate scripts are
  pinned at their epoch line counts (OWN004), so "add a step to test-all.sh" is not possible without a
  ratchet repin. The harness is N# (`tests/native/compile-time-bench`, auto-run by Step 3a as every
  native estate is), and the baseline lives at the ratchet's one JSON exemption,
  `tests/fixtures/compile-time/bootstrap-build-baseline.golden.json`. `SYSTEMS_BENCH=skip` is honored
  by the gate block itself; it is not in the step-cache salt (that list is ratchet-pinned too).
- **The parse/analyze/emit split:** the CLI's existing `--timings` (Resolve / Emit IL / Total) is
  reported as is; no new timing surface was added. It is printed only on a successful build, so the
  BootstrapServices rows carry none.
- **The gate pins exit 1, not 0**, for the reason in §3; the brief's "every run exited 0" is
  impossible on this tree and is replaced by "every run exited with the pinned code and the CLI
  reported the failure itself".
- **The SDK emit-only measurement is manual** (six commands, logged), not part of the N# harness,
  because it measures the packaged compiler through MSBuild rather than the CLI under test.
- **Artifacts are `git add -f`'d:** `artifacts/` is gitignored and `.gitignore` is ratchet-pinned.
- **Gate runs:** the first `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` (23:31–00:24) went red for
  two reasons: the gate block printed one line ahead of its JSON envelope and Step 3a's whole-file
  `json.load` refused it (fixed: a native test writes nothing; the block is silent on success), and the
  template pack timed out on nuget.org. The timeout's cause, found by the native-comparison session and
  verified here with `curl -6` (8 s, no answer) versus `curl -4` (0.05 s): IPv6 to `api.nuget.org` is
  black-holed on this machine and .NET's HttpClient does not fall back, so the isolated gate's fresh
  package cache stalls to NuGet's 100 s timeout. The re-run exports `DOTNET_SYSTEM_NET_DISABLEIPV6=1`
  in the launching shell (an environment workaround, not a repo change; it is not in the gate's
  env salt). Gates were serialized with the native-comparison session by message throughout.
- **STATUS.md was not edited.**
