import System.Text


// SIGNATURES: function, constructor, interface-member and local-function signatures, their parameter
// defaults, where-clauses and operator names.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.

// Parser slice 9: the first declaration-level recursive-descent kernel -- it COMPOSES the slice 6-8 type
// kernel (ParserTypeReferences.nl). Given a `func` keyword token index, ParseFunctionSignatureCore parses
// the function's signature -- name, parameter names + parameter type trees, and the return type tree.
// All parameter type trees and the return type tree share ONE columnar node table (the same table the
// type kernel fills), so each is an independent root within it; the shared `ParserState` (`st`) carries
// the node/child cursors across the per-type parses while st.Pos (pos) is repositioned to each type's start.
//
// Scope this slice: parameter NAME + parameter TYPE (any form the type kernel supports: Simple / Generic /
// Array / Nullable / Union / ByRef), the `: ReturnType` return type (or none), an optional generic
// TYPE-PARAMETER list `<T, U>` between the name and `(` — each type parameter is a bare Identifier (an
// inline constraint `<T: Base>` or any non-identifier form returns -1) — and zero or more generic
// CONSTRAINT clauses `where T: Item, Item ...` after the return type (D-17b). Each constraint ITEM is
// recorded as a flat row: the owning type parameter's name span plus a code — a type-tree ROOT (>= 0)
// parsed into the shared node table, or a special-constraint sentinel (-2 `class`, -3 `struct`,
// -4 `new()`). Clause grouping is NOT preserved (the host groups rows by owner name).
// Parameter modifiers `ref` (78) and `out` (79) wrap the parsed parameter type in a ByRef type node; `params`
// (82), `this` (42), `scoped 'a` lifetime annotations, `returns 'a` return-lifetime annotations,
// and attribute lists `[...]` are skipped. Supported one-token default values are
// materialized for CLR optional-parameter metadata; richer default expressions decline.
// Deferred (the corpus avoids them): `->` return-type syntax, `returns param(...)`/`returns heap(...)`,
// expression-bodied functions with full control-flow analysis, and non-literal default values.
//
// Output:
//   outNodeKinds/... (8 columns) + outChildIndices : the shared type node table (see ParserTypeReferences.nl)
//   outParamNameStarts[p], outParamNameLengths[p]  : byte span of parameter p's name
//   outParamTypeRoots[p]                            : node id of parameter p's type tree root
//   outTypeParamStarts[t], outTypeParamLengths[t]   : byte span of generic type parameter t's name
//   outWhereNameStarts[w], outWhereNameLengths[w]   : byte span of constraint row w's OWNER type-param name
//   outWhereItemCodes[w]                            : row w's constraint — a type root (>= 0) or a special
//                                                     sentinel (-2 class, -3 struct, -4 new())
//   outResult[0] = parameter count
//   outResult[1] = return type tree root node id, or -1 when the function has no return type
//   outResult[2] = total node count written to the shared table
//   outResult[3], outResult[4] = byte span (start, length) of the function name (start -1 if anonymous)
//   outResult[5] = generic type-parameter count (0 for a non-generic function)
//   outResult[6] = the token index immediately AFTER the parsed signature (after the `where` clauses when
//                  any exist, else after the return type / the `)`), so the host can verify what follows
//                  (the body `{`, a ctor `: this/base` initializer, or an unmodelled `=>` body to decline)
//   outResult[7] = constraint row count (0 for a function with no `where` clauses)
// Returns the parameter count, or -1 on a malformed signature / a parameter type the type kernel refuses.
//
// TokenType ordinals (Token.cs): Identifier 0, This 42, Ref 78, Out 79, Params 82, Assign 93, Func 7,
// New 41, Where 53, Class 8, Struct 9, Less 100, Greater 102, Colon 122, Comma 134, LeftParen 127,
// RightParen 128, LeftBrace 129, RightBrace 130, LeftBracket 131, RightBracket 132.
// Flattened ParseFunctionSignature*Into ABIs live in the parity corpus; product callers compose the
// typed cores in this file directly.
class FunctionSignatureInfoOutputTable {
    FunctionNameTexts: string[]
    ReturnTypeTexts: string[]
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ParamModifierKinds: int[]
    ParamDefaultKinds: int[]
    ParamDefaultTexts: string[]
    ParamTupleNameCounts: int[]
    ParamTupleNameTexts: string[]
    ReturnTupleNameTexts: string[]
    ReturnLabeledTypeTexts: string[]
    ParamLabeledTypeTexts: string[]
    TypeParamTexts: string[]
    TypeParamSpecials: int[]
    TypeParamConstraintCounts: int[]
    TypeParamConstraintTypeTexts: string[]
    constructor(functionNameTexts: string[], returnTypeTexts: string[], paramNameTexts: string[], paramTypeTexts: string[], paramModifierKinds: int[], paramDefaultKinds: int[], paramDefaultTexts: string[], paramTupleNameCounts: int[], paramTupleNameTexts: string[], returnTupleNameTexts: string[], returnLabeledTypeTexts: string[], paramLabeledTypeTexts: string[], typeParamTexts: string[], typeParamSpecials: int[], typeParamConstraintCounts: int[], typeParamConstraintTypeTexts: string[]) {
        FunctionNameTexts = functionNameTexts
        ReturnTypeTexts = returnTypeTexts
        ParamNameTexts = paramNameTexts
        ParamTypeTexts = paramTypeTexts
        ParamModifierKinds = paramModifierKinds
        ParamDefaultKinds = paramDefaultKinds
        ParamDefaultTexts = paramDefaultTexts
        ParamTupleNameCounts = paramTupleNameCounts
        ParamTupleNameTexts = paramTupleNameTexts
        ReturnTupleNameTexts = returnTupleNameTexts
        ReturnLabeledTypeTexts = returnLabeledTypeTexts
        ParamLabeledTypeTexts = paramLabeledTypeTexts
        TypeParamTexts = typeParamTexts
        TypeParamSpecials = typeParamSpecials
        TypeParamConstraintCounts = typeParamConstraintCounts
        TypeParamConstraintTypeTexts = typeParamConstraintTypeTexts
    }
}

class FunctionSignatureTupleNameScratchTable {
    Names: string[]
    constructor(names: string[]) {
        Names = names
    }
}

class FunctionSignatureNameSpanTable {
    Starts: int[]
    Lengths: int[]
    constructor(starts: int[], lengths: int[]) {
        Starts = starts
        Lengths = lengths
    }
}

class FunctionSignatureOwnerIndexTable {
    Indices: int[]
    constructor(indices: int[]) {
        Indices = indices
    }
}

class ParserFunctionParameterTable {
    NameStarts: int[]
    NameLengths: int[]
    TypeRoots: int[]
    constructor(nameStarts: int[], nameLengths: int[], typeRoots: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        TypeRoots = typeRoots
    }
}

class ParserFunctionTypeParameterTable {
    Starts: int[]
    Lengths: int[]
    constructor(starts: int[], lengths: int[]) {
        Starts = starts
        Lengths = lengths
    }
}

class ParserFunctionWhereTable {
    NameStarts: int[]
    NameLengths: int[]
    ItemCodes: int[]
    constructor(nameStarts: int[], nameLengths: int[], itemCodes: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        ItemCodes = itemCodes
    }
}

// Composed constructor-signature product core. ParserDeclarations.nl keeps the standalone constructor chain
// parser; this file owns the cross-file route that combines constructor parameter signatures, canonical type text,
// chaining initializer text, and body-brace validation for the columnar product adapter. The flattened
// ParseConstructorSignatureInfoInto ABI lives in the parity corpus.

class ConstructorSignatureOutputTable {
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ParamLabeledTypeTexts: string[]
    ArgKinds: int[]
    ArgStarts: int[]
    ArgLengths: int[]
    ArgTexts: string[]
    constructor(paramNameTexts: string[], paramTypeTexts: string[], paramLabeledTypeTexts: string[], argKinds: int[], argStarts: int[], argLengths: int[], argTexts: string[]) {
        ParamNameTexts = paramNameTexts
        ParamTypeTexts = paramTypeTexts
        ParamLabeledTypeTexts = paramLabeledTypeTexts
        ArgKinds = argKinds
        ArgStarts = argStarts
        ArgLengths = argLengths
        ArgTexts = argTexts
    }
}

