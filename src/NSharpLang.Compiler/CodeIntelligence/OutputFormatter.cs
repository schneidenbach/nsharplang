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
        if (results.Count == 0)
            return "No diagnostics found.";

        var sb = new StringBuilder();
        var errors = results.Count(d => d.Severity == "error");
        var warnings = results.Count(d => d.Severity == "warning");
        var info = results.Count(d => d.Severity == "info");

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
