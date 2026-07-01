using System.Globalization;

namespace NSharpLang.Cli.Daemon;

internal static class DaemonServerKernels
{
    internal static void ParsePosition(string position, out int line, out int column)
    {
        line = 0;
        column = 0;

        var colon = position.IndexOf(':');
        if (colon < 0 || colon != position.LastIndexOf(':'))
            return;

        if (TryParseIntSegment(position, 0, colon, out var parsedLine))
            line = parsedLine;

        if (TryParseIntSegment(position, colon + 1, position.Length, out var parsedColumn))
            column = parsedColumn;
    }

    internal static string GetUnknownMethodMessage(string method)
        => DaemonServerMessageKernels.GetUnknownMethodMessage(method);

    internal static string GetFailedLoadProjectMessage()
        => DaemonServerMessageKernels.GetFailedLoadProjectMessage();

    internal static string GetEmptyBatchPayloadMessage()
        => DaemonServerMessageKernels.GetEmptyBatchPayloadMessage();

    internal static string GetFileParameterRequiredMessage()
        => DaemonServerMessageKernels.GetFileParameterRequiredMessage();

    internal static string GetFileAndPosParametersRequiredMessage()
        => DaemonServerMessageKernels.GetFileAndPosParametersRequiredMessage();

    internal static string GetDefinitionTargetRequiredMessage()
        => DaemonServerMessageKernels.GetDefinitionTargetRequiredMessage();

    internal static string GetFileAndPosRequiredMessage()
        => DaemonServerMessageKernels.GetFileAndPosRequiredMessage();

    internal static string GetNoSymbolAtPositionMessage(string file, int line, int column)
        => $"No symbol found at {file}:{line.ToString(CultureInfo.InvariantCulture)}:{column.ToString(CultureInfo.InvariantCulture)}";

    internal static string GetSemanticReferencesUnavailableMessage()
        => DaemonServerMessageKernels.GetSemanticReferencesUnavailableMessage();

    internal static string GetListeningMessage(string socketPath, int processId)
        => DaemonServerMessageKernels.GetListeningMessage(socketPath, processId.ToString(CultureInfo.InvariantCulture));

    internal static string GetProjectMessage(string projectRoot)
        => DaemonServerMessageKernels.GetProjectMessage(projectRoot);

    internal static string GetIdleTimeoutMessage(string durationText)
        => DaemonServerMessageKernels.GetIdleTimeoutMessage(durationText);

    internal static string GetIdleTimeoutShutdownMessage(string durationText)
        => DaemonServerMessageKernels.GetIdleTimeoutShutdownMessage(durationText);

    internal static string GetServerErrorMessage(string messageText)
        => DaemonServerMessageKernels.GetServerErrorMessage(messageText);

    internal static string GetClientErrorMessage(string messageText)
        => DaemonServerMessageKernels.GetClientErrorMessage(messageText);

    internal static string GetLoadingProjectMessage()
        => DaemonServerMessageKernels.GetLoadingProjectMessage();

    internal static string GetProjectLoadedMessage(long elapsedMilliseconds, int fileCount)
        => DaemonServerMessageKernels.GetProjectLoadedMessage(
            elapsedMilliseconds.ToString(CultureInfo.InvariantCulture),
            fileCount.ToString(CultureInfo.InvariantCulture));

    internal static string GetProjectLoadFailedTraceMessage(string messageText)
        => DaemonServerMessageKernels.GetProjectLoadFailedTraceMessage(messageText);

    internal static string GetFileWatcherStartedMessage()
        => DaemonServerMessageKernels.GetFileWatcherStartedMessage();

    internal static string GetFileWatcherFailedMessage(string messageText)
        => DaemonServerMessageKernels.GetFileWatcherFailedMessage(messageText);

    internal static string GetFileChangedMessage(string fileName)
        => DaemonServerMessageKernels.GetFileChangedMessage(fileName);

    internal static string GetShutdownCompleteMessage()
        => DaemonServerMessageKernels.GetShutdownCompleteMessage();

    internal static string GetMalformedRequestParamMessage(string key, string typeName, string messageText)
        => DaemonServerMessageKernels.GetMalformedRequestParamMessage(key, typeName, messageText);

    private static bool TryParseIntSegment(string text, int start, int end, out int value)
    {
        while (start < end && char.IsWhiteSpace(text[start]))
            start++;

        while (end > start && char.IsWhiteSpace(text[end - 1]))
            end--;

        var segment = text[start..end];
        return int.TryParse(segment, NumberStyles.Integer, CultureInfo.InvariantCulture, out value);
    }
}
