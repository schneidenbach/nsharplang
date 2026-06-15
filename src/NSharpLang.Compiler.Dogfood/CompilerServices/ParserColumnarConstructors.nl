// Product columnar constructor parser wrapper. It composes constructor signature/chain parsing with the
// statement-node rowset so the C# adapter no longer orchestrates constructor body parsing.

struct ColumnarConstructorTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
}

struct ColumnarConstructorSignatureOutputTable {
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ArgKinds: int[]
    ArgStarts: int[]
    ArgLengths: int[]
    ArgTexts: string[]
}

struct ColumnarConstructorBodyTable {
    NodeKinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    SpanStarts: int[]
    SpanLengths: int[]
}

struct ColumnarConstructorResultTable {
    Values: int[]
}

func ParseColumnarConstructorInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outParamNameTexts: string[], outParamTypeTexts: string[], outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outArgTexts: string[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    tokens := new ColumnarConstructorTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    signatureOutputs := new ColumnarConstructorSignatureOutputTable { ParamNameTexts: outParamNameTexts, ParamTypeTexts: outParamTypeTexts, ArgKinds: outArgKinds, ArgStarts: outArgStarts, ArgLengths: outArgLengths, ArgTexts: outArgTexts }
    body := new ColumnarConstructorBodyTable { NodeKinds: outNodeKinds, ValueStarts: outValueStarts, ValueLengths: outValueLengths, ChildStart: outChildStart, ChildCount: outChildCount, ChildIndices: outChildIndices, SpanStarts: outSpanStarts, SpanLengths: outSpanLengths }
    result := new ColumnarConstructorResultTable { Values: outResult }
    return ParseColumnarConstructorInfoCore(source, ref tokens, ctorIndex, ref signatureOutputs, ref body, ref result)
}

func ParseColumnarConstructorInfoCore(source: string, tokens: &ColumnarConstructorTokenTable, ctorIndex: int, signatureOutputs: &ColumnarConstructorSignatureOutputTable, body: &ColumnarConstructorBodyTable, result: &ColumnarConstructorResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    signatureResult := new ColumnarConstructorResultTable { Values: new int[](4) }
    paramCount := ParseConstructorSignatureInfoInto(
        source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count, ctorIndex,
        signatureOutputs.ParamNameTexts, signatureOutputs.ParamTypeTexts,
        signatureOutputs.ArgKinds, signatureOutputs.ArgStarts, signatureOutputs.ArgLengths,
        signatureOutputs.ArgTexts, signatureResult.Values)
    if paramCount < 0 {
        return -1
    }

    bodyBrace := signatureResult.Values[1]
    if bodyBrace < 0 || bodyBrace >= tokens.Count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    bodyResult := new ColumnarConstructorResultTable { Values: new int[](2) }
    bodyNodeCount := ParseColumnarConstructorBodyNodesInto(ref tokens, bodyBrace, ref body, ref bodyResult)
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

func ParseColumnarConstructorBodyNodesInto(tokens: &ColumnarConstructorTokenTable, bodyBrace: int, body: &ColumnarConstructorBodyTable, result: &ColumnarConstructorResultTable): int {
    return ParseStatementNodesInto(
        tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count, bodyBrace,
        body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount,
        body.ChildIndices, body.SpanStarts, body.SpanLengths, result.Values)
}
