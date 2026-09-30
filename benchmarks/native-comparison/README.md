# native-comparison — systems N# vs Rust vs C

Standalone, reproducible cross-language micro-benchmarks for the systems hot paths, used to measure
systems-N# against native compilers (Rust, C). The Rust and C ports are NOT part of the `dotnet`
build — they are hand-rolled ports of the same algorithms the N# kernels measure, so we can compare
N# codegen against LLVM/clang directly. Treat checked-in numbers as historical unless they are
refreshed by a current benchmark run.

Each `<workload>/` has `main.rs` and `main.c` implementing the SAME algorithm as the corresponding
N# kernel, over the same sizes (64, 4096), with a warmup, a large fixed iteration count, and an
anti-dead-code-elimination sink that is printed (so `-O3` cannot elide the work). Each prints
`<workload> <size> <ns_per_op>` on stdout and a median/min/IQR stability line on stderr.

Two N# projects sit beside them:

- `nsharp-kernels/` — the six `[hot]` kernels and the measurement harness, with the same input fill,
  warmup, fixed-iteration and sink discipline as the ports. Beside them, `ControlKernels.nl` holds a
  frozen copy of the same six bodies: the throughput gate's same-run control, described below. It
  also answers `--verify` (kernel results), `--il-shape` (which `SimdReductions` helpers each emitted
  kernel actually calls, for the live kernels and the control) and `--paired` (the gate's interleaved
  live-against-control measurement).
  It is named `nsharp-kernels` rather than `nsharp` because the product gate's isolated copy of the
  tree excludes every directory named `nsharp/`, which would have hidden it from the gate that runs it.
- `runner/` — the comparison runner and the throughput gate, described below.

## Run

The runner owns the whole comparison: it records the environment, builds the N# kernel program,
compiles all twelve Rust/C ports, runs the three languages back to back per workload, and writes the
report. There is no shell loop to keep in sync any more.

```bash
CLI=src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll
dotnet "$CLI" build --project benchmarks/native-comparison/runner
dotnet benchmarks/native-comparison/runner/bin/Debug/net10.0/NSharpLang.NativeComparisonRunner.dll \
    compare --cli "$CLI" --repo "$PWD"
```

`--out <dir>` overrides the output directory (default `artifacts/native-comparison/<yyyy-MM-dd>/`),
`--runtime <dll>` supplies an already-built runtime (see below), and `--trials <n>` is forwarded to
the N# kernel program for a quick smoke run, so a `--trials 2` run proves the plumbing, not the
numbers.

The ports do NOT share one trial count. `checksum-sum`, `count-ascii`, `count-transitions` and
`parse-eight-digits` run 15 trials; `rolling-hash` and `min-max-delta` run 21. Iteration counts vary
too: most workloads use 2,000,000 iterations at size 64 and 50,000 at size 4096, while
`parse-eight-digits` uses 20,000,000 at both sizes because it only ever touches the first eight
elements. The N# kernel program mirrors each port's own iteration and trial counts so the two sides
of a row are the same experiment; `--trials <n>` overrides the trial count only, never the iteration
counts, and it applies only to the N# side — a Rust or C port has no such flag and always runs its
own full count.

It compiles the ports with exactly the flags this directory has always documented:

```
rustc -C opt-level=3 -o <tmp>/<workload>_rs benchmarks/native-comparison/<workload>/main.rs
clang -O3           -o <tmp>/<workload>_c  benchmarks/native-comparison/<workload>/main.c
```

`rustc` is resolved at `$HOME/.cargo/bin/rustc` first and falls back to `PATH`, so no
`source "$HOME/.cargo/env"` is needed. The binaries go in a temporary directory that is removed at
the end of the run.

### N# JIT settle preparation

Before its measured trials, each N# workload/size cell invokes the actual `RunTrial` path until at
least 500 ms has elapsed and that cell's selected timed-loop wrapper has been invoked at least 40
times. Settle invocations run 100 warmup and 1,000 measured iterations, but their nanosecond-per-op
samples are discarded and they are not reported as trials. The settle interval also keeps folding
results into the printed sink, so its exact fold count can vary.

This preparation is empirical: the 500 ms and 40 invocation minima are chosen to give CLR tiering and
OSR a chance to observe and compile the wrapper, kernel, and helper paths. They do not guarantee that
all code reaches Tier 1, and they are not evidence that any particular gate failure is solved. The
port-matched warmup, measured iteration, and trial counts remain unchanged.

### The runtime the kernels are measured against

