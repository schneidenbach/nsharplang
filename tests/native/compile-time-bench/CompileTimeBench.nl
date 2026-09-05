namespace NSharpLang.CompileTimeBench

import System
import System.Collections.Generic
import System.IO
import System.Text
import System.Text.Json


// THE PURE KERNELS OF THE COMPILE-TIME BENCHMARK.
//
// Everything in this file is a function of its arguments and, at most, of the file system's
// CONTENT. Nothing here starts a process, and nothing here writes. The process side lives in
// `CompileTimeRunner.nl`, the entry point in `Program.nl`, and every claim these kernels make is
// stated as a test in `CompileTimeBench.tests.nl`.
//
// WHY THE SOURCE-SELECTION RULE IS REPLICATED RATHER THAN GUESSED. A lines-per-second number is
// only meaningful if the numerator is the source the command actually read. `nlc build` reaches
// its source list through `ProjectConfig.GetSourceFiles(projectRoot, includeTests: false)`
// (`Program.Backends.cs` -> `CompileProjectWithIlBackend`), and `nlc check` reaches the SAME
// function through `CodeIntelligenceService.LoadProject` ->
// `MultiFileCompilerInputBuilder.BuildFromProject` -> `CompilerBootstrapServices.DiscoverSourceFiles`,
// which also passes `false`. So build and check read one file set, not two, and this file
// replicates that one rule: a recursive `*.nl` walk that skips the directory names
// `ProjectConfig.ShouldSkipSourceDirectory` skips, minus the paths ending in `.tests.nl`. The
// replication is not trusted on its word either — every measured row cross-checks its own file
// count against the `checkedFiles` field of `nlc check --json`, which is
// `snapshot.SourceFiles.Count` straight from the compiler.
//
// WHAT IS NOT REPLICATED, AND WHY THAT IS SAFE HERE. `ProjectSourceFileFilter` also drops paths
// matching the `exclude:` globs of `project.yml`. No project.yml in the measured corpus declares
// `exclude:`, so porting its glob engine would add an unreachable branch; the live `checkedFiles`
// cross-check is what would catch a project that started declaring one, and it reports the
// mismatch as a named row rather than silently mis-measuring.

// ─── SMALL TEXT AND NUMBER KERNELS ────────────────────────────────────────────────────────────
func BenchLongText(value: long): string {
    return value.ToString() ?? ""
}

func BenchIntText(value: int): string {
    return value.ToString() ?? ""
}

// A count the platform may have refused to answer renders as `unknown`, never as `-1`.
func BenchCountText(value: int): string {
    if value < 0 {
        return "unknown"
    }

    return BenchIntText(value)
}

func BenchBoolText(value: bool): string {
    if value {
        return "true"
    }

    return "false"
}

// Digits only, no sign, no separators: `-1` for anything else. A hand-rolled parse rather than
// `long.TryParse` because the `out` arity is not expressible on this emit path, and every number
// this harness reads (a timing, an RSS byte count, a `--runs` operand) is unsigned decimal.
func BenchParseLong(text: string): long {
    if text.Length == 0 {
        return -1
    }

    value := 0L
    i := 0
    while i < text.Length {
        c := text[i]
        if c < '0' || c > '9' {
            return -1
        }

        value = value * 10 + (c - '0')
        i = i + 1
    }

    return value
}

// The same parse narrowed to a run count: digits only, at least one, at most a thousand. `-1` for
// anything else, which the entry point turns into a usage error.
func BenchParseCount(text: string): int {
    if text.Length == 0 || text.Length > 4 {
        return -1
    }

    value := 0
    i := 0
    while i < text.Length {
        c := text[i]
        if c < '0' || c > '9' {
            return -1
        }

        value = value * 10 + (c - '0')
        i = i + 1
    }

    return value
}

// A decimal with at most three fractional digits, read as thousandths: `1.5` -> `1500`, `2` ->
// `2000`, `1.25` -> `1250`. `-1` when the text is not such a number. This is how `toleranceFactor`
// is carried, so the whole gate comparison stays in integer arithmetic.
func BenchParseFixed3(text: string): long {
    trimmed := text.Trim()
    if trimmed.Length == 0 {
        return -1
    }

    dot := trimmed.IndexOf(".", StringComparison.Ordinal)
    if dot < 0 {
        whole := BenchParseLong(trimmed)
        if whole < 0 {
            return -1
        }

        return whole * 1000
    }

    wholeText := trimmed.Substring(0, dot)
    fractionText := trimmed.Substring(dot + 1)
    if wholeText.Length == 0 || fractionText.Length == 0 || fractionText.Length > 3 {
        return -1
    }

    whole := BenchParseLong(wholeText)
    fraction := BenchParseLong(fractionText)
    if whole < 0 || fraction < 0 {
        return -1
    }

    scale := 1L
    i := fractionText.Length
    while i < 3 {
        scale = scale * 10
        i = i + 1
    }

    return whole * 1000 + fraction * scale
}

// The inverse of `BenchParseFixed3`, with trailing zeros trimmed: `1500` -> `1.5`, `2000` -> `2`.
func BenchFormatFixed3(thousandths: long): string {
    whole := thousandths / 1000
    fraction := thousandths - whole * 1000
    if fraction == 0 {
        return BenchLongText(whole)
    }

    text := BenchLongText(fraction)
    while text.Length < 3 {
        text = "0" + text
    }

    while text.Length > 1 && text.EndsWith("0") {
        text = text.Substring(0, text.Length - 1)
    }

    return BenchLongText(whole) + "." + text
}

// Tenths as `<whole>.<tenth>`; the estate has no float formatting, so every one-decimal column in
// the CSV and the Markdown is produced from an integer tenth count.
func BenchFormatTenths(tenths: long): string {
    if tenths < 0 {
        return ""
    }

    whole := tenths / 10
    fraction := tenths - whole * 10
    return BenchLongText(whole) + "." + BenchLongText(fraction)
}

// Bytes as megabytes with one decimal, rounded half-up. `""` when the peak RSS was unavailable,
// which is the same empty cell the CSV carries.
func BenchFormatMegabytes(bytes: long): string {
    if bytes < 0 {
        return ""
    }

    tenths := (bytes * 10 + 524288) / 1048576
    return BenchFormatTenths(tenths)
}

// `lines / (medianWallMs / 1000)`, in tenths, rounded half-up. `-1` when there is no rate to
// state: a project with no lines, or a run whose wall clock did not advance.
func BenchLinesPerSecondTenths(lines: long, medianWallMs: long): long {
    if lines <= 0 || medianWallMs <= 0 {
        return -1
    }

    return (lines * 10000 + medianWallMs / 2) / medianWallMs
}

