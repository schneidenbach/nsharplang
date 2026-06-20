using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct DoctorOptionSummary(
    bool Json,
    bool RequireVscode,
    bool SkipVscode,
    bool ShowHelp);

internal enum DoctorOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class DoctorCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out DoctorOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[4];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            summary = new DoctorOptionSummary(
                resultIndices[0] != 0,
                resultIndices[1] != 0,
                resultIndices[2] != 0,
                resultIndices[3] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetOutputMode(bool json, out DoctorOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.OutputMode(json ? 1 : 0);
            if (code is < 1 or > 2)
                return false;

            outputMode = (DoctorOutputModeKind)code;
            return true;
        }
        catch
        {
            outputMode = default;
            return false;
        }
    }

    internal static string GetHelpText()
    {
        if (TryGetMessage(bindings => bindings.DoctorHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetDotnetNotFoundMessage()
    {
        if (TryGetMessage(bindings => bindings.DoctorDotnetNotFoundMessage(), out var message))
            return message;

        return GetDotnetNotFoundMessageWithCSharp();
    }

    internal static string GetDotnetVersionFailedMessage()
    {
        if (TryGetMessage(bindings => bindings.DoctorDotnetVersionFailedMessage(), out var message))
            return message;

        return GetDotnetVersionFailedMessageWithCSharp();
    }

    internal static string GetNlcCommandMissingMessage()
    {
        if (TryGetMessage(bindings => bindings.DoctorNlcCommandMissingMessage(), out var message))
            return message;

        return GetNlcCommandMissingMessageWithCSharp();
    }

    internal static string GetPackageCacheMissingMessage(string packageCache)
    {
        if (TryGetMessage(bindings => bindings.DoctorPackageCacheMissingMessage(packageCache), out var message))
            return message;

        return GetPackageCacheMissingMessageWithCSharp(packageCache);
    }

    internal static string GetTemplateInstalledMessage()
    {
        if (TryGetMessage(bindings => bindings.DoctorTemplateInstalledMessage(), out var message))
            return message;

        return GetTemplateInstalledMessageWithCSharp();
    }

    internal static string GetTemplatesMissingMessage()
    {
        if (TryGetMessage(bindings => bindings.DoctorTemplatesMissingMessage(), out var message))
            return message;

        return GetTemplatesMissingMessageWithCSharp();
    }

    internal static string GetLanguageServerMissingMessage()
    {
        if (TryGetMessage(bindings => bindings.DoctorLanguageServerMissingMessage(), out var message))
            return message;

        return GetLanguageServerMissingMessageWithCSharp();
    }

    internal static string GetVscodeSkippedMessage()
    {
        if (TryGetMessage(bindings => bindings.DoctorVscodeSkippedMessage(), out var message))
            return message;

        return GetVscodeSkippedMessageWithCSharp();
    }

    internal static string GetVscodeRequiredMissingMessage()
    {
        if (TryGetMessage(bindings => bindings.DoctorVscodeRequiredMissingMessage(), out var message))
            return message;

        return GetVscodeRequiredMissingMessageWithCSharp();
    }

    internal static string GetVscodeOptionalMissingMessage()
    {
        if (TryGetMessage(bindings => bindings.DoctorVscodeOptionalMissingMessage(), out var message))
            return message;

        return GetVscodeOptionalMissingMessageWithCSharp();
    }

    internal static string GetVscodeExtensionMissingMessage(string extensionId)
    {
        if (TryGetMessage(bindings => bindings.DoctorVscodeExtensionMissingMessage(extensionId), out var message))
            return message;

        return GetVscodeExtensionMissingMessageWithCSharp(extensionId);
    }

    internal static string GetTextHeader()
    {
        if (TryGetMessage(bindings => bindings.DoctorTextHeader(), out var message))
            return message;

        return GetTextHeaderWithCSharp();
    }

    internal static string GetStatusLine(bool ok)
    {
        if (TryGetMessage(bindings => bindings.DoctorStatusLine(ok ? 1 : 0), out var message))
            return message;

        return GetStatusLineWithCSharp(ok);
    }

    internal static string GetCheckMarker(string status)
    {
        if (TryGetMessage(bindings => bindings.DoctorCheckMarker(status), out var message))
            return message;

        return GetCheckMarkerWithCSharp(status);
    }

    internal static string GetCheckLine(string marker, string name, string detail)
    {
        if (TryGetMessage(bindings => bindings.DoctorCheckLine(marker, name, detail), out var message))
            return message;

        return GetCheckLineWithCSharp(marker, name, detail);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product doctor command messages route through CliDoctor* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Doctor\n"
           + "\n"
           + "Usage: nlc doctor [options]\n"
           + "\n"
           + "Verifies the public N# install path: dotnet, nlc, local N# packages, templates,\n"
           + "language server, and the VS Code extension when the VS Code 'code' CLI is available.\n"
           + "\n"
           + "Options:\n"
           + "  --json              Output as JSON envelope\n"
           + "  --require-vscode    Treat missing VS Code or missing N# extension as a failure\n"
           + "  --skip-vscode       Skip VS Code extension probing\n"
           + "  --help, -h          Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc doctor\n"
           + "  nlc doctor --require-vscode\n"
           + "  nlc doctor --json --skip-vscode\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Required checks passed\n"
           + "  1  One or more required checks failed";

    private static string GetDotnetNotFoundMessageWithCSharp()
        => "dotnet CLI was not found on PATH";

    private static string GetDotnetVersionFailedMessageWithCSharp()
        => "dotnet --version failed";

    private static string GetNlcCommandMissingMessageWithCSharp()
        => "nlc is running, but no nlc command was found on PATH; source ~/.nsharp/env or use your package manager shell integration";

    private static string GetPackageCacheMissingMessageWithCSharp(string packageCache)
        => $"N# package cache was not found at {packageCache}; rerun the N# installer";

    private static string GetTemplateInstalledMessageWithCSharp()
        => "nsharp-console template is installed";

    private static string GetTemplatesMissingMessageWithCSharp()
        => "nsharp-console template was not found; run the N# installer or dotnet new install NSharpLang.Templates";

    private static string GetLanguageServerMissingMessageWithCSharp()
        => "nsharp-lsp was not found on PATH; source ~/.nsharp/env or reinstall N#";

    private static string GetVscodeSkippedMessageWithCSharp()
        => "skipped by --skip-vscode";

    private static string GetVscodeRequiredMissingMessageWithCSharp()
        => "VS Code 'code' CLI was not found on PATH";

    private static string GetVscodeOptionalMissingMessageWithCSharp()
        => "VS Code 'code' CLI was not found; install VS Code or rerun with --require-vscode on developer machines";

    private static string GetVscodeExtensionMissingMessageWithCSharp(string extensionId)
        => $"{extensionId} is not installed; run code --install-extension {extensionId}";

    private static string GetTextHeaderWithCSharp()
        => "N# doctor";

    private static string GetStatusLineWithCSharp(bool ok)
        => ok ? "status: ok" : "status: problems found";

    private static string GetCheckMarkerWithCSharp(string status)
        => status switch { "pass" => "✓", "warn" => "!", _ => "x" };

    private static string GetCheckLineWithCSharp(string marker, string name, string detail)
        => $"{marker} {name}: {detail}";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliDoctorOptionSummaryInto>(
                programType,
                "CliDoctorOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorOutputMode>(
                programType,
                "CliDoctorOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorHelpText>(
                programType,
                "CliDoctorHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorDotnetNotFoundMessage>(
                programType,
                "CliDoctorDotnetNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorDotnetVersionFailedMessage>(
                programType,
                "CliDoctorDotnetVersionFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorNlcCommandMissingMessage>(
                programType,
                "CliDoctorNlcCommandMissingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorPackageCacheMissingMessage>(
                programType,
                "CliDoctorPackageCacheMissingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorTemplateInstalledMessage>(
                programType,
                "CliDoctorTemplateInstalledMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorTemplatesMissingMessage>(
                programType,
                "CliDoctorTemplatesMissingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorLanguageServerMissingMessage>(
                programType,
                "CliDoctorLanguageServerMissingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorVscodeSkippedMessage>(
                programType,
                "CliDoctorVscodeSkippedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorVscodeRequiredMissingMessage>(
                programType,
                "CliDoctorVscodeRequiredMissingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorVscodeOptionalMissingMessage>(
                programType,
                "CliDoctorVscodeOptionalMissingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorVscodeExtensionMissingMessage>(
                programType,
                "CliDoctorVscodeExtensionMissingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorTextHeader>(
                programType,
                "CliDoctorTextHeader"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorStatusLine>(
                programType,
                "CliDoctorStatusLine"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorCheckMarker>(
                programType,
                "CliDoctorCheckMarker"),
            DogfoodKernelLoader.CreateDelegate<CliDoctorCheckLine>(
                programType,
                "CliDoctorCheckLine")));

    private delegate int CliDoctorOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliDoctorOutputMode(int json);

    private delegate string CliDoctorHelpText();
    private delegate string CliDoctorDotnetNotFoundMessage();
    private delegate string CliDoctorDotnetVersionFailedMessage();
    private delegate string CliDoctorNlcCommandMissingMessage();
    private delegate string CliDoctorPackageCacheMissingMessage(string packageCache);
    private delegate string CliDoctorTemplateInstalledMessage();
    private delegate string CliDoctorTemplatesMissingMessage();
    private delegate string CliDoctorLanguageServerMissingMessage();
    private delegate string CliDoctorVscodeSkippedMessage();
    private delegate string CliDoctorVscodeRequiredMissingMessage();
    private delegate string CliDoctorVscodeOptionalMissingMessage();
    private delegate string CliDoctorVscodeExtensionMissingMessage(string extensionId);
    private delegate string CliDoctorTextHeader();
    private delegate string CliDoctorStatusLine(int ok);
    private delegate string CliDoctorCheckMarker(string status);
    private delegate string CliDoctorCheckLine(string marker, string name, string detail);

    private sealed record Bindings(
        CliDoctorOptionSummaryInto OptionSummary,
        CliDoctorOutputMode OutputMode,
        CliDoctorHelpText DoctorHelpText,
        CliDoctorDotnetNotFoundMessage DoctorDotnetNotFoundMessage,
        CliDoctorDotnetVersionFailedMessage DoctorDotnetVersionFailedMessage,
        CliDoctorNlcCommandMissingMessage DoctorNlcCommandMissingMessage,
        CliDoctorPackageCacheMissingMessage DoctorPackageCacheMissingMessage,
        CliDoctorTemplateInstalledMessage DoctorTemplateInstalledMessage,
        CliDoctorTemplatesMissingMessage DoctorTemplatesMissingMessage,
        CliDoctorLanguageServerMissingMessage DoctorLanguageServerMissingMessage,
        CliDoctorVscodeSkippedMessage DoctorVscodeSkippedMessage,
        CliDoctorVscodeRequiredMissingMessage DoctorVscodeRequiredMissingMessage,
        CliDoctorVscodeOptionalMissingMessage DoctorVscodeOptionalMissingMessage,
        CliDoctorVscodeExtensionMissingMessage DoctorVscodeExtensionMissingMessage,
        CliDoctorTextHeader DoctorTextHeader,
        CliDoctorStatusLine DoctorStatusLine,
        CliDoctorCheckMarker DoctorCheckMarker,
        CliDoctorCheckLine DoctorCheckLine);
}
