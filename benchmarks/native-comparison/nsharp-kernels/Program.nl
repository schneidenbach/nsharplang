namespace NSharpLang.NativeComparison

import System
import System.Diagnostics
import System.Globalization


// THE N#-OWNED MEASUREMENT PATH FOR THE SIX NATIVE-COMPARISON KERNELS.
//
// This is the third port of one experiment. `../<workload>/main.rs` and `../<workload>/main.c` are the
// other two, and every discipline they follow is followed here so that the three sets of numbers are
// comparable: the same deterministic fill, the array built once per size, a warmup before EVERY trial,
// a fixed measured iteration count, an xor-folded sink that is printed so the chain stays live, and a
// MEDIAN reported with min and IQR beside it.
//
// THE STDOUT PROTOCOL IS THE CONTRACT. One `<workload> <size> <ns_per_op>` line per pair, then a final
// `sink <value>` line — that is what a runner parses. Everything a human wants (median, min, IQR, the
// quartiles, the iteration and trial counts) goes to stderr, so stdout stays machine-readable.
//
// WHY SIX NEAR-IDENTICAL TIMED-LOOP FUNCTIONS INSTEAD OF ONE PARAMETERISED BY WORKLOAD. Each port owns
// its own timed loop and calls its one kernel directly; a shared loop that selected the kernel per
// iteration would put an if-chain of up to five compare+branch pairs INSIDE the measured region. On the
// 64-element cells and on parse-eight-digits — kernels that answer in single-digit nanoseconds — that
// dispatch is tens of percent of the measurement, and it is overhead no port pays. So the workload is
// chosen ONCE per trial, in `RunTrial`, outside every timed region, and each `Time*` function's loop
// body is a direct static call. The duplication is the point: it is what makes the loop bodies the
// same shape as the ports'.
//
// ON ANTI-DEAD-CODE-ELIMINATION, WHICH IS NOT THE SAME PROBLEM HERE AS IT IS THERE. The Rust port needs
// `black_box` and the C port needs an inline-asm pointer launder because LLVM will otherwise hoist a
// loop-invariant call straight out of the timed loop. RyuJIT does not hoist a loop out of a loop, so the
// defence that matters on this runtime is the one both ports also use: every result is xor-folded into a
// sink that is PRINTED, so no kernel call is dead, and the array is a real heap array whose contents the
// JIT cannot fold to a constant. There is no N# equivalent of `black_box` to reach for. Every port
// prints `sink 0` for the same arithmetic reason — an identical value xor-folded an even number of
// times cancels — and this harness did too until the settle phase below started contributing an
// odd-or-even number of folds of its own. Either value is a property of the fold, not a sign that the
// work was elided.
//
// WHY THERE IS A JIT SETTLE PHASE THAT NO PORT HAS, AND WHY THE PER-TRIAL WARMUP DOES NOT REPLACE IT.
// Rust and C hand the CPU fully compiled code; the CLR does not. Both halves of a vectorized kernel —
// `Kernels.<name>` and the `SimdReductions` helper it calls — start at Tier 0, and promotion to Tier 1
// needs about 30 calls, THEN a ~100 ms call-counting delay, THEN a background compilation that is slow
// to get scheduled on a loaded machine. The ports' per-trial warmup is a cache/branch-predictor warmup
// and is far too short to cover that. Measured on this project: a `--trials 2` run reported
// checksum-sum at 64 elements as ~66 ns, while a 15-trial run of the same binary reported 14 ns
// (min 12.7, q3 14.7) and `DOTNET_TieredCompilation=0` reported ~15 ns. The first trial or two of every
// cell were timing Tier-0 code, and because the ports' quantile convention takes the UPPER sample of a
// two-sample set, the reported median was the Tier-0 one. Fifteen and twenty-one trials bury it, but
// promotion timing under load must not be able to move a median at all, so each (workload, size) is
// settled ONCE before its first trial: the kernel is called until at least 500 ms of wall time has
// passed, long enough for both halves to reach Tier 1 even when the compile queue is contended. The
// settle phase is not timed and adds no token to either output line; its results are xor-folded into
// the same sink, which is why `sink` is no longer always `0` — the fold count now depends on how many
// calls fitted in 500 ms.
//
// WHY THE CLOCK IS `GetElapsedTime` AND NOT `GetTimestamp` / `Frequency`. `Stopwatch.Frequency` declines
// to emit on the columnar backend (`emit.local.initializer`), so the tick-to-nanosecond conversion is
// done by `Stopwatch.GetElapsedTime`, which returns a `TimeSpan` of 100 ns ticks. Over a measured loop
// of ~200 ms that quantisation is ~5e-7 relative — four orders below the trial-to-trial spread the IQR
// line reports.

