namespace NSharpLang.NativeComparisonRunner

import System
import System.Collections.Generic
import System.Globalization
import System.Text


// THE ARTEFACTS A `compare` RUN LEAVES BEHIND, AND THE TABLE IT PRINTS.
//
//   results.csv       one row per (workload, size, language) — the machine-readable record
//   results.md        the header block, the twelve-row comparison table, and the stability lines
//   raw-stdout.log    every line the children wrote, prefixed with `[<language> <workload>]`
//   raw-stderr.log    the same for stderr
//
// WHY THE RAW LOGS EXIST AT ALL. The CSV and the table are both DERIVED, and the derivation drops
// things: the stderr shapes differ port by port and the parser keeps only six fields out of them.
// When a number looks wrong the question is always "what did the port actually print", and the raw
// logs are the only place that answers it without re-running a twenty-minute measurement.
//
// WHY A MISSING FIELD IS AN EMPTY CSV CELL. Four of the six Rust/C stderr shapes omit at least one
// of min/q1/q3/iters/trials. Writing a zero would make a reader — or a script — believe the port
// measured zero; an empty cell says the port did not report it, which is the truth.
//
// WHY THE `June N#/best-native` COLUMN DIVIDES JUNE BY JUNE. Today's `N#/best-native` and June's sit
// side by side so a reader can see whether the GAP to native moved, independently of whether the
// machine got faster. A ratio that mixed the two eras would confound them.
class RunCapture {
    Language: string
    Workload: string
    Stdout: string
    Stderr: string

    constructor(language: string, workload: string, stdout: string, stderr: string) {
        Language = language
        Workload = workload
        Stdout = stdout
        Stderr = stderr
    }
}

// Everything the report header states about the machine and the toolchains. Every field defaults to
// `unknown` so that one unavailable probe costs one cell, not the run.
class RunEnvironment {
    CommitShort: string
    CommitFull: string
    TimestampUtc: string
    CpuBrand: string
    Architecture: string
    CoreCount: string
    LoadAverage: string
    DotnetVersion: string
    RustcVersion: string
    ClangVersion: string
    RuntimePath: string
    RuntimeSizeBytes: long

    constructor() {
        CommitShort = "unknown"
        CommitFull = "unknown"
        TimestampUtc = ""
        CpuBrand = "unknown"
        Architecture = "unknown"
        CoreCount = "unknown"
        LoadAverage = "unknown"
        DotnetVersion = "unknown"
        RustcVersion = "unknown"
        ClangVersion = "unknown"
        RuntimePath = "unknown"
        RuntimeSizeBytes = -1
    }
}

// Everything `results.md` is written from, gathered so that the writer takes one argument instead of
// six. Assembled by `compare` after the last child has been read.
class ReportData {
    Environment: RunEnvironment
    Measurements: List<Measurement>
    IlShapes: List<IlShapeAnswer>
    Commands: List<string>
    TrialsLabel: string
    Captures: List<RunCapture>

    constructor() {
        Environment = new RunEnvironment()
        Measurements = new List<Measurement>()
        IlShapes = new List<IlShapeAnswer>()
        Commands = new List<string>()
        TrialsLabel = ""
        Captures = new List<RunCapture>()
    }
}

func NsharpLanguageKey(): string {
    return "nsharp"
}

func RustLanguageKey(): string {
    return "rust"
}

func CLanguageKey(): string {
    return "c"
}

func ReportLanguages(): string[] {
    languages := new string[](3)
    languages[0] = NsharpLanguageKey()
    languages[1] = RustLanguageKey()
    languages[2] = CLanguageKey()
    return languages
}

func LanguageDisplayName(language: string): string {
    if language == NsharpLanguageKey() {
        return "N#"
    }
    if language == RustLanguageKey() {
        return "Rust"
    }
    if language == CLanguageKey() {
        return "C"
    }
    return language
}

func FormatNanoseconds(value: double): string {
    if value < 0.0 {
        return "n/a"
    }
    return value.ToString("F3", CultureInfo.InvariantCulture)
}

func FormatRatio(value: double): string {
    if value < 0.0 {
        return "n/a"
    }
    return value.ToString("F2", CultureInfo.InvariantCulture) + "x"
}

