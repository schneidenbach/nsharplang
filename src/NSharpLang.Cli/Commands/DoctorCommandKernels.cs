using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct DoctorOptionSummary(
    bool Json,
    bool RequireVscode,
    bool SkipVscode,
    bool ShowHelp);

internal enum DoctorOutputModeKind
{
    Json = 1,
    Text = 2
}

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

    internal static bool TryGetOutputMode(bool json, out DoctorOutputModeKind outputMode)
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

            outputMode = (DoctorOutputModeKind)code;
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
            DogfoodKernelLoader.CreateDelegate<CliDoctorOptionSummaryInto>(
                programType,
                "CliDoctorOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorOutputMode>(
                programType,
                "CliDoctorOutputMode")));

    private delegate int CliDoctorOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliDoctorOutputMode(int json);

    private sealed record Bindings(
        CliDoctorOptionSummaryInto OptionSummary,
        CliDoctorOutputMode OutputMode);
}
