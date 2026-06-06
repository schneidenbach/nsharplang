/*
 * Faithful standalone C micro-bench for the N# `countTransitions` workload.
 *
 * Mirrors benchmarks/SystemsHotPathBenchmarks.cs:118-137 (N# `countTransitions`)
 * and the C# baseline at benchmarks/SystemsHotPathBenchmarks.cs:458-480.
 *
 * Algorithm (byte-for-byte):
 *   if values.Length == 0 { return 0 }
 *   transitions := 0
 *   previous := values[0]
 *   len := values.Length
 *   for i := 1; i < len; i++ {
 *       current := values[i]
 *       if current != previous { transitions = transitions + 1 }
 *       previous = current
 *   }
 *   return transitions
 *
 * Build:
 *   cc -O3 -fwrapv -march=native -o /tmp/count-transitions_c main.c   (M4-tuned)
 *   cc -O3 -fwrapv             -o /tmp/count-transitions_c main.c   (portable cross-compare)
 *   -fwrapv makes signed overflow defined two's-complement wrap == C# unchecked.
 *   No -ffast-math (integer only).
 *
 * Protocol: deterministic identical fill, build array once, warmup, fixed measured
 * loop timed with clock_gettime(CLOCK_MONOTONIC), xor-fold every result into a
 * volatile sink, repeat 15 trials and report MEDIAN ns/op (plus min + IQR). Print
 * sink so the whole chain stays observably live under -O3.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#define KEY "count-transitions"
#define TRIALS 15
#define WARMUP_ITERS 100000ULL

static const size_t SIZES[2] = {64, 4096};

/*
 * Deterministic fill identical to the N# bench (same as checksum-sum):
 *   (a) for i in 0..N: values[i] = ((i*17)+3) & 0x7f
 *   (b) if N >= 17: values[N-17] = 100003
 *   (c) for i in 0..min(8,N): values[i] = 48 + (i%10)
 */
static void build_input(int32_t *values, size_t n) {
    for (size_t i = 0; i < n; i++) {
        values[i] = (int32_t)((((int32_t)i * 17) + 3) & 0x7f);
    }
    if (n >= 17) {
        values[n - 17] = 100003;
    }
    size_t c = n < 8 ? n : 8;
    for (size_t i = 0; i < c; i++) {
        values[i] = (int32_t)(48 + (i % 10));
    }
}

/*
 * The workload under test. Natural `values[i]` indexing. -fwrapv gives defined
 * two's-complement wrap for the `transitions + 1` arithmetic (matches C# unchecked).
 */
__attribute__((noinline))
static int32_t count_transitions(const int32_t *values, size_t len) {
    if (len == 0) {
        return 0;
    }
    int32_t transitions = 0;
    int32_t previous = values[0];
    for (size_t i = 1; i < len; i++) {
        int32_t current = values[i];
        if (current != previous) {
            transitions = transitions + 1;
        }
        previous = current;
    }
    return transitions;
}

static unsigned long long iters_for(size_t size) {
    /* Total measured time per (kernel,size) >= ~200 ms. */
    if (size == 64) {
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

static double percentile(const double *sorted, size_t n, double p) {
    if (n == 0) return 0.0 / 0.0;
    long idx = (long)(((double)n - 1.0) * p + 0.5);
    if (idx < 0) idx = 0;
    if ((size_t)idx >= n) idx = (long)n - 1;
    return sorted[idx];
}

/* Anti-DCE sink: volatile so the compiler must materialize every xor. */
static volatile int64_t sink = 0;

int main(void) {
    for (size_t s = 0; s < 2; s++) {
        size_t size = SIZES[s];
        int32_t *values = (int32_t *)malloc(size * sizeof(int32_t));
        if (!values) {
            fprintf(stderr, "alloc failed\n");
            return 1;
        }
        build_input(values, size);

        unsigned long long iters = iters_for(size);
        double samples[TRIALS];

        for (int t = 0; t < TRIALS; t++) {
            /* Warmup, folded into sink so it isn't elided. */
            for (unsigned long long w = 0; w < WARMUP_ITERS; w++) {
                /* Clobber the pointer so -O3 cannot specialize on a known array. */
                const int32_t *p = values;
                __asm__ volatile("" : "+r"(p));
                int32_t r = count_transitions(p, size);
                sink ^= (int64_t)r;
            }

            struct timespec start, end;
            clock_gettime(CLOCK_MONOTONIC, &start);
            for (unsigned long long it = 0; it < iters; it++) {
                const int32_t *p = values;
                __asm__ volatile("" : "+r"(p));
                int32_t r = count_transitions(p, size);
                sink ^= (int64_t)r;
            }
            clock_gettime(CLOCK_MONOTONIC, &end);

            double elapsed_ns =
                (double)(end.tv_sec - start.tv_sec) * 1e9 +
                (double)(end.tv_nsec - start.tv_nsec);
            samples[t] = elapsed_ns / (double)iters;
        }

        qsort(samples, TRIALS, sizeof(double), cmp_double);
        double median = percentile(samples, TRIALS, 0.5);
        double mn = samples[0];
        double q1 = percentile(samples, TRIALS, 0.25);
        double q3 = percentile(samples, TRIALS, 0.75);
        double iqr = q3 - q1;

        /* Required machine-readable line: "<key> <size> <median_ns_per_op>". */
        printf("%s %zu %.3f\n", KEY, size, median);
        /* Stability detail to stderr so stdout stays clean for the parser. */
        fprintf(stderr,
                "%s %zu median=%.3f min=%.3f iqr=%.3f (q1=%.3f q3=%.3f) ns/op trials=%d\n",
                KEY, size, median, mn, iqr, q1, q3, TRIALS);

        free(values);
    }

    /* Anti-DCE: observe the whole accumulated chain. */
    printf("sink %lld\n", (long long)sink);
    return 0;
}
