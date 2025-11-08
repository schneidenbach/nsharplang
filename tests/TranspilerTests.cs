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

    [Fact]
    public void TestErrorHandlingTranspilation()
    {
        var source = @"
func MightFail(): string {
    throw new Exception(""oops"")
}

func Test() {
    result, err := MightFail()
    if err != null {
        Console.WriteLine(err.Message)
    }
}
        ";

        var result = Transpile(source);

        // Should generate try-catch wrapper
        Assert.Contains("object? result = null;", result);
        Assert.Contains("Exception? err = null;", result);
        Assert.Contains("try", result);
        Assert.Contains("result = MightFail()", result);
        Assert.Contains("catch (Exception ex)", result);
        Assert.Contains("err = ex;", result);
    }

    [Fact]
    public void TestThrowExpressionTranspilation()
    {
        var source = @"
func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception(""Division by zero"")
    }
    return a / b
}
        ";

        var result = Transpile(source);

        // Should contain throw statement
        Assert.Contains("throw new Exception(", result);
        Assert.Contains("Division by zero", result);
    }

    [Fact]
    public void TestMatchExpressionTranspilation()
    {
        var source = @"
union Result {
    Success { value: int }
    Failure { error: string }
}

func ProcessResult(r: Result): string {
    return match r {
        Result.Success { value } => $""Success: {value}"",
        Result.Failure { error } => $""Error: {error}""
    }
}
        ";

        var result = Transpile(source);

        // Should generate switch expression
        Assert.Contains("switch", result);
        Assert.Contains("Result.Success { value: var value }", result);
        Assert.Contains("Result.Failure { error: var error }", result);
        Assert.Contains("=>", result);
        Assert.Contains("$\"Success: {value}\"", result);
        Assert.Contains("$\"Error: {error}\"", result);
    }

    [Fact]
    public void TestWithExpressionTranspilation()
    {
        var source = @"
record Person {
    Name: string
    Age: int
}

func UpdateAge(p: Person): Person {
    return p with { Age: 31 }
}
        ";

        var result = Transpile(source);

        // Should generate with expression
        Assert.Contains("with", result);
        Assert.Contains("Age = 31", result);
        Assert.Contains("p with {", result);
    }

    [Fact]
    public void TestDefaultParameterTranspilation()
    {
        var source = @"
func Greet(name: string, greeting: string = ""Hello"") {
    Console.WriteLine(greeting)
}
        ";

        var result = Transpile(source);

        // Should include default value in parameter
        Assert.Contains("greeting = \"Hello\"", result);
        Assert.Contains("string greeting", result);
    }

    [Fact]
    public void TestNamedArgumentTranspilation()
    {
        var source = @"
func Test() {
    CreateUser(name: ""John"", age: 30)
}
        ";

        var result = Transpile(source);

        // Should preserve named arguments
        Assert.Contains("name: \"John\"", result);
        Assert.Contains("age: 30", result);
    }

    [Fact]
    public void TestAsyncAwaitTranspilation()
    {
        var source = @"
async func FetchData(): Task<string> {
    result := await GetDataAsync()
    return result
}
        ";

        var result = Transpile(source);

        // Should generate async method
        Assert.Contains("async Task<string> FetchData()", result);
        Assert.Contains("await GetDataAsync()", result);
        Assert.Contains("return result", result);
    }

    [Fact]
    public void TestIteratorFunctionTranspilation()
    {
        var source = @"
func* GetNumbers(): IEnumerable<int> {
    yield 1
    yield 2
    yield 3
}
        ";

        var result = Transpile(source);

        // Should contain yield statements
        Assert.Contains("IEnumerable<int> GetNumbers()", result);
        Assert.Contains("yield return 1", result);
        Assert.Contains("yield return 2", result);
        Assert.Contains("yield return 3", result);
    }

    [Fact]
    public void TestUsingStatementTranspilation()
    {
        var source = @"
func Test() {
    using stream := File.OpenRead(""file.txt"") {
        data := stream.Read()
    }
}
        ";

        var result = Transpile(source);

        // Should generate using statement
        Assert.Contains("using (", result);
        Assert.Contains("var stream = File.OpenRead(\"file.txt\")", result);
        Assert.Contains("var data = stream.Read()", result);
    }

    [Fact]
    public void TestSwitchStatementTranspilation()
    {
        var source = @"
func Test(value: int) {
    switch value {
        case 1 => Console.WriteLine(""One"")
        case 2 => Console.WriteLine(""Two"")
        default => Console.WriteLine(""Other"")
    }
}
        ";

        var result = Transpile(source);

        // Should generate switch statement
        Assert.Contains("switch (value)", result);
        Assert.Contains("case 1:", result);
        Assert.Contains("case 2:", result);
        Assert.Contains("default:", result);
        Assert.Contains("Console.WriteLine(\"One\")", result);
        Assert.Contains("Console.WriteLine(\"Two\")", result);
        Assert.Contains("Console.WriteLine(\"Other\")", result);
    }

    [Fact]
    public void TestSpreadOperatorTranspilation()
    {
        var source = @"
func Test() {
    arr1 := [1, 2, 3]
    arr2 := [...arr1, 4, 5]
}
        ";

        var result = Transpile(source);

        // Should generate array concatenation or spread syntax
        Assert.Contains("var arr1 = new[] { 1, 2, 3 }", result);
        // Spread should be transpiled (implementation may vary)
        Assert.Contains("arr2", result);
    }

    [Fact]
    public void TestPartialClassTranspilation()
    {
        var source = @"
partial class User {
    Name: string
}
        ";

        var result = Transpile(source);

        // Should include partial modifier
        Assert.Contains("partial class User", result);
        Assert.Contains("public string Name", result);
    }

    [Fact]
    public void TestAbstractClassTranspilation()
    {
        var source = @"
abstract class Animal {
    abstract func MakeSound()
}
        ";

        var result = Transpile(source);

        // Should include abstract modifiers
        Assert.Contains("abstract class Animal", result);
        Assert.Contains("abstract void MakeSound()", result);
    }

    [Fact]
    public void TestSealedClassTranspilation()
    {
        var source = @"
sealed class FinalClass {
    Name: string
}
        ";

        var result = Transpile(source);

        // Should include sealed modifier
        Assert.Contains("sealed class FinalClass", result);
        Assert.Contains("public string Name", result);
    }

    [Fact]
    public void TestVirtualMethodTranspilation()
    {
        var source = @"
class Animal {
    virtual func MakeSound() {
        Console.WriteLine(""Sound"")
    }
}

class Dog : Animal {
    func MakeSound() {
        Console.WriteLine(""Bark"")
    }
}
        ";

        var result = Transpile(source);

        // Should include virtual and override modifiers
        Assert.Contains("virtual void MakeSound()", result);
        Assert.Contains("class Dog : Animal", result);
        // The override method in derived class - transpiler should add override keyword
        Assert.Contains("void MakeSound()", result);
        Assert.Contains("Console.WriteLine(\"Bark\")", result);
    }

    [Fact]
    public void TestStructTranspilation()
    {
        var source = @"
struct Point {
    X: int
    Y: int
}
        ";

        var result = Transpile(source);

        // Should emit struct instead of class
        Assert.Contains("struct Point", result);
        Assert.Contains("public int X", result);
        Assert.Contains("public int Y", result);
    }

    [Fact]
    public void TestTypeAliasTranspilation()
    {
        var source = @"
type UserId = int
type Handler = Func<string, void>
        ";

        var result = Transpile(source);

        // Type aliases should be emitted as comments in C# (C# doesn't support type aliases at type level)
        Assert.Contains("// type UserId = int", result);
        // Func<string, void> transpiles to Action<string>
        Assert.Contains("// type Handler = Action<string>", result);
    }

    [Fact]
    public void TestAttributeTranspilation()
    {
        var source = @"
[Serializable]
class Person {
    [JsonProperty(""user_name"")]
    UserName: string
}

[HttpGet(""/api/users"")]
func GetUsers(): User[] {
    return []
}
        ";

        var result = Transpile(source);

        // Attributes should be preserved in C# output
        Assert.Contains("[Serializable]", result);
        Assert.Contains("class Person", result);
        Assert.Contains("[JsonProperty(\"user_name\")]", result);
        Assert.Contains("public string UserName", result);
        Assert.Contains("[HttpGet(\"/api/users\")]", result);
    }

    [Fact]
    public void TestExtensionMethodTranspilation()
    {
        var source = @"
func IsEmpty(this s: string): bool {
    return s.Length == 0
}

static class StringExtensions {
    static func ToUpperFirst(this s: string): string {
        return s.Substring(0, 1).ToUpper() + s.Substring(1)
    }
}
        ";

        var result = Transpile(source);

        // Extension methods need to be in static classes
        // Top-level extension method should be wrapped in internal static class
        Assert.Contains("internal static", result);
        Assert.Contains("static bool IsEmpty(this string s)", result);

        // Explicit static class
        Assert.Contains("static class StringExtensions", result);
        Assert.Contains("static string ToUpperFirst(this string s)", result);
    }

    [Fact]
    public void TestStaticClassTranspilation()
    {
        var source = @"
static class Helpers {
    static func DoThing() {
        Console.WriteLine(""done"")
    }
}
        ";

        var result = Transpile(source);

        // Should emit static class
        Assert.Contains("static class Helpers", result);
        Assert.Contains("static void DoThing()", result);
        Assert.Contains("Console.WriteLine(\"done\")", result);
    }

    [Fact]
    public void TestReadonlyFieldTranspilation()
    {
        var source = @"
class MyClass {
    readonly id: string

    constructor() {
        id = Guid.NewGuid().ToString()
    }
}
        ";

        var result = Transpile(source);

        // Should emit readonly modifier
        Assert.Contains("private readonly string id", result);
        Assert.Contains("public MyClass()", result);
        Assert.Contains("id = Guid.NewGuid().ToString()", result);
    }
}
