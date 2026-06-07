# P4 — LLVM / NativeAOT backend evaluation

**Status:** Decision document (2026-06-07). Feeds `P4` on [`roadmap-to-done.md`](roadmap-to-done.md) and
backlog item B in [`systems-perf-backlog.md`](systems-perf-backlog.md). Grounded in the rigorous
single-machine re-run in [`systems-vs-native.md`](systems-vs-native.md).

## TL;DR — decision

**Do NOT build a structural LLVM/transpile codegen backend now.** The throughput motivation that justified it
has been captured by per-pattern `Vector<T>` IL emission (Phase P): on the vectorizable kernels N# is now
**≤2.0× behind best-native (Rust/C), measured** — down from up to 10.5×. The residual ~1.6–2× is latency-bound,
small-input, and scalar-scheduling tax that a backend swap does **not** cheaply remove. The eng cost
(multi-quarter, correctness-critical, a native-toolchain build dependency in the CLI) is now grossly out of
proportion to a ~2× → maybe ~1.3× residual on a narrow i32-kernel class.

Two things are commonly conflated under "AOT/LLVM"; **split them:**

| Concern | Motivation | Status / recommendation |
|---|---|---|
| **Vectorizing backend (LLVM / transpile)** — kernel *throughput* | was the 8.8–10.5× SIMD gap | **Gap closed by Phase P. Defer the structural backend; evidence-gated reopen only.** |
| **NativeAOT *image emission*** — CLI *startup / size / no-JIT / self-contained* | `nlc publish --aot` is analysis-only today | **Real product gap, separate & lower-risk track. Worth pursuing on its own merits — it does NOT change throughput.** |

The rest of this doc justifies that split and defines the gates that would reopen the vectorizing-backend bet.

## How N# generates code today

N# is a **managed-IL** language. The compiler (`src/NSharpLang.Compiler/ILCompiler/`) emits ECMA-335 IL via
`System.Reflection.Emit.PersistedAssemblyBuilder` and writes the PE with
`System.Reflection.PortableExecutable.ManagedPEBuilder` + `System.Reflection.Metadata`. The output is a normal
.NET assembly that runs on **CoreCLR / RyuJIT** (JIT today; framework-dependent).

