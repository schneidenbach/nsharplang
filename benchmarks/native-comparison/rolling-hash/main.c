/* Faithful standalone C micro-bench for the N# `rollingHash` kernel.
 *
 * N# source (benchmarks/SystemsHotPathBenchmarks.cs:88-97):
 *   func rollingHash(values: int[]): int {
 *       hash := 17
 *       len := values.Length
 *       for i := 0; i < len; i++ {
 *           hash = ((hash * 31) + values[i]) & 65535
 *       }
 *       return hash
 *   }
 * C# baseline (benchmarks/SystemsHotPathBenchmarks.cs:424-434) is identical.
 *
 * Apples-to-apples protocol: build the input arrays ONCE, warm up, then time a
 * fixed iteration count of the EXACT kernel, xor-folding every result into a
 * volatile sink so -O3 cannot eliminate the work. Report median ns/op over
 * trials (also min + IQR). Print sink at the end so the chain stays live.
 *
 * Build (full protocol):
 *   cc -O3 -fwrapv -march=native -o /tmp/rolling-hash_c main.c
 *   (also report a -O3 without -march=native run when cross-comparing)
 * Compile-check in this task uses:
 *   clang -O3 -o /tmp/rolling-hash_c main.c
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/* Deterministic fill identical to the N#/C# bench input.
 * (a) values[i] = ((i*17)+3) & 0x7f
 * (b) if N >= 17: values[N-17] = 100003
 * (c) for i in 0..min(8,N): values[i] = 48 + (i%10)  */
static void build_input(int32_t *values, size_t n) {
    for (size_t i = 0; i < n; i++) {
        values[i] = (int32_t)(((int32_t)i * 17 + 3) & 0x7f);
    }
    if (n >= 17) {
        values[n - 17] = 100003;
    }
    size_t m = n < 8 ? n : 8;
    for (size_t i = 0; i < m; i++) {
        values[i] = (int32_t)(48 + (i % 10));
    }
}

/* Byte-for-byte port of the N# `rollingHash` kernel. Natural `values[i]`
 * indexing. Signed wrapping is defined via -fwrapv (matches C# unchecked). */
__attribute__((noinline))
static int32_t rolling_hash(const int32_t *values, size_t len) {
    int32_t hash = 17;
    for (size_t i = 0; i < len; i++) {
        hash = ((hash * 31) + values[i]) & 65535;
    }
    return hash;
}

static const size_t SIZES[] = {64, 4096};
#define NUM_SIZES (sizeof(SIZES) / sizeof(SIZES[0]))
#define WARMUP_ITERS 100000ULL
#define TRIALS 21

static uint64_t iters_for(size_t size) {
    /* Aim for >= ~200 ms per measured loop. */
    return size <= 64 ? 2000000ULL : 50000ULL;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    if (da < db) return -1;
    if (da > db) return 1;
    return 0;
}

static double median_sorted(const double *sorted, int n) {
    if (n % 2 == 1) return sorted[n / 2];
    return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0;
}

static double quartile_sorted(const double *sorted, int n, double q) {
    if (n == 1) return sorted[0];
    double pos = q * (double)(n - 1);
    int lo = (int)pos;
    int hi = (pos > (double)lo) ? lo + 1 : lo;
    if (lo == hi) return sorted[lo];
    return sorted[lo] + (pos - (double)lo) * (sorted[hi] - sorted[lo]);
}

static int64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

/* black_box analog: force the compiler to treat the pointer as opaque/escaped
 * each iteration so it cannot prove the kernel result is loop-invariant and
 * hoist the call out of the measured loop. Mirrors Rust's
 * black_box(&values[..]) passed INTO the kernel every iteration. */
static inline const int32_t *clobber_ptr(const int32_t *p) {
    __asm__ volatile("" : "+r"(p) : : "memory");
    return p;
}

int main(void) {
    volatile int64_t sink = 0;

    for (size_t s = 0; s < NUM_SIZES; s++) {
        size_t size = SIZES[s];
        uint64_t iters = iters_for(size);

        int32_t *values = (int32_t *)malloc(size * sizeof(int32_t));
        if (!values) {
            fprintf(stderr, "alloc failed for size %zu\n", size);
            return 1;
        }
        build_input(values, size);

        double per_trial[TRIALS];

        for (int t = 0; t < TRIALS; t++) {
            /* Warmup (folded into sink so it isn't elided). */
            for (uint64_t w = 0; w < WARMUP_ITERS; w++) {
                int32_t r = rolling_hash(clobber_ptr(values), size);
                sink ^= (int64_t)r;
            }

            /* Measured loop. */
            int64_t start = now_ns();
            for (uint64_t it = 0; it < iters; it++) {
                int32_t r = rolling_hash(clobber_ptr(values), size);
                sink ^= (int64_t)r;
            }
            int64_t elapsed_ns = now_ns() - start;
            per_trial[t] = (double)elapsed_ns / (double)iters;
        }

        double sorted[TRIALS];
        for (int i = 0; i < TRIALS; i++) sorted[i] = per_trial[i];
        qsort(sorted, TRIALS, sizeof(double), cmp_double);

        double med = median_sorted(sorted, TRIALS);
        double mn = sorted[0];
        double q1 = quartile_sorted(sorted, TRIALS, 0.25);
        double q3 = quartile_sorted(sorted, TRIALS, 0.75);

        /* Machine-readable line: "<key> <size> <median_ns_per_op>" */
        printf("rolling-hash %zu %.3f\n", size, med);
        /* Human-readable stability line on stderr. */
        fprintf(stderr,
                "rolling-hash size=%zu median=%.3f min=%.3f iqr=[%.3f,%.3f] "
                "ns/op (iters=%llu, trials=%d)\n",
                size, med, mn, q1, q3, (unsigned long long)iters, TRIALS);

        free(values);
    }

    /* Observe the sink so the whole chain is live. */
    printf("sink %lld\n", (long long)sink);
    return 0;
}
