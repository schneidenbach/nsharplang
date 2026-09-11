namespace NSharpLang.Compiler.Columnar

import System
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

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
            tokenCounts
        )

        ParamNameTexts = new string[](capacity)
        ParamTypeTexts = new string[](capacity)
        paramLabeledTypeTexts := new string[](capacity)
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
            paramLabeledTypeTexts,
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
            Result
        )
    }
}

class ColumnarStructDeclarationParseProbe {
    FieldCount: int
    FieldNameTexts: string[]
    FieldTypeTexts: string[]
    FieldStaticFlags: int[]
    FieldInitKinds: int[]
    FieldInitTexts: string[]
    TypeParamTexts: string[]
    BaseNameTexts: string[]
    StructNameTexts: string[]
    WhereOwnerTexts: string[]
    WhereItemCodes: int[]
    WhereTypeTexts: string[]
    ConstructorIndices: int[]
    ConstructorVisibilityFlags: int[]
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
            tokenCounts
        )

        FieldNameTexts = new string[](capacity)
        FieldTypeTexts = new string[](capacity)
        FieldStaticFlags = new int[](capacity)
        FieldInitKinds = new int[](capacity)
        FieldInitTexts = new string[](capacity)
        methodFuncIndices := new int[](capacity)
        methodStaticFlags := new int[](capacity)
        ConstructorIndices = new int[](capacity)
        ConstructorVisibilityFlags = new int[](capacity)
        propertyIndices := new int[](capacity)
        propertyStaticFlags := new int[](capacity)
        TypeParamTexts = new string[](capacity)
        BaseNameTexts = new string[](capacity)
        StructNameTexts = new string[](1)
        WhereOwnerTexts = new string[](capacity)
        WhereItemCodes = new int[](capacity)
        WhereTypeTexts = new string[](capacity)
        Result = new int[](11)
        structIndex := 0
        while structIndex < tokenCount && tokenKinds[structIndex] != 8 && tokenKinds[structIndex] != 9 && tokenKinds[structIndex] != 13 {
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
            FieldNameTexts,
            FieldTypeTexts,
            FieldStaticFlags,
            FieldInitKinds,
            FieldInitTexts,
            methodFuncIndices,
            methodStaticFlags,
            ConstructorIndices,
            propertyIndices,
            propertyStaticFlags,
            TypeParamTexts,
            BaseNameTexts,
            StructNameTexts,
            WhereOwnerTexts,
            WhereItemCodes,
            WhereTypeTexts,
            Result
        )

        constructorOffset := 0
        while constructorOffset < Result[3] {
            ConstructorVisibilityFlags[constructorOffset] = ColumnarConstructorDeclarationMetadataModifierFlagsAt(tokenKinds, ConstructorIndices[constructorOffset])
            constructorOffset = constructorOffset + 1
        }
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
            tokenCounts
        )

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
            new int[](capacity),
            StructIndices,
            ReferenceFlags,
            RecordFlags,
            VisibilityFlags,
            EnclosingTypeNames,
            result
        )
        Count = ScanStatus < 0 ? -1 : result[5]
    }
}

func ColumnarProgramDeclarationNullVisibilityStatus(source: string): int {
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
        tokenCounts
    )

    return ColumnarProgramDeclarationIndicesInto(
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
        new int[](capacity),
        new int[](capacity),
        new int[](capacity),
        new int[](capacity),
        null,
        new string[](capacity),
        new int[](6)
    )
}

// Runs the top-level declaration scan and captures the per-function async/generator facts. A `func*`
// declaration sets GeneratorFlags[k] = 1 (parallel to AsyncFlags); an ordinary `func` leaves it 0.
class ColumnarFunctionGeneratorScanProbe {
    ScanStatus: int
    FuncCount: int
    FuncIndices: int[]
    AsyncFlags: int[]
    GeneratorFlags: int[]

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
            tokenCounts
        )

        FuncIndices = new int[](capacity)
        AsyncFlags = new int[](capacity)
        GeneratorFlags = new int[](capacity)
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
            FuncIndices,
            AsyncFlags,
            GeneratorFlags,
            new int[](capacity),
            new int[](capacity),
            new int[](capacity),
            new int[](capacity),
            new int[](capacity),
            new int[](capacity),
            new int[](capacity),
            new string[](capacity),
            result
        )
        FuncCount = ScanStatus < 0 ? -1 : result[1]
    }
}

// Parses a whole `func` (or `func*`) via the product function ABI and counts YieldStatement (kind 72)
// nodes in the emitted body node table. Uses only raw int/string arrays and the product ABI, the same
// emit shape the declaration-scan probes use, so it materializes under the stage-0 columnar backend.
class ColumnarFunctionBodyYieldProbe {
    Status: int
    YieldNodeCount: int

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
            tokenCounts
        )

        funcIndex := 0
        while funcIndex < tokenCount && tokenKinds[funcIndex] != 7 {
            funcIndex = funcIndex + 1
        }

        functionNameTexts := new string[](1)
        returnTypeTexts := new string[](1)
        paramNameTexts := new string[](capacity)
        paramTypeTexts := new string[](capacity)
        paramModifierKinds := new int[](capacity)
        paramDefaultKinds := new int[](capacity)
        paramDefaultTexts := new string[](capacity)
        paramTupleNameCounts := new int[](capacity)
        paramTupleNameTexts := new string[](capacity)
        returnTupleNameTexts := new string[](capacity)
        returnLabeledTypeTexts := new string[](capacity)
        paramLabeledTypeTexts := new string[](capacity)
        typeParamTexts := new string[](capacity)
        typeParamSpecials := new int[](capacity)
        typeParamConstraintCounts := new int[](capacity)
        typeParamConstraintTypeTexts := new string[](capacity)
        nodeKinds := new int[](capacity)
        valueStarts := new int[](capacity)
        valueLengths := new int[](capacity)
        childStart := new int[](capacity)
        childCount := new int[](capacity)
        childIndices := new int[](capacity)
        spanStarts := new int[](capacity)
        spanLengths := new int[](capacity)
        localFunctionNodeIndices := new int[](capacity)
        localFunctionTokenIndices := new int[](capacity)
        result := new int[](9)

        Status = ParseColumnarProductFunctionInfoInto(
            source,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCount,
            funcIndex,
            0,
            functionNameTexts,
            returnTypeTexts,
            paramNameTexts,
            paramTypeTexts,
            paramModifierKinds,
            paramDefaultKinds,
            paramDefaultTexts,
            paramTupleNameCounts,
            paramTupleNameTexts,
            returnTupleNameTexts,
            returnLabeledTypeTexts,
            paramLabeledTypeTexts,
            typeParamTexts,
            typeParamSpecials,
            typeParamConstraintCounts,
            typeParamConstraintTypeTexts,
            nodeKinds,
            valueStarts,
            valueLengths,
            childStart,
            childCount,
            childIndices,
            spanStarts,
            spanLengths,
            localFunctionNodeIndices,
            localFunctionTokenIndices,
            result
        )

        YieldNodeCount = 0
        if Status >= 0 {
            bodyNodeCount := result[7]
            n := 0
            while n < bodyNodeCount {
                if nodeKinds[n] == 72 {
                    YieldNodeCount = YieldNodeCount + 1
                }

                n = n + 1
            }
        }
    }
}

