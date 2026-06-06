/*
 * Faithful standalone C micro-bench for the N# `parseEightDigits` workload.
 *
 * N# source (benchmarks/SystemsHotPathBenchmarks.cs:99-116):
 *   func parseEightDigits(values: int[]): int {
 *       if values.Length < 8 { return -1 }
 *       parsed := 0
 *       for i := 0; i < 8; i++ {
 *           value := values[i]
 *           if value < 48 || value > 57 { return -1 }
 *           parsed = parsed * 10 + (value - 48)
 *       }
 *       return parsed
 *   }
 *
 * C# baseline: benchmarks/SystemsHotPathBenchmarks.cs:436-456 (CSharpParseEightDigits).
 *
 * O(1) workload: fixed trip count of 8 regardless of N. ns/op should be
 * ~size-independent across 64 and 4096; reporting that invariance is the point.
 *
 * Build (matching JIT-tuned codegen on this M4):
 *   clang -O3 -fwrapv -march=native -o parse-eight-digits_c main.c
 * Also valid (portable, no -march=native):
 *   clang -O3 -fwrapv -o parse-eight-digits_c main.c
 *
 * -fwrapv makes signed overflow defined as two's-complement wrap, matching C#
 * `unchecked` semantics. Natural array indexing `values[i]` is used (no manual
 * bounds-check tricks); C has no array bounds checks, mirroring the JIT-elided path.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define KEY "parse-eight-digits"

#define WARMUP_ITERS   1000000ULL
#define MEASURED_ITERS 20000000ULL
#define TRIALS         15

/* Anti-DCE accumulator: volatile so the compiler cannot fold or hoist away
 * the call chain. */
static volatile int64_t sink = 0;

__attribute__((noinline))
static int32_t parse_eight_digits(const int32_t *values, size_t len) {
    if (len < 8) {
        return -1;
    }

    int32_t parsed = 0;
    for (int i = 0; i < 8; i++) {
        int32_t value = values[i];
        if (value < 48 || value > 57) {
            return -1;
        }
        /* parsed = parsed * 10 + (value - 48)  (unchecked / -fwrapv wrap) */
        parsed = parsed * 10 + (value - 48);
    }

    return parsed;
}

/* Deterministic fill identical to the shared methodology / N# bench input:
 * (a) values[i] = ((i*17)+3) & 0x7f
 * (b) if N >= 17: values[N-17] = 100003
 * (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
 */
static int32_t *build_input(size_t n) {
    int32_t *v = (int32_t *)malloc(n * sizeof(int32_t));
    if (!v) {
        fprintf(stderr, "alloc failed for n=%zu\n", n);
        exit(1);
    }
    for (size_t i = 0; i < n; i++) {
        v[i] = (int32_t)((((int64_t)i * 17) + 3) & 0x7f);
    }
    if (n >= 17) {
        v[n - 17] = 100003;
    }
    size_t m = (n < 8) ? n : 8;
    for (size_t i = 0; i < m; i++) {
        v[i] = (int32_t)(48 + (i % 10));
    }
    return v;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a;
    double db = *(const double *)b;
    if (da < db) return -1;
    if (da > db) return 1;
    return 0;
}

static double quartile(const double *sorted, int n, double q) {
    if (n == 1) return sorted[0];
    double pos = q * (double)(n - 1);
    int lo = (int)pos;
    int hi = (pos > (double)lo) ? lo + 1 : lo;
    if (lo == hi) return sorted[lo];
    double frac = pos - (double)lo;
    return sorted[lo] * (1.0 - frac) + sorted[hi] * frac;
}

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

int main(void) {
    const size_t sizes[2] = {64, 4096};

    for (int s = 0; s < 2; s++) {
        size_t n = sizes[s];
        int32_t *values = build_input(n);

        /* Force-clobber the pointer so the optimizer cannot specialize on a
         * known-constant array. */
        const int32_t *p = values;
        __asm__ volatile("" : "+r"(p));

        /* Warmup. */
        for (uint64_t it = 0; it < WARMUP_ITERS; it++) {
            __asm__ volatile("" : "+r"(p)); /* per-iter ptr launder: defeat clang hoisting the loop-invariant call */
            int32_t r = parse_eight_digits(p, n);
            sink ^= (int64_t)r;
        }

        double samples[TRIALS];
        for (int t = 0; t < TRIALS; t++) {
            __asm__ volatile("" : "+r"(p));
            double start = now_ns();
            for (uint64_t it = 0; it < MEASURED_ITERS; it++) {
                __asm__ volatile("" : "+r"(p)); /* per-iter ptr launder: defeat clang hoisting the loop-invariant call */
                int32_t r = parse_eight_digits(p, n);
                sink ^= (int64_t)r;
            }
            double elapsed = now_ns() - start;
            samples[t] = elapsed / (double)MEASURED_ITERS;
        }

        qsort(samples, TRIALS, sizeof(double), cmp_double);
        double med = (TRIALS % 2 == 1)
                         ? samples[TRIALS / 2]
                         : (samples[TRIALS / 2 - 1] + samples[TRIALS / 2]) / 2.0;
        double mn = samples[0];
        double q1 = quartile(samples, TRIALS, 0.25);
        double q3 = quartile(samples, TRIALS, 0.75);

        /* Required machine-readable line. */
        printf("%s %zu %.4f\n", KEY, n, med);
        /* Extra stability detail to stderr. */
        fprintf(stderr, "%s %zu median=%.4f min=%.4f iqr=[%.4f,%.4f] ns/op\n",
                KEY, n, med, mn, q1, q3);

        free(values);
    }

    /* Anti-DCE: print the live accumulator. */
    printf("sink %lld\n", (long long)sink);
    return 0;
}