// Composed interface-signature product core. ParserDeclarations.nl stays a standalone declaration parser; this
// file owns the cross-file routing that combines interface member indices, function-signature parsing, and canonical
// type text for the columnar product adapter. The flattened ParseInterfaceDeclarationSignatureInfoInto ABI lives
// in the parity corpus.

class InterfaceSignatureBaseOutputTable {
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    BaseNameTexts: string[]
    InterfaceNameTexts: string[]
    TypeParamTexts: string[]
    WhereOwnerTexts: string[]
    WhereItemCodes: int[]
    WhereTypeTexts: string[]
    EventNameTexts: string[]
    EventTypeTexts: string[]
    PropertyNameTexts: string[]
    PropertyTypeTexts: string[]
    constructor(baseNameStarts: int[], baseNameLengths: int[], baseNameTexts: string[], interfaceNameTexts: string[], typeParamTexts: string[], whereOwnerTexts: string[], whereItemCodes: int[], whereTypeTexts: string[], eventNameTexts: string[]? = null, eventTypeTexts: string[]? = null, propertyNameTexts: string[]? = null, propertyTypeTexts: string[]? = null) {
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
        BaseNameTexts = baseNameTexts
        InterfaceNameTexts = interfaceNameTexts
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

class InterfaceSignatureMethodOutputTable {
    FuncIndices: int[]
    NameTexts: string[]
    ReturnTexts: string[]
    ParamCounts: int[]
    BodyFlags: int[]
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ParamModifierKinds: int[]
    constructor(funcIndices: int[], nameTexts: string[], returnTexts: string[], paramCounts: int[], bodyFlags: int[], paramNameTexts: string[], paramTypeTexts: string[], paramModifierKinds: int[]) {
        FuncIndices = funcIndices
        NameTexts = nameTexts
        ReturnTexts = returnTexts
        ParamCounts = paramCounts
        BodyFlags = bodyFlags
        ParamNameTexts = paramNameTexts
        ParamTypeTexts = paramTypeTexts
        ParamModifierKinds = paramModifierKinds
    }
}

class InterfaceSignatureTupleNodeTable {
    Kinds: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    constructor(kinds: int[], childStart: int[], childCount: int[], childIndices: int[]) {
        Kinds = kinds
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
    }
}

// Local-function discovery core for product columnar routing. ParseStatementNodesCore already marks a local
// function declaration as statement kind 41 with the `func` keyword's source span; this core maps direct children
// of a function body block to their compact token indices in N#, keeping the adapter out of statement-table scans.
// The flattened DirectLocalFunctionTokenIndicesInto ABI lives in the parity corpus.

class LocalFunctionTokenTable {
    Kinds: int[]
    Starts: int[]
    Count: int
    constructor(kinds: int[], starts: int[], count: int) {
        Kinds = kinds
        Starts = starts
        Count = count
    }
}

class LocalFunctionNodeTable {
    Kinds: int[]
    ValueStarts: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    constructor(kinds: int[], valueStarts: int[], childStart: int[], childCount: int[], childIndices: int[]) {
        Kinds = kinds
        ValueStarts = valueStarts
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
    }
}

class LocalFunctionResultTable {
    NodeIndices: int[]
    FuncTokenIndices: int[]
    constructor(nodeIndices: int[], funcTokenIndices: int[]) {
        NodeIndices = nodeIndices
        FuncTokenIndices = funcTokenIndices
    }
}

func ParseFunctionSignatureInfoCore(source: string, tokens: ParserTokenTable, count: int, funcIndex: int, outputs: FunctionSignatureInfoOutputTable, typeStack: ParserArgumentStack, nodes: ParserNodeTable, children: ParserChildIndexTable, canonicalNodes: TypeReferenceCanonicalTable, parameters: ParserFunctionParameterTable, typeParams: ParserFunctionTypeParameterTable, whereItems: ParserFunctionWhereTable, signatureResult: ParserResultTable, ownerIndices: FunctionSignatureOwnerIndexTable, tupleNames: FunctionSignatureTupleNameScratchTable, result: ParserResultTable): int {
    if outputs.FunctionNameTexts.Length < 1 || outputs.ReturnTypeTexts.Length < 1 || result.Values.Length < 6 {
        return -1
    }

    paramCount := ParseFunctionSignatureCore(tokens, count, funcIndex, typeStack, nodes, children, parameters, typeParams, whereItems, signatureResult)
    if paramCount < 0 || signatureResult.Values[3] < 0 {
        return -1
    }

    bodyStart := signatureResult.Values[6]
    if bodyStart < 0 || bodyStart >= count {
        return -1
    }

    typeParamCount := signatureResult.Values[5]
    whereItemCount := signatureResult.Values[7]
    if paramCount > outputs.ParamNameTexts.Length || paramCount > outputs.ParamTypeTexts.Length || paramCount > outputs.ParamModifierKinds.Length || paramCount > outputs.ParamDefaultKinds.Length || paramCount > outputs.ParamDefaultTexts.Length || paramCount > outputs.ParamTupleNameCounts.Length {
        return -1
    }

    defaultCount := ParseFunctionParameterDefaultsCore(source, tokens, count, funcIndex, outputs)
    if defaultCount != paramCount {
        return -1
    }

    if typeParamCount > outputs.TypeParamTexts.Length || typeParamCount > outputs.TypeParamSpecials.Length || typeParamCount > outputs.TypeParamConstraintCounts.Length {
        return -1
    }

    declaredTypeParamNames := new FunctionSignatureNameSpanTable(typeParams.Starts, typeParams.Lengths)
    if ParserDeclarationNameSpansDistinct(source, declaredTypeParamNames.Starts, declaredTypeParamNames.Lengths, typeParamCount) == 0 {
        return -1
    }

    declaredParamNames := new FunctionSignatureNameSpanTable(parameters.NameStarts, parameters.NameLengths)
    if ParserDeclarationNameSpansDistinct(source, declaredParamNames.Starts, declaredParamNames.Lengths, paramCount) == 0 {
        return -1
    }

    functionName := ""
    if funcIndex < count && tokens.Kinds[funcIndex] == 85 {
        functionName = "op_Implicit"
    } else if funcIndex < count && tokens.Kinds[funcIndex] == 86 {
        functionName = "op_Explicit"
    } else if funcIndex + 2 < count && tokens.Kinds[funcIndex + 1] == 75 {
        functionName = FunctionSignatureOperatorClrName(tokens.Kinds[funcIndex + 2], paramCount)
    } else {
        functionName = ParserDeclarationMemberNameText(source, signatureResult.Values[3], signatureResult.Values[4])
    }

    if functionName == "" {
        return -1
    }

    outputs.FunctionNameTexts[0] = functionName

    returnTupleNameCount := 0
    returnRoot := signatureResult.Values[1]
    if returnRoot >= 0 {
        outputs.ReturnTypeTexts[0] = TypeReferenceCanonicalTextCore(source, canonicalNodes, returnRoot)
        if outputs.ReturnLabeledTypeTexts.Length > 0 {
            outputs.ReturnLabeledTypeTexts[0] = TypeReferenceLabeledCanonicalTextCore(source, canonicalNodes, returnRoot)
        }

        returnTupleNames := new TypeReferenceTupleNameTable(outputs.ReturnTupleNameTexts)
        returnTupleNameCount = TypeReferenceTupleElementNamesCore(source, canonicalNodes, returnRoot, returnTupleNames)
        if returnTupleNameCount < 0 {
            return -1
        }
    } else {
        outputs.ReturnTypeTexts[0] = "void"
        if outputs.ReturnLabeledTypeTexts.Length > 0 {
            outputs.ReturnLabeledTypeTexts[0] = "void"
        }
    }

    flatParamTupleNameCount := 0
    paramIndex := 0
    while paramIndex < paramCount {
        paramName := FunctionSignatureSpanText(source, parameters.NameStarts[paramIndex], parameters.NameLengths[paramIndex])
        if paramName == "" {
            return -1
        }

        paramRoot := parameters.TypeRoots[paramIndex]
        outputs.ParamNameTexts[paramIndex] = paramName
        outputs.ParamTypeTexts[paramIndex] = TypeReferenceCanonicalTextCore(source, canonicalNodes, paramRoot)
        if paramIndex < outputs.ParamLabeledTypeTexts.Length {
            outputs.ParamLabeledTypeTexts[paramIndex] = TypeReferenceLabeledCanonicalTextCore(source, canonicalNodes, paramRoot)
        }

        paramTupleNames := new TypeReferenceTupleNameTable(tupleNames.Names)
        tupleNameCount := TypeReferenceTupleElementNamesCore(source, canonicalNodes, paramRoot, paramTupleNames)
        if tupleNameCount < 0 || flatParamTupleNameCount + tupleNameCount > outputs.ParamTupleNameTexts.Length {
            return -1
        }

        outputs.ParamTupleNameCounts[paramIndex] = tupleNameCount
        tupleIndex := 0
        while tupleIndex < tupleNameCount {
            outputs.ParamTupleNameTexts[flatParamTupleNameCount + tupleIndex] = tupleNames.Names[tupleIndex]
            tupleIndex = tupleIndex + 1
        }

        flatParamTupleNameCount = flatParamTupleNameCount + tupleNameCount
        paramIndex = paramIndex + 1
    }

    typeParamIndex := 0
    while typeParamIndex < typeParamCount {
        typeParamName := FunctionSignatureSpanText(source, typeParams.Starts[typeParamIndex], typeParams.Lengths[typeParamIndex])
        if typeParamName == "" {
            return -1
        }

        outputs.TypeParamTexts[typeParamIndex] = typeParamName
        outputs.TypeParamSpecials[typeParamIndex] = 0
        outputs.TypeParamConstraintCounts[typeParamIndex] = 0
        typeParamIndex = typeParamIndex + 1
    }

    flatTypeConstraintCount := 0
    if whereItemCount > 0 {
        if typeParamCount == 0 {
            return -1
        }

        whereNames := new FunctionSignatureNameSpanTable(whereItems.NameStarts, whereItems.NameLengths)
        ownerIndexCount := FunctionSignatureWhereOwnerIndicesCore(source, declaredTypeParamNames, typeParamCount, whereNames, whereItemCount, ownerIndices)
        if ownerIndexCount != whereItemCount {
            return -1
        }

        typeParamIndex = 0
        while typeParamIndex < typeParamCount {
            whereIndex := 0
            while whereIndex < whereItemCount {
                if ownerIndices.Indices[whereIndex] == typeParamIndex {
                    itemCode := whereItems.ItemCodes[whereIndex]
                    if itemCode >= 0 {
                        if flatTypeConstraintCount >= outputs.TypeParamConstraintTypeTexts.Length {
                            return -1
                        }

                        outputs.TypeParamConstraintTypeTexts[flatTypeConstraintCount] = TypeReferenceCanonicalTextCore(source, canonicalNodes, itemCode)
                        outputs.TypeParamConstraintCounts[typeParamIndex] = outputs.TypeParamConstraintCounts[typeParamIndex] + 1
                        flatTypeConstraintCount = flatTypeConstraintCount + 1
                    } else if itemCode == -2 {
                        outputs.TypeParamSpecials[typeParamIndex] = outputs.TypeParamSpecials[typeParamIndex] | 1
                    } else if itemCode == -3 {
                        outputs.TypeParamSpecials[typeParamIndex] = outputs.TypeParamSpecials[typeParamIndex] | 2
                    } else if itemCode == -4 {
                        outputs.TypeParamSpecials[typeParamIndex] = outputs.TypeParamSpecials[typeParamIndex] | 4
                    } else {
                        return -1
                    }
                }

                whereIndex = whereIndex + 1
            }

            if (outputs.TypeParamSpecials[typeParamIndex] & 3) == 3 || (outputs.TypeParamSpecials[typeParamIndex] & 6) == 6 {
                return -1
            }

            typeParamIndex = typeParamIndex + 1
        }
    }

    result.Values[0] = returnTupleNameCount
    result.Values[1] = bodyStart
    result.Values[2] = typeParamCount
    result.Values[3] = flatTypeConstraintCount
    result.Values[4] = flatParamTupleNameCount
    result.Values[5] = whereItemCount
    return paramCount
}

func FunctionSignatureDefaultKindSupported(kind: int): bool {
    return kind == 46 || kind == 44 || kind == 45 || kind == 1 || kind == 4
}

func FunctionSignatureDefaultMemberAccessKind(): int {
    return 1000
}

func FunctionSignatureDefaultDottedNameSupported(tokens: ParserTokenTable, startIndex: int, endIndex: int): bool {
    if startIndex < 0 || endIndex <= startIndex || endIndex > tokens.Kinds.Length {
        return false
    }

    identifierCount := 0
    dotCount := 0
    expectIdentifier := true
    i := startIndex
    while i < endIndex {
        kind := tokens.Kinds[i]
        if expectIdentifier {
            if kind != 0 {
                return false
            }

            identifierCount = identifierCount + 1
            expectIdentifier = false
        } else {
            if kind != 124 {
                return false
            }

            dotCount = dotCount + 1
            expectIdentifier = true
        }

        i = i + 1
    }

    return !expectIdentifier && identifierCount >= 2 && dotCount >= 1
}

func FunctionSignatureDefaultDottedNameText(source: string, tokens: ParserTokenTable, startIndex: int, endIndex: int): string {
    if !FunctionSignatureDefaultDottedNameSupported(tokens, startIndex, endIndex) {
        return ""
    }
    builder := new StringBuilder()
    index := startIndex
    while index < endIndex {
        builder.Append(source.Substring(tokens.Starts[index], tokens.ValueLengths[index]))
        index = index + 1
    }
    return builder.ToString()
}

func ParseFunctionParameterDefaultsCore(source: string, tokens: ParserTokenTable, count: int, funcIndex: int, outputs: FunctionSignatureInfoOutputTable): int {
    if funcIndex < 0 || funcIndex >= count || (tokens.Kinds[funcIndex] != 7 && tokens.Kinds[funcIndex] != 85 && tokens.Kinds[funcIndex] != 86) {
        return -1
    }

    pos := funcIndex + 1
    // `func*` generator marker: skip the `*` (Star 90) so parameter-default scanning finds the name and
    // `(` exactly as an ordinary `func` does.
    if pos < count && tokens.Kinds[pos] == 90 {
        pos = pos + 1
    }
    if tokens.Kinds[funcIndex] == 85 || tokens.Kinds[funcIndex] == 86 {
        if pos >= count || tokens.Kinds[pos] != 75 {
            return -1
        }

        pos = pos + 1
    } else if pos < count && tokens.Kinds[pos] == 75 {
        if pos + 1 >= count || !FunctionSignatureOperatorKindSupported(tokens.Kinds[pos + 1]) {
            return -1
        }

        pos = pos + 2
    } else if pos < count && tokens.Kinds[pos] == 0 {
        pos = pos + 1
    } else {
        return -1
    }

    while pos < count && tokens.Kinds[pos] != 127 {
        pos = pos + 1
    }

    if pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }

    pos = pos + 1

    typeStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    st := new ParserState(0, 0, 0, 0, 0, 0)

    paramCount := 0
    foundDefault := 0
    while pos < count && tokens.Kinds[pos] != 128 {
        if paramCount >= outputs.ParamDefaultKinds.Length || paramCount >= outputs.ParamDefaultTexts.Length {
            return -1
        }

        while pos < count && tokens.Kinds[pos] == 131 {
            bracketDepth := 1
            pos = pos + 1
            while pos < count && bracketDepth > 0 {
                if tokens.Kinds[pos] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[pos] == 132 {
                    bracketDepth = bracketDepth - 1
                }

                pos = pos + 1
            }
        }

        // 78 `ref` -> 1, 79 `out` -> 2, 82 `params` -> 3, 42 `this` -> 4, 28 `in` -> 5. Kind 28 is the
        // same token `for x in xs` reads; it is a parameter MODIFIER only at the head of a parameter,
        // which is the only position this scan runs in.
        modifierKind := 0
        while pos < count && (tokens.Kinds[pos] == 78 || tokens.Kinds[pos] == 79 || tokens.Kinds[pos] == 82 || tokens.Kinds[pos] == 42 || tokens.Kinds[pos] == 28) {
            if tokens.Kinds[pos] == 78 {
                modifierKind = 1
            } else if tokens.Kinds[pos] == 79 {
                modifierKind = 2
            } else if tokens.Kinds[pos] == 82 {
                modifierKind = 3
            } else if tokens.Kinds[pos] == 42 {
                modifierKind = 4
            } else if tokens.Kinds[pos] == 28 {
                modifierKind = 5
            }

            pos = pos + 1
        }

        if pos >= count || tokens.Kinds[pos] != 0 {
            return -1
        }

        pos = pos + 1

        if pos >= count || tokens.Kinds[pos] != 122 {
            return -1
        }

        pos = pos + 1

        st.Pos = pos
        st.NodeCursor = 0
        st.ChildCursor = 0
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        typeRoot := ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
        if typeRoot < 0 {
            return -1
        }

        pos = st.Pos
        if pos + 1 < count && tokens.Kinds[pos] == 147 && tokens.Kinds[pos + 1] == 142 {
            pos = pos + 2
        }

        outputs.ParamDefaultKinds[paramCount] = -1
        outputs.ParamDefaultTexts[paramCount] = ""
        outputs.ParamModifierKinds[paramCount] = modifierKind

        if pos < count && tokens.Kinds[pos] == 93 {
            foundDefault = 1
            pos = pos + 1
            if pos >= count {
                return -1
            }

            defaultKind := tokens.Kinds[pos]
            defaultStart := tokens.Starts[pos]
            defaultLength := tokens.ValueLengths[pos]
            defaultTokenStart := pos
            defaultTokenCount := 0
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && pos < count {
                k := tokens.Kinds[pos]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        defaultTokenCount = defaultTokenCount + 1
                        pos = pos + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                }
            }

            if defaultTokenCount == 1 && FunctionSignatureDefaultKindSupported(defaultKind) {
                defaultLength = tokens.ValueLengths[defaultTokenStart]
            } else if FunctionSignatureDefaultDottedNameSupported(tokens, defaultTokenStart, pos) {
                defaultKind = FunctionSignatureDefaultMemberAccessKind()
                defaultLength = tokens.Starts[pos - 1] + tokens.ValueLengths[pos - 1] - defaultStart
            } else {
                return -1
            }

            outputs.ParamDefaultKinds[paramCount] = defaultKind
            if defaultKind == FunctionSignatureDefaultMemberAccessKind() {
                outputs.ParamDefaultTexts[paramCount] = FunctionSignatureDefaultDottedNameText(source, tokens, defaultTokenStart, pos)
            } else {
                outputs.ParamDefaultTexts[paramCount] = FunctionSignatureSpanText(source, defaultStart, defaultLength)
            }
        } else if foundDefault == 1 {
            return -1
        }

        paramCount = paramCount + 1

        if pos >= count || (tokens.Kinds[pos] != 134 && tokens.Kinds[pos] != 128) {
            return -1
        }

        if tokens.Kinds[pos] == 134 {
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }

    return paramCount
}

func FunctionSignatureWhereOwnerIndicesCore(source: string, typeParams: FunctionSignatureNameSpanTable, typeParamCount: int, whereNames: FunctionSignatureNameSpanTable, whereItemCount: int, result: FunctionSignatureOwnerIndexTable): int {
    if typeParamCount < 0 || whereItemCount < 0 || whereItemCount > result.Indices.Length {
        return -1
    }

    w := 0
    while w < whereItemCount {
        ownerIndex := FunctionSignatureTypeParameterIndexOfCore(source, typeParams, typeParamCount, whereNames.Starts[w], whereNames.Lengths[w])
        if ownerIndex < 0 {
            return -1
        }

        result.Indices[w] = ownerIndex
        w = w + 1
    }

    return whereItemCount
}

func FunctionSignatureTypeParameterIndexOfCore(source: string, typeParams: FunctionSignatureNameSpanTable, typeParamCount: int, nameStart: int, nameLength: int): int {
    i := 0
    while i < typeParamCount {
        if ParserDeclarationSourceSpansEqual(source, typeParams.Starts[i], typeParams.Lengths[i], nameStart, nameLength) {
            return i
        }

        i = i + 1
    }

    return -1
}

func FunctionSignatureSpanText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    return source.Substring(start, length)
}

