// Product columnar constructor parser wrapper. It composes constructor signature/chain parsing with the
// statement-node rowset so the C# adapter no longer orchestrates constructor body parsing.

func ParseColumnarConstructorInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outParamNameTexts: string[], outParamTypeTexts: string[], outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outArgTexts: string[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    if outResult.Length < 6 {
        return -1
    }

    signatureResult := new int[](4)
    paramCount := ParseConstructorSignatureInfoInto(
        source, tokenKinds, tokenStarts, tokenValueLengths, count, ctorIndex,
        outParamNameTexts, outParamTypeTexts,
        outArgKinds, outArgStarts, outArgLengths, outArgTexts, signatureResult)
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

    outResult[0] = signatureResult[0]
    outResult[1] = bodyBrace
    outResult[2] = signatureResult[2]
    outResult[3] = signatureResult[3]
    outResult[4] = bodyRoot
    outResult[5] = bodyNodeCount
    return paramCount
}
