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

internal enum FixOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class FixCommandArgumentKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out FixArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[7];
        try
        {
            var code = bindings.FixArgumentSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var fileOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var positionalProject))
            {
                summary = default;
                return false;
            }

            summary = new FixArgumentSummary(
                projectOption,
                fileOption,
                positionalProject,
                resultIndices[3] != 0,
                resultIndices[4] != 0,
                resultIndices[5] != 0,
                resultIndices[6] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static FixOutputModeKind GetEffectiveOutputMode(bool useText)
    {
        var result = RequiredBindings.FixEffectiveOutputMode(useText ? 1 : 0);
        if (result is < 1 or > 2)
            throw new InvalidOperationException("N# fix output mode kernel rejected the value.");

        return (FixOutputModeKind)result;
    }

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