func FormatCsvNumber(value: double): string {
    if value < 0.0 {
        return ""
    }
    return value.ToString("F3", CultureInfo.InvariantCulture)
}

func FormatCsvCount(value: long): string {
    if value < 0 {
        return ""
    }
    return value.ToString()
}

// A ratio, or the missing sentinel when either side is absent. Nothing here divides by zero.
func SafeRatio(numerator: double, denominator: double): double {
    if numerator < 0.0 || denominator <= 0.0 {
        return MissingNumber()
    }
    return numerator / denominator
}

func MarkdownRow(cells: List<string>): string {
    return "| " + String.Join(" | ", cells) + " |"
}

func ResultsCsvHeader(): string {
    return "workload,size,language,median_ns,min_ns,q1_ns,q3_ns,iters,trials"
}

// One row per (workload, size, language), in protocol order with the three languages together, so
// the file diffs cleanly between runs.
func BuildResultsCsv(measurements: List<Measurement>): string {
    builder := new StringBuilder()
    builder.AppendLine(ResultsCsvHeader())

    workloads := WorkloadKeys()
    sizes := BenchmarkSizes()
    languages := ReportLanguages()

    for w := 0; w < workloads.Length; w++ {
        for s := 0; s < sizes.Length; s++ {
            for l := 0; l < languages.Length; l++ {
                index := IndexOfMeasurement(measurements, workloads[w], sizes[s], languages[l])
                if index >= 0 {
                    builder.AppendLine(BuildCsvRow(measurements[index]))
                }
            }
        }
    }

    return builder.ToString()
}

func BuildCsvRow(entry: Measurement): string {
    cells := new List<string>()
    cells.Add(entry.Workload)
    cells.Add(entry.Size.ToString())
    cells.Add(entry.Language)
    cells.Add(FormatCsvNumber(entry.MedianNs))
    cells.Add(FormatCsvNumber(entry.MinNs))
    cells.Add(FormatCsvNumber(entry.Q1Ns))
    cells.Add(FormatCsvNumber(entry.Q3Ns))
    cells.Add(FormatCsvCount(entry.Iters))
    cells.Add(FormatCsvCount(Convert.ToInt64(entry.Trials)))
    return String.Join(",", cells)
}

func ComparisonTableHeader(): string {
    names := new List<string>()
    names.Add("Workload")
    names.Add("Size")
    names.Add("N# ns")
    names.Add("Rust ns")
    names.Add("C ns")
    names.Add("best-native")
    names.Add("N#/best-native")
    names.Add("June N# ns")
    names.Add("today/June N#")
    names.Add("June N#/best-native")
    names.Add("vectorized")

    alignments := new List<string>()
    alignments.Add("---")
    for i := 1; i < names.Count - 1; i++ {
        alignments.Add("---:")
    }
    alignments.Add("---")

    return MarkdownRow(names) + "\n" + MarkdownRow(alignments)
}

// The twelve-row comparison table. Written into `results.md` and printed verbatim to stdout, so
// what a reader sees in the terminal is byte-for-byte what the file records.
func BuildComparisonTable(measurements: List<Measurement>, ilShapes: List<IlShapeAnswer>): string {
    builder := new StringBuilder()
    builder.AppendLine(ComparisonTableHeader())

    juneRows := JuneRows()
    workloads := WorkloadKeys()
    sizes := BenchmarkSizes()

    for w := 0; w < workloads.Length; w++ {
        for s := 0; s < sizes.Length; s++ {
            row := BuildComparisonRow(measurements, juneRows, ilShapes, workloads[w], sizes[s])
            builder.AppendLine(row)
        }
    }

    return builder.ToString()
}

