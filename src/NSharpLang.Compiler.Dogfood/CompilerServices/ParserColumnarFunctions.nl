// Product columnar function parser wrapper. It composes the signature rowset, statement-node rowset, and
// direct local-function discovery so the C# adapter only materializes ColumnarFunctionInput containers.

func ParseColumnarFunctionInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, outFunctionNameTexts: string[], outReturnTypeTexts: string[], outParamNameTexts: string[], outParamTypeTexts: string[], outParamTupleNameCounts: int[], outParamTupleNameTexts: string[], outReturnTupleNameTexts: string[], outTypeParamTexts: string[], outTypeParamSpecials: int[], outTypeParamConstraintCounts: int[], outTypeParamConstraintTypeTexts: string[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outLocalFunctionNodeIndices: int[], outLocalFunctionTokenIndices: int[], outResult: int[]): int {
    if outResult.Length < 9 {
        return -1
    }

    signatureResult := new int[](6)
    paramCount := ParseFunctionSignatureInfoInto(
        source, tokenKinds, tokenStarts, tokenValueLengths, count, funcIndex,
        outFunctionNameTexts, outReturnTypeTexts, outParamNameTexts, outParamTypeTexts,
        outParamTupleNameCounts, outParamTupleNameTexts, outReturnTupleNameTexts,
        outTypeParamTexts, outTypeParamSpecials, outTypeParamConstraintCounts,
        outTypeParamConstraintTypeTexts, signatureResult)
    if paramCount < 0 {
        return -1
    }

    bodyBrace := signatureResult[1]
    if bodyBrace < 0 || bodyBrace >= count || tokenKinds[bodyBrace] != 129 {
        return -1
    }

    bodyResult := new int[](2)
    bodyNodeCount := ParseStatementNodesInto(
        tokenKinds, tokenStarts, tokenValueLengths, count, bodyBrace,
        outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount,
        outChildIndices, outSpanStarts, outSpanLengths, bodyResult)
    if bodyNodeCount <= 0 {
        return -1
    }

    bodyRoot := bodyResult[0]
    if bodyRoot < 0 || bodyRoot >= bodyNodeCount {
        return -1
    }

    localFunctionCount := DirectLocalFunctionTokenIndicesInto(
        tokenKinds, tokenStarts, count,
        outNodeKinds, outValueStarts, outChildStart, outChildCount, outChildIndices,
        bodyRoot, outLocalFunctionNodeIndices, outLocalFunctionTokenIndices)
    if localFunctionCount < 0 {
        return -1
    }

    outResult[0] = signatureResult[0]
    outResult[1] = bodyBrace
    outResult[2] = signatureResult[2]
    outResult[3] = signatureResult[3]
    outResult[4] = signatureResult[4]
    outResult[5] = signatureResult[5]
    outResult[6] = bodyRoot
    outResult[7] = bodyNodeCount
    outResult[8] = localFunctionCount
    return paramCount
}
