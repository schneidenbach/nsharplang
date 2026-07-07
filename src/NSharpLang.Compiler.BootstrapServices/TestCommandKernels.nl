namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Reflection
import System.Text

public class NativeTestCase {
    DisplayName: string
    FullyQualifiedName: string
    Method: MethodInfo
    Arguments: object?[]
    SkipReason: string?

    constructor(
        displayName: string,
        fullyQualifiedName: string,
        method: MethodInfo,
        arguments: object?[],
        skipReason: string?) {
        DisplayName = displayName
        FullyQualifiedName = fullyQualifiedName
        Method = method
        Arguments = arguments
        SkipReason = skipReason
    }
}

public class NativeTestResult {
    Name: string
    DisplayName: string
    Outcome: string
    Duration: string
    ErrorMessage: string?
    NsharpDescription: string?

    constructor(
        name: string,
        displayName: string,
        outcome: string,
        duration: string,
        errorMessage: string?,
        nsharpDescription: string?) {
        Name = name
        DisplayName = displayName
        Outcome = outcome
        Duration = duration
        ErrorMessage = errorMessage
        NsharpDescription = nsharpDescription
    }
}

public class NativeTestRun {
    Results: IReadOnlyList<NativeTestResult>
    OutcomeRanks: int[]
    OutcomeCount: int

    constructor(results: IReadOnlyList<NativeTestResult>, outcomeRanks: int[], outcomeCount: int) {
        Results = results
        OutcomeRanks = outcomeRanks
        OutcomeCount = outcomeCount
    }
}

public class TestOutcomeSummary {
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

public class NativeTestSummary {
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

    public static EmptyFailure: NativeTestSummary => new NativeTestSummary(false, 0, 0, 0, 0)

    constructor(ok: bool, total: int, passed: int, failed: int, skipped: int) {
        okValue = ok
        totalValue = total
        passedValue = passed
        failedValue = failed
        skippedValue = skipped
    }
}

public class TestOptionSummary {
    projectOptionValue: string?
    backendOptionValue: string?
    filterValue: string?
    timeoutValue: string?
    verboseValue: bool
    jsonOutputValue: bool
    coverageReportValue: bool
    collectCoverageValue: bool
    noCacheValue: bool
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
    ShowHelp: bool => showHelpValue

    constructor(
        projectOption: string?,
        backendOption: string?,
        filter: string?,
        timeout: string?,
        verbose: bool,
        jsonOutput: bool,
        coverageReport: bool,
        collectCoverage: bool,
        noCache: bool,
        showHelp: bool) {
        projectOptionValue = projectOption
        backendOptionValue = backendOption
        filterValue = filter
        timeoutValue = timeout
        verboseValue = verbose
        jsonOutputValue = jsonOutput
        coverageReportValue = coverageReport
        collectCoverageValue = collectCoverage
        noCacheValue = noCache
        showHelpValue = showHelp
    }
}

public class TestCommandKernels {
    public static func SummarizeOutcomeRanks(outcomeRanks: int[], outcomeCount: int): TestOutcomeSummary {
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

    public static func GetOptionSummary(args: string[]): TestOptionSummary {
        project: string? = null
        filter: string? = null
        timeout: string? = null
        backend: string? = null
        verbose := false
        json := false
        coverageReport := false
        collectCoverage := false
        noCache := false
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
            }

            i = i + 1
        }

        collectCoverage = collectCoverage || coverageReport

        return new TestOptionSummary(
            project,
            backend,
            filter,
            timeout,
            verbose,
            json,
            coverageReport,
            collectCoverage,
            noCache,
            showHelp)
    }

    public static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    public static func GetDurationMilliseconds(duration: string): int? {
        value := DurationMilliseconds(duration)
        if value < 0 {
            return null
        }

        return value
    }

