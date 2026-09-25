// Faithful standalone Rust micro-bench for the N# `parseEightDigits` workload.
//
// N# source:
//   func parseEightDigits(values: int[]): int {
//       if values.Length < 8 { return -1 }
//       parsed := 0
//       for i := 0; i < 8; i++ {
//           value := values[i]
//           if value < 48 || value > 57 { return -1 }
//           parsed = parsed * 10 + (value - 48)
//       }
//       return parsed
//   }
//
// O(1) workload: fixed trip count of 8 regardless of N. ns/op should be
// ~size-independent across 64 and 4096; reporting that invariance is the point.
//
// Build: rustc -O -C opt-level=3 (release-equivalent; debug overflow checks off).
// Wrapping arithmetic is explicit to use two's-complement wrap.
// Safe slice indexing is used (no get_unchecked) to mirror the natural N#/JIT path;
// the JIT elides bounds checks for the fixed [0,8) loop, and so does rustc here.

use std::hint::black_box;
use std::time::Instant;

const KEY: &str = "parse-eight-digits";
const SIZES: [usize; 2] = [64, 4096];

const WARMUP_ITERS: u64 = 1_000_000;
const MEASURED_ITERS: u64 = 20_000_000;
const TRIALS: usize = 15;

#[inline(never)]
fn parse_eight_digits(values: &[i32]) -> i32 {
    if values.len() < 8 {
        return -1;
    }

    let mut parsed: i32 = 0;
    for i in 0..8 {
        let value = values[i];
        if value < 48 || value > 57 {
            return -1;
        }
        // parsed = parsed * 10 + (value - 48)  (unchecked / wrapping)
        parsed = parsed
            .wrapping_mul(10)
            .wrapping_add(value.wrapping_sub(48));
    }

    parsed
}

// Deterministic fill identical to the shared methodology / N# bench input:
// (a) values[i] = ((i*17)+3) & 0x7f
// (b) if N >= 17: values[N-17] = 100003
// (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
fn build_input(n: usize) -> Vec<i32> {
    let mut v = vec![0i32; n];
    for i in 0..n {
        v[i] = (((i as i64) * 17 + 3) & 0x7f) as i32;
    }
    if n >= 17 {
        v[n - 17] = 100003;
    }
    let m = if n < 8 { n } else { 8 };
    for i in 0..m {
        v[i] = (48 + (i % 10)) as i32;
    }
    v
}

fn median(mut xs: Vec<f64>) -> f64 {
    xs.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = xs.len();
    if n % 2 == 1 {
        xs[n / 2]
    } else {
        (xs[n / 2 - 1] + xs[n / 2]) / 2.0
    }
}

fn quartile(sorted: &[f64], q: f64) -> f64 {
    // linear interpolation on sorted data
    let n = sorted.len();
    if n == 1 {
        return sorted[0];
    }
    let pos = q * ((n - 1) as f64);
    let lo = pos.floor() as usize;
    let hi = pos.ceil() as usize;
    if lo == hi {
        sorted[lo]
    } else {
        let frac = pos - lo as f64;
        sorted[lo] * (1.0 - frac) + sorted[hi] * frac
    }
}

fn main() {
    let mut sink: i64 = 0;

    for &n in SIZES.iter() {
        let values = build_input(n);

        // Warmup.
        for _ in 0..WARMUP_ITERS {
            let r = parse_eight_digits(black_box(&values[..]));
            sink ^= black_box(r) as i64;
        }

        let mut samples: Vec<f64> = Vec::with_capacity(TRIALS);
        for _ in 0..TRIALS {
            let start = Instant::now();
            for _ in 0..MEASURED_ITERS {
                let r = parse_eight_digits(black_box(&values[..]));
                sink ^= black_box(r) as i64;
            }
            let elapsed = start.elapsed();
            let ns = elapsed.as_nanos() as f64;
            samples.push(ns / MEASURED_ITERS as f64);
        }

        let med = median(samples.clone());
        let mut sorted = samples.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let mn = sorted[0];
        let q1 = quartile(&sorted, 0.25);
        let q3 = quartile(&sorted, 0.75);

        // Required machine-readable line.
        println!("{} {} {:.4}", KEY, n, med);
        // Extra stability detail to stderr so it doesn't pollute the parsed line.
        eprintln!(
            "{} {} median={:.4} min={:.4} iqr=[{:.4},{:.4}] ns/op",
            KEY, n, med, mn, q1, q3
        );
    }

    // Anti-DCE: the whole chain is observably live.
    println!("sink {}", sink);
}
