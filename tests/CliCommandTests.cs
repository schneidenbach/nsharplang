using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class CliCommandTests
{
    private static readonly string HelloWorldProject = Path.Combine(FindExamplesDir(), "01-hello-world");
    private static readonly string IssueTrackerFixture = Path.Combine(FindFixturesDir(), "issue-tracker");

    [Fact]
    public void CheckCommand_Help_IsSideEffectFree()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => CheckCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc check", stdout);
        Assert.DoesNotContain("Directory not found", stderr);
    }

    [Fact]
    public void CheckCommand_DefaultsToJsonEnvelope()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", HelloWorldProject }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        var doc = JsonDocument.Parse(stdout);
        Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal(NormalizePath(Path.GetFullPath(HelloWorldProject)),
            doc.RootElement.GetProperty("projectRoot").GetString());
        Assert.True(doc.RootElement.GetProperty("checkedFiles").GetInt32() >= 1);
        AssertJsonContract("check", stdout);
    }

    [Fact]
    public void FixCommand_Help_IsSideEffectFree()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => FixCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc fix", stdout);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
    }

    [Fact]
    public void FixCommand_DryRun_DefaultsToJsonEnvelope()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-fix-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var doc = JsonDocument.Parse(stdout);
            Assert.Equal("fix", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("dryRun").GetBoolean());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(NormalizePath(Path.GetFullPath(tempDir)),
                doc.RootElement.GetProperty("projectRoot").GetString());
            Assert.Equal(0, doc.RootElement.GetProperty("results").GetArrayLength());
            AssertJsonContract("fix", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void UpdateDependencyFilter_FiltersTargetNuGetDependencies()
    {
        var dependencies = new[]
        {
            new Reference { Nuget = "Serilog", Version = "3.1.1" },
            new Reference { Framework = "Microsoft.AspNetCore.App" },
            new Reference { Nuget = "Newtonsoft.Json", Version = "13.0.3" },
            new Reference { Dll = "lib/Analyzer.dll" },
            new Reference { Nuget = "serilog", Version = "4.0.0" },
            new Reference { Project = "../Shared/project.yml" },
            new Reference { Nuget = "System.Text.Json", Version = "10.0.0" }
        };

        var adapterAllNuGet = UpdateDependencyFilter.FilterAllNuGetDependencies(dependencies);
        Assert.Equal(new[] { "Serilog", "Newtonsoft.Json", "serilog", "System.Text.Json" },
            adapterAllNuGet.Select(reference => reference.Nuget));

        var serilog = UpdateDependencyFilter.FilterTargetNuGetDependencies(dependencies, "SERILOG");
        Assert.Equal(new[] { "Serilog", "serilog" },
            serilog.Select(reference => reference.Nuget));

        var missing = UpdateDependencyFilter.FilterTargetNuGetDependencies(dependencies, "Missing.Package");
        Assert.Empty(missing);
    }

    [Theory]
    [MemberData(nameof(QueryJsonContractCases))]
    public void QueryCommand_EmitsStableJsonEnvelope(string contractName, string[] args)
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(args));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        AssertJsonContract(contractName, stdout);
    }

    [Fact]
    public void QueryCommand_DiagnosticsClusters_EmitsClusterEnvelope()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-diagnostic-clusters-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: DiagnosticClusters
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    Console.WriteLine(undefinedVar1)
    Console.WriteLine(undefinedVar2)
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "diagnostics",
                "--clusters",
                "--project", tempDir
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("diagnostics.clusters", doc.RootElement.GetProperty("command").GetString());
            AssertJsonContract("diagnosticsClusters", stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            var cluster = Assert.Single(doc.RootElement.GetProperty("clusters").EnumerateArray(),
                item => item.GetProperty("category").GetString() == "identifier-resolution");
            Assert.Equal("symbols:missing-import-or-qualification", cluster.GetProperty("recipe").GetString());
            Assert.Equal("medium", cluster.GetProperty("risk").GetString());
            Assert.Equal("Program.nl", Assert.Single(cluster.GetProperty("files").EnumerateArray()).GetString());
            Assert.True(cluster.GetProperty("relatedDiagnostics").GetArrayLength() >= 2);
            Assert.StartsWith("nlc query inspect --file Program.nl --pos ", cluster.GetProperty("nextCommand").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Ast_EmitsStableNodeTypedJson()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-query-ast-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: AstQuery
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func add(x: int, y: int): int {
    return x + y
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "ast",
                "--file", "Program.nl",
                "--project", tempDir
            }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("query.ast", root.GetProperty("command").GetString());
            Assert.True(root.GetProperty("ok").GetBoolean());

            var file = Assert.Single(root.GetProperty("files").EnumerateArray());
            Assert.EndsWith("Program.nl", file.GetProperty("file").GetString());

            var ast = file.GetProperty("ast");
            Assert.Equal("CompilationUnit", ast.GetProperty("node").GetString());

            var func = Assert.Single(ast.GetProperty("declarations").EnumerateArray());
            Assert.Equal("FunctionDeclaration", func.GetProperty("node").GetString());
            Assert.Equal("add", func.GetProperty("name").GetString());
            Assert.Equal(2, func.GetProperty("parameters").GetArrayLength());
            Assert.Equal("x", func.GetProperty("parameters")[0].GetProperty("name").GetString());

            // Concrete node type is preserved through the polymorphic Statement base, with positions.
            var body = func.GetProperty("body");
            Assert.True(body.GetProperty("line").GetInt32() >= 1);
            var returnStmt = Assert.Single(body.GetProperty("statements").EnumerateArray());
            Assert.Equal("ReturnStatement", returnStmt.GetProperty("node").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Diagnostics_MalformedCode_EmitsStableHighSignalJson()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-malformed-diagnostics-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: MalformedDiagnostics
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class User {
    Name: string
}

func main() {
    first := 1 +
    Console.WriteLine(undefinedFromCli)
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "diagnostics",
                "--project", tempDir,
                "--file", "Program.nl",
                "--no-daemon"
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("diagnostics", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());

            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToList();
            Assert.Contains(results, result =>
                result.GetProperty("code").GetString() == "NL102" &&
                result.GetProperty("line").GetInt32() == 6 &&
                result.GetProperty("message").GetString()!.Contains("Expected expression after '+'") &&
                result.GetProperty("suggestion").GetString()!.Contains("Add an expression after '+'"));
            Assert.Contains(results, result =>
                result.GetProperty("code").GetString() == "NL301" &&
                result.GetProperty("message").GetString()!.Contains("undefinedFromCli"));
            Assert.DoesNotContain(results, result =>
                result.GetProperty("message").GetString()!.Contains("<error>", StringComparison.Ordinal));
            Assert.True(results.Count <= 4, $"Expected bounded diagnostics, got {results.Count}.");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Diagnostics_IncludesStrictLintErrorsForValidCode()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-lint-diagnostics-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: LintDiagnostics
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    unused := 42
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "diagnostics",
                "--project", tempDir,
                "--file", "Program.nl",
                "--no-daemon"
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            var diagnostic = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray(),
                result => result.GetProperty("code").GetString() == "NL001");
            Assert.Equal("error", diagnostic.GetProperty("severity").GetString());
            Assert.Contains("unused", diagnostic.GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Diagnostics_SeverityFilter_IsCaseInsensitive()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-diagnostic-severity-filter-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: SeverityFilterDiagnostics
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, ".editorconfig"), """
root = true

[*.nl]
dotnet_diagnostic.NL001.severity = warning
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    unused := 42
    undefinedFromCli()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "diagnostics",
                "--project", tempDir,
                "--file", "Program.nl",
                "--severity", "WARNING",
                "--no-daemon"
            }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            var diagnostic = Assert.Single(results);
            Assert.Equal("NL001", diagnostic.GetProperty("code").GetString());
            Assert.Equal("warning", diagnostic.GetProperty("severity").GetString());

            var summary = doc.RootElement.GetProperty("summary");
            Assert.Equal(0, summary.GetProperty("errors").GetInt32());
            Assert.Equal(1, summary.GetProperty("warnings").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Definition_SnapsFromClosingParen()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "definition",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "64:10"
        }));

        Assert.Equal(0, exitCode);

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("GetAll", doc.RootElement.GetProperty("result").GetProperty("name").GetString());
        Assert.Equal("Service.nl", doc.RootElement.GetProperty("result").GetProperty("file").GetString());
    }

    [Fact]
    public void QueryCommand_Type_NoSymbol_ReturnsStructuredEnvelope()
    {
        // Line 1 is a comment — no symbol there
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "type",
            "--project", IssueTrackerFixture,
            "--file", "Program.nl",
            "--pos", "1:1"
        }));

        Assert.Equal(1, exitCode);

        using var doc = JsonDocument.Parse(stdout);
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("type", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("noSymbol", doc.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.Equal("Program.nl",
            doc.RootElement.GetProperty("error").GetProperty("details").GetProperty("file").GetString());
        Assert.Equal(1,
            doc.RootElement.GetProperty("error").GetProperty("details").GetProperty("position").GetProperty("line").GetInt32());
    }

    [Fact]
    public void InspectSummary_Contract_UsesCompactEnvelope()
    {
        // Service.nl line 11: store: IssueStore (field)
        var (_, json, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "inspect",
            "--summary",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "11:5"
        }));

        AssertJsonContract("inspectSummary", json);
        using var doc = JsonDocument.Parse(json);
        Assert.True(doc.RootElement.TryGetProperty("summary", out var summary));
        Assert.False(doc.RootElement.TryGetProperty("result", out _));
        Assert.Equal("store", summary.GetProperty("symbol").GetProperty("name").GetString());
    }

    [Fact]
    public void QueryCommand_Inspect_TypeUseGenericArgument_UsesSemanticBinding()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-query-type-use-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(tempDir, "Foo"));
        Directory.CreateDirectory(Path.Combine(tempDir, "Bar"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: QueryTypeUse
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Foo", "Widget.nl"), """
namespace QueryTypeUse.Foo

record Widget {
    Value: string
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Bar", "Widget.nl"), """
namespace QueryTypeUse.Bar

record Widget {
    Value: int
}
""");
            var useSource = """
namespace QueryTypeUse.Foo
import System.Collections.Generic

func Read(items: List<Widget>): string {
    return ""
}
""";
            File.WriteAllText(Path.Combine(tempDir, "Foo", "UseWidget.nl"), useSource);
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
namespace QueryTypeUse

func Main() {
}
""");

            var typeUseColumn = useSource.Split('\n')[3].IndexOf("Widget", StringComparison.Ordinal) + 1;
            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "inspect",
                "--project", tempDir,
                "--file", "Foo/UseWidget.nl",
                "--pos", $"4:{typeUseColumn}"
            }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            var result = doc.RootElement.GetProperty("result");
            Assert.Equal("Widget", result.GetProperty("symbol").GetProperty("name").GetString());
            Assert.EndsWith("Foo/Widget.nl", result.GetProperty("definition").GetProperty("file").GetString(), StringComparison.Ordinal);

            var references = result.GetProperty("references").GetProperty("results").EnumerateArray().ToArray();
            Assert.Contains(references, item => item.GetProperty("file").GetString()!.EndsWith("Foo/UseWidget.nl", StringComparison.Ordinal));
            Assert.DoesNotContain(references, item => item.GetProperty("file").GetString()!.EndsWith("Bar/Widget.nl", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_UsesStableEnvelopeAndPerItemResponses()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "inspect",
    "file": "Service.nl",
    "pos": "11:5",
    "compact": true
  },
  {
    "command": "diagnostics",
    "clusters": true
  },
  {
    "command": "doc",
    "query": "Console.WriteLine"
  },
  {
    "command": "type",
    "file": "Program.nl",
    "pos": "1:1"
  }
]
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "batch",
                "--project", IssueTrackerFixture,
                "--requests", requestsPath
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            AssertJsonContract("batch", stdout);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("batch", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(4, doc.RootElement.GetProperty("requestCount").GetInt32());
            Assert.Equal(3, doc.RootElement.GetProperty("successCount").GetInt32());
            Assert.Equal(1, doc.RootElement.GetProperty("failureCount").GetInt32());

            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Equal("inspect", results[0].GetProperty("request").GetProperty("command").GetString());
            Assert.True(results[0].GetProperty("request").GetProperty("compact").GetBoolean());
            Assert.True(results[0].GetProperty("ok").GetBoolean());
            Assert.True(results[0].GetProperty("response").TryGetProperty("summary", out _));

            Assert.Equal("diagnostics", results[1].GetProperty("request").GetProperty("command").GetString());
            Assert.True(results[1].GetProperty("request").GetProperty("clusters").GetBoolean());
            Assert.True(results[1].GetProperty("ok").GetBoolean());
            Assert.Equal("diagnostics.clusters", results[1].GetProperty("response").GetProperty("command").GetString());

            Assert.Equal("doc", results[2].GetProperty("request").GetProperty("command").GetString());
            Assert.True(results[2].GetProperty("ok").GetBoolean());
            Assert.Equal("doc", results[2].GetProperty("response").GetProperty("command").GetString());

            Assert.Equal("type", results[3].GetProperty("request").GetProperty("command").GetString());
            Assert.False(results[3].GetProperty("ok").GetBoolean());
            Assert.Equal("noSymbol", results[3].GetProperty("response").GetProperty("error").GetProperty("code").GetString());
            Assert.Equal(
                QueryCommandKernels.GetNoSymbolAtPositionMessage("Program.nl", 1, 1),
                results[3].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_DocMissUsesQueryMessageKernel()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-doc-miss-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "doc",
    "query": "__DefinitelyMissingBatchDocType__"
  }
]
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "batch",
                "--project", IssueTrackerFixture,
                "--requests", requestsPath
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("batch", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(1, doc.RootElement.GetProperty("failureCount").GetInt32());

            var result = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray());
            Assert.Equal("doc", result.GetProperty("request").GetProperty("command").GetString());
            Assert.False(result.GetProperty("ok").GetBoolean());
            Assert.Equal(
                QueryCommandKernels.GetNoDocumentationMessage("__DefinitelyMissingBatchDocType__", null),
                result.GetProperty("response").GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchQueryRunner_LoadRequestsErrorsUseMessageKernels()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-load-errors-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var missingPath = Path.Combine(tempDir, "missing.json");
            var missing = Assert.Throws<FileNotFoundException>(() => BatchQueryRunner.LoadRequests(missingPath));
            Assert.Contains(BatchQueryKernels.GetRequestsFileNotFoundMessage(missingPath), missing.Message);

            var payloadPath = Path.Combine(tempDir, "payload.json");
            File.WriteAllText(payloadPath, "{}");
            var malformedPayload = Assert.Throws<InvalidDataException>(() => BatchQueryRunner.LoadRequests(payloadPath));
            Assert.Equal(BatchQueryKernels.GetPayloadShapeMessage(), malformedPayload.Message);

            var itemPath = Path.Combine(tempDir, "item.json");
            File.WriteAllText(itemPath, "[1]");
            var nonObjectItem = Assert.Throws<InvalidDataException>(() => BatchQueryRunner.LoadRequests(itemPath));
            Assert.Equal(BatchQueryKernels.GetRequestObjectRequiredMessage(), nonObjectItem.Message);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_DuplicateRequestIds_AreRejectedInOrdinalOrder()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-duplicates-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  { "id": "zeta", "command": "doc", "query": "Console.WriteLine" },
  { "id": "alpha", "command": "doc", "query": "String" },
  { "id": " ", "command": "doc", "query": "Int32" },
  { "id": "zeta", "command": "diagnostics" },
  { "id": "Alpha", "command": "doc", "query": "Console" },
  { "id": "alpha", "command": "symbols" }
]
""");

            var exception = Assert.Throws<InvalidDataException>(() => BatchQueryRunner.LoadRequests(requestsPath));
            Assert.Equal(BatchQueryKernels.GetDuplicateRequestIdsMessage("alpha, zeta"), exception.Message);

            var requests = new List<BatchQueryRequest>
            {
                new("doc", Id: "zeta"),
                new("doc", Id: "alpha"),
                new("doc", Id: " "),
                new("diagnostics", Id: "zeta"),
                new("doc", Id: "Alpha"),
                new("symbols", Id: "alpha")
            };

            var duplicateIds = BatchQueryKernels.FindDuplicateRequestIds(requests);
            Assert.Equal(new[] { "alpha", "zeta" }, duplicateIds);

            var okWords = new[] { 1UL | (1UL << 2) | (1UL << 5) | (1UL << 63) };
            var successCount = BatchQueryKernels.CountResultSuccesses(okWords, 6);
            Assert.Equal(3, successCount);

            Assert.Equal(0, BatchQueryKernels.CountResultSuccesses(Array.Empty<ulong>(), 0));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_InvalidRequestsUseMessageKernels()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-invalid-requests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "outline"
  },
  {
    "command": "doc"
  },
  {
    "command": "type",
    "file": "Program.nl"
  },
  {
    "command": "definition",
    "file": "Program.nl",
    "pos": "bad"
  },
  {
    "command": "unknown"
  }
]
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "batch",
                "--project", IssueTrackerFixture,
                "--requests", requestsPath
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(5, doc.RootElement.GetProperty("failureCount").GetInt32());

            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Equal(
                BatchQueryKernels.GetOutlineFileRequiredMessage(),
                results[0].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
            Assert.Equal(
                BatchQueryKernels.GetDocQueryRequiredMessage(),
                results[1].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
            Assert.Equal(
                BatchQueryKernels.GetFileAndPosRequiredMessage(),
                results[2].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
            Assert.Equal(
                BatchQueryKernels.GetInvalidPositionMessage("bad"),
                results[3].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
            Assert.Equal(
                BatchQueryKernels.GetUnsupportedCommandMessage("unknown"),
                results[4].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_PositionParsingUsesQueryKernelSemantics()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-position-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "type",
    "file": "Program.nl",
    "pos": " +1 : +1 "
  },
  {
    "command": "type",
    "file": "Program.nl",
    "pos": "2147483648:1"
  },
  {
    "command": "type",
    "file": "Program.nl",
    "pos": "1_000:2"
  }
]
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "batch",
                "--project", IssueTrackerFixture,
                "--requests", requestsPath
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal(3, doc.RootElement.GetProperty("requestCount").GetInt32());
            Assert.Equal(0, doc.RootElement.GetProperty("successCount").GetInt32());
            Assert.Equal(3, doc.RootElement.GetProperty("failureCount").GetInt32());

            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            var firstError = results[0].GetProperty("response").GetProperty("error");
            Assert.Equal("noSymbol", firstError.GetProperty("code").GetString());
            Assert.Equal(
                QueryCommandKernels.GetNoSymbolAtPositionMessage("Program.nl", 1, 1),
                firstError.GetProperty("message").GetString());
            var overflowError = results[1].GetProperty("response").GetProperty("error");
            Assert.Equal("invalidRequest", overflowError.GetProperty("code").GetString());
            Assert.Equal(
                BatchQueryKernels.GetInvalidPositionMessage("2147483648:1"),
                overflowError.GetProperty("message").GetString());
            var separatorError = results[2].GetProperty("response").GetProperty("error");
            Assert.Equal("invalidRequest", separatorError.GetProperty("code").GetString());
            Assert.Equal(
                BatchQueryKernels.GetInvalidPositionMessage("1_000:2"),
                separatorError.GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_SymbolKindParsingUsesQueryKernel()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-symbol-kind-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "symbols",
    "kind": "class"
  }
]
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "batch",
                "--project", IssueTrackerFixture,
                "--requests", requestsPath
            }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            var response = doc.RootElement.GetProperty("results")[0].GetProperty("response");
            var symbols = response.GetProperty("results").EnumerateArray().ToArray();
            Assert.NotEmpty(symbols);
            Assert.All(symbols, symbol => Assert.Equal("class", symbol.GetProperty("kind").GetString()));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryInspect_RejectsCompactTextOutputMode()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "inspect",
            "--file",
            "Program.nl",
            "--pos",
            "1:1",
            "--text",
            "--compact",
            "--no-daemon"
        }));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdout));
        Assert.Contains("--compact/--summary is only supported with JSON output.", stderr);
    }

    [Fact]
    public void NewCommandKernels_SummarizesArguments()
    {
        var args = new[] { "--template", "library", "--systems", "PacketCore", "-h" };

        var dogfoodSummary = NewCommandKernels.GetArgumentSummary(args);
        Assert.Equal("PacketCore", dogfoodSummary.FirstPositional);
        Assert.Null(dogfoodSummary.SecondPositional);
        Assert.Equal("library", dogfoodSummary.TemplateOption);
        Assert.True(dogfoodSummary.Systems);
        Assert.True(dogfoodSummary.ShowHelp);

        var positionalTemplate = NewCommandKernels.GetArgumentSummary(new[] { "systems-cli", "PacketTool" });
        Assert.Equal("systems-cli", positionalTemplate.FirstPositional);
        Assert.Equal("PacketTool", positionalTemplate.SecondPositional);
        Assert.Null(positionalTemplate.TemplateOption);

        var typeAlias = NewCommandKernels.GetArgumentSummary(new[] { "--type", "webapi", "MyApi" });
        Assert.Equal("webapi", typeAlias.TemplateOption);
        Assert.Equal("MyApi", typeAlias.FirstPositional);

        var libraryAlias = NewCommandKernels.NormalizeTemplateKind(" LIB ");
        Assert.Equal(NewProjectTemplateKind.Library, libraryAlias);
        var webApiAlias = NewCommandKernels.NormalizeTemplateKind("web-api");
        Assert.Equal(NewProjectTemplateKind.WebApi, webApiAlias);
        var systemsAlias = NewCommandKernels.NormalizeTemplateKind("systems");
        Assert.Equal(NewProjectTemplateKind.SystemsCli, systemsAlias);
        var unknownAlias = NewCommandKernels.NormalizeTemplateKind("unknown");
        Assert.Equal(NewProjectTemplateKind.Unknown, unknownAlias);

        var systemsConsole = NewCommandKernels.ResolveTemplateKind("console", systems: true);
        Assert.Equal(NewProjectTemplateKind.SystemsCli, systemsConsole);
        var systemsLibrary = NewCommandKernels.ResolveTemplateKind("library", systems: true);
        Assert.Equal(NewProjectTemplateKind.SystemsLib, systemsLibrary);
        var systemsTest = NewCommandKernels.ResolveTemplateKind("test", systems: true);
        Assert.Equal(NewProjectTemplateKind.Test, systemsTest);
        var effectiveWebApi = NewCommandKernels.ResolveTemplateKind("web-api", systems: false);
        Assert.Equal(NewProjectTemplateKind.WebApi, effectiveWebApi);

        var webApiSourceKinds = NewCommandKernels.GetTemplateSourceFileKinds("webapi");
        Assert.Equal(
            new[] { NewTemplateSourceFileKind.Program, NewTemplateSourceFileKind.WebApiController },
            webApiSourceKinds);
        var systemsLibSourceKinds = NewCommandKernels.GetTemplateSourceFileKinds("systems-lib");
        Assert.Equal(
            new[] { NewTemplateSourceFileKind.PacketCore, NewTemplateSourceFileKind.PacketCoreTests },
            systemsLibSourceKinds);
        var unknownSourceKinds = NewCommandKernels.GetTemplateSourceFileKinds("unknown");
        Assert.Empty(unknownSourceKinds);

        Assert.True(NewCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);

        var helpText = NewCommandKernels.GetHelpText();
        Assert.Contains("N# New Project", helpText);
        Assert.Contains("Usage: nlc new <project-name>", helpText);
        Assert.Contains("Project creation failed", helpText);
        Assert.Equal(
            "Usage: nlc new <project-name> [--template <template>]",
            NewCommandKernels.GetUsageMessage());
        Assert.Equal(
            "Invalid template. Expected one of: console, library, test, webapi, systems-cli, systems-lib.",
            NewCommandKernels.GetInvalidTemplateMessage());
        Assert.Equal(
            "Directory already exists: /tmp/MyApp. Use a different name or remove the existing directory.",
            NewCommandKernels.GetDirectoryExistsMessage("/tmp/MyApp"));
        Assert.Equal(
            "Creating new systems-cli project: PacketTool",
            NewCommandKernels.GetCreatingProjectMessage("systems-cli", "PacketTool"));
        Assert.Equal("Created: MyApp/project.yml", NewCommandKernels.GetCreatedFileMessage("MyApp", "project.yml"));
        Assert.Equal(
            "Project shape: csproj-free source tree; nlc builds directly from project.yml.",
            NewCommandKernels.GetProjectShapeMessage());
        Assert.Equal(
            "To check systems policy and inspect performance facts:",
            NewCommandKernels.GetNextStepsIntroMessage("systems-lib"));
        Assert.Equal("To build your project:", NewCommandKernels.GetNextStepsIntroMessage("library"));
        Assert.Equal("  cd MyApp", NewCommandKernels.GetCdCommandMessage("MyApp"));
        Assert.Equal("  nlc check --systems-report", NewCommandKernels.GetSystemsReportCommandMessage());
        Assert.Equal("  nlc build --perf-report", NewCommandKernels.GetSystemsBuildCommandMessage());
        Assert.Equal("  nlc build", NewCommandKernels.GetBuildCommandMessage());
        Assert.Equal("  nlc test", NewCommandKernels.GetTestCommandMessage());
        Assert.Equal("  nlc run", NewCommandKernels.GetRunCommandMessage());
        Assert.Equal("Failed to create project: denied", NewCommandKernels.GetFailedMessage("denied"));

        var consoleYaml = NewCommandKernels.GetProjectYamlText("MyApp", "console");
        Assert.Equal(ProjectFileParser.GenerateTemplate("MyApp"), consoleYaml);

        var libraryYaml = NewCommandKernels.GetProjectYamlText("MyLib", "library");
        Assert.Contains("name: MyLib\n", libraryYaml);
        Assert.Contains("outputType: library\n", libraryYaml);
        Assert.Contains("language:\n  asyncDefaultType: ValueTask\n", libraryYaml);
        Assert.DoesNotContain("entry: Program.nl", libraryYaml, StringComparison.Ordinal);

        var webApiYaml = NewCommandKernels.GetProjectYamlText("MyApi", "webapi");
        Assert.Contains("sdk: Microsoft.NET.Sdk.Web\n", webApiYaml);
        Assert.Contains("  - framework: Microsoft.AspNetCore.App\n", webApiYaml);
        Assert.Contains("  - nuget: Swashbuckle.AspNetCore\n    version: 7.2.0\n", webApiYaml);

        var systemsCliYaml = NewCommandKernels.GetProjectYamlText("PacketTool", "systems-cli");
        Assert.Contains("entry: Program.nl\n", systemsCliYaml);
        Assert.Contains("outputType: exe\n", systemsCliYaml);
        Assert.Contains("  profile: systems\n", systemsCliYaml);
        Assert.Contains("    warmup:\n      - Warmup\n", systemsCliYaml);

        var systemsLibYaml = NewCommandKernels.GetProjectYamlText("PacketCore", "systems-lib");
        Assert.Contains("outputType: library\n", systemsLibYaml);
        Assert.Contains("  profile: systems\n", systemsLibYaml);
        Assert.DoesNotContain("entry: Program.nl", systemsLibYaml, StringComparison.Ordinal);

        Assert.Equal(
            "{\n"
            + "  \"sdk\": {\n"
            + "    \"version\": \"10.0.100\",\n"
            + "    \"rollForward\": \"latestFeature\"\n"
            + "  },\n"
            + "  \"msbuild-sdks\": {\n"
            + "    \"NSharpLang.Sdk\": \"0.1.0\"\n"
            + "  }\n"
            + "}\n",
            NewCommandKernels.GetGlobalJsonText());
        var defaultNuGetConfig = NewCommandKernels.GetNuGetConfigText("%HOME%/.nsharp/packages");
        Assert.Equal(
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
            + "<configuration>\n"
            + "  <packageSources>\n"
            + "    <clear />\n"
            + "    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" />\n"
            + "    <add key=\"nsharp-local\" value=\"%HOME%/.nsharp/packages\" />\n"
            + "  </packageSources>\n"
            + "</configuration>\n",
            defaultNuGetConfig);
        Assert.Contains("value=\"%HOME%/.nsharp/packages\"", defaultNuGetConfig);

        var escapedNuGetConfig = NewCommandKernels.GetNuGetConfigText("/tmp/a&b<c>d\"e'f/packages");
        Assert.Contains("/tmp/a&amp;b&lt;c&gt;d&quot;e&apos;f/packages", escapedNuGetConfig);

        var consoleSource = NewCommandKernels.GetTemplateSourceText("console", NewTemplateSourceFileKind.Program);
        Assert.Equal("func main() {\n    print \"Hello, N#!\"\n}\n", consoleSource);

        var calculatorSource = NewCommandKernels.GetTemplateSourceText("library", NewTemplateSourceFileKind.Calculator);
        Assert.Contains("class Calculator {\n", calculatorSource);
        Assert.Contains("static func Add(a: int, b: int): int", calculatorSource);

        var calculatorTestsSource = NewCommandKernels.GetTemplateSourceText("test", NewTemplateSourceFileKind.CalculatorTests);
        Assert.Contains("test \"adds two numbers\" {\n", calculatorTestsSource);
        Assert.Contains("assert result == 3\n", calculatorTestsSource);

        var webApiProgramSource = NewCommandKernels.GetTemplateSourceText("webapi", NewTemplateSourceFileKind.Program);
        Assert.Contains("WebApplication.CreateBuilder(args)", webApiProgramSource);
        var controllerSource = NewCommandKernels.GetTemplateSourceText("webapi", NewTemplateSourceFileKind.WebApiController);
        Assert.Contains("[Route(\"api/weather\")]\n", controllerSource);
        Assert.Contains("CreateWeatherRequest", controllerSource);

        var systemsCliSource = NewCommandKernels.GetTemplateSourceText("systems-cli", NewTemplateSourceFileKind.Program);
        Assert.Contains("allow(alloc, reason: \"CLI startup allocates outside the hot parser\")", systemsCliSource);
        Assert.Contains("func main(): void", systemsCliSource);

        var packetCoreSource = NewCommandKernels.GetTemplateSourceText("systems-lib", NewTemplateSourceFileKind.PacketCore);
        Assert.Contains("public func AdaptPacket(bytes: byte[]): Result<uint, ParseError>", packetCoreSource);
        Assert.DoesNotContain("func main", packetCoreSource, StringComparison.Ordinal);

        var packetCoreTestsSource = NewCommandKernels.GetTemplateSourceText("systems-lib", NewTemplateSourceFileKind.PacketCoreTests);
        Assert.Equal("test \"systems smoke\" {\n    assert true\n}\n", packetCoreTestsSource);
    }

    [Fact]
    public void CompilationBackendSelectionKernels_ValidatesEffectiveBackend()
    {
        CompilationBackendSelectionKernels.Validate(null, null);
        CompilationBackendSelectionKernels.Validate("  ", new ProjectConfig { Backend = " il " });
        var invalid = Assert.Throws<InvalidOperationException>(() =>
            CompilationBackendSelectionKernels.Validate(null, new ProjectConfig { Backend = "native" }));
        Assert.Equal("Invalid backend: 'native'. Must be 'il'.", invalid.Message);
    }

    [Fact]
    public void UpdateCommandKernels_SummarizesArguments()
    {
        var args = new[] { "--dry-run", "-v", "Newtonsoft.Json", "-h" };

        var dogfoodSummary = UpdateCommandKernels.GetArgumentSummary(args);
        Assert.Equal("Newtonsoft.Json", dogfoodSummary.TargetPackage);
        Assert.True(dogfoodSummary.DryRun);
        Assert.True(dogfoodSummary.ShowHelp);

        Assert.Equal("Newtonsoft.Json", UpdateCommandKernels.GetArgumentSummary(new[] { "--dry-run", "Newtonsoft.Json" }).TargetPackage);
        Assert.Equal("Serilog", UpdateCommandKernels.GetArgumentSummary(new[] { "--dry-run", "-v", "Serilog" }).TargetPackage);
        Assert.Null(UpdateCommandKernels.GetArgumentSummary(new[] { "--dry-run" }).TargetPackage);
        Assert.True(UpdateCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);
        Assert.Equal("help", UpdateCommandKernels.GetArgumentSummary(new[] { "help" }).TargetPackage);

        var helpText = UpdateCommandKernels.GetHelpText();
        Assert.Contains("N# Update Dependencies", helpText);
        Assert.Contains("Usage: nlc update [package] [options]", helpText);
        Assert.Contains("Update failed", helpText);
        Assert.Equal("No project.yml found.", UpdateCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal("No NuGet dependencies to update.", UpdateCommandKernels.GetNoNuGetDependenciesMessage());
        Assert.Equal(
            "Package 'Serilog' not found in dependencies.",
            UpdateCommandKernels.GetPackageNotFoundMessage("Serilog"));
        Assert.Equal(
            "  Could not resolve latest version for Serilog",
            UpdateCommandKernels.GetResolveLatestFailureMessage("Serilog"));
        Assert.Equal(
            "  Serilog@3.1.0 is up to date",
            UpdateCommandKernels.GetPackageUpToDateMessage("Serilog", "3.1.0"));
        Assert.Equal(
            "  Serilog: unversioned -> 3.1.0",
            UpdateCommandKernels.GetPackageUpdateMessage("Serilog", string.Empty, "3.1.0"));
        Assert.Equal("Updated 1 package.", UpdateCommandKernels.GetUpdatedPackagesMessage(1));
        Assert.Equal("Updated 2 packages.", UpdateCommandKernels.GetUpdatedPackagesMessage(2));
        Assert.Equal("(dry run — no changes made)", UpdateCommandKernels.GetDryRunMessage());
        Assert.Equal("All packages are up to date.", UpdateCommandKernels.GetAllPackagesUpToDateMessage());
        Assert.Equal("Update failed: boom", UpdateCommandKernels.GetFailedMessage("boom"));
    }

    [Fact]
    public void AddCommandKernels_SummarizesArguments()
    {
        var args = new[] { "--version", "13.0.3", "--framework", "--prerelease", "Newtonsoft.Json" };

        var dogfoodSummary = AddCommandKernels.GetArgumentSummary(args);
        Assert.Equal("13.0.3", dogfoodSummary.VersionOption);
        Assert.Null(dogfoodSummary.PathOption);
        Assert.Equal("Newtonsoft.Json", dogfoodSummary.PackageOperand);
        Assert.True(dogfoodSummary.Framework);
        Assert.True(dogfoodSummary.Prerelease);
        Assert.False(dogfoodSummary.ShowHelp);

        Assert.Equal(
            "Newtonsoft.Json",
            AddCommandKernels.GetArgumentSummary(new[] { "--version", "13.0.3", "--framework", "Newtonsoft.Json" }).PackageOperand);
        Assert.Equal(
            "Serilog@3.1.1",
            AddCommandKernels.GetArgumentSummary(new[] { "--prerelease", "Serilog@3.1.1" }).PackageOperand);
        var pathSummary = AddCommandKernels.GetArgumentSummary(new[] { "--path", "../MyLibrary" });
        Assert.Equal("../MyLibrary", pathSummary.PathOption);
        Assert.Null(pathSummary.PackageOperand);
        var permissiveValue = AddCommandKernels.GetArgumentSummary(new[] { "--version", "--path", "../MyLibrary" });
        Assert.Equal("--path", permissiveValue.VersionOption);
        Assert.Equal("../MyLibrary", permissiveValue.PathOption);
        Assert.Equal("../MyLibrary", permissiveValue.PackageOperand);
        Assert.True(AddCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);
        Assert.Null(AddCommandKernels.GetArgumentSummary(new[] { "--version", "13.0.3" }).PackageOperand);

        var inlineSpec = AddCommandKernels.GetPackageSpec("Serilog@3.1.0", "ignored");
        Assert.Equal("Serilog", inlineSpec.PackageName);
        Assert.Equal("3.1.0", inlineSpec.Version);

        var explicitSpec = AddCommandKernels.GetPackageSpec("Serilog", "3.1.0");
        Assert.Equal("Serilog", explicitSpec.PackageName);
        Assert.Equal("3.1.0", explicitSpec.Version);

        var unversionedSpec = AddCommandKernels.GetPackageSpec("Serilog", null);
        Assert.Equal("Serilog", unversionedSpec.PackageName);
        Assert.Null(unversionedSpec.Version);

        var leadingAtSpec = AddCommandKernels.GetPackageSpec("@scope@1.0", "2.0.0");
        Assert.Equal("@scope@1.0", leadingAtSpec.PackageName);
        Assert.Equal("2.0.0", leadingAtSpec.Version);

        var dependencyLines = new[]
        {
            "name: Demo",
            "dependencies:",
            "  - Newtonsoft.Json@13.0.3",
            "    version: ignored",
            "targetFramework: net10.0"
        };
        var insertAt = AddCommandKernels.GetDependencyInsertIndex(dependencyLines);
        Assert.Equal(4, insertAt);

        var missingDependencySection = AddCommandKernels.GetDependencyInsertIndex(
            new[] { "name: Demo", "targetFramework: net10.0" });
        Assert.Equal(-1, missingDependencySection);

        var dependencies = new List<Reference>
        {
            new() { Nuget = "Newtonsoft.Json" },
            new() { Framework = "Microsoft.AspNetCore.App" },
            new() { Project = "../Shared/project.yml" },
            new()
        };

        var packageExists = AddCommandKernels.PackageOrFrameworkDependencyExists(
            dependencies,
            "newtonsoft.json");
        Assert.True(packageExists);

        var frameworkExists = AddCommandKernels.PackageOrFrameworkDependencyExists(
            dependencies,
            "microsoft.aspnetcore.app");
        Assert.True(frameworkExists);

        var packageMissing = AddCommandKernels.PackageOrFrameworkDependencyExists(
            dependencies,
            "Serilog");
        Assert.False(packageMissing);

        var projectExists = AddCommandKernels.ProjectDependencyExists(
            dependencies,
            "../shared/PROJECT.yml");
        Assert.True(projectExists);

        var projectMissing = AddCommandKernels.ProjectDependencyExists(
            dependencies,
            "../Other/project.yml");
        Assert.False(projectMissing);

        Assert.Equal(
            "Usage: nlc add <package> [--version <ver>]\n       nlc add <package>@<version>",
            AddCommandKernels.GetUsageMessage());
        Assert.Contains("--path <path>", AddCommandKernels.GetHelpText());
        Assert.Equal(
            "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project.",
            AddCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal(
            "Resolving latest version for Serilog...",
            AddCommandKernels.GetResolvingLatestVersionMessage("Serilog"));
        Assert.Equal(
            "Could not find package 'Missing.Package' on NuGet. Check the package name and try again.",
            AddCommandKernels.GetPackageNotFoundMessage("Missing.Package"));
        Assert.Equal(
            "'Serilog' is already in dependencies. Use 'nlc update' to change the version.",
            AddCommandKernels.GetDuplicatePackageMessage("Serilog"));
        Assert.Equal(
            "Project reference '../Shared/project.yml' is already in dependencies.",
            AddCommandKernels.GetDuplicateProjectReferenceMessage("../Shared/project.yml"));
        Assert.Equal(
            "Added framework reference 'Microsoft.AspNetCore.App' to project.yml",
            AddCommandKernels.GetFrameworkAddedMessage("Microsoft.AspNetCore.App"));
        Assert.Equal("Added Serilog@3.1.0 to project.yml", AddCommandKernels.GetPackageAddedMessage("Serilog", "3.1.0"));
        Assert.Equal(
            "Added project reference '../Shared/project.yml' to project.yml",
            AddCommandKernels.GetProjectReferenceAddedMessage("../Shared/project.yml"));
    }

    [Fact]
    public void RemoveCommandKernels_SummarizesArguments()
    {
        var args = new[] { "--dry-run", "Serilog", "-h" };

        var dogfoodSummary = RemoveCommandKernels.GetArgumentSummary(args);
        Assert.Equal("Serilog", dogfoodSummary.PackageOperand);
        Assert.True(dogfoodSummary.ShowHelp);

        Assert.Equal("Newtonsoft.Json", RemoveCommandKernels.GetArgumentSummary(new[] { "Newtonsoft.Json" }).PackageOperand);
        Assert.Equal("Serilog", RemoveCommandKernels.GetArgumentSummary(new[] { "--dry-run", "Serilog" }).PackageOperand);
        Assert.Null(RemoveCommandKernels.GetArgumentSummary(new[] { "--dry-run" }).PackageOperand);
        Assert.True(RemoveCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);
        Assert.Equal("help", RemoveCommandKernels.GetArgumentSummary(new[] { "help" }).PackageOperand);

        var shorthandVersion = RemoveCommandKernels.GetDependencyLineAction(
            "- Newtonsoft.Json@13.0.3",
            "Newtonsoft.Json");
        Assert.Equal(RemoveDependencyLineAction.RemoveSingleLine, shorthandVersion);

        var shorthandPackage = RemoveCommandKernels.GetDependencyLineAction(
            "  - serilog",
            "Serilog");
        Assert.Equal(RemoveDependencyLineAction.RemoveSingleLine, shorthandPackage);

        var nugetMapping = RemoveCommandKernels.GetDependencyLineAction(
            "- nuget: YamlDotNet",
            "YamlDotNet");
        Assert.Equal(RemoveDependencyLineAction.RemoveMappingBlock, nugetMapping);

        var frameworkMapping = RemoveCommandKernels.GetDependencyLineAction(
            "- framework: Microsoft.AspNetCore.App",
            "Microsoft.AspNetCore.App");
        Assert.Equal(RemoveDependencyLineAction.RemoveMappingBlock, frameworkMapping);

        var keep = RemoveCommandKernels.GetDependencyLineAction(
            "- package: Other",
            "Serilog");
        Assert.Equal(RemoveDependencyLineAction.Keep, keep);

        var stopIndented = RemoveCommandKernels.ShouldStopDependencyContinuationLine("    version: 1.0.0");
        Assert.False(stopIndented);

        var stopNextItem = RemoveCommandKernels.ShouldStopDependencyContinuationLine("- nuget: Other");
        Assert.True(stopNextItem);

        var stopTopLevel = RemoveCommandKernels.ShouldStopDependencyContinuationLine("dependencies:");
        Assert.True(stopTopLevel);

        Assert.Equal(
            RemoveDependencyLineAction.RemoveMappingBlock,
            RemoveCommandKernels.GetDependencyLineAction(" - nuget: YamlDotNet", "YamlDotNet"));
        Assert.False(RemoveCommandKernels.ShouldStopDependencyContinuationLine("  version: 1.0.0"));

        var helpText = RemoveCommandKernels.GetHelpText();
        Assert.Equal("Usage: nlc remove <package>", RemoveCommandKernels.GetUsageMessage());
        Assert.Contains("N# Remove Dependency", helpText);
        Assert.Contains("Failed to remove dependency", helpText);
        Assert.Equal("No project.yml found.", RemoveCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal(
            "Package 'Serilog' not found in dependencies.",
            RemoveCommandKernels.GetPackageNotFoundMessage("Serilog"));
        Assert.Equal("Removed Serilog from project.yml", RemoveCommandKernels.GetRemovedMessage("Serilog"));
    }

    [Fact]
    public void RestoreCommand_DeduplicatesProjectReferencesInGeneratedProps()
    {
        static int CountOccurrences(string text, string value)
        {
            var count = 0;
            var index = 0;
            while ((index = text.IndexOf(value, index, StringComparison.Ordinal)) >= 0)
            {
                count++;
                index += value.Length;
            }

            return count;
        }

        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-restore-dedup-{Guid.NewGuid():N}");
        var appDir = Path.Combine(tempDir, "App");
        var sharedDir = Path.Combine(tempDir, "Shared");
        Directory.CreateDirectory(appDir);
        Directory.CreateDirectory(sharedDir);

        try
        {
            File.WriteAllText(Path.Combine(sharedDir, "project.yml"), """
name: Shared
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(sharedDir, "Shared.csproj"), """<Project Sdk="NSharpLang.Sdk" />""");
            File.WriteAllText(Path.Combine(appDir, "project.yml"), """
name: App
outputType: exe
targetFramework: net10.0

dependencies:
  - nuget: Serilog
    version: 3.1.1
  - framework: Microsoft.AspNetCore.App
  - project: ../Shared/project.yml
  - project: ../Shared/Shared.csproj
  - project: ../Shared/project.yml
""");

            Assert.Equal(0, RestoreCommand.Restore(appDir, quiet: true));

            var props = File.ReadAllText(Path.Combine(appDir, "obj", "project.g.props"));
            Assert.Equal(1, CountOccurrences(props, "<ProjectReference Include="));
            Assert.Contains(Path.Combine(sharedDir, "Shared.csproj"), props);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompilerErrorSeverityFilter_FiltersCompilerErrorsBySeverity()
    {
        var errors = new[]
        {
            NewError("parse warning", ErrorSeverity.Warning),
            NewError("parse error", ErrorSeverity.Error),
            NewError("backend error", ErrorSeverity.Error),
            NewError("lint warning", ErrorSeverity.Warning),
            NewError("aot error", ErrorSeverity.Error)
        };

        var actualErrors = CompilerErrorSeverityFilter.Filter(errors, ErrorSeverity.Error);
        Assert.Equal(
            new[] { errors[1], errors[2], errors[4] },
            actualErrors);

        var actualWarnings = CompilerErrorSeverityFilter.Filter(errors, ErrorSeverity.Warning);
        Assert.Equal(
            new[] { errors[0], errors[3] },
            actualWarnings);

        static CompilerError NewError(string message, ErrorSeverity severity) =>
            new(ErrorCode.InvalidSyntax, message, 1, 1, severity);
    }

    [Fact]
    public void QuerySymbolNameFilter_FiltersSymbolsByNamePattern()
    {
        var symbols = new[]
        {
            NewSymbol("UserService"),
            NewSymbol("OrderService"),
            NewSymbol("UserQuery"),
            NewSymbol("RenderPipeline"),
            NewSymbol("CurrentUser")
        };

        var substringMatches = QuerySymbolNameFilter.Filter(
            symbols,
            "user",
            200);
        Assert.Equal(
            new[] { "UserService", "UserQuery", "CurrentUser" },
            substringMatches.Select(symbol => symbol.Name));

        var globMatches = QuerySymbolNameFilter.Filter(
            symbols,
            "*Service",
            200);
        Assert.Equal(
            new[] { "UserService", "OrderService" },
            globMatches.Select(symbol => symbol.Name));

        var limitedMatches = QuerySymbolNameFilter.Filter(
            symbols,
            "*",
            2);
        Assert.Equal(
            new[] { "UserService", "OrderService" },
            limitedMatches.Select(symbol => symbol.Name));

        Assert.Throws<InvalidOperationException>(() =>
            QuerySymbolNameFilter.Filter(
                new[] { NewSymbol("café") },
                "caf*",
                200));

        Assert.Throws<InvalidOperationException>(() =>
            QuerySymbolNameFilter.Filter(
                symbols,
                "usér",
                200));

        static SymbolResult NewSymbol(string name) =>
            new(
                name,
                SymbolKind.Function,
                "Program.nl",
                1,
                1,
                null,
                null,
                null,
                null);
    }

    [Fact]
    public void BatchCommand_TextMode_IsRejected()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, "[]");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "batch",
                "--text",
                "--requests", requestsPath
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("Batch queries only support JSON output.", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_ReportsMissingImportDiagnostics()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-check-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
    Console.WriteLine(sb.ToString())
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            var doc = JsonDocument.Parse(stdout);
            Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Contains(doc.RootElement.GetProperty("results").EnumerateArray(),
                result => result.GetProperty("code").GetString() == "NL002");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_CircularFileImports_ReportCyclePathInJsonAndText()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-circular-import-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CircularImports
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "A.nl"), """
import "B"

class A {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "B.nl"), """
import "C"

