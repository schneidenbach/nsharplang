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

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliCheckArgumentSummaryInto>(
                programType,
                "CliCheckArgumentSummaryInto")));

    private delegate int CliCheckArgumentSummaryInto(string[] args, int[] resultIndices);

    private sealed record Bindings(CliCheckArgumentSummaryInto CheckArgumentSummary);

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
