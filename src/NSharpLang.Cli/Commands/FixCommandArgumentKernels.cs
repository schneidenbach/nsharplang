using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct FixArgumentSummary(
    string? ProjectOption,
    string? FileOption,
    string? PositionalProject,
    bool DryRun,
    bool UseText,
    bool IncludeReviewNeeded,
    bool ShowHelp);

internal static class FixCommandArgumentKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static FixArgumentSummary GetArgumentSummary(string[] args)
    {
        var resultIndices = t_resultIndices ??= new int[7];
        var code = RequiredBindings.FixArgumentSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# fix argument summary kernel rejected the arguments.");

        var projectOption = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        var fileOption = resultIndices[1] == -1 ? null : args[resultIndices[1]];
        var positionalProject = resultIndices[2] == -1 ? null : args[resultIndices[2]];
        return new FixArgumentSummary(
            projectOption,
            fileOption,
            positionalProject,
            resultIndices[3] != 0,
            resultIndices[4] != 0,
            resultIndices[5] != 0,
            resultIndices[6] != 0);
    }

    internal static int GetEffectiveOutputMode(bool useText)
        => RequiredBindings.FixEffectiveOutputMode(useText ? 1 : 0);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFixArgumentSummaryInto>(
                programType,
                "CliFixArgumentSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliFixEffectiveOutputMode>(
                programType,
                "CliFixEffectiveOutputMode")));

    private delegate int CliFixArgumentSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliFixEffectiveOutputMode(int useText);

    private sealed record Bindings(
        CliFixArgumentSummaryInto FixArgumentSummary,
        CliFixEffectiveOutputMode FixEffectiveOutputMode);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# fix argument kernels are unavailable.");
}
