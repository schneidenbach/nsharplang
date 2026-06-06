/* Faithful C micro-bench for N# `countAscii`
 * (benchmarks/SystemsHotPathBenchmarks.cs:51-63).
 * C# baseline: CSharpCountAscii (benchmarks/SystemsHotPathBenchmarks.cs:381-395).
 *
 * Algorithm (byte-for-byte):
 *   count := 0
 *   len := values.Length
 *   for i := 0; i < len; i++ {
 *       value := values[i]
 *       if value >= 32 && value <= 126 { count = count + 1 }
 *   }
 *   return count
 *
 * `&&` short-circuits per N#/C#; both operands are pure comparisons so the
 * result is identical to a non-short-circuit AND. We keep `&&` (C short-circuits
 * it too) for exact semantic fidelity.
 *
 * Build: cc -O3 -fwrapv -march=native (signed overflow = two's-complement wrap,
 * matching C# unchecked). Indexing is the natural `values[i]`.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#define KEY "count-ascii"
#define WARMUP_ITERS 100000ULL
#define TRIALS 15

static const size_t SIZES[2] = {64, 4096};

/* Deterministic fill identical to the N# benchmark seed (see methodology):
 *   (a) for i in 0..N: values[i] = ((i*17)+3) & 0x7f
 *   (b) if N >= 17: values[N-17] = 100003
 *   (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
 */
static int32_t *build_input(size_t n) {
    int32_t *values = (int32_t *)malloc(n * sizeof(int32_t));
    if (!values) {
        fprintf(stderr, "alloc failed\n");
        exit(1);
    }
    for (size_t i = 0; i < n; i++) {
        values[i] = (((int32_t)i * 17) + 3) & 0x7f;
    }
    if (n >= 17) {
        values[n - 17] = 100003;
    }
    size_t m = n < 8 ? n : 8;
    for (size_t i = 0; i < m; i++) {
        values[i] = 48 + ((int32_t)i % 10);
    }
    return values;
}

/* The workload under test. __attribute__((noinline)) keeps it a real call,
 * matching a method invocation per BDN op. */
__attribute__((noinline))
static int32_t count_ascii(const int32_t *values, size_t len) {
    int32_t count = 0;
    for (size_t i = 0; i < len; i++) {
        int32_t value = values[i];
        if (value >= 32 && value <= 126) {
            count = count + 1;
        }
    }
    return count;
}

static uint64_t iters_for(size_t size) {
    /* Target >= ~200 ms per measured loop. */
    if (size <= 64) {
        return 2000000ULL;
    }
    return 50000ULL;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a;
    double db = *(const double *)b;
    if (da < db) return -1;
    if (da > db) return 1;
    return 0;
}

static int64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

int main(void) {
    /* Anti-DCE sink: volatile so the compiler cannot fold or hoist. */
    volatile int64_t sink = 0;

    for (size_t s = 0; s < 2; s++) {
        size_t size = SIZES[s];
        int32_t *values = build_input(size);
        uint64_t iters = iters_for(size);

        /* Warmup (folded into sink). */
        for (uint64_t w = 0; w < WARMUP_ITERS; w++) {
            const int32_t *p = values;
            /* Clobber the pointer so the compiler cannot specialize on a
             * known-constant array or elide the call. */
            __asm__ volatile("" : "+r"(p));
            int32_t r = count_ascii(p, size);
            sink ^= (int64_t)r;
        }

        double samples[TRIALS];
        for (int t = 0; t < TRIALS; t++) {
            int64_t start = now_ns();
            for (uint64_t it = 0; it < iters; it++) {
                const int32_t *p = values;
                __asm__ volatile("" : "+r"(p));
                int32_t r = count_ascii(p, size);
                sink ^= (int64_t)r;
            }
            int64_t elapsed = now_ns() - start;
            samples[t] = (double)elapsed / (double)iters;
        }

        qsort(samples, TRIALS, sizeof(double), cmp_double);
        double median = samples[TRIALS / 2];
        double min = samples[0];
        double q1 = samples[TRIALS / 4];
        double q3 = samples[(TRIALS * 3) / 4];
        double iqr = q3 - q1;

        /* Primary machine-readable line. */
        printf("%s %zu %.4f\n", KEY, size, median);
        /* Stability detail to stderr. */
        fprintf(stderr, "%s %zu median=%.4f min=%.4f iqr=%.4f ns/op\n",
                KEY, size, median, min, iqr);

        free(values);
    }

    /* Anti-DCE: print the observed sink. */
    printf("sink %lld\n", (long long)sink);
    return 0;
}
