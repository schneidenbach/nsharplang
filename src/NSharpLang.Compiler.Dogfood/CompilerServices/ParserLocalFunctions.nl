// Local-function discovery wrapper for product columnar routing. ParseStatementNodesInto already marks a local
// function declaration as statement kind 41 with the `func` keyword's source span; this wrapper maps direct children
// of a function body block to their compact token indices in N#, keeping the adapter out of statement-table scans.

func DirectLocalFunctionTokenIndicesInto(tokenKinds: int[], tokenStarts: int[], tokenCount: int, nodeKinds: int[], nodeValueStarts: int[], nodeChildStart: int[], nodeChildCount: int[], nodeChildIndices: int[], rootBlock: int, outNodeIndices: int[], outFuncTokenIndices: int[]): int {
    if rootBlock < 0 || rootBlock >= nodeKinds.Length {
        return -1
    }

    if nodeKinds[rootBlock] != 25 {
        return 0
    }

    childRun := nodeChildStart[rootBlock]
    childCount := nodeChildCount[rootBlock]
    if childRun < 0 || childCount < 0 {
        return -1
    }

    resultCount := 0
    childIndex := 0
    while childIndex < childCount {
        stmtNode := nodeChildIndices[childRun + childIndex]
        if stmtNode < 0 || stmtNode >= nodeKinds.Length {
            return -1
        }

        if nodeKinds[stmtNode] == 41 {
            if resultCount >= outNodeIndices.Length || resultCount >= outFuncTokenIndices.Length {
                return -1
            }

            funcTokenIndex := TokenIndexByKindStartInto(tokenKinds, tokenStarts, tokenCount, 7, nodeValueStarts[stmtNode])
            if funcTokenIndex < 0 {
                return -1
            }

            outNodeIndices[resultCount] = stmtNode
            outFuncTokenIndices[resultCount] = funcTokenIndex
            resultCount = resultCount + 1
        }

        childIndex = childIndex + 1
    }

    return resultCount
}
