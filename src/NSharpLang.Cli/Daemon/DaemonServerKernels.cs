using System;
using System.Globalization;

namespace NSharpLang.Cli.Daemon;

internal static class DaemonServerKernels
{
    [ThreadStatic]
    private static int[]? t_positionResult;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static void ParsePosition(string position, out int line, out int column)
    {
        var result = t_positionResult ??= new int[2];
        var code = RequiredBindings.ParsePosition(position, result);
        if (code != 0)
            throw new InvalidOperationException("N# daemon position parser kernel rejected the position.");

        line = result[0];
        column = result[1];
    }

    internal static string GetUnknownMethodMessage(string method)
        => RequiredBindings.UnknownMethodMessage(method);

    internal static string GetFailedLoadProjectMessage()
        => RequiredBindings.FailedLoadProjectMessage();

    internal static string GetEmptyBatchPayloadMessage()
        => RequiredBindings.EmptyBatchPayloadMessage();

    internal static string GetFileParameterRequiredMessage()
        => RequiredBindings.FileParameterRequiredMessage();

    internal static string GetFileAndPosParametersRequiredMessage()
        => RequiredBindings.FileAndPosParametersRequiredMessage();

    internal static string GetDefinitionTargetRequiredMessage()
        => RequiredBindings.DefinitionTargetRequiredMessage();

    internal static string GetFileAndPosRequiredMessage()
        => RequiredBindings.FileAndPosRequiredMessage();

    internal static string GetNoSymbolAtPositionMessage(string file, int line, int column)
        => RequiredBindings.NoSymbolAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetSemanticReferencesUnavailableMessage()
        => RequiredBindings.SemanticReferencesUnavailableMessage();

    internal static string GetListeningMessage(string socketPath, int processId)
        => RequiredBindings.ListeningMessage(socketPath, ToInvariantText(processId));

    internal static string GetProjectMessage(string projectRoot)
        => RequiredBindings.ProjectMessage(projectRoot);

    internal static string GetIdleTimeoutMessage(string durationText)
        => RequiredBindings.IdleTimeoutMessage(durationText);

    internal static string GetIdleTimeoutShutdownMessage(string durationText)
        => RequiredBindings.IdleTimeoutShutdownMessage(durationText);

    internal static string GetServerErrorMessage(string messageText)
        => RequiredBindings.ServerErrorMessage(messageText);

    internal static string GetClientErrorMessage(string messageText)
        => RequiredBindings.ClientErrorMessage(messageText);

    internal static string GetLoadingProjectMessage()
        => RequiredBindings.LoadingProjectMessage();

    internal static string GetProjectLoadedMessage(long elapsedMilliseconds, int fileCount)
        => RequiredBindings.ProjectLoadedMessage(
            elapsedMilliseconds.ToString(CultureInfo.InvariantCulture),
            ToInvariantText(fileCount));

    internal static string GetProjectLoadFailedTraceMessage(string messageText)
        => RequiredBindings.ProjectLoadFailedTraceMessage(messageText);

    internal static string GetFileWatcherStartedMessage()
        => RequiredBindings.FileWatcherStartedMessage();

    internal static string GetFileWatcherFailedMessage(string messageText)
        => RequiredBindings.FileWatcherFailedMessage(messageText);

    internal static string GetFileChangedMessage(string fileName)
        => RequiredBindings.FileChangedMessage(fileName);

    internal static string GetShutdownCompleteMessage()
        => RequiredBindings.ShutdownCompleteMessage();

