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
        if (args.Length == 0)
        {
            return ShowDaemonHelp();
        }

        var subcommand = args[0].ToLower();
        var projectDir = GetProjectDir(args);

        return subcommand switch
        {
            "start" => StartCommand(projectDir),
            "stop" => StopCommand(projectDir),
            "status" => StatusCommand(projectDir),
            "run" => RunCommand(projectDir), // Internal: runs the daemon in-process
            "help" or "--help" or "-h" => ShowDaemonHelp(),
            _ => ShowDaemonHelp()
        };
    }

    private static int StartCommand(string projectDir)
    {
        if (DaemonClient.IsRunning(projectDir))
        {
            Console.WriteLine("Daemon is already running.");
            return 0;
        }

        Console.WriteLine($"Starting daemon for {projectDir}...");
        if (DaemonClient.StartDaemon(projectDir))
        {
            Console.WriteLine("Daemon started.");
            return 0;
        }

        Console.Error.WriteLine("Failed to start daemon.");
        return 1;
    }

    private static int StopCommand(string projectDir)
    {
        if (!DaemonClient.IsRunning(projectDir))
        {
            Console.WriteLine("No daemon running.");
            return 0;
        }

        if (DaemonClient.StopDaemon(projectDir))
        {
            Console.WriteLine("Daemon stopped.");
            return 0;
        }

        Console.Error.WriteLine("Failed to stop daemon.");
        return 1;
    }

    private static int StatusCommand(string projectDir)
    {
        if (!DaemonClient.IsRunning(projectDir))
        {
            Console.WriteLine("No daemon running.");
            return 0;
        }

        var status = DaemonClient.GetStatus(projectDir);
        if (status != null)
        {
            Console.WriteLine(status);
        }
        else
        {
            Console.WriteLine("Daemon is running but not responding to status queries.");
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

    private static string GetProjectDir(string[] args)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--project")
                return args[i + 1];
        }
        return Directory.GetCurrentDirectory();
    }

    private static int ShowDaemonHelp()
    {
        Console.WriteLine(@"N# Analysis Daemon

Usage: nlc daemon <command> [options]

Commands:
  start     Start the daemon for the current project
  stop      Stop the running daemon
  status    Show daemon status (PID, uptime, cached files)

Options:
  --project <dir>   Project root directory (default: current directory)

The daemon caches project analysis and can serve JSON `nlc query` requests
via Unix domain socket for faster repeated response times.

- `nlc query` reuses the daemon only when one is already running
- Auto-exits after 30 minutes of inactivity
- Watches .nl, project.yml, and .editorconfig for changes and invalidates cache
- Socket: {projectRoot}/.nlc/daemon.sock

Exit codes:
  0  Command succeeded
  1  Command failed (e.g., daemon failed to start or stop)");


        return 0;
    }
}
