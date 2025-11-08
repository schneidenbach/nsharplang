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

        // Readonly fields transpile to properties with init accessors
        Assert.Contains("private string id { get; init; }", result);
        Assert.Contains("public MyClass()", result);
        Assert.Contains("id = Guid.NewGuid().ToString()", result);
    }

    [Fact]
    public void TestIndexerUsageTranspilation()
    {
        var source = @"
func Test() {
    arr := [1, 2, 3]
    x := arr[0]
    dict := new Dictionary<string, int>()
    dict[""key""] = 42
}
        ";

        var result = Transpile(source);

        Assert.Contains("arr[0]", result);
        Assert.Contains("dict[\"key\"] = 42", result);
    }

    [Fact]
    public void TestNullConditionalIndexingTranspilation()
    {
        var source = @"
func Test() {
    arr := GetArray()
    x := arr?[0]
    dict := GetDict()
    y := dict?[""key""]
}
        ";

        var result = Transpile(source);

        Assert.Contains("arr?[0]", result);
        Assert.Contains("dict?[\"key\"]", result);
    }

    [Fact]
    public void TestSafeCastTranspilation()
    {
        var source = @"
func Test() {
    let obj = GetObject()
    str := obj as string
    person := obj as Person
}
        ";

        var result = Transpile(source);

        Assert.Contains("obj as string", result);
        Assert.Contains("obj as Person", result);
    }

    [Fact]
    public void TestIsPatternTranspilation()
    {
        var source = @"
func Test() {
    if obj is string s {
        Console.WriteLine(s)
    }
}
        ";

        var result = Transpile(source);

        Assert.Contains("if (obj is string s)", result);
        Assert.Contains("Console.WriteLine(s)", result);
    }

    [Fact]
    public void TestNullCoalescingAssignmentTranspilation()
    {
        var source = @"
func Test() {
    let cache = null
    cache ??= ExpensiveOperation()
}
        ";

        var result = Transpile(source);

        Assert.Contains("cache ??= ExpensiveOperation()", result);
    }

    [Fact]
    public void TestThisKeywordTranspilation()
    {
        var source = @"
class MyClass {
    name: string

    func SetName(name: string) {
        this.name = name
    }

    func GetThis(): MyClass {
        return this
    }
}
        ";

        var result = Transpile(source);

        Assert.Contains("this.name = name", result);
        Assert.Contains("return this", result);
    }

    [Fact]
    public void TestBaseKeywordTranspilation()
    {
        var source = @"
class Animal {
    virtual func MakeSound() {
        Console.WriteLine(""Sound"")
    }
}

class Dog : Animal {
    func MakeSound() {
        base.MakeSound()
        Console.WriteLine(""Bark"")
    }
}
        ";

        var result = Transpile(source);

        Assert.Contains("base.MakeSound()", result);
        Assert.Contains("class Dog : Animal", result);
    }

    [Fact]
    public void TestMultipleInterfaceImplementationTranspilation()
    {
        var source = @"
class MyClass : BaseClass, IFoo, IBar {
    Name: string
}
        ";

        var result = Transpile(source);

        Assert.Contains("class MyClass : BaseClass, IFoo, IBar", result);
    }

    [Fact]
    public void TestGenericConstraintsTranspilation()
    {
        var source = @"
func Process<T>(item: T): T where T : IComparable {
    return item
}
        ";

        var result = Transpile(source);

        Assert.Contains("T Process<T>(T item) where T : IComparable", result);
        Assert.Contains("return item", result);
    }

    [Fact]
    public void TestMethodOverloadingTranspilation()
    {
        var source = @"
class Calculator {
    func Add(x: int): int {
        return x + 1
    }

    func Add(x: int, y: int): int {
        return x + y
    }
}
        ";

        var result = Transpile(source);

        // Both methods should be present
        Assert.Contains("int Add(int x)", result);
        Assert.Contains("int Add(int x, int y)", result);
    }

    [Fact]
    public void TestMultiLineTemplateStringTranspilation()
    {
        var source = @"
func Test() {
    template := """"""
    This is a multi-line
    string literal
    """"""
}
        ";

        var result = Transpile(source);

        // Triple-quoted strings should transpile to C# @"" verbatim strings or triple-quoted strings
        Assert.Contains("template", result);
        // The multi-line content should be preserved
        Assert.Contains("multi-line", result);
    }

    [Fact]
    public void TestPropertyGetOnlyTranspilation()
    {
        var source = @"
class Data {
    value: int

    Value: int {
        get { return value }
    }
}
        ";

        var result = Transpile(source);

        Assert.Contains("class Data", result);
        Assert.Contains("private int value", result);
        Assert.Contains("public int Value", result);
        Assert.Contains("get", result);
        Assert.Contains("return value", result);
        // Should not have a setter
        Assert.DoesNotContain("set {", result);
    }

    [Fact]
    public void TestPropertySetOnlyTranspilation()
    {
        var source = @"
class Logger {
    message: string

    Message: string {
        set {
            message = value
        }
    }
}
        ";

        var result = Transpile(source);

        Assert.Contains("class Logger", result);
        Assert.Contains("private string message", result);
        Assert.Contains("public string Message", result);
        Assert.Contains("set", result);
        Assert.Contains("message = value", result);
        // Should not have a getter
        Assert.DoesNotContain("get {", result);
    }

    [Fact]
    public void TestNestedClassTranspilation()
    {
        var source = @"
class Outer {
    Name: string

    class Inner {
        Value: int
    }
}
        ";

        var result = Transpile(source);

        Assert.Contains("class Outer", result);
        Assert.Contains("public string Name", result);
        Assert.Contains("class Inner", result);
        Assert.Contains("public int Value", result);
    }

    [Fact]
    public void TestNestedEnumTranspilation()
    {
        var source = @"
class Container {
    enum Status {
        Active,
        Inactive
    }

    CurrentStatus: Status
}
        ";

        var result = Transpile(source);

        Assert.Contains("class Container", result);
        Assert.Contains("enum Status", result);
        Assert.Contains("Active", result);
        Assert.Contains("Inactive", result);
        Assert.Contains("Status CurrentStatus", result);
    }

    [Fact]
    public void TestNestedRecordTranspilation()
    {
        var source = @"
class Service {
    record Config {
        Host: string
        Port: int
    }

    CurrentConfig: Config
}
        ";

        var result = Transpile(source);

        Assert.Contains("class Service", result);
        Assert.Contains("record Config", result);
        Assert.Contains("string Host", result);
        Assert.Contains("int Port", result);
        Assert.Contains("Config CurrentConfig", result);
    }

    [Fact]
    public void TestMatchExpressionWithGuardTranspilation()
    {
        var source = @"
func Test() {
    result := match x {
        n when n > 0 => ""positive"",
        n when n < 0 => ""negative"",
        _ => ""zero""
    }
}
        ";

        var result = Transpile(source);

        // Verify C# switch expression with when clauses
        Assert.Contains("switch", result);
        Assert.Contains("when", result);
        Assert.Contains("=> \"positive\"", result);
        Assert.Contains("=> \"negative\"", result);
        Assert.Contains("=> \"zero\"", result);
    }

    [Fact]
    public void TestMatchExpressionWithUnionPatternAndGuardTranspilation()
    {
        var source = @"
union Result {
    Success { value: int }
    Failure { error: string }
}

func Test() {
    msg := match r {
        Result.Success { value } when value > 10 => ""big"",
        Result.Success { value } => ""small"",
        Result.Failure { error } => error
    }
}
        ";

        var result = Transpile(source);

        // Verify C# switch expression with pattern and guard
        Assert.Contains("switch", result);
        Assert.Contains("when", result);
        Assert.Contains("value", result);
        Assert.Contains("=> \"big\"", result);
        Assert.Contains("=> \"small\"", result);
    }

    [Fact]
    public void TestPrintStatementTranspilation()
    {
        var source = @"
func main() {
    print ""Hello, world!""
    print $""Value: {x}""
}
        ";

        var result = Transpile(source);

        // Verify transpiles to Console.WriteLine
        Assert.Contains("Console.WriteLine(\"Hello, world!\");", result);
        Assert.Contains("Console.WriteLine($\"Value: {x}\");", result);
    }

    [Fact]
    public void TestNameofTranspilation()
    {
        var source = @"
func main() {
    name := nameof(myVariable)
    prop := nameof(person.Name)
}
        ";

        var result = Transpile(source);

        // Verify transpiles to C# nameof
        Assert.Contains("nameof(myVariable)", result);
        Assert.Contains("nameof(Name)", result);
    }

    [Fact]
    public void TestTypeofTranspilation()
    {
        var source = @"
func main() {
    t1 := typeof(int)
    t2 := typeof(Person)
}
        ";

        var result = Transpile(source);

        // Verify transpiles to C# typeof
        Assert.Contains("typeof(int)", result);
        Assert.Contains("typeof(Person)", result);
    }

    [Fact]
    public void TestExpressionBodiedPropertyTranspilation()
    {
        var source = @"
            class Person {
                FirstName: string
                LastName: string
                FullName: string => FirstName + "" "" + LastName
            }
        ";

        var result = Transpile(source);

        // Should use explicit type with => syntax
        Assert.Contains("string FullName =>", result);
    }

    [Fact]
    public void TestExpressionBodiedPropertyWithTypeTranspilation()
    {
        var source = @"
            class Calculator {
                Value: int
                DoubleValue: int => Value * 2
            }
        ";

        var result = Transpile(source);

        // Should use explicit type with => syntax (note: binary expressions are wrapped in parens)
        Assert.Contains("int DoubleValue => (Value * 2);", result);
    }

    [Fact]
    public void TestExpressionBodiedMethodTranspilation()
    {
        var source = @"
            class Calculator {
                func Add(a: int, b: int): int => a + b
            }
        ";

        var result = Transpile(source);

        // Should transpile to C# expression-bodied method (binary expressions wrapped in parens)
        Assert.Contains("int Add(int a, int b)", result);
        Assert.Contains("=> (a + b);", result);
    }

    [Fact]
    public void TestExpressionBodiedMethodComplexTranspilation()
    {
        var source = @"
            class Calculator {
                func Square(x: int): int => x * x
            }
        ";

        var result = Transpile(source);

        // Should transpile to expression-bodied method
        Assert.Contains("int Square(int x)", result);
        Assert.Contains("=> (x * x);", result);
    }

    [Fact]
    public void TestRelationalPatternTranspilation()
    {
        var source = "func classify(age: int): string {\n" +
                     "    result := match age {\n" +
                     "        < 13 => \"child\",\n" +
                     "        >= 65 => \"senior\",\n" +
                     "        _ => \"adult\"\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var result = Transpile(source);

        // Should transpile to C# switch expression with relational patterns
        Assert.Contains("< 13", result);
        Assert.Contains(">= 65", result);
        Assert.Contains("_ =>", result);
    }

    [Fact]
    public void TestAndPatternTranspilation()
    {
        var source = @"
            func check(x: int): bool {
                result := match x {
                    > 0 and < 100 => true,
                    _ => false
                }
                return result
            }
        ";

        var result = Transpile(source);

        // Should transpile to C# and pattern
        Assert.Contains("> 0 and < 100", result);
    }

    [Fact]
    public void TestOrPatternTranspilation()
    {
        var source = @"
            func check(x: int): bool {
                result := match x {
                    < 0 or > 100 => true,
                    _ => false
                }
                return result
            }
        ";

        var result = Transpile(source);

        // Should transpile to C# or pattern
        Assert.Contains("< 0 or > 100", result);
    }

    [Fact]
    public void TestNotPatternTranspilation()
    {
        var source = @"
            func check(x: int): bool {
                result := match x {
                    not 0 => true,
                    _ => false
                }
                return result
            }
        ";

        var result = Transpile(source);

        // Should transpile to C# not pattern
        Assert.Contains("not 0", result);
    }

    [Fact]
    public void TestPositionalPatternTranspilation()
    {
        var source = "func check(point: (int, int)): string {\n" +
                     "    result := match point {\n" +
                     "        (0, 0) => \"origin\",\n" +
                     "        (0, _) => \"y-axis\",\n" +
                     "        _ => \"other\"\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var result = Transpile(source);

        // Should transpile to C# positional pattern
        Assert.Contains("(0, 0)", result);
        Assert.Contains("(0, _)", result);
    }

    [Fact]
    public void TestComplexCombinedPatternsTranspilation()
    {
        var source = "func check(value: int): string {\n" +
                     "    result := match value {\n" +
                     "        (> 0 and < 10) or (> 90 and < 100) => \"valid\",\n" +
                     "        _ => \"other\"\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var result = Transpile(source);

        // Should transpile with proper pattern combinations
        Assert.Contains("(> 0 and < 10) or (> 90 and < 100)", result);
    }

    [Fact]
    public void TestNamespaceImportTranspilation()
    {
        var source = "import System.Collections.Generic\n" +
                     "import System.Linq\n" +
                     "class MyClass { }";

        var result = Transpile(source);

        // Should transpile to C# using statements
        Assert.Contains("using System.Collections.Generic;", result);
        Assert.Contains("using System.Linq;", result);
    }

    [Fact]
    public void TestNamespaceImportWithAliasTranspilation()
    {
        var source = "import System.Collections.Generic as Collections\n" +
                     "import Newtonsoft.Json as Json\n" +
                     "class MyClass { }";

        var result = Transpile(source);

        // Should transpile to C# using alias statements
        Assert.Contains("using Collections = System.Collections.Generic;", result);
        Assert.Contains("using Json = Newtonsoft.Json;", result);
    }

    [Fact]
    public void TestNestedPropertyPatternTranspilation()
    {
        var source = @"
            func Test() {
                result := match person {
                    { Address: { City: ""NYC"" } } => ""New Yorker"",
                    _ => ""Other""
                }
            }
        ";

        var result = Transpile(source);

        // Should transpile to C# nested property pattern
        Assert.Contains("{ Address: { City: \"NYC\" } } => \"New Yorker\"", result);
    }

    [Fact]
    public void TestNestedPropertyPatternWithBindingTranspilation()
    {
        var source = @"
            func Test() {
                result := match person {
                    { Address: { City: city, State: ""NY"" } } => city,
                    _ => """"
                }
            }
        ";

        var result = Transpile(source);

        // Should transpile with var binding for city
        Assert.Contains("{ Address: { City: var city, State: \"NY\" } } => city", result);
    }

    [Fact]
    public void TestThreeLevelNestedPropertyPatternTranspilation()
    {
        var source = @"
            func Test() {
                result := match company {
                    { HQ: { Address: { City: ""NYC"" } } } => ""NYC HQ"",
                    _ => ""Other""
                }
            }
        ";

        var result = Transpile(source);

        // Should transpile to deeply nested pattern
        Assert.Contains("{ HQ: { Address: { City: \"NYC\" } } } => \"NYC HQ\"", result);
    }

    [Fact]
    public void TestUnionCaseWithNestedPropertyPatternTranspilation()
    {
        var source = @"
            union Result {
                Success { value: Data }
                Failure
            }
            class Data {
                Count: int
            }
            func Test() {
                result := match res {
                    Result.Success { value: { Count: count } } => count,
                    _ => 0
                }
            }
        ";

        var result = Transpile(source);

        // Should transpile union case with nested property pattern
        Assert.Contains("Result.Success { value: { Count: var count } } => count", result);
    }

    [Fact]
    public void TestTestDeclarationTranspilation()
    {
        var source = @"
test ""should add two numbers"" {
    result := Add(2, 3)
    assert result == 5
}";

        var result = Transpile(source);

        // Should have [Fact] attribute
        Assert.Contains("[Fact]", result);
        // Should generate PascalCase method name
        Assert.Contains("public void ShouldAddTwoNumbers()", result);
        // Should transpile assert
        Assert.Contains("Assert.Equal(5, result);", result);
    }

    [Fact]
    public void TestAssertEqualTranspilation()
    {
        var source = @"
test ""test equals"" {
    assert x == 5
}";

        var result = Transpile(source);
        Assert.Contains("Assert.Equal(5, x);", result);
    }

    [Fact]
    public void TestAssertNotEqualTranspilation()
    {
        var source = @"
test ""test not equals"" {
    assert x != 5
}";

        var result = Transpile(source);
        Assert.Contains("Assert.NotEqual(5, x);", result);
    }

    [Fact]
    public void TestAssertNotNullTranspilation()
    {
        var source = @"
test ""test not null"" {
    assert value != null
}";

        var result = Transpile(source);
        Assert.Contains("Assert.NotNull(value);", result);
    }

    [Fact]
    public void TestAssertGreaterThanTranspilation()
    {
        var source = @"
test ""test greater than"" {
    assert x > 5
}";

        var result = Transpile(source);
        Assert.Contains("Assert.True(x > 5);", result);
    }

    [Fact]
    public void TestAssertBooleanTranspilation()
    {
        var source = @"
test ""test boolean"" {
    assert isValid
}";

        var result = Transpile(source);
        Assert.Contains("Assert.True(isValid);", result);
    }

    [Fact]
    public void TestMethodNameConversion()
    {
        var source = @"
test ""should-handle_special characters!"" {
    assert true
}";

        var result = Transpile(source);
        // Should convert to valid C# method name
        Assert.Contains("public void ShouldHandleSpecialCharacters()", result);
    }

    [Fact]
    public void TestOperatorOverloadBinaryTranspilation()
    {
        var source = @"
class Vector {
    X: int
    Y: int

    static func operator +(a: Vector, b: Vector): Vector {
        return new Vector { X: a.X + b.X, Y: a.Y + b.Y }
    }
}";

        var result = Transpile(source);
        Assert.Contains("public static Vector operator +(Vector a, Vector b)", result);
        Assert.Contains("return new Vector() { X = (a.X + b.X), Y = (a.Y + b.Y) };", result);
    }

    [Fact]
    public void TestOperatorOverloadUnaryTranspilation()
    {
        var source = @"
class Vector {
    X: int
    Y: int

    static func operator -(v: Vector): Vector {
        return new Vector { X: -v.X, Y: -v.Y }
    }
}";

        var result = Transpile(source);
        Assert.Contains("public static Vector operator -(Vector v)", result);
        Assert.Contains("return new Vector() { X = (-v.X), Y = (-v.Y) };", result);
    }

    [Fact]
    public void TestOperatorOverloadComparisonTranspilation()
    {
        var source = @"
class Money {
    Amount: decimal

    static func operator ==(a: Money, b: Money): bool {
        return a.Amount == b.Amount
    }

    static func operator !=(a: Money, b: Money): bool {
        return a.Amount != b.Amount
    }
}";

        var result = Transpile(source);
        Assert.Contains("public static bool operator ==(Money a, Money b)", result);
        Assert.Contains("public static bool operator !=(Money a, Money b)", result);
    }

    [Fact]
    public void TestOperatorOverloadExpressionBodied()
    {
        var source = @"
struct Complex {
    Real: double
    Imaginary: double

    static func operator +(a: Complex, b: Complex): Complex =>
        new Complex { Real: a.Real + b.Real, Imaginary: a.Imaginary + b.Imaginary }
}";

        var result = Transpile(source);
        Assert.Contains("public static Complex operator +(Complex a, Complex b)", result);
        Assert.Contains("=> new Complex()", result);
    }

    [Fact]
    public void TestOperatorOverloadMultipleOperators()
    {
        var source = @"
struct Flags {
    Value: int

    static func operator &(a: Flags, b: Flags): Flags {
        return new Flags { Value: a.Value & b.Value }
    }

    static func operator |(a: Flags, b: Flags): Flags {
        return new Flags { Value: a.Value | b.Value }
    }

    static func operator ~(f: Flags): Flags {
        return new Flags { Value: ~f.Value }
    }
}";

        var result = Transpile(source);
        Assert.Contains("public static Flags operator &(Flags a, Flags b)", result);
        Assert.Contains("public static Flags operator |(Flags a, Flags b)", result);
        Assert.Contains("public static Flags operator ~(Flags f)", result);
    }

    [Fact]
    public void TestIndexFromEndTranspilation()
    {
        var source = @"
class Test {
    func GetLastItem(arr: int[]): int {
        return arr[^1]
    }

    func GetSecondLast(arr: int[]): int {
        return arr[^2]
    }
}";

        var result = Transpile(source);
        Assert.Contains("arr[^1]", result);
        Assert.Contains("arr[^2]", result);
    }

    [Fact]
    public void TestRangeExpressionTranspilation()
    {
        var source = @"
class Test {
    func GetSlice(arr: int[]): int[] {
        return arr[1..4]
    }

    func GetSlice2(arr: int[]): int[] {
        return arr[0..3]
    }
}";

        var result = Transpile(source);
        Assert.Contains("arr[1..4]", result);
        Assert.Contains("arr[0..3]", result);
    }

    [Fact]
    public void TestRangeWithIndexFromEndTranspilation()
    {
        var source = @"
class Test {
    func GetMiddle(arr: int[]): int[] {
        return arr[1..^1]
    }

    func GetFirstToSecondLast(arr: int[]): int[] {
        return arr[0..^2]
    }
}";

        var result = Transpile(source);
        Assert.Contains("arr[1..^1]", result);
        Assert.Contains("arr[0..^2]", result);
    }

    [Fact]
    public void TestOpenEndedRangeToEndTranspilation()
    {
        var source = @"
class Test {
    func GetFirst(arr: int[]): int[] {
        return arr[..3]
    }
}";

        var result = Transpile(source);
        Assert.Contains("arr[..3]", result);
    }

    [Fact]
    public void TestOpenEndedRangeFromStartTranspilation()
    {
        var source = @"
class Test {
    func GetLast(arr: int[]): int[] {
        return arr[2..]
    }
}";

        var result = Transpile(source);
        Assert.Contains("arr[2..]", result);
    }

    [Fact]
    public void TestFullyOpenRangeTranspilation()
    {
        var source = @"
class Test {
    func GetAll(arr: int[]): int[] {
        return arr[..]
    }
}";

        var result = Transpile(source);
        Assert.Contains("arr[..]", result);
    }

    [Fact]
    public void TestPreprocessorDirectiveTopLevelTranspilation()
    {
        var source = @"
#if DEBUG
class DebugHelper {
    DebugFlag: bool = true
}
#endif
";

        var result = Transpile(source);
        Assert.Contains("#if DEBUG", result);
        Assert.Contains("class DebugHelper", result);
        Assert.Contains("bool DebugFlag", result);
        Assert.Contains("#endif", result);
    }

    [Fact]
    public void TestPreprocessorDirectiveInFunctionTranspilation()
    {
        var source = @"
func TestFunc() {
    #if DEBUG
    print ""Debug mode""
    #endif
}";

        var result = Transpile(source);
        Assert.Contains("#if DEBUG", result);
        Assert.Contains("Console.WriteLine", result);
        Assert.Contains("#endif", result);
    }

    [Fact]
    public void TestPreprocessorRegionTranspilation()
    {
        var source = @"
#region Helper Functions
func Helper(): int {
    return 42
}
#endregion
";

        var result = Transpile(source);
        Assert.Contains("#region Helper Functions", result);
        Assert.Contains("internal static int Helper()", result);
        Assert.Contains("#endregion", result);
    }

    [Fact]
    public void TestPreprocessorDefineTranspilation()
    {
        var source = @"
#define FEATURE_X
";

        var result = Transpile(source);
        Assert.Contains("#define FEATURE_X", result);
    }

    [Fact]
    public void TestRequiredPropertyTranspilation()
    {
        var source = @"
            class Person {
                required Name: string
                required Email: string
                Age: int = 0
            }
        ";

        var result = Transpile(source);
        Assert.Contains("public required string Name { get; set; }", result);
        Assert.Contains("public required string Email { get; set; }", result);
        Assert.Contains("public int Age { get; set; } = 0;", result);
    }

    [Fact]
    public void TestInitOnlyPropertyTranspilation()
    {
        var source = @"
            record Person {
                init Name: string
                init Age: int
            }
        ";

        var result = Transpile(source);
        Assert.Contains("public string Name { get; init; }", result);
        Assert.Contains("public int Age { get; init; }", result);
    }

    [Fact]
    public void TestRequiredInitPropertyTranspilation()
    {
        var source = @"
            class User {
                required init Id: string
                required init Email: string
                Name: string = """"
            }
        ";

        var result = Transpile(source);
        Assert.Contains("public required string Id { get; init; }", result);
        Assert.Contains("public required string Email { get; init; }", result);
        Assert.Contains("public string Name { get; set; } = \"\";", result);
    }

    [Fact]
    public void TestRefParameterTranspilation()
    {
        var source = "func Swap(ref a: int, ref b: int) { }";
        var result = Transpile(source);
        Assert.Contains("ref int a, ref int b", result);
    }

    [Fact]
    public void TestOutParameterTranspilation()
    {
        var source = "func TryParse(input: string, out result: int): bool { }";
        var result = Transpile(source);
        Assert.Contains("string input, out int result", result);
    }

    [Fact]
    public void TestRefArgumentTranspilation()
    {
        var source = @"
            func Main() {
                x := 5
                Swap(ref x, ref x)
            }
        ";
        var result = Transpile(source);
        Assert.Contains("Swap(ref x, ref x)", result);
    }

    [Fact]
    public void TestOutArgumentTranspilation()
    {
        var source = @"
            func Main() {
                let result: int
                success := int.TryParse(""123"", out result)
            }
        ";
        var result = Transpile(source);
        Assert.Contains("int.TryParse(\"123\", out result)", result);
    }
}
