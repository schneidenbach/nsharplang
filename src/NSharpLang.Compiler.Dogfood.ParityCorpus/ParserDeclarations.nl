// Flattened declaration parser ABIs retained for parity tests only. Product columnar parsing
// composes the typed declaration cores directly through ParserColumnarStructs.nl and
// ParserColumnarUnions.nl, ParserColumnarEnums.nl, and ParserInterfaceSignatures.nl.

func PackageNameSpanInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return PackageNameSpanCore(ref tokens, count, ref result)
}

func NamespaceImportSpansInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outNsStarts: int[], outNsLengths: int[], outAliasStarts: int[], outAliasLengths: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    imports := new NamespaceImportTable { NsStarts: outNsStarts, NsLengths: outNsLengths, AliasStarts: outAliasStarts, AliasLengths: outAliasLengths }
    return NamespaceImportSpansCore(ref tokens, count, ref imports)
}

func TopLevelDeclarationKindsInto(tokenKinds: int[], count: int, outKinds: int[]): int {
    tokens := new ParserDeclarationKindStream { Kinds: tokenKinds }
    decls := new TopLevelDeclarationKindTable { Kinds: outKinds }
    return TopLevelDeclarationKindsCore(ref tokens, count, ref decls)
}

func TopLevelDeclarationModifiersInto(tokenKinds: int[], count: int, outKinds: int[], outModifiers: int[]): int {
    tokens := new ParserDeclarationKindStream { Kinds: tokenKinds }
    decls := new TopLevelDeclarationModifierTable { Kinds: outKinds, Modifiers: outModifiers }
    return TopLevelDeclarationModifiersCore(ref tokens, count, ref decls)
}

func TopLevelDeclarationNameSpansInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outKinds: int[], outNameStarts: int[], outNameLengths: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decls := new TopLevelDeclarationNameTable { Kinds: outKinds, Indices: new int[](count + 1), NameStarts: outNameStarts, NameLengths: outNameLengths }
    return TopLevelDeclarationNameSpansCore(ref tokens, count, ref decls)
}

func TopLevelDeclarationIndicesInto(tokenKinds: int[], count: int, targetKind: int, suppressWhereClause: int, outIndices: int[]): int {
    tokens := new ParserDeclarationKindStream { Kinds: tokenKinds }
    indices := new TopLevelDeclarationIndexTable { Indices: outIndices }
    return TopLevelDeclarationIndicesCore(ref tokens, count, targetKind, suppressWhereClause, ref indices)
}

func TopLevelStructLikeDeclarationIndicesInto(tokenKinds: int[], count: int, outIndices: int[], outReferenceFlags: int[], outRecordFlags: int[]): int {
    tokens := new ParserDeclarationKindStream { Kinds: tokenKinds }
    output := new TopLevelStructLikeDeclarationTable { Indices: outIndices, ReferenceFlags: outReferenceFlags, RecordFlags: outRecordFlags }
    return TopLevelStructLikeDeclarationIndicesCore(ref tokens, count, ref output)
}

func TopLevelColumnarNominalDeclarationIndicesInto(tokenKinds: int[], count: int, outEnumIndices: int[], outUnionIndices: int[], outInterfaceIndices: int[], outResult: int[]): int {
    tokens := new ParserDeclarationKindStream { Kinds: tokenKinds }
    outputs := new TopLevelColumnarNominalDeclarationTable { EnumIndices: outEnumIndices, UnionIndices: outUnionIndices, InterfaceIndices: outInterfaceIndices }
    result := new ParserDeclarationResultTable { Values: outResult }
    return TopLevelColumnarNominalDeclarationIndicesCore(ref tokens, count, ref outputs, ref result)
}

func TopLevelColumnarFunctionDeclarationIndicesInto(source: string, rawTokenKinds: int[], rawTokenStarts: int[], rawTokenValueLengths: int[], rawCount: int, compactTokenKinds: int[], compactCount: int, outFuncIndices: int[], outAsyncFlags: int[], outResult: int[]): int {
    rawTokens := new ParserDeclarationTokenTable { Kinds: rawTokenKinds, Starts: rawTokenStarts, ValueLengths: rawTokenValueLengths }
    compactTokens := new ParserDeclarationKindStream { Kinds: compactTokenKinds }
    outputs := new TopLevelColumnarFunctionDeclarationTable { Indices: outFuncIndices, AsyncFlags: outAsyncFlags }
    result := new ParserDeclarationResultTable { Values: outResult }
    return TopLevelColumnarFunctionDeclarationIndicesCore(source, ref rawTokens, rawCount, ref compactTokens, compactCount, ref outputs, ref result)
}

