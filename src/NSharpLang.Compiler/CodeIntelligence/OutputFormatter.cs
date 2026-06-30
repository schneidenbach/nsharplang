using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
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
                allocationSites = NormalizePerfSites(allocationSites),
                delegateSites = NormalizePerfSites(delegateSites),
                boxingSites = NormalizePerfSites(boxingSites),
                dispatchSites = NormalizePerfSites(dispatchSites),
                closureCaptures = NormalizePerfSites(closureCaptures),
                poolSites = NormalizePerfSites(poolSites),
                resourceSites = NormalizePerfSites(resourceSites),
                boundaryLeakSites = NormalizePerfSites(boundaryLeakSites),
                hotReadinessSites = NormalizePerfSites(hotReadinessSites),
                implicitTrapSites = NormalizePerfSites(implicitTrapSites),
                trustedSites = NormalizeTrustedPerfSites(trustedSites),
            }
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    private static IReadOnlyList<PerfReportSite> NormalizePerfSites(IReadOnlyList<PerfReportSite>? sites)
        => (sites ?? Array.Empty<PerfReportSite>())
            .Select(OutputFormatterNormalizationKernels.NormalizePerfReportSite)
            .ToArray();

    private static IReadOnlyList<PerfReportTrustedSite> NormalizeTrustedPerfSites(IReadOnlyList<PerfReportTrustedSite>? sites)
        => (sites ?? Array.Empty<PerfReportTrustedSite>())
            .Select(OutputFormatterNormalizationKernels.NormalizePerfReportTrustedSite)
            .ToArray();

    public static string CheckSystemsReportToJson(
        List<DiagnosticResult> diagnostics,
        string? projectRoot,
        int checkedFiles,
        SystemsReport report)
    {
        var summary = new DiagnosticSummary(
            Errors: diagnostics.Count(d => d.Severity == "error"),
            Warnings: diagnostics.Count(d => d.Severity == "warning"),
            Info: diagnostics.Count(d => d.Severity == "info")
        );

        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "check.systemsReport",
            projectRoot = NormalizePath(projectRoot),
            checkedFiles,
            ok = summary.Errors == 0,
            diagnostics = diagnostics.Select(Normalize).ToList(),
            summary,
            systemsReport = NormalizeSystemsReport(report)
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string TrustedToJson(SystemsReport report, string? projectRoot)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "trusted",
            ok = true,
            projectRoot = NormalizePath(projectRoot),
            results = report.TrustedSites.Select(Normalize).ToArray(),
            summary = new { trustedSites = report.TrustedSites.Count }
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    private static object NormalizeSystemsReport(SystemsReport report)
    {
        return new
        {
            report.SchemaVersion,
            report.Profile,
            report.Mode,
            report.AotTarget,
            aot = report.Aot,
            warmup = report.Warmup,
            functions = report.Functions.Select(Normalize).ToArray(),
            findings = report.Findings.Select(Normalize).ToArray(),
            trustedSites = report.TrustedSites.Select(Normalize).ToArray(),
            report.Summary
        };
    }

    private static SystemsFunctionSummary Normalize(SystemsFunctionSummary function)
    {
        return new SystemsFunctionSummary(
            function.Name,
            NormalizePath(function.File) ?? function.File,
            function.Line,
            function.Column,
            function.IsHot,
            function.IsBoundary,
            function.AllocNone,
            function.SummarySource,
            function.Effects,
            function.Calls);
    }

    private static SystemsFinding Normalize(SystemsFinding finding)
    {
        return new SystemsFinding(
            finding.Code,
            finding.Severity,
            finding.Effect,
            finding.Message,
            NormalizePath(finding.File) ?? finding.File,
            finding.Line,
            finding.Column,
            finding.Length,
            finding.Function,
            finding.Policy,
            finding.SummarySource,
            finding.Suggestion,
            finding.CallPath);
    }

    private static SystemsTrustedSite Normalize(SystemsTrustedSite site)
    {
        return new SystemsTrustedSite(
            site.Function,
            NormalizePath(site.File) ?? site.File,
            site.Line,
            site.Column,
            site.Reason,
            site.Owner,
            site.Review,
            site.Expires,
            site.HasUnsafe,
            site.BodyStatementCount);
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
        return OutputFormatterTextBuilders.HoverToText(result, file, line, col);
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
        return OutputFormatterTextBuilders.CallGraphToText(result);
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

    // ── Diagnostic Clustering ───────────────────────────────────────────

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

    // ── Elm-Style Text Output ──────────────────────────────────────────

    public static string DiagnosticsToText(List<DiagnosticResult> results)
    {
        if (results.Count == 0)
            return OutputFormatterDiagnosticKernels.GetNoDiagnosticsText();

        var sb = new StringBuilder();
        var summary = SummarizeDiagnostics(results);

        AppendDiagnosticClusterSummary(sb, OutputFormatterDiagnosticClusterBuilder.BuildDiagnosticClusters(results));

        foreach (var diag in results)
        {
            sb.AppendLine(FormatSingleDiagnosticText(diag));
        }

        // Summary line
        sb.AppendLine();
        sb.AppendLine(OutputFormatterDiagnosticKernels.GetFoundSummaryText(summary));

        return sb.ToString();
    }

    private static string FormatSingleDiagnosticText(DiagnosticResult diag)
    {
        var sb = new StringBuilder();

        var title = FormatDiagnosticTitle(diag);

        sb.AppendLine(OutputFormatterDiagnosticKernels.GetHeaderLineText(
            title,
            diag.File,
            diag.Line,
            diag.Column));
        sb.AppendLine();

        // Source snippet with line number and caret
        if (!string.IsNullOrWhiteSpace(diag.SourceSnippet))
        {
            sb.AppendLine(OutputFormatterDiagnosticKernels.GetSourceLineText(diag.Line, diag.SourceSnippet.TrimEnd()));
            sb.AppendLine(OutputFormatterDiagnosticKernels.GetCaretLineText(diag.Line, diag.Column, diag.Length));
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
                sb.AppendLine(OutputFormatterDiagnosticKernels.GetExpectedTypeText(diag.ExpectedType));
            if (!string.IsNullOrWhiteSpace(diag.ActualType))
                sb.AppendLine(OutputFormatterDiagnosticKernels.GetActualTypeText(diag.ActualType));
        }

        // Hint
        if (!string.IsNullOrWhiteSpace(diag.Hint))
        {
            sb.AppendLine();
            sb.AppendLine(OutputFormatterDiagnosticKernels.GetHintText(diag.Hint));
        }

        // Suggestion
        if (!string.IsNullOrWhiteSpace(diag.Suggestion))
        {
            sb.AppendLine();
            sb.AppendLine(OutputFormatterDiagnosticKernels.GetSuggestionText(diag.Suggestion));
        }

        // Docs URL
        if (!string.IsNullOrWhiteSpace(diag.DocsUrl))
        {
            sb.AppendLine();
            sb.AppendLine(OutputFormatterDiagnosticKernels.GetDocsUrlText(diag.DocsUrl));
        }

        return sb.ToString();
    }

    private static string FormatDiagnosticTitle(DiagnosticResult diag)
        => OutputFormatterDiagnosticKernels.GetDiagnosticTitle(diag.Code, diag.Severity);

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