func FunctionSignatureOperatorKindSupported(kind: int): bool {
    return kind == 44 || kind == 45 || kind == 88 || kind == 89 || kind == 90 || kind == 91 || kind == 92 || kind == 98 || kind == 99 || kind == 100 || kind == 101 || kind == 102 || kind == 103 || kind == 106 || kind == 107 || kind == 108 || kind == 109 || kind == 110 || kind == 111 || kind == 112 || kind == 113 || kind == 114
}

func FunctionSignatureOperatorClrName(kind: int, paramCount: int): string {
    if kind == 44 {
        if paramCount == 1 {
            return "op_True"
        }

        return ""
    }

    if kind == 45 {
        if paramCount == 1 {
            return "op_False"
        }

        return ""
    }

    if kind == 88 {
        if paramCount == 1 {
            return "op_UnaryPlus"
        }

        if paramCount == 2 {
            return "op_Addition"
        }

        return ""
    }

    if kind == 89 {
        if paramCount == 1 {
            return "op_UnaryNegation"
        }

        if paramCount == 2 {
            return "op_Subtraction"
        }

        return ""
    }

    if kind == 90 {
        if paramCount == 2 {
            return "op_Multiply"
        }

        return ""
    }

    if kind == 91 {
        if paramCount == 2 {
            return "op_Division"
        }

        return ""
    }

    if kind == 92 {
        if paramCount == 2 {
            return "op_Modulus"
        }

        return ""
    }

    if kind == 98 {
        if paramCount == 2 {
            return "op_Equality"
        }

        return ""
    }

    if kind == 99 {
        if paramCount == 2 {
            return "op_Inequality"
        }

        return ""
    }

    if kind == 100 {
        if paramCount == 2 {
            return "op_LessThan"
        }

        return ""
    }

    if kind == 101 {
        if paramCount == 2 {
            return "op_LessThanOrEqual"
        }

        return ""
    }

    if kind == 102 {
        if paramCount == 2 {
            return "op_GreaterThan"
        }

        return ""
    }

    if kind == 103 {
        if paramCount == 2 {
            return "op_GreaterThanOrEqual"
        }

        return ""
    }

    if kind == 106 {
        if paramCount == 1 {
            return "op_LogicalNot"
        }

        return ""
    }

    if kind == 107 {
        if paramCount == 2 {
            return "op_BitwiseAnd"
        }

        return ""
    }

    if kind == 108 {
        if paramCount == 2 {
            return "op_BitwiseOr"
        }

        return ""
    }

    if kind == 109 {
        if paramCount == 2 {
            return "op_ExclusiveOr"
        }

        return ""
    }

    if kind == 110 {
        if paramCount == 1 {
            return "op_OnesComplement"
        }

        return ""
    }

    if kind == 111 {
        if paramCount == 2 {
            return "op_LeftShift"
        }

        return ""
    }

    if kind == 112 {
        if paramCount == 2 {
            return "op_RightShift"
        }

        return ""
    }

    if kind == 113 {
        if paramCount == 1 {
            return "op_Increment"
        }

        return ""
    }

    if kind == 114 {
        if paramCount == 1 {
            return "op_Decrement"
        }

        return ""
    }

    return ""
}

