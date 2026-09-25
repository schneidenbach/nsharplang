namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Globalization
import System.IO
import System.Reflection
import System.Text
import System.Text.Json
import NSharpLang.Compiler

class NativeTestCase {
    DisplayName: string
    FullyQualifiedName: string
    Method: MethodInfo
    SkipReason: string?

    constructor(displayName: string, fullyQualifiedName: string, method: MethodInfo, skipReason: string?) {
        DisplayName = displayName
        FullyQualifiedName = fullyQualifiedName
        Method = method
        SkipReason = skipReason
    }
}

class NativeTestResult {
    Name: string
    DisplayName: string
    Outcome: string
    Duration: string
    ErrorMessage: string?
    NsharpDescription: string?

    constructor(name: string, displayName: string, outcome: string, duration: string, errorMessage: string?, nsharpDescription: string?) {
        Name = name
        DisplayName = displayName
        Outcome = outcome
        Duration = duration
        ErrorMessage = errorMessage
        NsharpDescription = nsharpDescription
    }
}

class NativeTestRun {
    Results: IReadOnlyList<NativeTestResult>
    OutcomeRanks: int[]
    OutcomeCount: int

    constructor(results: IReadOnlyList<NativeTestResult>, outcomeRanks: int[], outcomeCount: int) {
        Results = results
        OutcomeRanks = outcomeRanks
        OutcomeCount = outcomeCount
    }
}

class TestOutcomeSummary {
    okValue: bool
    passedValue: int
    failedValue: int
    skippedValue: int

    Ok: bool => okValue
    Passed: int => passedValue
    Failed: int => failedValue
    Skipped: int => skippedValue

    constructor(ok: bool, passed: int, failed: int, skipped: int) {
        okValue = ok
        passedValue = passed
        failedValue = failed
        skippedValue = skipped
    }
}

class NativeTestSummary {
    okValue: bool
    totalValue: int
    passedValue: int
    failedValue: int
    skippedValue: int

    Ok: bool => okValue
    Total: int => totalValue
    Passed: int => passedValue
    Failed: int => failedValue
    Skipped: int => skippedValue

    static EmptyFailure: NativeTestSummary => new NativeTestSummary(false, 0, 0, 0, 0)

    constructor(ok: bool, total: int, passed: int, failed: int, skipped: int) {
        okValue = ok
        totalValue = total
        passedValue = passed
        failedValue = failed
        skippedValue = skipped
    }
}

// WHERE ONE `nlc test` RUN SPENT ITS TIME, reported only when `--timings` asks. The build is the
// incremental IL build of the project with its tests; the run is the chosen runner over the
// emitted assembly; the total is the whole command, so it also covers reading project.yml and
// discovering the test files, and is never less than the other two together.
class NativeTestTimings {
    BuildMilliseconds: long
    RunMilliseconds: long
    TotalMilliseconds: long

    constructor(buildMilliseconds: long, runMilliseconds: long, totalMilliseconds: long) {
        BuildMilliseconds = buildMilliseconds
        RunMilliseconds = runMilliseconds
        TotalMilliseconds = totalMilliseconds
    }
}

class TestOptionSummary {
    projectOptionValue: string?
    backendOptionValue: string?
    filterValue: string?
    timeoutValue: string?
    verboseValue: bool
    jsonOutputValue: bool
    coverageReportValue: bool
    collectCoverageValue: bool
    noCacheValue: bool
    timingsValue: bool
    showHelpValue: bool

    ProjectOption: string? => projectOptionValue
    BackendOption: string? => backendOptionValue
    Filter: string? => filterValue
    Timeout: string? => timeoutValue
    Verbose: bool => verboseValue
    JsonOutput: bool => jsonOutputValue
    CoverageReport: bool => coverageReportValue
    CollectCoverage: bool => collectCoverageValue
    NoCache: bool => noCacheValue
    Timings: bool => timingsValue
    ShowHelp: bool => showHelpValue

    constructor(projectOption: string?, backendOption: string?, filter: string?, timeout: string?, verbose: bool, jsonOutput: bool, coverageReport: bool, collectCoverage: bool, noCache: bool, timings: bool, showHelp: bool) {
        projectOptionValue = projectOption
        backendOptionValue = backendOption
        filterValue = filter
        timeoutValue = timeout
        verboseValue = verbose
        jsonOutputValue = jsonOutput
        coverageReportValue = coverageReport
        collectCoverageValue = collectCoverage
        noCacheValue = noCache
        timingsValue = timings
        showHelpValue = showHelp
    }
}

