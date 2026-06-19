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
        var options = GetOptionSummary(args);
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

    internal static DaemonOptionSummary GetOptionSummary(string[] args)
        => DaemonCommandKernels.TryGetOptionSummary(args, out var summary)
            ? summary
            : GetOptionSummaryWithCSharp(args);

    private static string GetProjectDir(DaemonOptionSummary options)
        => options.ProjectOption ?? Directory.GetCurrentDirectory();

    // Stage 6 C#-surface-shrink: fallback/oracle only; product daemon option parsing routes through DaemonCommandKernels.
    private static DaemonOptionSummary GetOptionSummaryWithCSharp(string[] args)
    {
        if (args.Length == 0)
            return new DaemonOptionSummary(DaemonSubcommandKind.Unknown, GetProjectOptionWithCSharp(args), ShowHelp: true);

        var subcommandKind = args[0].ToLower() switch
        {
            "start" => DaemonSubcommandKind.Start,
            "stop" => DaemonSubcommandKind.Stop,
            "status" => DaemonSubcommandKind.Status,
            "run" => DaemonSubcommandKind.Run,
            _ => DaemonSubcommandKind.Unknown
        };

        return new DaemonOptionSummary(
            subcommandKind,
            GetProjectOptionWithCSharp(args),
            args[0] is "help" or "--help" or "-h" || ContainsArgWithCSharp(args, "--help") || ContainsArgWithCSharp(args, "-h"));
    }

    private static string? GetProjectOptionWithCSharp(string[] args)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--project")
                return args[i + 1];
        }

        return null;
    }

    private static bool ContainsArgWithCSharp(string[] args, string value)
    {
        for (var i = 0; i < args.Length; i++)
            if (args[i] == value)
                return true;
        return false;
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
