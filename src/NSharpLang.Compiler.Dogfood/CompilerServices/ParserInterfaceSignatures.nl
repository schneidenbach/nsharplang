// Composed interface-signature product wrapper. ParserDeclarations.nl stays a standalone declaration parser; this
// file owns the cross-file routing that combines interface member indices, function-signature parsing, and canonical
// type text for the columnar product adapter.

func ParseInterfaceDeclarationSignatureInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameStarts: int[], outBaseNameLengths: int[], outBaseNameTexts: string[], outInterfaceNameTexts: string[], outMethodNameTexts: string[], outMethodReturnTexts: string[], outMethodParamCounts: int[], outMethodBodyFlags: int[], outMethodParamNameTexts: string[], outMethodParamTypeTexts: string[], outResult: int[]): int {
    if outResult.Length < 4 {
        return -1
    }

    methodCount := ParseInterfaceDeclarationInfoInto(source, tokenKinds, tokenStarts, tokenValueLengths, count, interfaceIndex, outMethodFuncIndices, outBaseNameStarts, outBaseNameLengths, outBaseNameTexts, outInterfaceNameTexts, outResult)
    if methodCount < 0 {
        return -1
    }

    if methodCount > outMethodNameTexts.Length || methodCount > outMethodReturnTexts.Length || methodCount > outMethodParamCounts.Length || methodCount > outMethodBodyFlags.Length {
        return -1
    }

    cap := count + 1
    flatParamCount := 0
    methodIndex := 0
    while methodIndex < methodCount {
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
            tokenKinds, tokenStarts, tokenValueLengths, count, outMethodFuncIndices[methodIndex],
            nodeKinds, nameStarts, nameLengths, childStart, childCount, childIndices, spanStarts, spanLengths,
            paramNameStarts, paramNameLengths, paramTypeRoots, typeParamStarts, typeParamLengths,
            whereNameStarts, whereNameLengths, whereItemCodes, signatureResult)
        if paramCount < 0 || signatureResult[3] < 0 {
            return -1
        }

        if signatureResult[5] > 0 || signatureResult[7] > 0 {
            return -1
        }

        afterSignature := signatureResult[6]
        if afterSignature < 0 || afterSignature >= count {
            return -1
        }

        methodName := FunctionSignatureSpanText(source, signatureResult[3], signatureResult[4])
        if methodName == "" {
            return -1
        }
        outMethodNameTexts[methodIndex] = methodName

        returnRoot := signatureResult[1]
        if returnRoot >= 0 {
            if ParseInterfaceSignatureHasTupleNames(nodeKinds, childStart, childCount, childIndices, returnRoot) != 0 {
                return -1
            }

            outMethodReturnTexts[methodIndex] = TypeReferenceCanonicalTextInto(source, nodeKinds, nameStarts, nameLengths, childStart, childCount, childIndices, returnRoot)
        } else {
            outMethodReturnTexts[methodIndex] = "void"
        }

        if flatParamCount + paramCount > outMethodParamNameTexts.Length || flatParamCount + paramCount > outMethodParamTypeTexts.Length {
            return -1
        }

        paramIndex := 0
        while paramIndex < paramCount {
            paramName := FunctionSignatureSpanText(source, paramNameStarts[paramIndex], paramNameLengths[paramIndex])
            if paramName == "" {
                return -1
            }

            paramRoot := paramTypeRoots[paramIndex]
            if ParseInterfaceSignatureHasTupleNames(nodeKinds, childStart, childCount, childIndices, paramRoot) != 0 {
                return -1
            }

            flatSlot := flatParamCount + paramIndex
            outMethodParamNameTexts[flatSlot] = paramName
            outMethodParamTypeTexts[flatSlot] = TypeReferenceCanonicalTextInto(source, nodeKinds, nameStarts, nameLengths, childStart, childCount, childIndices, paramRoot)
            paramIndex = paramIndex + 1
        }

        outMethodParamCounts[methodIndex] = paramCount
        flatParamCount = flatParamCount + paramCount

        if tokenKinds[afterSignature] == 129 {
            outMethodBodyFlags[methodIndex] = 1
        } else if tokenKinds[afterSignature] == 7 || tokenKinds[afterSignature] == 130 {
            outMethodBodyFlags[methodIndex] = 0
        } else {
            return -1
        }

        methodIndex = methodIndex + 1
    }

    outResult[3] = flatParamCount
    return methodCount
}

func ParseInterfaceSignatureHasTupleNames(nodeKinds: int[], childStart: int[], childCount: int[], childIndices: int[], root: int): int {
    if root < 0 || root >= nodeKinds.Length || nodeKinds[root] != 6 || childCount[root] == 0 {
        return 0
    }

    run := childStart[root]
    first := childIndices[run]
    if nodeKinds[first] != 7 {
        return 0
    }

    i := 0
    while i < childCount[root] {
        elem := childIndices[run + i]
        if nodeKinds[elem] != 7 {
            return -1
        }

        i = i + 1
    }

    return 1
}
