using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Token-boundary precision tests for the diagnostic span resolver
/// (<see cref="DiagnosticSpanResolver"/>, exercised through the public
/// <see cref="CompilerError.WithSnippet"/> entry point).
///
/// Every diagnostic underline must:
///   * start on a visible (non-whitespace) character,
///   * never start in the middle of an identifier,
///   * cover the whole offending token (full identifier, whole quoted string,
///     entire multi-character operator), and
///   * never collapse to length 0.
///
/// <see cref="CompilerError.WithSnippet"/> forwards the 1-based column and the
/// requested length (0 = "infer") to the resolver and surfaces the computed
/// 1-based column / underline length as <c>Column</c> / <c>Length</c>.
/// </summary>
public class DiagnosticSpanResolverTests
{
    private static (int Column, int Length) Resolve(string sourceLine, int oneBasedColumn, int requestedLength = 0)
    {
        var error = CompilerError.WithSnippet(
            ErrorCode.InvalidSyntax,
            "diagnostic",
            "test.nl",
            line: 1,
            column: oneBasedColumn,
            sourceSnippet: sourceLine,
            length: requestedLength);

        return (error.Column, error.Length);
    }

    // ---- Identifiers ---------------------------------------------------

    [Fact]
    public void Identifier_CoversWholeIdentifier()
    {
        var (column, length) = Resolve("let counter = 0", 5);

        Assert.Equal(5, column);
        Assert.Equal("counter".Length, length);
    }

    [Fact]
    public void Identifier_WithDigitsAndUnderscore_CoversWholeIdentifier()
    {
        var (column, length) = Resolve("value_2 := other", 1);

        Assert.Equal(1, column);
        Assert.Equal("value_2".Length, length);
    }

    [Fact]
    public void Identifier_ColumnInLeadingWhitespace_SnapsToVisibleToken()
    {
        // Column points at the leading indentation; the span must skip it.
        var (column, length) = Resolve("    print value", 1);

        Assert.Equal(5, column);
        Assert.Equal("print".Length, length);
    }

    [Fact]
    public void Keyword_CoversWholeKeyword()
    {
        var (column, length) = Resolve("return result", 1);

        Assert.Equal(1, column);
        Assert.Equal("return".Length, length);
    }

    // ---- Member access / nullable / null-forgiving ---------------------

    [Fact]
    public void MemberAccessChain_CoversEntireChain()
    {
        var (column, length) = Resolve("foo.bar.baz()", 1);

        Assert.Equal(1, column);
        Assert.Equal("foo.bar.baz".Length, length);
    }

    [Fact]
    public void NullableType_CoversIdentifierAndQuestionMark()
    {
        var (column, length) = Resolve("name int?", 6);

        Assert.Equal(6, column);
        Assert.Equal("int?".Length, length);
    }

    [Fact]
    public void NullForgiving_CoversIdentifierAndBang()
    {
        var (column, length) = Resolve("use value!", 5);

        Assert.Equal(5, column);
        Assert.Equal("value!".Length, length);
    }

    [Fact]
    public void Identifier_DoesNotSwallowFollowingNullConditionalOperator()
    {
        // `a?.b` -> the identifier `a` must NOT absorb the `?.` operator.
        var (column, length) = Resolve("a?.b", 1);

        Assert.Equal(1, column);
        Assert.Equal(1, length);
    }

    // ---- Numeric literals ----------------------------------------------

    [Fact]
    public void IntegerLiteral_CoversWholeNumber()
    {
        var (column, length) = Resolve("x := 12345", 6);

        Assert.Equal(6, column);
        Assert.Equal("12345".Length, length);
    }

    [Fact]
    public void FloatLiteral_CoversWholeNumberIncludingDecimalPoint()
    {
        var (column, length) = Resolve("x := 3.14", 6);

        Assert.Equal(6, column);
        Assert.Equal("3.14".Length, length);
    }

    // ---- String literals -----------------------------------------------

    [Fact]
    public void StringLiteral_CoversQuotesAndContents()
    {
        var snippet = "msg := \"hello world\"";
        var quoteColumn = snippet.IndexOf('"') + 1;

        var (column, length) = Resolve(snippet, quoteColumn);

        Assert.Equal(quoteColumn, column);
        Assert.Equal("\"hello world\"".Length, length);
    }

    [Fact]
    public void StringLiteral_WithEscapedQuote_CoversWholeLiteral()
    {
        // "a\"b" — the escaped quote must not terminate the literal early.
        var snippet = "s := \"a\\\"b\"";
        var quoteColumn = snippet.IndexOf('"') + 1;

        var (column, length) = Resolve(snippet, quoteColumn);

        Assert.Equal(quoteColumn, column);
        Assert.Equal("\"a\\\"b\"".Length, length);
    }

    [Fact]
    public void InterpolatedString_CoversDollarSignThroughClosingQuote()
    {
        var snippet = "msg := $\"hi {name}\"";
        var dollarColumn = snippet.IndexOf('$') + 1;

        var (column, length) = Resolve(snippet, dollarColumn);

        Assert.Equal(dollarColumn, column);
        Assert.Equal("$\"hi {name}\"".Length, length);
    }

