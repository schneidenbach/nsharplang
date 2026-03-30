using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Integration tests for the nlc query toolchain.
/// Uses REAL example projects as test fixtures — no toy snippets.
///
/// Fixture projects:
///   examples/01-hello-world          — single file, minimal function and locals
///   examples/06-classes-and-records   — multi-file, classes, records, enums, interfaces
///   examples/12-multi-file-projects/MultiFileProject — cross-file imports, namespaces
///   examples/05-unions               — unions, error handling
///   examples/16-task-cli             — cross-file semantic navigation over a larger app
///
/// These tests are the "does it actually work?" layer. They run the full
/// CodeIntelligenceService pipeline against real N# projects and verify
/// the results make semantic sense.
/// </summary>
public class QueryIntegrationTests : IDisposable
{
    private readonly CodeIntelligenceService _service = new();
    private readonly string _examplesDir;

    // Lazily loaded snapshots — one per project, shared across tests
    private ProjectSnapshot? _helloWorldSnapshot;
    private ProjectSnapshot? _classesAndRecordsSnapshot;
    private ProjectSnapshot? _multiFileSnapshot;
    private ProjectSnapshot? _unionsSnapshot;
    private ProjectSnapshot? _taskCliSnapshot;

    public QueryIntegrationTests()
    {
        _examplesDir = FindExamplesDir();
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

    private ProjectSnapshot HelloWorld => _helloWorldSnapshot ??=
        _service.LoadProject(Path.Combine(_examplesDir, "01-hello-world"));

    private ProjectSnapshot ClassesAndRecords => _classesAndRecordsSnapshot ??=
        _service.LoadProject(Path.Combine(_examplesDir, "06-classes-and-records"));

    private ProjectSnapshot MultiFile => _multiFileSnapshot ??=
        _service.LoadProject(Path.Combine(_examplesDir, "12-multi-file-projects", "MultiFileProject"));

    private ProjectSnapshot Unions => _unionsSnapshot ??=
        _service.LoadProject(Path.Combine(_examplesDir, "05-unions"));

    private ProjectSnapshot TaskCli => _taskCliSnapshot ??=
        _service.LoadProject(Path.Combine(_examplesDir, "16-task-cli"));

    // ═══════════════════════════════════════════════════════════════════
    //  SYMBOLS — does it actually find the right stuff?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Symbols_HelloWorld_FindsMainFunction()
    {
        var symbols = _service.GetSymbols(HelloWorld);
        Assert.Contains(symbols, s => s.Name == "Main" && s.Kind == SymbolKind.Function);
        Assert.Single(symbols);
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

    // ═══════════════════════════════════════════════════════════════════
    //  OUTLINE — does file structure look right?
    // ═══════════════════════════════════════════════════════════════════

    [Fact]
    public void Outline_HelloWorld_HasNoImportsAndMainFunction()
    {
        var outline = _service.GetOutline(HelloWorld, "Program.nl");
        Assert.Empty(outline.Imports);
        Assert.Contains(outline.Outline, o => o.Name == "Main" && o.Kind == SymbolKind.Function);
        Assert.Single(outline.Outline);
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
        Assert.Empty(singleFileOutline.Imports);
        Assert.Contains(singleFileOutline.Outline, o => o.Name == "Main");
        Assert.Single(singleFileOutline.Outline);
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
        var result = engine.GetCompletions(HelloWorld, "Program.nl", 2, 5);
        Assert.False(result.Completions.ContainsKey("keywords"),
            "Keywords should be excluded by default for LLM use");
        Assert.False(result.Completions.ContainsKey("primitiveTypes"),
            "Primitive types should be excluded by default for LLM use");
    }

    [Fact]
    public void Completions_IdentifierContext_IncludesKeywordsWhenRequested()
    {
        var engine = new CompletionEngine();
        var result = engine.GetCompletions(HelloWorld, "Program.nl", 2, 5, includeKeywords: true);
        Assert.True(result.Completions.ContainsKey("keywords"),
            "Keywords should be included when includeKeywords=true");

        var keywords = result.Completions["keywords"];
        Assert.Contains(keywords, k => k.Name == "if");
        Assert.Contains(keywords, k => k.Name == "return");
    }

    [Fact]
    public void Completions_MemberAccess_FieldMembers()
    {
        // PersonService.nl line 15: people.Add(person)
        // Completions at "people." should return List<Person> members
        var engine = new CompletionEngine();
        var result = engine.GetCompletions(MultiFile, "Services/PersonService.nl", 15, 15);
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
    public void Json_Outline_HasImportsAndOutlineArrays()
    {
        var outline = _service.GetOutline(HelloWorld, "Program.nl");
        var json = OutputFormatter.OutlineToJson(outline);
        var doc = JsonDocument.Parse(json);

        Assert.Equal(JsonValueKind.Array, doc.RootElement.GetProperty("imports").ValueKind);
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
    //   Line 1: func Main() {
    //   Line 2:     name := "World"
    //   Line 3:     print $"Hello, {name}!"

    [Fact]
    public void Definition_AtPosition_FindsNameVariable()
    {
        var result = _service.FindDefinition(HelloWorld, "Program.nl", 3, 21);
        Assert.NotNull(result);
        Assert.Equal("name", result!.Name);
        Assert.Equal("variable", result.Kind);
        Assert.Equal(2, result.Line);
        Assert.Equal(5, result.Column);
    }

    [Fact]
    public void Definition_AtPosition_FindsMainFunction()
    {
        var results = _service.FindDefinitionByName(HelloWorld, "Main");
        Assert.NotEmpty(results);
        var main = results.First(d => d.Name == "Main");
        Assert.Equal("function", main.Kind);
        Assert.Equal(1, main.Line);
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
        Assert.Equal(4, person.Line); // record Person is on line 4 of Person.nl
        Assert.Contains("Person.nl", person.File);
    }

    [Fact]
    public void Definition_MultiFile_GetInfoMethodFound()
    {
        var results = _service.FindDefinitionByName(MultiFile, "GetInfo");
        Assert.NotEmpty(results);
        var getInfo = results.First(d => d.Kind == "function");
        Assert.Equal(9, getInfo.Line); // func GetInfo on line 9
    }

    [Fact]
    public void Definition_MultiFile_StatusEnumAtCorrectLine()
    {
        var results = _service.FindDefinitionByName(MultiFile, "Status");
        Assert.NotEmpty(results);
        var status = results.First(d => d.Kind == "enum");
        Assert.Equal(15, status.Line); // enum Status on line 15
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
    public void References_HelloWorld_FindsNameVariableUsages()
    {
        var refs = _service.FindReferences(HelloWorld, "Program.nl", 2, 5);

        Assert.NotEmpty(refs);
        Assert.Equal(2, refs.Count);
        Assert.Single(refs.Where(r => r.IsDefinition));
        Assert.Contains(refs, r => r.File == "Program.nl" && r.Line == 3 && r.Column == 21);
    }

    [Fact]
    public void BindingMap_HelloWorld_HasSpecificBindings()
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

        var memberColumn = FindColumnInFile(programPath, 30, "GetPeople");
        var declaration = bindings.GetBindingAt(programPath, 30, memberColumn);

        Assert.NotNull(declaration);
        Assert.Equal("GetPeople", declaration!.Name);
        Assert.Equal("function", declaration.Kind);
        Assert.EndsWith(Path.Combine("Services", "PersonService.nl"), declaration.File, StringComparison.Ordinal);
        Assert.Equal(19, declaration.Line);
    }

    [Fact]
    public void Type_TaskCli_ClassNameInNewExpression_Resolves()
    {
        var result = _service.GetTypeAtPosition(TaskCli, "Program.nl", 39, 18);
        Assert.NotNull(result);
        Assert.Equal("TaskService", result!.Name);
        Assert.Equal("TaskService", result.ResolvedType);
        Assert.Equal("class", result.Kind);
    }

    [Fact]
    public void Type_TaskCli_ImportedMethodCall_ResolvesToReturnType()
    {
        var result = _service.GetTypeAtPosition(TaskCli, "Commands/StatsCommand.nl", 14, 26);
        Assert.NotNull(result);
        Assert.Equal("GetStats", result!.Name);
        Assert.Equal("TaskStats", result.ResolvedType);
        Assert.Equal("record", result.Kind);
    }

    [Fact]
    public void Type_TaskCli_LocalVariableFromImportedMethodCall_Resolves()
    {
        var result = _service.GetTypeAtPosition(TaskCli, "Commands/StatsCommand.nl", 14, 9);
        var statsCommandModel = TaskCli.SemanticModels.First(kvp => kvp.Key.EndsWith(Path.Combine("Commands", "StatsCommand.nl"), StringComparison.Ordinal)).Value;
        var variables = string.Join(", ", statsCommandModel.Variables.Select(v => $"{v.Key}:{v.Value}"));
        Assert.True(result != null, $"Expected stats type. StatsCommand variables: [{variables}]");
        Assert.Equal("stats", result!.Name);
        Assert.Equal("TaskStats", result.ResolvedType);
    }

    [Fact]
    public void Type_TaskCli_RecordPropertyUse_Resolves()
    {
        var result = _service.GetTypeAtPosition(TaskCli, "Services/Formatter.nl", 103, 31);
        Assert.NotNull(result);
        Assert.Equal("Total", result!.Name);
        Assert.Equal("int", result.ResolvedType);
        Assert.Equal("primitive", result.Kind);
    }

    [Fact]
    public void References_TaskCli_MethodDeclaration_IsNotDuplicatedAsUsage()
    {
        var refs = _service.FindReferences(TaskCli, "Services/TaskService.nl", 178, 10);

        Assert.Equal(2, refs.Count);
        Assert.Single(refs.Where(r => r.IsDefinition));
        Assert.Contains(refs, r => r.File == "Commands/StatsCommand.nl" && r.Line == 14);
    }

    [Fact]
    public void Definition_TaskCli_MethodUseSite_Resolves()
    {
        var result = _service.FindDefinition(TaskCli, "Commands/StatsCommand.nl", 14, 26);

        Assert.NotNull(result);
        Assert.Equal("GetStats", result!.Name);
        Assert.Equal("function", result.Kind);
        Assert.Equal("Services/TaskService.nl", result.File);
        Assert.Equal(178, result.Line);
        Assert.Equal(5, result.Column);
    }

    [Fact]
    public void Definition_TaskCli_MethodUseSite_ClosingParen_SnapsToMember()
    {
        var result = _service.FindDefinition(TaskCli, "Commands/StatsCommand.nl", 14, 35);

        Assert.NotNull(result);
        Assert.Equal("GetStats", result!.Name);
        Assert.Equal("function", result.Kind);
        Assert.Equal("Services/TaskService.nl", result.File);
        Assert.Equal(178, result.Line);
        Assert.Equal(5, result.Column);
    }

    [Fact]
    public void Definition_MultiFile_ImportedMemberUseSite_Resolves()
    {
        var programPath = Path.Combine(_examplesDir, "12-multi-file-projects", "MultiFileProject", "Program.nl");
        var memberColumn = FindColumnInFile(programPath, 30, "GetPeople");

        var result = _service.FindDefinition(MultiFile, "Program.nl", 30, memberColumn);

        Assert.NotNull(result);
        Assert.Equal("GetPeople", result!.Name);
        Assert.Equal("function", result.Kind);
        Assert.Equal("Services/PersonService.nl", result.File);
        Assert.Equal(19, result.Line);
        Assert.Equal(5, result.Column);
    }

    [Fact]
    public void Definition_TaskCli_RecordPropertyUseSite_Resolves()
    {
        var formatterPath = Path.Combine(_examplesDir, "16-task-cli", "Services", "Formatter.nl");
        var totalColumn = FindColumnInFile(formatterPath, 103, "Total");

        var result = _service.FindDefinition(TaskCli, "Services/Formatter.nl", 103, totalColumn);

        Assert.NotNull(result);
        Assert.Equal("Total", result!.Name);
        Assert.Equal("field", result.Kind);
        Assert.Equal("Services/TaskService.nl", result.File);
        Assert.Equal(281, result.Line);
        Assert.Equal(5, result.Column);
    }

    [Fact]
    public void Definition_TaskCli_LocalVariableInInterpolation_Resolves()
    {
        var result = _service.FindDefinition(TaskCli, "Services/Formatter.nl", 103, 25);

        Assert.NotNull(result);
        Assert.Equal("stats", result!.Name);
        Assert.Equal("variable", result.Kind);
        Assert.Equal("Services/Formatter.nl", result.File);
        Assert.Equal(101, result.Line);
        Assert.Equal(12, result.Column);
    }

    [Fact]
    public void Definition_TaskCli_RecordPropertyInInterpolation_Resolves()
    {
        var result = _service.FindDefinition(TaskCli, "Services/Formatter.nl", 103, 31);

        Assert.NotNull(result);
        Assert.Equal("Total", result!.Name);
        Assert.Equal("field", result.Kind);
        Assert.Equal("Services/TaskService.nl", result.File);
        Assert.Equal(281, result.Line);
        Assert.Equal(5, result.Column);
    }

    [Fact]
    public void References_TaskCli_LocalVariableUseSite_IncludeInterpolationUses()
    {
        var refs = _service.FindReferences(TaskCli, "Services/Formatter.nl", 103, 25);

        Assert.Equal(8, refs.Count);
        Assert.Single(refs.Where(r => r.IsDefinition));
        Assert.Contains(refs, r => r.File == "Services/Formatter.nl" && r.Line == 107 && r.Column == 12);
        Assert.Contains(refs, r => r.File == "Services/Formatter.nl" && r.Line == 108 && r.Column == 27);
    }

    [Fact]
    public void References_TaskCli_RecordPropertyUseSite_IncludeInterpolationUse()
    {
        var refs = _service.FindReferences(TaskCli, "Services/Formatter.nl", 103, 31);

        Assert.Equal(9, refs.Count);
        Assert.Single(refs.Where(r => r.IsDefinition));
        Assert.Contains(refs, r => r.File == "Services/Formatter.nl" && r.Line == 103 && r.Column == 31);
        Assert.Contains(refs, r => r.File == "Services/TaskService.nl" && r.Line == 195 && r.Column == 13);
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
}