// The workload keys, in the order the ports and the runner expect them.
[boundary]
func WorkloadKeys(): string[] {
    keys := new string[](6)
    keys[0] = "checksum-sum"
    keys[1] = "count-ascii"
    keys[2] = "count-transitions"
    keys[3] = "rolling-hash"
    keys[4] = "min-max-delta"
    keys[5] = "parse-eight-digits"
    return keys
}

[boundary]
func KernelNames(): string[] {
    // The `Kernels` method behind each key, in the same order as `WorkloadKeys`.
    names := new string[](6)
    names[0] = "Checksum"
    names[1] = "CountAscii"
    names[2] = "CountTransitions"
    names[3] = "RollingHash"
    names[4] = "MinMaxDelta"
    names[5] = "ParseEightDigits"
    return names
}

[boundary]
func Sizes(): int[] {
    sizes := new int[](2)
    sizes[0] = 64
    sizes[1] = 4096
    return sizes
}

// THE PER-WORKLOAD COUNTS, MIRRORING EACH PORT'S OWN CONSTANTS RATHER THAN A UNIFORM RULE.
//
// The six ports are not consistent with each other, so a single table would leave some cells measuring
// something the binary they are compared against does not measure. Each row below names the constants
// it mirrors in `../<workload>/main.rs` and `../<workload>/main.c`:
//
//   parse-eight-digits  MEASURED_ITERS = 20_000_000 at BOTH sizes, WARMUP_ITERS = 1_000_000, TRIALS 15.
//                       Its kernel reads eight elements whatever the array length, so the port does not
//                       scale iterations with size; at the other workloads' 50_000 the size-4096 cell
//                       would time a ~75 us window.
//   rolling-hash        iters_for 2_000_000 / 50_000, WARMUP_ITERS = 100_000, TRIALS = 21.
//   min-max-delta       iters_for 2_000_000 / 50_000, WARMUP_ITERS = 100_000, TRIALS = 21.
//   the other three     iters_for 2_000_000 / 50_000, WARMUP_ITERS = 100_000, TRIALS = 15.
//
// `--trials <n>` overrides every trial count; the iteration and warmup counts are not overridable,
// because changing them would stop the cell being comparable with its port.
func MeasuredIterations(workload: int, size: int): int {
    if workload == 5 {
        return 20000000
    }

    if size == 64 {
        return 2000000
    }

    return 50000
}

func WarmupIterations(workload: int): int {
    if workload == 5 {
        return 1000000
    }

    return 100000
}

func DefaultTrials(workload: int): int {
    if workload == 3 || workload == 4 {
        return 21
    }

    return 15
}

[boundary]
func BuildInput(n: int): int[] {
    // The ports' fill, in the ports' order: the arithmetic sweep, then the single sentinel 17 elements
    // from the end, then the eight ASCII digits at the front. The order matters — the sweep would
    // overwrite the other two.
    values := new int[](n)
    for i := 0; i < n; i++ {
        values[i] = ((i * 17) + 3) & 127
    }

    if n >= 17 {
        values[n - 17] = 100003
    }

    prefix := n
    if prefix > 8 {
        prefix = 8
    }

    for i := 0; i < prefix; i++ {
        values[i] = 48 + (i % 10)
    }

    return values
}