class TestCommandKernels {
    static func GetProjectYmlPath(projectRoot: string): string {
        return Path.Combine(projectRoot, "project.yml")
    }

    // A TEST RUN IS ALWAYS BUILT DEBUG, and this is the ONE place that decides it. The path below
    // and `src/NSharpLang.Cli/Program.Testing.cs`'s build call used to spell the word separately,
    // so the directory a test assembly was written to and the configuration it was built under
    // were two answers that happened to agree.
    static func GetTestBuildConfiguration(): string {
        return "Debug"
    }

    static func GetTestOutputDirectory(projectRoot: string, targetFramework: string): string {
        return Path.Combine(Path.Combine(Path.Combine(Path.Combine(projectRoot, "bin"), GetTestBuildConfiguration()), targetFramework), "tests")
    }

    static func GetAssemblyDirectory(assemblyPath: string): string? {
        return Path.GetDirectoryName(assemblyPath)
    }

    static func GetAssemblyCandidatePath(assemblyDirectory: string, assemblyName: string?): string {
        return Path.Combine(assemblyDirectory, (assemblyName ?? "") + ".dll")
    }

    static func ShouldRunNUnit(testFramework: string?): bool {
        return string.Equals(testFramework ?? "", "nunit", StringComparison.OrdinalIgnoreCase)
    }

    static func IsNSharpTestsTypeName(typeName: string?): bool {
        return string.Equals(typeName ?? "", "NSharpTests", StringComparison.Ordinal)
    }

    // ── THE LIFECYCLE VOCABULARY, AND ITS ORDER ───────────────────────────────
    //
    // The two arrays are the ORDER a native test runs in — everything before the test body, then
    // everything after it — and `IsLifecycleMethodName` is DEFINED IN TERMS OF THEM rather than
    // restating the names, so a runner that invokes a name discovery does not exclude, or excludes
    // a name it never invokes, cannot exist. `Dispose` is the one name that is excluded without
    // being invoked BY NAME: the runner reaches it through `IDisposable`, not reflection.
    static func GetPreTestLifecycleMethodNames(): string[] {
        return ["InitializeAsync", "Setup"]
    }

    static func GetPostTestLifecycleMethodNames(): string[] {
        return ["Teardown", "DisposeAsync"]
    }

    static func IsLifecycleMethodName(methodName: string): bool {
        return NamesContain(GetPreTestLifecycleMethodNames(), methodName) || NamesContain(GetPostTestLifecycleMethodNames(), methodName) || methodName == "Dispose"
    }

    static func NamesContain(names: string[], name: string): bool {
        for nameItem in names {
            if nameItem == name {
                return true
            }
        }

        return false
    }

    static func IsTestMethodAttributeName(attributeFullName: string?): bool {
        return attributeFullName == "Xunit.FactAttribute" || attributeFullName == "Xunit.TheoryAttribute" || attributeFullName == "NUnit.Framework.TestAttribute" || attributeFullName == "NUnit.Framework.TestCaseAttribute"
    }

    static func IsXunitTraitAttributeName(attributeFullName: string?): bool {
        return attributeFullName == "Xunit.TraitAttribute"
    }

    static func IsNSharpDescriptionTraitName(traitName: string?): bool {
        return string.Equals(traitName ?? "", ColumnarAttributeBlobs.DescriptionTraitKey(), StringComparison.Ordinal)
    }

    static func GetNSharpDescriptionTraitKey(): string {
        return ColumnarAttributeBlobs.DescriptionTraitKey()
    }

    static func IsNUnitIgnoreAttributeName(attributeFullName: string?): bool {
        return attributeFullName == "NUnit.Framework.IgnoreAttribute"
    }

    static func IsSkipNamedArgument(memberName: string): bool {
        return memberName == "Skip"
    }

    static func GetExitCode(ok: bool): int {
        if ok {
            return 0
        }

        return 1
    }

    static func IsJsonOutputMode(outputMode: int): bool {
        return outputMode == CommandOutputKernels.GetOutputMode(true)
    }

