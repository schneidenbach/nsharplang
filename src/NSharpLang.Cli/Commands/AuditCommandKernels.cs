using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct AuditOptionSummary(
    string? ProjectOption,
    bool Json,
    bool ShowHelp);

internal enum AuditOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class AuditCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out AuditOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[3];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption))
            {
                summary = default;
                return false;
            }

            summary = new AuditOptionSummary(
                projectOption,
                resultIndices[1] != 0,
                resultIndices[2] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetOutputMode(bool json, out AuditOutputModeKind outputMode)
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

            outputMode = (AuditOutputModeKind)code;
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
        if (TryGetMessage(bindings => bindings.AuditHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
    {
        if (TryGetMessage(bindings => bindings.AuditProjectDirectoryNotFoundMessage(projectRoot), out var message))
            return message;

        return GetProjectDirectoryNotFoundMessageWithCSharp(projectRoot);
    }

    internal static string GetNoCsprojFileMessage()
    {
        if (TryGetMessage(bindings => bindings.AuditNoCsprojFileMessage(), out var message))
            return message;

        return GetNoCsprojFileMessageWithCSharp();
    }

    internal static string GetVulnerableFlagUnsupportedMessage()
    {
        if (TryGetMessage(bindings => bindings.AuditVulnerableFlagUnsupportedMessage(), out var message))
            return message;

        return GetVulnerableFlagUnsupportedMessageWithCSharp();
    }

    internal static string GetFailedMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.AuditFailedMessage(message), out var result))
            return result;

        return GetFailedMessageWithCSharp(message);
    }

    internal static string GetNoKnownVulnerabilitiesMessage()
    {
        if (TryGetMessage(bindings => bindings.AuditNoKnownVulnerabilitiesMessage(), out var message))
            return message;

        return GetNoKnownVulnerabilitiesMessageWithCSharp();
    }

    internal static string GetVulnerabilitySummaryMessage(int vulnerabilityCount)
    {
        var countText = vulnerabilityCount.ToString();
        if (TryGetMessage(
                bindings => bindings.AuditVulnerabilitySummaryMessage(countText, vulnerabilityCount),
                out var message))
            return message;

        return GetVulnerabilitySummaryMessageWithCSharp(vulnerabilityCount);
    }

    internal static string GetVulnerabilityLine(string severity, string packageId, string version)
    {
        if (TryGetMessage(bindings => bindings.AuditVulnerabilityLine(severity, packageId, version), out var message))
            return message;

        return GetVulnerabilityLineWithCSharp(severity, packageId, version);
    }

    internal static string GetVulnerabilityUrlLine(string url)
    {
        if (TryGetMessage(bindings => bindings.AuditVulnerabilityUrlLine(url), out var message))
            return message;

        return GetVulnerabilityUrlLineWithCSharp(url);
    }

    internal static string GetParseFailureMessage()
    {
        if (TryGetMessage(bindings => bindings.AuditParseFailureMessage(), out var message))
            return message;

        return GetParseFailureMessageWithCSharp();
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product audit command messages route through CliAudit* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Security Audit\n"
           + "\n"
           + "Usage: nlc audit [options]\n"
           + "\n"
           + "Check dependencies for known security vulnerabilities.\n"
           + "\n"
           + "Options:\n"
           + "  --project <dir>   Project root directory (default: current directory)\n"
           + "  --json            Output as JSON envelope\n"
           + "  --help, -h        Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc audit\n"
           + "  nlc audit --json\n"
           + "  nlc audit --project examples/14-minimal-api\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  No vulnerabilities found\n"
           + "  1  Vulnerabilities found or audit failed";

    private static string GetProjectDirectoryNotFoundMessageWithCSharp(string projectRoot)
        => $"Project directory not found: {projectRoot}";

    private static string GetNoCsprojFileMessageWithCSharp()
        => "No .csproj file found. Run 'nlc init' to create one.";

    private static string GetVulnerableFlagUnsupportedMessageWithCSharp()
        => "The --vulnerable flag requires .NET SDK 8.0 or later.";

    private static string GetFailedMessageWithCSharp(string message)
        => $"Audit failed: {message}";

    private static string GetNoKnownVulnerabilitiesMessageWithCSharp()
        => "No known vulnerabilities found.";

    private static string GetVulnerabilitySummaryMessageWithCSharp(int vulnerabilityCount)
        => $"{vulnerabilityCount} vulnerabilit{(vulnerabilityCount == 1 ? "y" : "ies")} found:";

    private static string GetVulnerabilityLineWithCSharp(string severity, string packageId, string version)
        => $"  {severity}: {packageId}@{version}";

    private static string GetVulnerabilityUrlLineWithCSharp(string url)
        => $"    {url}";

    private static string GetParseFailureMessageWithCSharp()
        => "  (could not parse vulnerability details)";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliAuditOptionSummaryInto>(
                programType,
                "CliAuditOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliAuditOutputMode>(
                programType,
                "CliAuditOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliAuditHelpText>(
                programType,
                "CliAuditHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliAuditProjectDirectoryNotFoundMessage>(
                programType,
                "CliAuditProjectDirectoryNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAuditNoCsprojFileMessage>(
                programType,
                "CliAuditNoCsprojFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAuditVulnerableFlagUnsupportedMessage>(
                programType,
                "CliAuditVulnerableFlagUnsupportedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAuditFailedMessage>(
                programType,
                "CliAuditFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAuditNoKnownVulnerabilitiesMessage>(
                programType,
                "CliAuditNoKnownVulnerabilitiesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAuditVulnerabilitySummaryMessage>(
                programType,
                "CliAuditVulnerabilitySummaryMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAuditVulnerabilityLine>(
                programType,
                "CliAuditVulnerabilityLine"),
            DogfoodKernelLoader.CreateDelegate<CliAuditVulnerabilityUrlLine>(
                programType,
                "CliAuditVulnerabilityUrlLine"),
            DogfoodKernelLoader.CreateDelegate<CliAuditParseFailureMessage>(
                programType,
                "CliAuditParseFailureMessage")));

    private delegate int CliAuditOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliAuditOutputMode(int json);

    private delegate string CliAuditHelpText();
    private delegate string CliAuditProjectDirectoryNotFoundMessage(string projectRoot);
    private delegate string CliAuditNoCsprojFileMessage();
    private delegate string CliAuditVulnerableFlagUnsupportedMessage();
    private delegate string CliAuditFailedMessage(string message);
    private delegate string CliAuditNoKnownVulnerabilitiesMessage();
    private delegate string CliAuditVulnerabilitySummaryMessage(string countText, int vulnerabilityCount);
    private delegate string CliAuditVulnerabilityLine(string severity, string packageId, string version);
    private delegate string CliAuditVulnerabilityUrlLine(string url);
    private delegate string CliAuditParseFailureMessage();

    private sealed record Bindings(
        CliAuditOptionSummaryInto OptionSummary,
        CliAuditOutputMode OutputMode,
        CliAuditHelpText AuditHelpText,
        CliAuditProjectDirectoryNotFoundMessage AuditProjectDirectoryNotFoundMessage,
        CliAuditNoCsprojFileMessage AuditNoCsprojFileMessage,
        CliAuditVulnerableFlagUnsupportedMessage AuditVulnerableFlagUnsupportedMessage,
        CliAuditFailedMessage AuditFailedMessage,
        CliAuditNoKnownVulnerabilitiesMessage AuditNoKnownVulnerabilitiesMessage,
        CliAuditVulnerabilitySummaryMessage AuditVulnerabilitySummaryMessage,
        CliAuditVulnerabilityLine AuditVulnerabilityLine,
        CliAuditVulnerabilityUrlLine AuditVulnerabilityUrlLine,
        CliAuditParseFailureMessage AuditParseFailureMessage);

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
