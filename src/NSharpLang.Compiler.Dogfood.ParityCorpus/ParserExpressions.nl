// PARITY CORPUS (Arc M1): flattened parser-expression ABI extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/ParserExpressions.nl. This wrapper exists solely as
// a parity-test surface; production parser routing reaches ParseExpressionNodesCore through statement parsing.
// It is NOT part of the shipped dogfood assembly.

func ParseExpressionNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    argStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserExpressionNodeTable { Kinds: outNodeKinds, ValueStarts: outValueStarts, ValueLengths: outValueLengths, ChildStart: outChildStart, ChildCount: outChildCount, SpanStarts: outSpanStarts, SpanLengths: outSpanLengths }
    children := new ParserChildIndexTable { Indices: outChildIndices }
    result := new ParserResultTable { Values: outResult }
    return ParseExpressionNodesCore(ref tokens, count, start, ref argStack, ref nodes, ref children, ref result)
}

func ParseExpressionNodesCore(tokens: &ParserTokenTable, count: int, start: int, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, outResult: &ParserResultTable): int {
    st := new ParserState { Pos: start, NodeCursor: 0, ChildCursor: 0, ArgStackTop: 0, SplitGreaterDepth: 0, OwedGreaterByteEnd: 0 }

    root := ParseLambdaOrAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
    if root < 0 {
        return -1
    }

    outResult.Values[0] = root
    outResult.Values[1] = st.Pos
    return st.NodeCursor
}
