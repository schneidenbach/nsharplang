using System;
using System.Globalization;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal readonly record struct LintOptionSummary(
    string? ProjectOption,
    bool UseText,
    bool UseJson,
    bool ShowHelp);

internal static class LintCommandKernels
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    [ThreadStatic]
    private static int[]? t_optionResultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static LintOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionResultIndices ??= new int[4];
        var code = RequiredBindings.LintOptionSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# lint option summary kernel rejected the arguments.");

        var projectOption = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        return new LintOptionSummary(
            projectOption,
            resultIndices[1] != 0,
            resultIndices[2] != 0,
            resultIndices[3] != 0);
    }

    internal static string[] GetFileArgs(string[] args)
    {
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(args.Length);

        var count = RequiredBindings.LintFileArgIndices(
            args,
            scratch.ProjectValueIndices,
            scratch.ResultIndices);

        if (count < 0 || count > args.Length)
            throw new InvalidOperationException("N# lint file argument kernel rejected the arguments.");

        var files = new string[count];
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= args.Length)
                throw new InvalidOperationException("N# lint file argument kernel rejected the arguments.");

            files[i] = args[sourceIndex];
        }

        return files;
    }

    internal static int GetEffectiveOutputMode(
        bool useText,
        bool useJson)
        => RequiredBindings.LintEffectiveOutputMode(useText ? 1 : 0, useJson ? 1 : 0);

    internal static string GetHelpText()
        => RequiredBindings.HelpText();

    internal static string GetSeverityText(DiagnosticSeverity severity)
        => RequiredBindings.SeverityText((int)severity);

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
        => RequiredBindings.ProjectDirectoryNotFoundMessage(projectRoot);

    internal static string GetNoFilesFoundMessage()
        => RequiredBindings.NoFilesFoundMessage();

    internal static string GetFileNotFoundMessage(string sourceFile)
        => RequiredBindings.FileNotFoundMessage(sourceFile);

    internal static string GetParseErrorsMessage(string sourceFile, string messages)
        => RequiredBindings.ParseErrorsMessage(sourceFile, messages);

    internal static string GetErrorLintingDiagnosticMessage(string exceptionMessage)
        => RequiredBindings.ErrorLintingDiagnosticMessage(exceptionMessage);

    internal static string GetErrorLintingFileMessage(string sourceFile, string exceptionMessage)
        => RequiredBindings.ErrorLintingFileMessage(sourceFile, exceptionMessage);

    internal static string GetNoIssuesMessage(int fileCount, string elapsedText)
    {
        var countText = fileCount.ToString(CultureInfo.InvariantCulture);
        return RequiredBindings.NoIssuesMessage(countText, fileCount, elapsedText);
    }

    internal static string GetLintedInMessage(string elapsedText)
        => RequiredBindings.ElapsedMessage(elapsedText);

    internal static string GetFailedMessage(string exceptionMessage)
        => RequiredBindings.FailedMessage(exceptionMessage);

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
            DogfoodKernelLoader.CreateDelegate<CliLintSeverityText>(
                programType,
                "CliLintSeverityText"),
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

    private delegate string CliLintSeverityText(int severity);

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
        CliLintSeverityText SeverityText,
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

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# lint command kernels are unavailable.");

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
