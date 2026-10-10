/*
 * Faithful standalone C micro-bench for the N# `checksum` hot-path workload.
 *
 * Workload (`checksum`):
 *
 *     sum := 0
 *     len := values.Length
 *     for i := 0; i < len; i++ { sum = sum + values[i] }
 *     return sum
 *
 * Wrapping (two's-complement) int32 add.
 * Compile with -fwrapv so signed overflow is defined as two's-complement wrap.
 *
 * Input fill (identical bytes to the N# GlobalSetup at :271-284), in this order:
 *   (a) for i in 0..N: values[i] = ((i*17)+3) & 0x7f
 *   (b) if N >= 17:    values[N-17] = 100003
 *   (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
 *
 * Methodology: build array once outside the timed loop, warmup, then a fixed
 * MEASURED loop of ITERS kernel invocations over the SAME pre-built array.
 * A `volatile int64_t sink` receives an xor-fold of every result so -O3 cannot
 * constant-fold/hoist the call; the array pointer is laundered through an inline
 * asm clobber each iteration so the compiler cannot specialize on a known array.
 * Repeat 15 trials, report median (also min + IQR) ns/op per size.
 *
 * Build (per methodology):
 *   cc -O3 -fwrapv -march=native -o checksum_c main.c
 * Compile-check (no -march, portable):
 *   clang -O3 -o /tmp/checksum-sum_c main.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

/* The workload under test: one full kernel invocation over the length-N array,
 * returning the int32 sum with wrapping add. Natural `values[i]` indexing,
 * no bounds-check hacks. */
static int32_t checksum(const int32_t *values, size_t len) {
    int32_t sum = 0;
    for (size_t i = 0; i < len; i++) {
        sum = sum + values[i];
    }
    return sum;
}

/* Launder a pointer through an inline-asm clobber so the optimizer treats it as
 * opaque (anti-DCE / anti-specialization), mirroring Rust's black_box on input. */
static inline const int32_t *launder(const int32_t *p) {
#if defined(__GNUC__) || defined(__clang__)
    __asm__ volatile("" : "+r"(p));
#endif
    return p;
}

/* Deterministic fill identical to the N# benchmark setup. */
static int32_t *build_values(size_t n) {
    int32_t *values = (int32_t *)malloc(n * sizeof(int32_t));
    if (!values) {
        fprintf(stderr, "alloc failed for n=%zu\n", n);
        exit(1);
    }
    /* (a) */
    for (size_t i = 0; i < n; i++) {
        values[i] = (((int32_t)i * 17) + 3) & 0x7f;
    }
    /* (b) */
    if (n >= 17) {
        values[n - 17] = 100003;
    }
    /* (c) */
    size_t m = n < 8 ? n : 8;
    for (size_t i = 0; i < m; i++) {
        values[i] = 48 + (int32_t)(i % 10);
    }
    return values;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a;
    double db = *(const double *)b;
    if (da < db) return -1;
    if (da > db) return 1;
    return 0;
}

static double median_sorted(const double *s, int n) {
    if (n % 2 == 1) return s[n / 2];
    return (s[n / 2 - 1] + s[n / 2]) / 2.0;
}

static double percentile_sorted(const double *s, int n, double p) {
    if (n == 0) return 0.0;
    long idx = (long)(p * (n - 1) + 0.5);
    if (idx < 0) idx = 0;
    if (idx > n - 1) idx = n - 1;
    return s[idx];
}

/* volatile sink: every result is xor-folded in; printed at the end so the
 * whole dependency chain stays observably live. */
static volatile int64_t sink = 0;

static void run_size(const char *key, size_t n, uint64_t iters,
                     uint64_t warmup, int trials) {
    int32_t *values = build_values(n);

    double *samples = (double *)malloc((size_t)trials * sizeof(double));
    if (!samples) { fprintf(stderr, "alloc failed\n"); exit(1); }

    for (int t = 0; t < trials; t++) {
        /* Warmup (feed results into sink so warmup isn't elided). */
        for (uint64_t w = 0; w < warmup; w++) {
            const int32_t *p = launder(values);
            int32_t r = checksum(p, n);
            sink ^= (int64_t)r;
        }

        /* Measured loop. */
        struct timespec ts0, ts1;
        clock_gettime(CLOCK_MONOTONIC, &ts0);
        for (uint64_t it = 0; it < iters; it++) {
            const int32_t *p = launder(values);
            int32_t r = checksum(p, n);
            sink ^= (int64_t)r;
        }
        clock_gettime(CLOCK_MONOTONIC, &ts1);

        double elapsed_ns = (double)(ts1.tv_sec - ts0.tv_sec) * 1e9 +
                            (double)(ts1.tv_nsec - ts0.tv_nsec);
        samples[t] = elapsed_ns / (double)iters;
    }

    qsort(samples, (size_t)trials, sizeof(double), cmp_double);
    double med = median_sorted(samples, trials);
    double mn = samples[0];
    double q1 = percentile_sorted(samples, trials, 0.25);
    double q3 = percentile_sorted(samples, trials, 0.75);

    fprintf(stderr,
            "# %s size=%zu sink=%lld min=%.3f q1=%.3f q3=%.3f iqr=%.3f trials=%d\n",
            key, n, (long long)sink, mn, q1, q3, q3 - q1, trials);

    /* Required machine-readable line: "<key> <size> <median_ns_per_op>" */
    printf("%s %zu %.3f\n", key, n, med);

    free(samples);
    free(values);
}

int main(void) {
    const char *key = "checksum-sum";
    int trials = 15;
    uint64_t warmup = 100000;

    /* Size 64: ITERS = 2_000_000. */
    run_size(key, 64, 2000000ULL, warmup, trials);
    /* Size 4096: ITERS = 50_000. */
    run_size(key, 4096, 50000ULL, warmup, trials);

    /* Final observable use of sink. */
    fprintf(stderr, "# final sink=%lld\n", (long long)sink);
    return 0;
}
