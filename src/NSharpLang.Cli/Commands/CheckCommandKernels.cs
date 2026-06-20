using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct CheckArgumentSummary(
    string? ProjectOption,
    string? BackendOption,
    string? PositionalProject,
    bool UseText,
    bool Aot,
    bool SystemsReport,
    bool ShowHelp);

internal enum CheckOutputModeKind
{
    InvalidSystemsReportText = -1,
    Json = 1,
    Text = 2,
    SystemsReportJson = 3
}

internal static class CheckCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out CheckArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[7];
        try
        {
            var code = bindings.CheckArgumentSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var backendOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var positionalProject))
            {
                summary = default;
                return false;
            }

            summary = new CheckArgumentSummary(
                projectOption,
                backendOption,
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

    internal static bool TryGetEffectiveOutputMode(
        bool useText,
        bool systemsReport,
        out CheckOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.CheckEffectiveOutputMode(useText ? 1 : 0, systemsReport ? 1 : 0);
            if (result != -1 && result != 1 && result != 2 && result != 3)
                return false;

            outputMode = (CheckOutputModeKind)result;
            return true;
        }
        catch
        {
            outputMode = default;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliCheckArgumentSummaryInto>(
                programType,
                "CliCheckArgumentSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliCheckEffectiveOutputMode>(
                programType,
                "CliCheckEffectiveOutputMode")));

    private delegate int CliCheckArgumentSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliCheckEffectiveOutputMode(int useText, int systemsReport);

    private sealed record Bindings(
        CliCheckArgumentSummaryInto CheckArgumentSummary,
        CliCheckEffectiveOutputMode CheckEffectiveOutputMode);

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