Phase P's vectorization (`ILCompiler.Vectorization.cs`, `SimdReductions`) does **not** add a new backend — it
emits `System.Numerics.Vector<T>` IL for canonical hot-loop shapes (counted reductions, range-predicate
counts, fused min/max, seeded count-transitions). RyuJIT lowers `Vector<T>` to NEON/AVX. This is the
**.NET-recommended** way to get SIMD: RyuJIT does *not* auto-vectorize scalar loops (open since
[dotnet/runtime#11263](https://github.com/dotnet/runtime/issues/11263); the platform's stance is "expose SIMD
building blocks / `Vector<T>` / `Vector256<T>`," not a loop auto-vectorizer).

`nlc publish --aot` is **analysis-only today**: it runs AOT/trim-safety analysis and emits the usual
framework-dependent assembly (`nativeImageEmitted: false`). N# has **no native-image emission path yet** — a
relevant fact for the NativeAOT track below.

## The evidence that reframes the question

The 2026-06-06 run that motivated a structural backend found N# emitting *scalar* code, **8.8–10.5× behind
native** on the auto-vectorizable kernels — "LLVM emits SIMD, RyuJIT emits scalar." That was a real, large,
structural gap, and an LLVM backend was the obvious structural fix.

The 2026-06-07 single-machine re-run (after Phase P) measures a different world:

| Kernel (4096) | was N#/best-native (scalar) | now N#/best-native (vectorized) |
|---|---|---|
| checksum-sum | 8.78× | **2.02×** |
| count-ascii | 6.30× | **1.63×** |
| count-transitions | 4.54× | **1.97×** |
| min-max-delta | 10.5× | **1.67×** |
| rolling-hash (not vectorizable) | 1.61× | 1.62× |
| parse-eight-digits (already fast) | 1.84× | 1.80× |

The 8–10× gaps are gone. **The structural backend's original prize no longer exists.** What remains is a
~1.6–2× residual that is *not* a SIMD-vs-scalar gap — it is the latency-bound floor (rolling-hash), tiny-input
fixed overhead (min-max-delta @64 = 2.49×), and RyuJIT lowering its `Vector<T>` with less unrolling/scheduling
than LLVM. A new backend would chase that residual, not an order-of-magnitude win.

## Candidate backends (technical analysis)

### A. Stay on RyuJIT + per-pattern `Vector<T>` emission — *status quo (Phase P)*
- **What it gives:** SIMD on the matched shapes, on the existing runtime, with zero new toolchain. Already at
  ≤2.0× native on every vectorizable kernel.
- **Ceiling:** RyuJIT's `Vector<T>` lowering (unroll factor, scheduling, horizontal-reduce) and the
  no-loop-auto-vectorizer policy. Extending to new shapes is incremental and low-risk but only matters where a
  *measured* kernel needs it.
- **Cost/risk:** low. Each pattern is a focused, parity-gated ILCompiler change.

### B. NativeAOT (ILC + RyuJIT codegen)
- **What it gives:** native image — fast startup, no JIT warmup, smaller self-contained deploy, trimming.
  Directly relevant to **CLI startup** and `nlc publish --aot` (today analysis-only).
- **What it does NOT give:** *throughput on these kernels.* NativeAOT's code generator **is RyuJIT** (the
  CoreRT-derived ILC invokes RyuJIT ahead-of-time). It has the **same** no-loop-auto-vectorization behavior —
  a `Vector<T>` kernel JITs and AOT-compiles to the same SIMD; a scalar loop stays scalar either way. So
  NativeAOT changes the *startup/size* story, **not** the native-throughput gap.
- **Cost/risk:** moderate, well-trodden. AOT-safety analysis already exists; the missing piece is image
  emission + the trim/reflection discipline N# already surfaces (`NSYS060`).
- **Verdict:** **pursue on its own merits as a separate startup/size track** — but do not expect it to move
  the throughput numbers in `systems-vs-native.md`.

### C. NativeAOT-LLVM (dotnet/runtimelab)
- **What it is:** the only "LLVM-for-.NET" codegen path. **Experimental**, primarily **browser-wasm / WASI**
  targeted; large bundles (~95 MB, ~40 MB stripped), known delegate-marshalling and stability issues; not a
  supported desktop/CLI native-codegen backend. (See dotnet/runtimelab `feature/NativeAOT-LLVM`.)
- **Verdict:** **not viable** as a production backend for a desktop/CLI compiler. Track upstream; do not adopt.

### D. Custom LLVM IR emission for the systems subset
- **What it gives:** real LLVM auto-vectorization + unrolling + scheduling on `[hot]` kernels — the only path
  that *structurally* beats RyuJIT's `Vector<T>` lowering.
- **Cost/risk:** **very high, multi-quarter.** Requires: an LLVM-IR emitter for the systems subset; a
  managed↔native ABI/marshaling boundary (managed arrays/spans, GC pinning/safepoints, exceptions); a
  `libLLVM`/`llc` (or Cranelift) **build-time native-toolchain dependency shipped in the CLI** across
  win/mac/linux × x64/arm64; a debugging/diagnostics story; and a second correctness-critical codegen path to
  maintain in lockstep with the IL path. All to chase a ~2× → ~1.3× residual on i32 micro-kernels.
- **Verdict:** **not justified now.** The cost/prize ratio is backwards post-Phase-P.

### E. Source transpile of `[hot]` kernels to Rust/C/Zig + P/Invoke
- **What it gives:** LLVM-class codegen "for free" via the native compiler.
- **Cost/risk:** **high and structurally awkward.** A P/Invoke/marshaling boundary per kernel call (would
  *eat* the small-input wins — the 64-size cells are already overhead-dominated); a native toolchain in the
  CLI build; GC/managed-array interop and pinning hazards; supply-chain/security surface; two source languages
  to keep value-identical. Defeats the "compiler written in N#" dogfood goal for the very hottest paths.
- **Verdict:** **not justified.** Strictly worse than D for a managed-array kernel class.

## Decision matrix

| Option | Throughput win vs today | Effort | Risk | New runtime dep | Recommend |
|---|---|---|---|---|---|
| A. RyuJIT + `Vector<T>` (status quo) | baseline (≤2.0× native) | — | — | none | **Yes — keep, extend only on measured need** |
| B. NativeAOT image emission | none (startup/size only) | moderate | low–moderate | none (RyuJIT) | **Yes — separate startup/size track** |
| C. NativeAOT-LLVM | n/a (WASM, experimental) | — | very high | experimental | No |
| D. Custom LLVM IR backend | ~2× → ~1.3× residual only | very high | very high | LLVM toolchain | **No (defer; evidence-gated)** |
| E. Transpile to Rust/C/Zig | LLVM-class but marshaling-taxed | high | high | native toolchain | No |

## Recommendation

1. **Keep option A.** Per-pattern `Vector<T>` is the right approach for this runtime and already won the prize.
   Extend to a new shape *only when a measured, shipping hot path needs it* — not speculatively.
2. **Defer the vectorizing structural backend (D/E).** Reopen only against the evidence gates below.
3. **Treat NativeAOT image emission (B) as a separate, independently-justified track** for CLI
   startup/size/self-contained deploy — the real gap behind `nlc publish --aot`'s analysis-only state. It is
   lower-risk (RyuJIT-based) and orthogonal to throughput; do not bundle it into the LLVM decision.
4. **Sharpen evidence cheaply first:** broaden the comparison corpus from synthetic i32 kernels to a **real
   compiler hot path** (token scan, symbol-table probe, columnar pass) so any remaining gap is measured on the
   code we actually ship in N#, not micro-kernels. This is the cheapest, highest-value next perf step and is a
   precondition for reopening D.

## Evidence gates that would reopen the vectorizing-backend bet (D)

Reopen P4-as-LLVM only if **at least one** is demonstrated with measurements:

- **G1 — structural, not residual:** a broadened real-hot-path corpus shows a **>3×** N#-vs-best-native gap on
  code we intend to ship in N#, *and* a focused `Vector<T>` attempt provably cannot reach ~2× (i.e., the shape
  is not expressible as a matched SIMD pattern). The current i32 residual (≤2×) does **not** meet this bar.
- **G2 — float / non-associative throughput** becomes a shipping requirement (FP reductions are deliberately
  excluded from `Vector<T>` emission for associativity reasons; LLVM with `-ffast-math`-style relaxations
  could, with explicit opt-in, but that is a language-semantics decision, not just a backend).
- **G3 — a target platform** requires no-JIT startup **and** kernel throughput that NativeAOT (B, RyuJIT) is
  measured to cap below requirements — i.e., B is adopted and then shown insufficient on throughput.
- **G4 — RyuJIT's `Vector<T>` lowering is measured to cap** a shipping compiler hot path well above 2× with no
  pattern-level remedy (distinct from G1: this is about lowering quality, not pattern coverage).

Absent a gate, the per-pattern path (A) plus the NativeAOT startup track (B) is the correct, evidence-backed
plan, and `P4`-as-LLVM stays deferred.
