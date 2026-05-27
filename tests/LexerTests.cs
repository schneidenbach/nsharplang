using System;
using System.Linq;
using System.Collections.Generic;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

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
    public void TestVarIsIdentifier()
    {
        var tokens = Tokenize("var");

        Assert.Equal(2, tokens.Count); // var + EOF
        Assert.Equal(TokenType.Identifier, tokens[0].Type);
        Assert.Equal("var", tokens[0].Value);
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
    public void TestNumberDotIdentifier_ParsesAsMemberAccess()
    {
        // 5.ToString should tokenize as: IntLiteral("5"), Dot, Identifier("ToString"), EOF
        var source = "5.ToString";
        var tokens = Tokenize(source);

        Assert.Equal(4, tokens.Count);
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("5", tokens[0].Value);
        Assert.Equal(TokenType.Dot, tokens[1].Type);
        Assert.Equal(TokenType.Identifier, tokens[2].Type);
        Assert.Equal("ToString", tokens[2].Value);
    }

    [Fact]
    public void TestFloatDotIdentifier_ParsesAsMemberAccess()
    {
        // 3.14.Negate should tokenize as: FloatLiteral("3.14"), Dot, Identifier("Negate"), EOF
        var source = "3.14.Negate";
        var tokens = Tokenize(source);

        Assert.Equal(4, tokens.Count);
        Assert.Equal(TokenType.FloatLiteral, tokens[0].Type);
        Assert.Equal("3.14", tokens[0].Value);
        Assert.Equal(TokenType.Dot, tokens[1].Type);
        Assert.Equal(TokenType.Identifier, tokens[2].Type);
        Assert.Equal("Negate", tokens[2].Value);
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
        Assert.Equal("\"hello\"", strings[0].Value);
        Assert.Equal("\"world with spaces\"", strings[1].Value);
        Assert.Equal("\"escape\\ntest\\t\\r\"", strings[2].Value);
    }

    [Fact]
    public void TestInterpolatedString_WithNestedStringLiteralInInterpolation()
    {
        var source = """
            $"  Tags: {String.Join(", ", tags)}"
            """;

        var tokens = Tokenize(source);

        var strings = tokens.Where(t => t.Type == TokenType.StringLiteral).ToList();
        Assert.Single(strings);
        Assert.Equal("$\"  Tags: {String.Join(\", \", tags)}\"", strings[0].Value);
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
        Assert.Equal("\"John\"", tokens[5].Value);
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
    public void TestNullConditionalIndexing()
    {
        var source = "arr?[0]";
        var tokens = Tokenize(source);

        Assert.Equal(TokenType.Identifier, tokens[0].Type);
        Assert.Equal(TokenType.QuestionBracket, tokens[1].Type);
        Assert.Equal(TokenType.IntLiteral, tokens[2].Type);
        Assert.Equal(TokenType.RightBracket, tokens[3].Type);
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
        var tokens = Tokenize(source);
        Assert.Equal(TokenType.StringLiteral, tokens[0].Type);
        Assert.Equal("\"unterminated", tokens[0].Value);
    }

    [Fact]
    public void TestCharLiteral()
    {
        var source = "'|'";
        var tokens = Tokenize(source);
        Assert.Equal(TokenType.CharLiteral, tokens[0].Type);
        Assert.Equal("'|'", tokens[0].Value);
    }

    [Fact]
    public void TestEscapedCharLiteral()
    {
        var source = "'\\n'";
        var tokens = Tokenize(source);
        Assert.Equal(TokenType.CharLiteral, tokens[0].Type);
        Assert.Equal("'\\n'", tokens[0].Value);
    }

    [Fact]
    public void TestUnterminatedMultiLineComment()
    {
        var source = "/* unterminated";
        var tokens = Tokenize(source);
        // Comments are filtered out by the lexer; unterminated comments should not crash tokenization.
        Assert.Equal(TokenType.Eof, tokens[^1].Type);
        Assert.Single(tokens);
    }

    [Fact]
    public void TestUnexpectedCharacter()
    {
        var source = "@";
        var tokens = Tokenize(source);
        Assert.Equal(TokenType.Unknown, tokens[0].Type);
        Assert.Equal("@", tokens[0].Value);
    }

    [Fact]
    public void TestWhenKeyword()
    {
        var source = "when";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // when + EOF
        Assert.Equal(TokenType.When, tokens[0].Type);
        Assert.Equal("when", tokens[0].Value);
    }

    [Fact]
    public void TestPrintKeyword()
    {
        var source = "print";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // print + EOF
        Assert.Equal(TokenType.Print, tokens[0].Type);
        Assert.Equal("print", tokens[0].Value);
    }

    [Fact]
    public void TestNameofKeyword()
    {
        var source = "nameof";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // nameof + EOF
        Assert.Equal(TokenType.Nameof, tokens[0].Type);
        Assert.Equal("nameof", tokens[0].Value);
    }

    [Fact]
    public void TestMustKeyword()
    {
        var source = "must";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // must + EOF
        Assert.Equal(TokenType.Must, tokens[0].Type);
        Assert.Equal("must", tokens[0].Value);
    }

    [Fact]
    public void TestImportKeyword()
    {
        var source = "import";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // import + EOF
        Assert.Equal(TokenType.Import, tokens[0].Type);
        Assert.Equal("import", tokens[0].Value);
    }

    [Fact]
    public void TestRequiredKeyword()
    {
        var source = "required";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // required + EOF
        Assert.Equal(TokenType.Required, tokens[0].Type);
        Assert.Equal("required", tokens[0].Value);
    }

    [Fact]
    public void TestInitKeyword()
    {
        var source = "init";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // init + EOF
        Assert.Equal(TokenType.Init, tokens[0].Type);
        Assert.Equal("init", tokens[0].Value);
    }

    [Fact]
    public void TestRefKeyword()
    {
        var source = "ref";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // ref + EOF
        Assert.Equal(TokenType.Ref, tokens[0].Type);
        Assert.Equal("ref", tokens[0].Value);
    }

    [Fact]
    public void TestOutKeyword()
    {
        var source = "out";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // out + EOF
        Assert.Equal(TokenType.Out, tokens[0].Type);
        Assert.Equal("out", tokens[0].Value);
    }

    [Fact]
    public void TestLockKeyword()
    {
        var source = "lock";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // lock + EOF
        Assert.Equal(TokenType.Lock, tokens[0].Type);
        Assert.Equal("lock", tokens[0].Value);
    }

    [Fact]
    public void TestInterpolatedRawString()
    {
        var source = @"$""""""
Hello {name}
World
""""""";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // raw string + EOF
        Assert.Equal(TokenType.InterpolatedRawStringLiteral, tokens[0].Type);
        Assert.StartsWith("$\"\"\"", tokens[0].Value);
        Assert.EndsWith("\"\"\"", tokens[0].Value);
        Assert.Contains("{name}", tokens[0].Value);
    }

    [Fact]
    public void TestFileKeyword()
    {
        var source = "file";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // file + EOF
        Assert.Equal(TokenType.File, tokens[0].Type);
        Assert.Equal("file", tokens[0].Value);
    }

    [Fact]
    public void TestParamsKeyword()
    {
        var source = "params";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // params + EOF
        Assert.Equal(TokenType.Params, tokens[0].Type);
        Assert.Equal("params", tokens[0].Value);
    }

    [Fact]
    public void TestCheckedKeyword()
    {
        var source = "checked";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // checked + EOF
        Assert.Equal(TokenType.Checked, tokens[0].Type);
        Assert.Equal("checked", tokens[0].Value);
    }

    [Fact]
    public void TestUncheckedKeyword()
    {
        var source = "unchecked";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // unchecked + EOF
        Assert.Equal(TokenType.Unchecked, tokens[0].Type);
        Assert.Equal("unchecked", tokens[0].Value);
    }

    [Fact]
    public void TestImplicitKeyword()
    {
        var source = "implicit";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // implicit + EOF
        Assert.Equal(TokenType.Implicit, tokens[0].Type);
        Assert.Equal("implicit", tokens[0].Value);
    }

    [Fact]
    public void TestExplicitKeyword()
    {
        var source = "explicit";
        var tokens = Tokenize(source);
        Assert.Equal(2, tokens.Count); // explicit + EOF
        Assert.Equal(TokenType.Explicit, tokens[0].Type);
        Assert.Equal("explicit", tokens[0].Value);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Number literal edge cases (hex, binary, exponent, suffixes)
    // ════════════════════════════════════════════════════════════════════

    [Fact]
    public void TestHexLiteral()
    {
        var tokens = Tokenize("0xFF");
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("0xFF", tokens[0].Value);
    }

    [Fact]
    public void TestHexLiteralUppercase()
    {
        var tokens = Tokenize("0X1A2B");
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("0X1A2B", tokens[0].Value);
    }

    [Fact]
    public void TestHexLiteralWithUnderscores()
    {
        var tokens = Tokenize("0xFF_FF");
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("0xFFFF", tokens[0].Value);
    }

    [Fact]
    public void TestBinaryLiteral()
    {
        var tokens = Tokenize("0b1010");
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("0b1010", tokens[0].Value);
    }

    [Fact]
    public void TestBinaryLiteralUppercase()
    {
        var tokens = Tokenize("0B1100_0011");
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("0B11000011", tokens[0].Value);
    }

    [Fact]
    public void TestExponentNotation()
    {
        var tokens = Tokenize("1.5e10");
        Assert.Equal(TokenType.FloatLiteral, tokens[0].Type);
        Assert.Equal("1.5e10", tokens[0].Value);
    }

    [Fact]
    public void TestExponentNotationNegative()
    {
        var tokens = Tokenize("2.5E-3");
        Assert.Equal(TokenType.FloatLiteral, tokens[0].Type);
        Assert.Equal("2.5E-3", tokens[0].Value);
    }

    [Fact]
    public void TestExponentNotationPositive()
    {
        var tokens = Tokenize("1e+5");
        Assert.Equal(TokenType.FloatLiteral, tokens[0].Type);
        Assert.Equal("1e+5", tokens[0].Value);
    }

    [Fact]
    public void TestFloatSuffix()
    {
        var tokens = Tokenize("1.5f");
        Assert.Equal(TokenType.FloatLiteral, tokens[0].Type);
        Assert.Equal("1.5f", tokens[0].Value);
    }

    [Fact]
    public void TestDecimalSuffix()
    {
        var tokens = Tokenize("1.5m");
        Assert.Equal(TokenType.FloatLiteral, tokens[0].Type);
        Assert.Equal("1.5m", tokens[0].Value);
    }

    [Fact]
    public void TestDecimalSuffixOnWholeNumber()
    {
        var tokens = Tokenize("0m");
        Assert.Equal(TokenType.FloatLiteral, tokens[0].Type);
        Assert.Equal("0m", tokens[0].Value);
    }

    [Fact]
    public void TestDoubleSuffix()
    {
        var tokens = Tokenize("1.5d");
        Assert.Equal(TokenType.FloatLiteral, tokens[0].Type);
        Assert.Equal("1.5d", tokens[0].Value);
    }

    [Fact]
    public void TestLongSuffix()
    {
        var tokens = Tokenize("42L");
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("42L", tokens[0].Value);
    }

    [Fact]
    public void TestUnsignedLongSuffix()
    {
        var tokens = Tokenize("100UL");
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("100UL", tokens[0].Value);
    }

    [Fact]
    public void TestUnsignedSuffix()
    {
        var tokens = Tokenize("42u");
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("42u", tokens[0].Value);
    }

    [Fact]
    public void TestInvalidHexLiteral_ProducesErrorToken()
    {
        // 0x without hex digits should produce Unknown token, not crash
        var tokens = Tokenize("0x ");
        Assert.Equal(TokenType.Unknown, tokens[0].Type);
    }

    [Fact]
    public void TestInvalidHexLiteral_LeadingUnderscore_ProducesErrorToken()
    {
        // 0x_ with only underscore and no hex digits should produce Unknown token
        var tokens = Tokenize("0x_ ");
        Assert.Equal(TokenType.Unknown, tokens[0].Type);
    }

    [Fact]
    public void TestInvalidBinaryLiteral_ProducesErrorToken()
    {
        // 0b without binary digits should produce Unknown token
        var tokens = Tokenize("0b ");
        Assert.Equal(TokenType.Unknown, tokens[0].Type);
    }

    [Fact]
    public void TestInvalidBinaryLiteral_LeadingUnderscore_ProducesErrorToken()
    {
        // 0b_ with only underscore and no binary digits should produce Unknown token
        var tokens = Tokenize("0b_ ");
        Assert.Equal(TokenType.Unknown, tokens[0].Type);
    }

    [Fact]
    public void TestInvalidExponent_ProducesErrorToken()
    {
        // 1e without digits should produce Unknown token
        var tokens = Tokenize("1e ");
        Assert.Equal(TokenType.Unknown, tokens[0].Type);
    }

    [Fact]
    public void TestMultipleDecimalPoints_ProducesErrorToken()
    {
        // Multiple decimal points should produce Unknown token, not throw
        var tokens = Tokenize("1.2.3");
        Assert.Equal(TokenType.Unknown, tokens[0].Type);
    }

    [Fact]
    public void TestUnderscoresInLargeNumber()
    {
        var tokens = Tokenize("1_000_000");
        Assert.Equal(TokenType.IntLiteral, tokens[0].Type);
        Assert.Equal("1000000", tokens[0].Value);
    }
}
