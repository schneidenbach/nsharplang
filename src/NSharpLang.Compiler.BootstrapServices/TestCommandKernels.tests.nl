namespace NSharpLang.Cli

import System.Collections.Generic

// THE `nlc test` OUTCOME, OPTION, TIMEOUT, MESSAGE AND FILTER KERNELS.
//
// The blocks below the native-run summaries replace FIVE `[Fact]`s deleted from
// `tests/CliCommandTests.cs`: `TestCommandKernels_SummarizesTestOutcomeRanks`,
// `..._SummarizesOptions`, `..._ParsesTimeoutDurations`, `..._ShapesMessages` and
// `..._MatchFilters`.
//
// ONE OF THE FIVE IS SPLIT, AND THE SPLIT IS FORCED. `..._ParsesTimeoutDurations` made five kernel
// claims and then drove `nlc test --timeout 2147484s` through a console capture to read an exit
// code, a stderr sentence and a JSON envelope. `Console.SetOut` declines on this emit path at
// `emit.call.static-member-unmodeled`, so those rows CANNOT be made here; they are in
// `tests/native/cli-command-contracts`, spawned against the real binary.

func NativeRun(outcomeRanks: int[], outcomeCount: int): NativeTestRun {
    return new NativeTestRun(new List<NativeTestResult>(), outcomeRanks, outcomeCount)
}

test "native test summaries reject empty discovery" {
    summary := TestCommandKernels.SummarizeNativeTestRun(NativeRun(new int[](0), 0))

    assert !summary.Ok
    assert summary.Total == 0
    assert summary.Passed == 0
    assert summary.Failed == 0
    assert summary.Skipped == 0
}

test "native test summaries accept a nonempty successful run" {
    outcomes := new int[](2)
    outcomes[0] = TestCommandKernels.GetNativeTestOutcomeRank("passed")
    outcomes[1] = TestCommandKernels.GetNativeTestOutcomeRank("skipped")

    summary := TestCommandKernels.SummarizeNativeTestRun(NativeRun(outcomes, outcomes.Length))

    assert summary.Ok
    assert summary.Total == 2
    assert summary.Passed == 1
    assert summary.Failed == 0
    assert summary.Skipped == 1
}

// ── the outcome-rank summary ──────────────────────────────────────────────────

test "the outcome summary counts each rank and fails the run when any test failed" {
    // Ranks: 0 = unknown, 1 = passed, 2 = failed, 3 = skipped.
    summary := TestCommandKernels.SummarizeOutcomeRanks([1, 1, 3, 2, 0, 1], 6)

    assert !summary.Ok
    assert summary.Passed == 3
    assert summary.Failed == 1
    assert summary.Skipped == 1
}

test "the outcome summary honours its count, so a prefix answers from the prefix only" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. It passed the full width once; a kernel that
    // ignored `outcomeCount` and walked the whole array would have passed it unnoticed. The first
    // three of the same six ranks contain no failure at all, so the run must be OK.
    prefix := TestCommandKernels.SummarizeOutcomeRanks([1, 1, 3, 2, 0, 1], 3)

    assert prefix.Ok
    assert prefix.Passed == 2
    assert prefix.Failed == 0
    assert prefix.Skipped == 1
}

// ── the option summary ────────────────────────────────────────────────────────

test "the test option summary reads every flag and option value" {
    summary := TestCommandKernels.GetOptionSummary([
        "--project",
        "samples/demo",
        "--backend",
        "il",
        "--filter",
        "Adds",
        "--timeout",
        "30s",
        "--verbose",
        "--json",
        "--coverage-report",
        "--no-cache"
    ])

    assert summary.ProjectOption == "samples/demo"
    assert summary.BackendOption == "il"
    assert summary.Filter == "Adds"
    assert summary.Timeout == "30s"
    assert summary.Verbose
    assert summary.JsonOutput
    // `--coverage-report` implies collection; the deleted body pinned both together
    assert summary.CoverageReport
    assert summary.CollectCoverage
    assert summary.NoCache
    assert !summary.ShowHelp
}

test "the bare word help asks for help without swallowing the flags after it" {
    summary := TestCommandKernels.GetOptionSummary(["help", "--json"])

    assert summary.ShowHelp
    assert summary.JsonOutput
}

test "test option values are taken permissively, so --help can be consumed as the project" {
    // DELIBERATE AND PINNED: the option parser does not look ahead for a leading `-`, so
    // `--project --help` binds `--help` as the project path AND still sets the help flag.
    summary := TestCommandKernels.GetOptionSummary(["--project", "--help"])

    assert summary.ProjectOption == "--help"
    assert summary.ShowHelp
}

