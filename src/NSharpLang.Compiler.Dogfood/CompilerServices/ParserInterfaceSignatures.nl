// Composed interface-signature product core. ParserDeclarations.nl stays a standalone declaration parser; this
// file owns the cross-file routing that combines interface member indices, function-signature parsing, and canonical
// type text for the columnar product adapter. The flattened ParseInterfaceDeclarationSignatureInfoInto ABI lives
// in the parity corpus.

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

func ParseInterfaceDeclarationSignatureInfoCore(source: string, tokens: &ParserTokenTable, count: int, interfaceIndex: int, baseOutputs: &InterfaceSignatureBaseOutputTable, methodOutputs: &InterfaceSignatureMethodOutputTable, typeStack: &ParserArgumentStack, nodes: &ParserNodeTable, children: &ParserChildIndexTable, canonicalNodes: &TypeReferenceCanonicalTable, tupleNodes: &InterfaceSignatureTupleNodeTable, parameters: &ParserFunctionParameterTable, typeParams: &ParserFunctionTypeParameterTable, whereItems: &ParserFunctionWhereTable, signatureResult: &ParserResultTable, result: &ParserResultTable): int {
    if result.Values.Length < 4 {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    declaration := new InterfaceDeclarationTable { MethodFuncIndices: methodOutputs.FuncIndices, BaseNameStarts: baseOutputs.BaseNameStarts, BaseNameLengths: baseOutputs.BaseNameLengths }
    declarationResult := new ParserDeclarationResultTable { Values: result.Values }
    methodCount := ParseInterfaceDeclarationCore(ref declarationTokens, count, interfaceIndex, ref declaration, ref declarationResult)
    if methodCount < 0 {
        return -1
    }

    baseCount := result.Values[2]
    if baseOutputs.InterfaceNameTexts.Length < 1 || baseCount > baseOutputs.BaseNameTexts.Length {
        return -1
    }

    interfaceName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if interfaceName == "" {
        return -1
    }
    baseOutputs.InterfaceNameTexts[0] = interfaceName

    baseIndex := 0
    while baseIndex < baseCount {
        baseName := ParserDeclarationSpanText(source, declaration.BaseNameStarts[baseIndex], declaration.BaseNameLengths[baseIndex])
        if baseName == "" {
            return -1
        }

        baseOutputs.BaseNameTexts[baseIndex] = baseName
        baseIndex = baseIndex + 1
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