// The median of the first `count` entries, taken as the LOWER middle value for an even count so
// that the reported number is always one that was actually measured.
func BenchMedian(values: long[], count: int): long {
    if count <= 0 {
        return -1
    }

    sorted := new long[](count)
    i := 0
    while i < count {
        sorted[i] = values[i]
        i = i + 1
    }

    BenchSortLongs(sorted, count)
    return sorted[(count - 1) / 2]
}

func BenchMinimum(values: long[], count: int): long {
    if count <= 0 {
        return -1
    }

    result := values[0]
    i := 1
    while i < count {
        if values[i] < result {
            result = values[i]
        }

        i = i + 1
    }

    return result
}

func BenchMaximum(values: long[], count: int): long {
    if count <= 0 {
        return -1
    }

    result := values[0]
    i := 1
    while i < count {
        if values[i] > result {
            result = values[i]
        }

        i = i + 1
    }

    return result
}

func BenchSortLongs(values: long[], count: int) {
    i := 1
    while i < count {
        current := values[i]
        j := i - 1
        while j >= 0 && values[j] > current {
            values[j + 1] = values[j]
            j = j - 1
        }

        values[j + 1] = current
        i = i + 1
    }
}

func BenchSortStringsOrdinal(values: List<string>) {
    i := 1
    while i < values.Count {
        current := values[i]
        j := i - 1
        while j >= 0 && String.Compare(values[j], current, StringComparison.Ordinal) > 0 {
            values[j + 1] = values[j]
            j = j - 1
        }

        values[j + 1] = current
        i = i + 1
    }
}

// Every `\n`-terminated line. A trailing fragment with no newline is not a line, which is the
// definition the line counts in this harness are stated under.
func BenchCountLines(text: string): long {
    count := 0L
    i := 0
    while i < text.Length {
        if text[i] == '\n' {
            count = count + 1
        }

        i = i + 1
    }

    return count
}

// `\n`-split with the `\r` of a CRLF pair removed, so a parser written against `\n` reads a file
// written on either platform.
func BenchSplitLines(text: string): List<string> {
    lines := new List<string>()
    parts := text.Split('\n')
    i := 0
    while i < parts.Length {
        line := parts[i]
        if line.Length > 0 && line[line.Length - 1] == '\r' {
            line = line.Substring(0, line.Length - 1)
        }

        lines.Add(line)
        i = i + 1
    }

    return lines
}

func BenchJoinLines(lines: List<string>): string {
    builder := new StringBuilder()
    i := 0
    while i < lines.Count {
        if i > 0 {
            builder.Append("\n")
        }

        builder.Append(lines[i])
        i = i + 1
    }

    return builder.ToString() ?? ""
}

// A CSV cell that can never break the row: a value carrying `"`, `,`, or a newline is quoted and
// its quotes doubled. Repository-relative project paths do not carry any of the three today; the
// escape is here so that a path that one day does is still readable by a spreadsheet.
func BenchCsvCell(value: string): string {
    needsQuote := false
    i := 0
    while i < value.Length {
        c := value[i]
        if c == '"' || c == ',' || c == '\n' || c == '\r' {
            needsQuote = true
        }

        i = i + 1
    }

    if !needsQuote {
        return value
    }

    builder := new StringBuilder()
    builder.Append("\"")
    j := 0
    while j < value.Length {
        c := value[j]
        if c == '"' {
            builder.Append("\"")
        }

        builder.Append(c)
        j = j + 1
    }

    builder.Append("\"")
    return builder.ToString() ?? ""
}

// `-1` is this harness's one "not measured" marker, and it renders as an EMPTY CSV cell — the
// resolve/emit/total columns of a `check` row, and the peak-RSS column when `/usr/bin/time` is
// absent.
func BenchCsvNumber(value: long): string {
    if value < 0 {
        return ""
    }

    return BenchLongText(value)
}

// ─── THE `--timings` PARSER ───────────────────────────────────────────────────────────────────

// `nlc build --timings` writes, to STDERR:
//
//     Build timings:
//       Resolve:    0.4s
//       Emit IL:    12.1s
//       Total:      12.5s
//
// The three values come from `ProgramCommandKernels.FormatElapsedMilliseconds`, so their form is
// `<whole>.<tenth>s` under a minute and `<m>m <ss>s` at or above one — a tenth of a second is the
// finest the CLI itself reports, and these are the CLI's own numbers, not this harness's.
class BenchBuildTimings {
    Found: bool
    ResolveMs: long
    EmitMs: long
    TotalMs: long

    constructor(found: bool, resolveMs: long, emitMs: long, totalMs: long) {
        Found = found
        ResolveMs = resolveMs
        EmitMs = emitMs
        TotalMs = totalMs
    }
}

func BenchParseElapsedText(text: string): long {
    trimmed := text.Trim()
    if trimmed.Length < 2 || !trimmed.EndsWith("s") {
        return -1
    }

    body := trimmed.Substring(0, trimmed.Length - 1)
    minuteMark := body.IndexOf("m ", StringComparison.Ordinal)
    if minuteMark > 0 {
        minutes := BenchParseLong(body.Substring(0, minuteMark))
        seconds := BenchParseLong(body.Substring(minuteMark + 2))
        if minutes < 0 || seconds < 0 {
            return -1
        }

        return minutes * 60000 + seconds * 1000
    }

    dot := body.IndexOf(".", StringComparison.Ordinal)
    if dot < 0 {
        return -1
    }

    whole := BenchParseLong(body.Substring(0, dot))
    fraction := body.Substring(dot + 1)
    if whole < 0 || fraction.Length != 1 {
        return -1
    }

    tenths := BenchParseLong(fraction)
    if tenths < 0 {
        return -1
    }

    return whole * 1000 + tenths * 100
}

func BenchParseBuildTimings(stderr: string): BenchBuildTimings {
    lines := BenchSplitLines(stderr)
    resolveMs := -1L
    emitMs := -1L
    totalMs := -1L
    inBlock := false

    i := 0
    while i < lines.Count {
        line := lines[i].Trim()
        if line == "Build timings:" {
            inBlock = true
        } else if inBlock {
            if line.StartsWith("Resolve:") {
                resolveMs = BenchParseElapsedText(line.Substring(8))
            } else if line.StartsWith("Emit IL:") {
                emitMs = BenchParseElapsedText(line.Substring(8))
            } else if line.StartsWith("Total:") {
                totalMs = BenchParseElapsedText(line.Substring(6))
            }
        }

        i = i + 1
    }

    found := resolveMs >= 0 && emitMs >= 0 && totalMs >= 0
    return new BenchBuildTimings(found, resolveMs, emitMs, totalMs)
}

