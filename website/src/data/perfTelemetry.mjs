// Measured cross-language telemetry for the "High Performance from Scratch" course.
//
// SOURCE OF TRUTH: docs/design/systems-vs-native.md — the rigorous single-machine re-run
// of 2026-06-07 (vectorizing N# compiler, Phase P default-on). Every ns/op figure below is
// imported from ./measuredSystemsVsNative.mjs, the verbatim transcription of that table;
// the freshness test in website/src/lib/perfCourse.test.mjs pins both to the design doc.
// These are REAL measured numbers — do not edit them to be more flattering. The honesty
// bar mirrors the design doc: N# ties C# (RyuJIT) within noise on the non-vectorizable
// kernels, beats C# ~2–6× on the vectorizable kernels now that the systems lane emits
// System.Numerics.Vector<T>, and still TRAILS Rust/C — ≤2.02× at 4096, worst small-input
// cell 2.49× — because of RyuJIT-vs-LLVM codegen, not anything N#-specific. We never
// claim "as fast as Rust."

import {measuredRun} from './measuredSystemsVsNative.mjs';

const speedAt = (kernel, size) => ({...measuredRun.workloads[kernel][size], unit: 'ns/op'});
const smallSizeOf = (kernel) => ({size: 64, ...measuredRun.workloads[kernel][64]});

export const telemetryMeta = {
  machine: 'Apple M4',
  runtime: '.NET 10 · RyuJIT',
  native: 'rustc 1.96.0 · Apple clang 17 (-O3)',
  method:
    'N# / C# measured with BenchmarkDotNet (short job); Rust / C with hand-rolled micro-benchmarks ' +
    '(median-of-medians, black_box / inline-asm volatile barriers so -O3 cannot hoist the work).',
  measured: 'June 2026 (single-machine re-run, 2026-06-07)',
  reproduce: 'benchmarks/native-comparison/ + benchmarks/SystemsHotPathBenchmarks.cs',
  caveats: [
    'Single ARM / M4 machine — x64 auto-vectorization ratios can differ.',
    'Mixed instruments: BenchmarkDotNet carries ~1–2 ns/op of harness overhead, material only on the sub-5 ns rows.',
    'A narrow set of synthetic i32-array kernels at two sizes, chosen to probe scalar codegen — not a representative application or compiler hot path. Do not generalize these to "N# is N× slower than Rust" across the board.',
  ],
};

// Display order + colors for the four languages on every speed chart.
export const languageOrder = [
  { key: 'nsharp', label: 'N#' },
  { key: 'csharp', label: 'C#' },
  { key: 'rust', label: 'Rust' },
  { key: 'c', label: 'C' },
];

