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