test "test output mode is 2 for text and 1 for json" {
    assert TestCommandKernels.GetOutputMode(false) == 2
    assert TestCommandKernels.GetOutputMode(true) == 1
}

// ── the timeout parser ────────────────────────────────────────────────────────

test "the timeout parser reads seconds, minutes and hours, and trims" {
    seconds := TestCommandKernels.GetDurationMilliseconds("30s")
    assert seconds != null
    assert (seconds ?? 0) == 30000

    minutes := TestCommandKernels.GetDurationMilliseconds(" 5m ")
    assert minutes != null
    assert (minutes ?? 0) == 300000

    hours := TestCommandKernels.GetDurationMilliseconds("1h")
    assert hours != null
    assert (hours ?? 0) == 3600000
}

test "the timeout parser refuses a zero duration and one that overflows the millisecond field" {
    assert TestCommandKernels.GetDurationMilliseconds("0s") == null
    // 2,147,484 seconds is 2,147,484,000 ms, past Int32
    assert TestCommandKernels.GetDurationMilliseconds("2147484s") == null
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the test help text names the command, its usage and the coverage flag" {
    helpText := TestCommandKernels.GetHelpText()

    assert helpText.StartsWith("N# Test")
    assert helpText.Contains("Usage: nlc test [options]")
    assert helpText.Contains("--coverage-report")
}

test "the test command's failure and progress sentences are exactly these" {
    assert TestCommandKernels.GetMissingProjectFileMessage() == "IL-backed test runs require a project.yml file."
    assert TestCommandKernels.GetCoverageUnsupportedMessage() == "Coverage collection is not available in nlc test yet. The current runner executes IL-backed xUnit/NUnit tests without instrumentation. Omit --coverage/--coverage-report until native coverage support lands."
    assert TestCommandKernels.GetBuildFailedMessage() == "Test build failed."
    assert TestCommandKernels.GetInvalidTimeoutMessage("7w") == "Invalid timeout format '7w'. Expected a duration like 30s, 5m, or 1h."
    assert TestCommandKernels.GetProjectStartMessage("/tmp/demo") == "Testing project in /tmp/demo..."
    assert TestCommandKernels.GetNoTestFilesMessage() == "No test files (*.tests.nl) found."
    assert TestCommandKernels.GetFoundTestFilesMessage(3) == "Found 3 test file(s)"
    assert TestCommandKernels.GetSummaryMessage(2, 1, 4, 7) == "Passed: 2, Failed: 1, Skipped: 4, Total: 7"
    assert TestCommandKernels.GetCompletedElapsedMessage("42ms") == "  Tests completed in 42ms"
    assert TestCommandKernels.GetFailedElapsedMessage("42ms") == "  Tests failed in 42ms"
    assert TestCommandKernels.GetFailedMessage("boom") == "Test failed: boom"
}

test "the verbose per-test sentences are exactly these" {
    assert TestCommandKernels.GetVerbosePassedMessage("adds person", "12") == "Passed adds person [12 ms]"
    assert TestCommandKernels.GetVerboseSkippedMessage("adds person", "not today") == "Skipped adds person: not today"
    assert TestCommandKernels.GetVerboseFailedMessage("adds person", "nope") == "Failed adds person: nope"
}

// ── the --filter matcher ──────────────────────────────────────────────────────

test "the filter matches a display name, an alternate name or a fully-qualified name" {
    // Spaces are ignored and the comparison is case-insensitive: "addperson" reaches "Add Person".
    assert TestCommandKernels.MatchesFilter("addperson", "Add Person", "", "Tests.AddPerson")
    // a padded needle still matches inside the display name
    assert TestCommandKernels.MatchesFilter(" description ", "Custom Description", "RawDisplayName", "Tests.Raw")
    // the ALTERNATE display name is searched too
    assert TestCommandKernels.MatchesFilter("rawdisplay", "Custom Description", "RawDisplayName", "Tests.Raw")
}

test "a pipe in the filter is an OR, and an all-empty one matches nothing" {
    assert TestCommandKernels.MatchesFilter("missing | second", "First", "", "Tests.SecondCase")
    // " | " is two empty alternatives, which must NOT degenerate into "match everything"
    assert !TestCommandKernels.MatchesFilter(" | ", "First", "", "Tests.SecondCase")
    assert !TestCommandKernels.MatchesFilter("missing", "First", "", "Tests.SecondCase")
}