// Parses a whole `func` via the product function ABI and reports every IsExpression (kind 46) in the
// emitted body node table: how many there are, the first one's PATTERN VARIABLE text ("" when the node
// carries none), and how many statements the body block holds — the last of which is what catches a
// swallowed binding, because an orphaned name becomes an extra statement. Same raw-array emit shape as
// the yield probe so it materializes under the stage-0 columnar backend.
class ColumnarFunctionBodyIsPatternProbe {
    Status: int
    IsNodeCount: int
    FirstBindingText: string
    StatementCount: int

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
            tokenCounts
        )

        funcIndex := 0
        while funcIndex < tokenCount && tokenKinds[funcIndex] != 7 {
            funcIndex = funcIndex + 1
        }

        functionNameTexts := new string[](1)
        returnTypeTexts := new string[](1)
        paramNameTexts := new string[](capacity)
        paramTypeTexts := new string[](capacity)
        paramModifierKinds := new int[](capacity)
        paramDefaultKinds := new int[](capacity)
        paramDefaultTexts := new string[](capacity)
        paramTupleNameCounts := new int[](capacity)
        paramTupleNameTexts := new string[](capacity)
        returnTupleNameTexts := new string[](capacity)
        returnLabeledTypeTexts := new string[](capacity)
        paramLabeledTypeTexts := new string[](capacity)
        typeParamTexts := new string[](capacity)
        typeParamSpecials := new int[](capacity)
        typeParamConstraintCounts := new int[](capacity)
        typeParamConstraintTypeTexts := new string[](capacity)
        nodeKinds := new int[](capacity)
        valueStarts := new int[](capacity)
        valueLengths := new int[](capacity)
        childStart := new int[](capacity)
        childCount := new int[](capacity)
        childIndices := new int[](capacity)
        spanStarts := new int[](capacity)
        spanLengths := new int[](capacity)
        localFunctionNodeIndices := new int[](capacity)
        localFunctionTokenIndices := new int[](capacity)
        result := new int[](9)

        Status = ParseColumnarProductFunctionInfoInto(
            source,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCount,
            funcIndex,
            0,
            functionNameTexts,
            returnTypeTexts,
            paramNameTexts,
            paramTypeTexts,
            paramModifierKinds,
            paramDefaultKinds,
            paramDefaultTexts,
            paramTupleNameCounts,
            paramTupleNameTexts,
            returnTupleNameTexts,
            returnLabeledTypeTexts,
            paramLabeledTypeTexts,
            typeParamTexts,
            typeParamSpecials,
            typeParamConstraintCounts,
            typeParamConstraintTypeTexts,
            nodeKinds,
            valueStarts,
            valueLengths,
            childStart,
            childCount,
            childIndices,
            spanStarts,
            spanLengths,
            localFunctionNodeIndices,
            localFunctionTokenIndices,
            result
        )

        IsNodeCount = 0
        FirstBindingText = ""
        StatementCount = 0
        if Status >= 0 {
            bodyNodeCount := result[7]
            bodyRoot := result[6]
            if bodyRoot >= 0 && bodyRoot < bodyNodeCount && nodeKinds[bodyRoot] == 25 {
                StatementCount = childCount[bodyRoot]
            }

            n := 0
            while n < bodyNodeCount {
                if nodeKinds[n] == 46 {
                    if IsNodeCount == 0 && valueStarts[n] >= 0 {
                        FirstBindingText = source.Substring(valueStarts[n], valueLengths[n])
                    }

                    IsNodeCount = IsNodeCount + 1
                }

                n = n + 1
            }
        }
    }
}

// Parses a whole `func` via the product function ABI and reports every DefaultExpression (kind 74)
// the body emitted, plus the shape of the first one. Same raw-array emit shape as the yield probe so it
// materializes under the stage-0 columnar backend.
class ColumnarFunctionBodyDefaultProbe {
    Status: int
    DefaultNodeCount: int
    FirstDefaultChildCount: int
    FirstDefaultValueStart: int

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
            tokenCounts
        )

        funcIndex := 0
        while funcIndex < tokenCount && tokenKinds[funcIndex] != 7 {
            funcIndex = funcIndex + 1
        }

        functionNameTexts := new string[](1)
        returnTypeTexts := new string[](1)
        paramNameTexts := new string[](capacity)
        paramTypeTexts := new string[](capacity)
        paramModifierKinds := new int[](capacity)
        paramDefaultKinds := new int[](capacity)
        paramDefaultTexts := new string[](capacity)
        paramTupleNameCounts := new int[](capacity)
        paramTupleNameTexts := new string[](capacity)
        returnTupleNameTexts := new string[](capacity)
        returnLabeledTypeTexts := new string[](capacity)
        paramLabeledTypeTexts := new string[](capacity)
        typeParamTexts := new string[](capacity)
        typeParamSpecials := new int[](capacity)
        typeParamConstraintCounts := new int[](capacity)
        typeParamConstraintTypeTexts := new string[](capacity)
        nodeKinds := new int[](capacity)
        valueStarts := new int[](capacity)
        valueLengths := new int[](capacity)
        childStart := new int[](capacity)
        childCount := new int[](capacity)
        childIndices := new int[](capacity)
        spanStarts := new int[](capacity)
        spanLengths := new int[](capacity)
        localFunctionNodeIndices := new int[](capacity)
        localFunctionTokenIndices := new int[](capacity)
        result := new int[](9)

        Status = ParseColumnarProductFunctionInfoInto(
            source,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCount,
            funcIndex,
            0,
            functionNameTexts,
            returnTypeTexts,
            paramNameTexts,
            paramTypeTexts,
            paramModifierKinds,
            paramDefaultKinds,
            paramDefaultTexts,
            paramTupleNameCounts,
            paramTupleNameTexts,
            returnTupleNameTexts,
            returnLabeledTypeTexts,
            paramLabeledTypeTexts,
            typeParamTexts,
            typeParamSpecials,
            typeParamConstraintCounts,
            typeParamConstraintTypeTexts,
            nodeKinds,
            valueStarts,
            valueLengths,
            childStart,
            childCount,
            childIndices,
            spanStarts,
            spanLengths,
            localFunctionNodeIndices,
            localFunctionTokenIndices,
            result
        )

        DefaultNodeCount = 0
        FirstDefaultChildCount = -1
        FirstDefaultValueStart = -2
        if Status >= 0 {
            bodyNodeCount := result[7]
            n := 0
            while n < bodyNodeCount {
                if nodeKinds[n] == ColumnarExpressionNodeKind.DefaultExpression() {
                    if DefaultNodeCount == 0 {
                        FirstDefaultChildCount = childCount[n]
                        FirstDefaultValueStart = valueStarts[n]
                    }

                    DefaultNodeCount = DefaultNodeCount + 1
                }

                n = n + 1
            }
        }
    }
}

