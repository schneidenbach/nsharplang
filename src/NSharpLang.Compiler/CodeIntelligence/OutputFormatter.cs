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

    // ── JSON Output ────────────────────────────────────────────────────

    public static string SymbolsToJson(List<SymbolResult> results, string? projectRoot = null)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "symbols",
            projectRoot,
            results
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string OutlineToJson(OutlineResult result)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "outline",
            file = result.File,
            imports = result.Imports,
            outline = result.Outline
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
            projectRoot,
            results,
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
            file,
            position = new { line, column = col },
            result
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string DefinitionToJson(DefinitionResult result)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "definition",
            result
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string DefinitionSearchToJson(string name, List<DefinitionResult> results)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command = "definition",
            query = new { name },
            results,
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
            symbol = new { name = symbolName, kind = symbolKind, definedAt },
            count = results.Count,
            results
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public static string ErrorToJson(string command, string error)
    {
        var envelope = new
        {
            schemaVersion = SchemaVersion,
            command,
            error
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
}
