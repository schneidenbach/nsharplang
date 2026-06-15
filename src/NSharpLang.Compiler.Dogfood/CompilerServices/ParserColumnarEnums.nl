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
    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    members := new EnumMemberTable { NameStarts: scratch.NameStarts, NameLengths: scratch.NameLengths, ValueStarts: scratch.ValueStarts, ValueLengths: scratch.ValueLengths, HasValue: scratch.HasValue }
    declarationResult := new ParserDeclarationResultTable { Values: result.Values }
    memberCount := ParseEnumDeclarationCore(ref declarationTokens, tokens.Count, enumIndex, ref members, ref declarationResult)
    if memberCount < 0 {
        return -1
    }

    if !ParseEnumMemberValuesInto(source, ref members, memberCount, outputs.MemberValues) {
        return -1
    }

    if outputs.EnumNameTexts.Length < 1 || memberCount > outputs.MemberNameTexts.Length {
        return -1
    }

    enumName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if enumName == "" {
        return -1
    }
    outputs.EnumNameTexts[0] = enumName

    i := 0
    while i < memberCount {
        memberName := ParserDeclarationSpanText(source, scratch.NameStarts[i], scratch.NameLengths[i])
        if memberName == "" {
            return -1
        }

        outputs.MemberNameTexts[i] = memberName
        i = i + 1
    }

    return memberCount
}
