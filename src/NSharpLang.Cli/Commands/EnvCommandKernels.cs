using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct EnvOptionSummary(
    bool Json,
    bool ShowHelp);

internal enum EnvOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class EnvCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out EnvOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[2];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            summary = new EnvOptionSummary(
                resultIndices[0] != 0,
                resultIndices[1] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetOutputMode(bool json, out EnvOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.OutputMode(json ? 1 : 0);
            if (code is < 1 or > 2)
                return false;

            outputMode = (EnvOutputModeKind)code;
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
            DogfoodKernelLoader.CreateDelegate<CliEnvOptionSummaryInto>(
                programType,
                "CliEnvOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliEnvOutputMode>(
                programType,
                "CliEnvOutputMode")));

    private delegate int CliEnvOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliEnvOutputMode(int json);

    private sealed record Bindings(
        CliEnvOptionSummaryInto OptionSummary,
        CliEnvOutputMode OutputMode);
}
