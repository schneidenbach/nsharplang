// Faithful standalone Rust micro-bench for the N# `minMaxDelta` workload.
//
// Mirrors the N# `minMaxDelta` workload:
//
//   if values.Length == 0 { return 0 }
//   min := values[0]; max := values[0]; len := values.Length
//   for i := 1; i < len; i++ {
//       value := values[i]
//       if value < min { min = value }
//       if value > max { max = value }
//   }
//   return max - min   (wrapping i32 subtraction)
//
// Two independent branchy compares per element are kept verbatim (no branchless
// min/max intrinsics) so the compared codegen shape matches N#.
//
// Methodology: deterministic fill identical to checksum-sum, build array once,
// warmup, fixed measured loop, xor-fold into a black_box'd sink, 15+ trials,
// report median ns/op (also min + IQR). Safe slice indexing is used (reported as
// the safe-indexing number) to mirror what the JIT naturally elides.
//
// Build: rustc -O -C opt-level=3   (or cargo --release with codegen-units=1, lto=fat)

use std::hint::black_box;
use std::time::Instant;

const KEY: &str = "min-max-delta";
const SIZES: [usize; 2] = [64, 4096];

const WARMUP_ITERS: u64 = 100_000;
const TRIALS: usize = 21;

// ITERS chosen so each measured loop runs >= ~200 ms.
fn iters_for(size: usize) -> u64 {
    match size {
        64 => 2_000_000,
        4096 => 50_000,
        _ => 1_000_000,
    }
}

/// Deterministic fill, identical order to the checksum-sum / N# bench fill.
fn build_values(n: usize) -> Vec<i32> {
    let mut values = vec![0i32; n];
    // (a) for i in 0..N: values[i] = ((i*17)+3) & 0x7f
    for i in 0..n {
        values[i] = (((i as i32).wrapping_mul(17)).wrapping_add(3)) & 0x7f;
    }
    // (b) if N >= 17: values[N-17] = 100003
    if n >= 17 {
        values[n - 17] = 100003;
    }
    // (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
    let m = if n < 8 { n } else { 8 };
    for i in 0..m {
        values[i] = 48 + (i as i32 % 10);
    }
    values
}

/// The workload under test, byte-for-byte per the N# algorithm.
#[inline(never)]
fn min_max_delta(values: &[i32]) -> i32 {
    if values.len() == 0 {
        return 0;
    }

    let mut min = values[0];
    let mut max = values[0];
    let len = values.len();
    let mut i = 1usize;
    while i < len {
        let value = values[i];
        if value < min {
            min = value;
        }
        if value > max {
            max = value;
        }
        i += 1;
    }

    max.wrapping_sub(min)
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = v.len();
    if n % 2 == 1 {
        v[n / 2]
    } else {
        (v[n / 2 - 1] + v[n / 2]) / 2.0
    }
}

fn quantile_sorted(v: &[f64], q: f64) -> f64 {
    // Linear interpolation on an already-sorted slice.
    let n = v.len();
    if n == 1 {
        return v[0];
    }
    let pos = q * (n as f64 - 1.0);
    let lo = pos.floor() as usize;
    let hi = pos.ceil() as usize;
    if lo == hi {
        v[lo]
    } else {
        let frac = pos - lo as f64;
        v[lo] * (1.0 - frac) + v[hi] * frac
    }
}

fn main() {
    let mut sink: i64 = 0;

    for &size in SIZES.iter() {
        let values = build_values(size);
        let iters = iters_for(size);

        let mut samples: Vec<f64> = Vec::with_capacity(TRIALS);

        for _ in 0..TRIALS {
            // Warmup (results folded into sink so it isn't elided).
            for _ in 0..WARMUP_ITERS {
                let r = min_max_delta(black_box(&values[..]));
                sink ^= black_box(r) as i64;
            }

            // Measured loop.
            let start = Instant::now();
            for _ in 0..iters {
                let r = min_max_delta(black_box(&values[..]));
                sink ^= black_box(r) as i64;
            }
            let elapsed = start.elapsed();

            let ns_per_op = elapsed.as_nanos() as f64 / iters as f64;
            samples.push(ns_per_op);
        }

        let med = median(samples.clone());
        let mut sorted = samples.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let min_v = sorted[0];
        let q1 = quantile_sorted(&sorted, 0.25);
        let q3 = quantile_sorted(&sorted, 0.75);
        let iqr = q3 - q1;

        // Required one-line-per-size machine-readable output.
        println!("{} {} {:.4}", KEY, size, med);
        // Human-readable stability line on stderr.
        eprintln!(
            "{} {} median={:.4} min={:.4} iqr={:.4} (q1={:.4} q3={:.4}) iters={} trials={}",
            KEY, size, med, min_v, iqr, q1, q3, iters, TRIALS
        );
    }

    // Print sink so the whole chain is observably live (defeats DCE).
    println!("sink {}", sink);
}
