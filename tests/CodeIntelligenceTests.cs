using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Tests for the CodeIntelligence OutputFormatter and model types.
/// Service-level integration tests (LoadProject, GetSymbols, etc.) are excluded
/// because MultiFileCompiler.LoadSystemAssemblies() causes xUnit deadlocks (task 034).
/// Those features are validated via manual CLI testing against example projects.
/// </summary>
public class CodeIntelligenceOutputTests
{
    // ── OutputFormatter JSON Tests ──────────────────────────────────────

    [Fact]
    public void SymbolsToJson_HasVersionedEnvelope()
    {
        var symbols = new List<SymbolResult>
        {
            new("Main", SymbolKind.Function, "Program.nl", 1, 0, "void", null, null, null)
        };

        var json = OutputFormatter.SymbolsToJson(symbols, "/project");
        Assert.Contains("\"schemaVersion\": 1", json);
        Assert.Contains("\"command\": \"symbols\"", json);
        Assert.Contains("\"projectRoot\": \"/project\"", json);
        Assert.Contains("\"Main\"", json);
    }

    [Fact]
    public void DiagnosticsToJson_HasSummary()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            new("NL202", "error", "Type mismatch", "Program.nl", 5, 4, 3,
                null, null, null, null, "int", "string", null),
            new("NL901", "warning", "Unused variable", "Program.nl", 10, 4, 1,
                null, null, null, null, null, null, null)
        };

        var json = OutputFormatter.DiagnosticsToJson(diagnostics, "/project");
        Assert.Contains("\"errors\": 1", json);
        Assert.Contains("\"warnings\": 1", json);
        Assert.Contains("\"info\": 0", json);
    }

    [Fact]
    public void OutlineToJson_IncludesImportsAndStructure()
    {
        var outline = new OutlineResult("Program.nl",
            new[] { "System", "System.Linq" },
            new[]
            {
                new OutlineEntry("Main", SymbolKind.Function, 3, 10, "void", null, null),
                new OutlineEntry("Person", SymbolKind.Class, 12, 20, null, null,
                    new[]
                    {
                        new OutlineEntry("Name", SymbolKind.Property, 13, 13, null, "string", null)
                    })
            });

        var json = OutputFormatter.OutlineToJson(outline);
        Assert.Contains("\"schemaVersion\": 1", json);
        Assert.Contains("\"System\"", json);
        Assert.Contains("\"System.Linq\"", json);
        Assert.Contains("\"Main\"", json);
        Assert.Contains("\"Person\"", json);
        Assert.Contains("\"Name\"", json);
    }

    [Fact]
    public void TypeToJson_IncludesPositionAndDefinition()
    {
        var result = new TypeResult("p", "Person", "class",
            new LocationResult("Models.nl", 5, 0));

        var json = OutputFormatter.TypeToJson(result, "Program.nl", 8, 4);
        Assert.Contains("\"schemaVersion\": 1", json);
        Assert.Contains("\"command\": \"type\"", json);
        Assert.Contains("\"file\": \"Program.nl\"", json);
        Assert.Contains("\"line\": 8", json);
        Assert.Contains("\"resolvedType\": \"Person\"", json);
    }

    [Fact]
    public void DefinitionToJson_IncludesResult()
    {
        var result = new DefinitionResult("Person", "class", "Models.nl", 5, 0, 6);
        var json = OutputFormatter.DefinitionToJson(result);
        Assert.Contains("\"name\": \"Person\"", json);
        Assert.Contains("\"kind\": \"class\"", json);
        Assert.Contains("\"file\": \"Models.nl\"", json);
    }

    [Fact]
    public void DefinitionSearchToJson_IncludesNoteForMultipleResults()
    {
        var results = new List<DefinitionResult>
        {
            new("Point", "record", "Models.nl", 5, 0, 5),
            new("Point", "struct", "Other.nl", 10, 0, 5)
        };

        var json = OutputFormatter.DefinitionSearchToJson("Point", results);
        Assert.Contains("Multiple matches", json);
        Assert.Contains("\"query\":", json);
        Assert.Contains("\"name\": \"Point\"", json);
    }

    [Fact]
    public void DefinitionSearchToJson_NoNoteForSingleResult()
    {
        var results = new List<DefinitionResult>
        {
            new("Person", "class", "Models.nl", 5, 0, 6)
        };

        var json = OutputFormatter.DefinitionSearchToJson("Person", results);
        Assert.DoesNotContain("Multiple matches", json);
    }

    [Fact]
    public void ReferencesToJson_IncludesSymbolAndCount()
    {
        var results = new List<ReferenceResult>
        {
            new("Models.nl", 5, 0, 6, "class Person {", true),
            new("Program.nl", 3, 8, 6, "p := Person{}", false)
        };

        var json = OutputFormatter.ReferencesToJson("Person", "class",
            new LocationResult("Models.nl", 5, 0), results);
        Assert.Contains("\"count\": 2", json);
        Assert.Contains("\"isDefinition\": true", json);
        Assert.Contains("\"definedAt\":", json);
        Assert.Contains("\"name\": \"Person\"", json);
    }

    [Fact]
    public void ErrorToJson_FormatsCorrectly()
    {
        var json = OutputFormatter.ErrorToJson("type", "No type information found at file:5:4");
        Assert.Contains("\"error\":", json);
        Assert.Contains("No type information found", json);
        Assert.Contains("\"command\": \"type\"", json);
        Assert.Contains("\"schemaVersion\": 1", json);
    }

    // ── OutputFormatter Text Tests ──────────────────────────────────────

    [Fact]
    public void DiagnosticsToText_ElmStyleFormatting()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            new("NL202", "error", "Type mismatch: expected 'int' but got 'string'",
                "Program.nl", 5, 4, 3,
                "    x := \"hi\"",
                "Expected int but got string",
                "Use int.Parse",
                "Check your types",
                "int", "string", "https://docs.nsharp.dev/errors/NL202")
        };

        var text = OutputFormatter.DiagnosticsToText(diagnostics);

        // Header
        Assert.Contains("NL202", text);
        Assert.Contains("ERROR", text);
        Assert.Contains("Program.nl:5:4", text);

        // Source snippet with caret
        Assert.Contains("x := \"hi\"", text);
        Assert.Contains("^^^", text);

        // Message
        Assert.Contains("Type mismatch", text);

        // Explanation
        Assert.Contains("Expected int but got string", text);

        // Type info
        Assert.Contains("Expected: `int`", text);
        Assert.Contains("Actual: `string`", text);

        // Hint
        Assert.Contains("Hint: Check your types", text);

        // Suggestion
        Assert.Contains("Suggestion: Use int.Parse", text);

        // Docs URL
        Assert.Contains("See: https://docs.nsharp.dev/errors/NL202", text);

        // Summary
        Assert.Contains("1 error", text);
    }

    [Fact]
    public void DiagnosticsToText_MultipleErrorsSummary()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            new("NL301", "error", "Undefined variable 'x'", "A.nl", 1, 0, 1, null, null, null, null, null, null, null),
            new("NL301", "error", "Undefined variable 'y'", "B.nl", 2, 0, 1, null, null, null, null, null, null, null),
            new("NL901", "warning", "Unused variable", "A.nl", 5, 0, 1, null, null, null, null, null, null, null)
        };

        var text = OutputFormatter.DiagnosticsToText(diagnostics);
        Assert.Contains("2 errors", text);
        Assert.Contains("1 warning", text);
    }

    [Fact]
    public void DiagnosticsToText_EmptyReturnsNoDiagnostics()
    {
        var text = OutputFormatter.DiagnosticsToText(new List<DiagnosticResult>());
        Assert.Contains("No diagnostics found", text);
    }

    [Fact]
    public void SymbolsToText_FormatsReadably()
    {
        var symbols = new List<SymbolResult>
        {
            new("Main", SymbolKind.Function, "Program.nl", 1, 0, "void",
                new[] { "pub" }, null,
                new[] { new ParameterResult("name", "string", false, null) }),
            new("Person", SymbolKind.Class, "Models.nl", 5, 0, null,
                new[] { "pub" },
                new SymbolResult[]
                {
                    new("Name", SymbolKind.Property, "Models.nl", 6, 0, "string", null, null, null)
                },
                null)
        };

        var text = OutputFormatter.SymbolsToText(symbols);
        Assert.Contains("Function Main", text);
        Assert.Contains("Class Person", text);
        Assert.Contains("Property Name", text);
        Assert.Contains("name: string", text);
    }

    [Fact]
    public void SymbolsToText_EmptyReturnsNoSymbols()
    {
        var text = OutputFormatter.SymbolsToText(new List<SymbolResult>());
        Assert.Contains("No symbols found", text);
    }

    [Fact]
    public void OutlineToText_FormatsWithIndentation()
    {
        var outline = new OutlineResult("Program.nl", new[] { "System" },
            new[]
            {
                new OutlineEntry("Person", SymbolKind.Class, 5, 15, null, null,
                    new[]
                    {
                        new OutlineEntry("Name", SymbolKind.Property, 6, 6, null, "string", null),
                        new OutlineEntry("Greet", SymbolKind.Function, 8, 12, "string", null, null)
                    })
            });

        var text = OutputFormatter.OutlineToText(outline);
        Assert.Contains("File: Program.nl", text);
        Assert.Contains("Imports: System", text);
        Assert.Contains("Class Person", text);
        Assert.Contains("Property Name", text);
        Assert.Contains("Function Greet", text);
    }

    [Fact]
    public void ReferencesToText_FormatsWithCounts()
    {
        var results = new List<ReferenceResult>
        {
            new("Models.nl", 5, 0, 6, "class Person {", true),
            new("Program.nl", 3, 8, 6, "p := Person{}", false)
        };

        var text = OutputFormatter.ReferencesToText("Person", results);
        Assert.Contains("2 found", text);
        Assert.Contains("[definition]", text);
        Assert.Contains("Models.nl:5:0", text);
    }

    [Fact]
    public void ReferencesToText_EmptyReturnsNoReferences()
    {
        var text = OutputFormatter.ReferencesToText("Foo", new List<ReferenceResult>());
        Assert.Contains("No references found", text);
    }

    [Fact]
    public void DefinitionSearchToText_FormatsResults()
    {
        var results = new List<DefinitionResult>
        {
            new("Point", "record", "Models.nl", 5, 0, 5),
            new("Point", "struct", "Other.nl", 10, 0, 5)
        };

        var text = OutputFormatter.DefinitionSearchToText("Point", results);
        Assert.Contains("Definitions of 'Point'", text);
        Assert.Contains("record Point", text);
        Assert.Contains("struct Point", text);
    }

    // ── Model Record Tests ──────────────────────────────────────────────

    [Fact]
    public void SymbolKind_SerializesAsString()
    {
        var symbol = new SymbolResult("test", SymbolKind.Function, "file.nl", 1, 0, null, null, null, null);
        var json = OutputFormatter.SymbolsToJson(new List<SymbolResult> { symbol });
        Assert.Contains("\"function\"", json);
    }

    [Fact]
    public void DiagnosticSummary_CalculatesCorrectly()
    {
        var summary = new DiagnosticSummary(Errors: 3, Warnings: 2, Info: 1);
        Assert.Equal(3, summary.Errors);
        Assert.Equal(2, summary.Warnings);
        Assert.Equal(1, summary.Info);
    }
}
