using System;
using NSharpLang.Cli;

namespace NSharpLang.Cli.Commands;

public static class CompletionCommand
{
    private static readonly string TopLevelCommandNames = CommandRegistry.JoinCommandNames(CommandRegistry.TopLevelCommands);
    private static readonly string QueryCommandNames = CommandRegistry.JoinCommandNames(CommandRegistry.QueryCommands);

    public static int Execute(string[] args)
    {
        var options = CompletionCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var shellForError = args.Length == 0 ? string.Empty : args[0].ToLowerInvariant();
        return options.ShellKind switch
        {
            CompletionShellKind.Bash => WriteScript(BashScript),
            CompletionShellKind.Zsh => WriteScript(ZshScript),
            CompletionShellKind.Fish => WriteScript(FishScript),
            _ => Error(CompletionCommandKernels.GetUnknownShellMessage(shellForError))
        };
    }

    private static int WriteScript(string script)
    {
        Console.Write(script);
        return 0;
    }

    private static int ShowHelp()
    {
        Console.WriteLine(CompletionCommandKernels.GetHelpText());
        return 0;
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }

    private static readonly string BashScript = $$"""
_nlc_commands="{{TopLevelCommandNames}}"
_nlc_query_commands="{{QueryCommandNames}}"
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
commands=({{TopLevelCommandNames}})

case $words[2] in
  query)
    _values 'query command' {{QueryCommandNames}}
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
complete -c nlc -n '__fish_use_subcommand' -a '{{TopLevelCommandNames}}'
complete -c nlc -n '__fish_seen_subcommand_from query' -a '{{QueryCommandNames}}'
complete -c nlc -n '__fish_seen_subcommand_from daemon' -a 'start stop status run help'
complete -c nlc -n '__fish_seen_subcommand_from export' -a 'csharp help'
complete -c nlc -n '__fish_seen_subcommand_from watch' -a 'check build test lint format'
""";
}
