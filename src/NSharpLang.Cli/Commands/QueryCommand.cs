using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
                Console.Write(OutputFormatter.ErrorToJson("type", $"No type information found at {file}:{line}:{col}"));
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
                    Console.Write(OutputFormatter.ErrorToJson("definition", $"No definition found at {file}:{line}:{col}"));
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

        if (file == null || posStr == null)
        {
            return QueryError("Usage: nlc query inspect --file <path> --pos <line>:<col>");
        }

        if (!TryParsePosition(posStr, out var line, out var col))
        {
            return QueryError($"Invalid position format: {posStr}. Expected <line>:<col> (e.g. 5:12)");
        }

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

        if (options.UseText)
        {
            Console.Write(OutputFormatter.InspectToText(inspect, file, line, col));
        }
        else
        {
            Console.Write(OutputFormatter.InspectToJson(inspect, file, line, col));
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

        var snapshot = LoadProjectOrFail(options);
        if (snapshot == null) return 1;

        // First resolve what symbol is at this position
        var definition = Service.FindDefinition(snapshot, file, line, col);
        var symbolName = definition?.Name ?? "unknown";
        var symbolKind = definition?.Kind ?? "unknown";
        LocationResult? definedAt = definition != null
            ? new LocationResult(definition.File, definition.Line, definition.Column)
            : null;

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
        bool UseText);

    private static QueryOptions ParseOptions(string[] args, out string subcommand, out string[] remainingArgs)
    {
        string? projectDir = null;
        string? file = null;
        string? pos = null;
        var useText = false;

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
                default:
                    remaining.Add(args[i]);
                    break;
            }
        }

        remainingArgs = remaining.ToArray();
        return new QueryOptions(projectDir, file, pos, useText);
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
        var projectDir = options.ProjectDir ?? Directory.GetCurrentDirectory();

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

    private static string GetRelativePath(string basePath, string filePath)
    {
        try { return Path.GetRelativePath(basePath, filePath); }
        catch { return filePath; }
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
  --project     Project root directory (default: current directory)
  --file        Target file for file-scoped operations
  --pos         Position as line:col (e.g. 5:12)

Examples:
  nlc query symbols                          # All symbols in project
  nlc query symbols --file Program.nl        # Symbols in one file
  nlc query symbols --kind function          # Only functions
  nlc query outline Program.nl               # File structure
  nlc query diagnostics                      # All errors/warnings
  nlc query diagnostics --text               # Elm-style error output
  nlc query type --file Program.nl --pos 5:4 # Type at position
  nlc query inspect --file Program.nl --pos 5:4
  nlc query def --file Program.nl --pos 5:4  # Definition at position
  nlc query def --name Person                # Search by name
  nlc query refs --file Program.nl --pos 5:4 # All references
  nlc query doc Console                      # Type documentation
  nlc query doc Console.WriteLine            # Method documentation
  nlc query doc List                         # Generic type docs");

        return 0;
    }
}