Both modes replace the kernel program's `NSharpLang.Runtime.dll` before running it, and this is
load-bearing rather than housekeeping. `nlc build` copies the runtime that sits beside the CLI it was
launched from (`CompilationReferenceResolverKernels.nl` resolves it out of the CLI's own base
directory). A developer CLI is a Debug build, so that copy carries
`DebuggableAttribute(DisableOptimizations)`, and the JIT then compiles every `SimdReductions` helper
the kernels call at minopts. What gets measured is an unoptimized runtime, not N# codegen — and the
error lands squarely on the vectorized kernels, because they are the ones that call into it. Measured
A/B on a loaded machine: `checksum-sum` 4096 went from 3925 ns with the Debug runtime to 1019 ns with
the Release one, and `min-max-delta` 4096 down to 772 ns.

So the runner builds

```
dotnet build --disable-build-servers -nr:false src/NSharpLang.Runtime/NSharpLang.Runtime.csproj -c Release -v q
```

and copies `src/NSharpLang.Runtime/bin/Release/net10.0/NSharpLang.Runtime.dll` over the kernel
program's copy *after* `nlc build` has run — after, because the build is what puts the Debug copy
there. `--runtime <dll>` skips the build and uses the assembly you name; either way the runner
refuses to run the kernels if that assembly is missing, and `results.md` records the path and size it
used. This is not working around a product defect: the published toolset already packs the runtime
with `-c Release` (`scripts/lib/packages.sh`), so a user's install is optimized — only a dev CLI's
copy is not. `tests/scripts/test-all-core.sh` step 2c needs no change, because the runner builds the
Release runtime itself inside whatever isolated copy of the tree the gate runs from.

Four files land in the output directory:

| File | Contents |
| --- | --- |
| `results.csv` | one row per (workload, size, language): `median_ns,min_ns,q1_ns,q3_ns,iters,trials`. A field a port does not print is an empty cell, never a zero. |
| `results.md` | the environment header (commit, CPU, cores, load average, toolchain versions, exact flags and commands), the comparison table, and every stability line grouped by language. |
| `raw-stdout.log`, `raw-stderr.log` | everything the children wrote, prefixed `[<language> <workload>]`. |

The comparison table carries today's N#/Rust/C medians, the best of the two natives, `N#/best-native`,
the 2026-06-07 N# median, `today/June N#` (flagged `**REGRESSED**` above 1.15x), `June N#/best-native`
— June's N# over June's OWN best native, so the two gap columns can be read side by side — and the
`vectorized` column, which is that workload's `--il-shape` answer.

## Throughput gate

`gate` is the pass/fail form, and it is what the product gate runs (`tests/scripts/test-all-core.sh`,
step 2c, skipped when `SYSTEMS_BENCH=skip` is set). The gate runs it immediately after compiler build
and formatting, before prolonged self-host, native, and VS Code phases; that avoids preconditioning
from later gate work. It builds the Release runtime, builds the N# kernel program against it, and
runs it in its PAIRED mode. It runs no native compilers and no `git`, because the gate executes from
a copy of the tree without `.git/`. Its first line names the runtime it used, its second the protocol.

```bash
dotnet benchmarks/native-comparison/runner/bin/Debug/net10.0/NSharpLang.NativeComparisonRunner.dll \
    gate --cli "$CLI" --repo "$PWD"
```

### The gate measures its own reference

Each of the twelve cells is measured TWICE in one process, interleaved: once as the live kernel from
`Kernels.nl`, and once as `ControlKernels.nl` — the frozen transcription of the kernels the
2026-09-01 medians were taken from. The two sides settle the JIT together, alternating until each has
had >= 500 ms and >= 40 invocations, so neither is the one that settled into a colder process. Both
carry the same per-trial warmup and the same port-matched iteration count, and each repetition runs
one trial of each, live-first on even repetitions and control-first on odd ones.

The gate takes **31 repetitions per side**, not the ports' 15 and 21. `compare` mirrors each port's
own trial count because its question is "how many nanoseconds, beside the same experiment in Rust and
C". The gate's question is a ratio of two N# measurements, so the ports' counts bind nothing, and
what matters is how much noise reaches the verdict: under a six-core artificial load, 15 repetitions
gave paired ratios spanning 0.89x-1.24x and tripped about one run in three, while 31 gave
0.95x-1.06x. `--trials <n>` overrides it.

The cell's verdict is the **median of the per-repetition ratios** — each repetition's live sample
divided by the control sample measured beside it — and it fails above `1 + tolerance` (default
`--tolerance 0.20`). It is deliberately not the quotient of the two medians: a size-64 cell's
measured window is about ten milliseconds, the same order as a scheduler quantum, so a contended
machine costs a handful of windows outright and the two independently-taken medians drift apart by up
to 24% with nothing regressed. Dividing samples that were measured milliseconds apart cancels the
contention they shared. Both medians are still reported, in the table's two nanosecond columns.

