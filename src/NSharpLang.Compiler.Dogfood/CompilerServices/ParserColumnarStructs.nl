import "CompilerServices/ParserColumnarConstructors"
import "CompilerServices/ParserColumnarFunctions"
import "CompilerServices/ParserDeclarations"
import "CompilerServices/ParserLocalFunctions"

// Product columnar struct/class/record parser wrapper. It keeps declaration span scratch columns inside N#,
// rejects unsupported value-type storage/property shapes and member generic/local functions, and exposes only text,
// flag, and member-index rows needed by the columnar input builder.

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

func ParseColumnarStructInfoCore(source: string, tokens: &ColumnarStructTokenTable, structIndex: int, isReference: int, _isRecord: int, scratch: &ColumnarStructScratchTable, outputs: &ColumnarStructOutputTable, result: &ColumnarStructResultTable): int {
    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    decl := new StructDeclarationTable { FieldNameStarts: scratch.FieldNameStarts, FieldNameLengths: scratch.FieldNameLengths, FieldTypeStarts: scratch.FieldTypeStarts, FieldTypeLengths: scratch.FieldTypeLengths, FieldStaticFlags: outputs.FieldStaticFlags, FieldInitKinds: outputs.FieldInitKinds, FieldInitStarts: scratch.FieldInitStarts, FieldInitLengths: scratch.FieldInitLengths, MethodFuncIndices: outputs.MethodFuncIndices, MethodStaticFlags: outputs.MethodStaticFlags, CtorIndices: outputs.CtorIndices, PropIndices: outputs.PropIndices, PropStaticFlags: outputs.PropStaticFlags, TypeParamStarts: scratch.TypeParamStarts, TypeParamLengths: scratch.TypeParamLengths, BaseNameStarts: scratch.BaseNameStarts, BaseNameLengths: scratch.BaseNameLengths }
    declarationResult := new ParserDeclarationResultTable { Values: result.Values }
    fieldCount := ParseStructDeclarationCore(source, ref declarationTokens, tokens.Count, structIndex, ref decl, ref declarationResult)
    methodCount := result.Values[2]
    propCount := result.Values[4]
    typeParamCount := result.Values[7]
    baseNameCount := result.Values[8]
    ctorCount := result.Values[3]
    if fieldCount < 0 || outputs.StructNameTexts.Length < 1 || fieldCount > outputs.FieldNameTexts.Length || fieldCount > outputs.FieldTypeTexts.Length || fieldCount > outputs.FieldInitTexts.Length || typeParamCount > outputs.TypeParamTexts.Length || baseNameCount > outputs.BaseNameTexts.Length {
        return -1
    }
    if ColumnarStructTypeParameterNamesDistinct(source, ref scratch, typeParamCount) == 0 {
        return -1
    }
    if ColumnarStructFieldNamesDistinct(source, ref scratch, fieldCount) == 0 {
        return -1
    }
    if ColumnarStructBaseNamesDistinct(source, ref scratch, baseNameCount) == 0 {
        return -1
    }
    if ColumnarStructMethodMemberNamesSupported(source, ref tokens, ref scratch, ref outputs, fieldCount, methodCount) == 0 {
        return -1
    }
    if ColumnarStructPropertyMemberNamesDistinct(source, ref tokens, ref scratch, ref outputs, fieldCount, methodCount, propCount) == 0 {
        return -1
    }

    if isReference == 0 {
        instanceFieldCount := 0
        fieldSlot := 0
        while fieldSlot < fieldCount {
            if outputs.FieldStaticFlags[fieldSlot] == 0 {
                instanceFieldCount = instanceFieldCount + 1
            }

            fieldSlot = fieldSlot + 1
        }

        if instanceFieldCount == 0 {
            return -1
        }
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
            if outputs.MethodStaticFlags[i] == 1 {
                return -1
            }

            methodName := ColumnarStructMethodMemberNameText(source, ref tokens, outputs.MethodFuncIndices[i])
            if methodName == "" {
                return -1
            }

            if ColumnarStructNameMatchesTypeParamText(source, ref scratch, typeParamCount, methodName) {
                return -1
            }

            i = i + 1
        }

        i = 0
        while i < propCount {
            if outputs.PropStaticFlags[i] == 1 {
                return -1
            }

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

    methodUnsupported := ColumnarStructMethodUnsupportedStatus(source, ref tokens, ref outputs, methodCount)
    if methodUnsupported != 0 {
        return -1
    }
    ctorUnsupported := ColumnarStructConstructorUnsupportedStatus(source, ref tokens, ref outputs, ctorCount, isReference)
    if ctorUnsupported != 0 {
        return -1
    }

    structName := ParserDeclarationQualifiedNameText(source, ref declarationTokens, tokens.Count, structIndex, result.Values[0], result.Values[1])
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

func ColumnarStructMethodUnsupportedStatus(source: string, tokens: &ColumnarStructTokenTable, outputs: &ColumnarStructOutputTable, methodCount: int): int {
    functionTokens := new ColumnarFunctionTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths, Count: tokens.Count }
    cap := (tokens.Count + 1) * 4
    signatureOutputs := new ColumnarFunctionSignatureOutputTable {
        FunctionNameTexts: new string[](1),
        ReturnTypeTexts: new string[](1),
        ParamNameTexts: new string[](cap),
        ParamTypeTexts: new string[](cap),
        ParamModifierKinds: new int[](cap),
        ParamDefaultKinds: new int[](cap),
        ParamDefaultTexts: new string[](cap),
        ParamTupleNameCounts: new int[](cap),
        ParamTupleNameTexts: new string[](cap),
        ReturnTupleNameTexts: new string[](cap),
        TypeParamTexts: new string[](cap),
        TypeParamSpecials: new int[](cap),
        TypeParamConstraintCounts: new int[](cap),
        TypeParamConstraintTypeTexts: new string[](cap)
    }
    body := new ColumnarFunctionBodyTable {
        NodeKinds: new int[](cap),
        ValueStarts: new int[](cap),
        ValueLengths: new int[](cap),
        ChildStart: new int[](cap),
        ChildCount: new int[](cap),
        ChildIndices: new int[](cap),
        SpanStarts: new int[](cap),
        SpanLengths: new int[](cap)
    }
    locals := new ColumnarFunctionLocalTable { NodeIndices: new int[](cap), TokenIndices: new int[](cap) }
    result := new ColumnarFunctionResultTable { Values: new int[](9) }
    methodParamCounts := new int[](methodCount + 1)
    methodParamStarts := new int[](methodCount + 1)
    methodNameTexts := new string[](methodCount + 1)
    methodParamTypeTexts := new string[](cap)
    nextMethodParamType := 0

    for i := 0; i < methodCount; i++ {
        paramCount := ParseColumnarFunctionInfoCore(source, ref functionTokens, outputs.MethodFuncIndices[i], 0, ref signatureOutputs, ref body, ref locals, ref result)
        if paramCount < 0 {
            return -1
        }

        methodName := signatureOutputs.FunctionNameTexts[0]
        if methodName == "" {
            return -1
        }

        if nextMethodParamType + paramCount > methodParamTypeTexts.Length {
            return -1
        }

        methodParamCounts[i] = paramCount
        if outputs.MethodStaticFlags[i] == 1 {
            j := 0
            while j < i {
                if outputs.MethodStaticFlags[j] == 1 && methodParamCounts[j] == paramCount {
                    if methodName == methodNameTexts[j] {
                        sameSignature := true
                        paramSlot := 0
                        while paramSlot < paramCount {
                            if signatureOutputs.ParamTypeTexts[paramSlot] != methodParamTypeTexts[methodParamStarts[j] + paramSlot] {
                                sameSignature = false
                            }

                            paramSlot = paramSlot + 1
                        }

                        if sameSignature {
                            return 1
                        }
                    }
                }

                j = j + 1
            }
        }
        methodNameTexts[i] = methodName
        methodParamStarts[i] = nextMethodParamType
        paramSlot := 0
        while paramSlot < paramCount {
            if signatureOutputs.ParamTypeTexts[paramSlot] == "" {
                return -1
            }

            methodParamTypeTexts[nextMethodParamType + paramSlot] = signatureOutputs.ParamTypeTexts[paramSlot]
            paramSlot = paramSlot + 1
        }
        nextMethodParamType = nextMethodParamType + paramCount
        if result.Values[2] > 0 {
            return 1
        }
        if result.Values[8] > 0 {
            return 1
        }
    }

    return 0
}

func ColumnarStructConstructorUnsupportedStatus(source: string, tokens: &ColumnarStructTokenTable, outputs: &ColumnarStructOutputTable, ctorCount: int, isReference: int): int {
    constructorTokens := new ColumnarConstructorTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths, Count: tokens.Count }
    cap := (tokens.Count + 1) * 4
    signatureOutputs := new ColumnarConstructorSignatureOutputTable {
        ParamNameTexts: new string[](cap),
        ParamTypeTexts: new string[](cap),
        ArgKinds: new int[](cap),
        ArgStarts: new int[](cap),
        ArgLengths: new int[](cap),
        ArgTexts: new string[](cap)
    }
    body := new ColumnarConstructorBodyTable {
        NodeKinds: new int[](cap),
        ValueStarts: new int[](cap),
        ValueLengths: new int[](cap),
        ChildStart: new int[](cap),
        ChildCount: new int[](cap),
        ChildIndices: new int[](cap),
        SpanStarts: new int[](cap),
        SpanLengths: new int[](cap)
    }
    result := new ColumnarConstructorResultTable { Values: new int[](6) }
    localResults := new LocalFunctionResultTable { NodeIndices: new int[](cap), FuncTokenIndices: new int[](cap) }
    ctorParamCounts := new int[](ctorCount + 1)
    ctorParamStarts := new int[](ctorCount + 1)
    ctorParamTypeTexts := new string[](cap)
    nextCtorParamType := 0

    for i := 0; i < ctorCount; i++ {
        paramCount := ParseColumnarConstructorInfoCore(source, ref constructorTokens, outputs.CtorIndices[i], ref signatureOutputs, ref body, ref result)
        if paramCount < 0 {
            return -1
        }

        previousCtor := 0
        while previousCtor < i {
            if ctorParamCounts[previousCtor] == paramCount {
                sameSignature := true
                paramSlot := 0
                while paramSlot < paramCount {
                    if signatureOutputs.ParamTypeTexts[paramSlot] != ctorParamTypeTexts[ctorParamStarts[previousCtor] + paramSlot] {
                        sameSignature = false
                    }

                    paramSlot = paramSlot + 1
                }

                if sameSignature {
                    return 1
                }
            }

            previousCtor = previousCtor + 1
        }

        if nextCtorParamType + paramCount > ctorParamTypeTexts.Length {
            return -1
        }

        ctorParamCounts[i] = paramCount
        ctorParamStarts[i] = nextCtorParamType
        paramSlot := 0
        while paramSlot < paramCount {
            if signatureOutputs.ParamTypeTexts[paramSlot] == "" {
                return -1
            }

            ctorParamTypeTexts[nextCtorParamType + paramSlot] = signatureOutputs.ParamTypeTexts[paramSlot]
            paramSlot = paramSlot + 1
        }
        nextCtorParamType = nextCtorParamType + paramCount

        if isReference == 0 {
            if result.Values[0] != 0 || paramCount == 0 {
                return 1
            }
        }

        localTokens := new LocalFunctionTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, Count: tokens.Count }
        localNodes := new LocalFunctionNodeTable { Kinds: body.NodeKinds, ValueStarts: body.ValueStarts, ChildStart: body.ChildStart, ChildCount: body.ChildCount, ChildIndices: body.ChildIndices }
        localFunctionCount := DirectLocalFunctionTokenIndicesCore(ref localTokens, ref localNodes, result.Values[4], ref localResults)
        if localFunctionCount < 0 {
            return -1
        }
        if localFunctionCount > 0 {
            return 1
        }
    }

    return 0
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