// ─── THE OS TIME UTILITY'S STDERR ─────────────────────────────────────────────────────────────

// The child is wrapped in the OS time utility so that the KERNEL reports its peak resident set,
// and that report lands on the same stderr as the CLI's own `Build timings:` block and its
// diagnostics. These two kernels are what keep the streams apart: `BenchParsePeakRssBytes` reads
// only the time utility's rows, and `BenchStripTimeUtilityLines` hands back the CLI's own stderr
// so a failed run's message carries the compiler's words and not the rusage dump.
//
// The two forms, verbatim:
//   macOS  `/usr/bin/time -l`:  "          142606336  maximum resident set size"
//   Linux  `/usr/bin/time -v`:  "\tMaximum resident set size (kbytes): 139264"
func BenchIsTimeUtilityLine(line: string): bool {
    if line.Length == 0 {
        return false
    }

    // GNU `time -v` indents every one of its rows with a tab; the CLI indents with spaces.
    if line[0] == '\t' {
        return true
    }

    // BSD `time -l` prefixes every row with its number, including the `real/user/sys` header, and
    // every label it writes is plain words: `maximum resident set size`, `page reclaims`,
    // `involuntary context switches`. Requiring the REST of the row to be words and numbers too is
    // what keeps a compiler diagnostic's source-line gutter — `1486 |     func ParseTypeBody(` —
    // out of the time utility's bucket, since that line's `|` and `(` are not word characters.
    trimmed := line.Trim()
    if trimmed.Length == 0 {
        return false
    }

    i := 0
    digits := 0
    dots := 0
    while i < trimmed.Length {
        c := trimmed[i]
        if c == ' ' || c == '\t' {
            return digits > 0 && BenchIsPlainWordTail(trimmed, i)
        }

        if c >= '0' && c <= '9' {
            digits = digits + 1
        } else if c == '.' {
            dots = dots + 1
            if dots > 1 {
                return false
            }
        } else {
            return false
        }

        i = i + 1
    }

    return false
}

// Letters, digits, spaces, tabs and periods only, and at least one non-space character.
func BenchIsPlainWordTail(text: string, start: int): bool {
    content := 0
    i := start
    while i < text.Length {
        c := text[i]
        if c == ' ' || c == '\t' {
            i = i + 1
        } else if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' {
            content = content + 1
            i = i + 1
        } else {
            return false
        }
    }

    return content > 0
}

func BenchStripTimeUtilityLines(stderr: string): string {
    lines := BenchSplitLines(stderr)
    kept := new List<string>()
    i := 0
    while i < lines.Count {
        if !BenchIsTimeUtilityLine(lines[i]) {
            kept.Add(lines[i])
        }

        i = i + 1
    }

    return BenchJoinLines(kept)
}

// The child's peak resident set in BYTES, or `-1` when the time utility did not report one (it is
// absent, or the platform is neither macOS nor Linux). `-1` is an empty CSV cell, never a failure.
func BenchParsePeakRssBytes(stderr: string): long {
    lines := BenchSplitLines(stderr)
    i := 0
    while i < lines.Count {
        line := lines[i]
        lower := line.ToLowerInvariant()
        if lower.IndexOf("maximum resident set size", StringComparison.Ordinal) >= 0 {
            if lower.IndexOf("(kbytes)", StringComparison.Ordinal) >= 0 {
                colon := line.IndexOf(":", StringComparison.Ordinal)
                if colon >= 0 {
                    kilobytes := BenchParseLong(line.Substring(colon + 1).Trim())
                    if kilobytes >= 0 {
                        return kilobytes * 1024
                    }
                }
            } else {
                bytes := BenchParseLong(BenchFirstToken(line))
                if bytes >= 0 {
                    return bytes
                }
            }
        }

        i = i + 1
    }

    return -1
}

func BenchFirstToken(line: string): string {
    trimmed := line.Trim()
    space := trimmed.IndexOf(" ", StringComparison.Ordinal)
    if space < 0 {
        return trimmed
    }

    return trimmed.Substring(0, space)
}

// ─── THE THREE STATUSES A PROJECT ROW CAN HAVE ────────────────────────────────────────────────

// A project whose replicated selection yields ZERO files is NOT a project that failed to compile.
// 29 of the 68 corpus projects are of this shape: they hold only `.tests.nl` files, which
// `nlc build` and `nlc check` both exclude, so both commands have nothing to compile and exit 1.
// Recording that as `ok=false` would misstate the compiler — it would read as 29 broken projects
// when the truth is that `nlc test` is the command that compiles them, in the product gate's
// Step 3a. So they are classified instead: no command is spawned for them at all, and their row
// carries this status, zero runs and no medians.
func BenchNoSourcesStatus(): string {
    return "no non-test sources"
}

func BenchMeasuredStatus(): string {
    return "measured"
}

func BenchFailedStatus(): string {
    return "failed"
}

// ─── THE CHECK ENVELOPE'S DIAGNOSTIC CENSUS ───────────────────────────────────────────────────

// `<total> results: NL202 ×85, NL402 ×65, …` over the `results` array of an `nlc check --json`
// envelope, ordered by count descending and then by code ascending so that two runs of the same
// tree render the same string. `""` when the envelope carries no `results` or the array is empty.
//
// WHY A CENSUS AND NOT JUST AN EXIT CODE. A red row that says only "exit 1" cannot be told apart
// from a different red row that says only "exit 1". The census is what makes a failing project's
// row diagnosable, and on `src/NSharpLang.Compiler.BootstrapServices` it is the number that shows
// what the measured `nlc build` is actually spending its time on before it stops.
func BenchDiagnosticCensus(stdout: string): string {
    if stdout.Trim().Length == 0 {
        return ""
    }

    codes := new List<string>()
    counts := new List<int>()
    total := 0

    try {
        document := JsonDocument.Parse(stdout)
        enumerator := document.RootElement.GetProperty("results").EnumerateArray()
        while enumerator.MoveNext() {
            total = total + 1
            BenchTallyCode(codes, counts, BenchJsonStringOrEmpty(enumerator.Current, "code"))
        }

        document.Dispose()
    } catch {
        return ""
    }

    if total == 0 {
        return ""
    }

    BenchSortCensus(codes, counts)
    builder := new StringBuilder()
    builder.Append(BenchIntText(total))
    builder.Append(" results: ")
    i := 0
    while i < codes.Count {
        if i > 0 {
            builder.Append(", ")
        }

        builder.Append(codes[i])
        builder.Append(" ×")
        builder.Append(BenchIntText(counts[i]))
        i = i + 1
    }

    return builder.ToString() ?? ""
}

