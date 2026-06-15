// Composed constructor-signature product wrapper. ParserDeclarations.nl keeps the standalone constructor chain
// parser; this file owns the cross-file route that combines constructor parameter signatures, canonical type text,
// chaining initializer text, and body-brace validation for the columnar product adapter.

struct ConstructorSignatureOutputTable {
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ArgKinds: int[]
    ArgStarts: int[]
    ArgLengths: int[]
    ArgTexts: string[]
}

func ParseConstructorSignatureInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outParamNameTexts: string[], outParamTypeTexts: string[], outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outArgTexts: string[], outResult: int[]): int {
    if outResult.Length < 4 {
        return -1
    }

    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    outputs := new ConstructorSignatureOutputTable { ParamNameTexts: outParamNameTexts, ParamTypeTexts: outParamTypeTexts, ArgKinds: outArgKinds, ArgStarts: outArgStarts, ArgLengths: outArgLengths, ArgTexts: outArgTexts }
    typeStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserNodeTable { Kinds: new int[](count + 1), ValueStarts: new int[](count + 1), ValueLengths: new int[](count + 1), ChildStart: new int[](count + 1), ChildCount: new int[](count + 1), SpanStarts: new int[](count + 1), SpanLengths: new int[](count + 1) }
    children := new ParserChildIndexTable { Indices: new int[](count + 1) }
    canonicalNodes := new TypeReferenceCanonicalTable { Kinds: nodes.Kinds, ValueStarts: nodes.ValueStarts, ValueLengths: nodes.ValueLengths, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    parameters := new ParserFunctionParameterTable { NameStarts: new int[](count + 1), NameLengths: new int[](count + 1), TypeRoots: new int[](count + 1) }
    typeParams := new ParserFunctionTypeParameterTable { Starts: new int[](count + 1), Lengths: new int[](count + 1) }
    whereItems := new ParserFunctionWhereTable { NameStarts: new int[](count + 1), NameLengths: new int[](count + 1), ItemCodes: new int[](count + 1) }
    signatureResult := new ParserResultTable { Values: new int[](8) }
    result := new ParserResultTable { Values: outResult }
    return ParseConstructorSignatureInfoCore(source, ref tokens, count, ctorIndex, ref outputs, ref typeStack, ref nodes, ref children, ref canonicalNodes, ref parameters, ref typeParams, ref whereItems, ref signatureResult, ref result)
}

func ParseConstructorSignatureInfoCore(source: string, tokens: &ParserTokenTable, count: int, ctorIndex: int, outputs: &ConstructorSignatureOutputTable, typeStack: &ParserArgumentStack, nodes: &ParserNodeTable, children: &ParserChildIndexTable, canonicalNodes: &TypeReferenceCanonicalTable, parameters: &ParserFunctionParameterTable, typeParams: &ParserFunctionTypeParameterTable, whereItems: &ParserFunctionWhereTable, signatureResult: &ParserResultTable, result: &ParserResultTable): int {
    paramCount := ParseFunctionSignatureCore(ref tokens, count, ctorIndex, ref typeStack, ref nodes, ref children, ref parameters, ref typeParams, ref whereItems, ref signatureResult)
    if paramCount < 0 || signatureResult.Values[1] >= 0 || signatureResult.Values[5] != 0 || signatureResult.Values[7] != 0 {
        return -1
    }

    if paramCount > outputs.ParamNameTexts.Length || paramCount > outputs.ParamTypeTexts.Length {
        return -1
    }

    paramIndex := 0
    while paramIndex < paramCount {
        paramName := FunctionSignatureSpanText(source, parameters.NameStarts[paramIndex], parameters.NameLengths[paramIndex])
        if paramName == "" {
            return -1
        }

        outputs.ParamNameTexts[paramIndex] = paramName
        outputs.ParamTypeTexts[paramIndex] = TypeReferenceCanonicalTextCore(source, ref canonicalNodes, parameters.TypeRoots[paramIndex])
        paramIndex = paramIndex + 1
    }

    chainArgCount := ParseConstructorTextInfoInto(source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, count, ctorIndex, outputs.ArgKinds, outputs.ArgStarts, outputs.ArgLengths, outputs.ArgTexts, result.Values)
    if chainArgCount < 0 {
        return -1
    }

    bodyBrace := result.Values[1]
    if bodyBrace < 0 || bodyBrace >= count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    result.Values[2] = paramCount
    result.Values[3] = chainArgCount
    return paramCount
}
