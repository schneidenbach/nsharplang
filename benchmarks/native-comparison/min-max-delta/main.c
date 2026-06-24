/*
 * Faithful standalone C micro-bench for the N# `minMaxDelta` workload.
 *
 * Mirrors the N# `minMaxDelta` workload:
 *
 *   if (values.Length == 0) return 0;
 *   min = values[0]; max = values[0]; len = values.Length;
 *   for (i = 1; i < len; i++) {
 *       value = values[i];
 *       if (value < min) min = value;
 *       if (value > max) max = value;
 *   }
 *   return max - min;   // wrapping (unchecked) i32 subtraction
 *
 * Two independent branchy compares per element are kept verbatim (no branchless
 * min/max intrinsics) so the compared codegen shape matches N#.
 *
 * Methodology: deterministic fill identical to checksum-sum, build array once,
 * warmup, fixed measured loop, xor-fold into a volatile sink, 15+ trials, report
 * median ns/op (also min + IQR). Natural `values[i]` indexing is used.
 *
 * Build: cc -O3 -fwrapv -march=native main.c   (also report -O3 without -march=native)
 *        -fwrapv makes signed overflow defined as two's-complement wrap.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#define KEY "min-max-delta"

#define WARMUP_ITERS 100000UL
#define TRIALS 21

static const size_t SIZES[2] = {64, 4096};

/* ITERS chosen so each measured loop runs >= ~200 ms. */
static uint64_t iters_for(size_t size) {
    switch (size) {
        case 64:   return 2000000UL;
        case 4096: return 50000UL;
        default:   return 1000000UL;
    }
}

/* Deterministic fill, identical order to the checksum-sum / N# bench fill. */
static void build_values(int32_t *values, size_t n) {
    /* (a) for i in 0..N: values[i] = ((i*17)+3) & 0x7f */
    for (size_t i = 0; i < n; i++) {
        values[i] = (int32_t)(((int32_t)i * 17 + 3) & 0x7f);
    }
    /* (b) if N >= 17: values[N-17] = 100003 */
    if (n >= 17) {
        values[n - 17] = 100003;
    }
    /* (c) for i in 0..min(8,N): values[i] = 48 + (i%10) */
    size_t m = (n < 8) ? n : 8;
    for (size_t i = 0; i < m; i++) {
        values[i] = (int32_t)(48 + (i % 10));
    }
}

/* The workload under test, byte-for-byte per the N# algorithm.
 * -fwrapv guarantees the final subtraction wraps as two's complement. */
__attribute__((noinline))
static int32_t min_max_delta(const int32_t *values, size_t len) {
    if (len == 0) {
        return 0;
    }

    int32_t min = values[0];
    int32_t max = values[0];
    for (size_t i = 1; i < len; i++) {
        int32_t value = values[i];
        if (value < min) {
            min = value;
        }
        if (value > max) {
            max = value;
        }
    }

    return max - min;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a;
    double db = *(const double *)b;
    if (da < db) return -1;
    if (da > db) return 1;
    return 0;
}

/* Linear-interpolated quantile on an already-sorted array. */
static double quantile_sorted(const double *v, size_t n, double q) {
    if (n == 1) return v[0];
    double pos = q * ((double)n - 1.0);
    size_t lo = (size_t)pos;
    size_t hi = (pos > (double)lo) ? lo + 1 : lo;
    if (lo == hi) return v[lo];
    double frac = pos - (double)lo;
    return v[lo] * (1.0 - frac) + v[hi] * frac;
}

int main(void) {
    volatile int64_t sink = 0;

    for (size_t s = 0; s < 2; s++) {
        size_t size = SIZES[s];
        uint64_t iters = iters_for(size);

        int32_t *values = (int32_t *)malloc(size * sizeof(int32_t));
        if (!values) {
            fprintf(stderr, "alloc failed\n");
            return 1;
        }
        build_values(values, size);

        double samples[TRIALS];

        for (int t = 0; t < TRIALS; t++) {
            /* Warmup (folded into sink so it isn't elided). */
            for (uint64_t w = 0; w < WARMUP_ITERS; w++) {
                const int32_t *vp = values;
                __asm__ volatile("" : "+r"(vp)); /* launder ptr each iter: defeat clang hoisting the loop-invariant call (Rust black_box equivalent) */
                int32_t r = min_max_delta(vp, size);
                sink ^= (int64_t)r;
            }

            /* Measured loop. */
            struct timespec ts0, ts1;
            clock_gettime(CLOCK_MONOTONIC, &ts0);
            for (uint64_t it = 0; it < iters; it++) {
                const int32_t *vp = values;
                __asm__ volatile("" : "+r"(vp)); /* launder ptr each iter: defeat clang hoisting the loop-invariant call (Rust black_box equivalent) */
                int32_t r = min_max_delta(vp, size);
                sink ^= (int64_t)r;
            }
            clock_gettime(CLOCK_MONOTONIC, &ts1);

            double elapsed_ns = (double)(ts1.tv_sec - ts0.tv_sec) * 1e9 +
                                (double)(ts1.tv_nsec - ts0.tv_nsec);
            samples[t] = elapsed_ns / (double)iters;
        }

        qsort(samples, TRIALS, sizeof(double), cmp_double);
        double med;
        if (TRIALS % 2 == 1) {
            med = samples[TRIALS / 2];
        } else {
            med = (samples[TRIALS / 2 - 1] + samples[TRIALS / 2]) / 2.0;
        }
        double min_v = samples[0];
        double q1 = quantile_sorted(samples, TRIALS, 0.25);
        double q3 = quantile_sorted(samples, TRIALS, 0.75);
        double iqr = q3 - q1;

        /* Required one-line-per-size machine-readable output. */
        printf("%s %zu %.4f\n", KEY, size, med);
        /* Human-readable stability line on stderr. */
        fprintf(stderr,
                "%s %zu median=%.4f min=%.4f iqr=%.4f (q1=%.4f q3=%.4f) iters=%llu trials=%d\n",
                KEY, size, med, min_v, iqr, q1, q3,
                (unsigned long long)iters, TRIALS);

        free(values);
    }

    /* Print sink so the whole chain is observably live (defeats DCE). */
    printf("sink %lld\n", (long long)sink);
    return 0;
}