func TopLevelFunctionPreamblesAreValidInto(tokenKinds: int[], count: int, funcIndices: int[], funcCount: int): int {
    tokens := new ParserDeclarationKindStream { Kinds: tokenKinds }
    indices := new TopLevelDeclarationIndexTable { Indices: funcIndices }
    return TopLevelFunctionPreamblesAreValidCore(ref tokens, count, ref indices, funcCount)
}

func TopLevelContextualTestDeclarationExistsInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    return TopLevelContextualTestDeclarationExistsCore(source, ref tokens, count)
}

func MatchingCloseBraceInto(tokenKinds: int[], count: int, open: int): int {
    tokens := new ParserDeclarationKindStream { Kinds: tokenKinds }
    return MatchingCloseBraceCore(ref tokens, count, open)
}

func TokenIndexByKindStartInto(tokenKinds: int[], tokenStarts: int[], count: int, targetKind: int, targetStart: int): int {
    if count < 0 {
        return -1
    }

    if count > tokenKinds.Length {
        return -1
    }

    if count > tokenStarts.Length {
        return -1
    }

    tokens := new ParserDeclarationStartKindStream { Kinds: tokenKinds, Starts: tokenStarts }
    return TokenIndexByKindStartCore(ref tokens, count, targetKind, targetStart)
}

func ParseInterfaceDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameStarts: int[], outBaseNameLengths: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decl := new InterfaceDeclarationTable { MethodFuncIndices: outMethodFuncIndices, BaseNameStarts: outBaseNameStarts, BaseNameLengths: outBaseNameLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseInterfaceDeclarationCore(ref tokens, count, interfaceIndex, ref decl, ref result)
}

func ParseInterfaceDeclarationInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameStarts: int[], outBaseNameLengths: int[], outBaseNameTexts: string[], outInterfaceNameTexts: string[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decl := new InterfaceDeclarationTable { MethodFuncIndices: outMethodFuncIndices, BaseNameStarts: outBaseNameStarts, BaseNameLengths: outBaseNameLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    methodCount := ParseInterfaceDeclarationCore(ref tokens, count, interfaceIndex, ref decl, ref result)
    if methodCount < 0 {
        return -1
    }

    baseCount := result.Values[2]
    if outInterfaceNameTexts.Length < 1 || baseCount > outBaseNameTexts.Length {
        return -1
    }

    interfaceName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if interfaceName == "" {
        return -1
    }
    outInterfaceNameTexts[0] = interfaceName

    i := 0
    while i < baseCount {
        baseName := ParserDeclarationSpanText(source, decl.BaseNameStarts[i], decl.BaseNameLengths[i])
        if baseName == "" {
            return -1
        }

        outBaseNameTexts[i] = baseName
        i = i + 1
    }

    return methodCount
}

func ParseEnumDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameStarts: int[], outNameLengths: int[], outValueStarts: int[], outValueLengths: int[], outHasValue: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    members := new EnumMemberTable { NameStarts: outNameStarts, NameLengths: outNameLengths, ValueStarts: outValueStarts, ValueLengths: outValueLengths, HasValue: outHasValue }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseEnumDeclarationCore(ref tokens, count, enumIndex, ref members, ref result)
}

func ParseEnumDeclarationInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameStarts: int[], outNameLengths: int[], outValueStarts: int[], outValueLengths: int[], outHasValue: int[], outMemberValues: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    members := new EnumMemberTable { NameStarts: outNameStarts, NameLengths: outNameLengths, ValueStarts: outValueStarts, ValueLengths: outValueLengths, HasValue: outHasValue }
    result := new ParserDeclarationResultTable { Values: outResult }
    memberCount := ParseEnumDeclarationCore(ref tokens, count, enumIndex, ref members, ref result)
    if memberCount < 0 {
        return -1
    }

    memberValues := new EnumMemberValueTable { Values: outMemberValues }
    if !ParseEnumMemberValuesCore(source, ref members, memberCount, ref memberValues) {
        return -1
    }

    return memberCount
}

func ParseEnumDeclarationTextInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameStarts: int[], outNameLengths: int[], outNameTexts: string[], outValueStarts: int[], outValueLengths: int[], outHasValue: int[], outMemberValues: int[], outEnumNameTexts: string[], outResult: int[]): int {
    memberCount := ParseEnumDeclarationInfoInto(source, tokenKinds, tokenStarts, tokenValueLengths, count, enumIndex, outNameStarts, outNameLengths, outValueStarts, outValueLengths, outHasValue, outMemberValues, outResult)
    if memberCount < 0 {
        return -1
    }

    if outEnumNameTexts.Length < 1 || memberCount > outNameTexts.Length {
        return -1
    }

    enumName := ParserDeclarationSpanText(source, outResult[0], outResult[1])
    if enumName == "" {
        return -1
    }
    outEnumNameTexts[0] = enumName

    i := 0
    while i < memberCount {
        memberName := ParserDeclarationSpanText(source, outNameStarts[i], outNameLengths[i])
        if memberName == "" {
            return -1
        }

        outNameTexts[i] = memberName
        i = i + 1
    }

    return memberCount
}

func ParsePropertyAccessorInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, propIndex: int, outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParsePropertyAccessorInfoCore(source, ref tokens, count, propIndex, ref result)
}

func ParsePropertyAccessorTypeInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, propIndex: int, outNameTexts: string[], outTypeTexts: string[], outResult: int[]): int {
    if outNameTexts.Length < 1 || outTypeTexts.Length < 1 {
        return -1
    }

    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    accessorKind := ParsePropertyAccessorInfoCore(source, ref tokens, count, propIndex, ref result)
    if accessorKind < 0 {
        return -1
    }

    nameText := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if nameText == "" {
        return -1
    }

    typeText := ParserDeclarationCanonicalTypeText(source, result.Values[2], result.Values[3])
    if typeText == "" {
        return -1
    }

    outNameTexts[0] = nameText
    outTypeTexts[0] = typeText
    return accessorKind
}

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

func ParseConstructorChainInfoInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    args := new ConstructorChainArgTable { Kinds: outArgKinds, Starts: outArgStarts, Lengths: outArgLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseConstructorChainInfoCore(ref tokens, count, ctorIndex, ref args, ref result)
}

func ParseConstructorInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outResult: int[]): int {
    if ctorIndex < 0 || ctorIndex >= count {
        return -1
    }

    if tokenKinds[ctorIndex] != 0 {
        return -1
    }

    if !ParserDeclarationTokenTextEquals(source, tokenStarts[ctorIndex], tokenValueLengths[ctorIndex], "constructor") {
        return -1
    }

    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    args := new ConstructorChainArgTable { Kinds: outArgKinds, Starts: outArgStarts, Lengths: outArgLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseConstructorChainInfoCore(ref tokens, count, ctorIndex, ref args, ref result)
}

func ParseConstructorTextInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outArgTexts: string[], outResult: int[]): int {
    if ctorIndex < 0 || ctorIndex >= count {
        return -1
    }

    if tokenKinds[ctorIndex] != 0 {
        return -1
    }

    if !ParserDeclarationTokenTextEquals(source, tokenStarts[ctorIndex], tokenValueLengths[ctorIndex], "constructor") {
        return -1
    }

    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    args := new ConstructorChainArgTable { Kinds: outArgKinds, Starts: outArgStarts, Lengths: outArgLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    argCount := ParseConstructorChainInfoCore(ref tokens, count, ctorIndex, ref args, ref result)
    if argCount < 0 {
        return -1
    }

    if outArgTexts.Length < argCount {
        return -1
    }

    i := 0
    while i < argCount {
        outArgTexts[i] = source.Substring(args.Starts[i], args.Lengths[i])
        i = i + 1
    }

    return argCount
}
