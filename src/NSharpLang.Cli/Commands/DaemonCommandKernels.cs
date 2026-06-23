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

    internal static DaemonOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[3];
        var code = RequiredBindings.OptionSummary(args, resultIndices);
        if (code != 0
            || resultIndices[0] < (int)DaemonSubcommandKind.Unknown
            || resultIndices[0] > (int)DaemonSubcommandKind.Run
            || !TryGetOptionalArg(args, resultIndices[1], out var projectOption))
        {
            throw new InvalidOperationException("N# daemon option summary kernel rejected the arguments.");
        }

        return new DaemonOptionSummary(
            (DaemonSubcommandKind)resultIndices[0],
            projectOption,
            resultIndices[2] != 0);
    }

    internal static string GetHelpText()
        => RequiredBindings.DaemonHelpText();

    internal static string GetAlreadyRunningMessage()
        => RequiredBindings.DaemonAlreadyRunningMessage();

    internal static string GetStartingMessage(string projectDir)
        => RequiredBindings.DaemonStartingMessage(projectDir);

    internal static string GetStartedMessage()
        => RequiredBindings.DaemonStartedMessage();

    internal static string GetStartFailedMessage()
        => RequiredBindings.DaemonStartFailedMessage();

    internal static string GetNoDaemonRunningMessage()
        => RequiredBindings.DaemonNoDaemonRunningMessage();

    internal static string GetStoppedMessage()
        => RequiredBindings.DaemonStoppedMessage();

    internal static string GetStopFailedMessage()
        => RequiredBindings.DaemonStopFailedMessage();

    internal static string GetStatusNotRespondingMessage()
        => RequiredBindings.DaemonStatusNotRespondingMessage();

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

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# daemon command kernels are unavailable.");

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
