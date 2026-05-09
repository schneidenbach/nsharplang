using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using Xunit;

namespace NSharpLang.Tests;

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
    "summary": true
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
            Assert.Equal(3, doc.RootElement.GetProperty("requestCount").GetInt32());
            Assert.Equal(2, doc.RootElement.GetProperty("successCount").GetInt32());
            Assert.Equal(1, doc.RootElement.GetProperty("failureCount").GetInt32());

            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Equal("inspect", results[0].GetProperty("request").GetProperty("command").GetString());
            Assert.True(results[0].GetProperty("ok").GetBoolean());
            Assert.True(results[0].GetProperty("response").TryGetProperty("summary", out _));

            Assert.Equal("doc", results[1].GetProperty("request").GetProperty("command").GetString());
            Assert.True(results[1].GetProperty("ok").GetBoolean());
            Assert.Equal("doc", results[1].GetProperty("response").GetProperty("command").GetString());

            Assert.Equal("type", results[2].GetProperty("request").GetProperty("command").GetString());
            Assert.False(results[2].GetProperty("ok").GetBoolean());
            Assert.Equal("noSymbol", results[2].GetProperty("response").GetProperty("error").GetProperty("code").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
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
    item := new Item()
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
        // hello-world Program.nl line 3: func Hi(): int {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "hover",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", "3:6"
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
            "--pos", "2:1"    // blank line
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
    public void IdiomCommand_Help_IsSideEffectFree()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => IdiomCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc idiom", stdout);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
    }

    [Fact]
    public void IdiomCommand_EmitsMachineReadableMigrationReport()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-idiom-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            Directory.CreateDirectory(Path.Combine(tempDir, "Models"));
            Directory.CreateDirectory(Path.Combine(tempDir, "Services"));
            File.WriteAllText(Path.Combine(tempDir, "Models", "Customer.nl"), """
class CustomerDto {
    public id: string
    private _legacyId: string
    Name: string
}

record Order(id: string, total: decimal)
""");
            File.WriteAllText(Path.Combine(tempDir, "Services", "Store.nl"), """
package Models

using System;
namespace Legacy.Api;

func Load(input: string?): Result<string> {
    value := input!
    built := new User {
        Name = "A"
    }
    legacy := value;
    // TODO(migration): manual review required
    return match value {
        "" => Result.Failure { error: "empty" },
        _ => Result.Success { value: value }
    }
}

async func Ping(): string {
    return "pong"
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Legacy.cs"), """
public class LegacyDto
{
    public string Name { get; set; } = null!;
    public IActionResult Get() => Ok(new { Name = "legacy" });
    public bool TryRead(Dictionary<string, string> map, string key, out var value)
        => map.TryGetValue(key, out value);
    public string FromQuery(IEnumerable<User> users) =>
        (from user in users where user.Id == id select user.Name).First();
    public User Build() => new User { Name = "A" };
    public string MustRead(Result<string> result) => result.Value;
    public string Missing() => default!;
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                IdiomCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            AssertJsonContract("idiom", stdout);

            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal("idiom", root.GetProperty("command").GetString());
            Assert.True(root.GetProperty("ok").GetBoolean());
            Assert.Equal(3, root.GetProperty("scannedFiles").GetInt32());
            Assert.InRange(root.GetProperty("score").GetInt32(), 1, 99);

            Assert.True(root.TryGetProperty("grade", out _));
            Assert.True(root.TryGetProperty("thresholds", out _));

            var csharp = root.GetProperty("signals").GetProperty("csharpIsms");
            Assert.Equal(10, csharp.GetProperty("modifiers").GetInt32());
            Assert.Equal(1, csharp.GetProperty("propertySyntax").GetInt32());
            Assert.Equal(3, csharp.GetProperty("nullForgiving").GetInt32());
            Assert.Equal(2, csharp.GetProperty("outVar").GetInt32());
            Assert.Equal(1, csharp.GetProperty("tryGetValue").GetInt32());
            Assert.Equal(1, csharp.GetProperty("semicolons").GetInt32());
            Assert.Equal(1, csharp.GetProperty("underscoreFields").GetInt32());
            Assert.Equal(1, csharp.GetProperty("actionResults").GetInt32());
            Assert.Equal(1, csharp.GetProperty("anonymousApiDtos").GetInt32());
            Assert.Equal(1, csharp.GetProperty("querySyntax").GetInt32());
            Assert.Equal(2, csharp.GetProperty("equalsInitializers").GetInt32());
            Assert.Equal(1, csharp.GetProperty("unsafeValueAccess").GetInt32());
            Assert.Equal(1, csharp.GetProperty("usingDirectives").GetInt32());
            Assert.Equal(1, csharp.GetProperty("namespaceDeclarations").GetInt32());
            Assert.Equal(1, csharp.GetProperty("missingPackageDeclarations").GetInt32());
            Assert.Equal(1, csharp.GetProperty("wrongPackageDeclarations").GetInt32());

            var adoption = root.GetProperty("signals").GetProperty("nsharpAdoption");
            Assert.Equal(1, adoption.GetProperty("records").GetInt32());
            Assert.Equal(1, adoption.GetProperty("matchExpressions").GetInt32());
            Assert.Equal(4, adoption.GetProperty("resultMentions").GetInt32());
            Assert.Equal(2, adoption.GetProperty("packageLayoutDirectories").GetInt32());

            Assert.Equal(2, root.GetProperty("signals").GetProperty("dtoClasses").GetProperty("count").GetInt32());
            Assert.Equal(1, root.GetProperty("signals").GetProperty("casingVisibilityIssues").GetProperty("count").GetInt32());
            Assert.Equal(1, root.GetProperty("signals").GetProperty("manualReviewIslands").GetProperty("count").GetInt32());
            Assert.True(root.GetProperty("recommendations").GetArrayLength() > 0);

            var modifierExample = csharp.GetProperty("examples").GetProperty("modifiers")[0];
            Assert.True(modifierExample.TryGetProperty("file", out _));
            Assert.True(modifierExample.TryGetProperty("line", out _));
            Assert.True(modifierExample.TryGetProperty("column", out _));
            Assert.True(modifierExample.TryGetProperty("text", out _));
            Assert.False(modifierExample.TryGetProperty("File", out _));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void IdiomCommand_MissingProject_ReturnsMachineReadableErrorEnvelope()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-missing-idiom-{Guid.NewGuid():N}");

        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            IdiomCommand.Execute(new[] { "--project", missingDir }));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        var root = doc.RootElement;
        Assert.Equal("idiom", root.GetProperty("command").GetString());
        Assert.False(root.GetProperty("ok").GetBoolean());
        Assert.Equal(NormalizePath(Path.GetFullPath(missingDir)), root.GetProperty("projectRoot").GetString());
        Assert.Equal("directoryNotFound", root.GetProperty("error").GetProperty("code").GetString());
        Assert.Contains("Directory not found", root.GetProperty("error").GetProperty("message").GetString());
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
                "--summary",
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
                "--pos", "3:6"
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

        var fallback = "/Users/spencer/repos/nsharplang/examples";
        if (Directory.Exists(fallback))
            return fallback;

        throw new DirectoryNotFoundException("Could not find examples directory.");
    }

    private static string FindFixturesDir()
    {
        var dir = Directory.GetCurrentDirectory();
        for (int i = 0; i < 10; i++)
        {
            var candidate = Path.Combine(dir, "tests", "fixtures");
            if (Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "issue-tracker")))
                return candidate;

            var parent = Directory.GetParent(dir);
            if (parent == null)
                break;
            dir = parent.FullName;
        }

        var fallback = "/Users/spencer/repos/nsharplang/tests/fixtures";
        if (Directory.Exists(fallback))
            return fallback;

        throw new DirectoryNotFoundException("Could not find tests/fixtures directory.");
    }

    private static void AssertJsonContract(string contractName, string json)
    {
        var expected = LoadJsonContractRootKeys();
        var actual = GetRootPropertyNames(json);

        Assert.True(expected.TryGetValue(contractName, out var expectedKeys),
            $"Missing JSON contract snapshot: {contractName}");
        Assert.True(expectedKeys!.All(actual.Contains),
            $"{contractName} JSON envelope lost expected keys.\nExpected subset: [{string.Join(", ", expectedKeys)}]\nActual:        [{string.Join(", ", actual)}]");
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

        var fallback = "/Users/spencer/repos/nsharplang/tests/fixtures/json-contract-root-keys.golden.json";
        if (File.Exists(fallback))
        {
            return fallback;
        }

        throw new DirectoryNotFoundException("Could not find json-contract-root-keys.golden.json.");
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}
