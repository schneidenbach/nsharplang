using System;
using System.Linq;

namespace NSharpLang.Cli.Commands;

public static class CompletionCommand
{
    private static readonly string[] TopLevelCommands =
    {
        "build",
        "run",
        "new",
        "init",
        "test",
        "format",
        "lint",
        "bench",
        "clean",
        "watch",
        "doc",
        "completion",
        "check",
        "fix",
        "query",
        "daemon",
        "add",
        "tidy",
        "remove",
        "update",
        "publish",
        "export",
        "convert",
        "idiom",
        "tree",
        "audit",
        "env",
        "restore",
        "help"
    };

    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || args.Length == 0 || args[0] == "help")
            return ShowHelp();

        var shell = args[0].ToLowerInvariant();

        return shell switch
        {
            "bash" => WriteScript(BashScript),
            "zsh" => WriteScript(ZshScript),
            "fish" => WriteScript(FishScript),
            _ => Error($"Unknown shell '{shell}'. Expected bash, zsh, or fish.")
        };
    }

    private static int WriteScript(string script)
    {
        Console.Write(script);
        return 0;
    }

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# Shell Completion

Usage: nlc completion <bash|zsh|fish>

Generate shell completion scripts from the current `nlc` command tree.

Examples:
  nlc completion bash > /etc/bash_completion.d/nlc
  nlc completion zsh > ~/.zsh/completions/_nlc
  nlc completion fish > ~/.config/fish/completions/nlc.fish

Exit codes:
  0  Script generated successfully
  1  Invalid shell name");

        return 0;
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }

    private static readonly string BashScript = $$"""
_nlc_commands="{{string.Join(" ", TopLevelCommands)}}"
_nlc_query_commands="batch symbols outline diagnostics type inspect definition def references refs completions doc help"
_nlc_daemon_commands="start stop status run help"
_nlc_watch_commands="check build test lint format"
_nlc_export_commands="csharp help"

_nlc()
{
    local cur prev words cword
    _init_completion || return

    case "${words[1]}" in
        query)
            COMPREPLY=( $(compgen -W "${_nlc_query_commands}" -- "$cur") )
            return
            ;;
        daemon)
            COMPREPLY=( $(compgen -W "${_nlc_daemon_commands}" -- "$cur") )
            return
            ;;
        export)
            COMPREPLY=( $(compgen -W "${_nlc_export_commands}" -- "$cur") )
            return
            ;;
        watch)
            COMPREPLY=( $(compgen -W "${_nlc_watch_commands}" -- "$cur") )
            return
            ;;
    esac

    COMPREPLY=( $(compgen -W "${_nlc_commands}" -- "$cur") )
}

complete -F _nlc nlc
""";

    private static readonly string ZshScript = $$"""
#compdef nlc

local -a commands
commands=({{string.Join(" ", TopLevelCommands)}})

case $words[2] in
  query)
    _values 'query command' batch symbols outline diagnostics type inspect definition def references refs completions doc help
    ;;
  daemon)
    _values 'daemon command' start stop status run help
    ;;
  export)
    _values 'export command' csharp help
    ;;
  watch)
    _values 'watch command' check build test lint format
    ;;
  *)
    _values 'nlc command' $commands
    ;;
esac
""";

    private static readonly string FishScript = $$"""
complete -c nlc -f
complete -c nlc -n '__fish_use_subcommand' -a '{{string.Join(" ", TopLevelCommands)}}'
complete -c nlc -n '__fish_seen_subcommand_from query' -a 'batch symbols outline diagnostics type inspect definition def references refs completions doc help'
complete -c nlc -n '__fish_seen_subcommand_from daemon' -a 'start stop status run help'
complete -c nlc -n '__fish_seen_subcommand_from export' -a 'csharp help'
complete -c nlc -n '__fish_seen_subcommand_from watch' -a 'check build test lint format'
""";
}
