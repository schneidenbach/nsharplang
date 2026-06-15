// Product columnar interface parser wrapper. It keeps base-name span scratch columns inside N# and exposes only
// the interface/base text plus method signature rows needed by the C# transition materializer.

struct ColumnarInterfaceTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
}

struct ColumnarInterfaceBaseScratchTable {
    BaseNameStarts: int[]
    BaseNameLengths: int[]
}

struct ColumnarInterfaceOutputTable {
    MethodFuncIndices: int[]
    BaseNameTexts: string[]
    InterfaceNameTexts: string[]
    MethodNameTexts: string[]
    MethodReturnTexts: string[]
    MethodParamCounts: int[]
    MethodBodyFlags: int[]
    MethodParamNameTexts: string[]
    MethodParamTypeTexts: string[]
}

struct ColumnarInterfaceResultTable {
    Values: int[]
}

func ParseColumnarInterfaceInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameTexts: string[], outInterfaceNameTexts: string[], outMethodNameTexts: string[], outMethodReturnTexts: string[], outMethodParamCounts: int[], outMethodBodyFlags: int[], outMethodParamNameTexts: string[], outMethodParamTypeTexts: string[], outResult: int[]): int {
    tokens := new ColumnarInterfaceTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    scratch := new ColumnarInterfaceBaseScratchTable { BaseNameStarts: new int[](count + 1), BaseNameLengths: new int[](count + 1) }
    outputs := new ColumnarInterfaceOutputTable { MethodFuncIndices: outMethodFuncIndices, BaseNameTexts: outBaseNameTexts, InterfaceNameTexts: outInterfaceNameTexts, MethodNameTexts: outMethodNameTexts, MethodReturnTexts: outMethodReturnTexts, MethodParamCounts: outMethodParamCounts, MethodBodyFlags: outMethodBodyFlags, MethodParamNameTexts: outMethodParamNameTexts, MethodParamTypeTexts: outMethodParamTypeTexts }
    result := new ColumnarInterfaceResultTable { Values: outResult }
    return ParseColumnarInterfaceInfoCore(source, ref tokens, interfaceIndex, ref scratch, ref outputs, ref result)
}

func ParseColumnarInterfaceInfoCore(source: string, tokens: &ColumnarInterfaceTokenTable, interfaceIndex: int, scratch: &ColumnarInterfaceBaseScratchTable, outputs: &ColumnarInterfaceOutputTable, result: &ColumnarInterfaceResultTable): int {
    return ParseInterfaceDeclarationSignatureInfoInto(
        source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count, interfaceIndex,
        outputs.MethodFuncIndices, scratch.BaseNameStarts, scratch.BaseNameLengths,
        outputs.BaseNameTexts, outputs.InterfaceNameTexts,
        outputs.MethodNameTexts, outputs.MethodReturnTexts, outputs.MethodParamCounts,
        outputs.MethodBodyFlags, outputs.MethodParamNameTexts, outputs.MethodParamTypeTexts,
        result.Values)
}
