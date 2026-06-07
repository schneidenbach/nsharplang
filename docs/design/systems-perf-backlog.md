# Systems performance backlog — closing the N#-vs-Rust/C gap

**Status:** Backlog. Deferred by decision on 2026-06-06 ("finish self-host and sharpen evidence first;
backlog these"). The evidence motivating these is [`systems-vs-native.md`](systems-vs-native.md): systems-N#
ties C#/RyuJIT but trails Rust/C by 1.4×–10.5×, entirely due to RyuJIT's missing auto-vectorization /
unrolling. These two bets are how "top-of-class systems, as fast as Rust" becomes a *truthful* claim rather
than a CLR-relative one. Do NOT start without an explicit go-ahead — they are large.

## Backlog item A — Auto-vectorization + unrolling in the N# systems codegen (incremental bet)

**Goal:** recognize canonical hot-loop shapes in the N# compiler and emit SIMD + unrolled codegen directly
(via `System.Numerics.Vector<T>` / `Vector256<T>`), instead of relying on RyuJIT (which leaves them scalar).

- Highest leverage: counted reductions `for i<len { acc += a[i] }` (checksum-sum, the 8.2–8.8× gap) and
  range-predicate counts `for i<len { if a[i] in [lo,hi] count++ }` (count-ascii, 5.7–6.3×). Projected to
  turn ~8× into ~2–3×.
- Secondary: loop unrolling (4–8×) for proven-bounds counted loops (exposes ILP even pre-SIMD); per-iteration
  bounds-check elision (count-transitions's size-scaling tax); fixed-trip-count BCE (parse-eight-digits);
  AggressiveInlining/delegate-free `[hot]` kernels (small-input call boundary).
- **Suggested first move (a spike, ~contained):** prototype `Vector<int>` emission for ONLY the reduction
  shape on checksum-sum, benchmark how much of the 8× it closes, before committing to the full pattern set.
- Risk: correctness-critical codegen change to the ILCompiler; must not regress existing codegen; needs the
  full parity + benchmark gate per pattern.

### Ceiling MEASURED (2026-06-06, Apple M4 / .NET 10, `benchmarks/VectorReductionCeilingBenchmarks.cs`)

The spike's measurement, done before any codegen change — `System.Numerics.Vector<int>` reduction vs the
scalar reduction the N# codegen emits today, under the same RyuJIT the codegen targets (ratios vs scalar):

| Reduction (N=4096) | vs scalar | vs scalar (N=64) |
|---|---|---|
| scalar (today's N# codegen) | 1.00× | 1.00× |
| `Vector<int>`, single accumulator | **2.08× faster** | 3.8× faster |
| `Vector<int>`, **4 accumulators (unrolled)** | **4.5× faster** | 5.0× faster |

**Verdict: the prize is real and large — and UNROLLING is the key.** A naive single-accumulator `Vector<int>`
only reaches ~2× (ARM/NEON `Vector<int>.Count`=4, but a single accumulator is add-latency-bound). FOUR
independent accumulators reach **4.5×** by hiding latency (the trick LLVM uses for its ~8.8×). Applied to the
checksum-sum kernel (8.8× behind C/Rust), unrolled-vectorized codegen would close the gap to **≈8.8/4.5 ≈ 2×
behind native** — matching the ~2–3× projection and making the worst-case kernel top-tier for a CLR language.

**So item A is justified and is the next major Rust-perf effort.** Concrete plan: recognize the counted-
reduction shape — for the systems subset that is the `while` form `i := 0; while i < len { acc = acc + a[i];
i = i + 1 }` (the corpus uses `while`, not `for`) — and emit an unrolled (≥4 independent `Vector<int>`
accumulators) + horizontal-sum + scalar-tail loop. Safe for `int`/wrapping integer add (associative under
two's-complement wraparound, so reordering across accumulators is value-preserving); guard on no body side
effects and the array not being aliased/mutated in the loop. Gate: parity (vectorized result == scalar
result on randomized inputs) + the SystemsFastGate benchmark, per the AGENTS.md never-regress rule. This is a
large, correctness-critical ILCompiler change — its own focused effort, not folded into a self-host slice.

## Backlog item B — LLVM / NativeAOT-with-vectorizer backend for the systems subset (long-pole bet)

**Goal:** route the systems subset through a backend that already auto-vectorizes and unrolls, rather than
fighting RyuJIT's ceiling one pattern at a time (item A). The durable path to broad Rust/C parity on
vectorizable kernels.

- Framed as the long-pole, multi-phase investment — NOT a quick win. First step would be a feasibility/design
  workflow (LLVM IR emission vs NativeAOT + ILC vectorizer tuning vs an emit-to-Rust/C transpile for the
  systems subset), not code.
- Trade-off vs item A: A is incremental and ships value per-pattern on the existing CLR runtime; B is a
  bigger architectural lift but removes the ceiling structurally. Likely sequence: do A's spike to learn the
  ceiling, then decide whether B is warranted.

## When revisiting

Re-read [`systems-vs-native.md`](systems-vs-native.md) and re-run the harness (numbers are machine-specific;
the recorded run is Apple M4 / rustc 1.96 / Apple clang 17). Before either bet, finish the cheaper
evidence-sharpening: broaden the comparison corpus from synthetic i32 kernels to a real compiler hot path
(token scan, symbol-table probe) so the gap is measured on code we actually intend to ship in N#.
