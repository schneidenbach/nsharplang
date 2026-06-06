// Faithful standalone Rust micro-bench for the N# `checksum` hot-path workload.
//
// Workload (matches benchmarks/SystemsHotPathBenchmarks.cs:14-23 N# `checksum`,
// and the C# baseline CSharpChecksum at :339-349):
//
//     sum := 0
//     len := values.Length
//     for i := 0; i < len; i++ { sum = sum + values[i] }
//     return sum
//
// Wrapping (two's-complement) i32 add, exactly like C# `unchecked int`.
//
// Input fill (identical bytes to the N# GlobalSetup at :271-284), applied in
// this exact order:
//   (a) for i in 0..N: values[i] = ((i*17)+3) & 0x7f
//   (b) if N >= 17:    values[N-17] = 100003
//   (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
//
// Methodology: build array once outside the timed loop, warmup, then a fixed
// MEASURED loop of ITERS kernel invocations over the SAME pre-built array.
// black_box the input pointer and the result each iteration so -O3 cannot
// constant-fold/hoist; xor-fold result into a sink that is printed at the end.
// Repeat 15 trials, report median (also min + IQR) ns/op per size.

use std::hint::black_box;
use std::time::Instant;

/// The workload under test. Single function over the whole length-N array,
/// returning the i32 sum with wrapping add (C# unchecked semantics).
/// Safe slice indexing is kept (bounds-checked) to mirror what the N#/C# JIT
/// would also bounds-check; the JIT elides those, and LLVM elides ours too for
/// the `0..len` counted loop, so this is the apples-to-apples "safe" number.
#[inline(never)]
fn checksum(values: &[i32]) -> i32 {
    let mut sum: i32 = 0;
    let len = values.len();
    let mut i = 0usize;
    while i < len {
        sum = sum.wrapping_add(values[i]);
        i += 1;
    }
    sum
}

/// Deterministic fill identical to the N#/C# benchmark GlobalSetup.
fn build_values(n: usize) -> Vec<i32> {
    let mut values = vec![0i32; n];
    // (a)
    for i in 0..n {
        values[i] = (((i as i32).wrapping_mul(17)).wrapping_add(3)) & 0x7f;
    }
    // (b)
    if n >= 17 {
        values[n - 17] = 100_003;
    }
    // (c)
    let m = if n < 8 { n } else { 8 };
    for i in 0..m {
        values[i] = 48 + (i as i32 % 10);
    }
    values
}

fn median(sorted: &[f64]) -> f64 {
    let n = sorted.len();
    if n % 2 == 1 {
        sorted[n / 2]
    } else {
        (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }
}

fn percentile(sorted: &[f64], p: f64) -> f64 {
    // Nearest-rank on a 0..n-1 index scale.
    let n = sorted.len();
    if n == 0 {
        return 0.0;
    }
    let idx = (p * (n as f64 - 1.0)).round() as usize;
    sorted[idx.min(n - 1)]
}

fn run_size(key: &str, n: usize, iters: u64, warmup: u64, trials: usize) {
    let values = build_values(n);
    let mut sink: i64 = 0;

    let mut samples: Vec<f64> = Vec::with_capacity(trials);

    for _ in 0..trials {
        // Warmup (feed results into sink so it isn't elided).
        for _ in 0..warmup {
            let v: &[i32] = black_box(&values[..]);
            let r = checksum(v);
            sink ^= black_box(r) as i64;
        }

        // Measured loop.
        let start = Instant::now();
        for _ in 0..iters {
            let v: &[i32] = black_box(&values[..]);
            let r = checksum(v);
            sink ^= black_box(r) as i64;
        }
        let elapsed = start.elapsed();
        let ns_per_op = elapsed.as_nanos() as f64 / iters as f64;
        samples.push(ns_per_op);
    }

    samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let med = median(&samples);
    let min = samples[0];
    let q1 = percentile(&samples, 0.25);
    let q3 = percentile(&samples, 0.75);

    // Keep the sink observably live.
    black_box(sink);
    eprintln!(
        "# {} size={} sink={} min={:.3} q1={:.3} q3={:.3} iqr={:.3} trials={}",
        key,
        n,
        sink,
        min,
        q1,
        q3,
        q3 - q1,
        trials
    );

    // Required machine-readable line: "<key> <size> <median_ns_per_op>"
    println!("{} {} {:.3}", key, n, med);
}

fn main() {
    let key = "checksum-sum";
    let trials = 15usize;
    let warmup: u64 = 100_000;

    // Size 64: ITERS = 2_000_000 (>= ~200ms total at this scale).
    run_size(key, 64, 2_000_000, warmup, trials);
    // Size 4096: ITERS = 50_000.
    run_size(key, 4096, 50_000, warmup, trials);
}
