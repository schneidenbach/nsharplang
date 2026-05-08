using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

public class DiagnosticClusteringTests
{
    [Fact]
    public void CheckJson_IncludesAiConsumableDiagnosticClustersWithRootLocationExamplesAndActions()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            MissingSemicolon("src/A.nl", 40, "let answer = 42"),
            MissingSemicolon("src/B.nl", 7, "let total = count + 1"),
            UndefinedBuilder("src/C.nl", 12)
        };

        var json = OutputFormatter.CheckToJson(diagnostics, "/repo", checkedFiles: 3);

        using var doc = JsonDocument.Parse(json);
        var clusters = doc.RootElement.GetProperty("diagnosticClusters").EnumerateArray().ToArray();

        Assert.Equal(2, clusters.Length);
        Assert.Equal("NL102", clusters[0].GetProperty("code").GetString());
        Assert.Equal(2, clusters[0].GetProperty("count").GetInt32());
        Assert.Equal("syntax-missing-terminator", clusters[0].GetProperty("syntaxShape").GetString());
        Assert.Equal("variable-declaration", clusters[0].GetProperty("sourceConstruct").GetString());
        Assert.Equal("converter:semicolon-elision-or-statement-boundary", clusters[0].GetProperty("likelyRecipe").GetString());
        Assert.Equal("src/B.nl", clusters[0].GetProperty("rootLocation").GetProperty("file").GetString());
        Assert.Equal(7, clusters[0].GetProperty("rootLocation").GetProperty("line").GetInt32());
        Assert.NotEmpty(clusters[0].GetProperty("suggestedNextActions").EnumerateArray());
        Assert.Equal(2, clusters[0].GetProperty("examples").GetArrayLength());

        Assert.Equal("NL301", clusters[1].GetProperty("code").GetString());
        Assert.Equal("identifier-resolution", clusters[1].GetProperty("syntaxShape").GetString());
    }

    [Fact]
    public void CheckJson_ClassifiesCanonicalAsyncFunctionDeclarations()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            MissingSemicolon("src/A.nl", 12, "async func Load(): Task<int> {"),
            MissingSemicolon("src/B.nl", 20, "override async func Save(): Task {")
        };

        var json = OutputFormatter.CheckToJson(diagnostics, "/repo", checkedFiles: 2);

        using var doc = JsonDocument.Parse(json);
        var cluster = Assert.Single(doc.RootElement.GetProperty("diagnosticClusters").EnumerateArray());
        Assert.Equal("function-declaration", cluster.GetProperty("sourceConstruct").GetString());
    }

    [Fact]
    public void CheckJson_ClassifiesCSharpAutoPropertyAsMigrationArtifactNotParseFailure()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            new(
                Code: "NL102",
                Severity: "warning",
                Message: "C# auto-property accessor block '{ get; set; }' should be converted to N# property/record syntax",
                File: "src/Dto.nl",
                Line: 4,
                Column: 20,
                Length: 12,
                SourceSnippet: "Name: string { get; set; }",
                Explanation: null,
                Suggestion: "Prefer an N# record",
                Hint: null,
                ExpectedType: null,
                ActualType: null,
                DocsUrl: null)
        };

        var json = OutputFormatter.CheckToJson(diagnostics, "/repo", checkedFiles: 1);

        using var doc = JsonDocument.Parse(json);
        var cluster = Assert.Single(doc.RootElement.GetProperty("diagnosticClusters").EnumerateArray());
        Assert.Equal("csharp-migration-artifact", cluster.GetProperty("syntaxShape").GetString());
        Assert.Equal("property-declaration", cluster.GetProperty("sourceConstruct").GetString());
        Assert.Equal("migration:rewrite-auto-property-as-record-or-explicit-nsharp-property", cluster.GetProperty("likelyRecipe").GetString());
    }

    [Fact]
    public void DiagnosticsText_StartsWithClusterSummaryBeforeIndividualDiagnostics()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            MissingSemicolon("src/A.nl", 40, "let answer = 42"),
            MissingSemicolon("src/B.nl", 7, "let total = count + 1"),
            UndefinedBuilder("src/C.nl", 12)
        };

        var text = OutputFormatter.DiagnosticsToText(diagnostics);

        Assert.Contains("Diagnostic clusters (2 groups, 3 diagnostics)", text);
        Assert.Contains("[2x] NL102 / syntax-missing-terminator / variable-declaration", text);
        Assert.Contains("root: src/B.nl:7:5", text);
        Assert.Contains("next: Fix the earliest statement-boundary parse error first", text);
        Assert.True(text.IndexOf("Diagnostic clusters", StringComparison.Ordinal) < text.IndexOf("── [NL102] ERROR", StringComparison.Ordinal));
    }

    private static DiagnosticResult MissingSemicolon(string file, int line, string snippet) => new(
        Code: "NL102",
        Severity: "error",
        Message: "Expected token ';'",
        File: file,
        Line: line,
        Column: 5,
        Length: 1,
        SourceSnippet: snippet,
        Explanation: null,
        Suggestion: "Add ';'",
        Hint: null,
        ExpectedType: null,
        ActualType: null,
        DocsUrl: null);

    private static DiagnosticResult UndefinedBuilder(string file, int line) => new(
        Code: "NL301",
        Severity: "error",
        Message: "Undefined variable 'StringBuilder'",
        File: file,
        Line: line,
        Column: 10,
        Length: 13,
        SourceSnippet: "sb := new StringBuilder()",
        Explanation: null,
        Suggestion: "Import System.Text or qualify StringBuilder",
        Hint: null,
        ExpectedType: null,
        ActualType: null,
        DocsUrl: null);
}
