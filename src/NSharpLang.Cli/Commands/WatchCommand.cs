using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace NSharpLang.Cli.Commands;

public static class WatchCommand
{
    private static readonly string[] SupportedCommands = { "check", "build", "test", "lint", "format" };
    private static readonly string[] WatchOptionsWithValues = { "--project", "--debounce-ms", "--max-runs" };

    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || args.Length == 0 || args[0] == "help")
            return ShowHelp();

        var watchedCommand = args[0].ToLowerInvariant();
        if (!SupportedCommands.Contains(watchedCommand, StringComparer.Ordinal))
            return Error($"Unsupported watch target '{watchedCommand}'. Expected check, build, test, lint, or format.");

        var forwardedArgs = GetForwardedArgs(args.Skip(1).ToArray());
        var projectRoot = GetOption(args, "--project") ?? Directory.GetCurrentDirectory();
        projectRoot = Path.GetFullPath(projectRoot);

        if (!Directory.Exists(projectRoot))
            return Error($"Project directory not found: {projectRoot}");

        var debounceMs = ParsePositiveInt(GetOption(args, "--debounce-ms"), 250, "--debounce-ms");
        if (debounceMs == null)
            return 1;

        var maxRuns = ParsePositiveInt(GetOption(args, "--max-runs"), null, "--max-runs");
        if (GetOption(args, "--max-runs") != null && maxRuns == null)
            return 1;

        var wakeSignal = new AutoResetEvent(false);
        var cancelled = false;
        var pendingChange = false;
        var lastChangeUtc = DateTime.MinValue;
        var sync = new object();
        var lastExitCode = RunWatchedCommand(projectRoot, watchedCommand, forwardedArgs);
        var runCount = 1;

        if (maxRuns.HasValue && runCount >= maxRuns.Value)
            return lastExitCode;

        using var watcher = new FileSystemWatcher(projectRoot)
        {
            IncludeSubdirectories = true,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.CreationTime
        };

        void HandleChange(string path)
        {
            if (!ShouldWatch(path))
                return;

            lock (sync)
            {
                pendingChange = true;
                lastChangeUtc = DateTime.UtcNow;
            }

            wakeSignal.Set();
        }

        watcher.Changed += (_, eventArgs) => HandleChange(eventArgs.FullPath);
        watcher.Created += (_, eventArgs) => HandleChange(eventArgs.FullPath);
        watcher.Deleted += (_, eventArgs) => HandleChange(eventArgs.FullPath);
        watcher.Renamed += (_, eventArgs) => HandleChange(eventArgs.FullPath);
        watcher.EnableRaisingEvents = true;

        Console.WriteLine($"Watching {projectRoot} for N# changes. Press Ctrl+C to stop.");

        ConsoleCancelEventHandler cancelHandler = (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            cancelled = true;
            wakeSignal.Set();
        };

        Console.CancelKeyPress += cancelHandler;

        try
        {
            while (!cancelled)
            {
                wakeSignal.WaitOne(100);

                bool shouldRun;
                lock (sync)
                {
                    shouldRun = pendingChange && DateTime.UtcNow - lastChangeUtc >= TimeSpan.FromMilliseconds(debounceMs.Value);
                    if (shouldRun)
                        pendingChange = false;
                }

                if (!shouldRun)
                    continue;

                Console.WriteLine();
                Console.WriteLine($"Change detected at {DateTime.Now:T}. Re-running `nlc {watchedCommand}`.");
                lastExitCode = RunWatchedCommand(projectRoot, watchedCommand, forwardedArgs);
                runCount++;

                if (maxRuns.HasValue && runCount >= maxRuns.Value)
                    return lastExitCode;
            }

            return lastExitCode;
        }
        finally
        {
            Console.CancelKeyPress -= cancelHandler;
        }
    }

    private static int RunWatchedCommand(string projectRoot, string watchedCommand, IReadOnlyList<string> forwardedArgs)
    {
        var originalDirectory = Directory.GetCurrentDirectory();
        try
        {
            Directory.SetCurrentDirectory(projectRoot);
            return Program.Execute(new[] { watchedCommand }.Concat(forwardedArgs).ToArray());
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
        }
    }

    private static string[] GetForwardedArgs(string[] args)
    {
        var forwarded = new List<string>();

        for (var i = 0; i < args.Length; i++)
        {
            if (WatchOptionsWithValues.Contains(args[i], StringComparer.Ordinal))
            {
                i++;
                continue;
            }

            if (args[i] == "--help" || args[i] == "-h")
                continue;

            forwarded.Add(args[i]);
        }

        return forwarded.ToArray();
    }

    private static bool ShouldWatch(string path)
    {
        var fileName = Path.GetFileName(path);
        if (fileName.Equals("project.yml", StringComparison.OrdinalIgnoreCase) ||
            fileName.Equals(".editorconfig", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var extension = Path.GetExtension(path);
        return extension.Equals(".nl", StringComparison.OrdinalIgnoreCase);
    }

    private static int? ParsePositiveInt(string? value, int? defaultValue, string flag)
    {
        if (string.IsNullOrWhiteSpace(value))
            return defaultValue;

        if (int.TryParse(value, out var parsed) && parsed > 0)
            return parsed;

        Error($"{flag} expects a positive integer.");
        return null;
    }

    private static string? GetOption(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == flag)
                return args[i + 1];
        }

        return null;
    }

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# Watch

Usage: nlc watch <check|build|test|lint|format> [command-options]

Re-run an N# command when `.nl`, `project.yml`, or `.editorconfig` files change.

Options:
  --project <dir>      Project root directory to watch (default: current directory)
  --debounce-ms <ms>   Debounce window before rerunning (default: 250)
  --max-runs <count>   Exit after N command executions (useful for scripts and tests)
  --help, -h           Show this help text

Examples:
  nlc watch check
  nlc watch build
  nlc watch test --filter AddPerson
  nlc watch lint
  nlc watch format --check
  nlc watch check --project examples/16-task-cli --max-runs 2

Exit codes:
  0  Watch finished and the last run succeeded
  1  Invalid usage or the last watched run failed");

        return 0;
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}
