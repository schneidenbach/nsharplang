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
    Background: bool

    constructor(subcommandKind: DaemonSubcommandKind, projectOption: string?, showHelp: bool) {
        SubcommandKind = subcommandKind
        ProjectOption = projectOption
        ShowHelp = showHelp
        Background = false
    }

    constructor(subcommandKind: DaemonSubcommandKind, projectOption: string?, showHelp: bool, background: bool) {
        SubcommandKind = subcommandKind
        ProjectOption = projectOption
        ShowHelp = showHelp
        Background = background
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
        background := false

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

            if arg == "--background" {
                background = true
            }

            if arg == "--project" {
                if projectOption == null && i + 1 < args.Length {
                    projectOption = args[i + 1]
                }
            }

            i = i + 1
        }

        return new DaemonOptionSummary(subcommandKind, projectOption, showHelp, background)
    }

    static func GetHelpText(): string {
        return "N# Workspace Server\n" + "\n" + "Usage: nlc daemon <command> [options]\n" + "\n" + "Commands:\n" + "  start     Start the server for the current workspace\n" + "  stop      Stop the running server\n" + "  status    Show server status (PID, uptime, build identity, requests, memory)\n" + "\n" + "Options:\n" + "  --project <dir>   Directory inside the workspace (default: current directory)\n" + "\n" + "One warm server per workspace (the nearest directory above holding .git, else\n" + "project.yml) keeps the compiler JIT-compiled and its reference metadata loaded.\n" + "\n" + "- `nlc check`, `build`, `test`, `run`, `format`, `lint` and `fix` use it\n" + "  automatically and start it in the background on first use; output, exit\n" + "  codes, working directory and environment are exactly those of an\n" + "  in-process run\n" + "- `--no-daemon` or NLC_NO_DAEMON=1 runs a command in-process; on CI (CI=true)\n" + "  the server is off unless NLC_DAEMON=1\n" + "- A server of a different nlc build is replaced, never reused\n" + "- JSON `nlc query` commands reuse a running server\n" + "- Auto-exits after 30 minutes idle (NLC_DAEMON_IDLE_TIMEOUT), when its working\n" + "  set passes NLC_DAEMON_MAX_MEMORY_MB (default 4096), or when its workspace is deleted\n" + "- Socket: {workspace}/.nlc/daemon.sock (owner-only); log: {workspace}/.nlc/daemon.log\n" + "\n" + "Exit codes:\n" + "  0  Command succeeded\n" + "  1  Command failed (e.g., daemon failed to start or stop)"
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