func ColumnarStructNameMatchesTypeParamText(source: string, scratch: &ColumnarStructScratchTable, typeParamCount: int, nameText: string): bool {
    if nameText == "" {
        return false
    }

    i := 0
    while i < typeParamCount {
        typeParamName := ParserDeclarationSpanText(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i])
        if typeParamName == nameText {
            return true
        }

        i = i + 1
    }

    return false
}

func ColumnarStructFieldNamesDistinct(source: string, scratch: &ColumnarStructScratchTable, fieldCount: int): int {
    if fieldCount < 0 {
        return 0
    }

    i := 0
    while i < fieldCount {
        if scratch.FieldNameStarts[i] < 0 || scratch.FieldNameLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < fieldCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.FieldNameStarts[i], scratch.FieldNameLengths[i], scratch.FieldNameStarts[j], scratch.FieldNameLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarStructBaseNamesDistinct(source: string, scratch: &ColumnarStructScratchTable, baseNameCount: int): int {
    if baseNameCount < 0 {
        return 0
    }

    i := 0
    while i < baseNameCount {
        if scratch.BaseNameStarts[i] < 0 || scratch.BaseNameLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < baseNameCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.BaseNameStarts[i], scratch.BaseNameLengths[i], scratch.BaseNameStarts[j], scratch.BaseNameLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarStructOperatorMemberName(kind: int): string {
    if kind == 44 {
        return "operator true"
    }
    if kind == 45 {
        return "operator false"
    }
    if kind == 88 {
        return "operator +"
    }
    if kind == 89 {
        return "operator -"
    }
    if kind == 90 {
        return "operator *"
    }
    if kind == 91 {
        return "operator /"
    }
    if kind == 92 {
        return "operator %"
    }
    if kind == 98 {
        return "operator =="
    }
    if kind == 99 {
        return "operator !="
    }
    if kind == 100 {
        return "operator <"
    }
    if kind == 101 {
        return "operator <="
    }
    if kind == 102 {
        return "operator >"
    }
    if kind == 103 {
        return "operator >="
    }
    if kind == 106 {
        return "operator !"
    }
    if kind == 107 {
        return "operator &"
    }
    if kind == 108 {
        return "operator |"
    }
    if kind == 109 {
        return "operator ^"
    }
    if kind == 110 {
        return "operator ~"
    }
    if kind == 111 {
        return "operator <<"
    }
    if kind == 112 {
        return "operator >>"
    }
    if kind == 113 {
        return "operator ++"
    }
    if kind == 114 {
        return "operator --"
    }
    return ""
}

func ColumnarStructMethodMemberNameText(source: string, tokens: &ColumnarStructTokenTable, funcIndex: int): string {
    methodNameIndex := funcIndex + 1
    if methodNameIndex < 0 || methodNameIndex >= tokens.Count {
        return ""
    }

    if tokens.Kinds[methodNameIndex] == 0 {
        return ParserDeclarationSpanText(source, tokens.Starts[methodNameIndex], tokens.ValueLengths[methodNameIndex])
    }

    if tokens.Kinds[methodNameIndex] == 75 {
        symbolIndex := methodNameIndex + 1
        if symbolIndex < 0 || symbolIndex >= tokens.Count {
            return ""
        }
        return ColumnarStructOperatorMemberName(tokens.Kinds[symbolIndex])
    }

    return ""
}

func ColumnarStructMethodMemberNamesSupported(source: string, tokens: &ColumnarStructTokenTable, scratch: &ColumnarStructScratchTable, outputs: &ColumnarStructOutputTable, fieldCount: int, methodCount: int): int {
    if methodCount < 0 {
        return 0
    }

    i := 0
    while i < methodCount {
        if outputs.MethodStaticFlags[i] != 0 && outputs.MethodStaticFlags[i] != 1 {
            return 0
        }

        methodName := ColumnarStructMethodMemberNameText(source, ref tokens, outputs.MethodFuncIndices[i])
        if methodName == "" {
            return 0
        }

        f := 0
        while f < fieldCount {
            if scratch.FieldNameStarts[f] < 0 || scratch.FieldNameLengths[f] <= 0 {
                return 0
            }

            fieldName := ParserDeclarationSpanText(source, scratch.FieldNameStarts[f], scratch.FieldNameLengths[f])
            if methodName == fieldName {
                return 0
            }

            f = f + 1
        }

        j := i + 1
        while j < methodCount {
            if outputs.MethodStaticFlags[j] != 0 && outputs.MethodStaticFlags[j] != 1 {
                return 0
            }

            otherMethodName := ColumnarStructMethodMemberNameText(source, ref tokens, outputs.MethodFuncIndices[j])
            if otherMethodName == "" {
                return 0
            }

            if methodName == otherMethodName {
                if outputs.MethodStaticFlags[i] == 0 || outputs.MethodStaticFlags[j] == 0 {
                    return 0
                }
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarStructPropertyMemberNamesDistinct(source: string, tokens: &ColumnarStructTokenTable, scratch: &ColumnarStructScratchTable, outputs: &ColumnarStructOutputTable, fieldCount: int, methodCount: int, propCount: int): int {
    if propCount < 0 {
        return 0
    }

    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    propertyResult := new ParserDeclarationResultTable { Values: new int[](6) }

    i := 0
    while i < propCount {
        if outputs.PropStaticFlags[i] != 0 && outputs.PropStaticFlags[i] != 1 {
            return 0
        }

        propNameIndex := outputs.PropIndices[i]
        if propNameIndex < 0 || propNameIndex >= tokens.Count || tokens.Kinds[propNameIndex] != 0 {
            return 0
        }

        propName := ParserDeclarationSpanText(source, tokens.Starts[propNameIndex], tokens.ValueLengths[propNameIndex])
        if propName == "" {
            return 0
        }

        accessorKind := ParsePropertyAccessorInfoCore(source, ref declarationTokens, tokens.Count, propNameIndex, ref propertyResult)
        if accessorKind < 0 || accessorKind > 1 {
            return 0
        }

        getAccessorName := "get_" + propName
        setAccessorName := "set_" + propName

        f := 0
        while f < fieldCount {
            if scratch.FieldNameStarts[f] < 0 || scratch.FieldNameLengths[f] <= 0 {
                return 0
            }

            if ParserDeclarationSourceSpansEqual(source, tokens.Starts[propNameIndex], tokens.ValueLengths[propNameIndex], scratch.FieldNameStarts[f], scratch.FieldNameLengths[f]) {
                return 0
            }

            f = f + 1
        }

        m := 0
        while m < methodCount {
            methodName := ColumnarStructMethodMemberNameText(source, ref tokens, outputs.MethodFuncIndices[m])
            if methodName == "" {
                return 0
            }

            if methodName == propName {
                return 0
            }

            if methodName == getAccessorName || (accessorKind == 1 && methodName == setAccessorName) {
                return 0
            }

            m = m + 1
        }

        j := i + 1
        while j < propCount {
            if outputs.PropStaticFlags[j] != 0 && outputs.PropStaticFlags[j] != 1 {
                return 0
            }

            otherPropNameIndex := outputs.PropIndices[j]
            if otherPropNameIndex < 0 || otherPropNameIndex >= tokens.Count || tokens.Kinds[otherPropNameIndex] != 0 {
                return 0
            }

            if ParserDeclarationSourceSpansEqual(source, tokens.Starts[propNameIndex], tokens.ValueLengths[propNameIndex], tokens.Starts[otherPropNameIndex], tokens.ValueLengths[otherPropNameIndex]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarStructTypeParameterNamesDistinct(source: string, scratch: &ColumnarStructScratchTable, typeParamCount: int): int {
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
