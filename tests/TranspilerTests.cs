using System;
using System.Linq;
using NewCLILang.Compiler;
using Xunit;

namespace NewCLILang.Tests;

public class TranspilerTests
{
    private static string Transpile(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var cu = parser.ParseCompilationUnit();
        var transpiler = new Transpiler(cu);
        return transpiler.Transpile();
    }

    [Fact]
    public void TestIndexerTranspilation()
    {
        var source = @"
class Dictionary<K, V> {
    storage: Map<K, V>

    func this[key: K]: V {
        get { return storage[key] }
        set { storage[key] = value }
    }
}
        ";

        var result = Transpile(source);

        // Verify the output contains the indexer syntax
        Assert.Contains("this[", result);
        Assert.Contains("get", result);
        Assert.Contains("set", result);
        Assert.Contains("K key", result);
    }

    [Fact]
    public void TestSimpleFunctionTranspilation()
    {
        var source = @"
func Add(x: int, y: int): int {
    return x + y
}
        ";

        var result = Transpile(source);

        Assert.Contains("int Add(int x, int y)", result);
        Assert.Contains("return", result);
        Assert.Contains("x + y", result);
    }

    [Fact]
    public void TestClassTranspilation()
    {
        var source = @"
class Person {
    Name: string
    age: int
}
        ";

        var result = Transpile(source);

        Assert.Contains("class Person", result);
        Assert.Contains("public string Name", result);
        Assert.Contains("private int age", result);
    }

    [Fact]
    public void TestInterpolatedStringTranspilation()
    {
        var source = @"
func Greet(name: string): string {
    return $""Hello, {name}!""
}
        ";

        var result = Transpile(source);

        Assert.Contains("string Greet(string name)", result);
        Assert.Contains("$\"Hello, {name}!\"", result);
    }

    [Fact]
    public void TestImmutableArrayTranspilation()
    {
        var source = @"
func GetNumbers(): int[] {
    return immutable [1, 2, 3]
}
        ";

        var result = Transpile(source);

        Assert.Contains("int[] GetNumbers()", result);
        // Immutable arrays should use collection expression syntax
        Assert.Contains("[1, 2, 3]", result);
        Assert.DoesNotContain("new[]", result);
    }

    [Fact]
    public void TestMutableArrayTranspilation()
    {
        var source = @"
func GetNumbers(): int[] {
    return [1, 2, 3]
}
        ";

        var result = Transpile(source);

        Assert.Contains("int[] GetNumbers()", result);
        // Mutable arrays should use new[] syntax
        Assert.Contains("new[] { 1, 2, 3 }", result);
    }

    [Fact]
    public void TestConstructorTranspilation()
    {
        var source = @"
class Person {
    Name: string
    Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }
}
        ";

        var result = Transpile(source);

        Assert.Contains("class Person", result);
        // Constructor should use class name, not 'ctor'
        Assert.Contains("public Person(string name, int age)", result);
        Assert.DoesNotContain("ctor(", result);
        Assert.Contains("Name = name", result);
        Assert.Contains("Age = age", result);
    }

    [Fact]
    public void TestPropertyGetSetTranspilation()
    {
        var source = @"
class Counter {
    count: int

    Count: int {
        get { return count }
        set { count = value }
    }
}
        ";

        var result = Transpile(source);

        Assert.Contains("class Counter", result);
        Assert.Contains("private int count", result);
        Assert.Contains("public int Count", result);
        Assert.Contains("get", result);
        Assert.Contains("set", result);
        Assert.Contains("return count", result);
        Assert.Contains("count = value", result);
    }

    [Fact]
    public void TestTupleDeconstructionTranspilation()
    {
        var source = @"
func GetPair(): (int, string) {
    return (42, ""hello"")
}

func Test() {
    (x, y) := GetPair()
}
        ";

        var result = Transpile(source);

        Assert.Contains("(x, y) = GetPair()", result);
    }
}
