using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Tests for CompletionEngine.
/// Note: The engine reads source files from disk via File.ReadAllText, so we use temp files.
/// Tests that exercise code paths requiring assembly loading (like .NET type resolution)
/// use real assemblies available in the test process.
/// </summary>
public class CompletionEngineTests
{
    private (CompletionEngine engine, ProjectSnapshot snapshot, string filePath) SetupWithSource(string source)
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "nltest_" + Path.GetRandomFileName());
        Directory.CreateDirectory(tempDir);
        var filePath = Path.Combine(tempDir, "test.nl");
        File.WriteAllText(filePath, source);

        var lexer = new Lexer(source, filePath);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, filePath, source);
        var parseResult = parser.ParseCompilationUnit();

        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        var analysisResult = analyzer.Analyze(parseResult.CompilationUnit!, filePath, null, source);

        var compilationUnits = new Dictionary<string, CompilationUnit>
        {
            [filePath] = parseResult.CompilationUnit!
        };
        var semanticModels = new Dictionary<string, SemanticModel>
        {
            [filePath] = analysisResult.SemanticModel
        };

        var projectIndex = analysisResult.Bindings != null
            ? new ProjectIndex(analysisResult.Bindings, analyzer.GetTypeDeclarationFiles())
            : null;

        var snapshot = new ProjectSnapshot(
            tempDir,
            compilationUnits,
            semanticModels,
            new List<CompilerError>(),
            analyzer,
            new List<string> { filePath },
            projectIndex);

        return (new CompletionEngine(), snapshot, filePath);
    }

    private void Cleanup(string filePath)
    {
        var dir = Path.GetDirectoryName(filePath);
        if (dir != null && Directory.Exists(dir))
        {
            try { Directory.Delete(dir, true); } catch { }
        }
    }

    // ── Identifier Completions ──────────────────────────────────────────

    [Fact]
    public void GetCompletions_IdentifierContext_ReturnsVariables()
    {
        var source = "func main() {\n    name := \"Spencer\"\n    n\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 3, 5);

            Assert.Equal(CompletionContext.Identifier, result.Context);
            Assert.True(result.Completions.ContainsKey("variables"));
            Assert.Contains(result.Completions["variables"], c => c.Name == "name");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_IdentifierContext_ReturnsFunctions()
    {
        var source = "func helper(): int {\n    return 42\n}\n\nfunc main() {\n    h\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 6, 5);

            Assert.Equal(CompletionContext.Identifier, result.Context);
            Assert.True(result.Completions.ContainsKey("functions"));
            Assert.Contains(result.Completions["functions"], c => c.Name == "helper");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_IdentifierContext_IncludesTypeDeclarations()
    {
        var source = "class Person {\n    Name: string\n}\n\nfunc main() {\n    P\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 6, 5);

            Assert.True(result.Completions.ContainsKey("types"));
            Assert.Contains(result.Completions["types"], c => c.Name == "Person" && c.Kind == "class");
        }
        finally { Cleanup(filePath); }
    }

    // ── Keyword Completions ─────────────────────────────────────────────

    [Fact]
    public void GetCompletions_IncludeKeywords_ReturnsKeywordsAndPrimitiveTypes()
    {
        var source = "func main() {\n    \n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 2, 4, includeKeywords: true);

            Assert.True(result.Completions.ContainsKey("keywords"));
            Assert.True(result.Completions.ContainsKey("primitiveTypes"));
            Assert.True(result.Completions.ContainsKey("modifiers"));

            Assert.Contains(result.Completions["keywords"], c => c.Name == "import");
            Assert.Contains(result.Completions["keywords"], c => c.Name == "func");
            Assert.Contains(result.Completions["primitiveTypes"], c => c.Name == "int");
            Assert.Contains(result.Completions["primitiveTypes"], c => c.Name == "string");
            Assert.Contains(result.Completions["modifiers"], c => c.Name == "pub");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_ExcludeKeywordsByDefault_OmitsKeywords()
    {
        var source = "func main() {\n    \n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 2, 4);

            Assert.False(result.Completions.ContainsKey("keywords"));
            Assert.False(result.Completions.ContainsKey("primitiveTypes"));
            Assert.False(result.Completions.ContainsKey("modifiers"));
        }
        finally { Cleanup(filePath); }
    }

    // ── Member Access Completions (Static) ──────────────────────────────

    [Fact]
    public void GetCompletions_MemberAccess_ConsoleStaticMembers()
    {
        var source = "func main() {\n    Console.\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 2, 12);

            Assert.Equal(CompletionContext.MemberAccess, result.Context);
            Assert.Equal("Console", result.Receiver);
            Assert.NotNull(result.ReceiverType);

            // Console has static methods like WriteLine
            var allItems = result.Completions.Values.SelectMany(v => v).ToList();
            Assert.Contains(allItems, c => c.Name == "WriteLine");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_MemberAccess_MathStaticMembers()
    {
        var source = "func main() {\n    Math.\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 2, 9);

            Assert.Equal(CompletionContext.MemberAccess, result.Context);
            Assert.Equal("Math", result.Receiver);

            var allItems = result.Completions.Values.SelectMany(v => v).ToList();
            Assert.Contains(allItems, c => c.Name == "Max");
            Assert.Contains(allItems, c => c.Name == "Min");
        }
        finally { Cleanup(filePath); }
    }

    // ── Member Access Completions (Instance) ────────────────────────────

    [Fact]
    public void GetCompletions_MemberAccess_StringInstanceMembers()
    {
        var source = "func main() {\n    name := \"hello\"\n    name.\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 3, 9);

            Assert.Equal(CompletionContext.MemberAccess, result.Context);
            Assert.Equal("name", result.Receiver);

            var allItems = result.Completions.Values.SelectMany(v => v).ToList();
            // String should have well-known instance members
            Assert.Contains(allItems, c => c.Name == "Length");
            Assert.Contains(allItems, c => c.Name == "ToUpper");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_MemberAccess_InterpolatedStringLiteralMembers()
    {
        var source = "func main() {\n    $\"this is a string\".\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var line = 2;
            var col = source.Split('\n')[line - 1].Length;
            var result = engine.GetCompletions(snapshot, filePath, line, col);

            Assert.Equal(CompletionContext.MemberAccess, result.Context);
            Assert.Equal("System.String", result.ReceiverType);

            var allItems = result.Completions.Values.SelectMany(v => v).ToList();
            Assert.Contains(allItems, c => c.Name == "Length");
            Assert.Contains(allItems, c => c.Name == "ToUpper");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_ChainedMemberAccess_StringCallMembers()
    {
        var source = "func main() {\n    name := \"hello\"\n    name.ToUpper().\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var line = 3;
            var col = source.Split('\n')[line - 1].Length;
            var result = engine.GetCompletions(snapshot, filePath, line, col);

            Assert.Equal(CompletionContext.MemberAccess, result.Context);
            Assert.Equal("name.ToUpper()", result.Receiver);

            var allItems = result.Completions.Values.SelectMany(v => v).ToList();
            Assert.Contains(allItems, c => c.Name == "Length");
            Assert.Contains(allItems, c => c.Name == "ToLower");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_ChainedMemberAccess_NonStringReturnMembers()
    {
        var source = "func main() {\n    name := \"hello\"\n    name.IndexOf(\"e\").\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var line = 3;
            var col = source.Split('\n')[line - 1].Length;
            var result = engine.GetCompletions(snapshot, filePath, line, col);

            Assert.Equal(CompletionContext.MemberAccess, result.Context);
            Assert.Equal("name.IndexOf()", result.Receiver);

            var allItems = result.Completions.Values.SelectMany(v => v).ToList();
            Assert.Contains(allItems, c => c.Name == "CompareTo");
            Assert.DoesNotContain(allItems, c => c.Name == "ToLower");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_ChainedMemberAccess_NSharpReturnMembers()
    {
        var source = """
class Dog {
    Name: string
    func Bark(): string {
        return "Woof"
    }
}

class Factory {
    func Create(): Dog {
        return new Dog { Name: "Rex" }
    }
}

func main() {
    factory := new Factory {}
    factory.Create().
}
""";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var line = 16;
            var col = source.Split('\n')[line - 1].Length;
            var result = engine.GetCompletions(snapshot, filePath, line, col);

            Assert.Equal(CompletionContext.MemberAccess, result.Context);
            Assert.Equal("factory.Create()", result.Receiver);

            var allItems = result.Completions.Values.SelectMany(v => v).ToList();
            Assert.Contains(allItems, c => c.Name == "Name");
            Assert.Contains(allItems, c => c.Name == "Bark");
        }
        finally { Cleanup(filePath); }
    }

    // ── Namespace Completions ───────────────────────────────────────────

    [Fact]
    public void GetCompletions_NamespaceAccess_SystemTypes()
    {
        var source = "func main() {\n    System.\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 2, 11);

            Assert.Equal(CompletionContext.Namespace, result.Context);
            Assert.Equal("System", result.Receiver);
            Assert.True(result.Completions.ContainsKey("types"));
            Assert.True(result.Completions["types"].Count > 0, "System namespace should have types");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_NamespaceAccess_SystemIO()
    {
        var source = "func main() {\n    System.IO.\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 2, 14);

            Assert.Equal(CompletionContext.Namespace, result.Context);
            Assert.Equal("System.IO", result.Receiver);
            Assert.True(result.Completions.ContainsKey("types"));
        }
        finally { Cleanup(filePath); }
    }

    // ── N# Type Member Completions ──────────────────────────────────────

    [Fact]
    public void GetCompletions_NSharpClassMembers_ShowsFieldsAndMethods()
    {
        var source = "class Dog {\n    Name: string\n    func Bark(): string {\n        return \"Woof\"\n    }\n}\n\nfunc main() {\n    dog := new Dog { Name: \"Rex\" }\n    dog.\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 10, 8);

            Assert.Equal(CompletionContext.MemberAccess, result.Context);

            var allItems = result.Completions.Values.SelectMany(v => v).ToList();
            Assert.True(allItems.Count > 0, "Should have members for N# class Dog");
            // Verify actual N# class members are present
            Assert.Contains(allItems, c => c.Name == "Name");
            Assert.Contains(allItems, c => c.Name == "Bark");
        }
        finally { Cleanup(filePath); }
    }

    // ── Edge Cases ──────────────────────────────────────────────────────

    [Fact]
    public void GetCompletions_InvalidFile_ReturnsUnknownContext()
    {
        var source = "func main() {}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, "nonexistent.nl", 1, 1);

            Assert.Equal(CompletionContext.Unknown, result.Context);
            Assert.Empty(result.Completions);
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_LineOutOfRange_ReturnsUnknownContext()
    {
        var source = "func main() {}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 999, 1);

            Assert.Equal(CompletionContext.Unknown, result.Context);
            Assert.Empty(result.Completions);
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_LineZero_ReturnsUnknownContext()
    {
        var source = "func main() {}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 0, 1);

            Assert.Equal(CompletionContext.Unknown, result.Context);
            Assert.Empty(result.Completions);
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_MultipleTypesInFile_AllAppearAsCompletions()
    {
        var source = "class Cat {}\nstruct Point {\n    X: int\n    Y: int\n}\nenum Color { Red, Green, Blue }\n\nfunc main() {\n    \n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 9, 4);

            Assert.True(result.Completions.ContainsKey("types"));
            var types = result.Completions["types"];
            Assert.Contains(types, c => c.Name == "Cat" && c.Kind == "class");
            Assert.Contains(types, c => c.Name == "Point" && c.Kind == "struct");
            Assert.Contains(types, c => c.Name == "Color" && c.Kind == "enum");
        }
        finally { Cleanup(filePath); }
    }

    [Fact]
    public void GetCompletions_CompletionItemProperties_ArePopulated()
    {
        var source = "func add(a: int, b: int): int {\n    return a + b\n}\n\nfunc main() {\n    a\n}";
        var (engine, snapshot, filePath) = SetupWithSource(source);

        try
        {
            var result = engine.GetCompletions(snapshot, filePath, 6, 5);

            Assert.True(result.Completions.ContainsKey("functions"));
            var addFunc = result.Completions["functions"].FirstOrDefault(c => c.Name == "add");
            Assert.NotNull(addFunc);
            Assert.Equal("function", addFunc!.Kind);
            Assert.NotNull(addFunc.Type); // return type should be populated
            Assert.Equal("int", addFunc.Type);
            Assert.False(addFunc.IsStatic);

            // The function also appears via declarations with full parameter metadata
            Assert.True(result.Completions.ContainsKey("types"));
            var addDecl = result.Completions["types"].FirstOrDefault(c => c.Name == "add");
            Assert.NotNull(addDecl);
            Assert.NotNull(addDecl!.Parameters);
            Assert.Contains("a", addDecl.Parameters!);
            Assert.Contains("b", addDecl.Parameters!);
        }
        finally { Cleanup(filePath); }
    }
}
