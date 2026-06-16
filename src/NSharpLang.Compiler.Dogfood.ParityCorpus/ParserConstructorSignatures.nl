// Flattened constructor-signature ABI retained for parser parity tests only. Product constructor
// parsing composes ParseConstructorSignatureInfoCore directly through ParserColumnarConstructors.nl.

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
