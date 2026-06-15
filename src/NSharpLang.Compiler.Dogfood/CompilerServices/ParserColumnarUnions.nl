// Product columnar union parser wrapper. It keeps declaration span scratch columns inside N# and exposes only
// the text/count rows needed by the C# transition materializer.

func ParseColumnarUnionInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, unionIndex: int, outCaseNameTexts: string[], outCaseFieldCounts: int[], outFieldNameTexts: string[], outFieldTypeTexts: string[], outTypeParamTexts: string[], outUnionNameTexts: string[], outResult: int[]): int {
    cap := count + 1
    caseNameStarts := new int[](cap)
    caseNameLengths := new int[](cap)
    fieldNameStarts := new int[](cap)
    fieldNameLengths := new int[](cap)
    fieldTypeStarts := new int[](cap)
    fieldTypeLengths := new int[](cap)
    typeParamStarts := new int[](cap)
    typeParamLengths := new int[](cap)

    return ParseUnionDeclarationInfoInto(
        source, tokenKinds, tokenStarts, tokenValueLengths, count, unionIndex,
        caseNameStarts, caseNameLengths, outCaseNameTexts, outCaseFieldCounts,
        fieldNameStarts, fieldNameLengths, outFieldNameTexts,
        fieldTypeStarts, fieldTypeLengths, outFieldTypeTexts,
        typeParamStarts, typeParamLengths, outTypeParamTexts,
        outUnionNameTexts, outResult)
}