    internal static string GetMalformedRequestParamMessage(string key, string typeName, string messageText)
        => RequiredBindings.MalformedRequestParamMessage(key, typeName, messageText);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliDaemonPositionInto>(
                programType,
                "CliDaemonPositionInto"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonUnknownMethodMessage>(
                programType,
                "CliDaemonUnknownMethodMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonFailedLoadProjectMessage>(
                programType,
                "CliDaemonFailedLoadProjectMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonEmptyBatchPayloadMessage>(
                programType,
                "CliDaemonEmptyBatchPayloadMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonFileParameterRequiredMessage>(
                programType,
                "CliDaemonFileParameterRequiredMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonFileAndPosParametersRequiredMessage>(
                programType,
                "CliDaemonFileAndPosParametersRequiredMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonDefinitionTargetRequiredMessage>(
                programType,
                "CliDaemonDefinitionTargetRequiredMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonFileAndPosRequiredMessage>(
                programType,
                "CliDaemonFileAndPosRequiredMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonNoSymbolAtPositionMessage>(
                programType,
                "CliDaemonNoSymbolAtPositionMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonSemanticReferencesUnavailableMessage>(
                programType,
                "CliDaemonSemanticReferencesUnavailableMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonListeningMessage>(
                programType,
                "CliDaemonListeningMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonProjectMessage>(
                programType,
                "CliDaemonProjectMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonIdleTimeoutMessage>(
                programType,
                "CliDaemonIdleTimeoutMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonIdleTimeoutShutdownMessage>(
                programType,
                "CliDaemonIdleTimeoutShutdownMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonServerErrorMessage>(
                programType,
                "CliDaemonServerErrorMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonClientErrorMessage>(
                programType,
                "CliDaemonClientErrorMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonLoadingProjectMessage>(
                programType,
                "CliDaemonLoadingProjectMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonProjectLoadedMessage>(
                programType,
                "CliDaemonProjectLoadedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonProjectLoadFailedTraceMessage>(
                programType,
                "CliDaemonProjectLoadFailedTraceMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonFileWatcherStartedMessage>(
                programType,
                "CliDaemonFileWatcherStartedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonFileWatcherFailedMessage>(
                programType,
                "CliDaemonFileWatcherFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonFileChangedMessage>(
                programType,
                "CliDaemonFileChangedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonShutdownCompleteMessage>(
                programType,
                "CliDaemonShutdownCompleteMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDaemonMalformedRequestParamMessage>(
                programType,
                "CliDaemonMalformedRequestParamMessage")));

    private static string ToInvariantText(int value)
        => value.ToString(CultureInfo.InvariantCulture);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# daemon server kernels are unavailable.");

    private delegate int CliDaemonPositionInto(string position, int[] result);

    private delegate string CliDaemonUnknownMethodMessage(string method);
    private delegate string CliDaemonFailedLoadProjectMessage();
    private delegate string CliDaemonEmptyBatchPayloadMessage();
    private delegate string CliDaemonFileParameterRequiredMessage();
    private delegate string CliDaemonFileAndPosParametersRequiredMessage();
    private delegate string CliDaemonDefinitionTargetRequiredMessage();
    private delegate string CliDaemonFileAndPosRequiredMessage();
    private delegate string CliDaemonNoSymbolAtPositionMessage(string file, string lineText, string columnText);
    private delegate string CliDaemonSemanticReferencesUnavailableMessage();
    private delegate string CliDaemonListeningMessage(string socketPath, string processIdText);
    private delegate string CliDaemonProjectMessage(string projectRoot);
    private delegate string CliDaemonIdleTimeoutMessage(string durationText);
    private delegate string CliDaemonIdleTimeoutShutdownMessage(string durationText);
    private delegate string CliDaemonServerErrorMessage(string messageText);
    private delegate string CliDaemonClientErrorMessage(string messageText);
    private delegate string CliDaemonLoadingProjectMessage();
    private delegate string CliDaemonProjectLoadedMessage(string elapsedMillisecondsText, string fileCountText);
    private delegate string CliDaemonProjectLoadFailedTraceMessage(string messageText);
    private delegate string CliDaemonFileWatcherStartedMessage();
    private delegate string CliDaemonFileWatcherFailedMessage(string messageText);
    private delegate string CliDaemonFileChangedMessage(string fileName);
    private delegate string CliDaemonShutdownCompleteMessage();
    private delegate string CliDaemonMalformedRequestParamMessage(string key, string typeName, string messageText);

    private sealed record Bindings(
        CliDaemonPositionInto ParsePosition,
        CliDaemonUnknownMethodMessage UnknownMethodMessage,
        CliDaemonFailedLoadProjectMessage FailedLoadProjectMessage,
        CliDaemonEmptyBatchPayloadMessage EmptyBatchPayloadMessage,
        CliDaemonFileParameterRequiredMessage FileParameterRequiredMessage,
        CliDaemonFileAndPosParametersRequiredMessage FileAndPosParametersRequiredMessage,
        CliDaemonDefinitionTargetRequiredMessage DefinitionTargetRequiredMessage,
        CliDaemonFileAndPosRequiredMessage FileAndPosRequiredMessage,
        CliDaemonNoSymbolAtPositionMessage NoSymbolAtPositionMessage,
        CliDaemonSemanticReferencesUnavailableMessage SemanticReferencesUnavailableMessage,
        CliDaemonListeningMessage ListeningMessage,
        CliDaemonProjectMessage ProjectMessage,
        CliDaemonIdleTimeoutMessage IdleTimeoutMessage,
        CliDaemonIdleTimeoutShutdownMessage IdleTimeoutShutdownMessage,
        CliDaemonServerErrorMessage ServerErrorMessage,
        CliDaemonClientErrorMessage ClientErrorMessage,
        CliDaemonLoadingProjectMessage LoadingProjectMessage,
        CliDaemonProjectLoadedMessage ProjectLoadedMessage,
        CliDaemonProjectLoadFailedTraceMessage ProjectLoadFailedTraceMessage,
        CliDaemonFileWatcherStartedMessage FileWatcherStartedMessage,
        CliDaemonFileWatcherFailedMessage FileWatcherFailedMessage,
        CliDaemonFileChangedMessage FileChangedMessage,
        CliDaemonShutdownCompleteMessage ShutdownCompleteMessage,
        CliDaemonMalformedRequestParamMessage MalformedRequestParamMessage);
}
