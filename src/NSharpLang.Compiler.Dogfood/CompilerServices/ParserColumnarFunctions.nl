// Product columnar function parser wrapper. It composes the signature rowset, statement-node rowset, and
// direct local-function discovery so the C# adapter only materializes ColumnarFunctionInput containers.

struct ColumnarFunctionTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
}

struct ColumnarFunctionSignatureOutputTable {
    FunctionNameTexts: string[]
    ReturnTypeTexts: string[]
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ParamTupleNameCounts: int[]
    ParamTupleNameTexts: string[]
    ReturnTupleNameTexts: string[]
    TypeParamTexts: string[]
    TypeParamSpecials: int[]
    TypeParamConstraintCounts: int[]
    TypeParamConstraintTypeTexts: string[]
}

struct ColumnarFunctionBodyTable {
    NodeKinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    SpanStarts: int[]
    SpanLengths: int[]
}

struct ColumnarFunctionLocalTable {
    NodeIndices: int[]
    TokenIndices: int[]
}

struct ColumnarFunctionResultTable {
    Values: int[]
}

func ParseColumnarFunctionInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, outFunctionNameTexts: string[], outReturnTypeTexts: string[], outParamNameTexts: string[], outParamTypeTexts: string[], outParamTupleNameCounts: int[], outParamTupleNameTexts: string[], outReturnTupleNameTexts: string[], outTypeParamTexts: string[], outTypeParamSpecials: int[], outTypeParamConstraintCounts: int[], outTypeParamConstraintTypeTexts: string[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outLocalFunctionNodeIndices: int[], outLocalFunctionTokenIndices: int[], outResult: int[]): int {
    tokens := new ColumnarFunctionTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    signatureOutputs := new ColumnarFunctionSignatureOutputTable { FunctionNameTexts: outFunctionNameTexts, ReturnTypeTexts: outReturnTypeTexts, ParamNameTexts: outParamNameTexts, ParamTypeTexts: outParamTypeTexts, ParamTupleNameCounts: outParamTupleNameCounts, ParamTupleNameTexts: outParamTupleNameTexts, ReturnTupleNameTexts: outReturnTupleNameTexts, TypeParamTexts: outTypeParamTexts, TypeParamSpecials: outTypeParamSpecials, TypeParamConstraintCounts: outTypeParamConstraintCounts, TypeParamConstraintTypeTexts: outTypeParamConstraintTypeTexts }
    body := new ColumnarFunctionBodyTable { NodeKinds: outNodeKinds, ValueStarts: outValueStarts, ValueLengths: outValueLengths, ChildStart: outChildStart, ChildCount: outChildCount, ChildIndices: outChildIndices, SpanStarts: outSpanStarts, SpanLengths: outSpanLengths }
    locals := new ColumnarFunctionLocalTable { NodeIndices: outLocalFunctionNodeIndices, TokenIndices: outLocalFunctionTokenIndices }
    result := new ColumnarFunctionResultTable { Values: outResult }
    return ParseColumnarFunctionInfoCore(source, ref tokens, funcIndex, ref signatureOutputs, ref body, ref locals, ref result)
}

