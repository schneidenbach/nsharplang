using System;
using System.Globalization;

namespace NSharpLang.Cli;

internal readonly record struct FormatOptionSummary(
    string? ProjectOption,
    bool VerifyOnly,
    bool DiffOnly,
    bool StdinMode,
    bool ShowHelp);

internal static class FormatCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out FormatOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[5];
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

            summary = new FormatOptionSummary(
                projectOption,
                resultIndices[1] != 0,
                resultIndices[2] != 0,
                resultIndices[3] != 0,
                resultIndices[4] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static string GetHelpText()
        => TryGetMessage(bindings => bindings.HelpText(), out var message)
            ? message
            : FallbackHelpText();

    internal static string GetStdinWithFilesMessage()
        => TryGetMessage(bindings => bindings.StdinWithFilesMessage(), out var message)
            ? message
            : FallbackStdinWithFilesMessage();

    internal static string GetNoFilesFoundMessage()
        => TryGetMessage(bindings => bindings.NoFilesFoundMessage(), out var message)
            ? message
            : FallbackNoFilesFoundMessage();

    internal static string GetFileNotFoundMessage(string sourceFile)
        => TryGetMessage(bindings => bindings.FileNotFoundMessage(sourceFile), out var message)
            ? message
            : FallbackFileNotFoundMessage(sourceFile);

    internal static string GetErrorFormattingMessage(string sourceFile, string exceptionMessage)
        => TryGetMessage(bindings => bindings.ErrorFormattingMessage(sourceFile, exceptionMessage), out var message)
            ? message
            : FallbackErrorFormattingMessage(sourceFile, exceptionMessage);

    internal static string GetCheckFailedHeader(int count)
    {
        var countText = count.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(bindings => bindings.CheckFailedHeader(countText), out var message)
            ? message
            : FallbackCheckFailedHeader(countText);
    }

    internal static string GetCheckFailedPathLine(string sourceFile)
        => TryGetMessage(bindings => bindings.CheckFailedPathLine(sourceFile), out var message)
            ? message
            : FallbackCheckFailedPathLine(sourceFile);

    internal static string GetAllFilesFormattedMessage()
        => TryGetMessage(bindings => bindings.AllFilesFormattedMessage(), out var message)
            ? message
            : FallbackAllFilesFormattedMessage();

    internal static string GetFormattedCountMessage(int count)
    {
        var countText = count.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(bindings => bindings.FormattedCountMessage(countText), out var message)
            ? message
            : FallbackFormattedCountMessage(countText);
    }

    internal static string GetFailedMessage(string exceptionMessage)
        => TryGetMessage(bindings => bindings.FailedMessage(exceptionMessage), out var message)
            ? message
            : FallbackFailedMessage(exceptionMessage);

    internal static string GetParseErrorsMessage(string relativePath, string messages)
        => TryGetMessage(bindings => bindings.ParseErrorsMessage(relativePath, messages), out var message)
            ? message
            : FallbackParseErrorsMessage(relativePath, messages);

    internal static bool TryShouldFormatDiscoveredPath(string relativePath, out bool shouldFormat)
    {
        shouldFormat = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.ShouldFormatDiscoveredPath(relativePath);
            if (result is not 0 and not 1)
                return false;

            shouldFormat = result == 1;
            return true;
        }
        catch
        {
            shouldFormat = false;
            return false;
        }
    }

    internal static bool TryShouldSkipDiscoveredDirectoryName(string directoryName, out bool shouldSkip)
    {
        shouldSkip = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.ShouldSkipDiscoveredDirectoryName(directoryName);
            if (result is not 0 and not 1)
                return false;

            shouldSkip = result == 1;
            return true;
        }
        catch
        {
            shouldSkip = false;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFormatOptionSummaryInto>(
                programType,
                "CliFormatOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliFormatHelpText>(
                programType,
                "CliFormatHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliFormatStdinWithFilesMessage>(
                programType,
                "CliFormatStdinWithFilesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFormatNoFilesFoundMessage>(
                programType,
                "CliFormatNoFilesFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFormatFileNotFoundMessage>(
                programType,
                "CliFormatFileNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFormatErrorFormattingMessage>(
                programType,
                "CliFormatErrorFormattingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFormatCheckFailedHeader>(
                programType,
                "CliFormatCheckFailedHeader"),
            DogfoodKernelLoader.CreateDelegate<CliFormatCheckFailedPathLine>(
                programType,
                "CliFormatCheckFailedPathLine"),
            DogfoodKernelLoader.CreateDelegate<CliFormatAllFilesFormattedMessage>(
                programType,
                "CliFormatAllFilesFormattedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFormatFormattedCountMessage>(
                programType,
                "CliFormatFormattedCountMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFormatFailedMessage>(
                programType,
                "CliFormatFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFormatParseErrorsMessage>(
                programType,
                "CliFormatParseErrorsMessage"),
            DogfoodKernelLoader.CreateDelegate<CliShouldFormatDiscoveredPath>(
                programType,
                "CliShouldFormatDiscoveredPath"),
            DogfoodKernelLoader.CreateDelegate<CliShouldSkipFormatDirectoryName>(
                programType,
                "CliShouldSkipFormatDirectoryName")));

    private delegate int CliFormatOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate string CliFormatHelpText();

    private delegate string CliFormatStdinWithFilesMessage();

    private delegate string CliFormatNoFilesFoundMessage();

    private delegate string CliFormatFileNotFoundMessage(string sourceFile);

    private delegate string CliFormatErrorFormattingMessage(string sourceFile, string message);

    private delegate string CliFormatCheckFailedHeader(string countText);

    private delegate string CliFormatCheckFailedPathLine(string sourceFile);

    private delegate string CliFormatAllFilesFormattedMessage();

    private delegate string CliFormatFormattedCountMessage(string countText);

    private delegate string CliFormatFailedMessage(string message);

    private delegate string CliFormatParseErrorsMessage(string relativePath, string messages);

    private delegate int CliShouldFormatDiscoveredPath(string relativePath);

    private delegate int CliShouldSkipFormatDirectoryName(string directoryName);

    private sealed record Bindings(
        CliFormatOptionSummaryInto OptionSummary,
        CliFormatHelpText HelpText,
        CliFormatStdinWithFilesMessage StdinWithFilesMessage,
        CliFormatNoFilesFoundMessage NoFilesFoundMessage,
        CliFormatFileNotFoundMessage FileNotFoundMessage,
        CliFormatErrorFormattingMessage ErrorFormattingMessage,
        CliFormatCheckFailedHeader CheckFailedHeader,
        CliFormatCheckFailedPathLine CheckFailedPathLine,
        CliFormatAllFilesFormattedMessage AllFilesFormattedMessage,
        CliFormatFormattedCountMessage FormattedCountMessage,
        CliFormatFailedMessage FailedMessage,
        CliFormatParseErrorsMessage ParseErrorsMessage,
        CliShouldFormatDiscoveredPath ShouldFormatDiscoveredPath,
        CliShouldSkipFormatDirectoryName ShouldSkipDiscoveredDirectoryName);

    private static bool TryGetMessage(Func<Bindings, string> getMessage, out string message)
    {
        message = string.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            message = getMessage(bindings);
            return message.Length > 0;
        }
        catch
        {
            message = string.Empty;
            return false;
        }
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product format messages route through CliFormat* kernels.
    private static string FallbackHelpText()
        => @"N# Format

