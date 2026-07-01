using System;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class AstNodeFinderTests
{
    private static CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var parser = new Parser(lexer.Tokenize(), "test.nl", source);
        var result = parser.ParseCompilationUnit();
        return result.CompilationUnit!;
    }

    [Fact]
    public void FindExpressionAtPosition_PrefersMemberAccessAtMemberCursor()
    {
        var source = "func main() {\n    value := user.Name\n}";
        var unit = Parse(source);
        var line = source.Split('\n')[1];
        var memberColumn = line.IndexOf("Name", StringComparison.Ordinal);

        var expression = AstNodeFinder.FindExpressionAtPosition(unit, 1, memberColumn);

        var memberAccess = Assert.IsType<MemberAccessExpression>(expression);
        Assert.Equal("Name", memberAccess.MemberName);
    }

    [Fact]
    public void FindExpressionAtPosition_ReturnsIncompleteMemberAccessAtDotCursor()
    {
        var source = "\nclass Person {\n    Name: string\n}\n\nfunc main(): void\n    let p = new Person()\n    p.";
        var unit = Parse(source);
        var line = source.Split('\n')[7];
        var dotColumn = line.IndexOf(".", StringComparison.Ordinal);

        var expression = AstNodeFinder.FindExpressionAtPosition(unit, 7, dotColumn + 1);

        var memberAccess = Assert.IsType<MemberAccessExpression>(expression);
        Assert.Equal("<error>", memberAccess.MemberName);
        var receiver = Assert.IsType<IdentifierExpression>(memberAccess.Object);
        Assert.Equal("p", receiver.Name);

        using var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        var analysis = analyzer.Analyze(unit, "test.nl", null, source);
        var receiverType = Assert.IsType<ClassTypeInfo>(analysis.SemanticModel.LookupIdentifier(receiver.Name));
        Assert.Contains(receiverType.DeclaredMembers, member => member.Name == "Name");
    }

    [Fact]
    public void FindExpressionAtPosition_ReturnsIncompleteMemberAccessForCompletionSource()
    {
        var source = @"
class Person {
    Name: string
    Age: int

    func Greet(): string {
        return ""Hello""
    }
}

func main(): void
    let p = new Person()
    p.";
        var unit = Parse(source);

        var expression = AstNodeFinder.FindExpressionAtPosition(unit, 12, 6);

        var memberAccess = Assert.IsType<MemberAccessExpression>(expression);
        Assert.Equal("<error>", memberAccess.MemberName);
        var receiver = Assert.IsType<IdentifierExpression>(memberAccess.Object);
        Assert.Equal("p", receiver.Name);

        using var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        var analysis = analyzer.Analyze(unit, "/test/nsharp-class.nl", "/test", source);
        var receiverType = Assert.IsType<ClassTypeInfo>(analysis.SemanticModel.LookupIdentifier(receiver.Name));
        Assert.Equal("Person", receiverType.Name);
        Assert.Contains(receiverType.DeclaredMembers, member => member.Name == "Name");
        Assert.Contains(receiverType.DeclaredMembers, member => member.Name == "Age");
        Assert.Contains(receiverType.DeclaredMembers, member => member.Name == "Greet");
    }

    [Fact]
    public void FindExpressionAtPosition_TraversesClassFunctionBodies()
    {
        var source = "class Person {\n    func Speak(): string {\n        return Name\n    }\n}";
        var unit = Parse(source);
        var line = source.Split('\n')[2];
        var nameColumn = line.IndexOf("Name", StringComparison.Ordinal);

        var expression = AstNodeFinder.FindExpressionAtPosition(unit, 2, nameColumn);

        var identifier = Assert.IsType<IdentifierExpression>(expression);
        Assert.Equal("Name", identifier.Name);
    }

    [Fact]
    public void FindExpressionAtPosition_PrefersCallArgumentAtArgumentCursor()
    {
        var source = "\nfunc main(): void\n    let count = 42\n    print(count)";
        var unit = Parse(source);
        var line = source.Split('\n')[3];
        var countColumn = line.IndexOf("count", StringComparison.Ordinal) + 1;

        var expression = AstNodeFinder.FindExpressionAtPosition(unit, 3, countColumn);

        var identifier = Assert.IsType<IdentifierExpression>(expression);
        Assert.Equal("count", identifier.Name);
    }
}
