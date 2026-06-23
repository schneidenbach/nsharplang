using System;
using System.Globalization;

namespace NSharpLang.Cli.Commands;

internal readonly record struct CheckArgumentSummary(
    string? ProjectOption,
    string? BackendOption,
    string? PositionalProject,
    bool UseText,
    bool Aot,
    bool SystemsReport,
    bool ShowHelp);

internal static class CheckCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static CheckArgumentSummary GetArgumentSummary(string[] args)
    {
        var resultIndices = t_resultIndices ??= new int[7];
        var code = RequiredBindings.CheckArgumentSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# check argument parser kernel rejected the arguments.");

        var projectOption = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        var backendOption = resultIndices[1] == -1 ? null : args[resultIndices[1]];
        var positionalProject = resultIndices[2] == -1 ? null : args[resultIndices[2]];
        return new CheckArgumentSummary(
            projectOption,
            backendOption,
            positionalProject,
            resultIndices[3] != 0,
            resultIndices[4] != 0,
            resultIndices[5] != 0,
            resultIndices[6] != 0);
    }

    internal static int GetEffectiveOutputMode(
        bool useText,
        bool systemsReport)
        => RequiredBindings.CheckEffectiveOutputMode(useText ? 1 : 0, systemsReport ? 1 : 0);

    internal static string GetHelpText()
        => RequiredBindings.HelpText();

    internal static string GetProjectDirectoryNotFoundMessage(string projectDir)
        => RequiredBindings.ProjectDirectoryNotFoundMessage(projectDir);

    internal static string GetSystemsReportTextUnavailableMessage()
        => RequiredBindings.SystemsReportTextUnavailableMessage();

    internal static string GetNoErrorsMessage(int fileCount, string elapsedText)
    {
        var fileCountText = fileCount.ToString(CultureInfo.InvariantCulture);
        return RequiredBindings.NoErrorsMessage(fileCountText, fileCount, elapsedText);
    }

    internal static string GetCheckedInMessage(string elapsedText)
        => RequiredBindings.ElapsedMessage(elapsedText);

    internal static string GetFailedElapsedMessage(string elapsedText)
        => RequiredBindings.FailedElapsedMessage(elapsedText);

    internal static string GetFailedMessage(string message)
        => RequiredBindings.FailedMessage(message);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliCheckArgumentSummaryInto>(
                programType,
                "CliCheckArgumentSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliCheckEffectiveOutputMode>(
                programType,
                "CliCheckEffectiveOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliCheckHelpText>(
                programType,
                "CliCheckHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliCheckProjectDirectoryNotFoundMessage>(
                programType,
                "CliCheckProjectDirectoryNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliCheckSystemsReportTextUnavailableMessage>(
                programType,
                "CliCheckSystemsReportTextUnavailableMessage"),
            DogfoodKernelLoader.CreateDelegate<CliCheckNoErrorsMessage>(
                programType,
                "CliCheckNoErrorsMessage"),
            DogfoodKernelLoader.CreateDelegate<CliCheckElapsedMessage>(
                programType,
                "CliCheckElapsedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliCheckFailedElapsedMessage>(
                programType,
                "CliCheckFailedElapsedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliCheckFailedMessage>(
                programType,
                "CliCheckFailedMessage")));

    private delegate int CliCheckArgumentSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliCheckEffectiveOutputMode(int useText, int systemsReport);

    private delegate string CliCheckHelpText();

    private delegate string CliCheckProjectDirectoryNotFoundMessage(string projectDir);

    private delegate string CliCheckSystemsReportTextUnavailableMessage();

    private delegate string CliCheckNoErrorsMessage(string fileCountText, int fileCount, string elapsedText);

    private delegate string CliCheckElapsedMessage(string elapsedText);

    private delegate string CliCheckFailedElapsedMessage(string elapsedText);

    private delegate string CliCheckFailedMessage(string message);

    private sealed record Bindings(
        CliCheckArgumentSummaryInto CheckArgumentSummary,
        CliCheckEffectiveOutputMode CheckEffectiveOutputMode,
        CliCheckHelpText HelpText,
        CliCheckProjectDirectoryNotFoundMessage ProjectDirectoryNotFoundMessage,
        CliCheckSystemsReportTextUnavailableMessage SystemsReportTextUnavailableMessage,
        CliCheckNoErrorsMessage NoErrorsMessage,
        CliCheckElapsedMessage ElapsedMessage,
        CliCheckFailedElapsedMessage FailedElapsedMessage,
        CliCheckFailedMessage FailedMessage);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# check command kernels are unavailable.");
}
