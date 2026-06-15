// Product columnar interface parser wrapper. It keeps base-name span scratch columns inside N# and exposes only
// the interface/base text plus method signature rows needed by the C# transition materializer.

func ParseColumnarInterfaceInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameTexts: string[], outInterfaceNameTexts: string[], outMethodNameTexts: string[], outMethodReturnTexts: string[], outMethodParamCounts: int[], outMethodBodyFlags: int[], outMethodParamNameTexts: string[], outMethodParamTypeTexts: string[], outResult: int[]): int {
    cap := count + 1
    baseNameStarts := new int[](cap)
    baseNameLengths := new int[](cap)

    return ParseInterfaceDeclarationSignatureInfoInto(
        source, tokenKinds, tokenStarts, tokenValueLengths, count, interfaceIndex,
        outMethodFuncIndices, baseNameStarts, baseNameLengths, outBaseNameTexts, outInterfaceNameTexts,
        outMethodNameTexts, outMethodReturnTexts, outMethodParamCounts, outMethodBodyFlags,
        outMethodParamNameTexts, outMethodParamTypeTexts, outResult)
}
