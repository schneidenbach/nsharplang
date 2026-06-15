// Composed interface-signature product wrapper. ParserDeclarations.nl stays a standalone declaration parser; this
// file owns the cross-file routing that combines interface member indices, function-signature parsing, and canonical
// type text for the columnar product adapter.

struct InterfaceSignatureBaseOutputTable {
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    BaseNameTexts: string[]
    InterfaceNameTexts: string[]
}

struct InterfaceSignatureMethodOutputTable {
    FuncIndices: int[]
    NameTexts: string[]
    ReturnTexts: string[]
    ParamCounts: int[]
    BodyFlags: int[]
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
}

struct InterfaceSignatureTupleNodeTable {
    Kinds: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
}

func ParseInterfaceDeclarationSignatureInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameStarts: int[], outBaseNameLengths: int[], outBaseNameTexts: string[], outInterfaceNameTexts: string[], outMethodNameTexts: string[], outMethodReturnTexts: string[], outMethodParamCounts: int[], outMethodBodyFlags: int[], outMethodParamNameTexts: string[], outMethodParamTypeTexts: string[], outResult: int[]): int {
    if outResult.Length < 4 {
        return -1
    }

    cap := count + 1
    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    baseOutputs := new InterfaceSignatureBaseOutputTable { BaseNameStarts: outBaseNameStarts, BaseNameLengths: outBaseNameLengths, BaseNameTexts: outBaseNameTexts, InterfaceNameTexts: outInterfaceNameTexts }
    methodOutputs := new InterfaceSignatureMethodOutputTable { FuncIndices: outMethodFuncIndices, NameTexts: outMethodNameTexts, ReturnTexts: outMethodReturnTexts, ParamCounts: outMethodParamCounts, BodyFlags: outMethodBodyFlags, ParamNameTexts: outMethodParamNameTexts, ParamTypeTexts: outMethodParamTypeTexts }
    typeStack := new ParserArgumentStack { Values: new int[](cap) }
    nodes := new ParserNodeTable { Kinds: new int[](cap), ValueStarts: new int[](cap), ValueLengths: new int[](cap), ChildStart: new int[](cap), ChildCount: new int[](cap), SpanStarts: new int[](cap), SpanLengths: new int[](cap) }
    children := new ParserChildIndexTable { Indices: new int[](cap) }
    canonicalNodes := new TypeReferenceCanonicalTable { Kinds: nodes.Kinds, ValueStarts: nodes.ValueStarts, ValueLengths: nodes.ValueLengths, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    tupleNodes := new InterfaceSignatureTupleNodeTable { Kinds: nodes.Kinds, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    parameters := new ParserFunctionParameterTable { NameStarts: new int[](cap), NameLengths: new int[](cap), TypeRoots: new int[](cap) }
    typeParams := new ParserFunctionTypeParameterTable { Starts: new int[](cap), Lengths: new int[](cap) }
    whereItems := new ParserFunctionWhereTable { NameStarts: new int[](cap), NameLengths: new int[](cap), ItemCodes: new int[](cap) }
    signatureResult := new ParserResultTable { Values: new int[](8) }
    result := new ParserResultTable { Values: outResult }
    return ParseInterfaceDeclarationSignatureInfoCore(source, ref tokens, count, interfaceIndex, ref baseOutputs, ref methodOutputs, ref typeStack, ref nodes, ref children, ref canonicalNodes, ref tupleNodes, ref parameters, ref typeParams, ref whereItems, ref signatureResult, ref result)
}

func ParseInterfaceDeclarationSignatureInfoCore(source: string, tokens: &ParserTokenTable, count: int, interfaceIndex: int, baseOutputs: &InterfaceSignatureBaseOutputTable, methodOutputs: &InterfaceSignatureMethodOutputTable, typeStack: &ParserArgumentStack, nodes: &ParserNodeTable, children: &ParserChildIndexTable, canonicalNodes: &TypeReferenceCanonicalTable, tupleNodes: &InterfaceSignatureTupleNodeTable, parameters: &ParserFunctionParameterTable, typeParams: &ParserFunctionTypeParameterTable, whereItems: &ParserFunctionWhereTable, signatureResult: &ParserResultTable, result: &ParserResultTable): int {
    methodCount := ParseInterfaceDeclarationInfoInto(source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, count, interfaceIndex, methodOutputs.FuncIndices, baseOutputs.BaseNameStarts, baseOutputs.BaseNameLengths, baseOutputs.BaseNameTexts, baseOutputs.InterfaceNameTexts, result.Values)
    if methodCount < 0 {
        return -1
    }

    if methodCount > methodOutputs.NameTexts.Length || methodCount > methodOutputs.ReturnTexts.Length || methodCount > methodOutputs.ParamCounts.Length || methodCount > methodOutputs.BodyFlags.Length {
        return -1
    }

    flatParamCount := 0
    methodIndex := 0
    while methodIndex < methodCount {
        paramCount := ParseFunctionSignatureCore(ref tokens, count, methodOutputs.FuncIndices[methodIndex], ref typeStack, ref nodes, ref children, ref parameters, ref typeParams, ref whereItems, ref signatureResult)
        if paramCount < 0 || signatureResult.Values[3] < 0 {
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
            if ParseInterfaceSignatureHasTupleNamesCore(ref tupleNodes, returnRoot) != 0 {
                return -1
            }

            methodOutputs.ReturnTexts[methodIndex] = TypeReferenceCanonicalTextCore(source, ref canonicalNodes, returnRoot)
        } else {
            methodOutputs.ReturnTexts[methodIndex] = "void"
        }

        if flatParamCount + paramCount > methodOutputs.ParamNameTexts.Length || flatParamCount + paramCount > methodOutputs.ParamTypeTexts.Length {
            return -1
        }

        paramIndex := 0
        while paramIndex < paramCount {
            paramName := FunctionSignatureSpanText(source, parameters.NameStarts[paramIndex], parameters.NameLengths[paramIndex])
            if paramName == "" {
                return -1
            }

            paramRoot := parameters.TypeRoots[paramIndex]
            if ParseInterfaceSignatureHasTupleNamesCore(ref tupleNodes, paramRoot) != 0 {
                return -1
            }

            flatSlot := flatParamCount + paramIndex
            methodOutputs.ParamNameTexts[flatSlot] = paramName
            methodOutputs.ParamTypeTexts[flatSlot] = TypeReferenceCanonicalTextCore(source, ref canonicalNodes, paramRoot)
            paramIndex = paramIndex + 1
        }

        methodOutputs.ParamCounts[methodIndex] = paramCount
        flatParamCount = flatParamCount + paramCount

        if tokens.Kinds[afterSignature] == 129 {
            methodOutputs.BodyFlags[methodIndex] = 1
        } else if tokens.Kinds[afterSignature] == 7 || tokens.Kinds[afterSignature] == 130 {
            methodOutputs.BodyFlags[methodIndex] = 0
        } else {
            return -1
        }

        methodIndex = methodIndex + 1
    }

    result.Values[3] = flatParamCount
    return methodCount
}

func ParseInterfaceSignatureHasTupleNames(nodeKinds: int[], childStart: int[], childCount: int[], childIndices: int[], root: int): int {
    nodes := new InterfaceSignatureTupleNodeTable { Kinds: nodeKinds, ChildStart: childStart, ChildCount: childCount, ChildIndices: childIndices }
    return ParseInterfaceSignatureHasTupleNamesCore(ref nodes, root)
}

func ParseInterfaceSignatureHasTupleNamesCore(nodes: &InterfaceSignatureTupleNodeTable, root: int): int {
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