// THE `where` CLAUSE SCAN, WRITTEN ONCE FOR EVERY DECLARATION THAT CAN CARRY ONE.
//
// `where T: Item, Item ... where U: Item ...`. Each item appends one flat row (owner name span + code);
// the owner identifier is NOT validated against the declared type parameters here — the host resolves
// the span against the declaration's type-parameter spans, because the kernel cannot compare source
// text. A constraint TYPE parses as another root in the shared node table, exactly like a parameter
// type; `new` must be followed directly by `(` `)` or the clause is malformed.
//
// Item codes: a type-tree root (>= 0), or a special sentinel — -2 `class`, -3 `struct`, -4 `new()`.
//
// This was inline in `ParseFunctionSignatureCore` while a function was the only declaration that could
// carry a clause. It is called from there and from the struct/class/record, interface and union
// declaration cores, each of which reaches it before the `{` gate that used to refuse a `where` token
// outright. Answers the row count, or -1 on a malformed clause; `nextIndex` is the first token after
// the last clause (equal to `start` when there is no `where` at all).
func ParseWhereClausesCore(tokens: ParserTokenTable, count: int, start: int, st: ParserState, typeStack: ParserArgumentStack, nodes: ParserNodeTable, children: ParserChildIndexTable, whereItems: ParserFunctionWhereTable, out nextIndex: int): int {
    i := start
    nextIndex = start
    whereItemCount := 0
    while i < count && tokens.Kinds[i] == 53 {
        i = i + 1
        if i >= count || tokens.Kinds[i] != 0 {
            return -1
        }

        whereNameStart := tokens.Starts[i]
        whereNameLength := tokens.ValueLengths[i]
        i = i + 1
        if i >= count || tokens.Kinds[i] != 122 {
            return -1
        }

        i = i + 1

        moreItems := true
        while moreItems {
            itemCode := -1
            if i < count && tokens.Kinds[i] == 8 {
                itemCode = -2
                i = i + 1
            } else if i < count && tokens.Kinds[i] == 9 {
                itemCode = -3
                i = i + 1
            } else if i < count && tokens.Kinds[i] == 41 {
                if i + 2 >= count || tokens.Kinds[i + 1] != 127 || tokens.Kinds[i + 2] != 128 {
                    return -1
                }

                itemCode = -4
                i = i + 3
            } else {
                st.Pos = i
                st.SplitGreaterDepth = 0
                st.ArgStackTop = 0
                itemCode = ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
                if itemCode < 0 {
                    return -1
                }

                i = st.Pos
            }

            if whereItemCount >= whereItems.ItemCodes.Length {
                return -1
            }

            whereItems.NameStarts[whereItemCount] = whereNameStart
            whereItems.NameLengths[whereItemCount] = whereNameLength
            whereItems.ItemCodes[whereItemCount] = itemCode
            whereItemCount = whereItemCount + 1

            if i < count && tokens.Kinds[i] == 134 {
                i = i + 1
            } else {
                moreItems = false
            }
        }
    }

    nextIndex = i
    return whereItemCount
}