// ns/op (lower = faster). size is the array length the row was measured at.
// `vectorized` marks the kernels where N# now emits SIMD and beats the C# scalar baseline.
// Every `memory` block tells the honest allocation story for that concept.
export const kernels = {
  'checksum-sum': {
    label: 'Sum reduction',
    blurb: 'Add every element of a 4096-element int array (a checksum).',
    size: 4096,
    speed: speedAt('checksum-sum', 4096),
    smallSize: smallSizeOf('checksum-sum'),
    vectorized: true,
    headline: 'N# auto-vectorizes the reduction → 4.4× faster than the C# scalar baseline.',
    detail:
      'Before the systems lane emitted SIMD, N# tied C# and both ran scalar — ~8.8× behind LLVM. ' +
      'N# now emits System.Numerics.Vector<T> for the counted reduction, closing the native gap to 2.02×.',
    memory: {
      nsharp: 0, csharp: 0, rust: 0, c: 0, unit: 'B/op',
      measured: true,
      note: 'Pure stack loop — zero heap allocation in all three languages. The speed gap here is pure codegen, not memory pressure.',
    },
  },
  'count-ascii': {
    label: 'Range-predicate count',
    blurb: 'Count how many bytes fall in the printable-ASCII range [32, 126] over 4096 elements.',
    size: 4096,
    speed: speedAt('count-ascii', 4096),
    smallSize: smallSizeOf('count-ascii'),
    vectorized: true,
    headline: 'A masked-SIMD count → 3.9× faster than C#, 1.63× behind native.',
    detail:
      'The "is this value in [lo, hi]?" test vectorizes into packed compares + a masked accumulate. ' +
      'LLVM did this automatically; RyuJIT ran it scalar. N# now emits the masked-SIMD count itself.',
    memory: {
      nsharp: 0, csharp: 0, rust: 0, c: 0, unit: 'B/op',
      measured: true,
      note: 'Zero allocation in all three — the predicate count is register-resident.',
    },
  },
  'min-max-delta': {
    label: 'Min / max delta',
    blurb: 'Find (max − min) over 4096 elements in one sweep.',
    size: 4096,
    speed: speedAt('min-max-delta', 4096),
    smallSize: smallSizeOf('min-max-delta'),
    vectorized: true,
    headline: 'Fused single-pass Vector.Min / Vector.Max → 5.9× faster than C#, 1.67× behind native.',
    detail:
      'This was N#’s single largest native gap (10.5× behind LLVM, scalar). Min and max are ' +
      'associative + commutative, so they vectorize — and the fused kernel loads each vector once ' +
      'and feeds both the min and max accumulators in a single sweep. The worst remaining cell in ' +
      'the whole suite is this kernel at 64 elements (2.49× behind native), where fixed SIMD setup ' +
      'dominates the tiny input; at 4096 it is 1.67×.',
    memory: {
      nsharp: 0, csharp: 0, rust: 0, c: 0, unit: 'B/op',
      measured: true,
      note: 'Two running scalars, no allocation. Vectorizing kept the memory profile identical and cut the time.',
    },
  },
  'count-transitions': {
    label: 'Adjacent transitions',
    blurb: 'Count how many times a value differs from the one before it, over 4096 elements.',
    size: 4096,
    speed: speedAt('count-transitions', 4096),
    smallSize: smallSizeOf('count-transitions'),
    vectorized: true,
    headline: 'A seeded shifted-compare SIMD count → 2.2× faster than C#, 1.97× behind native.',
    detail:
      'Each step compares element i with i−1, which looks serial — but the dependency is on the ' +
      'input array, not the previous iteration’s result. Comparing the array against itself shifted ' +
      'by one element turns it into packed compare-not-equal lanes with a masked accumulate, so it ' +
      'vectorizes after all. RyuJIT alone leaves it scalar; N# emits the shifted-compare kernel itself.',
    memory: {
      nsharp: 0, csharp: 0, rust: 0, c: 0, unit: 'B/op',
      measured: true,
      note: 'No allocation anywhere; the cost is per-iteration loads and branch misprediction, not memory.',
    },
  },
  'rolling-hash': {
    label: 'Rolling hash',
    blurb: 'Fold 4096 elements into one hash where each step depends on the last.',
    size: 4096,
    speed: speedAt('rolling-hash', 4096),
    smallSize: smallSizeOf('rolling-hash'),
    vectorized: false,
    headline: 'The floor: a carried dependency can’t parallelize — N# sits ~1.5× off native, right at the CLR limit.',
    detail:
      'Iteration N needs iteration N−1’s result (multiply + mask), so there are no independent lanes to ' +
      'fill — nothing for SIMD to do in any language. The residual ~1.4–1.6× is register-allocation and ' +
      'scheduling, the smallest gap in the suite. N# ties C# and is close to the best a CLR JIT can do.',
    memory: {
      nsharp: 0, csharp: 0, rust: 0, c: 0, unit: 'B/op',
      measured: true,
      note: 'A single accumulator in a register — zero allocation.',
    },
  },
};

// Module id -> kernel key. Modules without a dedicated measured kernel are null and lean
// on the qualitative cost-model framing (boxing / dispatch) instead of a ns chart.
export const moduleKernel = {
  'memory-is-the-machine': 'checksum-sum',
  'heap-and-stack': 'checksum-sum',
  'counting-and-branches': 'count-ascii',
  'simd-many-at-once': 'min-max-delta',
  'bounds-checks-and-safety': 'count-transitions',
  'latency-vs-throughput': 'rolling-hash',
  'boxing-and-dispatch': null,
  'the-systems-lane': 'checksum-sum',
};

// Illustrative (NOT micro-benchmarked) allocation contrasts for the memory-focused modules.
// Each is a defensible lower bound, and is labeled "illustrative" in the UI so it is never
// mistaken for a measured ns/op row.
export const allocationStories = {
  'heap-and-stack': {
    title: 'Building an intermediate array vs streaming in place',
    illustrative: true,
    rows: [
      { label: 'Naive: build a doubled int[] of 4096, then sum', bytes: 16384, note: 'the result buffer alone is 4096 × 4 bytes — before List/iterator overhead' },
      { label: 'Systems N#: one [hot] foreach, accumulate in place', bytes: 0, note: 'NSYS010 proves zero heap allocation at build time' },
    ],
    unit: 'B',
    takeaway: 'Same answer, same loop count — but the streaming version never touches the heap, so the GC never has to clean up after it.',
  },
  'boxing-and-dispatch': {
    title: 'Summing through object boxes vs concrete ints',
    illustrative: true,
    rows: [
      { label: 'Boxed: each int stored as object', bytes: 98304, note: '4096 × ~24 bytes per boxed int32 (header + value + padding) — illustrative' },
      { label: 'Concrete: int accumulator, no boxing', bytes: 0, note: 'values stay in registers; NSYS020 flags any accidental box' },
    ],
    unit: 'B',
    takeaway: 'Boxing turns a free value into a heap object plus a copy, per element. Monomorphic, concrete code keeps the loop allocation-free and inlinable.',
  },
};
