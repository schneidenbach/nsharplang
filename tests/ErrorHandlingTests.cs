using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using System.Linq;

namespace NSharpLang.Tests;

/// <summary>
/// Tests for error handling, malformed code, and edge cases
/// Ensures the compiler handles invalid input gracefully with helpful error messages
/// </summary>
public class ErrorHandlingTests
{
    private static CompilationUnit Parse(string code)
    {
        var lexer = new Lexer(code, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        return result.CompilationUnit!; // We expect parsing to succeed even with errors
    }

    #region Syntax Errors

    [Fact]
    public void Parser_HandlesUnterminatedString()
    {
        var code = @"func main() {
    var s = ""unterminated
}";
        var unit = Parse(code);
        // Parser should recover and produce an AST even with errors
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesUnterminatedComment()
    {
        var code = @"/* This comment never ends
func main() {
    print(""hello"")
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesMissingClosingBrace()
    {
        var code = @"func main() {
    var x = 5
    if x > 0 {
        print(x)
    // Missing closing brace
";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesMissingClosingParen()
    {
        var code = @"func main() {
    var result = add(1, 2
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesTrailingComma()
    {
        var code = @"func main() {
    var arr = [1, 2, 3,]
    var result = add(1, 2,)
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesInvalidOperator()
    {
        var code = @"func main() {
    var x = 5 @ 3  // @ is not a valid operator
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesInvalidTokenSequence()
    {
        var code = @"func main() {
    var ] { = 5
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    #endregion

    #region Type Errors

    [Fact]
    public void Analyzer_DetectsTypeMismatch()
    {
        var code = @"func main() {
    var x: int = ""string""  // Type mismatch
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var analyzer = new Analyzer();
        var result = analyzer.Analyze(unit);

        // Should have type errors (200-299 range)
        Assert.Contains(result.Errors, e => (int)e.Code >= 200 && (int)e.Code < 300);
    }

    [Fact]
    public void Analyzer_DetectsUndefinedVariable()
    {
        var code = @"func main() {
    print(undefinedVar)
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var analyzer = new Analyzer();
        var result = analyzer.Analyze(unit);

        Assert.Contains(result.Errors, e => e.Message.Contains("undefined") || e.Message.Contains("not found"));
    }

    [Fact]
    public void Analyzer_DetectsUndefinedFunction()
    {
        var code = @"func main() {
    undefinedFunc()
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var analyzer = new Analyzer();
        var result = analyzer.Analyze(unit);

        Assert.Contains(result.Errors, e => e.Message.Contains("undefined") || e.Message.Contains("not found"));
    }

    [Fact]
    public void Analyzer_DetectsWrongArgumentCount()
    {
        var code = @"func add(a: int, b: int) -> int {
    return a + b
}

func main() {
    var result = add(1)  // Wrong number of arguments
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var analyzer = new Analyzer();
        var result = analyzer.Analyze(unit);

        Assert.Contains(result.Errors, e => e.Message.Contains("argument"));
    }

    [Fact]
    public void Analyzer_DetectsReturnTypeMismatch()
    {
        var code = @"func getNumber() -> int {
    return ""not a number""
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var analyzer = new Analyzer();
        var result = analyzer.Analyze(unit);

        // Should have type errors (200-299 range)
        Assert.Contains(result.Errors, e => (int)e.Code >= 200 && (int)e.Code < 300);
    }

    #endregion

    #region Edge Cases

    [Fact]
    public void Parser_HandlesEmptyFile()
    {
        var code = "";
        var unit = Parse(code);
        Assert.NotNull(unit);
        Assert.Empty(unit.Declarations);
    }

    [Fact]
    public void Parser_HandlesOnlyComments()
    {
        var code = @"// Just a comment
/* Another comment */";
        var unit = Parse(code);
        Assert.NotNull(unit);
        Assert.Empty(unit.Declarations);
    }

    [Fact]
    public void Parser_HandlesOnlyWhitespace()
    {
        var code = "   \n\t\r\n   ";
        var unit = Parse(code);
        Assert.NotNull(unit);
        Assert.Empty(unit.Declarations);
    }

    [Fact]
    public void Parser_HandlesVeryLongIdentifier()
    {
        var longName = new string('a', 1000);
        var code = $@"func main() {{
    var {longName} = 5
}}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesDeeplyNestedExpressions()
    {
        // Create deeply nested parentheses
        var nested = "1";
        for (int i = 0; i < 100; i++)
        {
            nested = $"({nested})";
        }

        var code = $@"func main() {{
    var x = {nested}
}}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesDeeplyNestedBlocks()
    {
        var code = @"func main() {";
        for (int i = 0; i < 50; i++)
        {
            code += " if true {";
        }
        code += " var x = 1";
        for (int i = 0; i < 50; i++)
        {
            code += " }";
        }
        code += "}";

        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesUnicodeIdentifiers()
    {
        var code = @"func main() {
    var café = ""coffee""
    var π = 3.14
    var 数字 = 42
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesSpecialCharactersInStrings()
    {
        var code = @"func main() {
    var s1 = ""Hello\nWorld""
    var s2 = ""Tab\tSeparated""
    var s3 = ""Quote:\"" ""
    var s4 = ""Backslash:\\""
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    #endregion

    #region Malformed Declarations

    [Fact]
    public void Parser_HandlesMissingFunctionBody()
    {
        var code = @"func main() ";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesMissingFunctionParameters()
    {
        var code = @"func main {
    print(""hello"")
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesMissingVariableInitializer()
    {
        var code = @"func main() {
    var x: int
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesDuplicateFunctionDeclarations()
    {
        var code = @"func test() {
    print(""first"")
}

func test() {
    print(""second"")
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var analyzer = new Analyzer();
        var result = analyzer.Analyze(unit);

        // Should detect duplicate declaration
        Assert.Contains(result.Errors, e =>
            e.Message.Contains("duplicate") ||
            e.Message.Contains("already defined") ||
            e.Message.Contains("already declared"));
    }

    [Fact]
    public void Parser_HandlesMissingReturnType()
    {
        var code = @"func getValue() {
    return 42
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    #endregion

    #region Invalid Expressions

    [Fact]
    public void Parser_HandlesIncompleteBinaryExpression()
    {
        var code = @"func main() {
    var x = 5 +
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesInvalidArrayAccess()
    {
        var code = @"func main() {
    var arr = [1, 2, 3]
    var x = arr[
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesInvalidMemberAccess()
    {
        var code = @"func main() {
    var x = obj.
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_HandlesChainedErrors()
    {
        var code = @"func main() {
    var x = 5 + + * 3  // Multiple syntax errors
}";
        var unit = Parse(code);
        Assert.NotNull(unit);
    }

    [Fact]
    public void Parser_RecoversFromMalformedUnionAndParsesFollowingDeclaration()
    {
        var code = @"
union Result {
    Success {
        value: int
    }
    @@
    Failure {
        error: string
    }
}

func after() {
    print(""ok"")
}";

        var unit = Parse(code);

        Assert.NotNull(unit);
        Assert.Contains(unit.Declarations.OfType<FunctionDeclaration>(), decl => decl.Name == "after");
    }

    #endregion

    #region Control Flow Errors

    [Fact]
    public void Analyzer_DetectsUnreachableCode()
    {
        var code = @"func main() {
    return
    print(""unreachable"")
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var linter = new Linter();
        var diagnostics = linter.Lint(unit);

        // Linter should warn about unreachable code
        Assert.Contains(diagnostics, d => d.Message.Contains("unreachable"));
    }

    [Fact]
    public void Analyzer_DetectsMissingReturn()
    {
        var code = @"func getValue() -> int {
    if true {
        return 42
    }
    // Missing return in else branch
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var analyzer = new Analyzer();
        var result = analyzer.Analyze(unit);

        // Should detect potentially missing return
        Assert.Contains(result.Errors, e => e.Message.Contains("return") || e.Message.Contains("path"));
    }

    [Fact]
    public void Parser_HandlesInvalidBreakStatement()
    {
        var code = @"func main() {
    break  // Break outside loop
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var analyzer = new Analyzer();
        var result = analyzer.Analyze(unit);

        Assert.Contains(result.Errors, e => e.Message.Contains("break", System.StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Parser_HandlesInvalidContinueStatement()
    {
        var code = @"func main() {
    continue  // Continue outside loop
}";
        var unit = Parse(code);
        Assert.NotNull(unit);

        var analyzer = new Analyzer();
        var result = analyzer.Analyze(unit);

        Assert.Contains(result.Errors, e => e.Message.Contains("continue", System.StringComparison.OrdinalIgnoreCase));
    }

    #endregion
}
