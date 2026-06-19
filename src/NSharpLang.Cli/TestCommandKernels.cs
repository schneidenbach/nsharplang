using System;

namespace NSharpLang.Cli;

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

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliTestOutcomeSummaryInto>(
                programType,
                "CliTestOutcomeSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliTestOptionSummaryInto>(
                programType,
                "CliTestOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliTestDurationMilliseconds>(
                programType,
                "CliTestDurationMilliseconds"),
            DogfoodKernelLoader.CreateDelegate<CliTestFilterMatches>(
                programType,
                "CliTestFilterMatches")));

    private delegate int CliTestOutcomeSummaryInto(
        int[] outcomeRanks,
        int count,
        int[] resultCounts);

    private delegate int CliTestOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliTestDurationMilliseconds(string duration);

    private delegate int CliTestFilterMatches(
        string filter,
        string displayName,
        string alternateDisplayName,
        string fullyQualifiedName);

    private sealed record Bindings(
        CliTestOutcomeSummaryInto TestOutcomeSummary,
        CliTestOptionSummaryInto TestOptionSummary,
        CliTestDurationMilliseconds TestDurationMilliseconds,
        CliTestFilterMatches TestFilterMatches);

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
