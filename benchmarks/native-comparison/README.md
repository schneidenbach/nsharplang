# native-comparison — systems N# vs Rust vs C

Standalone, reproducible cross-language micro-benchmarks for the systems hot paths, used to measure
systems-N# against native compilers (Rust, C). These are NOT part of the `dotnet` build — they are
hand-rolled Rust/C ports of the same algorithms the N# systems benchmarks measure, so we can compare N#
codegen against LLVM/clang directly. Treat checked-in numbers as historical unless they are refreshed by
a current benchmark run.

Each `<workload>/` has `main.rs` and `main.c` implementing the SAME algorithm as the corresponding N#
systems workload, over the same sizes (64, 4096), with a warmup, a large fixed iteration count, and an
anti-dead-code-elimination sink that is printed (so `-O3` cannot elide the work). Each prints
`<workload> <size> <ns_per_op>`.

## Run

```bash
source "$HOME/.cargo/env"
for w in checksum-sum count-ascii count-transitions rolling-hash min-max-delta parse-eight-digits; do
  rustc -C opt-level=3 -o /tmp/${w}_rs benchmarks/native-comparison/$w/main.rs && /tmp/${w}_rs
  clang -O3 -o /tmp/${w}_c  benchmarks/native-comparison/$w/main.c  && /tmp/${w}_c
done
```

Refresh N# numbers from an N#-owned measurement path before comparing them with
the native runs in this directory.

## Methodology note

All six workloads are methodologically clean on both Rust and C. The C kernels use a per-iteration inline-asm
pointer-launder barrier (`__asm__ volatile("" : "+r"(p))`, the C equivalent of Rust's `black_box`) so
`clang -O3` cannot hoist/DCE the loop-invariant kernel call out of the timed loop. (min-max-delta and
parse-eight-digits originally lacked this per-iteration barrier and were DCE'd; fixed 2026-06-06.) Each port
prints both the machine-readable `<key> <size> <ns>` line on stdout and a stability line
(median/min/IQR/iters/trials) on stderr.
