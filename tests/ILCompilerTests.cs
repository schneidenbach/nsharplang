using System;
using System.Linq;
using System.Reflection;
using NewCLILang.Compiler;
using NewCLILang.Compiler.Ast;
using NewCLILang.Compiler.ILCompiler;
using Xunit;

namespace NewCLILang.Tests;

public class ILCompilerTests
{
    private CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        return parser.ParseCompilationUnit();
    }

    private object? CompileAndInvoke(string source, string functionName = "main", params object[] args)
    {
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Compile will create in-memory assembly
        compiler.Compile();

        // For now, we can't easily test the compiled assembly since it's in-memory only
        // and AssemblyBuilder.DefineDynamicAssembly with RunAndCollect doesn't allow easy invocation
        // We'll need to implement saving to disk first
        return null;
    }

    [Fact]
    public void ILCompiler_CanBeConstructed()
    {
        var source = "func main() { }";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        Assert.NotNull(compiler);
    }

    [Fact]
    public void ILCompiler_CanCompileEmptyFunction()
    {
        var source = "func main() { }";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileFunctionWithReturn()
    {
        var source = @"
func add(x: int, y: int): int {
    return x + y
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileVariableDeclaration()
    {
        var source = @"
func myFunc() {
    x := 5
    y := 10
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileBinaryExpression()
    {
        var source = @"
func calculate(): int {
    return 5 + 3
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompilePrintStatement()
    {
        var source = @"
func main() {
    print ""Hello from IL!""
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileIfStatement()
    {
        var source = @"
func checkValue(x: int): int {
    if x > 5 {
        return 10
    } else {
        return 0
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileWhileLoop()
    {
        var source = @"
func countTo10(): int {
    x := 0
    while x < 10 {
        x := x + 1
    }
    return x
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileComplexProgram()
    {
        var source = @"
func fibonacci(n: int): int {
    if n <= 1 {
        return n
    }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

func main() {
    result := fibonacci(10)
    print result
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }
}
