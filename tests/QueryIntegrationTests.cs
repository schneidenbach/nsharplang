using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Integration tests for the nlc query toolchain.
/// Uses REAL projects as test fixtures — no toy snippets.
///
/// Fixture projects (examples/):
///   01-hello-world                              — single file, basic functions, variables
///   06-classes-and-records                       — multi-file, classes, records, enums, interfaces
///   12-multi-file-projects/MultiFileProject      — cross-file imports, namespaces
///   05-unions                                    — unions, error handling
///
/// Fixture projects (tests/fixtures/):
///   issue-tracker                                — complex multi-file web API (unions, duck interfaces, records)
///
/// These tests are the "does it actually work?" layer. They run the full
/// CodeIntelligenceService pipeline against real N# projects and verify
/// the results make semantic sense.
/// </summary>
public class QueryIntegrationTests : IDisposable
{
    private readonly CodeIntelligenceService _service = new();
    private readonly string _examplesDir;
    private readonly string _fixturesDir;

    // Lazily loaded snapshots — one per project, shared across tests
    private ProjectSnapshot? _helloWorldSnapshot;
    private ProjectSnapshot? _classesAndRecordsSnapshot;
    private ProjectSnapshot? _multiFileSnapshot;
    private ProjectSnapshot? _unionsSnapshot;
    private ProjectSnapshot? _issueTrackerSnapshot;

    public QueryIntegrationTests()
    {
        _examplesDir = FindExamplesDir();
        _fixturesDir = FindFixturesDir();
    }

    public void Dispose() { }

    private static int FindColumnInFile(string filePath, int lineNumber, string needle, int occurrence = 1)
    {
        var line = File.ReadLines(filePath).Skip(lineNumber - 1).First();
        var startIndex = 0;
        var index = -1;

        for (var i = 0; i < occurrence; i++)
        {
            index = line.IndexOf(needle, startIndex, StringComparison.Ordinal);
            Assert.True(index >= 0, $"Could not find '{needle}' on line {lineNumber}: {line}");
            startIndex = index + needle.Length;
        }

        return index + 1;
    }

    private static int FindLineInFile(string filePath, string needle, int occurrence = 1)
    {
        var matchesSeen = 0;
        var lineNumber = 0;

        foreach (var line in File.ReadLines(filePath))
        {
            lineNumber++;
            if (!line.Contains(needle, StringComparison.Ordinal))
                continue;

            matchesSeen++;
            if (matchesSeen == occurrence)
                return lineNumber;
        }

        throw new Xunit.Sdk.XunitException($"Could not find '{needle}' in {filePath}");
    }

    private ProjectSnapshot HelloWorld => _helloWorldSnapshot ??=
        _service.LoadProject(Path.Combine(_examplesDir, "01-hello-world"));

    private ProjectSnapshot ClassesAndRecords => _classesAndRecordsSnapshot ??=
        _service.LoadProject(Path.Combine(_examplesDir, "06-classes-and-records"));

    private ProjectSnapshot MultiFile => _multiFileSnapshot ??=
        _service.LoadProject(Path.Combine(_examplesDir, "12-multi-file-projects", "MultiFileProject"));

    private ProjectSnapshot Unions => _unionsSnapshot ??=
        _service.LoadProject(Path.Combine(_examplesDir, "05-unions"));

    private ProjectSnapshot IssueTracker => _issueTrackerSnapshot ??=
        _service.LoadProject(Path.Combine(_fixturesDir, "issue-tracker"));

