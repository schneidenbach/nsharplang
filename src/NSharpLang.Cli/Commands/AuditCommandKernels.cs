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

    internal static AuditOutputModeKind GetOutputMode(bool json)
    {
        var code = RequiredBindings.OutputMode(json ? 1 : 0);
        if (code is < 1 or > 2)
            throw new InvalidOperationException("N# audit output mode kernel rejected the value.");

        return (AuditOutputModeKind)code;
    }

    internal static string GetHelpText()
        => RequiredBindings.AuditHelpText();

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
        => RequiredBindings.AuditProjectDirectoryNotFoundMessage(projectRoot);

    internal static string GetNoCsprojFileMessage()
        => RequiredBindings.AuditNoCsprojFileMessage();

    internal static string GetVulnerableFlagUnsupportedMessage()
        => RequiredBindings.AuditVulnerableFlagUnsupportedMessage();

    internal static string GetFailedMessage(string message)
        => RequiredBindings.AuditFailedMessage(message);

    internal static string GetNoKnownVulnerabilitiesMessage()
        => RequiredBindings.AuditNoKnownVulnerabilitiesMessage();

    internal static string GetVulnerabilitySummaryMessage(int vulnerabilityCount)
        => RequiredBindings.AuditVulnerabilitySummaryMessage(vulnerabilityCount.ToString(), vulnerabilityCount);

    internal static string GetVulnerabilityLine(string severity, string packageId, string version)
        => RequiredBindings.AuditVulnerabilityLine(severity, packageId, version);

    internal static string GetVulnerabilityUrlLine(string url)
        => RequiredBindings.AuditVulnerabilityUrlLine(url);

    internal static string GetParseFailureMessage()
        => RequiredBindings.AuditParseFailureMessage();

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# audit command kernels are unavailable.");

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
