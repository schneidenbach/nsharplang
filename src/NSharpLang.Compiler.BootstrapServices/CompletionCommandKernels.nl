namespace NSharpLang.Cli.Commands

import System

enum CompletionShellKind {
    Unknown = 0,
    Bash = 1,
    Zsh = 2,
    Fish = 3
}

class CompletionOptionSummary {
    ShellKind: CompletionShellKind
    ShowHelp: bool

    constructor(shellKind: CompletionShellKind, showHelp: bool) {
        ShellKind = shellKind
        ShowHelp = showHelp
    }
}

class CompletionCommandKernels {
    static func GetOptionSummary(args: string[]): CompletionOptionSummary {
        shellKind := CompletionShellKind.Unknown
        showHelp := false

        if args.Length == 0 {
            return new CompletionOptionSummary(shellKind, true)
        }

        firstArg := args[0]
        if firstArg == "help" {
            showHelp = true
        }

        if String.Compare(firstArg, "bash", StringComparison.OrdinalIgnoreCase) == 0 {
            shellKind = CompletionShellKind.Bash
        }

        if String.Compare(firstArg, "zsh", StringComparison.OrdinalIgnoreCase) == 0 {
            shellKind = CompletionShellKind.Zsh
        }

        if String.Compare(firstArg, "fish", StringComparison.OrdinalIgnoreCase) == 0 {
            shellKind = CompletionShellKind.Fish
        }

        i := 0
        while i < args.Length {
            arg := args[i]
            if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new CompletionOptionSummary(shellKind, showHelp)
    }

    static func GetHelpText(): string {
        return "N# Shell Completion\n" + "\n" + "Usage: nlc completion <bash|zsh|fish>\n" + "\n" + "Generate shell completion scripts from the current `nlc` command tree.\n" + "\n" + "Examples:\n" + "  nlc completion bash > /etc/bash_completion.d/nlc\n" + "  nlc completion zsh > ~/.zsh/completions/_nlc\n" + "  nlc completion fish > ~/.config/fish/completions/nlc.fish\n" + "\n" + "Exit codes:\n" + "  0  Script generated successfully\n" + "  1  Invalid shell name"
    }

    static func GetUnknownShellMessage(shell: string): string {
        return "Unknown shell '" + shell + "'. Expected bash, zsh, or fish."
    }
}