// A diagnostic with no `code` is still a result, and is counted under `(no code)` rather than
// dropped, so the per-code counts always add up to the total the census states.
func BenchTallyCode(codes: List<string>, counts: List<int>, code: string) {
    name := code
    if name == "" {
        name = "(no code)"
    }

    i := 0
    while i < codes.Count {
        if codes[i] == name {
            counts[i] = counts[i] + 1
            return
        }

        i = i + 1
    }

    codes.Add(name)
    counts.Add(1)
}

func BenchSortCensus(codes: List<string>, counts: List<int>) {
    i := 1
    while i < codes.Count {
        code := codes[i]
        count := counts[i]
        j := i - 1
        while j >= 0 && BenchCensusPrecedes(code, count, codes[j], counts[j]) {
            codes[j + 1] = codes[j]
            counts[j + 1] = counts[j]
            j = j - 1
        }

        codes[j + 1] = code
        counts[j + 1] = count
        i = i + 1
    }
}

func BenchCensusPrecedes(leftCode: string, leftCount: int, rightCode: string, rightCount: int): bool {
    if leftCount != rightCount {
        return leftCount > rightCount
    }

    return String.Compare(leftCode, rightCode, StringComparison.Ordinal) < 0
}

// The number of entries in the envelope's `results` array, or `-1` when it carried none. This is
// the `check results` column; the census above is the same data spelled out.
func BenchDiagnosticResultCount(stdout: string): int {
    if stdout.Trim().Length == 0 {
        return -1
    }

    try {
        document := JsonDocument.Parse(stdout)
        count := document.RootElement.GetProperty("results").GetArrayLength()
        document.Dispose()
        return count
    } catch {
        return -1
    }
}

// ─── THE SOURCE-SELECTION RULE, REPLICATED ────────────────────────────────────────────────────

// `ProjectConfig.ShouldSkipSourceDirectory`, name for name.
func BenchShouldSkipSourceDirectory(name: string): bool {
    return BenchNameEquals(name, ".context") || BenchNameEquals(name, ".git") || BenchNameEquals(name, ".github") || BenchNameEquals(name, ".hermes") || BenchNameEquals(name, ".vscode") || BenchNameEquals(name, ".vscode-test") || BenchNameEquals(name, ".worktrees") || BenchNameEquals(name, "bin") || BenchNameEquals(name, "node_modules") || BenchNameEquals(name, "nsharp") || BenchNameEquals(name, "obj") || BenchNameEquals(name, "out")
}

func BenchNameEquals(left: string, right: string): bool {
    return String.Compare(left, right, StringComparison.OrdinalIgnoreCase) == 0
}

// `ProjectSourceFileFilter.ProjectSourceFilterIsTestFile`: the nine-character `.tests.nl` suffix,
// case-insensitively.
func BenchIsTestSourcePath(path: string): bool {
    if path.Length < 9 {
        return false
    }

    return path.ToLowerInvariant().EndsWith(".tests.nl")
}

// Every `.nl` file `nlc build` and `nlc check` compile for this project, in walk order.
func BenchCollectProjectSourceFiles(projectRoot: string): List<string> {
    files := new List<string>()
    if Directory.Exists(projectRoot) {
        BenchCollectProjectSourceFilesRecursive(Path.GetFullPath(projectRoot), files)
    }

    return files
}

func BenchCollectProjectSourceFilesRecursive(directory: string, files: List<string>) {
    directoryFiles := Directory.GetFiles(directory, "*.nl", SearchOption.TopDirectoryOnly)
    BenchSortStringArray(directoryFiles)
    i := 0
    while i < directoryFiles.Length {
        if !BenchIsTestSourcePath(directoryFiles[i]) {
            files.Add(directoryFiles[i])
        }

        i = i + 1
    }

    subdirectories := Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)
    BenchSortStringArray(subdirectories)
    j := 0
    while j < subdirectories.Length {
        name := Path.GetFileName(subdirectories[j]) ?? ""
        if !BenchShouldSkipSourceDirectory(name) {
            BenchCollectProjectSourceFilesRecursive(subdirectories[j], files)
        }

        j = j + 1
    }
}

func BenchSortStringArray(values: string[]) {
    i := 1
    while i < values.Length {
        current := values[i]
        j := i - 1
        while j >= 0 && String.Compare(values[j], current, StringComparison.Ordinal) > 0 {
            values[j + 1] = values[j]
            j = j - 1
        }

        values[j + 1] = current
        i = i + 1
    }
}

class BenchSourceMeasure {
    Files: int
    Lines: long

    constructor(files: int, lines: long) {
        Files = files
        Lines = lines
    }
}

func BenchMeasureProjectSources(projectRoot: string): BenchSourceMeasure {
    files := BenchCollectProjectSourceFiles(projectRoot)
    lines := 0L
    i := 0
    while i < files.Count {
        lines = lines + BenchCountLines(File.ReadAllText(files[i]))
        i = i + 1
    }

    return new BenchSourceMeasure(files.Count, lines)
}

// ─── THE CORPUS ───────────────────────────────────────────────────────────────────────────────

// The large-project case. It is NOT part of the corpus: it sits under `src/`, and the corpus is
// the `examples/`, `tests/` and `templates/` trees.
func BenchBootstrapProjectPath(): string {
    return "src/NSharpLang.Compiler.BootstrapServices"
}

// This harness's own project, excluded from the corpus it measures: a benchmark that rebuilt
// itself inside its own sweep would be reporting on a moving target, and the corpus count is
// stated as a fact about the tree under measurement, not about the tool doing the measuring.
func BenchSelfProjectPath(): string {
    return "tests/native/compile-time-bench"
}

func BenchShouldSkipCorpusDirectory(name: string): bool {
    return BenchNameEquals(name, "bin") || BenchNameEquals(name, "obj") || BenchNameEquals(name, "node_modules") || BenchNameEquals(name, ".git")
}

