using System;
using System.Globalization;

namespace NSharpLang.Cli.Commands;

internal readonly record struct LintOptionSummary(
    string? ProjectOption,
    bool UseText,
    bool UseJson,
    bool ShowHelp);

internal enum LintOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class LintCommandKernels
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    [ThreadStatic]
    private static int[]? t_optionResultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out LintOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionResultIndices ??= new int[4];
        try
        {
            var code = bindings.LintOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption))
            {
                summary = default;
                return false;
            }

            summary = new LintOptionSummary(
                projectOption,
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

    internal static bool TryGetFileArgs(string[] args, out string[] files)
    {
        files = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            var count = bindings.LintFileArgIndices(
                args,
                scratch.ProjectValueIndices,
                scratch.ResultIndices);

            if (count < 0 || count > args.Length)
                return false;

            if (count == 0)
                return true;

            files = new string[count];
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= args.Length)
                {
                    files = Array.Empty<string>();
                    return false;
                }

                files[i] = args[sourceIndex];
            }

            return true;
        }
        catch
        {
            files = Array.Empty<string>();
            return false;
        }
    }

    internal static bool TryGetEffectiveOutputMode(
        bool useText,
        bool useJson,
        out LintOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.LintEffectiveOutputMode(useText ? 1 : 0, useJson ? 1 : 0);
            if (result is < 1 or > 2)
                return false;

            outputMode = (LintOutputModeKind)result;
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

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
        => TryGetMessage(bindings => bindings.ProjectDirectoryNotFoundMessage(projectRoot), out var message)
            ? message
            : FallbackProjectDirectoryNotFoundMessage(projectRoot);

    internal static string GetNoFilesFoundMessage()
        => TryGetMessage(bindings => bindings.NoFilesFoundMessage(), out var message)
            ? message
            : FallbackNoFilesFoundMessage();

    internal static string GetFileNotFoundMessage(string sourceFile)
        => TryGetMessage(bindings => bindings.FileNotFoundMessage(sourceFile), out var message)
            ? message
            : FallbackFileNotFoundMessage(sourceFile);

    internal static string GetParseErrorsMessage(string sourceFile, string messages)
        => TryGetMessage(bindings => bindings.ParseErrorsMessage(sourceFile, messages), out var message)
            ? message
            : FallbackParseErrorsMessage(sourceFile, messages);

    internal static string GetErrorLintingDiagnosticMessage(string exceptionMessage)
        => TryGetMessage(bindings => bindings.ErrorLintingDiagnosticMessage(exceptionMessage), out var message)
            ? message
            : FallbackErrorLintingDiagnosticMessage(exceptionMessage);

    internal static string GetErrorLintingFileMessage(string sourceFile, string exceptionMessage)
        => TryGetMessage(bindings => bindings.ErrorLintingFileMessage(sourceFile, exceptionMessage), out var message)
            ? message
            : FallbackErrorLintingFileMessage(sourceFile, exceptionMessage);

    internal static string GetNoIssuesMessage(int fileCount, string elapsedText)
    {
        var countText = fileCount.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(bindings => bindings.NoIssuesMessage(countText, fileCount, elapsedText), out var message)
            ? message
            : FallbackNoIssuesMessage(countText, fileCount, elapsedText);
    }

    internal static string GetLintedInMessage(string elapsedText)
        => TryGetMessage(bindings => bindings.ElapsedMessage(elapsedText), out var message)
            ? message
            : FallbackLintedInMessage(elapsedText);

    internal static string GetFailedMessage(string exceptionMessage)
        => TryGetMessage(bindings => bindings.FailedMessage(exceptionMessage), out var message)
            ? message
            : FallbackFailedMessage(exceptionMessage);

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
            DogfoodKernelLoader.CreateDelegate<CliLintOptionSummaryInto>(
                programType,
                "CliLintOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliLintFileArgIndicesInto>(
                programType,
                "CliLintFileArgIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliLintEffectiveOutputMode>(
                programType,
                "CliLintEffectiveOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliLintHelpText>(
                programType,
                "CliLintHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliLintProjectDirectoryNotFoundMessage>(
                programType,
                "CliLintProjectDirectoryNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliLintNoFilesFoundMessage>(
                programType,
                "CliLintNoFilesFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliLintFileNotFoundMessage>(
                programType,
                "CliLintFileNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliLintParseErrorsMessage>(
                programType,
                "CliLintParseErrorsMessage"),
            DogfoodKernelLoader.CreateDelegate<CliLintErrorLintingDiagnosticMessage>(
                programType,
                "CliLintErrorLintingDiagnosticMessage"),
            DogfoodKernelLoader.CreateDelegate<CliLintErrorLintingFileMessage>(
                programType,
                "CliLintErrorLintingFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliLintNoIssuesMessage>(
                programType,
                "CliLintNoIssuesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliLintElapsedMessage>(
                programType,
                "CliLintElapsedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliLintFailedMessage>(
                programType,
                "CliLintFailedMessage")));

    private delegate int CliLintOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliLintFileArgIndicesInto(
        string[] args,
        int[] projectValueIndices,
        int[] resultIndices);

    private delegate int CliLintEffectiveOutputMode(int useText, int useJson);

    private delegate string CliLintHelpText();

    private delegate string CliLintProjectDirectoryNotFoundMessage(string projectRoot);

    private delegate string CliLintNoFilesFoundMessage();

    private delegate string CliLintFileNotFoundMessage(string sourceFile);

    private delegate string CliLintParseErrorsMessage(string sourceFile, string messages);

    private delegate string CliLintErrorLintingDiagnosticMessage(string message);

    private delegate string CliLintErrorLintingFileMessage(string sourceFile, string message);

    private delegate string CliLintNoIssuesMessage(string fileCountText, int fileCount, string elapsedText);

    private delegate string CliLintElapsedMessage(string elapsedText);

    private delegate string CliLintFailedMessage(string message);

    private sealed record Bindings(
        CliLintOptionSummaryInto LintOptionSummary,
        CliLintFileArgIndicesInto LintFileArgIndices,
        CliLintEffectiveOutputMode LintEffectiveOutputMode,
        CliLintHelpText HelpText,
        CliLintProjectDirectoryNotFoundMessage ProjectDirectoryNotFoundMessage,
        CliLintNoFilesFoundMessage NoFilesFoundMessage,
        CliLintFileNotFoundMessage FileNotFoundMessage,
        CliLintParseErrorsMessage ParseErrorsMessage,
        CliLintErrorLintingDiagnosticMessage ErrorLintingDiagnosticMessage,
        CliLintErrorLintingFileMessage ErrorLintingFileMessage,
        CliLintNoIssuesMessage NoIssuesMessage,
        CliLintElapsedMessage ElapsedMessage,
        CliLintFailedMessage FailedMessage);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product lint messages route through CliLint* kernels.
    private static string FallbackHelpText()
        => "N# Lint\n"
           + "\n"
           + "Usage: nlc lint [options] [files...]\n"
           + "\n"
           + "Run static analysis rules on N# source files. Error-severity lints are\n"
           + "also included in 'nlc check' and block project builds.\n"
           + "\n"
           + "Options:\n"
           + "  --project <dir>   Project root directory (default: current directory)\n"
           + "  --json            Output as JSON (default)\n"
           + "  --text            Output as human-readable diagnostics\n"
           + "  --help, -h        Show this help text\n"
           + "\n"
           + "Lint Rules:\n"
           + "  NL001  error     Unused variable\n"
           + "  NL002  error     Missing import\n"
           + "  NL003  error     Unnecessary null check on value type\n"
           + "  NL004  error     Async function without await\n"
           + "  NL006  error     Unreachable code\n"
           + "  NL010  error     Unused import\n"
           + "  NL011  error     Empty catch block\n"
           + "  NL012  error     Unused parameter\n"
           + "  NL016  error     Redundant null check\n"
           + "  NL020  error     Shadowed variable\n"
           + "\n"
           + "Inline Suppression:\n"
           + "  // nlc:ignore NL001\n"
           + "  unusedVar := 42\n"
           + "\n"
           + "Examples:\n"
           + "  nlc lint\n"
           + "  nlc lint --json\n"
           + "  nlc lint --text\n"
           + "  nlc lint Program.nl\n"
           + "  nlc lint --project examples/16-task-cli\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  No errors found\n"
           + "  1  One or more errors were reported";

    private static string FallbackProjectDirectoryNotFoundMessage(string projectRoot)
        => $"Directory not found: {projectRoot}";

    private static string FallbackNoFilesFoundMessage()
        => "No .nl files found. Ensure you are in a project directory or specify files explicitly.";

    private static string FallbackFileNotFoundMessage(string sourceFile)
        => $"File not found: {sourceFile}";

    private static string FallbackParseErrorsMessage(string sourceFile, string messages)
        => $"Parse errors in {sourceFile}: {messages}";

    private static string FallbackErrorLintingDiagnosticMessage(string message)
        => $"Error linting: {message}";

    private static string FallbackErrorLintingFileMessage(string sourceFile, string message)
        => $"Error linting {sourceFile}: {message}";

    private static string FallbackNoIssuesMessage(string fileCountText, int fileCount, string elapsedText)
    {
        var suffix = fileCount == 1 ? string.Empty : "s";
        return $"  Linted {fileCountText} file{suffix} — no issues. [{elapsedText}]";
    }

    private static string FallbackLintedInMessage(string elapsedText)
        => $"  Linted in {elapsedText}";

    private static string FallbackFailedMessage(string message)
        => $"Lint failed: {message}";

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

    private sealed class Scratch
    {
        internal int[] ProjectValueIndices = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (ProjectValueIndices.Length != count)
                ProjectValueIndices = new int[count];

            if (ResultIndices.Length != count)
                ResultIndices = new int[count];
        }
    }
}
