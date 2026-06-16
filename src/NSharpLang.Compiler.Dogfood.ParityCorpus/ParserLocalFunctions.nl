// Flattened local-function discovery ABI retained for parser parity tests only. Product function
// parsing composes DirectLocalFunctionTokenIndicesCore directly through ParserColumnarFunctions.nl.

func DirectLocalFunctionTokenIndicesInto(tokenKinds: int[], tokenStarts: int[], tokenCount: int, nodeKinds: int[], nodeValueStarts: int[], nodeChildStart: int[], nodeChildCount: int[], nodeChildIndices: int[], rootBlock: int, outNodeIndices: int[], outFuncTokenIndices: int[]): int {
    tokens := new LocalFunctionTokenTable { Kinds: tokenKinds, Starts: tokenStarts, Count: tokenCount }
    nodes := new LocalFunctionNodeTable { Kinds: nodeKinds, ValueStarts: nodeValueStarts, ChildStart: nodeChildStart, ChildCount: nodeChildCount, ChildIndices: nodeChildIndices }
    results := new LocalFunctionResultTable { NodeIndices: outNodeIndices, FuncTokenIndices: outFuncTokenIndices }
    return DirectLocalFunctionTokenIndicesCore(ref tokens, ref nodes, rootBlock, ref results)
}
