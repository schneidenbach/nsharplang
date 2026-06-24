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
    private const int InspectSummaryReferenceSampleSize = 5;
    private const int InspectSummaryCompletionSampleSize = 8;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        MaxDepth = 256,
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

    public static DiagnosticSummary SummarizeDiagnostics(IReadOnlyList<DiagnosticResult> results)
        => OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(results);

    public static List<DiagnosticResult> FilterDiagnosticsBySeverity(
        IReadOnlyList<DiagnosticResult> diagnostics,
        string severity)
    {
        var (resultIndices, resultCount) = OutputFormatterDiagnosticKernels.FilterDiagnosticSeverities(
            diagnostics,
            severity);

        var results = new List<DiagnosticResult>(resultCount);
        for (var i = 0; i < resultCount; i++)
        {
            var diagnosticIndex = resultIndices[i];
            if (diagnosticIndex < 0 || diagnosticIndex >= diagnostics.Count)
                throw new InvalidOperationException("N# diagnostic severity filter kernel returned an invalid index.");

            results.Add(diagnostics[diagnosticIndex]);
        }

        return results;
    }

    public static List<DiagnosticResult> DeduplicateAndSortDiagnostics(IReadOnlyList<DiagnosticResult> diagnostics)
    {
        var (resultIndices, resultCount) = CodeIntelligenceResultKernels.DeduplicateDiagnostics(diagnostics);
        var results = new List<DiagnosticResult>(resultCount);
        for (var i = 0; i < resultCount; i++)
        {
            var diagnosticIndex = resultIndices[i];
            if (diagnosticIndex < 0 || diagnosticIndex >= diagnostics.Count)
                throw new InvalidOperationException("N# diagnostic deduplication kernel returned an invalid index.");

            results.Add(diagnostics[diagnosticIndex]);
        }

        return results;
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
            try
            {
                propertyValue = property.GetValue(value);
            }
            catch
            {
                continue;
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
    /// A single AOT blocker as rendered into the perf report's <c>aotBlockers</c> array.
    /// The schema is stable and versioned via the report envelope's <c>schemaVersion</c>.
    /// </summary>
    public sealed record PerfReportAotBlocker(
        string Code,
        string Kind,
        string File,
        int Line,
        int Column,
        string Construct,
        string EnclosingBoundary,
        string? EnclosingDeclaration,
        bool OnPublicSurface);

    public sealed record PerfReportSite(
        string Code,
        string Effect,
        string File,
        int Line,
        int Column,
        string Message,
        string? Function,
        string? Suggestion);

    public sealed record PerfReportTrustedSite(
        string Function,
        string File,
        int Line,
        int Column,
        string? Owner,
        string? Review,
        string? Expires,
        bool HasUnsafe,
        int BodyStatementCount);

    /// <summary>
    /// Emits the versioned performance report envelope for <c>nlc build --perf-report</c>.
    /// The report groups performance facts by category. Categories without a wired fact source
    /// are emitted as empty arrays so the envelope shape is stable for downstream consumers;
    /// <c>aotBlockers</c> is populated from the AOT-blocker analysis pass.
    /// </summary>
    public static string BuildPerfReportToJson(
        string? projectRoot,
        bool ok = true,
        IReadOnlyList<PerfReportAotBlocker>? aotBlockers = null,
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
                aotBlockers = (aotBlockers ?? Array.Empty<PerfReportAotBlocker>())
                    .Select(blocker => blocker with { File = NormalizePath(blocker.File) ?? blocker.File })
                    .ToArray()
            }
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    private static IReadOnlyList<PerfReportSite> NormalizePerfSites(IReadOnlyList<PerfReportSite>? sites)
        => (sites ?? Array.Empty<PerfReportSite>())
            .Select(site => site with { File = NormalizePath(site.File) ?? site.File })
            .ToArray();

    private static IReadOnlyList<PerfReportTrustedSite> NormalizeTrustedPerfSites(IReadOnlyList<PerfReportTrustedSite>? sites)
        => (sites ?? Array.Empty<PerfReportTrustedSite>())
            .Select(site => site with { File = NormalizePath(site.File) ?? site.File })
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
            results = report.TrustedSites.Select(site => site with
            {
                File = NormalizePath(site.File) ?? site.File
            }).ToArray(),
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
            functions = report.Functions.Select(function => function with
            {
                File = NormalizePath(function.File) ?? function.File
            }).ToArray(),
            findings = report.Findings.Select(finding => finding with
            {
                File = NormalizePath(finding.File) ?? finding.File
            }).ToArray(),
            trustedSites = report.TrustedSites.Select(site => site with
            {
                File = NormalizePath(site.File) ?? site.File
            }).ToArray(),
            report.Summary
        };
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
        sb.AppendLine(OutputFormatterTextKernels.GetCompletionsHeaderText(
            file,
            line,
            col,
            result.Context.ToString().ToLowerInvariant()));

        if (result.Receiver != null)
        {
            sb.AppendLine(OutputFormatterTextKernels.GetCompletionReceiverLineText(
                result.Receiver,
                result.ReceiverType));
        }

        sb.AppendLine();

        foreach (var (category, items) in result.Completions)
        {
            sb.AppendLine(OutputFormatterTextKernels.GetCompletionCategoryLineText(category, items.Count));
            foreach (var item in items.Take(50)) // Limit for text output
            {
                sb.AppendLine(OutputFormatterTextKernels.GetCompletionItemLineText(item));
            }
            if (items.Count > 50)
            {
                sb.AppendLine(OutputFormatterTextKernels.GetCompletionOverflowLineText(items.Count - 50));
            }
        }

        return sb.ToString();
    }

    public static string InspectToText(InspectResult result, string file, int line, int col)
    {
        var sb = new StringBuilder();
        sb.AppendLine(OutputFormatterTextKernels.GetInspectHeaderText(file, line, col));
        sb.AppendLine();

        if (result.Symbol != null)
        {
            sb.AppendLine(OutputFormatterTextKernels.GetInspectSymbolLineText(result.Symbol));
            if (result.Symbol.Definition != null)
            {
                sb.AppendLine(OutputFormatterTextKernels.GetTypeDefinedAtLineText(result.Symbol.Definition));
            }
        }
        else
        {
            sb.AppendLine(OutputFormatterTextKernels.GetInspectNoSymbolText());
        }

        sb.AppendLine();

        if (result.Type != null)
        {
            sb.AppendLine(OutputFormatterTextKernels.GetInspectTypeLineText(result.Type));
            if (!string.IsNullOrWhiteSpace(result.Type.Nullability))
                sb.AppendLine(OutputFormatterTextKernels.GetTypeNullabilityLineText(result.Type.Nullability));
        }
        else
        {
            sb.AppendLine(OutputFormatterTextKernels.GetInspectUnknownTypeText());
        }

        sb.AppendLine();

        if (result.Definition != null)
        {
            sb.AppendLine(OutputFormatterTextKernels.GetInspectDefinitionLineText(result.Definition));
        }
        else
        {
            sb.AppendLine(OutputFormatterTextKernels.GetInspectNoDefinitionText());
        }

        sb.AppendLine();
        sb.AppendLine(OutputFormatterTextKernels.GetInspectReferencesHeaderText(
            result.References.Count,
            result.References.DefinitionCount));
        foreach (var reference in result.References.Results.Take(10))
        {
            sb.AppendLine(OutputFormatterTextKernels.GetReferenceLineText(reference));
        }
        if (result.References.Count > 10)
        {
            sb.AppendLine(OutputFormatterTextKernels.GetInspectReferencesOverflowLineText(result.References.Count - 10));
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
        sb.AppendLine(OutputFormatterTextKernels.GetHoverHeaderText(file, line, col));
        sb.AppendLine();
        sb.AppendLine(OutputFormatterTextKernels.GetHoverSignatureLineText(result.Signature));
        sb.AppendLine(OutputFormatterTextKernels.GetHoverKindLineText(result.Kind));
        if (result.DefinedIn != null)
            sb.AppendLine(OutputFormatterTextKernels.GetHoverDefinedInLineText(result.DefinedIn));
        if (!string.IsNullOrWhiteSpace(result.Documentation))
        {
            sb.AppendLine();
            sb.AppendLine(OutputFormatterTextKernels.GetHoverDocumentationHeaderText());
            foreach (var docLine in result.Documentation.Split('\n'))
                sb.AppendLine(OutputFormatterTextKernels.GetHoverDocumentationLineText(docLine));
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
            sb.AppendLine(OutputFormatterTextKernels.GetCallGraphFunctionHeaderText(result.Function));
        else
            sb.AppendLine(OutputFormatterTextKernels.GetCallGraphFullHeaderText());
        sb.AppendLine();

        sb.AppendLine(OutputFormatterTextKernels.GetCallGraphSectionHeaderText("Callers", result.Callers.Count));
        foreach (var c in result.Callers)
            sb.AppendLine(OutputFormatterTextKernels.GetCallGraphEdgeLineText(c));

        sb.AppendLine();
        sb.AppendLine(OutputFormatterTextKernels.GetCallGraphSectionHeaderText("Callees", result.Callees.Count));
        foreach (var c in result.Callees)
            sb.AppendLine(OutputFormatterTextKernels.GetCallGraphEdgeLineText(c));

        if (result.Truncated)
            sb.AppendLine(OutputFormatterTextKernels.GetCallGraphTruncatedLineText());

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
        sb.AppendLine(OutputFormatterTextKernels.GetImplementorsHeaderText(
            result.Interface,
            result.Results.Count));
        sb.AppendLine();
        foreach (var r in result.Results)
            sb.AppendLine(OutputFormatterTextKernels.GetImplementorLineText(r));
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

        var referenceFiles = OutputFormatterReferenceFileKernels.BuildInspectSummaryReferenceFiles(result.References.Results);

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

    private sealed record ClassifiedDiagnostic(DiagnosticResult Diagnostic, DiagnosticClusterTraits Traits);

    private sealed record ClassifiedDiagnosticSet(
        List<ClassifiedDiagnostic> Items,
        DiagnosticResult[] Diagnostics,
        int[] CategoryIds,
        int[] SourceConstructIds,
        string[] MessagePatterns);

    private sealed record DiagnosticClusterTraits(
        string Category,
        string SourceConstruct,
        string Recipe,
        string Risk,
        string MessagePattern,
        string[] SuggestedNextActions);

    private static List<DiagnosticCluster> BuildDiagnosticClusters(List<DiagnosticResult> results)
    {
        var classified = BuildClassifiedDiagnostics(results);
        return BuildDiagnosticClustersFromDogfoodGroups(classified);
    }

    private static List<DiagnosticCluster> BuildDiagnosticClustersFromDogfoodGroups(ClassifiedDiagnosticSet classified)
    {
        var grouping = OutputFormatterDiagnosticClusterKernels.GroupDiagnosticClusters(
            classified.Diagnostics,
            classified.CategoryIds,
            classified.SourceConstructIds,
            classified.MessagePatterns);

        var clusters = new List<DiagnosticCluster>(grouping.GroupCount);
        var ordered = new List<DiagnosticResult>();
        for (var groupIndex = 0; groupIndex < grouping.GroupCount; groupIndex++)
        {
            var rootIndex = grouping.RootIndices[groupIndex];
            if (rootIndex < 0 || rootIndex >= classified.Items.Count)
                throw new InvalidOperationException("N# diagnostic cluster grouping kernel returned an invalid root index.");

            var memberStart = grouping.MemberStarts[groupIndex];
            var memberCount = grouping.Counts[groupIndex];
            if (memberStart < 0
                || memberCount < 0
                || memberStart > grouping.MemberIndices.Length - memberCount)
            {
                throw new InvalidOperationException("N# diagnostic cluster grouping kernel returned an invalid member range.");
            }

            ordered.Clear();
            for (var memberOffset = 0; memberOffset < memberCount; memberOffset++)
            {
                var diagnosticIndex = grouping.MemberIndices[memberStart + memberOffset];
                if (diagnosticIndex < 0 || diagnosticIndex >= classified.Items.Count)
                    throw new InvalidOperationException("N# diagnostic cluster grouping kernel returned an invalid diagnostic index.");

                ordered.Add(classified.Items[diagnosticIndex].Diagnostic);
            }

            if (ordered.Count != memberCount)
                throw new InvalidOperationException("N# diagnostic cluster grouping kernel returned incomplete members.");

            if (memberCount > 0 && grouping.MemberIndices[memberStart] != rootIndex)
                throw new InvalidOperationException("N# diagnostic cluster grouping kernel returned a non-root first member.");

            var traits = classified.Items[rootIndex].Traits;
            clusters.Add(CreateDiagnosticCluster(ordered, traits));
        }

        return clusters;
    }

    private static DiagnosticCluster CreateDiagnosticCluster(
        List<DiagnosticResult> ordered,
        DiagnosticClusterTraits traits)
    {
        var root = ordered[0];
        var files = OutputFormatterReferenceFileKernels.BuildDiagnosticClusterFiles(ordered);

        return new DiagnosticCluster(
            Id: CreateClusterId(root.Code, root.Severity, traits.Category, traits.SourceConstruct, traits.Recipe, traits.MessagePattern),
            Category: traits.Category,
            Recipe: traits.Recipe,
            Risk: traits.Risk,
            Count: ordered.Count,
            Severity: root.Severity,
            Files: files,
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
    }

    private static ClassifiedDiagnosticSet BuildClassifiedDiagnostics(List<DiagnosticResult> results)
    {
        var classified = new List<ClassifiedDiagnostic>(results.Count);
        var diagnostics = new DiagnosticResult[results.Count];
        var (categories, sourceConstructs) =
            OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticClusterTraits(results);

        var messagePatterns = new string[results.Count];
        for (var i = 0; i < results.Count; i++)
        {
            var diagnostic = results[i];
            var messagePattern = NormalizeMessagePattern(diagnostic.Message ?? string.Empty);
            var normalized = Normalize(diagnostic);
            messagePatterns[i] = messagePattern;
            diagnostics[i] = normalized;
            classified.Add(new ClassifiedDiagnostic(
                normalized,
                CreateDiagnosticClusterTraits(
                    categories[i],
                    sourceConstructs[i],
                    messagePattern)));
        }

        return new ClassifiedDiagnosticSet(classified, diagnostics, categories, sourceConstructs, messagePatterns);
    }

    private static DiagnosticClusterTraits CreateDiagnosticClusterTraits(
        int category,
        int sourceConstruct,
        string messagePattern)
    {
        var sourceConstructText = DiagnosticSourceConstructName(sourceConstruct);
        return category switch
        {
            0 => new DiagnosticClusterTraits(
                "syntax-missing-terminator",
                sourceConstructText,
                "syntax:statement-boundary",
                "high",
                messagePattern,
                new[]
                {
                    "Fix the earliest statement-boundary parse error first; later syntax diagnostics are often cascades.",
                    "Inspect the refactor or code-generation path that emitted this construct and add a delimiter/terminator regression test."
                }),
            1 => new DiagnosticClusterTraits(
                "syntax-missing-delimiter",
                sourceConstructText,
                "syntax:delimiter-balancing",
                "high",
                messagePattern,
                new[]
                {
                    "Fix the earliest statement-boundary parse error first; later syntax diagnostics are often cascades.",
                    "Inspect the refactor or code-generation path that emitted this construct and add a delimiter/terminator regression test."
                }),
            2 => new DiagnosticClusterTraits(
                "import-cycle",
                "import",
                "architecture:extract-shared-module-or-invert-dependency",
                "high",
                messagePattern,
                new[]
                {
                    "Break the cycle at the reported import path by moving shared declarations into a third file/package or inverting one dependency.",
                    "Rerun `nlc check` after removing the cycle; unused-import warnings in the same files may be cascades."
                }),
            3 => new DiagnosticClusterTraits(
                "identifier-resolution",
                sourceConstructText,
                "symbols:missing-import-or-qualification",
                "medium",
                messagePattern,
                new[]
                {
                    "Resolve the first missing identifier by adding the import/qualification or correcting the declaration name.",
                    "Rerun diagnostics after the root symbol is resolved; dependent member/type errors may disappear."
                }),
            4 => new DiagnosticClusterTraits(
                "type-resolution",
                sourceConstructText,
                "types:resolve-type-or-import",
                "medium",
                messagePattern,
                new[]
                {
                    "Resolve the type/import at the earliest root location before chasing downstream uses.",
                    "Check whether the source construct needs full qualification or a project reference."
                }),
            5 => new DiagnosticClusterTraits(
                "type-mismatch",
                sourceConstructText,
                "refactor:signature-or-expression-shape",
                "medium",
                messagePattern,
                new[]
                {
                    "Compare the expected and actual types at the root example and update the refactor recipe that changed the expression/signature shape.",
                    "Prefer fixing the producer expression over adding casts to each cascaded consumer."
                }),
            6 => new DiagnosticClusterTraits(
                "member-resolution",
                sourceConstructText,
                "members:api-rename-or-extension-import",
                "medium",
                messagePattern,
                new[]
                {
                    "Verify the API/member name for the root receiver before fixing repeated call sites.",
                    "Check whether an extension-method import or receiver type conversion was dropped."
                }),
            _ => new DiagnosticClusterTraits(
                "diagnostic-message-shape",
                sourceConstructText,
                "manual-triage:inspect-root-diagnostic",
                "low",
                messagePattern,
                new[]
                {
                    "Start at the root example and decide whether this is a source, refactor, or compiler diagnostic issue.",
                    "After fixing the root cause, rerun diagnostics and compare the remaining cluster counts."
                })
        };
    }

    private static string DiagnosticSourceConstructName(int sourceConstruct) => sourceConstruct switch
    {
        0 => "variable-declaration",
        1 => "function-declaration",
        2 => "class-declaration",
        3 => "interface-declaration",
        4 => "import",
        5 => "return-statement",
        6 => "control-flow",
        7 => "call-or-construction",
        _ => "unknown-construct"
    };

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
            return OutputFormatterDiagnosticKernels.GetNoDiagnosticsText();

        var sb = new StringBuilder();
        var summary = SummarizeDiagnostics(results);

        AppendDiagnosticClusterSummary(sb, BuildDiagnosticClusters(results));

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
        if (results.Count == 0)
            return OutputFormatterTextKernels.GetNoSymbolsText();

        var sb = new StringBuilder();
        foreach (var sym in results)
        {
            FormatSymbolText(sb, sym, indent: 0);
        }
        return sb.ToString();
    }

    private static void FormatSymbolText(StringBuilder sb, SymbolResult sym, int indent)
    {
        sb.AppendLine(OutputFormatterTextKernels.GetSymbolLineText(sym, indent));

        if (sym.Parameters is { Length: > 0 })
        {
            sb.AppendLine(OutputFormatterTextKernels.GetSymbolParametersLineText(sym.Parameters, indent));
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
        sb.AppendLine(OutputFormatterTextKernels.GetOutlineFileLineText(result.File));

        if (result.Imports.Length > 0)
        {
            sb.AppendLine(OutputFormatterTextKernels.GetOutlineImportsLineText(result.Imports));
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
        sb.AppendLine(OutputFormatterTextKernels.GetOutlineEntryLineText(entry, indent));

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
        sb.AppendLine(OutputFormatterTextKernels.GetTypeLocationHeaderText(file, line, col));
        sb.AppendLine(OutputFormatterTextKernels.GetTypeResultLineText(result));
        if (!string.IsNullOrWhiteSpace(result.Nullability))
            sb.AppendLine(OutputFormatterTextKernels.GetTypeNullabilityLineText(result.Nullability));
        if (result.Definition != null)
        {
            sb.AppendLine(OutputFormatterTextKernels.GetTypeDefinedAtLineText(result.Definition));
        }
        return sb.ToString();
    }

    public static string DefinitionToText(DefinitionResult result)
    {
        return OutputFormatterTextKernels.GetDefinitionLineText(result);
    }

    public static string ReferencesToText(string symbolName, List<ReferenceResult> results)
    {
        if (results.Count == 0)
            return OutputFormatterTextKernels.GetNoReferencesText(symbolName);

        var sb = new StringBuilder();
        sb.AppendLine(OutputFormatterTextKernels.GetReferencesHeaderText(symbolName, results.Count));
        foreach (var r in results)
        {
            sb.AppendLine(OutputFormatterTextKernels.GetReferenceLineText(r));
        }
        return sb.ToString();
    }

    public static string DocToText(DocResult result)
    {
        var sb = new StringBuilder();

        // Header
        sb.AppendLine(OutputFormatterTextKernels.GetDocHeaderText(result));
        if (result.Namespace != null)
            sb.AppendLine(OutputFormatterTextKernels.GetDocNamespaceLineText(result.Namespace));

        // Summary
        if (!string.IsNullOrWhiteSpace(result.Summary))
        {
            sb.AppendLine();
            sb.AppendLine(OutputFormatterTextKernels.GetDocSummaryLineText(result.Summary));
        }

        // Base types
        if (result.BaseTypes is { Length: > 0 })
        {
            sb.AppendLine();
            sb.AppendLine(OutputFormatterTextKernels.GetDocImplementsLineText(result.BaseTypes));
        }

        // Parameters (for methods)
        if (result.Parameters is { Length: > 0 })
        {
            sb.AppendLine();
            sb.AppendLine(OutputFormatterTextKernels.GetDocParametersHeaderText());
            foreach (var p in result.Parameters)
            {
                sb.AppendLine(OutputFormatterTextKernels.GetDocParameterLineText(p));
            }
        }

        // Return type
        if (result.ReturnType != null && result.ReturnType != "void")
        {
            sb.AppendLine();
            sb.AppendLine(OutputFormatterTextKernels.GetDocReturnsLineText(result.ReturnType, result.ReturnDoc));
        }

        // Members (for types, or overloads for methods)
        if (result.Members is { Length: > 0 })
        {
            sb.AppendLine();
            sb.AppendLine(OutputFormatterTextKernels.GetDocMembersHeaderText(result.Kind));
            foreach (var m in result.Members.Take(30))
            {
                sb.AppendLine(OutputFormatterTextKernels.GetDocMemberLineText(m));
            }
            if (result.Members.Length > 30)
            {
                sb.AppendLine(OutputFormatterTextKernels.GetDocOverflowLineText(result.Members.Length - 30));
            }
        }

        return sb.ToString();
    }
}
