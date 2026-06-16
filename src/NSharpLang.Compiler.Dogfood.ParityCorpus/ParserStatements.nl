// Flattened statement parser ABI retained for parser parity tests only. Product function,
// constructor, and property body parsing compose ParseStatementNodesCore directly.

func ParseStatementNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    argStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserExpressionNodeTable { Kinds: outNodeKinds, ValueStarts: outValueStarts, ValueLengths: outValueLengths, ChildStart: outChildStart, ChildCount: outChildCount, SpanStarts: outSpanStarts, SpanLengths: outSpanLengths }
    children := new ParserChildIndexTable { Indices: outChildIndices }
    result := new ParserResultTable { Values: outResult }
    return ParseStatementNodesCore(ref tokens, count, start, ref argStack, ref nodes, ref children, ref result)
}
