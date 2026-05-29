using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Formats code intelligence results as either JSON (default, for LLM consumption)
/// or Elm-style text (--text, for human consumption).
///
/// JSON output uses a versioned envelope: { schemaVersion, command, ... }
/// Text output uses Elm-inspired formatting with clear headers, source snippets, and suggestions.
/// </summary>
public static class OutputFormatter
{
    private const int SchemaVersion = 1;
    private const int InspectSummaryReferenceSampleSize = 5;
    private const int InspectSummaryCompletionSampleSize = 8;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private static string? NormalizePath(string? path) => path?.Replace('\\', '/');

    private static SymbolResult Normalize(SymbolResult result) =>
        result with
        {
            File = NormalizePath(result.File) ?? result.File,
            Members = result.Members?.Select(Normalize).ToArray()
        };

    private static OutlineResult Normalize(OutlineResult result) =>
        result with
        {
            File = NormalizePath(result.File) ?? result.File,
            Outline = result.Outline.Select(Normalize).ToArray()
        };

    private static OutlineEntry Normalize(OutlineEntry entry) =>
        entry with
        {
            Children = entry.Children?.Select(Normalize).ToArray()
        };

    private static DiagnosticResult Normalize(DiagnosticResult result) =>
        result with
        {
            File = NormalizePath(result.File) ?? result.File
        };

    private static TypeResult Normalize(TypeResult result) =>
        result with
        {
            Definition = result.Definition != null ? Normalize(result.Definition) : null
        };

    private static DefinitionResult Normalize(DefinitionResult result) =>
        result with
        {
            File = NormalizePath(result.File) ?? result.File
        };

    private static ReferenceResult Normalize(ReferenceResult result) =>
        result with
        {
            File = NormalizePath(result.File) ?? result.File
        };

    private static LocationResult Normalize(LocationResult result) =>
        result with
        {
            File = NormalizePath(result.File) ?? result.File
        };

    private static InspectSymbolResult Normalize(InspectSymbolResult result) =>
        result with
        {
            Definition = result.Definition != null ? Normalize(result.Definition) : null
        };

    private static InspectReferencesResult Normalize(InspectReferencesResult result) =>
        result with
        {
            Results = result.Results.Select(Normalize).ToArray()
        };

    private static InspectResult Normalize(InspectResult result) =>
        result with
        {
            Symbol = result.Symbol != null ? Normalize(result.Symbol) : null,
            Type = result.Type != null ? Normalize(result.Type) : null,
            Definition = result.Definition != null ? Normalize(result.Definition) : null,
            References = Normalize(result.References)
        };

    private static InspectReferenceSummaryResult Normalize(InspectReferenceSummaryResult result) =>
        result with
        {
            File = NormalizePath(result.File) ?? result.File
        };

    private static InspectSummaryReferencesResult Normalize(InspectSummaryReferencesResult result) =>
        result with
        {
            Files = result.Files.Select(file => NormalizePath(file) ?? file).ToArray(),
            Sample = result.Sample.Select(Normalize).ToArray()
        };

    private static InspectSummaryResult Normalize(InspectSummaryResult result) =>
        result with
        {
            Definition = result.Definition != null ? Normalize(result.Definition) : null,
            References = Normalize(result.References)
        };

    // ── JSON Output ────────────────────────────────────────────────────

