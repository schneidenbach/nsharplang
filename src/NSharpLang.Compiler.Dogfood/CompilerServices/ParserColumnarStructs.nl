// Product columnar struct/class/record parser wrapper. It keeps declaration span scratch columns inside N# and
// exposes only text, flag, and member-index rows needed by the C# transition materializer.

func ParseColumnarStructInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, structIndex: int, outFieldNameTexts: string[], outFieldTypeTexts: string[], outFieldStaticFlags: int[], outFieldInitKinds: int[], outFieldInitTexts: string[], outMethodFuncIndices: int[], outMethodStaticFlags: int[], outCtorIndices: int[], outPropIndices: int[], outPropStaticFlags: int[], outTypeParamTexts: string[], outBaseNameTexts: string[], outStructNameTexts: string[], outResult: int[]): int {
    cap := count + 1
    fieldNameStarts := new int[](cap)
    fieldNameLengths := new int[](cap)
    fieldTypeStarts := new int[](cap)
    fieldTypeLengths := new int[](cap)
    fieldInitStarts := new int[](cap)
    fieldInitLengths := new int[](cap)
    typeParamStarts := new int[](cap)
    typeParamLengths := new int[](cap)
    baseNameStarts := new int[](cap)
    baseNameLengths := new int[](cap)

    return ParseStructDeclarationInfoInto(
        source, tokenKinds, tokenStarts, tokenValueLengths, count, structIndex,
        fieldNameStarts, fieldNameLengths, outFieldNameTexts,
        fieldTypeStarts, fieldTypeLengths, outFieldTypeTexts,
        outFieldStaticFlags, outFieldInitKinds, fieldInitStarts, fieldInitLengths, outFieldInitTexts,
        outMethodFuncIndices, outMethodStaticFlags, outCtorIndices, outPropIndices, outPropStaticFlags,
        typeParamStarts, typeParamLengths, outTypeParamTexts,
        baseNameStarts, baseNameLengths, outBaseNameTexts,
        outStructNameTexts, outResult)
}