// Parses a whole `func` via the product function ABI and captures the shape of the first
// AwaitForeachStatement (kind 73) in the emitted body node table: the loop-variable value-span text,
// the child count, and the child kinds ([collection, body]). Same raw-array emit shape as the yield
// probe so it materializes under the stage-0 columnar backend.
class ColumnarFunctionBodyAwaitForeachProbe {
    Status: int
    AwaitForeachNodeCount: int
    VarText: string
    ChildCount: int
    CollectionKind: int
    BodyKind: int

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
            tokenCounts
        )

        funcIndex := 0
        while funcIndex < tokenCount && tokenKinds[funcIndex] != 7 {
            funcIndex = funcIndex + 1
        }

        functionNameTexts := new string[](1)
        returnTypeTexts := new string[](1)
        paramNameTexts := new string[](capacity)
        paramTypeTexts := new string[](capacity)
        paramModifierKinds := new int[](capacity)
        paramDefaultKinds := new int[](capacity)
        paramDefaultTexts := new string[](capacity)
        paramTupleNameCounts := new int[](capacity)
        paramTupleNameTexts := new string[](capacity)
        returnTupleNameTexts := new string[](capacity)
        returnLabeledTypeTexts := new string[](capacity)
        paramLabeledTypeTexts := new string[](capacity)
        typeParamTexts := new string[](capacity)
        typeParamSpecials := new int[](capacity)
        typeParamConstraintCounts := new int[](capacity)
        typeParamConstraintTypeTexts := new string[](capacity)
        nodeKinds := new int[](capacity)
        valueStarts := new int[](capacity)
        valueLengths := new int[](capacity)
        childStart := new int[](capacity)
        childCount := new int[](capacity)
        childIndices := new int[](capacity)
        spanStarts := new int[](capacity)
        spanLengths := new int[](capacity)
        localFunctionNodeIndices := new int[](capacity)
        localFunctionTokenIndices := new int[](capacity)
        result := new int[](9)

        Status = ParseColumnarProductFunctionInfoInto(
            source,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCount,
            funcIndex,
            0,
            functionNameTexts,
            returnTypeTexts,
            paramNameTexts,
            paramTypeTexts,
            paramModifierKinds,
            paramDefaultKinds,
            paramDefaultTexts,
            paramTupleNameCounts,
            paramTupleNameTexts,
            returnTupleNameTexts,
            returnLabeledTypeTexts,
            paramLabeledTypeTexts,
            typeParamTexts,
            typeParamSpecials,
            typeParamConstraintCounts,
            typeParamConstraintTypeTexts,
            nodeKinds,
            valueStarts,
            valueLengths,
            childStart,
            childCount,
            childIndices,
            spanStarts,
            spanLengths,
            localFunctionNodeIndices,
            localFunctionTokenIndices,
            result
        )

        AwaitForeachNodeCount = 0
        VarText = ""
        ChildCount = -1
        CollectionKind = -1
        BodyKind = -1
        if Status >= 0 {
            bodyNodeCount := result[7]
            n := 0
            while n < bodyNodeCount {
                if nodeKinds[n] == 73 {
                    if AwaitForeachNodeCount == 0 {
                        VarText = source.Substring(valueStarts[n], valueLengths[n])
                        ChildCount = childCount[n]
                        if childCount[n] == 2 {
                            CollectionKind = nodeKinds[childIndices[childStart[n]]]
                            BodyKind = nodeKinds[childIndices[childStart[n] + 1]]
                        }
                    }

                    AwaitForeachNodeCount = AwaitForeachNodeCount + 1
                }

                n = n + 1
            }
        }
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
    assert ColumnarExpressionNodeKind.DefaultExpression() == 74
}

// `default` IS A PRIMARY, AND IT IS THE NULL LITERAL'S TWIN. Both keywords name the target type's zero
// value and neither carries an operand, so both record NO value span and NO children — the whole of the
// node is its kind and the keyword's source span. The type is not the parser's to know: the position the
// expression sits in supplies it, which is why nothing here mentions one.
test "the default keyword parses as a childless primary carrying only its own span" {
    source := "default"
    probe := new ColumnarNumericLiteralParseProbe(source)

    assert probe.NodeCount == 1
    assert probe.ParseResult[0] == 0
    assert probe.ParseResult[1] == 1
    assert probe.NodeKinds[0] == ColumnarExpressionNodeKind.DefaultExpression()
    assert probe.NodeChildCounts[0] == 0
    assert probe.NodeValueStarts[0] == -1
    assert probe.NodeValueLengths[0] == 0
    assert probe.NodeSpanStarts[0] == 0
    assert probe.NodeSpanLengths[0] == source.Length
    assert source.Substring(probe.NodeSpanStarts[0], probe.NodeSpanLengths[0]) == "default"
}

// THE `is` PATTERN VARIABLE. It has nowhere else to go: a kind-46 child run is [value, typeRoot] and
// every scan reads child 0 as a value and child 1 as a TYPE, so the binding is the node's VALUE span —
// the slot `is` otherwise leaves empty and `as` never uses. Without it the kernel stopped the expression
// at the type and left the name to be read as a FRESH STATEMENT, which is how
// `return o is string s && s.Length > 0` silently became a return plus dead code.
test "an is-expression records its pattern variable in the value span" {
    source := "o is string s"
    probe := new ColumnarNumericLiteralParseProbe(source)

    root := probe.ParseResult[0]
    assert probe.NodeKinds[root] == 46
    assert probe.NodeChildCounts[root] == 2
    assert probe.NodeValueStarts[root] == source.Length - 1
    assert probe.NodeValueLengths[root] == 1
    assert source.Substring(probe.NodeValueStarts[root], probe.NodeValueLengths[root]) == "s"
    assert probe.NodeSpanStarts[root] == 0
    assert probe.NodeSpanLengths[root] == source.Length
}

test "an is-expression without a pattern variable leaves the value span empty" {
    source := "o is string"
    probe := new ColumnarNumericLiteralParseProbe(source)

    root := probe.ParseResult[0]
    assert probe.NodeKinds[root] == 46
    assert probe.NodeChildCounts[root] == 2
    assert probe.NodeValueStarts[root] == -1
    assert probe.NodeValueLengths[root] == 0
}

