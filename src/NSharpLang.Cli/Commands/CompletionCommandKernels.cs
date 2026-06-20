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

    internal static string GetHelpText()
    {
        if (TryGetMessage(bindings => bindings.CompletionHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetUnknownShellMessage(string shell)
    {
        if (TryGetMessage(bindings => bindings.CompletionUnknownShellMessage(shell), out var message))
            return message;

        return GetUnknownShellMessageWithCSharp(shell);
    }

    private static bool TryGetMessage(Func<Bindings, string> getMessage, out string message)
    {
        message = string.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            message = getMessage(bindings);
            return !string.IsNullOrEmpty(message);
        }
        catch
        {
            message = string.Empty;
            return false;
        }
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product completion command messages route through CliCompletion* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Shell Completion\n"
           + "\n"
           + "Usage: nlc completion <bash|zsh|fish>\n"
           + "\n"
           + "Generate shell completion scripts from the current `nlc` command tree.\n"
           + "\n"
           + "Examples:\n"
           + "  nlc completion bash > /etc/bash_completion.d/nlc\n"
           + "  nlc completion zsh > ~/.zsh/completions/_nlc\n"
           + "  nlc completion fish > ~/.config/fish/completions/nlc.fish\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Script generated successfully\n"
           + "  1  Invalid shell name";

    private static string GetUnknownShellMessageWithCSharp(string shell)
        => $"Unknown shell '{shell}'. Expected bash, zsh, or fish.";

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
