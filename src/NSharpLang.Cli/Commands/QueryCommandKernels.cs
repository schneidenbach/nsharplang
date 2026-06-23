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

    internal static bool TryGetDaemonParameterSummary(string[] args, out QueryDaemonParameterSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[7];
        try
        {
            var code = bindings.QueryDaemonParameterSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var file)
                || !TryGetOptionalArg(args, resultIndices[1], out var pos)
                || !TryGetOptionalArg(args, resultIndices[2], out var name)
                || !TryGetOptionalArg(args, resultIndices[3], out var kind)
                || !TryGetOptionalArg(args, resultIndices[4], out var severity))
            {
                summary = default;
                return false;
            }

            summary = new QueryDaemonParameterSummary(
                file,
                pos,
                name,
                kind,
                severity,
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

    internal static bool TryGetCommandOptionSummary(string[] args, out QueryCommandOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_commandOptionIndices ??= new int[5];
        try
        {
            var code = bindings.QueryCommandOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var filter)
                || !TryGetOptionalArg(args, resultIndices[1], out var function)
                || !TryGetOptionalArg(args, resultIndices[2], out var limit)
                || !TryGetOptionalArg(args, resultIndices[3], out var requests)
                || !TryGetOptionalArg(args, resultIndices[4], out var leadingOperand))
            {
                summary = default;
                return false;
            }

            summary = new QueryCommandOptionSummary(
                filter,
                function,
                limit,
                requests,
                leadingOperand);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetTopLevelOptionSummary(string[] args, out QueryTopLevelOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_topLevelOptionIndices ??= new int[7];
        var remainingIndices = t_topLevelRemainingIndices;
        if (remainingIndices == null || remainingIndices.Length < args.Length)
        {
            remainingIndices = new int[Math.Max(args.Length, 1)];
            t_topLevelRemainingIndices = remainingIndices;
        }

        try
        {
            var remainingCount = bindings.QueryTopLevelOptionSummary(args, resultIndices, remainingIndices);
            if (remainingCount < 0 || remainingCount > args.Length)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var subcommand)
                || !TryGetOptionalArg(args, resultIndices[1], out var projectDir)
                || !TryGetOptionalArg(args, resultIndices[2], out var file)
                || !TryGetOptionalArg(args, resultIndices[3], out var pos))
            {
                summary = default;
                return false;
            }

            var remainingArgs = new string[remainingCount];
            for (var i = 0; i < remainingCount; i++)
            {
                var index = remainingIndices[i];
                if (index < 0 || index >= args.Length)
                {
                    summary = default;
                    return false;
                }

                remainingArgs[i] = args[index];
            }

            summary = new QueryTopLevelOptionSummary(
                subcommand,
                projectDir,
                file,
                pos,
                resultIndices[4] != 0,
                resultIndices[5] != 0,
                resultIndices[6] != 0,
                remainingArgs);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryParsePosition(string position, out bool parsed, out int line, out int column)
    {
        parsed = false;
        line = 0;
        column = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_positionResult ??= new int[2];
        try
        {
            var code = bindings.TryParsePosition(position, result);
            if (code is not 0 and not 1)
                return false;

            parsed = code == 1;
            line = result[0];
            column = result[1];
            return true;
        }
        catch
        {
            parsed = false;
            line = 0;
            column = 0;
            return false;
        }
    }

    internal static bool TryParsePositiveInt(string value, out bool parsed, out int result)
    {
        parsed = false;
        result = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultArray = t_positiveIntResult ??= new int[1];
        try
        {
            var code = bindings.TryParsePositiveInt(value, resultArray);
            if (code is not 0 and not 1)
                return false;

            parsed = code == 1;
            result = resultArray[0];
            return true;
        }
        catch
        {
            parsed = false;
            result = 0;
            return false;
        }
    }

    internal static bool TryGetInspectOutputMode(
        bool useText,
        bool inspectCompact,
        out QueryInspectOutputModeKind mode)
    {
        mode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.QueryInspectOutputMode(useText ? 1 : 0, inspectCompact ? 1 : 0);
            mode = code switch
            {
                -1 => QueryInspectOutputModeKind.InvalidCompactText,
                1 => QueryInspectOutputModeKind.Json,
                2 => QueryInspectOutputModeKind.CompactJson,
                3 => QueryInspectOutputModeKind.Text,
                _ => default
            };

            return code is -1 or 1 or 2 or 3;
        }
        catch
        {
            mode = default;
            return false;
        }
    }

    internal static bool TryShouldUseDaemon(bool useText, bool noDaemon, out bool shouldUse)
    {
        shouldUse = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.QueryShouldUseDaemon(useText ? 1 : 0, noDaemon ? 1 : 0);
            if (code is not 0 and not 1)
                return false;

            shouldUse = code != 0;
            return true;
        }
        catch
        {
            shouldUse = false;
            return false;
        }
    }

    internal static bool TryGetDiagnosticsOutputMode(
        bool useText,
        bool clusters,
        out QueryDiagnosticsOutputModeKind mode)
    {
        mode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.QueryDiagnosticsOutputMode(useText ? 1 : 0, clusters ? 1 : 0);
            mode = code switch
            {
                1 => QueryDiagnosticsOutputModeKind.Json,
                2 => QueryDiagnosticsOutputModeKind.Text,
                3 => QueryDiagnosticsOutputModeKind.ClustersJson,
                _ => default
            };

            return code is 1 or 2 or 3;
        }
        catch
        {
            mode = default;
            return false;
        }
    }

    internal static bool TryGetJsonOnlyOutputMode(bool useText, out QueryJsonOnlyOutputModeKind mode)
    {
        mode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.QueryJsonOnlyOutputMode(useText ? 1 : 0);
            mode = code switch
            {
                -1 => QueryJsonOnlyOutputModeKind.TextUnsupported,
                1 => QueryJsonOnlyOutputModeKind.Json,
                _ => default
            };

            return code is -1 or 1;
        }
        catch
        {
            mode = default;
            return false;
        }
    }

    internal static bool TryGetTextJsonOutputMode(bool useText, out QueryTextJsonOutputModeKind mode)
    {
        mode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.QueryTextJsonOutputMode(useText ? 1 : 0);
            mode = code switch
            {
                1 => QueryTextJsonOutputModeKind.Json,
                2 => QueryTextJsonOutputModeKind.Text,
                _ => default
            };

            return code is 1 or 2;
        }
        catch
        {
            mode = default;
            return false;
        }
    }

    internal static bool TryParseSymbolKind(string value, out SymbolKind kind)
    {
        if (TryParseSymbolKindWithDogfood(value, out var parsed, out kind))
            return parsed;

        throw new InvalidOperationException("N# query symbol-kind parser kernel rejected the value.");
    }

    private static bool TryParseSymbolKindWithDogfood(string value, out bool parsed, out SymbolKind kind)
    {
        parsed = false;
        kind = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultArray = t_symbolKindResult ??= new int[1];
        try
        {
            var code = bindings.TryParseSymbolKind(value, resultArray);
            if (code is not 0 and not 1)
                return false;

            parsed = code == 1;
            kind = (SymbolKind)resultArray[0];
            return true;
        }
        catch
        {
            parsed = false;
            kind = default;
            return false;
        }
    }

    internal static string GetHelpText(string commandLines)
    {
        if (TryGetMessage(bindings => bindings.QueryHelpText(commandLines), out var message))
            return message;

        throw new InvalidOperationException("N# query help-text kernel rejected the values.");
    }

    internal static string GetDescriptionWithAliases(string description, string aliasesText)
    {
        if (TryGetMessage(bindings => bindings.QueryDescriptionWithAliases(description, aliasesText), out var message))
            return message;

        throw new InvalidOperationException("N# query description kernel rejected the values.");
    }

    internal static string GetUnknownSubcommandMessage(string subcommand)
    {
        if (TryGetMessage(bindings => bindings.QueryUnknownSubcommandMessage(subcommand), out var message))
            return message;

        throw new InvalidOperationException("N# query unknown-subcommand message kernel rejected the values.");
    }

    internal static string GetNoCompilationUnitForFileMessage(string fileFilter)
    {
        if (TryGetMessage(bindings => bindings.QueryNoCompilationUnitForFileMessage(fileFilter), out var message))
            return message;

        throw new InvalidOperationException("N# query no-compilation-unit message kernel rejected the values.");
    }

    internal static string GetNoCompilationUnitsMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryNoCompilationUnitsMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query no-compilation-units message kernel rejected the values.");
    }

    internal static string GetPositionUsageMessage(string subcommand)
    {
        if (TryGetMessage(bindings => bindings.QueryPositionUsageMessage(subcommand), out var message))
            return message;

        throw new InvalidOperationException("N# query position-usage message kernel rejected the values.");
    }

    internal static string GetInvalidPositionMessage(string position)
    {
        if (TryGetMessage(bindings => bindings.QueryInvalidPositionMessage(position), out var message))
            return message;

        throw new InvalidOperationException("N# query invalid-position message kernel rejected the values.");
    }

    internal static string GetNoSymbolAtPositionMessage(string file, int line, int column)
        => GetNoSymbolAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetNoSymbolAtPositionMessage(string file, string lineText, string columnText)
    {
        if (TryGetMessage(bindings => bindings.QueryNoSymbolAtPositionMessage(file, lineText, columnText), out var message))
            return message;

        throw new InvalidOperationException("N# query no-symbol message kernel rejected the values.");
    }

    internal static string GetNoTypeInformationAtPositionMessage(string file, int line, int column)
        => GetNoTypeInformationAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetNoTypeInformationAtPositionMessage(string file, string lineText, string columnText)
    {
        if (TryGetMessage(bindings => bindings.QueryNoTypeInformationAtPositionMessage(file, lineText, columnText), out var message))
            return message;

        throw new InvalidOperationException("N# query no-type message kernel rejected the values.");
    }

    internal static string GetNoDefinitionAtPositionMessage(string file, int line, int column)
        => GetNoDefinitionAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetNoDefinitionAtPositionMessage(string file, string lineText, string columnText)
    {
        if (TryGetMessage(bindings => bindings.QueryNoDefinitionAtPositionMessage(file, lineText, columnText), out var message))
            return message;

        throw new InvalidOperationException("N# query no-definition message kernel rejected the values.");
    }

    internal static string GetNoInterfaceAtPositionMessage(string file, int line, int column)
        => GetNoInterfaceAtPositionMessage(file, ToInvariantText(line), ToInvariantText(column));

    internal static string GetNoInterfaceAtPositionMessage(string file, string lineText, string columnText)
    {
        if (TryGetMessage(bindings => bindings.QueryNoInterfaceAtPositionMessage(file, lineText, columnText), out var message))
            return message;

        throw new InvalidOperationException("N# query no-interface message kernel rejected the values.");
    }

    internal static string GetPerformanceJsonOnlyMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryPerformanceJsonOnlyMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query performance JSON-only message kernel rejected the values.");
    }

    internal static string GetTrustedJsonOnlyMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryTrustedJsonOnlyMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query trusted JSON-only message kernel rejected the values.");
    }

    internal static string GetImplementorsUsageMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryImplementorsUsageMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query implementors usage message kernel rejected the values.");
    }

    internal static string GetBatchJsonOnlyMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryBatchJsonOnlyMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query batch JSON-only message kernel rejected the values.");
    }

    internal static string GetBatchUsageMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryBatchUsageMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query batch usage message kernel rejected the values.");
    }

    internal static string GetEmptyBatchMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryEmptyBatchMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query empty-batch message kernel rejected the values.");
    }

    internal static string GetOutlineUsageMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryOutlineUsageMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query outline usage message kernel rejected the values.");
    }

    internal static string GetFileNotFoundMessage(string filePath)
    {
        if (TryGetMessage(bindings => bindings.QueryFileNotFoundMessage(filePath), out var message))
            return message;

        throw new InvalidOperationException("N# query file-not-found message kernel rejected the values.");
    }

    internal static string GetDefinitionUsageMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryDefinitionUsageMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query definition usage message kernel rejected the values.");
    }

    internal static string GetInspectCompactTextUnsupportedMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryInspectCompactTextUnsupportedMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query inspect compact/text message kernel rejected the values.");
    }

    internal static string GetReferencesUsageMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryReferencesUsageMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query references usage message kernel rejected the values.");
    }

    internal static string GetSemanticReferencesUnavailableMessage()
    {
        if (TryGetMessage(bindings => bindings.QuerySemanticReferencesUnavailableMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query semantic references message kernel rejected the values.");
    }

    internal static string GetDocUsageMessage()
    {
        if (TryGetMessage(bindings => bindings.QueryDocUsageMessage(), out var message))
            return message;

        throw new InvalidOperationException("N# query doc usage message kernel rejected the values.");
    }

    internal static string GetNoDocumentationMessage(string query)
    {
        if (TryGetMessage(bindings => bindings.QueryNoDocumentationMessage(query), out var message))
            return message;

        throw new InvalidOperationException("N# query no-documentation message kernel rejected the values.");
    }

    internal static string GetProjectDirectoryNotFoundMessage(string projectDir)
    {
        if (TryGetMessage(bindings => bindings.QueryProjectDirectoryNotFoundMessage(projectDir), out var message))
            return message;

        throw new InvalidOperationException("N# query project-directory message kernel rejected the values.");
    }

    internal static string GetFailedAnalyzeProjectMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.QueryFailedAnalyzeProjectMessage(message), out var result))
            return result;

        throw new InvalidOperationException("N# query failed-analysis message kernel rejected the values.");
    }

    private static string ToInvariantText(int value)
        => value.ToString(CultureInfo.InvariantCulture);

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
        CliQuerySymbolKindInto TryParseSymbolKind,
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
