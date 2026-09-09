namespace NSharpLang.Cli.Commands

import System
import System.IO

enum DaemonSubcommandKind {
    Unknown = 0,
    Start = 1,
    Stop = 2,
    Status = 3,
    Run = 4
}

class DaemonOptionSummary {
    SubcommandKind: DaemonSubcommandKind
    ProjectOption: string?
    ShowHelp: bool

    constructor(subcommandKind: DaemonSubcommandKind, projectOption: string?, showHelp: bool) {
        SubcommandKind = subcommandKind
        ProjectOption = projectOption
        ShowHelp = showHelp
    }
}

class DaemonCommandKernels {
    static func ResolveProjectDirectory(projectOption: string?, currentDirectory: string): string {
        if projectOption == null {
            return currentDirectory
        }

        return Path.GetFullPath(projectOption)
    }

    static func GetOptionSummary(args: string[]): DaemonOptionSummary {
        subcommandKind := DaemonSubcommandKind.Unknown
        projectOption: string? = null
        showHelp := false

        if args.Length == 0 {
            return new DaemonOptionSummary(subcommandKind, projectOption, true)
        }

        firstArg := args[0]
        if String.Compare(firstArg, "start", StringComparison.OrdinalIgnoreCase) == 0 {
            subcommandKind = DaemonSubcommandKind.Start
        } else if String.Compare(firstArg, "stop", StringComparison.OrdinalIgnoreCase) == 0 {
            subcommandKind = DaemonSubcommandKind.Stop
        } else if String.Compare(firstArg, "status", StringComparison.OrdinalIgnoreCase) == 0 {
            subcommandKind = DaemonSubcommandKind.Status
        } else if String.Compare(firstArg, "run", StringComparison.OrdinalIgnoreCase) == 0 {
            subcommandKind = DaemonSubcommandKind.Run
        } else if firstArg == "help" || firstArg == "--help" || firstArg == "-h" {
            showHelp = true
        }

        i := 0
        while i < args.Length {
            arg := args[i]
            if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            if arg == "--project" {
                if projectOption == null && i + 1 < args.Length {
                    projectOption = args[i + 1]
                }
            }

            i = i + 1
        }

        return new DaemonOptionSummary(subcommandKind, projectOption, showHelp)
    }

    static func GetHelpText(): string {
        return "N# Analysis Daemon\n" + "\n" + "Usage: nlc daemon <command> [options]\n" + "\n" + "Commands:\n" + "  start     Start the daemon for the current project\n" + "  stop      Stop the running daemon\n" + "  status    Show daemon status (PID, uptime, cached files)\n" + "\n" + "Options:\n" + "  --project <dir>   Project root directory (default: current directory)\n" + "\n" + "The daemon caches project analysis and can serve JSON `nlc query` requests\n" + "via Unix domain socket for faster repeated response times.\n" + "\n" + "- `nlc query` reuses the daemon only when one is already running\n" + "- Auto-exits after 30 minutes of inactivity\n" + "- Watches .nl, project.yml, and .editorconfig for changes and invalidates cache\n" + "- Socket: {projectRoot}/.nlc/daemon.sock\n" + "\n" + "Exit codes:\n" + "  0  Command succeeded\n" + "  1  Command failed (e.g., daemon failed to start or stop)"
    }

    static func GetAlreadyRunningMessage(): string {
        return "Daemon is already running."
    }

    static func GetStartingMessage(projectDir: string): string {
        return "Starting daemon for " + projectDir + "..."
    }

    static func GetStartedMessage(): string {
        return "Daemon started."
    }

    static func GetStartFailedMessage(): string {
        return "Failed to start daemon."
    }

    static func GetNoDaemonRunningMessage(): string {
        return "No daemon running."
    }

    static func GetStoppedMessage(): string {
        return "Daemon stopped."
    }

    static func GetStopFailedMessage(): string {
        return "Failed to stop daemon."
    }

    static func GetStatusNotRespondingMessage(): string {
        return "Daemon is running but not responding to status queries."
    }
}
