import "CompilerServices/ParserDeclarations"

// Local-function discovery core for product columnar routing. ParseStatementNodesCore already marks a local
// function declaration as statement kind 41 with the `func` keyword's source span; this core maps direct children
// of a function body block to their compact token indices in N#, keeping the adapter out of statement-table scans.
// The flattened DirectLocalFunctionTokenIndicesInto ABI lives in the parity corpus.

struct LocalFunctionTokenTable {
    Kinds: int[]
    Starts: int[]
    Count: int
}

struct LocalFunctionNodeTable {
    Kinds: int[]
    ValueStarts: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
}

struct LocalFunctionResultTable {
    NodeIndices: int[]
    FuncTokenIndices: int[]
}

func DirectLocalFunctionTokenIndicesCore(tokens: &LocalFunctionTokenTable, nodes: &LocalFunctionNodeTable, rootBlock: int, results: &LocalFunctionResultTable): int {
    if rootBlock < 0 || rootBlock >= nodes.Kinds.Length {
        return -1
    }

    if nodes.Kinds[rootBlock] != 25 {
        return 0
    }

    childRun := nodes.ChildStart[rootBlock]
    childCount := nodes.ChildCount[rootBlock]
    if childRun < 0 || childCount < 0 {
        return -1
    }

    resultCount := 0
    childIndex := 0
    declarationTokens := new ParserDeclarationStartKindStream { Kinds: tokens.Kinds, Starts: tokens.Starts }
    while childIndex < childCount {
        stmtNode := nodes.ChildIndices[childRun + childIndex]
        if stmtNode < 0 || stmtNode >= nodes.Kinds.Length {
            return -1
        }

        if nodes.Kinds[stmtNode] == 41 {
            if resultCount >= results.NodeIndices.Length || resultCount >= results.FuncTokenIndices.Length {
                return -1
            }

            funcTokenIndex := TokenIndexByKindStartCore(ref declarationTokens, tokens.Count, 7, nodes.ValueStarts[stmtNode])
            if funcTokenIndex < 0 {
                return -1
            }

            results.NodeIndices[resultCount] = stmtNode
            results.FuncTokenIndices[resultCount] = funcTokenIndex
            resultCount = resultCount + 1
        }

        childIndex = childIndex + 1
    }

    return resultCount
}
