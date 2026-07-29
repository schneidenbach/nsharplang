using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Columnar;

namespace NSharpLang.Tests;

public class LocalFunctionTests
{
    private static CompilationUnit Parse(string source)
    {
        var result = ColumnarParserRecovery.ParseFileAst(source, "test.nl");
        return result.CompilationUnit!; // Tests expect valid syntax
    }

    // Parser Tests
    [Fact]
    public void TestLocalFunctionBasic()
    {
        var source = @"
func Outer(): void {
    func Inner(): int {
        return 42
    }
}";
        var ast = Parse(source);

        Assert.Single(ast.Declarations);
        var outerFunc = Assert.IsType<FunctionDeclaration>(ast.Declarations[0]);
        Assert.Equal("Outer", outerFunc.Name);
        Assert.NotNull(outerFunc.Body);
        Assert.Single(outerFunc.Body!.Statements);
        var localFunc = Assert.IsType<LocalFunctionStatement>(outerFunc.Body.Statements[0]);
        Assert.Equal("Inner", localFunc.Function.Name);
    }

    [Fact]
    public void TestStaticLocalFunction()
    {
        var source = @"
func Outer(): void {
    static func Inner(): int {
        return 42
    }
}";
        var ast = Parse(source);

        var outerFunc = Assert.IsType<FunctionDeclaration>(ast.Declarations[0]);
        var localFunc = Assert.IsType<LocalFunctionStatement>(outerFunc.Body!.Statements[0]);
        Assert.True(localFunc.Function.Modifiers.HasFlag(Modifiers.Static));
    }

    [Fact]
    public void TestExpressionBodiedLocalFunction()
    {
        var source = @"
func Outer(): void {
    func Inner(x: int) => x * 2
}";
        var ast = Parse(source);

        var outerFunc = Assert.IsType<FunctionDeclaration>(ast.Declarations[0]);
        var localFunc = Assert.IsType<LocalFunctionStatement>(outerFunc.Body!.Statements[0]);
        Assert.NotNull(localFunc.Function.ExpressionBody);
        Assert.Null(localFunc.Function.Body);
    }

    [Fact]
    public void TestAsyncLocalFunction()
    {
        var source = @"
func Outer(): void {
    async func Inner(): string {
        return ""test""
    }
}";
        var ast = Parse(source);

        var outerFunc = Assert.IsType<FunctionDeclaration>(ast.Declarations[0]);
        var localFunc = Assert.IsType<LocalFunctionStatement>(outerFunc.Body!.Statements[0]);
        Assert.True(localFunc.Function.Modifiers.HasFlag(Modifiers.Async));
    }

}