    static func IsTextOutputMode(outputMode: int): bool {
        return outputMode == CommandOutputKernels.GetOutputMode(false)
    }

    // ── THE OUTCOME VOCABULARY ────────────────────────────────────────────────
    //
    // These three words are `results[].outcome` in the `nlc test --json` envelope AND the join to
    // the rank table below, so they decide both what a user reads and what the process exits with:
    // a word this table does not know ranks 0, which `SummarizeOutcomeRanks` counts as NOT OK.
    // The rank table is DEFINED IN TERMS OF the three accessors rather than restating them.
    static func GetPassedOutcome(): string {
        return "passed"
    }

    static func GetFailedOutcome(): string {
        return "failed"
    }

    static func GetSkippedOutcome(): string {
        return "skipped"
    }

    static func IsSkippedOutcome(outcome: string): bool {
        return outcome == GetSkippedOutcome()
    }

    static func GetXunitRunnerErrorName(): string {
        return "xunit.runner"
    }

    static func GetXunitRunnerErrorDisplayName(): string {
        return "xUnit runner"
    }

    static func GetNativeTestOutcomeRank(outcome: string): int {
        if outcome == GetPassedOutcome() {
            return 1
        }

        if outcome == GetFailedOutcome() {
            return 2
        }

        if outcome == GetSkippedOutcome() {
            return 3
        }

        return 0
    }

    static func SummarizeOutcomeRanks(outcomeRanks: int[], outcomeCount: int): TestOutcomeSummary {
        if outcomeCount < 0 || outcomeCount > outcomeRanks.Length {
            throw new InvalidOperationException("N# test outcome summary kernel rejected the native test results.")
        }

        passed := 0
        failed := 0
        skipped := 0
        nonOk := 0
        i := 0
        while i < outcomeCount {
            rank := outcomeRanks[i]
            if rank == 1 {
                passed = passed + 1
            } else if rank == 2 {
                failed = failed + 1
                nonOk = nonOk + 1
            } else if rank == 3 {
                skipped = skipped + 1
            } else {
                nonOk = nonOk + 1
            }

            i = i + 1
        }

        return new TestOutcomeSummary(nonOk == 0, passed, failed, skipped)
    }

    static func SummarizeNativeTestRun(testRun: NativeTestRun): NativeTestSummary {
        outcomeSummary := SummarizeOutcomeRanks(testRun.OutcomeRanks, testRun.OutcomeCount)
        return new NativeTestSummary(outcomeSummary.Ok && testRun.OutcomeCount > 0, testRun.OutcomeCount, outcomeSummary.Passed, outcomeSummary.Failed, outcomeSummary.Skipped)
    }

    static func NativeTestJson(projectRoot: string, ok: bool, testResults: IReadOnlyList<NativeTestResult>, errorMessage: string?, summary: NativeTestSummary): string {
        return NativeTestJson(projectRoot, ok, testResults, errorMessage, summary, null)
    }

    // `timings` is present only when `--timings` asked for it, so the envelope a caller already
    // reads is byte-for-byte what it was: the field is additive and opt-in, and schemaVersion 1
    // still describes every document without it.
    static func NativeTestJson(projectRoot: string, ok: bool, testResults: IReadOnlyList<NativeTestResult>, errorMessage: string?, summary: NativeTestSummary, timings: NativeTestTimings?): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "test"
        envelope["ok"] = ok
        envelope["projectRoot"] = CommandOutputKernels.NormalizePath(projectRoot)

        if errorMessage != null {
            envelope["error"] = errorMessage ?? ""
        }

        envelope["summary"] = BuildNativeTestSummary(summary)
        if timings != null {
            envelope["timings"] = BuildNativeTestTimings(timings)
        }

