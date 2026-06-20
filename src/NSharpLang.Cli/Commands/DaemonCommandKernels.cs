using System;

namespace NSharpLang.Cli.Commands;

internal enum DaemonSubcommandKind
{
    Unknown = 0,
    Start = 1,
    Stop = 2,
    Status = 3,
    Run = 4
}

internal readonly record struct DaemonOptionSummary(
    DaemonSubcommandKind SubcommandKind,
    string? ProjectOption,
    bool ShowHelp);

internal static class DaemonCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out DaemonOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[3];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0
                || resultIndices[0] < (int)DaemonSubcommandKind.Unknown
                || resultIndices[0] > (int)DaemonSubcommandKind.Run)
            {
                return false;
            }

            if (!TryGetOptionalArg(args, resultIndices[1], out var projectOption))
            {
                summary = default;
                return false;
            }

            summary = new DaemonOptionSummary(
                (DaemonSubcommandKind)resultIndices[0],
                projectOption,
                resultIndices[2] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static string GetHelpText()
    {
        if (TryGetMessage(bindings => bindings.DaemonHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetAlreadyRunningMessage()
    {
        if (TryGetMessage(bindings => bindings.DaemonAlreadyRunningMessage(), out var message))
            return message;

        return GetAlreadyRunningMessageWithCSharp();
    }

    internal static string GetStartingMessage(string projectDir)
    {
        if (TryGetMessage(bindings => bindings.DaemonStartingMessage(projectDir), out var message))
            return message;

        return GetStartingMessageWithCSharp(projectDir);
    }

    internal static string GetStartedMessage()
    {
        if (TryGetMessage(bindings => bindings.DaemonStartedMessage(), out var message))
            return message;

        return GetStartedMessageWithCSharp();
    }

    internal static string GetStartFailedMessage()
    {
        if (TryGetMessage(bindings => bindings.DaemonStartFailedMessage(), out var message))
            return message;

        return GetStartFailedMessageWithCSharp();
    }

    internal static string GetNoDaemonRunningMessage()
    {
        if (TryGetMessage(bindings => bindings.DaemonNoDaemonRunningMessage(), out var message))
            return message;

        return GetNoDaemonRunningMessageWithCSharp();
    }

    internal static string GetStoppedMessage()
    {
        if (TryGetMessage(bindings => bindings.DaemonStoppedMessage(), out var message))
            return message;

        return GetStoppedMessageWithCSharp();
    }

    internal static string GetStopFailedMessage()
    {
        if (TryGetMessage(bindings => bindings.DaemonStopFailedMessage(), out var message))
            return message;

        return GetStopFailedMessageWithCSharp();
    }

    internal static string GetStatusNotRespondingMessage()
    {
        if (TryGetMessage(bindings => bindings.DaemonStatusNotRespondingMessage(), out var message))
            return message;

        return GetStatusNotRespondingMessageWithCSharp();
    }

    private static bool TryGetMessage(Func<Bindings, string> getMessage, out string message)
    {
        message = string.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            message = getMessage(bindings);
            return !string.IsNullOrEmpty(message);
        }
        catch
        {
            message = string.Empty;
            return false;
        }
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product daemon command messages route through CliDaemon* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Analysis Daemon\n"
           + "\n"
           + "Usage: nlc daemon <command> [options]\n"
           + "\n"
           + "Commands:\n"
           + "  start     Start the daemon for the current project\n"
           + "  stop      Stop the running daemon\n"
           + "  status    Show daemon status (PID, uptime, cached files)\n"
           + "\n"
           + "Options:\n"
           + "  --project <dir>   Project root directory (default: current directory)\n"
           + "\n"
           + "The daemon caches project analysis and can serve JSON `nlc query` requests\n"
           + "via Unix domain socket for faster repeated response times.\n"
           + "\n"
           + "- `nlc query` reuses the daemon only when one is already running\n"
           + "- Auto-exits after 30 minutes of inactivity\n"
           + "- Watches .nl, project.yml, and .editorconfig for changes and invalidates cache\n"
           + "- Socket: {projectRoot}/.nlc/daemon.sock\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Command succeeded\n"
           + "  1  Command failed (e.g., daemon failed to start or stop)";

    private static string GetAlreadyRunningMessageWithCSharp()
        => "Daemon is already running.";

    private static string GetStartingMessageWithCSharp(string projectDir)
        => $"Starting daemon for {projectDir}...";

    private static string GetStartedMessageWithCSharp()
        => "Daemon started.";

    private static string GetStartFailedMessageWithCSharp()
        => "Failed to start daemon.";

    private static string GetNoDaemonRunningMessageWithCSharp()
        => "No daemon running.";

    private static string GetStoppedMessageWithCSharp()
        => "Daemon stopped.";

    private static string GetStopFailedMessageWithCSharp()
        => "Failed to stop daemon.";

    private static string GetStatusNotRespondingMessageWithCSharp()
        => "Daemon is running but not responding to status queries.";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliDaemonOptionSummaryInto>(
                programType,
                "CliDaemonOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonHelpText>(
                programType,
                "CliDaemonHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonAlreadyRunningMessage>(
                programType,
                "CliDaemonAlreadyRunningMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonStartingMessage>(
                programType,
                "CliDaemonStartingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonStartedMessage>(
                programType,
                "CliDaemonStartedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonStartFailedMessage>(
                programType,
                "CliDaemonStartFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonNoDaemonRunningMessage>(
                programType,
                "CliDaemonNoDaemonRunningMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonStoppedMessage>(
                programType,
                "CliDaemonStoppedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonStopFailedMessage>(
                programType,
                "CliDaemonStopFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonStatusNotRespondingMessage>(
                programType,
                "CliDaemonStatusNotRespondingMessage")));

    private delegate int CliDaemonOptionSummaryInto(string[] args, int[] resultIndices);
    private delegate string CliDaemonHelpText();
    private delegate string CliDaemonAlreadyRunningMessage();
    private delegate string CliDaemonStartingMessage(string projectDir);
    private delegate string CliDaemonStartedMessage();
    private delegate string CliDaemonStartFailedMessage();
    private delegate string CliDaemonNoDaemonRunningMessage();
    private delegate string CliDaemonStoppedMessage();
    private delegate string CliDaemonStopFailedMessage();
    private delegate string CliDaemonStatusNotRespondingMessage();

    private sealed record Bindings(
        CliDaemonOptionSummaryInto OptionSummary,
        CliDaemonHelpText DaemonHelpText,
        CliDaemonAlreadyRunningMessage DaemonAlreadyRunningMessage,
        CliDaemonStartingMessage DaemonStartingMessage,
        CliDaemonStartedMessage DaemonStartedMessage,
        CliDaemonStartFailedMessage DaemonStartFailedMessage,
        CliDaemonNoDaemonRunningMessage DaemonNoDaemonRunningMessage,
        CliDaemonStoppedMessage DaemonStoppedMessage,
        CliDaemonStopFailedMessage DaemonStopFailedMessage,
        CliDaemonStatusNotRespondingMessage DaemonStatusNotRespondingMessage);

    private static bool TryGetOptionalArg(string[] args, int index, out string? value)
    {
        value = null;
        if (index == -1)
            return true;

        if (index < 0 || index >= args.Length)
            return false;

        value = args[index];
        return true;
    }
}