func BuildComparisonRow(measurements: List<Measurement>, juneRows: List<JuneRow>, ilShapes: List<IlShapeAnswer>, workload: string, size: int): string {
    nsharpNs := MedianFor(measurements, workload, size, NsharpLanguageKey())
    rustNs := MedianFor(measurements, workload, size, RustLanguageKey())
    cNs := MedianFor(measurements, workload, size, CLanguageKey())
    bestNativeNs := BestNativeNanoseconds(rustNs, cNs)

    juneNsharpNs := MissingNumber()
    juneGap := MissingNumber()
    juneIndex := IndexOfJuneRow(juneRows, workload, size)
    if juneIndex >= 0 {
        juneRow := juneRows[juneIndex]
        juneNsharpNs = juneRow.NsharpNs
        juneGap = SafeRatio(juneRow.NsharpNs, juneRow.BestNativeNs())
    }

    cells := new List<string>()
    cells.Add(workload)
    cells.Add(size.ToString())
    cells.Add(FormatNanoseconds(nsharpNs))
    cells.Add(FormatNanoseconds(rustNs))
    cells.Add(FormatNanoseconds(cNs))
    cells.Add(FormatBestNative(rustNs, cNs))
    cells.Add(FormatRatio(SafeRatio(nsharpNs, bestNativeNs)))
    cells.Add(FormatNanoseconds(juneNsharpNs))
    cells.Add(FormatJuneDrift(SafeRatio(nsharpNs, juneNsharpNs)))
    cells.Add(FormatRatio(juneGap))
    cells.Add(IlShapeFor(ilShapes, workload))
    return MarkdownRow(cells)
}

func FormatBestNative(rustNs: double, cNs: double): string {
    bestNativeNs := BestNativeNanoseconds(rustNs, cNs)
    if bestNativeNs < 0.0 {
        return "n/a"
    }
    return FormatNanoseconds(bestNativeNs) + " (" + BestNativeName(rustNs, cNs) + ")"
}

func FormatJuneDrift(ratio: double): string {
    text := FormatRatio(ratio)
    if ratio >= 0.0 && ratio > JuneRegressionFlagRatio() {
        text = text + " **REGRESSED**"
    }
    return text
}

func MedianFor(measurements: List<Measurement>, workload: string, size: int, language: string): double {
    index := IndexOfMeasurement(measurements, workload, size, language)
    if index < 0 {
        return MissingNumber()
    }
    return measurements[index].MedianNs
}

func BestNativeNanoseconds(rustNs: double, cNs: double): double {
    if rustNs < 0.0 {
        return cNs
    }
    if cNs < 0.0 {
        return rustNs
    }
    return Math.Min(rustNs, cNs)
}

func BestNativeName(rustNs: double, cNs: double): string {
    if rustNs < 0.0 {
        return "C"
    }
    if cNs < 0.0 {
        return "Rust"
    }
    if rustNs <= cNs {
        return "Rust"
    }
    return "C"
}

// Every flagged cell, one line each, for the terminal summary printed after the table.
func RegressionNotices(measurements: List<Measurement>): List<string> {
    notices := new List<string>()
    juneRows := JuneRows()
    workloads := WorkloadKeys()
    sizes := BenchmarkSizes()

    for w := 0; w < workloads.Length; w++ {
        for s := 0; s < sizes.Length; s++ {
            juneIndex := IndexOfJuneRow(juneRows, workloads[w], sizes[s])
            if juneIndex < 0 {
                continue
            }
            juneNs := juneRows[juneIndex].NsharpNs
            measured := MedianFor(measurements, workloads[w], sizes[s], NsharpLanguageKey())
            ratio := SafeRatio(measured, juneNs)
            if ratio >= 0.0 && ratio > JuneRegressionFlagRatio() {
                notice := "REGRESSED vs June: " + workloads[w] + " " + sizes[s].ToString()
                notice = notice + " is " + FormatRatio(ratio) + " of " + FormatNanoseconds(juneNs) + " ns"
                notices.Add(notice)
            }
        }
    }

    return notices
}

func BuildResultsMarkdown(report: ReportData): string {
    builder := new StringBuilder()
    builder.AppendLine("# native-comparison results — " + report.Environment.TimestampUtc)
    builder.AppendLine("")
    AppendEnvironmentBlock(builder, report.Environment, report.TrialsLabel)
    builder.AppendLine("")
    builder.AppendLine("## Commands")
    builder.AppendLine("")
    builder.AppendLine("```")
    for i := 0; i < report.Commands.Count; i++ {
        builder.AppendLine(report.Commands[i])
    }
    builder.AppendLine("```")
    builder.AppendLine("")
    builder.AppendLine("## Comparison")
    builder.AppendLine("")
    builder.Append(BuildComparisonTable(report.Measurements, report.IlShapes))
    builder.AppendLine("")
    AppendColumnLegend(builder)
    builder.AppendLine("")
    builder.Append(BuildStabilitySection(report.Captures))
    return builder.ToString()
}

