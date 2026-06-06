// Faithful standalone Rust micro-bench for the N# `rollingHash` kernel.
//
// N# source (benchmarks/SystemsHotPathBenchmarks.cs:88-97):
//   func rollingHash(values: int[]): int {
//       hash := 17
//       len := values.Length
//       for i := 0; i < len; i++ {
//           hash = ((hash * 31) + values[i]) & 65535
//       }
//       return hash
//   }
// C# baseline (benchmarks/SystemsHotPathBenchmarks.cs:424-434) is identical.
//
// Apples-to-apples protocol: build the input arrays ONCE, warm up, then time a
// fixed iteration count of the EXACT kernel, xor-folding every result into a
// black_box'd sink so -O3 cannot eliminate the work. Report median ns/op over
// trials (also min + IQR). Print sink at the end so the chain stays live.
//
// Build:
//   rustc -O -C opt-level=3 -C codegen-units=1 -C lto=fat -o /tmp/rolling-hash_rs main.rs
// (compile-check in this task uses: rustc -O -C opt-level=3 -o /tmp/rolling-hash_rs main.rs)

use std::hint::black_box;
use std::time::Instant;

/// Deterministic fill identical to the N#/C# bench input.
/// (a) values[i] = ((i*17)+3) & 0x7f
/// (b) if N >= 17: values[N-17] = 100003
/// (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
fn build_input(n: usize) -> Vec<i32> {
    let mut v = vec![0i32; n];
    for i in 0..n {
        v[i] = (((i as i32).wrapping_mul(17)).wrapping_add(3)) & 0x7f;
    }
    if n >= 17 {
        v[n - 17] = 100003;
    }
    let m = if n < 8 { n } else { 8 };
    for i in 0..m {
        v[i] = 48 + (i as i32 % 10);
    }
    v
}

/// Byte-for-byte port of the N# `rollingHash` kernel. Safe slice indexing
/// (keeps the natural bounds check, matching how N#/C# rely on the JIT to
/// elide it for counted loops). Wrapping arithmetic mirrors C# `unchecked`.
#[inline(never)]
fn rolling_hash(values: &[i32]) -> i32 {
    let mut hash: i32 = 17;
    let len = values.len();
    let mut i = 0usize;
    while i < len {
        hash = (hash.wrapping_mul(31).wrapping_add(values[i])) & 65535;
        i += 1;
    }
    hash
}

const SIZES: [usize; 2] = [64, 4096];
const WARMUP_ITERS: u64 = 100_000;
const TRIALS: usize = 21;

fn iters_for(size: usize) -> u64 {
    // Aim for >= ~200 ms per measured loop.
    if size <= 64 {
        2_000_000
    } else {
        50_000
    }
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
    // Linear interpolation on the sorted slice.
    let n = sorted.len();
    if n == 1 {
        return sorted[0];
    }
    let pos = q * (n as f64 - 1.0);
    let lo = pos.floor() as usize;
    let hi = pos.ceil() as usize;
    if lo == hi {
        sorted[lo]
    } else {
        sorted[lo] + (pos - lo as f64) * (sorted[hi] - sorted[lo])
    }
}

fn main() {
    let mut sink: i64 = 0;

    for &size in SIZES.iter() {
        let values = build_input(size);
        let iters = iters_for(size);

        let mut per_trial: Vec<f64> = Vec::with_capacity(TRIALS);

        for _ in 0..TRIALS {
            // Warmup (folded into sink so it isn't elided).
            for _ in 0..WARMUP_ITERS {
                let r = rolling_hash(black_box(&values[..]));
                sink ^= black_box(r) as i64;
            }

            // Measured loop.
            let start = Instant::now();
            for _ in 0..iters {
                let r = rolling_hash(black_box(&values[..]));
                sink ^= black_box(r) as i64;
            }
            let elapsed_ns = start.elapsed().as_nanos() as f64;
            per_trial.push(elapsed_ns / iters as f64);
        }

        let mut sorted = per_trial.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let med = median(per_trial);
        let min = sorted[0];
        let q1 = quartile(&sorted, 0.25);
        let q3 = quartile(&sorted, 0.75);

        // Machine-readable line: "<key> <size> <median_ns_per_op>"
        println!("rolling-hash {} {:.3}", size, med);
        // Human-readable stability line on stderr.
        eprintln!(
            "rolling-hash size={} median={:.3} min={:.3} iqr=[{:.3},{:.3}] ns/op (iters={}, trials={})",
            size, med, min, q1, q3, iters, TRIALS
        );
    }

    // Observe the sink so the whole chain is live.
    println!("sink {}", black_box(sink));
}
