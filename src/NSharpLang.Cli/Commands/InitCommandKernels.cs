using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct InitOptionSummary(
    string? NameOption,
    string? TypeOption,
    bool Force,
    bool ShowHelp);

internal static class InitCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out InitOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[4];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var nameOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var typeOption))
            {
                summary = default;
                return false;
            }

            summary = new InitOptionSummary(
                nameOption,
                typeOption,
                resultIndices[2] != 0,
                resultIndices[3] != 0);
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
            DogfoodKernelLoader.CreateDelegate<CliInitOptionSummaryInto>(
                programType,
                "CliInitOptionSummaryInto")));

    private delegate int CliInitOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private sealed record Bindings(CliInitOptionSummaryInto OptionSummary);

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
