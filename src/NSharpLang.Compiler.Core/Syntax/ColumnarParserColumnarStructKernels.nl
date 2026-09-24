import NSharpLang.Compiler
import NSharpLang.Compiler.Columnar


// THE COLUMNAR STRUCT INFO KERNEL: field, method, property and constructor extraction, the
// static-initializer body, the member flag readers, and the shape rules a struct must satisfy.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.

// Product columnar struct/class/record parser wrapper. It keeps declaration span scratch columns inside N#,
// rejects unsupported value-type storage/property shapes and member generic/local functions, and exposes only text,
// flag, and member-index rows needed by the columnar input builder.
class ColumnarStructTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
    constructor(kinds: int[], starts: int[], valueLengths: int[], count: int) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }
}

class ColumnarStructScratchTable {
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    FieldInitStarts: int[]
    FieldInitLengths: int[]
    FieldInitTokens: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    Where: ParserDeclarationWhereTable
    constructor(fieldNameStarts: int[], fieldNameLengths: int[], fieldTypeStarts: int[], fieldTypeLengths: int[], fieldInitStarts: int[], fieldInitLengths: int[], fieldInitTokens: int[], typeParamStarts: int[], typeParamLengths: int[], baseNameStarts: int[], baseNameLengths: int[], whereTable: ParserDeclarationWhereTable) {
        FieldNameStarts = fieldNameStarts
        FieldNameLengths = fieldNameLengths
        FieldTypeStarts = fieldTypeStarts
        FieldTypeLengths = fieldTypeLengths
        FieldInitStarts = fieldInitStarts
        FieldInitLengths = fieldInitLengths
        FieldInitTokens = fieldInitTokens
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
        Where = whereTable
    }
}

class ColumnarStructOutputTable {
    WhereOwnerTexts: string[]
    WhereItemCodes: int[]
    WhereTypeTexts: string[]
    FieldNameTexts: string[]
    FieldTypeTexts: string[]
    FieldStaticFlags: int[]
    FieldInitKinds: int[]
    FieldInitTexts: string[]
    FieldDeclTokens: int[]
    MethodFuncIndices: int[]
    MethodStaticFlags: int[]
    CtorIndices: int[]
    PropIndices: int[]
    PropStaticFlags: int[]
    TypeParamTexts: string[]
    BaseNameTexts: string[]
    StructNameTexts: string[]
    constructor(fieldNameTexts: string[], fieldTypeTexts: string[], fieldStaticFlags: int[], fieldInitKinds: int[], fieldInitTexts: string[], fieldDeclTokens: int[], methodFuncIndices: int[], methodStaticFlags: int[], ctorIndices: int[], propIndices: int[], propStaticFlags: int[], typeParamTexts: string[], baseNameTexts: string[], structNameTexts: string[], whereOwnerTexts: string[], whereItemCodes: int[], whereTypeTexts: string[]) {
        FieldNameTexts = fieldNameTexts
        FieldTypeTexts = fieldTypeTexts
        FieldStaticFlags = fieldStaticFlags
        FieldInitKinds = fieldInitKinds
        FieldInitTexts = fieldInitTexts
        FieldDeclTokens = fieldDeclTokens
        MethodFuncIndices = methodFuncIndices
        MethodStaticFlags = methodStaticFlags
        CtorIndices = ctorIndices
        PropIndices = propIndices
        PropStaticFlags = propStaticFlags
        TypeParamTexts = typeParamTexts
        BaseNameTexts = baseNameTexts
        StructNameTexts = structNameTexts
        WhereOwnerTexts = whereOwnerTexts
        WhereItemCodes = whereItemCodes
        WhereTypeTexts = whereTypeTexts
    }
}

class ColumnarStructResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

// Product columnar union parser wrapper. It keeps declaration span scratch columns inside N# and exposes only
// the text/count rows needed by the columnar input builder.

func ParseColumnarStructInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, structIndex: int, isReference: int, isRecord: int, outFieldNameTexts: string[], outFieldTypeTexts: string[], outFieldStaticFlags: int[], outFieldInitKinds: int[], outFieldInitTexts: string[], outFieldDeclTokens: int[], outMethodFuncIndices: int[], outMethodStaticFlags: int[], outCtorIndices: int[], outPropIndices: int[], outPropStaticFlags: int[], outTypeParamTexts: string[], outBaseNameTexts: string[], outStructNameTexts: string[], outWhereOwnerTexts: string[], outWhereItemCodes: int[], outWhereTypeTexts: string[], outResult: int[], outStaticInitNodeKinds: int[], outStaticInitValueStarts: int[], outStaticInitValueLengths: int[], outStaticInitChildStart: int[], outStaticInitChildCount: int[], outStaticInitChildIndices: int[], outStaticInitSpanStarts: int[], outStaticInitSpanLengths: int[], outStaticInitResult: int[]): int {
    tokens := new ColumnarStructTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    whereScratch := new ParserDeclarationWhereTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    scratch := new ColumnarStructScratchTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), whereScratch)
    outputs := new ColumnarStructOutputTable(outFieldNameTexts, outFieldTypeTexts, outFieldStaticFlags, outFieldInitKinds, outFieldInitTexts, outFieldDeclTokens, outMethodFuncIndices, outMethodStaticFlags, outCtorIndices, outPropIndices, outPropStaticFlags, outTypeParamTexts, outBaseNameTexts, outStructNameTexts, outWhereOwnerTexts, outWhereItemCodes, outWhereTypeTexts)
    result := new ColumnarStructResultTable(outResult)
    staticInitializerBody := new ColumnarConstructorBodyTable(outStaticInitNodeKinds, outStaticInitValueStarts, outStaticInitValueLengths, outStaticInitChildStart, outStaticInitChildCount, outStaticInitChildIndices, outStaticInitSpanStarts, outStaticInitSpanLengths)
    staticInitializerResult := new ColumnarConstructorResultTable(outStaticInitResult)
    return ParseColumnarStructInfoCore(source, tokens, structIndex, isReference, isRecord, scratch, outputs, result, staticInitializerBody, staticInitializerResult)
}

