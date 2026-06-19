using System;

namespace NSharpLang.Cli.Commands;

internal enum DaemonSubcommandKind
{
    Unknown = 0,
    Start = 1,
    Stop = 2,
    Status = 3,
    Run = 4
}

internal readonly record struct DaemonOptionSummary(
    DaemonSubcommandKind SubcommandKind,
    string? ProjectOption,
    bool ShowHelp);

internal static class DaemonCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out DaemonOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[3];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0
                || resultIndices[0] < (int)DaemonSubcommandKind.Unknown
                || resultIndices[0] > (int)DaemonSubcommandKind.Run)
            {
                return false;
            }

            if (!TryGetOptionalArg(args, resultIndices[1], out var projectOption))
            {
                summary = default;
                return false;
            }

            summary = new DaemonOptionSummary(
                (DaemonSubcommandKind)resultIndices[0],
                projectOption,
                resultIndices[2] != 0);
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
            DogfoodKernelLoader.CreateDelegate<CliDaemonOptionSummaryInto>(
                programType,
                "CliDaemonOptionSummaryInto")));

    private delegate int CliDaemonOptionSummaryInto(string[] args, int[] resultIndices);

    private sealed record Bindings(CliDaemonOptionSummaryInto OptionSummary);

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