    [Fact]
    public void CharLiteral_CoversQuotesAndContents()
    {
        var snippet = "c := 'x'";
        var quoteColumn = snippet.IndexOf('\'') + 1;

        var (column, length) = Resolve(snippet, quoteColumn);

        Assert.Equal(quoteColumn, column);
        Assert.Equal("'x'".Length, length);
    }

    // ---- Multi-character operators -------------------------------------

    [Theory]
    [InlineData("==")]
    [InlineData("!=")]
    [InlineData("<=")]
    [InlineData(">=")]
    [InlineData("=>")]
    [InlineData("::")]
    [InlineData(":=")]
    [InlineData("&&")]
    [InlineData("||")]
    [InlineData("??")]
    [InlineData("?.")]
    [InlineData("?[")]
    [InlineData("<<")]
    [InlineData(">>")]
    [InlineData("++")]
    [InlineData("--")]
    [InlineData("+=")]
    [InlineData("-=")]
    [InlineData("*=")]
    [InlineData("/=")]
    [InlineData("..")]
    public void TwoCharOperator_CoversWholeOperator(string op)
    {
        // Surround with spaces so the operator is the visible token at the column.
        var snippet = $"a {op} b";
        var opColumn = snippet.IndexOf(op, System.StringComparison.Ordinal) + 1;

        var (column, length) = Resolve(snippet, opColumn);

        Assert.Equal(opColumn, column);
        Assert.Equal(2, length);
    }

    [Theory]
    [InlineData("??=")]
    [InlineData("...")]
    public void ThreeCharOperator_CoversWholeOperator(string op)
    {
        var snippet = $"a {op} b";
        var opColumn = snippet.IndexOf(op, System.StringComparison.Ordinal) + 1;

        var (column, length) = Resolve(snippet, opColumn);

        Assert.Equal(opColumn, column);
        Assert.Equal(3, length);
    }

    [Fact]
    public void Operator_ColumnInLeadingWhitespace_SnapsToOperator()
    {
        // Column points at whitespace; nearest visible token is the operator.
        var snippet = "x  == y";
        var (column, length) = Resolve(snippet, 2);

        Assert.Equal(snippet.IndexOf("==", System.StringComparison.Ordinal) + 1, column);
        Assert.Equal(2, length);
    }

    // ---- Single-character punctuation ----------------------------------

    [Theory]
    [InlineData("(")]
    [InlineData(")")]
    [InlineData("{")]
    [InlineData("}")]
    [InlineData("[")]
    [InlineData("]")]
    [InlineData(",")]
    [InlineData(";")]
    [InlineData("+")]
    [InlineData("-")]
    [InlineData("*")]
    [InlineData("/")]
    [InlineData("<")]
    [InlineData(">")]
    [InlineData("=")]
    [InlineData(":")]
    [InlineData("!")]
    [InlineData("?")]
    public void SingleCharPunctuation_CoversOneChar(string punctuation)
    {
        var snippet = $"a {punctuation} b";
        var column = snippet.IndexOf(punctuation, System.StringComparison.Ordinal) + 1;

        var (resolvedColumn, length) = Resolve(snippet, column);

        Assert.Equal(column, resolvedColumn);
        Assert.Equal(1, length);
    }

    // ---- Boundary / contract guarantees --------------------------------

    [Fact]
    public void ColumnPastEndOfLine_ProducesLengthOne()
    {
        var (column, length) = Resolve("ab", 10);

        Assert.Equal(10, column);
        Assert.Equal(1, length);
    }

    [Fact]
    public void TokenAtEndOfLine_DoesNotOverrun()
    {
        var snippet = "value foo";
        var (column, length) = Resolve(snippet, snippet.IndexOf("foo", System.StringComparison.Ordinal) + 1);

        Assert.Equal(snippet.IndexOf("foo", System.StringComparison.Ordinal) + 1, column);
        Assert.Equal("foo".Length, length);
    }

    [Fact]
    public void TrailingWhitespaceColumn_SnapsBackToPrecedingToken()
    {
        // Column points into trailing whitespace with no following token.
        var snippet = "result   ";
        var (column, length) = Resolve(snippet, 8);

        Assert.Equal(1, column);
        Assert.Equal("result".Length, length);
    }

    [Fact]
    public void ExplicitRequestedLength_IsHonored()
    {
        var (column, length) = Resolve("anything here", oneBasedColumn: 3, requestedLength: 4);

        Assert.Equal(3, column);
        Assert.Equal(4, length);
    }

    [Fact]
    public void EmptySourceLine_ProducesLengthOne()
    {
        var (column, length) = Resolve(string.Empty, 1);

        Assert.Equal(1, column);
        Assert.Equal(1, length);
    }

    [Fact]
    public void Resolve_NeverProducesZeroLength()
    {
        var samples = new[]
        {
            "let x = 1",
            "    spaced",
            "a == b",
            "foo.bar.baz",
            "\"string\"",
            "$\"interp {x}\"",
            "obj?.member",
            "i++",
            "value!",
            "int?",
            ";",
            "",
        };

        foreach (var sample in samples)
        {
            for (var col = 1; col <= System.Math.Max(1, sample.Length) + 2; col++)
            {
                var (_, length) = Resolve(sample, col);
                Assert.True(length >= 1, $"length {length} for column {col} in `{sample}`");
            }
        }
    }
}