// Every `project.yml` under `examples/`, `tests/` and `templates/`, as repository-relative
// directories with `/` separators, sorted ordinally.
func BenchCollectCorpusProjects(repositoryRoot: string): List<string> {
    projects := new List<string>()
    BenchCollectCorpusProjectsUnder(repositoryRoot, "examples", projects)
    BenchCollectCorpusProjectsUnder(repositoryRoot, "tests", projects)
    BenchCollectCorpusProjectsUnder(repositoryRoot, "templates", projects)
    BenchSortStringsOrdinal(projects)
    return projects
}

func BenchCollectCorpusProjectsUnder(repositoryRoot: string, relativeRoot: string, projects: List<string>) {
    directory := Path.Combine(repositoryRoot, relativeRoot)
    if !Directory.Exists(directory) {
        return
    }

    BenchCollectCorpusProjectsRecursive(directory, relativeRoot, projects)
}

func BenchCollectCorpusProjectsRecursive(directory: string, relativePath: string, projects: List<string>) {
    if File.Exists(Path.Combine(directory, "project.yml")) && relativePath != BenchSelfProjectPath() {
        projects.Add(relativePath)
    }

    subdirectories := Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)
    BenchSortStringArray(subdirectories)
    i := 0
    while i < subdirectories.Length {
        name := Path.GetFileName(subdirectories[i]) ?? ""
        if !BenchShouldSkipCorpusDirectory(name) {
            BenchCollectCorpusProjectsRecursive(subdirectories[i], relativePath + "/" + name, projects)
        }

        i = i + 1
    }
}

// ─── THE TREE-UNTOUCHED PROOF ─────────────────────────────────────────────────────────────────

// A recursive listing of a directory as `<relative path>|<last write UTC ticks>`, one entry per
// line, deterministic because every directory's own files and subdirectories are sorted before they
// are walked. Taken before and after each measured build, this is what proves that
// `nlc build -o <temp dir>` left the project it compiled untouched: an added, removed, renamed or
// rewritten file changes the listing, and any change fails the run.
//
// THE ENTRY CARRIES NO LENGTH, AND THAT IS A MEASURED LIMIT, NOT A CHOICE. `FileInfo` is the only
// route to a file's byte length in `System.IO`, and it is unreachable on this emit path: as a typed
// local it declines at `emit.typed-local.unsupported-type` ("typed local declaration type is not
// supported ... FileInfo"), as an inferred local at `emit.local.initializer`, and as a return
// expression at `emit.return.expression`. The last-write tick is what remains, and it is the
// stronger half of the pair anyway — a write updates it whether or not the length changed.
func BenchSnapshotDirectory(directory: string): string {
    lines := new List<string>()
    if Directory.Exists(directory) {
        BenchSnapshotDirectoryRecursive(Path.GetFullPath(directory), "", lines)
    }

    return BenchJoinLines(lines)
}

func BenchSnapshotDirectoryRecursive(directory: string, relativePath: string, lines: List<string>) {
    files := Directory.GetFiles(directory, "*", SearchOption.TopDirectoryOnly)
    BenchSortStringArray(files)
    i := 0
    while i < files.Length {
        name := Path.GetFileName(files[i]) ?? ""
        lines.Add(
            BenchSnapshotEntryPath(relativePath, name) + "|" + BenchLongText(BenchFileLastWriteTicks(files[i]))
        )
        i = i + 1
    }

    subdirectories := Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)
    BenchSortStringArray(subdirectories)
    j := 0
    while j < subdirectories.Length {
        name := Path.GetFileName(subdirectories[j]) ?? ""
        BenchSnapshotDirectoryRecursive(subdirectories[j], BenchSnapshotEntryPath(relativePath, name), lines)
        j = j + 1
    }
}

func BenchFileLastWriteTicks(path: string): long {
    return File.GetLastWriteTimeUtc(path).Ticks
}

func BenchSnapshotEntryPath(relativePath: string, name: string): string {
    if relativePath.Length == 0 {
        return name
    }

    return relativePath + "/" + name
}

// `""` when the two listings agree. Otherwise the first differing entries, at most eight of them,
// each marked `-` for what was there before and `+` for what is there now.
func BenchDiffSnapshots(before: string, after: string): string {
    if before == after {
        return ""
    }

    beforeLines := BenchSplitLines(before)
    afterLines := BenchSplitLines(after)
    beforeSet := new HashSet<string>()
    afterSet := new HashSet<string>()

    i := 0
    while i < beforeLines.Count {
        beforeSet.Add(beforeLines[i])
        i = i + 1
    }

    j := 0
    while j < afterLines.Count {
        afterSet.Add(afterLines[j])
        j = j + 1
    }

    differences := new List<string>()
    k := 0
    while k < beforeLines.Count && differences.Count < 8 {
        if !afterSet.Contains(beforeLines[k]) {
            differences.Add("- " + beforeLines[k])
        }

        k = k + 1
    }

    m := 0
    while m < afterLines.Count && differences.Count < 8 {
        if !beforeSet.Contains(afterLines[m]) {
            differences.Add("+ " + afterLines[m])
        }

        m = m + 1
    }

    return BenchJoinLines(differences)
}

// ─── THE CHECKED-IN BASELINE ──────────────────────────────────────────────────────────────────

// THE BASELINE SAYS WHAT STAGE IT COVERS, AND WHAT EXIT CODE THAT STAGE PRODUCES.
//
// `nlc build` runs `MultiFileCompiler.CompileToIlAssembly(validateStrictLint: true)`, and
// `RunLegacyValidationPipeline` RETURNS before `AnalyzeAllFiles()` as soon as strict lint reports an
// error. On `src/NSharpLang.Compiler.BootstrapServices` it does: `nlc check --json` reports 243
// error-severity results there, 45 of them lint findings that stop the build at that gate, so a
// "build" of that project today measures PARSE + STRICT LINT and nothing after it. The product
// itself builds this project through the MSBuild SDK with legacy analysis switched off by project
// name (`src/NSharpLang.Sdk/Sdk/Sdk.targets:16`), which is why the failure is not visible in a
// normal `dotnet build`.
//
// A benchmark that reported that number as "build time" would be claiming coverage it does not
// have. So the baseline carries `stage` — prose naming exactly what the measurement covers, carried
// in every failure message the gate can produce — and `expectedExitCode`, which the gate requires
// each run to MATCH. Matching, not merely tolerating: an exit 0 where 1 was baselined means the
// front-end stopped failing and the run now reaches analysis and emit, so the number is no longer
// comparable and the baseline has to be re-measured. That is a gate failure, not a quiet pass.
class BenchBaseline {
    SchemaVersion: int
    Project: string
    Command: string
    Stage: string
    ExpectedExitCode: int
    MeasuredAt: string
    CliCommit: string
    Machine: string
    Runs: int
    Files: int
    Lines: long
    MedianWallMs: long
    MedianPeakRssBytes: long
    ToleranceThousandths: long

