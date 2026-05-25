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
    public void AnalyzerBindingMap_InterpolatedMemberAccess_ResolvesToFieldDeclaration()
    {
        var source = @"
record Person {
    Name: string
}

func test() {
    person := new Person { Name: ""Spencer"" }
    print $""Hello, {person.Name}!""
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

    [Fact]
    public void AnalyzerBindingMap_InterpolatedRawStringIdentifier_ResolvesToDeclaration()
    {
        var source = @"
func test() {
    name := ""Spencer""
    print $""""""
Hello, {name}!
""""""
}";

        var result = Analyze(source);
        var bindings = Assert.IsType<BindingMap>(result.Bindings);

        var usageColumn = FindColumn(source, 5, "name");
        var declaration = bindings.GetBindingAt("test.nl", 5, usageColumn);

        Assert.NotNull(declaration);
        Assert.Equal("name", declaration!.Name);
        Assert.Equal("local", declaration.Kind);
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

    [Fact]
    public void AnalyzerBindingMap_TypeAnnotation_RecordsBindingToTypeDeclaration()
    {
        var source = @"
class Greeter {
    Name: string
}

func test() {
    g: Greeter = new Greeter()
}";

        var result = Analyze(source);
        var bindings = Assert.IsType<BindingMap>(result.Bindings);

        // The type annotation "Greeter" on line 7 should bind to the class declaration on line 2
        var typeRefColumn = FindColumn(source, 7, "Greeter");
        var declaration = bindings.GetBindingAt("test.nl", 7, typeRefColumn);

        Assert.NotNull(declaration);
        Assert.Equal("Greeter", declaration!.Name);
        Assert.Equal("class", declaration.Kind);
        Assert.Equal(2, declaration.Line);
    }

    [Fact]
    public void AnalyzerBindingMap_TypeAnnotationInParameter_RecordsBinding()
    {
        var source = @"
record Point {
    X: int
    Y: int
}

func draw(p: Point) {
    print p.X
}";

        var result = Analyze(source);
        var bindings = Assert.IsType<BindingMap>(result.Bindings);

        // The parameter type "Point" on line 7 should bind to the record declaration on line 2
        var typeRefColumn = FindColumn(source, 7, "Point");
        var declaration = bindings.GetBindingAt("test.nl", 7, typeRefColumn);

        Assert.NotNull(declaration);
        Assert.Equal("Point", declaration!.Name);
        Assert.Equal("record", declaration.Kind);
        Assert.Equal(2, declaration.Line);
    }

    [Fact]
    public void AnalyzerBindingMap_ReturnType_RecordsBinding()
    {
        var source = @"
struct Vector {
    X: float
    Y: float
}

func make(): Vector {
    return new Vector()
}";

        var result = Analyze(source);
        var bindings = Assert.IsType<BindingMap>(result.Bindings);

        // The return type "Vector" on line 7 should bind to the struct declaration on line 2
        var typeRefColumn = FindColumn(source, 7, "Vector");
        var declaration = bindings.GetBindingAt("test.nl", 7, typeRefColumn);

        Assert.NotNull(declaration);
        Assert.Equal("Vector", declaration!.Name);
        Assert.Equal("struct", declaration.Kind);
        Assert.Equal(2, declaration.Line);
    }

    [Fact]
    public void AnalyzerBindingMap_FieldTypeAnnotation_RecordsBinding()
    {
        var source = @"
record Address {
    City: string
}

class Person {
    Home: Address
}";

        var result = Analyze(source);
        var bindings = Assert.IsType<BindingMap>(result.Bindings);

        // The field type "Address" on line 7 should bind to the record declaration on line 2
        var typeRefColumn = FindColumn(source, 7, "Address");
        var declaration = bindings.GetBindingAt("test.nl", 7, typeRefColumn);

        Assert.NotNull(declaration);
        Assert.Equal("Address", declaration!.Name);
        Assert.Equal("record", declaration.Kind);
        Assert.Equal(2, declaration.Line);
    }

    [Fact]
    public void AnalyzerBindingMap_FindAllReferences_IncludesTypeAnnotations()
    {
        var source = @"
class Config {
    Value: string
}

func make(): Config {
    c: Config = new Config()
    return c
}";

        var result = Analyze(source);
        var bindings = Assert.IsType<BindingMap>(result.Bindings);

        // FindAllReferences from the Config declaration (at 'class' keyword position)
        var declColumn = FindColumn(source, 2, "class");
        var (declaration, usages) = bindings.FindAllReferences("test.nl", 2, declColumn);

        Assert.NotNull(declaration);
        Assert.Equal("Config", declaration!.Name);

        // Should have usages from: return type (line 6), variable type (line 7), constructor (line 7)
        Assert.True(usages.Count >= 2, $"Expected at least 2 usages, got {usages.Count}");
    }

    [Fact]
    public void AnalyzerBindingMap_CompositeTypeUses_RecordSemanticBindings()
    {
        var source = @"
record Person {
    Name: string
}

record Box<T> {
    Value: T
}

func use(
    maybe: Person?,
    many: Person[],
    box: Box<Person>,
    mapper: Func<Person, string>
) {
}";

        var result = Analyze(source);
        var bindings = Assert.IsType<BindingMap>(result.Bindings);

        var maybePerson = bindings.GetBindingAt("test.nl", 11, FindColumn(source, 11, "Person"));
        Assert.NotNull(maybePerson);
        Assert.Equal("Person", maybePerson!.Name);
        Assert.Equal("record", maybePerson.Kind);
        Assert.Equal(2, maybePerson.Line);

        var arrayPerson = bindings.GetBindingAt("test.nl", 12, FindColumn(source, 12, "Person"));
        Assert.NotNull(arrayPerson);
        Assert.Equal("Person", arrayPerson!.Name);
        Assert.Equal(2, arrayPerson.Line);

        var boxUse = bindings.GetBindingAt("test.nl", 13, FindColumn(source, 13, "Box"));
        Assert.NotNull(boxUse);
        Assert.Equal("Box", boxUse!.Name);
        Assert.Equal(6, boxUse.Line);

        var genericPerson = bindings.GetBindingAt("test.nl", 13, FindColumn(source, 13, "Person"));
        Assert.NotNull(genericPerson);
        Assert.Equal("Person", genericPerson!.Name);
        Assert.Equal(2, genericPerson.Line);

        var functionPerson = bindings.GetBindingAt("test.nl", 14, FindColumn(source, 14, "Person"));
        Assert.NotNull(functionPerson);
        Assert.Equal("Person", functionPerson!.Name);
        Assert.Equal(2, functionPerson.Line);
    }
}
