using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct EnvOptionSummary(
    bool Json,
    bool ShowHelp);

internal static class EnvCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static EnvOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[2];
        var code = RequiredBindings.OptionSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# env option parser kernel rejected the arguments.");

        return new EnvOptionSummary(
            resultIndices[0] != 0,
            resultIndices[1] != 0);
    }

    internal static int GetOutputMode(bool json)
        => RequiredBindings.OutputMode(json ? 1 : 0);

    internal static string GetHelpText()
        => RequiredBindings.EnvHelpText();

    internal static string GetTextLine(int kind, string value)
        => RequiredBindings.EnvTextLine(kind, value);

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
