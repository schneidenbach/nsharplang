using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Performance;

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

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        MaxDepth = 256,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private static string? NormalizePath(string? path) => OutputFormatterNormalizationKernels.NormalizePath(path);

    private static SymbolResult Normalize(SymbolResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeSymbol(result);
        return result;
    }

    private static OutlineResult Normalize(OutlineResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeOutline(result);
        return result;
    }

    private static OutlineEntry Normalize(OutlineEntry entry)
    {
        OutputFormatterNormalizationKernels.NormalizeOutlineEntry(entry);
        return entry;
    }

    private static DiagnosticResult Normalize(DiagnosticResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeDiagnostic(result);
        return result;
    }

    private static TypeResult Normalize(TypeResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeType(result);
        return result;
    }

    private static DefinitionResult Normalize(DefinitionResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeDefinition(result);
        return result;
    }

    private static ReferenceResult Normalize(ReferenceResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeReference(result);
        return result;
    }

    private static LocationResult Normalize(LocationResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeLocation(result);
        return result;
    }

    private static InspectSymbolResult Normalize(InspectSymbolResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeInspectSymbol(result);
        return result;
    }

    private static InspectReferencesResult Normalize(InspectReferencesResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeInspectReferences(result);
        return result;
    }

    private static InspectResult Normalize(InspectResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeInspect(result);
        return result;
    }

    private static InspectReferenceSummaryResult Normalize(InspectReferenceSummaryResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeInspectReferenceSummary(result);
        return result;
    }

    private static InspectSummaryReferencesResult Normalize(InspectSummaryReferencesResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeInspectSummaryReferences(result);
        return result;
    }

    private static InspectSummaryResult Normalize(InspectSummaryResult result)
    {
        OutputFormatterNormalizationKernels.NormalizeInspectSummary(result);
        return result;
    }

    public static DiagnosticSummary SummarizeDiagnostics(IReadOnlyList<DiagnosticResult> results)
        => OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(results);

    public static List<DiagnosticResult> FilterDiagnosticsBySeverity(
        IReadOnlyList<DiagnosticResult> diagnostics,
        string severity)
    {
        return OutputFormatterDiagnosticKernels.FilterDiagnosticSeverityResults(
            diagnostics,
            severity);
    }

    public static List<DiagnosticResult> DeduplicateAndSortDiagnostics(IReadOnlyList<DiagnosticResult> diagnostics)
    {
        return CodeIntelligenceResultKernels.DeduplicateDiagnosticResults(diagnostics);
    }

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

    /// <summary>
    /// Serializes one or more parsed compilation-unit ASTs to the stable versioned JSON envelope.
    /// Each AST node is emitted as { "node": "&lt;ConcreteNodeType&gt;", &lt;camelCased properties&gt; }, recursing
    /// into child nodes and lists, so the concrete node kind (which a plain System.Text.Json polymorphic
    /// serialization of the Declaration/Statement/Expression bases would drop) is always present. This is
    /// the canonical AST representation for `nlc query ast` (LLM-first navigation) and for verifying a
    /// future N# parser against the C# parser. Property order is declaration order (stable per node type).
    /// </summary>
    public static string AstToJson(IReadOnlyList<(string File, CompilationUnit Unit)> units)
    {
        var files = new JsonArray();
        foreach (var (file, unit) in units)
        {
            files.Add(new JsonObject
            {
                ["file"] = NormalizePath(file),
                ["ast"] = AstValueToJson(unit)
            });
        }

        var envelope = new JsonObject
        {
            ["schemaVersion"] = SchemaVersion,
            ["command"] = "query.ast",
            ["ok"] = true,
            ["files"] = files
        };
        return envelope.ToJsonString(JsonOptions);
    }

    private static JsonNode? AstValueToJson(object? value)
    {
        switch (value)
        {
            case null:
                return null;
            case string s:
                return JsonValue.Create(s);
            case bool b:
                return JsonValue.Create(b);
            case char c:
                return JsonValue.Create(c.ToString());
            case Enum e:
                return JsonValue.Create(e.ToString());
            case int i:
                return JsonValue.Create(i);
            case long l:
                return JsonValue.Create(l);
            case double d:
                return JsonValue.Create(d);
        }

        var type = value.GetType();
        if (type.IsPrimitive)
        {
            return JsonValue.Create(Convert.ToString(value, CultureInfo.InvariantCulture));
        }

        if (value is System.Collections.IEnumerable sequence)
        {
            var array = new JsonArray();
            foreach (var item in sequence)
            {
                array.Add(AstValueToJson(item));
            }

            return array;
        }

        // An AST record / node object: emit the concrete node type then its declared properties.
        var obj = new JsonObject { ["node"] = type.Name };
        foreach (var property in type
            .GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(static p => p.GetIndexParameters().Length == 0 && p.Name != "EqualityContract")
            .OrderBy(static p => p.MetadataToken))
        {
            object? propertyValue;
            {
                propertyValue = property.GetValue(value);
            }

            obj[JsonNamingPolicy.CamelCase.ConvertName(property.Name)] = AstValueToJson(propertyValue);
        }

        return obj;
    }

    public static string DiagnosticsToJson(List<DiagnosticResult> results, string? projectRoot = null)
    {
        var summary = SummarizeDiagnostics(results);
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
        var summary = SummarizeDiagnostics(results);
        var clusters = OutputFormatterDiagnosticClusterBuilder.BuildDiagnosticClusters(results);
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
        var summary = SummarizeDiagnostics(results);

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
        var summary = SummarizeDiagnostics(results);

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
        return OutputFormatterJsonKernels.TypeToJson(result, file, line, col);
    }

    /// <summary>
    /// Emits the versioned performance report envelope for <c>nlc build --perf-report</c>.
    /// The report groups performance facts by category. Categories without a wired fact source
    /// are emitted as empty arrays so the envelope shape is stable for downstream consumers;
    /// </summary>
    public static string BuildPerfReportToJson(
        string? projectRoot,
        bool ok = true,
        IReadOnlyList<PerfReportSite>? allocationSites = null,
        IReadOnlyList<PerfReportSite>? delegateSites = null,
        IReadOnlyList<PerfReportSite>? boxingSites = null,
        IReadOnlyList<PerfReportSite>? dispatchSites = null,
        IReadOnlyList<PerfReportSite>? closureCaptures = null,
        IReadOnlyList<PerfReportSite>? poolSites = null,
        IReadOnlyList<PerfReportSite>? resourceSites = null,
        IReadOnlyList<PerfReportSite>? boundaryLeakSites = null,
        IReadOnlyList<PerfReportSite>? hotReadinessSites = null,
        IReadOnlyList<PerfReportSite>? implicitTrapSites = null,
        IReadOnlyList<PerfReportTrustedSite>? trustedSites = null)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "build",
            ok,
            projectRoot = NormalizePath(projectRoot),
            perfReport = new
            {
                allocationSites = OutputFormatterNormalizationKernels.NormalizePerfReportSites(allocationSites ?? Array.Empty<PerfReportSite>()),
                delegateSites = OutputFormatterNormalizationKernels.NormalizePerfReportSites(delegateSites ?? Array.Empty<PerfReportSite>()),
                boxingSites = OutputFormatterNormalizationKernels.NormalizePerfReportSites(boxingSites ?? Array.Empty<PerfReportSite>()),
                dispatchSites = OutputFormatterNormalizationKernels.NormalizePerfReportSites(dispatchSites ?? Array.Empty<PerfReportSite>()),
                closureCaptures = OutputFormatterNormalizationKernels.NormalizePerfReportSites(closureCaptures ?? Array.Empty<PerfReportSite>()),
                poolSites = OutputFormatterNormalizationKernels.NormalizePerfReportSites(poolSites ?? Array.Empty<PerfReportSite>()),
                resourceSites = OutputFormatterNormalizationKernels.NormalizePerfReportSites(resourceSites ?? Array.Empty<PerfReportSite>()),
                boundaryLeakSites = OutputFormatterNormalizationKernels.NormalizePerfReportSites(boundaryLeakSites ?? Array.Empty<PerfReportSite>()),
                hotReadinessSites = OutputFormatterNormalizationKernels.NormalizePerfReportSites(hotReadinessSites ?? Array.Empty<PerfReportSite>()),
                implicitTrapSites = OutputFormatterNormalizationKernels.NormalizePerfReportSites(implicitTrapSites ?? Array.Empty<PerfReportSite>()),
                trustedSites = OutputFormatterNormalizationKernels.NormalizePerfReportTrustedSites(trustedSites ?? Array.Empty<PerfReportTrustedSite>()),
            }
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string CheckSystemsReportToJson(
        List<DiagnosticResult> diagnostics,
        string? projectRoot,
        int checkedFiles,
        SystemsReport report)
    {
        var summary = SummarizeDiagnostics(diagnostics);

        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "check.systemsReport",
            projectRoot = NormalizePath(projectRoot),
            checkedFiles,
            ok = summary.Errors == 0,
            diagnostics = diagnostics.Select(Normalize).ToList(),
            summary,
            systemsReport = OutputFormatterNormalizationKernels.NormalizeSystemsReport(report)
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string TrustedToJson(SystemsReport report, string? projectRoot)
    {
        return OutputFormatterJsonKernels.TrustedToJson(report, projectRoot);
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
        return OutputFormatterJsonKernels.DefinitionToJson(result);
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
        var summary = Normalize(InspectSummaryBuilder.Build(result));
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
        return OutputFormatterTextBuilders.CompletionsToText(result, file, line, col);
    }

    public static string InspectToText(InspectResult result, string file, int line, int col)
    {
        return OutputFormatterTextBuilders.InspectToText(result, file, line, col);
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
        return OutputFormatterJsonKernels.HoverToJson(result, file, line, col);
    }

    public static string HoverToText(HoverResult result, string file, int line, int col)
    {
        return OutputFormatterTextBuilders.HoverToText(result, file, line, col);
    }

    // ── Call Graph ─────────────────────────────────────────────────────────

    public static string CallGraphToJson(CallGraphResult result)
    {
        return OutputFormatterJsonKernels.CallGraphToJson(result);
    }

    public static string CallGraphToText(CallGraphResult result)
    {
        return OutputFormatterTextBuilders.CallGraphToText(result);
    }

    // ── Implementors ───────────────────────────────────────────────────────

    public static string ImplementorsToJson(ImplementorsResult result)
    {
        return OutputFormatterJsonKernels.ImplementorsToJson(result);
    }

    public static string ImplementorsToText(ImplementorsResult result)
    {
        return OutputFormatterTextBuilders.ImplementorsToText(result);
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

    // ── Elm-Style Text Output ──────────────────────────────────────────

    public static string DiagnosticsToText(List<DiagnosticResult> results)
    {
        return OutputFormatterTextBuilders.DiagnosticsToText(results);
    }

    public static string SymbolsToText(List<SymbolResult> results)
    {
        return OutputFormatterTextBuilders.SymbolsToText(results);
    }

    public static string OutlineToText(OutlineResult result)
    {
        return OutputFormatterTextBuilders.OutlineToText(result);
    }

    public static string TypeToText(TypeResult result, string file, int line, int col)
    {
        return OutputFormatterTextBuilders.TypeToText(result, file, line, col);
    }

    public static string DefinitionToText(DefinitionResult result)
    {
        return OutputFormatterTextBuilders.DefinitionToText(result);
    }

    public static string ReferencesToText(string symbolName, List<ReferenceResult> results)
    {
        return OutputFormatterTextBuilders.ReferencesToText(symbolName, results);
    }

    public static string DocToText(DocResult result)
    {
        return OutputFormatterTextBuilders.DocToText(result);
    }
}
