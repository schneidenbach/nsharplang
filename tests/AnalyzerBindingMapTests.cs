using System;
using Xunit;
using NSharpLang.Compiler;

namespace Tests;

public class AnalyzerBindingMapTests
{
    private static AnalysisResult Analyze(string source)
    {
        var lexer = new Lexer(source);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var parseResult = parser.ParseCompilationUnit();

        Assert.NotNull(parseResult.CompilationUnit);

        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(parseResult.CompilationUnit!, "test.nl", null, source);
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
    public void AnalyzerBindingMap_InterpolatedIdentifier_ResolvesToDeclaration()
    {
        var source = @"
func test() {
    name := ""Spencer""
    print $""Hello, {name}!""
}";

        var result = Analyze(source);
        var bindings = Assert.IsType<BindingMap>(result.Bindings);

        var nameUsageColumn = FindColumn(source, 4, "name");
        var declaration = bindings.GetBindingAt("test.nl", 4, nameUsageColumn);

        Assert.NotNull(declaration);
        Assert.Equal("name", declaration!.Name);
        Assert.Equal(3, declaration.Line);
        Assert.Equal(5, declaration.Column);
    }

    [Fact]
    public void AnalyzerBindingMap_MemberAccess_ResolvesToPropertyDeclaration()
    {
        var source = @"
record Person {
    Name: string
}

func test() {
    person := new Person { Name: ""Spencer"" }
    print person.Name
}";

        var result = Analyze(source);
        var bindings = Assert.IsType<BindingMap>(result.Bindings);

        var memberUsageColumn = FindColumn(source, 8, "Name");
        var declaration = bindings.GetBindingAt("test.nl", 8, memberUsageColumn);

        Assert.NotNull(declaration);
        Assert.Equal("Name", declaration!.Name);
        Assert.Equal("field", declaration.Kind);
        Assert.Equal(3, declaration.Line);
        Assert.Equal(5, declaration.Column);
    }
}
