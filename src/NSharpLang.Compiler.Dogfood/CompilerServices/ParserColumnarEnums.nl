// Product columnar enum parser wrapper. It keeps span/value-literal scratch columns inside N# and exposes only
// the enum/member text plus resolved int values needed by the C# transition materializer.

func ParseColumnarEnumInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameTexts: string[], outMemberValues: int[], outEnumNameTexts: string[], outResult: int[]): int {
    cap := count + 1
    nameStarts := new int[](cap)
    nameLengths := new int[](cap)
    valueStarts := new int[](cap)
    valueLengths := new int[](cap)
    hasValue := new int[](cap)

    return ParseEnumDeclarationTextInfoInto(
        source, tokenKinds, tokenStarts, tokenValueLengths, count, enumIndex,
        nameStarts, nameLengths, outNameTexts, valueStarts, valueLengths,
        hasValue, outMemberValues, outEnumNameTexts, outResult)
}
