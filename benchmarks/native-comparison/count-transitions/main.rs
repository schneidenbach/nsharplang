// Faithful standalone Rust micro-bench for the N# `countTransitions` workload.
//
// Mirrors benchmarks/SystemsHotPathBenchmarks.cs:118-137 (N# `countTransitions`)
// and the C# baseline at benchmarks/SystemsHotPathBenchmarks.cs:458-480.
//
// Algorithm (byte-for-byte):
//   if values.Length == 0 { return 0 }
//   transitions := 0
//   previous := values[0]
//   len := values.Length
//   for i := 1; i < len; i++ {
//       current := values[i]
//       if current != previous { transitions = transitions + 1 }
//       previous = current
//   }
//   return transitions
//
// Build (release-equivalent):
//   rustc -O -C opt-level=3 -C codegen-units=1 -C lto=fat -o /tmp/count-transitions_rs main.rs
// or via cargo with the bench profile (opt-level=3, codegen-units=1, lto="fat").
//
// Protocol: deterministic identical fill, build array once, warmup, fixed measured
// loop timed with std::time::Instant, xor-fold every result into a black_box'd sink,
// repeat 15 trials and report MEDIAN ns/op (plus min + IQR). Print sink so the whole
// chain stays observably live under -O3.

use std::hint::black_box;
use std::time::Instant;

const KEY: &str = "count-transitions";
const SIZES: [usize; 2] = [64, 4096];
const TRIALS: usize = 15;

/// Deterministic fill identical to the N# bench (same as checksum-sum):
///   (a) for i in 0..N: values[i] = ((i*17)+3) & 0x7f
///   (b) if N >= 17: values[N-17] = 100003
///   (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
fn build_input(n: usize) -> Vec<i32> {
    let mut values = vec![0i32; n];
    for i in 0..n {
        values[i] = (((i as i32).wrapping_mul(17)).wrapping_add(3)) & 0x7f;
    }
    if n >= 17 {
        values[n - 17] = 100003;
    }
    let c = if n < 8 { n } else { 8 };
    for i in 0..c {
        values[i] = 48 + (i as i32 % 10);
    }
    values
}

/// The workload under test. Safe slice indexing (bounds checks kept) — reported as
/// the safe-indexing number, mirroring how N#/C# emit JIT-bounds-checked loops.
#[inline(never)]
fn count_transitions(values: &[i32]) -> i32 {
    if values.len() == 0 {
        return 0;
    }
    let mut transitions: i32 = 0;
    let mut previous: i32 = values[0];
    let len = values.len();
    let mut i = 1usize;
    while i < len {
        let current = values[i];
        if current != previous {
            transitions = transitions.wrapping_add(1);
        }
        previous = current;
        i += 1;
    }
    transitions
}

fn iters_for(size: usize) -> u64 {
    // Total measured time per (kernel,size) >= ~200 ms.
    match size {
        64 => 2_000_000,
        _ => 50_000,
    }
}

const WARMUP_ITERS: u64 = 100_000;

fn percentile(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return f64::NAN;
    }
    let idx = ((sorted.len() as f64 - 1.0) * p).round() as usize;
    sorted[idx]
}

fn main() {
    // Global sink kept observably live: printed at the very end.
    let mut sink: i64 = 0;

    for &size in SIZES.iter() {
        let values = build_input(size);
        let iters = iters_for(size);

        let mut samples: Vec<f64> = Vec::with_capacity(TRIALS);

        for _ in 0..TRIALS {
            // Warmup (fed into sink so it isn't elided).
            for _ in 0..WARMUP_ITERS {
                let r = count_transitions(black_box(&values[..]));
                sink ^= black_box(r) as i64;
            }

            // Measured loop over the SAME pre-built array.
            let start = Instant::now();
            for _ in 0..iters {
                let r = count_transitions(black_box(&values[..]));
                sink ^= black_box(r) as i64;
            }
            let elapsed_ns = start.elapsed().as_nanos() as f64;
            samples.push(elapsed_ns / iters as f64);
        }

        samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let median = percentile(&samples, 0.5);
        let min = samples[0];
        let q1 = percentile(&samples, 0.25);
        let q3 = percentile(&samples, 0.75);
        let iqr = q3 - q1;

        // Required machine-readable line: "<key> <size> <median_ns_per_op>".
        println!("{} {} {:.3}", KEY, size, median);
        // Stability detail to stderr so stdout stays clean for the parser.
        eprintln!(
            "{} {} median={:.3} min={:.3} iqr={:.3} (q1={:.3} q3={:.3}) ns/op trials={}",
            KEY, size, median, min, iqr, q1, q3, TRIALS
        );
    }

    // Anti-DCE: observe the whole accumulated chain.
    println!("sink {}", sink);
}
