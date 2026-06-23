using System;
using System.IO;
using NSharpLang.Cli.Daemon;

namespace NSharpLang.Cli.Commands;

/// <summary>
/// Handles 'nlc daemon' subcommands: start, stop, status, run.
/// </summary>
public static class DaemonCommand
{
    public static int Execute(string[] args)
    {
        var options = DaemonCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowDaemonHelp();

        var projectDir = GetProjectDir(options);
        return options.SubcommandKind switch
        {
            DaemonSubcommandKind.Start => StartCommand(projectDir),
            DaemonSubcommandKind.Stop => StopCommand(projectDir),
            DaemonSubcommandKind.Status => StatusCommand(projectDir),
            DaemonSubcommandKind.Run => RunCommand(projectDir), // Internal: runs the daemon in-process
            _ => ShowDaemonHelp()
        };
    }

    private static int StartCommand(string projectDir)
    {
        if (DaemonClient.IsRunning(projectDir))
        {
            Console.WriteLine(DaemonCommandKernels.GetAlreadyRunningMessage());
            return 0;
        }

        Console.WriteLine(DaemonCommandKernels.GetStartingMessage(projectDir));
        if (DaemonClient.StartDaemon(projectDir))
        {
            Console.WriteLine(DaemonCommandKernels.GetStartedMessage());
            return 0;
        }

        Console.Error.WriteLine(DaemonCommandKernels.GetStartFailedMessage());
        return 1;
    }

    private static int StopCommand(string projectDir)
    {
        if (!DaemonClient.IsRunning(projectDir))
        {
            Console.WriteLine(DaemonCommandKernels.GetNoDaemonRunningMessage());
            return 0;
        }

        if (DaemonClient.StopDaemon(projectDir))
        {
            Console.WriteLine(DaemonCommandKernels.GetStoppedMessage());
            return 0;
        }

        Console.Error.WriteLine(DaemonCommandKernels.GetStopFailedMessage());
        return 1;
    }

    private static int StatusCommand(string projectDir)
    {
        if (!DaemonClient.IsRunning(projectDir))
        {
            Console.WriteLine(DaemonCommandKernels.GetNoDaemonRunningMessage());
            return 0;
        }

        var status = DaemonClient.GetStatus(projectDir);
        if (status != null)
        {
            Console.WriteLine(status);
        }
        else
        {
            Console.WriteLine(DaemonCommandKernels.GetStatusNotRespondingMessage());
        }
        return 0;
    }

    /// <summary>
    /// Run the daemon server in-process (called by StartDaemon as a background process).
    /// </summary>
    private static int RunCommand(string projectDir)
    {
        var server = new DaemonServer(projectDir);
        server.Run();
        return 0;
    }

    private static string GetProjectDir(DaemonOptionSummary options)
        => options.ProjectOption ?? Directory.GetCurrentDirectory();

    private static int ShowDaemonHelp()
    {
        Console.WriteLine(DaemonCommandKernels.GetHelpText());
        return 0;
    }
}
