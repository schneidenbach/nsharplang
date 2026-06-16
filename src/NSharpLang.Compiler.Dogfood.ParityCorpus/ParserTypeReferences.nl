// PARITY CORPUS (Arc M1): flattened parser-type-reference ABI extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/ParserTypeReferences.nl. This wrapper exists solely as
// a parity-test surface; production parser routing reaches ParseTypeReferenceNodesCore from signature and
// expression parsing.
// It is NOT part of the shipped dogfood assembly.

func ParseTypeReferenceNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    stack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserNodeTable { Kinds: outNodeKinds, ValueStarts: outNameStarts, ValueLengths: outNameLengths, ChildStart: outChildStart, ChildCount: outChildCount, SpanStarts: outSpanStarts, SpanLengths: outSpanLengths }
    children := new ParserChildIndexTable { Indices: outChildIndices }
    result := new ParserResultTable { Values: outResult }
    return ParseTypeReferenceNodesCore(ref tokens, count, start, ref stack, ref nodes, ref children, ref result)
}

// Flattened canonicalization ABIs retained for parser parity tests only. Product signature,
// constructor, and interface parsing compose the table-shaped cores directly.
func TypeReferenceCanonicalTextInto(source: string, nodeKinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], childIndices: int[], root: int): string {
    nodes := new TypeReferenceCanonicalTable { Kinds: nodeKinds, ValueStarts: valueStarts, ValueLengths: valueLengths, ChildStart: childStart, ChildCount: childCount, ChildIndices: childIndices }
    return TypeReferenceCanonicalTextCore(source, ref nodes, root)
}

func TypeReferenceTupleElementNamesInto(source: string, nodeKinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], childIndices: int[], root: int, outNames: string[]): int {
    nodes := new TypeReferenceCanonicalTable { Kinds: nodeKinds, ValueStarts: valueStarts, ValueLengths: valueLengths, ChildStart: childStart, ChildCount: childCount, ChildIndices: childIndices }
    return TypeReferenceTupleElementNamesCore(source, ref nodes, root, outNames)
}

func ParseTypeReferenceNodesCore(
    tokens: &ParserTokenTable,
    count: int,
    start: int,
    argStack: &ParserArgumentStack,
    nodes: &ParserNodeTable,
    outChildIndices: &ParserChildIndexTable,
    outResult: &ParserResultTable): int {
    st := new ParserState { Pos: start, NodeCursor: 0, ChildCursor: 0, ArgStackTop: 0, SplitGreaterDepth: 0, OwedGreaterByteEnd: 0 }

    root := ParseUnionTypeReferenceNodeCore(ref tokens, count, ref st, ref argStack, ref nodes, ref outChildIndices, 0)
    if root < 0 {
        return -1
    }

    outResult.Values[0] = root
    outResult.Values[1] = st.Pos
    return st.NodeCursor
}
