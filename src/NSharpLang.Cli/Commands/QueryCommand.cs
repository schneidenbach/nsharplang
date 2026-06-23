using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli;
using NSharpLang.Cli.Daemon;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

/// <summary>
/// Handles all 'nlc query' subcommands.
/// JSON output goes to stdout. Logs/errors go to stderr.
/// </summary>
public static class QueryCommand
{
    private static readonly CodeIntelligenceService Service = new();

    public static int Execute(string[] args)
    {
        if (args.Length == 0)
        {
            return ShowQueryHelp();
        }

        // Parse global options
        var options = ParseOptions(args, out var subcommand, out var positionalArgs);

        return subcommand switch
        {
            "batch" => BatchCommand(positionalArgs, options),
            "symbols" => SymbolsCommand(positionalArgs, options),
            "outline" => OutlineCommand(positionalArgs, options),
            "ast" => AstCommand(positionalArgs, options),
            "diagnostics" => DiagnosticsCommand(positionalArgs, options),
            "type" => TypeCommand(positionalArgs, options),
            "inspect" => InspectCommand(positionalArgs, options),
            "definition" or "def" => DefinitionCommand(positionalArgs, options),
            "references" or "refs" => ReferencesCommand(positionalArgs, options),
            "completions" => CompletionsCommand(positionalArgs, options),
            "doc" => DocCommand(positionalArgs, options),
            "hover" => HoverCommand(positionalArgs, options),
            "call-graph" => CallGraphCommand(positionalArgs, options),
            "perf" => PerformanceCommand(positionalArgs, options),
            "trusted" => TrustedCommand(positionalArgs, options),
            "implementors" => ImplementorsCommand(positionalArgs, options),
            "help" or "--help" or "-h" => ShowQueryHelp(),
            _ => QueryError(QueryCommandKernels.GetUnknownSubcommandMessage(subcommand))
        };
    }

    // ── Subcommands ─────────────────────────────────────────────────────

