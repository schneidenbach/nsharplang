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

func ParseColumnarStructInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, structIndex: int, isReference: int, isRecord: int, outFieldNameTexts: string[], outFieldTypeTexts: string[], outFieldStaticFlags: int[], outFieldInitKinds: int[], outFieldInitTexts: string[], outMethodFuncIndices: int[], outMethodStaticFlags: int[], outCtorIndices: int[], outPropIndices: int[], outPropStaticFlags: int[], outTypeParamTexts: string[], outBaseNameTexts: string[], outStructNameTexts: string[], outResult: int[]): int {
    tokens := new ColumnarStructTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    scratch := new ColumnarStructScratchTable { FieldNameStarts: new int[](count + 1), FieldNameLengths: new int[](count + 1), FieldTypeStarts: new int[](count + 1), FieldTypeLengths: new int[](count + 1), FieldInitStarts: new int[](count + 1), FieldInitLengths: new int[](count + 1), TypeParamStarts: new int[](count + 1), TypeParamLengths: new int[](count + 1), BaseNameStarts: new int[](count + 1), BaseNameLengths: new int[](count + 1) }
    outputs := new ColumnarStructOutputTable { FieldNameTexts: outFieldNameTexts, FieldTypeTexts: outFieldTypeTexts, FieldStaticFlags: outFieldStaticFlags, FieldInitKinds: outFieldInitKinds, FieldInitTexts: outFieldInitTexts, MethodFuncIndices: outMethodFuncIndices, MethodStaticFlags: outMethodStaticFlags, CtorIndices: outCtorIndices, PropIndices: outPropIndices, PropStaticFlags: outPropStaticFlags, TypeParamTexts: outTypeParamTexts, BaseNameTexts: outBaseNameTexts, StructNameTexts: outStructNameTexts }
    result := new ColumnarStructResultTable { Values: outResult }
    return ParseColumnarStructInfoCore(source, ref tokens, structIndex, isReference, isRecord, ref scratch, ref outputs, ref result)
}

func ParseColumnarStructInfoCore(source: string, tokens: &ColumnarStructTokenTable, structIndex: int, isReference: int, isRecord: int, scratch: &ColumnarStructScratchTable, outputs: &ColumnarStructOutputTable, result: &ColumnarStructResultTable): int {
    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    decl := new StructDeclarationTable { FieldNameStarts: scratch.FieldNameStarts, FieldNameLengths: scratch.FieldNameLengths, FieldTypeStarts: scratch.FieldTypeStarts, FieldTypeLengths: scratch.FieldTypeLengths, FieldStaticFlags: outputs.FieldStaticFlags, FieldInitKinds: outputs.FieldInitKinds, FieldInitStarts: scratch.FieldInitStarts, FieldInitLengths: scratch.FieldInitLengths, MethodFuncIndices: outputs.MethodFuncIndices, MethodStaticFlags: outputs.MethodStaticFlags, CtorIndices: outputs.CtorIndices, PropIndices: outputs.PropIndices, PropStaticFlags: outputs.PropStaticFlags, TypeParamStarts: scratch.TypeParamStarts, TypeParamLengths: scratch.TypeParamLengths, BaseNameStarts: scratch.BaseNameStarts, BaseNameLengths: scratch.BaseNameLengths }
    declarationResult := new ParserDeclarationResultTable { Values: result.Values }
    fieldCount := ParseStructDeclarationCore(ref declarationTokens, tokens.Count, structIndex, ref decl, ref declarationResult)
    methodCount := result.Values[2]
    propCount := result.Values[4]
    typeParamCount := result.Values[7]
    baseNameCount := result.Values[8]
    ctorCount := result.Values[3]
    if fieldCount < 0 || outputs.StructNameTexts.Length < 1 || fieldCount > outputs.FieldNameTexts.Length || fieldCount > outputs.FieldTypeTexts.Length || fieldCount > outputs.FieldInitTexts.Length || typeParamCount > outputs.TypeParamTexts.Length || baseNameCount > outputs.BaseNameTexts.Length {
        return -1
    }

    if fieldCount == 0 && isReference == 0 {
        return -1
    }

    if isRecord == 1 && ctorCount > 0 {
        return -1
    }

    if typeParamCount > 0 && baseNameCount > 0 {
        return -1
    }

    i := 0
    if typeParamCount > 0 {
        while i < fieldCount {
            if outputs.FieldStaticFlags[i] == 1 {
                return -1
            }

            if ColumnarStructNameMatchesTypeParam(source, ref scratch, typeParamCount, scratch.FieldNameStarts[i], scratch.FieldNameLengths[i]) {
                return -1
            }

            i = i + 1
        }

        i = 0
        while i < methodCount {
            methodNameIndex := outputs.MethodFuncIndices[i] + 1
            if methodNameIndex < 0 || methodNameIndex >= tokens.Count || tokens.Kinds[methodNameIndex] != 0 {
                return -1
            }

            if ColumnarStructNameMatchesTypeParam(source, ref scratch, typeParamCount, tokens.Starts[methodNameIndex], tokens.ValueLengths[methodNameIndex]) {
                return -1
            }

            i = i + 1
        }

        i = 0
        while i < propCount {
            propNameIndex := outputs.PropIndices[i]
            if propNameIndex < 0 || propNameIndex >= tokens.Count || tokens.Kinds[propNameIndex] != 0 {
                return -1
            }

            if ColumnarStructNameMatchesTypeParam(source, ref scratch, typeParamCount, tokens.Starts[propNameIndex], tokens.ValueLengths[propNameIndex]) {
                return -1
            }

            i = i + 1
        }
    }

    structName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if structName == "" {
        return -1
    }
    outputs.StructNameTexts[0] = structName

    i = 0
    while i < typeParamCount {
        typeParamName := ParserDeclarationSpanText(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i])
        if typeParamName == "" {
            return -1
        }

        outputs.TypeParamTexts[i] = typeParamName
        i = i + 1
    }

    i = 0
    while i < baseNameCount {
        baseName := ParserDeclarationSpanText(source, scratch.BaseNameStarts[i], scratch.BaseNameLengths[i])
        if baseName == "" {
            return -1
        }

        outputs.BaseNameTexts[i] = baseName
        i = i + 1
    }

    i = 0
    while i < fieldCount {
        fieldName := ParserDeclarationSpanText(source, scratch.FieldNameStarts[i], scratch.FieldNameLengths[i])
        if fieldName == "" {
            return -1
        }

        text := ParserDeclarationCanonicalTypeText(source, scratch.FieldTypeStarts[i], scratch.FieldTypeLengths[i])
        if text.Length == 0 {
            return -1
        }

        outputs.FieldNameTexts[i] = fieldName
        outputs.FieldTypeTexts[i] = text
        if outputs.FieldInitKinds[i] >= 0 {
            initText := source.Substring(scratch.FieldInitStarts[i], scratch.FieldInitLengths[i])
            if initText.Length == 0 {
                return -1
            }

            outputs.FieldInitTexts[i] = initText
        }

        i = i + 1
    }

    return fieldCount
}

func ColumnarStructNameMatchesTypeParam(source: string, scratch: &ColumnarStructScratchTable, typeParamCount: int, nameStart: int, nameLength: int): bool {
    i := 0
    while i < typeParamCount {
        if ParserDeclarationSourceSpansEqual(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i], nameStart, nameLength) {
            return true
        }

        i = i + 1
    }

    return false
}