    public static func MatchesFilter(
        filter: string,
        displayName: string,
        alternateDisplayName: string,
        fullyQualifiedName: string): bool {
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

    public static func GetHelpText(): string {
        builder := new StringBuilder()
        AppendLine(builder, "N# Test")
        AppendLine(builder, "")
        AppendLine(builder, "Usage: nlc test [options]")
        AppendLine(builder, "")
        AppendLine(builder, "Run `.tests.nl` suites through the IL compilation backend.")
        AppendLine(builder, "")
        AppendLine(builder, "Options:")
        AppendLine(builder, "  --project <dir>       Project root directory (default: current directory)")
        AppendLine(builder, "  --backend <mode>      Compilation backend: il")
        AppendLine(builder, "  --filter <name>       Run only tests whose display name or fully-qualified name matches")
        AppendLine(builder, "  --verbose             Show individual test results")
        AppendLine(builder, "  --json                Output results as structured JSON (schemaVersion 1 envelope)")
        AppendLine(builder, "  --timeout <duration>  Test timeout per assembly (e.g., 30s, 5m, 1h). Default: no timeout")
        AppendLine(builder, "  --no-cache            Force clean rebuild before running tests (bypass incremental build)")
        AppendLine(builder, "  --coverage            Planned; currently exits with unsupported-feature guidance")
        AppendLine(builder, "  --coverage-report     Planned; currently exits with unsupported-feature guidance")
        AppendLine(builder, "  --help, -h            Show this help text")
        AppendLine(builder, "")
        AppendLine(builder, "The test framework is configured in project.yml via the `testFramework` field.")
        AppendLine(builder, "Supported values: xunit (default), nunit")
        AppendLine(builder, "")
        AppendLine(builder, "Coverage collection is not available in the native nlc test runner yet.")
        AppendLine(builder, "When --coverage or --coverage-report is requested, nlc exits 1 and emits")
        AppendLine(builder, "a structured JSON error if --json was also requested.")
        AppendLine(builder, "")
        AppendLine(builder, "Examples:")
        AppendLine(builder, "  nlc test")
        AppendLine(builder, "  nlc test --backend il")
        AppendLine(builder, "  nlc test --filter AddPerson")
        AppendLine(builder, "  nlc test --project examples/16-task-cli --verbose")
        AppendLine(builder, "  nlc test --json")
        AppendLine(builder, "")
        AppendLine(builder, "Exit codes:")
        AppendLine(builder, "  0  Tests passed")
        builder.Append("  1  Compilation or test execution failed")
        return builder.ToString()
    }

    public static func GetMissingProjectFileMessage(): string {
        return "IL-backed test runs require a project.yml file."
    }

    public static func GetCoverageUnsupportedMessage(): string {
        return "Coverage collection is not available in nlc test yet. "
            + "The current runner executes IL-backed xUnit/NUnit tests without instrumentation. "
            + "Omit --coverage/--coverage-report until native coverage support lands."
    }

    public static func GetBuildFailedMessage(): string {
        return "Test build failed."
    }

    public static func GetInvalidTimeoutMessage(timeout: string): string {
        return "Invalid timeout format '" + timeout + "'. Expected a duration like 30s, 5m, or 1h."
    }

    public static func GetProjectStartMessage(projectRoot: string): string {
        return "Testing project in " + projectRoot + "..."
    }

    public static func GetNoTestFilesMessage(): string {
        return "No test files (*.tests.nl) found."
    }

    public static func GetFoundTestFilesMessage(testFileCount: int): string {
        return "Found " + testFileCount.ToString() + " test file(s)"
    }

    public static func GetSummaryMessage(passed: int, failed: int, skipped: int, total: int): string {
        return "Passed: " + passed.ToString()
            + ", Failed: " + failed.ToString()
            + ", Skipped: " + skipped.ToString()
            + ", Total: " + total.ToString()
    }

    public static func GetCompletedElapsedMessage(elapsedText: string): string {
        return "  Tests completed in " + elapsedText
    }

    public static func GetFailedElapsedMessage(elapsedText: string): string {
        return "  Tests failed in " + elapsedText
    }

    public static func GetFailedMessage(message: string): string {
        return "Test failed: " + message
    }

    public static func GetVerbosePassedMessage(displayName: string, elapsedMillisecondsText: string): string {
        return "Passed " + displayName + " [" + elapsedMillisecondsText + " ms]"
    }

    public static func GetVerboseSkippedMessage(displayName: string, reason: string): string {
        return "Skipped " + displayName + ": " + reason
    }

    public static func GetVerboseFailedMessage(displayName: string, message: string): string {
        return "Failed " + displayName + ": " + message
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

    static func AppendLine(builder: StringBuilder, text: string) {
        builder.Append(text)
        builder.Append((char)10)
    }
}
