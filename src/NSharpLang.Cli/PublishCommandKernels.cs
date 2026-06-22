using System;

namespace NSharpLang.Cli;

internal static class PublishCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out PublishArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[9];
        try
        {
            var code = bindings.PublishOptionsInto(args, resultIndices);
            if (code < 0 || code > 4)
                return false;

            var validationError = GetValidationError(args, code, resultIndices[7]);
            if (validationError != null)
            {
                summary = new PublishArgumentSummary(
                    validationError,
                    null,
                    null,
                    "Release",
                    null,
                    null,
                    false,
                    false,
                    resultIndices[8] != 0);
                return true;
            }

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var backendOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var configuration)
                || !TryGetOptionalArg(args, resultIndices[3], out var output)
                || !TryGetOptionalArg(args, resultIndices[4], out var runtime))
            {
                summary = default;
                return false;
            }

            summary = new PublishArgumentSummary(
                null,
                projectOption,
                backendOption,
                configuration ?? "Release",
                output,
                runtime,
                resultIndices[5] != 0,
                resultIndices[6] != 0,
                resultIndices[8] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    private static string? GetValidationError(string[] args, int code, int errorArgIndex)
    {
        if (code == 0)
            return null;

        var errorArg = errorArgIndex >= 0 && errorArgIndex < args.Length
            ? args[errorArgIndex]
            : string.Empty;

        if (TryGetValidationErrorMessage(code, errorArg, out var dogfoodMessage))
            return dogfoodMessage;

        return GetValidationErrorWithCSharp(args, code, errorArgIndex);
    }

    private static bool TryGetValidationErrorMessage(int code, string errorArg, out string message)
    {
        message = string.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            message = bindings.PublishValidationErrorMessage(code, errorArg);
            return !string.IsNullOrEmpty(message);
        }
        catch
        {
            message = string.Empty;
            return false;
        }
    }

    internal static string GetAotAnalysisOnlyNotice()
    {
        if (TryGetPublishMessage(bindings => bindings.PublishAotAnalysisOnlyNotice(), out var message))
            return message;

        return GetAotAnalysisOnlyNoticeWithCSharp();
    }

    internal static string GetHelpText()
    {
        if (TryGetPublishMessage(bindings => bindings.PublishHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetSelfContainedUnsupportedMessage()
    {
        if (TryGetPublishMessage(bindings => bindings.PublishSelfContainedUnsupportedMessage(), out var message))
            return message;

        return GetSelfContainedUnsupportedMessageWithCSharp();
    }

    internal static string GetCrossRuntimeUnsupportedMessage(string requestedRuntime, string currentRuntime)
    {
        if (TryGetPublishMessage(
                bindings => bindings.PublishCrossRuntimeUnsupportedMessage(requestedRuntime, currentRuntime),
                out var message))
        {
            return message;
        }

        return GetCrossRuntimeUnsupportedMessageWithCSharp(requestedRuntime, currentRuntime);
    }

    internal static string GetBuildFailureMessage(bool aotMode)
    {
        if (TryGetPublishMessage(bindings => bindings.PublishBuildFailureMessage(aotMode ? 1 : 0), out var message))
            return message;

        return GetBuildFailureMessageWithCSharp(aotMode);
    }

    internal static string GetExceptionFailureMessage(string exceptionMessage)
    {
        if (TryGetPublishMessage(bindings => bindings.PublishExceptionFailureMessage(exceptionMessage), out var message))
            return message;

        return GetExceptionFailureMessageWithCSharp(exceptionMessage);
    }

    internal static string GetStartMessage(string projectRoot)
    {
        if (TryGetPublishMessage(bindings => bindings.PublishStartMessage(projectRoot), out var message))
            return message;

        return GetStartMessageWithCSharp(projectRoot);
    }

    internal static string GetMissingProjectFileMessage()
    {
        if (TryGetPublishMessage(bindings => bindings.PublishMissingProjectFileMessage(), out var message))
            return message;

        return GetMissingProjectFileMessageWithCSharp();
    }

    internal static string GetSuccessMessage()
    {
        if (TryGetPublishMessage(bindings => bindings.PublishSuccessMessage(), out var message))
            return message;

        return GetSuccessMessageWithCSharp();
    }

    private static bool TryGetPublishMessage(Func<Bindings, string> getMessage, out string message)
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish help text routes through CliPublishHelpText.
    private static string GetHelpTextWithCSharp()
        => "N# Publish\n"
           + "\n"
           + "Usage: nlc publish [options]\n"
           + "\n"
           + "Package the project for distribution.\n"
           + "\n"
           + "Options:\n"
           + "  --project <dir>         Project root directory (default: current directory)\n"
           + "  --backend <mode>        Compilation backend: il\n"
           + "  --configuration <cfg>   Build configuration (default: Release)\n"
           + "  --output <dir>          Output directory for published files\n"
           + "  --runtime <rid>         Current host runtime only; adds a framework-dependent launcher\n"
           + "  --self-contained        Planned; currently exits with guidance\n"
           + "  --aot                   Analysis-only: verify Native AOT safety and annotate public APIs\n"
           + "  --help, -h              Show this help text\n"
           + "\n"
           + "Supported publish shapes:\n"
           + "  - Portable framework-dependent: nlc publish --output ./dist\n"
           + "  - Current-runtime launcher: nlc publish --runtime <current-rid>\n"
           + "\n"
           + "Native AOT (--aot):\n"
           + "  Analysis-only this release. Fails the publish on any AOT blocker (reflection,\n"
           + "  dynamic code, runtime generics, expression trees) and stamps public APIs with\n"
           + "  [RequiresUnreferencedCode]/[RequiresDynamicCode]. It does NOT emit a native image yet.\n"
           + "\n"
           + "Unsupported today:\n"
           + "  - Cross-runtime publishing, e.g. publishing linux-x64 from osx-arm64\n"
           + "  - Self-contained apphost/runtime bundles\n"
           + "  - Native AOT image generation\n"
           + "\n"
           + "Examples:\n"
           + "  nlc publish\n"
           + "  nlc publish --backend il --output ./dist\n"
           + "  nlc publish --configuration Release\n"
           + "  nlc publish --runtime <current-rid> --output ./dist\n"
           + "  nlc publish --aot\n"
           + "  nlc publish --output ./dist\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Publish succeeded\n"
           + "  1  Publish failed";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish status messages route through CliPublish*Message kernels.
    private static string GetAotAnalysisOnlyNoticeWithCSharp()
        => "nlc publish --aot is analysis-only in this release: it verifies your project is Native AOT-safe " +
           "(failing on any AOT blocker) and stamps [RequiresUnreferencedCode]/[RequiresDynamicCode] on public APIs, " +
           "but it does NOT produce a native image yet. The output is the usual framework-dependent assembly.";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish unsupported-shape messages route through CliPublish*Message kernels.
    private static string GetSelfContainedUnsupportedMessageWithCSharp()
        => "Self-contained publish is not available in nlc publish yet. " +
           "Today nlc publish produces framework-dependent artifacts. " +
           "Omit --self-contained, or use dotnet publish with an MSBuild compatibility project when you need a true apphost/self-contained bundle.";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish unsupported-shape messages route through CliPublish*Message kernels.
    private static string GetCrossRuntimeUnsupportedMessageWithCSharp(string requestedRuntime, string currentRuntime)
        => $"Cross-runtime publish is not available in nlc publish yet. Requested runtime '{requestedRuntime}', but this machine is '{currentRuntime}'. " +
           "Today --runtime only supports the current host runtime to add a framework-dependent launcher. " +
           "Omit --runtime for portable 'dotnet <app>.dll' output, or run nlc publish on the target runtime.";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish failure messages route through CliPublish*FailureMessage kernels.
    private static string GetBuildFailureMessageWithCSharp(bool aotMode)
        => aotMode
            ? "Publish failed: Native AOT blockers were found (see the diagnostics above). Fix them, then publish again."
            : "Publish failed";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish failure messages route through CliPublish*FailureMessage kernels.
    private static string GetExceptionFailureMessageWithCSharp(string exceptionMessage)
        => $"Publish failed: {exceptionMessage}";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish status messages route through CliPublish*Message kernels.
    private static string GetStartMessageWithCSharp(string projectRoot)
        => $"Publishing project in {projectRoot}...";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish status messages route through CliPublish*Message kernels.
    private static string GetMissingProjectFileMessageWithCSharp()
        => "No project.yml found in current directory. Run 'nlc new <name>' to create a project.";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish status messages route through CliPublish*Message kernels.
    private static string GetSuccessMessageWithCSharp()
        => "Publish successful!";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product publish validation messages route through CliPublishValidationErrorMessage.
    private static string? GetValidationErrorWithCSharp(string[] args, int code, int errorArgIndex)
    {
        if (code == 2)
        {
            return "Target-platform publishing is expressed as --runtime <rid>, and nlc publish does not support cross-runtime publishing yet.";
        }

        if (errorArgIndex < 0 || errorArgIndex >= args.Length)
            return null;

        return code switch
        {
            1 => $"Option '{args[errorArgIndex]}' requires a value.",
            3 => $"Unknown publish option '{args[errorArgIndex]}'. Run 'nlc publish --help' for supported options.",
            4 => $"Unexpected publish argument '{args[errorArgIndex]}'. Run 'nlc publish --help' for usage.",
            _ => null
        };
    }

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
}
