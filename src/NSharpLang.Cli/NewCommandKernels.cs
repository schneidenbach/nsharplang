using System;

namespace NSharpLang.Cli;

internal readonly record struct NewArgumentSummary(
    string? FirstPositional,
    string? SecondPositional,
    string? TemplateOption,
    bool Systems,
    bool ShowHelp);

internal static class NewCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out NewArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[5];
        try
        {
            var code = bindings.NewArgumentSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var firstPositional)
                || !TryGetOptionalArg(args, resultIndices[1], out var secondPositional)
                || !TryGetOptionalArg(args, resultIndices[2], out var templateOption))
            {
                summary = default;
                return false;
            }

            summary = new NewArgumentSummary(
                firstPositional,
                secondPositional,
                templateOption,
                resultIndices[3] != 0,
                resultIndices[4] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetProjectNameOperand(
        string[] args,
        string[] optionsWithValues,
        out string? projectName)
    {
        projectName = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.FirstPositionalArgIndex(args, optionsWithValues);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            projectName = args[index];
            return true;
        }
        catch
        {
            projectName = null;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFirstPositionalArgIndex>(
                programType,
                "CliFirstPositionalArgIndex"),
            DogfoodKernelLoader.CreateDelegate<CliNewArgumentSummaryInto>(
                programType,
                "CliNewArgumentSummaryInto")));

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliNewArgumentSummaryInto(
        string[] args,
        int[] resultIndices);

    private sealed record Bindings(
        CliFirstPositionalArgIndex FirstPositionalArgIndex,
        CliNewArgumentSummaryInto NewArgumentSummary);

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
