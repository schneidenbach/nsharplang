namespace NSharpLang.NativeComparisonRunner

import System
import System.Collections.Generic
import System.Globalization


// THE THREE-LANGUAGE OUTPUT PROTOCOL, PARSED.
//
// Every port — the N# kernel program, the six Rust ports, the six C ports — prints ONE
// machine-readable line per (workload, size) on stdout:
//
//     <workload> <size> <ns_per_op>
//
// That line is the contract, it is identical in all three languages, and `MedianNs` is always read
// from it. The runner never reads a median from anywhere else.
//
// THE STABILITY LINE ON STDERR IS NOT UNIFORM, AND THAT IS WHY THIS PARSER IS SHAPED THE WAY IT IS.
// The six Rust/C port pairs were written at different times and print five different stderr shapes:
//
//     checksum-sum        # <key> size=<n> sink=<v> min= q1= q3= iqr= trials=      (no median=)
//     count-ascii         <key> <n> median= min= iqr= ns/op                        (no q1/q3/trials)
//     count-transitions   <key> <n> median= min= iqr= (q1= q3=) ns/op trials=
//     min-max-delta       <key> <n> median= min= iqr= (q1= q3=) iters= trials=
//     rolling-hash        rolling-hash size=<n> median= min= iqr=[q1,q3] ns/op (iters=, trials=)
//     parse-eight-digits  <key> <n> median= min= iqr=[q1,q3] ns/op                 (no iters/trials)
//
// So the stderr reader is a TOLERANT key=value scan rather than a positional one: it strips the
// `(`, `)` and `,` that wrap tokens in three of those shapes, understands both the scalar `iqr=`
// and the bracketed `iqr=[q1,q3]` spelling, and leaves any field the port did not print at the
// `MissingNumber` sentinel. A missing field is written as an EMPTY CSV cell, never as a zero — a
// zero would read as a measurement, and none of these ports measured zero nanoseconds.
//
// Rewriting the twelve native ports to one stderr shape would be the other way to solve this, and
// it is deliberately not taken: the ports are the historical measurement baseline, and editing them
// to suit a new reader would invalidate the numbers already published against them.
class Measurement {
    Workload: string
    Size: int
    Language: string
    MedianNs: double
    MinNs: double
    Q1Ns: double
    Q3Ns: double
    Iters: long
    Trials: int

    constructor(workload: string, size: int, language: string, medianNs: double) {
        Workload = workload
        Size = size
        Language = language
        MedianNs = medianNs
        MinNs = MissingNumber()
        Q1Ns = MissingNumber()
        Q3Ns = MissingNumber()
        Iters = MissingCount()
        Trials = MissingCount()
    }
}

// One workload's answer to `--il-shape`: the `SimdReductions` helpers the emitted kernel actually
// calls, or `none`. This is what the report's `vectorized` column states.
class IlShapeAnswer {
    Workload: string
    Simd: string

    constructor(workload: string, simd: string) {
        Workload = workload
        Simd = simd
    }
}

// Nanoseconds are positive and counts are positive, so a negative value can carry "the port did not
// print this" without colliding with any real measurement.
func MissingNumber(): double {
    return -1.0
}

func MissingCount(): int {
    return -1
}

// The workload keys in protocol order — the order the kernel program prints them in, the order the
// runner runs them in, and the order every report table is written in.
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

func BenchmarkSizes(): int[] {
    sizes := new int[](2)
    sizes[0] = 64
    sizes[1] = 4096
    return sizes
}

func IsWorkloadKey(candidate: string): bool {
    keys := WorkloadKeys()
    for i := 0; i < keys.Length; i++ {
        if keys[i] == candidate {
            return true
        }
    }
    return false
}

func SplitLines(text: string): string[] {
    return text.Replace("\r\n", "\n").Split('\n')
}

// Strip the wrappers three of the stderr shapes put around a `key=value` token: `(q1=4.150` and
// `trials=15)` and `(iters=2000000,`. `]` is deliberately NOT stripped, because the bracketed
// `iqr=[q1,q3]` spelling needs both of its brackets to be recognised as that spelling.
func StripWrappers(token: string): string {
    text := token
    while text.StartsWith("(") {
        text = text.Substring(1)
    }
    while text.EndsWith(")") || text.EndsWith(",") {
        text = text.Substring(0, text.Length - 1)
    }
    return text
}

func ParseDoubleOrMissing(text: string): double {
    value := 0.0
    if Double.TryParse(text, CultureInfo.InvariantCulture, out value) {
        return value
    }
    return MissingNumber()
}

func ParseIntOrMissing(text: string): int {
    value := 0
    if Int32.TryParse(text, out value) {
        return value
    }
    return MissingCount()
}

