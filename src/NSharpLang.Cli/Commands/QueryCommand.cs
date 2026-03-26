using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli;
using NSharpLang.Cli.Daemon;
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
            "diagnostics" => DiagnosticsCommand(positionalArgs, options),
            "type" => TypeCommand(positionalArgs, options),
            "inspect" => InspectCommand(positionalArgs, options),
            "definition" or "def" => DefinitionCommand(positionalArgs, options),
            "references" or "refs" => ReferencesCommand(positionalArgs, options),
            "completions" => CompletionsCommand(positionalArgs, options),
            "doc" => DocCommand(positionalArgs, options),
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

        SymbolKind? kindFilter = null;
        var kindArg = GetOption(args, "--kind");
        if (kindArg != null && Enum.TryParse<SymbolKind>(kindArg, ignoreCase: true, out var parsed))
        {
            kindFilter = parsed;
        }

        var fileFilter = GetOption(args, "--file") ?? options.File;

        var results = Service.GetSymbols(snapshot, fileFilter, kindFilter);

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

    private static int BatchCommand(string[] args, QueryOptions options)
    {
        if (options.UseText)
        {
            return QueryError("Batch queries only support JSON output.");
        }

        var requestsPath = GetOption(args, "--requests")
            ?? (args.Length > 0 && !args[0].StartsWith("--", StringComparison.Ordinal) ? args[0] : null);

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
        var file = args.Length > 0 ? args[0] : options.File;

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
        if (TryExecuteViaDaemon(options, DaemonConstants.MethodDiagnostics, BuildDaemonParameters(args, options), out var daemonExitCode))
            return daemonExitCode;

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        var fileFilter = GetOption(args, "--file") ?? options.File;
        var results = Service.GetDiagnostics(snapshot, fileFilter);

        // Filter by severity if requested
        var severityFilter = GetOption(args, "--severity");
        if (severityFilter != null)
        {
            results = results.Where(d => d.Severity.Equals(severityFilter, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        if (options.UseText)
        {
            Console.Write(OutputFormatter.DiagnosticsToText(results));
        }
        else
        {
            Console.Write(OutputFormatter.DiagnosticsToJson(results, snapshot.ProjectRoot));
        }

        return results.Any(d => d.Severity == "error") ? 1 : 0;
    }

    private static int TypeCommand(string[] args, QueryOptions options)
    {
        var file = GetOption(args, "--file") ?? options.File;
        var posStr = GetOption(args, "--pos") ?? options.Pos;

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
        var file = GetOption(args, "--file") ?? options.File;
        var posStr = GetOption(args, "--pos") ?? options.Pos;
        var name = GetOption(args, "--name") ?? (args.Length > 0 && !args[0].StartsWith("--") ? args[0] : null);

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
        var file = GetOption(args, "--file") ?? options.File;
        var posStr = GetOption(args, "--pos") ?? options.Pos;
        var summaryMode = options.InspectSummary;

        if (file == null || posStr == null)
        {
            return QueryError("Usage: nlc query inspect --file <path> --pos <line>:<col>");
        }

        if (summaryMode && options.UseText)
        {
            return QueryError("--summary is only supported with JSON output.");
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

        var includeKeywords = args.Contains("--include-keywords");
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
            Console.Write(summaryMode
                ? OutputFormatter.InspectSummaryToJson(inspect, file, line, col)
                : OutputFormatter.InspectToJson(inspect, file, line, col));
        }

        return 0;
    }

    private static int ReferencesCommand(string[] args, QueryOptions options)
    {
        var file = GetOption(args, "--file") ?? options.File;
        var posStr = GetOption(args, "--pos") ?? options.Pos;

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
        var file = GetOption(args, "--file") ?? options.File;
        var posStr = GetOption(args, "--pos") ?? options.Pos;

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

        var includeKeywords = args.Contains("--include-keywords");
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
        var query = args.Length > 0 && !args[0].StartsWith("--") ? args[0] : null;

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
        bool InspectSummary);

    private static QueryOptions ParseOptions(string[] args, out string subcommand, out string[] remainingArgs)
    {
        string? projectDir = null;
        string? file = null;
        string? pos = null;
        var useText = false;
        var noDaemon = false;
        var inspectSummary = false;

        subcommand = args[0];
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
                    inspectSummary = true;
                    break;
                default:
                    remaining.Add(args[i]);
                    break;
            }
        }

        remainingArgs = remaining.ToArray();
        return new QueryOptions(projectDir, file, pos, useText, noDaemon, inspectSummary);
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
            return Service.LoadProject(projectDir);
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

        return Service.LoadProject(projectDir);
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
        var file = GetOption(args, "--file") ?? options.File;
        var pos = GetOption(args, "--pos") ?? options.Pos;
        var name = GetOption(args, "--name");
        var kind = GetOption(args, "--kind");
        var severity = GetOption(args, "--severity");
        var includeKeywords = args.Contains("--include-keywords");
        var summaryMode = options.InspectSummary;

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
        if (summaryMode)
            parameters["summary"] = true;

        return parameters;
    }

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

        var result = DaemonClient.Query(projectRoot, method, parameters);
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

    private static int ShowQueryHelp()
    {
        Console.WriteLine(@"N# Code Intelligence CLI

Usage: nlc query <command> [options]

Commands:
  batch         Execute multiple query requests from one JSON file
  symbols       List all symbols in a file or project
  outline       Structural outline of a file
  diagnostics   Errors and warnings with rich context
  type          Get type info at a position
  inspect       One-shot symbol/type/refs/completions bundle
  definition    Find where a symbol is defined (aliases: def)
  references    Find all references to a symbol (aliases: refs)
  completions   Get completions at a position (LLM-optimized)
  doc           Look up .NET API documentation

Global Options:
  --json        Output as JSON (default)
  --text        Output as human-readable text (Elm-style)
  --no-daemon   Force in-process analysis even if a daemon is running
  --project     Project root directory (default: current directory)
  --file        Target file for file-scoped operations
  --pos         Position as line:col (e.g. 5:12)

Examples:
  nlc query symbols                          # All symbols in project
  nlc query batch --requests requests.json   # Mixed semantic queries in one call
  nlc query symbols --file Program.nl        # Symbols in one file
  nlc query symbols --kind function          # Only functions
  nlc query outline Program.nl               # File structure
  nlc query diagnostics                      # All errors/warnings
  nlc query diagnostics --text               # Elm-style error output
  nlc query type --file Program.nl --pos 5:4 # Type at position
  nlc query inspect --file Program.nl --pos 5:4
  nlc query inspect --file Program.nl --pos 5:4 --summary
  nlc query def --file Program.nl --pos 5:4  # Definition at position
  nlc query def --name Person                # Search by name
  nlc query refs --file Program.nl --pos 5:4 # All references
  nlc query doc Console                      # Type documentation
  nlc query doc Console.WriteLine            # Method documentation
  nlc query doc List                         # Generic type docs

JSON queries reuse `nlc daemon` automatically when a daemon is already running.
Use `--no-daemon` to bypass the daemon for debugging.");

        return 0;
    }
}
