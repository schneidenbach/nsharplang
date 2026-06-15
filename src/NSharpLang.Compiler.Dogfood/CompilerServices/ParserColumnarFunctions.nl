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

    signatureResult := new ColumnarFunctionResultTable { Values: new int[](6) }
    paramCount := ParseFunctionSignatureInfoInto(
        source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count, funcIndex,
        signatureOutputs.FunctionNameTexts, signatureOutputs.ReturnTypeTexts,
        signatureOutputs.ParamNameTexts, signatureOutputs.ParamTypeTexts,
        signatureOutputs.ParamTupleNameCounts, signatureOutputs.ParamTupleNameTexts,
        signatureOutputs.ReturnTupleNameTexts, signatureOutputs.TypeParamTexts,
        signatureOutputs.TypeParamSpecials, signatureOutputs.TypeParamConstraintCounts,
        signatureOutputs.TypeParamConstraintTypeTexts, signatureResult.Values)
    if paramCount < 0 {
        return -1
    }

    bodyBrace := signatureResult.Values[1]
    if bodyBrace < 0 || bodyBrace >= tokens.Count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    bodyResult := new ColumnarFunctionResultTable { Values: new int[](2) }
    bodyNodeCount := ParseColumnarFunctionBodyNodesInto(ref tokens, bodyBrace, ref body, ref bodyResult)
    if bodyNodeCount <= 0 {
        return -1
    }

    bodyRoot := bodyResult.Values[0]
    if bodyRoot < 0 || bodyRoot >= bodyNodeCount {
        return -1
    }

    localFunctionCount := DirectLocalFunctionTokenIndicesInto(
        tokens.Kinds, tokens.Starts, tokens.Count,
        body.NodeKinds, body.ValueStarts, body.ChildStart, body.ChildCount, body.ChildIndices,
        bodyRoot, locals.NodeIndices, locals.TokenIndices)
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

func ParseColumnarFunctionBodyNodesInto(tokens: &ColumnarFunctionTokenTable, bodyBrace: int, body: &ColumnarFunctionBodyTable, result: &ColumnarFunctionResultTable): int {
    return ParseStatementNodesInto(
        tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count, bodyBrace,
        body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount,
        body.ChildIndices, body.SpanStarts, body.SpanLengths, result.Values)
}
