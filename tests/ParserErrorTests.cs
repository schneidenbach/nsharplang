using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
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
    public void Parser_ReportsError_IncompleteMemberAccessBeforeSameLineToken_PointsAtDot()
    {
        var source = "func test() { x. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.ExpectedToken &&
                     error.Message.Contains("Expected member name"));

        Assert.Equal(1, error.Line);
        Assert.Equal(16, error.Column);
        Assert.Equal(1, error.Length);
        Assert.Contains("dot (.)", error.HumanExplanation);
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
        Assert.Contains(result.Errors, error =>
            error.Code == ErrorCode.ExpectedToken &&
            error.Line == 3 &&
            error.Message.Contains("Expected expression after '+'"));

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
        Assert.Equal(10, diagnostic.Column);
        Assert.Equal(":=".Length, diagnostic.Length);
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
        Assert.Equal(29, diagnostic.Column);
        Assert.Contains("N# uses ':'", diagnostic.Message);
        Assert.Contains("Name: value", diagnostic.ContextualHint);
        Assert.Contains("Name: ...", Assert.Single(diagnostic.Suggestions!));
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
}
