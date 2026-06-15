// Product columnar struct/class/record parser wrapper. It keeps declaration span scratch columns inside N# and
// exposes only text, flag, and member-index rows needed by the C# transition materializer.

struct ColumnarStructTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
}

struct ColumnarStructScratchTable {
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    FieldInitStarts: int[]
    FieldInitLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    BaseNameStarts: int[]
    BaseNameLengths: int[]
}

struct ColumnarStructOutputTable {
    FieldNameTexts: string[]
    FieldTypeTexts: string[]
    FieldStaticFlags: int[]
    FieldInitKinds: int[]
    FieldInitTexts: string[]
    MethodFuncIndices: int[]
    MethodStaticFlags: int[]
    CtorIndices: int[]
    PropIndices: int[]
    PropStaticFlags: int[]
    TypeParamTexts: string[]
    BaseNameTexts: string[]
    StructNameTexts: string[]
}

struct ColumnarStructResultTable {
    Values: int[]
}

func ParseColumnarStructInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, structIndex: int, outFieldNameTexts: string[], outFieldTypeTexts: string[], outFieldStaticFlags: int[], outFieldInitKinds: int[], outFieldInitTexts: string[], outMethodFuncIndices: int[], outMethodStaticFlags: int[], outCtorIndices: int[], outPropIndices: int[], outPropStaticFlags: int[], outTypeParamTexts: string[], outBaseNameTexts: string[], outStructNameTexts: string[], outResult: int[]): int {
    tokens := new ColumnarStructTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    cap := count + 1
    scratch := new ColumnarStructScratchTable { FieldNameStarts: new int[](cap), FieldNameLengths: new int[](cap), FieldTypeStarts: new int[](cap), FieldTypeLengths: new int[](cap), FieldInitStarts: new int[](cap), FieldInitLengths: new int[](cap), TypeParamStarts: new int[](cap), TypeParamLengths: new int[](cap), BaseNameStarts: new int[](cap), BaseNameLengths: new int[](cap) }
    outputs := new ColumnarStructOutputTable { FieldNameTexts: outFieldNameTexts, FieldTypeTexts: outFieldTypeTexts, FieldStaticFlags: outFieldStaticFlags, FieldInitKinds: outFieldInitKinds, FieldInitTexts: outFieldInitTexts, MethodFuncIndices: outMethodFuncIndices, MethodStaticFlags: outMethodStaticFlags, CtorIndices: outCtorIndices, PropIndices: outPropIndices, PropStaticFlags: outPropStaticFlags, TypeParamTexts: outTypeParamTexts, BaseNameTexts: outBaseNameTexts, StructNameTexts: outStructNameTexts }
    result := new ColumnarStructResultTable { Values: outResult }
    return ParseColumnarStructInfoCore(source, ref tokens, structIndex, ref scratch, ref outputs, ref result)
}

func ParseColumnarStructInfoCore(source: string, tokens: &ColumnarStructTokenTable, structIndex: int, scratch: &ColumnarStructScratchTable, outputs: &ColumnarStructOutputTable, result: &ColumnarStructResultTable): int {
    return ParseStructDeclarationInfoInto(
        source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count, structIndex,
        scratch.FieldNameStarts, scratch.FieldNameLengths, outputs.FieldNameTexts,
        scratch.FieldTypeStarts, scratch.FieldTypeLengths, outputs.FieldTypeTexts,
        outputs.FieldStaticFlags, outputs.FieldInitKinds,
        scratch.FieldInitStarts, scratch.FieldInitLengths, outputs.FieldInitTexts,
        outputs.MethodFuncIndices, outputs.MethodStaticFlags,
        outputs.CtorIndices, outputs.PropIndices, outputs.PropStaticFlags,
        scratch.TypeParamStarts, scratch.TypeParamLengths, outputs.TypeParamTexts,
        scratch.BaseNameStarts, scratch.BaseNameLengths, outputs.BaseNameTexts,
        outputs.StructNameTexts, result.Values)
}