class B {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "C.nl"), """
import "A"

class C {
}
""");

            var (jsonExitCode, jsonStdout, jsonStderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));
            var (textExitCode, textStdout, textStderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir, "--text" }));

            Assert.Equal(1, jsonExitCode);
            Assert.True(string.IsNullOrWhiteSpace(jsonStderr));
            using var doc = JsonDocument.Parse(jsonStdout);
            var diagnostic = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray(),
                result => result.GetProperty("code").GetString() == "NL703");
            var jsonMessage = diagnostic.GetProperty("message").GetString();
            var jsonExplanation = diagnostic.GetProperty("explanation").GetString();
            var jsonHint = diagnostic.GetProperty("hint").GetString();
            var jsonSuggestion = diagnostic.GetProperty("suggestion").GetString();
            Assert.Contains("A.nl -> B.nl -> C.nl -> A.nl", jsonMessage);
            Assert.Contains("A.nl -> B.nl -> C.nl -> A.nl", jsonExplanation);
            Assert.Contains("Import path: A.nl -> B.nl -> C.nl -> A.nl", jsonHint);
            Assert.Contains("Move shared types", jsonSuggestion);

            Assert.Equal(1, textExitCode);
            Assert.True(string.IsNullOrWhiteSpace(textStdout));
            Assert.Contains("A.nl -> B.nl -> C.nl -> A.nl", textStderr);
            Assert.Contains("Move shared types", textStderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_LongCircularFileImports_BoundsCyclePathInJsonAndText()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-circular-import-long-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: LongCircularImports
outputType: exe
targetFramework: net10.0
""");

            const int fileCount = 12;
            for (var i = 0; i < fileCount; i++)
            {
                var current = $"F{i:00}";
                var next = $"F{(i + 1) % fileCount:00}";
                File.WriteAllText(Path.Combine(tempDir, $"{current}.nl"), $$"""
import "{{next}}"

class {{current}} {
}
""");
            }

            var (jsonExitCode, jsonStdout, jsonStderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));
            var (textExitCode, textStdout, textStderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir, "--text" }));

            Assert.Equal(1, jsonExitCode);
            Assert.True(string.IsNullOrWhiteSpace(jsonStderr));
            using var doc = JsonDocument.Parse(jsonStdout);
            var diagnostic = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray(),
                result => result.GetProperty("code").GetString() == "NL703");
            var jsonMessage = diagnostic.GetProperty("message").GetString();
            var jsonHint = diagnostic.GetProperty("hint").GetString();
            Assert.Contains("F00.nl -> F01.nl -> F02.nl -> F03.nl -> F04.nl -> F05.nl", jsonMessage);
            Assert.Contains("... (4 more imports) -> F10.nl -> F11.nl -> F00.nl", jsonMessage);
            Assert.DoesNotContain("F06.nl -> F07.nl -> F08.nl -> F09.nl", jsonMessage);
            Assert.Contains("... (4 more imports)", jsonHint);

            Assert.Equal(1, textExitCode);
            Assert.True(string.IsNullOrWhiteSpace(textStdout));
            Assert.Contains("... (4 more imports) -> F10.nl -> F11.nl -> F00.nl", textStderr);
            Assert.DoesNotContain("F06.nl -> F07.nl -> F08.nl -> F09.nl", textStderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_PackageImport_AllowsPascalCaseExports()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-package-exports-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
package Models

class Item {
    func Visible(): string {
        return "visible"
    }
}

public class explicitItem {
    public func visibleExplicit(): string {
        return "explicit"
    }
}

func BuildItem(): Item {
    return new Item()
}

enum Status {
    Ready,
    hidden
}

public func buildExplicit(): explicitItem {
    return new explicitItem()
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import Models

package App

func Main() {
    item := BuildItem()
    explicitValue := buildExplicit()
    print item.Visible()
    print explicitValue.visibleExplicit()
    print Status.hidden
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_PackageImport_RejectsCamelCaseTypesMembersAndFunctions()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-package-hidden-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
package Models

class Item {
    func hiddenMethod(): string {
        return "hidden"
    }
}

private class SecretPascal {
}

class hiddenThing {
}

union Outcome {
    Ok
    hidden
}

func hiddenFunction(): string {
    return "hidden"
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import Models

package App

func Main() {
    thing := new hiddenThing()
    secret := new SecretPascal()
    item := new Item()
    print item.hiddenMethod()
    print Outcome.hidden
    print hiddenFunction()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenThing' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'SecretPascal' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenMethod' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hidden' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenFunction' is not exported"));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_InaccessibleMember_ReportsNL308WithMemberNameSpan()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-nl308-span-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: InaccessibleSpan
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Widget.nl"), """
package Models

class Widget {
    func secretMethod(): string {
        return "x"
    }
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import "Models/Widget"

package App

func Main() {
    w := new Widget()
    print w.secretMethod()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();

            var diagnostic = Assert.Single(results,
                result => result.GetProperty("message").GetString()!.Contains("'secretMethod' is not exported"));
            Assert.Equal("NL308", diagnostic.GetProperty("code").GetString());
            // `print w.secretMethod()` — column 13 is where `secretMethod` begins (1-based).
            Assert.Equal(7, diagnostic.GetProperty("line").GetInt32());
            Assert.Equal(13, diagnostic.GetProperty("column").GetInt32());
            Assert.Equal("secretMethod".Length, diagnostic.GetProperty("length").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_PackageImport_UsesImportedPackageBeforeDuplicateProjectSymbolAmbiguity()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-package-duplicate-export-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));
        Directory.CreateDirectory(Path.Combine(tempDir, "Other"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
package Models

class Item {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Other", "Item.nl"), """
package Other

class Item {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import Models

package App

func Main() {
    _item := new Item()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_PackageImport_ReportsUnexportedImportedDuplicateInsteadOfAmbiguity()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-package-duplicate-hidden-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));
        Directory.CreateDirectory(Path.Combine(tempDir, "Other"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
package Models

class hiddenThing {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Other", "Item.nl"), """
package Other

class hiddenThing {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import Models

package App

func Main() {
    thing := new hiddenThing()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenThing' is not exported"));
            Assert.DoesNotContain(results, result => result.GetProperty("message").GetString()!.Contains("defined in multiple files"));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_NamespaceImport_RejectsCamelCaseTypesMembersAndFunctions()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-namespace-hidden-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: NamespaceVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
namespace Models

class Item {
    func hiddenMethod(): string {
        return "hidden"
    }
}

private class SecretPascal {
}

class hiddenThing {
}

enum Status {
    Ready,
    hidden
}

union Outcome {
    Ok
    hidden
}

func hiddenFunction(): string {
    return "hidden"
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
namespace App

import Models

func Main() {
    thing := new hiddenThing()
    secret := new SecretPascal()
    item := new Item()
    print item.hiddenMethod()
    print Outcome.hidden
    print hiddenFunction()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenThing' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'SecretPascal' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenMethod' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hidden' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenFunction' is not exported"));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_MissingProject_ReturnsStructuredErrorEnvelope()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-missing-{Guid.NewGuid():N}");

        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", missingDir }));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        var doc = JsonDocument.Parse(stdout);
        Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal(NormalizePath(Path.GetFullPath(missingDir)),
            doc.RootElement.GetProperty("projectRoot").GetString());
        Assert.Contains("Directory not found",
            doc.RootElement.GetProperty("error").GetProperty("message").GetString());
    }

    [Fact]
    public void FixCommand_DryRun_WithPendingFixes_UsesStructuredEnvelopeAndExitCodeOne()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-fix-{Guid.NewGuid():N}");
        var sourceDir = Path.Combine(tempDir, "src");
        Directory.CreateDirectory(sourceDir);

        try
        {
            File.WriteAllText(Path.Combine(sourceDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--file", Path.Combine("src", "Program.nl"), "--dry-run" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var doc = JsonDocument.Parse(stdout);
            Assert.Equal("fix", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(NormalizePath(Path.GetFullPath(tempDir)),
                doc.RootElement.GetProperty("projectRoot").GetString());
            Assert.Equal(1, doc.RootElement.GetProperty("filesModified").GetInt32());
            Assert.Equal(1, doc.RootElement.GetProperty("results").GetArrayLength());
            Assert.Equal(1, doc.RootElement.GetProperty("fixesApplied").GetArrayLength());
            Assert.Equal("src/Program.nl",
                doc.RootElement.GetProperty("fixesApplied")[0].GetProperty("file").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void HoverCommand_AtFunctionDefinition_ReturnsSignature()
    {
        var hiLine = File.ReadLines(Path.Combine(HelloWorldProject, "Program.nl"))
            .Select((text, index) => (Text: text, Line: index + 1))
            .First(line => line.Text.TrimStart().StartsWith("func Hi(", StringComparison.Ordinal))
            .Line;

        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "hover",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", $"{hiLine}:6"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("hover", doc.RootElement.GetProperty("command").GetString());

        var result = doc.RootElement.GetProperty("result");
        Assert.Equal("function", result.GetProperty("kind").GetString());
        Assert.Contains("Hi", result.GetProperty("signature").GetString() ?? "");
        AssertJsonContract("hover", stdout);
    }

    [Fact]
    public void HoverCommand_NoSymbol_ReturnsStructuredError()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "hover",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", "6:1"    // blank line
        }));

        Assert.Equal(1, exitCode);
        using var doc = JsonDocument.Parse(stdout);
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("hover", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("noSymbol", doc.RootElement.GetProperty("error").GetProperty("code").GetString());
    }

    [Fact]
    public void CallGraphCommand_FindsCalleesOfMain()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "call-graph",
            "--project", HelloWorldProject,
            "--function", "Main"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("callGraph", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("Main", doc.RootElement.GetProperty("function").GetString());

        var callees = doc.RootElement.GetProperty("callees").EnumerateArray().ToArray();
        Assert.Contains(callees, c => c.GetProperty("name").GetString() == "Hi");
        AssertJsonContract("callGraph", stdout);
    }

    [Fact]
    public void CallGraphCommand_NoFunction_ReturnsAllEdges()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "call-graph",
            "--project", HelloWorldProject
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("callGraph", doc.RootElement.GetProperty("command").GetString());
        // When no --function is specified, "function" key should be null/absent
        var hasFunction = doc.RootElement.TryGetProperty("function", out var funcProp);
        if (hasFunction)
            Assert.Equal(JsonValueKind.Null, funcProp.ValueKind);
    }

    [Fact]
    public void QueryTextJsonOutputRoutes_UseTextMode()
    {
        var classesAndRecordsProject = Path.Combine(FindExamplesDir(), "06-classes-and-records");
        var hiLine = File.ReadLines(Path.Combine(HelloWorldProject, "Program.nl"))
            .Select((text, index) => (Text: text, Line: index + 1))
            .First(line => line.Text.TrimStart().StartsWith("func Hi(", StringComparison.Ordinal))
            .Line;

        var (symbolsExitCode, symbolsStdout, symbolsStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "symbols",
            "--project", classesAndRecordsProject,
            "--filter", "*ircle",
            "--text"
        }));

        Assert.Equal(0, symbolsExitCode);
        Assert.True(string.IsNullOrWhiteSpace(symbolsStderr));
        Assert.Contains("Class Circle", symbolsStdout);
        Assert.DoesNotContain("\"command\"", symbolsStdout);

        var (hoverExitCode, hoverStdout, hoverStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "hover",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", $"{hiLine}:6",
            "--text"
        }));

        Assert.Equal(0, hoverExitCode);
        Assert.True(string.IsNullOrWhiteSpace(hoverStderr));
        Assert.Contains("Signature:", hoverStdout);
        Assert.Contains("Hi", hoverStdout);
        Assert.DoesNotContain("\"command\"", hoverStdout);

        var (callGraphExitCode, callGraphStdout, callGraphStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "call-graph",
            "--project", HelloWorldProject,
            "--function", "Main",
            "--text"
        }));

        Assert.Equal(0, callGraphExitCode);
        Assert.True(string.IsNullOrWhiteSpace(callGraphStderr));
        Assert.Contains("Call graph for: Main", callGraphStdout);
        Assert.Contains("Hi", callGraphStdout);
        Assert.DoesNotContain("\"command\"", callGraphStdout);
    }

    [Fact]
    public void QueryTextJsonOutputRoutes_RemainingCommandsUseTextMode()
    {
        var examplesDir = FindExamplesDir();
        var classesAndRecordsProject = Path.Combine(examplesDir, "06-classes-and-records");
        var multiFileProject = Path.Combine(examplesDir, "12-multi-file-projects", "MultiFileProject");

        void AssertTextSuccess(int exitCode, string stdout, string stderr, params string[] expectedStdout)
        {
            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            foreach (var expected in expectedStdout)
            {
                Assert.Contains(expected, stdout);
            }
            Assert.DoesNotContain("\"command\"", stdout);
        }

        void AssertTextError(int exitCode, string stdout, string stderr, string expectedStderr)
        {
            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains(expectedStderr, stderr);
            Assert.DoesNotContain("\"command\"", stderr);
        }

        var (implementorsExitCode, implementorsStdout, implementorsStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "implementors",
            "--project", classesAndRecordsProject,
            "--name", "IShape",
            "--text"
        }));
        AssertTextSuccess(implementorsExitCode, implementorsStdout, implementorsStderr, "Implementors of IShape", "Circle");

        var (outlineExitCode, outlineStdout, outlineStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "outline",
            "--project", HelloWorldProject,
            "Program.nl",
            "--text"
        }));
        AssertTextSuccess(outlineExitCode, outlineStdout, outlineStderr, "File: Program.nl", "Function Main");

        var (typeExitCode, typeStdout, typeStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "type",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "11:5",
            "--text"
        }));
        AssertTextSuccess(typeExitCode, typeStdout, typeStderr, "At Service.nl:11:5:", "IssueStore");

        var (definitionSearchExitCode, definitionSearchStdout, definitionSearchStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "definition",
            "--project", classesAndRecordsProject,
            "--name", "Point",
            "--text"
        }));
        AssertTextSuccess(definitionSearchExitCode, definitionSearchStdout, definitionSearchStderr, "Definitions of 'Point':", "record Point");

        var (definitionExitCode, definitionStdout, definitionStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "definition",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "22:10",
            "--text"
        }));
        AssertTextSuccess(definitionExitCode, definitionStdout, definitionStderr, "CreateIssue", "Service.nl");

        var (referencesExitCode, referencesStdout, referencesStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "references",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "10:7",
            "--text"
        }));
        AssertTextSuccess(referencesExitCode, referencesStdout, referencesStderr, "References to 'IssueService'", "Service.nl");

        var (completionsExitCode, completionsStdout, completionsStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "completions",
            "--project", multiFileProject,
            "--file", "Services/PersonService.nl",
            "--pos", "14:15",
            "--text"
        }));
        AssertTextSuccess(completionsExitCode, completionsStdout, completionsStderr, "Completions at Services/PersonService.nl:14:15", "methods");

        var (implementorsErrorExitCode, implementorsErrorStdout, implementorsErrorStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "implementors",
            "--project", classesAndRecordsProject,
            "--file", "RecordsAndInterfaces.nl",
            "--pos", "4:8",
            "--text"
        }));
        AssertTextError(implementorsErrorExitCode, implementorsErrorStdout, implementorsErrorStderr, "No interface found at RecordsAndInterfaces.nl:4:8");

        var (typeErrorExitCode, typeErrorStdout, typeErrorStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "type",
            "--project", IssueTrackerFixture,
            "--file", "Program.nl",
            "--pos", "1:1",
            "--text"
        }));
        AssertTextError(typeErrorExitCode, typeErrorStdout, typeErrorStderr, "No type information found at Program.nl:1:1");

        var (definitionErrorExitCode, definitionErrorStdout, definitionErrorStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "definition",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", "1:1",
            "--text"
        }));
        AssertTextError(definitionErrorExitCode, definitionErrorStdout, definitionErrorStderr, "No definition found at Program.nl:1:1");

        var (referencesErrorExitCode, referencesErrorStdout, referencesErrorStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "references",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", "1:1",
            "--text"
        }));
        AssertTextError(referencesErrorExitCode, referencesErrorStdout, referencesErrorStderr, "No symbol found at Program.nl:1:1");
    }

    [Fact]
    public void ImplementorsCommand_FindsCircleForIShape()
    {
        var classesAndRecordsProject = Path.Combine(FindExamplesDir(), "06-classes-and-records");

        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "implementors",
            "--project", classesAndRecordsProject,
            "--name", "IShape"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("implementors", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("IShape", doc.RootElement.GetProperty("interface").GetString());

        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.Contains(results, r =>
            r.GetProperty("typeName").GetString() == "Circle" &&
            r.GetProperty("kind").GetString() == "class");
        AssertJsonContract("implementors", stdout);
    }

    [Fact]
    public void ImplementorsCommand_MissingName_ReturnsError()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "implementors",
            "--project", HelloWorldProject
        }));

        Assert.Equal(1, exitCode);
        Assert.Contains("Usage:", stderr);
    }

    [Fact]
    public void SymbolsCommand_WildcardFilter_MatchesGlob()
    {
        var classesAndRecordsProject = Path.Combine(FindExamplesDir(), "06-classes-and-records");

        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "symbols",
            "--project", classesAndRecordsProject,
            "--filter", "*ircle"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());

        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.Contains(results, r => r.GetProperty("name").GetString() == "Circle");
        Assert.DoesNotContain(results, r => r.GetProperty("name").GetString() == "Square");
    }

    [Fact]
    public void SymbolsCommand_KindParsingUsesQueryKernel()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "symbols",
            "--project", IssueTrackerFixture,
            "--kind", "class",
            "--no-daemon"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.NotEmpty(results);
        Assert.All(results, symbol => Assert.Equal("class", symbol.GetProperty("kind").GetString()));
    }

    [Fact]
    public void SymbolsCommand_SubstringFilter_MatchesSubstring()
    {
        var classesAndRecordsProject = Path.Combine(FindExamplesDir(), "06-classes-and-records");

        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "symbols",
            "--project", classesAndRecordsProject,
            "--filter", "quare"  // should match Square, not Circle
        }));

        Assert.Equal(0, exitCode);
        using var doc = JsonDocument.Parse(stdout);
        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.Contains(results, r => r.GetProperty("name").GetString() == "Square");
        Assert.DoesNotContain(results, r => r.GetProperty("name").GetString() == "Circle");
    }

    [Fact]
    public void CliCommandRegistry_StaysInSyncWithHelpCompletionsAndDocs()
    {
        var publicTopLevelCommands = CommandRegistry.TopLevelCommands.Select(command => command.Name).ToArray();
        var publicQueryCommands = CommandRegistry.QueryCommands.Select(command => command.Name).ToArray();

        var (_, help, _) = CaptureConsole(() => ExecuteProgram("help"));
        var (_, queryHelp, _) = CaptureConsole(() => QueryCommand.Execute(new[] { "help" }));
        var (_, zshCompletion, _) = CaptureConsole(() => CompletionCommand.Execute(new[] { "zsh" }));
        var docs = File.ReadAllText(Path.Combine(FindRepoRoot(), "website", "docs", "cli-reference.md"));

        foreach (var command in publicTopLevelCommands)
        {
            Assert.Contains(command, help);
            Assert.Contains(command, zshCompletion);
            Assert.Contains($"nlc {command}", docs);
        }

        foreach (var command in publicQueryCommands)
        {
            Assert.Contains(command, queryHelp);
            Assert.Contains(command, zshCompletion);
            Assert.Contains($"nlc query {command}", docs);
        }

        Assert.DoesNotContain("idiom", publicTopLevelCommands);
        Assert.DoesNotContain("nlc idiom", help);
        Assert.DoesNotContain("nlc idiom", zshCompletion);
        Assert.DoesNotContain("nlc idiom", docs);
    }

    [Fact]
    public void CompletionCommandKernels_SummarizesOptions()
    {
        var bash = CompletionCommandKernels.GetOptionSummary(new[] { "BASH" });
        Assert.Equal(CompletionShellKind.Bash, bash.ShellKind);
        Assert.False(bash.ShowHelp);

        var zshHelp = CompletionCommandKernels.GetOptionSummary(new[] { "zsh", "--help" });
        Assert.Equal(CompletionShellKind.Zsh, zshHelp.ShellKind);
        Assert.True(zshHelp.ShowHelp);

        var fish = CompletionCommandKernels.GetOptionSummary(new[] { "fish" });
        Assert.Equal(CompletionShellKind.Fish, fish.ShellKind);
        Assert.False(fish.ShowHelp);

        var unknown = CompletionCommandKernels.GetOptionSummary(new[] { "PowerShell" });
        Assert.Equal(CompletionShellKind.Unknown, unknown.ShellKind);
        Assert.False(unknown.ShowHelp);

        Assert.True(CompletionCommandKernels.GetOptionSummary(Array.Empty<string>()).ShowHelp);
        Assert.True(CompletionCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(CompletionCommandKernels.GetOptionSummary(new[] { "-h" }).ShowHelp);

        var helpText = CompletionCommandKernels.GetHelpText();
        Assert.Contains("N# Shell Completion", helpText);
        Assert.Contains("Usage: nlc completion <bash|zsh|fish>", helpText);
        Assert.Contains("Invalid shell name", helpText);
        Assert.Equal(
            "Unknown shell 'powershell'. Expected bash, zsh, or fish.",
            CompletionCommandKernels.GetUnknownShellMessage("powershell"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => CompletionCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
        Assert.Contains("Usage: nlc completion <bash|zsh|fish>", helpStdout);

        var (errorExitCode, errorStdout, errorStderr) = CaptureConsole(() => CompletionCommand.Execute(new[] { "PowerShell" }));
        Assert.Equal(1, errorExitCode);
        Assert.True(string.IsNullOrWhiteSpace(errorStdout));
        Assert.Contains("Unknown shell 'powershell'. Expected bash, zsh, or fish.", errorStderr);
    }

    private static int ExecuteProgram(params string[] args)
    {
        var programType = typeof(CheckCommand).Assembly.GetType("NSharpLang.Cli.Program");
        Assert.NotNull(programType);

        var method = programType!.GetMethod("Execute", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic);
        Assert.NotNull(method);

        return (int)(method!.Invoke(null, new object[] { args }) ?? -1);
    }

    private static (int ExitCode, string Stdout, string Stderr) CaptureConsole(Func<int> action, string? stdin = null)
    {
        var originalOut = Console.Out;
        var originalError = Console.Error;
        var originalIn = Console.In;
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        using var input = new StringReader(stdin ?? string.Empty);

        Console.SetOut(stdout);
        Console.SetError(stderr);
        Console.SetIn(input);

        try
        {
            var exitCode = action();
            return (exitCode, stdout.ToString(), stderr.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetError(originalError);
            Console.SetIn(originalIn);
        }
    }

    public static IEnumerable<object[]> QueryJsonContractCases()
    {
        var examplesDir = FindExamplesDir();

        yield return new object[]
        {
            "symbols",
            new[] { "symbols", "--project", Path.Combine(examplesDir, "01-hello-world") }
        };

        yield return new object[]
        {
            "outline",
            new[] { "outline", "--project", Path.Combine(examplesDir, "01-hello-world"), "Program.nl" }
        };

        yield return new object[]
        {
            "diagnostics",
            new[] { "diagnostics", "--project", Path.Combine(examplesDir, "01-hello-world") }
        };

        yield return new object[]
        {
            "doc",
            new[] { "doc", "Console.WriteLine" }
        };

        yield return new object[]
        {
            "type",
            new[]
            {
                "type",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "11:5"
            }
        };

        yield return new object[]
        {
            "definitionSearch",
            new[]
            {
                "definition",
                "--project", Path.Combine(examplesDir, "06-classes-and-records"),
                "--name", "Point"
            }
        };

        yield return new object[]
        {
            "definition",
            new[]
            {
                "definition",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "22:10"
            }
        };

        yield return new object[]
        {
            "references",
            new[]
            {
                "references",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "10:7"
            }
        };

        yield return new object[]
        {
            "completions",
            new[]
            {
                "completions",
                "--project", Path.Combine(examplesDir, "12-multi-file-projects", "MultiFileProject"),
                "--file", "Services/PersonService.nl",
                "--pos", "14:15"
            }
        };

        yield return new object[]
        {
            "inspect",
            new[]
            {
                "inspect",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "11:5"
            }
        };

        yield return new object[]
        {
            "inspectSummary",
            new[]
            {
                "inspect",
                "--compact",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "11:5"
            }
        };

        yield return new object[]
        {
            "hover",
            new[]
            {
                "hover",
                "--project", Path.Combine(examplesDir, "01-hello-world"),
                "--file", "Program.nl",
                "--pos", "18:10"
            }
        };

        yield return new object[]
        {
            "callGraph",
            new[]
            {
                "call-graph",
                "--project", Path.Combine(examplesDir, "01-hello-world"),
                "--function", "Main"
            }
        };

        yield return new object[]
        {
            "implementors",
            new[]
            {
                "implementors",
                "--project", Path.Combine(examplesDir, "06-classes-and-records"),
                "--name", "IShape"
            }
        };
    }

    private static string FindExamplesDir()
    {
        var dir = Directory.GetCurrentDirectory();
        for (int i = 0; i < 10; i++)
        {
            var candidate = Path.Combine(dir, "examples");
            if (Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "01-hello-world")))
                return candidate;

            var parent = Directory.GetParent(dir);
            if (parent == null)
                break;
            dir = parent.FullName;
        }

        throw new DirectoryNotFoundException("Could not find examples directory.");
    }

    private static string FindFixturesDir()
    {
        var repoRoot = FindRepoRoot();
        var candidate = Path.Combine(repoRoot, "tests", "fixtures");
        if (Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "issue-tracker")))
            return candidate;

        throw new DirectoryNotFoundException("Could not find tests/fixtures directory.");
    }

    private static string FindRepoRoot()
    {
        var dir = Directory.GetCurrentDirectory();
        for (int i = 0; i < 10; i++)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")) && Directory.Exists(Path.Combine(dir, "docs")))
                return dir;

            var parent = Directory.GetParent(dir);
            if (parent == null)
                break;
            dir = parent.FullName;
        }

        throw new DirectoryNotFoundException("Could not find repository root.");
    }

    private static void AssertJsonContract(string contractName, string json)
    {
        var expected = LoadJsonContractRootKeys();
        var actual = GetRootPropertyNames(json);

        Assert.True(expected.TryGetValue(contractName, out var expectedKeys),
            $"Missing JSON contract snapshot: {contractName}");
        Assert.True(expectedKeys!.SequenceEqual(actual),
            $"{contractName} JSON envelope changed.\nExpected: [{string.Join(", ", expectedKeys)}]\nActual:   [{string.Join(", ", actual)}]");
    }

    private static IReadOnlyDictionary<string, string[]> LoadJsonContractRootKeys()
    {
        var path = FindJsonContractFixturePath();
        using var document = JsonDocument.Parse(File.ReadAllText(path));

        return document.RootElement.EnumerateObject()
            .ToDictionary(
                property => property.Name,
                property => property.Value.EnumerateArray().Select(value => value.GetString() ?? string.Empty).ToArray(),
                StringComparer.Ordinal);
    }

    private static string[] GetRootPropertyNames(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateObject().Select(property => property.Name).ToArray();
    }

    private static string FindJsonContractFixturePath()
    {
        var examplesDir = FindExamplesDir();
        var repoRoot = Directory.GetParent(examplesDir)?.FullName;
        if (repoRoot != null)
        {
            var candidate = Path.Combine(repoRoot, "tests", "fixtures", "json-contract-root-keys.golden.json");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new DirectoryNotFoundException("Could not find json-contract-root-keys.golden.json.");
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}
