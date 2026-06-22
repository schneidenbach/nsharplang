using System;

namespace NSharpLang.Cli.Daemon;

internal static class DaemonClientKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string GetConnectionErrorMessage(string messageText)
    {
        if (TryGetMessage(bindings => bindings.ConnectionErrorMessage(messageText), out var message))
            return message;

        return GetConnectionErrorMessageWithCSharp(messageText);
    }

    internal static string GetExecutablePathMissingMessage()
    {
        if (TryGetMessage(bindings => bindings.ExecutablePathMissingMessage(), out var message))
            return message;

        return GetExecutablePathMissingMessageWithCSharp();
    }

    internal static string GetStartTimeoutMessage()
    {
        if (TryGetMessage(bindings => bindings.StartTimeoutMessage(), out var message))
            return message;

        return GetStartTimeoutMessageWithCSharp();
    }

    internal static string GetStartFailedWithReasonMessage(string messageText)
    {
        if (TryGetMessage(bindings => bindings.StartFailedWithReasonMessage(messageText), out var message))
            return message;

        return GetStartFailedWithReasonMessageWithCSharp(messageText);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product daemon client messages route through CliDaemonClient* kernels.
    private static string GetConnectionErrorMessageWithCSharp(string messageText)
        => $"[daemon] Connection error: {messageText}";

    private static string GetExecutablePathMissingMessageWithCSharp()
        => "Cannot determine executable path for daemon";

    private static string GetStartTimeoutMessageWithCSharp()
        => "Daemon started but not responding within 5 seconds";

    private static string GetStartFailedWithReasonMessageWithCSharp(string messageText)
        => $"Failed to start daemon: {messageText}";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliDaemonClientConnectionErrorMessage>(
                programType,
                "CliDaemonClientConnectionErrorMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonClientExecutablePathMissingMessage>(
                programType,
                "CliDaemonClientExecutablePathMissingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonClientStartTimeoutMessage>(
                programType,
                "CliDaemonClientStartTimeoutMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonClientStartFailedWithReasonMessage>(
                programType,
                "CliDaemonClientStartFailedWithReasonMessage")));

    private delegate string CliDaemonClientConnectionErrorMessage(string messageText);
    private delegate string CliDaemonClientExecutablePathMissingMessage();
    private delegate string CliDaemonClientStartTimeoutMessage();
    private delegate string CliDaemonClientStartFailedWithReasonMessage(string messageText);

    private sealed record Bindings(
        CliDaemonClientConnectionErrorMessage ConnectionErrorMessage,
        CliDaemonClientExecutablePathMissingMessage ExecutablePathMissingMessage,
        CliDaemonClientStartTimeoutMessage StartTimeoutMessage,
        CliDaemonClientStartFailedWithReasonMessage StartFailedWithReasonMessage);
}
