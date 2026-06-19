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

    internal static bool TryGetOptionSummary(string[] args, out CompletionOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[2];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0 || resultIndices[0] < 0 || resultIndices[0] > (int)CompletionShellKind.Fish)
                return false;

            summary = new CompletionOptionSummary(
                (CompletionShellKind)resultIndices[0],
                resultIndices[1] != 0);
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
            DogfoodKernelLoader.CreateDelegate<CliCompletionOptionSummaryInto>(
                programType,
                "CliCompletionOptionSummaryInto")));

    private delegate int CliCompletionOptionSummaryInto(string[] args, int[] resultIndices);

    private sealed record Bindings(CliCompletionOptionSummaryInto OptionSummary);
}