func ParseColumnarFunctionInfoCore(source: string, tokens: &ColumnarFunctionTokenTable, funcIndex: int, signatureOutputs: &ColumnarFunctionSignatureOutputTable, body: &ColumnarFunctionBodyTable, locals: &ColumnarFunctionLocalTable, result: &ColumnarFunctionResultTable): int {
    if result.Values.Length < 9 {
        return -1
    }

    signatureTokens := new ParserTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    signatureOutput := new FunctionSignatureInfoOutputTable { FunctionNameTexts: signatureOutputs.FunctionNameTexts, ReturnTypeTexts: signatureOutputs.ReturnTypeTexts, ParamNameTexts: signatureOutputs.ParamNameTexts, ParamTypeTexts: signatureOutputs.ParamTypeTexts, ParamTupleNameCounts: signatureOutputs.ParamTupleNameCounts, ParamTupleNameTexts: signatureOutputs.ParamTupleNameTexts, ReturnTupleNameTexts: signatureOutputs.ReturnTupleNameTexts, TypeParamTexts: signatureOutputs.TypeParamTexts, TypeParamSpecials: signatureOutputs.TypeParamSpecials, TypeParamConstraintCounts: signatureOutputs.TypeParamConstraintCounts, TypeParamConstraintTypeTexts: signatureOutputs.TypeParamConstraintTypeTexts }
    typeStack := new ParserArgumentStack { Values: new int[](tokens.Count + 1) }
    nodes := new ParserNodeTable { Kinds: new int[](tokens.Count + 1), ValueStarts: new int[](tokens.Count + 1), ValueLengths: new int[](tokens.Count + 1), ChildStart: new int[](tokens.Count + 1), ChildCount: new int[](tokens.Count + 1), SpanStarts: new int[](tokens.Count + 1), SpanLengths: new int[](tokens.Count + 1) }
    children := new ParserChildIndexTable { Indices: new int[](tokens.Count + 1) }
    canonicalNodes := new TypeReferenceCanonicalTable { Kinds: nodes.Kinds, ValueStarts: nodes.ValueStarts, ValueLengths: nodes.ValueLengths, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    parameters := new ParserFunctionParameterTable { NameStarts: new int[](tokens.Count + 1), NameLengths: new int[](tokens.Count + 1), TypeRoots: new int[](tokens.Count + 1) }
    typeParams := new ParserFunctionTypeParameterTable { Starts: new int[](tokens.Count + 1), Lengths: new int[](tokens.Count + 1) }
    whereItems := new ParserFunctionWhereTable { NameStarts: new int[](tokens.Count + 1), NameLengths: new int[](tokens.Count + 1), ItemCodes: new int[](tokens.Count + 1) }
    functionSignatureResult := new ParserResultTable { Values: new int[](8) }
    ownerIndices := new FunctionSignatureOwnerIndexTable { Indices: new int[](tokens.Count + 1) }
    tupleNames := new FunctionSignatureTupleNameScratchTable { Names: new string[](tokens.Count + 1) }
    signatureResult := new ParserResultTable { Values: new int[](6) }
    paramCount := ParseFunctionSignatureInfoCore(source, ref signatureTokens, tokens.Count, funcIndex, ref signatureOutput, ref typeStack, ref nodes, ref children, ref canonicalNodes, ref parameters, ref typeParams, ref whereItems, ref functionSignatureResult, ref ownerIndices, ref tupleNames, ref signatureResult)
    if paramCount < 0 {
        return -1
    }

    bodyBrace := signatureResult.Values[1]
    if bodyBrace < 0 || bodyBrace >= tokens.Count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    bodyResult := new ColumnarFunctionResultTable { Values: new int[](2) }
    bodyNodeCount := ParseColumnarFunctionBodyNodesCore(ref tokens, bodyBrace, ref body, ref bodyResult)
    if bodyNodeCount <= 0 {
        return -1
    }

    bodyRoot := bodyResult.Values[0]
    if bodyRoot < 0 || bodyRoot >= bodyNodeCount {
        return -1
    }

    localTokens := new LocalFunctionTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, Count: tokens.Count }
    localNodes := new LocalFunctionNodeTable { Kinds: body.NodeKinds, ValueStarts: body.ValueStarts, ChildStart: body.ChildStart, ChildCount: body.ChildCount, ChildIndices: body.ChildIndices }
    localResults := new LocalFunctionResultTable { NodeIndices: locals.NodeIndices, FuncTokenIndices: locals.TokenIndices }
    localFunctionCount := DirectLocalFunctionTokenIndicesCore(ref localTokens, ref localNodes, bodyRoot, ref localResults)
    if localFunctionCount < 0 {
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

func ParseColumnarFunctionBodyNodesCore(tokens: &ColumnarFunctionTokenTable, bodyBrace: int, body: &ColumnarFunctionBodyTable, result: &ColumnarFunctionResultTable): int {
    statementTokens := new ParserTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    argStack := new ParserArgumentStack { Values: new int[](tokens.Count + 1) }
    nodes := new ParserExpressionNodeTable { Kinds: body.NodeKinds, ValueStarts: body.ValueStarts, ValueLengths: body.ValueLengths, ChildStart: body.ChildStart, ChildCount: body.ChildCount, SpanStarts: body.SpanStarts, SpanLengths: body.SpanLengths }
    children := new ParserChildIndexTable { Indices: body.ChildIndices }
    statementResult := new ParserResultTable { Values: result.Values }
    return ParseStatementNodesCore(ref statementTokens, tokens.Count, bodyBrace, ref argStack, ref nodes, ref children, ref statementResult)
}
