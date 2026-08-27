namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Globalization

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

// ── the timeout classification and the arity policy ───────────────────────────
//
// SLICE 44 MOVED THESE THREE DECISIONS OUT OF `src/NSharpLang.Cli/Program.Testing.cs`, WHICH IS
// WHAT DISCHARGES TASK 020's CONDITION (2). Slice 42's partition of that file found six residue
// items and split them: three are internal invariant violations on paths the CLR hands back —
// mechanical, and they stay — while these three are not. A TIMEOUT IS AN OUTCOME, so classifying
// one is result classification by definition and both sentences are user-facing; and the
// parameter-arity refusal is a POLICY with a user-facing sentence attached.
//
// The C# now reads `IsSupportedTestMethodArity` for the decision and calls the three message
// kernels for the words. These blocks are what pin them, so a change to either sentence has to be
// made here.

test "the two timeout sentences are exactly these, and they are DIFFERENT sentences" {
    // The whole-run timeout and the per-test timeout are distinct classifications and read
    // differently. A move that collapsed them into one string would pass a `Contains` check and
    // fail this.
    assert TestCommandKernels.GetRunTimedOutMessage() == "Test run timed out."
    assert TestCommandKernels.GetTestTimedOutMessage() == "Test timed out."
    assert TestCommandKernels.GetRunTimedOutMessage() != TestCommandKernels.GetTestTimedOutMessage()
}

test "a native test method takes NO parameters, and every other arity is refused" {
    assert TestCommandKernels.IsSupportedTestMethodArity(0)
    assert !TestCommandKernels.IsSupportedTestMethodArity(1)
    assert !TestCommandKernels.IsSupportedTestMethodArity(2)
    // a negative count cannot come from `GetParameters().Length`, but the predicate is total
    assert !TestCommandKernels.IsSupportedTestMethodArity(-1)
}

test "the arity refusal names the test and the count it actually found" {
    assert TestCommandKernels.GetUnsupportedTestArityMessage("Tests.Adds", 2)
        == "Test 'Tests.Adds' expects 2 argument(s), but a native test method takes none."
    // both arguments are really read — a kernel hard-coding either would pass one row and fail this
    assert TestCommandKernels.GetUnsupportedTestArityMessage("Other.Subtracts", 1)
        == "Test 'Other.Subtracts' expects 1 argument(s), but a native test method takes none."
}

test "the test full name joins the declaring type and the method with a dot" {
    assert TestCommandKernels.GetTestFullName("NSharpTests", "Adds") == "NSharpTests.Adds"
    // A CLR-HANDED NULL IS THE CASE THE C# INTERPOLATION USED TO ABSORB SILENTLY. `MethodInfo`'s
    // `DeclaringType` is nullable, and `$"{null}.{name}"` rendered a leading dot; the kernel keeps
    // exactly that shape rather than inventing a new one, so the move changes no output.
    assert TestCommandKernels.GetTestFullName(null, "Adds") == ".Adds"
}


// ══ 021/6: THE RUNNER'S REMAINING VOCABULARY ═══════════════════════════════════════════════════
//
// SLICE 42's partition of `src/NSharpLang.Cli/Program.Testing.cs` named FOUR residues; a full
// literal census at slice 6's tip found TWELVE. The blocks below pin the ones that decide what a
// user reads or what the process exits with. THEY ARE ALSO THE FIRST PINS THESE ANSWERS HAVE EVER
// HAD: before this slice, `grep '"outcome"'` over `tests/native/cli-command-contracts/*.nl` and
// `tests/*.cs` returned no row naming a native `nlc test` outcome, so the three words that decide
// `nlc test`'s exit code could have been renamed to anything and the whole suite would have passed.

// ── the outcome vocabulary, and the exit code that hangs off it ────────────────

test "the three native test outcomes are exactly these words" {
    assert TestCommandKernels.GetPassedOutcome() == "passed"
    assert TestCommandKernels.GetFailedOutcome() == "failed"
    assert TestCommandKernels.GetSkippedOutcome() == "skipped"
    // all three distinct — a move that collapsed two of them would still satisfy a `Contains` check
    assert TestCommandKernels.GetPassedOutcome() != TestCommandKernels.GetFailedOutcome()
    assert TestCommandKernels.GetPassedOutcome() != TestCommandKernels.GetSkippedOutcome()
    assert TestCommandKernels.GetFailedOutcome() != TestCommandKernels.GetSkippedOutcome()
}

test "the rank table answers over the vocabulary it is defined from" {
    assert TestCommandKernels.GetNativeTestOutcomeRank(TestCommandKernels.GetPassedOutcome()) == 1
    assert TestCommandKernels.GetNativeTestOutcomeRank(TestCommandKernels.GetFailedOutcome()) == 2
    assert TestCommandKernels.GetNativeTestOutcomeRank(TestCommandKernels.GetSkippedOutcome()) == 3
}

