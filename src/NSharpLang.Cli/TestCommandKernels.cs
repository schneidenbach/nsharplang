using System;
using System.Globalization;

namespace NSharpLang.Cli;

internal enum TestOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class TestCommandKernels
{
    [ThreadStatic]
    private static int[]? t_summaryCounts;

    [ThreadStatic]
    private static int[]? t_optionResultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TrySummarizeOutcomeRanks(
        int[] outcomeRanks,
        int outcomeCount,
        out (bool Ok, int Passed, int Failed, int Skipped) summary)
    {
        summary = (true, 0, 0, 0);

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (outcomeCount < 0 || outcomeCount > outcomeRanks.Length)
            return false;

        if (outcomeCount == 0)
            return true;

        var summaryCounts = t_summaryCounts ??= new int[4];
        try
        {
            var summarizedCount = bindings.TestOutcomeSummary(
                outcomeRanks,
                outcomeCount,
                summaryCounts);

            var passed = summaryCounts[0];
            var failed = summaryCounts[1];
            var skipped = summaryCounts[2];
            var nonOk = summaryCounts[3];
            if (summarizedCount != outcomeCount ||
                passed < 0 ||
                failed < 0 ||
                skipped < 0 ||
                nonOk < 0 ||
                passed > outcomeCount ||
                failed > outcomeCount ||
                skipped > outcomeCount ||
                nonOk > outcomeCount ||
                passed + failed + skipped > outcomeCount ||
                nonOk < failed)
            {
                summary = (true, 0, 0, 0);
                return false;
            }

            summary = (nonOk == 0, passed, failed, skipped);
            return true;
        }
        catch
        {
            summary = (true, 0, 0, 0);
            return false;
        }
    }

    internal static bool TryGetOptionSummary(string[] args, out TestOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionResultIndices ??= new int[10];
        try
        {
            var code = bindings.TestOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var project)
                || !TryGetOptionalArg(args, resultIndices[1], out var filter)
                || !TryGetOptionalArg(args, resultIndices[2], out var timeout)
                || !TryGetOptionalArg(args, resultIndices[3], out var backend))
            {
                summary = default;
                return false;
            }

            var coverageReport = resultIndices[6] != 0;
            summary = new TestOptionSummary(
                project,
                backend,
                filter,
                timeout,
                resultIndices[4] != 0,
                resultIndices[5] != 0,
                coverageReport,
                resultIndices[7] != 0 || coverageReport,
                resultIndices[8] != 0,
                resultIndices[9] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetOutputMode(bool json, out TestOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.TestOutputMode(json ? 1 : 0);
            if (code is < 1 or > 2)
                return false;

            outputMode = (TestOutputModeKind)code;
            return true;
        }
        catch
        {
            outputMode = default;
            return false;
        }
    }