test "an as-expression never claims a following identifier" {
    source := "o as string"
    probe := new ColumnarNumericLiteralParseProbe(source)

    root := probe.ParseResult[0]
    assert probe.NodeKinds[root] == 47
    assert probe.NodeValueStarts[root] == -1
}

test "a pattern variable on the next line stays a new statement" {
    // Statements are newline-terminated, so an identifier opening the next line is not the binding —
    // and the tokenizer has already removed the newline by the time the kernel sees the stream, so the
    // gate has to read the SOURCE between the two spans. Without it `other` became the binding and the
    // `:= 42` that follows it was orphaned.
    probe := new ColumnarFunctionBodyIsPatternProbe(
        "func F(o: object?): bool {\n    flag := o is string\n    other := 42\n    return flag && other > 0\n}"
    )

    assert probe.Status >= 0
    assert probe.IsNodeCount == 1
    assert probe.FirstBindingText == ""
    assert probe.StatementCount == 3
}

test "a pattern variable on the same line is the binding" {
    probe := new ColumnarFunctionBodyIsPatternProbe(
        "func F(o: object?): bool {\n    return o is string text && text.Length > 0\n}"
    )

    assert probe.Status >= 0
    assert probe.IsNodeCount == 1
    assert probe.FirstBindingText == "text"
    assert probe.StatementCount == 1
}

test "a pattern variable binds tighter than the conjunction that reads it" {
    source := "o is string s && s.Length > 0"
    probe := new ColumnarNumericLiteralParseProbe(source)

    root := probe.ParseResult[0]
    assert probe.NodeKinds[root] == ColumnarExpressionNodeKind.BinaryExpression()
    assert probe.NodeChildCounts[root] == 2
    left := probe.NodeChildren[probe.NodeChildStarts[root]]
    assert probe.NodeKinds[left] == 46
    assert source.Substring(probe.NodeValueStarts[left], probe.NodeValueLengths[left]) == "s"
}

test "default composes as an ordinary operand of the expression grammar" {
    source := "Wrap(default, 1)"
    probe := new ColumnarNumericLiteralParseProbe(source)

    assert probe.NodeCount > 0
    defaultNodes := 0
    n := 0
    while n < probe.NodeCount {
        if probe.NodeKinds[n] == ColumnarExpressionNodeKind.DefaultExpression() {
            defaultNodes = defaultNodes + 1
            assert probe.NodeChildCounts[n] == 0
            assert source.Substring(probe.NodeSpanStarts[n], probe.NodeSpanLengths[n]) == "default"
        }

        n = n + 1
    }

    assert defaultNodes == 1
    assert probe.NodeKinds[probe.ParseResult[0]] == ColumnarExpressionNodeKind.CallExpression()
}

test "a function body carrying default parses through the product function ABI" {
    probe := new ColumnarFunctionBodyDefaultProbe("func Zero(): int {\n    return default\n}")

    assert probe.Status >= 0
    assert probe.DefaultNodeCount == 1
    assert probe.FirstDefaultChildCount == 0
    assert probe.FirstDefaultValueStart == -1
}

test "a struct member body carrying default no longer declines the declaration" {
    probe := new ColumnarStructDeclarationParseProbe(
        "class Zeroed<T> {\n    Value: T\n\n    constructor(value: T) {\n        Value = value\n    }\n\n    static func Empty(): Zeroed<T> {\n        return new Zeroed<T>(default)\n    }\n}"
    )

    assert probe.FieldCount == 1
    assert probe.Result[2] == 1
    assert probe.Result[7] == 1
    assert probe.StructNameTexts[0] == "Zeroed"
    assert probe.TypeParamTexts[0] == "T"
}

test "constructor parser preserves dotted enum member defaults" {
    probe := new ColumnarConstructorDefaultParseProbe(
        "constructor(count: int, day: System.DayOfWeek = System . DayOfWeek . Friday) {}"
    )

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
        "class Schedule(count: int, day: System.DayOfWeek = System . DayOfWeek . Friday) {}"
    )

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

test "constructor parser preserves ordered expression spans and the accepted trailing comma in a chain" {
    probe := new ColumnarConstructorDefaultParseProbe(
        "constructor(root: string): this(Build(root, Nested(1, null)), null, new Cache(),) {}"
    )

    assert probe.ParamCount == 1
    assert probe.Result[0] == 1
    assert probe.Result[3] == 3
    assert probe.ArgKinds[1] == 0
    assert probe.ArgTexts[1] == "Build(root, Nested(1, null))"
    assert probe.ArgKinds[2] == 46
    assert probe.ArgTexts[2] == "null"
    assert probe.ArgKinds[3] == 41
    assert probe.ArgTexts[3] == "new Cache()"
}

test "constructor parser rejects a missing expression between chained arguments" {
    probe := new ColumnarConstructorDefaultParseProbe(
        "constructor(root: string): base(root, , null) {}"
    )

    assert probe.ParamCount == -1
}

test "struct parser preserves generic parameters alongside a constructed base" {
    probe := new ColumnarStructDeclarationParseProbe(
        "class Derived<X,Y>: Base<string,Y> {}"
    )

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
        "namespace Scope\nclass Widget {}"
    )

    assert probe.FieldCount == 0
    assert probe.StructNameTexts[0] == "Widget"
}

test "struct parser accepts a method parameter whose nested generic closes with a split >>" {
    // Owed-`>` discipline regression: while a split `>>` close owes a `>`, the type kernel's
    // argument/postfix/union loops must treat the owed `>` as the effective current token. Before
    // the fix, the argument loop read the raw cursor and consumed the PARAMETER comma after
    // `Dictionary<string, Dictionary<string, int>>` as another type argument, so the struct scan
    // declined at parse.struct (real corpus site: AnalyzerDeclarationContext.TryResolveFileImportAliasType).
    probe := new ColumnarStructDeclarationParseProbe(
        "class Holder { func Route(name: string, table: Dictionary<string, Dictionary<string, int>>, out claimed: bool): bool { claimed = true\nreturn true } }"
    )

    assert probe.FieldCount == 0
    assert probe.StructNameTexts[0] == "Holder"
    assert probe.Result[2] == 1
}

test "struct parser binds a '?' after a split >> close to the OUTER generic parameter type" {
    // The postfix half of the same discipline: with a `>` still owed, `Dictionary<string, List<int>>?`
    // must not wrap the INNER List nullable — the suffix belongs to the enclosing type after its
    // close consumes the owed `>`. A desync here mis-scans the signature and declines the scan.
    probe := new ColumnarStructDeclarationParseProbe(
        "class Holder { func Find(map: Dictionary<string, List<int>>?): bool { return map != null } }"
    )

    assert probe.FieldCount == 0
    assert probe.StructNameTexts[0] == "Holder"
    assert probe.Result[2] == 1
}

