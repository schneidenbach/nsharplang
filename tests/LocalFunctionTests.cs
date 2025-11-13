using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Tests;

public class LocalFunctionTests
{
    private static CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
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
    func async Inner(): string {
        return ""test""
    }
}";
        var ast = Parse(source);

        var outerFunc = Assert.IsType<FunctionDeclaration>(ast.Declarations[0]);
        var localFunc = Assert.IsType<LocalFunctionStatement>(outerFunc.Body!.Statements[0]);
        Assert.True(localFunc.Function.Modifiers.HasFlag(Modifiers.Async));
    }

    // Transpiler Tests
    [Fact]
    public void TestLocalFunctionTranspilation()
    {
        var source = @"
func ProcessData(items: int[]): int[] {
    func IsValid(value: int): bool {
        return value > 0 && value < 100
    }

    return items.Where(IsValid).ToArray()
}";
        var ast = Parse(source);
        var analyzer = new Analyzer();
        analyzer.Analyze(ast);
        var transpiler = new Transpiler(ast, null);
        var output = transpiler.Transpile();

        Assert.Contains("bool IsValid(int value)", output);
        Assert.Contains("value > 0", output);
        Assert.Contains("value < 100", output);
    }

    [Fact]
    public void TestStaticLocalFunctionTranspilation()
    {
        var source = @"
func ProcessData(): void {
    static func Helper(): int {
        return 42
    }
}";
        var ast = Parse(source);
        var analyzer = new Analyzer();
        analyzer.Analyze(ast);
        var transpiler = new Transpiler(ast, null);
        var output = transpiler.Transpile();

        Assert.Contains("static int Helper()", output);
    }

    [Fact]
    public void TestExpressionBodiedLocalFunctionTranspilation()
    {
        var source = @"
func ProcessData(): void {
    func Double(x: int): int => x * 2
}";
        var ast = Parse(source);
        var analyzer = new Analyzer();
        analyzer.Analyze(ast);
        var transpiler = new Transpiler(ast, null);
        var output = transpiler.Transpile();

        Assert.Contains("int Double(int x)", output);
        Assert.Contains("x * 2", output);
    }
}