    internal static bool TryGetDurationMilliseconds(string duration, out int? milliseconds)
    {
        milliseconds = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var value = bindings.TestDurationMilliseconds(duration);
            if (value < 0)
                return true;

            milliseconds = value;
            return true;
        }
        catch
        {
            milliseconds = null;
            return false;
        }
    }

    internal static bool TryMatchesFilter(
        string filter,
        string displayName,
        string alternateDisplayName,
        string fullyQualifiedName,
        out bool matches)
    {
        matches = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.TestFilterMatches(filter, displayName, alternateDisplayName, fullyQualifiedName);
            if (code is not 0 and not 1)
                return false;

            matches = code == 1;
            return true;
        }
        catch
        {
            matches = false;
            return false;
        }
    }

    internal static string GetHelpText()
        => RequiredBindings.TestHelpText();

    internal static string GetMissingProjectFileMessage()
        => RequiredBindings.TestMissingProjectFileMessage();

    internal static string GetCoverageUnsupportedMessage()
        => RequiredBindings.TestCoverageUnsupportedMessage();

    internal static string GetBuildFailedMessage()
        => RequiredBindings.TestBuildFailedMessage();

    internal static string GetInvalidTimeoutMessage(string timeout)
        => RequiredBindings.TestInvalidTimeoutMessage(timeout);

    internal static string GetProjectStartMessage(string projectRoot)
        => RequiredBindings.TestProjectStartMessage(projectRoot);

    internal static string GetNoTestFilesMessage()
        => RequiredBindings.TestNoTestFilesMessage();

    internal static string GetFoundTestFilesMessage(int testFileCount)
    {
        var countText = testFileCount.ToString(CultureInfo.InvariantCulture);
        return RequiredBindings.TestFoundTestFilesMessage(countText, testFileCount);
    }

    internal static string GetSummaryMessage(int passed, int failed, int skipped, int total)
        => RequiredBindings.TestSummaryMessage(
            passed.ToString(CultureInfo.InvariantCulture),
            failed.ToString(CultureInfo.InvariantCulture),
            skipped.ToString(CultureInfo.InvariantCulture),
            total.ToString(CultureInfo.InvariantCulture));

    internal static string GetCompletedElapsedMessage(string elapsedText)
        => RequiredBindings.TestCompletedElapsedMessage(elapsedText);

    internal static string GetFailedElapsedMessage(string elapsedText)
        => RequiredBindings.TestFailedElapsedMessage(elapsedText);

    internal static string GetFailedMessage(string message)
        => RequiredBindings.TestFailedMessage(message);

    internal static string GetVerbosePassedMessage(string displayName, string elapsedMillisecondsText)
        => RequiredBindings.TestVerbosePassedMessage(displayName, elapsedMillisecondsText);

    internal static string GetVerboseSkippedMessage(string displayName, string reason)
        => RequiredBindings.TestVerboseSkippedMessage(displayName, reason);

    internal static string GetVerboseFailedMessage(string displayName, string message)
        => RequiredBindings.TestVerboseFailedMessage(displayName, message);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# test command kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliTestOutcomeSummaryInto>(
                programType,
                "CliTestOutcomeSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliTestOptionSummaryInto>(
                programType,
                "CliTestOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliTestOutputMode>(
                programType,
                "CliTestOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliTestDurationMilliseconds>(
                programType,
                "CliTestDurationMilliseconds"),
            DogfoodKernelLoader.CreateDelegate<CliTestFilterMatches>(
                programType,
                "CliTestFilterMatches"),
            DogfoodKernelLoader.CreateDelegate<CliTestHelpText>(
                programType,
                "CliTestHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliTestMissingProjectFileMessage>(
                programType,
                "CliTestMissingProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestCoverageUnsupportedMessage>(
                programType,
                "CliTestCoverageUnsupportedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestBuildFailedMessage>(
                programType,
                "CliTestBuildFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestInvalidTimeoutMessage>(
                programType,
                "CliTestInvalidTimeoutMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestProjectStartMessage>(
                programType,
                "CliTestProjectStartMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestNoTestFilesMessage>(
                programType,
                "CliTestNoTestFilesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestFoundTestFilesMessage>(
                programType,
                "CliTestFoundTestFilesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestSummaryMessage>(
                programType,
                "CliTestSummaryMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestCompletedElapsedMessage>(
                programType,
                "CliTestCompletedElapsedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestFailedElapsedMessage>(
                programType,
                "CliTestFailedElapsedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestFailedMessage>(
                programType,
                "CliTestFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestVerbosePassedMessage>(
                programType,
                "CliTestVerbosePassedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestVerboseSkippedMessage>(
                programType,
                "CliTestVerboseSkippedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTestVerboseFailedMessage>(
                programType,
                "CliTestVerboseFailedMessage")));

    private delegate int CliTestOutcomeSummaryInto(
        int[] outcomeRanks,
        int count,
        int[] resultCounts);

    private delegate int CliTestOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliTestOutputMode(int json);

    private delegate int CliTestDurationMilliseconds(string duration);

    private delegate int CliTestFilterMatches(
        string filter,
        string displayName,
        string alternateDisplayName,
        string fullyQualifiedName);

    private delegate string CliTestHelpText();
    private delegate string CliTestMissingProjectFileMessage();
    private delegate string CliTestCoverageUnsupportedMessage();
    private delegate string CliTestBuildFailedMessage();
    private delegate string CliTestInvalidTimeoutMessage(string timeout);
    private delegate string CliTestProjectStartMessage(string projectRoot);
    private delegate string CliTestNoTestFilesMessage();
    private delegate string CliTestFoundTestFilesMessage(string countText, int testFileCount);
    private delegate string CliTestSummaryMessage(string passedText, string failedText, string skippedText, string totalText);
    private delegate string CliTestCompletedElapsedMessage(string elapsedText);
    private delegate string CliTestFailedElapsedMessage(string elapsedText);
    private delegate string CliTestFailedMessage(string message);
    private delegate string CliTestVerbosePassedMessage(string displayName, string elapsedMillisecondsText);
    private delegate string CliTestVerboseSkippedMessage(string displayName, string reason);
    private delegate string CliTestVerboseFailedMessage(string displayName, string message);

    private sealed record Bindings(
        CliTestOutcomeSummaryInto TestOutcomeSummary,
        CliTestOptionSummaryInto TestOptionSummary,
        CliTestOutputMode TestOutputMode,
        CliTestDurationMilliseconds TestDurationMilliseconds,
        CliTestFilterMatches TestFilterMatches,
        CliTestHelpText TestHelpText,
        CliTestMissingProjectFileMessage TestMissingProjectFileMessage,
        CliTestCoverageUnsupportedMessage TestCoverageUnsupportedMessage,
        CliTestBuildFailedMessage TestBuildFailedMessage,
        CliTestInvalidTimeoutMessage TestInvalidTimeoutMessage,
        CliTestProjectStartMessage TestProjectStartMessage,
        CliTestNoTestFilesMessage TestNoTestFilesMessage,
        CliTestFoundTestFilesMessage TestFoundTestFilesMessage,
        CliTestSummaryMessage TestSummaryMessage,
        CliTestCompletedElapsedMessage TestCompletedElapsedMessage,
        CliTestFailedElapsedMessage TestFailedElapsedMessage,
        CliTestFailedMessage TestFailedMessage,
        CliTestVerbosePassedMessage TestVerbosePassedMessage,
        CliTestVerboseSkippedMessage TestVerboseSkippedMessage,
        CliTestVerboseFailedMessage TestVerboseFailedMessage);

    private static bool TryGetOptionalArg(string[] args, int index, out string? value)
    {
        value = null;
        if (index == -1)
            return true;

        if (index < 0 || index >= args.Length)
            return false;

        value = args[index];
        return true;
    }
}
