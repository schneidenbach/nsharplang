// Flattened function-signature parser ABIs retained for parser parity tests only. Product function
// parsing composes ParseFunctionSignatureCore / ParseFunctionSignatureInfoCore directly.

func ParseFunctionSignatureInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outParamNameStarts: int[], outParamNameLengths: int[], outParamTypeRoots: int[], outTypeParamStarts: int[], outTypeParamLengths: int[], outWhereNameStarts: int[], outWhereNameLengths: int[], outWhereItemCodes: int[], outResult: int[]): int {
    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    typeStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserNodeTable { Kinds: outNodeKinds, ValueStarts: outNameStarts, ValueLengths: outNameLengths, ChildStart: outChildStart, ChildCount: outChildCount, SpanStarts: outSpanStarts, SpanLengths: outSpanLengths }
    children := new ParserChildIndexTable { Indices: outChildIndices }
    parameters := new ParserFunctionParameterTable { NameStarts: outParamNameStarts, NameLengths: outParamNameLengths, TypeRoots: outParamTypeRoots }
    typeParams := new ParserFunctionTypeParameterTable { Starts: outTypeParamStarts, Lengths: outTypeParamLengths }
    whereItems := new ParserFunctionWhereTable { NameStarts: outWhereNameStarts, NameLengths: outWhereNameLengths, ItemCodes: outWhereItemCodes }
    result := new ParserResultTable { Values: outResult }
    return ParseFunctionSignatureCore(ref tokens, count, funcIndex, ref typeStack, ref nodes, ref children, ref parameters, ref typeParams, ref whereItems, ref result)
}

func ParseFunctionSignatureTextInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outParamNameStarts: int[], outParamNameLengths: int[], outParamNameTexts: string[], outParamTypeRoots: int[], outTypeParamStarts: int[], outTypeParamLengths: int[], outTypeParamTexts: string[], outWhereNameStarts: int[], outWhereNameLengths: int[], outWhereNameTexts: string[], outWhereItemCodes: int[], outFunctionNameTexts: string[], outResult: int[]): int {
    if outFunctionNameTexts.Length < 1 {
        return -1
    }

    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    typeStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserNodeTable { Kinds: outNodeKinds, ValueStarts: outNameStarts, ValueLengths: outNameLengths, ChildStart: outChildStart, ChildCount: outChildCount, SpanStarts: outSpanStarts, SpanLengths: outSpanLengths }
    children := new ParserChildIndexTable { Indices: outChildIndices }
    parameters := new ParserFunctionParameterTable { NameStarts: outParamNameStarts, NameLengths: outParamNameLengths, TypeRoots: outParamTypeRoots }
    typeParams := new ParserFunctionTypeParameterTable { Starts: outTypeParamStarts, Lengths: outTypeParamLengths }
    whereItems := new ParserFunctionWhereTable { NameStarts: outWhereNameStarts, NameLengths: outWhereNameLengths, ItemCodes: outWhereItemCodes }
    result := new ParserResultTable { Values: outResult }
    paramCount := ParseFunctionSignatureCore(ref tokens, count, funcIndex, ref typeStack, ref nodes, ref children, ref parameters, ref typeParams, ref whereItems, ref result)
    if paramCount < 0 {
        return -1
    }

    typeParamCount := result.Values[5]
    whereItemCount := result.Values[7]
    if paramCount > outParamNameTexts.Length || typeParamCount > outTypeParamTexts.Length || whereItemCount > outWhereNameTexts.Length {
        return -1
    }

    if result.Values[3] >= 0 {
        functionName := FunctionSignatureSpanText(source, result.Values[3], result.Values[4])
        if functionName == "" {
            return -1
        }
        outFunctionNameTexts[0] = functionName
    } else {
        outFunctionNameTexts[0] = ""
    }

    i := 0
    while i < paramCount {
        text := FunctionSignatureSpanText(source, parameters.NameStarts[i], parameters.NameLengths[i])
        if text == "" {
            return -1
        }

        outParamNameTexts[i] = text
        i = i + 1
    }

    i = 0
    while i < typeParamCount {
        text := FunctionSignatureSpanText(source, typeParams.Starts[i], typeParams.Lengths[i])
        if text == "" {
            return -1
        }

        outTypeParamTexts[i] = text
        i = i + 1
    }

    i = 0
    while i < whereItemCount {
        text := FunctionSignatureSpanText(source, whereItems.NameStarts[i], whereItems.NameLengths[i])
        if text == "" {
            return -1
        }

        outWhereNameTexts[i] = text
        i = i + 1
    }

    return paramCount
}

func ParseFunctionSignatureInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, outFunctionNameTexts: string[], outReturnTypeTexts: string[], outParamNameTexts: string[], outParamTypeTexts: string[], outParamTupleNameCounts: int[], outParamTupleNameTexts: string[], outReturnTupleNameTexts: string[], outTypeParamTexts: string[], outTypeParamSpecials: int[], outTypeParamConstraintCounts: int[], outTypeParamConstraintTypeTexts: string[], outResult: int[]): int {
    if outFunctionNameTexts.Length < 1 || outReturnTypeTexts.Length < 1 || outResult.Length < 6 {
        return -1
    }

    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    outputs := new FunctionSignatureInfoOutputTable { FunctionNameTexts: outFunctionNameTexts, ReturnTypeTexts: outReturnTypeTexts, ParamNameTexts: outParamNameTexts, ParamTypeTexts: outParamTypeTexts, ParamTupleNameCounts: outParamTupleNameCounts, ParamTupleNameTexts: outParamTupleNameTexts, ReturnTupleNameTexts: outReturnTupleNameTexts, TypeParamTexts: outTypeParamTexts, TypeParamSpecials: outTypeParamSpecials, TypeParamConstraintCounts: outTypeParamConstraintCounts, TypeParamConstraintTypeTexts: outTypeParamConstraintTypeTexts }
    typeStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserNodeTable { Kinds: new int[](count + 1), ValueStarts: new int[](count + 1), ValueLengths: new int[](count + 1), ChildStart: new int[](count + 1), ChildCount: new int[](count + 1), SpanStarts: new int[](count + 1), SpanLengths: new int[](count + 1) }
    children := new ParserChildIndexTable { Indices: new int[](count + 1) }
    canonicalNodes := new TypeReferenceCanonicalTable { Kinds: nodes.Kinds, ValueStarts: nodes.ValueStarts, ValueLengths: nodes.ValueLengths, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    parameters := new ParserFunctionParameterTable { NameStarts: new int[](count + 1), NameLengths: new int[](count + 1), TypeRoots: new int[](count + 1) }
    typeParams := new ParserFunctionTypeParameterTable { Starts: new int[](count + 1), Lengths: new int[](count + 1) }
    whereItems := new ParserFunctionWhereTable { NameStarts: new int[](count + 1), NameLengths: new int[](count + 1), ItemCodes: new int[](count + 1) }
    signatureResult := new ParserResultTable { Values: new int[](8) }
    ownerIndices := new FunctionSignatureOwnerIndexTable { Indices: new int[](count + 1) }
    tupleNames := new FunctionSignatureTupleNameScratchTable { Names: new string[](count + 1) }
    result := new ParserResultTable { Values: outResult }
    return ParseFunctionSignatureInfoCore(source, ref tokens, count, funcIndex, ref outputs, ref typeStack, ref nodes, ref children, ref canonicalNodes, ref parameters, ref typeParams, ref whereItems, ref signatureResult, ref ownerIndices, ref tupleNames, ref result)
}