func ParseFunctionSignatureCore(tokens: ParserTokenTable, count: int, funcIndex: int, typeStack: ParserArgumentStack, nodes: ParserNodeTable, children: ParserChildIndexTable, parameters: ParserFunctionParameterTable, typeParams: ParserFunctionTypeParameterTable, whereItems: ParserFunctionWhereTable, outResult: ParserResultTable): int {
    funcNameStart := -1
    funcNameLength := 0
    returnRoot := -1
    conversionOperatorKind := 0
    st := new ParserState(0, 0, 0, 0, 0, 0)
    i := funcIndex + 1
    // `func*` (generator/iterator) carries a `*` (Star 90) between the keyword and the name. Skip it so
    // the name, type parameters, parameters, and return type parse exactly as an ordinary `func` does;
    // the generator fact itself is recorded by the declaration/member scan, not the signature.
    if i < count && tokens.Kinds[i] == 90 {
        i = i + 1
    }
    if funcIndex >= 0 && funcIndex < count && (tokens.Kinds[funcIndex] == 85 || tokens.Kinds[funcIndex] == 86) {
        conversionOperatorKind = tokens.Kinds[funcIndex]
        if i >= count || tokens.Kinds[i] != 75 {
            return -1
        }

        funcNameStart = tokens.Starts[funcIndex]
        funcNameLength = tokens.Starts[i] + tokens.ValueLengths[i] - tokens.Starts[funcIndex]
        i = i + 1
    } else if i < count && tokens.Kinds[i] == 75 {
        if i + 1 >= count || !FunctionSignatureOperatorKindSupported(tokens.Kinds[i + 1]) {
            return -1
        }

        funcNameStart = tokens.Starts[i]
        funcNameLength = tokens.Starts[i + 1] + tokens.ValueLengths[i + 1] - tokens.Starts[i]
        i = i + 2
    } else if i < count && tokens.Kinds[i] == 0 {
        funcNameStart = tokens.Starts[i]
        funcNameLength = tokens.ValueLengths[i]
        i = i + 1
        // AN EXPLICIT INTERFACE IMPLEMENTATION'S NAME IS QUALIFIED — `func IEnumerable.GetEnumerator()`
        // — and the whole qualified spelling IS the member's name. A generic METHOD's `<T>` is not part
        // of a name and is left for the type-parameter list below, which is why the scan answers -1
        // unless a DOT really follows.
        qualifiedNameEnd := ExplicitInterfaceMemberNameEnd(tokens.Kinds, count, i)
        if qualifiedNameEnd > i {
            funcNameLength = tokens.Starts[qualifiedNameEnd - 1] + tokens.ValueLengths[qualifiedNameEnd - 1] - funcNameStart
            i = qualifiedNameEnd
        }
    }

    // Optional generic TYPE-PARAMETER list `<T, U>`: bare comma-separated Identifiers only, with lifetime
    // parameters (`<'a>`) accepted and ignored for emission metadata. An inline constraint (`<T: Base>`),
    // an empty list, or any other form is unmodelled — return -1 (the host declines to the N# backend path).
    // With no `<`, the list is empty.
    typeParamCount := 0
    if i < count && tokens.Kinds[i] == 100 {
        i = i + 1
        typeParamItemCount := 0
        while i < count && tokens.Kinds[i] != 102 {
            if tokens.Kinds[i] == 0 {
                typeParams.Starts[typeParamCount] = tokens.Starts[i]
                typeParams.Lengths[typeParamCount] = tokens.ValueLengths[i]
                typeParamCount = typeParamCount + 1
            } else if tokens.Kinds[i] != 142 {
                return -1
            }

            typeParamItemCount = typeParamItemCount + 1
            i = i + 1

            if i < count && tokens.Kinds[i] != 102 {
                if tokens.Kinds[i] != 134 {
                    return -1
                }

                i = i + 1
                // A consumed comma must be FOLLOWED by another parameter name — a trailing comma
                // (`<T,>`) is a production-parser error (adversarial-review finding: the loop's
                // `!= 102` condition would otherwise exit cleanly and ACCEPT what the pipeline rejects).
                if i >= count || (tokens.Kinds[i] != 0 && tokens.Kinds[i] != 142) {
                    return -1
                }
            }
        }

        if i >= count || tokens.Kinds[i] != 102 || typeParamItemCount == 0 {
            return -1
        }

        i = i + 1
    }

    if conversionOperatorKind != 0 {
        st.Pos = i
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        returnRoot = ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
        if returnRoot < 0 {
            return -1
        }

        i = st.Pos
    }

    // The parameter list `(` must follow the name (and optional type parameters) DIRECTLY. (Previously this
    // scanned blindly to the first `(`, silently skipping a `<T>` list — a generic function then declined
    // later at type resolution; the list is now parsed above, and anything ELSE in the gap is malformed and
    // declines at parse instead of at emit.)
    if i >= count || tokens.Kinds[i] != 127 {
        return -1
    }

    i = i + 1

    paramCount := 0

    while i < count && tokens.Kinds[i] != 128 {

        // Skip attribute lists `[ ... ]` (balanced).
        while i < count && tokens.Kinds[i] == 131 {
            bracketDepth := 1
            i = i + 1
            while i < count && bracketDepth > 0 {
                if tokens.Kinds[i] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[i] == 132 {
                    bracketDepth = bracketDepth - 1
                }

                i = i + 1
            }
        }

        // `ref`/`out`/`in` are semantic: they wrap the parsed parameter type in a ByRef node, because on
        // the CLR all three ARE `&T` and differ only in the direction bits beside the signature.
        // `params` and `this` are signature modifiers this kernel does not otherwise model.
        byRefParameter := false
        while i < count && (tokens.Kinds[i] == 78 || tokens.Kinds[i] == 79 || tokens.Kinds[i] == 82 || tokens.Kinds[i] == 42 || tokens.Kinds[i] == 28) {
            if tokens.Kinds[i] == 78 || tokens.Kinds[i] == 79 || tokens.Kinds[i] == 28 {
                byRefParameter = true
            }

            i = i + 1
        }

        if i >= count || tokens.Kinds[i] != 0 {
            return -1
        }

        paramNameStart := tokens.Starts[i]
        paramNameLength := tokens.ValueLengths[i]
        i = i + 1

        if i >= count || tokens.Kinds[i] != 122 {
            return -1
        }

        i = i + 1

        st.Pos = i
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        typeRoot := ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
        if typeRoot < 0 {
            return -1
        }

        i = st.Pos
        if byRefParameter {
            childRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, children, typeRoot)
            typeSpanStart := nodes.SpanStarts[typeRoot]
            typeSpanEnd := typeSpanStart + nodes.SpanLengths[typeRoot]
            typeRoot = EmitTypeReferenceNode(st, nodes, 5, -1, 0, childRunStart, 1, typeSpanStart, typeSpanEnd - typeSpanStart)
        }

        if i + 1 < count && tokens.Kinds[i] == 147 && tokens.Kinds[i + 1] == 142 {
            i = i + 2
        }

        parameters.NameStarts[paramCount] = paramNameStart
        parameters.NameLengths[paramCount] = paramNameLength
        parameters.TypeRoots[paramCount] = typeRoot
        paramCount = paramCount + 1

        // Skip a `= default` value without parsing it (balanced to the next depth-0 `,` or `)`).
        if i < count && tokens.Kinds[i] == 93 {
            i = i + 1
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && i < count {
                k := tokens.Kinds[i]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    i = i + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        i = i + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    i = i + 1
                }
            }
        }

        // After a parameter (and its optional default), the next token must cleanly terminate the parameter
        // -- a `,` (another parameter) or `)` (end of the list). Anything else means a malformed parameter
        // (e.g. an unbalanced default value whose depth tracking overshot the list's `)`, or a deferred
        // trailing annotation): refuse with -1 rather than silently mis-parsing the rest of the signature.
        if i >= count || (tokens.Kinds[i] != 134 && tokens.Kinds[i] != 128) {
            return -1
        }

        if tokens.Kinds[i] == 134 {
            i = i + 1
        }
    }

    if i < count && tokens.Kinds[i] == 128 {
        i = i + 1
    }

    if conversionOperatorKind == 0 && i < count && tokens.Kinds[i] == 122 {

        // A `: this(...)` / `: base(...)` CONSTRUCTOR chaining initializer is NOT a return type — leave returnRoot at
        // -1 and stop; the composed constructor parser handles the initializer via ParseConstructorChainInfoCore. A regular
        // function's `: ReturnType` always has a TYPE token after `:`, never `this` (42) / `base` (43), so this
        // branch is constructor-only and leaves function-signature parsing unchanged.
        if !(i + 1 < count && (tokens.Kinds[i + 1] == 42 || tokens.Kinds[i + 1] == 43)) {
            i = i + 1
            st.Pos = i
            st.SplitGreaterDepth = 0
            st.ArgStackTop = 0
            returnRoot = ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
            if returnRoot < 0 {
                return -1
            }

            i = st.Pos
        }
    }

    if i + 1 < count && tokens.Kinds[i] == 0 && tokens.Kinds[i + 1] == 142 {
        i = i + 2
    }

    // Generic CONSTRAINT clauses (D-17b) — the scan is `ParseWhereClausesCore` below, shared with the
    // three TYPE declaration cores so the grammar is written once.
    whereNext := i
    whereItemCount := ParseWhereClausesCore(tokens, count, i, st, typeStack, nodes, children, whereItems, out whereNext)
    if whereItemCount < 0 {
        return -1
    }

    i = whereNext

    outResult.Values[0] = paramCount
    outResult.Values[1] = returnRoot
    outResult.Values[2] = st.NodeCursor
    outResult.Values[3] = funcNameStart
    outResult.Values[4] = funcNameLength
    outResult.Values[5] = typeParamCount
    outResult.Values[6] = i
    outResult.Values[7] = whereItemCount
    return paramCount
}