    public static string SymbolsToJson(List<SymbolResult> results, string? projectRoot = null)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "symbols",
            ok = true,
            projectRoot = NormalizePath(projectRoot),
            results = results.Select(Normalize).ToList()
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string OutlineToJson(OutlineResult result)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "outline",
            ok = true,
            file = NormalizePath(result.File),
            imports = result.Imports,
            outline = Normalize(result).Outline
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string DiagnosticsToJson(List<DiagnosticResult> results, string? projectRoot = null)
    {
        var summary = new DiagnosticSummary(
            Errors: results.Count(d => d.Severity == "error"),
            Warnings: results.Count(d => d.Severity == "warning"),
            Info: results.Count(d => d.Severity == "info")
        );
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "diagnostics",
            ok = summary.Errors == 0,
            projectRoot = NormalizePath(projectRoot),
            results = results.Select(Normalize).ToList(),
            summary
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string DiagnosticClustersToJson(List<DiagnosticResult> results, string? projectRoot = null)
    {
        var summary = new DiagnosticSummary(
            Errors: results.Count(d => d.Severity == "error"),
            Warnings: results.Count(d => d.Severity == "warning"),
            Info: results.Count(d => d.Severity == "info")
        );
        var clusters = BuildDiagnosticClusters(results);
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "diagnostics.clusters",
            ok = summary.Errors == 0,
            projectRoot = NormalizePath(projectRoot),
            clusters,
            summary
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string CheckToJson(List<DiagnosticResult> results, string? projectRoot, int checkedFiles)
    {
        var summary = new DiagnosticSummary(
            Errors: results.Count(d => d.Severity == "error"),
            Warnings: results.Count(d => d.Severity == "warning"),
            Info: results.Count(d => d.Severity == "info")
        );

        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "check",
            projectRoot = NormalizePath(projectRoot),
            checkedFiles,
            ok = summary.Errors == 0,
            results = results.Select(Normalize).ToList(),
            summary
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string LintToJson(List<DiagnosticResult> results, string? projectRoot, int lintedFiles)
    {
        var summary = new DiagnosticSummary(
            Errors: results.Count(d => d.Severity == "error"),
            Warnings: results.Count(d => d.Severity == "warning"),
            Info: results.Count(d => d.Severity == "info")
        );

        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "lint",
            projectRoot = NormalizePath(projectRoot),
            lintedFiles,
            ok = summary.Errors == 0,
            results = results.Select(Normalize).ToList(),
            summary
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string TypeToJson(TypeResult result, string file, int line, int col)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "type",
            ok = true,
            file = NormalizePath(file),
            position = new { line, column = col },
            result = Normalize(result)
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    /// <summary>
    /// Emits the versioned performance report envelope for <c>nlc build --perf-report</c>.
    /// The report groups performance facts by category. Until the compiler wires up a
    /// performance-fact source, the categories are emitted as empty arrays so the
    /// envelope shape is stable for downstream consumers.
    /// </summary>
    public static string BuildPerfReportToJson(string? projectRoot, bool ok = true)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "build",
            ok,
            projectRoot = NormalizePath(projectRoot),
            perfReport = new
            {
                allocationSites = Array.Empty<object>(),
                delegateSites = Array.Empty<object>(),
                boxingSites = Array.Empty<object>(),
                dispatchSites = Array.Empty<object>(),
                closureCaptures = Array.Empty<object>(),
                aotBlockers = Array.Empty<object>()
            }
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string PerfToJson(string file, int line, int col, string? projectRoot,
        IReadOnlyList<object>? facts = null)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "perf",
            ok = true,
            projectRoot = NormalizePath(projectRoot),
            file = NormalizePath(file),
            position = new { line, column = col },
            facts = facts ?? Array.Empty<object>()
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string DefinitionToJson(DefinitionResult result)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "definition",
            ok = true,
            result = Normalize(result)
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string DefinitionSearchToJson(string name, List<DefinitionResult> results)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "definition",
            ok = results.Count > 0,
            query = new { name },
            results = results.Select(Normalize).ToList(),
            note = results.Count > 1
                ? "Multiple matches. Use --file --pos for unambiguous semantic resolution."
                : (string?)null
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string ReferencesToJson(string symbolName, string symbolKind,
        LocationResult? definedAt, List<ReferenceResult> results)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "references",
            ok = true,
            symbol = new { name = symbolName, kind = symbolKind, definedAt = definedAt != null ? Normalize(definedAt) : null },
            count = results.Count,
            results = results.Select(Normalize).ToList()
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string CompletionsToJson(CompletionResult result, string file, int line, int col)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "completions",
            ok = true,
            file = NormalizePath(file),
            position = new { line, column = col },
            context = result.Context.ToString().ToLowerInvariant(),
            receiver = result.Receiver != null ? new { name = result.Receiver, type = result.ReceiverType } : null,
            completions = result.Completions
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string InspectToJson(InspectResult result, string file, int line, int col)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "inspect",
            ok = true,
            file = NormalizePath(file),
            position = new { line, column = col },
            result = Normalize(result)
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string InspectSummaryToJson(InspectResult result, string file, int line, int col)
    {
        var summary = Normalize(ToInspectSummary(result));
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "inspect",
            ok = true,
            file = NormalizePath(file),
            position = new { line, column = col },
            summary
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string CompletionsToText(CompletionResult result, string file, int line, int col)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"Completions at {file}:{line}:{col} (context: {result.Context.ToString().ToLowerInvariant()})");

        if (result.Receiver != null)
        {
            sb.AppendLine($"Receiver: {result.Receiver}" + (result.ReceiverType != null ? $" ({result.ReceiverType})" : ""));
        }

        sb.AppendLine();

        foreach (var (category, items) in result.Completions)
        {
            sb.AppendLine($"  {category} ({items.Count}):");
            foreach (var item in items.Take(50)) // Limit for text output
            {
                var typeStr = item.Type != null ? $": {item.Type}" : "";
                var paramStr = item.Parameters != null ? $" {item.Parameters}" : "";
                sb.AppendLine($"    {item.Name}{paramStr}{typeStr}");
            }
            if (items.Count > 50)
            {
                sb.AppendLine($"    ... and {items.Count - 50} more");
            }
        }

        return sb.ToString();
    }

    public static string InspectToText(InspectResult result, string file, int line, int col)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"Inspect {file}:{line}:{col}");
        sb.AppendLine();

        if (result.Symbol != null)
        {
            sb.AppendLine($"Symbol: {result.Symbol.Name} ({result.Symbol.Kind})");
            if (result.Symbol.Definition != null)
            {
                sb.AppendLine($"  Defined at: {result.Symbol.Definition.File}:{result.Symbol.Definition.Line}:{result.Symbol.Definition.Column}");
            }
        }
        else
        {
            sb.AppendLine("Symbol: none");
        }

        sb.AppendLine();

        if (result.Type != null)
        {
            sb.AppendLine($"Type: {result.Type.ResolvedType} ({result.Type.Kind})");
            if (!string.IsNullOrWhiteSpace(result.Type.Nullability))
                sb.AppendLine($"  Nullability: {result.Type.Nullability}");
        }
        else
        {
            sb.AppendLine("Type: unknown");
        }

        sb.AppendLine();

        if (result.Definition != null)
        {
            sb.AppendLine($"Definition: {result.Definition.Kind} {result.Definition.Name} at {result.Definition.File}:{result.Definition.Line}:{result.Definition.Column}");
        }
        else
        {
            sb.AppendLine("Definition: none");
        }

        sb.AppendLine();
        sb.AppendLine($"References: {result.References.Count} total ({result.References.DefinitionCount} definitions)");
        foreach (var reference in result.References.Results.Take(10))
        {
            var definitionMarker = reference.IsDefinition ? " [definition]" : "";
            var context = reference.Context != null ? $"  {reference.Context.Trim()}" : "";
            sb.AppendLine($"  {reference.File}:{reference.Line}:{reference.Column}{definitionMarker}{context}");
        }
        if (result.References.Count > 10)
        {
            sb.AppendLine($"  ... and {result.References.Count - 10} more");
        }

        sb.AppendLine();
        sb.Append(CompletionsToText(result.Completions, file, line, col));
        return sb.ToString();
    }

    public static string DocToJson(DocResult result, string query)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "doc",
            ok = true,
            query,
            result
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    // ── Hover ──────────────────────────────────────────────────────────────

    public static string HoverToJson(HoverResult result, string file, int line, int col)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "hover",
            ok = true,
            file = NormalizePath(file),
            position = new { line, column = col },
            result = new
            {
                signature = result.Signature,
                documentation = result.Documentation,
                definedIn = NormalizePath(result.DefinedIn),
                kind = result.Kind
            }
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string HoverToText(HoverResult result, string file, int line, int col)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"Hover {file}:{line}:{col}");
        sb.AppendLine();
        sb.AppendLine($"Signature:  {result.Signature}");
        sb.AppendLine($"Kind:       {result.Kind}");
        if (result.DefinedIn != null)
            sb.AppendLine($"Defined in: {result.DefinedIn}");
        if (!string.IsNullOrWhiteSpace(result.Documentation))
        {
            sb.AppendLine();
            sb.AppendLine("Documentation:");
            foreach (var docLine in result.Documentation.Split('\n'))
                sb.AppendLine($"  {docLine}");
        }
        return sb.ToString();
    }

    // ── Call Graph ─────────────────────────────────────────────────────────

    public static string CallGraphToJson(CallGraphResult result)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "callGraph",
            ok = true,
            function = result.Function,
            callers = result.Callers.Select(c => new
            {
                name = c.Name,
                file = NormalizePath(c.File),
                line = c.Line,
                column = c.Column
            }).ToList(),
            callees = result.Callees.Select(c => new
            {
                name = c.Name,
                file = NormalizePath(c.File),
                line = c.Line,
                column = c.Column
            }).ToList(),
            truncated = result.Truncated
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string CallGraphToText(CallGraphResult result)
    {
        var sb = new StringBuilder();
        if (result.Function != null)
            sb.AppendLine($"Call graph for: {result.Function}");
        else
            sb.AppendLine("Call graph (full project)");
        sb.AppendLine();

        sb.AppendLine($"Callers ({result.Callers.Count}):");
        foreach (var c in result.Callers)
            sb.AppendLine($"  {c.Name}  ({c.File}:{c.Line})");

        sb.AppendLine();
        sb.AppendLine($"Callees ({result.Callees.Count}):");
        foreach (var c in result.Callees)
            sb.AppendLine($"  {c.Name}  ({c.File}:{c.Line})");

        if (result.Truncated)
            sb.AppendLine("(results truncated — use --limit to increase)");

        return sb.ToString();
    }

    // ── Implementors ───────────────────────────────────────────────────────

    public static string ImplementorsToJson(ImplementorsResult result)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "implementors",
            ok = true,
            @interface = result.Interface,
            results = result.Results.Select(r => new
            {
                typeName = r.TypeName,
                kind = r.Kind,
                file = NormalizePath(r.File),
                line = r.Line,
                column = r.Column
            }).ToList()
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string ImplementorsToText(ImplementorsResult result)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"Implementors of {result.Interface} ({result.Results.Count}):");
        sb.AppendLine();
        foreach (var r in result.Results)
            sb.AppendLine($"  {r.Kind} {r.TypeName}  ({r.File}:{r.Line})");
        return sb.ToString();
    }

    // ── Error ──────────────────────────────────────────────────────────────

    public static string ErrorToJson(string command, string error, string? projectRoot = null,
        string? errorCode = null, object? details = null)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command,
            ok = false,
            projectRoot = NormalizePath(projectRoot),
            error = new
            {
                code = errorCode,
                message = error,
                details
            }
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    private static InspectSummaryResult ToInspectSummary(InspectResult result)
    {
        var groups = result.Completions.Completions
            .OrderBy(group => group.Key, StringComparer.Ordinal)
            .ToArray();

        var groupCounts = groups.ToDictionary(
            group => group.Key,
            group => group.Value.Count,
            StringComparer.Ordinal);

        var sampledGroups = groups.ToDictionary(
            group => group.Key,
            group => group.Value
                .Select(item => item.Name)
                .Distinct(StringComparer.Ordinal)
                .Take(InspectSummaryCompletionSampleSize)
                .ToArray(),
            StringComparer.Ordinal);

        var definition = result.Definition != null
            ? new LocationResult(result.Definition.File, result.Definition.Line, result.Definition.Column)
            : result.Symbol?.Definition;

        var referenceFiles = result.References.Results
            .Select(reference => NormalizePath(reference.File) ?? reference.File)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(file => file, StringComparer.Ordinal)
            .ToArray();

        var referenceSample = result.References.Results
            .Take(InspectSummaryReferenceSampleSize)
            .Select(reference => new InspectReferenceSummaryResult(
                reference.File,
                reference.Line,
                reference.Column,
                reference.IsDefinition))
            .ToArray();

        return new InspectSummaryResult(
            result.Symbol != null
                ? new InspectSummarySymbolResult(result.Symbol.Name, result.Symbol.Kind)
                : null,
            result.Type != null
                ? new InspectSummaryTypeResult(result.Type.Name, result.Type.ResolvedType, result.Type.Kind, result.Type.Nullability)
                : null,
            definition,
            new InspectSummaryReferencesResult(
                result.References.Count,
                result.References.DefinitionCount,
                referenceFiles,
                referenceSample),
            new InspectSummaryCompletionsResult(
                result.Completions.Context.ToString().ToLowerInvariant(),
                result.Completions.Receiver,
                result.Completions.ReceiverType,
                result.Completions.Completions.Sum(group => group.Value.Count),
                groupCounts,
                sampledGroups));
    }

    // ── Diagnostic Clustering ───────────────────────────────────────────

    private const int DiagnosticClusterExampleLimit = 3;

    private sealed record DiagnosticCluster(
        string Id,
        string Category,
        string Recipe,
        string Risk,
        int Count,
        string Severity,
        string[] Files,
        DiagnosticClusterRelatedDiagnostic[] RelatedDiagnostics,
        string NextCommand,
        DiagnosticClusterLocation RootLocation,
        string MessagePattern,
        string SourceConstruct,
        string[] SuggestedNextActions,
        DiagnosticClusterExample[] Examples);

    private sealed record DiagnosticClusterLocation(string File, int Line, int Column);

    private sealed record DiagnosticClusterRelatedDiagnostic(
        string Code,
        string Severity,
        string File,
        int Line,
        int Column,
        string Message);

    private sealed record DiagnosticClusterExample(
        string File,
        int Line,
        int Column,
        string Message,
        string? SourceSnippet,
        string? Suggestion);

    private sealed record DiagnosticClusterTraits(
        string Category,
        string SourceConstruct,
        string Recipe,
        string Risk,
        string MessagePattern,
        string[] SuggestedNextActions);

    private static List<DiagnosticCluster> BuildDiagnosticClusters(List<DiagnosticResult> results)
    {
        return results
            .Select(diagnostic => new { Diagnostic = Normalize(diagnostic), Traits = ClassifyDiagnostic(diagnostic) })
            .GroupBy(item => new
            {
                item.Diagnostic.Severity,
                item.Diagnostic.Code,
                item.Traits.Category,
                item.Traits.SourceConstruct,
                item.Traits.Recipe,
                item.Traits.Risk,
                item.Traits.MessagePattern
            })
            .Select(group =>
            {
                var ordered = group
                    .Select(item => item.Diagnostic)
                    .OrderBy(d => d.Line)
                    .ThenBy(d => d.Column)
                    .ThenBy(d => d.File, StringComparer.OrdinalIgnoreCase)
                    .ToList();
                var root = ordered.First();
                var traits = group.First().Traits;

                return new DiagnosticCluster(
                    Id: CreateClusterId(root.Code, root.Severity, traits.Category, traits.SourceConstruct, traits.Recipe, traits.MessagePattern),
                    Category: traits.Category,
                    Recipe: traits.Recipe,
                    Risk: traits.Risk,
                    Count: ordered.Count,
                    Severity: root.Severity,
                    Files: ordered.Select(d => d.File).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(file => file, StringComparer.OrdinalIgnoreCase).ToArray(),
                    RelatedDiagnostics: ordered.Select(d => new DiagnosticClusterRelatedDiagnostic(
                        d.Code,
                        d.Severity,
                        d.File,
                        d.Line,
                        d.Column,
                        d.Message)).ToArray(),
                    NextCommand: BuildDiagnosticClusterNextCommand(root),
                    RootLocation: new DiagnosticClusterLocation(root.File, root.Line, root.Column),
                    MessagePattern: traits.MessagePattern,
                    SourceConstruct: traits.SourceConstruct,
                    SuggestedNextActions: traits.SuggestedNextActions,
                    Examples: ordered.Take(DiagnosticClusterExampleLimit).Select(d => new DiagnosticClusterExample(
                        d.File,
                        d.Line,
                        d.Column,
                        d.Message,
                        string.IsNullOrWhiteSpace(d.SourceSnippet) ? null : d.SourceSnippet.Trim(),
                        string.IsNullOrWhiteSpace(d.Suggestion) ? null : d.Suggestion.Trim())).ToArray());
            })
            .OrderByDescending(cluster => cluster.Count)
            .ThenBy(cluster => cluster.RootLocation.File, StringComparer.OrdinalIgnoreCase)
            .ThenBy(cluster => cluster.RootLocation.Line)
            .ThenBy(cluster => cluster.RootLocation.Column)
            .ToList();
    }

    private static void AppendDiagnosticClusterSummary(StringBuilder sb, List<DiagnosticCluster> clusters)
    {
        if (clusters.Count == 0)
            return;

        var diagnosticCount = clusters.Sum(cluster => cluster.Count);
        sb.AppendLine($"Diagnostic clusters ({clusters.Count} group{(clusters.Count == 1 ? "" : "s")}, {diagnosticCount} diagnostic{(diagnosticCount == 1 ? "" : "s")})");
        foreach (var cluster in clusters.Take(10))
        {
            sb.AppendLine($"  [{cluster.Count}x] {cluster.Category} / {cluster.SourceConstruct} / risk: {cluster.Risk}");
            sb.AppendLine($"       recipe: {cluster.Recipe}");
            sb.AppendLine($"       root: {cluster.RootLocation.File}:{cluster.RootLocation.Line}:{cluster.RootLocation.Column}");
            sb.AppendLine($"       next command: {cluster.NextCommand}");
            sb.AppendLine($"       example: {cluster.Examples[0].Message}");
            foreach (var action in cluster.SuggestedNextActions.Take(2))
            {
                sb.AppendLine($"       next: {action}");
            }
        }
        if (clusters.Count > 10)
        {
            sb.AppendLine($"  ... {clusters.Count - 10} more cluster{(clusters.Count - 10 == 1 ? "" : "s")} omitted; use --json for the full AI-consumable cluster list.");
        }
        sb.AppendLine();
    }

    private static DiagnosticClusterTraits ClassifyDiagnostic(DiagnosticResult diagnostic)
    {
        var message = diagnostic.Message ?? string.Empty;
        var snippet = diagnostic.SourceSnippet ?? string.Empty;
        var code = diagnostic.Code ?? string.Empty;
        var messageLower = message.ToLowerInvariant();
        var snippetLower = snippet.ToLowerInvariant();

        if (code == "NL102" || messageLower.Contains("expected token") || messageLower.Contains("missing"))
        {
            var construct = InferSourceConstruct(snippetLower);
            var shape = messageLower.Contains(";", StringComparison.Ordinal) || messageLower.Contains("semicolon", StringComparison.Ordinal)
                ? "syntax-missing-terminator"
                : "syntax-missing-delimiter";
            var recipe = shape == "syntax-missing-terminator"
                ? "syntax:statement-boundary"
                : "syntax:delimiter-balancing";
            return new DiagnosticClusterTraits(
                shape,
                construct,
                recipe,
                "high",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Fix the earliest statement-boundary parse error first; later syntax diagnostics are often cascades.",
                    "Inspect the refactor or code-generation path that emitted this construct and add a delimiter/terminator regression test."
                });
        }

        if (code == "NL703" || messageLower.Contains("circular import"))
        {
            return new DiagnosticClusterTraits(
                "import-cycle",
                "import",
                "architecture:extract-shared-module-or-invert-dependency",
                "high",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Break the cycle at the reported import path by moving shared declarations into a third file/package or inverting one dependency.",
                    "Rerun `nlc check` after removing the cycle; unused-import warnings in the same files may be cascades."
                });
        }

        if (code == "NL301" || code == "NL412" || messageLower.Contains("undefined variable") || messageLower.Contains("undefined symbol"))
        {
            return new DiagnosticClusterTraits(
                "identifier-resolution",
                InferSourceConstruct(snippetLower),
                "symbols:missing-import-or-qualification",
                "medium",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Resolve the first missing identifier by adding the import/qualification or correcting the declaration name.",
                    "Rerun diagnostics after the root symbol is resolved; dependent member/type errors may disappear."
                });
        }

        if (code == "NL201" || code == "NL302" || messageLower.Contains("type not found") || messageLower.Contains("undefined type") || messageLower.Contains("cannot resolve type"))
        {
            return new DiagnosticClusterTraits(
                "type-resolution",
                InferSourceConstruct(snippetLower),
                "types:resolve-type-or-import",
                "medium",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Resolve the type/import at the earliest root location before chasing downstream uses.",
                    "Check whether the source construct needs full qualification or a project reference."
                });
        }

        if (code == "NL202" || messageLower.Contains("type mismatch"))
        {
            return new DiagnosticClusterTraits(
                "type-mismatch",
                InferSourceConstruct(snippetLower),
                "refactor:signature-or-expression-shape",
                "medium",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Compare the expected and actual types at the root example and update the refactor recipe that changed the expression/signature shape.",
                    "Prefer fixing the producer expression over adding casts to each cascaded consumer."
                });
        }

        if (code == "NL303" || messageLower.Contains("member") || messageLower.Contains("method"))
        {
            return new DiagnosticClusterTraits(
                "member-resolution",
                InferSourceConstruct(snippetLower),
                "members:api-rename-or-extension-import",
                "medium",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Verify the API/member name for the root receiver before fixing repeated call sites.",
                    "Check whether an extension-method import or receiver type conversion was dropped."
                });
        }

        return new DiagnosticClusterTraits(
            "diagnostic-message-shape",
            InferSourceConstruct(snippetLower),
            "manual-triage:inspect-root-diagnostic",
            "low",
            NormalizeMessagePattern(message),
            new[]
            {
                "Start at the root example and decide whether this is a source, refactor, or compiler diagnostic issue.",
                "After fixing the root cause, rerun diagnostics and compare the remaining cluster counts."
            });
    }

    private static string InferSourceConstruct(string sourceSnippetLower)
    {
        var snippet = sourceSnippetLower.TrimStart();
        if (snippet.StartsWith("let ", StringComparison.Ordinal) || snippet.Contains(" := ", StringComparison.Ordinal) || snippet.Contains(":=", StringComparison.Ordinal))
            return "variable-declaration";
        var declarationSnippet = StripLeadingDeclarationModifiers(snippet);
        if (declarationSnippet.StartsWith("func ", StringComparison.Ordinal) || declarationSnippet.StartsWith("func* ", StringComparison.Ordinal))
            return "function-declaration";
        if (snippet.StartsWith("class ", StringComparison.Ordinal))
            return "class-declaration";
        if (snippet.StartsWith("interface ", StringComparison.Ordinal))
            return "interface-declaration";
        if (snippet.StartsWith("import ", StringComparison.Ordinal) || snippet.StartsWith("using ", StringComparison.Ordinal))
            return "import";
        if (snippet.StartsWith("return ", StringComparison.Ordinal))
            return "return-statement";
        if (snippet.StartsWith("if ", StringComparison.Ordinal) || snippet.StartsWith("for ", StringComparison.Ordinal) || snippet.StartsWith("while ", StringComparison.Ordinal) || snippet.StartsWith("match ", StringComparison.Ordinal))
            return "control-flow";
        if (snippet.Contains("(", StringComparison.Ordinal) && snippet.Contains(")", StringComparison.Ordinal))
            return "call-or-construction";
        return "unknown-construct";
    }

    private static string StripLeadingDeclarationModifiers(string snippet)
    {
        while (true)
        {
            var trimmed = snippet.TrimStart();
            if (trimmed.StartsWith("async ", StringComparison.Ordinal))
            {
                snippet = trimmed["async ".Length..];
                continue;
            }

            if (trimmed.StartsWith("static ", StringComparison.Ordinal))
            {
                snippet = trimmed["static ".Length..];
                continue;
            }

            if (trimmed.StartsWith("override ", StringComparison.Ordinal))
            {
                snippet = trimmed["override ".Length..];
                continue;
            }

            if (trimmed.StartsWith("public ", StringComparison.Ordinal))
            {
                snippet = trimmed["public ".Length..];
                continue;
            }

            if (trimmed.StartsWith("private ", StringComparison.Ordinal))
            {
                snippet = trimmed["private ".Length..];
                continue;
            }

            if (trimmed.StartsWith("protected ", StringComparison.Ordinal))
            {
                snippet = trimmed["protected ".Length..];
                continue;
            }

            if (trimmed.StartsWith("internal ", StringComparison.Ordinal))
            {
                snippet = trimmed["internal ".Length..];
                continue;
            }

            return trimmed;
        }
    }

    private static string NormalizeMessagePattern(string message)
    {
        if (string.IsNullOrWhiteSpace(message))
            return "unknown-message";

        var builder = new StringBuilder(message.Length);
        var inQuoted = false;
        foreach (var c in message)
        {
            if (c == '\'' || c == '"')
            {
                inQuoted = !inQuoted;
                if (inQuoted)
                    builder.Append("{value}");
                continue;
            }

            if (!inQuoted)
            {
                builder.Append(char.IsDigit(c) ? '#' : c);
            }
        }

        return builder.ToString().Trim();
    }

    private static string CreateClusterId(string code, string severity, string category, string sourceConstruct, string recipe, string messagePattern)
    {
        var key = $"{code}|{severity}|{category}|{sourceConstruct}|{recipe}|{messagePattern}";
        var hash = 17;
        foreach (var c in key)
        {
            hash = (hash * 31) + c;
        }
        return $"diag-{Math.Abs(hash):x}";
    }

    private static string BuildDiagnosticClusterNextCommand(DiagnosticResult root)
    {
        var file = EscapeCommandArgument(root.File);
        return $"nlc query inspect --file {file} --pos {root.Line}:{root.Column}";
    }

    private static string EscapeCommandArgument(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return "\"\"";

        if (value.All(c => char.IsLetterOrDigit(c) || c is '/' or '.' or '_' or '-'))
            return value;

        return $"\"{value.Replace("\\", "\\\\").Replace("\"", "\\\"")}\"";
    }

    // ── Elm-Style Text Output ──────────────────────────────────────────

    public static string DiagnosticsToText(List<DiagnosticResult> results)
    {
        if (results.Count == 0)
            return "No diagnostics found.";

        var sb = new StringBuilder();
        var errors = results.Count(d => d.Severity == "error");
        var warnings = results.Count(d => d.Severity == "warning");
        var info = results.Count(d => d.Severity == "info");

        AppendDiagnosticClusterSummary(sb, BuildDiagnosticClusters(results));

        foreach (var diag in results)
        {
            sb.AppendLine(FormatSingleDiagnosticText(diag));
        }

        // Summary line
        sb.AppendLine();
        var parts = new List<string>();
        if (errors > 0) parts.Add($"{errors} error{(errors == 1 ? "" : "s")}");
        if (warnings > 0) parts.Add($"{warnings} warning{(warnings == 1 ? "" : "s")}");
        if (info > 0) parts.Add($"{info} info");
        sb.AppendLine($"Found {string.Join(", ", parts)}.");

        return sb.ToString();
    }

    private static string FormatSingleDiagnosticText(DiagnosticResult diag)
    {
        var sb = new StringBuilder();

        // Header line: ── ERROR TITLE ──────── file:line:col ──
        var title = FormatDiagnosticTitle(diag);
        var location = $"{diag.File}:{diag.Line}:{diag.Column}";
        var headerContent = $" {title} ";
        var locationPart = $" {location} ";
        var remainingWidth = Math.Max(0, 60 - headerContent.Length - locationPart.Length);
        var dashes = new string('\u2500', Math.Max(2, remainingWidth));

        sb.AppendLine($"\u2500\u2500{headerContent}{dashes}{locationPart}\u2500\u2500");
        sb.AppendLine();

        // Source snippet with line number and caret
        if (!string.IsNullOrWhiteSpace(diag.SourceSnippet))
        {
            var lineNumStr = diag.Line.ToString();
            var padding = new string(' ', lineNumStr.Length);
            sb.AppendLine($"    {lineNumStr} | {diag.SourceSnippet.TrimEnd()}");

            // Caret line
            var caretOffset = Math.Max(0, diag.Column - 1);
            var caretLine = new string(' ', caretOffset) + new string('^', Math.Max(1, diag.Length));
            sb.AppendLine($"    {padding} | {caretLine}");
        }

        sb.AppendLine();

        // Main message
        sb.AppendLine(diag.Message);

        // Explanation (the "why")
        if (!string.IsNullOrWhiteSpace(diag.Explanation))
        {
            sb.AppendLine();
            sb.AppendLine(diag.Explanation);
        }

        // Type mismatch details
        if (!string.IsNullOrWhiteSpace(diag.ExpectedType) || !string.IsNullOrWhiteSpace(diag.ActualType))
        {
            sb.AppendLine();
            if (!string.IsNullOrWhiteSpace(diag.ExpectedType))
                sb.AppendLine($"Expected: `{diag.ExpectedType}`");
            if (!string.IsNullOrWhiteSpace(diag.ActualType))
                sb.AppendLine($"  Actual: `{diag.ActualType}`");
        }

        // Hint
        if (!string.IsNullOrWhiteSpace(diag.Hint))
        {
            sb.AppendLine();
            sb.AppendLine($"Hint: {diag.Hint}");
        }

        // Suggestion
        if (!string.IsNullOrWhiteSpace(diag.Suggestion))
        {
            sb.AppendLine();
            sb.AppendLine($"Suggestion: {diag.Suggestion}");
        }

        // Docs URL
        if (!string.IsNullOrWhiteSpace(diag.DocsUrl))
        {
            sb.AppendLine();
            sb.AppendLine($"See: {diag.DocsUrl}");
        }

        return sb.ToString();
    }

    private static string FormatDiagnosticTitle(DiagnosticResult diag)
    {
        var severityLabel = diag.Severity.ToUpperInvariant();
        return $"[{diag.Code}] {severityLabel}";
    }

    public static string SymbolsToText(List<SymbolResult> results)
    {
        if (results.Count == 0)
            return "No symbols found.";

        var sb = new StringBuilder();
        foreach (var sym in results)
        {
            FormatSymbolText(sb, sym, indent: 0);
        }
        return sb.ToString();
    }

    private static void FormatSymbolText(StringBuilder sb, SymbolResult sym, int indent)
    {
        var prefix = new string(' ', indent * 2);
        var typeStr = sym.TypeName != null ? $": {sym.TypeName}" : "";
        var modStr = sym.Modifiers is { Length: > 0 } ? $"[{string.Join(", ", sym.Modifiers)}] " : "";
        sb.AppendLine($"{prefix}{modStr}{sym.Kind} {sym.Name}{typeStr}  ({sym.File}:{sym.Line})");

        if (sym.Parameters is { Length: > 0 })
        {
            var paramStr = string.Join(", ", sym.Parameters.Select(p =>
                p.HasDefault ? $"{p.Name}: {p.Type} = {p.DefaultValue}" : $"{p.Name}: {p.Type}"));
            sb.AppendLine($"{prefix}  ({paramStr})");
        }

        if (sym.Members is { Length: > 0 })
        {
            foreach (var member in sym.Members)
            {
                FormatSymbolText(sb, member, indent + 1);
            }
        }
    }

    public static string OutlineToText(OutlineResult result)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"File: {result.File}");

        if (result.Imports.Length > 0)
        {
            sb.AppendLine($"Imports: {string.Join(", ", result.Imports)}");
        }

        sb.AppendLine();

        foreach (var entry in result.Outline)
        {
            FormatOutlineEntryText(sb, entry, indent: 0);
        }

        return sb.ToString();
    }

    private static void FormatOutlineEntryText(StringBuilder sb, OutlineEntry entry, int indent)
    {
        var prefix = new string(' ', indent * 2);
        var typeStr = entry.ReturnType != null ? $" -> {entry.ReturnType}" : "";
        var rangeStr = entry.EndLine > entry.Line ? $" (lines {entry.Line}-{entry.EndLine})" : $" (line {entry.Line})";
        sb.AppendLine($"{prefix}{entry.Kind} {entry.Name}{typeStr}{rangeStr}");

        if (entry.Children is { Length: > 0 })
        {
            foreach (var child in entry.Children)
            {
                FormatOutlineEntryText(sb, child, indent + 1);
            }
        }
    }

    public static string TypeToText(TypeResult result, string file, int line, int col)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"At {file}:{line}:{col}:");
        sb.AppendLine($"  {result.Name}: {result.ResolvedType} ({result.Kind})");
        if (!string.IsNullOrWhiteSpace(result.Nullability))
            sb.AppendLine($"  Nullability: {result.Nullability}");
        if (result.Definition != null)
        {
            sb.AppendLine($"  Defined at: {result.Definition.File}:{result.Definition.Line}:{result.Definition.Column}");
        }
        return sb.ToString();
    }

    public static string DefinitionToText(DefinitionResult result)
    {
        return $"{result.Kind} {result.Name} at {result.File}:{result.Line}:{result.Column}";
    }

    public static string DefinitionSearchToText(string name, List<DefinitionResult> results)
    {
        if (results.Count == 0)
            return $"No definitions found for '{name}'.";

        var sb = new StringBuilder();
        sb.AppendLine($"Definitions of '{name}':");
        foreach (var r in results)
        {
            sb.AppendLine($"  {r.Kind} {r.Name} at {r.File}:{r.Line}:{r.Column}");
        }
        return sb.ToString();
    }

    public static string ReferencesToText(string symbolName, List<ReferenceResult> results)
    {
        if (results.Count == 0)
            return $"No references found for '{symbolName}'.";

        var sb = new StringBuilder();
        sb.AppendLine($"References to '{symbolName}' ({results.Count} found):");
        foreach (var r in results)
        {
            var defMarker = r.IsDefinition ? " [definition]" : "";
            var contextStr = r.Context != null ? $"  {r.Context.Trim()}" : "";
            sb.AppendLine($"  {r.File}:{r.Line}:{r.Column}{defMarker}{contextStr}");
        }
        return sb.ToString();
    }

    public static string DocToText(DocResult result)
    {
        var sb = new StringBuilder();

        // Header
        sb.AppendLine($"{result.Kind} {result.FullName}");
        if (result.Namespace != null)
            sb.AppendLine($"  Namespace: {result.Namespace}");

        // Summary
        if (!string.IsNullOrWhiteSpace(result.Summary))
        {
            sb.AppendLine();
            sb.AppendLine($"  {result.Summary}");
        }

        // Base types
        if (result.BaseTypes is { Length: > 0 })
        {
            sb.AppendLine();
            sb.AppendLine($"  Implements: {string.Join(", ", result.BaseTypes)}");
        }

        // Parameters (for methods)
        if (result.Parameters is { Length: > 0 })
        {
            sb.AppendLine();
            sb.AppendLine("  Parameters:");
            foreach (var p in result.Parameters)
            {
                var doc = p.Summary != null ? $" — {p.Summary}" : "";
                sb.AppendLine($"    {p.Name}: {p.Type}{doc}");
            }
        }

        // Return type
        if (result.ReturnType != null && result.ReturnType != "void")
        {
            sb.AppendLine();
            var doc = result.ReturnDoc != null ? $" — {result.ReturnDoc}" : "";
            sb.AppendLine($"  Returns: {result.ReturnType}{doc}");
        }

        // Members (for types, or overloads for methods)
        if (result.Members is { Length: > 0 })
        {
            sb.AppendLine();
            var memberLabel = result.Kind.Contains("overload") ? "Overloads:" : "Members:";
            sb.AppendLine($"  {memberLabel}");
            foreach (var m in result.Members.Take(30))
            {
                var typeStr = m.Type != null ? $": {m.Type}" : "";
                var docStr = m.Summary != null ? $" — {m.Summary}" : "";
                var paramStr = m.Parameters != null ? $" {m.Parameters}" : "";
                sb.AppendLine($"    {m.Kind} {m.Name}{paramStr}{typeStr}{docStr}");
            }
            if (result.Members.Length > 30)
            {
                sb.AppendLine($"    ... and {result.Members.Length - 30} more");
            }
        }

        return sb.ToString();
    }
}
