using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct WatchOptionSummary(
    string? ProjectOption,
    string? DebounceMsOption,
    string? MaxRunsOption,
    bool ShowHelp);

internal static class WatchCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out WatchOptionSummary summary)
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
                || !TryGetOptionalArg(args, resultIndices[1], out var debounceMsOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var maxRunsOption))
            {
                summary = default;
                return false;
            }

            summary = new WatchOptionSummary(
                projectOption,
                debounceMsOption,
                maxRunsOption,
                resultIndices[3] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetForwardedArgs(string[] args, out string[] forwardedArgs)
    {
        forwardedArgs = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length <= 1)
            return true;

        var resultIndices = t_resultIndices;
        if (resultIndices == null || resultIndices.Length < args.Length)
        {
            resultIndices = new int[args.Length];
            t_resultIndices = resultIndices;
        }

        try
        {
            var count = bindings.WatchForwardedArgIndices(args, resultIndices);
            if (count < 0 || count > args.Length)
                return false;

            if (count == 0)
                return true;

            forwardedArgs = new string[count];
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = resultIndices[i];
                if (sourceIndex <= 0 || sourceIndex >= args.Length)
                {
                    forwardedArgs = Array.Empty<string>();
                    return false;
                }

                forwardedArgs[i] = args[sourceIndex];
            }

            return true;
        }
        catch
        {
            forwardedArgs = Array.Empty<string>();
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliWatchOptionSummaryInto>(
                programType,
                "CliWatchOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliWatchForwardedArgIndicesInto>(
                programType,
                "CliWatchForwardedArgIndicesInto")));

    private delegate int CliWatchOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliWatchForwardedArgIndicesInto(string[] args, int[] resultIndices);

    private sealed record Bindings(
        CliWatchOptionSummaryInto OptionSummary,
        CliWatchForwardedArgIndicesInto WatchForwardedArgIndices);

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
