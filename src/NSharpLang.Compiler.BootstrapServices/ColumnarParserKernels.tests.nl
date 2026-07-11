namespace NSharpLang.Compiler.Columnar

import System
import NSharpLang.Compiler

class ColumnarNumericLiteralParseProbe {
    public Source: string
    public RawKinds: int[]
    public RawStarts: int[]
    public RawValueLengths: int[]
    public TokenKinds: int[]
    public TokenStarts: int[]
    public TokenValueLengths: int[]
    public TokenCount: int
    public RawCount: int
    public NodeKinds: int[]
    public NodeValueStarts: int[]
    public NodeValueLengths: int[]
    public NodeChildStarts: int[]
    public NodeChildCounts: int[]
    public NodeChildren: int[]
    public NodeSpanStarts: int[]
    public NodeSpanLengths: int[]
    public ParseResult: int[]
    public NodeCount: int

    constructor(source: string) {
        Source = source
        capacity := source.Length * 3 + 16
        RawKinds = new int[](capacity)
        RawStarts = new int[](capacity)
        RawValueLengths = new int[](capacity)
        TokenKinds = new int[](capacity)
        TokenStarts = new int[](capacity)
        TokenValueLengths = new int[](capacity)
        tokenCounts := new int[](2)
        TokenCount = TokenizeColumnarSourceInto(
            source,
            RawKinds,
            RawStarts,
            RawValueLengths,
            TokenKinds,
            TokenStarts,
            TokenValueLengths,
            tokenCounts)
        RawCount = tokenCounts[0]

        NodeKinds = new int[](capacity)
        NodeValueStarts = new int[](capacity)
        NodeValueLengths = new int[](capacity)
        NodeChildStarts = new int[](capacity)
        NodeChildCounts = new int[](capacity)
        NodeChildren = new int[](capacity * 4)
        NodeSpanStarts = new int[](capacity)
        NodeSpanLengths = new int[](capacity)
        ParseResult = new int[](3)
        NodeCount = ParseColumnarExpressionInto(
            source,
            TokenKinds,
            TokenStarts,
            TokenValueLengths,
            TokenCount,
            NodeKinds,
            NodeValueStarts,
            NodeValueLengths,
            NodeChildStarts,
            NodeChildCounts,
            NodeChildren,
            NodeSpanStarts,
            NodeSpanLengths,
            ParseResult)
    }

    public func AssertSingleLiteral(expectedTokenKind: int, expectedNodeKind: int): void {
        assert RawCount == 2
        assert TokenCount == 2
        assert RawKinds[0] == expectedTokenKind
        assert RawStarts[0] == 0
        assert RawValueLengths[0] == Source.Length
        assert Source.Substring(RawStarts[0], RawValueLengths[0]) == Source
        assert TokenKinds[0] == expectedTokenKind
        assert TokenStarts[0] == 0
        assert TokenValueLengths[0] == Source.Length
        assert Source.Substring(TokenStarts[0], TokenValueLengths[0]) == Source

        assert NodeCount == 1
        assert ParseResult[0] == 0
        assert ParseResult[1] == 1
        assert ParseResult[2] == 0
        assert NodeKinds[0] == expectedNodeKind
        assert NodeValueStarts[0] == 0
        assert NodeValueLengths[0] == Source.Length
        assert Source.Substring(NodeValueStarts[0], NodeValueLengths[0]) == Source
        assert NodeSpanStarts[0] == 0
        assert NodeSpanLengths[0] == Source.Length
        assert Source.Substring(NodeSpanStarts[0], NodeSpanLengths[0]) == Source
    }
}

func AssertColumnarSeparatedIntegerLiteral(source: string, expectedValue: ulong): void {
    probe := new ColumnarNumericLiteralParseProbe(source)
    probe.AssertSingleLiteral(1, ColumnarExpressionNodeKind.IntLiteralExpression())
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude(source) == expectedValue
}

func AssertMalformedColumnarNumberPrefix(source: string, consumedText: string): void {
    capacity := source.Length * 3 + 16
    rawKinds := new int[](capacity)
    rawStarts := new int[](capacity)
    rawValueLengths := new int[](capacity)
    tokenKinds := new int[](capacity)
    tokenStarts := new int[](capacity)
    tokenValueLengths := new int[](capacity)
    tokenCounts := new int[](2)
    tokenCount := TokenizeColumnarSourceInto(
        source,
        rawKinds,
        rawStarts,
        rawValueLengths,
        tokenKinds,
        tokenStarts,
        tokenValueLengths,
        tokenCounts)

    assert tokenCounts[0] == 3
    assert tokenCount == 3
    assert rawKinds[0] == 137
    assert rawStarts[0] == 0
    assert rawValueLengths[0] == consumedText.Length
    assert source.Substring(rawStarts[0], rawValueLengths[0]) == consumedText
    assert tokenKinds[0] == 137
    assert tokenStarts[0] == 0
    assert tokenValueLengths[0] == consumedText.Length
    assert source.Substring(tokenStarts[0], tokenValueLengths[0]) == consumedText

    assert rawKinds[1] == 0
    assert rawStarts[1] == consumedText.Length
    assert rawValueLengths[1] == source.Length - consumedText.Length
    assert source.Substring(rawStarts[1], rawValueLengths[1]) == source.Substring(consumedText.Length)
}

