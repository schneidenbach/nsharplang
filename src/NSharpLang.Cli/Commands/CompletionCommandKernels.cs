using System;

namespace NSharpLang.Cli.Commands;

internal enum CompletionShellKind
{
    Unknown = 0,
    Bash = 1,
    Zsh = 2,
    Fish = 3
}

internal readonly record struct CompletionOptionSummary(
    CompletionShellKind ShellKind,
    bool ShowHelp);

internal static class CompletionCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static CompletionOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[2];
        var code = RequiredBindings.OptionSummary(args, resultIndices);
        if (code != 0 || resultIndices[0] < 0 || resultIndices[0] > (int)CompletionShellKind.Fish)
            throw new InvalidOperationException("N# completion option parser kernel rejected the arguments.");

        return new CompletionOptionSummary(
            (CompletionShellKind)resultIndices[0],
            resultIndices[1] != 0);
    }

    internal static string GetHelpText()
        => RequiredBindings.CompletionHelpText();

    internal static string GetUnknownShellMessage(string shell)
        => RequiredBindings.CompletionUnknownShellMessage(shell);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# completion command kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliCompletionOptionSummaryInto>(
                programType,
                "CliCompletionOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliCompletionHelpText>(
                programType,
                "CliCompletionHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliCompletionUnknownShellMessage>(
                programType,
                "CliCompletionUnknownShellMessage")));

    private delegate int CliCompletionOptionSummaryInto(string[] args, int[] resultIndices);
    private delegate string CliCompletionHelpText();
    private delegate string CliCompletionUnknownShellMessage(string shell);

    private sealed record Bindings(
        CliCompletionOptionSummaryInto OptionSummary,
        CliCompletionHelpText CompletionHelpText,
        CliCompletionUnknownShellMessage CompletionUnknownShellMessage);
}
