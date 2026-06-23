using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace NSharpLang.Cli.Commands;

public static class WatchCommand
{
    public static int Execute(string[] args)
    {
        var options = WatchCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var targetSummary = WatchCommandKernels.GetTargetSummary(args);
        if (targetSummary.TargetKind == WatchTargetKind.Unknown)
            return Error(WatchCommandKernels.GetUnsupportedTargetMessage(GetUnsupportedTargetName(args)));

        var watchedCommand = WatchCommandKernels.GetTargetCommandName(targetSummary.TargetKind);

        var forwardedArgs = WatchCommandKernels.GetForwardedArgs(args);
        var projectRoot = options.ProjectOption ?? Directory.GetCurrentDirectory();
        projectRoot = Path.GetFullPath(projectRoot);

        if (!Directory.Exists(projectRoot))
            return Error(WatchCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot));

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
            if (!WatchCommandKernels.ShouldTriggerForChangedPath(path))
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

        Console.WriteLine(WatchCommandKernels.GetStartedMessage(projectRoot));

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
                Console.WriteLine(WatchCommandKernels.GetChangeDetectedMessage(DateTime.Now.ToString("T"), watchedCommand));
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

    private static int? ParsePositiveInt(string? value, int? defaultValue, string flag)
    {
        if (string.IsNullOrWhiteSpace(value))
            return defaultValue;

        var parsedFromKernel = WatchCommandKernels.ParsePositiveInt(value);
        if (parsedFromKernel > 0)
            return parsedFromKernel;

        Error(WatchCommandKernels.GetPositiveIntExpectedMessage(flag));
        return null;
    }

    private static string GetUnsupportedTargetName(string[] args)
        => args.Length == 0 ? string.Empty : args[0].ToLowerInvariant();

    private static int ShowHelp()
    {
        Console.WriteLine(WatchCommandKernels.GetHelpText());
        return 0;
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}
