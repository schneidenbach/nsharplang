using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace NSharpLang.Cli.Commands;

public static class WatchCommand
{
    private static readonly string[] WatchOptionsWithValues = { "--project", "--debounce-ms", "--max-runs" };

    public static int Execute(string[] args)
    {
        var options = GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var targetSummary = GetTargetSummary(args);
        if (targetSummary.TargetKind == WatchTargetKind.Unknown)
            return Error($"Unsupported watch target '{GetUnsupportedTargetName(args)}'. Expected check, build, test, lint, or format.");

        var watchedCommand = GetWatchedCommandName(targetSummary.TargetKind);

        var forwardedArgs = GetForwardedArgs(args);
        var projectRoot = options.ProjectOption ?? Directory.GetCurrentDirectory();
        projectRoot = Path.GetFullPath(projectRoot);

        if (!Directory.Exists(projectRoot))
            return Error($"Project directory not found: {projectRoot}");

        var debounceMs = ParsePositiveInt(options.DebounceMsOption, 250, "--debounce-ms");
        if (debounceMs == null)
            return 1;

        var maxRuns = ParsePositiveInt(options.MaxRunsOption, null, "--max-runs");
        if (options.MaxRunsOption != null && maxRuns == null)
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

    internal static WatchOptionSummary GetOptionSummary(string[] args)
        => WatchCommandKernels.TryGetOptionSummary(args, out var summary)
            ? summary
            : GetOptionSummaryWithCSharp(args);

    internal static WatchTargetSummary GetTargetSummary(string[] args)
        => WatchCommandKernels.TryGetTargetSummary(args, out var summary)
            ? summary
            : GetTargetSummaryWithCSharp(args);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product watch target parsing routes through WatchCommandKernels.
    private static WatchTargetSummary GetTargetSummaryWithCSharp(string[] args)
    {
        if (args.Length == 0)
            return new WatchTargetSummary(WatchTargetKind.Unknown);

        return new WatchTargetSummary(args[0].ToLowerInvariant() switch
        {
            "check" => WatchTargetKind.Check,
            "build" => WatchTargetKind.Build,
            "test" => WatchTargetKind.Test,
            "lint" => WatchTargetKind.Lint,
            "format" => WatchTargetKind.Format,
            _ => WatchTargetKind.Unknown
        });
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product watch option parsing routes through WatchCommandKernels.
    private static WatchOptionSummary GetOptionSummaryWithCSharp(string[] args)
        => new(
            GetOptionWithCSharp(args, "--project"),
            GetOptionWithCSharp(args, "--debounce-ms"),
            GetOptionWithCSharp(args, "--max-runs"),
            args.Length == 0
                || args[0] == "help"
                || ContainsArgWithCSharp(args, "--help")
                || ContainsArgWithCSharp(args, "-h"));

    private static string[] GetForwardedArgs(string[] args)
    {
        if (WatchCommandKernels.TryGetForwardedArgs(args, out var forwardedArgs))
            return forwardedArgs;

        return GetForwardedArgsWithCSharp(args);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product watch forwarding routes through WatchCommandKernels.
    private static string[] GetForwardedArgsWithCSharp(string[] args)
    {
        var forwarded = new List<string>();

        for (var i = 1; i < args.Length; i++)
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

        if (WatchCommandKernels.TryParsePositiveInt(value, out var parsedFromKernel))
        {
            if (parsedFromKernel > 0)
                return parsedFromKernel;

            Error($"{flag} expects a positive integer.");
            return null;
        }

        return ParsePositiveIntWithCSharp(value, flag);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product watch numeric option parsing routes through WatchCommandKernels.
    private static int? ParsePositiveIntWithCSharp(string value, string flag)
    {
        if (int.TryParse(value, out var parsed) && parsed > 0)
            return parsed;

        Error($"{flag} expects a positive integer.");
        return null;
    }

    private static string GetWatchedCommandName(WatchTargetKind targetKind)
        => targetKind switch
        {
            WatchTargetKind.Check => "check",
            WatchTargetKind.Build => "build",
            WatchTargetKind.Test => "test",
            WatchTargetKind.Lint => "lint",
            WatchTargetKind.Format => "format",
            _ => string.Empty
        };

    private static string GetUnsupportedTargetName(string[] args)
        => args.Length == 0 ? string.Empty : args[0].ToLowerInvariant();

    private static string? GetOptionWithCSharp(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == flag)
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