// The verification and IL-shape paths only: this is the one place a workload is selected by index at
// call time, and it is never reached from a timed region.
func RunWorkload(workload: int, values: int[]): int {
    if workload == 0 {
        return Kernels.Checksum(values)
    }

    if workload == 1 {
        return Kernels.CountAscii(values)
    }

    if workload == 2 {
        return Kernels.CountTransitions(values)
    }

    if workload == 3 {
        return Kernels.RollingHash(values)
    }

    if workload == 4 {
        return Kernels.MinMaxDelta(values)
    }

    return Kernels.ParseEightDigits(values)
}

[boundary]
func ElapsedMilliseconds(start: long, stop: long): double {
    return Stopwatch.GetElapsedTime(start, stop).TotalMilliseconds
}

[boundary]
func SettleMilliseconds(): double {
    return 500.0
}

[boundary]
func SettleJit(workload: int, values: int[]): long {
    // Run this cell's kernel until the CLR has had time to tier it up. See the header: 500 ms is
    // chosen to cover ~30 calls plus the ~100 ms call-counting delay plus a background compilation
    // that schedules slowly on a loaded machine, for BOTH the kernel and its `SimdReductions` helper.
    // Nothing here is timed, so the batch's dispatch costs nothing that is reported; the clock is read
    // once per batch rather than once per call only to keep the loop's shape close to the timed one.
    folded: long = 0
    budget := SettleMilliseconds()
    start := Stopwatch.GetTimestamp()
    elapsed := 0.0
    while elapsed < budget {
        for i := 0; i < 1000; i++ {
            folded = folded ^ (long)RunWorkload(workload, values)
        }

        elapsed = ElapsedMilliseconds(start, Stopwatch.GetTimestamp())
    }

    return folded
}

[boundary]
func ElapsedNanosecondsPerOp(start: long, stop: long, iterations: int): double {
    // Called once per trial, after the clock has been read and outside every timed region.
    elapsedNanoseconds := Stopwatch.GetElapsedTime(start, stop).TotalMilliseconds * 1000000.0
    return elapsedNanoseconds / (double)iterations
}

// ---- the six timed loops; see the header for why they are not one function --------------------

[boundary]
func TimeChecksum(values: int[], warmup: int, iterations: int, out nanosecondsPerOp: double): long {
    folded: long = 0
    for i := 0; i < warmup; i++ {
        folded = folded ^ (long)Kernels.Checksum(values)
    }

    start := Stopwatch.GetTimestamp()
    for i := 0; i < iterations; i++ {
        folded = folded ^ (long)Kernels.Checksum(values)
    }

    stop := Stopwatch.GetTimestamp()
    nanosecondsPerOp = ElapsedNanosecondsPerOp(start, stop, iterations)
    return folded
}

[boundary]
func TimeCountAscii(values: int[], warmup: int, iterations: int, out nanosecondsPerOp: double): long {
    folded: long = 0
    for i := 0; i < warmup; i++ {
        folded = folded ^ (long)Kernels.CountAscii(values)
    }

    start := Stopwatch.GetTimestamp()
    for i := 0; i < iterations; i++ {
        folded = folded ^ (long)Kernels.CountAscii(values)
    }

    stop := Stopwatch.GetTimestamp()
    nanosecondsPerOp = ElapsedNanosecondsPerOp(start, stop, iterations)
    return folded
}

[boundary]
func TimeCountTransitions(values: int[], warmup: int, iterations: int, out nanosecondsPerOp: double): long {
    folded: long = 0
    for i := 0; i < warmup; i++ {
        folded = folded ^ (long)Kernels.CountTransitions(values)
    }

    start := Stopwatch.GetTimestamp()
    for i := 0; i < iterations; i++ {
        folded = folded ^ (long)Kernels.CountTransitions(values)
    }

    stop := Stopwatch.GetTimestamp()
    nanosecondsPerOp = ElapsedNanosecondsPerOp(start, stop, iterations)
    return folded
}

