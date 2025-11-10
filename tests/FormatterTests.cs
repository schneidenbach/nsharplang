using System;
using System.Linq;
using NewCLILang.Compiler;
using NewCLILang.Compiler.Ast;
using Xunit;

namespace NewCLILang.Tests;

public class FormatterTests
{
    private static CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        return parser.ParseCompilationUnit();
    }

    private static string Format(string source)
    {
        var ast = Parse(source);
        var formatter = new Formatter();
        return formatter.Format(ast);
    }

    [Fact]
    public void Format_FixesIndentation()
    {
        var input = "func main(){print 5}";
        var expected = @"func main() {
    print 5
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_SimpleFunction()
    {
        var input = @"func Add(x: int, y: int): int {
return x + y
}";
        var expected = @"func Add(x: int, y: int): int {
    return x + y
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_FunctionWithMultipleStatements()
    {
        var input = @"func Calculate(x: int): int {
z := x * 2
w := z + 1
return w
}";
        var expected = @"func Calculate(x: int): int {
    z := x * 2
    w := z + 1
    return w
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_NestedBlocks()
    {
        var input = @"func Test(x: int): int {
if x > 0 {
return x
} else {
return -x
}
}";
        var expected = @"func Test(x: int): int {
    if x > 0 {
        return x
    } else {
        return -x
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Class()
    {
        var input = @"class Person {
Name: string
Age: int
}";
        var expected = @"class Person {
    Name: string
    Age: int
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_ClassWithMethods()
    {
        var input = @"class Calculator {
func Add(x: int, y: int): int {
return x + y
}
}";
        var expected = @"class Calculator {
    func Add(x: int, y: int): int {
        return x + y
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_ExpressionBodiedFunction()
    {
        var input = @"func Double(x: int): int => x * 2";
        var expected = @"func Double(x: int): int => x * 2";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_BinaryOperators_WithSpacing()
    {
        var input = @"func Test(): int {
x := 1+2*3
return x
}";
        var expected = @"func Test(): int {
    x := 1 + 2 * 3
    return x
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_ForLoop()
    {
        var input = @"func Loop() {
for i = 0; i < 10; i = i + 1 {
print i
}
}";
        var expected = @"func Loop() {
    for i = 0; i < 10; i = i + 1 {
        print i
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_ForeachLoop()
    {
        var input = @"func Loop(items: int[]) {
foreach item in items {
print item
}
}";
        var expected = @"func Loop(items: int[]) {
    foreach item in items {
        print item
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_WhileLoop()
    {
        var input = @"func Loop() {
i := 0
while i < 10 {
print i
i = i + 1
}
}";
        var expected = @"func Loop() {
    i := 0
    while i < 10 {
        print i
        i = i + 1
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_IfElseIf()
    {
        var input = @"func Test(x: int): string {
if x > 0 {
return ""positive""
} else if x < 0 {
return ""negative""
} else {
return ""zero""
}
}";
        var expected = @"func Test(x: int): string {
    if x > 0 {
        return ""positive""
    } else if x < 0 {
        return ""negative""
    } else {
        return ""zero""
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Union()
    {
        var input = @"union Result {
Success(value: int)
Error(message: string)
}";
        var expected = @"union Result {
    Success(value: int)
    Error(message: string)
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Enum()
    {
        var input = @"enum Color {
Red,
Green,
Blue
}";
        var expected = @"enum Color {
    Red,
    Green,
    Blue
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Interface()
    {
        var input = @"interface ICalculator {
Add(x: int, y: int): int
}";
        var expected = @"interface ICalculator {
    func Add(x: int, y: int): int
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_MatchExpression()
    {
        var input = @"func Test(x: int): string {
return x match {
0 => ""zero""
1 => ""one""
_ => ""other""
}
}";
        var expected = @"func Test(x: int): string {
    return x match {
        0 => ""zero""
        1 => ""one""
        _ => ""other""
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Lambda()
    {
        var input = @"func Test() {
f := (x: int) => x * 2
print f(5)
}";
        var expected = @"func Test() {
    f := (x: int) => x * 2
    print f(5)
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Array()
    {
        var input = @"func Test() {
arr := [1,2,3]
print arr
}";
        var expected = @"func Test() {
    arr := [1, 2, 3]
    print arr
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_TryCatch()
    {
        var input = @"func Test() {
try {
print ""trying""
} catch Exception e {
print e
}
}";
        var expected = @"func Test() {
    try {
        print ""trying""
    } catch Exception e {
        print e
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_PackageAndNamespace()
    {
        var input = @"package MyPackage
namespace MyApp.Core

func Main() {
print ""hello""
}";
        var expected = @"package MyPackage

namespace MyApp.Core

func Main() {
    print ""hello""
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Imports()
    {
        var input = @"import System.Collections.Generic
import System.Linq

func Main() {
print ""hello""
}";
        var expected = @"import System.Collections.Generic
import System.Linq

func Main() {
    print ""hello""
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_FunctionCall()
    {
        var input = @"func Test() {
result := Add(1,2,3)
print result
}";
        var expected = @"func Test() {
    result := Add(1, 2, 3)
    print result
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_MemberAccess()
    {
        var input = @"func Test() {
x := person.name.length
return x
}";
        var expected = @"func Test() {
    x := person.name.length
    return x
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_NewExpression()
    {
        var input = @"func Test() {
p := new Person(""John"",30)
return p
}";
        var expected = @"func Test() {
    p := new Person(""John"", 30)
    return p
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Tuple()
    {
        var input = @"func Test() {
t := (1,2,3)
return t
}";
        var expected = @"func Test() {
    t := (1, 2, 3)
    return t
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_TupleDeconstruction()
    {
        var input = @"func Test() {
(x,y) := GetPair()
return x + y
}";
        var expected = @"func Test() {
    (x, y) := GetPair()
    return x + y
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_StaticFunction()
    {
        var input = @"static func Main() {
print ""hello""
}";
        var expected = @"static func Main() {
    print ""hello""
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_PublicClass()
    {
        var input = @"public class MyClass {
Value: int
}";
        var expected = @"public class MyClass {
    Value: int
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_AsyncFunction()
    {
        var input = @"async func GetData(): Task<string> {
result := await FetchData()
return result
}";
        var expected = @"async func GetData(): Task<string> {
    result := await FetchData()
    return result
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_YieldStatement()
    {
        var input = @"func* Generate(): IEnumerable<int> {
yield 1
yield 2
yield 3
}";
        var expected = @"func* Generate(): IEnumerable<int> {
    yield 1
    yield 2
    yield 3
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_WithExpression()
    {
        var input = @"func Test(p: Person): Person {
return p with { Age = 30 }
}";
        var expected = @"func Test(p: Person): Person {
    return p with { Age = 30 }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_RangeExpression()
    {
        var input = @"func Test() {
r := 0..10
return r
}";
        var expected = @"func Test() {
    r := 0..10
    return r
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_NullCoalescing()
    {
        var input = @"func Test(x: string?): string {
return x ?? ""default""
}";
        var expected = @"func Test(x: string?): string {
    return x ?? ""default""
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_NullConditionalAccess()
    {
        var input = @"func Test(p: Person?): string? {
return p?.Name
}";
        var expected = @"func Test(p: Person?): string? {
    return p?.Name
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_GenericFunction()
    {
        var input = @"func Identity<T>(x: T): T {
return x
}";
        var expected = @"func Identity<T>(x: T): T {
    return x
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_GenericClass()
    {
        var input = @"class Container<T> {
Value: T
}";
        var expected = @"class Container<T> {
    Value: T
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Record()
    {
        var input = @"record Person(Name: string, Age: int)";
        var expected = @"record Person(Name: string, Age: int)";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Struct()
    {
        var input = @"struct Point {
X: int
Y: int
}";
        var expected = @"struct Point {
    X: int
    Y: int
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }
}
