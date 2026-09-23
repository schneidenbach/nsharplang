import NSharpLang.Compiler.Columnar


// THE COLUMNAR FUNCTION AND CONSTRUCTOR INFO KERNELS, including primary-constructor assignment
// synthesis.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.

// Product columnar function parser wrapper. It composes the signature rowset, statement-node rowset, and
// direct local-function discovery so the host adapter only materializes ColumnarFunctionInput containers.
class ColumnarFunctionTokenTable {
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

class ColumnarFunctionSignatureOutputTable {
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

class ColumnarFunctionBodyTable {
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

class ColumnarFunctionLocalTable {
    NodeIndices: int[]
    TokenIndices: int[]
    constructor(nodeIndices: int[], tokenIndices: int[]) {
        NodeIndices = nodeIndices
        TokenIndices = tokenIndices
    }
}

class ColumnarFunctionResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

// Product columnar constructor parser wrapper. It composes constructor signature/chain parsing with the
// statement-node rowset so the host adapter no longer orchestrates constructor body parsing.

class ColumnarConstructorTokenTable {
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

class ColumnarConstructorSignatureOutputTable {
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

class ColumnarConstructorBodyTable {
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

class ColumnarConstructorResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

func ParseColumnarProductFunctionInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, isLocalFunction: int, outFunctionNameTexts: string[], outReturnTypeTexts: string[], outParamNameTexts: string[], outParamTypeTexts: string[], outParamModifierKinds: int[], outParamDefaultKinds: int[], outParamDefaultTexts: string[], outParamTupleNameCounts: int[], outParamTupleNameTexts: string[], outReturnTupleNameTexts: string[], outReturnLabeledTypeTexts: string[], outParamLabeledTypeTexts: string[], outTypeParamTexts: string[], outTypeParamSpecials: int[], outTypeParamConstraintCounts: int[], outTypeParamConstraintTypeTexts: string[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outLocalFunctionNodeIndices: int[], outLocalFunctionTokenIndices: int[], outResult: int[]): int {
    tokens := new ColumnarFunctionTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    signatureOutputs := new ColumnarFunctionSignatureOutputTable(outFunctionNameTexts, outReturnTypeTexts, outParamNameTexts, outParamTypeTexts, outParamModifierKinds, outParamDefaultKinds, outParamDefaultTexts, outParamTupleNameCounts, outParamTupleNameTexts, outReturnTupleNameTexts, outReturnLabeledTypeTexts, outParamLabeledTypeTexts, outTypeParamTexts, outTypeParamSpecials, outTypeParamConstraintCounts, outTypeParamConstraintTypeTexts)
    body := new ColumnarFunctionBodyTable(outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths)
    locals := new ColumnarFunctionLocalTable(outLocalFunctionNodeIndices, outLocalFunctionTokenIndices)
    result := new ColumnarFunctionResultTable(outResult)
    return ParseColumnarFunctionInfoCore(source, tokens, funcIndex, isLocalFunction, signatureOutputs, body, locals, result)
}

func ParseColumnarProductFunctionSignatureInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, outFunctionNameTexts: string[], outReturnTypeTexts: string[], outParamNameTexts: string[], outParamTypeTexts: string[], outParamModifierKinds: int[], outParamDefaultKinds: int[], outParamDefaultTexts: string[], outParamTupleNameCounts: int[], outParamTupleNameTexts: string[], outReturnTupleNameTexts: string[], outReturnLabeledTypeTexts: string[], outParamLabeledTypeTexts: string[], outTypeParamTexts: string[], outTypeParamSpecials: int[], outTypeParamConstraintCounts: int[], outTypeParamConstraintTypeTexts: string[], outResult: int[]): int {
    tokens := new ColumnarFunctionTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    signatureOutputs := new ColumnarFunctionSignatureOutputTable(outFunctionNameTexts, outReturnTypeTexts, outParamNameTexts, outParamTypeTexts, outParamModifierKinds, outParamDefaultKinds, outParamDefaultTexts, outParamTupleNameCounts, outParamTupleNameTexts, outReturnTupleNameTexts, outReturnLabeledTypeTexts, outParamLabeledTypeTexts, outTypeParamTexts, outTypeParamSpecials, outTypeParamConstraintCounts, outTypeParamConstraintTypeTexts)
    return ParseColumnarFunctionSignatureOnlyInfoCore(source, tokens, funcIndex, signatureOutputs, new ColumnarFunctionResultTable(outResult))
}

func ParseColumnarFunctionSignatureOnlyInfoCore(source: string, tokens: ColumnarFunctionTokenTable, funcIndex: int, signatureOutputs: ColumnarFunctionSignatureOutputTable, result: ColumnarFunctionResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    signatureOutput := new FunctionSignatureInfoOutputTable(signatureOutputs.FunctionNameTexts, signatureOutputs.ReturnTypeTexts, signatureOutputs.ParamNameTexts, signatureOutputs.ParamTypeTexts, signatureOutputs.ParamModifierKinds, signatureOutputs.ParamDefaultKinds, signatureOutputs.ParamDefaultTexts, signatureOutputs.ParamTupleNameCounts, signatureOutputs.ParamTupleNameTexts, signatureOutputs.ReturnTupleNameTexts, signatureOutputs.ReturnLabeledTypeTexts, signatureOutputs.ParamLabeledTypeTexts, signatureOutputs.TypeParamTexts, signatureOutputs.TypeParamSpecials, signatureOutputs.TypeParamConstraintCounts, signatureOutputs.TypeParamConstraintTypeTexts)
    typeStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserNodeTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    children := new ParserChildIndexTable(new int[](tokens.Count + 1))
    canonicalNodes := new TypeReferenceCanonicalTable(nodes.Kinds, nodes.ValueStarts, nodes.ValueLengths, nodes.ChildStart, nodes.ChildCount, children.Indices)
    parameters := new ParserFunctionParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    functionSignatureResult := new ParserResultTable(new int[](8))
    ownerIndices := new FunctionSignatureOwnerIndexTable(new int[](tokens.Count + 1))
    tupleNames := new FunctionSignatureTupleNameScratchTable(new string[](tokens.Count + 1))
    signatureResult := new ParserResultTable(result.Values)
    return ParseFunctionSignatureInfoCore(source, signatureTokens, tokens.Count, funcIndex, signatureOutput, typeStack, nodes, children, canonicalNodes, parameters, typeParams, whereItems, functionSignatureResult, ownerIndices, tupleNames, signatureResult)
}

func ParseColumnarFunctionInfoCore(source: string, tokens: ColumnarFunctionTokenTable, funcIndex: int, isLocalFunction: int, signatureOutputs: ColumnarFunctionSignatureOutputTable, body: ColumnarFunctionBodyTable, locals: ColumnarFunctionLocalTable, result: ColumnarFunctionResultTable): int {
    if result.Values.Length < 9 {
        return -1
    }

    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    signatureOutput := new FunctionSignatureInfoOutputTable(signatureOutputs.FunctionNameTexts, signatureOutputs.ReturnTypeTexts, signatureOutputs.ParamNameTexts, signatureOutputs.ParamTypeTexts, signatureOutputs.ParamModifierKinds, signatureOutputs.ParamDefaultKinds, signatureOutputs.ParamDefaultTexts, signatureOutputs.ParamTupleNameCounts, signatureOutputs.ParamTupleNameTexts, signatureOutputs.ReturnTupleNameTexts, signatureOutputs.ReturnLabeledTypeTexts, signatureOutputs.ParamLabeledTypeTexts, signatureOutputs.TypeParamTexts, signatureOutputs.TypeParamSpecials, signatureOutputs.TypeParamConstraintCounts, signatureOutputs.TypeParamConstraintTypeTexts)
    typeStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserNodeTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    children := new ParserChildIndexTable(new int[](tokens.Count + 1))
    canonicalNodes := new TypeReferenceCanonicalTable(nodes.Kinds, nodes.ValueStarts, nodes.ValueLengths, nodes.ChildStart, nodes.ChildCount, children.Indices)
    parameters := new ParserFunctionParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    functionSignatureResult := new ParserResultTable(new int[](8))
    ownerIndices := new FunctionSignatureOwnerIndexTable(new int[](tokens.Count + 1))
    tupleNames := new FunctionSignatureTupleNameScratchTable(new string[](tokens.Count + 1))
    signatureResult := new ParserResultTable(new int[](6))
    paramCount := ParseFunctionSignatureInfoCore(source, signatureTokens, tokens.Count, funcIndex, signatureOutput, typeStack, nodes, children, canonicalNodes, parameters, typeParams, whereItems, functionSignatureResult, ownerIndices, tupleNames, signatureResult)
    if paramCount < 0 {
        return -1
    }

    bodyBrace := signatureResult.Values[1]
    if bodyBrace < 0 || bodyBrace >= tokens.Count || (tokens.Kinds[bodyBrace] != 129 && tokens.Kinds[bodyBrace] != 120) {
        return -1
    }

    bodyResult := new ColumnarFunctionResultTable(new int[](2))
    bodyNodeCount := 0
    if tokens.Kinds[bodyBrace] == 129 {
        bodyNodeCount = ParseColumnarFunctionBodyNodesCore(source, tokens, bodyBrace, body, bodyResult)
    } else {
        // WHAT AN EXPRESSION BODY MEANS DEPENDS ON THE DECLARED RETURN, and only the signature knows
        // it. A value function's `=> expr` RETURNS the expression; a `void` one's PERFORMS it, so it
        // is an expression statement. (An omitted return type canonicalizes to `void` above, which is
        // the same answer.) Lowering both as a return made `func write(t: string): void =>
        // log.Append(t)` emit `return <value>` from a void method and decline at emit.body.
        bodyNodeCount = ParseColumnarFunctionExpressionBodyNodesCore(source, tokens, bodyBrace, signatureOutputs.ReturnTypeTexts[0] == "void", body, bodyResult)
    }

    if bodyNodeCount <= 0 {
        return -1
    }

    bodyRoot := bodyResult.Values[0]
    if bodyRoot < 0 || bodyRoot >= bodyNodeCount {
        return -1
    }

    localTokens := new LocalFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.Count)
    localNodes := new LocalFunctionNodeTable(body.NodeKinds, body.ValueStarts, body.ChildStart, body.ChildCount, body.ChildIndices)
    localResults := new LocalFunctionResultTable(locals.NodeIndices, locals.TokenIndices)
    localFunctionCount := DirectLocalFunctionTokenIndicesCore(localTokens, localNodes, bodyRoot, localResults)
    if localFunctionCount < 0 {
        return -1
    }

