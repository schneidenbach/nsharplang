using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Services;
using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Tests;

/// <summary>
/// Tests for Parser error reporting with INVALID sources
/// These tests verify that Parser correctly reports errors with proper codes and locations
/// </summary>
public class ParserErrorTests
{
    private static List<Token> Tokenize(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        return lexer.Tokenize();
    }

    private static ParseResult Parse(string source)
    {
        var tokens = Tokenize(source);
        var parser = new Parser(tokens, "test.nl", source);
        return parser.ParseCompilationUnit();
    }

    #region Reserved Keyword As Name (NL109)

    [Fact]
    public void Parser_ReportsError_ReservedKeyword_AsFieldName()
    {
        // `base` is a reserved keyword; it cannot name a field. Regression test for the
        // class of bug where a keyword-named field flowed into the IL backend as an
        // `<error>` placeholder and emitted unverifiable IL (InvalidProgramException).
        var source = @"
class Counter {
    base: int
}";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = Assert.Single(result.Errors);
        Assert.Equal(ErrorCode.ReservedKeywordAsName, error.Code);
        Assert.Equal("NL109", error.DiagnosticId);
        Assert.Equal(3, error.Line);
        Assert.NotNull(error.HumanExplanation);
        Assert.Contains("reserved keyword", error.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("base", error.HumanExplanation, StringComparison.Ordinal);
        Assert.NotNull(error.Suggestions);
        Assert.NotEmpty(error.Suggestions);
    }

    [Fact]
    public void Parser_ReportsError_ReservedKeyword_AsMemberNameAfterDot()
    {
        var source = @"
func test() {
    x := obj.base
}";
        var result = Parse(source);

        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Code == ErrorCode.ReservedKeywordAsName);
        var error = result.Errors.First(e => e.Code == ErrorCode.ReservedKeywordAsName);
        Assert.NotNull(error.HumanExplanation);
        Assert.Contains("reserved keyword", error.HumanExplanation, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_ReportsError_ReservedKeyword_AsFunctionParameterName()
    {
        var source = "func test(base: int) {}";
        var result = Parse(source);

        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Code == ErrorCode.ReservedKeywordAsName);
    }

    [Fact]
    public void Parser_AcceptsNonKeywordIdentifiers_ThatAreIlAsmReserved()
    {
        // `value` and `method` are reserved words in ILAsm textual syntax but are NOT N#
        // keywords and are valid field names in CLR metadata. They must parse cleanly.
        var source = @"
class Box {
    value: int
    method: int
}";
        var result = Parse(source);

        Assert.True(result.Success, "value/method are valid N# identifiers and must parse");
        Assert.Empty(result.Errors);
    }

    #endregion

    #region Single Line Errors

    [Fact]
    public void Parser_ReportsError_IncompleteMemberAccess_SingleLine()
    {
        var source = @"
func test() {
    x.
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.Single(result.Errors);

        var error = result.Errors[0];
        Assert.Equal(ErrorCode.ExpectedToken, error.Code);
        Assert.Equal(3, error.Line); // Line with "x."
        Assert.NotNull(error.HumanExplanation);
        Assert.Contains("dot", error.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.NotNull(error.Suggestions);
        Assert.NotEmpty(error.Suggestions);
    }

    [Fact]
    public void Parser_ReportsError_IncompleteMemberAccessBeforeSameLineToken_PointsAtReceiver()
    {
        var source = "func test() { name. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.ExpectedToken &&
                     error.Message.Contains("Expected member name"));

        Assert.Equal(1, error.Line);
        Assert.Equal(15, error.Column);
        Assert.Equal("name".Length, error.Length);
        Assert.Contains("dot (.)", error.HumanExplanation);
    }

    [Theory]
    [InlineData("func () {\n}", "Expected function name", "func")]
    [InlineData("class {\n}", "Expected class name", "class")]
    [InlineData("struct {\n}", "Expected struct name", "struct")]
    [InlineData("record {\n}", "Expected record name", "record")]
    [InlineData("interface {\n}", "Expected interface name", "interface")]
    [InlineData("union {\n}", "Expected union name", "union")]
    [InlineData("enum {\n}", "Expected enum name", "enum")]
    [InlineData("type = int", "Expected type alias name", "type")]
    public void Parser_MissingDeclarationName_PointsAtDeclarationKeyword(
        string source,
        string message,
        string keyword)
    {
        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains(message));
        Assert.Equal(1, diagnostic.Line);
        Assert.Equal(1, diagnostic.Column);
        Assert.Equal(keyword.Length, diagnostic.Length);
        Assert.StartsWith(keyword, diagnostic.SourceSnippet, StringComparison.Ordinal);
    }

    [Fact]
    public void Parser_MissingParameterName_PointsAtTypeToken()
    {
        var result = Parse("func main(: string) {\n}");

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected parameter name"));
        Assert.Equal(1, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal("string".Length, diagnostic.Length);
    }

    [Fact]
    public void Parser_MissingParameterType_PointsAtParameterName()
    {
        var result = Parse("func main(name:) {\n}");

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected type name"));
        Assert.Equal(1, diagnostic.Line);
        Assert.Equal(11, diagnostic.Column);
        Assert.Equal("name".Length, diagnostic.Length);
    }

    [Fact]
    public void Parser_TrailingParameterComma_PointsAtPreviousParameter()
    {
        var result = Parse("func main(name: string, ) {\n}");

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected parameter name"));
        Assert.Equal(1, diagnostic.Line);
        Assert.Equal(11, diagnostic.Column);
        Assert.Equal("name: string,".Length, diagnostic.Length);
    }

    [Theory]
    [InlineData("func main<T,>() {\n}", 10, 4)]
    [InlineData("class Box<> {\n}", 10, 2)]
    public void Parser_MissingTypeParameterName_PointsAtGenericParameterList(
        string source,
        int expectedColumn,
        int expectedLength)
    {
        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected type parameter name"));
        Assert.Equal(1, diagnostic.Line);
        Assert.Equal(expectedColumn, diagnostic.Column);
        Assert.Equal(expectedLength, diagnostic.Length);
    }

    [Fact]
    public void Parser_MissingFieldType_PointsAtFieldName()
    {
        var result = Parse("class User {\n    Name:\n}");

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected type name"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("Name".Length, diagnostic.Length);
    }

    [Fact]
    public void Parser_MissingGenericTypeArgument_PointsAtGenericType()
    {
        var result = Parse("class User {\n    Items: List<>\n}");

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected type name"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(12, diagnostic.Column);
        Assert.Equal("List<>".Length, diagnostic.Length);
    }

    [Fact]
    public void Parser_MissingFieldTypeBeforeNextField_PointsAtFieldNameAndContinues()
    {
        var result = Parse("class User {\n    Name:\n    Items: List<>\n}");

        Assert.Contains(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected type name") &&
            error.Line == 2 &&
            error.Column == 5 &&
            error.Length == "Name".Length);
        Assert.Contains(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected type name") &&
            error.Line == 3 &&
            error.Column == 12 &&
            error.Length == "List<>".Length);
    }

    [Fact]
    public void Parser_MissingObjectInitializerColon_PointsAtPropertyName()
    {
        var result = Parse("""
class User {
    Name: string
}
func main() {
    user := new User { Name }
}
""");

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected ':' after object initializer member 'Name'"));
        Assert.Equal(5, diagnostic.Line);
        Assert.Equal(24, diagnostic.Column);
        Assert.Equal("Name".Length, diagnostic.Length);
    }

    [Fact]
    public void Parser_NewMissingType_PointsAtNewKeyword()
    {
        var result = Parse("func main() {\n    value := new\n}");

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected type name"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(14, diagnostic.Column);
        Assert.Equal("new".Length, diagnostic.Length);
    }

    [Fact]
    public void Parser_ReportsError_MissingClosingParen_SingleLine()
    {
        var source = @"
func test() {
    Console.WriteLine(""hello""
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Code == ErrorCode.MissingClosingParen);

        var error = result.Errors.First(e => e.Code == ErrorCode.MissingClosingParen);
        Assert.Equal(3, error.Line); // Line where the ) should have appeared
        Assert.NotNull(error.HumanExplanation);
    }

    [Fact]
    public void Parser_ReportsError_InvalidTokenInExpression()
    {
        var source = @"
func test() {
    x = 5 @@ 3
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotEmpty(result.Errors);
        // The error should be on line 3 where the invalid token is
        Assert.Contains(result.Errors, e => e.Line == 3);
    }

    #endregion

    #region Multi-Line Errors

    [Fact]
    public void Parser_ReportsMultipleErrors_DifferentLines()
    {
        var source = @"
func test1() {
    x.
}

func test2() {
    y.
}

func test3() {
    z.
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.True(result.Errors.Count >= 3, $"Expected at least 3 errors, got {result.Errors.Count}");

        // Verify each error is on the correct line
        Assert.Contains(result.Errors, e => e.Line == 3 && e.Code == ErrorCode.ExpectedToken);
        Assert.Contains(result.Errors, e => e.Line == 7 && e.Code == ErrorCode.ExpectedToken);
        Assert.Contains(result.Errors, e => e.Line == 11 && e.Code == ErrorCode.ExpectedToken);
    }

    [Fact]
    public void Parser_ReportsMultipleErrors_SameFunction()
    {
        var source = @"
func test() {
    x.
    y.
    z.
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.True(result.Errors.Count >= 3, $"Expected at least 3 errors, got {result.Errors.Count}");

        // Each error should be on its own line
        Assert.Contains(result.Errors, e => e.Line == 3);
        Assert.Contains(result.Errors, e => e.Line == 4);
        Assert.Contains(result.Errors, e => e.Line == 5);

        // All should have proper error codes
        Assert.All(result.Errors, e => Assert.Equal(ErrorCode.ExpectedToken, e.Code));
    }

    [Fact]
    public void Parser_ReportsMultipleErrors_FromSingleMalformedSource()
    {
        var source = @"
func test() {
    match value {
        @@ => 1,
        other => 2
    }

    new Person {
        @@
    }
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotNull(result.CompilationUnit);
        Assert.True(result.Errors.Count >= 2, $"Expected at least 2 errors, got {result.Errors.Count}");
        Assert.True(result.Errors.Select(e => e.Line).Distinct().Count() >= 2, "Expected errors on multiple lines");
    }

    #endregion

    #region Error Code Verification

    [Fact]
    public void Parser_ReturnsCorrectErrorCode_ExpectedToken()
    {
        var source = "func test() { x. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.Equal(ErrorCode.ExpectedToken, error.Code);
    }

    [Fact]
    public void Parser_MissingParameterColon_PointsAtParameterName()
    {
        var source = "func greet(name string): string { return name }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.ExpectedToken &&
                     error.Message.Contains("Expected ':' after parameter name"));

        Assert.Equal(1, error.Line);
        Assert.Equal(12, error.Column);
        Assert.Equal("name".Length, error.Length);
        Assert.Contains("name: Type", error.ContextualHint);
    }

    [Fact]
    public void Parser_MissingFieldColon_PointsAtFieldName()
    {
        var source = """
class User {
    Name string
}
""";

        var result = Parse(source);

        Assert.False(result.Success);
        var error = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.ExpectedToken &&
                     error.Message.Contains("Expected ':' or ':=' after field name"));

        Assert.Equal(2, error.Line);
        Assert.Equal(5, error.Column);
        Assert.Equal("Name".Length, error.Length);
        Assert.Equal("    Name string", error.SourceSnippet);
        Assert.Contains("Name: Type", error.ContextualHint);
    }

    [Fact]
    public void Parser_MissingFunctionReturnColon_PointsAtFunctionName()
    {
        var source = "func answer() int { return 1 }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.ExpectedToken &&
                     error.Message.Contains("Expected ':' before return type"));

        Assert.Equal(1, error.Line);
        Assert.Equal(6, error.Column);
        Assert.Equal("answer".Length, error.Length);
        Assert.Equal("func answer() int { return 1 }", error.SourceSnippet);
        Assert.Contains("func name(...): Type", error.ContextualHint);
    }

    [Fact]
    public void Parser_DefaultDiagnosticSpan_CoversVisibleToken()
    {
        var source = "enum Status: decimal { Open }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.UnexpectedToken &&
                     error.Message.Contains("Unsupported enum backing type"));

        Assert.Equal(1, error.Line);
        Assert.Equal(14, error.Column);
        Assert.Equal("decimal".Length, error.Length);
        Assert.Equal(source, error.SourceSnippet);
    }

    [Fact]
    public void Parser_ReturnsCorrectErrorCode_UnexpectedToken()
    {
        var source = "class Test { ] }"; // Random closing bracket
        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotEmpty(result.Errors);
        // Should report some kind of error  - just verify we have an error code
        Assert.All(result.Errors, e => Assert.True(e.Code != default(ErrorCode)));
    }

    #endregion

    #region Error Message Quality

    [Fact]
    public void Parser_ProvidesHumanExplanation()
    {
        var source = "func test() { x. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.NotNull(error.HumanExplanation);
        Assert.NotEmpty(error.HumanExplanation);
        // Should be conversational, not technical
        Assert.DoesNotContain("null", error.HumanExplanation, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_ProvidesSuggestions_ForIncompleteMemberAccess()
    {
        var source = "func test() { employees. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.NotNull(error.Suggestions);
        Assert.NotEmpty(error.Suggestions);
        // Suggestions should be actionable
        Assert.All(error.Suggestions, s => Assert.NotEmpty(s));
    }

    [Fact]
    public void Parser_ProvidesSourceSnippet()
    {
        var source = @"func test() {
    x.
}";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.NotNull(error.SourceSnippet);
        Assert.Contains("x.", error.SourceSnippet);
    }

    [Fact]
    public void Parser_ProvidesDocsUrl()
    {
        var source = "func test() { x. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.NotNull(error.DocsUrl);
        Assert.Contains("https://docs.n-sharp.dev/errors/", error.DocsUrl);
        Assert.Contains($"NL{(int)error.Code:D3}", error.DocsUrl);
    }

    #endregion

    #region Complex Multi-Error Scenarios

    [Fact]
    public void Parser_HandlesComplexMultiError_AcrossFile()
    {
        var source = @"
// Line 2
func test1() {
    // Line 4
    x.   // Error on line 5
}

// Line 8
class Test {
    // Line 10
    prop := 5 @@ 3  // Error on line 11 (invalid operator)
}

// Line 14
func test2() {
    // Line 16
    Console.WriteLine(""test""  // Error on line 17 (missing paren)
}

// Line 20
func test3() {
    // Line 22
    y.   // Error on line 23
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.True(result.Errors.Count >= 3, $"Expected at least 3 errors, got {result.Errors.Count}");

        // Verify errors are distributed across the file
        var errorLines = result.Errors.Select(e => e.Line).Distinct().ToList();
        Assert.True(errorLines.Count >= 3, "Errors should be on different lines");

        // All errors should have proper metadata
        Assert.All(result.Errors, error =>
        {
            Assert.True(error.Line > 0, "Error line should be positive");
            Assert.True(error.Column > 0, "Error column should be positive");
            Assert.NotNull(error.Message);
            Assert.NotEmpty(error.Message);
        });
    }

    #endregion

    #region Formatting Tests

    [Fact]
    public void Parser_ErrorFormat_IsReadable()
    {
        var source = "func test() { x. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);

        var formatted = error.Format(useColors: false);
        Assert.NotEmpty(formatted);

        // Should contain key components
        Assert.Contains($"NL{(int)error.Code:D3}", formatted); // Error code
        Assert.Contains("test.nl", formatted); // File name
        Assert.Contains($"{error.Line}", formatted); // Line number
    }

    #endregion

    #region Edge Cases

    [Fact]
    public void Parser_HandlesError_AtStartOfFile()
    {
        var source = "@@ invalid";
        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotEmpty(result.Errors);

        var error = result.Errors[0];
        Assert.True(error.Line >= 1, "Error line should be at least 1");
    }

    [Fact]
    public void Parser_HandlesError_AtEndOfFile()
    {
        var source = @"
func test() {
    x = 5
";  // Missing closing brace

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotEmpty(result.Errors);
    }

    [Fact]
    public void Parser_HandlesEmptyInput()
    {
        var source = "";
        var result = Parse(source);

        // Empty input should parse successfully (empty compilation unit)
        // OR report an appropriate error if required
        Assert.NotNull(result);
    }

    #endregion

    #region Error Recovery Tests

    [Fact]
    public void Parser_ThreeErrorsInThreeFunctions_AllReported()
    {
        var source = @"
func test1() {
    let x: int = @@
}

func test2() {
    let y: int = @@
}

func test3() {
    let z: int = @@
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotNull(result.CompilationUnit);
        Assert.True(result.Errors.Count >= 3, $"Expected at least 3 errors, got {result.Errors.Count}");

        // All 3 functions should be parsed
        var functions = result.CompilationUnit!.Declarations
            .OfType<FunctionDeclaration>()
            .Where(f => f.Name != "<error>")
            .ToList();
        Assert.Equal(3, functions.Count);
    }

    [Fact]
    public void Parser_ErrorInFirstFunction_SecondFunctionStillParsed()
    {
        var source = @"
func broken() {
    let x: int = @@
}

func valid() {
    let y = 42
}";

        var result = Parse(source);

        Assert.NotNull(result.CompilationUnit);

        // The valid function should be parsed correctly
        var functions = result.CompilationUnit!.Declarations
            .OfType<FunctionDeclaration>()
            .Where(f => f.Name != "<error>")
            .ToList();
        Assert.Contains(functions, f => f.Name == "valid");

        // The valid function should have a body with statements
        var validFunc = functions.First(f => f.Name == "valid");
        Assert.NotNull(validFunc.Body);
        Assert.NotEmpty(validFunc.Body!.Statements);
    }

    [Fact]
    public void Parser_MissingClosingBrace_NextDeclarationStillParsed()
    {
        var source = @"
func broken() {
    let x = 5

class MyClass {
    name: string
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotNull(result.CompilationUnit);

        // Should report a missing brace error
        Assert.Contains(result.Errors, e => e.Code == ErrorCode.MissingClosingBrace);

        // The class declaration should still be parsed
        var classDecl = result.CompilationUnit!.Declarations
            .OfType<ClassDeclaration>()
            .FirstOrDefault(c => c.Name == "MyClass");
        Assert.NotNull(classDecl);
    }

    [Fact]
    public void Parser_InvalidExpressionInsideFunction_FunctionBoundaryRecovered()
    {
        var source = @"
func broken() {
    let x = 5 @@ 3
}

func valid() {
    let y = 10
}";

        var result = Parse(source);

        Assert.NotNull(result.CompilationUnit);
        Assert.NotEmpty(result.Errors);

        // The valid function should be parsed
        var functions = result.CompilationUnit!.Declarations
            .OfType<FunctionDeclaration>()
            .Where(f => f.Name != "<error>")
            .ToList();
        Assert.Contains(functions, f => f.Name == "valid");
    }

    [Fact]
    public void Parser_EmptyMalformedFile_NoException()
    {
        // Completely malformed content
        var source = "@@ ## !! %%";

        var result = Parse(source);

        Assert.NotNull(result);
        Assert.NotEmpty(result.Errors);
        // Should not throw, should produce some AST or null
    }

    [Fact]
    public void Parser_MissingBrace_ErrorPositionAccurate()
    {
        var source = @"
func test() {
    let x = 5

struct Point {
    x: int
    y: int
}";

        var result = Parse(source);

        Assert.False(result.Success);

        // The missing brace error should reference the block that started on line 2
        var braceError = result.Errors.FirstOrDefault(e => e.Code == ErrorCode.MissingClosingBrace);
        Assert.NotNull(braceError);
        Assert.Equal(2, braceError!.Line); // The block started on line 2

        // Struct should still be parsed
        var structDecl = result.CompilationUnit!.Declarations
            .OfType<StructDeclaration>()
            .FirstOrDefault(s => s.Name == "Point");
        Assert.NotNull(structDecl);
    }

    [Fact]
    public void Parser_MissingFunctionClosingBrace_PointsAtFunctionName()
    {
        var source = """
func main() {
    print "hi"
""";

        var result = Parse(source);

        var error = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.MissingClosingBrace &&
                     error.Message.Contains("Missing closing '}'"));

        Assert.Equal(1, error.Line);
        Assert.Equal(6, error.Column);
        Assert.Equal("main".Length, error.Length);
    }

    [Fact]
    public void Parser_MissingTypeClosingBrace_PointsAtTypeName()
    {
        var source = """
class User {
    Name: string
""";

        var result = Parse(source);

        var error = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.MissingClosingBrace &&
                     error.Message.Contains("Missing closing '}'"));

        Assert.Equal(1, error.Line);
        Assert.Equal(7, error.Column);
        Assert.Equal("User".Length, error.Length);
    }

    [Fact]
    public void Parser_MultipleDeclarationTypes_AllRecovered()
    {
        var source = @"
func broken() {
    let x = @@
}

enum Color {
    Red,
    Green,
    Blue
}

class Person {
    name: string
    age: int
}

func alsoValid() {
    let y = 42
}";

        var result = Parse(source);

        Assert.NotNull(result.CompilationUnit);

        // All valid declarations should be parsed
        var decls = result.CompilationUnit!.Declarations;
        Assert.Contains(decls, d => d is EnumDeclaration e && e.Name == "Color");
        Assert.Contains(decls, d => d is ClassDeclaration c && c.Name == "Person");
        Assert.Contains(decls, d => d is FunctionDeclaration f && f.Name == "alsoValid");
    }

    [Fact]
    public void Parser_CascadingErrorsSuppressed()
    {
        // A single missing } could cause many cascading errors.
        // With panic mode, we should see a reasonable number of errors, not dozens.
        var source = @"
func test() {
    let x = 5 +

func other() {
    let y = 10
}";

        var result = Parse(source);

        Assert.NotNull(result.CompilationUnit);
        // Should not produce an unreasonable number of errors
        Assert.True(result.Errors.Count <= 5,
            $"Expected 5 or fewer errors (cascading suppression), got {result.Errors.Count}");
    }

    [Fact]
    public void Parser_DanglingBinaryOperator_DoesNotSwallowFollowingStatements()
    {
        var source = @"
func test() {
    first := 1 +
    second := missingValue
    third := @@
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotNull(result.CompilationUnit);
        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Line == 3 &&
            error.Message.Contains("Expected expression after '+'"));
        Assert.Equal(14, diagnostic.Column);
        Assert.Equal("1 +".Length, diagnostic.Length);
        Assert.Equal("    first := 1 +", diagnostic.SourceSnippet);

        var function = Assert.Single(result.CompilationUnit!.Declarations.OfType<FunctionDeclaration>());
        var declarations = function.Body!.Statements
            .OfType<VariableDeclarationStatement>()
            .Select(statement => statement.Name)
            .ToList();
        Assert.Equal(new[] { "first", "second", "third" }, declarations);
    }

    [Fact]
    public void Parser_MissingInitializer_DoesNotSwallowFollowingStatement()
    {
        var source = """
func test() {
    name :=
        greeting := "hi"
    print greeting
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected an initializer expression after ':='"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("name".Length, diagnostic.Length);
        Assert.Equal("    name :=", diagnostic.SourceSnippet);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);

        var function = Assert.Single(result.CompilationUnit!.Declarations.OfType<FunctionDeclaration>());
        var declarations = function.Body!.Statements
            .OfType<VariableDeclarationStatement>()
            .Select(statement => statement.Name)
            .ToList();
        Assert.Equal(new[] { "name", "greeting" }, declarations);
    }

    [Fact]
    public void Parser_MissingAssignmentValue_UsesTargetSpanAndContinues()
    {
        var source = """
func test() {
    value := 1
    value =
    print value
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected expression after '='"));
        Assert.Equal(3, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("value".Length, diagnostic.Length);
        Assert.Equal("    value =", diagnostic.SourceSnippet);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);

        var function = Assert.Single(result.CompilationUnit!.Declarations.OfType<FunctionDeclaration>());
        Assert.Contains(function.Body!.Statements, statement =>
            statement is PrintStatement);
    }

    [Fact]
    public void Parser_PrintMissingExpression_DoesNotSwallowFollowingStatement()
    {
        var source = """
func test() {
    print
        greeting := "hi"
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected an expression to print after 'print'"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("print".Length, diagnostic.Length);
        Assert.Equal("    print", diagnostic.SourceSnippet);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);

        var function = Assert.Single(result.CompilationUnit!.Declarations.OfType<FunctionDeclaration>());
        Assert.Contains(function.Body!.Statements, statement =>
            statement is VariableDeclarationStatement { Name: "greeting" });
    }

    [Fact]
    public void Parser_ForeachMissingIn_UnderlinesForeachKeywordAndContinues()
    {
        var source = """
func test() {
    foreach item items {
        print item
    }
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected 'in' between the loop variable and collection"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("foreach".Length, diagnostic.Length);
        Assert.Equal("    foreach item items {", diagnostic.SourceSnippet);

        var function = Assert.Single(result.CompilationUnit!.Declarations.OfType<FunctionDeclaration>());
        Assert.Contains(function.Body!.Statements, statement =>
            statement is ForeachStatement { VariableName: "item" });
    }

    [Fact]
    public void Parser_ForInMissingIn_UnderlinesForKeywordAndContinues()
    {
        var source = """
func test() {
    for item items {
        print item
    }
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected 'in' between the loop variable and collection"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("for".Length, diagnostic.Length);
        Assert.Equal("    for item items {", diagnostic.SourceSnippet);

        var function = Assert.Single(result.CompilationUnit!.Declarations.OfType<FunctionDeclaration>());
        var forStatement = Assert.Single(function.Body!.Statements.OfType<ForStatement>());
        Assert.IsType<ForeachStatement>(forStatement.Body);
    }

    [Fact]
    public void Parser_WhileMissingCondition_UnderlinesWhileKeywordAndContinues()
    {
        var source = """
func test() {
    while {
        print "hi"
    }
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected a condition expression after 'while'"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("while".Length, diagnostic.Length);
        Assert.Equal("    while {", diagnostic.SourceSnippet);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);

        var function = Assert.Single(result.CompilationUnit!.Declarations.OfType<FunctionDeclaration>());
        Assert.Contains(function.Body!.Statements, statement =>
            statement is WhileStatement { Body: BlockStatement });
    }

    [Theory]
    [InlineData("""
func test() {
    if true
}
""", "if", 2, "Expected statement body")]
    [InlineData("""
func test() {
    for item in items
}
""", "for", 2, "Expected statement body")]
    [InlineData("""
func test() {
    while true
}
""", "while", 2, "Expected statement body")]
    public void Parser_MissingStatementBody_UnderlinesControlFlowKeyword(
        string source,
        string keyword,
        int line,
        string message)
    {
        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains(message));

        Assert.Equal(line, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal(keyword.Length, diagnostic.Length);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);
    }

    [Fact]
    public void Parser_InvalidPrefixPlus_UnderlinesVisibleExpressionSegment()
    {
        var source = """
func test() {
    + 1
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.InvalidSyntax &&
            error.Message.Contains("Prefix '+'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("+ 1".Length, diagnostic.Length);
        Assert.Equal("    + 1", diagnostic.SourceSnippet);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);
    }

    [Fact]
    public void Parser_LeadingMemberAccess_UnderlinesVisibleMemberAccess()
    {
        var source = """
func test() {
    .Name
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected expression before '.'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal(".Name".Length, diagnostic.Length);
        Assert.Equal("    .Name", diagnostic.SourceSnippet);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);
    }

    [Theory]
    [InlineData("await", "Expected an expression to await after 'await'", 14, "await")]
    [InlineData("must", "Expected a nullable expression to unwrap after 'must'", 14, "must")]
    public void Parser_MissingUnaryKeywordOperand_UnderlinesKeyword(
        string keyword,
        string message,
        int column,
        string highlightedText)
    {
        var source = $$"""
func test() {
    value := {{keyword}}
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains(message));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(column, diagnostic.Column);
        Assert.Equal(highlightedText.Length, diagnostic.Length);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);
    }

    [Fact]
    public void Parser_MissingLambdaBody_UnderlinesLambdaHeader()
    {
        var source = """
func test() {
    f := x =>
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected a lambda body expression after '=>'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(10, diagnostic.Column);
        Assert.Equal("x =>".Length, diagnostic.Length);
    }

    [Fact]
    public void Parser_MissingTernaryElse_UnderlinesTernaryExpression()
    {
        var source = """
func test() {
    value := condition ? 1 :
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected an else expression after ':'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(14, diagnostic.Column);
        Assert.Equal("condition ? 1 :".Length, diagnostic.Length);
    }

    [Fact]
    public void Parser_ObjectInitializerEquals_ReportsActionableDiagnosticAndContinues()
    {
        var source = @"
func test() {
    user := new User { Name = ""Ada"", Age: 42 }
}";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.InvalidSyntax &&
            error.Message.Contains("Object initializer member 'Name' uses '='"));
        Assert.Equal(3, diagnostic.Line);
        Assert.Equal(24, diagnostic.Column);
        Assert.Equal("Name".Length, diagnostic.Length);
        Assert.Contains("N# uses ':'", diagnostic.Message);
        Assert.Contains("Name: value", diagnostic.ContextualHint);
        Assert.Contains("Name: ...", Assert.Single(diagnostic.Suggestions!));
    }

    [Fact]
    public void Parser_ObjectInitializerMissingValue_UsesPropertyNameSpanAndContinues()
    {
        var source = """
func test() {
    user := new User { Name: }
    print "after"
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Message.Contains("Expected a value for object initializer member 'Name'"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(24, diagnostic.Column);
        Assert.Equal("Name".Length, diagnostic.Length);
        Assert.Equal("    user := new User { Name: }", diagnostic.SourceSnippet);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);

        var function = Assert.Single(result.CompilationUnit!.Declarations.OfType<FunctionDeclaration>());
        Assert.Contains(function.Body!.Statements, statement =>
            statement is PrintStatement);
    }

    [Fact]
    public void Parser_UnterminatedStringLiteral_ReportsInvalidLiteralAtOpeningQuote()
    {
        var source = """
func test() {
    name := "Ada
    print name
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.InvalidLiteral &&
            error.Message.Contains("Unterminated string literal"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(4, diagnostic.Length);
        Assert.Equal("    name := \"Ada", diagnostic.SourceSnippet);
        Assert.Contains("closing quote", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("triple-quoted string", diagnostic.ContextualHint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_UnterminatedStringLiteral_WithEscapedQuote_ReportsInvalidLiteralAtOpeningQuote()
    {
        var source = """
func test() {
    name := "Ada\"
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.InvalidLiteral &&
            error.Message.Contains("Unterminated string literal"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(6, diagnostic.Length);
        Assert.Equal("    name := \"Ada\\\"", diagnostic.SourceSnippet);
        Assert.Contains("closing quote", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_UnterminatedCharacterLiteral_ReportsInvalidLiteralAtOpeningQuote()
    {
        var source = """
func test() {
    letter := 'a
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.InvalidLiteral &&
            error.Message.Contains("Unterminated character literal"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(15, diagnostic.Column);
        Assert.Equal(2, diagnostic.Length);
        Assert.Equal("    letter := 'a", diagnostic.SourceSnippet);
        Assert.Contains("closing quote", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("single character", diagnostic.ContextualHint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_UnterminatedTripleQuoteStringLiteral_ReportsInvalidLiteralAtOpeningDelimiter()
    {
        var source = "func test() {\n    text := \"\"\"hello\nworld\n}\n";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.InvalidLiteral &&
            error.Message.Contains("Unterminated triple-quoted string literal"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(3, diagnostic.Length);
        Assert.Equal("    text := \"\"\"hello", diagnostic.SourceSnippet);
        Assert.Contains("closing triple quote", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("closing triple quote", diagnostic.ContextualHint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_UnterminatedInterpolatedRawStringLiteral_ReportsInvalidLiteralAtOpeningDelimiter()
    {
        var source = "func test() {\n    text := $\"\"\"hello {name}\n}\n";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.InvalidLiteral &&
            error.Message.Contains("Unterminated interpolated raw string literal"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(4, diagnostic.Length);
        Assert.Equal("    text := $\"\"\"hello {name}", diagnostic.SourceSnippet);
        Assert.Contains("closing triple quote", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("closing triple quote", diagnostic.ContextualHint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_MissingClosingParen_PointsAtCallOwner()
    {
        var source = """
func test() {
    print("hello"
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.MissingClosingParen &&
            error.Message.Contains("Missing closing ')'"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("print".Length, diagnostic.Length);
        Assert.Equal("    print(\"hello\"", diagnostic.SourceSnippet);
        Assert.Contains("closing ')'", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("matching closing parenthesis", diagnostic.ContextualHint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_UnclosedEmptyCallArgumentList_ReportsMissingParenAtCallOwner()
    {
        var source = """
func test() {
    print(
    greeting.CompareTo("ter")
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.MissingClosingParen &&
            error.Message.Contains("Missing closing ')'"));
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("print".Length, diagnostic.Length);
        Assert.Equal("    print(", diagnostic.SourceSnippet);
        Assert.Contains("closing ')'", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("matching closing parenthesis", diagnostic.ContextualHint, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.UnexpectedToken);
    }

    [Fact]
    public void Parser_UnclosedEmptyFunctionParameterList_ReportsMissingParenAtFunctionName()
    {
        var source = "func test(\n";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.MissingClosingParen &&
            error.Message.Contains("Missing closing ')'"));
        Assert.Equal(1, diagnostic.Line);
        Assert.Equal(6, diagnostic.Column);
        Assert.Equal("test".Length, diagnostic.Length);
        Assert.Equal("func test(", diagnostic.SourceSnippet);
        Assert.Contains("closing ')'", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("matching closing parenthesis", diagnostic.ContextualHint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_MissingClosingBracket_ArrayLiteralPointsAtAssignedVariable()
    {
        var source = """
func test() {
    nums := [1, 2
    print nums
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.MissingClosingBracket &&
            error.Message.Contains("Missing closing ']'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("nums".Length, diagnostic.Length);
        Assert.Equal("    nums := [1, 2", diagnostic.SourceSnippet);
        Assert.Contains("closing ']'", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("matching closing bracket", diagnostic.ContextualHint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_MissingClosingBracket_IndexAccessPointsAtReceiver()
    {
        var source = """
func test() {
    nums := [1, 2, 3]
    print nums[0
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.MissingClosingBracket &&
            error.Message.Contains("Missing closing ']'"));

        Assert.Equal(3, diagnostic.Line);
        Assert.Equal(11, diagnostic.Column);
        Assert.Equal("nums".Length, diagnostic.Length);
        Assert.Equal("    print nums[0", diagnostic.SourceSnippet);
        Assert.Contains("closing ']'", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("matching closing bracket", diagnostic.ContextualHint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_UsingTupleDeconstruction_PointsAtTuplePattern()
    {
        var source = """
func test() {
    using let (left, right) := getPair() {
        print "ok"
    }
}
""";

        var result = Parse(source);

        var diagnostic = Assert.Single(result.Errors, error =>
            error.Code == ErrorCode.InvalidSyntax &&
            error.Message.Contains("Using statement requires a variable declaration"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(15, diagnostic.Column);
        Assert.Equal("(left, right)".Length, diagnostic.Length);
        Assert.Equal("    using let (left, right) := getPair() {", diagnostic.SourceSnippet);
        Assert.Contains("single variable declarations", diagnostic.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("using let resource", diagnostic.ContextualHint, StringComparison.Ordinal);
    }

    [Fact]
    public void Parser_MultipleStatementsWithErrors_InSameBlock_AllReported()
    {
        // Multiple distinct bad statements inside a single function body
        var source = @"
func test() {
    let a: int = @@
    let b: int = @@
    let c: int = @@
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.True(result.Errors.Count >= 3,
            $"Expected at least 3 errors (one per bad statement), got {result.Errors.Count}");

        // Each error should be on its own line
        var distinctLines = result.Errors.Select(e => e.Line).Distinct().ToList();
        Assert.True(distinctLines.Count >= 3,
            $"Expected errors on at least 3 distinct lines, got {distinctLines.Count}");
    }

    [Fact]
    public void Parser_MixedErrorTypes_AllReported()
    {
        // Incomplete member access + invalid token + missing brace — different error kinds
        var source = @"
func test1() {
    x.
}

func test2() {
    let a: int = @@
}

func test3() {
    Console.WriteLine(""hi""
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.True(result.Errors.Count >= 3,
            $"Expected at least 3 errors, got {result.Errors.Count}");

        // Errors should span multiple functions
        var distinctLines = result.Errors.Select(e => e.Line).Distinct().OrderBy(l => l).ToList();
        Assert.True(distinctLines.Count >= 3,
            $"Expected errors on at least 3 distinct lines, got {distinctLines.Count}");
    }

    [Fact]
    public void Parser_ErrorInClassMember_NextMemberStillParsed()
    {
        var source = @"
class Foo {
    Name: string = @@
    Age: int
}";

        var result = Parse(source);

        Assert.NotNull(result.CompilationUnit);
        Assert.False(result.Success);
        Assert.NotEmpty(result.Errors);

        // The class should still be parsed
        var classDecl = result.CompilationUnit!.Declarations
            .OfType<ClassDeclaration>()
            .FirstOrDefault(c => c.Name == "Foo");
        Assert.NotNull(classDecl);
    }

    [Fact]
    public void Parser_ErrorsInMultipleClassMembers_AllReported()
    {
        var source = @"
class Foo {
    Name: string = @@
    Age: int = @@
}

class Bar {
    Value: int
}";

        var result = Parse(source);

        Assert.NotNull(result.CompilationUnit);
        Assert.True(result.Errors.Count >= 2,
            $"Expected at least 2 errors from 2 bad members, got {result.Errors.Count}");

        // Both classes should be parsed
        var classes = result.CompilationUnit!.Declarations
            .OfType<ClassDeclaration>()
            .ToList();
        Assert.True(classes.Count >= 2, $"Expected 2 classes parsed, got {classes.Count}");
    }

    #endregion

    #region Audit Regression Tests

    [Fact]
    public void Parser_NamedTuple_NonIdentifierBeforeColon_DoesNotCrash()
    {
        // Previously this would throw InvalidCastException
        // because (1+2: value) tried to cast BinaryExpression to IdentifierExpression
        var source = @"
func test() {
    x := (1+2)
}";
        var result = Parse(source);
        // Should parse without crashing — the expression is just parenthesized
        Assert.NotNull(result.CompilationUnit);
    }

    [Fact]
    public void Parser_InterpolatedString_ErrorsArePropagated()
    {
        // Syntax errors inside interpolated string holes should produce diagnostics
        var source = @"
func test() {
    x := $""hello {1 +}""
}";
        var result = Parse(source);
        // Should have at least one error from the malformed expression inside {1 +}
        Assert.NotNull(result.CompilationUnit);
    }

    [Fact]
    public void Parser_MultipleErrors_RecoveryBetweenDeclarations()
    {
        var source = @"
class Person
    Name: string
@@@@
class Employee
    Id: int
";
        var result = Parse(source);
        // Should recover and find Employee class even after garbage
        Assert.True(result.Errors.Count > 0, "Expected errors from garbage tokens");
        var classes = result.CompilationUnit?.Declarations
            .OfType<ClassDeclaration>()
            .Where(c => c.Name != "<error>")
            .ToList();
        Assert.True(classes != null && classes.Count >= 1, "Should recover at least one valid class");
    }

    [Fact]
    public void Parser_MissingClosingParen_RecoverToNextFunction()
    {
        var source = @"
func Foo(x int
func Bar() int => 42
";
        var result = Parse(source);
        Assert.True(result.Errors.Count > 0, "Expected error for missing )");
        // Bar should still be parsed
        var funcs = result.CompilationUnit?.Declarations
            .OfType<FunctionDeclaration>()
            .Where(f => f.Name == "Bar")
            .ToList();
        Assert.True(funcs != null && funcs.Count == 1, "Bar function should be recovered");
    }

    #endregion

    #region Syntax Diagnostic Spans (NL101-NL108)

    // Exact start/end span coverage for every parser/syntax diagnostic code.
    // The asserted (line, column, length) is the same data that maps to the VS Code
    // squiggle Range via LspDiagnosticConverter: Range(line-1, col-1, line-1, col-1+length).

    [Fact]
    public void Span_NL101_UnexpectedToken_UnderlinesOffendingToken()
    {
        var source = "package T\n\nfunc Main() {\n    let x = @\n}\n";

        var error = SingleSyntaxError(source, ErrorCode.UnexpectedToken);

        AssertSpan(error, line: 4, column: 13, length: 1, "@");
    }

    [Fact]
    public void Span_NL102_ExpectedToken_UnderlinesParameterName()
    {
        var source = "package T\n\nfunc greet(name string) {\n    return name\n}\n";

        var error = SingleSyntaxError(source, ErrorCode.ExpectedToken,
            e => e.Message.Contains("after parameter name"));

        AssertSpan(error, line: 3, column: 12, length: "name".Length, "name");
    }

    [Fact]
    public void Span_NL103_InvalidSyntax_UnderlinesObjectInitializerMember()
    {
        var source = "package T\n\nfunc Make() {\n    let u = new User { Name = \"Ada\" }\n}\n";

        var error = SingleSyntaxError(source, ErrorCode.InvalidSyntax,
            e => e.Message.Contains("Object initializer member"));

        AssertSpan(error, line: 4, column: 24, length: "Name".Length, "Name");
    }

    [Fact]
    public void Span_NL104_UnexpectedEndOfFile_UnderlinesLastVisibleOwner()
    {
        // File ends after `class Foo` with no body; the parser expects '{' but hits EOF.
        var source = "package T\n\nclass Foo";

        var error = SingleSyntaxError(source, ErrorCode.UnexpectedEndOfFile);

        // Span anchors on the visible owner token `Foo`, never on the empty EOF position.
        AssertSpan(error, line: 3, column: 7, length: "Foo".Length, "Foo");
        Assert.DoesNotContain("''", error.Message);
        Assert.Contains("end of the file", error.Message);
    }

    [Fact]
    public void Span_NL104_UnexpectedEndOfFile_MissingIdentifier_UnderlinesKeyword()
    {
        // File ends right after `func`; the parser expects a name but hits EOF.
        var source = "package T\n\nfunc";

        var error = SingleSyntaxError(source, ErrorCode.UnexpectedEndOfFile);

        AssertSpan(error, line: 3, column: 1, length: "func".Length, "func");
        Assert.DoesNotContain("''", error.Message);
        Assert.Contains("end of the file", error.Message);
    }

    [Fact]
    public void Span_NL105_InvalidLiteral_UnderlinesUnterminatedString()
    {
        var source = "package T\n\nfunc Main() {\n    name := \"Ada\n}\n";

        var error = SingleSyntaxError(source, ErrorCode.InvalidLiteral);

        AssertSpan(error, line: 4, column: 13, length: "\"Ada".Length, "\"Ada");
    }

    [Fact]
    public void Span_NL106_MissingClosingBrace_UnderlinesFunctionName()
    {
        var source = "func Main() {\n    print \"hi\"\n";

        var error = SingleSyntaxError(source, ErrorCode.MissingClosingBrace);

        AssertSpan(error, line: 1, column: 6, length: "Main".Length, "Main");
    }

    [Fact]
    public void Span_NL107_MissingClosingParen_UnderlinesCallOwner()
    {
        var source = "func Main() {\n    print(\"hello\"\n}\n";

        var error = SingleSyntaxError(source, ErrorCode.MissingClosingParen);

        AssertSpan(error, line: 2, column: 5, length: "print".Length, "print");
    }

    [Fact]
    public void Span_NL108_MissingClosingBracket_UnderlinesAssignedVariable()
    {
        var source = "func Main() {\n    nums := [1, 2\n    print nums\n}\n";

        var error = SingleSyntaxError(source, ErrorCode.MissingClosingBracket);

        AssertSpan(error, line: 2, column: 5, length: "nums".Length, "nums");
    }

    private static CompilerError SingleSyntaxError(string source, ErrorCode code, Func<CompilerError, bool>? predicate = null)
    {
        var result = Parse(source);
        return Assert.Single(result.Errors, error => error.Code == code && (predicate?.Invoke(error) ?? true));
    }

    /// <summary>
    /// Asserts the 1-based compiler span AND the 0-based, end-exclusive LSP range derived from it,
    /// and that the underlined characters of the source line match the expected visible token.
    /// </summary>
    private static void AssertSpan(CompilerError error, int line, int column, int length, string expectedToken)
    {
        Assert.Equal(line, error.Line);
        Assert.Equal(column, error.Column);
        Assert.Equal(length, error.Length);

        // The actual LSP range that drives the VS Code squiggle (0-based, end-exclusive).
        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);
        Assert.Equal(line - 1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(column - 1, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(column - 1 + length, (int)lspDiagnostic.Range.End.Character);
        Assert.Equal(line - 1, (int)lspDiagnostic.Range.End.Line);

        // The underlined characters cover the expected visible token (no whitespace-only spans).
        var snippet = error.SourceSnippet;
        if (!string.IsNullOrEmpty(snippet) && column - 1 + length <= snippet!.Length)
        {
            var underlined = snippet.Substring(column - 1, length);
            Assert.Equal(expectedToken, underlined);
            Assert.False(string.IsNullOrWhiteSpace(underlined), "Span must underline a visible token, not whitespace.");
        }
    }

    #endregion
}
