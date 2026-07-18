namespace NSharpLang.Compiler.Columnar

import NSharpLang.Compiler

class ColumnarNumericLiteralParseProbe {
    Source: string
    RawKinds: int[]
    RawStarts: int[]
    RawValueLengths: int[]
    TokenKinds: int[]
    TokenStarts: int[]
    TokenValueLengths: int[]
    TokenCount: int
    RawCount: int
    NodeKinds: int[]
    NodeValueStarts: int[]
    NodeValueLengths: int[]
    NodeChildStarts: int[]
    NodeChildCounts: int[]
    NodeChildren: int[]
    NodeSpanStarts: int[]
    NodeSpanLengths: int[]
    ParseResult: int[]
    NodeCount: int

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
        TokenCount = TokenizeColumnarSourceInto(source, RawKinds, RawStarts, RawValueLengths, TokenKinds, TokenStarts, TokenValueLengths, tokenCounts)

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
        NodeCount = ParseColumnarExpressionInto(source, TokenKinds, TokenStarts, TokenValueLengths, TokenCount, NodeKinds, NodeValueStarts, NodeValueLengths, NodeChildStarts, NodeChildCounts, NodeChildren, NodeSpanStarts, NodeSpanLengths, ParseResult)
    }

    func AssertSingleLiteral(expectedTokenKind: int, expectedNodeKind: int): void {
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

class ColumnarConstructorDefaultParseProbe {
    ParamCount: int
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ArgKinds: int[]
    ArgTexts: string[]
    Result: int[]

    constructor(source: string) {
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

        ParamNameTexts = new string[](capacity)
        ParamTypeTexts = new string[](capacity)
        ArgKinds = new int[](capacity)
        argStarts := new int[](capacity)
        argLengths := new int[](capacity)
        ArgTexts = new string[](capacity)
        nodeKinds := new int[](capacity)
        valueStarts := new int[](capacity)
        valueLengths := new int[](capacity)
        childStarts := new int[](capacity)
        childCounts := new int[](capacity)
        childIndices := new int[](capacity * 4)
        spanStarts := new int[](capacity)
        spanLengths := new int[](capacity)
        Result = new int[](6)

        ParamCount = ParseColumnarConstructorInfoInto(
            source,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCount,
            0,
            ParamNameTexts,
            ParamTypeTexts,
            ArgKinds,
            argStarts,
            argLengths,
            ArgTexts,
            nodeKinds,
            valueStarts,
            valueLengths,
            childStarts,
            childCounts,
            childIndices,
            spanStarts,
            spanLengths,
            Result)
    }
}

class ColumnarStructDeclarationParseProbe {
    FieldCount: int
    TypeParamTexts: string[]
    BaseNameTexts: string[]
    StructNameTexts: string[]
    Result: int[]

    constructor(source: string) {
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

        fieldNameTexts := new string[](capacity)
        fieldTypeTexts := new string[](capacity)
        fieldStaticFlags := new int[](capacity)
        fieldInitKinds := new int[](capacity)
        fieldInitTexts := new string[](capacity)
        methodFuncIndices := new int[](capacity)
        methodStaticFlags := new int[](capacity)
        constructorIndices := new int[](capacity)
        propertyIndices := new int[](capacity)
        propertyStaticFlags := new int[](capacity)
        TypeParamTexts = new string[](capacity)
        BaseNameTexts = new string[](capacity)
        StructNameTexts = new string[](1)
        Result = new int[](10)
        structIndex := 0
        while structIndex < tokenCount
            && tokenKinds[structIndex] != 8
            && tokenKinds[structIndex] != 9
            && tokenKinds[structIndex] != 13 {
            structIndex = structIndex + 1
        }
        FieldCount = ParseColumnarStructInfoInto(
            source,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCount,
            structIndex,
            1,
            0,
            fieldNameTexts,
            fieldTypeTexts,
            fieldStaticFlags,
            fieldInitKinds,
            fieldInitTexts,
            methodFuncIndices,
            methodStaticFlags,
            constructorIndices,
            propertyIndices,
            propertyStaticFlags,
            TypeParamTexts,
            BaseNameTexts,
            StructNameTexts,
            Result)
    }
}

class ColumnarNestedStructDeclarationProbe {
    ScanStatus: int
    Count: int
    StructIndices: int[]
    ReferenceFlags: int[]
    RecordFlags: int[]
    VisibilityFlags: int[]
    EnclosingTypeNames: string[]

    constructor(source: string) {
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

        StructIndices = new int[](capacity)
        ReferenceFlags = new int[](capacity)
        RecordFlags = new int[](capacity)
        VisibilityFlags = new int[](capacity)
        EnclosingTypeNames = new string[](capacity)
        result := new int[](6)
        ScanStatus = ColumnarProgramDeclarationIndicesInto(
            source,
            rawKinds,
            rawStarts,
            rawValueLengths,
            tokenCounts[0],
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCount,
            new int[](capacity),
            new int[](capacity),
            new int[](capacity),
            new int[](capacity),
            new int[](capacity),
            StructIndices,
            ReferenceFlags,
            RecordFlags,
            VisibilityFlags,
            EnclosingTypeNames,
            result)
        Count = ScanStatus < 0 ? -1 : result[5]
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
    tokenCount := TokenizeColumnarSourceInto(source, rawKinds, rawStarts, rawValueLengths, tokenKinds, tokenStarts, tokenValueLengths, tokenCounts)

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
    assert ColumnarExpressionNodeKind.CallExpression() == 9
    assert ColumnarExpressionNodeKind.BinaryExpression() == 12

    assert ColumnarPrimaryConstructorLiteralExpressionKind(1) == ColumnarExpressionNodeKind.IntLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(2) == ColumnarExpressionNodeKind.FloatLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(3) == ColumnarExpressionNodeKind.CharLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(4) == ColumnarExpressionNodeKind.StringLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(44) == ColumnarExpressionNodeKind.BoolLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(45) == ColumnarExpressionNodeKind.BoolLiteralExpression()
    assert ColumnarPrimaryConstructorLiteralExpressionKind(46) == ColumnarExpressionNodeKind.NullLiteralExpression()
}

test "constructor parser preserves dotted enum member defaults" {
    probe := new ColumnarConstructorDefaultParseProbe(
        "constructor(count: int, day: System.DayOfWeek = System . DayOfWeek . Friday) {}")

    assert probe.ParamCount == 2
    assert probe.Result[2] == 2
    assert probe.ParamNameTexts[0] == "count"
    assert probe.ParamNameTexts[1] == "day"
    assert probe.ParamTypeTexts[0] == "int"
    assert probe.ParamTypeTexts[1] == "System.DayOfWeek"
    assert probe.ArgKinds[0] == -1
    assert probe.ArgTexts[0] == ""
    assert probe.ArgKinds[1] == 1000
    assert probe.ArgTexts[1] == "System.DayOfWeek.Friday"
}

test "primary constructor parser canonicalizes dotted enum member defaults" {
    probe := new ColumnarConstructorDefaultParseProbe(
        "class Schedule(count: int, day: System.DayOfWeek = System . DayOfWeek . Friday) {}")

    assert probe.ParamCount == 2
    assert probe.Result[2] == 2
    assert probe.ParamNameTexts[0] == "count"
    assert probe.ParamNameTexts[1] == "day"
    assert probe.ParamTypeTexts[0] == "int"
    assert probe.ParamTypeTexts[1] == "System.DayOfWeek"
    assert probe.ArgKinds[0] == -1
    assert probe.ArgTexts[0] == ""
    assert probe.ArgKinds[1] == 1000
    assert probe.ArgTexts[1] == "System.DayOfWeek.Friday"
}

test "struct parser preserves generic parameters alongside a constructed base" {
    probe := new ColumnarStructDeclarationParseProbe(
        "class Derived<X,Y>: Base<string,Y> {}")

    assert probe.FieldCount == 0
    assert probe.Result[7] == 2
    assert probe.Result[8] == 1
    assert probe.TypeParamTexts[0] == "X"
    assert probe.TypeParamTexts[1] == "Y"
    assert probe.BaseNameTexts[0] == "Base<string,Y>"
    assert probe.StructNameTexts[0] == "Derived"
}

test "struct parser leaves namespace ownership with the file binding scope" {
    probe := new ColumnarStructDeclarationParseProbe(
        "namespace Scope\nclass Widget {}")

    assert probe.FieldCount == 0
    assert probe.StructNameTexts[0] == "Widget"
}

test "program declaration scanner appends nested lexical owner paths and declaration kinds" {
    probe := new ColumnarNestedStructDeclarationProbe(
        "class Outer { public class Sibling {} class Middle { record struct Value {} class Inner {} } func Run() { value := typeof(string) } }")

    assert probe.ScanStatus >= 0
    assert probe.Count == 5
    assert probe.EnclosingTypeNames[1] == "Outer"
    assert probe.EnclosingTypeNames[2] == "Outer"
    assert probe.EnclosingTypeNames[3] == "Outer.Middle"
    assert probe.EnclosingTypeNames[4] == "Outer.Middle"
    assert probe.ReferenceFlags[1] == 1
    assert probe.RecordFlags[1] == 0
    assert probe.ReferenceFlags[2] == 1
    assert probe.RecordFlags[2] == 0
    assert probe.ReferenceFlags[3] == 0
    assert probe.RecordFlags[3] == 1
    assert probe.ReferenceFlags[4] == 1
    assert probe.RecordFlags[4] == 0
    assert probe.VisibilityFlags[1] == 1
    assert probe.VisibilityFlags[2] == 0
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

class ColumnarInterfaceModifierParseProbe {
    MethodCount: int
    MethodNames: string[]
    MethodParamCounts: int[]
    MethodParamNames: string[]
    MethodParamTypes: string[]
    MethodParamModifierKinds: int[]
    MethodBodyFlags: int[]
    Result: int[]

    constructor(source: string) {
        capacity := source.Length * 3 + 16
        rawKinds := new int[](capacity)
        rawStarts := new int[](capacity)
        rawValueLengths := new int[](capacity)
        tokenKinds := new int[](capacity)
        tokenStarts := new int[](capacity)
        tokenValueLengths := new int[](capacity)
        tokenCounts := new int[](2)
        tokenCount := TokenizeColumnarSourceInto(source, rawKinds, rawStarts, rawValueLengths, tokenKinds, tokenStarts, tokenValueLengths, tokenCounts)

        methodFuncIndices := new int[](capacity)
        baseNames := new string[](capacity)
        interfaceNames := new string[](1)
        MethodNames = new string[](capacity)
        methodReturns := new string[](capacity)
        MethodParamCounts = new int[](capacity)
        MethodBodyFlags = new int[](capacity)
        MethodParamNames = new string[](capacity)
        MethodParamTypes = new string[](capacity)
        MethodParamModifierKinds = new int[](capacity)
        typeParams := new string[](capacity)
        Result = new int[](8)
        MethodCount = ParseColumnarInterfaceInfoInto(source, tokenKinds, tokenStarts, tokenValueLengths, tokenCount, 0, methodFuncIndices, baseNames, interfaceNames, MethodNames, methodReturns, MethodParamCounts, MethodBodyFlags, MethodParamNames, MethodParamTypes, MethodParamModifierKinds, typeParams, Result)
    }
}

test "columnar interface parser flattens ref out and params modifier facts" {
    source := "interface IModifierProbe {\n    func Mutate(ref left: int, out right: int)\n    func Collect(params rest: string[])\n}\n"
    probe := new ColumnarInterfaceModifierParseProbe(source)

    assert probe.MethodCount == 2
    assert probe.MethodNames[0] == "Mutate"
    assert probe.MethodNames[1] == "Collect"
    assert probe.MethodParamCounts[0] == 2
    assert probe.MethodParamCounts[1] == 1
    assert probe.MethodBodyFlags[0] == 0
    assert probe.MethodBodyFlags[1] == 0
    assert probe.Result[3] == 3
    assert probe.MethodParamNames[0] == "left"
    assert probe.MethodParamNames[1] == "right"
    assert probe.MethodParamNames[2] == "rest"
    assert probe.MethodParamModifierKinds[0] == 1
    assert probe.MethodParamModifierKinds[1] == 2
    assert probe.MethodParamModifierKinds[2] == 3
}

test "columnar interface input carries modifiers while old construction defaults to ordinary parameters" {
    methodNames := new string[](1)
    methodNames[0] = "Apply"
    returnTypes := new string[](1)
    returnTypes[0] = "void"
    parameterNames := new string[][](1)
    parameterNames[0] = new string[](3)
    parameterNames[0][0] = "left"
    parameterNames[0][1] = "right"
    parameterNames[0][2] = "rest"
    parameterTypes := new string[][](1)
    parameterTypes[0] = new string[](3)
    parameterTypes[0][0] = "int&"
    parameterTypes[0][1] = "int&"
    parameterTypes[0][2] = "string[]"
    modifierKinds := new int[][](1)
    modifierKinds[0] = new int[](3)
    modifierKinds[0][0] = 1
    modifierKinds[0][1] = 2
    modifierKinds[0][2] = 3

    input := new ColumnarInterfaceInput("IModifierProbe", new string[](0), methodNames, returnTypes, parameterNames, parameterTypes, new ColumnarFunctionInput?[](1), new string[](0), 0, modifierKinds)

    assert input.MethodParamModifierKinds[0][0] == 1
    assert input.MethodParamModifierKinds[0][1] == 2
    assert input.MethodParamModifierKinds[0][2] == 3

    ordinaryInput := new ColumnarInterfaceInput("IOrdinaryProbe", new string[](0), methodNames, returnTypes, parameterNames, parameterTypes)

    assert ordinaryInput.MethodParamModifierKinds.Length == 1
    assert ordinaryInput.MethodParamModifierKinds[0].Length == 3
    assert ordinaryInput.MethodParamModifierKinds[0][0] == 0
    assert ordinaryInput.MethodParamModifierKinds[0][1] == 0
    assert ordinaryInput.MethodParamModifierKinds[0][2] == 0
}