[boundary]
func TimeRollingHash(values: int[], warmup: int, iterations: int, out nanosecondsPerOp: double): long {
    folded: long = 0
    for i := 0; i < warmup; i++ {
        folded = folded ^ (long)Kernels.RollingHash(values)
    }

    start := Stopwatch.GetTimestamp()
    for i := 0; i < iterations; i++ {
        folded = folded ^ (long)Kernels.RollingHash(values)
    }

    stop := Stopwatch.GetTimestamp()
    nanosecondsPerOp = ElapsedNanosecondsPerOp(start, stop, iterations)
    return folded
}

[boundary]
func TimeMinMaxDelta(values: int[], warmup: int, iterations: int, out nanosecondsPerOp: double): long {
    folded: long = 0
    for i := 0; i < warmup; i++ {
        folded = folded ^ (long)Kernels.MinMaxDelta(values)
    }

    start := Stopwatch.GetTimestamp()
    for i := 0; i < iterations; i++ {
        folded = folded ^ (long)Kernels.MinMaxDelta(values)
    }

    stop := Stopwatch.GetTimestamp()
    nanosecondsPerOp = ElapsedNanosecondsPerOp(start, stop, iterations)
    return folded
}

[boundary]
func TimeParseEightDigits(values: int[], warmup: int, iterations: int, out nanosecondsPerOp: double): long {
    folded: long = 0
    for i := 0; i < warmup; i++ {
        folded = folded ^ (long)Kernels.ParseEightDigits(values)
    }

    start := Stopwatch.GetTimestamp()
    for i := 0; i < iterations; i++ {
        folded = folded ^ (long)Kernels.ParseEightDigits(values)
    }

    stop := Stopwatch.GetTimestamp()
    nanosecondsPerOp = ElapsedNanosecondsPerOp(start, stop, iterations)
    return folded
}

[boundary]
func RunTrial(workload: int, values: int[], warmup: int, iterations: int, out nanosecondsPerOp: double): long {
    // THE ONLY DISPATCH IN THE MEASUREMENT PATH, and it is taken once per trial rather than once per
    // iteration. Everything below the chosen arm is a loop whose body is a direct static call.
    if workload == 0 {
        return TimeChecksum(values, warmup, iterations, out nanosecondsPerOp)
    }

    if workload == 1 {
        return TimeCountAscii(values, warmup, iterations, out nanosecondsPerOp)
    }

    if workload == 2 {
        return TimeCountTransitions(values, warmup, iterations, out nanosecondsPerOp)
    }

    if workload == 3 {
        return TimeRollingHash(values, warmup, iterations, out nanosecondsPerOp)
    }

    if workload == 4 {
        return TimeMinMaxDelta(values, warmup, iterations, out nanosecondsPerOp)
    }

    return TimeParseEightDigits(values, warmup, iterations, out nanosecondsPerOp)
}

// The ports' quantile convention: the nearest sample by `round((n - 1) * p)`, rounding halves away
// from zero. `Math.Round` is banker's rounding by default, so the index is computed directly.
func Percentile(sorted: double[], fraction: double): double {
    scaled := (double)(sorted.Length - 1) * fraction
    return sorted[(int)(scaled + 0.5)]
}

[boundary]
func Format(value: double): string {
    return value.ToString("F3", CultureInfo.InvariantCulture)
}

func WorkloadIndex(key: string): int {
    keys := WorkloadKeys()
    for i := 0; i < keys.Length; i++ {
        if keys[i] == key {
            return i
        }
    }

    return -1
}

// `only` is a workload index, or -1 for all six.
func FirstWorkload(only: int): int {
    if only < 0 {
        return 0
    }

    return only
}

func LastWorkload(only: int): int {
    if only < 0 {
        return 5
    }

    return only
}

// `requestedTrials` is the `--trials` override, or -1 to use each workload's port-matched default.
func TrialsFor(workload: int, requestedTrials: int): int {
    if requestedTrials > 0 {
        return requestedTrials
    }

    return DefaultTrials(workload)
}

