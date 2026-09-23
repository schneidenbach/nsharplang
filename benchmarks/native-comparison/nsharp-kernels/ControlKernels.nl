namespace NSharpLang.NativeComparison


// THE THROUGHPUT GATE'S CONTROL: THE 2026-09-01 REFERENCE KERNELS, FROZEN.
//
// WHAT THIS FILE IS. `SystemsThroughputBaseline.nl` used to be the gate's only reference: twelve
// nanosecond medians measured once, on 2026-09-01, on an idle Apple M4 at commit 8cf40128a. A
// stored nanosecond is a measurement of ONE machine in ONE state, so a gate that compares today's
// nanoseconds against it fails whenever the machine is busier than that machine was — which is what
// happened repeatedly (`count-transitions` tripped at 1.2x-1.75x under a concurrent build while
// passing at 0.95x-1.06x on a quiet box). The stored numbers were not wrong; they were being asked
// a question they cannot answer.
//
// So the reference moved from a NUMBER to a PROGRAM. This class is the reference implementation the
// 2026-09-01 medians were taken from, transcribed here so the gate can re-measure it in the same
// run, on the same machine, in the same load, interleaved with the live kernels. The gate's verdict
// is then `live / control`, a ratio of two medians taken microseconds apart, and machine load
// cancels out of it.
//
// WHY IT IS AN N# COPY AND NOT THE ORIGINAL C#. The bodies below and the ones in `Kernels.nl` share
// one ancestor: `benchmarks/SystemsHotPathBenchmarks.cs`, deleted at a50cb4000 with the rest of the
// C# export tooling and its BenchmarkDotNet harness. That file is gone, its harness is not coming
// back, and the ownership ratchet (`tests/native/ownership-audit`) refuses any NEW non-N# file
// (OWN003) — so the control is transcribed into the kernel program in N#, exactly as `Kernels.nl`
// itself was.
//
// WHAT THE CONTROL CAN AND CANNOT SEE, STATED PLAINLY. Control and live are compiled by the same
// `nlc` in the same build, so a compiler change that de-vectorizes THIS SHAPE moves both sides
// together and the ratio does not notice. That failure mode is not left unguarded: the gate also
// reads the emitted IL back at run time (`--il-shape`, `IlShape.nl`) and fails when a kernel that
// must lower to a `SimdReductions` helper no longer does — a deterministic check, and a strictly
// better one than a timing threshold ever was. The ratio's job is the other half: a change to
// `Kernels.nl`, or to the lowering of the specific shape `Kernels.nl` uses and this file does not,
// that costs throughput.
//
// THIS FILE IS FROZEN. It is the reference, not a kernel under test. Do not "improve" a body, do not
// reshape a loop, do not add or drop `[hot]`, and do not refactor the two classes into one shared
// implementation — a control that moves with the subject measures nothing. The only legitimate edit
// is a deliberate, documented re-baselining, which also means re-measuring
// `SystemsThroughputBaseline.nl`'s informational drift rows in the same session.
//
// The bodies are byte-identical to `Kernels.nl`'s as of 2026-09-23, including the shapes the
// columnar vectorizer matches on (`len := values.Length` hoisted, `for i := 0; i < len; i++`, the
// `value := values[i]` temp, `count = count + 1` rather than `count++`). That is the point: both
// sides start from the same shape, so the ratio starts at 1.00x and only a real change moves it.
class ControlKernels {
    [hot]
    static func Checksum(values: int[]): int {
        sum := 0
        len := values.Length
        for i := 0; i < len; i++ {
            sum = sum + values[i]
        }

        return sum
    }

    [hot]
    static func CountAscii(values: int[]): int {
        count := 0
        len := values.Length
        for i := 0; i < len; i++ {
            value := values[i]
            if value >= 32 && value <= 126 {
                count = count + 1
            }
        }

        return count
    }

    [hot]
    static func MinMaxDelta(values: int[]): int {
        if values.Length == 0 {
            return 0
        }

        min := values[0]
        max := values[0]
        len := values.Length
        for i := 1; i < len; i++ {
            value := values[i]
            if value < min {
                min = value
            }

            if value > max {
                max = value
            }
        }

        return max - min
    }

    [hot]
    static func RollingHash(values: int[]): int {
        hash := 17
        len := values.Length
        for i := 0; i < len; i++ {
            hash = ((hash * 31) + values[i]) & 65535
        }

        return hash
    }

    [hot]
    static func ParseEightDigits(values: int[]): int {
        if values.Length < 8 {
            return -1
        }

        parsed := 0
        for i := 0; i < 8; i++ {
            value := values[i]
            if value < 48 || value > 57 {
                return -1
            }

            parsed = parsed * 10 + (value - 48)
        }

        return parsed
    }

    [hot]
    static func CountTransitions(values: int[]): int {
        if values.Length == 0 {
            return 0
        }

        transitions := 0
        previous := values[0]
        len := values.Length
        for i := 1; i < len; i++ {
            current := values[i]
            if current != previous {
                transitions = transitions + 1
            }

            previous = current
        }

        return transitions
    }
}
