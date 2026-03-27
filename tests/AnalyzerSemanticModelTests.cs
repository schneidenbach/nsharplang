using System;
using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;

namespace Tests;

public class AnalyzerSemanticModelTests
{
    private AnalysisResult Analyze(string source)
    {
        var lexer = new Lexer(source);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var parseResult = parser.ParseCompilationUnit();

        Assert.NotNull(parseResult.CompilationUnit);

        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(parseResult.CompilationUnit, "test.nl", null, source);
    }

    private static int FindColumn(string source, int lineNumber, string needle, int occurrence = 1)
    {
        var line = source.Split('\n')[lineNumber - 1];
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

    [Fact]
    public void Analyzer_VariableDeclaration_PopulatesSemanticModel()
    {
        var source = @"
func test() {
    x := 42
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var xType = result.SemanticModel.LookupIdentifier("x");
        Assert.NotNull(xType);
        Assert.Equal("int", xType.ToString());
    }

    [Fact]
    public void Analyzer_VariableWithExplicitType_PopulatesSemanticModel()
    {
        var source = @"
func test() {
    name: string = ""John""
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var nameType = result.SemanticModel.LookupIdentifier("name");
        Assert.NotNull(nameType);
        Assert.Equal("string", nameType.ToString());
    }

    [Fact]
    public void Analyzer_FunctionParameters_PopulateSemanticModel()
    {
        var source = @"
func greet(name: string, age: int) {
    print(name)
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);

        var nameType = result.SemanticModel.LookupIdentifier("name");
        Assert.NotNull(nameType);
        Assert.Equal("string", nameType.ToString());

        var ageType = result.SemanticModel.LookupIdentifier("age");
        Assert.NotNull(ageType);
        Assert.Equal("int", ageType.ToString());
    }

    [Fact]
    public void Analyzer_FunctionReturnType_PopulatesSemanticModel()
    {
        var source = @"
func getNumber(): int {
    return 42
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var funcType = result.SemanticModel.LookupIdentifier("getNumber");
        Assert.NotNull(funcType);
        // Function lookup returns the function's return type
        Assert.Equal("int", funcType.ToString());
    }

    [Fact]
    public void Analyzer_MultipleVariables_AllInSemanticModel()
    {
        var source = @"
func test() {
    x := 1
    name := ""test""
    active := true
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("x")?.ToString());
        Assert.Equal("string", result.SemanticModel.LookupIdentifier("name")?.ToString());
        Assert.Equal("bool", result.SemanticModel.LookupIdentifier("active")?.ToString());
    }

    [Fact]
    public void Analyzer_ArrayType_PopulatesSemanticModel()
    {
        var source = @"
func test() {
    numbers: int[] = [1, 2, 3]
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var numbersType = result.SemanticModel.LookupIdentifier("numbers");
        Assert.NotNull(numbersType);
        Assert.Equal("int[]", numbersType.ToString());
    }

    [Fact]
    public void Analyzer_NullableType_PopulatesSemanticModel()
    {
        var source = @"
func test() {
    optionalName: string? = null
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var optionalNameType = result.SemanticModel.LookupIdentifier("optionalName");
        Assert.NotNull(optionalNameType);
        Assert.Equal("string?", optionalNameType.ToString());
    }

    [Fact]
    public void Analyzer_InferredArrayType_PopulatesSemanticModel()
    {
        var source = @"
func test() {
    numbers := [1, 2, 3]
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var numbersType = result.SemanticModel.LookupIdentifier("numbers");
        Assert.NotNull(numbersType);
        // Should infer as int[]
        Assert.Equal("int[]", numbersType.ToString());
    }

    [Fact]
    public void Analyzer_SemanticModelNotNull_EvenWithErrors()
    {
        var source = @"
func test() {
    x := unknownFunction()  // This will cause an error
}";

        var result = Analyze(source);

        // Even with analysis errors, semantic model should exist
        Assert.NotNull(result.SemanticModel);
        // x should still be recorded (type might be Unknown)
        var xType = result.SemanticModel.LookupIdentifier("x");
        Assert.NotNull(xType);
    }

    [Fact]
    public void Analyzer_LINQMethodChain_InfersConstructedListType()
    {
        var source = @"
import System.Linq

func test() {
    numbers: int[] = [1, 2, 3, 4, 5]
    doubled := numbers.Where(x => x > 2).Select(x => x * 2).ToList()
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var doubledType = result.SemanticModel.LookupIdentifier("doubled");
        Assert.NotNull(doubledType);
        Assert.Equal("List<int>", doubledType.ToString());
    }

    [Fact]
    public void Analyzer_LINQIndexedSelect_InfersConstructedListType()
    {
        var source = @"
import System.Linq

func test() {
    numbers: int[] = [1, 2, 3]
    indexed := numbers.Select((item, index) => item + index).ToList()
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var indexedType = result.SemanticModel.LookupIdentifier("indexed");
        Assert.NotNull(indexedType);
        Assert.Equal("List<int>", indexedType.ToString());
    }

    [Fact]
    public void Analyzer_ExpressionType_IsQueryableBySourcePosition()
    {
        var source = @"
func test() {
    x := 41
    y := x + 1
}";

        var result = Analyze(source);

        var xUseColumn = FindColumn(source, 4, "x");
        var xUseType = result.SemanticModel.LookupTypeAtPosition(4, xUseColumn);

        Assert.NotNull(xUseType);
        Assert.Equal("int", xUseType!.ToString());
    }
}