    private static int SymbolsCommand(string[] args, QueryOptions options)
    {
        var outputMode = GetTextJsonOutputMode(options.UseText);
        if (TryExecuteViaDaemon(options, DaemonConstants.MethodSymbols, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var summary = GetDaemonParameterSummary(args);
        var commandSummary = GetCommandOptionSummary(args);
        SymbolKind? kindFilter = null;
        var kindArg = summary.Kind;
        if (kindArg != null && QueryCommandKernels.TryParseSymbolKind(kindArg, out var parsed))
        {
            kindFilter = parsed;
        }

        var fileFilter = summary.File ?? options.File;
        var filterPattern = commandSummary.Filter;

        var results = Service.GetSymbols(snapshot, fileFilter, kindFilter);

        // Apply fuzzy/glob filter: * = wildcard, bare string = substring match
        if (!string.IsNullOrWhiteSpace(filterPattern))
        {
            if (!QuerySymbolNameFilter.TryFilter(results, filterPattern, 200, out var filteredResults))
                throw new InvalidOperationException("N# query symbol-name filter kernel rejected the pattern.");

            results = filteredResults;
        }

        if (outputMode == QueryTextJsonOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.SymbolsToText(results));
        }
        else
        {
            Console.Write(OutputFormatter.SymbolsToJson(results, snapshot.ProjectRoot));
        }

        return 0;
    }

    private static int AstCommand(string[] args, QueryOptions options)
    {
        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var summary = GetDaemonParameterSummary(args);
        var fileFilter = summary.File ?? options.File;
        var normalizedFilter = fileFilter?.Replace('\\', '/');

        var units = new List<(string File, CompilationUnit Unit)>();
        foreach (var pair in snapshot.CompilationUnits.OrderBy(static kvp => kvp.Key, StringComparer.Ordinal))
        {
            if (normalizedFilter != null)
            {
                var normalizedPath = pair.Key.Replace('\\', '/');
                var matches =
                    string.Equals(normalizedPath, normalizedFilter, StringComparison.OrdinalIgnoreCase) ||
                    normalizedPath.EndsWith("/" + normalizedFilter, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(Path.GetFileName(normalizedPath), Path.GetFileName(normalizedFilter), StringComparison.OrdinalIgnoreCase);
                if (!matches) continue;
            }

            units.Add((pair.Key, pair.Value));
        }

        if (units.Count == 0)
        {
            return fileFilter != null
                ? QueryError(QueryCommandKernels.GetNoCompilationUnitForFileMessage(fileFilter))
                : QueryError(QueryCommandKernels.GetNoCompilationUnitsMessage());
        }

        // The AST is structured data; `ast` always emits the stable JSON envelope (LLM-first).
        Console.Write(OutputFormatter.AstToJson(units));
        return 0;
    }

    private static int HoverCommand(string[] args, QueryOptions options)
    {
        var outputMode = GetTextJsonOutputMode(options.UseText);
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("hover"));
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr));
        }

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var result = Service.GetHoverInfo(snapshot, file, line, col);
        if (result == null)
        {
            if (outputMode == QueryTextJsonOutputModeKind.Text)
            {
                Console.Error.WriteLine(QueryCommandKernels.GetNoSymbolAtPositionMessage(file, line, col));
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson(
                    "hover",
                    QueryCommandKernels.GetNoSymbolAtPositionMessage(file, line, col),
                    GetProjectRoot(options),
                    "noSymbol",
                    new
                    {
                        file = NormalizePath(file),
                        position = new { line, column = col }
                    }));
            }
            return 1;
        }

        if (outputMode == QueryTextJsonOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.HoverToText(result, file, line, col));
        }
        else
        {
            Console.Write(OutputFormatter.HoverToJson(result, file, line, col));
        }

        return 0;
    }

    private static int CallGraphCommand(string[] args, QueryOptions options)
    {
        var outputMode = GetTextJsonOutputMode(options.UseText);
        var commandSummary = GetCommandOptionSummary(args);
        var functionName = commandSummary.Function;
        var limit = GetCallGraphLimit(commandSummary.Limit);

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var result = Service.GetCallGraph(snapshot, functionName, limit);

        if (outputMode == QueryTextJsonOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.CallGraphToText(result));
        }
        else
        {
            Console.Write(OutputFormatter.CallGraphToJson(result));
        }

        return 0;
    }

    private static int GetCallGraphLimit(string? limitStr)
    {
        const int defaultLimit = 100;
        if (limitStr != null && TryParsePositiveInt(limitStr, out var parsedLimit))
            return parsedLimit;

        return defaultLimit;
    }

    private static int PerformanceCommand(string[] args, QueryOptions options)
    {
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("perf"));
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr));
        }

        if (GetJsonOnlyOutputMode(options.UseText) == QueryJsonOnlyOutputModeKind.TextUnsupported)
        {
            return QueryError(QueryCommandKernels.GetPerformanceJsonOnlyMessage());
        }

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var facts = new List<object>();
        if (snapshot.PerformanceFacts != null)
        {
            foreach (var (key, value) in snapshot.PerformanceFacts.All)
            {
                if (MatchesFile(key.File, file) && key.Line == line && key.Column == col)
                {
                    facts.Add(new
                    {
                        source = "performanceFacts",
                        file = NormalizePath(key.File ?? file),
                        line = key.Line,
                        column = key.Column,
                        allocation = value.Allocation.ToString(),
                        capture = value.Capture.ToString(),
                        dispatch = value.Dispatch.ToString(),
                        escape = value.Escape.ToString(),
                        valueLayout = value.ValueLayout.ToString(),
                        aotSafety = value.AotSafety.ToString()
                    });
                }
            }
        }

        foreach (var finding in snapshot.SystemsReport.Findings)
        {
            if (MatchesFile(finding.File, file) && finding.Line == line)
            {
                facts.Add(new
                {
                    source = "systems",
                    finding.Code,
                    finding.Severity,
                    finding.Effect,
                    finding.Message,
                    finding.Function,
                    finding.Policy,
                    finding.Suggestion
                });
            }
        }

        foreach (var function in snapshot.SystemsReport.Functions)
        {
            if (MatchesFile(function.File, file) && function.Line == line)
            {
                facts.Add(new
                {
                    source = "systemsFunction",
                    function.Name,
                    function.IsHot,
                    function.IsBoundary,
                    function.AllocNone,
                    function.SummarySource,
                    function.Effects,
                    function.Calls
                });
            }
        }

        Console.Write(OutputFormatter.PerfToJson(file, line, col, snapshot.ProjectRoot, facts));
        return 0;
    }

    private static int TrustedCommand(string[] args, QueryOptions options)
    {
        if (GetJsonOnlyOutputMode(options.UseText) == QueryJsonOnlyOutputModeKind.TextUnsupported)
        {
            return QueryError(QueryCommandKernels.GetTrustedJsonOnlyMessage());
        }

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        Console.Write(OutputFormatter.TrustedToJson(snapshot.SystemsReport, snapshot.ProjectRoot));
        return 0;
    }

    private static bool MatchesFile(string? candidate, string query)
    {
        if (string.IsNullOrWhiteSpace(candidate))
            return false;

        var normalizedCandidate = NormalizePath(candidate);
        var normalizedQuery = NormalizePath(query);
        return string.Equals(normalizedCandidate, normalizedQuery, StringComparison.OrdinalIgnoreCase)
            || normalizedCandidate.EndsWith("/" + normalizedQuery, StringComparison.OrdinalIgnoreCase)
            || normalizedCandidate.EndsWith(normalizedQuery, StringComparison.OrdinalIgnoreCase);
    }

    private static int ImplementorsCommand(string[] args, QueryOptions options)
    {
        var outputMode = GetTextJsonOutputMode(options.UseText);
        var summary = GetDaemonParameterSummary(args);
        var name = summary.Name;
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        // Name-based lookup (primary)
        if (name != null)
        {
            var snapshot = LoadProjectOrFail(options);
            if (snapshot == null) return 1;

            var result = Service.GetImplementors(snapshot, name);

            if (outputMode == QueryTextJsonOutputModeKind.Text)
            {
                Console.Write(OutputFormatter.ImplementorsToText(result));
            }
            else
            {
                Console.Write(OutputFormatter.ImplementorsToJson(result));
            }

            return result.Results.Count > 0 ? 0 : 1;
        }

        // Position-based: resolve the interface name at position, then find implementors
        if (file != null && posStr != null)
        {
            if (!TryParsePosition(posStr, out var line, out var col))
            {
                return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr));
            }

            var snapshot = LoadProjectOrFail(options);
            if (snapshot == null) return 1;

            var definition = Service.FindDefinition(snapshot, file, line, col);
            if (definition == null || !string.Equals(definition.Kind, "interface", StringComparison.OrdinalIgnoreCase))
            {
                if (outputMode == QueryTextJsonOutputModeKind.Text)
                {
                    Console.Error.WriteLine(QueryCommandKernels.GetNoInterfaceAtPositionMessage(file, line, col));
                }
                else
                {
                    Console.Write(OutputFormatter.ErrorToJson(
                        "implementors",
                        QueryCommandKernels.GetNoInterfaceAtPositionMessage(file, line, col),
                        GetProjectRoot(options),
                        "noInterface",
                        new
                        {
                            file = NormalizePath(file),
                            position = new { line, column = col }
                        }));
                }
                return 1;
            }

            var result = Service.GetImplementors(snapshot, definition.Name);

            if (outputMode == QueryTextJsonOutputModeKind.Text)
            {
                Console.Write(OutputFormatter.ImplementorsToText(result));
            }
            else
            {
                Console.Write(OutputFormatter.ImplementorsToJson(result));
            }

            return result.Results.Count > 0 ? 0 : 1;
        }

        return QueryError(QueryCommandKernels.GetImplementorsUsageMessage());
    }

    private static int BatchCommand(string[] args, QueryOptions options)
    {
        if (GetJsonOnlyOutputMode(options.UseText) == QueryJsonOnlyOutputModeKind.TextUnsupported)
        {
            return QueryError(QueryCommandKernels.GetBatchJsonOnlyMessage());
        }

        var commandSummary = GetCommandOptionSummary(args);
        var requestsPath = commandSummary.Requests ?? commandSummary.LeadingOperand;

        if (string.IsNullOrWhiteSpace(requestsPath))
        {
            return QueryError(QueryCommandKernels.GetBatchUsageMessage());
        }

        List<BatchQueryRequest> requests;
        try
        {
            requests = BatchQueryRunner.LoadRequests(requestsPath);
        }
        catch (Exception ex)
        {
            Console.Write(OutputFormatter.ErrorToJson(
                "batch",
                ex.Message,
                GetProjectRoot(options),
                "invalidRequestsFile",
                new { requests = NormalizePath(requestsPath) }));
            return 1;
        }

        if (requests.Count == 0)
        {
            Console.Write(OutputFormatter.ErrorToJson(
                "batch",
                QueryCommandKernels.GetEmptyBatchMessage(),
                GetProjectRoot(options),
                "emptyBatch",
                new { requests = NormalizePath(requestsPath) }));
            return 1;
        }

        if (TryExecuteViaDaemon(
                options,
                DaemonConstants.MethodBatch,
                new Dictionary<string, object?> { ["requests"] = requests },
                out var daemonExitCode))
        {
            return daemonExitCode;
        }

        ProjectSnapshot? snapshot = null;
        var execution = BatchQueryRunner.Execute(
            requests,
            GetProjectRoot(options),
            () => snapshot ??= LoadProjectOrThrow(options),
            Service,
            new CompletionEngine());

        Console.Write(execution.Json);
        return execution.Ok ? 0 : 1;
    }

    private static int OutlineCommand(string[] args, QueryOptions options)
    {
        var outputMode = GetTextJsonOutputMode(options.UseText);
        // Outline can work on a single file without full project analysis
        var commandSummary = GetCommandOptionSummary(args);
        var file = commandSummary.LeadingOperand ?? options.File;

        if (file == null)
        {
            return QueryError(QueryCommandKernels.GetOutlineUsageMessage());
        }

        var projectRoot = options.ProjectDir ?? Directory.GetCurrentDirectory();
        var filePath = Path.IsPathRooted(file) ? file : Path.Combine(projectRoot, file);

        if (!File.Exists(filePath))
        {
            return QueryError(QueryCommandKernels.GetFileNotFoundMessage(filePath));
        }

        // Use single-file fast path
        var result = Service.GetOutlineSingleFile(filePath);

        // Make the file path relative to project root for output
        result = result with { File = GetRelativePath(projectRoot, filePath) };

        if (outputMode == QueryTextJsonOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.OutlineToText(result));
        }
        else
        {
            Console.Write(OutputFormatter.OutlineToJson(result));
        }

        return 0;
    }

    private static int DiagnosticsCommand(string[] args, QueryOptions options)
    {
        var parameterSummary = GetDaemonParameterSummary(args);
        var wantsClusters = parameterSummary.Clusters;
        var outputMode = GetDiagnosticsOutputMode(options.UseText, wantsClusters);
        if (TryExecuteViaDaemon(options, DaemonConstants.MethodDiagnostics, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var fileFilter = parameterSummary.File ?? options.File;
        var results = Service.GetDiagnostics(snapshot, fileFilter);

        // Filter by severity if requested
        var severityFilter = parameterSummary.Severity;
        if (severityFilter != null)
        {
            results = OutputFormatter.FilterDiagnosticsBySeverity(results, severityFilter);
        }

        var summary = OutputFormatter.SummarizeDiagnostics(results);
        if (outputMode == QueryDiagnosticsOutputModeKind.ClustersJson)
        {
            Console.Write(OutputFormatter.DiagnosticClustersToJson(results, snapshot.ProjectRoot));
        }
        else if (outputMode == QueryDiagnosticsOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.DiagnosticsToText(results));
        }
        else
        {
            Console.Write(OutputFormatter.DiagnosticsToJson(results, snapshot.ProjectRoot));
        }

        return summary.Errors > 0 ? 1 : 0;
    }

    private static int TypeCommand(string[] args, QueryOptions options)
    {
        var outputMode = GetTextJsonOutputMode(options.UseText);
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("type"));
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr));
        }

        if (TryExecuteViaDaemon(options, DaemonConstants.MethodType, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var result = Service.GetTypeAtPosition(snapshot, file, line, col);
        if (result == null)
        {
            if (outputMode == QueryTextJsonOutputModeKind.Text)
            {
                Console.Error.WriteLine(QueryCommandKernels.GetNoTypeInformationAtPositionMessage(file, line, col));
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson(
                    "type",
                    QueryCommandKernels.GetNoSymbolAtPositionMessage(file, line, col),
                    GetProjectRoot(options),
                    "noSymbol",
                    new
                    {
                        file = NormalizePath(file),
                        position = new { line, column = col }
                    }));
            }
            return 1;
        }

        if (outputMode == QueryTextJsonOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.TypeToText(result, file, line, col));
        }
        else
        {
            Console.Write(OutputFormatter.TypeToJson(result, file, line, col));
        }

        return 0;
    }

    private static int DefinitionCommand(string[] args, QueryOptions options)
    {
        var outputMode = GetTextJsonOutputMode(options.UseText);
        var summary = GetDaemonParameterSummary(args);
        var commandSummary = GetCommandOptionSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;
        var name = summary.Name ?? commandSummary.LeadingOperand;

        // Position-based (primary, semantic)
        if (file != null && posStr != null)
        {
            if (!TryParsePosition(posStr, out var line, out var col))
            {
                return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr));
            }

            if (TryExecuteViaDaemon(options, DaemonConstants.MethodDefinition, BuildDaemonParameters(args, options), out var daemonExitCode))
                return daemonExitCode;

            var snapshot = LoadProjectOrFail(options);
            if (snapshot == null) return 1;

            var result = Service.FindDefinition(snapshot, file, line, col);
            if (result == null)
            {
                if (outputMode == QueryTextJsonOutputModeKind.Text)
                {
                    Console.Error.WriteLine(QueryCommandKernels.GetNoDefinitionAtPositionMessage(file, line, col));
                }
                else
                {
                    Console.Write(OutputFormatter.ErrorToJson(
                        "definition",
                        QueryCommandKernels.GetNoSymbolAtPositionMessage(file, line, col),
                        GetProjectRoot(options),
                        "noSymbol",
                        new
                        {
                            file = NormalizePath(file),
                            position = new { line, column = col }
                        }));
                }
                return 1;
            }

            if (outputMode == QueryTextJsonOutputModeKind.Text)
            {
                Console.Write(OutputFormatter.DefinitionToText(result));
            }
            else
            {
                Console.Write(OutputFormatter.DefinitionToJson(result));
            }

            return 0;
        }

        // Name-based (search sugar)
        if (name != null)
        {
            if (TryExecuteViaDaemon(options, DaemonConstants.MethodDefinition, new Dictionary<string, object?>
            {
                ["name"] = name
            }, out var daemonExitCode))
                return daemonExitCode;

            var snapshot = LoadProjectOrFail(options);
            if (snapshot == null) return 1;

            var results = Service.FindDefinitionByName(snapshot, name);

            if (outputMode == QueryTextJsonOutputModeKind.Text)
            {
                Console.Write(OutputFormatter.DefinitionSearchToText(name, results));
            }
            else
            {
                Console.Write(OutputFormatter.DefinitionSearchToJson(name, results));
            }

            return results.Count > 0 ? 0 : 1;
        }

        return QueryError(QueryCommandKernels.GetDefinitionUsageMessage());
    }

    private static int InspectCommand(string[] args, QueryOptions options)
    {
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;
        var outputMode = GetInspectOutputMode(options.UseText, options.InspectCompact);
        var compactMode = outputMode == QueryInspectOutputModeKind.CompactJson;

        if (file == null || posStr == null)
        {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("inspect"));
        }

        if (outputMode == QueryInspectOutputModeKind.InvalidCompactText)
        {
            return QueryError(QueryCommandKernels.GetInspectCompactTextUnsupportedMessage());
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr));
        }

        if (TryExecuteViaDaemon(options, DaemonConstants.MethodInspect, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var type = Service.GetTypeAtPosition(snapshot, file, line, col);
        var definition = Service.FindDefinition(snapshot, file, line, col);
        var references = Service.FindReferences(snapshot, file, line, col);

        var includeKeywords = summary.IncludeKeywords;
        var engine = new CompletionEngine();
        var completions = engine.GetCompletions(snapshot, file, line, col, includeKeywords);

        InspectSymbolResult? symbol = null;
        if (definition != null)
        {
            symbol = new InspectSymbolResult(
                definition.Name,
                definition.Kind,
                new LocationResult(definition.File, definition.Line, definition.Column));
        }
        else if (type != null)
        {
            symbol = new InspectSymbolResult(type.Name, type.Kind, type.Definition);
        }

        var inspect = new InspectResult(
            symbol,
            type,
            definition,
            new InspectReferencesResult(
                references.Count,
                references.Count(r => r.IsDefinition),
                references.ToArray()),
            completions);

        if (type == null && definition == null && references.Count == 0)
        {
            if (outputMode == QueryInspectOutputModeKind.Text)
            {
                Console.Error.WriteLine(QueryCommandKernels.GetNoSymbolAtPositionMessage(file, line, col));
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson(
                    "inspect",
                    QueryCommandKernels.GetNoSymbolAtPositionMessage(file, line, col),
                    GetProjectRoot(options),
                    "noSymbol",
                    new
                    {
                        file = NormalizePath(file),
                        position = new { line, column = col }
                    }));
            }

            return 1;
        }

        if (outputMode == QueryInspectOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.InspectToText(inspect, file, line, col));
        }
        else
        {
            Console.Write(compactMode
                ? OutputFormatter.InspectSummaryToJson(inspect, file, line, col)
                : OutputFormatter.InspectToJson(inspect, file, line, col));
        }

        return 0;
    }

    private static int ReferencesCommand(string[] args, QueryOptions options)
    {
        var outputMode = GetTextJsonOutputMode(options.UseText);
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError(QueryCommandKernels.GetReferencesUsageMessage());
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr));
        }

        if (TryExecuteViaDaemon(options, DaemonConstants.MethodReferences, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        // First resolve what symbol is at this position
        var definition = Service.FindDefinition(snapshot, file, line, col);
        if (definition == null)
        {
            if (outputMode == QueryTextJsonOutputModeKind.Text)
            {
                Console.Error.WriteLine(QueryCommandKernels.GetNoSymbolAtPositionMessage(file, line, col));
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson(
                    "references",
                    QueryCommandKernels.GetNoSymbolAtPositionMessage(file, line, col),
                    GetProjectRoot(options),
                    "noSymbol",
                    new
                    {
                        file = NormalizePath(file),
                        position = new { line, column = col }
                    }));
            }

            return 1;
        }

        var symbolName = definition.Name;
        var symbolKind = definition.Kind;
        LocationResult definedAt = new(definition.File, definition.Line, definition.Column);

        var results = Service.FindReferences(snapshot, file, line, col);
        if (results.Count == 0)
        {
            var message = QueryCommandKernels.GetSemanticReferencesUnavailableMessage();

            if (outputMode == QueryTextJsonOutputModeKind.Text)
            {
                Console.Error.WriteLine(message);
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson(
                    "references",
                    message,
                    GetProjectRoot(options),
                    "semanticReferencesUnavailable",
                    new
                    {
                        file = NormalizePath(file),
                        position = new { line, column = col },
                        symbol = new { name = symbolName, kind = symbolKind, definedAt }
                    }));
            }

            return 1;
        }

        if (outputMode == QueryTextJsonOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.ReferencesToText(symbolName, results));
        }
        else
        {
            Console.Write(OutputFormatter.ReferencesToJson(symbolName, symbolKind, definedAt, results));
        }

        return 0;
    }

    private static int CompletionsCommand(string[] args, QueryOptions options)
    {
        var outputMode = GetTextJsonOutputMode(options.UseText);
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("completions"));
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr));
        }

        if (TryExecuteViaDaemon(options, DaemonConstants.MethodCompletions, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var includeKeywords = summary.IncludeKeywords;
        var engine = new CompletionEngine();
        var result = engine.GetCompletions(snapshot, file, line, col, includeKeywords);

        if (outputMode == QueryTextJsonOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.CompletionsToText(result, file, line, col));
        }
        else
        {
            Console.Write(OutputFormatter.CompletionsToJson(result, file, line, col));
        }

        return 0;
    }

    private static readonly Lazy<DocQuery> _docQuery = new(() =>
    {
        var dq = new DocQuery();
        dq.LoadSystemAssemblies();
        return dq;
    });

    private static int DocCommand(string[] args, QueryOptions options)
    {
        var commandSummary = GetCommandOptionSummary(args);
        var query = commandSummary.LeadingOperand;
        var outputMode = GetTextJsonOutputMode(options.UseText);

        if (query == null)
        {
            return QueryError(QueryCommandKernels.GetDocUsageMessage());
        }

        var result = _docQuery.Value.Lookup(query);
        if (result == null)
        {
            if (outputMode == QueryTextJsonOutputModeKind.Text)
            {
                Console.Error.WriteLine(QueryCommandKernels.GetNoDocumentationMessage(query));
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson("doc", QueryCommandKernels.GetNoDocumentationMessage(query)));
            }
            return 1;
        }

        if (outputMode == QueryTextJsonOutputModeKind.Text)
        {
            Console.Write(OutputFormatter.DocToText(result));
        }
        else
        {
            Console.Write(OutputFormatter.DocToJson(result, query));
        }

        return 0;
    }

    // ── Option Parsing ──────────────────────────────────────────────────

    private record QueryOptions(
        string? ProjectDir,
        string? File,
        string? Pos,
        bool UseText,
        bool NoDaemon,
        bool InspectCompact);

    private static QueryOptions ParseOptions(string[] args, out string subcommand, out string[] remainingArgs)
    {
        var summary = GetTopLevelOptionSummary(args);
        subcommand = summary.Subcommand ?? string.Empty;
        remainingArgs = summary.RemainingArgs;
        return new QueryOptions(
            summary.ProjectDir,
            summary.File,
            summary.Pos,
            summary.UseText,
            summary.NoDaemon,
            summary.InspectCompact);
    }

    internal static QueryTopLevelOptionSummary GetTopLevelOptionSummary(string[] args)
        => QueryCommandKernels.GetTopLevelOptionSummary(args);

    private static bool TryParsePosition(string posStr, out int line, out int col)
        => QueryCommandKernels.ParsePosition(posStr, out line, out col);

    private static bool TryParsePositiveInt(string value, out int parsed)
        => QueryCommandKernels.ParsePositiveInt(value, out parsed);

    internal static QueryInspectOutputModeKind GetInspectOutputMode(bool useText, bool inspectCompact)
        => QueryCommandKernels.GetInspectOutputMode(useText, inspectCompact);

    internal static QueryDiagnosticsOutputModeKind GetDiagnosticsOutputMode(bool useText, bool clusters)
        => QueryCommandKernels.GetDiagnosticsOutputMode(useText, clusters);

    internal static QueryJsonOnlyOutputModeKind GetJsonOnlyOutputMode(bool useText)
        => QueryCommandKernels.GetJsonOnlyOutputMode(useText);

    internal static QueryTextJsonOutputModeKind GetTextJsonOutputMode(bool useText)
        => QueryCommandKernels.GetTextJsonOutputMode(useText);

    private static ProjectSnapshot? LoadProjectOrFail(QueryOptions options)
    {
        var projectDir = GetProjectRoot(options);

        if (!Directory.Exists(projectDir))
        {
            Console.Error.WriteLine(QueryCommandKernels.GetProjectDirectoryNotFoundMessage(projectDir));
            return null;
        }

        try
        {
            var config = ProjectFileParser.ParseFromDirectory(projectDir) ?? ProjectFileParser.CreateDefault(Path.GetFileName(projectDir));
            // `nlc query` is a read-only/LLM-first inspection path: it must never spawn `dotnet build`
            // for project references (multi-second stalls + the build-pipe deadlock) (H4). Resolve
            // package/already-resolved references only; cross-project resolution requires `nlc build`.
            CompilationReferenceResolver.AddResolvedDllReferences(
                projectDir,
                config,
                new ReferenceResolutionOptions(Quiet: true, BuildProjectReferences: false));
            return Service.LoadProject(projectDir, config);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(QueryCommandKernels.GetFailedAnalyzeProjectMessage(ex.Message));
            return null;
        }
    }

    private static ProjectSnapshot LoadProjectOrThrow(QueryOptions options)
    {
        var projectDir = GetProjectRoot(options);

        if (!Directory.Exists(projectDir))
        {
            throw new DirectoryNotFoundException(QueryCommandKernels.GetProjectDirectoryNotFoundMessage(projectDir));
        }

        var config = ProjectFileParser.ParseFromDirectory(projectDir) ?? ProjectFileParser.CreateDefault(Path.GetFileName(projectDir));
        // Read-only query path: never spawn `dotnet build` for project references (H4).
        CompilationReferenceResolver.AddResolvedDllReferences(
            projectDir,
            config,
            new ReferenceResolutionOptions(Quiet: true, BuildProjectReferences: false));
        return Service.LoadProject(projectDir, config);
    }

    private static string GetRelativePath(string basePath, string filePath)
    {
        try { return Path.GetRelativePath(basePath, filePath); }
        catch { return filePath; }
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private static string GetProjectRoot(QueryOptions options)
        => Path.GetFullPath(options.ProjectDir ?? Directory.GetCurrentDirectory());

    private static Dictionary<string, object?> BuildDaemonParameters(string[] args, QueryOptions options)
    {
        var parameters = new Dictionary<string, object?>();
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var pos = summary.Pos ?? options.Pos;
        var name = summary.Name;
        var kind = summary.Kind;
        var severity = summary.Severity;
        var includeKeywords = summary.IncludeKeywords;
        var compactMode = options.InspectCompact;
        var clusters = summary.Clusters;

        if (!string.IsNullOrWhiteSpace(file))
            parameters["file"] = file;
        if (!string.IsNullOrWhiteSpace(pos))
            parameters["pos"] = pos;
        if (!string.IsNullOrWhiteSpace(name))
            parameters["name"] = name;
        if (!string.IsNullOrWhiteSpace(kind))
            parameters["kind"] = kind;
        if (!string.IsNullOrWhiteSpace(severity))
            parameters["severity"] = severity;
        if (includeKeywords)
            parameters["includeKeywords"] = true;
        if (compactMode)
            parameters["summary"] = true;
        if (clusters)
            parameters["clusters"] = true;

        return parameters;
    }

    internal static QueryDaemonParameterSummary GetDaemonParameterSummary(string[] args)
        => QueryCommandKernels.GetDaemonParameterSummary(args);

    internal static QueryCommandOptionSummary GetCommandOptionSummary(string[] args)
        => QueryCommandKernels.GetCommandOptionSummary(args);

    private static bool TryExecuteViaDaemon(QueryOptions options, string method,
        Dictionary<string, object?> parameters, out int exitCode)
    {
        exitCode = 0;
        if (!ShouldTryExecuteViaDaemon(options.UseText, options.NoDaemon))
            return false;

        var projectRoot = GetProjectRoot(options);
        if (!Directory.Exists(projectRoot))
            return false;

        if (!DaemonClient.IsRunning(projectRoot))
            return false;

        var response = DaemonClient.QueryResponse(projectRoot, method, parameters);
        if (response == null)
            return false;

        if (response.Error != null)
        {
            Console.Error.WriteLine(JsonSerializer.Serialize(response));
            exitCode = 1;
            return true;
        }

        var result = response.Result;
        if (string.IsNullOrWhiteSpace(result))
            return false;

        Console.Write(result);
        exitCode = GetJsonExitCode(result);
        return true;
    }

    internal static bool ShouldTryExecuteViaDaemon(bool useText, bool noDaemon)
        => QueryCommandKernels.ShouldUseDaemon(useText, noDaemon);

    private static int GetJsonExitCode(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.TryGetProperty("ok", out var okElement))
                return okElement.ValueKind == JsonValueKind.True ? 0 : 1;
        }
        catch
        {
            // Fall back to success when daemon returned malformed/non-envelope JSON.
        }

        return 0;
    }

    private static int QueryError(string message)
    {
        Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(message));
        return 1;
    }

    private static string FormatQueryDescription(CliCommandSpec command)
    {
        var aliases = CommandRegistry.QueryCommands
            .Where(candidate => string.Equals(candidate.AliasOf, command.Name, StringComparison.Ordinal))
            .Select(candidate => candidate.Name)
            .ToArray();

        return QueryCommandKernels.GetDescriptionWithAliases(
            command.Description,
            string.Join(", ", aliases));
    }

    private static int ShowQueryHelp()
    {
        var commandLines = string.Join(Environment.NewLine, CommandRegistry.QueryCommands
            .Where(command => !command.IsAlias)
            .Select(command => $"  {command.Name,-13} {FormatQueryDescription(command)}"));

        Console.WriteLine(QueryCommandKernels.GetHelpText(commandLines));

        return 0;
    }
}
