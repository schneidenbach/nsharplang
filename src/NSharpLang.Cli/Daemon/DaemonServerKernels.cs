using System;
using System.Globalization;

namespace NSharpLang.Cli.Daemon;

internal static class DaemonServerKernels
{
    [ThreadStatic]
    private static int[]? t_positionResult;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryParsePosition(string position, out int line, out int column)
    {
        line = 0;
        column = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_positionResult ??= new int[2];
        try
        {
            var code = bindings.ParsePosition(position, result);
            if (code != 0)
                return false;

            line = result[0];
            column = result[1];
            return true;
        }
        catch
        {
            line = 0;
            column = 0;
            return false;
        }
    }

    internal static string GetUnknownMethodMessage(string method)
    {
        if (TryGetMessage(bindings => bindings.UnknownMethodMessage(method), out var message))
            return message;

        return GetUnknownMethodMessageWithCSharp(method);
    }

    internal static string GetFailedLoadProjectMessage()
    {
        if (TryGetMessage(bindings => bindings.FailedLoadProjectMessage(), out var message))
            return message;

        return GetFailedLoadProjectMessageWithCSharp();
    }

    internal static string GetEmptyBatchPayloadMessage()
    {
        if (TryGetMessage(bindings => bindings.EmptyBatchPayloadMessage(), out var message))
            return message;

        return GetEmptyBatchPayloadMessageWithCSharp();
    }

    internal static string GetFileParameterRequiredMessage()
    {
        if (TryGetMessage(bindings => bindings.FileParameterRequiredMessage(), out var message))
            return message;

        return GetFileParameterRequiredMessageWithCSharp();
    }

    internal static string GetFileAndPosParametersRequiredMessage()
    {
        if (TryGetMessage(bindings => bindings.FileAndPosParametersRequiredMessage(), out var message))
            return message;

        return GetFileAndPosParametersRequiredMessageWithCSharp();
    }

    internal static string GetDefinitionTargetRequiredMessage()
    {
        if (TryGetMessage(bindings => bindings.DefinitionTargetRequiredMessage(), out var message))
            return message;

        return GetDefinitionTargetRequiredMessageWithCSharp();
    }

    internal static string GetFileAndPosRequiredMessage()
    {
        if (TryGetMessage(bindings => bindings.FileAndPosRequiredMessage(), out var message))
            return message;

        return GetFileAndPosRequiredMessageWithCSharp();
    }

    internal static string GetNoSymbolAtPositionMessage(string file, int line, int column)
        => GetNoSymbolAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetNoSymbolAtPositionMessage(string file, string lineText, string columnText)
    {
        if (TryGetMessage(bindings => bindings.NoSymbolAtPositionMessage(file, lineText, columnText), out var message))
            return message;

        return GetNoSymbolAtPositionMessageWithCSharp(file, lineText, columnText);
    }

    internal static string GetSemanticReferencesUnavailableMessage()
    {
        if (TryGetMessage(bindings => bindings.SemanticReferencesUnavailableMessage(), out var message))
            return message;

        return GetSemanticReferencesUnavailableMessageWithCSharp();
    }

    internal static string GetListeningMessage(string socketPath, int processId)
        => GetListeningMessage(socketPath, ToInvariantText(processId));

    internal static string GetListeningMessage(string socketPath, string processIdText)
    {
        if (TryGetMessage(bindings => bindings.ListeningMessage(socketPath, processIdText), out var message))
            return message;

        return GetListeningMessageWithCSharp(socketPath, processIdText);
    }

    internal static string GetProjectMessage(string projectRoot)
    {
        if (TryGetMessage(bindings => bindings.ProjectMessage(projectRoot), out var message))
            return message;

        return GetProjectMessageWithCSharp(projectRoot);
    }

    internal static string GetIdleTimeoutMessage(string durationText)
    {
        if (TryGetMessage(bindings => bindings.IdleTimeoutMessage(durationText), out var message))
            return message;

        return GetIdleTimeoutMessageWithCSharp(durationText);
    }

    internal static string GetIdleTimeoutShutdownMessage(string durationText)
    {
        if (TryGetMessage(bindings => bindings.IdleTimeoutShutdownMessage(durationText), out var message))
            return message;

        return GetIdleTimeoutShutdownMessageWithCSharp(durationText);
    }

    internal static string GetServerErrorMessage(string messageText)
    {
        if (TryGetMessage(bindings => bindings.ServerErrorMessage(messageText), out var message))
            return message;

        return GetServerErrorMessageWithCSharp(messageText);
    }

    internal static string GetClientErrorMessage(string messageText)
    {
        if (TryGetMessage(bindings => bindings.ClientErrorMessage(messageText), out var message))
            return message;

        return GetClientErrorMessageWithCSharp(messageText);
    }

    internal static string GetLoadingProjectMessage()
    {
        if (TryGetMessage(bindings => bindings.LoadingProjectMessage(), out var message))
            return message;

        return GetLoadingProjectMessageWithCSharp();
    }

    internal static string GetProjectLoadedMessage(long elapsedMilliseconds, int fileCount)
        => GetProjectLoadedMessage(
            elapsedMilliseconds.ToString(CultureInfo.InvariantCulture),
            ToInvariantText(fileCount));