    if ColumnarFunctionLocalFunctionNamesDistinct(source, tokens, locals, localFunctionCount) == 0 {
        return -1
    }

    if isLocalFunction != 0 && localFunctionCount > 0 {
        return -1
    }

    result.Values[0] = signatureResult.Values[0]
    result.Values[1] = bodyBrace
    result.Values[2] = signatureResult.Values[2]
    result.Values[3] = signatureResult.Values[3]
    result.Values[4] = signatureResult.Values[4]
    result.Values[5] = signatureResult.Values[5]
    result.Values[6] = bodyRoot
    result.Values[7] = bodyNodeCount
    result.Values[8] = localFunctionCount
    return paramCount
}

func ParseColumnarFunctionBodyNodesCore(source: string, tokens: ColumnarFunctionTokenTable, bodyBrace: int, body: ColumnarFunctionBodyTable, result: ColumnarFunctionResultTable): int {
    statementTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    argStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    children := new ParserChildIndexTable(body.ChildIndices)
    statementResult := new ParserResultTable(result.Values)
    return ParseStatementNodesCore(source, statementTokens, tokens.Count, bodyBrace, argStack, nodes, children, statementResult)
}

// AN EXPRESSION BODY AS A BODY NODE. `returnsVoid` chooses which statement the expression becomes:
// a ReturnStatement (kind 20) carrying the value, or an ExpressionStatement (kind 23) performing it.
func ParseColumnarFunctionExpressionBodyNodesCore(source: string, tokens: ColumnarFunctionTokenTable, arrowIndex: int, returnsVoid: bool, body: ColumnarFunctionBodyTable, result: ColumnarFunctionResultTable): int {
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
    // A `void` body is an expression STATEMENT (kind 23) — `=> log.Append(t)` is a call, not a
    // return. A throw body is the exception: `=> throw e` on a `void` function keeps the synthesized
    // return (kind 20), which is the shape the return owner ends with `throw`; as an expression
    // statement a throw has no owner and the body would decline.
    bodyStatementKind := 20
    if returnsVoid && nodes.Kinds[valueRoot] != 83 {
        bodyStatementKind = 23
    }

    bodyStatementNode := EmitExpressionNode(st, nodes, bodyStatementKind, -1, 0, childRunStart, 1, tokens.Starts[arrowIndex], valueEnd - tokens.Starts[arrowIndex])
    result.Values[0] = bodyStatementNode
    result.Values[1] = st.Pos
    return st.NodeCursor
}

func ColumnarFunctionLocalFunctionNamesDistinct(source: string, tokens: ColumnarFunctionTokenTable, locals: ColumnarFunctionLocalTable, localFunctionCount: int): int {
    if localFunctionCount < 0 {
        return 0
    }

    i := 0
    while i < localFunctionCount {
        nameToken := locals.TokenIndices[i] + 1
        if nameToken < 0 || nameToken >= tokens.Count || tokens.Kinds[nameToken] != 0 {
            return 0
        }

        j := i + 1
        while j < localFunctionCount {
            otherNameToken := locals.TokenIndices[j] + 1
            if otherNameToken < 0 || otherNameToken >= tokens.Count || tokens.Kinds[otherNameToken] != 0 {
                return 0
            }

            if ParserDeclarationSourceSpansEqual(source, tokens.Starts[nameToken], tokens.ValueLengths[nameToken], tokens.Starts[otherNameToken], tokens.ValueLengths[otherNameToken]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ParseColumnarConstructorInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outParamNameTexts: string[], outParamTypeTexts: string[], outParamLabeledTypeTexts: string[], outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outArgTexts: string[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    tokens := new ColumnarConstructorTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    signatureOutputs := new ColumnarConstructorSignatureOutputTable(outParamNameTexts, outParamTypeTexts, outParamLabeledTypeTexts, outArgKinds, outArgStarts, outArgLengths, outArgTexts)
    body := new ColumnarConstructorBodyTable(outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths)
    result := new ColumnarConstructorResultTable(outResult)
    return ParseColumnarConstructorInfoCore(source, tokens, ctorIndex, signatureOutputs, body, result)
}

func ParseColumnarConstructorInfoCore(source: string, tokens: ColumnarConstructorTokenTable, ctorIndex: int, signatureOutputs: ColumnarConstructorSignatureOutputTable, body: ColumnarConstructorBodyTable, result: ColumnarConstructorResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    if ctorIndex >= 0 && ctorIndex < tokens.Count && (tokens.Kinds[ctorIndex] == 8 || tokens.Kinds[ctorIndex] == 9 || tokens.Kinds[ctorIndex] == 13) {
        return ParseColumnarPrimaryConstructorInfoCore(source, tokens, ctorIndex, signatureOutputs, body, result)
    }

    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    signatureOutput := new ConstructorSignatureOutputTable(signatureOutputs.ParamNameTexts, signatureOutputs.ParamTypeTexts, signatureOutputs.ParamLabeledTypeTexts, signatureOutputs.ArgKinds, signatureOutputs.ArgStarts, signatureOutputs.ArgLengths, signatureOutputs.ArgTexts)
    typeStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserNodeTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    children := new ParserChildIndexTable(new int[](tokens.Count + 1))
    canonicalNodes := new TypeReferenceCanonicalTable(nodes.Kinds, nodes.ValueStarts, nodes.ValueLengths, nodes.ChildStart, nodes.ChildCount, children.Indices)
    parameters := new ParserFunctionParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    functionSignatureResult := new ParserResultTable(new int[](8))
    signatureResult := new ParserResultTable(new int[](4))
    paramCount := ParseConstructorSignatureInfoCore(source, signatureTokens, tokens.Count, ctorIndex, signatureOutput, typeStack, nodes, children, canonicalNodes, parameters, typeParams, whereItems, functionSignatureResult, signatureResult)
    if paramCount < 0 {
        return -1
    }

    bodyBrace := signatureResult.Values[1]
    if bodyBrace < 0 || bodyBrace >= tokens.Count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    bodyResult := new ColumnarConstructorResultTable(new int[](2))
    bodyNodeCount := ParseColumnarConstructorBodyNodesCore(source, tokens, bodyBrace, body, bodyResult)
    if bodyNodeCount <= 0 {
        return -1
    }

    bodyRoot := bodyResult.Values[0]
    if bodyRoot < 0 || bodyRoot >= bodyNodeCount {
        return -1
    }

    result.Values[0] = signatureResult.Values[0]
    result.Values[1] = bodyBrace
    result.Values[2] = signatureResult.Values[2]
    result.Values[3] = signatureResult.Values[3]
    result.Values[4] = bodyRoot
    result.Values[5] = bodyNodeCount
    return paramCount
}

func ColumnarPrimaryConstructorTypeIsNullable(source: string, typeStart: int, typeLength: int): bool {
    if typeStart < 0 || typeLength <= 0 || typeStart + typeLength > source.Length {
        return false
    }

    return source[typeStart + typeLength - 1] == '?'
}

func EmitColumnarPrimaryConstructorAssignmentNode(body: ColumnarConstructorBodyTable, fieldStart: int, fieldLength: int, valueKind: int, valueStart: int, valueLength: int, eqStart: int, eqLength: int, nodeCursor: int, childCursor: int, result: ColumnarConstructorResultTable): int {
    if result.Values.Length < 2 {
        return -1
    }

    if nodeCursor + 4 > body.NodeKinds.Length || childCursor + 3 > body.ChildIndices.Length {
        return -1
    }

    targetNode := nodeCursor
    body.NodeKinds[targetNode] = 6
    body.ValueStarts[targetNode] = fieldStart
    body.ValueLengths[targetNode] = fieldLength
    body.ChildStart[targetNode] = -1
    body.ChildCount[targetNode] = 0
    body.SpanStarts[targetNode] = fieldStart
    body.SpanLengths[targetNode] = fieldLength
    nodeCursor = nodeCursor + 1

    valueNode := nodeCursor
    body.NodeKinds[valueNode] = valueKind
    body.ValueStarts[valueNode] = valueStart
    body.ValueLengths[valueNode] = valueLength
    body.ChildStart[valueNode] = -1
    body.ChildCount[valueNode] = 0
    body.SpanStarts[valueNode] = valueStart
    body.SpanLengths[valueNode] = valueLength
    nodeCursor = nodeCursor + 1

    assignmentNode := nodeCursor
    body.NodeKinds[assignmentNode] = 14
    body.ValueStarts[assignmentNode] = eqStart
    body.ValueLengths[assignmentNode] = eqLength
    body.ChildStart[assignmentNode] = childCursor
    body.ChildCount[assignmentNode] = 2
    body.ChildIndices[childCursor] = targetNode
    body.ChildIndices[childCursor + 1] = valueNode
    body.SpanStarts[assignmentNode] = fieldStart
    if valueStart >= 0 {
        body.SpanLengths[assignmentNode] = valueStart + valueLength - fieldStart
    } else {
        body.SpanLengths[assignmentNode] = fieldLength
    }

    childCursor = childCursor + 2
    nodeCursor = nodeCursor + 1

    statementNode := nodeCursor
    body.NodeKinds[statementNode] = 23
    body.ValueStarts[statementNode] = -1
    body.ValueLengths[statementNode] = 0
    body.ChildStart[statementNode] = childCursor
    body.ChildCount[statementNode] = 1
    body.ChildIndices[childCursor] = assignmentNode
    body.SpanStarts[statementNode] = fieldStart
    if valueStart >= 0 {
        body.SpanLengths[statementNode] = valueStart + valueLength - fieldStart
    } else {
        body.SpanLengths[statementNode] = fieldLength
    }

    childCursor = childCursor + 1
    nodeCursor = nodeCursor + 1

    result.Values[0] = nodeCursor
    result.Values[1] = childCursor
    return statementNode
}

func EmitColumnarPrimaryConstructorAssignmentRootNode(body: ColumnarConstructorBodyTable, fieldStart: int, fieldLength: int, valueRoot: int, eqStart: int, eqLength: int, nodeCursor: int, childCursor: int, result: ColumnarConstructorResultTable): int {
    if result.Values.Length < 2 {
        return -1
    }

    if valueRoot < 0 || valueRoot >= nodeCursor || nodeCursor + 3 > body.NodeKinds.Length || childCursor + 3 > body.ChildIndices.Length {
        return -1
    }

    targetNode := nodeCursor
    body.NodeKinds[targetNode] = 6
    body.ValueStarts[targetNode] = fieldStart
    body.ValueLengths[targetNode] = fieldLength
    body.ChildStart[targetNode] = -1
    body.ChildCount[targetNode] = 0
    body.SpanStarts[targetNode] = fieldStart
    body.SpanLengths[targetNode] = fieldLength
    nodeCursor = nodeCursor + 1

    assignmentNode := nodeCursor
    body.NodeKinds[assignmentNode] = 14
    body.ValueStarts[assignmentNode] = eqStart
    body.ValueLengths[assignmentNode] = eqLength
    body.ChildStart[assignmentNode] = childCursor
    body.ChildCount[assignmentNode] = 2
    body.ChildIndices[childCursor] = targetNode
    body.ChildIndices[childCursor + 1] = valueRoot
    body.SpanStarts[assignmentNode] = fieldStart
    body.SpanLengths[assignmentNode] = body.SpanStarts[valueRoot] + body.SpanLengths[valueRoot] - fieldStart
    childCursor = childCursor + 2
    nodeCursor = nodeCursor + 1

    statementNode := nodeCursor
    body.NodeKinds[statementNode] = 23
    body.ValueStarts[statementNode] = -1
    body.ValueLengths[statementNode] = 0
    body.ChildStart[statementNode] = childCursor
    body.ChildCount[statementNode] = 1
    body.ChildIndices[childCursor] = assignmentNode
    body.SpanStarts[statementNode] = fieldStart
    body.SpanLengths[statementNode] = body.SpanStarts[valueRoot] + body.SpanLengths[valueRoot] - fieldStart
    childCursor = childCursor + 1
    nodeCursor = nodeCursor + 1

    result.Values[0] = nodeCursor
    result.Values[1] = childCursor
    return statementNode
}

func ParseColumnarPrimaryConstructorInfoCore(source: string, tokens: ColumnarConstructorTokenTable, ctorIndex: int, signatureOutputs: ColumnarConstructorSignatureOutputTable, body: ColumnarConstructorBodyTable, result: ColumnarConstructorResultTable): int {
    pos := ctorIndex + 1
    // `record struct Name(...)` — skip the record-struct TAIL Struct token before the name.
    if pos < tokens.Count && tokens.Kinds[ctorIndex] == 13 && tokens.Kinds[pos] == 9 {
        pos = pos + 1
    }

    if pos >= tokens.Count || tokens.Kinds[pos] != 0 {
        return -1
    }

    pos = pos + 1

    if pos < tokens.Count && tokens.Kinds[pos] == 100 {
        gdepth := 0
        gdone := 0
        while pos < tokens.Count && gdone == 0 {
            if tokens.Kinds[pos] == 100 {
                gdepth = gdepth + 1
            } else if tokens.Kinds[pos] == 102 {
                gdepth = gdepth - 1
                if gdepth == 0 {
                    gdone = 1
                }
            } else if tokens.Kinds[pos] == 112 {
                gdepth = gdepth - 2
                if gdepth == 0 {
                    gdone = 1
                }
            }

            if gdepth < 0 {
                return -1
            }

            pos = pos + 1
        }

        if gdone == 0 {
            return -1
        }
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    primaryParameters := new PrimaryConstructorParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    primaryResult := new ParserDeclarationResultTable(new int[](1))
    paramCount := 0
    if pos < tokens.Count && tokens.Kinds[pos] == 127 {
        paramCount = ParsePrimaryConstructorParameterSpansCore(source, declarationTokens, tokens.Count, pos, primaryParameters, primaryResult)
    } else {
        primaryResult.Values[0] = pos
    }

    if paramCount < 0 || paramCount > signatureOutputs.ParamNameTexts.Length || paramCount > signatureOutputs.ParamTypeTexts.Length || paramCount > signatureOutputs.ArgKinds.Length || paramCount > signatureOutputs.ArgTexts.Length {
        return -1
    }

    p := 0
    while p < paramCount {
        paramName := ParserDeclarationSpanText(source, primaryParameters.NameStarts[p], primaryParameters.NameLengths[p])
        paramType := ParserDeclarationCanonicalTypeText(source, primaryParameters.TypeStarts[p], primaryParameters.TypeLengths[p])
        if paramName == "" || paramType == "" {
            return -1
        }

        signatureOutputs.ParamNameTexts[p] = paramName
        signatureOutputs.ParamTypeTexts[p] = paramType
        if p < signatureOutputs.ParamLabeledTypeTexts.Length {
            // A PRIMARY constructor's parameter types are read as text spans rather than from a
            // type-reference tree, so the labelled spelling is the spelling already read.
            signatureOutputs.ParamLabeledTypeTexts[p] = paramType
        }

        signatureOutputs.ArgKinds[p] = primaryParameters.DefaultKinds[p]
        if primaryParameters.DefaultKinds[p] >= 0 {
            if primaryParameters.DefaultKinds[p] == ParserDeclarationDefaultMemberAccessKind() {
                signatureOutputs.ArgTexts[p] = ParserDeclarationCanonicalDottedNameText(source, primaryParameters.DefaultStarts[p], primaryParameters.DefaultLengths[p])
            } else {
                signatureOutputs.ArgTexts[p] = ParserDeclarationSpanText(source, primaryParameters.DefaultStarts[p], primaryParameters.DefaultLengths[p])
            }
        } else {
            signatureOutputs.ArgTexts[p] = ""
        }

        p = p + 1
    }

    // THE BASE / INTERFACE LIST, READ AS THE TYPE REFERENCES IT HOLDS. Each entry used to be assumed
    // to be a single Identifier, so `class Catalogue: Collection<Item>` left the scan sitting on the
    // `<` and this whole kernel answered -1 — which the caller reports as `parse.struct` on the class
    // header. A type with a GENERIC base and any instance field initializer was refused outright, and
    // the same naive reading had no answer for a `where` clause either. The declaration parser's own
    // type-span and constraint kernels answer both.
    pos = primaryResult.Values[0]
    baseTypeResult := new ParserDeclarationResultTable(new int[](2))
    if pos < tokens.Count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        while true {
            pos = ParseDeclarationTypeSpanCore(declarationTokens, tokens.Count, pos, baseTypeResult)
            if pos < 0 {
                return -1
            }

            if pos < tokens.Count && tokens.Kinds[pos] == 134 {
                pos = pos + 1
                continue
            }

            break
        }
    }

    whereScratch := new ParserDeclarationWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    whereNext := pos
    if ParseDeclarationWhereClausesCore(declarationTokens, tokens.Count, pos, whereScratch, out whereNext) < 0 {
        return -1
    }

    pos = whereNext

    bodyBrace := pos
    if bodyBrace < 0 || bodyBrace >= tokens.Count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    statementIndices := new int[](tokens.Count + 1)
    assignedFlags := new int[](tokens.Count + 1)
    nodeCursor := 0
    childCursor := 0
    assignmentCount := 0
    cursorResult := new ColumnarConstructorResultTable(new int[](2))
    typeResult := new ParserDeclarationResultTable(new int[](2))
    memberModifierValues := new int[](2)
    memberModifiers := new ParserDeclarationResultTable(memberModifierValues)
    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    expressionNodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    expressionChildren := new ParserChildIndexTable(body.ChildIndices)
    expressionStack := new ParserArgumentStack(new int[](tokens.Count + 1))

    // THE WHOLE BODY, NOT THE RUN OF FIELDS AT THE TOP OF IT. This scan used to stop at the first
    // `func` or constructor, exactly as the member scan did, so a field written AFTER a method kept
    // its declaration but silently lost its INITIALIZER: `N: int = 7` below a method left `N` at
    // zero, with no diagnostic anywhere. Methods, constructors, nested types and events are stepped
    // over now and the fields between them are all read, in declaration order.
    scan := bodyBrace + 1
    while scan < tokens.Count && tokens.Kinds[scan] != 130 {
        memberStart := ParseMemberModifierPrefixCore(source, declarationTokens, tokens.Count, scan, memberModifiers)
        if memberStart < 0 || memberStart >= tokens.Count {
            return -1
        }

        // A VALUE MEMBER'S NAME MAY BE QUALIFIED. `IReadOnlyCollection<string>.Count: int => …` is an
        // explicit interface implementation, and THIS IS THE THIRD WALK OF A TYPE'S BODY — the
        // synthesized instance-initializer constructor's — so it has to agree with the other two about
        // where a member's name ends. It used to read the `:` one token in, so a qualified value member
        // matched no arm at all and the WHOLE declaration declined at `parse.struct`.
        storageNameEnd := ParseDeclarationMemberNameEnd(declarationTokens, tokens.Count, memberStart)

        if tokens.Kinds[memberStart] == 7 || tokens.Kinds[memberStart] == 85 || tokens.Kinds[memberStart] == 86 {
            methodSignatureEnd := ParseDeclarationFunctionSignatureEndCore(source, declarationTokens, tokens.Count, memberStart)
            if methodSignatureEnd < 0 || methodSignatureEnd >= tokens.Count {
                return -1
            }

            if tokens.Kinds[methodSignatureEnd] != 129 && tokens.Kinds[methodSignatureEnd] != 120 {
                scan = methodSignatureEnd
            } else {
                scan = ParseDeclarationMemberBodyEndCore(source, declarationTokens, tokens.Count, methodSignatureEnd)
                if scan < 0 {
                    return -1
                }
            }
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 1 < tokens.Count && tokens.Kinds[memberStart + 1] == 127 {
            scan = ParseDeclarationMemberBodyEndCore(source, declarationTokens, tokens.Count, memberStart + 1)
            if scan < 0 {
                return -1
            }
        } else if ParseDeclarationNestedTypeDeclarationKind(tokens.Kinds[memberStart]) {
            scan = ParseDeclarationSkipDeclarationBlockCore(declarationTokens, tokens.Count, memberStart)
            if scan < 0 {
                return -1
            }
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 2 < tokens.Count && tokens.Kinds[memberStart + 1] == 0 && tokens.Kinds[memberStart + 2] == 122 && ParserDeclarationTokenTextEquals(source, tokens.Starts[memberStart], tokens.ValueLengths[memberStart], "event") {
            // A field-like EVENT declares its storage but never carries a written initializer.
            scan = ParseDeclarationTypeSpanCore(declarationTokens, tokens.Count, memberStart + 3, typeResult)
            if scan < 0 {
                return -1
            }
        } else if tokens.Kinds[memberStart] == 0 && storageNameEnd < tokens.Count && tokens.Kinds[storageNameEnd] == 122 {
            fieldNameStart := tokens.Starts[memberStart]
            fieldNameLength := ParseDeclarationMemberNameSpanLength(declarationTokens, memberStart, storageNameEnd)
            scan = storageNameEnd + 1
            scan = ParseDeclarationTypeSpanCore(declarationTokens, tokens.Count, scan, typeResult)
            if scan < 0 {
                return -1
            }

            if scan < tokens.Count && tokens.Kinds[scan] == 129 {
                pdepth := 0
                pdone := 0
                while scan < tokens.Count && pdone == 0 {
                    if tokens.Kinds[scan] == 129 {
                        pdepth = pdepth + 1
                    } else if tokens.Kinds[scan] == 130 {
                        pdepth = pdepth - 1
                        if pdepth == 0 {
                            pdone = 1
                        }
                    }

                    scan = scan + 1
                }

                if pdone == 0 {
                    return -1
                }
            } else if scan < tokens.Count && tokens.Kinds[scan] == 120 {
                while scan < tokens.Count && tokens.Kinds[scan] != 136 && tokens.Kinds[scan] != 130 {
                    scan = scan + 1
                }

                if scan < tokens.Count && tokens.Kinds[scan] == 136 {
                    scan = scan + 1
                }
            } else {
                valueKind := -1
                valueStart := -1
                valueLength := 0
                eqStart := -1
                eqLength := 1
                valueRoot := -1
                if scan < tokens.Count && tokens.Kinds[scan] == 93 {
                    eqStart = tokens.Starts[scan]
                    eqLength = tokens.ValueLengths[scan]
                    scan = scan + 1
                    if scan >= tokens.Count {
                        return -1
                    }

                    // EVERY written initializer is an ordinary expression — a lone literal and
                    // `3 + 4` take the same path, so a literal opening token can no longer strand
                    // the rest of the expression in the member scan.
                    expressionState := new ParserState(scan, nodeCursor, childCursor, 0, 0, 0)
                    valueRoot = ParseLambdaOrAssignmentExpressionNode(expressionTokens, tokens.Count, expressionState, expressionStack, expressionNodes, expressionChildren, 0)
                    if valueRoot < 0 || expressionState.Pos <= scan {
                        return -1
                    }

                    // Only a BARE parameter name makes this field the primary parameter's storage.
                    if tokens.Kinds[scan] == 0 && expressionState.Pos == scan + 1 {
                        paramIndex := PrimaryConstructorParameterIndexOf(source, primaryParameters, paramCount, tokens.Starts[scan], tokens.ValueLengths[scan])
                        if paramIndex >= 0 {
                            assignedFlags[paramIndex] = 1
                        }
                    }

                    nodeCursor = expressionState.NodeCursor
                    childCursor = expressionState.ChildCursor
                    scan = expressionState.Pos
                } else if ColumnarPrimaryConstructorTypeIsNullable(source, typeResult.Values[0], typeResult.Values[1]) {
                    valueKind = ColumnarExpressionNodeKind.NullLiteralExpression
                } else {
                    matchedParam := PrimaryConstructorParameterIndexOf(source, primaryParameters, paramCount, fieldNameStart, fieldNameLength)
                    if matchedParam >= 0 {
                        assignedFlags[matchedParam] = 1
                        valueKind = 6
                        valueStart = primaryParameters.NameStarts[matchedParam]
                        valueLength = primaryParameters.NameLengths[matchedParam]
                    }
                }

                if valueKind >= 0 && memberModifiers.Values[0] == 0 {
                    statementNode := EmitColumnarPrimaryConstructorAssignmentNode(body, fieldNameStart, fieldNameLength, valueKind, valueStart, valueLength, eqStart, eqLength, nodeCursor, childCursor, cursorResult)
                    if statementNode < 0 || assignmentCount >= statementIndices.Length {
                        return -1
                    }

                    nodeCursor = cursorResult.Values[0]
                    childCursor = cursorResult.Values[1]
                    statementIndices[assignmentCount] = statementNode
                    assignmentCount = assignmentCount + 1
                } else if valueRoot >= 0 && memberModifiers.Values[0] == 0 {
                    statementNode := EmitColumnarPrimaryConstructorAssignmentRootNode(body, fieldNameStart, fieldNameLength, valueRoot, eqStart, eqLength, nodeCursor, childCursor, cursorResult)
                    if statementNode < 0 || assignmentCount >= statementIndices.Length {
                        return -1
                    }

                    nodeCursor = cursorResult.Values[0]
                    childCursor = cursorResult.Values[1]
                    statementIndices[assignmentCount] = statementNode
                    assignmentCount = assignmentCount + 1
                }
            }
        } else {
            return -1
        }
    }

    if tokens.Kinds[ctorIndex] == 8 || tokens.Kinds[ctorIndex] == 9 || tokens.Kinds[ctorIndex] == 13 {
        p = 0
        while p < paramCount {
            if assignedFlags[p] == 0 {
                statementNode := EmitColumnarPrimaryConstructorAssignmentNode(body, primaryParameters.NameStarts[p], primaryParameters.NameLengths[p], 6, primaryParameters.NameStarts[p], primaryParameters.NameLengths[p], -1, 1, nodeCursor, childCursor, cursorResult)
                if statementNode < 0 || assignmentCount >= statementIndices.Length {
                    return -1
                }

                nodeCursor = cursorResult.Values[0]
                childCursor = cursorResult.Values[1]
                statementIndices[assignmentCount] = statementNode
                assignmentCount = assignmentCount + 1
            }

            p = p + 1
        }
    }

    if nodeCursor >= body.NodeKinds.Length || childCursor + assignmentCount > body.ChildIndices.Length {
        return -1
    }

    root := nodeCursor
    body.NodeKinds[root] = 25
    body.ValueStarts[root] = -1
    body.ValueLengths[root] = 0
    body.ChildStart[root] = childCursor
    body.ChildCount[root] = assignmentCount
    body.SpanStarts[root] = tokens.Starts[bodyBrace]
    body.SpanLengths[root] = tokens.ValueLengths[bodyBrace]
    i := 0
    while i < assignmentCount {
        body.ChildIndices[childCursor + i] = statementIndices[i]
        i = i + 1
    }

    nodeCursor = nodeCursor + 1

    result.Values[0] = 0
    result.Values[1] = bodyBrace
    result.Values[2] = paramCount
    result.Values[3] = 0
    result.Values[4] = root
    result.Values[5] = nodeCursor
    return paramCount
}

func ParseColumnarConstructorBodyNodesCore(source: string, tokens: ColumnarConstructorTokenTable, bodyBrace: int, body: ColumnarConstructorBodyTable, result: ColumnarConstructorResultTable): int {
    statementTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    argStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    children := new ParserChildIndexTable(body.ChildIndices)
    statementResult := new ParserResultTable(result.Values)
    return ParseStatementNodesCore(source, statementTokens, tokens.Count, bodyBrace, argStack, nodes, children, statementResult)
}
