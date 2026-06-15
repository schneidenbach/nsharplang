// Product columnar union parser wrapper. It keeps declaration span scratch columns inside N# and exposes only
// the text/count rows needed by the C# transition materializer.

struct ColumnarUnionTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
}

struct ColumnarUnionScratchTable {
    CaseNameStarts: int[]
    CaseNameLengths: int[]
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
}

struct ColumnarUnionTextOutputTable {
    CaseNameTexts: string[]
    CaseFieldCounts: int[]
    FieldNameTexts: string[]
    FieldTypeTexts: string[]
    TypeParamTexts: string[]
    UnionNameTexts: string[]
}

struct ColumnarUnionResultTable {
    Values: int[]
}

func ParseColumnarUnionInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, unionIndex: int, outCaseNameTexts: string[], outCaseFieldCounts: int[], outFieldNameTexts: string[], outFieldTypeTexts: string[], outTypeParamTexts: string[], outUnionNameTexts: string[], outResult: int[]): int {
    tokens := new ColumnarUnionTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    cap := count + 1
    scratch := new ColumnarUnionScratchTable { CaseNameStarts: new int[](cap), CaseNameLengths: new int[](cap), FieldNameStarts: new int[](cap), FieldNameLengths: new int[](cap), FieldTypeStarts: new int[](cap), FieldTypeLengths: new int[](cap), TypeParamStarts: new int[](cap), TypeParamLengths: new int[](cap) }
    outputs := new ColumnarUnionTextOutputTable { CaseNameTexts: outCaseNameTexts, CaseFieldCounts: outCaseFieldCounts, FieldNameTexts: outFieldNameTexts, FieldTypeTexts: outFieldTypeTexts, TypeParamTexts: outTypeParamTexts, UnionNameTexts: outUnionNameTexts }
    result := new ColumnarUnionResultTable { Values: outResult }
    return ParseColumnarUnionInfoCore(source, ref tokens, unionIndex, ref scratch, ref outputs, ref result)
}

func ParseColumnarUnionInfoCore(source: string, tokens: &ColumnarUnionTokenTable, unionIndex: int, scratch: &ColumnarUnionScratchTable, outputs: &ColumnarUnionTextOutputTable, result: &ColumnarUnionResultTable): int {
    return ParseUnionDeclarationInfoInto(
        source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count, unionIndex,
        scratch.CaseNameStarts, scratch.CaseNameLengths, outputs.CaseNameTexts, outputs.CaseFieldCounts,
        scratch.FieldNameStarts, scratch.FieldNameLengths, outputs.FieldNameTexts,
        scratch.FieldTypeStarts, scratch.FieldTypeLengths, outputs.FieldTypeTexts,
        scratch.TypeParamStarts, scratch.TypeParamLengths, outputs.TypeParamTexts,
        outputs.UnionNameTexts, result.Values)
}
