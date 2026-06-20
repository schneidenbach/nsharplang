using System;
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

    internal static bool TryParseSymbolKind(string value, out SymbolKind kind)
    {
        if (TryParseSymbolKindWithDogfood(value, out var parsed, out kind))
        {
            if (parsed)
                return true;

            return TryParseSymbolKindWithCSharp(value, out kind);
        }

        return TryParseSymbolKindWithCSharp(value, out kind);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product query symbol-kind parsing routes through QueryCommandKernels.
    private static bool TryParseSymbolKindWithCSharp(string value, out SymbolKind kind)
        => Enum.TryParse(value, ignoreCase: true, out kind);

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
            DogfoodKernelLoader.CreateDelegate<CliQueryShouldUseDaemon>(
                programType,
                "CliQueryShouldUseDaemon"),
            DogfoodKernelLoader.CreateDelegate<CliQuerySymbolKindInto>(
                programType,
                "CliQuerySymbolKindInto")));

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

    private delegate int CliQueryShouldUseDaemon(int useText, int noDaemon);

    private delegate int CliQuerySymbolKindInto(string value, int[] result);

    private sealed record Bindings(
        CliQueryDaemonParameterSummaryInto QueryDaemonParameterSummary,
        CliQueryCommandOptionSummaryInto QueryCommandOptionSummary,
        CliQueryTopLevelOptionSummaryInto QueryTopLevelOptionSummary,
        CliTryParsePositionInto TryParsePosition,
        CliTryParsePositiveIntInto TryParsePositiveInt,
        CliQueryInspectOutputMode QueryInspectOutputMode,
        CliQueryDiagnosticsOutputMode QueryDiagnosticsOutputMode,
        CliQueryJsonOnlyOutputMode QueryJsonOnlyOutputMode,
        CliQueryShouldUseDaemon QueryShouldUseDaemon,
        CliQuerySymbolKindInto TryParseSymbolKind);
}