test "an outcome word the table does not know ranks 0 and FAILS THE RUN" {
    // THE CONSEQUENCE THE VOCABULARY CARRIES, MADE EXPLICIT. The three words are not decoration:
    // they are the join between the runner and the classifier, so a runner that wrote "Passed"
    // with a capital P would produce a run of one passing test that exits 1.
    assert TestCommandKernels.GetNativeTestOutcomeRank("Passed") == 0
    assert TestCommandKernels.GetNativeTestOutcomeRank("") == 0

    misspelled := new int[](1)
    misspelled[0] = TestCommandKernels.GetNativeTestOutcomeRank("Passed")
    summary := TestCommandKernels.SummarizeNativeTestRun(NativeRun(misspelled, 1))

    assert !summary.Ok
    assert summary.Passed == 0
    assert TestCommandKernels.GetExitCode(summary.Ok) == 1
}

test "the skipped predicate answers over the same word the vocabulary names" {
    assert TestCommandKernels.IsSkippedOutcome(TestCommandKernels.GetSkippedOutcome())
    assert !TestCommandKernels.IsSkippedOutcome(TestCommandKernels.GetPassedOutcome())
    assert !TestCommandKernels.IsSkippedOutcome(TestCommandKernels.GetFailedOutcome())
    assert !TestCommandKernels.IsSkippedOutcome("Skipped")
}

test "the xUnit runner error row is named and shown with exactly these two strings" {
    // A RUNNER-LEVEL `IErrorMessage` has no test behind it, so the runner synthesizes a result row.
    // These are its `name` and its `displayName`/`nsharpDescription` in the JSON envelope, and they
    // are DIFFERENT strings — an id and a label.
    assert TestCommandKernels.GetXunitRunnerErrorName() == "xunit.runner"
    assert TestCommandKernels.GetXunitRunnerErrorDisplayName() == "xUnit runner"
    assert TestCommandKernels.GetXunitRunnerErrorName() != TestCommandKernels.GetXunitRunnerErrorDisplayName()
}

// ── the duration and elapsed formats ──────────────────────────────────────────

test "a test duration is three decimal places and a trailing s" {
    assert TestCommandKernels.FormatTestDurationSeconds(0.0) == "0.000s"
    assert TestCommandKernels.FormatTestDurationSeconds(0.5) == "0.500s"
    assert TestCommandKernels.FormatTestDurationSeconds(12.3456) == "12.346s"
    // the zero literal the runner used to spell inline is the same function at zero
    assert TestCommandKernels.GetZeroTestDuration() == "0.000s"
    assert TestCommandKernels.GetZeroTestDuration() == TestCommandKernels.FormatTestDurationSeconds(0.0)
}

test "the duration format is INVARIANT, so the JSON envelope never carries a comma decimal" {
    // THE ONE BEHAVIOUR CHANGE THIS SLICE MAKES ON PURPOSE. The runner built this string with
    // `$"{…:F3}s"`, which reads the CURRENT culture; under a comma-decimal locale the versioned
    // envelope printed `1,234s`. Stable output is invariant output.
    probe := 1.234
    formatted := TestCommandKernels.FormatTestDurationSeconds(probe)

    assert formatted == "1.234s"
    // THE CONTROL, WITHOUT WHICH THIS BLOCK WOULD BE A PROPERTY OF THE AMBIENT LOCALE RATHER THAN
    // OF THE KERNEL: the same value under a comma-decimal culture really does render a comma here.
    assert probe.ToString("F3", CultureInfo.GetCultureInfo("de-DE")) == "1,234"
    assert !formatted.Contains(",")
}

test "the verbose elapsed number is whole milliseconds, invariant, with no unit" {
    // The ` ms` suffix belongs to `GetVerbosePassedMessage`; this kernel owns only the number.
    assert TestCommandKernels.FormatTestElapsedMilliseconds(12.0) == "12"
    assert TestCommandKernels.FormatTestElapsedMilliseconds(1234.6) == "1235"
    assert TestCommandKernels.FormatTestElapsedMilliseconds(0.0) == "0"
    assert !TestCommandKernels.FormatTestElapsedMilliseconds(1234.6).Contains(",")
}

// ── which verbose sentence prints ─────────────────────────────────────────────

test "the verbose classification picks the passed, skipped or failed sentence" {
    assert TestCommandKernels.GetVerboseMessage(TestCommandKernels.GetPassedOutcome(), "adds person", "12", null)
        == "Passed adds person [12 ms]"
    assert TestCommandKernels.GetVerboseMessage(TestCommandKernels.GetSkippedOutcome(), "adds person", "0", "not today")
        == "Skipped adds person: not today"
    assert TestCommandKernels.GetVerboseMessage(TestCommandKernels.GetFailedOutcome(), "adds person", "3", "nope")
        == "Failed adds person: nope"
}

