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

    internal static FormatOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[5];
        var code = RequiredBindings.OptionSummary(args, resultIndices);
        if (code != 0 || !TryGetOptionalArg(args, resultIndices[0], out var projectOption))
            throw new InvalidOperationException("N# format option summary kernel rejected the arguments.");

        return new FormatOptionSummary(
            projectOption,
            resultIndices[1] != 0,
            resultIndices[2] != 0,
            resultIndices[3] != 0,
            resultIndices[4] != 0);
    }

    internal static string GetHelpText()
        => RequiredBindings.HelpText();

    internal static string GetStdinWithFilesMessage()
        => RequiredBindings.StdinWithFilesMessage();

    internal static string GetNoFilesFoundMessage()
        => RequiredBindings.NoFilesFoundMessage();

    internal static string GetFileNotFoundMessage(string sourceFile)
        => RequiredBindings.FileNotFoundMessage(sourceFile);

    internal static string GetErrorFormattingMessage(string sourceFile, string exceptionMessage)
        => RequiredBindings.ErrorFormattingMessage(sourceFile, exceptionMessage);

    internal static string GetWarningLine(string relativePath, string warning)
        => RequiredBindings.WarningLine(relativePath, warning);

    internal static string GetSafetyCheckFailedMessage(string warnings)
        => RequiredBindings.SafetyCheckFailedMessage(warnings);

    internal static string GetCheckFailedHeader(int count)
    {
        var countText = count.ToString(CultureInfo.InvariantCulture);
        return RequiredBindings.CheckFailedHeader(countText);
    }

    internal static string GetCheckFailedPathLine(string sourceFile)
        => RequiredBindings.CheckFailedPathLine(sourceFile);

    internal static string GetAllFilesFormattedMessage()
        => RequiredBindings.AllFilesFormattedMessage();

    internal static string GetFormattedCountMessage(int count)
    {
        var countText = count.ToString(CultureInfo.InvariantCulture);
        return RequiredBindings.FormattedCountMessage(countText);
    }

    internal static string GetFailedMessage(string exceptionMessage)
        => RequiredBindings.FailedMessage(exceptionMessage);

    internal static string GetParseErrorsMessage(string relativePath, string messages)
        => RequiredBindings.ParseErrorsMessage(relativePath, messages);

    internal static bool ShouldFormatDiscoveredPath(string relativePath)
    {
        var result = RequiredBindings.ShouldFormatDiscoveredPath(relativePath);
        if (result is not 0 and not 1)
            throw new InvalidOperationException("N# format discovery path kernel rejected the path.");

        return result == 1;
    }

    internal static bool ShouldSkipDiscoveredDirectoryName(string directoryName)
    {
        var result = RequiredBindings.ShouldSkipDiscoveredDirectoryName(directoryName);
        if (result is not 0 and not 1)
            throw new InvalidOperationException("N# format directory pruning kernel rejected the directory name.");

        return result == 1;
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
            DogfoodKernelLoader.CreateDelegate<CliFormatWarningLine>(
                programType,
                "CliFormatWarningLine"),
            DogfoodKernelLoader.CreateDelegate<CliFormatSafetyCheckFailedMessage>(
                programType,
                "CliFormatSafetyCheckFailedMessage"),
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

    private delegate string CliFormatWarningLine(string relativePath, string warning);

    private delegate string CliFormatSafetyCheckFailedMessage(string warnings);

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
        CliFormatWarningLine WarningLine,
        CliFormatSafetyCheckFailedMessage SafetyCheckFailedMessage,
        CliFormatCheckFailedHeader CheckFailedHeader,
        CliFormatCheckFailedPathLine CheckFailedPathLine,
        CliFormatAllFilesFormattedMessage AllFilesFormattedMessage,
        CliFormatFormattedCountMessage FormattedCountMessage,
        CliFormatFailedMessage FailedMessage,
        CliFormatParseErrorsMessage ParseErrorsMessage,
        CliShouldFormatDiscoveredPath ShouldFormatDiscoveredPath,
        CliShouldSkipFormatDirectoryName ShouldSkipDiscoveredDirectoryName);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# format command kernels are unavailable.");

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