[boundary]
func ReportVerify(only: int): int {
    keys := WorkloadKeys()
    sizes := Sizes()
    inputs := new int[][](2)
    inputs[0] = BuildInput(sizes[0])
    inputs[1] = BuildInput(sizes[1])
    for workload := FirstWorkload(only); workload <= LastWorkload(only); workload++ {
        for s := 0; s < sizes.Length; s++ {
            result := RunWorkload(workload, inputs[s])
            Console.WriteLine(keys[workload] + " " + sizes[s].ToString(CultureInfo.InvariantCulture) + " result=" + result.ToString(CultureInfo.InvariantCulture))
        }
    }

    return 0
}

[boundary]
func ReportIlShape(only: int): int {
    keys := WorkloadKeys()
    names := KernelNames()
    for workload := FirstWorkload(only); workload <= LastWorkload(only); workload++ {
        Console.WriteLine(keys[workload] + " simd=" + IlShape.SimdHelpersFor(names[workload]))
    }

    return 0
}

[boundary]
func ReportTimings(only: int, requestedTrials: int): int {
    keys := WorkloadKeys()
    sizes := Sizes()
    inputs := new int[][](2)
    inputs[0] = BuildInput(sizes[0])
    inputs[1] = BuildInput(sizes[1])
    sink: long = 0
    for workload := FirstWorkload(only); workload <= LastWorkload(only); workload++ {
        trials := TrialsFor(workload, requestedTrials)
        warmup := WarmupIterations(workload)
        for s := 0; s < sizes.Length; s++ {
            iterations := MeasuredIterations(workload, sizes[s])
            settleSink := SettleJit(workload, inputs[s])
            sink = sink ^ settleSink
            samples := new double[](trials)
            for t := 0; t < trials; t++ {
                sample := 0.0
                trialSink := RunTrial(workload, inputs[s], warmup, iterations, out sample)
                sink = sink ^ trialSink
                samples[t] = sample
            }

            Array.Sort(samples)
            median := Percentile(samples, 0.5)
            q1 := Percentile(samples, 0.25)
            q3 := Percentile(samples, 0.75)
            sizeText := sizes[s].ToString(CultureInfo.InvariantCulture)
            Console.WriteLine(keys[workload] + " " + sizeText + " " + Format(median))
            Console.Error.WriteLine(keys[workload] + " " + sizeText + " median=" + Format(median) + " min=" + Format(samples[0]) + " iqr=" + Format(q3 - q1) + " (q1=" + Format(q1) + " q3=" + Format(q3) + ") ns/op iters=" + iterations.ToString(CultureInfo.InvariantCulture) + " trials=" + trials.ToString(CultureInfo.InvariantCulture))
        }
    }

    Console.WriteLine("sink " + sink.ToString(CultureInfo.InvariantCulture))
    return 0
}

[boundary]
func Main(args: string[]): int {
    requestedTrials := -1
    only := -1
    verify := false
    ilShape := false
    index := 0
    while index < args.Length {
        argument := args[index]
        if argument == "--trials" {
            index = index + 1
            if index >= args.Length {
                Console.Error.WriteLine("--trials needs a trial count")
                return 2
            }

            parsed := 0
            if !Int32.TryParse(args[index], out parsed) || parsed < 1 {
                Console.Error.WriteLine("--trials needs a positive integer, got '" + args[index] + "'")
                return 2
            }

            requestedTrials = parsed
        } else if argument == "--only" {
            index = index + 1
            if index >= args.Length {
                Console.Error.WriteLine("--only needs a workload key")
                return 2
            }

            only = WorkloadIndex(args[index])
            if only < 0 {
                Console.Error.WriteLine("unknown workload '" + args[index] + "'; expected one of checksum-sum count-ascii count-transitions rolling-hash min-max-delta parse-eight-digits")
                return 2
            }
        } else if argument == "--verify" {
            verify = true
        } else if argument == "--il-shape" {
            ilShape = true
        } else {
            Console.Error.WriteLine("unknown argument '" + argument + "'; expected --trials, --only, --verify or --il-shape")
            return 2
        }

        index = index + 1
    }

    if ilShape {
        return ReportIlShape(only)
    }

    if verify {
        return ReportVerify(only)
    }

    return ReportTimings(only, requestedTrials)
}
