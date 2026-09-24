// THE COLUMNAR UNION, ENUM, INTERFACE AND PROPERTY INFO KERNELS.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.
class ColumnarUnionTokenTable {
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

class ColumnarUnionScratchTable {
    CaseNameStarts: int[]
    CaseNameLengths: int[]
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    constructor(caseNameStarts: int[], caseNameLengths: int[], fieldNameStarts: int[], fieldNameLengths: int[], fieldTypeStarts: int[], fieldTypeLengths: int[], typeParamStarts: int[], typeParamLengths: int[]) {
        CaseNameStarts = caseNameStarts
        CaseNameLengths = caseNameLengths
        FieldNameStarts = fieldNameStarts
        FieldNameLengths = fieldNameLengths
        FieldTypeStarts = fieldTypeStarts
        FieldTypeLengths = fieldTypeLengths
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
    }
}

class ColumnarUnionTextOutputTable {
    WhereOwnerTexts: string[]
    WhereItemCodes: int[]
    WhereTypeTexts: string[]
    CaseNameTexts: string[]
    CaseFieldCounts: int[]
    FieldNameTexts: string[]
    FieldTypeTexts: string[]
    TypeParamTexts: string[]
    UnionNameTexts: string[]
    constructor(caseNameTexts: string[], caseFieldCounts: int[], fieldNameTexts: string[], fieldTypeTexts: string[], typeParamTexts: string[], unionNameTexts: string[], whereOwnerTexts: string[], whereItemCodes: int[], whereTypeTexts: string[]) {
        CaseNameTexts = caseNameTexts
        CaseFieldCounts = caseFieldCounts
        FieldNameTexts = fieldNameTexts
        FieldTypeTexts = fieldTypeTexts
        TypeParamTexts = typeParamTexts
        UnionNameTexts = unionNameTexts
        WhereOwnerTexts = whereOwnerTexts
        WhereItemCodes = whereItemCodes
        WhereTypeTexts = whereTypeTexts
    }
}

class ColumnarUnionResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

// Mirrors UnionValueLayout.IsValueStructEmittable on the columnar union shape. A small, closed,
// payload-free, non-generic union emits as its allocation-free PUBLIC readonly tag struct. The
// columnar input builder consults this kernel so it can select the value-struct ABI instead of
// heap case classes. Eligibility holds when the
// union is non-generic, has 1..MaxValueStructCases (16) cases, and every case is payload-free (caseFieldCounts[c]
// is case c's field count; a non-zero count means the case carries a payload). Returns 1 when eligible, else 0.

// Product columnar enum parser wrapper. It keeps span/value-literal scratch columns inside N# and exposes only
// the enum/member text plus resolved int values needed by the columnar input builder.

class ColumnarEnumTokenTable {
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

class ColumnarEnumMemberScratchTable {
    NameStarts: int[]
    NameLengths: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    HasValue: int[]
    NameTokens: int[]
    constructor(nameStarts: int[], nameLengths: int[], valueStarts: int[], valueLengths: int[], hasValue: int[], nameTokens: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        HasValue = hasValue
        NameTokens = nameTokens
    }
}

class ColumnarEnumTextOutputTable {
    MemberNameTexts: string[]
    MemberValues: int[]
    MemberStringValues: string[]
    EnumNameTexts: string[]
    constructor(memberNameTexts: string[], memberValues: int[], memberStringValues: string[], enumNameTexts: string[]) {
        MemberNameTexts = memberNameTexts
        MemberValues = memberValues
        MemberStringValues = memberStringValues
        EnumNameTexts = enumNameTexts
    }
}

class ColumnarEnumResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

// Product columnar interface parser wrapper. It keeps base-name span scratch columns inside N#,
// rejects unsupported default-method local functions, and exposes only the interface/base text
// plus method signature rows needed by the columnar input builder.

class ColumnarInterfaceTokenTable {
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

class ColumnarInterfaceBaseScratchTable {
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    constructor(baseNameStarts: int[], baseNameLengths: int[], typeParamStarts: int[], typeParamLengths: int[]) {
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
    }
}

class ColumnarInterfaceOutputTable {
    WhereOwnerTexts: string[]
    WhereItemCodes: int[]
    WhereTypeTexts: string[]
    MethodFuncIndices: int[]
    BaseNameTexts: string[]
    InterfaceNameTexts: string[]
    MethodNameTexts: string[]
    MethodReturnTexts: string[]
    MethodParamCounts: int[]
    MethodBodyFlags: int[]
    MethodParamNameTexts: string[]
    MethodParamTypeTexts: string[]
    MethodParamModifierKinds: int[]
    TypeParamTexts: string[]
    // `event Name: DelegateType` members, in written order: the name and the handler type's canonical
    // text, which is everything an interface event is — two abstract accessor slots and an `EventInfo`.
    EventNameTexts: string[]
    EventTypeTexts: string[]
    // `Name: Type` members, in written order: the name and the member type's canonical text, which is
    // everything an interface value member is — one abstract `get_Name` slot and a `PropertyInfo`.
    PropertyNameTexts: string[]
    PropertyTypeTexts: string[]
    constructor(methodFuncIndices: int[], baseNameTexts: string[], interfaceNameTexts: string[], methodNameTexts: string[], methodReturnTexts: string[], methodParamCounts: int[], methodBodyFlags: int[], methodParamNameTexts: string[], methodParamTypeTexts: string[], methodParamModifierKinds: int[], typeParamTexts: string[], whereOwnerTexts: string[], whereItemCodes: int[], whereTypeTexts: string[], eventNameTexts: string[]? = null, eventTypeTexts: string[]? = null, propertyNameTexts: string[]? = null, propertyTypeTexts: string[]? = null) {
        MethodFuncIndices = methodFuncIndices
        BaseNameTexts = baseNameTexts
        InterfaceNameTexts = interfaceNameTexts
        MethodNameTexts = methodNameTexts
        MethodReturnTexts = methodReturnTexts
        MethodParamCounts = methodParamCounts
        MethodBodyFlags = methodBodyFlags
        MethodParamNameTexts = methodParamNameTexts
        MethodParamTypeTexts = methodParamTypeTexts
        MethodParamModifierKinds = methodParamModifierKinds
        TypeParamTexts = typeParamTexts
        WhereOwnerTexts = whereOwnerTexts
        WhereItemCodes = whereItemCodes
        WhereTypeTexts = whereTypeTexts
        EventNameTexts = eventNameTexts ?? new string[](0)
        EventTypeTexts = eventTypeTexts ?? new string[](0)
        PropertyNameTexts = propertyNameTexts ?? new string[](0)
        PropertyTypeTexts = propertyTypeTexts ?? new string[](0)
    }
}

class ColumnarInterfaceResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

// Product columnar property parser wrapper. It composes property accessor/type parsing with getter/setter
// statement-node rowsets so the host adapter no longer binds statement parsing for property bodies.

class ColumnarPropertyTokenTable {
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

class ColumnarPropertyTextTable {
    NameTexts: string[]
    TypeTexts: string[]
    constructor(nameTexts: string[], typeTexts: string[]) {
        NameTexts = nameTexts
        TypeTexts = typeTexts
    }
}

class ColumnarPropertyBodyTable {
    NodeKinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    SpanStarts: int[]
    SpanLengths: int[]
    constructor(nodeKinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], childIndices: int[], spanStarts: int[], spanLengths: int[]) {
        NodeKinds = nodeKinds
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
        SpanStarts = spanStarts
        SpanLengths = spanLengths
    }
}

class ColumnarPropertyResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

func ParseColumnarUnionInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, unionIndex: int, outCaseNameTexts: string[], outCaseFieldCounts: int[], outFieldNameTexts: string[], outFieldTypeTexts: string[], outTypeParamTexts: string[], outUnionNameTexts: string[], outWhereOwnerTexts: string[], outWhereItemCodes: int[], outWhereTypeTexts: string[], outResult: int[]): int {
    tokens := new ColumnarUnionTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    scratch := new ColumnarUnionScratchTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    outputs := new ColumnarUnionTextOutputTable(outCaseNameTexts, outCaseFieldCounts, outFieldNameTexts, outFieldTypeTexts, outTypeParamTexts, outUnionNameTexts, outWhereOwnerTexts, outWhereItemCodes, outWhereTypeTexts)
    result := new ColumnarUnionResultTable(outResult)
    return ParseColumnarUnionInfoCore(source, tokens, unionIndex, scratch, outputs, result)
}

func ParseColumnarUnionInfoCore(source: string, tokens: ColumnarUnionTokenTable, unionIndex: int, scratch: ColumnarUnionScratchTable, outputs: ColumnarUnionTextOutputTable, result: ColumnarUnionResultTable): int {
    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    unionWhere := new ParserDeclarationWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    decl := new UnionDeclarationTable(scratch.CaseNameStarts, scratch.CaseNameLengths, outputs.CaseFieldCounts, scratch.FieldNameStarts, scratch.FieldNameLengths, scratch.FieldTypeStarts, scratch.FieldTypeLengths, scratch.TypeParamStarts, scratch.TypeParamLengths, unionWhere)
    declarationResult := new ParserDeclarationResultTable(result.Values)
    caseCount := ParseUnionDeclarationCore(declarationTokens, tokens.Count, unionIndex, decl, declarationResult)
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

    if ParserDeclarationNameSpansDistinct(source, scratch.TypeParamStarts, scratch.TypeParamLengths, typeParamCount) == 0 {
        return -1
    }

    if ParserDeclarationNameSpansDistinct(source, scratch.CaseNameStarts, scratch.CaseNameLengths, caseCount) == 0 {
        return -1
    }

    if ColumnarUnionCaseFieldNamesDistinct(source, scratch, outputs, caseCount) == 0 {
        return -1
    }

    unionName := ParserDeclarationQualifiedNameText(source, declarationTokens, tokens.Count, unionIndex, result.Values[0], result.Values[1])
    if unionName == "" {
        return -1
    }

    outputs.UnionNameTexts[0] = unionName

    // The constraint rows, rendered as the struct and interface cores render them.
    unionWhereCount := 0
    if result.Values.Length > 5 {
        unionWhereCount = result.Values[5]
    }

    if unionWhereCount > outputs.WhereOwnerTexts.Length || unionWhereCount > outputs.WhereItemCodes.Length || unionWhereCount > outputs.WhereTypeTexts.Length {
        return -1
    }

    w := 0
    while w < unionWhereCount {
        ownerName := ParserDeclarationSpanText(source, decl.Where.NameStarts[w], decl.Where.NameLengths[w])
        if ownerName == "" {
            return -1
        }

        outputs.WhereOwnerTexts[w] = ownerName
        outputs.WhereItemCodes[w] = decl.Where.ItemCodes[w]
        constraintText := ""
        if decl.Where.ItemCodes[w] == 0 {
            constraintText = ParserDeclarationCanonicalTypeText(source, decl.Where.TypeStarts[w], decl.Where.TypeLengths[w])
            if constraintText == "" {
                return -1
            }
        }

        outputs.WhereTypeTexts[w] = constraintText
        w = w + 1
    }

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

func ColumnarUnionCaseFieldNamesDistinct(source: string, scratch: ColumnarUnionScratchTable, outputs: ColumnarUnionTextOutputTable, caseCount: int): int {
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

func ParseColumnarEnumInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameTexts: string[], outMemberValues: int[], outMemberStringValues: string[], outEnumNameTexts: string[], outResult: int[], outMemberDeclTokens: int[]): int {
    tokens := new ColumnarEnumTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    scratch := new ColumnarEnumMemberScratchTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), outMemberDeclTokens)
    outputs := new ColumnarEnumTextOutputTable(outNameTexts, outMemberValues, outMemberStringValues, outEnumNameTexts)
    result := new ColumnarEnumResultTable(outResult)
    return ParseColumnarEnumInfoCore(source, tokens, enumIndex, scratch, outputs, result)
}

func ParseColumnarEnumInfoCore(source: string, tokens: ColumnarEnumTokenTable, enumIndex: int, scratch: ColumnarEnumMemberScratchTable, outputs: ColumnarEnumTextOutputTable, result: ColumnarEnumResultTable): int {
    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    members := new EnumMemberTable(scratch.NameStarts, scratch.NameLengths, scratch.ValueStarts, scratch.ValueLengths, scratch.HasValue, scratch.NameTokens)
    declarationResult := new ParserDeclarationResultTable(result.Values)
    memberCount := ParseEnumDeclarationCore(declarationTokens, tokens.Count, enumIndex, members, declarationResult)
    if memberCount < 0 {
        return -1
    }

    if ParserDeclarationNameSpansDistinct(source, scratch.NameStarts, scratch.NameLengths, memberCount) == 0 {
        return -1
    }

    backingKind := ColumnarEnumBackingKind(source, tokens, enumIndex, scratch, memberCount)
    if backingKind < 0 {
        return -1
    }

    if result.Values.Length > 2 {
        result.Values[2] = backingKind
    }

    if backingKind == 0 {
        memberValues := new EnumMemberValueTable(outputs.MemberValues)
        if !ParseEnumMemberValuesCore(source, members, memberCount, memberValues) {
            return -1
        }
    } else if !ColumnarEnumStringMemberValues(source, scratch, memberCount, outputs) {
        return -1
    }

    if outputs.EnumNameTexts.Length < 1 || memberCount > outputs.MemberNameTexts.Length {
        return -1
    }

    enumName := ParserDeclarationQualifiedNameText(source, declarationTokens, tokens.Count, enumIndex, result.Values[0], result.Values[1])
    if enumName == "" {
        return -1
    }

    containerName := ParserDeclarationDirectContainingTypeNameText(source, declarationTokens, tokens.Count, enumIndex)
    if containerName != "" {
        simpleName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
        if simpleName == "" {
            return -1
        }

        enumName = containerName + "." + simpleName
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

func ColumnarEnumBackingKind(source: string, tokens: ColumnarEnumTokenTable, enumIndex: int, scratch: ColumnarEnumMemberScratchTable, memberCount: int): int {
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
            valueKind := ColumnarEnumValueTokenKind(tokens, scratch.ValueStarts[i])
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

func ColumnarEnumValueTokenKind(tokens: ColumnarEnumTokenTable, valueStart: int): int {
    i := 0
    while i < tokens.Count {
        if tokens.Starts[i] == valueStart {
            return tokens.Kinds[i]
        }

        i = i + 1
    }

    return -1
}

func ColumnarEnumStringMemberValues(source: string, scratch: ColumnarEnumMemberScratchTable, memberCount: int, outputs: ColumnarEnumTextOutputTable): bool {
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

func ParseColumnarInterfaceInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameTexts: string[], outInterfaceNameTexts: string[], outMethodNameTexts: string[], outMethodReturnTexts: string[], outMethodParamCounts: int[], outMethodBodyFlags: int[], outMethodParamNameTexts: string[], outMethodParamTypeTexts: string[], outMethodParamModifierKinds: int[], outTypeParamTexts: string[], outWhereOwnerTexts: string[], outWhereItemCodes: int[], outWhereTypeTexts: string[], outResult: int[], outEventNameTexts: string[], outEventTypeTexts: string[], outPropertyNameTexts: string[], outPropertyTypeTexts: string[]): int {
    tokens := new ColumnarInterfaceTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    scratch := new ColumnarInterfaceBaseScratchTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    outputs := new ColumnarInterfaceOutputTable(outMethodFuncIndices, outBaseNameTexts, outInterfaceNameTexts, outMethodNameTexts, outMethodReturnTexts, outMethodParamCounts, outMethodBodyFlags, outMethodParamNameTexts, outMethodParamTypeTexts, outMethodParamModifierKinds, outTypeParamTexts, outWhereOwnerTexts, outWhereItemCodes, outWhereTypeTexts, outEventNameTexts, outEventTypeTexts, outPropertyNameTexts, outPropertyTypeTexts)
    result := new ColumnarInterfaceResultTable(outResult)
    return ParseColumnarInterfaceInfoCore(source, tokens, interfaceIndex, scratch, outputs, result)
}

func ParseColumnarInterfaceInfoCore(source: string, tokens: ColumnarInterfaceTokenTable, interfaceIndex: int, scratch: ColumnarInterfaceBaseScratchTable, outputs: ColumnarInterfaceOutputTable, result: ColumnarInterfaceResultTable): int {
    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    baseOutputs := new InterfaceSignatureBaseOutputTable(scratch.BaseNameStarts, scratch.BaseNameLengths, outputs.BaseNameTexts, outputs.InterfaceNameTexts, outputs.TypeParamTexts, outputs.WhereOwnerTexts, outputs.WhereItemCodes, outputs.WhereTypeTexts, outputs.EventNameTexts, outputs.EventTypeTexts, outputs.PropertyNameTexts, outputs.PropertyTypeTexts)
    methodOutputs := new InterfaceSignatureMethodOutputTable(outputs.MethodFuncIndices, outputs.MethodNameTexts, outputs.MethodReturnTexts, outputs.MethodParamCounts, outputs.MethodBodyFlags, outputs.MethodParamNameTexts, outputs.MethodParamTypeTexts, outputs.MethodParamModifierKinds)
    typeStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserNodeTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    children := new ParserChildIndexTable(new int[](tokens.Count + 1))
    canonicalNodes := new TypeReferenceCanonicalTable(nodes.Kinds, nodes.ValueStarts, nodes.ValueLengths, nodes.ChildStart, nodes.ChildCount, children.Indices)
    tupleNodes := new InterfaceSignatureTupleNodeTable(nodes.Kinds, nodes.ChildStart, nodes.ChildCount, children.Indices)
    parameters := new ParserFunctionParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    signatureResult := new ParserResultTable(new int[](8))
    interfaceResult := new ParserResultTable(result.Values)
    methodCount := ParseInterfaceDeclarationSignatureInfoCore(source, signatureTokens, tokens.Count, interfaceIndex, baseOutputs, methodOutputs, typeStack, nodes, children, canonicalNodes, tupleNodes, parameters, typeParams, whereItems, signatureResult, interfaceResult)
    if methodCount < 0 {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    interfaceName := ParserDeclarationQualifiedNameText(source, declarationTokens, tokens.Count, interfaceIndex, result.Values[0], result.Values[1])
    if interfaceName == "" {
        return -1
    }

    outputs.InterfaceNameTexts[0] = interfaceName

    if ColumnarInterfaceBaseNamesDistinct(outputs, result.Values[2]) == 0 {
        return -1
    }

    if ColumnarInterfaceMethodNamesDistinct(outputs, methodCount) == 0 {
        return -1
    }

    if ColumnarInterfaceMethodParamNamesDistinct(outputs, methodCount) == 0 {
        return -1
    }

    if ColumnarInterfaceMemberNamesDistinct(outputs, methodCount, result.Values[7], result.Values[8]) == 0 {
        return -1
    }

    localStatus := InterfaceDefaultMethodLocalFunctionStatus(source, tokens, outputs, methodCount)
    if localStatus != 0 {
        return -1
    }

    return methodCount
}

func ColumnarInterfaceBaseNamesDistinct(outputs: ColumnarInterfaceOutputTable, baseCount: int): int {
    if baseCount < 0 {
        return 0
    }

    i := 0
    while i < baseCount {
        if outputs.BaseNameTexts[i] == "" {
            return 0
        }

        j := i + 1
        while j < baseCount {
            if outputs.BaseNameTexts[i] == outputs.BaseNameTexts[j] {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarInterfaceMethodNamesDistinct(outputs: ColumnarInterfaceOutputTable, methodCount: int): int {
    if methodCount < 0 {
        return 0
    }

    i := 0
    while i < methodCount {
        if outputs.MethodNameTexts[i] == "" {
            return 0
        }

        j := i + 1
        while j < methodCount {
            if outputs.MethodNameTexts[i] == outputs.MethodNameTexts[j] {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

// ONE MEMBER NAMESPACE. A `func`, an `event` and a value member of one interface cannot share a name:
// each lowers to methods on the same type, and two of them would collide in metadata rather than
// overload. A value member's own name must also be non-empty, which the scan already guarantees and
// this re-reads so a malformed row cannot reach the emitter.
func ColumnarInterfaceMemberNamesDistinct(outputs: ColumnarInterfaceOutputTable, methodCount: int, eventCount: int, propertyCount: int): int {
    if eventCount < 0 || propertyCount < 0 || eventCount > outputs.EventNameTexts.Length || propertyCount > outputs.PropertyNameTexts.Length {
        return 0
    }

    i := 0
    while i < propertyCount {
        if outputs.PropertyNameTexts[i] == "" {
            return 0
        }

        j := i + 1
        while j < propertyCount {
            if outputs.PropertyNameTexts[i] == outputs.PropertyNameTexts[j] {
                return 0
            }

            j = j + 1
        }

        m := 0
        while m < methodCount {
            if outputs.PropertyNameTexts[i] == outputs.MethodNameTexts[m] {
                return 0
            }

            m = m + 1
        }

        e := 0
        while e < eventCount {
            if outputs.PropertyNameTexts[i] == outputs.EventNameTexts[e] {
                return 0
            }

            e = e + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarInterfaceMethodParamNamesDistinct(outputs: ColumnarInterfaceOutputTable, methodCount: int): int {
    if methodCount < 0 {
        return 0
    }

    paramOffset := 0
    m := 0
    while m < methodCount {
        paramCount := outputs.MethodParamCounts[m]
        if paramCount < 0 {
            return 0
        }

        i := 0
        while i < paramCount {
            leftIndex := paramOffset + i
            if leftIndex < 0 || leftIndex >= outputs.MethodParamNameTexts.Length || outputs.MethodParamNameTexts[leftIndex] == "" {
                return 0
            }

            j := i + 1
            while j < paramCount {
                rightIndex := paramOffset + j
                if rightIndex < 0 || rightIndex >= outputs.MethodParamNameTexts.Length {
                    return 0
                }

                if outputs.MethodParamNameTexts[leftIndex] == outputs.MethodParamNameTexts[rightIndex] {
                    return 0
                }

                j = j + 1
            }

            i = i + 1
        }

        paramOffset = paramOffset + paramCount
        m = m + 1
    }

    return 1
}

func InterfaceDefaultMethodLocalFunctionStatus(source: string, tokens: ColumnarInterfaceTokenTable, outputs: ColumnarInterfaceOutputTable, methodCount: int): int {
    functionTokens := new ColumnarFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count)
    cap := tokens.Count + 1
    signatureOutputs := new ColumnarFunctionSignatureOutputTable(new string[](1), new string[](1), new string[](cap), new string[](cap), new int[](cap), new int[](cap), new string[](cap), new int[](cap), new string[](cap), new string[](cap), new string[](1), new string[](cap), new string[](cap), new int[](cap), new int[](cap), new string[](cap))
    body := new ColumnarFunctionBodyTable(new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap))
    locals := new ColumnarFunctionLocalTable(new int[](cap), new int[](cap))
    result := new ColumnarFunctionResultTable(new int[](9))

    for i := 0; i < methodCount; i++ {
        bodyFlag := outputs.MethodBodyFlags[i]
        if bodyFlag == 0 {
            continue
        }

        if bodyFlag != 1 {
            return -1
        }

        paramCount := ParseColumnarFunctionInfoCore(source, functionTokens, outputs.MethodFuncIndices[i], 0, signatureOutputs, body, locals, result)
        if paramCount < 0 {
            return -1
        }

        if result.Values[8] > 0 {
            return 1
        }
    }

    return 0
}

func ParseColumnarPropertyInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, propIndex: int, outNameTexts: string[], outTypeTexts: string[], outGetNodeKinds: int[], outGetValueStarts: int[], outGetValueLengths: int[], outGetChildStart: int[], outGetChildCount: int[], outGetChildIndices: int[], outGetSpanStarts: int[], outGetSpanLengths: int[], outSetNodeKinds: int[], outSetValueStarts: int[], outSetValueLengths: int[], outSetChildStart: int[], outSetChildCount: int[], outSetChildIndices: int[], outSetSpanStarts: int[], outSetSpanLengths: int[], outResult: int[]): int {
    tokens := new ColumnarPropertyTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    texts := new ColumnarPropertyTextTable(outNameTexts, outTypeTexts)
    getBody := new ColumnarPropertyBodyTable(outGetNodeKinds, outGetValueStarts, outGetValueLengths, outGetChildStart, outGetChildCount, outGetChildIndices, outGetSpanStarts, outGetSpanLengths)
    setBody := new ColumnarPropertyBodyTable(outSetNodeKinds, outSetValueStarts, outSetValueLengths, outSetChildStart, outSetChildCount, outSetChildIndices, outSetSpanStarts, outSetSpanLengths)
    result := new ColumnarPropertyResultTable(outResult)
    return ParseColumnarPropertyInfoCore(source, tokens, propIndex, texts, getBody, setBody, result)
}

func ParseColumnarPropertyInfoCore(source: string, tokens: ColumnarPropertyTokenTable, propIndex: int, texts: ColumnarPropertyTextTable, getBody: ColumnarPropertyBodyTable, setBody: ColumnarPropertyBodyTable, result: ColumnarPropertyResultTable): int {
    if result.Values.Length < 10 {
        return -1
    }

    if texts.NameTexts.Length < 1 || texts.TypeTexts.Length < 1 {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    propertyResult := new ParserDeclarationResultTable(new int[](6))
    accessorKind := ParsePropertyAccessorInfoCore(source, declarationTokens, tokens.Count, propIndex, propertyResult)
    if accessorKind < 0 {
        return -1
    }

    nameText := ParserDeclarationMemberNameText(source, propertyResult.Values[0], propertyResult.Values[1])
    if nameText == "" {
        return -1
    }

    typeText := ParserDeclarationCanonicalTypeText(source, propertyResult.Values[2], propertyResult.Values[3])
    if typeText == "" {
        return -1
    }

    texts.NameTexts[0] = nameText
    texts.TypeTexts[0] = typeText

    getBodyBrace := propertyResult.Values[4]
    if getBodyBrace < 0 || getBodyBrace >= tokens.Count || (tokens.Kinds[getBodyBrace] != 129 && tokens.Kinds[getBodyBrace] != 120) {
        return -1
    }

    getBodyResult := new ColumnarPropertyResultTable(new int[](2))
    getBodyNodeCount := 0
    if tokens.Kinds[getBodyBrace] == 129 {
        getBodyNodeCount = ParseColumnarPropertyBodyNodesCore(source, tokens, getBodyBrace, getBody, getBodyResult)
    } else {
        getBodyNodeCount = ParseColumnarPropertyExpressionBodyNodesCore(source, tokens, getBodyBrace, getBody, getBodyResult)
    }

    if getBodyNodeCount <= 0 {
        return -1
    }

    getBodyRoot := getBodyResult.Values[0]
    if getBodyRoot < 0 || getBodyRoot >= getBodyNodeCount {
        return -1
    }

    getLocalFunctionStatus := ColumnarPropertyDirectLocalFunctionStatus(tokens, getBody, getBodyRoot)
    if getLocalFunctionStatus != 0 {
        return -1
    }

    setBodyRoot := -1
    setBodyNodeCount := 0
    if accessorKind == 1 {
        setBodyBrace := propertyResult.Values[5]
        if setBodyBrace < 0 || setBodyBrace >= tokens.Count || tokens.Kinds[setBodyBrace] != 129 {
            return -1
        }

        setBodyResult := new ColumnarPropertyResultTable(new int[](2))
        setBodyNodeCount = ParseColumnarPropertyBodyNodesCore(source, tokens, setBodyBrace, setBody, setBodyResult)
        if setBodyNodeCount <= 0 {
            return -1
        }

        setBodyRoot = setBodyResult.Values[0]
        if setBodyRoot < 0 || setBodyRoot >= setBodyNodeCount {
            return -1
        }

        setLocalFunctionStatus := ColumnarPropertyDirectLocalFunctionStatus(tokens, setBody, setBodyRoot)
        if setLocalFunctionStatus != 0 {
            return -1
        }
    } else if accessorKind != 0 {
        return -1
    }

    result.Values[0] = propertyResult.Values[0]
    result.Values[1] = propertyResult.Values[1]
    result.Values[2] = propertyResult.Values[2]
    result.Values[3] = propertyResult.Values[3]
    result.Values[4] = getBodyBrace
    result.Values[5] = propertyResult.Values[5]
    result.Values[6] = getBodyRoot
    result.Values[7] = getBodyNodeCount
    result.Values[8] = setBodyRoot
    result.Values[9] = setBodyNodeCount
    return accessorKind
}

func ColumnarPropertyDirectLocalFunctionStatus(tokens: ColumnarPropertyTokenTable, body: ColumnarPropertyBodyTable, rootBlock: int): int {
    localTokens := new LocalFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.Count)
    localNodes := new LocalFunctionNodeTable(body.NodeKinds, body.ValueStarts, body.ChildStart, body.ChildCount, body.ChildIndices)
    cap := tokens.Count + 1
    localResults := new LocalFunctionResultTable(new int[](cap), new int[](cap))
    localFunctionCount := DirectLocalFunctionTokenIndicesCore(localTokens, localNodes, rootBlock, localResults)
    if localFunctionCount < 0 {
        return -1
    }

    if localFunctionCount > 0 {
        return 1
    }

    return 0
}

func ParseColumnarPropertyBodyNodesCore(source: string, tokens: ColumnarPropertyTokenTable, bodyBrace: int, body: ColumnarPropertyBodyTable, result: ColumnarPropertyResultTable): int {
    statementTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    argStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    children := new ParserChildIndexTable(body.ChildIndices)
    statementResult := new ParserResultTable(result.Values)
    return ParseStatementNodesCore(source, statementTokens, tokens.Count, bodyBrace, argStack, nodes, children, statementResult)
}

func ParseColumnarPropertyExpressionBodyNodesCore(source: string, tokens: ColumnarPropertyTokenTable, arrowIndex: int, body: ColumnarPropertyBodyTable, result: ColumnarPropertyResultTable): int {
    if arrowIndex < 0 || arrowIndex >= tokens.Count || tokens.Kinds[arrowIndex] != 120 || result.Values.Length < 2 {
        return -1
    }

    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    argStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    children := new ParserChildIndexTable(body.ChildIndices)
    st := new ParserState(arrowIndex + 1, 0, 0, 0, 0, 0)
    // `=> throw <exception>` is an expression body whose value is a throw (kind 83). The synthesized
    // `return` below still wraps it; the return owner recognises the shape and ends the path with
    // `throw` instead of a `ret` that would have nothing to return.
    valueRoot := ParseBodyValueOrThrowExpressionNode(expressionTokens, tokens.Count, st, argStack, nodes, children, 0)
    if valueRoot < 0 || st.Pos <= arrowIndex + 1 {
        return -1
    }

    childRunStart := st.ChildCursor
    AppendExpressionChild(st, children, valueRoot)
    valueEnd := nodes.SpanStarts[valueRoot] + nodes.SpanLengths[valueRoot]
    returnNode := EmitExpressionNode(st, nodes, 20, -1, 0, childRunStart, 1, tokens.Starts[arrowIndex], valueEnd - tokens.Starts[arrowIndex])
    result.Values[0] = returnNode
    result.Values[1] = st.Pos
    return st.NodeCursor
}
