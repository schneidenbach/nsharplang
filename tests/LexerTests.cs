using System;
using System.Linq;
using System.Collections.Generic;
using NewCLILang.Compiler;
using Xunit;

namespace NewCLILang.Tests;

public class LexerTests
{
    private static List<Token> Tokenize(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        return lexer.Tokenize();
    }

    [Fact]
    public void TestEmptyInput()
    {
        var tokens = Tokenize("");
        Assert.Single(tokens);
        Assert.Equal(TokenType.Eof, tokens[0].Type);
    }

    [Fact]
    public void TestKeywords()
    {
        var source = "func class struct interface union if else for while return";
        var tokens = Tokenize(source);

        Assert.Equal(11, tokens.Count); // 10 keywords + EOF
        Assert.Equal(TokenType.Func, tokens[0].Type);
        Assert.Equal(TokenType.Class, tokens[1].Type);
        Assert.Equal(TokenType.Struct, tokens[2].Type);
        Assert.Equal(TokenType.Interface, tokens[3].Type);
        Assert.Equal(TokenType.Union, tokens[4].Type);
        Assert.Equal(TokenType.If, tokens[5].Type);
        Assert.Equal(TokenType.Else, tokens[6].Type);
        Assert.Equal(TokenType.For, tokens[7].Type);
        Assert.Equal(TokenType.While, tokens[8].Type);
        Assert.Equal(TokenType.Return, tokens[9].Type);
    }

    [Fact]
    public void TestIdentifiers()
    {
        var source = "myVar _private MyPublic some_snake_case";
        var tokens = Tokenize(source);

        Assert.Equal(5, tokens.Count); // 4 identifiers + EOF
        Assert.All(tokens.Take(4), t => Assert.Equal(TokenType.Identifier, t.Type));
        Assert.Equal("myVar", tokens[0].Value);
        Assert.Equal("_private", tokens[1].Value);
        Assert.Equal("MyPublic", tokens[2].Value);
        Assert.Equal("some_snake_case", tokens[3].Value);
    }

    [Fact]
    public void TestNumbers()
    {
        var source = "42 3.14 100_000 1.5_5";
        var tokens = Tokenize(source);

        Assert.Equal(5, tokens.Count);
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("42", tokens[0].Value);
        Assert.Equal(TokenType.FloatLiteral, tokens[1].Type);
        Assert.Equal("3.14", tokens[1].Value);
        Assert.Equal(TokenType.IntLiteral, tokens[2].Type);
        Assert.Equal("100000", tokens[2].Value);
        Assert.Equal(TokenType.FloatLiteral, tokens[3].Type);
        Assert.Equal("1.55", tokens[3].Value);
    }

    [Fact]
    public void TestStrings()
    {
        var source = """
            "hello"
            "world with spaces"
            "escape\ntest\t\r"
            """;
        var tokens = Tokenize(source);

        // 3 strings + 2 newlines + EOF = 6
        Assert.Equal(6, tokens.Count);

        var strings = tokens.Where(t => t.Type == TokenType.StringLiteral).ToList();
        Assert.Equal(3, strings.Count);
        Assert.Equal("hello", strings[0].Value);
        Assert.Equal("world with spaces", strings[1].Value);
        Assert.Equal("escape\ntest\t\r", strings[2].Value);
    }

    [Fact]
    public void TestTripleQuoteString()
    {
        var source = "\"\"\"This is\na multi-line\nstring\"\"\"";
        var tokens = Tokenize(source);

        var strings = tokens.Where(t => t.Type == TokenType.TripleQuoteStringLiteral).ToList();
        Assert.Single(strings);
        Assert.Equal("This is\na multi-line\nstring", strings[0].Value);
    }

