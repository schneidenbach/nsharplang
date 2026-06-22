using System;

namespace NSharpLang.Cli.Daemon;

internal static class DaemonClientKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string GetConnectionErrorMessage(string messageText)
        => RequiredBindings.ConnectionErrorMessage(messageText);

    internal static string GetExecutablePathMissingMessage()
        => RequiredBindings.ExecutablePathMissingMessage();

    internal static string GetStartTimeoutMessage()
        => RequiredBindings.StartTimeoutMessage();

    internal static string GetStartFailedWithReasonMessage(string messageText)
        => RequiredBindings.StartFailedWithReasonMessage(messageText);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# daemon client kernels are unavailable.");

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
