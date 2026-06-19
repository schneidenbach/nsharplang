using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct EnvOptionSummary(
    bool Json,
    bool ShowHelp);

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

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliEnvOptionSummaryInto>(
                programType,
                "CliEnvOptionSummaryInto")));

    private delegate int CliEnvOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private sealed record Bindings(CliEnvOptionSummaryInto OptionSummary);
}