    [Fact]
    public void TestOperators()
    {
        var source = "+ - * / % = == != < <= > >= && || ! ?: ?? ??= ?. => := :: . .. ...";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.Plus, tokens[0].Type);
        Assert.Equal(TokenType.Minus, tokens[1].Type);
        Assert.Equal(TokenType.Star, tokens[2].Type);
        Assert.Equal(TokenType.Slash, tokens[3].Type);
        Assert.Equal(TokenType.Percent, tokens[4].Type);
        Assert.Equal(TokenType.Assign, tokens[5].Type);
        Assert.Equal(TokenType.Equal, tokens[6].Type);
        Assert.Equal(TokenType.NotEqual, tokens[7].Type);
        Assert.Equal(TokenType.Less, tokens[8].Type);
        Assert.Equal(TokenType.LessEqual, tokens[9].Type);
        Assert.Equal(TokenType.Greater, tokens[10].Type);
        Assert.Equal(TokenType.GreaterEqual, tokens[11].Type);
        Assert.Equal(TokenType.And, tokens[12].Type);
        Assert.Equal(TokenType.Or, tokens[13].Type);
        Assert.Equal(TokenType.Not, tokens[14].Type);
        Assert.Equal(TokenType.Question, tokens[15].Type);
        Assert.Equal(TokenType.Colon, tokens[16].Type);
        Assert.Equal(TokenType.QuestionQuestion, tokens[17].Type);
        Assert.Equal(TokenType.QuestionQuestionAssign, tokens[18].Type);
        Assert.Equal(TokenType.QuestionDot, tokens[19].Type);
        Assert.Equal(TokenType.Arrow, tokens[20].Type);
        Assert.Equal(TokenType.ColonAssign, tokens[21].Type);
        Assert.Equal(TokenType.DoubleColon, tokens[22].Type);
        Assert.Equal(TokenType.Dot, tokens[23].Type);
        Assert.Equal(TokenType.DotDot, tokens[24].Type);
        Assert.Equal(TokenType.DotDotDot, tokens[25].Type);
    }

    [Fact]
    public void TestCompoundAssignments()
    {
        var source = "+= -= *= /=";
        var tokens = Tokenize(source);

        Assert.Equal(5, tokens.Count); // 4 operators + EOF
        Assert.Equal(TokenType.PlusAssign, tokens[0].Type);
        Assert.Equal(TokenType.MinusAssign, tokens[1].Type);
        Assert.Equal(TokenType.StarAssign, tokens[2].Type);
        Assert.Equal(TokenType.SlashAssign, tokens[3].Type);
    }

    [Fact]
    public void TestIncrementDecrement()
    {
        var source = "++ --";
        var tokens = Tokenize(source);

        Assert.Equal(3, tokens.Count);
        Assert.Equal(TokenType.Increment, tokens[0].Type);
        Assert.Equal(TokenType.Decrement, tokens[1].Type);
    }

    [Fact]
    public void TestDelimiters()
    {
        var source = "( ) { } [ ] ; ,";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.LeftParen, tokens[0].Type);
        Assert.Equal(TokenType.RightParen, tokens[1].Type);
        Assert.Equal(TokenType.LeftBrace, tokens[2].Type);
        Assert.Equal(TokenType.RightBrace, tokens[3].Type);
        Assert.Equal(TokenType.LeftBracket, tokens[4].Type);
        Assert.Equal(TokenType.RightBracket, tokens[5].Type);
        Assert.Equal(TokenType.Semicolon, tokens[6].Type);
        Assert.Equal(TokenType.Comma, tokens[7].Type);
    }

    [Fact]
    public void TestBitwiseOperators()
    {
        var source = "& | ^ ~ << >>";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.BitwiseAnd, tokens[0].Type);
        Assert.Equal(TokenType.BitwiseOr, tokens[1].Type);
        Assert.Equal(TokenType.BitwiseXor, tokens[2].Type);
        Assert.Equal(TokenType.BitwiseNot, tokens[3].Type);
        Assert.Equal(TokenType.LeftShift, tokens[4].Type);
        Assert.Equal(TokenType.RightShift, tokens[5].Type);
    }

    [Fact]
    public void TestComments()
    {
        var source = """
            // single line comment
            x := 42
            /* multi
               line
               comment */
            y := 10
            """;
        var tokens = Tokenize(source);

        // Should have: newline, identifier, :=, number, newline, identifier, :=, number, newline, EOF
        // Comments are filtered out
        var nonNewlineTokens = tokens.Where(t => t.Type != TokenType.Newline && t.Type != TokenType.Eof).ToList();
        Assert.Equal(6, nonNewlineTokens.Count); // x, :=, 42, y, :=, 10
    }

    [Fact]
    public void TestXmlDocComment()
    {
        var source = """
            /// <summary>This is a doc comment</summary>
            func Test() {}
            """;
        var tokens = Tokenize(source);

        // XML doc comments are filtered out like regular comments
        var funcToken = tokens.FirstOrDefault(t => t.Type == TokenType.Func);
        Assert.NotNull(funcToken);
    }

    [Fact]
    public void TestPreprocessorDirective()
    {
        var source = """
            #if DEBUG
            x := 1
            #endif
            """;
        var tokens = Tokenize(source);

        var preprocessor = tokens.Where(t => t.Type == TokenType.PreprocessorDirective).ToList();
        Assert.Equal(2, preprocessor.Count);
        Assert.Equal("#if DEBUG", preprocessor[0].Value);
        Assert.Equal("#endif", preprocessor[1].Value);
    }

    [Fact]
    public void TestNewlines()
    {
        var source = "a\nb\nc";
        var tokens = Tokenize(source);

        // a, newline, b, newline, c, EOF
        Assert.Equal(6, tokens.Count);
        Assert.Equal(TokenType.Identifier, tokens[0].Type);
        Assert.Equal(TokenType.Newline, tokens[1].Type);
        Assert.Equal(TokenType.Identifier, tokens[2].Type);
        Assert.Equal(TokenType.Newline, tokens[3].Type);
        Assert.Equal(TokenType.Identifier, tokens[4].Type);
        Assert.Equal(TokenType.Eof, tokens[5].Type);
    }

    [Fact]
    public void TestSimpleFunction()
    {
        var source = """
            func Add(x: int, y: int): int {
                return x + y
            }
            """;
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.Func, tokens[0].Type);
        Assert.Equal(TokenType.Identifier, tokens[1].Type);
        Assert.Equal("Add", tokens[1].Value);
        Assert.Equal(TokenType.LeftParen, tokens[2].Type);
    }

    [Fact]
    public void TestVariableDeclaration()
    {
        var source = "let name: string = \"John\"";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.Let, tokens[0].Type);
        Assert.Equal(TokenType.Identifier, tokens[1].Type);
        Assert.Equal("name", tokens[1].Value);
        Assert.Equal(TokenType.Colon, tokens[2].Type);
        Assert.Equal(TokenType.Identifier, tokens[3].Type);
        Assert.Equal("string", tokens[3].Value);
        Assert.Equal(TokenType.Assign, tokens[4].Type);
        Assert.Equal(TokenType.StringLiteral, tokens[5].Type);
        Assert.Equal("John", tokens[5].Value);
    }

    [Fact]
    public void TestShorthandDeclaration()
    {
        var source = "x := 42";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.Identifier, tokens[0].Type);
        Assert.Equal("x", tokens[0].Value);
        Assert.Equal(TokenType.ColonAssign, tokens[1].Type);
        Assert.Equal(":=", tokens[1].Value);
        Assert.Equal(TokenType.IntLiteral, tokens[2].Type);
        Assert.Equal("42", tokens[2].Value);
    }

    [Fact]
    public void TestLambda()
    {
        var source = "x => x * 2";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.Identifier, tokens[0].Type);
        Assert.Equal(TokenType.Arrow, tokens[1].Type);
        Assert.Equal(TokenType.Identifier, tokens[2].Type);
        Assert.Equal(TokenType.Star, tokens[3].Type);
        Assert.Equal(TokenType.IntLiteral, tokens[4].Type);
    }

    [Fact]
    public void TestNullableOperators()
    {
        var source = "person?.Name ?? \"Unknown\"";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.Identifier, tokens[0].Type);
        Assert.Equal(TokenType.QuestionDot, tokens[1].Type);
        Assert.Equal(TokenType.Identifier, tokens[2].Type);
        Assert.Equal(TokenType.QuestionQuestion, tokens[3].Type);
        Assert.Equal(TokenType.StringLiteral, tokens[4].Type);
    }

    [Fact]
    public void TestArrayLiteral()
    {
        var source = "[1, 2, 3]";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.LeftBracket, tokens[0].Type);
        Assert.Equal(TokenType.IntLiteral, tokens[1].Type);
        Assert.Equal(TokenType.Comma, tokens[2].Type);
        Assert.Equal(TokenType.IntLiteral, tokens[3].Type);
        Assert.Equal(TokenType.Comma, tokens[4].Type);
        Assert.Equal(TokenType.IntLiteral, tokens[5].Type);
        Assert.Equal(TokenType.RightBracket, tokens[6].Type);
    }

    [Fact]
    public void TestSpreadOperator()
    {
        var source = "...items";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.DotDotDot, tokens[0].Type);
        Assert.Equal(TokenType.Identifier, tokens[1].Type);
        Assert.Equal("items", tokens[1].Value);
    }

    [Fact]
    public void TestRangeOperatorVsDotDot()
    {
        var source = "1..10";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal(TokenType.DotDot, tokens[1].Type);
        Assert.Equal(TokenType.IntLiteral, tokens[2].Type);
    }

    [Fact]
    public void TestLineAndColumnTracking()
    {
        var source = """
            func Test() {
                x := 42
            }
            """;
        var tokens = Tokenize(source);

        Assert.Equal(1, tokens[0].Line); // func on line 1
        var xToken = tokens.First(t => t.Value == "x");
        Assert.Equal(2, xToken.Line); // x on line 2
    }

    [Fact]
    public void TestUnterminatedString()
    {
        var source = "\"unterminated";
        Assert.Throws<Exception>(() => Tokenize(source));
    }

    [Fact]
    public void TestUnterminatedMultiLineComment()
    {
        var source = "/* unterminated";
        Assert.Throws<Exception>(() => Tokenize(source));
    }

    [Fact]
    public void TestUnexpectedCharacter()
    {
        var source = "@";
        Assert.Throws<Exception>(() => Tokenize(source));
    }
}
