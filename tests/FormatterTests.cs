using System;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class FormatterTests
{
    private static CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        return result.CompilationUnit!; // Tests expect valid syntax
    }

    private static string Format(string source)
    {
        var ast = Parse(source);
        var formatter = new Formatter();
        return formatter.Format(ast);
    }

    /// <summary>
    /// Format with comment preservation (uses lexer to extract comments).
    /// </summary>
    private static string FormatWithComments(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        var formatter = new Formatter();
        return formatter.Format(result.CompilationUnit!, lexer.Comments);
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
    for item in items {
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
Success { value: int }
Error { message: string }
}";
        var expected = @"union Result {
    Success { value: int }
    Error { message: string }
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
func Add(x: int, y: int): int
}";
        var expected = @"interface ICalculator {
    func Add(x: int, y: int): int
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_PreservesDeclarationAttributes()
    {
        var input = @"class Person {
[Column(""Last Name"")]
[StringLength(19)]
IdNumber: string = null
}";
        var expected = @"class Person {
    [Column(""Last Name"")]
    [StringLength(19)]
    IdNumber: string = null
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_MatchExpression()
    {
        var input = @"func Test(x: int): string {
return match x {
0 => ""zero"",
1 => ""one"",
_ => ""other""
}
}";
        var expected = @"func Test(x: int): string {
    return match x {
        0 => ""zero"",
        1 => ""one"",
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
f := x => x * 2
print f(5)
}";
        var expected = @"func Test() {
    f := x => x * 2
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
} catch (Exception e) {
print e
}
}";
        var expected = @"func Test() {
    try {
        print ""trying""
    } catch (Exception e) {
        print e
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_PackageAndNamespace()
    {
        var input = @"package MyApp.Core

func Main() {
print ""hello""
}";
        var expected = @"package MyApp.Core

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
    x, y := GetPair()
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
        var input = @"class MyClass {
Value: int
}";
        var expected = @"class MyClass {
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
    public void Format_LegacyPostfixAsyncFunctionCanonicalizes()
    {
        var input = @"func async GetData(): Task<string> {
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
    public void Format_OverrideAsyncFunctionKeepsAsyncAdjacentToFunc()
    {
        var input = @"class Repository : BaseRepository {
override async func GetData(): Task<string> {
return FetchData()
}
}";
        var expected = @"class Repository: BaseRepository {
    override async func GetData(): Task<string> {
        return FetchData()
    }
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
return p with { Age: 30 }
}";
        var expected = @"func Test(p: Person): Person {
    return p with { Age: 30 }
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
        var input = @"record Person {
Name: string
Age: int
}";
        var expected = @"record Person {
    Name: string
    Age: int
}";

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

    [Fact]
    public void FormatterConfig_DefaultIndent()
    {
        var config = new FormatterConfig();
        Assert.Equal(4, config.IndentSize);
        Assert.True(config.UseSpaces);
        Assert.Equal("    ", config.GetIndentString());
    }

    [Fact]
    public void FormatterConfig_TwoSpaces()
    {
        var config = new FormatterConfig { IndentSize = 2, UseSpaces = true };
        Assert.Equal("  ", config.GetIndentString());
    }

    [Fact]
    public void FormatterConfig_Tabs()
    {
        var config = new FormatterConfig { UseSpaces = false };
        Assert.Equal("\t", config.GetIndentString());
    }

    [Fact]
    public void Format_WithCustomIndent()
    {
        var input = "func main(){print 5}";
        var expected = @"func main() {
  print 5
}";

        var ast = Parse(input);
        var config = new FormatterConfig { IndentSize = 2, UseSpaces = true };
        var formatter = new Formatter(config);
        var result = formatter.Format(ast).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_WithTabs()
    {
        var input = "func main(){print 5}";
        var expected = "func main() {\n\tprint 5\n}";

        var ast = Parse(input);
        var config = new FormatterConfig { UseSpaces = false };
        var formatter = new Formatter(config);
        var result = formatter.Format(ast).Trim();
        Assert.Equal(expected, result);
    }

    // ── Idempotency tests ──────────────────────────────────────────────

    [Fact]
    public void Format_Idempotent_SimpleFunction()
    {
        var input = @"func Add(x: int, y: int): int {
    return x + y
}";
        var first = Format(input).Trim();
        var second = Format(first).Trim();
        Assert.Equal(first, second);
    }

    [Fact]
    public void Format_Idempotent_ClassWithMembers()
    {
        var input = @"class Calculator {
    func Add(x: int, y: int): int {
        return x + y
    }

    func Sub(x: int, y: int): int {
        return x - y
    }
}";
        var first = Format(input).Trim();
        var second = Format(first).Trim();
        Assert.Equal(first, second);
    }

    // ── Parenthesis preservation ────────────────────────────────────────

    [Fact]
    public void Format_PreservesParentheses()
    {
        var input = @"func Test(): int {
    return 2 * (x + y)
}";
        var expected = @"func Test(): int {
    return 2 * (x + y)
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_PreservesNestedParentheses()
    {
        var input = @"func Test(): int {
    return (a + b) * (c + d)
}";
        var expected = @"func Test(): int {
    return (a + b) * (c + d)
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── for...in canonical style ────────────────────────────────────────

    [Fact]
    public void Format_ForIn_Canonical()
    {
        var input = @"func Loop(items: int[]) {
for item in items {
print item
}
}";
        var expected = @"func Loop(items: int[]) {
    for item in items {
        print item
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_ForeachNormalizesToForIn()
    {
        // Both foreach and for...in should output canonical for...in
        var input = @"func Loop(items: int[]) {
foreach item in items {
print item
}
}";
        var expected = @"func Loop(items: int[]) {
    for item in items {
        print item
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Lambda formatting ───────────────────────────────────────────────

    [Fact]
    public void Format_LambdaSingleParam_NoType()
    {
        var input = @"func Test() {
f := x => x * 2
}";
        var expected = @"func Test() {
    f := x => x * 2
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_LambdaMultiParam()
    {
        var input = @"func Test() {
f := (x, y) => x + y
}";
        var expected = @"func Test() {
    f := (x, y) => x + y
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Target-typed new ────────────────────────────────────────────────

    [Fact]
    public void Format_TargetTypedNew_NoSpace()
    {
        var input = @"func Test(): Person {
return new(""Alice"", 30)
}";
        var expected = @"func Test(): Person {
    return new(""Alice"", 30)
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_NewWithType_HasSpace()
    {
        var input = @"func Test() {
p := new Person(""Alice"", 30)
}";
        var expected = @"func Test() {
    p := new Person(""Alice"", 30)
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Comment preservation ────────────────────────────────────────────

    [Fact]
    public void Format_PreservesComments_BeforeFunction()
    {
        var input = @"// This is a helper function
func Add(x: int, y: int): int {
    return x + y
}";
        var expected = @"// This is a helper function
func Add(x: int, y: int): int {
    return x + y
}";

        var result = FormatWithComments(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_PreservesComments_InsideFunction()
    {
        var input = @"func Test() {
    // Calculate result
    x := 1 + 2
    print x
}";
        var expected = @"func Test() {
    // Calculate result
    x := 1 + 2
    print x
}";

        var result = FormatWithComments(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_PreservesComments_BetweenDeclarations()
    {
        var input = @"// First function
func First() {
    print 1
}

// Second function
func Second() {
    print 2
}";
        var expected = @"// First function
func First() {
    print 1
}

// Second function
func Second() {
    print 2
}";

        var result = FormatWithComments(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Blank line preservation ─────────────────────────────────────────

    [Fact]
    public void Format_PreservesBlankLines_BetweenStatements()
    {
        var input = @"func Test() {
    x := 1

    y := 2
    print x + y
}";
        var expected = @"func Test() {
    x := 1

    y := 2
    print x + y
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Import sorting ──────────────────────────────────────────────────

    [Fact]
    public void Format_SortsImports_SystemFirst()
    {
        var input = @"import MyApp.Utils
import System.Linq
import System
import ThirdParty.Lib

func Main() {
    print ""hello""
}";
        var expected = @"import System
import System.Linq
import MyApp.Utils
import ThirdParty.Lib

func Main() {
    print ""hello""
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── String literals not mangled ─────────────────────────────────────

    [Fact]
    public void Format_InterpolatedString_NotMangled()
    {
        var input = @"func Test() {
    name := ""Alice""
    print $""Hello, {name}!""
}";
        var expected = @"func Test() {
    name := ""Alice""
    print $""Hello, {name}!""
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Match expression formatting ─────────────────────────────────────

    [Fact]
    public void Format_MatchExpression_Indented()
    {
        var input = @"func Test(x: int): string {
return match x {
0 => ""zero"",
1 => ""one"",
_ => ""other""
}
}";
        var expected = @"func Test(x: int): string {
    return match x {
        0 => ""zero"",
        1 => ""one"",
        _ => ""other""
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── C-style for loop still works ────────────────────────────────────

    [Fact]
    public void Format_CStyleForLoop()
    {
        var input = @"func Test() {
for i = 0; i < 10; i++ {
print i
}
}";
        var expected = @"func Test() {
    for i = 0; i < 10; i++ {
        print i
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Regression tests: bug-014 (union case formatting) ───────────

    [Fact]
    public void Format_UnionCases_UsesBraces_NotParens()
    {
        // Bug-014: formatter was emitting Success(value: int) which the parser rejects
        var input = @"union Shape {
Circle { radius: float }
Rectangle { width: float, height: float }
Point
}";
        var expected = @"union Shape {
    Circle { radius: float }
    Rectangle { width: float, height: float }
    Point
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_UnionCases_RoundTrip()
    {
        // The formatted output must re-parse without errors
        var input = @"union Result {
Success { value: int }
Error { message: string }
}";
        var formatted = Format(input).Trim();
        // Re-parse the formatted output
        var lexer = new Lexer(formatted, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        Assert.Empty(result.Errors.Where(e => e.Severity == Compiler.ErrorSeverity.Error));
    }

    // ── Regression tests: bug-015 (match expression formatting) ─────

    [Fact]
    public void Format_ReturnMatch_UsesMatchPrefix()
    {
        // Bug-015: formatter was emitting `return x match {` which the parser rejects
        var input = @"func Test(x: int): string {
return match x {
0 => ""zero"",
_ => ""other""
}
}";
        var expected = @"func Test(x: int): string {
    return match x {
        0 => ""zero"",
        _ => ""other""
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_MatchExpression_HasCommasBetweenCases()
    {
        var input = @"func Test(x: int): string {
return match x {
0 => ""zero"",
1 => ""one"",
_ => ""other""
}
}";
        var formatted = Format(input).Trim();
        // Verify commas between cases (but not after last)
        Assert.Contains(@"0 => ""zero"",", formatted);
        Assert.Contains(@"1 => ""one"",", formatted);
        // Last case should NOT have a trailing comma
        Assert.Contains(@"_ => ""other""", formatted);
        Assert.DoesNotContain(@"_ => ""other"",", formatted);
    }

    [Fact]
    public void Format_MatchExpression_RoundTrip()
    {
        var input = @"func Test(x: int): string {
return match x {
0 => ""zero"",
1 => ""one"",
_ => ""other""
}
}";
        var formatted = Format(input).Trim();
        var lexer = new Lexer(formatted, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        Assert.Empty(result.Errors.Where(e => e.Severity == Compiler.ErrorSeverity.Error));
    }

    [Fact]
    public void Format_MatchWithGuard()
    {
        var input = @"func Test(x: int): string {
return match x {
_ when x > 0 => ""positive"",
_ => ""non-positive""
}
}";
        var expected = @"func Test(x: int): string {
    return match x {
        _ when x > 0 => ""positive"",
        _ => ""non-positive""
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Regression tests: bug-016 (for-loop := declaration) ─────────

    [Fact]
    public void Format_ForLoop_ShorthandDeclaration_UsesColonEquals()
    {
        // Bug-016: formatter was emitting `for i = 0` instead of `for i := 0`
        var input = @"func Test() {
for i := 0; i < 10; i++ {
print i
}
}";
        var expected = @"func Test() {
    for i := 0; i < 10; i++ {
        print i
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_ForLoop_ShorthandDecl_RoundTrip()
    {
        var input = @"func Test() {
for i := 0; i < 10; i++ {
print i
}
}";
        var formatted = Format(input).Trim();
        var lexer = new Lexer(formatted, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        Assert.Empty(result.Errors.Where(e => e.Severity == Compiler.ErrorSeverity.Error));
    }

    // ── Regression tests: let declarations ──────────────────────────

    [Fact]
    public void Format_LetDeclaration_ShorthandPreserved()
    {
        // Shorthand let (no type) must use :=
        var input = @"func Test() {
x := 42
print x
}";
        var expected = @"func Test() {
    x := 42
    print x
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_LetDeclaration_TypedUsesEquals()
    {
        // Typed let must use =
        var input = @"func Test() {
x: int = 42
print x
}";
        var expected = @"func Test() {
    x: int = 42
    print x
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Regression tests: lambda formatting ─────────────────────────

    [Fact]
    public void Format_Lambda_BlockBody()
    {
        var input = @"func Test() {
f := (x, y) => {
return x + y
}
}";
        var expected = @"func Test() {
    f := (x, y) => {
        return x + y
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_Lambda_SingleParam_InferredType()
    {
        var input = @"func Test() {
f := x => x * 2
}";
        var expected = @"func Test() {
    f := x => x * 2
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Regression tests: every loop form ───────────────────────────

    [Fact]
    public void Format_ForInLoop()
    {
        var input = @"func Test(items: int[]) {
for item in items {
print item
}
}";
        var expected = @"func Test(items: int[]) {
    for item in items {
        print item
    }
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Regression tests: every declaration type ────────────────────

    [Fact]
    public void Format_TypeAlias()
    {
        var input = @"type UserId = int";
        var expected = @"type UserId = int";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_DuckInterface()
    {
        var input = @"duck interface Printable {
func Print(): string
}";
        var expected = @"duck interface Printable {
    func Print(): string
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_RecordStruct()
    {
        var input = @"record struct Point {
X: int
Y: int
}";
        var expected = @"record struct Point {
    X: int
    Y: int
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_StringEnum()
    {
        var input = @"enum Status: string {
Pending = ""pending"",
Active = ""active"",
Done = ""done""
}";
        var expected = @"enum Status: string {
    Pending = ""pending"",
    Active = ""active"",
    Done = ""done""
}";

        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Safety gate tests ───────────────────────────────────────────

    [Fact]
    public void FormatSafe_ValidCode_ReturnsFormatted()
    {
        var source = "func main(){print 5}";
        var ast = Parse(source);
        var formatter = new Formatter();
        var result = formatter.FormatSafe(source, ast, null, "test.nl");
        Assert.True(result.Success);
        Assert.Contains("func main() {", result.Text);
        Assert.Empty(result.Warnings);
    }

    [Fact]
    public void FormatSafe_IdempotentOutput()
    {
        var source = @"func Test(x: int): string {
    return match x {
        0 => ""zero"",
        _ => ""other""
    }
}";
        var ast = Parse(source);
        var formatter = new Formatter();
        var result = formatter.FormatSafe(source, ast, null, "test.nl");
        Assert.True(result.Success);

        // Format again — must be identical
        var ast2 = Parse(result.Text);
        var result2 = formatter.FormatSafe(result.Text, ast2, null, "test.nl");
        Assert.True(result2.Success);
        Assert.Equal(result.Text, result2.Text);
    }

    // ── Idempotence: format twice always identical ──────────────────

    [Fact]
    public void Format_Idempotent_Union()
    {
        var input = @"union Result {
    Success { value: int }
    Error { message: string }
}";
        var first = Format(input).Trim();
        var second = Format(first).Trim();
        Assert.Equal(first, second);
    }

    [Fact]
    public void Format_Idempotent_MatchExpression()
    {
        var input = @"func Test(x: int): string {
    return match x {
        0 => ""zero"",
        1 => ""one"",
        _ => ""other""
    }
}";
        var first = Format(input).Trim();
        var second = Format(first).Trim();
        Assert.Equal(first, second);
    }

    [Fact]
    public void Format_Idempotent_ForLoop()
    {
        var input = @"func Test() {
    for i := 0; i < 10; i++ {
        print i
    }
}";
        var first = Format(input).Trim();
        var second = Format(first).Trim();
        Assert.Equal(first, second);
    }

    [Fact]
    public void Format_Idempotent_AllLoopForms()
    {
        // for...in
        var forIn = @"func Test(items: int[]) {
    for item in items {
        print item
    }
}";
        var first1 = Format(forIn).Trim();
        Assert.Equal(first1, Format(first1).Trim());

        // while
        var whileLoop = @"func Test() {
    i := 0
    while i < 10 {
        print i
        i = i + 1
    }
}";
        var first2 = Format(whileLoop).Trim();
        Assert.Equal(first2, Format(first2).Trim());
    }

    // ── Object initializer wrapping ─────────────────────────────────────

    [Fact]
    public void Format_ObjectInitializer_ShortFitsOnOneLine()
    {
        var input = @"func Test() {
    x := new Foo() { A: 1, B: 2 }
}";
        var expected = @"func Test() {
    x := new Foo() { A: 1, B: 2 }
}";
        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_ObjectInitializer_LongWrapsToMultipleLines()
    {
        var input = @"func Test() {
    options := new JsonSerializerOptions() { PropertyNameCaseInsensitive: true, PropertyNamingPolicy: someLongValue }
}";
        var expected = @"func Test() {
    options := new JsonSerializerOptions() {
        PropertyNameCaseInsensitive: true,
        PropertyNamingPolicy: someLongValue
    }
}";
        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_ObjectInitializer_SinglePropertyStaysInline()
    {
        // Single property always stays inline, even if line is long
        var input = @"func Test() {
    x := new SomeVeryLongTypeName() { SomeVeryLongPropertyNameThatExceedsLimit: true }
}";
        var expected = @"func Test() {
    x := new SomeVeryLongTypeName() { SomeVeryLongPropertyNameThatExceedsLimit: true }
}";
        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    [Fact]
    public void Format_ObjectInitializer_MultiLine_Idempotent()
    {
        // Multi-line format should be stable when re-formatted
        var input = @"func Test() {
    options := new JsonSerializerOptions() { PropertyNameCaseInsensitive: true, PropertyNamingPolicy: someLongValue }
}";
        var first = Format(input).Trim();
        var second = Format(first).Trim();
        Assert.Equal(first, second);
    }

    [Fact]
    public void Format_ObjectInitializer_AlreadyMultiLine_StaysMultiLine()
    {
        var input = @"func Test() {
    options := new JsonSerializerOptions() {
        PropertyNameCaseInsensitive: true,
        PropertyNamingPolicy: someLongValue
    }
}";
        var expected = @"func Test() {
    options := new JsonSerializerOptions() {
        PropertyNameCaseInsensitive: true,
        PropertyNamingPolicy: someLongValue
    }
}";
        var result = Format(input).Trim();
        Assert.Equal(expected, result);
    }

    // ── Blank line between header comment and namespace ─────────────────

    [Fact]
    public void Format_PreservesBlankLine_BetweenHeaderCommentAndNamespace()
    {
        var input = @"// File header comment

namespace MyApp";
        var result = FormatWithComments(input).Trim();
        // Blank line between comment and namespace should be preserved
        Assert.Contains("// File header comment\n\nnamespace MyApp", result);
    }

    [Fact]
    public void Format_NoBlankLine_BetweenCommentAndNamespace_WhenSourceHasNone()
    {
        var input = @"// File header comment
namespace MyApp";
        var result = FormatWithComments(input).Trim();
        // No blank line should be inserted when source has none
        Assert.Equal("// File header comment\nnamespace MyApp", result);
    }

    // ── FormatSafe regression tests ─────────────────────────────────────

    [Fact]
    public void FormatSafe_MatchWithUnionCasePattern_ProducesValidOutput()
    {
        // Regression: Dubai bug-005, bug-009 — formatter emitted UnionCasePattern
        // with parentheses instead of braces, causing reparse error:
        // "Expected '=>'. Expected 'arrow', got '('"
        var source = @"union Shape {
    Circle { radius: float }
    Rect { w: float, h: float }
}

func Describe(s: Shape): string {
    return match s {
        Circle { radius: r } => ""circle"",
        Rect { w: w, h: h } => ""rect""
    }
}";
        var ast = Parse(source);
        var formatter = new Formatter();
        var result = formatter.FormatSafe(source, ast, null, "test.nl");
        Assert.True(result.Success, $"FormatSafe failed: {string.Join("; ", result.Warnings)}");
        // Verify idempotence
        var ast2 = Parse(result.Text);
        var result2 = formatter.FormatSafe(result.Text, ast2, null, "test.nl");
        Assert.True(result2.Success, $"FormatSafe not idempotent: {string.Join("; ", result2.Warnings)}");
        Assert.Equal(result.Text, result2.Text);
    }

    [Fact]
    public void FormatSafe_CatchWithExceptionType_ProducesValidOutput()
    {
        // Regression: Tripoli bug-071 — formatter omitted parentheses
        // around catch clause exception type
        var source = @"func Test() {
    try {
        print ""trying""
    } catch (Exception ex) {
        print ex
    }
}";
        var ast = Parse(source);
        var formatter = new Formatter();
        var result = formatter.FormatSafe(source, ast, null, "test.nl");
        Assert.True(result.Success, $"FormatSafe failed: {string.Join("; ", result.Warnings)}");
        Assert.Contains("catch (Exception ex)", result.Text);
    }

    [Fact]
    public void FormatSafe_MatchWithMultiplePatternTypes_ProducesValidOutput()
    {
        // Regression: Tripoli bug-070 — various pattern types in match
        var source = @"func Classify(x: int): string {
    return match x {
        0 => ""zero"",
        > 0 => ""positive"",
        _ => ""negative""
    }
}";
        var ast = Parse(source);
        var formatter = new Formatter();
        var result = formatter.FormatSafe(source, ast, null, "test.nl");
        Assert.True(result.Success, $"FormatSafe failed: {string.Join("; ", result.Warnings)}");
        var ast2 = Parse(result.Text);
        var result2 = formatter.FormatSafe(result.Text, ast2, null, "test.nl");
        Assert.True(result2.Success, $"FormatSafe not idempotent: {string.Join("; ", result2.Warnings)}");
        Assert.Equal(result.Text, result2.Text);
    }

    [Fact]
    public void FormatSafe_RealWorldApp_TryCatchAndMatch()
    {
        // Regression: Tripoli bug-096 — formatter could not handle
        // a normal real-world app combining try/catch and match
        var source = @"func ProcessRequest(req: Request): Response {
    try {
        result := match req.Type {
            ""GET"" => HandleGet(req),
            ""POST"" => HandlePost(req),
            _ => BadRequest()
        }
        return result
    } catch (HttpException ex) {
        return ErrorResponse(ex.StatusCode)
    } catch (Exception ex) {
        return ErrorResponse(500)
    }
}";
        var ast = Parse(source);
        var formatter = new Formatter();
        var result = formatter.FormatSafe(source, ast, null, "test.nl");
        Assert.True(result.Success, $"FormatSafe failed: {string.Join("; ", result.Warnings)}");
        Assert.Contains("catch (HttpException ex)", result.Text);
        Assert.Contains("catch (Exception ex)", result.Text);
        // Verify idempotence
        var ast2 = Parse(result.Text);
        var result2 = formatter.FormatSafe(result.Text, ast2, null, "test.nl");
        Assert.True(result2.Success, $"FormatSafe not idempotent: {string.Join("; ", result2.Warnings)}");
        Assert.Equal(result.Text, result2.Text);
    }

    [Fact]
    public void Format_CatchWithoutType_NoParen()
    {
        // Bare catch (no exception type) should not have parentheses
        var source = @"func Test() {
    try {
        print ""trying""
    } catch {
        print ""caught""
    }
}";
        var result = Format(source).Trim();
        Assert.Contains("} catch {", result);
        Assert.DoesNotContain("catch ()", result);
    }
}
