// Product columnar property parser wrapper. It composes property accessor/type parsing with getter/setter
// statement-node rowsets so the C# adapter no longer binds statement parsing for property bodies.

func ParseColumnarPropertyInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, propIndex: int, outNameTexts: string[], outTypeTexts: string[], outGetNodeKinds: int[], outGetValueStarts: int[], outGetValueLengths: int[], outGetChildStart: int[], outGetChildCount: int[], outGetChildIndices: int[], outGetSpanStarts: int[], outGetSpanLengths: int[], outSetNodeKinds: int[], outSetValueStarts: int[], outSetValueLengths: int[], outSetChildStart: int[], outSetChildCount: int[], outSetChildIndices: int[], outSetSpanStarts: int[], outSetSpanLengths: int[], outResult: int[]): int {
    if outResult.Length < 10 {
        return -1
    }

    propertyResult := new int[](6)
    accessorKind := ParsePropertyAccessorTypeInfoInto(
        source, tokenKinds, tokenStarts, tokenValueLengths, count, propIndex,
        outNameTexts, outTypeTexts, propertyResult)
    if accessorKind < 0 {
        return -1
    }

    getBodyBrace := propertyResult[4]
    if getBodyBrace < 0 || getBodyBrace >= count || tokenKinds[getBodyBrace] != 129 {
        return -1
    }

    getBodyResult := new int[](2)
    getBodyNodeCount := ParseStatementNodesInto(
        tokenKinds, tokenStarts, tokenValueLengths, count, getBodyBrace,
        outGetNodeKinds, outGetValueStarts, outGetValueLengths, outGetChildStart, outGetChildCount,
        outGetChildIndices, outGetSpanStarts, outGetSpanLengths, getBodyResult)
    if getBodyNodeCount <= 0 {
        return -1
    }

    getBodyRoot := getBodyResult[0]
    if getBodyRoot < 0 || getBodyRoot >= getBodyNodeCount {
        return -1
    }

    setBodyRoot := -1
    setBodyNodeCount := 0
    if accessorKind == 1 {
        setBodyBrace := propertyResult[5]
        if setBodyBrace < 0 || setBodyBrace >= count || tokenKinds[setBodyBrace] != 129 {
            return -1
        }

        setBodyResult := new int[](2)
        setBodyNodeCount = ParseStatementNodesInto(
            tokenKinds, tokenStarts, tokenValueLengths, count, setBodyBrace,
            outSetNodeKinds, outSetValueStarts, outSetValueLengths, outSetChildStart, outSetChildCount,
            outSetChildIndices, outSetSpanStarts, outSetSpanLengths, setBodyResult)
        if setBodyNodeCount <= 0 {
            return -1
        }

        setBodyRoot = setBodyResult[0]
        if setBodyRoot < 0 || setBodyRoot >= setBodyNodeCount {
            return -1
        }
    } else if accessorKind != 0 {
        return -1
    }

    outResult[0] = propertyResult[0]
    outResult[1] = propertyResult[1]
    outResult[2] = propertyResult[2]
    outResult[3] = propertyResult[3]
    outResult[4] = getBodyBrace
    outResult[5] = propertyResult[5]
    outResult[6] = getBodyRoot
    outResult[7] = getBodyNodeCount
    outResult[8] = setBodyRoot
    outResult[9] = setBodyNodeCount
    return accessorKind
}
