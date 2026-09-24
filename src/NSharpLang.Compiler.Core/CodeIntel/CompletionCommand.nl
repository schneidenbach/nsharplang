namespace NSharpLang.Cli.Commands

import System

class CompletionCommand {
    static func Execute(args: string[]): int {
        options := CompletionCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            print CompletionCommandKernels.GetHelpText()
            return 0
        }

        script: string? = null
        if options.ShellKind == CompletionShellKind.Bash {
            script = GetBashScript()
        } else if options.ShellKind == CompletionShellKind.Zsh {
            script = GetZshScript()
        } else if options.ShellKind == CompletionShellKind.Fish {
            script = GetFishScript()
        }

        if script != null {
            scriptText := script ?? ""
            print scriptText
            return 0
        }

        shellForError := ""
        if args.Length > 0 {
            shellForError = args[0].ToLowerInvariant()
        }

        Console.Error.WriteLine(CompletionCommandKernels.GetUnknownShellMessage(shellForError))
        return 1
    }

    static func GetTopLevelCommandNames(): string {
        return "build run new init test format lint clean watch doc completion check fix query daemon add tidy remove update publish tree audit env doctor restore pack help"
    }

    static func GetQueryCommandNames(): string {
        return "batch symbols outline ast diagnostics type inspect definition def references refs completions doc hover call-graph implementors perf trusted help"
    }

    static func GetBashScript(): string {
        topLevelCommandNames := GetTopLevelCommandNames()
        queryCommandNames := GetQueryCommandNames()

        return "_nlc_commands=\"" + topLevelCommandNames + "\"\n" + "_nlc_query_commands=\"" + queryCommandNames + "\"\n" + "_nlc_daemon_commands=\"start stop status run help\"\n" + "_nlc_watch_commands=\"check build test lint format\"\n" + "\n" + "_nlc()\n" + "{\n" + "    local cur prev words cword\n" + "    _init_completion || return\n" + "\n" + "    case \"${words[1]}\" in\n" + "        query)\n" + "            COMPREPLY=( $(compgen -W \"${_nlc_query_commands}\" -- \"$cur\") )\n" + "            return\n" + "            ;;\n" + "        daemon)\n" + "            COMPREPLY=( $(compgen -W \"${_nlc_daemon_commands}\" -- \"$cur\") )\n" + "            return\n" + "            ;;\n" + "        watch)\n" + "            COMPREPLY=( $(compgen -W \"${_nlc_watch_commands}\" -- \"$cur\") )\n" + "            return\n" + "            ;;\n" + "    esac\n" + "\n" + "    COMPREPLY=( $(compgen -W \"${_nlc_commands}\" -- \"$cur\") )\n" + "}\n" + "\n" + "complete -F _nlc nlc"
    }

    static func GetZshScript(): string {
        topLevelCommandNames := GetTopLevelCommandNames()
        queryCommandNames := GetQueryCommandNames()

        return "#compdef nlc\n" + "\n" + "local -a commands\n" + "commands=(" + topLevelCommandNames + ")\n" + "\n" + "case $words[2] in\n" + "  query)\n" + "    _values 'query command' " + queryCommandNames + "\n" + "    ;;\n" + "  daemon)\n" + "    _values 'daemon command' start stop status run help\n" + "    ;;\n" + "  watch)\n" + "    _values 'watch command' check build test lint format\n" + "    ;;\n" + "  *)\n" + "    _values 'nlc command' $commands\n" + "    ;;\n" + "esac"
    }

    static func GetFishScript(): string {
        topLevelCommandNames := GetTopLevelCommandNames()
        queryCommandNames := GetQueryCommandNames()

        return "complete -c nlc -f\n" + "complete -c nlc -n '__fish_use_subcommand' -a '" + topLevelCommandNames + "'\n" + "complete -c nlc -n '__fish_seen_subcommand_from query' -a '" + queryCommandNames + "'\n" + "complete -c nlc -n '__fish_seen_subcommand_from daemon' -a 'start stop status run help'\n" + "complete -c nlc -n '__fish_seen_subcommand_from watch' -a 'check build test lint format'"
    }
}
