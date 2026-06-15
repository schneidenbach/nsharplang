// Product columnar enum parser wrapper. It keeps span/value-literal scratch columns inside N# and exposes only
// the enum/member text plus resolved int values needed by the C# transition materializer.

struct ColumnarEnumTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
}

struct ColumnarEnumMemberScratchTable {
    NameStarts: int[]
    NameLengths: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    HasValue: int[]
}

struct ColumnarEnumTextOutputTable {
    MemberNameTexts: string[]
    MemberValues: int[]
    EnumNameTexts: string[]
}

struct ColumnarEnumResultTable {
    Values: int[]
}

func ParseColumnarEnumInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameTexts: string[], outMemberValues: int[], outEnumNameTexts: string[], outResult: int[]): int {
    tokens := new ColumnarEnumTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    scratch := new ColumnarEnumMemberScratchTable { NameStarts: new int[](count + 1), NameLengths: new int[](count + 1), ValueStarts: new int[](count + 1), ValueLengths: new int[](count + 1), HasValue: new int[](count + 1) }
    outputs := new ColumnarEnumTextOutputTable { MemberNameTexts: outNameTexts, MemberValues: outMemberValues, EnumNameTexts: outEnumNameTexts }
    result := new ColumnarEnumResultTable { Values: outResult }
    return ParseColumnarEnumInfoCore(source, ref tokens, enumIndex, ref scratch, ref outputs, ref result)
}

func ParseColumnarEnumInfoCore(source: string, tokens: &ColumnarEnumTokenTable, enumIndex: int, scratch: &ColumnarEnumMemberScratchTable, outputs: &ColumnarEnumTextOutputTable, result: &ColumnarEnumResultTable): int {
    return ParseEnumDeclarationTextInfoInto(
        source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count, enumIndex,
        scratch.NameStarts, scratch.NameLengths, outputs.MemberNameTexts,
        scratch.ValueStarts, scratch.ValueLengths, scratch.HasValue,
        outputs.MemberValues, outputs.EnumNameTexts, result.Values)
}
