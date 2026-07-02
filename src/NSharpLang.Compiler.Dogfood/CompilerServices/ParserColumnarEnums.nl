import "CompilerServices/ParserDeclarations"

// Product columnar enum parser wrapper. It keeps span/value-literal scratch columns inside N# and exposes only
// the enum/member text plus resolved int values needed by the columnar input builder.

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
    MemberStringValues: string[]
    EnumNameTexts: string[]
}

struct ColumnarEnumResultTable {
    Values: int[]
}

func ParseColumnarEnumInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameTexts: string[], outMemberValues: int[], outMemberStringValues: string[], outEnumNameTexts: string[], outResult: int[]): int {
    tokens := new ColumnarEnumTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    scratch := new ColumnarEnumMemberScratchTable { NameStarts: new int[](count + 1), NameLengths: new int[](count + 1), ValueStarts: new int[](count + 1), ValueLengths: new int[](count + 1), HasValue: new int[](count + 1) }
    outputs := new ColumnarEnumTextOutputTable { MemberNameTexts: outNameTexts, MemberValues: outMemberValues, MemberStringValues: outMemberStringValues, EnumNameTexts: outEnumNameTexts }
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

    if ColumnarEnumMemberNamesDistinct(source, ref scratch, memberCount) == 0 {
        return -1
    }

    backingKind := ColumnarEnumBackingKind(source, ref tokens, enumIndex, ref scratch, memberCount)
    if backingKind < 0 {
        return -1
    }

    if result.Values.Length > 2 {
        result.Values[2] = backingKind
    }

    if backingKind == 0 {
        memberValues := new EnumMemberValueTable { Values: outputs.MemberValues }
        if !ParseEnumMemberValuesCore(source, ref members, memberCount, ref memberValues) {
            return -1
        }
    } else if !ColumnarEnumStringMemberValues(source, ref scratch, memberCount, ref outputs) {
        return -1
    }

    if outputs.EnumNameTexts.Length < 1 || memberCount > outputs.MemberNameTexts.Length {
        return -1
    }

    enumName := ParserDeclarationQualifiedNameText(source, ref declarationTokens, tokens.Count, enumIndex, result.Values[0], result.Values[1])
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

func ColumnarEnumBackingKind(source: string, tokens: &ColumnarEnumTokenTable, enumIndex: int, scratch: &ColumnarEnumMemberScratchTable, memberCount: int): int {
    explicitKind := -1
    pos := enumIndex + 2
    if pos < tokens.Count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        if pos >= tokens.Count || tokens.Kinds[pos] != 0 {
            return -1
        }

        if ParserDeclarationTokenTextEquals(source, tokens.Starts[pos], tokens.ValueLengths[pos], "string") {
            explicitKind = 1
        } else if ParserDeclarationTokenTextEquals(source, tokens.Starts[pos], tokens.ValueLengths[pos], "int") {
            explicitKind = 0
        } else {
            return -1
        }
    }

    backingKind := 0
    if explicitKind == 1 {
        backingKind = 1
    }

    sawIntValue := 0
    i := 0
    while i < memberCount {
        if scratch.HasValue[i] != 0 {
            valueKind := ColumnarEnumValueTokenKind(ref tokens, scratch.ValueStarts[i])
            if valueKind == 4 {
                if explicitKind == 0 || sawIntValue != 0 {
                    return -1
                }
                backingKind = 1
            } else if valueKind == 1 {
                if explicitKind == 1 || backingKind == 1 {
                    return -1
                }
                sawIntValue = 1
            } else {
                return -1
            }
        }

        i = i + 1
    }

    return backingKind
}

func ColumnarEnumValueTokenKind(tokens: &ColumnarEnumTokenTable, valueStart: int): int {
    i := 0
    while i < tokens.Count {
        if tokens.Starts[i] == valueStart {
            return tokens.Kinds[i]
        }

        i = i + 1
    }

    return -1
}

func ColumnarEnumStringMemberValues(source: string, scratch: &ColumnarEnumMemberScratchTable, memberCount: int, outputs: &ColumnarEnumTextOutputTable): bool {
    if memberCount < 0 || memberCount > outputs.MemberStringValues.Length {
        return false
    }

    i := 0
    while i < memberCount {
        valueText := ""
        if scratch.HasValue[i] != 0 {
            valueText = ParserDeclarationSpanText(source, scratch.ValueStarts[i], scratch.ValueLengths[i])
        } else {
            valueText = ParserDeclarationSpanText(source, scratch.NameStarts[i], scratch.NameLengths[i])
        }

        if valueText == "" {
            return false
        }

        outputs.MemberStringValues[i] = valueText
        i = i + 1
    }

    return true
}

func ColumnarEnumMemberNamesDistinct(source: string, scratch: &ColumnarEnumMemberScratchTable, memberCount: int): int {
    if memberCount < 0 {
        return 0
    }

    i := 0
    while i < memberCount {
        if scratch.NameStarts[i] < 0 || scratch.NameLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < memberCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.NameStarts[i], scratch.NameLengths[i], scratch.NameStarts[j], scratch.NameLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}
