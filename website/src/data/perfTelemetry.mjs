// Measured cross-language telemetry for the "High Performance from Scratch" course.
//
// SOURCE OF TRUTH: docs/design/systems-vs-native.md (the `systems-nsharp-vs-rust-c`
// workflow run, 2026-06-06) plus the 2026-06-07 auto-vectorization update. These are
// REAL measured numbers — do not edit them to be more flattering. The honesty bar here
// mirrors the design doc: N# ties C# (RyuJIT) within ~1–5% everywhere, beats C# ~3.3–4.5×
// on the vectorizable kernels now that the systems lane emits System.Numerics.Vector<T>,
// and still TRAILS Rust/C by ~1.4–3.2× because of RyuJIT-vs-LLVM codegen — not anything
// N#-specific. We never claim "as fast as Rust."

export const telemetryMeta = {
  machine: 'Apple M4',
  runtime: '.NET 10 · RyuJIT',
  native: 'rustc 1.96.0 · Apple clang 17 (-O3)',
  method:
    'N# / C# measured with BenchmarkDotNet (short job); Rust / C with hand-rolled micro-benchmarks ' +
    '(median-of-medians, black_box / inline-asm volatile barriers so -O3 cannot hoist the work).',
  measured: 'June 2026',
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
    speed: { nsharp: 222.5, csharp: 994.7, rust: 111.17, c: 114.38, unit: 'ns/op' },
    smallSize: { size: 64, nsharp: 4.19, csharp: 17.37, rust: 2.393, c: 1.964 },
    vectorized: true,
    headline: 'N# auto-vectorizes the reduction → 4.5× faster than the C# scalar baseline.',
    detail:
      'Before the systems lane emitted SIMD, N# tied C# and both ran scalar — ~8.8× behind LLVM. ' +
      'N# now emits System.Numerics.Vector<T> for the counted reduction, closing the native gap to ~2×.',
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
    speed: { nsharp: 296.4, csharp: 1172.9, rust: 183.86, c: 185.68, unit: 'ns/op' },
    smallSize: { size: 64, nsharp: 5.28, csharp: 18.36, rust: 3.362, c: 3.336 },
    vectorized: true,
    headline: 'A masked-SIMD count → 4.0× faster than C#, ~1.6× behind native.',
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
    speed: { nsharp: 468.0, csharp: 1535.3, rust: 150.57, c: 139.76, unit: 'ns/op' },
    smallSize: { size: 64, nsharp: 16.79, csharp: 23.55, rust: 4.09, c: 8.11 },
    vectorized: true,
    headline: 'Lane-wise Vector.Min / Vector.Max → 3.28× faster than C#.',
    detail:
      'This was N#’s single largest native gap (10.5× behind LLVM, scalar). Min and max are ' +
      'associative + commutative, so they vectorize. The remaining ~3.2× is the two-pass cost ' +
      '(min and max each re-scan); a fused single-pass kernel is the planned follow-up.',
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
    speed: { nsharp: 1132.37, csharp: 1133.75, rust: 249.65, c: 249.64, unit: 'ns/op' },
    smallSize: { size: 64, nsharp: 16.81, csharp: 16.85, rust: 7.199, c: 6.872 },
    vectorized: false,
    headline: 'Honest gap: N# ties C# but trails native ~4.5× — this shape does not vectorize cleanly.',
    detail:
      'Each step reads element i and i−1 and branches — an indexed-load + branch tax that scales with ' +
      'size and does not match a reduction or masked-count pattern. N# is CLR-fast (ties C#) but still ' +
      'behind LLVM here, and we tell you exactly why instead of hiding it.',
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
    speed: { nsharp: 4613.06, csharp: 4614.47, rust: 2862.21, c: 2867.10, unit: 'ns/op' },
    smallSize: { size: 64, nsharp: 43.12, csharp: 40.90, rust: 29.97, c: 30.30 },
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
