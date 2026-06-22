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
                "CliDaemonSemanticReferencesUnavailableMessage")));

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

    // Stage 6 C#-surface-shrink: fallback/oracle only; daemon query messages route through DaemonServerKernels.
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
        CliDaemonSemanticReferencesUnavailableMessage SemanticReferencesUnavailableMessage);
}
