using System;

namespace NSharpLang.Cli;

internal static class PublishCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static PublishArgumentSummary GetArgumentSummary(string[] args)
    {
        var bindings = RequiredBindings;
        var resultIndices = t_resultIndices ??= new int[9];
        var code = bindings.PublishOptionsInto(args, resultIndices);
        if (code < 0 || code > 4)
            throw new InvalidOperationException("N# publish argument summary kernel rejected the arguments.");

        var validationError = GetValidationError(args, code, resultIndices[7]);
        if (validationError != null)
        {
            return new PublishArgumentSummary(
                validationError,
                null,
                null,
                "Release",
                null,
                null,
                false,
                false,
                resultIndices[8] != 0);
        }

        if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
            || !TryGetOptionalArg(args, resultIndices[1], out var backendOption)
            || !TryGetOptionalArg(args, resultIndices[2], out var configuration)
            || !TryGetOptionalArg(args, resultIndices[3], out var output)
            || !TryGetOptionalArg(args, resultIndices[4], out var runtime))
        {
            throw new InvalidOperationException("N# publish argument summary kernel rejected the arguments.");
        }

        return new PublishArgumentSummary(
            null,
            projectOption,
            backendOption,
            configuration ?? "Release",
            output,
            runtime,
            resultIndices[5] != 0,
            resultIndices[6] != 0,
            resultIndices[8] != 0);
    }

    private static string? GetValidationError(string[] args, int code, int errorArgIndex)
    {
        if (code == 0)
            return null;

        var errorArg = errorArgIndex >= 0 && errorArgIndex < args.Length
            ? args[errorArgIndex]
            : string.Empty;

        var message = RequiredBindings.PublishValidationErrorMessage(code, errorArg);
        if (!string.IsNullOrEmpty(message))
            return message;

        throw new InvalidOperationException("N# publish validation message kernel rejected the validation code.");
    }

    internal static string GetAotAnalysisOnlyNotice()
        => RequiredBindings.PublishAotAnalysisOnlyNotice();

    internal static string GetHelpText()
        => RequiredBindings.PublishHelpText();

    internal static string GetSelfContainedUnsupportedMessage()
        => RequiredBindings.PublishSelfContainedUnsupportedMessage();

    internal static string GetCrossRuntimeUnsupportedMessage(string requestedRuntime, string currentRuntime)
        => RequiredBindings.PublishCrossRuntimeUnsupportedMessage(requestedRuntime, currentRuntime);

    internal static string GetBuildFailureMessage(bool aotMode)
        => RequiredBindings.PublishBuildFailureMessage(aotMode ? 1 : 0);

    internal static string GetExceptionFailureMessage(string exceptionMessage)
        => RequiredBindings.PublishExceptionFailureMessage(exceptionMessage);

    internal static string GetStartMessage(string projectRoot)
        => RequiredBindings.PublishStartMessage(projectRoot);

    internal static string GetMissingProjectFileMessage()
        => RequiredBindings.PublishMissingProjectFileMessage();

    internal static string GetSuccessMessage()
        => RequiredBindings.PublishSuccessMessage();

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

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliPublishOptionsInto>(
                programType,
                "CliPublishOptionsInto"),
            DogfoodKernelLoader.CreateDelegate<CliPublishValidationErrorMessage>(
                programType,
                "CliPublishValidationErrorMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPublishHelpText>(
                programType,
                "CliPublishHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliPublishAotAnalysisOnlyNotice>(
                programType,
                "CliPublishAotAnalysisOnlyNotice"),
            DogfoodKernelLoader.CreateDelegate<CliPublishSelfContainedUnsupportedMessage>(
                programType,
                "CliPublishSelfContainedUnsupportedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPublishCrossRuntimeUnsupportedMessage>(
                programType,
                "CliPublishCrossRuntimeUnsupportedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPublishBuildFailureMessage>(
                programType,
                "CliPublishBuildFailureMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPublishExceptionFailureMessage>(
                programType,
                "CliPublishExceptionFailureMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPublishStartMessage>(
                programType,
                "CliPublishStartMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPublishMissingProjectFileMessage>(
                programType,
                "CliPublishMissingProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPublishSuccessMessage>(
                programType,
                "CliPublishSuccessMessage")));

    private delegate int CliPublishOptionsInto(string[] args, int[] resultIndices);
    private delegate string CliPublishValidationErrorMessage(int code, string arg);
    private delegate string CliPublishHelpText();
    private delegate string CliPublishAotAnalysisOnlyNotice();
    private delegate string CliPublishSelfContainedUnsupportedMessage();
    private delegate string CliPublishCrossRuntimeUnsupportedMessage(string requestedRuntime, string currentRuntime);
    private delegate string CliPublishBuildFailureMessage(int aotMode);
    private delegate string CliPublishExceptionFailureMessage(string exceptionMessage);
    private delegate string CliPublishStartMessage(string projectRoot);
    private delegate string CliPublishMissingProjectFileMessage();
    private delegate string CliPublishSuccessMessage();

    private sealed record Bindings(
        CliPublishOptionsInto PublishOptionsInto,
        CliPublishValidationErrorMessage PublishValidationErrorMessage,
        CliPublishHelpText PublishHelpText,
        CliPublishAotAnalysisOnlyNotice PublishAotAnalysisOnlyNotice,
        CliPublishSelfContainedUnsupportedMessage PublishSelfContainedUnsupportedMessage,
        CliPublishCrossRuntimeUnsupportedMessage PublishCrossRuntimeUnsupportedMessage,
        CliPublishBuildFailureMessage PublishBuildFailureMessage,
        CliPublishExceptionFailureMessage PublishExceptionFailureMessage,
        CliPublishStartMessage PublishStartMessage,
        CliPublishMissingProjectFileMessage PublishMissingProjectFileMessage,
        CliPublishSuccessMessage PublishSuccessMessage);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# publish command kernels are unavailable.");
}
