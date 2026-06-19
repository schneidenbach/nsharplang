using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct TreeOptionSummary(
    string? ProjectOption,
    string? DepthOption,
    bool Json,
    bool ShowHelp);

internal static class TreeCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    [ThreadStatic]
    private static int[]? t_depthResult;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out TreeOptionSummary summary)
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

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var depthOption))
            {
                summary = default;
                return false;
            }

            summary = new TreeOptionSummary(
                projectOption,
                depthOption,
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

    internal static bool TryGetMaxDepth(string[] args, int defaultDepth, out int maxDepth)
    {
        maxDepth = defaultDepth;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_depthResult ??= new int[1];
        try
        {
            var code = bindings.MaxDepth(args, defaultDepth, result);
            if (code < 0)
                return false;

            maxDepth = result[0];
            return true;
        }
        catch
        {
            maxDepth = defaultDepth;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliTreeOptionSummaryInto>(
                programType,
                "CliTreeOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliTreeMaxDepthInto>(
                programType,
                "CliTreeMaxDepthInto")));

    private delegate int CliTreeOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliTreeMaxDepthInto(
        string[] args,
        int defaultDepth,
        int[] result);

    private sealed record Bindings(
        CliTreeOptionSummaryInto OptionSummary,
        CliTreeMaxDepthInto MaxDepth);

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
