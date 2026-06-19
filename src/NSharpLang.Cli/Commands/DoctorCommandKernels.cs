using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct DoctorOptionSummary(
    bool Json,
    bool RequireVscode,
    bool SkipVscode,
    bool ShowHelp);

internal static class DoctorCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out DoctorOptionSummary summary)
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

            summary = new DoctorOptionSummary(
                resultIndices[0] != 0,
                resultIndices[1] != 0,
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
            DogfoodKernelLoader.CreateDelegate<CliDoctorOptionSummaryInto>(
                programType,
                "CliDoctorOptionSummaryInto")));

    private delegate int CliDoctorOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private sealed record Bindings(CliDoctorOptionSummaryInto OptionSummary);
}