test "literal node-kind ledger owns every primary literal ordinal" {
    assert ColumnarExpressionNodeKind.IntLiteralExpression() == 0
    assert ColumnarExpressionNodeKind.FloatLiteralExpression() == 1
    assert ColumnarExpressionNodeKind.CharLiteralExpression() == 2
    assert ColumnarExpressionNodeKind.StringLiteralExpression() == 3
    assert ColumnarExpressionNodeKind.TypeOfExpression() == 55
    assert ColumnarExpressionNodeKind.BoolLiteralExpression() == 4
    assert ColumnarExpressionNodeKind.NullLiteralExpression() == 5

    assert ColumnarPrimaryConstructorLiteralExpressionKind(1) == ColumnarExpressionNodeKind.IntLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(2) == ColumnarExpressionNodeKind.FloatLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(3) == ColumnarExpressionNodeKind.CharLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(4) == ColumnarExpressionNodeKind.StringLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(44) == ColumnarExpressionNodeKind.BoolLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(45) == ColumnarExpressionNodeKind.BoolLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(46) == ColumnarExpressionNodeKind.NullLiteralExpression()
}

test "columnar decimal literal spans preserve separators and value" {
    AssertColumnarSeparatedIntegerLiteral("1_000UL", 1000UL)
}

test "columnar hexadecimal literal spans preserve separators and value" {
    AssertColumnarSeparatedIntegerLiteral("0xFF_FFUL", 65535UL)
}

test "columnar binary literal spans preserve separators and value" {
    AssertColumnarSeparatedIntegerLiteral("0b1010_0101", 165UL)
}

test "columnar integer suffix remains inside a separated literal span" {
    AssertColumnarSeparatedIntegerLiteral("4_2uL", 42UL)
}

test "columnar floating literal spans preserve separators and scanner kind" {
    source := "1_2.5_0e+1"
    probe := new ColumnarNumericLiteralParseProbe(source)
    probe.AssertSingleLiteral(2, ColumnarExpressionNodeKind.FloatLiteralExpression())
}

test "columnar range adjacency preserves both separated literal spans" {
    source := "1_0..2_0"
    probe := new ColumnarNumericLiteralParseProbe(source)

    assert probe.RawCount == 4
    assert probe.TokenCount == 4
    assert probe.RawKinds[0] == 1
    assert probe.RawStarts[0] == 0
    assert probe.RawValueLengths[0] == 3
    assert source.Substring(probe.RawStarts[0], probe.RawValueLengths[0]) == "1_0"
    assert probe.RawKinds[1] == 125
    assert probe.RawStarts[1] == 3
    assert probe.RawValueLengths[1] == 2
    assert source.Substring(probe.RawStarts[1], probe.RawValueLengths[1]) == ".."
    assert probe.RawKinds[2] == 1
    assert probe.RawStarts[2] == 5
    assert probe.RawValueLengths[2] == 3
    assert source.Substring(probe.RawStarts[2], probe.RawValueLengths[2]) == "2_0"

    assert probe.NodeCount == 3
    assert probe.ParseResult[0] == 2
    assert probe.NodeKinds[0] == ColumnarExpressionNodeKind.IntLiteralExpression()
    assert probe.NodeValueStarts[0] == 0
    assert probe.NodeValueLengths[0] == 3
    assert source.Substring(probe.NodeValueStarts[0], probe.NodeValueLengths[0]) == "1_0"
    assert probe.NodeKinds[1] == ColumnarExpressionNodeKind.IntLiteralExpression()
    assert probe.NodeValueStarts[1] == 5
    assert probe.NodeValueLengths[1] == 3
    assert source.Substring(probe.NodeValueStarts[1], probe.NodeValueLengths[1]) == "2_0"
    assert probe.NodeKinds[2] == ColumnarExpressionNodeKind.RangeExpression()
    assert probe.NodeValueStarts[2] == 3
    assert probe.NodeValueLengths[2] == 2
    assert probe.NodeChildCounts[2] == 2
    assert probe.NodeChildren[probe.NodeChildStarts[2]] == 0
    assert probe.NodeChildren[probe.NodeChildStarts[2] + 1] == 1
    assert probe.NodeSpanStarts[2] == 0
    assert probe.NodeSpanLengths[2] == source.Length
    assert source.Substring(probe.NodeSpanStarts[2], probe.NodeSpanLengths[2]) == source
}

test "malformed based literals stop before a leading separator" {
    AssertMalformedColumnarNumberPrefix("0x_FF", "0x")
    AssertMalformedColumnarNumberPrefix("0b_10", "0b")
}

test "malformed exponent stops after its sign before a separator" {
    AssertMalformedColumnarNumberPrefix("1_0e+_2", "1_0e+")
}

test "enum integer value consumer ignores numeric separators" {
    values := new EnumMemberValueTable(new int[](3))
    maxText := "2_147_483_647"
    // The live scanner accepts trailing separators after the required first digit. Keep the
    // enum consumer aligned with that existing spelling contract at the signed lower bound.
    minText := "-2_147_483_648_"
    overflowText := "2_147_483_648"

    assert ParserDeclarationTryParseIntLiteralCore(maxText, 0, maxText.Length, values, 0)
    assert values.Values[0] == 2147483647
    assert ParserDeclarationTryParseIntLiteralCore(minText, 0, minText.Length, values, 1)
    assert values.Values[1] == 0 - 2147483647 - 1
    assert !ParserDeclarationTryParseIntLiteralCore(overflowText, 0, overflowText.Length, values, 2)
}
