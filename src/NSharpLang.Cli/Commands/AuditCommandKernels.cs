using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct AuditOptionSummary(
    string? ProjectOption,
    bool Json,
    bool ShowHelp);

internal enum AuditOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class AuditCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out AuditOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[3];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption))
            {
                summary = default;
                return false;
            }

            summary = new AuditOptionSummary(
                projectOption,
                resultIndices[1] != 0,
                resultIndices[2] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetOutputMode(bool json, out AuditOutputModeKind outputMode)
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

            outputMode = (AuditOutputModeKind)code;
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
            DogfoodKernelLoader.CreateDelegate<CliAuditOptionSummaryInto>(
                programType,
                "CliAuditOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliAuditOutputMode>(
                programType,
                "CliAuditOutputMode")));

    private delegate int CliAuditOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliAuditOutputMode(int json);

    private sealed record Bindings(
        CliAuditOptionSummaryInto OptionSummary,
        CliAuditOutputMode OutputMode);

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