test "program declaration scanner appends nested lexical owner paths and declaration kinds" {
    probe := new ColumnarNestedStructDeclarationProbe(
        "class Outer { public class Sibling {} class Middle { record struct Value {} class Inner {} } func Run() { value := typeof(string) } }"
    )

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

test "program declaration scanner retains sealed beside visibility for every reference type shape" {
    probe := new ColumnarNestedStructDeclarationProbe(
        "struct PlainValue {}\nsealed record SealedRecord {}\nsealed class Outer<T> { private sealed class Inner<U> {} private sealed record Item {} class PlainNested {} struct NestedValue {} }\nclass PlainClass {}"
    )

    assert probe.ScanStatus >= 0
    assert probe.Count == 8
    // Top-level struct-like declarations are stored by kind: struct, record, then classes.
    assert probe.ReferenceFlags[0] == 0
    assert probe.VisibilityFlags[0] == 0
    assert probe.ReferenceFlags[1] == 1
    assert probe.RecordFlags[1] == 1
    assert probe.VisibilityFlags[1] == 128
    assert probe.ReferenceFlags[2] == 1
    assert probe.RecordFlags[2] == 0
    assert probe.VisibilityFlags[2] == 128
    assert probe.ReferenceFlags[3] == 1
    assert probe.VisibilityFlags[3] == 0

    assert probe.EnclosingTypeNames[4] == "Outer"
    assert probe.ReferenceFlags[4] == 1
    assert probe.RecordFlags[4] == 0
    assert probe.VisibilityFlags[4] == 130
    assert probe.EnclosingTypeNames[5] == "Outer"
    assert probe.ReferenceFlags[5] == 1
    assert probe.RecordFlags[5] == 1
    assert probe.VisibilityFlags[5] == 130
    assert probe.EnclosingTypeNames[6] == "Outer"
    assert probe.ReferenceFlags[6] == 1
    assert probe.VisibilityFlags[6] == 0
    assert probe.EnclosingTypeNames[7] == "Outer"
    assert probe.ReferenceFlags[7] == 0
    assert probe.VisibilityFlags[7] == 0
}

test "program declaration scanner reports its existing failure code for a null visibility column" {
    assert ColumnarProgramDeclarationNullVisibilityStatus("class Plain {}") == -6
}

test "constructor visibility scan crosses an interleaved attribute prefix" {
    probe := new ColumnarStructDeclarationParseProbe(
        "class Secret { private [System.Obsolete] constructor() {} }"
    )

    assert probe.FieldCount == 0
    assert probe.Result[3] == 1
    assert probe.ConstructorVisibilityFlags[0] == 2
}

test "constructor visibility scan retains explicit and synthesized public defaults" {
    explicitPublic := new ColumnarStructDeclarationParseProbe(
        "class PublicOwner { public constructor() {} }"
    )
    assert explicitPublic.FieldCount == 0
    assert explicitPublic.Result[3] == 1
    assert explicitPublic.ConstructorVisibilityFlags[0] == 1

    implicitPublic := new ColumnarStructDeclarationParseProbe(
        "class ImplicitOwner { constructor() {} }"
    )
    assert implicitPublic.FieldCount == 0
    assert implicitPublic.Result[3] == 1
    assert implicitPublic.ConstructorVisibilityFlags[0] == 0

    synthesized := new ColumnarStructDeclarationParseProbe(
        "class SynthesizedOwner { Value: int = 1 }"
    )
    assert synthesized.FieldCount == 1
    assert synthesized.Result[3] == 1
    assert synthesized.ConstructorVisibilityFlags[0] == 0
}

test "declaration scanner parses func* and records the generator fact parallel to async" {
    probe := new ColumnarFunctionGeneratorScanProbe(
        "func Plain(): int { return 1 }\nfunc* Gen(count: int): IEnumerable<int> { yield count }"
    )

    assert probe.ScanStatus >= 0
    assert probe.FuncCount == 2
    assert probe.GeneratorFlags[0] == 0
    assert probe.AsyncFlags[0] == 0
    assert probe.GeneratorFlags[1] == 1
    assert probe.AsyncFlags[1] == 0
}

test "declaration scanner records async and generator facts independently for async func*" {
    probe := new ColumnarFunctionGeneratorScanProbe(
        "async func* Stream(): IAsyncEnumerable<int> { yield 1 }"
    )

    assert probe.ScanStatus >= 0
    assert probe.FuncCount == 1
    assert probe.AsyncFlags[0] == 1
    assert probe.GeneratorFlags[0] == 1
}

test "function body parser lands a value yield as YieldStatement kind 72" {
    probe := new ColumnarFunctionBodyYieldProbe(
        "func* Gen(): IEnumerable<int> { yield 41 }"
    )

    assert probe.Status >= 0
    assert probe.YieldNodeCount == 1
}

test "function body parser lands a yield break as YieldStatement kind 72" {
    probe := new ColumnarFunctionBodyYieldProbe(
        "func* Gen(): IEnumerable<int> { yield break }"
    )

    assert probe.Status >= 0
    assert probe.YieldNodeCount == 1
}

test "function body parser lands await foreach as AwaitForeachStatement kind 73" {
    probe := new ColumnarFunctionBodyAwaitForeachProbe(
        "async func Consume(xs: IAsyncEnumerable<int>) { await foreach n in xs { print n } }"
    )

    assert probe.Status >= 0
    assert probe.AwaitForeachNodeCount == 1
    assert probe.VarText == "n"
    assert probe.ChildCount == 2
    assert probe.CollectionKind == 6
    assert probe.BodyKind == 25
}

test "function body parser lands a call-collection await foreach as kind 73" {
    probe := new ColumnarFunctionBodyAwaitForeachProbe(
        "async func Consume() { await foreach item in GetItemsAsync() { print item } }"
    )

    assert probe.Status >= 0
    assert probe.AwaitForeachNodeCount == 1
    assert probe.VarText == "item"
    assert probe.CollectionKind == 9
    assert probe.BodyKind == 25
}

test "function body parser keeps a bare await statement an expression statement" {
    probe := new ColumnarFunctionBodyAwaitForeachProbe(
        "async func Wait(t: Task) { await t }"
    )

    assert probe.Status >= 0
    assert probe.AwaitForeachNodeCount == 0
}

test "await foreach without the in keyword refuses" {
    probe := new ColumnarFunctionBodyAwaitForeachProbe(
        "async func Consume(xs: IAsyncEnumerable<int>) { await foreach n xs { print n } }"
    )

    assert probe.Status < 0
}

test "parenthesised await foreach stays deferred like foreach" {
    probe := new ColumnarFunctionBodyAwaitForeachProbe(
        "async func Consume(xs: IAsyncEnumerable<int>) { await foreach (n in xs) { print n } }"
    )

    assert probe.Status < 0
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
    WhereOwnerTexts: string[]
    WhereItemCodes: int[]
    WhereTypeTexts: string[]
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
        WhereOwnerTexts = new string[](capacity)
        WhereItemCodes = new int[](capacity)
        WhereTypeTexts = new string[](capacity)
        Result = new int[](8)
        MethodCount = ParseColumnarInterfaceInfoInto(source, tokenKinds, tokenStarts, tokenValueLengths, tokenCount, 0, methodFuncIndices, baseNames, interfaceNames, MethodNames, methodReturns, MethodParamCounts, MethodBodyFlags, MethodParamNames, MethodParamTypes, MethodParamModifierKinds, typeParams, WhereOwnerTexts, WhereItemCodes, WhereTypeTexts, Result)
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

// ---------------------------------------------------------------------------------------------
// TABLE-DRIVEN TEST CASES — the columnar scan, the per-row lowering, and the case label.
// ---------------------------------------------------------------------------------------------

// The COOKED token stream, exactly as ColumnarProgramInputBuilder hands it to these kernels — the
// production caller passes `tokens.Kinds`/`tokens.Count`, not the raw stream.
class ColumnarTestCaseProbe {
    Source: string
    RawKinds: int[]
    RawStarts: int[]
    RawValueLengths: int[]
    RawCount: int
    CaseIndices: int[]
    CaseCount: int

    constructor(source: string) {
        Source = source
        capacity := source.Length * 3 + 16
        rawKinds := new int[](capacity)
        rawStarts := new int[](capacity)
        rawValueLengths := new int[](capacity)
        RawKinds = new int[](capacity)
        RawStarts = new int[](capacity)
        RawValueLengths = new int[](capacity)
        tokenCounts := new int[](2)
        RawCount = TokenizeColumnarSourceInto(source, rawKinds, rawStarts, rawValueLengths, RawKinds, RawStarts, RawValueLengths, tokenCounts)
        CaseIndices = new int[](RawCount + 1)
        scan := new int[](1)
        CaseCount = TopLevelColumnarTestDeclarationIndicesInto(source, RawKinds, RawStarts, RawValueLengths, RawCount, CaseIndices, scan)
    }

    func Tokens(): ParserDeclarationTokenTable {
        return new ParserDeclarationTokenTable(RawKinds, RawStarts, RawValueLengths)
    }

    func UnmodeledShapeExists(): int {
        return TopLevelUnmodeledTestShapeExistsCore(Source, Tokens(), RawCount)
    }

    func HeaderEndsAt(testIndex: int): int {
        return TopLevelTestHeaderEndsAt(Tokens(), RawCount, testIndex)
    }

    func TextAt(tokenIndex: int): string {
        return Source.Substring(RawStarts[tokenIndex], RawValueLengths[tokenIndex])
    }
}

class ColumnarTestCaseBodyProbe {
    NodeKinds: int[]
    NodeValueStarts: int[]
    NodeValueLengths: int[]
    NodeChildStarts: int[]
    NodeChildCounts: int[]
    NodeChildren: int[]
    NodeSpanStarts: int[]
    NodeSpanLengths: int[]
    Result: int[]
    NodeCount: int
    Source: string

    constructor(probe: ColumnarTestCaseProbe, caseSlot: int) {
        Source = probe.Source
        capacity := probe.RawCount + 1
        NodeKinds = new int[](capacity)
        NodeValueStarts = new int[](capacity)
        NodeValueLengths = new int[](capacity)
        NodeChildStarts = new int[](capacity)
        NodeChildCounts = new int[](capacity)
        NodeChildren = new int[](capacity)
        NodeSpanStarts = new int[](capacity)
        NodeSpanLengths = new int[](capacity)
        Result = new int[](6)
        NodeCount = ParseColumnarTestInfoInto(probe.Source, probe.RawKinds, probe.RawStarts, probe.RawValueLengths, probe.RawCount, probe.CaseIndices[caseSlot], NodeKinds, NodeValueStarts, NodeValueLengths, NodeChildStarts, NodeChildCounts, NodeChildren, NodeSpanStarts, NodeSpanLengths, Result)
    }

    func BodyRoot(): int {
        return Result[2]
    }

    func Label(): string {
        return ColumnarTestCaseLabel(Source, Result)
    }

    func ChildAt(node: int, index: int): int {
        return NodeChildren[NodeChildStarts[node] + index]
    }

    func TextOf(node: int): string {
        return Source.Substring(NodeValueStarts[node], NodeValueLengths[node])
    }
}

test "the columnar test scan records one entry per plain test at its keyword" {
    probe := new ColumnarTestCaseProbe("test \"first\" {\n    assert 1 == 1\n}\n\ntest \"second\" {\n    assert 2 == 2\n}\n")

    assert probe.CaseCount == 2
    // `test` is a CONTEXTUAL keyword: the lexer hands it back as an Identifier, and the scan
    // recognises it by text plus the string literal that must follow.
    assert probe.TextAt(probe.CaseIndices[0]) == "test"
    assert probe.TextAt(probe.CaseIndices[1]) == "test"
    assert probe.HeaderEndsAt(probe.CaseIndices[0]) > probe.CaseIndices[0]
    assert probe.UnmodeledShapeExists() == 0
}

test "the columnar test scan records one entry per table ROW at that row's open paren" {
    probe := new ColumnarTestCaseProbe("test \"sums\" with (a: int, b: int) [\n    (1, 2),\n    (3, 4),\n    (5, 6)\n] {\n    assert a < b\n}\n")

    assert probe.CaseCount == 3
    assert probe.RawKinds[probe.CaseIndices[0]] == 127
    assert probe.RawKinds[probe.CaseIndices[1]] == 127
    assert probe.RawKinds[probe.CaseIndices[2]] == 127
    assert probe.CaseIndices[0] < probe.CaseIndices[1]
    assert probe.CaseIndices[1] < probe.CaseIndices[2]
    assert probe.UnmodeledShapeExists() == 0
}

test "a table header ends at the body brace and a skip header is still unmodeled" {
    table := new ColumnarTestCaseProbe("test \"sums\" with (a: int) [\n    (1)\n] {\n    assert a == 1\n}\n")
    assert table.HeaderEndsAt(0) >= 0
    assert table.RawKinds[table.HeaderEndsAt(0)] == 129

    skipped := new ColumnarTestCaseProbe("test \"sums\" skip \"later\" {\n    assert 1 == 1\n}\n")
    assert skipped.HeaderEndsAt(0) == -1
    assert skipped.CaseCount == 0
    assert skipped.UnmodeledShapeExists() == 1
}

test "a table with no rows is refused rather than silently emitting nothing" {
    probe := new ColumnarTestCaseProbe("test \"sums\" with (a: int) [\n] {\n    assert a == 1\n}\n")

    assert probe.HeaderEndsAt(0) == -1
    assert probe.CaseCount == 0
    assert probe.UnmodeledShapeExists() == 1
}

test "a table parameter must be spelled name colon type" {
    good := new ColumnarTestCaseProbe("test \"sums\" with (a: int, values: List<int>) [\n    (1, null)\n] {\n    assert a == 1\n}\n")
    nameStarts := new int[](good.RawCount + 1)
    nameLengths := new int[](good.RawCount + 1)
    typeStarts := new int[](good.RawCount + 1)
    typeLengths := new int[](good.RawCount + 1)
    withIndex := TestTableWithIndexAt(good.Tokens(), good.RawCount, 0)
    assert withIndex > 0
    assert TestTableParameterSpansInto(good.Tokens(), good.RawCount, withIndex, nameStarts, nameLengths, typeStarts, typeLengths) == 2
    assert good.Source.Substring(nameStarts[0], nameLengths[0]) == "a"
    assert good.Source.Substring(typeStarts[0], typeLengths[0]) == "int"
    assert good.Source.Substring(nameStarts[1], nameLengths[1]) == "values"
    assert good.Source.Substring(typeStarts[1], typeLengths[1]) == "List<int>"

    // An UNTYPED parameter is refused by the walk. The header itself still ends at the brace,
    // because the front end reports the far better NL102 ("Parameter 'a' needs a ':' before its
    // type.") long before emit — the kernel's job is only to never lower a shape it cannot bind.
    untyped := new ColumnarTestCaseProbe("test \"sums\" with (a) [\n    (1)\n] {\n    assert a == 1\n}\n")
    untypedWith := TestTableWithIndexAt(untyped.Tokens(), untyped.RawCount, 0)
    assert TestTableParameterSpansInto(untyped.Tokens(), untyped.RawCount, untypedWith, nameStarts, nameLengths, typeStarts, typeLengths) == -1
    untypedCase := new ColumnarTestCaseBodyProbe(untyped, 0)
    assert untypedCase.NodeCount == -1
}

test "a table row lowers into typed locals prepended to the shared body" {
    probe := new ColumnarTestCaseProbe("test \"sums\" with (a: int, b: string) [\n    (7, \"x\"),\n    (9, \"y\")\n] {\n    assert a > 0\n    assert b.Length == 1\n}\n")
    assert probe.CaseCount == 2

    first := new ColumnarTestCaseBodyProbe(probe, 0)
    assert first.NodeCount > 0
    root := first.BodyRoot()
    assert first.NodeKinds[root] == 25
    // The shared body has two statements; the lowered body has those two plus one typed local per
    // table parameter, and the locals come FIRST.
    assert first.NodeChildCounts[root] == 4

    firstLocal := first.ChildAt(root, 0)
    assert first.NodeKinds[firstLocal] == 40
    assert first.NodeChildCounts[firstLocal] == 2
    assert first.TextOf(firstLocal) == "int"
    firstName := first.ChildAt(firstLocal, 0)
    assert first.NodeKinds[firstName] == 6
    assert first.TextOf(firstName) == "a"
    firstValue := first.ChildAt(firstLocal, 1)
    assert first.Source.Substring(first.NodeSpanStarts[firstValue], first.NodeSpanLengths[firstValue]) == "7"

    secondLocal := first.ChildAt(root, 1)
    assert first.NodeKinds[secondLocal] == 40
    assert first.TextOf(secondLocal) == "string"
    secondName := first.ChildAt(secondLocal, 0)
    assert first.TextOf(secondName) == "b"
    secondValue := first.ChildAt(secondLocal, 1)
    assert first.Source.Substring(first.NodeSpanStarts[secondValue], first.NodeSpanLengths[secondValue]) == "\"x\""

    // The SECOND row is an independent body that binds the second row's values.
    second := new ColumnarTestCaseBodyProbe(probe, 1)
    secondRoot := second.BodyRoot()
    assert second.NodeChildCounts[secondRoot] == 4
    secondRowLocal := second.ChildAt(secondRoot, 0)
    secondRowValue := second.ChildAt(secondRowLocal, 1)
    assert second.Source.Substring(second.NodeSpanStarts[secondRowValue], second.NodeSpanLengths[secondRowValue]) == "9"
}

test "a row whose value count does not match the parameter count is declined" {
    probe := new ColumnarTestCaseProbe("test \"sums\" with (a: int, b: int) [\n    (1, 2),\n    (3)\n] {\n    assert a < b\n}\n")
    assert probe.CaseCount == 2

    ok := new ColumnarTestCaseBodyProbe(probe, 0)
    assert ok.NodeCount > 0

    short := new ColumnarTestCaseBodyProbe(probe, 1)
    assert short.NodeCount == -1
}

test "the case label names the plain description or the description plus its row" {
    plain := new ColumnarTestCaseProbe("test \"adds two values\" {\n    assert 1 == 1\n}\n")
    plainCase := new ColumnarTestCaseBodyProbe(plain, 0)
    assert plainCase.Label() == "adds two values"
    assert plainCase.Result[4] == -1

    table := new ColumnarTestCaseProbe("test \"adds\" with (a: int, b: int, sum: int) [\n    (1, 2, 3),\n    (\n        20,\n        30,\n        50\n    )\n] {\n    assert a + b == sum\n}\n")
    firstCase := new ColumnarTestCaseBodyProbe(table, 0)
    assert firstCase.Label() == "adds (1, 2, 3)"

    // A row spread over several lines still labels its case on ONE line, with no space hugging the
    // row's own punctuation.
    secondCase := new ColumnarTestCaseBodyProbe(table, 1)
    assert secondCase.Label() == "adds (20, 30, 50)"
}

// ---- THE MODIFIER-BIT WORDS THIS FILE'S KERNELS WRITE -----------------------------------------
//
// The declaration scan writes two packed flag words — one per field, one per method — and a 0/1
// generator column. Until this slice `ColumnarProgramInputBuilder.cs` unpacked all of them with
// bare integer literals in C# (`& 1`, `& 2`, `& 16`, `& 2048`, `& 131072`, and a private
// `NSharpModifierGenerator = 4096` whose comment said it "must mirror Modifiers.Generator"), even
// though THREE of the accessors below already shipped here and the caller simply did not use them.
//
// `131072` deserves naming: it is `1 << 17`, one bit past `Modifiers.Override` (65536), and it is
// NOT a member of `Modifiers` at all. It exists only as `ColumnarFunctionInput.NativeImportModifierFlag()`,
// which is why every caller must ask rather than remember.

test "the field flag word separates static readonly private and ThreadStatic across its whole domain" {
    // The scan packs four independent booleans, so all sixteen words must decode without equality
    // shortcuts that would silently break when a later bit is present.
    flags := 0
    while flags < 16 {
        assert ColumnarStructFieldFlagIsStatic(flags) == ((flags & 1) != 0)
        assert ColumnarStructFieldFlagIsReadonly(flags) == ((flags & 2) != 0)
        assert ColumnarStructFieldFlagIsPrivate(flags) == ((flags & 4) != 0)
        assert ColumnarStructFieldFlagIsThreadStatic(flags) == ((flags & 8) != 0)
        flags = flags + 1
    }
}

test "the struct parser recognizes only exact qualified no-argument System ThreadStatic spellings" {
    probe := new ColumnarStructDeclarationParseProbe(
        "class Trace {\n" + "[ThreadStatic] private static Short: int\n" + "[ThreadStaticAttribute()] private static UnqualifiedSuffixed: int\n" + "[System.ThreadStatic] private static Qualified: int\n" + "[System.ThreadStaticAttribute()] private static QualifiedSuffixed: int\n" + "[Other.ThreadStatic] private static WrongNamespace: int\n" + "[System.ThreadStatic(1)] private static HasArgument: int\n" + "[Obsolete] private static Unrelated: int\n" + "[System.ThreadStatic] public static PublicField: int\n" + "}"
    )

    assert probe.FieldCount == 8
    assert probe.FieldNameTexts[0] == "Short"
    assert probe.FieldNameTexts[7] == "PublicField"
    assert probe.FieldStaticFlags[0] == 5
    assert probe.FieldStaticFlags[1] == 5
    assert probe.FieldStaticFlags[2] == 13
    assert probe.FieldStaticFlags[3] == 13
    assert probe.FieldStaticFlags[4] == 5
    assert probe.FieldStaticFlags[5] == 5
    assert probe.FieldStaticFlags[6] == 5
    assert probe.FieldStaticFlags[7] == 9
}

test "the method flag word names `static`, `async` and the LibraryImport bit rather than their numbers" {
    assert Convert.ToInt32(Modifiers.Static) == 16
    assert Convert.ToInt32(Modifiers.Async) == 2048
    assert Convert.ToInt32(Modifiers.Generator) == 4096

    assert !ColumnarStructMethodFlagIsStatic(0)
    assert ColumnarStructMethodFlagIsStatic(Convert.ToInt32(Modifiers.Static))
    assert !ColumnarStructMethodFlagIsAsync(Convert.ToInt32(Modifiers.Static))

    assert ColumnarStructMethodFlagIsAsync(Convert.ToInt32(Modifiers.Async))
    assert !ColumnarStructMethodFlagIsStatic(Convert.ToInt32(Modifiers.Async))

    // A static async method answers both, which is what makes these bit tests and not equality.
    both := Convert.ToInt32(Modifiers.Static) + Convert.ToInt32(Modifiers.Async)
    assert ColumnarStructMethodFlagIsStatic(both)
    assert ColumnarStructMethodFlagIsAsync(both)

    // `Modifiers.Override` is 65536 and the LibraryImport bit is the NEXT one up, 131072, which is
    // not a `Modifiers` member at all. Neighbour bits must not answer for it.
    assert ColumnarFunctionInput.NativeImportModifierFlag() == 131072
    assert ColumnarFunctionInput.NativeImportModifierFlag() == Convert.ToInt32(Modifiers.Override) * 2
    assert ColumnarFunctionInput.HasNativeImportModifier(ColumnarFunctionInput.NativeImportModifierFlag())
    assert !ColumnarFunctionInput.HasNativeImportModifier(Convert.ToInt32(Modifiers.Override))
    assert !ColumnarFunctionInput.HasNativeImportModifier(both)
    assert !ColumnarStructMethodFlagIsStatic(ColumnarFunctionInput.NativeImportModifierFlag())
}

test "the generator column becomes the Modifiers.Generator word, and nothing else does" {
    assert ColumnarFunctionModifierFlagsForGenerator(1) == Convert.ToInt32(Modifiers.Generator)
    assert ColumnarFunctionModifierFlagsForGenerator(1) == 4096
    assert ColumnarFunctionModifierFlagsForGenerator(0) == 0

    // The column is 0/1. Anything else is not a generator, and answering 4096 for it would put a
    // modifier on a function the source never marked `func*`.
    assert ColumnarFunctionModifierFlagsForGenerator(-1) == 0
    assert ColumnarFunctionModifierFlagsForGenerator(2) == 0
    assert ColumnarFunctionModifierFlagsForGenerator(4096) == 0
}

test "the method flag word also names `abstract` and `virtual`, and they do not answer for each other" {
    assert Convert.ToInt32(Modifiers.Abstract) == 64
    assert Convert.ToInt32(Modifiers.Virtual) == 32

    assert !ColumnarStructMethodFlagIsAbstract(0)
    assert !ColumnarStructMethodFlagIsVirtual(0)

    assert ColumnarStructMethodFlagIsAbstract(Convert.ToInt32(Modifiers.Abstract))
    assert !ColumnarStructMethodFlagIsVirtual(Convert.ToInt32(Modifiers.Abstract))

    assert ColumnarStructMethodFlagIsVirtual(Convert.ToInt32(Modifiers.Virtual))
    assert !ColumnarStructMethodFlagIsAbstract(Convert.ToInt32(Modifiers.Virtual))

    // `abstract` is the bit BELOW `sealed` (128) and ABOVE `virtual` (32); neither neighbour answers
    // for it, which is the whole reason these are bit tests over a shared word.
    assert !ColumnarStructMethodFlagIsAbstract(Convert.ToInt32(Modifiers.Sealed))
    assert !ColumnarStructMethodFlagIsAbstract(Convert.ToInt32(Modifiers.Override))

    // The columnar input side reads the same word to the same answer, so a member that scanned as
    // abstract is the one the emitter treats as bodyless.
    assert ColumnarFunctionInput.AbstractModifierFlag() == 64
    assert ColumnarFunctionInput.VirtualModifierFlag() == 32
    assert ColumnarFunctionInput.SealedModifierFlag() == 128
    assert ColumnarFunctionInput.HasAbstractModifier(Convert.ToInt32(Modifiers.Abstract))
    assert ColumnarFunctionInput.HasVirtualModifier(Convert.ToInt32(Modifiers.Virtual))
    assert ColumnarFunctionInput.HasSealedModifier(Convert.ToInt32(Modifiers.Sealed))

    // A BODYLESS member is an abstract INSTANCE member. `static abstract` has no slot to be abstract
    // in, so it must not be read as bodyless — it declines elsewhere instead of losing its body here.
    assert ColumnarFunctionInput.IsBodylessAbstractMember(Convert.ToInt32(Modifiers.Abstract), false)
    assert !ColumnarFunctionInput.IsBodylessAbstractMember(Convert.ToInt32(Modifiers.Abstract), true)
    assert !ColumnarFunctionInput.IsBodylessAbstractMember(Convert.ToInt32(Modifiers.Virtual), false)
    assert !ColumnarFunctionInput.IsBodylessAbstractMember(0, false)
}
