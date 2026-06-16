// Flattened interface-signature ABI retained for parser parity tests only. Product interface
// parsing composes ParseInterfaceDeclarationSignatureInfoCore directly through ParserColumnarInterfaces.nl.

func ParseInterfaceDeclarationSignatureInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameStarts: int[], outBaseNameLengths: int[], outBaseNameTexts: string[], outInterfaceNameTexts: string[], outMethodNameTexts: string[], outMethodReturnTexts: string[], outMethodParamCounts: int[], outMethodBodyFlags: int[], outMethodParamNameTexts: string[], outMethodParamTypeTexts: string[], outResult: int[]): int {
    if outResult.Length < 4 {
        return -1
    }

    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    baseOutputs := new InterfaceSignatureBaseOutputTable { BaseNameStarts: outBaseNameStarts, BaseNameLengths: outBaseNameLengths, BaseNameTexts: outBaseNameTexts, InterfaceNameTexts: outInterfaceNameTexts }
    methodOutputs := new InterfaceSignatureMethodOutputTable { FuncIndices: outMethodFuncIndices, NameTexts: outMethodNameTexts, ReturnTexts: outMethodReturnTexts, ParamCounts: outMethodParamCounts, BodyFlags: outMethodBodyFlags, ParamNameTexts: outMethodParamNameTexts, ParamTypeTexts: outMethodParamTypeTexts }
    typeStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserNodeTable { Kinds: new int[](count + 1), ValueStarts: new int[](count + 1), ValueLengths: new int[](count + 1), ChildStart: new int[](count + 1), ChildCount: new int[](count + 1), SpanStarts: new int[](count + 1), SpanLengths: new int[](count + 1) }
    children := new ParserChildIndexTable { Indices: new int[](count + 1) }
    canonicalNodes := new TypeReferenceCanonicalTable { Kinds: nodes.Kinds, ValueStarts: nodes.ValueStarts, ValueLengths: nodes.ValueLengths, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    tupleNodes := new InterfaceSignatureTupleNodeTable { Kinds: nodes.Kinds, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    parameters := new ParserFunctionParameterTable { NameStarts: new int[](count + 1), NameLengths: new int[](count + 1), TypeRoots: new int[](count + 1) }
    typeParams := new ParserFunctionTypeParameterTable { Starts: new int[](count + 1), Lengths: new int[](count + 1) }
    whereItems := new ParserFunctionWhereTable { NameStarts: new int[](count + 1), NameLengths: new int[](count + 1), ItemCodes: new int[](count + 1) }
    signatureResult := new ParserResultTable { Values: new int[](8) }
    result := new ParserResultTable { Values: outResult }
    return ParseInterfaceDeclarationSignatureInfoCore(source, ref tokens, count, interfaceIndex, ref baseOutputs, ref methodOutputs, ref typeStack, ref nodes, ref children, ref canonicalNodes, ref tupleNodes, ref parameters, ref typeParams, ref whereItems, ref signatureResult, ref result)
}

func ParseInterfaceSignatureHasTupleNames(nodeKinds: int[], childStart: int[], childCount: int[], childIndices: int[], root: int): int {
    nodes := new InterfaceSignatureTupleNodeTable { Kinds: nodeKinds, ChildStart: childStart, ChildCount: childCount, ChildIndices: childIndices }
    return ParseInterfaceSignatureHasTupleNamesCore(ref nodes, root)
}
