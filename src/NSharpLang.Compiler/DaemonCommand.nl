namespace NSharpLang.Cli.Commands

import System
import System.IO
import NSharpLang.Cli.Daemon

// Handles 'nlc daemon' subcommands: start, stop, status, run.
//
// Every sentence, every exit code and every decision about WHICH subcommand was asked for belongs
// to `DaemonCommandKernels`; this owner only prints, starts a server, and asks the client whether
// one is already there.
static class DaemonCommand {
    static func Execute(args: string[]): int {
        options := DaemonCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            Console.WriteLine(DaemonCommandKernels.GetHelpText())
            return 0
        }

        projectDir := DaemonCommandKernels.ResolveProjectDirectory(options.ProjectOption, Directory.GetCurrentDirectory())
        subcommandKind := options.SubcommandKind

        if subcommandKind == DaemonSubcommandKind.Start {
            return StartCommand(projectDir)
        }

        if subcommandKind == DaemonSubcommandKind.Stop {
            return StopCommand(projectDir)
        }

        if subcommandKind == DaemonSubcommandKind.Status {
            return StatusCommand(projectDir)
        }

        if subcommandKind == DaemonSubcommandKind.Run {
            server := new DaemonServer(projectDir)
            server.Run()
            return 0
        }

        Console.WriteLine(DaemonCommandKernels.GetHelpText())
        return 0
    }

    static func StartCommand(projectDir: string): int {
        if DaemonClient.IsRunning(projectDir) {
            Console.WriteLine(DaemonCommandKernels.GetAlreadyRunningMessage())
            return 0
        }

        Console.WriteLine(DaemonCommandKernels.GetStartingMessage(projectDir))
        if DaemonClient.StartDaemon(projectDir) {
            Console.WriteLine(DaemonCommandKernels.GetStartedMessage())
            return 0
        }

        Console.Error.WriteLine(DaemonCommandKernels.GetStartFailedMessage())
        return 1
    }

    static func StopCommand(projectDir: string): int {
        if !DaemonClient.IsRunning(projectDir) {
            Console.WriteLine(DaemonCommandKernels.GetNoDaemonRunningMessage())
            return 0
        }

        if DaemonClient.StopDaemon(projectDir) {
            Console.WriteLine(DaemonCommandKernels.GetStoppedMessage())
            return 0
        }

        Console.Error.WriteLine(DaemonCommandKernels.GetStopFailedMessage())
        return 1
    }

    static func StatusCommand(projectDir: string): int {
        if !DaemonClient.IsRunning(projectDir) {
            Console.WriteLine(DaemonCommandKernels.GetNoDaemonRunningMessage())
            return 0
        }

        status := DaemonClient.GetStatus(projectDir)
        if status != null {
            Console.WriteLine(status)
        } else {
            Console.WriteLine(DaemonCommandKernels.GetStatusNotRespondingMessage())
        }

        return 0
    }
}
