using System;

namespace NSharpLang.Cli;

internal static class TestCommandKernels
{
    [ThreadStatic]
    private static int[]? t_summaryCounts;

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

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliTestOutcomeSummaryInto>(
                programType,
                "CliTestOutcomeSummaryInto")));

    private delegate int CliTestOutcomeSummaryInto(
        int[] outcomeRanks,
        int count,
        int[] resultCounts);

    private sealed record Bindings(CliTestOutcomeSummaryInto TestOutcomeSummary);
}
