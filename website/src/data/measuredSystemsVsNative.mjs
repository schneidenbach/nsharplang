// The single checked-in measured-results source for every perf number the site shows.
//
// Transcribed VERBATIM from the authoritative table in docs/design/systems-vs-native.md
// ("Numbers — rigorous single-machine re-run (2026-06-07; vectorized N#)"). Do not edit
// these values by hand to be more flattering, and do not recompute or re-round them:
// re-run the benchmarks, update the design doc, then update this transcription.
// website/src/lib/perfCourse.test.mjs pins perfTelemetry.mjs to this fixture AND pins
// this fixture's values to the design doc text, so site copy cannot silently drift.
export const measuredRun = {
  source: 'docs/design/systems-vs-native.md',
  run: 'rigorous single-machine re-run, 2026-06-07 (vectorizing N# compiler, Phase P default-on)',
  machine: 'Apple M4 · .NET 10 / RyuJIT · rustc 1.96.0 · Apple clang 17 (-O3)',
  // ns/op (lower = faster), straight from the table, three decimals as printed.
  workloads: {
    'checksum-sum': {
      64: { nsharp: 4.219, csharp: 16.524, rust: 2.634, c: 2.256 },
      4096: { nsharp: 222.625, csharp: 982.916, rust: 111.272, c: 110.180 },
    },
    'count-ascii': {
      64: { nsharp: 5.291, csharp: 18.934, rust: 3.388, c: 3.369 },
      4096: { nsharp: 298.051, csharp: 1174.088, rust: 183.151, c: 183.020 },
    },
    'count-transitions': {
      64: { nsharp: 11.368, csharp: 17.027, rust: 7.012, c: 6.702 },
      4096: { nsharp: 477.331, csharp: 1069.094, rust: 241.827, c: 245.100 },
    },
    'min-max-delta': {
      64: { nsharp: 11.130, csharp: 23.699, rust: 4.474, c: 8.602 },
      4096: { nsharp: 253.578, csharp: 1496.034, rust: 155.317, c: 151.840 },
    },
    'rolling-hash': {
      64: { nsharp: 42.251, csharp: 41.707, rust: 29.655, c: 31.265 },
      4096: { nsharp: 4695.715, csharp: 4708.774, rust: 2889.787, c: 3066.720 },
    },
    'parse-eight-digits': {
      64: { nsharp: 2.787, csharp: 4.159, rust: 1.546, c: 1.554 },
      4096: { nsharp: 2.776, csharp: 4.145, rust: 1.546, c: 1.552 },
    },
  },
  // The kernels where the N# systems lane emits Vector<T> and beats the C# scalar baseline.
  vectorizedKernels: ['checksum-sum', 'count-ascii', 'count-transitions', 'min-max-delta'],
};