    internal static string GetProjectLoadedMessage(string elapsedMillisecondsText, string fileCountText)
    {
        if (TryGetMessage(bindings => bindings.ProjectLoadedMessage(elapsedMillisecondsText, fileCountText), out var message))
            return message;

        return GetProjectLoadedMessageWithCSharp(elapsedMillisecondsText, fileCountText);
    }

    internal static string GetProjectLoadFailedTraceMessage(string messageText)
    {
        if (TryGetMessage(bindings => bindings.ProjectLoadFailedTraceMessage(messageText), out var message))
            return message;

        return GetProjectLoadFailedTraceMessageWithCSharp(messageText);
    }

    internal static string GetFileWatcherStartedMessage()
    {
        if (TryGetMessage(bindings => bindings.FileWatcherStartedMessage(), out var message))
            return message;

        return GetFileWatcherStartedMessageWithCSharp();
    }

    internal static string GetFileWatcherFailedMessage(string messageText)
    {
        if (TryGetMessage(bindings => bindings.FileWatcherFailedMessage(messageText), out var message))
            return message;

        return GetFileWatcherFailedMessageWithCSharp(messageText);
    }

    internal static string GetFileChangedMessage(string fileName)
    {
        if (TryGetMessage(bindings => bindings.FileChangedMessage(fileName), out var message))
            return message;

        return GetFileChangedMessageWithCSharp(fileName);
    }

    internal static string GetShutdownCompleteMessage()
    {
        if (TryGetMessage(bindings => bindings.ShutdownCompleteMessage(), out var message))
            return message;

        return GetShutdownCompleteMessageWithCSharp();
    }

    internal static string GetMalformedRequestParamMessage(string key, string typeName, string messageText)
    {
        if (TryGetMessage(bindings => bindings.MalformedRequestParamMessage(key, typeName, messageText), out var message))
            return message;

        return GetMalformedRequestParamMessageWithCSharp(key, typeName, messageText);
    }

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

    // Stage 6 C#-surface-shrink: fallback/oracle only; daemon query and lifecycle messages route through DaemonServerKernels.
    private static string GetUnknownMethodMessageWithCSharp(string method)
        => $"Unknown method: {method}";

    private static string GetFailedLoadProjectMessageWithCSharp()
        => "Failed to load project";

    private static string GetEmptyBatchPayloadMessageWithCSharp()
        => "Batch request payload did not contain any requests.";

    private static string GetFileParameterRequiredMessageWithCSharp()
        => "file parameter required";

    private static string GetFileAndPosParametersRequiredMessageWithCSharp()
        => "file and pos parameters required";

    private static string GetDefinitionTargetRequiredMessageWithCSharp()
        => "file+pos or name required";

    private static string GetFileAndPosRequiredMessageWithCSharp()
        => "file and pos required";

    private static string GetNoSymbolAtPositionMessageWithCSharp(string file, string lineText, string columnText)
        => $"No symbol found at {file}:{lineText}:{columnText}";

    private static string GetSemanticReferencesUnavailableMessageWithCSharp()
        => "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. "
           + "No name-based or text-based fallback was used.";

    private static string GetListeningMessageWithCSharp(string socketPath, string processIdText)
        => $"[daemon] Listening on {socketPath} (PID {processIdText})";

    private static string GetProjectMessageWithCSharp(string projectRoot)
        => $"[daemon] Project: {projectRoot}";

    private static string GetIdleTimeoutMessageWithCSharp(string durationText)
        => $"[daemon] Idle timeout: {durationText}";

    private static string GetIdleTimeoutShutdownMessageWithCSharp(string durationText)
        => $"[daemon] Idle timeout ({durationText}). Shutting down.";

    private static string GetServerErrorMessageWithCSharp(string messageText)
        => $"[daemon] Error: {messageText}";

    private static string GetClientErrorMessageWithCSharp(string messageText)
        => $"[daemon] Client error: {messageText}";

    private static string GetLoadingProjectMessageWithCSharp()
        => "[daemon] Loading project...";

    private static string GetProjectLoadedMessageWithCSharp(string elapsedMillisecondsText, string fileCountText)
        => $"[daemon] Project loaded in {elapsedMillisecondsText}ms ({fileCountText} files)";

    private static string GetProjectLoadFailedTraceMessageWithCSharp(string messageText)
        => $"[daemon] Failed to load project: {messageText}";

    private static string GetFileWatcherStartedMessageWithCSharp()
        => "[daemon] File watcher started for *.nl, project.yml, .editorconfig";

    private static string GetFileWatcherFailedMessageWithCSharp(string messageText)
        => $"[daemon] File watcher failed: {messageText}";

    private static string GetFileChangedMessageWithCSharp(string fileName)
        => $"[daemon] File changed: {fileName} — cache invalidated";

    private static string GetShutdownCompleteMessageWithCSharp()
        => "[daemon] Shutdown complete.";

    private static string GetMalformedRequestParamMessageWithCSharp(string key, string typeName, string messageText)
        => $"[daemon] Ignoring malformed request param '{key}' (expected {typeName}): {messageText}";

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