This replaced a comparison against stored nanoseconds, and the reason is recorded rather than
asserted. The old gate divided each measured median by a number taken once, on 2026-09-01, on an idle
Apple M4. That is a measurement of one machine in one state, and the gate runs on whatever machine is
free: `count-transitions` failed at 1.20x-1.75x whenever another build was running and passed at
0.95x-1.06x on a quiet box, and one run under load average 25 failed all twelve cells at 1.63x-4.04x
with nothing regressed. Widening the tolerance would have traded those false alarms for blindness.
Measuring the reference in the same minutes on the same machine removes the variable instead: load
multiplies both medians and divides out of their ratio.

A row with no measurement, a measurement with no row, and a row whose CONTROL did not report all
fail, because the twelve rows are a contract.

### What the control cannot see, and what covers it

Control and live are compiled by the same `nlc`, so a compiler change that de-vectorizes the shape
they share slows both sides equally and the ratio does not move. That is the 2x-6x regression this
lane exists for, so the gate checks it directly rather than statistically: it runs the kernel program
a second time with `--il-shape`, reads out of the emitted IL which `SimdReductions` helper each
kernel actually calls, on BOTH sides, and fails when an answer is not the one
`SystemsThroughputBaseline.nl`'s `ExpectedSimdHelper` names. An IL fact needs no quiet machine and
admits no tolerance. The paired mode also refuses to report any timing at all if the control and the
live kernel ever compute different answers.

### The drift table

The gate then prints a second, clearly informational table: this run's control median over the stored
2026-09-01 median, per cell, plus a `DRIFT (informational, never gating)` summary. This is the one
thing a same-run ratio deliberately cannot see — the machine and the toolchain moving under both
sides at once. On a quiet box it sits near 1.0x; under a concurrent build it rises to 2x-4x, which is
the load being reported rather than a regression. It never contributes to the exit status.

`gate --print-baseline` prints this run's CONTROL medians as the exact N# rows of
`SystemsThroughputBaseline.nl`, so resetting the drift reference on an idle machine is a paste rather
than twelve hand edits. Refreshing it changes no verdict.

Every gate run also writes its raw kernel stdout/stderr and a context record to
`artifacts/native-comparison/<date>/gate-<UTC-timestamp>/`; `compare` itself still uses the parent
`<date>/` directory. The raw logs keep the stability lines (including min/IQR/quartiles), and the
context records measurement start/end UTC plus pre/post load. The runner prints the three artifact
paths. This is observability only and does not change the timing protocol, tolerance, or exit
status. An isolated product-gate copy is deleted after the run unless `NSHARP_TEST_KEEP_RUN=1`
retains it, so copy those artifacts out of the retained tree when diagnosing an isolated failure.

It compares MEDIANS, not means, on both sides of every ratio: the BenchmarkDotNet gate this replaces
compared means and flaked under load, because a handful of thermally-throttled iterations move a mean
and do not move the median of 15 trials. 20 percent is wide enough to absorb the run-to-run spread
between two interleaved medians — a few percent on a quiet box and, because the two sides share the
machine, still a few percent under load — and tight enough to catch a kernel that got materially
slower than the reference it is supposed to match.

## Why the runner is N# and not a shell script

The natural spelling of all this would be a `scripts/bench-native-comparison.sh` next to a
`scripts/systems-throughput-baseline.json`. Neither can exist: the ownership ratchet
(`tests/native/ownership-audit`) fails on any NEW non-N# file added to the repository (OWN003). That
is the right answer here rather than an obstacle — a benchmark runner that drives the N# compiler is
exactly the kind of tooling the dogfood rule exists to move into N#. So the runner, the report
writer, the June comparison table and the throughput baseline are all N# source, and because the
baselines are N# DATA rather than a parsed data file, a malformed baseline is a compile error instead
of a runtime surprise inside the gate.

## Methodology note

All six workloads are methodologically clean on both Rust and C. The C kernels use a per-iteration inline-asm
pointer-launder barrier (`__asm__ volatile("" : "+r"(p))`, the C equivalent of Rust's `black_box`) so
`clang -O3` cannot hoist/DCE the loop-invariant kernel call out of the timed loop. (min-max-delta and
parse-eight-digits originally lacked this per-iteration barrier and were DCE'd; fixed 2026-06-06.) Each port
prints both the machine-readable `<key> <size> <ns>` line on stdout and a stability line
(median/min/IQR/iters/trials) on stderr.

The stability lines are NOT uniform: the six port pairs were written at different times and print
five different stderr shapes (some omit `median=`, some omit `q1`/`q3`, some spell the quartiles
`iqr=[q1,q3]`). The runner reads them with a tolerant `key=value` scan and always takes the median
from the stdout line, which every port prints identically. The ports are deliberately not rewritten
to one shape: they are the historical measurement baseline, and editing them to suit a new reader
would invalidate the numbers already published against them.
