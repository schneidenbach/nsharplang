import "CompilerServices/ParserDeclarations"

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
    scratch := new ColumnarUnionScratchTable { CaseNameStarts: new int[](count + 1), CaseNameLengths: new int[](count + 1), FieldNameStarts: new int[](count + 1), FieldNameLengths: new int[](count + 1), FieldTypeStarts: new int[](count + 1), FieldTypeLengths: new int[](count + 1), TypeParamStarts: new int[](count + 1), TypeParamLengths: new int[](count + 1) }
    outputs := new ColumnarUnionTextOutputTable { CaseNameTexts: outCaseNameTexts, CaseFieldCounts: outCaseFieldCounts, FieldNameTexts: outFieldNameTexts, FieldTypeTexts: outFieldTypeTexts, TypeParamTexts: outTypeParamTexts, UnionNameTexts: outUnionNameTexts }
    result := new ColumnarUnionResultTable { Values: outResult }
    return ParseColumnarUnionInfoCore(source, ref tokens, unionIndex, ref scratch, ref outputs, ref result)
}

func ParseColumnarUnionInfoCore(source: string, tokens: &ColumnarUnionTokenTable, unionIndex: int, scratch: &ColumnarUnionScratchTable, outputs: &ColumnarUnionTextOutputTable, result: &ColumnarUnionResultTable): int {
    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    decl := new UnionDeclarationTable { CaseNameStarts: scratch.CaseNameStarts, CaseNameLengths: scratch.CaseNameLengths, CaseFieldCounts: outputs.CaseFieldCounts, FieldNameStarts: scratch.FieldNameStarts, FieldNameLengths: scratch.FieldNameLengths, FieldTypeStarts: scratch.FieldTypeStarts, FieldTypeLengths: scratch.FieldTypeLengths, TypeParamStarts: scratch.TypeParamStarts, TypeParamLengths: scratch.TypeParamLengths }
    declarationResult := new ParserDeclarationResultTable { Values: result.Values }
    caseCount := ParseUnionDeclarationCore(ref declarationTokens, tokens.Count, unionIndex, ref decl, ref declarationResult)
    if caseCount < 0 {
        return -1
    }

    typeParamCount := result.Values[2]
    fieldCount := 0
    i := 0
    while i < caseCount {
        fieldCount = fieldCount + outputs.CaseFieldCounts[i]
        i = i + 1
    }

    if outputs.UnionNameTexts.Length < 1 || caseCount > outputs.CaseNameTexts.Length || fieldCount > outputs.FieldNameTexts.Length || fieldCount > outputs.FieldTypeTexts.Length || typeParamCount > outputs.TypeParamTexts.Length {
        return -1
    }
    if ColumnarUnionTypeParameterNamesDistinct(source, ref scratch, typeParamCount) == 0 {
        return -1
    }
    if ColumnarUnionCaseNamesDistinct(source, ref scratch, caseCount) == 0 {
        return -1
    }
    if ColumnarUnionCaseFieldNamesDistinct(source, ref scratch, ref outputs, caseCount) == 0 {
        return -1
    }

    unionName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if unionName == "" {
        return -1
    }
    outputs.UnionNameTexts[0] = unionName

    i = 0
    while i < typeParamCount {
        text := ParserDeclarationSpanText(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i])
        if text == "" {
            return -1
        }

        outputs.TypeParamTexts[i] = text
        i = i + 1
    }

    i = 0
    while i < caseCount {
        text := ParserDeclarationSpanText(source, scratch.CaseNameStarts[i], scratch.CaseNameLengths[i])
        if text == "" {
            return -1
        }

        outputs.CaseNameTexts[i] = text
        i = i + 1
    }

    i = 0
    while i < fieldCount {
        fieldName := ParserDeclarationSpanText(source, scratch.FieldNameStarts[i], scratch.FieldNameLengths[i])
        if fieldName == "" {
            return -1
        }

        fieldType := ParserDeclarationCanonicalTypeText(source, scratch.FieldTypeStarts[i], scratch.FieldTypeLengths[i])
        if fieldType == "" {
            return -1
        }

        outputs.FieldNameTexts[i] = fieldName
        outputs.FieldTypeTexts[i] = fieldType
        i = i + 1
    }

    return caseCount
}