func AppendEnvironmentBlock(builder: StringBuilder, environment: RunEnvironment, trialsLabel: string) {
    commit := "`" + environment.CommitShort + "` (`" + environment.CommitFull + "`)"
    machine := environment.CpuBrand + " (" + environment.Architecture + ", "
    machine = machine + environment.CoreCount + " cores)"
    june := JuneBaselineDate() + " (commit " + JuneBaselineCommit() + ")"

    builder.AppendLine("- Commit: " + commit)
    builder.AppendLine("- CPU: " + machine)
    builder.AppendLine("- Load average at start: " + environment.LoadAverage)
    builder.AppendLine("- dotnet: " + environment.DotnetVersion)
    builder.AppendLine("- rustc: " + environment.RustcVersion)
    builder.AppendLine("- clang: " + environment.ClangVersion)
    builder.AppendLine("- runtime: `" + environment.RuntimePath + "` (" + FormatCsvCount(environment.RuntimeSizeBytes) + " bytes) — copied over the kernel program's")
    builder.AppendLine("  own `NSharpLang.Runtime.dll` after `nlc build`. A Debug runtime carries")
    builder.AppendLine("  `DebuggableAttribute(DisableOptimizations)`, which makes the JIT compile every")
    builder.AppendLine("  `SimdReductions` helper at minopts and understates the vectorized kernels by 3-4x.")
    builder.AppendLine("- Rust flags: `" + RustOptimizationFlags() + "`")
    builder.AppendLine("- C flags: `" + ClangOptimizationFlags() + "`")
    builder.AppendLine("- Trials: " + trialsLabel)
    builder.AppendLine("- June baseline: " + june)
}

func AppendColumnLegend(builder: StringBuilder) {
    flag := FormatRatio(JuneRegressionFlagRatio())
    builder.AppendLine("`best-native` is the faster of Rust and C for that cell. `today/June N#`")
    builder.AppendLine("compares this run's N# median with the " + JuneBaselineDate() + " N# median")
    builder.AppendLine("and is flagged **REGRESSED** above " + flag + ". `June N#/best-native` divides")
    builder.AppendLine("June's N# by June's OWN best native, so it reads directly beside today's")
    builder.AppendLine("`N#/best-native`. `vectorized` is the workload's `--il-shape` answer: the")
    builder.AppendLine("`SimdReductions` helpers the emitted kernel actually calls, or `none`.")
}

// Every stability line the children wrote, verbatim, grouped by language. Verbatim matters: the six
// stderr shapes disagree, and the parser's normalisation is exactly what a reader checking a
// suspicious number needs to be able to look behind.
func BuildStabilitySection(captures: List<RunCapture>): string {
    builder := new StringBuilder()
    builder.AppendLine("## Stability")
    builder.AppendLine("")

    languages := ReportLanguages()
    for l := 0; l < languages.Length; l++ {
        builder.AppendLine("### " + LanguageDisplayName(languages[l]))
        builder.AppendLine("")
        builder.AppendLine("```")
        AppendStabilityLines(builder, captures, languages[l])
        builder.AppendLine("```")
        builder.AppendLine("")
    }

    return builder.ToString()
}

func AppendStabilityLines(builder: StringBuilder, captures: List<RunCapture>, language: string) {
    for c := 0; c < captures.Count; c++ {
        capture := captures[c]
        if capture.Language != language {
            continue
        }
        lines := SplitLines(capture.Stderr)
        for i := 0; i < lines.Length; i++ {
            line := lines[i].TrimEnd()
            if line != "" {
                builder.AppendLine(line)
            }
        }
    }
}

func BuildRawLog(captures: List<RunCapture>, readStderr: bool): string {
    builder := new StringBuilder()
    for c := 0; c < captures.Count; c++ {
        capture := captures[c]
        text := capture.Stdout
        if readStderr {
            text = capture.Stderr
        }
        prefix := "[" + capture.Language + " " + capture.Workload + "] "
        lines := SplitLines(text)
        for i := 0; i < lines.Length; i++ {
            line := lines[i].TrimEnd()
            if line != "" {
                builder.AppendLine(prefix + line)
            }
        }
    }
    return builder.ToString()
}