        envelope["results"] = BuildNativeTestResults(testResults)
        return JsonSerializer.Serialize(envelope, CommandOutputKernels.CreateWriteIndentedOptions())
    }

    static func BuildNativeTestTimings(timings: NativeTestTimings): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["buildMs"] = timings.BuildMilliseconds
        payload["runMs"] = timings.RunMilliseconds
        payload["totalMs"] = timings.TotalMilliseconds
        return payload
    }

    static func GetTimingsMessage(buildElapsed: string, runElapsed: string, totalElapsed: string): string {
        return "Test timings:\n" + "  Build:      " + buildElapsed + "\n" + "  Run:        " + runElapsed + "\n" + "  Total:      " + totalElapsed
    }

    static func BuildNativeTestSummary(summary: NativeTestSummary): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["total"] = summary.Total
        payload["passed"] = summary.Passed
        payload["failed"] = summary.Failed
        payload["skipped"] = summary.Skipped
        payload["duration"] = "0s"
        return payload
    }

    static func BuildNativeTestResults(testResults: IReadOnlyList<NativeTestResult>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for testResult in testResults {
            payload.Add(BuildNativeTestResult(testResult))
        }

        return payload
    }

    static func BuildNativeTestResult(result: NativeTestResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = result.Name
        payload["displayName"] = result.DisplayName
        payload["outcome"] = result.Outcome
        payload["duration"] = result.Duration

        if result.ErrorMessage != null {
            payload["errorMessage"] = result.ErrorMessage ?? ""
        }

        if result.NsharpDescription != null {
            payload["nsharpDescription"] = result.NsharpDescription ?? ""
        }

        return payload
    }

    static func GetOptionSummary(args: string[]): TestOptionSummary {
        project: string? = null
        filter: string? = null
        timeout: string? = null
        backend: string? = null
        verbose := false
        json := false
        coverageReport := false
        collectCoverage := false
        noCache := false
        timings := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            valueIndex := i + 1
            hasValue := valueIndex < args.Length

            if arg == "--help" {
                showHelp = true
            } else if arg == "-h" {
                showHelp = true
            } else if arg == "--project" {
                if project == null && hasValue {
                    project = args[valueIndex]
                }
            } else if arg == "--filter" {
                if filter == null && hasValue {
                    filter = args[valueIndex]
                }
            } else if arg == "--timeout" {
                if timeout == null && hasValue {
                    timeout = args[valueIndex]
                }
            } else if arg == "--backend" {
                if backend == null && hasValue {
                    backend = args[valueIndex]
                }
            } else if arg == "--verbose" {
                verbose = true
            } else if arg == "--json" {
                json = true
            } else if arg == "--coverage-report" {
                coverageReport = true
            } else if arg == "--coverage" {
                collectCoverage = true
            } else if arg == "--no-cache" {
                noCache = true
            } else if arg == "--timings" {
                timings = true
            }

            i = i + 1
        }

        collectCoverage = collectCoverage || coverageReport

        return new TestOptionSummary(project, backend, filter, timeout, verbose, json, coverageReport, collectCoverage, noCache, timings, showHelp)
    }

    static func GetDurationMilliseconds(duration: string): int? {
        value := DurationMilliseconds(duration)
        if value < 0 {
            return null
        }

        return value
    }

    static func MatchesFilter(filter: string, displayName: string, alternateDisplayName: string, fullyQualifiedName: string): bool {
        segmentStart := 0
        while segmentStart <= filter.Length {
            segmentEnd := segmentStart
            scanning := true
            while scanning {
                if segmentEnd >= filter.Length {
                    scanning = false
                } else if filter[segmentEnd] == '|' {
                    scanning = false
                } else {
                    segmentEnd = segmentEnd + 1
                }
            }

            trimStart := segmentStart
            trimEnd := segmentEnd
            trimmingStart := true
            while trimmingStart {
                if trimStart >= trimEnd {
                    trimmingStart = false
                } else if char.IsWhiteSpace(filter[trimStart]) {
                    trimStart = trimStart + 1
                } else {
                    trimmingStart = false
                }
            }

            trimmingEnd := true
            while trimmingEnd {
                if trimEnd <= trimStart {
                    trimmingEnd = false
                } else if char.IsWhiteSpace(filter[trimEnd - 1]) {
                    trimEnd = trimEnd - 1
                } else {
                    trimmingEnd = false
                }
            }

            if trimStart < trimEnd {
                part := filter.Substring(trimStart, trimEnd - trimStart)
                if ContainsIgnoreCase(displayName, part) {
                    return true
                }

                if ContainsIgnoreCase(alternateDisplayName, part) {
                    return true
                }

                if ContainsIgnoreCase(fullyQualifiedName, part) {
                    return true
                }
            }

            if segmentEnd >= filter.Length {
                break
            }

            segmentStart = segmentEnd + 1
        }

        return false
    }

    static func GetHelpText(): string {
        builder := new StringBuilder()
        CommandOutputKernels.AppendLine(builder, "N# Test")
        CommandOutputKernels.AppendLine(builder, "")
        CommandOutputKernels.AppendLine(builder, "Usage: nlc test [options]")
        CommandOutputKernels.AppendLine(builder, "")
        CommandOutputKernels.AppendLine(builder, "Run `.tests.nl` suites through the IL compilation backend.")
        CommandOutputKernels.AppendLine(builder, "")
        CommandOutputKernels.AppendLine(builder, "Options:")
        CommandOutputKernels.AppendLine(builder, "  --project <dir>       Project root directory (default: current directory)")
        CommandOutputKernels.AppendLine(builder, "  --backend <mode>      Compilation backend: il")
        CommandOutputKernels.AppendLine(builder, "  --filter <name>       Run only tests whose display name or fully-qualified name matches")
        CommandOutputKernels.AppendLine(builder, "  --verbose             Show individual test results")
        CommandOutputKernels.AppendLine(builder, "  --json                Output results as structured JSON (schemaVersion 1 envelope)")
        CommandOutputKernels.AppendLine(builder, "  --timeout <duration>  Test timeout per assembly (e.g., 30s, 5m, 1h). Default: no timeout")
        CommandOutputKernels.AppendLine(builder, "  --no-cache            Force clean rebuild before running tests (bypass incremental build)")
        CommandOutputKernels.AppendLine(builder, "  --timings             Report the build, run and total time (stderr, or `timings` in --json)")
        CommandOutputKernels.AppendLine(builder, "  --coverage            Planned; currently exits with unsupported-feature guidance")
        CommandOutputKernels.AppendLine(builder, "  --coverage-report     Planned; currently exits with unsupported-feature guidance")
        CommandOutputKernels.AppendLine(builder, "  --help, -h            Show this help text")
        CommandOutputKernels.AppendLine(builder, "")
        CommandOutputKernels.AppendLine(builder, "The test framework is configured in project.yml via the `testFramework` field.")
        CommandOutputKernels.AppendLine(builder, "Supported values: xunit (default), nunit")
        CommandOutputKernels.AppendLine(builder, "")
        CommandOutputKernels.AppendLine(builder, "Coverage collection is not available in the native nlc test runner yet.")
        CommandOutputKernels.AppendLine(builder, "When --coverage or --coverage-report is requested, nlc exits 1 and emits")
        CommandOutputKernels.AppendLine(builder, "a structured JSON error if --json was also requested.")
        CommandOutputKernels.AppendLine(builder, "")
        CommandOutputKernels.AppendLine(builder, "Examples:")
        CommandOutputKernels.AppendLine(builder, "  nlc test")
        CommandOutputKernels.AppendLine(builder, "  nlc test --backend il")
        CommandOutputKernels.AppendLine(builder, "  nlc test --filter AddPerson")
        CommandOutputKernels.AppendLine(builder, "  nlc test --project examples/16-task-cli --verbose")
        CommandOutputKernels.AppendLine(builder, "  nlc test --json")
        CommandOutputKernels.AppendLine(builder, "  nlc test --json --timings")
        CommandOutputKernels.AppendLine(builder, "")
        CommandOutputKernels.AppendLine(builder, "Exit codes:")
        CommandOutputKernels.AppendLine(builder, "  0  Tests passed")
        builder.Append("  1  Compilation or test execution failed")
        return builder.ToString()
    }

    static func GetMissingProjectFileMessage(): string {
        return "IL-backed test runs require a project.yml file."
    }

    static func GetCoverageUnsupportedMessage(): string {
        return "Coverage collection is not available in nlc test yet. " + "The current runner executes IL-backed xUnit/NUnit tests without instrumentation. " + "Omit --coverage/--coverage-report until native coverage support lands."
    }

    static func GetBuildFailedMessage(): string {
        return "Test build failed."
    }

    static func GetInvalidTimeoutMessage(timeout: string): string {
        return "Invalid timeout format '" + timeout + "'. Expected a duration like 30s, 5m, or 1h."
    }

    static func GetProjectStartMessage(projectRoot: string): string {
        return "Testing project in " + projectRoot + "..."
    }

    static func GetNoTestFilesMessage(): string {
        return "No test files (*.tests.nl) found."
    }

    static func GetFoundTestFilesMessage(testFileCount: int): string {
        return "Found " + testFileCount.ToString() + " test file(s)"
    }

    static func GetSummaryMessage(passed: int, failed: int, skipped: int, total: int): string {
        return "Passed: " + passed.ToString() + ", Failed: " + failed.ToString() + ", Skipped: " + skipped.ToString() + ", Total: " + total.ToString()
    }

    // ── THE FAILURES A TEXT RUN NAMES ─────────────────────────────────────────
    //
    // A red text run that prints only `Passed: 27, Failed: 1, …` has told its reader THAT something
    // failed and nothing about WHAT: CI run 36165060886 is exactly that log, and the only way to
    // learn the row was to rerun the job with `--json`. So the default output names every failed row
    // before the summary — the sentence the reader wrote, the method it lowered to, and the failure
    // message indented under it — and a green run prints nothing new. The JSON envelope already
    // carries the same three facts per row (`displayName`, `name`, `errorMessage`), so this is the
    // text route catching up, not a new fact.
    //
    // The report comes BEFORE the summary so the summary stays the last line a script reads.
    static func GetFailureReport(testResults: IReadOnlyList<NativeTestResult>): string? {
        failures := new List<NativeTestResult>()
        for testResult in testResults {
            if testResult.Outcome == GetFailedOutcome() {
                failures.Add(testResult)
            }
        }

        if failures.Count == 0 {
            return null
        }

        report := new StringBuilder()
        report.Append("Failed tests (" + failures.Count.ToString() + "):\n")
        index := 0
        while index < failures.Count {
            failure := failures[index]
            report.Append("\n  " + (index + 1).ToString() + ". " + failure.DisplayName + "\n")
            if failure.Name != failure.DisplayName {
                report.Append("     at " + failure.Name + "\n")
            }

            message := failure.ErrorMessage ?? ""
            if string.IsNullOrWhiteSpace(message) {
                message = GetFailureWithoutMessageText()
            }

            for line in message.Replace("\r\n", "\n").TrimEnd('\n').Split('\n') {
                report.Append("     " + line + "\n")
            }

            index = index + 1
        }

        return report.ToString()
    }

    static func GetFailureWithoutMessageText(): string {
        return "(the test runner reported this failure without a message)"
    }

    static func GetCompletedElapsedMessage(elapsedText: string): string {
        return "  Tests completed in " + elapsedText
    }

    static func GetFailedElapsedMessage(elapsedText: string): string {
        return "  Tests failed in " + elapsedText
    }

    static func GetFailedMessage(message: string): string {
        return "Test failed: " + message
    }

    static func GetVerbosePassedMessage(displayName: string, elapsedMillisecondsText: string): string {
        return "Passed " + displayName + " [" + elapsedMillisecondsText + " ms]"
    }

    static func GetVerboseSkippedMessage(displayName: string, reason: string): string {
        return "Skipped " + displayName + ": " + reason
    }

    static func GetVerboseFailedMessage(displayName: string, message: string): string {
        return "Failed " + displayName + ": " + message
    }

    // ── WHICH VERBOSE SENTENCE PRINTS ─────────────────────────────────────────
    //
    // This is result classification and it used to be a nested conditional in the runner, keyed on
    // the literal `"skipped"`. THE SHAPE IS KEPT EXACTLY, including the part that is surprising:
    // the ABSENCE of an error message wins over the outcome, so a skip with no reason reads as a
    // pass. That is the behaviour the runner had; changing it is a separate decision, and it is now
    // a decision this file makes rather than one buried in a `?:`.
    static func GetVerboseMessage(outcome: string, displayName: string, elapsedMillisecondsText: string, errorMessage: string?): string {
        if errorMessage == null {
            return GetVerbosePassedMessage(displayName, elapsedMillisecondsText)
        }

        if IsSkippedOutcome(outcome) {
            return GetVerboseSkippedMessage(displayName, errorMessage ?? "")
        }

        return GetVerboseFailedMessage(displayName, errorMessage ?? "")
    }

    // ── THE DURATION AND ELAPSED FORMATS ──────────────────────────────────────
    //
    // `FormatTestDurationSeconds` is `results[].duration` in the versioned JSON envelope, so it is
    // stable output and it is INVARIANT. The runner used to build it with `$"{…:F3}s"`, which reads
    // the CURRENT culture — under a comma-decimal locale the envelope printed `1,234s`. Moving the
    // format here fixes that, and the fix is the one behaviour change this owner makes on purpose.
    static func FormatTestDurationSeconds(seconds: double): string {
        return seconds.ToString("F3", CultureInfo.InvariantCulture) + "s"
    }

    static func GetZeroTestDuration(): string {
        return FormatTestDurationSeconds(0.0)
    }

    static func FormatTestElapsedMilliseconds(milliseconds: double): string {
        return milliseconds.ToString("F0", CultureInfo.InvariantCulture)
    }

    // ── THE NAME A TEST IS SHOWN UNDER ────────────────────────────────────────
    //
    // An N# `test "…"` declaration lowers its sentence into an `NSharpDescription` trait, and that
    // sentence WINS over whatever xUnit or the reflection walk would otherwise call the method.
    static func GetPreferredDisplayName(nsharpDescription: string?, frameworkDisplayName: string): string {
        return nsharpDescription ?? frameworkDisplayName
    }

    // ── THE FAILURE TEXT A RUNNER-LEVEL ERROR SHOWS ───────────────────────────
    //
    // xUnit hands back a message ARRAY; this is what turns it into the one `errorMessage` string
    // the envelope and the verbose line carry. Blank entries are dropped rather than printed as
    // empty lines.
    static func JoinFailureMessages(messages: string[]): string {
        kept := new List<string>()
        for message in messages {
            if !string.IsNullOrWhiteSpace(message) {
                kept.Add(message)
            }
        }

        return string.Join(Environment.NewLine, kept)
    }

    // ── THE TIMEOUT CLASSIFICATION AND THE ARITY POLICY ───────────────────────
    //
    // A TIMEOUT IS AN OUTCOME, so classifying one is result classification and both of its
    // sentences are stable user-facing output. The parameter-arity refusal is a POLICY — "a native
    // test method takes none" — with a user-facing sentence attached. Task 020's contract puts all
    // three on this side of the line: `src/NSharpLang.Cli/Program.Testing.cs` may only mechanically
    // execute the plan these decide.

    static func GetRunTimedOutMessage(): string {
        return "Test run timed out."
    }

    static func GetTestTimedOutMessage(): string {
        return "Test timed out."
    }

    // A native test method takes no parameters: N# lowers a table row's values into locals in the
    // body, so there is nothing for the runner to bind.
    static func IsSupportedTestMethodArity(parameterCount: int): bool {
        return parameterCount == 0
    }

    static func GetUnsupportedTestArityMessage(testFullName: string, parameterCount: int): string {
        return "Test '" + testFullName + "' expects " + parameterCount.ToString() + " argument(s), but a native test method takes none."
    }

    static func GetTestFullName(declaringTypeFullName: string?, methodName: string): string {
        return (declaringTypeFullName ?? "") + "." + methodName
    }

    static func DurationMilliseconds(duration: string): int {
        start := 0
        end := duration.Length - 1
        while start <= end && char.IsWhiteSpace(duration[start]) {
            start = start + 1
        }

        while end >= start && char.IsWhiteSpace(duration[end]) {
            end = end - 1
        }

        trimmedLength := end - start + 1
        if trimmedLength < 2 {
            return -1
        }

        unit := duration[end]
        multiplier := 0
        if unit == 's' {
            multiplier = 1000
        } else if unit == 'm' {
            multiplier = 60000
        } else if unit == 'h' {
            multiplier = 3600000
        } else {
            return -1
        }

        limit := 2147483647 / multiplier
        value := 0
        index := start
        while index < end {
            ch := duration[index]
            if ch < '0' || ch > '9' {
                return -1
            }

            digit := ch - '0'
            if value > (limit - digit) / 10 {
                return -1
            }

            value = value * 10 + digit
            index = index + 1
        }

        if value <= 0 {
            return -1
        }

        return value * multiplier
    }

    static func ContainsIgnoreCase(text: string, part: string): bool {
        return text.IndexOf(part, StringComparison.OrdinalIgnoreCase) >= 0
    }
}
