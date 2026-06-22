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

internal enum CheckOutputModeKind
{
    InvalidSystemsReportText = -1,
    Json = 1,
    Text = 2,
    SystemsReportJson = 3
}

internal static class CheckCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out CheckArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[7];
        try
        {
            var code = bindings.CheckArgumentSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var backendOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var positionalProject))
            {
                summary = default;
                return false;
            }

            summary = new CheckArgumentSummary(
                projectOption,
                backendOption,
                positionalProject,
                resultIndices[3] != 0,
                resultIndices[4] != 0,
                resultIndices[5] != 0,
                resultIndices[6] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetEffectiveOutputMode(
        bool useText,
        bool systemsReport,
        out CheckOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.CheckEffectiveOutputMode(useText ? 1 : 0, systemsReport ? 1 : 0);
            if (result != -1 && result != 1 && result != 2 && result != 3)
                return false;

            outputMode = (CheckOutputModeKind)result;
            return true;
        }
        catch
        {
            outputMode = default;
            return false;
        }
    }

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
