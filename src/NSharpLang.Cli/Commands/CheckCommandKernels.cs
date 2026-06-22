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
        => TryGetMessage(bindings => bindings.HelpText(), out var message)
            ? message
            : FallbackHelpText();

    internal static string GetProjectDirectoryNotFoundMessage(string projectDir)
        => TryGetMessage(bindings => bindings.ProjectDirectoryNotFoundMessage(projectDir), out var message)
            ? message
            : FallbackProjectDirectoryNotFoundMessage(projectDir);

    internal static string GetSystemsReportTextUnavailableMessage()
        => TryGetMessage(bindings => bindings.SystemsReportTextUnavailableMessage(), out var message)
            ? message
            : FallbackSystemsReportTextUnavailableMessage();

    internal static string GetNoErrorsMessage(int fileCount, string elapsedText)
    {
        var fileCountText = fileCount.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(bindings => bindings.NoErrorsMessage(fileCountText, fileCount, elapsedText), out var message)
            ? message
            : FallbackNoErrorsMessage(fileCountText, fileCount, elapsedText);
    }

    internal static string GetCheckedInMessage(string elapsedText)
        => TryGetMessage(bindings => bindings.ElapsedMessage(elapsedText), out var message)
            ? message
            : FallbackCheckedInMessage(elapsedText);

    internal static string GetFailedElapsedMessage(string elapsedText)
        => TryGetMessage(bindings => bindings.FailedElapsedMessage(elapsedText), out var message)
            ? message
            : FallbackFailedElapsedMessage(elapsedText);

    internal static string GetFailedMessage(string message)
        => TryGetMessage(bindings => bindings.FailedMessage(message), out var result)
            ? result
            : FallbackFailedMessage(message);

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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product check messages route through CliCheck* kernels.
    private static string FallbackHelpText()
        => "N# Type Check\n"
           + "\n"
           + "Usage: nlc check [options] [project-dir]\n"
           + "\n"
           + "Verifies your N# project compiles without errors. Runs semantic analysis,\n"
           + "linting, and IL backend verification.\n"
           + "\n"
           + "Options:\n"
           + "  --backend <mode>  Compilation backend: il\n"
           + "  --json        Output as JSON (default)\n"
           + "  --text        Output as human-readable diagnostics\n"
           + "  --aot         Report Native AOT blockers as errors\n"
           + "  --systems-report\n"
           + "                Output the versioned Systems N# effect/policy report as JSON\n"
           + "  --project     Project root directory (default: current directory)\n"
           + "  --help, -h    Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc check\n"
           + "  nlc check --backend il\n"
           + "  nlc check --text\n"
           + "  nlc check --aot\n"
           + "  nlc check --project examples/16-task-cli\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  No errors found\n"
           + "  1  One or more errors detected";

    private static string FallbackProjectDirectoryNotFoundMessage(string projectDir)
        => $"Directory not found: {projectDir}";

    private static string FallbackSystemsReportTextUnavailableMessage()
        => "--systems-report is only available as JSON output.";

    private static string FallbackNoErrorsMessage(string fileCountText, int fileCount, string elapsedText)
    {
        var suffix = fileCount == 1 ? string.Empty : "s";
        return $"  Checked {fileCountText} file{suffix} — no errors. [{elapsedText}]";
    }

    private static string FallbackCheckedInMessage(string elapsedText)
        => $"  Checked in {elapsedText}";

    private static string FallbackFailedElapsedMessage(string elapsedText)
        => $"  Check failed in {elapsedText}";

    private static string FallbackFailedMessage(string message)
        => $"Check failed: {message}";

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
