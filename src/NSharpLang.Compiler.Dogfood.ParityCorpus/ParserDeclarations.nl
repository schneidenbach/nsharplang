// Flattened declaration parser ABIs retained for parity tests only. Product columnar parsing
// composes the typed declaration cores directly through ParserColumnarStructs.nl and
// ParserColumnarUnions.nl.

func ParseStructDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, structIndex: int, outFieldNameStarts: int[], outFieldNameLengths: int[], outFieldTypeStarts: int[], outFieldTypeLengths: int[], outFieldStaticFlags: int[], outFieldInitKinds: int[], outFieldInitStarts: int[], outFieldInitLengths: int[], outMethodFuncIndices: int[], outMethodStaticFlags: int[], outCtorIndices: int[], outPropIndices: int[], outPropStaticFlags: int[], outTypeParamStarts: int[], outTypeParamLengths: int[], outBaseNameStarts: int[], outBaseNameLengths: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decl := new StructDeclarationTable { FieldNameStarts: outFieldNameStarts, FieldNameLengths: outFieldNameLengths, FieldTypeStarts: outFieldTypeStarts, FieldTypeLengths: outFieldTypeLengths, FieldStaticFlags: outFieldStaticFlags, FieldInitKinds: outFieldInitKinds, FieldInitStarts: outFieldInitStarts, FieldInitLengths: outFieldInitLengths, MethodFuncIndices: outMethodFuncIndices, MethodStaticFlags: outMethodStaticFlags, CtorIndices: outCtorIndices, PropIndices: outPropIndices, PropStaticFlags: outPropStaticFlags, TypeParamStarts: outTypeParamStarts, TypeParamLengths: outTypeParamLengths, BaseNameStarts: outBaseNameStarts, BaseNameLengths: outBaseNameLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseStructDeclarationCore(ref tokens, count, structIndex, ref decl, ref result)
}

func ParseStructDeclarationInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, structIndex: int, outFieldNameStarts: int[], outFieldNameLengths: int[], outFieldNameTexts: string[], outFieldTypeStarts: int[], outFieldTypeLengths: int[], outFieldTypeTexts: string[], outFieldStaticFlags: int[], outFieldInitKinds: int[], outFieldInitStarts: int[], outFieldInitLengths: int[], outFieldInitTexts: string[], outMethodFuncIndices: int[], outMethodStaticFlags: int[], outCtorIndices: int[], outPropIndices: int[], outPropStaticFlags: int[], outTypeParamStarts: int[], outTypeParamLengths: int[], outTypeParamTexts: string[], outBaseNameStarts: int[], outBaseNameLengths: int[], outBaseNameTexts: string[], outStructNameTexts: string[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decl := new StructDeclarationTable { FieldNameStarts: outFieldNameStarts, FieldNameLengths: outFieldNameLengths, FieldTypeStarts: outFieldTypeStarts, FieldTypeLengths: outFieldTypeLengths, FieldStaticFlags: outFieldStaticFlags, FieldInitKinds: outFieldInitKinds, FieldInitStarts: outFieldInitStarts, FieldInitLengths: outFieldInitLengths, MethodFuncIndices: outMethodFuncIndices, MethodStaticFlags: outMethodStaticFlags, CtorIndices: outCtorIndices, PropIndices: outPropIndices, PropStaticFlags: outPropStaticFlags, TypeParamStarts: outTypeParamStarts, TypeParamLengths: outTypeParamLengths, BaseNameStarts: outBaseNameStarts, BaseNameLengths: outBaseNameLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    fieldCount := ParseStructDeclarationCore(ref tokens, count, structIndex, ref decl, ref result)
    typeParamCount := result.Values[7]
    baseNameCount := result.Values[8]
    if fieldCount < 0 || outStructNameTexts.Length < 1 || fieldCount > outFieldNameTexts.Length || fieldCount > outFieldTypeTexts.Length || fieldCount > outFieldInitTexts.Length || typeParamCount > outTypeParamTexts.Length || baseNameCount > outBaseNameTexts.Length {
        return -1
    }

    structName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if structName == "" {
        return -1
    }
    outStructNameTexts[0] = structName

    i := 0
    while i < typeParamCount {
        typeParamName := ParserDeclarationSpanText(source, decl.TypeParamStarts[i], decl.TypeParamLengths[i])
        if typeParamName == "" {
            return -1
        }

        outTypeParamTexts[i] = typeParamName
        i = i + 1
    }

    i = 0
    while i < baseNameCount {
        baseName := ParserDeclarationSpanText(source, decl.BaseNameStarts[i], decl.BaseNameLengths[i])
        if baseName == "" {
            return -1
        }

        outBaseNameTexts[i] = baseName
        i = i + 1
    }

    i = 0
    while i < fieldCount {
        fieldName := ParserDeclarationSpanText(source, decl.FieldNameStarts[i], decl.FieldNameLengths[i])
        if fieldName == "" {
            return -1
        }

        text := ParserDeclarationCanonicalTypeText(source, decl.FieldTypeStarts[i], decl.FieldTypeLengths[i])
        if text.Length == 0 {
            return -1
        }

        outFieldNameTexts[i] = fieldName
        outFieldTypeTexts[i] = text
        if decl.FieldInitKinds[i] >= 0 {
            initText := source.Substring(decl.FieldInitStarts[i], decl.FieldInitLengths[i])
            if initText.Length == 0 {
                return -1
            }

            outFieldInitTexts[i] = initText
        }

        i = i + 1
    }

    return fieldCount
}

func ParseUnionDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, unionIndex: int, outCaseNameStarts: int[], outCaseNameLengths: int[], outCaseFieldCounts: int[], outFieldNameStarts: int[], outFieldNameLengths: int[], outFieldTypeStarts: int[], outFieldTypeLengths: int[], outTypeParamStarts: int[], outTypeParamLengths: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decl := new UnionDeclarationTable { CaseNameStarts: outCaseNameStarts, CaseNameLengths: outCaseNameLengths, CaseFieldCounts: outCaseFieldCounts, FieldNameStarts: outFieldNameStarts, FieldNameLengths: outFieldNameLengths, FieldTypeStarts: outFieldTypeStarts, FieldTypeLengths: outFieldTypeLengths, TypeParamStarts: outTypeParamStarts, TypeParamLengths: outTypeParamLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseUnionDeclarationCore(ref tokens, count, unionIndex, ref decl, ref result)
}

func ParseUnionDeclarationInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, unionIndex: int, outCaseNameStarts: int[], outCaseNameLengths: int[], outCaseNameTexts: string[], outCaseFieldCounts: int[], outFieldNameStarts: int[], outFieldNameLengths: int[], outFieldNameTexts: string[], outFieldTypeStarts: int[], outFieldTypeLengths: int[], outFieldTypeTexts: string[], outTypeParamStarts: int[], outTypeParamLengths: int[], outTypeParamTexts: string[], outUnionNameTexts: string[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decl := new UnionDeclarationTable { CaseNameStarts: outCaseNameStarts, CaseNameLengths: outCaseNameLengths, CaseFieldCounts: outCaseFieldCounts, FieldNameStarts: outFieldNameStarts, FieldNameLengths: outFieldNameLengths, FieldTypeStarts: outFieldTypeStarts, FieldTypeLengths: outFieldTypeLengths, TypeParamStarts: outTypeParamStarts, TypeParamLengths: outTypeParamLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    caseCount := ParseUnionDeclarationCore(ref tokens, count, unionIndex, ref decl, ref result)
    if caseCount < 0 {
        return -1
    }

    typeParamCount := result.Values[2]
    fieldCount := 0
    i := 0
    while i < caseCount {
        fieldCount = fieldCount + decl.CaseFieldCounts[i]
        i = i + 1
    }

    if outUnionNameTexts.Length < 1 || caseCount > outCaseNameTexts.Length || fieldCount > outFieldNameTexts.Length || fieldCount > outFieldTypeTexts.Length || typeParamCount > outTypeParamTexts.Length {
        return -1
    }

    unionName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if unionName == "" {
        return -1
    }
    outUnionNameTexts[0] = unionName

    i = 0
    while i < typeParamCount {
        text := ParserDeclarationSpanText(source, decl.TypeParamStarts[i], decl.TypeParamLengths[i])
        if text == "" {
            return -1
        }

        outTypeParamTexts[i] = text
        i = i + 1
    }

    i = 0
    while i < caseCount {
        text := ParserDeclarationSpanText(source, decl.CaseNameStarts[i], decl.CaseNameLengths[i])
        if text == "" {
            return -1
        }

        outCaseNameTexts[i] = text
        i = i + 1
    }

    i = 0
    while i < fieldCount {
        fieldName := ParserDeclarationSpanText(source, decl.FieldNameStarts[i], decl.FieldNameLengths[i])
        if fieldName == "" {
            return -1
        }

        fieldType := ParserDeclarationCanonicalTypeText(source, decl.FieldTypeStarts[i], decl.FieldTypeLengths[i])
        if fieldType == "" {
            return -1
        }

        outFieldNameTexts[i] = fieldName
        outFieldTypeTexts[i] = fieldType
        i = i + 1
    }

    return caseCount
}