    constructor(
        schemaVersion: int,
        project: string,
        command: string,
        stage: string,
        expectedExitCode: int,
        measuredAt: string,
        cliCommit: string,
        machine: string,
        runs: int,
        files: int,
        lines: long,
        medianWallMs: long,
        medianPeakRssBytes: long,
        toleranceThousandths: long
    ) {
        SchemaVersion = schemaVersion
        Project = project
        Command = command
        Stage = stage
        ExpectedExitCode = expectedExitCode
        MeasuredAt = measuredAt
        CliCommit = cliCommit
        Machine = machine
        Runs = runs
        Files = files
        Lines = lines
        MedianWallMs = medianWallMs
        MedianPeakRssBytes = medianPeakRssBytes
        ToleranceThousandths = toleranceThousandths
    }
}

// `stage` and `expectedExitCode` are read SOFTLY — absent means the empty string and `-1` — so that
// a baseline written before those keys existed is REFUSED BY NAME by `BenchBaselineRefusal` instead
// of throwing an unreadable `KeyNotFoundException` out of the gate.
func BenchJsonStringOrEmpty(root: JsonElement, name: string): string {
    try {
        return root.GetProperty(name).GetString() ?? ""
    } catch {
        return ""
    }
}

func BenchJsonIntOrMissing(root: JsonElement, name: string): int {
    try {
        return root.GetProperty(name).GetInt32()
    } catch {
        return -1
    }
}

func BenchParseBaseline(json: string): BenchBaseline {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    baseline := new BenchBaseline(
        root.GetProperty("schemaVersion").GetInt32(),
        root.GetProperty("project").GetString() ?? "",
        root.GetProperty("command").GetString() ?? "",
        BenchJsonStringOrEmpty(root, "stage"),
        BenchJsonIntOrMissing(root, "expectedExitCode"),
        root.GetProperty("measuredAt").GetString() ?? "",
        root.GetProperty("cliCommit").GetString() ?? "",
        root.GetProperty("machine").GetString() ?? "",
        root.GetProperty("runs").GetInt32(),
        root.GetProperty("files").GetInt32(),
        root.GetProperty("lines").GetInt64(),
        root.GetProperty("medianWallMs").GetInt64(),
        root.GetProperty("medianPeakRssBytes").GetInt64(),
        BenchParseFixed3(root.GetProperty("toleranceFactor").GetRawText() ?? "")
    )
    document.Dispose()
    return baseline
}

// `""` when the baseline is usable. Otherwise the reason it is not, in the words a red gate should
// print. The `medianWallMs == 0` arm is the one that matters most: the file is checked in with
// placeholder zeros, and a placeholder must never be able to pass the gate it guards.
func BenchBaselineRefusal(baseline: BenchBaseline): string {
    if baseline.SchemaVersion != 1 {
        return "baseline schemaVersion " + BenchIntText(baseline.SchemaVersion) + " is not the supported version 1"
    }

    if baseline.Project != BenchBootstrapProjectPath() {
        return "baseline project '" + baseline.Project + "' is not '" + BenchBootstrapProjectPath() + "'"
    }

    if baseline.Command != "build" {
        return "baseline command '" + baseline.Command + "' is not 'build'"
    }

    if baseline.Stage == "" {
        return "baseline stage is missing: the baseline must say in prose which stage of the command" + " its milliseconds cover, because `nlc build` stops at strict lint on this project and" + " does not reach analysis or emit"
    }

    if baseline.ExpectedExitCode < 0 {
        return "baseline expectedExitCode is missing or negative: the baseline must pin the exit code" + " the measured stage produces, so that a run which stops failing is caught instead of" + " silently changing what is measured"
    }

    if baseline.MedianWallMs <= 0 {
        return "baseline not measured: medianWallMs is " + BenchLongText(baseline.MedianWallMs) + " in tests/fixtures/compile-time/bootstrap-build-baseline.golden.json." + " Run the harness on src/NSharpLang.Compiler.BootstrapServices and fill in the measured" + " medianWallMs, medianPeakRssBytes, files, lines, cliCommit, machine and measuredAt."
    }

    if baseline.ToleranceThousandths <= 0 {
        return "baseline toleranceFactor is missing or not a positive decimal"
    }

    return ""
}

// ─── THE MACHINE THE MEDIAN WAS TAKEN ON ──────────────────────────────────────────────────────

// WHY A TIMING GATE READS THE LOAD BEFORE IT JUDGES.
//
// The baseline this gate compares against was measured on an IDLE machine — its `machine` field
// says so in words — so a median taken while the box is busy measures the BOX, not the compiler.
// Measured: five product gates in two days went red at one-minute load averages of 4.4 to 8.1 on
// this 10-core M4, with medians of 11,941 / 12,319 / 13,241 / 15,623 / 17,010 ms against an
// 11,802 ms limit (1.52x to 2.16x the baseline), while the same code measured 6-7 s on a quiet
// box; a sixth run at load 5.18 reproduced it at 12,401 ms. Reporting that as a regression is a
// lie about the code, and five people paid for it with a red sweep each.
//
// So the block reads the one-minute load average FIRST — the way the systems throughput gate does
// (`benchmarks/native-comparison/runner/Program.nl` prints `load average { … }, 10 cores` before
// it judges) — and REFUSES TO JUDGE the median above a threshold instead of failing.
//
// THE CORRECTNESS HALF IS NOT SKIPPED WITH IT. The exit code must still match the baseline, the
// CLI's own failure banner must still be on stdout, and a placeholder baseline is still refused.
// Those are facts about the build; load does not move them, so load cannot excuse them.
class BenchMachineLoad {
    LoadThousandths: long
    Cores: int

    constructor(loadThousandths: long, cores: int) {
        LoadThousandths = loadThousandths
        Cores = cores
    }
}

// The load a caller has not measured, and the load a platform refused to answer: both -1.
func BenchUnknownLoad(): BenchMachineLoad {
    return new BenchMachineLoad(-1, -1)
}

func BenchLoadAverageMarker(): string {
    return "load average"
}

func BenchIsLoadSeparator(c: char): bool {
    return c == ' ' || c == '\t' || c == ',' || c == '{' || c == '}'
}

