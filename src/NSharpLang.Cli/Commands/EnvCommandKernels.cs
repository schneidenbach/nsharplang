using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct EnvOptionSummary(
    bool Json,
    bool ShowHelp);

internal enum EnvOutputModeKind
{
    Json = 1,
    Text = 2
}

internal enum EnvTextLineKind
{
    NlcVersion = 1,
    DotnetVersion = 2,
    Runtime = 3,
    Os = 4,
    Arch = 5,
    NugetCache = 6,
    NsharpBin = 7,
    NsharpPackages = 8,
    Project = 9,
    Target = 10,
    OutputType = 11,
    Sdk = 12
}

internal static class EnvCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out EnvOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[2];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            summary = new EnvOptionSummary(
                resultIndices[0] != 0,
                resultIndices[1] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static EnvOutputModeKind GetOutputMode(bool json)
    {
        var code = RequiredBindings.OutputMode(json ? 1 : 0);
        if (code is < 1 or > 2)
            throw new InvalidOperationException("N# env output-mode kernel rejected the options.");

        return (EnvOutputModeKind)code;
    }

    internal static string GetHelpText()
        => RequiredBindings.EnvHelpText();

    internal static string GetTextLine(EnvTextLineKind kind, string value)
        => RequiredBindings.EnvTextLine((int)kind, value);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# env command kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliEnvOptionSummaryInto>(
                programType,
                "CliEnvOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliEnvOutputMode>(
                programType,
                "CliEnvOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliEnvHelpText>(
                programType,
                "CliEnvHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliEnvTextLine>(
                programType,
                "CliEnvTextLine")));

    private delegate int CliEnvOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliEnvOutputMode(int json);

    private delegate string CliEnvHelpText();

    private delegate string CliEnvTextLine(
        int lineKind,
        string value);

    private sealed record Bindings(
        CliEnvOptionSummaryInto OptionSummary,
        CliEnvOutputMode OutputMode,
        CliEnvHelpText EnvHelpText,
        CliEnvTextLine EnvTextLine);
}
