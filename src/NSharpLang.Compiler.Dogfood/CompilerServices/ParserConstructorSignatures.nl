// Composed constructor-signature product wrapper. ParserDeclarations.nl keeps the standalone constructor chain
// parser; this file owns the cross-file route that combines constructor parameter signatures, canonical type text,
// chaining initializer text, and body-brace validation for the columnar product adapter.

func ParseConstructorSignatureInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outParamNameTexts: string[], outParamTypeTexts: string[], outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outArgTexts: string[], outResult: int[]): int {
    if outResult.Length < 4 {
        return -1
    }

    cap := count + 1
    nodeKinds := new int[](cap)
    nameStarts := new int[](cap)
    nameLengths := new int[](cap)
    childStart := new int[](cap)
    childCount := new int[](cap)
    childIndices := new int[](cap)
    spanStarts := new int[](cap)
    spanLengths := new int[](cap)
    paramNameStarts := new int[](cap)
    paramNameLengths := new int[](cap)
    paramTypeRoots := new int[](cap)
    typeParamStarts := new int[](cap)
    typeParamLengths := new int[](cap)
    whereNameStarts := new int[](cap)
    whereNameLengths := new int[](cap)
    whereItemCodes := new int[](cap)
    signatureResult := new int[](8)
    paramCount := ParseFunctionSignatureInto(
        tokenKinds, tokenStarts, tokenValueLengths, count, ctorIndex,
        nodeKinds, nameStarts, nameLengths, childStart, childCount, childIndices, spanStarts, spanLengths,
        paramNameStarts, paramNameLengths, paramTypeRoots, typeParamStarts, typeParamLengths,
        whereNameStarts, whereNameLengths, whereItemCodes, signatureResult)
    if paramCount < 0 || signatureResult[1] >= 0 || signatureResult[5] != 0 || signatureResult[7] != 0 {
        return -1
    }

    if paramCount > outParamNameTexts.Length || paramCount > outParamTypeTexts.Length {
        return -1
    }

    paramIndex := 0
    while paramIndex < paramCount {
        paramName := FunctionSignatureSpanText(source, paramNameStarts[paramIndex], paramNameLengths[paramIndex])
        if paramName == "" {
            return -1
        }

        outParamNameTexts[paramIndex] = paramName
        outParamTypeTexts[paramIndex] = TypeReferenceCanonicalTextInto(source, nodeKinds, nameStarts, nameLengths, childStart, childCount, childIndices, paramTypeRoots[paramIndex])
        paramIndex = paramIndex + 1
    }

    chainArgCount := ParseConstructorTextInfoInto(source, tokenKinds, tokenStarts, tokenValueLengths, count, ctorIndex, outArgKinds, outArgStarts, outArgLengths, outArgTexts, outResult)
    if chainArgCount < 0 {
        return -1
    }

    bodyBrace := outResult[1]
    if bodyBrace < 0 || bodyBrace >= count || tokenKinds[bodyBrace] != 129 {
        return -1
    }

    outResult[2] = paramCount
    outResult[3] = chainArgCount
    return paramCount
}