func BenchFirstLoadToken(text: string, start: int): string {
    i := start
    while i < text.Length && BenchIsLoadSeparator(text[i]) {
        i = i + 1
    }

    from := i
    while i < text.Length && !BenchIsLoadSeparator(text[i]) {
        i = i + 1
    }

    if i <= from {
        return ""
    }

    return text.Substring(from, i - from)
}

// The one-minute load average in THOUSANDTHS, from either shape a platform answers with:
// `sysctl -n vm.loadavg` -> `{ 4.17 4.42 4.62 }`; `uptime` -> `13:04  up  3:46, 1 user, load
// averages: 4.17 4.42 4.62` on macOS and `… load average: 0.52, 0.58, 0.59` on Linux. `-1` for
// anything else — a load that cannot be READ is not a load of zero.
//
// Thousandths rather than a `double` because this estate has no float parse or format at all; the
// same `BenchParseFixed3` that reads the baseline's `toleranceFactor` reads a load figure exactly.
//
// THE MARKER CUT IS NOT OPTIONAL. An uptime line carries numbers BEFORE the load figures — the
// clock, the uptime, the user count — and the first parseable token of
// `13:04  up  3:46, 1 user, load averages: 4.17 …` is the `1` of "1 user". A reader that took the
// first number in the line would report a machine at load 4.17 as idle at 1.0.
func BenchOneMinuteLoadThousandths(text: string): long {
    marker := text.IndexOf(BenchLoadAverageMarker(), StringComparison.OrdinalIgnoreCase)
    if marker >= 0 {
        tail := text.Substring(marker)
        colon := tail.IndexOf(":", StringComparison.Ordinal)
        if colon < 0 {
            return -1
        }

        return BenchParseFixed3(BenchFirstLoadToken(tail, colon + 1))
    }

    if text.Trim().StartsWith("{") {
        return BenchParseFixed3(BenchFirstLoadToken(text, 0))
    }

    return -1
}

// THE THRESHOLD IS A FIFTH OF THE LOGICAL CORES — 2.0 on the 10-core machine the baseline was
// taken on — so that it travels to a machine of another size instead of pinning one box's number.
//
// Where it comes from: the measured inflation on this machine is about `1 + 0.13 x load` (six runs
// at loads 4.4-8.1 landed at 1.52x-2.16x the baseline), so load alone reaches the x1.5 tolerance at
// about 3.9 and the gate has no margin left by then. At 2.0 load spends ~1.25x, half of the
// tolerance's headroom, and leaves the other half to catch an actual regression. `2000` when the
// platform did not answer with a core count, because 10 cores is what the baseline says.
func BenchLoadThresholdThousandths(cores: int): long {
    if cores <= 0 {
        return 2000
    }

    return cores * 200
}

// A load that could not be READ refuses judgement too: a timing gate must not judge a machine it
// cannot compare to its baseline. That is only safe because `BenchReadMachineLoad` is pinned by a
// LIVE contract on macOS and Linux — a reader that stops answering turns THAT test red instead of
// switching this gate off in silence.
func BenchLoadRefusesTimingJudgement(load: BenchMachineLoad): bool {
    if load.LoadThousandths < 0 {
        return true
    }

    return load.LoadThousandths >= BenchLoadThresholdThousandths(load.Cores)
}

func BenchLoadText(thousandths: long): string {
    if thousandths < 0 {
        return "unknown"
    }

    return BenchFormatFixed3(thousandths)
}

// `git rev-parse HEAD` cannot answer in a tree that has no git metadata, and the product gate's
// isolated copy is exactly that tree: `tests/scripts/test-all.sh` rsyncs the repository with
// `--exclude='.git/'`, nothing in the copy stamps the commit, and every red gate's message
// therefore said `cliCommit=unknown`. "unknown" reads as a broken gate; the reason reads as the
// fact it is, and says where the commit actually lives.
func BenchCliCommitUnavailableReason(hasGitMetadata: bool, isolatedGateCopy: bool): string {
    if isolatedGateCopy {
        return "unavailable (isolated gate copy - tests/scripts/test-all.sh copies the tree without .git, so no commit is recorded in it; read the commit in the tree the gate was launched from)"
    }

    if !hasGitMetadata {
        return "unavailable (this tree carries no .git metadata)"
    }

    return "unavailable (git rev-parse HEAD failed in this tree)"
}

// ─── THE GATE'S VERDICT ───────────────────────────────────────────────────────────────────────

// Every number the gate has, in one line, on every path: the three wall clocks, the exit codes,
// the median against the baseline and its limit, the CLI commit under test, the stage the baseline
// covers, and the machine the median was taken on.
func BenchGateDetail(
    wallMs: long[],
    exitCodes: int[],
    count: int,
    medianWallMs: long,
    baseline: BenchBaseline,
    cliCommit: string,
    load: BenchMachineLoad
): string {
    return "runs=[" + BenchLongListText(wallMs, count) + "] ms" + " exitCodes=[" + BenchIntListText(exitCodes, count) + "]" + " expectedExitCode=" + BenchIntText(baseline.ExpectedExitCode) + " median=" + BenchLongText(medianWallMs) + "ms" + " baseline=" + BenchLongText(baseline.MedianWallMs) + "ms" + " tolerance=x" + BenchFormatFixed3(baseline.ToleranceThousandths) + " limit=" + BenchLongText(BenchGateLimitMs(baseline)) + "ms" + " cliCommit=" + cliCommit + " baselineCliCommit=" + baseline.CliCommit + " baselineMachine=" + baseline.Machine + " stage=" + baseline.Stage + " load=" + BenchLoadText(load.LoadThousandths) + " cores=" + BenchCountText(load.Cores) + " loadThreshold=" + BenchFormatFixed3(BenchLoadThresholdThousandths(load.Cores))
}

