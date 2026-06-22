using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Performance;
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
    public void GetDiagnostics_KeepsNonShadowingLintsWhenCompilerErrorExists()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-codeintel-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var filePath = Path.Combine(tempDir, "Program.nl");
            var source = """
                func Main(unused: int) {
                    Console.WriteLine(undefined)
                }
                """;

            var snapshot = CreateDiagnosticSnapshot(
                tempDir,
                filePath,
                source,
                CompilerError.Create(
                    ErrorCode.UndefinedVariable,
                    "Undefined variable 'undefined'",
                    2,
                    23) with
                {
                    FileName = filePath,
                    SourceSnippet = "    Console.WriteLine(undefined)",
                    Length = "undefined".Length
                });

            var diagnostics = new CodeIntelligenceService().GetDiagnostics(snapshot);

            Assert.Contains(diagnostics, diagnostic => diagnostic.Code == "NL301");
            Assert.Contains(diagnostics, diagnostic => diagnostic.Code == "NL012");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void GetDiagnostics_SuppressesOnlyLinterShadowingWhenCompilerShadowingExists()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-codeintel-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var filePath = Path.Combine(tempDir, "Program.nl");
            var source = """
                func Main(value: int) {
                    if true {
                        value := 1
                    }
                }
                """;

            var snapshot = CreateDiagnosticSnapshot(
                tempDir,
                filePath,
                source,
                CompilerError.Create(
                    ErrorCode.ShadowedDeclaration,
                    "Local variable 'value' shadows an existing declaration",
                    3,
                    9) with
                {
                    FileName = filePath,
                    SourceSnippet = "        value := 1",
                    Length = "value".Length
                });

            var diagnostics = new CodeIntelligenceService().GetDiagnostics(snapshot);

            Assert.Contains(diagnostics, diagnostic => diagnostic.Code == "NL316");
            Assert.DoesNotContain(diagnostics, diagnostic => diagnostic.Code == "NL020");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

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
        var doc = JsonDocument.Parse(json);
        Assert.Equal("diagnostics", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal(1, doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32());
        Assert.Equal(1, doc.RootElement.GetProperty("summary").GetProperty("warnings").GetInt32());
        Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("info").GetInt32());
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
        var doc = JsonDocument.Parse(json);
        Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("type", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("Program.nl", doc.RootElement.GetProperty("file").GetString());
        Assert.Equal(8, doc.RootElement.GetProperty("position").GetProperty("line").GetInt32());
        Assert.Equal("Person", doc.RootElement.GetProperty("result").GetProperty("resolvedType").GetString());
    }

    [Fact]
    public void DefinitionToJson_IncludesResult()
    {
        var result = new DefinitionResult("Person", "class", "Models.nl", 5, 0, 6);
        var json = OutputFormatter.DefinitionToJson(result);
        var doc = JsonDocument.Parse(json);
        var value = doc.RootElement.GetProperty("result");
        Assert.Equal("definition", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("Person", value.GetProperty("name").GetString());
        Assert.Equal("class", value.GetProperty("kind").GetString());
        Assert.Equal("Models.nl", value.GetProperty("file").GetString());
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
        var doc = JsonDocument.Parse(json);
        Assert.Equal("references", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal(2, doc.RootElement.GetProperty("count").GetInt32());
        Assert.Equal("Person", doc.RootElement.GetProperty("symbol").GetProperty("name").GetString());
        Assert.True(doc.RootElement.GetProperty("results")[0].GetProperty("isDefinition").GetBoolean());
    }

    [Fact]
    public void ErrorToJson_FormatsCorrectly()
    {
        var json = OutputFormatter.ErrorToJson(
            "type",
            "No symbol found at Program.nl:83:1",
            "/project",
            "noSymbol",
            new
            {
                file = "Program.nl",
                position = new { line = 83, column = 1 }
            });

        using var doc = JsonDocument.Parse(json);
        Assert.Equal("type", doc.RootElement.GetProperty("command").GetString());
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("/project", doc.RootElement.GetProperty("projectRoot").GetString());
        Assert.Equal("noSymbol", doc.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.Equal("Program.nl", doc.RootElement.GetProperty("error").GetProperty("details").GetProperty("file").GetString());
    }

    [Fact]
    public void InspectToJson_IncludesBundledNavigationData()
    {
        var inspect = new InspectResult(
            new InspectSymbolResult("GetStats", "function", new LocationResult("Services/TaskService.nl", 93, 5)),
            new TypeResult("GetStats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1)),
            new DefinitionResult("GetStats", "function", "Services/TaskService.nl", 93, 5, 8),
            new InspectReferencesResult(5, 1, new[]
            {
                new ReferenceResult("Services/TaskService.nl", 93, 5, 8, "func GetStats(): TaskStats {", true),
                new ReferenceResult("Program.nl", 85, 22, 8, "stats := service.GetStats()", false),
                new ReferenceResult(@"Services\TaskService.nl", 94, 9, 8, "normalized duplicate", false),
                new ReferenceResult("Generated/Stats.nl", 12, 4, 8, "generated reference", false),
                new ReferenceResult("Program.nl", 86, 11, 8, "duplicate program reference", false)
            }),
            new CompletionResult(
                CompletionContext.MemberAccess,
                "service",
                "TaskService",
                new Dictionary<string, List<CompletionItem>>
                {
                    ["functions"] = new()
                    {
                        new CompletionItem("GetStats", "function", "TaskStats", "()", null, false)
                    }
                }));

        var json = OutputFormatter.InspectToJson(inspect, "Program.nl", 85, 22);
        var doc = JsonDocument.Parse(json);
        var result = doc.RootElement.GetProperty("result");
        Assert.Equal("inspect", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("GetStats", result.GetProperty("symbol").GetProperty("name").GetString());
        Assert.Equal(1, result.GetProperty("references").GetProperty("definitionCount").GetInt32());
        Assert.Equal("service", result.GetProperty("completions").GetProperty("receiver").GetString());
    }

    [Fact]
    public void InspectSummaryToJson_ProducesCompactSummaryPayload()
    {
        var inspect = new InspectResult(
            new InspectSymbolResult("GetStats", "function", new LocationResult("Services/TaskService.nl", 93, 5)),
            new TypeResult("GetStats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1)),
            new DefinitionResult("GetStats", "function", "Services/TaskService.nl", 93, 5, 8),
            new InspectReferencesResult(5, 1, new[]
            {
                new ReferenceResult("Services/TaskService.nl", 93, 5, 8, "func GetStats(): TaskStats {", true),
                new ReferenceResult("Program.nl", 85, 22, 8, "stats := service.GetStats()", false),
                new ReferenceResult("Program.nl", 87, 14, 8, "Log(service.GetStats())", false),
                new ReferenceResult("Generated\\Stats.nl", 12, 9, 8, "value = service.GetStats()", false),
                new ReferenceResult("Services/TaskService.nl", 101, 13, 8, "return GetStats()", false)
            }),
            new CompletionResult(
                CompletionContext.MemberAccess,
                "service",
                "TaskService",
                new Dictionary<string, List<CompletionItem>>
                {
                    ["functions"] = new()
                    {
                        new CompletionItem("GetStats", "function", "TaskStats", "()", null, false),
                        new CompletionItem("CreateTask", "function", "TaskResult", "(string title)", null, false)
                    },
                    ["properties"] = new()
                    {
                        new CompletionItem("Total", "property", "int", null, null, false)
                    }
                }));

        var json = OutputFormatter.InspectSummaryToJson(inspect, "Program.nl", 85, 22);
        using var doc = JsonDocument.Parse(json);

        Assert.Equal("inspect", doc.RootElement.GetProperty("command").GetString());
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.True(doc.RootElement.TryGetProperty("summary", out var summary));
        Assert.False(doc.RootElement.TryGetProperty("result", out _));
        var references = summary.GetProperty("references");
        Assert.Equal(5, references.GetProperty("count").GetInt32());
        Assert.Equal(
            new[] { "Generated/Stats.nl", "Program.nl", "Services/TaskService.nl" },
            references.GetProperty("files").EnumerateArray().Select(file => file.GetString()).ToArray());
        Assert.Equal(3, summary.GetProperty("completions").GetProperty("totalCount").GetInt32());
        Assert.Equal(2, summary.GetProperty("completions").GetProperty("groupCounts").GetProperty("functions").GetInt32());
        Assert.Equal("GetStats", summary.GetProperty("completions").GetProperty("groups").GetProperty("functions")[0].GetString());
    }

    [Fact]
    public void DiagnosticClustersToJson_OrdersClusterFilesCaseInsensitively()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            new("NL301", "error", "Undefined variable 'customer'", "src/B.nl", 1, 5, 8,
                null, null, null, null, null, null, null),
            new("NL301", "error", "Undefined variable 'customer'", "src/a.nl", 2, 5, 8,
                null, null, null, null, null, null, null),
            new("NL301", "error", "Undefined variable 'customer'", "SRC/A.NL", 3, 5, 8,
                null, null, null, null, null, null, null),
            new("NL301", "error", "Undefined variable 'customer'", "src/C.nl", 4, 5, 8,
                null, null, null, null, null, null, null)
        };

        var json = OutputFormatter.DiagnosticClustersToJson(diagnostics, "/project");
        using var doc = JsonDocument.Parse(json);

        var cluster = Assert.Single(doc.RootElement.GetProperty("clusters").EnumerateArray());
        Assert.Equal(
            new[] { "src/a.nl", "src/B.nl", "src/C.nl" },
            cluster.GetProperty("files").EnumerateArray().Select(file => file.GetString()).ToArray());
    }

    [Fact]
    public void CheckToJson_HasStableEnvelope()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            new("NL202", "error", "Type mismatch", "Program.nl", 5, 4, 3,
                null, null, null, null, "int", "string", null)
        };

        var json = OutputFormatter.CheckToJson(diagnostics, "/project", 3);
        var doc = JsonDocument.Parse(json);

        Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("/project", doc.RootElement.GetProperty("projectRoot").GetString());
        Assert.Equal(3, doc.RootElement.GetProperty("checkedFiles").GetInt32());
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal(1, doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32());
    }

    [Fact]
    public void SummarizeDiagnostics_CountsStableSeveritiesAndIgnoresUnknown()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            new("NL101", "error", "Syntax error", "Program.nl", 1, 1, 1,
                null, null, null, null, null, null, null),
            new("NL201", "warning", "Warning", "Program.nl", 2, 1, 1,
                null, null, null, null, null, null, null),
            new("NL301", "info", "Info", "Program.nl", 3, 1, 1,
                null, null, null, null, null, null, null),
            new("NL999", "hint", "Hint", "Program.nl", 4, 1, 1,
                null, null, null, null, null, null, null)
        };

        var summary = OutputFormatter.SummarizeDiagnostics(diagnostics);

        Assert.Equal(1, summary.Errors);
        Assert.Equal(1, summary.Warnings);
        Assert.Equal(1, summary.Info);
    }

    [Fact]
    public void JsonContracts_MatchGoldenRootKeys()
    {
        var expected = LoadJsonContractRootKeys();

        AssertJsonContract("symbols",
            OutputFormatter.SymbolsToJson(
                new List<SymbolResult>
                {
                    new(
                        "Main",
                        SymbolKind.Function,
                        "Program.nl",
                        1,
                        0,
                        "void",
                        new[] { "pub" },
                        new[]
                        {
                            new SymbolResult("Run", SymbolKind.Function, "Program.nl", 2, 4, "void", null, null, null)
                        },
                        new[]
                        {
                            new ParameterResult("args", "string[]", false, null)
                        })
                },
                "/project"),
            expected);

        AssertJsonContract("outline",
            OutputFormatter.OutlineToJson(new OutlineResult(
                "Program.nl",
                new[] { "System", "System.Linq" },
                new[]
                {
                    new OutlineEntry("Main", SymbolKind.Function, 3, 10, "void", null, null),
                    new OutlineEntry("Person", SymbolKind.Class, 12, 20, null, null,
                        new[]
                        {
                            new OutlineEntry("Name", SymbolKind.Property, 13, 13, null, "string", null)
                        })
                })),
            expected);

        var diagnostics = new List<DiagnosticResult>
        {
            new("NL202", "error", "Type mismatch", "Program.nl", 5, 4, 3,
                null, null, null, null, "int", "string", null),
            new("NL901", "warning", "Unused variable", "Program.nl", 10, 4, 1,
                null, null, null, null, null, null, null)
        };

        AssertJsonContract("diagnostics",
            OutputFormatter.DiagnosticsToJson(diagnostics, "/project"),
            expected);

        AssertJsonContract("diagnosticsClusters",
            OutputFormatter.DiagnosticClustersToJson(diagnostics, "/project"),
            expected);

        AssertJsonContract("doc",
            OutputFormatter.DocToJson(
                new DocResult(
                    "Console",
                    "System.Console",
                    "class",
                    "Represents the standard input, output, and error streams.",
                    "System",
                    new[]
                    {
                        new DocMemberResult("WriteLine", "method", "void", "Writes a line", "(string value)")
                    },
                    new[]
                    {
                        new DocParameterResult("value", "string", "The text to write")
                    },
                    null,
                    null,
                    new[] { "Object" }),
                "Console"),
            expected);

        AssertJsonContract("type",
            OutputFormatter.TypeToJson(
                new TypeResult("stats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1)),
                "Program.nl",
                85,
                22),
            expected);

        AssertJsonContract("definition",
            OutputFormatter.DefinitionToJson(
                new DefinitionResult("GetStats", "function", "Services/TaskService.nl", 93, 5, 8)),
            expected);

        AssertJsonContract("definitionSearch",
            OutputFormatter.DefinitionSearchToJson(
                "Person",
                new List<DefinitionResult>
                {
                    new("Person", "record", "Models.nl", 5, 0, 5),
                    new("Person", "class", "Other.nl", 10, 0, 5)
                }),
            expected);

        AssertJsonContract("references",
            OutputFormatter.ReferencesToJson(
                "Person",
                "class",
                new LocationResult("Models.nl", 5, 0),
                new List<ReferenceResult>
                {
                    new("Models.nl", 5, 0, 6, "class Person {", true),
                    new("Program.nl", 3, 8, 6, "p := Person{}", false)
                }),
            expected);

        AssertJsonContract("completions",
            OutputFormatter.CompletionsToJson(
                new CompletionResult(
                    CompletionContext.MemberAccess,
                    "service",
                    "TaskService",
                    new Dictionary<string, List<CompletionItem>>
                    {
                        ["functions"] = new()
                        {
                            new CompletionItem("GetStats", "function", "TaskStats", "()", "Returns the task statistics", false)
                        }
                    }),
                "Program.nl",
                85,
                22),
            expected);

        AssertJsonContract("inspect",
            OutputFormatter.InspectToJson(
                new InspectResult(
                    new InspectSymbolResult("GetStats", "function", new LocationResult("Services/TaskService.nl", 93, 5)),
                    new TypeResult("GetStats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1)),
                    new DefinitionResult("GetStats", "function", "Services/TaskService.nl", 93, 5, 8),
                    new InspectReferencesResult(2, 1, new[]
                    {
                        new ReferenceResult("Services/TaskService.nl", 93, 5, 8, "func GetStats(): TaskStats {", true),
                        new ReferenceResult("Program.nl", 85, 22, 8, "stats := service.GetStats()", false)
                    }),
                    new CompletionResult(
                        CompletionContext.MemberAccess,
                        "service",
                        "TaskService",
                        new Dictionary<string, List<CompletionItem>>
                        {
                            ["functions"] = new()
                            {
                                new CompletionItem("GetStats", "function", "TaskStats", "()", null, false)
                            }
                        })),
                "Program.nl",
                85,
                22),
            expected);

        AssertJsonContract("perf",
            OutputFormatter.PerfToJson("Program.nl", 5, 12, "/project"),
            expected);

        AssertJsonContract("buildPerfReport",
            OutputFormatter.BuildPerfReportToJson(
                "/project",
                aotBlockers: new[]
                {
                    new OutputFormatter.PerfReportAotBlocker(
                        "NL960",
                        "metadata-required",
                        "Program.nl",
                        5,
                        12,
                        "GetType",
                        "ClrPublic",
                        "Main",
                        true)
                }),
            expected);

        AssertJsonContract("check",
            OutputFormatter.CheckToJson(
                new List<DiagnosticResult>
                {
                    new("NL202", "error", "Type mismatch", "Program.nl", 5, 4, 3,
                        null, null, null, null, "int", "string", null)
                },
                "/project",
                3),
            expected);

        AssertJsonContract("checkSystemsReport",
            OutputFormatter.CheckSystemsReportToJson(
                new List<DiagnosticResult>(),
                "/project",
                1,
                SystemsReport.Empty(ProjectFileParser.CreateDefault("JsonContract"))),
            expected);

        AssertJsonContract("trusted",
            OutputFormatter.TrustedToJson(
                SystemsReport.Empty(ProjectFileParser.CreateDefault("JsonContract")),
                "/project"),
            expected);
    }

    [Fact]
    public void Json_InspectSummary_HasStableEnvelope()
    {
        var expected = LoadJsonContractRootKeys();

        var json = OutputFormatter.InspectSummaryToJson(
            new InspectResult(
                new InspectSymbolResult("GetStats", "function", new LocationResult("Services/TaskService.nl", 93, 5)),
                new TypeResult("GetStats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1)),
                new DefinitionResult("GetStats", "function", "Services/TaskService.nl", 93, 5, 8),
                new InspectReferencesResult(2, 1, new[]
                {
                    new ReferenceResult("Services/TaskService.nl", 93, 5, 8, "func GetStats(): TaskStats {", true),
                    new ReferenceResult("Program.nl", 85, 22, 8, "stats := service.GetStats()", false)
                }),
                new CompletionResult(
                    CompletionContext.MemberAccess,
                    "service",
                    "TaskService",
                    new Dictionary<string, List<CompletionItem>>
                    {
                        ["functions"] = new()
                        {
                            new CompletionItem("GetStats", "function", "TaskStats", "()", null, false)
                        }
                    })),
            "Program.nl",
            85,
            22);

        AssertJsonContract("inspectSummary", json, expected);
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
                "int", "string", "https://docs.n-sharp.dev/errors/NL202")
        };

        var text = OutputFormatter.DiagnosticsToText(diagnostics);

        // Header
        var expectedHeader = "\u2500\u2500 [NL202] ERROR " + new string('\u2500', 29) + " Program.nl:5:4 \u2500\u2500";
        Assert.Contains(expectedHeader, text);
        Assert.Contains("[NL202] ERROR", text);
        Assert.Contains("Program.nl:5:4", text);

        // Source snippet with caret
        Assert.Contains("    5 |     x := \"hi\"", text);
        Assert.Contains("      |    ^^^", text);

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
        Assert.Contains("See: https://docs.n-sharp.dev/errors/NL202", text);

        // Summary
        Assert.Contains("1 error", text);
    }

    [Fact]
    public void DiagnosticsToText_SourceSnippetTrimsAndPinsCaretWidth()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            new("NL202", "error", "Type mismatch",
                "Program.nl", 12, 0, 0,
                "value := 1   ",
                null, null, null, null, null, null)
        };

        var text = OutputFormatter.DiagnosticsToText(diagnostics);

        Assert.Contains("    12 | value := 1", text);
        Assert.DoesNotContain("    12 | value := 1   ", text);
        Assert.Contains("       | ^", text);
    }

    [Fact]
    public void DiagnosticsToText_UnknownSeverityUsesInvariantFallback()
    {
        var previousCulture = CultureInfo.CurrentCulture;
        CultureInfo.CurrentCulture = new CultureInfo("tr-TR");

        try
        {
            var diagnostics = new List<DiagnosticResult>
            {
                new("NL777", "idi", "Unknown severity edge case", "Program.nl", 1, 1, 1,
                    null, null, null, null, null, null, null)
            };

            var text = OutputFormatter.DiagnosticsToText(diagnostics);

            Assert.Contains("[NL777] IDI", text);
            Assert.DoesNotContain("[NL777] \u0130D\u0130", text);
        }
        finally
        {
            CultureInfo.CurrentCulture = previousCulture;
        }
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
        Assert.Contains("Found 2 errors, 1 warning.", text);
    }

    [Fact]
    public void DiagnosticsToText_EmptyReturnsNoDiagnostics()
    {
        var text = OutputFormatter.DiagnosticsToText(new List<DiagnosticResult>());
        Assert.Equal("No diagnostics found.", text);
    }

    [Fact]
    public void CompletionsToText_FormatsGroupedItemsAndReceiver()
    {
        var completions = new CompletionResult(
            CompletionContext.MemberAccess,
            "service",
            "TaskService",
            new Dictionary<string, List<CompletionItem>>
            {
                ["functions"] = new()
                {
                    new CompletionItem("GetStats", "function", "TaskStats", "()", null, false)
                },
                ["properties"] = new()
                {
                    new CompletionItem("Total", "property", "int", null, null, false)
                }
            });

        var text = OutputFormatter.CompletionsToText(completions, "Program.nl", 85, 22);

        Assert.Equal(
            string.Join(Environment.NewLine,
                "Completions at Program.nl:85:22 (context: memberaccess)",
                "Receiver: service (TaskService)",
                string.Empty,
                "  functions (1):",
                "    GetStats (): TaskStats",
                "  properties (1):",
                "    Total: int",
                string.Empty),
            text);
    }

    [Fact]
    public void CompletionsToText_TruncatesLongCategories()
    {
        var items = Enumerable.Range(1, 51)
            .Select(i => new CompletionItem($"Item{i}", "method", null, null, null, false))
            .ToList();
        var completions = new CompletionResult(
            CompletionContext.Identifier,
            null,
            null,
            new Dictionary<string, List<CompletionItem>>
            {
                ["methods"] = items
            });

        var text = OutputFormatter.CompletionsToText(completions, "Program.nl", 3, 8);

        var expectedLines = new List<string>
        {
            "Completions at Program.nl:3:8 (context: identifier)",
            string.Empty,
            "  methods (51):"
        };
        expectedLines.AddRange(Enumerable.Range(1, 50).Select(i => $"    Item{i}"));
        expectedLines.Add("    ... and 1 more");
        expectedLines.Add(string.Empty);
        Assert.Equal(string.Join(Environment.NewLine, expectedLines), text);
    }

    [Fact]
    public void SymbolsToText_FormatsReadably()
    {
        var symbols = new List<SymbolResult>
        {
            new("Main", SymbolKind.Function, "Program.nl", 1, 0, "void",
                new[] { "pub" }, null,
                new[]
                {
                    new ParameterResult("name", "string", false, null),
                    new ParameterResult("count", "int", true, "42")
                }),
            new("Person", SymbolKind.Class, "Models.nl", 5, 0, null,
                new[] { "pub" },
                new SymbolResult[]
                {
                    new("Name", SymbolKind.Property, "Models.nl", 6, 0, "string", null, null, null)
                },
                null)
        };

        var text = OutputFormatter.SymbolsToText(symbols);
        Assert.Equal(
            string.Join(Environment.NewLine,
                "[pub] Function Main: void  (Program.nl:1)",
                "  (name: string, count: int = 42)",
                "[pub] Class Person  (Models.nl:5)",
                "  Property Name: string  (Models.nl:6)",
                string.Empty),
            text);
    }

    [Fact]
    public void SymbolsToText_EmptyReturnsNoSymbols()
    {
        var text = OutputFormatter.SymbolsToText(new List<SymbolResult>());
        Assert.Equal("No symbols found.", text);
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
        Assert.Equal(
            string.Join(Environment.NewLine,
                "File: Program.nl",
                "Imports: System",
                string.Empty,
                "Class Person (lines 5-15)",
                "  Property Name (line 6)",
                "  Function Greet -> string (lines 8-12)",
                string.Empty),
            text);
    }

    [Fact]
    public void ReferencesToText_FormatsWithCounts()
    {
        var results = new List<ReferenceResult>
        {
            new("Models.nl", 5, 0, 6, "  class Person {  ", true),
            new("Program.nl", 3, 8, 6, "p := Person{}", false),
            new("Generated.nl", 9, 2, 6, null, false)
        };

        var text = OutputFormatter.ReferencesToText("Person", results);
        Assert.Equal(
            string.Join(Environment.NewLine,
                "References to 'Person' (3 found):",
                "  Models.nl:5:0 [definition]  class Person {",
                "  Program.nl:3:8  p := Person{}",
                "  Generated.nl:9:2",
                string.Empty),
            text);
    }

    [Fact]
    public void ReferencesToText_EmptyReturnsNoReferences()
    {
        var text = OutputFormatter.ReferencesToText("Foo", new List<ReferenceResult>());
        Assert.Equal("No references found for 'Foo'.", text);
    }

    [Fact]
    public void TypeToText_FormatsLocationAndDefinition()
    {
        var result = new TypeResult(
            "stats",
            "TaskStats",
            "record",
            new LocationResult("Services/TaskService.nl", 105, 1),
            "non-null");

        var text = OutputFormatter.TypeToText(result, "Program.nl", 85, 22);

        Assert.Equal(
            string.Join(Environment.NewLine,
                "At Program.nl:85:22:",
                "  stats: TaskStats (record)",
                "  Nullability: non-null",
                "  Defined at: Services/TaskService.nl:105:1",
                string.Empty),
            text);
    }

    [Fact]
    public void TypeToText_OmitsOptionalLines()
    {
        var result = new TypeResult("count", "int", "local", null);

        var text = OutputFormatter.TypeToText(result, "Program.nl", 3, 8);

        Assert.Equal(
            string.Join(Environment.NewLine,
                "At Program.nl:3:8:",
                "  count: int (local)",
                string.Empty),
            text);
    }

    [Fact]
    public void DefinitionToText_FormatsSingleResult()
    {
        var result = new DefinitionResult("Hi", "function", "Program.nl", 2, 6, 2);

        var text = OutputFormatter.DefinitionToText(result);

        Assert.Equal("function Hi at Program.nl:2:6", text);
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
        Assert.Equal(
            string.Join(Environment.NewLine,
                "Definitions of 'Point':",
                "  record Point at Models.nl:5:0",
                "  struct Point at Other.nl:10:0",
                string.Empty),
            text);
    }

    [Fact]
    public void DefinitionSearchToText_EmptyReturnsNoDefinitions()
    {
        var text = OutputFormatter.DefinitionSearchToText("Missing", new List<DefinitionResult>());

        Assert.Equal("No definitions found for 'Missing'.", text);
    }

    [Fact]
    public void InspectToText_FormatsSections()
    {
        var inspect = new InspectResult(
            new InspectSymbolResult("stats", "variable", new LocationResult("Program.nl", 85, 5)),
            new TypeResult("stats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1)),
            new DefinitionResult("Total", "property", "Services/TaskService.nl", 106, 5, 5),
            new InspectReferencesResult(2, 1, new[]
            {
                new ReferenceResult("Program.nl", 85, 5, 5, "stats := service.GetStats()", true),
                new ReferenceResult("Program.nl", 86, 33, 5, "Console.WriteLine($\"Total: {stats.Total}\")", false)
            }),
            new CompletionResult(
                CompletionContext.MemberAccess,
                "stats",
                "TaskStats",
                new Dictionary<string, List<CompletionItem>>
                {
                    ["properties"] = new()
                    {
                        new CompletionItem("Total", "property", "int", null, null, false)
                    }
                }));

        var text = OutputFormatter.InspectToText(inspect, "Program.nl", 86, 39);
        Assert.Equal(
            string.Join(Environment.NewLine,
                "Inspect Program.nl:86:39",
                string.Empty,
                "Symbol: stats (variable)",
                "  Defined at: Program.nl:85:5",
                string.Empty,
                "Type: TaskStats (record)",
                string.Empty,
                "Definition: property Total at Services/TaskService.nl:106:5",
                string.Empty,
                "References: 2 total (1 definitions)",
                "  Program.nl:85:5 [definition]  stats := service.GetStats()",
                "  Program.nl:86:33  Console.WriteLine($\"Total: {stats.Total}\")",
                string.Empty,
                "Completions at Program.nl:86:39 (context: memberaccess)",
                "Receiver: stats (TaskStats)",
                string.Empty,
                "  properties (1):",
                "    Total: int",
                string.Empty),
            text);
    }

    [Fact]
    public void InspectToText_FormatsMissingSections()
    {
        var inspect = new InspectResult(
            null,
            null,
            null,
            new InspectReferencesResult(0, 0, Array.Empty<ReferenceResult>()),
            new CompletionResult(
                CompletionContext.Unknown,
                null,
                null,
                new Dictionary<string, List<CompletionItem>>()));

        var text = OutputFormatter.InspectToText(inspect, "Program.nl", 1, 1);

        Assert.Equal(
            string.Join(Environment.NewLine,
                "Inspect Program.nl:1:1",
                string.Empty,
                "Symbol: none",
                string.Empty,
                "Type: unknown",
                string.Empty,
                "Definition: none",
                string.Empty,
                "References: 0 total (0 definitions)",
                string.Empty,
                "Completions at Program.nl:1:1 (context: unknown)",
                string.Empty,
                string.Empty),
            text);
    }

    [Fact]
    public void HoverToText_FormatsSignatureDefinitionAndDocumentation()
    {
        var hover = new HoverResult(
            "func Hi(): int",
            "Returns a value.\nSecond line.",
            "Program.nl",
            "function");

        var text = OutputFormatter.HoverToText(hover, "Program.nl", 2, 6);

        Assert.Equal(
            string.Join(Environment.NewLine,
                "Hover Program.nl:2:6",
                string.Empty,
                "Signature:  func Hi(): int",
                "Kind:       function",
                "Defined in: Program.nl",
                string.Empty,
                "Documentation:",
                "  Returns a value.",
                "  Second line.",
                string.Empty),
            text);
    }

    [Fact]
    public void HoverToText_OmitsOptionalLines()
    {
        var hover = new HoverResult("name: string", null, null, "variable");

        var text = OutputFormatter.HoverToText(hover, "Program.nl", 11, 5);

        Assert.Equal(
            string.Join(Environment.NewLine,
                "Hover Program.nl:11:5",
                string.Empty,
                "Signature:  name: string",
                "Kind:       variable",
                string.Empty),
            text);
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

    private static ProjectSnapshot CreateDiagnosticSnapshot(
        string projectRoot,
        string filePath,
        string source,
        CompilerError compilerError)
    {
        var fullPath = Path.GetFullPath(filePath);
        var unit = ParseCompilationUnit(source, fullPath);
        return new ProjectSnapshot(
            projectRoot,
            new Dictionary<string, CompilationUnit>(StringComparer.OrdinalIgnoreCase)
            {
                [fullPath] = unit
            },
            new Dictionary<string, SemanticModel>(StringComparer.OrdinalIgnoreCase),
            new[] { compilerError },
            new Analyzer(),
            new[] { fullPath },
            index: null,
            sourceTexts: new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                [fullPath] = source
            });
    }

    private static CompilationUnit ParseCompilationUnit(string source, string filePath)
    {
        var lexer = new Lexer(source, filePath);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, filePath, source);
        var result = parser.ParseCompilationUnit();

        Assert.NotNull(result.CompilationUnit);
        return result.CompilationUnit!;
    }

    private static void AssertJsonContract(string name, string json, IReadOnlyDictionary<string, string[]> expected)
    {
        var actual = GetRootPropertyNames(json);
        Assert.True(expected.TryGetValue(name, out var expectedKeys), $"Missing JSON contract snapshot: {name}");
        Assert.True(expectedKeys!.SequenceEqual(actual),
            $"{name} JSON envelope changed.\nExpected: [{string.Join(", ", expectedKeys)}]\nActual:   [{string.Join(", ", actual)}]");
    }

    private static IReadOnlyDictionary<string, string[]> LoadJsonContractRootKeys()
    {
        var path = FindJsonContractFixturePath();
        using var document = JsonDocument.Parse(File.ReadAllText(path));

        return document.RootElement.EnumerateObject()
            .ToDictionary(property => property.Name,
                property => property.Value.EnumerateArray()
                    .Select(value => value.GetString() ?? string.Empty)
                    .ToArray(),
                StringComparer.Ordinal);
    }

    private static string[] GetRootPropertyNames(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateObject().Select(property => property.Name).ToArray();
    }

    private static string FindJsonContractFixturePath()
    {
        var dir = Directory.GetCurrentDirectory();

        for (var i = 0; i < 10; i++)
        {
            var candidate = Path.Combine(dir, "tests", "fixtures", "json-contract-root-keys.golden.json");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            var parent = Directory.GetParent(dir);
            if (parent == null)
            {
                break;
            }

            dir = parent.FullName;
        }

        throw new DirectoryNotFoundException("Could not find json-contract-root-keys.golden.json.");
    }
}
