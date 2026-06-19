using System;

namespace NSharpLang.Cli;

internal readonly record struct RunOptionSummary(
    string? BackendOption,
    bool ShowHelp);

internal static class RunCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out RunOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[2];
        try
        {
            var code = bindings.RunOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var backendOption))
            {
                summary = default;
                return false;
            }

            summary = new RunOptionSummary(
                backendOption,
                resultIndices[1] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetSourceOperand(string[] args, out string? operand)
    {
        operand = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.RunFirstOperandIndex(args);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            operand = args[index];
            return true;
        }
        catch
        {
            operand = null;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliRunOptionSummaryInto>(
                programType,
                "CliRunOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliRunFirstOperandIndex>(
                programType,
                "CliRunFirstOperandIndex")));

    private delegate int CliRunOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliRunFirstOperandIndex(string[] args);

    private sealed record Bindings(
        CliRunOptionSummaryInto RunOptionSummary,
        CliRunFirstOperandIndex RunFirstOperandIndex);

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