func ParseColumnarStructInfoCore(source: string, tokens: ColumnarStructTokenTable, structIndex: int, isReference: int, _isRecord: int, scratch: ColumnarStructScratchTable, outputs: ColumnarStructOutputTable, result: ColumnarStructResultTable, staticInitializerBody: ColumnarConstructorBodyTable, staticInitializerResult: ColumnarConstructorResultTable): int {
    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    decl := new StructDeclarationTable(scratch.FieldNameStarts, scratch.FieldNameLengths, scratch.FieldTypeStarts, scratch.FieldTypeLengths, outputs.FieldStaticFlags, outputs.FieldInitKinds, scratch.FieldInitStarts, scratch.FieldInitLengths, scratch.FieldInitTokens, outputs.FieldDeclTokens, outputs.MethodFuncIndices, outputs.MethodStaticFlags, outputs.MethodStaticFlags, outputs.CtorIndices, outputs.PropIndices, outputs.PropStaticFlags, scratch.TypeParamStarts, scratch.TypeParamLengths, scratch.BaseNameStarts, scratch.BaseNameLengths, scratch.Where)
    declarationResult := new ParserDeclarationResultTable(result.Values)
    fieldCount := ParseStructDeclarationCore(source, declarationTokens, tokens.Count, structIndex, decl, declarationResult)
    methodCount := result.Values[2]
    propCount := result.Values[4]
    typeParamCount := result.Values[7]
    baseNameCount := result.Values[8]
    ctorCount := result.Values[3]
    if fieldCount < 0 || outputs.StructNameTexts.Length < 1 || fieldCount > outputs.FieldNameTexts.Length || fieldCount > outputs.FieldTypeTexts.Length || fieldCount > outputs.FieldInitTexts.Length || typeParamCount > outputs.TypeParamTexts.Length || baseNameCount > outputs.BaseNameTexts.Length {
        return -1
    }

    if ParserDeclarationNameSpansDistinct(source, scratch.TypeParamStarts, scratch.TypeParamLengths, typeParamCount) == 0 {
        return -1
    }

    if ParserDeclarationNameSpansDistinct(source, scratch.FieldNameStarts, scratch.FieldNameLengths, fieldCount) == 0 {
        return -1
    }

    if ParserDeclarationNameSpansDistinct(source, scratch.BaseNameStarts, scratch.BaseNameLengths, baseNameCount) == 0 {
        return -1
    }

    if ColumnarStructMethodMemberNamesSupported(source, tokens, scratch, outputs, fieldCount, methodCount) == 0 {
        return -1
    }

    if ColumnarStructPropertyMemberNamesDistinct(source, tokens, scratch, outputs, fieldCount, methodCount, propCount) == 0 {
        return -1
    }

    if isReference == 0 {
        instanceFieldCount := 0
        fieldSlot := 0
        while fieldSlot < fieldCount {
            if !ColumnarStructFieldFlagIsStatic(outputs.FieldStaticFlags[fieldSlot]) {
                instanceFieldCount = instanceFieldCount + 1
            }

            fieldSlot = fieldSlot + 1
        }

        if instanceFieldCount == 0 {
            return -1
        }
    }

    i := 0
    if typeParamCount > 0 {
        while i < fieldCount {
            if ColumnarStructNameMatchesTypeParam(source, scratch, typeParamCount, scratch.FieldNameStarts[i], scratch.FieldNameLengths[i]) {
                return -1
            }

            i = i + 1
        }

        i = 0
        while i < methodCount {
            methodName := ColumnarStructMethodMemberNameText(source, tokens, outputs.MethodFuncIndices[i])
            if methodName == "" {
                return -1
            }

            if ColumnarStructNameMatchesTypeParamText(source, scratch, typeParamCount, methodName) {
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

            if ColumnarStructNameMatchesTypeParam(source, scratch, typeParamCount, tokens.Starts[propNameIndex], tokens.ValueLengths[propNameIndex]) {
                return -1
            }

            i = i + 1
        }
    }

    methodUnsupported := ColumnarStructMethodUnsupportedStatus(source, tokens, outputs, methodCount)
    if methodUnsupported != 0 {
        return -1
    }

    ctorUnsupported := ColumnarStructConstructorUnsupportedStatus(source, tokens, outputs, ctorCount, isReference)
    if ctorUnsupported != 0 {
        return -1
    }

    // Struct inputs carry a source-relative simple name plus an explicit enclosing-type path.
    // Namespace qualification belongs to ColumnarBindingScopeFacts, which has the file identity;
    // returning a namespace-qualified string here would force the mechanical C# bridge to strip
    // semantic identity back apart.
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
        baseName := ParserDeclarationCanonicalTypeText(source, scratch.BaseNameStarts[i], scratch.BaseNameLengths[i])
        if baseName == "" {
            return -1
        }

        outputs.BaseNameTexts[i] = baseName
        i = i + 1
    }

    // The constraint rows, rendered like the base list: the owner type-parameter NAME as a plain span
    // and the constraint TYPE canonically, so the host compares owner names against the declared type
    // parameters and hands the type texts straight to the input builder.
    whereItemCount := 0
    if result.Values.Length > 10 {
        whereItemCount = result.Values[10]
    }

    if whereItemCount > outputs.WhereOwnerTexts.Length || whereItemCount > outputs.WhereItemCodes.Length || whereItemCount > outputs.WhereTypeTexts.Length {
        return -1
    }

    i = 0
    while i < whereItemCount {
        ownerName := ParserDeclarationSpanText(source, scratch.Where.NameStarts[i], scratch.Where.NameLengths[i])
        if ownerName == "" {
            return -1
        }

        outputs.WhereOwnerTexts[i] = ownerName
        outputs.WhereItemCodes[i] = scratch.Where.ItemCodes[i]
        constraintText := ""
        if scratch.Where.ItemCodes[i] == 0 {
            constraintText = ParserDeclarationCanonicalTypeText(source, scratch.Where.TypeStarts[i], scratch.Where.TypeLengths[i])
            if constraintText == "" {
                return -1
            }
        }

        outputs.WhereTypeTexts[i] = constraintText
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

    if BuildColumnarStaticInitializerBodyCore(source, tokens, scratch, outputs, fieldCount, staticInitializerBody, staticInitializerResult) < 0 {
        return -1
    }

    return fieldCount
}

// THE SYNTHESIZED STATIC INITIALIZER. A type's static field initializers are ordinary expressions
// that run once, in textual order, inside the type's `.cctor`. Reading them as a BLOCK of
// `Name = <expression>` statements puts them on the same lowering path every other statement takes,
// so a static initializer resolves names, overloads, operators and conversions exactly the way the
// same assignment written in a static method does. `const` is excluded: its initializer is metadata
// (`.field static literal`), not code. The result's statement count is 0 for a type that declares no
// static initializer, and the emitter defines no `.cctor` for one.
func BuildColumnarStaticInitializerBodyCore(source: string, tokens: ColumnarStructTokenTable, scratch: ColumnarStructScratchTable, outputs: ColumnarStructOutputTable, fieldCount: int, body: ColumnarConstructorBodyTable, result: ColumnarConstructorResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    result.Values[0] = 0
    result.Values[1] = -1
    result.Values[2] = 0
    result.Values[3] = 0
    result.Values[4] = -1
    result.Values[5] = 0
    statementIndices := new int[](fieldCount + 1)
    cursorResult := new ColumnarConstructorResultTable(new int[](2))
    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    expressionNodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    expressionChildren := new ParserChildIndexTable(body.ChildIndices)
    expressionStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodeCursor := 0
    childCursor := 0
    statementCount := 0
    firstInitializerStart := -1
    lastInitializerEnd := -1
    i := 0
    while i < fieldCount {
        if outputs.FieldInitKinds[i] < 0 || !ColumnarStructFieldFlagIsStatic(outputs.FieldStaticFlags[i]) || ColumnarStructFieldFlagIsConst(outputs.FieldStaticFlags[i]) {
            i = i + 1
            continue
        }

        initToken := scratch.FieldInitTokens[i]
        if initToken <= 0 || initToken >= tokens.Count {
            return -1
        }

        expressionState := new ParserState(initToken, nodeCursor, childCursor, 0, 0, 0)
        valueRoot := ParseLambdaOrAssignmentExpressionNode(expressionTokens, tokens.Count, expressionState, expressionStack, expressionNodes, expressionChildren, 0)
        if valueRoot < 0 || expressionState.Pos <= initToken {
            return -1
        }

        nodeCursor = expressionState.NodeCursor
        childCursor = expressionState.ChildCursor
        // The assignment operator span is the `=` token immediately before the initializer.
        statementNode := EmitColumnarPrimaryConstructorAssignmentRootNode(
            body,
            scratch.FieldNameStarts[i],
            scratch.FieldNameLengths[i],
            valueRoot,
            tokens.Starts[initToken - 1],
            tokens.ValueLengths[initToken - 1],
            nodeCursor,
            childCursor,
            cursorResult
        )
        if statementNode < 0 || statementCount >= statementIndices.Length {
            return -1
        }

        nodeCursor = cursorResult.Values[0]
        childCursor = cursorResult.Values[1]
        statementIndices[statementCount] = statementNode
        statementCount = statementCount + 1
        if firstInitializerStart < 0 {
            firstInitializerStart = scratch.FieldNameStarts[i]
        }

        lastInitializerEnd = scratch.FieldInitStarts[i] + scratch.FieldInitLengths[i]
        i = i + 1
    }

    if statementCount == 0 {
        return 0
    }

    if nodeCursor >= body.NodeKinds.Length || childCursor + statementCount > body.ChildIndices.Length {
        return -1
    }

    root := nodeCursor
    body.NodeKinds[root] = 25
    body.ValueStarts[root] = -1
    body.ValueLengths[root] = 0
    body.ChildStart[root] = childCursor
    body.ChildCount[root] = statementCount
    body.SpanStarts[root] = firstInitializerStart
    body.SpanLengths[root] = lastInitializerEnd - firstInitializerStart
    i = 0
    while i < statementCount {
        body.ChildIndices[childCursor + i] = statementIndices[i]
        i = i + 1
    }

    nodeCursor = nodeCursor + 1
    result.Values[4] = root
    result.Values[5] = nodeCursor
    result.Values[2] = statementCount
    return statementCount
}

func ColumnarStructFieldFlagIsStatic(flags: int): bool {
    return (flags & 1) != 0
}

// The field word packs eight independent facts: bit 0 `static`, bit 1 `readonly`, bit 2 `private`,
// bit 3 the exact System.ThreadStatic intrinsic, bit 4 `const`, bit 5 `protected`, bit 6 `internal`
// and bit 7 `public`. The columnar input builder used to decode the first two itself; every bit's
// meaning belongs to the kernel that writes the word.
func ColumnarStructFieldFlagIsReadonly(flags: int): bool {
    return (flags & 2) != 0
}

func ColumnarStructFieldFlagIsPrivate(flags: int): bool {
    return (flags & 4) != 0
}

// The field word's visibility bits, translated back into the ONE modifier bit space `Modifiers`
// (DeclarationEnums.nl) uses: Public 1, Private 2, Internal 4, Protected 8. The packed word keeps
// its own layout because its other four bits are storage facts, not accessibility.
func ColumnarStructFieldVisibilityModifiers(flags: int): int {
    modifiers := 0
    if (flags & 128) != 0 {
        modifiers = modifiers | 1
    }
    if (flags & 4) != 0 {
        modifiers = modifiers | 2
    }
    if (flags & 64) != 0 {
        modifiers = modifiers | 4
    }
    if (flags & 32) != 0 {
        modifiers = modifiers | 8
    }
    return modifiers
}

func ColumnarStructFieldFlagIsThreadStatic(flags: int): bool {
    return (flags & 8) != 0
}

func ColumnarStructFieldFlagIsConst(flags: int): bool {
    return (flags & 16) != 0
}

// Bit 8: the field is a source-declared EVENT's backing storage. It is not a modifier anyone writes —
// it records that the member was spelled `event Name: DelegateType`, which is the one declaration that
// produces a field the author never named. The emitter reads it to force private storage and to define
// the `add_`/`remove_` accessors and the `EventInfo` row beside the field.
func ColumnarStructFieldFlagIsEvent(flags: int): bool {
    return (flags & 256) != 0
}

// Bits 9, 10 and 11: `virtual`, `abstract` and `override` as written on the member. Only an EVENT row
// can act on them — an event's accessors are ordinary methods, so they take ordinary virtual slots —
// and a plain field carrying one is refused by the analyzer before emission is asked.
func ColumnarStructFieldFlagIsVirtual(flags: int): bool {
    return (flags & 512) != 0
}

func ColumnarStructFieldFlagIsAbstract(flags: int): bool {
    return (flags & 1024) != 0
}

func ColumnarStructFieldFlagIsOverride(flags: int): bool {
    return (flags & 2048) != 0
}

// Bits 12 and 13: `required` and `init` as written on the member. A `required` row stays a field and
// gains the metadata a caller's object initializer is checked against; an `init` row becomes an
// init-only auto-property, whose storage is a private compiler-generated field.
func ColumnarStructFieldFlagIsRequired(flags: int): bool {
    return (flags & 4096) != 0
}

func ColumnarStructFieldFlagIsInitOnly(flags: int): bool {
    return (flags & 8192) != 0
}

// Property prefix flags share the existing integer output column: bit 0 is static, bit 1 is the
// exact MSBuild RequiredAttribute marker, bit 2 is the exact MSBuild OutputAttribute marker, bit 3
// is the `required` word and bit 4 the `init` word. Naming the reads here keeps the host from
// duplicating the packed representation.
func ColumnarStructPropertyFlagIsStatic(flags: int): bool {
    return (flags & 1) != 0
}

func ColumnarStructPropertyFlagHasMsBuildRequired(flags: int): bool {
    return (flags & 2) != 0
}

func ColumnarStructPropertyFlagHasMsBuildOutput(flags: int): bool {
    return (flags & 4) != 0
}

// Bits 3 and 4: the `required` and `init` words written in front of a property declaration.
func ColumnarStructPropertyFlagIsRequired(flags: int): bool {
    return (flags & 8) != 0
}

func ColumnarStructPropertyFlagIsInitOnly(flags: int): bool {
    return (flags & 16) != 0
}

func ColumnarStructMethodUnsupportedStatus(source: string, tokens: ColumnarStructTokenTable, outputs: ColumnarStructOutputTable, methodCount: int): int {
    functionTokens := new ColumnarFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count)
    cap := (tokens.Count + 1) * 4
    signatureOutputs := new ColumnarFunctionSignatureOutputTable(new string[](1), new string[](1), new string[](cap), new string[](cap), new int[](cap), new int[](cap), new string[](cap), new int[](cap), new string[](cap), new string[](cap), new string[](1), new string[](cap), new string[](cap), new int[](cap), new int[](cap), new string[](cap))
    body := new ColumnarFunctionBodyTable(new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap))
    locals := new ColumnarFunctionLocalTable(new int[](cap), new int[](cap))
    result := new ColumnarFunctionResultTable(new int[](9))
    methodParamCounts := new int[](methodCount + 1)
    methodParamStarts := new int[](methodCount + 1)
    methodNameTexts := new string[](methodCount + 1)
    methodParamTypeTexts := new string[](cap)
    nextMethodParamType := 0

    for i := 0; i < methodCount; i++ {
        result.Values[8] = 0
        nativeImportMethod := ColumnarFunctionModifierFlags.HasNativeImportModifier(outputs.MethodStaticFlags[i])
        abstractMethod := ColumnarStructMethodFlagIsAbstract(outputs.MethodStaticFlags[i]) && !ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[i])
        paramCount := 0
        if nativeImportMethod {
            if !ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[i]) {
                return -1
            }

            paramCount = ParseColumnarFunctionSignatureOnlyInfoCore(source, functionTokens, outputs.MethodFuncIndices[i], signatureOutputs, result)
        } else if abstractMethod {
            paramCount = ParseColumnarFunctionSignatureOnlyInfoCore(source, functionTokens, outputs.MethodFuncIndices[i], signatureOutputs, result)
        } else {
            paramCount = ParseColumnarFunctionInfoCore(source, functionTokens, outputs.MethodFuncIndices[i], 0, signatureOutputs, body, locals, result)
        }

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
        if ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[i]) {
            j := 0
            while j < i {
                if ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[j]) && methodParamCounts[j] == paramCount {
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
        } else {
            j := 0
            while j < i {
                if !ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[j]) && methodParamCounts[j] == paramCount {
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
    }

    return 0
}

func ColumnarStructConstructorUnsupportedStatus(source: string, tokens: ColumnarStructTokenTable, outputs: ColumnarStructOutputTable, ctorCount: int, isReference: int): int {
    constructorTokens := new ColumnarConstructorTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count)
    cap := (tokens.Count + 1) * 4
    signatureOutputs := new ColumnarConstructorSignatureOutputTable(new string[](cap), new string[](cap), new string[](cap), new int[](cap), new int[](cap), new int[](cap), new string[](cap))
    body := new ColumnarConstructorBodyTable(new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap))
    result := new ColumnarConstructorResultTable(new int[](6))
    localResults := new LocalFunctionResultTable(new int[](cap), new int[](cap))
    ctorParamCounts := new int[](ctorCount + 1)
    ctorParamStarts := new int[](ctorCount + 1)
    ctorParamTypeTexts := new string[](cap)
    nextCtorParamType := 0

    for i := 0; i < ctorCount; i++ {
        paramCount := ParseColumnarConstructorInfoCore(source, constructorTokens, outputs.CtorIndices[i], signatureOutputs, body, result)
        if paramCount < 0 {
            return -1
        }

        currentIsInitializerMethod := ColumnarStructCtorIndexIsZeroParamSynthesizedInitializer(tokens, outputs.CtorIndices[i], paramCount)
        previousCtor := 0
        while previousCtor < i {
            previousIsInitializerMethod := ColumnarStructCtorIndexIsZeroParamSynthesizedInitializer(tokens, outputs.CtorIndices[previousCtor], ctorParamCounts[previousCtor])
            if !currentIsInitializerMethod && !previousIsInitializerMethod && ctorParamCounts[previousCtor] == paramCount {
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
            if currentIsInitializerMethod {
                // A VALUE TYPE TAKES THE SYNTHESIZED FIELD-INITIALIZER CONSTRUCTOR, but only when the
                // type declares a constructor of its own for those stores to run in: with none, every
                // value of the type would skip them. NL329 says exactly that at `check`; refusing the
                // shape here too keeps any other path from emitting a type whose initializers can
                // never run. A WRITTEN parameterless struct constructor stays refused below.
                if ctorCount <= 1 {
                    return 1
                }
            } else if result.Values[0] != 0 || paramCount == 0 {
                return 1
            }
        }

        localTokens := new LocalFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.Count)
        localNodes := new LocalFunctionNodeTable(body.NodeKinds, body.ValueStarts, body.ChildStart, body.ChildCount, body.ChildIndices)
        localFunctionCount := DirectLocalFunctionTokenIndicesCore(localTokens, localNodes, result.Values[4], localResults)
        if localFunctionCount < 0 {
            return -1
        }

        if localFunctionCount > 0 {
            return 1
        }
    }

    return 0
}

