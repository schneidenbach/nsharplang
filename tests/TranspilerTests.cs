using System;
using System.Linq;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class TranspilerTests
{
    private static string Transpile(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        var transpiler = new Transpiler(result.CompilationUnit!);
        return transpiler.Transpile();
    }

    private static string TranspileWithConfig(string source, ProjectConfig config)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        var transpiler = new Transpiler(result.CompilationUnit!, config);
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
        // Arrays now use C# 12 collection expression syntax
        Assert.Contains("[1, 2, 3]", result);
        Assert.DoesNotContain("new[]", result);
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
    public void TestAsyncMainTranspilation_UsesTask_NotValueTask()
    {
        // async Main must use Task (not ValueTask) because C# entry points don't support ValueTask
        var source = @"
import System.Threading.Tasks

async func Main() {
    await Task.Delay(100)
}
        ";

        var result = Transpile(source);

        // Should generate async Task Main() for entry point
        Assert.Contains("async Task Main()", result);
        // Should NOT use ValueTask for Main
        Assert.DoesNotContain("ValueTask Main()", result);
    }

    [Fact]
    public void TestAsyncMainWithReturnType_UsesTask_NotValueTask()
    {
        // async Main with int return must use Task<int> (not ValueTask<int>)
        var source = @"
import System.Threading.Tasks

async func Main(): int {
    await Task.Delay(100)
    return 0
}
        ";

        var result = Transpile(source);

        // Should generate async Task<int> Main() for entry point
        Assert.Contains("async Task<int> Main()", result);
        // Should NOT use ValueTask<int> for Main
        Assert.DoesNotContain("ValueTask<int> Main()", result);
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
    public void TestYieldBreakTranspilation()
    {
        var source = @"
func* GetNumbersUntilNegative(numbers: int[]): IEnumerable<int> {
    for num in numbers {
        if num < 0 {
            yield break
        }
        yield num
    }
}
        ";

        var result = Transpile(source);

        // Should contain yield break and yield return
        Assert.Contains("IEnumerable<int> GetNumbersUntilNegative", result);
        Assert.Contains("yield break;", result);
        Assert.Contains("yield return num;", result);
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
    public void TestLockStatementTranspilation()
    {
        var source = @"
func Increment() {
    lock _lockObject {
        _counter++
    }
}
        ";

        var result = Transpile(source);

        // Should generate lock statement
        Assert.Contains("lock (_lockObject)", result);
        Assert.Contains("_counter++", result);
    }

    [Fact]
    public void TestLockStatementWithParensTranspilation()
    {
        var source = @"
func Increment() {
    lock (_lockObject) {
        _counter++
    }
}
        ";

        var result = Transpile(source);

        // Should generate lock statement
        Assert.Contains("lock (_lockObject)", result);
        Assert.Contains("_counter++", result);
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

        // var declarations should use explicit array syntax (not collection expressions)
        Assert.Contains("var arr1 = new int[] { 1, 2, 3 }", result);
        // Spread should be transpiled (implementation may vary)
        Assert.Contains("arr2", result);
    }

    [Fact]
    public void TestSpreadOperatorInFunctionCallTranspilation()
    {
        var source = @"
func Sum(params numbers: int[]): int {
    return 0
}

func Test() {
    items := [1, 2, 3]
    result := Sum(...items)
}
        ";

        var result = Transpile(source);

        // Spread in function calls transpiles to direct array passing in C#
        // N#: Sum(...items) -> C#: Sum(items)
        Assert.Contains("Sum(items)", result);
    }

    [Fact]
    public void TestCollectionExpressionListTranspilation()
    {
        var source = @"
import System.Collections.Generic

func Test() {
    let numbers: List<int> = [1, 2, 3]
    let names: List<string> = [""Alice"", ""Bob""]
}
        ";

        var result = Transpile(source);

        // Should use collection expression syntax with explicit types
        Assert.Contains("List<int> numbers = [1, 2, 3]", result);
        Assert.Contains("List<string> names = [\"Alice\", \"Bob\"]", result);
        Assert.DoesNotContain("new[]", result);
    }

    [Fact]
    public void TestCollectionExpressionHashSetTranspilation()
    {
        var source = @"
import System.Collections.Generic

func Test() {
    let unique: HashSet<int> = [1, 2, 3]
}
        ";

        var result = Transpile(source);

        Assert.Contains("HashSet<int> unique = [1, 2, 3]", result);
        Assert.DoesNotContain("new[]", result);
    }

    [Fact]
    public void TestCollectionExpressionQueueTranspilation()
    {
        var source = @"
import System.Collections.Generic

func Test() {
    let queue: Queue<string> = [""first"", ""second"", ""third""]
}
        ";

        var result = Transpile(source);

        Assert.Contains("Queue<string> queue = [\"first\", \"second\", \"third\"]", result);
    }

    [Fact]
    public void TestCollectionExpressionIEnumerableTranspilation()
    {
        var source = @"
import System.Collections.Generic

func Test() {
    let items: IEnumerable<int> = [1, 2, 3, 4, 5]
}
        ";

        var result = Transpile(source);

        Assert.Contains("IEnumerable<int> items = [1, 2, 3, 4, 5]", result);
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

        // Type aliases emit as C# file-scoped using directives
        Assert.Contains("using UserId = int;", result);
        // Func<string, void> transpiles to System.Action<string>
        Assert.Contains("using Handler = System.Action<string>;", result);
    }

    [Fact]
    public void TestTypeAliasFullyQualified()
    {
        var source = @"
type StringDict = Dictionary<string, string>
        ";

        var result = Transpile(source);

        Assert.Contains("using StringDict = System.Collections.Generic.Dictionary<string, string>;", result);
    }

    [Fact]
    public void TestTypeAliasFuncVoidToAction()
    {
        var source = @"
type Callback = Func<void>
        ";

        var result = Transpile(source);

        Assert.Contains("using Callback = System.Action;", result);
    }

    [Fact]
    public void TestTypeAliasMultiple()
    {
        var source = @"
type UserId = int
type Name = string
type Lookup = Dictionary<string, int>
type Callback = Func<void>
type Handler = Func<string, void>
type Transformer = Func<string, int>
        ";

        var result = Transpile(source);

        Assert.Contains("using UserId = int;", result);
        Assert.Contains("using Name = string;", result);
        Assert.Contains("using Lookup = System.Collections.Generic.Dictionary<string, int>;", result);
        Assert.Contains("using Callback = System.Action;", result);
        Assert.Contains("using Handler = System.Action<string>;", result);
        Assert.Contains("using Transformer = System.Func<string, int>;", result);
    }

    [Fact]
    public void TestTypeAliasAppearsBeforeNamespace()
    {
        var source = @"
namespace MyApp

type UserId = int

class User {
    Id: UserId
}
        ";

        var result = Transpile(source);

        // The using alias must appear before the namespace declaration
        var usingIndex = result.IndexOf("using UserId = int;");
        var namespaceIndex = result.IndexOf("namespace MyApp;");
        Assert.True(usingIndex >= 0, "using alias should be present");
        Assert.True(namespaceIndex >= 0, "namespace should be present");
        Assert.True(usingIndex < namespaceIndex, "using alias must appear before namespace declaration");
    }

    [Fact]
    public void TestTypeAliasNotEmittedAsComment()
    {
        var source = @"
type UserId = int
        ";

        var result = Transpile(source);

        // Should NOT emit as a comment anymore
        Assert.DoesNotContain("// type UserId", result);
        Assert.Contains("using UserId = int;", result);
    }

    [Fact]
    public void TestNewtypeTranspilation()
    {
        var source = @"
type UserId = newtype int
        ";

        var result = Transpile(source);

        // Newtypes emit as readonly record struct wrappers
        Assert.Contains("public readonly record struct UserId(int Value);", result);
        // Should NOT emit as a using alias
        Assert.DoesNotContain("using UserId", result);
    }

    [Fact]
    public void TestNewtypeConstruction()
    {
        var source = @"
type UserId = newtype int

func main() {
    id := UserId(42)
    let raw: int = id.Value
}
        ";

        var result = Transpile(source);

        // Construction should emit as new
        Assert.Contains("new UserId(42)", result);
        // .Value access should work
        Assert.Contains(".Value", result);
    }

    [Fact]
    public void TestNewtypeStringUnderlying()
    {
        var source = @"
type Email = newtype string
        ";

        var result = Transpile(source);

        Assert.Contains("public readonly record struct Email(string Value);", result);
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
    public void TestQualifiedAttributeTranspilation()
    {
        var source = @"
[System.Serializable]
class Person {
    Name: string
}

[System.Runtime.CompilerServices.InlineArray(10)]
struct Buffer {
    element: int
}

[System.Diagnostics.CodeAnalysis.SuppressMessage(""Category"", ""CheckId"")]
func DoWork() {
}
        ";

        var result = Transpile(source);

        // Qualified attributes should be preserved in C# output
        Assert.Contains("[System.Serializable]", result);
        Assert.Contains("class Person", result);
        Assert.Contains("[System.Runtime.CompilerServices.InlineArray(10)]", result);
        Assert.Contains("struct Buffer", result);
        Assert.Contains("[System.Diagnostics.CodeAnalysis.SuppressMessage(\"Category\", \"CheckId\")]", result);
    }

    [Fact]
    public void TestParameterAttributeTranspilation()
    {
        var source = @"
func Create([FromBody] dto: TaskDto, [Required] name: string): void {
}
        ";

        var result = Transpile(source);

        // Parameter attributes should appear inline in the C# parameter list
        Assert.Contains("[FromBody] TaskDto dto", result);
        Assert.Contains("[Required] string name", result);
    }

    [Fact]
    public void TestParameterAttributeWithArgumentsTranspilation()
    {
        var source = @"
func Search([FromQuery(Name = ""q"")] query: string, [Range(1, 100)] page: int): void {
}
        ";

        var result = Transpile(source);

        Assert.Contains("[FromQuery(Name = \"q\")] string query", result);
        Assert.Contains("[Range(1, 100)] int page", result);
    }

    [Fact]
    public void TestParameterMultipleAttributesTranspilation()
    {
        var source = @"
func Create([FromBody] [Required] dto: TaskDto): void {
}
        ";

        var result = Transpile(source);

        Assert.Contains("[FromBody] [Required] TaskDto dto", result);
    }

    [Fact]
    public void TestParameterAttributesWithModifiersTranspilation()
    {
        var source = @"
func Process([Required] ref data: byte[]): void {
}
        ";

        var result = Transpile(source);

        Assert.Contains("[Required] ref byte[] data", result);
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
    public void TestPrintStatementTranspilation_WithNestedStringLiteralInInterpolation()
    {
        var source = @"
func main(tags: string[]) {
    print $""  Tags: {String.Join("", "", tags)}""
}
        ";

        var result = Transpile(source);

        Assert.Contains("Console.WriteLine($\"  Tags: {String.Join(\", \", tags)}\");", result);
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
    public void TestCheckedExpressionTranspilation()
    {
        var source = @"
func main() {
    a := 1
    b := 2
    result := checked(a + b)
}
        ";

        var result = Transpile(source);

        // Verify transpiles to C# checked (note: binary expressions get extra parens)
        Assert.Contains("checked((a + b))", result);
    }

    [Fact]
    public void TestUncheckedExpressionTranspilation()
    {
        var source = @"
func main() {
    a := 1
    b := 2
    result := unchecked(a - b)
}
        ";

        var result = Transpile(source);

        // Verify transpiles to C# unchecked (note: binary expressions get extra parens)
        Assert.Contains("unchecked((a - b))", result);
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
    public void TestListPatternEmptyTranspilation()
    {
        var source = "func check(arr: int[]): bool {\n" +
                     "    result := match arr {\n" +
                     "        [] => true,\n" +
                     "        _ => false\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var result = Transpile(source);

        // Should transpile to C# 11 list pattern
        Assert.Contains("[]", result);
    }

    [Fact]
    public void TestListPatternLiteralTranspilation()
    {
        var source = "func check(arr: int[]): bool {\n" +
                     "    result := match arr {\n" +
                     "        [1, 2, 3] => true,\n" +
                     "        _ => false\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var result = Transpile(source);

        // Should transpile to C# 11 list pattern
        Assert.Contains("[1, 2, 3]", result);
    }

    [Fact]
    public void TestListPatternWithSliceTranspilation()
    {
        var source = "func check(arr: int[]): int {\n" +
                     "    result := match arr {\n" +
                     "        [first, ..] => first,\n" +
                     "        _ => 0\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var result = Transpile(source);

        // Should transpile to C# 11 slice pattern
        Assert.Contains("[var first, ..]", result);
    }

    [Fact]
    public void TestListPatternWithNamedSliceTranspilation()
    {
        var source = "func check(arr: int[]): int[] {\n" +
                     "    result := match arr {\n" +
                     "        [first, .. rest] => rest,\n" +
                     "        _ => []\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var result = Transpile(source);

        // Should transpile to C# 11 slice pattern with binding
        Assert.Contains("[var first, .. var rest]", result);
    }

    [Fact]
    public void TestListPatternWithMiddleSliceTranspilation()
    {
        var source = "func check(arr: int[]): (int, int) {\n" +
                     "    result := match arr {\n" +
                     "        [first, .. middle, last] => (first, last),\n" +
                     "        _ => (0, 0)\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var result = Transpile(source);

        // Should transpile to C# 11 list pattern with middle slice
        Assert.Contains("[var first, .. var middle, var last]", result);
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
    public void TestAssertWithMessageTranspilation()
    {
        var source = @"
test ""test with message"" {
    assert x == 5, ""should be five""
}";

        var result = Transpile(source);
        // Custom message forces Assert.True wrapping (TranspileExpression wraps binary in parens)
        Assert.Contains("Assert.True((x == 5)", result);
        Assert.Contains(@"""should be five""", result);
    }

    [Fact]
    public void TestAssertThrowsTranspilation()
    {
        var source = @"
test ""should throw"" {
    assert throws DivideByZeroException {
        Calculator.Divide(10, 0)
    }
}";

        var result = Transpile(source);
        Assert.Contains("Assert.Throws<DivideByZeroException>(() =>", result);
        Assert.Contains("Calculator.Divide(10, 0);", result);
    }

    [Fact]
    public void TestTableDrivenTestTranspilation()
    {
        var source = @"
test ""should add"" with (a: int, b: int, expected: int) [
    (1, 2, 3),
    (0, 0, 0)
] {
    assert Add(a, b) == expected
}";

        var result = Transpile(source);
        Assert.Contains("[Theory]", result);
        Assert.Contains("[InlineData(1, 2, 3)]", result);
        Assert.Contains("[InlineData(0, 0, 0)]", result);
        Assert.Contains("public void ShouldAdd(int a, int b, int expected)", result);
    }

    [Fact]
    public void TestSkipTestTranspilation()
    {
        var source = @"
test ""needs network"" skip ""no network in CI"" {
    assert true
}";

        var result = Transpile(source);
        Assert.Contains("[Fact(Skip = \"no network in CI\")]", result);
    }

    [Fact]
    public void TestSkipTableDrivenTestTranspilation()
    {
        var source = @"
test ""should add"" with (a: int, b: int, expected: int) [
    (1, 2, 3)
] skip ""disabled"" {
    assert Add(a, b) == expected
}";

        var result = Transpile(source);
        Assert.Contains("[Theory(Skip = \"disabled\")]", result);
    }

    [Fact]
    public void TestTraitAttributeTranspilation()
    {
        var source = @"
test ""should add two numbers"" {
    assert true
}";

        var result = Transpile(source);
        Assert.Contains("[Trait(\"NSharpDescription\", \"should add two numbers\")]", result);
    }

    [Fact]
    public void TestAssertNullTranspilation()
    {
        var source = @"
test ""test null"" {
    assert x == null
}";

        var result = Transpile(source);
        Assert.Contains("Assert.Null(x);", result);
    }

    [Fact]
    public void TestAssertEmptyCountTranspilation()
    {
        var source = @"
test ""test empty"" {
    assert list.Count == 0
}";

        var result = Transpile(source);
        Assert.Contains("Assert.Empty(list);", result);
    }

    [Fact]
    public void TestAssertEmptyLengthTranspilation()
    {
        var source = @"
test ""test empty string"" {
    assert str.Length == 0
}";

        var result = Transpile(source);
        Assert.Contains("Assert.Empty(str);", result);
    }

    [Fact]
    public void TestAssertContainsTranspilation()
    {
        var source = @"
test ""test contains"" {
    assert list.Contains(x)
}";

        var result = Transpile(source);
        Assert.Contains("Assert.Contains(x, list);", result);
    }

    [Fact]
    public void TestAssertStartsWithTranspilation()
    {
        var source = @"
test ""test starts with"" {
    assert str.StartsWith(""hello"")
}";

        var result = Transpile(source);
        Assert.Contains("Assert.StartsWith(\"hello\", str);", result);
    }

    [Fact]
    public void TestAssertEndsWithTranspilation()
    {
        var source = @"
test ""test ends with"" {
    assert str.EndsWith(""world"")
}";

        var result = Transpile(source);
        Assert.Contains("Assert.EndsWith(\"world\", str);", result);
    }

    [Fact]
    public void TestAssertFalseTranspilation()
    {
        var source = @"
test ""test false"" {
    assert !isValid
}";

        var result = Transpile(source);
        Assert.Contains("Assert.False(isValid);", result);
    }

    [Fact]
    public void TestAssertDoesNotContainTranspilation()
    {
        var source = @"
test ""test does not contain"" {
    assert !list.Contains(x)
}";

        var result = Transpile(source);
        Assert.Contains("Assert.DoesNotContain(x, list);", result);
    }

    [Fact]
    public void TestAssertSingleTranspilation()
    {
        var source = @"
test ""test single"" {
    assert list.Count == 1
}";

        var result = Transpile(source);
        Assert.Contains("Assert.Single(list);", result);
    }

    [Fact]
    public void TestAssertNotEmptyTranspilation()
    {
        var source = @"
test ""test not empty"" {
    assert list.Count != 0
}";

        var result = Transpile(source);
        Assert.Contains("Assert.NotEmpty(list);", result);
    }

    [Fact]
    public void TestSetupBlockTranspilation()
    {
        var source = @"
setup {
    store := new TaskStore()
}

test ""should work"" {
    assert store != null
}";

        var result = Transpile(source);
        // Should have a field and constructor (type inferred from new expression)
        Assert.Contains("private TaskStore store;", result);
        Assert.Contains("store = new TaskStore();", result);
        // Should still have the test method
        Assert.Contains("[Fact]", result);
        Assert.Contains("public void ShouldWork()", result);
    }

    [Fact]
    public void TestSetupBlockTypeInferenceNewExpression()
    {
        var source = @"
setup {
    store := new TaskStore()
}

test ""should work"" {
    assert store != null
}";

        var result = Transpile(source);
        // new TaskStore() should infer TaskStore, not dynamic
        Assert.Contains("private TaskStore store;", result);
        Assert.DoesNotContain("dynamic", result);
    }

    [Fact]
    public void TestSetupBlockTypeInferenceLiterals()
    {
        var source = @"
setup {
    count := 42
    name := ""hello""
    flag := true
}

test ""should work"" {
    assert count == 42
}";

        var result = Transpile(source);
        Assert.Contains("private int count;", result);
        Assert.Contains("private string name;", result);
        Assert.Contains("private bool flag;", result);
    }

    [Fact]
    public void TestTeardownBlockSyncXUnit()
    {
        var source = @"
setup {
    db := new Database()
}

teardown {
    db.Close()
}

test ""should query"" {
    assert db != null
}";

        var result = Transpile(source);
        // Should implement IDisposable for sync teardown
        Assert.Contains(": IDisposable", result);
        Assert.Contains("public void Dispose()", result);
        Assert.Contains("db.Close();", result);
        // Setup still in constructor
        Assert.Contains("public Tests()", result);
    }

    [Fact]
    public void TestAsyncSetupXUnit()
    {
        var source = @"
setup {
    db := new Database()
    await db.ConnectAsync()
}

test ""should query"" {
    assert db != null
}";

        var result = Transpile(source);
        // Should implement IAsyncLifetime for async setup
        Assert.Contains(": IAsyncLifetime", result);
        Assert.Contains("public async Task InitializeAsync()", result);
        Assert.Contains("await db.ConnectAsync();", result);
        // Empty DisposeAsync since no teardown
        Assert.Contains("public Task DisposeAsync() => Task.CompletedTask;", result);
    }

    [Fact]
    public void TestAsyncSetupAndTeardownXUnit()
    {
        var source = @"
setup {
    db := new Database()
    await db.ConnectAsync()
}

teardown {
    await db.DisconnectAsync()
}

test ""should query"" {
    assert db != null
}";

        var result = Transpile(source);
        Assert.Contains(": IAsyncLifetime", result);
        Assert.Contains("public async Task InitializeAsync()", result);
        Assert.Contains("public async Task DisposeAsync()", result);
        Assert.Contains("await db.ConnectAsync();", result);
        Assert.Contains("await db.DisconnectAsync();", result);
    }

    [Fact]
    public void TestSyncSetupSyncTeardownNUnit()
    {
        var source = @"
setup {
    db := new Database()
}

teardown {
    db.Close()
}

test ""should query"" {
    assert db != null
}";

        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("[TestFixture]", result);
        Assert.Contains("[SetUp]", result);
        Assert.Contains("public void Setup()", result);
        Assert.Contains("[TearDown]", result);
        Assert.Contains("public void Teardown()", result);
        Assert.Contains("db.Close();", result);
    }

    [Fact]
    public void TestAsyncSetupNUnit()
    {
        var source = @"
setup {
    db := new Database()
    await db.ConnectAsync()
}

test ""should query"" {
    assert db != null
}";

        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("[SetUp]", result);
        Assert.Contains("public async Task Setup()", result);
        Assert.Contains("await db.ConnectAsync();", result);
    }

    [Fact]
    public void TestTeardownOnlyXUnit()
    {
        var source = @"
teardown {
    TempFile.Delete()
}

test ""should work"" {
    assert true
}";

        var result = Transpile(source);
        Assert.Contains(": IDisposable", result);
        Assert.Contains("public void Dispose()", result);
        Assert.Contains("TempFile.Delete();", result);
        // No constructor or InitializeAsync since no setup
        Assert.DoesNotContain("InitializeAsync", result);
    }

    [Fact]
    public void TestAsyncTeardownOnlyXUnit()
    {
        var source = @"
teardown {
    await Cleanup()
}

test ""should work"" {
    assert true
}";

        var result = Transpile(source);
        Assert.Contains(": IAsyncLifetime", result);
        Assert.Contains("public async Task DisposeAsync()", result);
        // Empty InitializeAsync since no setup
        Assert.Contains("public Task InitializeAsync() => Task.CompletedTask;", result);
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
    public void TestImplicitConversionOperatorTranspilation()
    {
        var source = @"
class Celsius {
    Value: double

    implicit operator Fahrenheit(c: Celsius) {
        return new Fahrenheit { Value: c.Value * 9.0 / 5.0 + 32.0 }
    }
}";

        var result = Transpile(source);
        Assert.Contains("public static implicit operator Fahrenheit(Celsius c)", result);
        Assert.DoesNotContain("Fahrenheit Fahrenheit", result); // Should not duplicate return type
    }

    [Fact]
    public void TestExplicitConversionOperatorTranspilation()
    {
        var source = @"
struct Fraction {
    Numerator: int
    Denominator: int

    explicit operator double(f: Fraction) {
        return f.Numerator / (double)f.Denominator
    }
}";

        var result = Transpile(source);
        Assert.Contains("public static explicit operator double(Fraction f)", result);
    }

    [Fact]
    public void TestConversionOperatorExpressionBodied()
    {
        var source = @"
class Meters {
    Value: double

    implicit operator Centimeters(m: Meters) => new Centimeters { Value: m.Value * 100.0 }
}";

        var result = Transpile(source);
        Assert.Contains("public static implicit operator Centimeters(Meters m)", result);
        Assert.Contains("=> new Centimeters", result);
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
    public void TestParamsParameterTranspilation()
    {
        var source = "func Sum(params numbers: int[]): int { }";
        var result = Transpile(source);
        Assert.Contains("params int[] numbers", result);
    }

    [Fact]
    public void TestParamsWithOtherParametersTranspilation()
    {
        var source = "func Format(format: string, params args: object[]): string { }";
        var result = Transpile(source);
        Assert.Contains("string format, params object[] args", result);
    }

    // C# 13 Params Collections Transpilation Tests
    [Fact]
    public void TestParamsWithReadOnlySpanTranspilation()
    {
        var source = "func Process(params items: ReadOnlySpan<int>) { }";
        var result = Transpile(source);
        Assert.Contains("params ReadOnlySpan<int> items", result);
    }

    [Fact]
    public void TestParamsWithSpanTranspilation()
    {
        var source = "func Process(params items: Span<string>) { }";
        var result = Transpile(source);
        Assert.Contains("params Span<string> items", result);
    }

    [Fact]
    public void TestParamsWithIEnumerableTranspilation()
    {
        var source = "func Sum(params numbers: IEnumerable<int>): int { return 0 }";
        var result = Transpile(source);
        Assert.Contains("params IEnumerable<int> numbers", result);
    }

    [Fact]
    public void TestParamsWithListTranspilation()
    {
        var source = "func Process(params items: List<string>) { }";
        var result = Transpile(source);
        Assert.Contains("params List<string> items", result);
    }

    [Fact]
    public void TestParamsWithIReadOnlyListTranspilation()
    {
        var source = "func Process(params items: IReadOnlyList<int>) { }";
        var result = Transpile(source);
        Assert.Contains("params IReadOnlyList<int> items", result);
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

    [Fact]
    public void TestConstructorThisInitializerTranspilation()
    {
        var source = @"
            class Person {
                Name: string
                Age: int

                constructor(name: string): this(name, 0) {
                }

                constructor(name: string, age: int) {
                    Name = name
                    Age = age
                }
            }
        ";
        var result = Transpile(source);
        Assert.Contains("public Person(string name) : this(name, 0)", result);
    }

    [Fact]
    public void TestConstructorBaseInitializerTranspilation()
    {
        var source = @"
            class Employee : Person {
                EmployeeId: string

                constructor(name: string, id: string): base(name) {
                    EmployeeId = id
                }
            }
        ";
        var result = Transpile(source);
        Assert.Contains("public Employee(string name, string id) : base(name)", result);
    }

    [Fact]
    public void TestInterpolatedRawStringTranspilation()
    {
        var source = @"
            func GenerateJson(name: string, age: int): string {
                return $""""""
                {
                    ""name"": ""{name}"",
                    ""age"": {age}
                }
                """"""
            }
        ";
        var result = Transpile(source);
        // Verify the C# 11 raw string literal syntax is preserved
        Assert.Contains("$\"\"\"", result);
        Assert.Contains("\"\"\"", result);
        Assert.Contains("{name}", result);
        Assert.Contains("{age}", result);
    }

    [Fact]
    public void TestClassWithPrimaryConstructorTranspilation()
    {
        var source = @"
class UserService(logger: ILogger, db: IDatabase) {
    func DoWork() {
        logger.Log(""Working"")
    }
}
        ";

        var result = Transpile(source);

        // Verify C# 12 primary constructor syntax
        Assert.Contains("class UserService(ILogger logger, IDatabase db)", result);
        Assert.DoesNotContain("public UserService(", result); // Should NOT generate explicit constructor
    }

    [Fact]
    public void TestStructWithPrimaryConstructorTranspilation()
    {
        var source = @"
struct Point(x: double, y: double) {
    func GetDistance(): double {
        return Math.Sqrt(x * x + y * y)
    }
}
        ";

        var result = Transpile(source);

        // Verify C# 12 primary constructor syntax
        Assert.Contains("struct Point(double x, double y)", result);
    }

    [Fact]
    public void TestRecordWithPrimaryConstructorTranspilation()
    {
        var source = @"
record Person(name: string, age: int) {
    FullInfo: string => $""{name} is {age} years old""
}
        ";

        var result = Transpile(source);

        // Verify C# 12 primary constructor syntax
        Assert.Contains("record Person(string name, int age)", result);
        Assert.Contains("=> $\"{name} is {age} years old\"", result);
    }

    [Fact]
    public void TestRecordStructTranspilation()
    {
        var source = @"
record struct Point {
    X: double
    Y: double
}
        ";

        var result = Transpile(source);

        // Verify C# 10 record struct syntax
        Assert.Contains("record struct Point", result);
        Assert.Contains("public double X", result);
        Assert.Contains("public double Y", result);
    }

    [Fact]
    public void TestRecordStructWithPrimaryConstructorTranspilation()
    {
        var source = @"
import System

record struct Point(x: double, y: double) {
    Length: double => Math.Sqrt(x * x + y * y)
}
        ";

        var result = Transpile(source);

        // Verify C# 10 record struct with C# 12 primary constructor
        Assert.Contains("record struct Point(double x, double y)", result);
        Assert.Contains("public double Length => Math.Sqrt", result);  // Allow for parenthesis variations
        Assert.Contains("x * x", result);
        Assert.Contains("y * y", result);
    }

    [Fact]
    public void TestRecordClassTranspilation()
    {
        var source = @"
record Person {
    Name: string
}
        ";

        var result = Transpile(source);

        // Verify default record (class) syntax - no 'struct' keyword
        Assert.Contains("record Person", result);
        Assert.DoesNotContain("record struct", result);
    }

    [Fact]
    public void TestTargetTypedNewTranspilation()
    {
        var source = @"
class Person {
    Name: string
}

func Test() {
    let p: Person = new()
}
        ";

        var result = Transpile(source);

        // Verify C# 9 target-typed new syntax
        Assert.Contains("Person p = new()", result);
    }

    [Fact]
    public void TestTargetTypedNewWithArgumentsTranspilation()
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

func Test() {
    let p: Person = new(""Alice"", 30)
}
        ";

        var result = Transpile(source);

        // Verify C# 9 target-typed new syntax with arguments
        Assert.Contains("Person p = new(\"Alice\", 30)", result);
    }

    [Fact]
    public void TestTargetTypedNewWithInitializerTranspilation()
    {
        var source = @"
class Person {
    Name: string
    Age: int
}

func Test() {
    let p: Person = new { Name: ""Alice"", Age: 30 }
}
        ";

        var result = Transpile(source);

        // Note: In N#, `new { ... }` without a type creates an anonymous object in C#
        // Even with a type annotation, it's treated as an anonymous object
        // For explicit type, use `new Person { ... }` instead
        Assert.Contains("Person p = new { Name = \"Alice\", Age = 30 }", result);
    }

    [Fact]
    public void TestFileClassTranspilation()
    {
        var source = @"
file class InternalHelper {
    Name: string
}
        ";

        var result = Transpile(source);

        // Verify file modifier emitted in C#
        Assert.Contains("file class InternalHelper", result);
        Assert.DoesNotContain("public file class InternalHelper", result);
        Assert.DoesNotContain("file public class InternalHelper", result);
    }

    [Fact]
    public void TestFileStructTranspilation()
    {
        var source = @"
file struct Point {
    X: double
    Y: double
}
        ";

        var result = Transpile(source);

        // Verify file modifier emitted in C#
        Assert.Contains("file struct Point", result);
        Assert.DoesNotContain("public file struct Point", result);
        Assert.DoesNotContain("file public struct Point", result);
    }

    [Fact]
    public void TestFileRecordTranspilation()
    {
        var source = @"
file record Person {
    Name: string
    Age: int
}
        ";

        var result = Transpile(source);

        // Verify file modifier emitted in C#
        Assert.Contains("file record Person", result);
        Assert.DoesNotContain("public file record Person", result);
        Assert.DoesNotContain("file public record Person", result);
    }

    [Fact]
    public void TestFileInterfaceTranspilation()
    {
        var source = @"
file interface IHelper {
    func DoWork(): void
}
        ";

        var result = Transpile(source);

        // Verify file modifier emitted in C#
        Assert.Contains("file interface IHelper", result);
        Assert.DoesNotContain("public file interface IHelper", result);
        Assert.DoesNotContain("file public interface IHelper", result);
    }

    [Fact]
    public void TestFileEnumTranspilation()
    {
        var source = @"
file enum Status {
    Active,
    Inactive
}
        ";

        var result = Transpile(source);

        Assert.Contains("file enum Status", result);
        Assert.DoesNotContain("public file enum Status", result);
        Assert.DoesNotContain("file public enum Status", result);
    }

    [Fact]
    public void TestFileUnionTranspilation()
    {
        var source = @"
file union Result {
    Success { value: int }
    Failure { error: string }
}
        ";

        var result = Transpile(source);

        Assert.Contains("file abstract record Result", result);
        Assert.DoesNotContain("public file abstract record Result", result);
        Assert.DoesNotContain("file public abstract record Result", result);
    }

    [Fact]
    public void TestTypePatternTranspilation()
    {
        var source = @"
func check(obj: object): string {
    result := match obj {
        string s => s,
        int n => n.ToString(),
        _ => ""unknown""
    }
    return result
}
        ";

        var result = Transpile(source);

        // Verify type patterns transpile to C# syntax
        Assert.Contains("string s => s", result);
        Assert.Contains("int n => n.ToString()", result);
    }

    [Fact]
    public void TestTypePatternWithQualifiedNameTranspilation()
    {
        var source = @"
func check(obj: object): string {
    result := match obj {
        System.String s => s.ToUpper(),
        _ => ""unknown""
    }
    return result
}
        ";

        var result = Transpile(source);

        // Verify qualified type names work
        Assert.Contains("System.String s => s.ToUpper()", result);
    }

    [Fact]
    public void TestTypePatternWithGuardTranspilation()
    {
        var source = @"
func check(obj: object): string {
    result := match obj {
        string s when s.Length > 5 => ""long"",
        string s => ""short"",
        _ => ""not string""
    }
    return result
}
        ";

        var result = Transpile(source);

        // Verify type pattern with guard clause
        Assert.Contains("string s when (s.Length > 5) => \"long\"", result);
        Assert.Contains("string s => \"short\"", result);
    }

    [Fact]
    public void TestInlineOutVarTranspilation()
    {
        var source = @"
func TryParse(input: string, out result: int): bool {
    result = 42
    return true
}

func Main() {
    if TryParse(""123"", out var num) {
        print num
    }
}
";

        var csharp = Transpile(source);
        Assert.Contains("if (TryParse(\"123\", out var num))", csharp);
    }

    [Fact]
    public void TestInlineOutExplicitTypeTranspilation()
    {
        var source = @"
func TryParse(input: string, out result: int): bool {
    result = 42
    return true
}

func Main() {
    if TryParse(""456"", out int value) {
        print value
    }
}
";

        var csharp = Transpile(source);
        Assert.Contains("if (TryParse(\"456\", out int value))", csharp);
    }

    [Fact]
    public void TestGenericMethodCallTranspilation()
    {
        var source = @"
func Test() {
    result := Method<int>(42)
}
";

        var csharp = Transpile(source);
        Assert.Contains("Method<int>(42)", csharp);
    }

    [Fact]
    public void TestGenericMethodCallWithMultipleTypeArgsTranspilation()
    {
        var source = @"
func Test() {
    result := Method<int, string, bool>(42, ""hello"", true)
}
";

        var csharp = Transpile(source);
        Assert.Contains("Method<int, string, bool>(42, \"hello\", true)", csharp);
    }

    [Fact]
    public void TestGenericMethodCallWithNestedGenericsTranspilation()
    {
        var source = @"
func Test() {
    result := Method<List<int>>(list)
}
";

        var csharp = Transpile(source);
        Assert.Contains("Method<List<int>>(list)", csharp);
    }

    [Fact]
    public void TestGenericMethodCallOnMemberAccessTranspilation()
    {
        var source = @"
func Test() {
    result := list.OfType<string>()
    result2 := obj.Method<int>(42)
}
";

        var csharp = Transpile(source);
        Assert.Contains("list.OfType<string>()", csharp);
        Assert.Contains("obj.Method<int>(42)", csharp);
    }

    [Fact]
    public void TestGenericMethodCallWithNullableTypeTranspilation()
    {
        var source = @"
func Test() {
    result := Method<int?>(value)
}
";

        var csharp = Transpile(source);
        Assert.Contains("Method<int?>(value)", csharp);
    }

    [Fact]
    public void TestGenericMethodCallWithArrayTypeTranspilation()
    {
        var source = @"
func Test() {
    result := Method<int[]>(array)
}
";

        var csharp = Transpile(source);
        Assert.Contains("Method<int[]>(array)", csharp);
    }

    [Fact]
    public void TestGenericMethodCallWithDictionaryTranspilation()
    {
        var source = @"
func Test() {
    result := Method<Dictionary<string, int>>(dict)
}
";

        var csharp = Transpile(source);
        Assert.Contains("Method<Dictionary<string, int>>(dict)", csharp);
    }

    [Fact]
    public void TestCollectionInitializerWithIndexersTranspilation()
    {
        var source = @"
func Test() {
    dict := new Dictionary<string, int> {
        [""one""] = 1,
        [""two""] = 2,
        [""three""] = 3
    }
}
";

        var csharp = Transpile(source);
        Assert.Contains("new Dictionary<string, int>() { [\"one\"] = 1, [\"two\"] = 2, [\"three\"] = 3 }", csharp);
    }

    [Fact]
    public void TestMixedPropertyAndIndexerInitializersTranspilation()
    {
        var source = @"
class MyType {
    Name: string
    Age: int
}

func Test() {
    obj := new MyType {
        Name: ""test"",
        Age: 30
    }

    dict := new Dictionary<string, int> {
        [""key1""] = 1,
        [""key2""] = 2
    }
}
";

        var csharp = Transpile(source);
        // Verify property initializers
        Assert.Contains("Name = \"test\", Age = 30", csharp);
        // Verify indexer initializers
        Assert.Contains("[\"key1\"] = 1, [\"key2\"] = 2", csharp);
    }

    [Fact]
    public void TestIndexerInitializerWithComplexExpressions()
    {
        var source = @"
func Test() {
    key := ""myKey""
    value := 42
    dict := new Dictionary<string, int> {
        [key] = value,
        [""literal""] = 100
    }
}
";

        var csharp = Transpile(source);
        // Should handle variable references in indexer expressions
        Assert.Contains("[key] = value", csharp);
        Assert.Contains("[\"literal\"] = 100", csharp);
    }

    // Array Literal Type Inference Tests (v1.69)

    [Fact]
    public void TestArrayLiteralWithVarUsesExplicitType()
    {
        var source = @"
func Test() {
    x := [1, 2, 3]
}
        ";

        var result = Transpile(source);
        // var declarations should use explicit array syntax for type inference
        Assert.Contains("var x = new int[] { 1, 2, 3 }", result);
    }

    [Fact]
    public void TestArrayLiteralWithExplicitTypeUsesCollectionExpression()
    {
        var source = @"
func Test() {
    let numbers: int[] = [1, 2, 3]
}
        ";

        var result = Transpile(source);
        // Explicit types should use C# 12 collection expression syntax
        Assert.Contains("int[] numbers = [1, 2, 3]", result);
    }

    [Fact]
    public void TestStringArrayInference()
    {
        var source = @"
func Test() {
    names := [""Alice"", ""Bob"", ""Charlie""]
}
        ";

        var result = Transpile(source);
        Assert.Contains("var names = new string[] { \"Alice\", \"Bob\", \"Charlie\" }", result);
    }

    [Fact]
    public void TestBoolArrayInference()
    {
        var source = @"
func Test() {
    flags := [true, false, true]
}
        ";

        var result = Transpile(source);
        Assert.Contains("var flags = new bool[] { true, false, true }", result);
    }

    [Fact]
    public void TestDoubleArrayInference()
    {
        var source = @"
func Test() {
    values := [1.0, 2.5, 3.14]
}
        ";

        var result = Transpile(source);
        Assert.Contains("var values = new double[] { 1.0, 2.5, 3.14 }", result);
    }

    [Fact]
    public void TestNestedArrayInference()
    {
        var source = @"
func Test() {
    matrix := [[1, 2], [3, 4], [5, 6]]
}
        ";

        var result = Transpile(source);
        Assert.Contains("var matrix = new int[][] {", result);
        Assert.Contains("new int[] { 1, 2 }", result);
        Assert.Contains("new int[] { 3, 4 }", result);
        Assert.Contains("new int[] { 5, 6 }", result);
    }

    [Fact]
    public void TestEmptyArrayInference()
    {
        var source = @"
func Test() {
    empty := []
}
        ";

        var result = Transpile(source);
        // Empty arrays default to object[]
        Assert.Contains("var empty = new object[] { }", result);
    }

    [Fact]
    public void TestListCollectionExpressionStillWorks()
    {
        var source = @"
import System.Collections.Generic

func Test() {
    let list: List<int> = [1, 2, 3, 4, 5]
}
        ";

        var result = Transpile(source);
        // Explicit List<T> type should use collection expression
        Assert.Contains("List<int> list = [1, 2, 3, 4, 5]", result);
    }

    [Fact]
    public void TestMixedVarAndExplicitTypes()
    {
        var source = @"
import System.Collections.Generic

func Test() {
    // var should use explicit array syntax
    inferred := [1, 2, 3]

    // Explicit types should use collection expressions
    let explicitArray: int[] = [4, 5, 6]
    let list: List<string> = [""a"", ""b"", ""c""]
}
        ";

        var result = Transpile(source);

        // var declaration needs explicit type
        Assert.Contains("var inferred = new int[] { 1, 2, 3 }", result);

        // Explicit types can use collection expressions
        Assert.Contains("int[] explicitArray = [4, 5, 6]", result);
        Assert.Contains("List<string> list = [\"a\", \"b\", \"c\"]", result);
    }

    [Fact]
    public void TestPropertyTypeInferenceTranspilation()
    {
        var source = @"
            class Person {
                Name := ""Alice""
                Age := 30
                Score := 95.5
                IsActive := true
                Items := [1, 2, 3]
            }
        ";

        var result = Transpile(source);

        // Check that types were correctly inferred and emitted
        Assert.Contains("public string Name { get; set; } = \"Alice\"", result);
        Assert.Contains("public int Age { get; set; } = 30", result);
        Assert.Contains("public double Score { get; set; } = 95.5", result);
        Assert.Contains("public bool IsActive { get; set; } = true", result);
        Assert.Contains("public int[] Items { get; set; } = [1, 2, 3]", result);
    }

    [Fact]
    public void TestPropertyMixedExplicitAndInferredTypes()
    {
        var source = @"
            class Data {
                // Explicit type
                ExplicitName: string = ""test""

                // Inferred type
                InferredName := ""inferred""

                // Explicit type with different value
                Count: int = 0

                // Inferred type
                Total := 100
            }
        ";

        var result = Transpile(source);

        // Explicit types
        Assert.Contains("public string ExplicitName { get; set; } = \"test\"", result);
        Assert.Contains("public int Count { get; set; } = 0", result);

        // Inferred types
        Assert.Contains("public string InferredName { get; set; } = \"inferred\"", result);
        Assert.Contains("public int Total { get; set; } = 100", result);
    }

    [Fact]
    public void TestPropertyTypeInferenceWithArrays()
    {
        var source = @"
            class Container {
                Numbers := [1, 2, 3, 4, 5]
                EmptyArray := []
            }
        ";

        var result = Transpile(source);

        // Array types should be inferred
        Assert.Contains("public int[] Numbers { get; set; } = [1, 2, 3, 4, 5]", result);
        Assert.Contains("public object[] EmptyArray { get; set; } = []", result);
    }

    [Fact]
    public void TestPackageTranspilation()
    {
        var source = @"
            package MathUtils

            func Add(a: int, b: int): int => a + b
        ";

        var result = Transpile(source);

        Assert.Contains("public static partial class Functions_MathUtils", result);
        Assert.Contains("using static MathUtils.Functions_MathUtils;", result);
        Assert.Contains("public static int Add(int a, int b)", result);
    }

    [Fact]
    public void TestNoPackageUsesTopLevel()
    {
        var source = @"
            func Add(a: int, b: int): int => a + b
        ";

        var result = Transpile(source);

        Assert.Contains("internal static partial class _TopLevel", result);
        Assert.Contains("internal static int Add(int a, int b)", result);
    }

    [Fact]
    public void TestDottedPackageName()
    {
        var source = @"
            package MyCompany.Utils

            func Helper(): string => ""test""
        ";

        var result = Transpile(source);

        Assert.Contains("public static partial class Functions_MyCompany.Utils", result);
        Assert.Contains("using static MyCompany.Utils.Functions_MyCompany.Utils;", result);
    }

    // Lambda syntax tests (Task 033)

    [Fact]
    public void Transpile_SingleParamLambda_EmitsParens()
    {
        var source = @"
            import System.Linq

            func Test() {
                items := [1, 2, 3]
                evens := items.Where(x => x % 2 == 0)
            }
        ";

        var result = Transpile(source);

        // C# output should have parens even though N# doesn't require them
        Assert.Contains("(x) =>", result);
    }

    [Fact]
    public void Transpile_MultiParamLambda_EmitsParens()
    {
        var source = @"
            func Test() {
                items := [1, 2, 3]
                indexed := items.Select((item, index) => new { Item: item, Index: index })
            }
        ";

        var result = Transpile(source);

        Assert.Contains("(item, index) =>", result);
    }

    [Fact]
    public void Transpile_NoParamLambda_EmitsParens()
    {
        var source = @"
            func Test() {
                Task.Run(() => { print ""Hello"" })
            }
        ";

        var result = Transpile(source);

        Assert.Contains("() =>", result);
    }

    // ASP.NET Core Integration Tests (Task 034)

    [Fact]
    public void ExternalTypeResolution_WebApplication_Transpiles()
    {
        var source = @"
import Microsoft.AspNetCore.Builder

package TestApp

func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()
    app.Run()
}";

        var result = Transpile(source);

        Assert.Contains("var builder = WebApplication.CreateBuilder(args)", result);
        Assert.Contains("var app = builder.Build()", result);
        Assert.Contains("app.Run()", result);
    }

    [Fact]
    public void BooleanInference_IsDevelopment_Transpiles()
    {
        var source = @"
import Microsoft.AspNetCore.Builder

package TestApp

func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()

    if app.Environment.IsDevelopment() {
        print ""Development mode""
    }

    app.Run()
}";

        var result = Transpile(source);

        Assert.Contains("if (app.Environment.IsDevelopment())", result);
        Assert.Contains("Console.WriteLine(\"Development mode\")", result);
    }

    [Fact]
    public void NullCoalescing_WithNullableProperties_Transpiles()
    {
        var source = @"
package TestApp

record TaskDto {
    Title: string?
    Description: string?
}

func ProcessTask(dto: TaskDto) {
    title := dto.Title ?? ""Untitled""
    description := dto.Description ?? ""No description""
    print title
    print description
}";

        var result = Transpile(source);

        Assert.Contains("var title = (dto.Title ?? \"Untitled\")", result);
        Assert.Contains("var description = (dto.Description ?? \"No description\")", result);
    }

    [Fact]
    public void Attributes_ClassAndMethodLevel_Transpile()
    {
        var source = @"
import Microsoft.AspNetCore.Mvc
import System

package TestApp

[ApiController]
[Route(""api/tasks"")]
class TasksController : ControllerBase {

    [HttpGet]
    func GetAll(): IActionResult {
        return Ok(""All tasks"")
    }

    [HttpGet(""{id}"")]
    func GetById(id: Guid): IActionResult {
        return Ok(id)
    }

    [HttpPost]
    func Create(dto: string): IActionResult {
        return Ok(dto)
    }
}";

        var result = Transpile(source);

        Assert.Contains("[ApiController]", result);
        Assert.Contains("[Route(\"api/tasks\")]", result);
        Assert.Contains("[HttpGet]", result);
        Assert.Contains("[HttpGet(\"{id}\")]", result);
        Assert.Contains("[HttpPost]", result);
    }

    [Fact]
    public void Properties_ImplicitGetSet_Transpile()
    {
        var source = @"
import System

package TestApp

class TaskEntity {
    Id: Guid
    Title: string
    CreatedAt: DateTime
}";

        var result = Transpile(source);

        Assert.Contains("public Guid Id { get; set; }", result);
        Assert.Contains("public string Title { get; set; }", result);
        Assert.Contains("public DateTime CreatedAt { get; set; }", result);
    }

    // ===================================================================
    // Duck Interface Lowering Tests
    // ===================================================================

    [Fact]
    public void DuckInterface_EmitsInternalInterface()
    {
        var source = @"
duck interface IReader {
    func Read(): string
}
        ";

        var result = Transpile(source);

        Assert.Contains("internal interface IReader", result);
        Assert.Contains("string Read();", result);
    }

    [Fact]
    public void DuckInterface_ClassAutoImplements()
    {
        var source = @"
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string {
        return ""file contents""
    }
}
        ";

        var result = Transpile(source);

        // Class should auto-implement the duck interface
        // IReader is public because FileReader (PascalCase) is public
        Assert.Contains("public interface IReader", result);
        Assert.Contains("class FileReader : IReader", result);
    }

    [Fact]
    public void DuckInterface_LowercaseMethodForcedPublic()
    {
        // Bug fix: duck interface methods with lowercase names must be emitted as public
        // so C# interface compliance is satisfied (CS0737)
        var source = @"
duck interface IReader {
    func read(): string
}

class FileReader {
    func read(): string {
        return ""file contents""
    }
}
        ";

        var result = Transpile(source);

        // Class should auto-implement the duck interface
        Assert.Contains("class FileReader : IReader", result);
        // The method must be public even though it's lowercase (duck interface requirement)
        Assert.Contains("public string read()", result);
    }

    [Fact]
    public void DuckInterface_NestedTypeDoesNotClearOuterVisibility()
    {
        // Bug fix: nested types must not clear the outer type's duck-interface tracking
        var source = @"
duck interface IReader {
    func read(): string
}

class FileReader {
    func read(): string {
        return ""file contents""
    }

    class Helper {
        func help(): string {
            return ""helping""
        }
    }
}
        ";

        var result = Transpile(source);

        // FileReader should auto-implement IReader and read() should be public
        Assert.Contains("class FileReader : IReader", result);
        Assert.Contains("public string read()", result);
    }

    [Fact]
    public void DuckInterface_NonMatchingClassDoesNotImplement()
    {
        var source = @"
duck interface IReader {
    func Read(): string
}

class Writer {
    func Write(s: string) {
    }
}
        ";

        var result = Transpile(source);

        // Writer should NOT implement IReader
        Assert.DoesNotContain("class Writer : IReader", result);
    }

    // NUnit test framework transpilation tests

    [Fact]
    public void TestNUnitAssertEqualTranspilation()
    {
        var source = @"
test ""test equals"" {
    assert x == 5
}";
        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("using NUnit.Framework;", result);
        Assert.Contains("[TestFixture]", result);
        Assert.Contains("[Test]", result);
        Assert.Contains("Assert.That(x, Is.EqualTo(5));", result);
    }

    [Fact]
    public void TestNUnitAssertNotEqualTranspilation()
    {
        var source = @"
test ""test not equals"" {
    assert x != 5
}";
        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("Assert.That(x, Is.Not.EqualTo(5));", result);
    }

    [Fact]
    public void TestNUnitAssertNotNullTranspilation()
    {
        var source = @"
test ""test not null"" {
    assert value != null
}";
        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("Assert.That(value, Is.Not.Null);", result);
    }

    [Fact]
    public void TestNUnitAssertGreaterThanTranspilation()
    {
        var source = @"
test ""test greater than"" {
    assert x > 5
}";
        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("Assert.That(x, Is.GreaterThan(5));", result);
    }

    [Fact]
    public void TestNUnitAssertLessThanTranspilation()
    {
        var source = @"
test ""test less than"" {
    assert x < 5
}";
        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("Assert.That(x, Is.LessThan(5));", result);
    }

    [Fact]
    public void TestNUnitAssertGreaterThanOrEqualTranspilation()
    {
        var source = @"
test ""test gte"" {
    assert x >= 5
}";
        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("Assert.That(x, Is.GreaterThanOrEqualTo(5));", result);
    }

    [Fact]
    public void TestNUnitAssertLessThanOrEqualTranspilation()
    {
        var source = @"
test ""test lte"" {
    assert x <= 5
}";
        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("Assert.That(x, Is.LessThanOrEqualTo(5));", result);
    }

    [Fact]
    public void TestNUnitAssertBooleanTranspilation()
    {
        var source = @"
test ""test boolean"" {
    assert isValid
}";
        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("Assert.That(isValid, Is.True);", result);
    }

    [Fact]
    public void TestNUnitAssertIsTypeTranspilation()
    {
        var source = @"
test ""test type check"" {
    assert value is string
}";
        var config = new ProjectConfig { TestFramework = "nunit" };
        var result = TranspileWithConfig(source, config);
        Assert.Contains("Assert.That(value, Is.InstanceOf<string>());", result);
    }

    [Fact]
    public void TestXUnitIsDefaultWhenNoConfig()
    {
        var source = @"
test ""test default"" {
    assert x == 5
}";
        var result = Transpile(source);
        Assert.Contains("using Xunit;", result);
        Assert.Contains("[Fact]", result);
        Assert.Contains("Assert.Equal(5, x);", result);
        Assert.DoesNotContain("NUnit", result);
        Assert.DoesNotContain("[TestFixture]", result);
    }

    // ========================================================================
    // Debug Information Tests (#line directives, #line hidden)
    // ========================================================================

    private static string TranspileWithDebugInfo(string source, string filePath = "test.nl")
    {
        var lexer = new Lexer(source, filePath);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, filePath);
        var result = parser.ParseCompilationUnit();
        var transpiler = new Transpiler(result.CompilationUnit!, sourceFilePath: filePath);
        return transpiler.Transpile();
    }

    [Fact]
    public void TestNoLineDirectivesWhenNoSourcePath()
    {
        var source = @"
func Main() {
    x := 42
    print x
}";
        var result = Transpile(source);
        Assert.DoesNotContain("#line", result);
    }

    [Fact]
    public void TestLineDirectivesEmittedForStatements()
    {
        var source = @"
func Main() {
    x := 42
    print x
}";
        var result = TranspileWithDebugInfo(source);
        Assert.Contains("#line", result);
        Assert.Contains("\"test.nl\"", result);
    }

    [Fact]
    public void TestLineDefaultAtEnd()
    {
        var source = @"
func Main() {
    x := 42
}";
        var result = TranspileWithDebugInfo(source);
        Assert.EndsWith("#line default\n", result);
    }

    [Fact]
    public void TestLineHiddenForProgramClassScaffolding()
    {
        var source = @"
func Main() {
    x := 42
}";
        var result = TranspileWithDebugInfo(source);
        // Program class scaffolding should be hidden via #line hidden
        Assert.Contains("#line hidden", result);
        Assert.Contains("public partial class Program", result);
        // Should NOT use [DebuggerNonUserCode] on wrapper classes — it would mark user methods as non-user code
        Assert.DoesNotContain("[DebuggerNonUserCode]", result);
    }

    [Fact]
    public void TestLineHiddenForFunctionsClassScaffolding()
    {
        var source = @"
func add(a: int, b: int): int {
    return a + b
}";
        var result = TranspileWithDebugInfo(source);
        // Functions wrapper class should be hidden via #line hidden
        Assert.Contains("#line hidden", result);
        Assert.DoesNotContain("[DebuggerNonUserCode]", result);
        // The function itself should have a #line directive
        Assert.Contains("#line 2 \"test.nl\"", result);
    }

    [Fact]
    public void TestLineHiddenForTestClassScaffolding()
    {
        var source = @"
test ""my test"" {
    assert 1 == 1
}";
        var result = TranspileWithDebugInfo(source);
        // Test class wrapper should be hidden via #line hidden
        Assert.Contains("#line hidden", result);
        Assert.DoesNotContain("[DebuggerNonUserCode]", result);
        Assert.Contains("public class Tests", result);
    }

    [Fact]
    public void TestLineHiddenErrorHandlingTryCatch()
    {
        var source = @"
func riskyCall(): int {
    return 42
}

func Main() {
    result, err := riskyCall()
}";
        var result = TranspileWithDebugInfo(source);
        // Error handling scaffolding should have #line hidden
        Assert.Contains("#line hidden", result);
        // But the actual function call should still map to source
        Assert.Contains("riskyCall()", result);
    }

    [Fact]
    public void TestLambdaBlockBodyNoInlineLineDirectives()
    {
        var source = @"
func Main() {
    action := () => {
        x := 42
    }
}";
        var result = TranspileWithDebugInfo(source);
        // The lambda body should not contain #line directives (they'd break C# syntax)
        var lambdaStart = result.IndexOf("() =>");
        if (lambdaStart >= 0)
        {
            // Find the lambda block body
            var afterLambda = result.Substring(lambdaStart);
            var braceStart = afterLambda.IndexOf('{');
            var braceEnd = afterLambda.IndexOf('}');
            if (braceStart >= 0 && braceEnd > braceStart)
            {
                var lambdaBody = afterLambda.Substring(braceStart, braceEnd - braceStart + 1);
                Assert.DoesNotContain("#line", lambdaBody);
            }
        }
    }

    [Fact]
    public void TestSwitchCaseLineDirectives()
    {
        var source = @"
func Main() {
    x := 5
    switch x {
        case 1 => print 1
        case 2 => print 2
        default => print 0
    }
}";
        var result = TranspileWithDebugInfo(source);
        // Each case should have a #line directive for its line
        Assert.Contains("case 1:", result);
        Assert.Contains("default:", result);
        // The auto-generated break; should be hidden
        var lines = result.Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            if (lines[i].Trim() == "break;")
            {
                // The line before break should be #line hidden or preceded by it
                var precedingContent = string.Join("\n", lines.Take(i));
                // At minimum, there should be #line hidden somewhere before each break
                Assert.Contains("#line hidden", precedingContent);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Warning suppression tests
    // -----------------------------------------------------------------------

    /// <summary>
    /// Transpile helper that runs the analyzer first (like the real build pipeline),
    /// so that IsExhaustive flags are set on match expressions.
    /// </summary>
    private static string TranspileWithAnalysis(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var parseResult = parser.ParseCompilationUnit();
        var unit = parseResult.CompilationUnit!;

        // Run the analyzer to set IsExhaustive and other semantic flags
        using var analyzer = new Analyzer();
        analyzer.Analyze(unit, "test.nl", null, source);

        var transpiler = new Transpiler(unit);
        return transpiler.Transpile();
    }

    [Fact]
    public void TestExhaustiveUnionMatch_EmitsDiscardArm()
    {
        var source = @"
union Result {
    Success { value: int }
    Failure { error: string }
}

func ProcessResult(r: Result): string {
    return match r {
        Result.Success { value } => $""ok: {value}"",
        Result.Failure { error } => $""err: {error}""
    }
}
        ";

        var result = TranspileWithAnalysis(source);

        // Exhaustive union match should have a discard arm, not a pragma
        Assert.Contains("_ => throw new System.InvalidOperationException(\"Unreachable\")", result);
        Assert.DoesNotContain("#pragma warning disable CS8509", result);
    }

    [Fact]
    public void TestExhaustiveUnionMatch_WithWildcard_NoDiscardArm()
    {
        var source = @"
union Shape {
    Circle { radius: float }
    Square { side: float }
}

func Describe(s: Shape): string {
    return match s {
        Shape.Circle { radius } => $""circle r={radius}"",
        _ => ""other""
    }
}
        ";

        var result = TranspileWithAnalysis(source);

        // Match has an explicit wildcard — should NOT add a second discard arm
        Assert.DoesNotContain("InvalidOperationException", result);
        Assert.DoesNotContain("#pragma warning disable CS8509", result);
        Assert.Contains("_ => \"other\"", result);
    }

    [Fact]
    public void TestNonExhaustiveMatch_EmitsPragma()
    {
        // Match on a non-union type with no wildcard — non-exhaustive by design
        var source = @"
func Describe(x: int): string {
    return match x {
        1 => ""one"",
        2 => ""two""
    }
}
        ";

        var result = Transpile(source);

        // Non-exhaustive match without wildcard should get pragma suppression
        Assert.Contains("#pragma warning disable CS8509", result);
        Assert.Contains("#pragma warning restore CS8509", result);
        // Should NOT have a discard arm
        Assert.DoesNotContain("InvalidOperationException", result);
    }

    [Fact]
    public void TestErrorTupleLowering_EmitsNullabilityPragma()
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

        // Error tuple lowering should wrap with nullability pragma
        Assert.Contains("#pragma warning disable CS8600, CS8601", result);
        Assert.Contains("#pragma warning restore CS8600, CS8601", result);

        // The pragma should wrap only the variable declarations, not the user's code
        var disableIdx = result.IndexOf("#pragma warning disable CS8600");
        var restoreIdx = result.IndexOf("#pragma warning restore CS8600");
        var tryIdx = result.IndexOf("try");

        Assert.True(disableIdx < restoreIdx, "Pragma disable should appear before restore");
        Assert.True(restoreIdx < tryIdx, "Pragma restore should appear before try (only declarations suppressed)");
    }

    [Fact]
    public void TestFieldWithoutInitializer_EmitsDefaultBang()
    {
        var source = @"
class Person {
    Name: string
    Age: int
}
        ";

        var result = Transpile(source);

        // Fields without initializers should use = default!; to suppress CS8618
        Assert.Contains("Name { get; set; } = default!;", result);
        Assert.Contains("Age { get; set; } = default!;", result);
    }

    [Fact]
    public void TestFieldWithInitializer_NoDefaultBang()
    {
        var source = @"
class Config {
    Name: string = ""default""
    Count: int = 0
}
        ";

        var result = Transpile(source);

        // Fields WITH initializers should keep their initializer, not default!
        Assert.Contains("Name { get; set; } = \"default\";", result);
        Assert.Contains("Count { get; set; } = 0;", result);
        // Only one occurrence of each field — no double default!
        Assert.DoesNotContain("default!", result);
    }

    [Fact]
    public void TestWarningSuppressionIsTargeted_NotBlanket()
    {
        // This test verifies that suppression is scoped, not file-level.
        // The pragma disable/restore pairs are matched, so warnings outside
        // the suppressed region are still active.
        var source = @"
func MightFail(): string {
    throw new Exception(""oops"")
}

func Test() {
    result, err := MightFail()
    x := 10
}
        ";

        var result = Transpile(source);

        // The pragma pair should be matched (disable + restore)
        var disableCount = CountOccurrences(result, "#pragma warning disable CS8600, CS8601");
        var restoreCount = CountOccurrences(result, "#pragma warning restore CS8600, CS8601");
        Assert.Equal(disableCount, restoreCount);
        Assert.True(disableCount > 0, "Should have at least one pragma disable for error tuple");

        // No file-level or project-level suppression
        Assert.DoesNotContain("NoWarn", result);
        Assert.DoesNotContain("#pragma warning disable\n", result); // No blanket disable-all
    }

    [Fact]
    public void TestIntEnumEmitsJsonStringEnumConverter()
    {
        var source = @"
enum Priority {
    Low,
    Medium,
    High
}
        ";

        var result = Transpile(source);

        Assert.Contains("using System.Text.Json.Serialization;", result);
        Assert.Contains("[JsonConverter(typeof(JsonStringEnumConverter))]", result);
        Assert.Contains("public enum Priority", result);
    }

    [Fact]
    public void TestStringEnumEmitsOwnJsonConverter()
    {
        var source = @"
enum Status: string {
    Active = ""active"",
    Inactive = ""inactive""
}
        ";

        var result = Transpile(source);

        // String enums transpile to readonly struct with their own nested JsonConverter
        Assert.Contains("JsonConverter(typeof(StatusJsonConverter))", result);
        Assert.Contains("readonly struct Status", result);
        Assert.DoesNotContain("static class Status", result);
    }

    [Fact]
    public void TestUnionEmitsPolymorphicJsonAttributes()
    {
        var source = @"
union Result {
    Success { value: int }
    Failure { error: string }
}
        ";

        var result = Transpile(source);

        Assert.Contains("using System.Text.Json.Serialization;", result);
        Assert.Contains("[JsonPolymorphic(TypeDiscriminatorPropertyName = \"$type\")]", result);
        Assert.Contains("[JsonDerivedType(typeof(Result.Success), \"Success\")]", result);
        Assert.Contains("[JsonDerivedType(typeof(Result.Failure), \"Failure\")]", result);
        Assert.Contains("public abstract record Result", result);
    }

    [Fact]
    public void TestUnionWithNoCasesEmitsPolymorphicAttribute()
    {
        var source = @"
union Empty {
}
        ";

        var result = Transpile(source);

        Assert.Contains("[JsonPolymorphic(TypeDiscriminatorPropertyName = \"$type\")]", result);
        Assert.DoesNotContain("[JsonDerivedType", result);
    }

    [Fact]
    public void TestFileEnumStillEmitsJsonConverter()
    {
        var source = @"
file enum Status {
    Active,
    Inactive
}
        ";

        var result = Transpile(source);

        Assert.Contains("[JsonConverter(typeof(JsonStringEnumConverter))]", result);
        Assert.Contains("file enum Status", result);
    }

    [Fact]
    public void TestFileUnionStillEmitsPolymorphicAttributes()
    {
        var source = @"
file union Result {
    Success { value: int }
    Failure { error: string }
}
        ";

        var result = Transpile(source);

        Assert.Contains("[JsonPolymorphic(TypeDiscriminatorPropertyName = \"$type\")]", result);
        Assert.Contains("[JsonDerivedType(typeof(Result.Success), \"Success\")]", result);
        Assert.Contains("[JsonDerivedType(typeof(Result.Failure), \"Failure\")]", result);
        Assert.Contains("file abstract record Result", result);
    }

    [Fact]
    public void TestNestedEnumInClassEmitsJsonUsing()
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

        Assert.Contains("using System.Text.Json.Serialization;", result);
        Assert.Contains("[JsonConverter(typeof(JsonStringEnumConverter))]", result);
    }

    [Fact]
    public void TestNoJsonUsingWhenNoEnumsOrUnions()
    {
        var source = @"
func main() {
    println(""hello"")
}
        ";

        var result = Transpile(source);

        Assert.DoesNotContain("System.Text.Json.Serialization", result);
    }

    [Fact]
    public void TestJsonConverterAppearsBeforeEnumDeclaration()
    {
        var source = @"
enum Priority {
    Low,
    Medium,
    High
}
        ";

        var result = Transpile(source);

        // JsonConverter attribute must appear before the enum declaration
        var converterIndex = result.IndexOf("[JsonConverter(typeof(JsonStringEnumConverter))]");
        var enumIndex = result.IndexOf("public enum Priority");
        Assert.True(converterIndex >= 0, "JsonConverter attribute should be present");
        Assert.True(enumIndex >= 0, "enum declaration should be present");
        Assert.True(converterIndex < enumIndex, "JsonConverter should appear before enum declaration");
    }

    [Fact]
    public void TestPolymorphicAttributesAppearBeforeUnionDeclaration()
    {
        var source = @"
union Shape {
    Circle { radius: float }
    Rectangle { width: float, height: float }
}
        ";

        var result = Transpile(source);

        var polymorphicIndex = result.IndexOf("[JsonPolymorphic");
        var derivedCircle = result.IndexOf("[JsonDerivedType(typeof(Shape.Circle)");
        var derivedRect = result.IndexOf("[JsonDerivedType(typeof(Shape.Rectangle)");
        var recordIndex = result.IndexOf("public abstract record Shape");

        Assert.True(polymorphicIndex >= 0);
        Assert.True(derivedCircle >= 0);
        Assert.True(derivedRect >= 0);
        Assert.True(recordIndex >= 0);
        Assert.True(polymorphicIndex < derivedCircle);
        Assert.True(derivedCircle < derivedRect);
        Assert.True(derivedRect < recordIndex);
    }

    private static int CountOccurrences(string text, string pattern)
    {
        int count = 0;
        int index = 0;
        while ((index = text.IndexOf(pattern, index, StringComparison.Ordinal)) != -1)
        {
            count++;
            index += pattern.Length;
        }
        return count;
    }

    // ── Bug regression tests ────────────────────────────────────────────

    [Fact]
    public void TestNewArrayInitializerSyntax()
    {
        // Bug 075: new string[] { "a", "b" } was parsed as object initializer
        var source = @"
func Test() {
    names := new string[] { ""Alice"", ""Bob"", ""Charlie"" }
}
        ";
        var result = Transpile(source);
        Assert.Contains("new string[] { \"Alice\", \"Bob\", \"Charlie\" }", result);
    }

    [Fact]
    public void TestNewIntArrayInitializerSyntax()
    {
        // Bug 075: array initializer with int values
        var source = @"
func Test() {
    nums := new int[] { 1, 2, 3 }
}
        ";
        var result = Transpile(source);
        Assert.Contains("new int[] { 1, 2, 3 }", result);
    }

    [Fact]
    public void TestIntParseTranspilation()
    {
        // Bug 001: int.Parse should transpile as-is (C# resolves int to System.Int32)
        var source = @"
func Main() {
    x := int.Parse(""42"")
}
        ";
        var result = Transpile(source);
        Assert.Contains("int.Parse(\"42\")", result);
    }

    [Fact]
    public void TestIntTryParseWithOutVarTranspilation()
    {
        // Bug 076: int.TryParse with out var should work
        var source = @"
func Main() {
    if int.TryParse(""123"", out var result) {
        print result
    }
}
        ";
        var result = Transpile(source);
        Assert.Contains("int.TryParse(\"123\", out var result)", result);
    }

    [Fact]
    public void TestOverloadedMethodsInClassTranspilation()
    {
        // Bug 074: multiple overloads with different arities in a class
        var source = @"
class Helper {
    static func Format(a: string): string {
        return a
    }
    static func Format(a: string, b: string): string {
        return a
    }
    static func Format(a: string, b: string, c: string): string {
        return a
    }
}
        ";
        var result = Transpile(source);
        // All three overloads should be emitted
        Assert.Contains("Format(string a)", result);
        Assert.Contains("Format(string a, string b)", result);
        Assert.Contains("Format(string a, string b, string c)", result);
    }

    #region String Enum Transpilation

    [Fact]
    public void TestStringEnumTranspilesToReadonlyStruct()
    {
        var source = @"
enum Status: string {
    Active = ""active"",
    Inactive = ""inactive""
}
        ";

        var result = Transpile(source);

        Assert.Contains("readonly struct Status : System.IEquatable<Status>", result);
        Assert.Contains("public static readonly Status Active = new Status(\"active\")", result);
        Assert.Contains("public static readonly Status Inactive = new Status(\"inactive\")", result);
        Assert.Contains("public string Value { get; }", result);
        Assert.Contains("private Status(string value) => Value = value;", result);
        Assert.Contains("public static implicit operator string(Status value) => value.Value;", result);
        Assert.Contains("public bool Equals(Status other) => Value == other.Value;", result);
        Assert.Contains("public static bool operator ==(Status left, Status right) => left.Equals(right);", result);
        Assert.Contains("public static bool operator !=(Status left, Status right) => !left.Equals(right);", result);
        Assert.DoesNotContain("static class", result);
        Assert.DoesNotContain("const string", result);
    }

    [Fact]
    public void TestStringEnumHasJsonConverter()
    {
        var source = @"
enum Color: string {
    Red = ""red"",
    Blue = ""blue""
}
        ";

        var result = Transpile(source);

        Assert.Contains("[System.Text.Json.Serialization.JsonConverter(typeof(ColorJsonConverter))]", result);
        Assert.Contains("private sealed class ColorJsonConverter : System.Text.Json.Serialization.JsonConverter<Color>", result);
        Assert.Contains("reader.GetString()!", result);
        Assert.Contains("writer.WriteStringValue(value.Value)", result);
    }

    [Fact]
    public void TestStringEnumDefaultValueUsesName()
    {
        var source = @"
enum Direction: string {
    North,
    South
}
        ";

        var result = Transpile(source);

        Assert.Contains("public static readonly Direction North = new Direction(\"North\")", result);
        Assert.Contains("public static readonly Direction South = new Direction(\"South\")", result);
    }

    [Fact]
    public void TestStringEnumPatternMatchUsesWhenGuard()
    {
        var source = @"
enum Status: string {
    Active = ""active"",
    Inactive = ""inactive""
}

func Describe(s: Status): string {
    return match s {
        Status.Active => ""yes"",
        Status.Inactive => ""no""
    }
}
        ";

        var result = Transpile(source);

        Assert.Contains("var _se0 when _se0 == Status.Active", result);
        Assert.Contains("var _se1 when _se1 == Status.Inactive", result);
        // Bare constant patterns (without when guard) should not appear
        Assert.DoesNotContain("Status.Active,", result);
        Assert.DoesNotContain("Status.Inactive,", result);
    }

    [Fact]
    public void TestStringEnumOrPatternUsesWhenGuard()
    {
        var source = @"
enum Status: string {
    Active = ""active"",
    Inactive = ""inactive"",
    Pending = ""pending""
}

func Describe(s: Status): string {
    return match s {
        Status.Active or Status.Pending => ""present"",
        Status.Inactive => ""absent""
    }
}
        ";

        var result = Transpile(source);

        // Or-pattern should be decomposed into when-guard with ||
        Assert.Contains("var _se0 when (_se0 == Status.Active || _se0 == Status.Pending)", result);
        Assert.Contains("var _se1 when _se1 == Status.Inactive", result);
    }

    [Fact]
    public void TestIntEnumNotAffected()
    {
        var source = @"
enum Priority {
    Low = 0,
    High = 1
}
        ";

        var result = Transpile(source);

        Assert.Contains("enum Priority", result);
        Assert.DoesNotContain("readonly struct", result);
        // Int enums use JsonStringEnumConverter, not a custom nested converter
        Assert.DoesNotContain("PriorityJsonConverter", result);
    }

    #endregion

}
