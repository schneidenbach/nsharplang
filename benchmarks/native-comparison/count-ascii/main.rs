// Faithful Rust micro-bench for N# `countAscii`.
//
// Algorithm (byte-for-byte):
//   count := 0
//   len := values.Length
//   for i := 0; i < len; i++ {
//       value := values[i]
//       if value >= 32 && value <= 126 { count = count + 1 }
//   }
//   return count
//
// `&&` short-circuits; both operands are pure comparisons so the
// result is identical to a non-short-circuit AND. We keep the `&&` operator
// (Rust short-circuits it too) for exact semantic fidelity.
//
// Build: rustc -O -C opt-level=3 (release). Indexing is safe slice indexing
// `values[i]` (bounds-checked) to mirror the safe-indexing baseline; the JIT
// elides the bounds check on this counted loop, Rust/LLVM does the same for
// this shape. Reported number is the safe-indexing number.

use std::hint::black_box;
use std::time::Instant;

const SIZES: [usize; 2] = [64, 4096];
const KEY: &str = "count-ascii";

const WARMUP_ITERS: u64 = 100_000;
const TRIALS: usize = 15;

// Deterministic fill identical to the N# benchmark seed (see methodology):
//   (a) for i in 0..N: values[i] = ((i*17)+3) & 0x7f
//   (b) if N >= 17: values[N-17] = 100003
//   (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
fn build_input(n: usize) -> Vec<i32> {
    let mut values = vec![0i32; n];
    for i in 0..n {
        values[i] = (((i as i32) * 17) + 3) & 0x7f;
    }
    if n >= 17 {
        values[n - 17] = 100_003;
    }
    let m = if n < 8 { n } else { 8 };
    for i in 0..m {
        values[i] = 48 + ((i as i32) % 10);
    }
    values
}

#[inline(never)]
fn count_ascii(values: &[i32]) -> i32 {
    let mut count: i32 = 0;
    let len = values.len();
    let mut i = 0usize;
    while i < len {
        let value = values[i];
        if value >= 32 && value <= 126 {
            count = count.wrapping_add(1);
        }
        i += 1;
    }
    count
}

fn iters_for(size: usize) -> u64 {
    // Target >= ~200 ms per measured loop.
    if size <= 64 {
        2_000_000
    } else {
        50_000
    }
}

fn main() {
    let mut sink: i64 = 0;

    for &size in SIZES.iter() {
        let values = build_input(size);
        let iters = iters_for(size);

        // Warmup (folded into sink so it isn't elided).
        for _ in 0..WARMUP_ITERS {
            let r = count_ascii(black_box(&values[..]));
            sink ^= black_box(r) as i64;
        }

        let mut samples: Vec<f64> = Vec::with_capacity(TRIALS);
        for _ in 0..TRIALS {
            // Extra warmup-ish stabilization is not needed per trial, but feed
            // a few into sink to keep the array live across trials.
            let start = Instant::now();
            for _ in 0..iters {
                let r = count_ascii(black_box(&values[..]));
                sink ^= black_box(r) as i64;
            }
            let elapsed_ns = start.elapsed().as_nanos() as f64;
            samples.push(elapsed_ns / (iters as f64));
        }

        samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let median = samples[samples.len() / 2];
        let min = samples[0];
        let q1 = samples[samples.len() / 4];
        let q3 = samples[(samples.len() * 3) / 4];
        let iqr = q3 - q1;

        // Primary machine-readable line.
        println!("{} {} {:.4}", KEY, size, median);
        // Stability detail to stderr so it doesn't pollute the parseable line.
        eprintln!(
            "{} {} median={:.4} min={:.4} iqr={:.4} ns/op",
            KEY, size, median, min, iqr
        );
    }

    // Anti-DCE: print the observed sink.
    println!("sink {}", sink);
}
