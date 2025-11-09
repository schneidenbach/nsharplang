using System;
using System.IO;
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

    [Fact]
    public void ILCompiler_CanCompileVariableAssignment()
    {
        var source = @"
func testAssignment(): int {
    x := 5
    x = 10
    return x
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileCompoundAssignment()
    {
        var source = @"
func testCompoundAssignment(): int {
    x := 5
    x += 3
    x -= 2
    x *= 2
    x /= 3
    return x
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_SavesAssemblyToDisk()
    {
        var outputPath = Path.Combine(Path.GetTempPath(), "ILCompilerTest_" + Guid.NewGuid() + ".dll");
        try
        {
            var source = @"
func add(x: int, y: int): int {
    return x + y
}";
            var compilationUnit = Parse(source);
            var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", outputPath);

            compiler.Compile();

            // Verify that the file was created
            Assert.True(File.Exists(outputPath), $"Assembly file should exist at {outputPath}");

            // Verify that the file has content
            var fileInfo = new FileInfo(outputPath);
            Assert.True(fileInfo.Length > 0, "Assembly file should not be empty");
        }
        finally
        {
            // Clean up
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    [Fact]
    public void ILCompiler_CanCompileSimpleClass()
    {
        var source = @"
class Point {
    X: int
    Y: int
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassWithConstructor()
    {
        var source = @"
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassWithMethod()
    {
        var source = @"
class Calculator {
    func Add(x: int, y: int): int {
        return x + y
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassInstantiation()
    {
        var source = @"
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }
}

func main() {
    p := new Point(3, 4)
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileFieldAccess()
    {
        var source = @"
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }
}

func main() {
    p := new Point(3, 4)
    x := p.X
    y := p.Y
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileInstanceMethodCall()
    {
        var source = @"
class Calculator {
    func Add(x: int, y: int): int {
        return x + y
    }
}

func main(): int {
    calc := new Calculator()
    return calc.Add(5, 3)
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileComplexClassProgram()
    {
        var source = @"
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }

    func DistanceSquared(): int {
        return this.X * this.X + this.Y * this.Y
    }
}

func main() {
    p := new Point(3, 4)
    dist := p.DistanceSquared()
    print dist
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileStruct()
    {
        var source = @"
struct Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }

    func Sum(): int {
        return this.X + this.Y
    }
}

func main(): int {
    p := new Point(3, 4)
    return p.Sum()
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }
}