Usage: nlc format [options] [files...]

Format N# source files with the canonical formatter.

Options:
  --project <dir>         Project root directory (default: current directory)
  --check                 Exit with code 1 if any file needs formatting
  --verify-no-changes     Back-compat alias for --check
  --diff                  Print unified diffs instead of writing files
  --stdin                 Read source from stdin and write the formatted result to stdout
  --help, -h              Show this help text

Examples:
  nlc format
  nlc format --check
  nlc format --diff Program.nl
  nlc format --stdin < Program.nl

Exit codes:
  0  Formatting succeeded
  1  Formatting failed or --check found unformatted files";

    private static string FallbackStdinWithFilesMessage()
        => "Cannot combine --stdin with file arguments.";

    private static string FallbackNoFilesFoundMessage()
        => "No .nl files found to format.";

    private static string FallbackFileNotFoundMessage(string sourceFile)
        => $"File not found: {sourceFile}";

    private static string FallbackErrorFormattingMessage(string sourceFile, string message)
        => $"Error formatting {sourceFile}: {message}";

    private static string FallbackCheckFailedHeader(string countText)
        => $"Formatting check failed for {countText} file(s):";

    private static string FallbackCheckFailedPathLine(string sourceFile)
        => $"  {sourceFile}";

    private static string FallbackAllFilesFormattedMessage()
        => "All files are properly formatted.";

    private static string FallbackFormattedCountMessage(string countText)
        => $"Formatted {countText} file(s).";

    private static string FallbackFailedMessage(string message)
        => $"Format failed: {message}";

    private static string FallbackParseErrorsMessage(string relativePath, string messages)
        => $"Parse errors in {relativePath}: {messages}";

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
