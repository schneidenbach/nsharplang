using System;
using System.Globalization;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

internal readonly record struct QueryDaemonParameterSummary(
    string? File,
    string? Pos,
    string? Name,
    string? Kind,
    string? Severity,
    bool IncludeKeywords,
    bool Clusters);

internal readonly record struct QueryCommandOptionSummary(
    string? Filter,
    string? Function,
    string? Limit,
    string? Requests,
    string? LeadingOperand);

internal readonly record struct QueryTopLevelOptionSummary(
    string? Subcommand,
    string? ProjectDir,
    string? File,
    string? Pos,
    bool UseText,
    bool NoDaemon,
    bool InspectCompact,
    string[] RemainingArgs);

internal enum QueryInspectOutputModeKind
{
    InvalidCompactText = -1,
    Json = 1,
    CompactJson = 2,
    Text = 3
}

internal enum QueryDiagnosticsOutputModeKind
{
    Json = 1,
    Text = 2,
    ClustersJson = 3
}

internal enum QueryJsonOnlyOutputModeKind
{
    TextUnsupported = -1,
    Json = 1
}

internal enum QueryTextJsonOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class QueryCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    [ThreadStatic]
    private static int[]? t_commandOptionIndices;

    [ThreadStatic]
    private static int[]? t_topLevelOptionIndices;

    [ThreadStatic]
    private static int[]? t_topLevelRemainingIndices;

    [ThreadStatic]
    private static int[]? t_positionResult;

    [ThreadStatic]
    private static int[]? t_positiveIntResult;

    [ThreadStatic]
    private static int[]? t_symbolKindResult;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static QueryDaemonParameterSummary GetDaemonParameterSummary(string[] args)
    {
        var resultIndices = t_resultIndices ??= new int[7];
        var code = RequiredBindings.QueryDaemonParameterSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# query daemon parameter kernel rejected the arguments.");

        var file = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        var pos = resultIndices[1] == -1 ? null : args[resultIndices[1]];
        var name = resultIndices[2] == -1 ? null : args[resultIndices[2]];
        var kind = resultIndices[3] == -1 ? null : args[resultIndices[3]];
        var severity = resultIndices[4] == -1 ? null : args[resultIndices[4]];
        return new QueryDaemonParameterSummary(
            file,
            pos,
            name,
            kind,
            severity,
            resultIndices[5] != 0,
            resultIndices[6] != 0);
    }

    internal static QueryCommandOptionSummary GetCommandOptionSummary(string[] args)
    {
        var resultIndices = t_commandOptionIndices ??= new int[5];
        var code = RequiredBindings.QueryCommandOptionSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# query command option kernel rejected the arguments.");

        var filter = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        var function = resultIndices[1] == -1 ? null : args[resultIndices[1]];
        var limit = resultIndices[2] == -1 ? null : args[resultIndices[2]];
        var requests = resultIndices[3] == -1 ? null : args[resultIndices[3]];
        var leadingOperand = resultIndices[4] == -1 ? null : args[resultIndices[4]];
        return new QueryCommandOptionSummary(
            filter,
            function,
            limit,
            requests,
            leadingOperand);
    }

    internal static QueryTopLevelOptionSummary GetTopLevelOptionSummary(string[] args)
    {
        var resultIndices = t_topLevelOptionIndices ??= new int[7];
        var remainingIndices = t_topLevelRemainingIndices;
        if (remainingIndices == null || remainingIndices.Length < args.Length)
        {
            remainingIndices = new int[Math.Max(args.Length, 1)];
            t_topLevelRemainingIndices = remainingIndices;
        }

        var remainingCount = RequiredBindings.QueryTopLevelOptionSummary(args, resultIndices, remainingIndices);
        if (remainingCount < 0 || remainingCount > args.Length)
            throw new InvalidOperationException("N# query top-level option kernel rejected the arguments.");

        var subcommand = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        var projectDir = resultIndices[1] == -1 ? null : args[resultIndices[1]];
        var file = resultIndices[2] == -1 ? null : args[resultIndices[2]];
        var pos = resultIndices[3] == -1 ? null : args[resultIndices[3]];
        var remainingArgs = new string[remainingCount];
        for (var i = 0; i < remainingCount; i++)
        {
            var index = remainingIndices[i];
            if (index < 0 || index >= args.Length)
                throw new InvalidOperationException("N# query top-level option kernel rejected the arguments.");

            remainingArgs[i] = args[index];
        }

        return new QueryTopLevelOptionSummary(
            subcommand,
            projectDir,
            file,
            pos,
            resultIndices[4] != 0,
            resultIndices[5] != 0,
            resultIndices[6] != 0,
            remainingArgs);
    }

    internal static bool ParsePosition(string position, out int line, out int column)
    {
        var result = t_positionResult ??= new int[2];
        var code = RequiredBindings.TryParsePosition(position, result);
        if (code is not 0 and not 1)
            throw new InvalidOperationException("N# query position parser kernel rejected the position.");

        line = result[0];
        column = result[1];
        return code == 1;
    }

    internal static bool ParsePositiveInt(string value, out int result)
    {
        var resultArray = t_positiveIntResult ??= new int[1];
        var code = RequiredBindings.TryParsePositiveInt(value, resultArray);
        if (code is not 0 and not 1)
            throw new InvalidOperationException("N# query positive-int parser kernel rejected the value.");

        result = resultArray[0];
        return code == 1;
    }

    internal static QueryInspectOutputModeKind GetInspectOutputMode(
        bool useText,
        bool inspectCompact)
    {
        var code = RequiredBindings.QueryInspectOutputMode(useText ? 1 : 0, inspectCompact ? 1 : 0);
        return code switch
        {
            -1 => QueryInspectOutputModeKind.InvalidCompactText,
            1 => QueryInspectOutputModeKind.Json,
            2 => QueryInspectOutputModeKind.CompactJson,
            3 => QueryInspectOutputModeKind.Text,
            _ => throw new InvalidOperationException("N# query inspect output-mode kernel rejected the values.")
        };
    }

    internal static bool ShouldUseDaemon(bool useText, bool noDaemon)
    {
        var code = RequiredBindings.QueryShouldUseDaemon(useText ? 1 : 0, noDaemon ? 1 : 0);
        if (code is not 0 and not 1)
            throw new InvalidOperationException("N# query daemon routing kernel rejected the values.");

        return code != 0;
    }

    internal static QueryDiagnosticsOutputModeKind GetDiagnosticsOutputMode(
        bool useText,
        bool clusters)
    {
        var code = RequiredBindings.QueryDiagnosticsOutputMode(useText ? 1 : 0, clusters ? 1 : 0);
        return code switch
        {
            1 => QueryDiagnosticsOutputModeKind.Json,
            2 => QueryDiagnosticsOutputModeKind.Text,
            3 => QueryDiagnosticsOutputModeKind.ClustersJson,
            _ => throw new InvalidOperationException("N# query diagnostics output-mode kernel rejected the values.")
        };
    }

    internal static QueryJsonOnlyOutputModeKind GetJsonOnlyOutputMode(bool useText)
    {
        var code = RequiredBindings.QueryJsonOnlyOutputMode(useText ? 1 : 0);
        return code switch
        {
            -1 => QueryJsonOnlyOutputModeKind.TextUnsupported,
            1 => QueryJsonOnlyOutputModeKind.Json,
            _ => throw new InvalidOperationException("N# query JSON-only output-mode kernel rejected the value.")
        };
    }

    internal static QueryTextJsonOutputModeKind GetTextJsonOutputMode(bool useText)
    {
        var code = RequiredBindings.QueryTextJsonOutputMode(useText ? 1 : 0);
        return code switch
        {
            1 => QueryTextJsonOutputModeKind.Json,
            2 => QueryTextJsonOutputModeKind.Text,
            _ => throw new InvalidOperationException("N# query text/json output-mode kernel rejected the value.")
        };
    }

    internal static SymbolKind? ParseSymbolKind(string value)
    {
        var resultArray = t_symbolKindResult ??= new int[1];
        var code = RequiredBindings.ParseSymbolKind(value, resultArray);
        if (code is not 0 and not 1)
            throw new InvalidOperationException("N# query symbol-kind parser kernel rejected the value.");

        return code == 1 ? (SymbolKind)resultArray[0] : null;
    }

    internal static string GetHelpText(string commandLines)
        => GetMessage(bindings => bindings.QueryHelpText(commandLines));

    internal static string GetDescriptionWithAliases(string description, string aliasesText)
        => GetMessage(bindings => bindings.QueryDescriptionWithAliases(description, aliasesText));

    internal static string GetUnknownSubcommandMessage(string subcommand)
        => GetMessage(bindings => bindings.QueryUnknownSubcommandMessage(subcommand));

    internal static string GetNoCompilationUnitForFileMessage(string fileFilter)
        => GetMessage(bindings => bindings.QueryNoCompilationUnitForFileMessage(fileFilter));

    internal static string GetNoCompilationUnitsMessage()
        => GetMessage(bindings => bindings.QueryNoCompilationUnitsMessage());

    internal static string GetPositionUsageMessage(string subcommand)
        => GetMessage(bindings => bindings.QueryPositionUsageMessage(subcommand));

    internal static string GetInvalidPositionMessage(string position)
        => GetMessage(bindings => bindings.QueryInvalidPositionMessage(position));

    internal static string GetNoSymbolAtPositionMessage(string file, int line, int column)
        => GetNoSymbolAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetNoSymbolAtPositionMessage(string file, string lineText, string columnText)
        => GetMessage(bindings => bindings.QueryNoSymbolAtPositionMessage(file, lineText, columnText));

    internal static string GetNoTypeInformationAtPositionMessage(string file, int line, int column)
        => GetNoTypeInformationAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetNoTypeInformationAtPositionMessage(string file, string lineText, string columnText)
        => GetMessage(bindings => bindings.QueryNoTypeInformationAtPositionMessage(file, lineText, columnText));

    internal static string GetNoDefinitionAtPositionMessage(string file, int line, int column)
        => GetNoDefinitionAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetNoDefinitionAtPositionMessage(string file, string lineText, string columnText)
        => GetMessage(bindings => bindings.QueryNoDefinitionAtPositionMessage(file, lineText, columnText));

    internal static string GetNoInterfaceAtPositionMessage(string file, int line, int column)
        => GetNoInterfaceAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetNoInterfaceAtPositionMessage(string file, string lineText, string columnText)
        => GetMessage(bindings => bindings.QueryNoInterfaceAtPositionMessage(file, lineText, columnText));

    internal static string GetPerformanceJsonOnlyMessage()
        => GetMessage(bindings => bindings.QueryPerformanceJsonOnlyMessage());

    internal static string GetTrustedJsonOnlyMessage()
        => GetMessage(bindings => bindings.QueryTrustedJsonOnlyMessage());

    internal static string GetImplementorsUsageMessage()
        => GetMessage(bindings => bindings.QueryImplementorsUsageMessage());

    internal static string GetBatchJsonOnlyMessage()
        => GetMessage(bindings => bindings.QueryBatchJsonOnlyMessage());

    internal static string GetBatchUsageMessage()
        => GetMessage(bindings => bindings.QueryBatchUsageMessage());

    internal static string GetEmptyBatchMessage()
        => GetMessage(bindings => bindings.QueryEmptyBatchMessage());

    internal static string GetOutlineUsageMessage()
        => GetMessage(bindings => bindings.QueryOutlineUsageMessage());

    internal static string GetFileNotFoundMessage(string filePath)
        => GetMessage(bindings => bindings.QueryFileNotFoundMessage(filePath));

    internal static string GetDefinitionUsageMessage()
        => GetMessage(bindings => bindings.QueryDefinitionUsageMessage());

    internal static string GetInspectCompactTextUnsupportedMessage()
        => GetMessage(bindings => bindings.QueryInspectCompactTextUnsupportedMessage());

    internal static string GetReferencesUsageMessage()
        => GetMessage(bindings => bindings.QueryReferencesUsageMessage());

    internal static string GetSemanticReferencesUnavailableMessage()
        => GetMessage(bindings => bindings.QuerySemanticReferencesUnavailableMessage());

    internal static string GetDocUsageMessage()
        => GetMessage(bindings => bindings.QueryDocUsageMessage());

    internal static string GetNoDocumentationMessage(string query)
        => GetMessage(bindings => bindings.QueryNoDocumentationMessage(query));

    internal static string GetProjectDirectoryNotFoundMessage(string projectDir)
        => GetMessage(bindings => bindings.QueryProjectDirectoryNotFoundMessage(projectDir));

    internal static string GetFailedAnalyzeProjectMessage(string message)
        => GetMessage(bindings => bindings.QueryFailedAnalyzeProjectMessage(message));

    private static string ToInvariantText(int value)
        => value.ToString(CultureInfo.InvariantCulture);

    private static string GetMessage(Func<Bindings, string> getMessage)
    {
        var bindings = s_bindings.Value ?? throw new InvalidOperationException("N# query message kernels are unavailable.");
        var message = getMessage(bindings);
        return !string.IsNullOrEmpty(message)
            ? message
            : throw new InvalidOperationException("N# query message kernel returned empty output.");
    }

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# query kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliQueryDaemonParameterSummaryInto>(
                programType,
                "CliQueryDaemonParameterSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliQueryCommandOptionSummaryInto>(
                programType,
                "CliQueryCommandOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliQueryTopLevelOptionSummaryInto>(
                programType,
                "CliQueryTopLevelOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliTryParsePositionInto>(
                programType,
                "CliTryParsePositionInto"),
            DogfoodKernelLoader.CreateDelegate<CliTryParsePositiveIntInto>(
                programType,
                "CliTryParsePositiveIntInto"),
            DogfoodKernelLoader.CreateDelegate<CliQueryInspectOutputMode>(
                programType,
                "CliQueryInspectOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliQueryDiagnosticsOutputMode>(
                programType,
                "CliQueryDiagnosticsOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliQueryJsonOnlyOutputMode>(
                programType,
                "CliQueryJsonOnlyOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliQueryTextJsonOutputMode>(
                programType,
                "CliQueryTextJsonOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliQueryShouldUseDaemon>(
                programType,
                "CliQueryShouldUseDaemon"),
            DogfoodKernelLoader.CreateDelegate<CliQuerySymbolKindInto>(
                programType,
                "CliQuerySymbolKindInto"),
            DogfoodKernelLoader.CreateDelegate<CliQueryHelpText>(
                programType,
                "CliQueryHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliQueryDescriptionWithAliases>(
                programType,
                "CliQueryDescriptionWithAliases"),
            DogfoodKernelLoader.CreateDelegate<CliQueryUnknownSubcommandMessage>(
                programType,
                "CliQueryUnknownSubcommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryNoCompilationUnitForFileMessage>(
                programType,
                "CliQueryNoCompilationUnitForFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryNoCompilationUnitsMessage>(
                programType,
                "CliQueryNoCompilationUnitsMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryPositionUsageMessage>(
                programType,
                "CliQueryPositionUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryInvalidPositionMessage>(
                programType,
                "CliQueryInvalidPositionMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryNoSymbolAtPositionMessage>(
                programType,
                "CliQueryNoSymbolAtPositionMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryNoTypeInformationAtPositionMessage>(
                programType,
                "CliQueryNoTypeInformationAtPositionMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryNoDefinitionAtPositionMessage>(
                programType,
                "CliQueryNoDefinitionAtPositionMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryNoInterfaceAtPositionMessage>(
                programType,
                "CliQueryNoInterfaceAtPositionMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryPerformanceJsonOnlyMessage>(
                programType,
                "CliQueryPerformanceJsonOnlyMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryTrustedJsonOnlyMessage>(
                programType,
                "CliQueryTrustedJsonOnlyMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryImplementorsUsageMessage>(
                programType,
                "CliQueryImplementorsUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryBatchJsonOnlyMessage>(
                programType,
                "CliQueryBatchJsonOnlyMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryBatchUsageMessage>(
                programType,
                "CliQueryBatchUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryEmptyBatchMessage>(
                programType,
                "CliQueryEmptyBatchMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryOutlineUsageMessage>(
                programType,
                "CliQueryOutlineUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryFileNotFoundMessage>(
                programType,
                "CliQueryFileNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryDefinitionUsageMessage>(
                programType,
                "CliQueryDefinitionUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryInspectCompactTextUnsupportedMessage>(
                programType,
                "CliQueryInspectCompactTextUnsupportedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryReferencesUsageMessage>(
                programType,
                "CliQueryReferencesUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQuerySemanticReferencesUnavailableMessage>(
                programType,
                "CliQuerySemanticReferencesUnavailableMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryDocUsageMessage>(
                programType,
                "CliQueryDocUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryNoDocumentationMessage>(
                programType,
                "CliQueryNoDocumentationMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryProjectDirectoryNotFoundMessage>(
                programType,
                "CliQueryProjectDirectoryNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliQueryFailedAnalyzeProjectMessage>(
                programType,
                "CliQueryFailedAnalyzeProjectMessage")));

    private delegate int CliQueryDaemonParameterSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliQueryCommandOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliQueryTopLevelOptionSummaryInto(
        string[] args,
        int[] resultIndices,
        int[] remainingIndices);

    private delegate int CliTryParsePositionInto(string position, int[] result);

    private delegate int CliTryParsePositiveIntInto(string value, int[] result);

    private delegate int CliQueryInspectOutputMode(int useText, int inspectCompact);

    private delegate int CliQueryDiagnosticsOutputMode(int useText, int clusters);

    private delegate int CliQueryJsonOnlyOutputMode(int useText);

    private delegate int CliQueryTextJsonOutputMode(int useText);

    private delegate int CliQueryShouldUseDaemon(int useText, int noDaemon);

    private delegate int CliQuerySymbolKindInto(string value, int[] result);

    private delegate string CliQueryHelpText(string commandLines);
    private delegate string CliQueryDescriptionWithAliases(string description, string aliasesText);
    private delegate string CliQueryUnknownSubcommandMessage(string subcommand);
    private delegate string CliQueryNoCompilationUnitForFileMessage(string fileFilter);
    private delegate string CliQueryNoCompilationUnitsMessage();
    private delegate string CliQueryPositionUsageMessage(string subcommand);
    private delegate string CliQueryInvalidPositionMessage(string position);
    private delegate string CliQueryNoSymbolAtPositionMessage(string file, string lineText, string columnText);
    private delegate string CliQueryNoTypeInformationAtPositionMessage(string file, string lineText, string columnText);
    private delegate string CliQueryNoDefinitionAtPositionMessage(string file, string lineText, string columnText);
    private delegate string CliQueryNoInterfaceAtPositionMessage(string file, string lineText, string columnText);
    private delegate string CliQueryPerformanceJsonOnlyMessage();
    private delegate string CliQueryTrustedJsonOnlyMessage();
    private delegate string CliQueryImplementorsUsageMessage();
    private delegate string CliQueryBatchJsonOnlyMessage();
    private delegate string CliQueryBatchUsageMessage();
    private delegate string CliQueryEmptyBatchMessage();
    private delegate string CliQueryOutlineUsageMessage();
    private delegate string CliQueryFileNotFoundMessage(string filePath);
    private delegate string CliQueryDefinitionUsageMessage();
    private delegate string CliQueryInspectCompactTextUnsupportedMessage();
    private delegate string CliQueryReferencesUsageMessage();
    private delegate string CliQuerySemanticReferencesUnavailableMessage();
    private delegate string CliQueryDocUsageMessage();
    private delegate string CliQueryNoDocumentationMessage(string query);
    private delegate string CliQueryProjectDirectoryNotFoundMessage(string projectDir);
    private delegate string CliQueryFailedAnalyzeProjectMessage(string message);

    private sealed record Bindings(
        CliQueryDaemonParameterSummaryInto QueryDaemonParameterSummary,
        CliQueryCommandOptionSummaryInto QueryCommandOptionSummary,
        CliQueryTopLevelOptionSummaryInto QueryTopLevelOptionSummary,
        CliTryParsePositionInto TryParsePosition,
        CliTryParsePositiveIntInto TryParsePositiveInt,
        CliQueryInspectOutputMode QueryInspectOutputMode,
        CliQueryDiagnosticsOutputMode QueryDiagnosticsOutputMode,
        CliQueryJsonOnlyOutputMode QueryJsonOnlyOutputMode,
        CliQueryTextJsonOutputMode QueryTextJsonOutputMode,
        CliQueryShouldUseDaemon QueryShouldUseDaemon,
        CliQuerySymbolKindInto ParseSymbolKind,
        CliQueryHelpText QueryHelpText,
        CliQueryDescriptionWithAliases QueryDescriptionWithAliases,
        CliQueryUnknownSubcommandMessage QueryUnknownSubcommandMessage,
        CliQueryNoCompilationUnitForFileMessage QueryNoCompilationUnitForFileMessage,
        CliQueryNoCompilationUnitsMessage QueryNoCompilationUnitsMessage,
        CliQueryPositionUsageMessage QueryPositionUsageMessage,
        CliQueryInvalidPositionMessage QueryInvalidPositionMessage,
        CliQueryNoSymbolAtPositionMessage QueryNoSymbolAtPositionMessage,
        CliQueryNoTypeInformationAtPositionMessage QueryNoTypeInformationAtPositionMessage,
        CliQueryNoDefinitionAtPositionMessage QueryNoDefinitionAtPositionMessage,
        CliQueryNoInterfaceAtPositionMessage QueryNoInterfaceAtPositionMessage,
        CliQueryPerformanceJsonOnlyMessage QueryPerformanceJsonOnlyMessage,
        CliQueryTrustedJsonOnlyMessage QueryTrustedJsonOnlyMessage,
        CliQueryImplementorsUsageMessage QueryImplementorsUsageMessage,
        CliQueryBatchJsonOnlyMessage QueryBatchJsonOnlyMessage,
        CliQueryBatchUsageMessage QueryBatchUsageMessage,
        CliQueryEmptyBatchMessage QueryEmptyBatchMessage,
        CliQueryOutlineUsageMessage QueryOutlineUsageMessage,
        CliQueryFileNotFoundMessage QueryFileNotFoundMessage,
        CliQueryDefinitionUsageMessage QueryDefinitionUsageMessage,
        CliQueryInspectCompactTextUnsupportedMessage QueryInspectCompactTextUnsupportedMessage,
        CliQueryReferencesUsageMessage QueryReferencesUsageMessage,
        CliQuerySemanticReferencesUnavailableMessage QuerySemanticReferencesUnavailableMessage,
        CliQueryDocUsageMessage QueryDocUsageMessage,
        CliQueryNoDocumentationMessage QueryNoDocumentationMessage,
        CliQueryProjectDirectoryNotFoundMessage QueryProjectDirectoryNotFoundMessage,
        CliQueryFailedAnalyzeProjectMessage QueryFailedAnalyzeProjectMessage);
}
