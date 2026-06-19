using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
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
            _ => QueryError($"Unknown query subcommand: {subcommand}. Run 'nlc query help' for usage.")
        };
    }

    // ── Subcommands ─────────────────────────────────────────────────────

    private static int SymbolsCommand(string[] args, QueryOptions options)
    {
        if (TryExecuteViaDaemon(options, DaemonConstants.MethodSymbols, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var summary = GetDaemonParameterSummary(args);
        var commandSummary = GetCommandOptionSummary(args);
        SymbolKind? kindFilter = null;
        var kindArg = summary.Kind;
        if (kindArg != null && Enum.TryParse<SymbolKind>(kindArg, ignoreCase: true, out var parsed))
        {
            kindFilter = parsed;
        }

        var fileFilter = summary.File ?? options.File;
        var filterPattern = commandSummary.Filter;

        var results = Service.GetSymbols(snapshot, fileFilter, kindFilter);

        // Apply fuzzy/glob filter: * = wildcard, bare string = substring match
        if (!string.IsNullOrWhiteSpace(filterPattern))
        {
            results = QuerySymbolNameFilter.TryFilter(
                    results,
                    filterPattern,
                    200,
                    out var dogfoodResults)
                ? dogfoodResults
                : FilterSymbolsByNamePatternWithRegex(results, filterPattern);
        }

        if (options.UseText)
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
                ? QueryError($"No compilation unit found for --file {fileFilter}")
                : QueryError("No compilation units in project.");
        }

        // The AST is structured data; `ast` always emits the stable JSON envelope (LLM-first).
        Console.Write(OutputFormatter.AstToJson(units));
        return 0;
    }

    private static List<SymbolResult> FilterSymbolsByNamePatternWithRegex(
        IReadOnlyList<SymbolResult> symbols,
        string pattern)
    {
        var regex = BuildSymbolFilterRegex(pattern);
        return symbols.Where(s => regex.IsMatch(s.Name)).Take(200).ToList();
    }

    private static Regex BuildSymbolFilterRegex(string pattern)
    {
        // If the pattern contains *, treat it as a glob: * -> .*
        // Otherwise, treat it as a case-insensitive substring match
        if (pattern.Contains('*'))
        {
            var regexPattern = "^" + Regex.Escape(pattern).Replace("\\*", ".*") + "$";
            return new Regex(regexPattern, RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(200));
        }
        return new Regex(Regex.Escape(pattern), RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(200));
    }

    private static int HoverCommand(string[] args, QueryOptions options)
    {
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError("Usage: nlc query hover --file <path> --pos <line>:<col>");
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError($"Invalid position format: {posStr}. Expected <line>:<col> (e.g. 5:12)");
        }

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var result = Service.GetHoverInfo(snapshot, file, line, col);
        if (result == null)
        {
            if (options.UseText)
            {
                Console.Error.WriteLine($"No symbol found at {file}:{line}:{col}");
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson(
                    "hover",
                    $"No symbol found at {file}:{line}:{col}",
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

        if (options.UseText)
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
        var commandSummary = GetCommandOptionSummary(args);
        var functionName = commandSummary.Function;
        var limitStr = commandSummary.Limit;
        var limit = 100;
        if (limitStr != null && int.TryParse(limitStr, out var parsedLimit) && parsedLimit > 0)
        {
            limit = parsedLimit;
        }

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var result = Service.GetCallGraph(snapshot, functionName, limit);

        if (options.UseText)
        {
            Console.Write(OutputFormatter.CallGraphToText(result));
        }
        else
        {
            Console.Write(OutputFormatter.CallGraphToJson(result));
        }

        return 0;
    }

    private static int PerformanceCommand(string[] args, QueryOptions options)
    {
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError("Usage: nlc query perf --file <path> --pos <line>:<col>");
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError($"Invalid position format: {posStr}. Expected <line>:<col> (e.g. 5:12)");
        }

        if (options.UseText)
        {
            return QueryError("Performance facts are only available as JSON output.");
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
        if (options.UseText)
        {
            return QueryError("Trusted-site reports are only available as JSON output.");
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

            if (options.UseText)
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
                return QueryError($"Invalid position format: {posStr}. Expected <line>:<col> (e.g. 5:12)");
            }

            var snapshot = LoadProjectOrFail(options);
            if (snapshot == null) return 1;

            var definition = Service.FindDefinition(snapshot, file, line, col);
            if (definition == null || !string.Equals(definition.Kind, "interface", StringComparison.OrdinalIgnoreCase))
            {
                if (options.UseText)
                {
                    Console.Error.WriteLine($"No interface found at {file}:{line}:{col}");
                }
                else
                {
                    Console.Write(OutputFormatter.ErrorToJson(
                        "implementors",
                        $"No interface found at {file}:{line}:{col}",
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

            if (options.UseText)
            {
                Console.Write(OutputFormatter.ImplementorsToText(result));
            }
            else
            {
                Console.Write(OutputFormatter.ImplementorsToJson(result));
            }

            return result.Results.Count > 0 ? 0 : 1;
        }

        return QueryError("Usage: nlc query implementors --name <interface>\n       nlc query implementors --file <path> --pos <line>:<col>");
    }

    private static int BatchCommand(string[] args, QueryOptions options)
    {
        if (options.UseText)
        {
            return QueryError("Batch queries only support JSON output.");
        }

        var commandSummary = GetCommandOptionSummary(args);
        var requestsPath = commandSummary.Requests ?? commandSummary.LeadingOperand;

        if (string.IsNullOrWhiteSpace(requestsPath))
        {
            return QueryError("Usage: nlc query batch --requests <path-to-json>");
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
                "Batch request file did not contain any requests.",
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
        // Outline can work on a single file without full project analysis
        var commandSummary = GetCommandOptionSummary(args);
        var file = commandSummary.LeadingOperand ?? options.File;

        if (file == null)
        {
            return QueryError("Usage: nlc query outline <file>");
        }

        var projectRoot = options.ProjectDir ?? Directory.GetCurrentDirectory();
        var filePath = Path.IsPathRooted(file) ? file : Path.Combine(projectRoot, file);

        if (!File.Exists(filePath))
        {
            return QueryError($"File not found: {filePath}");
        }

        // Use single-file fast path
        var result = Service.GetOutlineSingleFile(filePath);

        // Make the file path relative to project root for output
        result = result with { File = GetRelativePath(projectRoot, filePath) };

        if (options.UseText)
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
        if (wantsClusters)
        {
            Console.Write(OutputFormatter.DiagnosticClustersToJson(results, snapshot.ProjectRoot));
        }
        else if (options.UseText)
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
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError("Usage: nlc query type --file <path> --pos <line>:<col>");
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError($"Invalid position format: {posStr}. Expected <line>:<col> (e.g. 5:12)");
        }

        if (TryExecuteViaDaemon(options, DaemonConstants.MethodType, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var result = Service.GetTypeAtPosition(snapshot, file, line, col);
        if (result == null)
        {
            if (options.UseText)
            {
                Console.Error.WriteLine($"No type information found at {file}:{line}:{col}");
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson(
                    "type",
                    $"No symbol found at {file}:{line}:{col}",
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

        if (options.UseText)
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
                return QueryError($"Invalid position format: {posStr}. Expected <line>:<col> (e.g. 5:12)");
            }

            if (TryExecuteViaDaemon(options, DaemonConstants.MethodDefinition, BuildDaemonParameters(args, options), out var daemonExitCode))
                return daemonExitCode;

            var snapshot = LoadProjectOrFail(options);
            if (snapshot == null) return 1;

            var result = Service.FindDefinition(snapshot, file, line, col);
            if (result == null)
            {
                if (options.UseText)
                {
                    Console.Error.WriteLine($"No definition found at {file}:{line}:{col}");
                }
                else
                {
                    Console.Write(OutputFormatter.ErrorToJson(
                        "definition",
                        $"No symbol found at {file}:{line}:{col}",
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

            if (options.UseText)
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

            if (options.UseText)
            {
                Console.Write(OutputFormatter.DefinitionSearchToText(name, results));
            }
            else
            {
                Console.Write(OutputFormatter.DefinitionSearchToJson(name, results));
            }

            return results.Count > 0 ? 0 : 1;
        }

        return QueryError("Usage: nlc query definition --file <path> --pos <line>:<col>\n       nlc query definition --name <name>");
    }

    private static int InspectCommand(string[] args, QueryOptions options)
    {
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;
        var compactMode = options.InspectCompact;

        if (file == null || posStr == null)
        {
            return QueryError("Usage: nlc query inspect --file <path> --pos <line>:<col>");
        }

        if (compactMode && options.UseText)
        {
            return QueryError("--compact/--summary is only supported with JSON output.");
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError($"Invalid position format: {posStr}. Expected <line>:<col> (e.g. 5:12)");
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
            if (options.UseText)
            {
                Console.Error.WriteLine($"No symbol found at {file}:{line}:{col}");
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson(
                    "inspect",
                    $"No symbol found at {file}:{line}:{col}",
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

        if (options.UseText)
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
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError("Usage: nlc query references --file <path> --pos <line>:<col>\n\nThis is a semantic operation. Position-based only — no name-based shortcut.");
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError($"Invalid position format: {posStr}. Expected <line>:<col> (e.g. 5:12)");
        }

        if (TryExecuteViaDaemon(options, DaemonConstants.MethodReferences, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        // First resolve what symbol is at this position
        var definition = Service.FindDefinition(snapshot, file, line, col);
        if (definition == null)
        {
            if (options.UseText)
            {
                Console.Error.WriteLine($"No symbol found at {file}:{line}:{col}");
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson(
                    "references",
                    $"No symbol found at {file}:{line}:{col}",
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
            const string message =
                "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. " +
                "No name-based or text-based fallback was used.";

            if (options.UseText)
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

        if (options.UseText)
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
        var summary = GetDaemonParameterSummary(args);
        var file = summary.File ?? options.File;
        var posStr = summary.Pos ?? options.Pos;

        if (file == null || posStr == null)
        {
            return QueryError("Usage: nlc query completions --file <path> --pos <line>:<col>");
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError($"Invalid position format: {posStr}. Expected <line>:<col> (e.g. 5:12)");
        }

        if (TryExecuteViaDaemon(options, DaemonConstants.MethodCompletions, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var includeKeywords = summary.IncludeKeywords;
        var engine = new CompletionEngine();
        var result = engine.GetCompletions(snapshot, file, line, col, includeKeywords);

        if (options.UseText)
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

        if (query == null)
        {
            return QueryError("Usage: nlc query doc <type-or-member>\n\nExamples:\n  nlc query doc Console\n  nlc query doc Console.WriteLine\n  nlc query doc List\n  nlc query doc System.IO.File");
        }

        var result = _docQuery.Value.Lookup(query);
        if (result == null)
        {
            if (options.UseText)
            {
                Console.Error.WriteLine($"No documentation found for '{query}'.");
            }
            else
            {
                Console.Write(OutputFormatter.ErrorToJson("doc", $"No documentation found for '{query}'."));
            }
            return 1;
        }

        if (options.UseText)
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
    {
        if (QueryCommandKernels.TryGetTopLevelOptionSummary(args, out var summary))
            return summary;

        return GetTopLevelOptionSummaryWithCSharp(args);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product query top-level option parsing routes through QueryCommandKernels.
    private static QueryTopLevelOptionSummary GetTopLevelOptionSummaryWithCSharp(string[] args)
    {
        string? projectDir = null;
        string? file = null;
        string? pos = null;
        var useText = false;
        var noDaemon = false;
        var inspectCompact = false;

        var subcommand = args.Length > 0 ? args[0] : null;
        var remaining = new List<string>();

        for (int i = 1; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--project" when i + 1 < args.Length:
                    projectDir = args[++i];
                    break;
                case "--file" when i + 1 < args.Length:
                    file = args[++i];
                    break;
                case "--pos" when i + 1 < args.Length:
                    pos = args[++i];
                    break;
                case "--text":
                    useText = true;
                    break;
                case "--json":
                    useText = false;
                    break;
                case "--no-daemon":
                    noDaemon = true;
                    break;
                case "--summary":
                case "--compact":
                    inspectCompact = true;
                    break;
                default:
                    remaining.Add(args[i]);
                    break;
            }
        }

        return new QueryTopLevelOptionSummary(
            subcommand,
            projectDir,
            file,
            pos,
            useText,
            noDaemon,
            inspectCompact,
            remaining.ToArray());
    }

    private static string? GetOption(string[] args, string flag)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == flag)
                return args[i + 1];
        }
        return null;
    }

    private static bool TryParsePosition(string posStr, out int line, out int col)
    {
        line = 0;
        col = 0;
        var parts = posStr.Split(':');
        if (parts.Length != 2) return false;
        return int.TryParse(parts[0], out line) && int.TryParse(parts[1], out col);
    }

    private static ProjectSnapshot? LoadProjectOrFail(QueryOptions options)
    {
        var projectDir = GetProjectRoot(options);

        if (!Directory.Exists(projectDir))
        {
            Console.Error.WriteLine($"Project directory not found: {projectDir}");
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
            Console.Error.WriteLine($"Failed to analyze project: {ex.Message}");
            return null;
        }
    }

    private static ProjectSnapshot LoadProjectOrThrow(QueryOptions options)
    {
        var projectDir = GetProjectRoot(options);

        if (!Directory.Exists(projectDir))
        {
            throw new DirectoryNotFoundException($"Project directory not found: {projectDir}");
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
    {
        if (QueryCommandKernels.TryGetDaemonParameterSummary(args, out var summary))
            return summary;

        return GetDaemonParameterSummaryWithCSharp(args);
    }

    internal static QueryCommandOptionSummary GetCommandOptionSummary(string[] args)
    {
        if (QueryCommandKernels.TryGetCommandOptionSummary(args, out var summary))
            return summary;

        return GetCommandOptionSummaryWithCSharp(args);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; query daemon parameter parsing routes through QueryCommandKernels.
    private static QueryDaemonParameterSummary GetDaemonParameterSummaryWithCSharp(string[] args)
        => new(
            GetOption(args, "--file"),
            GetOption(args, "--pos"),
            GetOption(args, "--name"),
            GetOption(args, "--kind"),
            GetOption(args, "--severity"),
            args.Contains("--include-keywords"),
            args.Contains("--clusters"));

    // Stage 6 C#-surface-shrink: fallback/oracle only; query command-option parsing routes through QueryCommandKernels.
    private static QueryCommandOptionSummary GetCommandOptionSummaryWithCSharp(string[] args)
        => new(
            GetOption(args, "--filter"),
            GetOption(args, "--function"),
            GetOption(args, "--limit"),
            GetOption(args, "--requests"),
            args.Length > 0 && !args[0].StartsWith("--", StringComparison.Ordinal) ? args[0] : null);

    private static bool TryExecuteViaDaemon(QueryOptions options, string method,
        Dictionary<string, object?> parameters, out int exitCode)
    {
        exitCode = 0;
        if (options.UseText || options.NoDaemon)
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
        Console.Error.WriteLine($"Error: {message}");
        return 1;
    }

    private static string FormatQueryDescription(CliCommandSpec command)
    {
        var aliases = CommandRegistry.QueryCommands
            .Where(candidate => string.Equals(candidate.AliasOf, command.Name, StringComparison.Ordinal))
            .Select(candidate => candidate.Name)
            .ToArray();

        return aliases.Length == 0
            ? command.Description
            : $"{command.Description} (aliases: {string.Join(", ", aliases)})";
    }

    private static int ShowQueryHelp()
    {
        var commandLines = string.Join(Environment.NewLine, CommandRegistry.QueryCommands
            .Where(command => !command.IsAlias)
            .Select(command => $"  {command.Name,-13} {FormatQueryDescription(command)}"));

        Console.WriteLine($@"N# Code Intelligence CLI

Usage: nlc query <command> [options]

Commands:
{commandLines}

Global Options:
  --json        Output as JSON (default)
  --text        Output as human-readable text (Elm-style)
  --no-daemon   Force in-process analysis even if a daemon is running
  --project     Project root directory (default: current directory)
  --file        Target file for file-scoped operations
  --pos         Position as line:col (e.g. 5:12)
  --compact     For inspect, emit the compact token-efficient envelope (alias: --summary)
  --clusters    For diagnostics, emit the stable diagnostic-cluster JSON envelope

Examples:
  nlc query symbols                              # All symbols in project
  nlc query symbols --filter '*Person*'          # Symbols matching glob
  nlc query symbols --filter Person              # Symbols matching substring
  nlc query batch --requests requests.json       # Mixed semantic queries in one call
  nlc query symbols --file Program.nl            # Symbols in one file
  nlc query symbols --kind function              # Only functions
  nlc query outline Program.nl                   # File structure
  nlc query diagnostics                          # All errors/warnings
  nlc query diagnostics --clusters               # Diagnostic clusters
  nlc query diagnostics --text                   # Elm-style error output
  nlc query type --file Program.nl --pos 5:4     # Type at position
  nlc query inspect --file Program.nl --pos 5:4
  nlc query inspect --file Program.nl --pos 5:4 --compact
  nlc query def --file Program.nl --pos 5:4      # Definition at position
  nlc query def --name Person                    # Search by name
  nlc query refs --file Program.nl --pos 5:4     # All references
  nlc query hover --file Program.nl --pos 5:4    # Signature + docs at position
  nlc query call-graph --function Main           # Callers/callees of Main
  nlc query call-graph --function Main --limit 50
  nlc query implementors --name IShape           # Types implementing IShape
  nlc query implementors --file Program.nl --pos 10:11
  nlc query perf --file Program.nl --pos 5:4     # Allocation/dispatch/ABI facts
  nlc query trusted                              # Governed [trusted] wrappers
  nlc query doc Console                          # Type documentation
  nlc query doc Console.WriteLine                # Method documentation
  nlc query doc List                             # Generic type docs

JSON queries reuse `nlc daemon` automatically when a daemon is already running.
Use `--no-daemon` to bypass the daemon for debugging.");

        return 0;
    }
}