// The half of the gate the machine's load cannot excuse: every run exited as the baseline pins,
// and a baselined FAILURE carried the CLI's own banner. `"ok"` when both hold.
func BenchGateCorrectnessVerdict(
    wallMs: long[],
    exitCodes: int[],
    failureBanners: bool[],
    count: int,
    medianWallMs: long,
    baseline: BenchBaseline,
    cliCommit: string,
    load: BenchMachineLoad
): string {
    detail := BenchGateDetail(wallMs, exitCodes, count, medianWallMs, baseline, cliCommit, load)

    i := 0
    while i < count {
        if exitCodes[i] != baseline.ExpectedExitCode {
            return "compile-time gate: nlc build on " + baseline.Project + " exited " + BenchIntText(exitCodes[i]) + " on run " + BenchIntText(i + 1) + " but the baseline pins " + BenchIntText(baseline.ExpectedExitCode) + ". " + BenchExitCodeChangeAdvice(exitCodes[i], baseline.ExpectedExitCode) + " " + detail
        }

        i = i + 1
    }

    // A non-zero expected exit is only meaningful if the CLI ITSELF reported the failure. Without
    // this check a crashed, killed or missing CLI exits non-zero too, and would sail through as
    // "the expected failure" while measuring nothing at all.
    if baseline.ExpectedExitCode != 0 {
        j := 0
        while j < count {
            if !failureBanners[j] {
                return "compile-time gate: run " + BenchIntText(j + 1) + " of nlc build on " + baseline.Project + " exited " + BenchIntText(exitCodes[j]) + " as baselined but its stdout did NOT carry the" + " CLI's own '" + BenchBuildFailedBanner() + "' banner, so the CLI did not report the" + " failure itself — a crash, a kill or a missing CLI cannot pass as the expected failure. " + detail
            }

            j = j + 1
        }
    }

    return "ok"
}

// The half that only means something on a machine comparable to the baseline's.
func BenchGateTimingVerdict(
    wallMs: long[],
    exitCodes: int[],
    count: int,
    medianWallMs: long,
    baseline: BenchBaseline,
    cliCommit: string,
    load: BenchMachineLoad
): string {
    if medianWallMs > BenchGateLimitMs(baseline) {
        return "compile-time gate: nlc build on " + baseline.Project + " regressed; " + BenchGateDetail(wallMs, exitCodes, count, medianWallMs, baseline, cliCommit, load)
    }

    return "ok"
}

// The gate's own verdict, so that the whole diagnosis is one string: `"ok"` when every run exited
// zero and the median is inside the tolerance, and otherwise a message carrying the three wall
// times, the median, the baseline, the tolerance and the CLI commit under test. This form JUDGES
// unconditionally and states the load as `unknown`; `BenchGateOutcome` is the form the live gate
// calls, which knows what the machine was doing.
func BenchGateVerdict(
    wallMs: long[],
    exitCodes: int[],
    failureBanners: bool[],
    count: int,
    medianWallMs: long,
    baseline: BenchBaseline,
    cliCommit: string
): string {
    load := BenchUnknownLoad()
    correctness := BenchGateCorrectnessVerdict(wallMs, exitCodes, failureBanners, count, medianWallMs, baseline, cliCommit, load)
    if correctness != "ok" {
        return correctness
    }

    return BenchGateTimingVerdict(wallMs, exitCodes, count, medianWallMs, baseline, cliCommit, load)
}

func BenchSkippedByLoadPrefix(): string {
    return "skipped-by-load:"
}

// The two outcomes the gate block says NOTHING about: a judged pass, and a timing judgement it
// honestly declined to make. Every other outcome is an assertion failure carrying its numbers.
func BenchGateOutcomeIsSilent(outcome: string): bool {
    return outcome == "ok" || outcome.StartsWith(BenchSkippedByLoadPrefix())
}

// The live gate's outcome: the correctness half always, the timing half only on a machine this
// median can be compared to the baseline on.
func BenchGateOutcome(
    wallMs: long[],
    exitCodes: int[],
    failureBanners: bool[],
    count: int,
    medianWallMs: long,
    baseline: BenchBaseline,
    cliCommit: string,
    load: BenchMachineLoad
): string {
    correctness := BenchGateCorrectnessVerdict(wallMs, exitCodes, failureBanners, count, medianWallMs, baseline, cliCommit, load)
    if correctness != "ok" {
        return correctness
    }

    if BenchLoadRefusesTimingJudgement(load) {
        return BenchSkippedByLoadPrefix() + " the compile-time gate did NOT judge the median: the one-minute load average is " + BenchLoadText(load.LoadThousandths) + " on " + BenchCountText(load.Cores) + " logical cores, at or above the " + BenchFormatFixed3(BenchLoadThresholdThousandths(load.Cores)) + " this gate needs to compare a median against a baseline measured on an IDLE machine." + " The exit codes and the CLI's failure banner WERE checked and are as baselined; only the" + " timing is unjudged. Re-run on a quiet machine to judge it: dotnet <Cli.dll> test --project" + " tests/native/compile-time-bench. " + BenchGateDetail(wallMs, exitCodes, count, medianWallMs, baseline, cliCommit, load)
    }

    return BenchGateTimingVerdict(wallMs, exitCodes, count, medianWallMs, baseline, cliCommit, load)
}

// The line the gate leaves behind at `artifacts/compile-time/last-gate-run.txt`. `"ok"` on its own
// would say nothing, so a judged pass carries the same detail every other outcome does: a reader
// of a GREEN gate must be able to see whether the timing was judged, and on what machine.
func BenchGateRecordLine(outcome: string, detailText: string): string {
    if outcome == "ok" {
        return "ok " + detailText
    }

    return outcome
}

// The banner `BuildCommandKernels.GetFailedElapsedMessage` writes to STDOUT when a build fails.
func BenchBuildFailedBanner(): string {
    return "Build failed in "
}

func BenchSawBuildFailedBanner(stdout: string): bool {
    return stdout.IndexOf(BenchBuildFailedBanner(), StringComparison.Ordinal) >= 0
}

// Which direction the exit code moved decides what the reader has to do about it.
func BenchExitCodeChangeAdvice(actual: int, expected: int): string {
    if expected != 0 && actual == 0 {
        return "The command now SUCCEEDS where the baseline recorded a failure, so it is reaching stages" + " the baseline never covered and the two numbers are not comparable: re-measure the baseline" + " and rewrite its stage before trusting this gate again."
    }

    if expected == 0 && actual != 0 {
        return "The command now FAILS where the baseline recorded a success; fix the failure rather than" + " the baseline."
    }

    return "The measured stage changed: re-measure the baseline and rewrite its stage."
}

func BenchGateLimitMs(baseline: BenchBaseline): long {
    return baseline.MedianWallMs * baseline.ToleranceThousandths / 1000
}

func BenchLongListText(values: long[], count: int): string {
    builder := new StringBuilder()
    i := 0
    while i < count {
        if i > 0 {
            builder.Append(", ")
        }

        builder.Append(BenchLongText(values[i]))
        i = i + 1
    }

    return builder.ToString() ?? ""
}

func BenchIntListText(values: int[], count: int): string {
    builder := new StringBuilder()
    i := 0
    while i < count {
        if i > 0 {
            builder.Append(", ")
        }

        builder.Append(BenchIntText(values[i]))
        i = i + 1
    }

    return builder.ToString() ?? ""
}