// The stdout reader. Anything that is not exactly `<workload> <size> <number>` — the `sink <value>`
// line, a blank line, a stray note — is ignored rather than treated as an error, because the ports
// do not agree on whether they print a sink line at all (checksum-sum folds its sink into stderr).
func ParseMeasurementLines(language: string, stdout: string): List<Measurement> {
    measurements := new List<Measurement>()
    lines := SplitLines(stdout)
    for i := 0; i < lines.Length; i++ {
        tokens := SignificantTokens(lines[i])
        if tokens.Count != 3 {
            continue
        }
        if !IsWorkloadKey(tokens[0]) {
            continue
        }
        size := ParseIntOrMissing(tokens[1])
        median := ParseDoubleOrMissing(tokens[2])
        if size < 0 || median < 0.0 {
            continue
        }
        measurements.Add(new Measurement(tokens[0], size, language, median))
    }
    return measurements
}

// The `--il-shape` reader: `<workload> simd=<names or none>`.
func ParseIlShapeLines(stdout: string): List<IlShapeAnswer> {
    answers := new List<IlShapeAnswer>()
    lines := SplitLines(stdout)
    for i := 0; i < lines.Length; i++ {
        tokens := SignificantTokens(lines[i])
        if tokens.Count != 2 {
            continue
        }
        if !IsWorkloadKey(tokens[0]) || !tokens[1].StartsWith("simd=") {
            continue
        }
        answers.Add(new IlShapeAnswer(tokens[0], tokens[1].Substring(5)))
    }
    return answers
}

func IlShapeFor(answers: List<IlShapeAnswer>, workload: string): string {
    for i := 0; i < answers.Count; i++ {
        answer := answers[i]
        if answer.Workload == workload {
            return answer.Simd
        }
    }
    return "unknown"
}

// The tolerant stderr reader described in this file's header. It fills only fields that are still
// missing, so a port that states `q1=`/`q3=` outright wins over the bracketed `iqr=[q1,q3]` form.
func ApplyStabilityLines(measurements: List<Measurement>, language: string, stderr: string) {
    lines := SplitLines(stderr)
    for i := 0; i < lines.Length; i++ {
        ApplyOneStabilityLine(measurements, language, lines[i])
    }
}

func ApplyOneStabilityLine(measurements: List<Measurement>, language: string, line: string) {
    tokens := SignificantTokens(line)
    workload := ""
    size := MissingCount()
    minNs := MissingNumber()
    q1 := MissingNumber()
    q3 := MissingNumber()
    bracketQ1 := MissingNumber()
    bracketQ3 := MissingNumber()
    iters := MissingNumber()
    trials := MissingCount()

    for i := 0; i < tokens.Count; i++ {
        token := StripWrappers(tokens[i])
        if token == "" || token == "#" {
            continue
        }

        separator := token.IndexOf('=')
        if separator <= 0 {
            if workload == "" && IsWorkloadKey(token) {
                workload = token
            } else if size < 0 {
                size = ParseIntOrMissing(token)
            }
            continue
        }

        key := token.Substring(0, separator)
        value := token.Substring(separator + 1)
        if key == "size" {
            size = ParseIntOrMissing(value)
        } else if key == "min" {
            minNs = ParseDoubleOrMissing(value)
        } else if key == "q1" {
            q1 = ParseDoubleOrMissing(value)
        } else if key == "q3" {
            q3 = ParseDoubleOrMissing(value)
        } else if key == "iters" {
            iters = ParseDoubleOrMissing(value)
        } else if key == "trials" {
            trials = ParseIntOrMissing(value)
        } else if key == "iqr" && value.StartsWith("[") && value.EndsWith("]") {
            halves := value.Substring(1, value.Length - 2).Split(',')
            if halves.Length == 2 {
                bracketQ1 = ParseDoubleOrMissing(halves[0])
                bracketQ3 = ParseDoubleOrMissing(halves[1])
            }
        }
    }

    if workload == "" || size < 0 {
        return
    }

    index := IndexOfMeasurement(measurements, workload, size, language)
    if index < 0 {
        return
    }

    entry := measurements[index]
    if entry.MinNs < 0.0 {
        entry.MinNs = minNs
    }
    if entry.Q1Ns < 0.0 {
        if q1 >= 0.0 {
            entry.Q1Ns = q1
        } else {
            entry.Q1Ns = bracketQ1
        }
    }
    if entry.Q3Ns < 0.0 {
        if q3 >= 0.0 {
            entry.Q3Ns = q3
        } else {
            entry.Q3Ns = bracketQ3
        }
    }
    if entry.Iters < 0 && iters >= 0.0 {
        entry.Iters = Convert.ToInt64(iters)
    }
    if entry.Trials < 0 {
        entry.Trials = trials
    }
}

func IndexOfMeasurement(measurements: List<Measurement>, workload: string, size: int, language: string): int {
    for i := 0; i < measurements.Count; i++ {
        entry := measurements[i]
        if entry.Workload == workload && entry.Size == size && entry.Language == language {
            return i
        }
    }
    return -1
}

// Whitespace-separated tokens with the empties dropped, so a double space or a trailing newline in
// a child's output cannot shift a positional read.
func SignificantTokens(line: string): List<string> {
    tokens := new List<string>()
    parts := line.Replace("\t", " ").Split(' ')
    for i := 0; i < parts.Length; i++ {
        part := parts[i].Trim()
        if part != "" {
            tokens.Add(part)
        }
    }
    return tokens
}
