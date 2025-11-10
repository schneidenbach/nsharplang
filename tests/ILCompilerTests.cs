using System;
using System.IO;
using System.Linq;
using System.Reflection;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.ILCompiler;
using Xunit;

namespace NSharpLang.Tests;

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

    [Fact]
    public void ILCompiler_CanCompileGenericFunction()
    {
        var source = @"
func identity<T>(value: T): T {
    return value
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileGenericFunctionWithConstraint()
    {
        var source = @"
func compare<T>(a: T, b: T): int where T: IComparable<T> {
    return a.CompareTo(b)
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileGenericFunctionWithMultipleParameters()
    {
        var source = @"
func swap<T, U>(first: T, second: U): bool {
    return true
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileGenericFunctionWithLocalVariables()
    {
        var source = @"
func process<T>(value: T): T {
    temp := value
    return temp
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileForeachOverArray()
    {
        var source = @"
func sumArray(numbers: int[]): int {
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileForeachWithPrint()
    {
        var source = @"
func printArray(numbers: int[]) {
    foreach num in numbers {
        print num
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileForeachOverList()
    {
        var source = @"
import System.Collections.Generic

func countList(items: List<int>): int {
    count := 0
    foreach item in items {
        count = count + 1
    }
    return count
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileNestedForeach()
    {
        var source = @"
func nestedLoops(matrix: int[][]) {
    foreach row in matrix {
        foreach cell in row {
            print cell
        }
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryCatch()
    {
        var source = @"
func safeDivide(x: int, y: int): int {
    try {
        return x + y
    } catch (Exception e) {
        print e
        return 0
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryCatchWithoutVariable()
    {
        var source = @"
func safeDivide(x: int, y: int): int {
    try {
        return x + y
    } catch (Exception) {
        return 1
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryFinally()
    {
        var source = @"
func doWork(): int {
    x := 0
    try {
        x = 42
        return x
    } finally {
        print ""cleanup""
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryCatchFinally()
    {
        var source = @"
func complexOperation(): int {
    try {
        x := 10 + 2
        return x
    } catch (Exception e) {
        print e
        return 1
    } finally {
        print ""done""
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileMultipleCatchClauses()
    {
        var source = @"
func handleErrors(): int {
    try {
        x := 10 + 5
        return x
    } catch (DivideByZeroException) {
        return 1
    } catch (Exception e) {
        print e
        return 2
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileNestedTryCatch()
    {
        var source = @"
func nestedExceptionHandling(): int {
    try {
        try {
            return 10 + 5
        } catch (DivideByZeroException) {
            return 1
        }
    } catch (Exception e) {
        print e
        return 2
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryCatchWithLocalVariables()
    {
        var source = @"
func testWithLocals(): int {
    result := 0
    try {
        x := 10
        y := 2
        result = x + y
    } catch (Exception e) {
        print e
        result = 1
    } finally {
        print result
    }
    return result
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    // ==================== Interface Tests ====================

    [Fact]
    public void ILCompiler_CanCompileSimpleInterface()
    {
        var source = @"
interface IReader {
    func Read(): string
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileInterfaceWithMultipleMethods()
    {
        var source = @"
interface IRepository {
    func Get(id: int): string
    func Save(value: string): void
    func Delete(id: int): bool
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassImplementingInterface()
    {
        var source = @"
interface IGreeter {
    func Greet(): string
}

class SimpleGreeter : IGreeter {
    func Greet(): string {
        return ""Hello""
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassImplementingMultipleInterfaces()
    {
        var source = @"
interface IReader {
    func Read(): string
}

interface IWriter {
    func Write(value: string): void
}

class ReadWriter : IReader, IWriter {
    func Read(): string {
        return ""data""
    }

    func Write(value: string): void {
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_SkipsDuckInterfaces()
    {
        var source = @"
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string {
        return ""file contents""
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw - duck interface should be skipped
        compiler.Compile();
    }

    // ==================== Virtual Method Tests ====================

    [Fact]
    public void ILCompiler_CanCompileVirtualMethod()
    {
        var source = @"
class Animal {
    virtual func MakeSound(): void {
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileVirtualMethodWithReturn()
    {
        var source = @"
class Base {
    virtual func GetValue(): int {
        return 0
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileOverrideMethod()
    {
        var source = @"
class Animal {
    virtual func MakeSound(): void {
    }
}

class Dog : Animal {
    override func MakeSound(): void {
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileOverrideMethodWithReturnValue()
    {
        var source = @"
class Base {
    virtual func GetValue(): int {
        return 0
    }
}

class Derived : Base {
    override func GetValue(): int {
        return 42
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileInheritanceChainWithVirtualMethods()
    {
        var source = @"
class A {
    virtual func DoWork(): void {
    }
}

class B : A {
    override func DoWork(): void {
    }
}

class C : B {
    override func DoWork(): void {
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassWithBaseClass()
    {
        var source = @"
class Animal {
    Name: string

    func GetName(): string {
        return Name
    }
}

class Dog : Animal {
    Breed: string
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassWithBaseAndInterfaces()
    {
        var source = @"
interface IGreeter {
    func Greet(): string
}

class Animal {
    Name: string
}

class Dog : Animal, IGreeter {
    func Greet(): string {
        return ""Woof""
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact(Skip = "IL compiler doesn't support using statements with constructor calls followed by blocks yet - parser sees 'new Resource() {' and thinks it's an object initializer")]
    public void ILCompiler_CanCompileSimpleUsingStatement()
    {
        var source = @"
class Resource {
    func Dispose(): void {
    }

    static func Create(): Resource => new Resource()
}

func Test(): void {
    using r := Resource.Create() {
        x := 1
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithLiteralPatterns()
    {
        var source = @"
func testMatch(x: int): string {
    result := match x {
        0 => ""zero"",
        1 => ""one"",
        2 => ""two"",
        _ => ""other""
    }
    return result
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithStringLiterals()
    {
        var source = @"
func greet(name: string): string {
    message := match name {
        ""Alice"" => ""Hello Alice!"",
        ""Bob"" => ""Hi Bob!"",
        _ => ""Hello stranger!""
    }
    return message
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithVariableBinding()
    {
        var source = @"
func processValue(x: int): int {
    result := match x {
        0 => 100,
        n => n * 2
    }
    return result
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithTypePattern()
    {
        var source = @"
func getTypeName(obj: object): string {
    name := match obj {
        string => ""It's a string"",
        int => ""It's an int"",
        _ => ""Unknown type""
    }
    return name
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithGuard()
    {
        var source = @"
func classifyNumber(x: int): string {
    result := match x {
        n when n < 0 => ""negative"",
        0 => ""zero"",
        n when n > 0 => ""positive"",
        _ => ""unknown""
    }
    return result
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithRelationalPattern()
    {
        var source = @"
func getRange(x: int): string {
    result := match x {
        < 0 => ""negative"",
        0 => ""zero"",
        > 0 => ""positive""
    }
    return result
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionInReturnStatement()
    {
        var source = @"
func doubleOrZero(x: int): int {
    return match x {
        0 => 0,
        n => n * 2
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileNestedMatchExpressions()
    {
        var source = @"
func classify(x: int, y: int): string {
    return match x {
        0 => match y {
            0 => ""both zero"",
            _ => ""x is zero""
        },
        _ => match y {
            0 => ""y is zero"",
            _ => ""neither zero""
        }
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileSimpleRecord()
    {
        var source = @"
record Person {
    Name: string
    Age: int
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileRecordWithPrimaryConstructor()
    {
        var source = @"
record Point(x: int, y: int) {}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileRecordStruct()
    {
        var source = @"
record struct Point {
    X: int
    Y: int
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileRecordStructWithPrimaryConstructor()
    {
        var source = @"
record struct Vector2D(x: int, y: int) {}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileRecordWithMethods()
    {
        var source = @"
record Person(name: string, age: int) {
    func GetInfo(): int {
        return 42
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileRecordWithInterface()
    {
        var source = @"
interface IIdentifiable {
    func GetId(): int
}

record Person(id: int, name: string): IIdentifiable {
    func GetId(): int {
        return 123
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileSimpleLambdaExpression()
    {
        var source = @"
func TestLambda() {
    add := (x, y) => x + y
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileSimpleLambdaBlock()
    {
        var source = @"
func TestLambda() {
    add := (x, y) => {
        return x + y
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileLambdaWithClosure()
    {
        var source = @"
func TestClosure() {
    multiplier := 5
    multiply := (x) => x * multiplier
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileLambdaWithMultipleCapturedVariables()
    {
        var source = @"
func TestMultipleCaptured() {
    a := 10
    b := 20
    add := (x) => x + a + b
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileNestedLambdas()
    {
        var source = @"
func TestNestedLambdas() {
    outer := (x) => {
        inner := (y) => x + y
        return x
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileLambdaWithNoParameters()
    {
        var source = @"
func TestNoParams() {
    getValue := () => 42
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileLambdaWithVoidReturn()
    {
        var source = @"
func TestVoidLambda() {
    action := (x) => {
        y := x + 1
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }
}
