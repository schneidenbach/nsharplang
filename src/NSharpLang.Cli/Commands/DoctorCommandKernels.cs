using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct DoctorOptionSummary(
    bool Json,
    bool RequireVscode,
    bool SkipVscode,
    bool ShowHelp);

internal static class DoctorCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static DoctorOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[4];
        var code = RequiredBindings.OptionSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# doctor option parser kernel rejected the arguments.");

        return new DoctorOptionSummary(
            resultIndices[0] != 0,
            resultIndices[1] != 0,
            resultIndices[2] != 0,
            resultIndices[3] != 0);
    }

    internal static int GetOutputMode(bool json)
        => RequiredBindings.OutputMode(json ? 1 : 0);

    internal static string GetHelpText()
        => RequiredBindings.DoctorHelpText();

    internal static string GetDotnetNotFoundMessage()
        => RequiredBindings.DoctorDotnetNotFoundMessage();

    internal static string GetDotnetVersionFailedMessage()
        => RequiredBindings.DoctorDotnetVersionFailedMessage();

    internal static string GetNlcCommandMissingMessage()
        => RequiredBindings.DoctorNlcCommandMissingMessage();

    internal static string GetPackageCacheMissingMessage(string packageCache)
        => RequiredBindings.DoctorPackageCacheMissingMessage(packageCache);

    internal static string GetTemplateInstalledMessage()
        => RequiredBindings.DoctorTemplateInstalledMessage();

    internal static string GetTemplatesMissingMessage()
        => RequiredBindings.DoctorTemplatesMissingMessage();

    internal static string GetLanguageServerMissingMessage()
        => RequiredBindings.DoctorLanguageServerMissingMessage();

    internal static string GetVscodeSkippedMessage()
        => RequiredBindings.DoctorVscodeSkippedMessage();

    internal static string GetVscodeRequiredMissingMessage()
        => RequiredBindings.DoctorVscodeRequiredMissingMessage();

    internal static string GetVscodeOptionalMissingMessage()
        => RequiredBindings.DoctorVscodeOptionalMissingMessage();

    internal static string GetVscodeExtensionMissingMessage(string extensionId)
        => RequiredBindings.DoctorVscodeExtensionMissingMessage(extensionId);

    internal static string GetTextHeader()
        => RequiredBindings.DoctorTextHeader();

    internal static string GetStatusLine(bool ok)
        => RequiredBindings.DoctorStatusLine(ok ? 1 : 0);

    internal static string GetCheckMarker(string status)
        => RequiredBindings.DoctorCheckMarker(status);

    internal static string GetCheckLine(string marker, string name, string detail)
        => RequiredBindings.DoctorCheckLine(marker, name, detail);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# doctor command kernels are unavailable.");

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