func ColumnarUnionCaseNamesDistinct(source: string, scratch: &ColumnarUnionScratchTable, caseCount: int): int {
    if caseCount < 0 {
        return 0
    }

    i := 0
    while i < caseCount {
        if scratch.CaseNameStarts[i] < 0 || scratch.CaseNameLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < caseCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.CaseNameStarts[i], scratch.CaseNameLengths[i], scratch.CaseNameStarts[j], scratch.CaseNameLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarUnionCaseFieldNamesDistinct(source: string, scratch: &ColumnarUnionScratchTable, outputs: &ColumnarUnionTextOutputTable, caseCount: int): int {
    if caseCount < 0 {
        return 0
    }

    fieldOffset := 0
    c := 0
    while c < caseCount {
        caseFieldCount := outputs.CaseFieldCounts[c]
        if caseFieldCount < 0 {
            return 0
        }

        i := 0
        while i < caseFieldCount {
            leftIndex := fieldOffset + i
            if leftIndex < 0 || leftIndex >= scratch.FieldNameStarts.Length || scratch.FieldNameStarts[leftIndex] < 0 || scratch.FieldNameLengths[leftIndex] <= 0 {
                return 0
            }

            j := i + 1
            while j < caseFieldCount {
                rightIndex := fieldOffset + j
                if rightIndex < 0 || rightIndex >= scratch.FieldNameStarts.Length {
                    return 0
                }

                if ParserDeclarationSourceSpansEqual(source, scratch.FieldNameStarts[leftIndex], scratch.FieldNameLengths[leftIndex], scratch.FieldNameStarts[rightIndex], scratch.FieldNameLengths[rightIndex]) {
                    return 0
                }

                j = j + 1
            }

            i = i + 1
        }

        fieldOffset = fieldOffset + caseFieldCount
        c = c + 1
    }

    return 1
}

// Mirrors UnionValueLayout.IsValueStructEmittable on the columnar union shape. The C# oracle emits a small,
// closed, payload-free, non-generic union as its allocation-free PUBLIC readonly tag struct
// (DeclareValueStructUnion; ILCompiler_PayloadFreeUnion_IsEmittedAsValueStruct pins IsValueType==true). The
// columnar emitter only knows the class-hierarchy layout, so the columnar input builder consults this kernel and
// DECLINES a value-struct-emittable union to the oracle rather than silently swap the public value-struct ABI for
// heap case classes (the documented Stage-6 caveat in performance-compiler-refactor.md). Eligibility holds when the
// union is non-generic, has 1..MaxValueStructCases (16) cases, and every case is payload-free (caseFieldCounts[c]
// is case c's field count; a non-zero count means the case carries a payload). Returns 1 when eligible, else 0.
func ColumnarUnionIsValueStructEmittable(caseFieldCounts: int[], caseCount: int, typeParamCount: int): int {
    if typeParamCount != 0 {
        return 0
    }

    if caseCount < 1 || caseCount > 16 {
        return 0
    }

    if caseCount > caseFieldCounts.Length {
        return 0
    }

    i := 0
    while i < caseCount {
        if caseFieldCounts[i] != 0 {
            return 0
        }

        i = i + 1
    }

    return 1
}

func ColumnarUnionTypeParameterNamesDistinct(source: string, scratch: &ColumnarUnionScratchTable, typeParamCount: int): int {
    if typeParamCount < 0 {
        return 0
    }

    i := 0
    while i < typeParamCount {
        if scratch.TypeParamStarts[i] < 0 || scratch.TypeParamLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < typeParamCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i], scratch.TypeParamStarts[j], scratch.TypeParamLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}