func ParseConstructorSignatureInfoCore(source: string, tokens: ParserTokenTable, count: int, ctorIndex: int, outputs: ConstructorSignatureOutputTable, typeStack: ParserArgumentStack, nodes: ParserNodeTable, children: ParserChildIndexTable, canonicalNodes: TypeReferenceCanonicalTable, parameters: ParserFunctionParameterTable, typeParams: ParserFunctionTypeParameterTable, whereItems: ParserFunctionWhereTable, signatureResult: ParserResultTable, result: ParserResultTable): int {
    if result.Values.Length < 4 {
        return -1
    }

    paramCount := ParseFunctionSignatureCore(tokens, count, ctorIndex, typeStack, nodes, children, parameters, typeParams, whereItems, signatureResult)
    if paramCount < 0 || signatureResult.Values[1] >= 0 || signatureResult.Values[5] != 0 || signatureResult.Values[7] != 0 {
        return -1
    }

    if paramCount > outputs.ParamNameTexts.Length || paramCount > outputs.ParamTypeTexts.Length {
        return -1
    }

    if paramCount > outputs.ArgKinds.Length || paramCount > outputs.ArgTexts.Length {
        return -1
    }

    defaultCount := ParseConstructorParameterDefaultsCore(source, tokens, count, ctorIndex, outputs)
    if defaultCount != paramCount {
        return -1
    }

    paramIndex := 0
    while paramIndex < paramCount {
        paramName := FunctionSignatureSpanText(source, parameters.NameStarts[paramIndex], parameters.NameLengths[paramIndex])
        if paramName == "" {
            return -1
        }

        outputs.ParamNameTexts[paramIndex] = paramName
        outputs.ParamTypeTexts[paramIndex] = TypeReferenceCanonicalTextCore(source, canonicalNodes, parameters.TypeRoots[paramIndex])
        if paramIndex < outputs.ParamLabeledTypeTexts.Length {
            outputs.ParamLabeledTypeTexts[paramIndex] = TypeReferenceLabeledCanonicalTextCore(source, canonicalNodes, parameters.TypeRoots[paramIndex])
        }

        paramIndex = paramIndex + 1
    }

    if ctorIndex < 0 || ctorIndex >= count {
        return -1
    }

    if tokens.Kinds[ctorIndex] != 0 {
        return -1
    }

    if !ParserDeclarationTokenTextEquals(source, tokens.Starts[ctorIndex], tokens.ValueLengths[ctorIndex], "constructor") {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    chainArgKinds := new int[](count + 1)
    chainArgStarts := new int[](count + 1)
    chainArgLengths := new int[](count + 1)
    chainArgNames := new string[](count + 1)
    chainArgs := new ConstructorChainArgTable(chainArgKinds, chainArgStarts, chainArgLengths, chainArgNames)
    chainResult := new ParserDeclarationResultTable(result.Values)
    chainArgCount := ParseConstructorChainInfoCore(source, declarationTokens, count, ctorIndex, chainArgs, chainResult)
    if chainArgCount < 0 {
        return -1
    }

    if outputs.ArgTexts.Length < paramCount + chainArgCount || outputs.ArgKinds.Length < paramCount + chainArgCount || outputs.ArgStarts.Length < paramCount + chainArgCount || outputs.ArgLengths.Length < paramCount + chainArgCount {
        return -1
    }

    chainArgIndex := 0
    while chainArgIndex < chainArgCount {
        chainOutputIndex := paramCount + chainArgIndex
        outputs.ArgKinds[chainOutputIndex] = chainArgs.Kinds[chainArgIndex]
        outputs.ArgStarts[chainOutputIndex] = chainArgs.Starts[chainArgIndex]
        outputs.ArgLengths[chainOutputIndex] = chainArgs.Lengths[chainArgIndex]
        outputs.ArgTexts[chainOutputIndex] = chainArgs.Names[chainArgIndex]
        chainArgIndex = chainArgIndex + 1
    }

    bodyBrace := result.Values[1]
    if bodyBrace < 0 || bodyBrace >= count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    result.Values[2] = paramCount
    result.Values[3] = chainArgCount
    return paramCount
}

func ConstructorSignatureDefaultKindSupported(kind: int): bool {
    return kind == 46 || kind == 44 || kind == 45 || kind == 1 || kind == 4
}

func ParseConstructorParameterDefaultsCore(source: string, tokens: ParserTokenTable, count: int, ctorIndex: int, outputs: ConstructorSignatureOutputTable): int {
    if ctorIndex < 0 || ctorIndex >= count || tokens.Kinds[ctorIndex] != 0 {
        return -1
    }

    if !ParserDeclarationTokenTextEquals(source, tokens.Starts[ctorIndex], tokens.ValueLengths[ctorIndex], "constructor") {
        return -1
    }

    pos := ctorIndex + 1
    if pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }

    pos = pos + 1

    typeStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    st := new ParserState(0, 0, 0, 0, 0, 0)

    paramCount := 0
    foundDefault := 0
    while pos < count && tokens.Kinds[pos] != 128 {
        if paramCount >= outputs.ArgKinds.Length || paramCount >= outputs.ArgTexts.Length {
            return -1
        }

        while pos < count && tokens.Kinds[pos] == 131 {
            bracketDepth := 1
            pos = pos + 1
            while pos < count && bracketDepth > 0 {
                if tokens.Kinds[pos] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[pos] == 132 {
                    bracketDepth = bracketDepth - 1
                }

                pos = pos + 1
            }
        }

        while pos < count && (tokens.Kinds[pos] == 78 || tokens.Kinds[pos] == 79 || tokens.Kinds[pos] == 82 || tokens.Kinds[pos] == 42 || tokens.Kinds[pos] == 28) {
            pos = pos + 1
        }

        if pos >= count || tokens.Kinds[pos] != 0 {
            return -1
        }

        pos = pos + 1

        if pos >= count || tokens.Kinds[pos] != 122 {
            return -1
        }

        pos = pos + 1

        st.Pos = pos
        st.NodeCursor = 0
        st.ChildCursor = 0
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        typeRoot := ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
        if typeRoot < 0 {
            return -1
        }

        pos = st.Pos

        outputs.ArgKinds[paramCount] = -1
        outputs.ArgTexts[paramCount] = ""

        if pos < count && tokens.Kinds[pos] == 93 {
            foundDefault = 1
            pos = pos + 1
            if pos >= count {
                return -1
            }

            defaultKind := tokens.Kinds[pos]
            defaultStart := tokens.Starts[pos]
            defaultLength := tokens.ValueLengths[pos]
            defaultTokenStart := pos
            defaultTokenCount := 0
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && pos < count {
                k := tokens.Kinds[pos]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        defaultTokenCount = defaultTokenCount + 1
                        pos = pos + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                }
            }

            if defaultTokenCount == 1 && ConstructorSignatureDefaultKindSupported(defaultKind) {
                defaultLength = tokens.ValueLengths[defaultTokenStart]
            } else if FunctionSignatureDefaultDottedNameSupported(tokens, defaultTokenStart, pos) {
                defaultKind = FunctionSignatureDefaultMemberAccessKind()
                defaultLength = tokens.Starts[pos - 1] + tokens.ValueLengths[pos - 1] - defaultStart
            } else {
                return -1
            }

            outputs.ArgKinds[paramCount] = defaultKind
            if defaultKind == FunctionSignatureDefaultMemberAccessKind() {
                outputs.ArgTexts[paramCount] = FunctionSignatureDefaultDottedNameText(source, tokens, defaultTokenStart, pos)
            } else {
                outputs.ArgTexts[paramCount] = FunctionSignatureSpanText(source, defaultStart, defaultLength)
            }
        } else if foundDefault == 1 {
            return -1
        }

        paramCount = paramCount + 1

        if pos >= count || (tokens.Kinds[pos] != 134 && tokens.Kinds[pos] != 128) {
            return -1
        }

        if tokens.Kinds[pos] == 134 {
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }

    return paramCount
}