// The synthesized field-initializer constructor is the one recorded at the TYPE's own keyword token,
// and it carries no parameters. Class (8), struct (9) and record (13) all produce one: a struct's is
// what carries its field initializers into each of its declared constructors.
func ColumnarStructCtorIndexIsZeroParamSynthesizedInitializer(tokens: ColumnarStructTokenTable, ctorIndex: int, paramCount: int): bool {
    if paramCount != 0 || ctorIndex < 0 || ctorIndex >= tokens.Count {
        return false
    }

    return tokens.Kinds[ctorIndex] == 8 || tokens.Kinds[ctorIndex] == 9 || tokens.Kinds[ctorIndex] == 13
}

func ColumnarStructNameMatchesTypeParam(source: string, scratch: ColumnarStructScratchTable, typeParamCount: int, nameStart: int, nameLength: int): bool {
    i := 0
    while i < typeParamCount {
        if ParserDeclarationSourceSpansEqual(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i], nameStart, nameLength) {
            return true
        }

        i = i + 1
    }

    return false
}

func ColumnarStructNameMatchesTypeParamText(source: string, scratch: ColumnarStructScratchTable, typeParamCount: int, nameText: string): bool {
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

func ColumnarStructMethodMemberNameText(source: string, tokens: ColumnarStructTokenTable, funcIndex: int): string {
    if funcIndex >= 0 && funcIndex < tokens.Count {
        if tokens.Kinds[funcIndex] == 85 {
            return "op_Implicit"
        }

        if tokens.Kinds[funcIndex] == 86 {
            return "op_Explicit"
        }
    }

    methodNameIndex := funcIndex + 1
    // `func*` generator method: skip the `*` (Star 90) so the member name resolves to the identifier.
    if methodNameIndex < tokens.Count && tokens.Kinds[methodNameIndex] == 90 {
        methodNameIndex = methodNameIndex + 1
    }
    if methodNameIndex < 0 || methodNameIndex >= tokens.Count {
        return ""
    }

    if tokens.Kinds[methodNameIndex] == 0 {
        // AN EXPLICIT INTERFACE IMPLEMENTATION'S NAME IS THE WHOLE QUALIFIED SPELLING, and it is the
        // key every member table stores the member under — which is what makes it unreachable through
        // the declaring type while an implicit member of the same simple name keeps its own key.
        qualifiedNameEnd := ExplicitInterfaceMemberNameEnd(tokens.Kinds, tokens.Count, methodNameIndex + 1)
        if qualifiedNameEnd > methodNameIndex + 1 {
            return ParserDeclarationMemberNameText(source, tokens.Starts[methodNameIndex], tokens.Starts[qualifiedNameEnd - 1] + tokens.ValueLengths[qualifiedNameEnd - 1] - tokens.Starts[methodNameIndex])
        }

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

// A VALUE MEMBER'S NAME AS DECLARED, qualified when it is an explicit interface implementation. The
// twin of `ColumnarStructMethodMemberNameText`, and for the same reason: the name is stored as a
// token INDEX, so every reader has to recompute the same extent.
func ColumnarStructPropertyMemberNameText(source: string, tokens: ColumnarStructTokenTable, propNameIndex: int): string {
    if propNameIndex < 0 || propNameIndex >= tokens.Count || tokens.Kinds[propNameIndex] != 0 {
        return ""
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    nameEnd := ParseDeclarationMemberNameEnd(declarationTokens, tokens.Count, propNameIndex)
    return ParserDeclarationMemberNameText(source, tokens.Starts[propNameIndex], ParseDeclarationMemberNameSpanLength(declarationTokens, propNameIndex, nameEnd))
}

func ColumnarStructMethodFlagIsStatic(flags: int): bool {
    return (flags & 16) != 0
}

// `Modifiers.Async` (2048, DeclarationEnums.nl) in the method flag word this file writes, named
// beside its `static` and `LibraryImport` siblings so no caller has to know the bit.
func ColumnarStructMethodFlagIsAsync(flags: int): bool {
    return (flags & 2048) != 0
}

// `Modifiers.Abstract` (64, DeclarationEnums.nl) in the method flag word this file writes. An
// abstract member is the ONE ordinary managed member that has no body at all: the declaration is
// the whole member, and the `{ … }` a body scan would demand is not merely absent, it is forbidden.
// The word's meaning is decided here, beside the scan that writes it, for the same reason every
// other bit's is.
func ColumnarStructMethodFlagIsAbstract(flags: int): bool {
    return (flags & 64) != 0
}

// `Modifiers.Virtual` (32) — the member declares a NEW virtual slot with a body.
func ColumnarStructMethodFlagIsVirtual(flags: int): bool {
    return (flags & 32) != 0
}

func ColumnarStructMethodMemberNamesSupported(source: string, tokens: ColumnarStructTokenTable, scratch: ColumnarStructScratchTable, outputs: ColumnarStructOutputTable, fieldCount: int, methodCount: int): int {
    if methodCount < 0 {
        return 0
    }

    i := 0
    while i < methodCount {
        methodName := ColumnarStructMethodMemberNameText(source, tokens, outputs.MethodFuncIndices[i])
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
            otherMethodName := ColumnarStructMethodMemberNameText(source, tokens, outputs.MethodFuncIndices[j])
            if otherMethodName == "" {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarStructPropertyMemberNamesDistinct(source: string, tokens: ColumnarStructTokenTable, scratch: ColumnarStructScratchTable, outputs: ColumnarStructOutputTable, fieldCount: int, methodCount: int, propCount: int): int {
    if propCount < 0 {
        return 0
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    propertyResult := new ParserDeclarationResultTable(new int[](6))

    i := 0
    while i < propCount {
        if outputs.PropStaticFlags[i] < 0 || outputs.PropStaticFlags[i] > 31 {
            return 0
        }

        propNameIndex := outputs.PropIndices[i]
        if propNameIndex < 0 || propNameIndex >= tokens.Count || tokens.Kinds[propNameIndex] != 0 {
            return 0
        }

        propName := ColumnarStructPropertyMemberNameText(source, tokens, propNameIndex)
        if propName == "" {
            return 0
        }

        accessorKind := ParsePropertyAccessorInfoCore(source, declarationTokens, tokens.Count, propNameIndex, propertyResult)
        if accessorKind < 0 || accessorKind > 1 {
            return 0
        }

        // AN EXPLICIT VALUE MEMBER'S ACCESSORS CARRY THE QUALIFICATION TOO — the BCL spells them
        // `System.Collections.IList.get_Item` beside `System.Collections.IList.Item` — so the prefix
        // goes on the SIMPLE name, inside the qualification. Building `get_Interface.Member` would
        // compare against a name no member can have, and the collision would go unseen.
        propQualifier := ExplicitInterfaceMemberFacts.QualifierOf(propName)
        propSimpleName := ExplicitInterfaceMemberFacts.SimpleNameOf(propName)
        getAccessorName := "get_" + propSimpleName
        setAccessorName := "set_" + propSimpleName
        if propQualifier != "" {
            getAccessorName = ExplicitInterfaceMemberFacts.MetadataAccessorName(propQualifier, "get_", propSimpleName)
            setAccessorName = ExplicitInterfaceMemberFacts.MetadataAccessorName(propQualifier, "set_", propSimpleName)
        }

        f := 0
        while f < fieldCount {
            if scratch.FieldNameStarts[f] < 0 || scratch.FieldNameLengths[f] <= 0 {
                return 0
            }

            if propName == ParserDeclarationMemberNameText(source, scratch.FieldNameStarts[f], scratch.FieldNameLengths[f]) {
                return 0
            }

            f = f + 1
        }

        m := 0
        while m < methodCount {
            methodName := ColumnarStructMethodMemberNameText(source, tokens, outputs.MethodFuncIndices[m])
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
            if outputs.PropStaticFlags[j] < 0 || outputs.PropStaticFlags[j] > 31 {
                return 0
            }

            otherPropNameIndex := outputs.PropIndices[j]
            if otherPropNameIndex < 0 || otherPropNameIndex >= tokens.Count || tokens.Kinds[otherPropNameIndex] != 0 {
                return 0
            }

            if propName == ColumnarStructPropertyMemberNameText(source, tokens, otherPropNameIndex) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}