test "the ABSENCE of an error message wins over the outcome, exactly as the runner had it" {
    // PINNED BECAUSE IT IS SURPRISING, NOT BECAUSE IT IS RIGHT. The C# conditional this replaces
    // tested `errorMessage == null` FIRST, so a skip carrying no reason read as a pass. The move is
    // an ownership move; changing this is a separate decision, and this row is what would fail it.
    assert TestCommandKernels.GetVerboseMessage(TestCommandKernels.GetSkippedOutcome(), "adds person", "0", null)
        == "Passed adds person [0 ms]"
    // and an unknown outcome carrying a message reads as a failure
    assert TestCommandKernels.GetVerboseMessage("weird", "adds person", "1", "boom")
        == "Failed adds person: boom"
}

// ── the lifecycle vocabulary and its order ────────────────────────────────────

test "the pre-test lifecycle runs InitializeAsync and then Setup, IN THAT ORDER" {
    names := TestCommandKernels.GetPreTestLifecycleMethodNames()

    assert names.Length == 2
    assert names[0] == "InitializeAsync"
    assert names[1] == "Setup"
}

test "the post-test lifecycle runs Teardown and then DisposeAsync, IN THAT ORDER" {
    names := TestCommandKernels.GetPostTestLifecycleMethodNames()

    assert names.Length == 2
    assert names[0] == "Teardown"
    assert names[1] == "DisposeAsync"
}

test "every name the runner INVOKES is a name discovery EXCLUDES, and Dispose is the only extra" {
    // The two directions used to be spelled separately — four literals in the runner, five in the
    // predicate — so a lifecycle method could have been invoked AND discovered as a test. The
    // predicate is now defined from the two arrays, and this is what pins the remainder.
    pre := TestCommandKernels.GetPreTestLifecycleMethodNames()
    post := TestCommandKernels.GetPostTestLifecycleMethodNames()

    assert TestCommandKernels.IsLifecycleMethodName(pre[0])
    assert TestCommandKernels.IsLifecycleMethodName(pre[1])
    assert TestCommandKernels.IsLifecycleMethodName(post[0])
    assert TestCommandKernels.IsLifecycleMethodName(post[1])
    // `Dispose` is excluded from discovery but never invoked BY NAME — the runner reaches it
    // through `IDisposable`
    assert TestCommandKernels.IsLifecycleMethodName("Dispose")
    assert !TestCommandKernels.NamesContain(pre, "Dispose")
    assert !TestCommandKernels.NamesContain(post, "Dispose")
    // an ordinary test method is none of them
    assert !TestCommandKernels.IsLifecycleMethodName("Adds")
    assert !TestCommandKernels.IsLifecycleMethodName("setup")
}

// ── the name a test is shown under ────────────────────────────────────────────

test "an N# description wins over the framework display name, and null falls back" {
    assert TestCommandKernels.GetPreferredDisplayName("adds a person", "Adds_APerson") == "adds a person"
    assert TestCommandKernels.GetPreferredDisplayName(null, "Adds_APerson") == "Adds_APerson"
    // an EMPTY description is still a description — the runner never treated "" as absent
    assert TestCommandKernels.GetPreferredDisplayName("", "Adds_APerson") == ""
}

// ── the failure text ──────────────────────────────────────────────────────────

test "failure messages join on a newline and blank entries are dropped" {
    joined := TestCommandKernels.JoinFailureMessages(["first", "  ", "second", ""])

    // THE SEPARATOR IS STATED IN FULL, AND THAT IS A CORRECTION. A first draft of this block only
    // checked that both messages survived; the vacuity control then joined on a SPACE and the block
    // still passed. A separator assertion has to be an equality, not a `Contains`.
    assert joined == "first" + Environment.NewLine + "second"
    assert TestCommandKernels.JoinFailureMessages(new string[](0)) == ""
    assert TestCommandKernels.JoinFailureMessages(["only"]) == "only"
    // a single surviving entry gets no separator at all
    assert TestCommandKernels.JoinFailureMessages(["  ", "only", " "]) == "only"
}

// ── the output-mode ordinals and the build configuration ──────────────────────

test "the output-mode predicates answer over GetOutputMode's own ordinals" {
    assert TestCommandKernels.IsJsonOutputMode(TestCommandKernels.GetOutputMode(true))
    assert TestCommandKernels.IsTextOutputMode(TestCommandKernels.GetOutputMode(false))
    // and they are EXCLUSIVE — the runner branches on both, so a mode cannot be neither or both
    assert !TestCommandKernels.IsTextOutputMode(TestCommandKernels.GetOutputMode(true))
    assert !TestCommandKernels.IsJsonOutputMode(TestCommandKernels.GetOutputMode(false))
    assert !TestCommandKernels.IsJsonOutputMode(0)
    assert !TestCommandKernels.IsTextOutputMode(0)
}

test "a test run is built Debug, and the output directory is built from the SAME word" {
    assert TestCommandKernels.GetTestBuildConfiguration() == "Debug"
    // the second copy this slice deleted: the runner passed its own "Debug" to the build while the
    // directory kernel spelled another one into the path
    assert TestCommandKernels.GetTestOutputDirectory("/tmp/demo", "net10.0")
        .Contains(TestCommandKernels.GetTestBuildConfiguration())
    assert TestCommandKernels.GetTestOutputDirectory("/tmp/demo", "net10.0").EndsWith("tests")
}