func ParseInterfaceDeclarationSignatureInfoCore(source: string, tokens: ParserTokenTable, count: int, interfaceIndex: int, baseOutputs: InterfaceSignatureBaseOutputTable, methodOutputs: InterfaceSignatureMethodOutputTable, typeStack: ParserArgumentStack, nodes: ParserNodeTable, children: ParserChildIndexTable, canonicalNodes: TypeReferenceCanonicalTable, tupleNodes: InterfaceSignatureTupleNodeTable, parameters: ParserFunctionParameterTable, typeParams: ParserFunctionTypeParameterTable, whereItems: ParserFunctionWhereTable, signatureResult: ParserResultTable, result: ParserResultTable): int {
    if result.Values.Length < 5 {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    declarationWhere := new ParserDeclarationWhereTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    declaration := new InterfaceDeclarationTable(methodOutputs.FuncIndices, baseOutputs.BaseNameStarts, baseOutputs.BaseNameLengths, new int[](count + 1), new int[](count + 1), declarationWhere, new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    declarationResult := new ParserDeclarationResultTable(result.Values)
    methodCount := ParseInterfaceDeclarationCore(source, declarationTokens, count, interfaceIndex, declaration, declarationResult)
    if methodCount < 0 {
        return -1
    }

    // THE EVENT ROWS, RENDERED. An event's handler type is a TYPE REFERENCE like any other, so it is
    // canonicalised exactly as a method's return and parameter types are.
    eventCount := 0
    if result.Values.Length > 7 {
        eventCount = result.Values[7]
    }

    if eventCount > baseOutputs.EventNameTexts.Length || eventCount > baseOutputs.EventTypeTexts.Length {
        return -1
    }

    e := 0
    while e < eventCount {
        eventName := ParserDeclarationSpanText(source, declaration.EventNameStarts[e], declaration.EventNameLengths[e])
        if eventName == "" {
            return -1
        }

        eventTypeText := ParserDeclarationCanonicalTypeText(source, declaration.EventTypeStarts[e], declaration.EventTypeLengths[e])
        if eventTypeText == "" {
            return -1
        }

        baseOutputs.EventNameTexts[e] = eventName
        baseOutputs.EventTypeTexts[e] = eventTypeText
        e = e + 1
    }

    // THE VALUE ROWS, RENDERED. A value member's type is a TYPE REFERENCE like any other, so it is
    // canonicalised exactly as a method's return and an event's handler are.
    propertyCount := 0
    if result.Values.Length > 8 {
        propertyCount = result.Values[8]
    }

    if propertyCount > baseOutputs.PropertyNameTexts.Length || propertyCount > baseOutputs.PropertyTypeTexts.Length {
        return -1
    }

    v := 0
    while v < propertyCount {
        propertyName := ParserDeclarationSpanText(source, declaration.PropertyNameStarts[v], declaration.PropertyNameLengths[v])
        if propertyName == "" {
            return -1
        }

        propertyTypeText := ParserDeclarationCanonicalTypeText(source, declaration.PropertyTypeStarts[v], declaration.PropertyTypeLengths[v])
        if propertyTypeText == "" {
            return -1
        }

        baseOutputs.PropertyNameTexts[v] = propertyName
        baseOutputs.PropertyTypeTexts[v] = propertyTypeText
        v = v + 1
    }

    baseCount := result.Values[2]
    typeParamCount := result.Values[4]
    if baseOutputs.InterfaceNameTexts.Length < 1 || baseCount > baseOutputs.BaseNameTexts.Length || typeParamCount > baseOutputs.TypeParamTexts.Length {
        return -1
    }

    declaredInterfaceTypeParamNames := new FunctionSignatureNameSpanTable(declaration.TypeParamStarts, declaration.TypeParamLengths)
    if ParserDeclarationNameSpansDistinct(source, declaredInterfaceTypeParamNames.Starts, declaredInterfaceTypeParamNames.Lengths, typeParamCount) == 0 {
        return -1
    }

    interfaceName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if interfaceName == "" {
        return -1
    }

    // The constraint rows, rendered exactly as the struct core renders them.
    ifaceWhereCount := 0
    if result.Values.Length > 6 {
        ifaceWhereCount = result.Values[6]
    }

    if ifaceWhereCount > baseOutputs.WhereOwnerTexts.Length || ifaceWhereCount > baseOutputs.WhereItemCodes.Length || ifaceWhereCount > baseOutputs.WhereTypeTexts.Length {
        return -1
    }

    w := 0
    while w < ifaceWhereCount {
        ownerName := ParserDeclarationSpanText(source, declaration.Where.NameStarts[w], declaration.Where.NameLengths[w])
        if ownerName == "" {
            return -1
        }

        baseOutputs.WhereOwnerTexts[w] = ownerName
        baseOutputs.WhereItemCodes[w] = declaration.Where.ItemCodes[w]
        constraintText := ""
        if declaration.Where.ItemCodes[w] == 0 {
            constraintText = ParserDeclarationCanonicalTypeText(source, declaration.Where.TypeStarts[w], declaration.Where.TypeLengths[w])
            if constraintText == "" {
                return -1
            }
        }

        baseOutputs.WhereTypeTexts[w] = constraintText
        w = w + 1
    }

    baseOutputs.InterfaceNameTexts[0] = interfaceName

    baseIndex := 0
    while baseIndex < baseCount {
        baseName := ParserDeclarationCanonicalTypeText(source, declaration.BaseNameStarts[baseIndex], declaration.BaseNameLengths[baseIndex])
        if baseName == "" {
            return -1
        }

        baseOutputs.BaseNameTexts[baseIndex] = baseName
        baseIndex = baseIndex + 1
    }

    typeParamIndex := 0
    while typeParamIndex < typeParamCount {
        typeParamName := ParserDeclarationSpanText(source, declaration.TypeParamStarts[typeParamIndex], declaration.TypeParamLengths[typeParamIndex])
        if typeParamName == "" {
            return -1
        }

        baseOutputs.TypeParamTexts[typeParamIndex] = typeParamName
        typeParamIndex = typeParamIndex + 1
    }

    if methodCount > methodOutputs.NameTexts.Length || methodCount > methodOutputs.ReturnTexts.Length || methodCount > methodOutputs.ParamCounts.Length || methodCount > methodOutputs.BodyFlags.Length {
        return -1
    }

    modifierScratch := new int[](count + 1)
    modifierOutputs := new FunctionSignatureInfoOutputTable(new string[](0), new string[](0), new string[](0), new string[](0), modifierScratch, new int[](count + 1), new string[](count + 1), new int[](0), new string[](0), new string[](0), new string[](0), new string[](0), new string[](0), new int[](0), new int[](0), new string[](0))

    flatParamCount := 0
    methodIndex := 0
    while methodIndex < methodCount {
        paramCount := ParseFunctionSignatureCore(tokens, count, methodOutputs.FuncIndices[methodIndex], typeStack, nodes, children, parameters, typeParams, whereItems, signatureResult)
        if paramCount < 0 || signatureResult.Values[3] < 0 {
            return -1
        }

        modifierCount := ParseFunctionParameterDefaultsCore(source, tokens, count, methodOutputs.FuncIndices[methodIndex], modifierOutputs)
        if modifierCount != paramCount {
            return -1
        }

        if signatureResult.Values[5] > 0 || signatureResult.Values[7] > 0 {
            return -1
        }

        afterSignature := signatureResult.Values[6]
        if afterSignature < 0 || afterSignature >= count {
            return -1
        }

        methodName := FunctionSignatureSpanText(source, signatureResult.Values[3], signatureResult.Values[4])
        if methodName == "" {
            return -1
        }

        methodOutputs.NameTexts[methodIndex] = methodName

        returnRoot := signatureResult.Values[1]
        if returnRoot >= 0 {
            if ParseInterfaceSignatureHasTupleNamesCore(tupleNodes, returnRoot) != 0 {
                return -1
            }

            methodOutputs.ReturnTexts[methodIndex] = TypeReferenceCanonicalTextCore(source, canonicalNodes, returnRoot)
        } else {
            methodOutputs.ReturnTexts[methodIndex] = "void"
        }

        if flatParamCount + paramCount > methodOutputs.ParamNameTexts.Length || flatParamCount + paramCount > methodOutputs.ParamTypeTexts.Length || flatParamCount + paramCount > methodOutputs.ParamModifierKinds.Length {
            return -1
        }

        paramIndex := 0
        while paramIndex < paramCount {
            paramName := FunctionSignatureSpanText(source, parameters.NameStarts[paramIndex], parameters.NameLengths[paramIndex])
            if paramName == "" {
                return -1
            }

            paramRoot := parameters.TypeRoots[paramIndex]
            if ParseInterfaceSignatureHasTupleNamesCore(tupleNodes, paramRoot) != 0 {
                return -1
            }

            flatSlot := flatParamCount + paramIndex
            methodOutputs.ParamNameTexts[flatSlot] = paramName
            methodOutputs.ParamTypeTexts[flatSlot] = TypeReferenceCanonicalTextCore(source, canonicalNodes, paramRoot)
            methodOutputs.ParamModifierKinds[flatSlot] = modifierScratch[paramIndex]
            paramIndex = paramIndex + 1
        }

        methodOutputs.ParamCounts[methodIndex] = paramCount
        flatParamCount = flatParamCount + paramCount

        // WHAT FOLLOWS A SIGNATURE SAYS WHETHER IT HAS A BODY: a `{` opens one, and the next member or
        // the closing brace means it is a slot. An EVENT and a VALUE member are both "next member"
        // spellings — each begins with an ordinary identifier rather than a keyword — so both are
        // named here too, or a bodiless method followed by one reads as a malformed declaration.
        declarationTokensAfterSignature := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
        if tokens.Kinds[afterSignature] == 129 {
            methodOutputs.BodyFlags[methodIndex] = 1
        } else if tokens.Kinds[afterSignature] == 7 || tokens.Kinds[afterSignature] == 130 || ParseInterfaceDeclarationMemberIsEvent(source, declarationTokensAfterSignature, count, afterSignature) || ParseInterfaceDeclarationMemberIsValue(declarationTokensAfterSignature, count, afterSignature) {
            methodOutputs.BodyFlags[methodIndex] = 0
        } else {
            return -1
        }

        methodIndex = methodIndex + 1
    }

    result.Values[3] = flatParamCount
    return methodCount
}

func ParseInterfaceSignatureHasTupleNamesCore(nodes: InterfaceSignatureTupleNodeTable, root: int): int {
    if root < 0 || root >= nodes.Kinds.Length || nodes.Kinds[root] != 6 || nodes.ChildCount[root] == 0 {
        return 0
    }

    run := nodes.ChildStart[root]
    first := nodes.ChildIndices[run]
    if nodes.Kinds[first] != 7 {
        return 0
    }

    i := 0
    while i < nodes.ChildCount[root] {
        elem := nodes.ChildIndices[run + i]
        if nodes.Kinds[elem] != 7 {
            return -1
        }

        i = i + 1
    }

    return 1
}

func DirectLocalFunctionTokenIndicesCore(tokens: LocalFunctionTokenTable, nodes: LocalFunctionNodeTable, rootBlock: int, results: LocalFunctionResultTable): int {
    if rootBlock < 0 || rootBlock >= nodes.Kinds.Length {
        return -1
    }

    if nodes.Kinds[rootBlock] != 25 {
        return 0
    }

    childRun := nodes.ChildStart[rootBlock]
    childCount := nodes.ChildCount[rootBlock]
    if childRun < 0 || childCount < 0 {
        return -1
    }

    resultCount := 0
    childIndex := 0
    declarationTokens := new ParserDeclarationStartKindStream(tokens.Kinds, tokens.Starts)
    while childIndex < childCount {
        stmtNode := nodes.ChildIndices[childRun + childIndex]
        if stmtNode < 0 || stmtNode >= nodes.Kinds.Length {
            return -1
        }

        if nodes.Kinds[stmtNode] == 41 {
            if resultCount >= results.NodeIndices.Length || resultCount >= results.FuncTokenIndices.Length {
                return -1
            }

            funcTokenIndex := TokenIndexByKindStartCore(declarationTokens, tokens.Count, 7, nodes.ValueStarts[stmtNode])
            if funcTokenIndex < 0 {
                return -1
            }

            results.NodeIndices[resultCount] = stmtNode
            results.FuncTokenIndices[resultCount] = funcTokenIndex
            resultCount = resultCount + 1
        }

        childIndex = childIndex + 1
    }

    return resultCount
}