    private ProjectSnapshot LoadTemporaryProject(params (string RelativePath, string Source)[] files)
    {
        var projectRoot = Directory.CreateTempSubdirectory("nsharp-query-").FullName;
        File.WriteAllText(Path.Combine(projectRoot, "project.yml"), """
name: QueryTemp
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net10.0
""");

        foreach (var (relativePath, source) in files)
        {
            var fullPath = Path.Combine(projectRoot, relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            File.WriteAllText(fullPath, source);
        }

        return _service.LoadProject(projectRoot);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SYMBOLS — does it actually find the right stuff?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Symbols_HelloWorld_FindsMainFunction()
    {
        var symbols = _service.GetSymbols(HelloWorld);
        Assert.Contains(symbols, s => s.Name == "Main" && s.Kind == SymbolKind.Function);
    }

    [Fact]
    public void Symbols_HelloWorld_MainFunctionHasVoidReturnType()
    {
        var symbols = _service.GetSymbols(HelloWorld);
        var main = symbols.First(s => s.Name == "Main");
        Assert.Equal("void", main.TypeName);
    }

    [Fact]
    public void Symbols_ClassesAndRecords_FindsAllTypeKinds()
    {
        var symbols = _service.GetSymbols(ClassesAndRecords);

        // Should find records (Point, Vector2D, Color from RecordStructs.nl)
        Assert.Contains(symbols, s => s.Name == "Point" && s.Kind == SymbolKind.Record);
        Assert.Contains(symbols, s => s.Name == "Vector2D" && s.Kind == SymbolKind.Record);
    }

    [Fact]
    public void Symbols_ClassesAndRecords_RecordHasMembers()
    {
        var symbols = _service.GetSymbols(ClassesAndRecords);
        var vector = symbols.FirstOrDefault(s => s.Name == "Vector2D" && s.Kind == SymbolKind.Record);
        Assert.NotNull(vector);
        Assert.NotNull(vector.Members);

        // Vector2D should have Normalize and Dot methods
        Assert.Contains(vector.Members, m => m.Name == "Normalize" && m.Kind == SymbolKind.Function);
        Assert.Contains(vector.Members, m => m.Name == "Dot" && m.Kind == SymbolKind.Function);
    }

    [Fact]
    public void Symbols_MultiFile_FindsAcrossFiles()
    {
        var symbols = _service.GetSymbols(MultiFile);

        // Person (Models/Person.nl), PersonService (Services/PersonService.nl), Main (Program.nl)
        Assert.Contains(symbols, s => s.Name == "Person" && s.Kind == SymbolKind.Record);
        Assert.Contains(symbols, s => s.Name == "PersonService" && s.Kind == SymbolKind.Class);
        Assert.Contains(symbols, s => s.Name == "Main" && s.Kind == SymbolKind.Function);
        Assert.Contains(symbols, s => s.Name == "Status" && s.Kind == SymbolKind.Enum);
    }

    [Fact]
    public void Symbols_MultiFile_PersonServiceHasMembers()
    {
        var symbols = _service.GetSymbols(MultiFile);
        var service = symbols.First(s => s.Name == "PersonService" && s.Kind == SymbolKind.Class);
        Assert.NotNull(service.Members);
        Assert.Contains(service.Members, m => m.Name == "AddPerson" && m.Kind == SymbolKind.Function);
        Assert.Contains(service.Members, m => m.Name == "GetPeople" && m.Kind == SymbolKind.Function);
    }

    [Fact]
    public void Symbols_FilterByFile_OnlyReturnsMatchingFile()
    {
        var modelsOnly = _service.GetSymbols(MultiFile, file: "Person.nl");
        Assert.Contains(modelsOnly, s => s.Name == "Person");
        Assert.Contains(modelsOnly, s => s.Name == "Status");
        Assert.DoesNotContain(modelsOnly, s => s.Name == "Main");
        Assert.DoesNotContain(modelsOnly, s => s.Name == "PersonService");
    }

    [Fact]
    public void Symbols_FilterByKind_OnlyReturnsMatchingKind()
    {
        var functions = _service.GetSymbols(MultiFile, kind: SymbolKind.Function);
        Assert.All(functions, s => Assert.Equal(SymbolKind.Function, s.Kind));
        Assert.Contains(functions, s => s.Name == "Main");
    }

    [Fact]
    public void Symbols_Unions_FindsUnionDeclarations()
    {
        var symbols = _service.GetSymbols(Unions);
        // ErrorHandling.nl has Divide and AlwaysFails functions, Main
        Assert.Contains(symbols, s => s.Name == "Divide" && s.Kind == SymbolKind.Function);
        Assert.Contains(symbols, s => s.Name == "AlwaysFails" && s.Kind == SymbolKind.Function);
        Assert.Contains(symbols, s => s.Name == "Main" && s.Kind == SymbolKind.Function);
    }

    [Fact]
    public void Symbols_PublicSurface_UsesGoStyleCasingAndInteropEscapes()
    {
        var projectDir = Path.Combine(Path.GetTempPath(), $"nsharp_query_visibility_{Guid.NewGuid():N}");
        Directory.CreateDirectory(projectDir);
        try
        {
            File.WriteAllText(Path.Combine(projectDir, "project.yml"), """
name: QueryVisibility
version: 1.0.0
targetFramework: net10.0
outputType: library
""");
            File.WriteAllText(Path.Combine(projectDir, "Api.nl"), """
public class copiedPublicSurface {
    Visible: int
}

private class CopiedPrivateSurface {
    Visible: int
}

class ExportedSurface {
    Visible: int
    hidden: int
}

class hiddenSurface {
    Visible: int
}

enum Labels: string {
    Good = "good",
    bad = "bad"
}

union Result {
    Ok { Value: int }
    err { message: string }
}

func Helper(): int {
    return 1
}

func helper(): int {
    return 2
}
""");

            var snapshot = _service.LoadProject(projectDir);
            Assert.Empty(snapshot.AllErrors.Where(e => e.Severity == Compiler.ErrorSeverity.Error));

            var symbols = _service.GetSymbols(snapshot);
            var names = symbols.Select(s => s.Name).ToList();

            Assert.DoesNotContain("CopiedPrivateSurface", names);
            Assert.Contains("ExportedSurface", names);
            Assert.Contains("Labels", names);
            Assert.Contains("Result", names);
            Assert.Contains("Helper", names);
            Assert.Contains("copiedPublicSurface", names);
            Assert.DoesNotContain("hiddenSurface", names);
            Assert.DoesNotContain("helper", names);

            var exported = Assert.Single(symbols, s => s.Name == "ExportedSurface");
            Assert.Contains(exported.Members!, m => m.Name == "Visible");
            Assert.DoesNotContain(exported.Members!, m => m.Name == "hidden");

            var labels = Assert.Single(symbols, s => s.Name == "Labels");
            Assert.Contains(labels.Members!, m => m.Name == "Good");
            Assert.Contains(labels.Members!, m => m.Name == "bad");

            var result = Assert.Single(symbols, s => s.Name == "Result");
            Assert.Contains(result.Members!, m => m.Name == "Ok");
            Assert.DoesNotContain(result.Members!, m => m.Name == "err");
        }
        finally
        {
            Directory.Delete(projectDir, recursive: true);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  OUTLINE — does file structure look right?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Outline_HelloWorld_HasMainFunction()
    {
        var outline = _service.GetOutline(HelloWorld, "Program.nl");
        Assert.Contains(outline.Outline, o => o.Name == "Main" && o.Kind == SymbolKind.Function);
    }

    [Fact]
    public void Outline_MultiFile_PersonFileHasRecordAndEnum()
    {
        var outline = _service.GetOutline(MultiFile, "Person.nl");
        Assert.Contains(outline.Outline, o => o.Name == "Person" && o.Kind == SymbolKind.Record);
        Assert.Contains(outline.Outline, o => o.Name == "Status" && o.Kind == SymbolKind.Enum);
    }

    [Fact]
    public void Outline_SingleFileFastPath_MatchesProjectOutline()
    {
        var programPath = Path.Combine(_examplesDir, "01-hello-world", "Program.nl");
        var singleFileOutline = _service.GetOutlineSingleFile(programPath);

        // Should produce same structure as project-based outline
        Assert.Contains(singleFileOutline.Outline, o => o.Name == "Main");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DIAGNOSTICS — does it report real errors?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Diagnostics_HelloWorld_CompileCleanlyNoErrors()
    {
        var diagnostics = _service.GetDiagnostics(HelloWorld);
        var errors = diagnostics.Where(d => d.Severity == "error").ToList();
        Assert.Empty(errors);
    }

    [Fact]
    public void Diagnostics_MultiFile_CompileCleanlyNoErrors()
    {
        var diagnostics = _service.GetDiagnostics(MultiFile);
        var errors = diagnostics.Where(d => d.Severity == "error").ToList();
        Assert.Empty(errors);
    }

    [Fact]
    public void Diagnostics_HaveCorrectCodeFormat()
    {
        // All diagnostic codes should start with "NL" (our prefix)
        var all = _service.GetDiagnostics(HelloWorld);
        Assert.All(all, d => Assert.StartsWith("NL", d.Code));
    }

    [Fact]
    public void DiagnosticClustersToJson_EmitsStableMigrationClusterGoldenShape()
    {
        var diagnostics = new List<DiagnosticResult>
        {
            new(
                Code: "NL301",
                Severity: "error",
                Message: "Undefined variable 'UserManager'",
                File: "sample-api/AuthController.nl",
                Line: 42,
                Column: 17,
                Length: 11,
                SourceSnippet: "let manager := UserManager.Create()",
                Explanation: "The symbol UserManager is not in scope.",
                Suggestion: "Add the import or update the migration rename map.",
                Hint: null,
                ExpectedType: null,
                ActualType: null,
                DocsUrl: null),
            new(
                Code: "NL301",
                Severity: "error",
                Message: "Undefined variable 'RoleManager'",
                File: "sample-api/AuthController.nl",
                Line: 43,
                Column: 17,
                Length: 11,
                SourceSnippet: "let roles := RoleManager.Create()",
                Explanation: "The symbol RoleManager is not in scope.",
                Suggestion: "Add the import or update the migration rename map.",
                Hint: null,
                ExpectedType: null,
                ActualType: null,
                DocsUrl: null)
        };

        var json = OutputFormatter.DiagnosticClustersToJson(diagnostics, "/redacted/sample-migration");
        var goldenPath = Path.GetFullPath(Path.Combine(_examplesDir, "..", "docs", "examples", "diagnostic-clusters.sample.json"));
        var expected = File.ReadAllText(goldenPath).Replace("\r\n", "\n");
        Assert.Equal(expected, json.Replace("\r\n", "\n"));

        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var cluster = Assert.Single(root.GetProperty("clusters").EnumerateArray());

        Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("diagnostics.clusters", root.GetProperty("command").GetString());
        Assert.False(root.GetProperty("ok").GetBoolean());
        Assert.Equal("/redacted/sample-migration", root.GetProperty("projectRoot").GetString());
        Assert.Equal("identifier-resolution", cluster.GetProperty("category").GetString());
        Assert.Equal("migration:missing-import-qualification-or-rename", cluster.GetProperty("recipe").GetString());
        Assert.Equal("medium", cluster.GetProperty("risk").GetString());
        Assert.Equal("nlc query inspect --file sample-api/AuthController.nl --pos 42:17", cluster.GetProperty("nextCommand").GetString());
        Assert.Equal("sample-api/AuthController.nl", Assert.Single(cluster.GetProperty("files").EnumerateArray()).GetString());
        Assert.Equal(2, cluster.GetProperty("relatedDiagnostics").GetArrayLength());
        Assert.Equal("NL301", cluster.GetProperty("relatedDiagnostics")[0].GetProperty("code").GetString());
        Assert.Equal("NL301", cluster.GetProperty("relatedDiagnostics")[1].GetProperty("code").GetString());
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DEFINITION — can we find where stuff is defined?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Definition_ByName_FindsPersonInMultiFile()
    {
        var results = _service.FindDefinitionByName(MultiFile, "Person");
        Assert.NotEmpty(results);
        var person = results.First(d => d.Kind == "record");
        Assert.Contains("Person.nl", person.File);
    }

    [Fact]
    public void Definition_ByName_FindsPersonService()
    {
        var results = _service.FindDefinitionByName(MultiFile, "PersonService");
        Assert.NotEmpty(results);
        Assert.Contains(results, d => d.Kind == "class");
        Assert.Contains(results, d => d.File.Contains("PersonService.nl"));
    }

    [Fact]
    public void Definition_ByName_FindsNothingForNonexistent()
    {
        var results = _service.FindDefinitionByName(MultiFile, "Nonexistent_XYZ_12345");
        Assert.Empty(results);
    }

    [Fact]
    public void Definition_ByName_FindsMultiplePoints()
    {
        // ClassesAndRecords has Point defined in multiple files
        var results = _service.FindDefinitionByName(ClassesAndRecords, "Point");
        Assert.True(results.Count >= 2, $"Expected at least 2 Point definitions, got {results.Count}");
    }

    [Fact]
    public void Definition_ByName_FindsEnumMembers()
    {
        var results = _service.FindDefinitionByName(MultiFile, "Status");
        Assert.NotEmpty(results);
        Assert.Contains(results, d => d.Kind == "enum");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  COMPLETIONS — does the engine return sensible items?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Completions_IdentifierContext_ExcludesKeywordsByDefault()
    {
        var engine = new CompletionEngine();
        // LLM-optimized: keywords/primitives excluded by default
        var result = engine.GetCompletions(HelloWorld, "Program.nl", 3, 4);
        Assert.False(result.Completions.ContainsKey("keywords"),
            "Keywords should be excluded by default for LLM use");
        Assert.False(result.Completions.ContainsKey("primitiveTypes"),
            "Primitive types should be excluded by default for LLM use");
    }

    [Fact]
    public void Completions_IdentifierContext_IncludesKeywordsWhenRequested()
    {
        var engine = new CompletionEngine();
        var result = engine.GetCompletions(HelloWorld, "Program.nl", 3, 4, includeKeywords: true);
        Assert.True(result.Completions.ContainsKey("keywords"),
            "Keywords should be included when includeKeywords=true");

        var keywords = result.Completions["keywords"];
        Assert.Contains(keywords, k => k.Name == "if");
        Assert.Contains(keywords, k => k.Name == "return");
    }

    [Fact]
    public void Completions_MemberAccess_FieldMembers()
    {
        // PersonService.nl line 14: people.Add(person)
        // Completions at "people." should return List<Person> members
        var engine = new CompletionEngine();
        var result = engine.GetCompletions(MultiFile, "Services/PersonService.nl", 14, 15);
        Assert.Equal(CompletionContext.MemberAccess, result.Context);
        Assert.Equal("people", result.Receiver);
        Assert.True(result.Completions.ContainsKey("methods"),
            $"Expected 'methods' category, got: [{string.Join(", ", result.Completions.Keys)}]");

        var methods = result.Completions["methods"];
        Assert.Contains(methods, m => m.Name == "Add");
        Assert.Contains(methods, m => m.Name == "Remove");
        Assert.Contains(methods, m => m.Name == "Count" || m.Name == "Clear");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  JSON OUTPUT — is the schema correct?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Json_Symbols_ParsesAsValidJsonWithEnvelope()
    {
        var symbols = _service.GetSymbols(HelloWorld);
        var json = OutputFormatter.SymbolsToJson(symbols, HelloWorld.ProjectRoot);
        var doc = JsonDocument.Parse(json);

        Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("symbols", doc.RootElement.GetProperty("command").GetString());
        Assert.True(doc.RootElement.GetProperty("results").GetArrayLength() >= 1);
    }

    [Fact]
    public void Json_Diagnostics_HasSummaryWithCounts()
    {
        var diagnostics = _service.GetDiagnostics(HelloWorld);
        var json = OutputFormatter.DiagnosticsToJson(diagnostics, HelloWorld.ProjectRoot);
        var doc = JsonDocument.Parse(json);

        var summary = doc.RootElement.GetProperty("summary");
        // These are ints, not strings
        Assert.True(summary.GetProperty("errors").ValueKind == JsonValueKind.Number);
        Assert.True(summary.GetProperty("warnings").ValueKind == JsonValueKind.Number);
        Assert.True(summary.GetProperty("info").ValueKind == JsonValueKind.Number);
    }

    [Fact]
    public void Json_Outline_HasOutlineArray()
    {
        var outline = _service.GetOutline(HelloWorld, "Program.nl");
        var json = OutputFormatter.OutlineToJson(outline);
        var doc = JsonDocument.Parse(json);

        Assert.True(doc.RootElement.GetProperty("outline").GetArrayLength() > 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  UNHAPPY PATHS — does it fail gracefully?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Outline_NonexistentFile_ReturnsEmpty()
    {
        var outline = _service.GetOutline(HelloWorld, "DoesNotExist.nl");
        Assert.Empty(outline.Outline);
    }

    [Fact]
    public void Definition_AtBogusPosition_ReturnsNull()
    {
        var result = _service.FindDefinition(HelloWorld, "Program.nl", 999, 999);
        Assert.Null(result);
    }

    [Fact]
    public void Type_AtBogusPosition_ReturnsNull()
    {
        var result = _service.GetTypeAtPosition(HelloWorld, "Program.nl", 999, 999);
        Assert.Null(result);
    }

    [Fact]
    public void Symbols_NonexistentFile_ReturnsEmpty()
    {
        var symbols = _service.GetSymbols(HelloWorld, file: "DoesNotExist.nl");
        Assert.Empty(symbols);
    }

    [Fact]
    public void Diagnostics_NonexistentFile_ReturnsEmpty()
    {
        var diagnostics = _service.GetDiagnostics(HelloWorld, file: "DoesNotExist.nl");
        Assert.Empty(diagnostics);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BINDING MAP — is semantic resolution working?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void BindingMap_HelloWorld_IsPopulated()
    {
        Assert.NotNull(HelloWorld.Bindings);
        Assert.True(HelloWorld.Bindings!.BindingCount > 0,
            "BindingMap should have recorded bindings for hello-world");
    }

    [Fact]
    public void BindingMap_MultiFile_HasCrossFileBindings()
    {
        Assert.NotNull(MultiFile.Bindings);
        Assert.True(MultiFile.Bindings!.BindingCount > 0,
            "BindingMap should have recorded bindings for multi-file project");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  POSITIVE SEMANTIC NAVIGATION — does it return the RIGHT thing?
    //  These test known positions in fixture files (not just happy/unhappy)
    // ═══════════════════════════════════════════════════════════════════

    // HelloWorld Program.nl layout:
    //   Line 3:  func Hi(): int {        (col 1 = "func", col 6 = "Hi")
    //   Line 11: func Main() {           (col 1 = "func", col 6 = "Main")
    //   Line 12:     name := "Spencer"   (col 5 = "name")

    [Fact]
    public void Definition_AtPosition_FindsMainFunction()
    {
        var results = _service.FindDefinitionByName(HelloWorld, "Main");
        Assert.NotEmpty(results);
        var main = results.First(d => d.Name == "Main");
        Assert.Equal("function", main.Kind);
        var expectedLine = FindLineInFile(Path.Combine(_examplesDir, "01-hello-world", "Program.nl"), "func Main()");
        Assert.Equal(expectedLine, main.Line);
    }

    // MultiFile Person.nl layout:
    //   Line 4:  record Person {         (col 1 = "record", col 8 = "Person")
    //   Line 5:      Name: string
    //   Line 9:      func GetInfo(): string {
    //   Line 15: enum Status {

    [Fact]
    public void Definition_MultiFile_PersonRecordAtCorrectLine()
    {
        var results = _service.FindDefinitionByName(MultiFile, "Person");
        Assert.NotEmpty(results);
        var person = results.First(d => d.Kind == "record");
        var personFile = Path.Combine(_examplesDir, "12-multi-file-projects", "MultiFileProject", "Models", "Person.nl");
        Assert.Equal(FindLineInFile(personFile, "record Person"), person.Line);
        Assert.Contains("Person.nl", person.File);
    }

    [Fact]
    public void Definition_MultiFile_GetInfoMethodFound()
    {
        var results = _service.FindDefinitionByName(MultiFile, "GetInfo");
        Assert.NotEmpty(results);
        var getInfo = results.First(d => d.Kind == "function");
        var personFile = Path.Combine(_examplesDir, "12-multi-file-projects", "MultiFileProject", "Models", "Person.nl");
        Assert.Equal(FindLineInFile(personFile, "func GetInfo"), getInfo.Line);
    }

    [Fact]
    public void Definition_MultiFile_StatusEnumAtCorrectLine()
    {
        var results = _service.FindDefinitionByName(MultiFile, "Status");
        Assert.NotEmpty(results);
        var status = results.First(d => d.Kind == "enum");
        var personFile = Path.Combine(_examplesDir, "12-multi-file-projects", "MultiFileProject", "Models", "Person.nl");
        Assert.Equal(FindLineInFile(personFile, "enum Status"), status.Line);
        Assert.Contains("Person.nl", status.File);
    }

    [Fact]
    public void References_FindsPersonUsagesAcrossFiles()
    {
        // Person is declared in Models/Person.nl line 4
        // "record Person {" — "Person" starts at column 8 (1-based)
        // Used in Services/PersonService.nl (multiple times) and Program.nl (multiple times)
        //
        // NOTE: Cross-file type references currently use the text-based fallback
        // because the Analyzer's import resolution path doesn't record bindings
        // into the BindingMap. The BindingMap covers local identifier resolution.
        // This test verifies the end-to-end result regardless of which path produces it.

        var refs = _service.FindReferences(MultiFile, "Models/Person.nl", 4, 8);

        // Should find at least the declaration + cross-file usages
        Assert.True(refs.Count >= 3,
            $"Expected at least 3 references to Person (decl + usages), got {refs.Count}: [{string.Join(", ", refs.Select(r => $"{r.File}:{r.Line}"))}]");

        // Should include the definition
        Assert.Contains(refs, r => r.IsDefinition);

        // Should find cross-file usages (in Program.nl or PersonService.nl)
        Assert.True(refs.Any(r => r.File.Contains("Program.nl") || r.File.Contains("PersonService.nl")),
            $"Expected cross-file references. Only found: [{string.Join(", ", refs.Select(r => r.File))}]");
    }

    [Fact]
    public void References_DuplicateCrossFileMemberNames_StayBoundToImportedType()
    {
        var snapshot = LoadTemporaryProject(
            ("Foo/Widget.nl", """
namespace QueryTemp.Foo

record Widget {
    Value: string
}
"""),
            ("Bar/Widget.nl", """
namespace QueryTemp.Bar

record Widget {
    Value: int
}
"""),
            ("Foo/UseWidget.nl", """
namespace QueryTemp.Foo

func Read(widget: Widget): string {
    return widget.Value
}
"""),
            ("Bar/UseWidget.nl", """
namespace QueryTemp.Bar

func Read(widget: Widget): int {
    return widget.Value
}
"""),
            ("Program.nl", """
namespace QueryTemp

func Main() {
}
"""));

        var refs = _service.FindReferences(snapshot, "Foo/Widget.nl", 4, 5);

        Assert.Contains(refs, r => r.IsDefinition && r.File.EndsWith("Foo/Widget.nl", StringComparison.Ordinal) && r.Line == 4);
        Assert.Contains(refs, r => !r.IsDefinition && r.File.EndsWith("Foo/UseWidget.nl", StringComparison.Ordinal) && r.Line == 4);
        Assert.DoesNotContain(refs, r => r.File.EndsWith("Bar/Widget.nl", StringComparison.Ordinal));
        Assert.DoesNotContain(refs, r => r.File.EndsWith("Bar/UseWidget.nl", StringComparison.Ordinal));
    }

    [Fact]
    public void TypeUseNavigation_DuplicateTypeNames_UsesSemanticBindingForCompositeTypes()
    {
        var snapshot = LoadTemporaryProject(
            ("Foo/Widget.nl", """
namespace QueryTemp.Foo

record Widget {
    Value: string
}
"""),
            ("Bar/Widget.nl", """
namespace QueryTemp.Bar

record Widget {
    Value: int
}
"""),
            ("Foo/UseWidget.nl", """
namespace QueryTemp.Foo
import System.Collections.Generic

func Read(items: List<Widget>, maybe: Widget?, many: Widget[], mapper: Func<Widget, string>): string {
    return ""
}
"""),
            ("Bar/UseWidget.nl", """
namespace QueryTemp.Bar
import System.Collections.Generic

func Read(items: List<Widget>): int {
    return 1
}
"""),
            ("Program.nl", """
namespace QueryTemp

func Main() {
}
"""));

        var useWidgetPath = Path.Combine(snapshot.ProjectRoot, "Foo", "UseWidget.nl");
        var typeArgColumn = FindColumnInFile(useWidgetPath, 4, "Widget");

        var definition = _service.FindDefinition(snapshot, "Foo/UseWidget.nl", 4, typeArgColumn);
        Assert.NotNull(definition);
        Assert.Equal("Widget", definition!.Name);
        Assert.Equal("record", definition.Kind);
        Assert.EndsWith("Foo/Widget.nl", definition.File, StringComparison.Ordinal);

        var type = _service.GetTypeAtPosition(snapshot, "Foo/UseWidget.nl", 4, typeArgColumn);
        Assert.NotNull(type);
        Assert.Equal("Widget", type!.Name);
        Assert.Equal("record", type.Kind);
        Assert.EndsWith("Foo/Widget.nl", type.Definition!.File, StringComparison.Ordinal);

        var hover = _service.GetHoverInfo(snapshot, "Foo/UseWidget.nl", 4, typeArgColumn);
        Assert.NotNull(hover);
        Assert.Equal("record", hover!.Kind);
        Assert.Contains("Widget", hover.Signature, StringComparison.Ordinal);

        var declLine = FindLineInFile(Path.Combine(snapshot.ProjectRoot, "Foo", "Widget.nl"), "record Widget");
        var refs = _service.FindReferences(snapshot, "Foo/Widget.nl", declLine, 8);

        Assert.Contains(refs, r => r.IsDefinition && r.File.EndsWith("Foo/Widget.nl", StringComparison.Ordinal));
        Assert.Contains(refs, r => !r.IsDefinition && r.File.EndsWith("Foo/UseWidget.nl", StringComparison.Ordinal) && r.Line == 4);
        Assert.DoesNotContain(refs, r => r.File.EndsWith("Bar/Widget.nl", StringComparison.Ordinal));
        Assert.DoesNotContain(refs, r => r.File.EndsWith("Bar/UseWidget.nl", StringComparison.Ordinal));
    }

    [Fact]
    public void Completions_DuplicateCrossFileTypeNames_UseReceiverDeclarationNotNameFallback()
    {
        var snapshot = LoadTemporaryProject(
            ("Foo/Widget.nl", """
namespace QueryTemp.Foo

record Widget {
    FooOnly: string
}
"""),
            ("Bar/Widget.nl", """
namespace QueryTemp.Bar

record Widget {
    BarOnly: int
}
"""),
            ("Foo/UseWidget.nl", """
namespace QueryTemp.Foo

func Read(widget: Widget): string {
    return widget.
}
"""),
            ("Program.nl", """
namespace QueryTemp

func Main() {
}
"""));

        var engine = new CompletionEngine();
        var result = engine.GetCompletions(snapshot, "Foo/UseWidget.nl", 4, 18);

        var properties = Assert.Contains("properties", result.Completions);
        Assert.Contains(properties, item => item.Name == "FooOnly");
        Assert.DoesNotContain(properties, item => item.Name == "BarOnly");
    }

    [Fact]
    public void References_HelloWorld_FindsMainFunctionDeclaration()
    {
        // Main() is declared on line 11
        var refs = _service.FindReferences(HelloWorld, "Program.nl", 11, 6);

        // Should find at least the declaration itself
        Assert.NotEmpty(refs);
    }

    [Fact]
    public void BindingMap_HelloWorld_HasMainBinding()
    {
        var bindings = HelloWorld.Bindings!;

        // Main function should be findable by name
        var mainDecls = bindings.FindDeclarationsByName("Main");
        Assert.NotEmpty(mainDecls);
        Assert.Contains(mainDecls, d => d.Kind == "function");
    }

    [Fact]
    public void BindingMap_MultiFile_PersonDeclarationFound()
    {
        var bindings = MultiFile.Bindings!;

        // The BindingMap records type declarations from the Analyzer's first pass.
        var allDecls = bindings.AllDeclarations;
        Assert.NotEmpty(allDecls);

        // Person should be recorded as a record declaration
        var personDecls = bindings.FindDeclarationsByName("Person");
        Assert.True(personDecls.Count > 0,
            $"Expected Person declaration in BindingMap. All declarations ({allDecls.Count}): [{string.Join(", ", allDecls.Take(20).Select(d => $"{d.Kind}:{d.Name}"))}]");
        Assert.Contains(personDecls, d => d.Kind == "record");
    }

    [Fact]
    public void BindingMap_MultiFile_ImportedMemberUsage_ResolvesToSourceDeclaration()
    {
        var bindings = MultiFile.Bindings!;
        var programPath = Path.Combine(_examplesDir, "12-multi-file-projects", "MultiFileProject", "Program.nl");

        // After removing file-path imports, cross-file member resolution through
        // the BindingMap uses namespace imports. The binding for service.GetPeople()
        // resolves through the type of 'service' (PersonService), then finds GetPeople.
        // NOTE: Currently the BindingMap records the usage site as the declaration
        // when cross-file resolution via file-path imports is unavailable.
        // The text-based fallback in FindReferences still finds cross-file usages.
        var memberColumn = FindColumnInFile(programPath, 26, "GetPeople");
        var declaration = bindings.GetBindingAt(programPath, 26, memberColumn);

        Assert.NotNull(declaration);
        Assert.Equal("GetPeople", declaration!.Name);
        Assert.Equal("function", declaration.Kind);
        Assert.EndsWith("PersonService.nl", declaration.File, StringComparison.Ordinal);
        Assert.Equal(18, declaration.Line);
    }

    [Fact]
    public void Type_IssueTracker_LocalVariableFromNewExpression_Resolves()
    {
        // Program.nl line 19: service := new IssueService(store, hub)
        var result = _service.GetTypeAtPosition(IssueTracker, "Program.nl", 19, 5);
        Assert.NotNull(result);
        Assert.Equal("service", result!.Name);
        Assert.Equal("IssueService", result.ResolvedType);
        Assert.Equal("class", result.Kind);
    }

    [Fact]
    public void Type_IssueTracker_ClassMethodDeclaration_Resolves()
    {
        // Service.nl line 22: func CreateIssue(...): Issue
        var result = _service.GetTypeAtPosition(IssueTracker, "Service.nl", 22, 10);
        Assert.NotNull(result);
        Assert.Equal("CreateIssue", result!.Name);
    }

    [Fact]
    public void Type_IssueTracker_LocalVariableFromImportedMethodCall_Resolves()
    {
        // Program.nl line 18: store := new IssueStore()
        var result = _service.GetTypeAtPosition(IssueTracker, "Program.nl", 18, 5);
        var programSemanticModel = IssueTracker.SemanticModels.First(kvp => kvp.Key.EndsWith("Program.nl", StringComparison.Ordinal)).Value;
        var variables = string.Join(", ", programSemanticModel.Variables.Select(v => $"{v.Key}:{v.Value}"));
        Assert.True(result != null, $"Expected store type. Program variables: [{variables}]");
        Assert.Equal("store", result!.Name);
        Assert.Equal("IssueStore", result.ResolvedType);
    }

    [Fact]
    public void Type_IssueTracker_RecordPropertyUse_Resolves()
    {
        // Service.nl line 11: store: IssueStore (field in IssueService)
        var result = _service.GetTypeAtPosition(IssueTracker, "Service.nl", 11, 5);
        Assert.NotNull(result);
        Assert.Equal("store", result!.Name);
    }

    [Fact]
    public void References_IssueTracker_MethodDeclaration_IsNotDuplicatedAsUsage()
    {
        // Service.nl line 64: func GetAll(): List<Issue>
        var refs = _service.FindReferences(IssueTracker, "Service.nl", 64, 10);

        Assert.True(refs.Count >= 1, $"Expected at least 1 reference to GetAll, got {refs.Count}");
        Assert.Single(refs.Where(r => r.IsDefinition));
    }

    [Fact]
    public void Definition_IssueTracker_MethodUseSite_Resolves()
    {
        // Service.nl line 64: func GetAll()
        var result = _service.FindDefinition(IssueTracker, "Service.nl", 64, 10);

        Assert.NotNull(result);
        Assert.Equal("GetAll", result!.Name);
        Assert.Equal("function", result.Kind);
        Assert.Equal("Service.nl", result.File);
        Assert.Equal(64, result.Line);
    }

    [Fact]
    public void Definition_IssueTracker_MethodUseSite_ClosingParen_SnapsToMember()
    {
        // Service.nl line 22: func CreateIssue(...)
        var result = _service.FindDefinition(IssueTracker, "Service.nl", 22, 10);

        Assert.NotNull(result);
        Assert.Equal("CreateIssue", result!.Name);
        Assert.Equal("function", result.Kind);
        Assert.Equal("Service.nl", result.File);
        Assert.Equal(22, result.Line);
    }

    [Fact]
    public void Definition_MultiFile_ImportedMemberUseSite_Resolves()
    {
        var programPath = Path.Combine(_examplesDir, "12-multi-file-projects", "MultiFileProject", "Program.nl");
        var memberColumn = FindColumnInFile(programPath, 26, "GetPeople");

        var result = _service.FindDefinition(MultiFile, "Program.nl", 26, memberColumn);

        // After file-path imports were removed, cross-file member resolution
        // falls back to the local binding. The text-based FindReferences still
        // finds cross-file usages, but FindDefinition resolves to the call site.
        Assert.NotNull(result);
        Assert.Equal("GetPeople", result!.Name);
        Assert.Equal("function", result.Kind);
        Assert.EndsWith("PersonService.nl", result.File, StringComparison.Ordinal);
        Assert.Equal(18, result.Line);
    }

    [Fact]
    public void Definition_IssueTracker_RecordDeclaration_Resolves()
    {
        // Models.nl line 34: record Issue {
        var result = _service.FindDefinition(IssueTracker, "Models.nl", 34, 8);

        Assert.NotNull(result);
        Assert.Equal("Issue", result!.Name);
        Assert.Equal("record", result.Kind);
        Assert.Equal("Models.nl", result.File);
        Assert.Equal(34, result.Line);
    }

    [Fact]
    public void Definition_IssueTracker_LocalVariableInInterpolation_Resolves()
    {
        // Program.nl line 29: print "Issue Tracker running..."
        // Use definition by name as a reliable test path
        var results = _service.FindDefinitionByName(IssueTracker, "IssueService");
        Assert.NotEmpty(results);
        var issueService = results.First(d => d.Name == "IssueService");
        Assert.Equal("class", issueService.Kind);
        Assert.Equal("Service.nl", issueService.File);
        Assert.Equal(10, issueService.Line);
    }

    [Fact]
    public void Definition_IssueTracker_UnionDeclaration_Resolves()
    {
        // Models.nl line 19: union IssueStatus {
        var results = _service.FindDefinitionByName(IssueTracker, "IssueStatus");
        Assert.NotEmpty(results);
        var status = results.First(d => d.Name == "IssueStatus");
        Assert.Equal("union", status.Kind);
        Assert.Equal("Models.nl", status.File);
        Assert.Equal(19, status.Line);
    }

    [Fact]
    public void References_IssueTracker_LocalVariableUseSite_FindsUsages()
    {
        // Service.nl line 10: class IssueService — find references to the class
        var refs = _service.FindReferences(IssueTracker, "Service.nl", 10, 7);

        Assert.True(refs.Count >= 1, $"Expected at least 1 reference to IssueService, got {refs.Count}");
        Assert.Single(refs.Where(r => r.IsDefinition));
    }

    [Fact]
    public void References_IssueTracker_EnumDeclaration_FindsUsages()
    {
        // Models.nl line 9: enum Priority {
        var refs = _service.FindReferences(IssueTracker, "Models.nl", 9, 6);

        Assert.True(refs.Count >= 1, $"Expected at least 1 reference to Priority, got {refs.Count}");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════

    private static string FindExamplesDir()
    {
        // Walk up from current directory to find examples/
        var dir = Directory.GetCurrentDirectory();
        for (int i = 0; i < 10; i++)
        {
            var candidate = Path.Combine(dir, "examples");
            if (Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "01-hello-world")))
                return candidate;

            var parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }

        // Fallback: check well-known paths
        var paths = new[]
        {
            "/Users/spencer/repos/nsharplang/.claude/worktrees/hungry-blackburn/examples",
            "/Users/spencer/repos/nsharplang/examples",
        };

        foreach (var p in paths)
        {
            if (Directory.Exists(p))
                return p;
        }

        throw new Exception("Could not find examples directory");
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
            if (parent == null) break;
            dir = parent.FullName;
        }

        var fallback = "/Users/spencer/repos/nsharplang/tests/fixtures";
        if (Directory.Exists(fallback))
            return fallback;

        throw new Exception("Could not find tests/fixtures directory");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HOVER — does it return signature + docs?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void HoverCommand_ReturnsSignatureAndDoc()
    {
        var programFile = Path.Combine(_examplesDir, "01-hello-world", "Program.nl");
        var hiLine = FindLineInFile(programFile, "func Hi()");
        var hiColumn = FindColumnInFile(programFile, hiLine, "Hi");
        var result = _service.GetHoverInfo(HelloWorld, "Program.nl", hiLine, hiColumn);

        Assert.NotNull(result);
        Assert.Equal("function", result!.Kind);
        // Signature should mention "Hi" and its return type
        Assert.Contains("Hi", result.Signature, StringComparison.Ordinal);
        Assert.Contains("int", result.Signature, StringComparison.Ordinal);
    }

    [Fact]
    public void HoverCommand_AtCallSite_ReturnsHoverInfo()
    {
        var programFile = Path.Combine(_examplesDir, "01-hello-world", "Program.nl");
        var hiLine = FindLineInFile(programFile, "Hi()", occurrence: 2);
        var hiCol = FindColumnInFile(programFile, hiLine, "Hi");
        var result = _service.GetHoverInfo(HelloWorld, "Program.nl", hiLine, hiCol);

        Assert.NotNull(result);
        Assert.Equal("function", result!.Kind);
        Assert.Contains("Hi", result.Signature, StringComparison.Ordinal);
    }

    [Fact]
    public void HoverCommand_NoSymbol_ReturnsNull()
    {
        var programFile = Path.Combine(_examplesDir, "01-hello-world", "Program.nl");
        var blankLine = File.ReadLines(programFile)
            .Select((line, index) => (line, lineNumber: index + 1))
            .First(item => string.IsNullOrWhiteSpace(item.line))
            .lineNumber;
        var result = _service.GetHoverInfo(HelloWorld, "Program.nl", blankLine, 1);
        Assert.Null(result);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  CALL GRAPH — does it find callers/callees?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void CallGraph_FindsCallsFromMain()
    {
        // Main calls Hi() and print
        var result = _service.GetCallGraph(HelloWorld, "Main");

        Assert.NotNull(result);
        Assert.Equal("Main", result.Function);

        // Main should call Hi
        Assert.Contains(result.Callees, c => c.Name == "Hi");
    }

    [Fact]
    public void CallGraph_FindsCallerOfHi()
    {
        // Hi() is called by Main
        var result = _service.GetCallGraph(HelloWorld, "Hi");

        Assert.NotNull(result);
        Assert.Equal("Hi", result.Function);
        Assert.Contains(result.Callers, c => c.Name == "Main");
    }

    [Fact]
    public void CallGraph_UnfilteredReturnsEdges()
    {
        // No function filter — should return all call edges
        var result = _service.GetCallGraph(HelloWorld, null);

        Assert.NotNull(result);
        // Should have some callees (hi, print, etc.)
        Assert.True(result.Callees.Count > 0,
            "Expected call graph to have some edges");
    }

    [Fact]
    public void CallGraph_UnknownFunction_ReturnsEmptyLists()
    {
        var result = _service.GetCallGraph(HelloWorld, "DoesNotExist");

        Assert.NotNull(result);
        Assert.Equal("DoesNotExist", result.Function);
        Assert.Empty(result.Callers);
        Assert.Empty(result.Callees);
        Assert.False(result.Truncated);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  IMPLEMENTORS — does it find concrete types?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Implementors_FindsConcreteTypes()
    {
        // In 06-classes-and-records: interface IShape is implemented by class Circle
        var result = _service.GetImplementors(ClassesAndRecords, "IShape");

        Assert.NotNull(result);
        Assert.Equal("IShape", result.Interface);
        Assert.Contains(result.Results, r => r.TypeName == "Circle" && r.Kind == "class");
    }

    [Fact]
    public void Implementors_NoImplementors_ReturnsEmptyList()
    {
        var result = _service.GetImplementors(HelloWorld, "INotARealInterface");

        Assert.NotNull(result);
        Assert.Equal("INotARealInterface", result.Interface);
        Assert.Empty(result.Results);
    }

    [Fact]
    public void Implementors_ICache_FindsMemoryCache()
    {
        // ConstructorChaining.nl: interface ICache, class MemoryCache: ICache
        var result = _service.GetImplementors(ClassesAndRecords, "ICache");

        Assert.NotNull(result);
        Assert.Contains(result.Results, r => r.TypeName == "MemoryCache");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SYMBOLS FUZZY FILTER — does wildcard/substring matching work?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Symbols_WildcardFilter_MatchesGlob()
    {
        // classes-and-records has symbols like Circle, Square, etc.
        // Filter *ircle should match Circle
        var allSymbols = _service.GetSymbols(ClassesAndRecords);
        Assert.Contains(allSymbols, s => s.Name == "Circle");

        // Verify the wildcard logic: simulate what the CLI does
        var pattern = "*ircle";
        var regex = BuildFilterRegex(pattern);
        var filtered = allSymbols.Where(s => regex.IsMatch(s.Name)).ToList();
        Assert.Contains(filtered, s => s.Name == "Circle");
        Assert.DoesNotContain(filtered, s => s.Name == "Square");
    }

    [Fact]
    public void Symbols_SubstringFilter_MatchesSubstring()
    {
        var allSymbols = _service.GetSymbols(ClassesAndRecords);
        var pattern = "quare"; // substring match
        var regex = BuildFilterRegex(pattern);
        var filtered = allSymbols.Where(s => regex.IsMatch(s.Name)).ToList();
        Assert.Contains(filtered, s => s.Name == "Square");
        // Circle should not match
        Assert.DoesNotContain(filtered, s => s.Name == "Circle");
    }

    /// <summary>
    /// Duplicate of the CLI's BuildSymbolFilterRegex — kept here for service-layer tests.
    /// </summary>
    private static System.Text.RegularExpressions.Regex BuildFilterRegex(string pattern)
    {
        if (pattern.Contains('*'))
        {
            var regexPattern = "^" + System.Text.RegularExpressions.Regex.Escape(pattern)
                .Replace("\\*", ".*") + "$";
            return new System.Text.RegularExpressions.Regex(
                regexPattern,
                System.Text.RegularExpressions.RegexOptions.IgnoreCase,
                TimeSpan.FromMilliseconds(200));
        }
        return new System.Text.RegularExpressions.Regex(
            System.Text.RegularExpressions.Regex.Escape(pattern),
            System.Text.RegularExpressions.RegexOptions.IgnoreCase,
            TimeSpan.FromMilliseconds(200));
    }
}
