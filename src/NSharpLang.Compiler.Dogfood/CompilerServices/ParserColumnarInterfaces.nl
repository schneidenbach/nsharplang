import "CompilerServices/ParserColumnarFunctions"
import "CompilerServices/ParserFunctionSignatures"
import "CompilerServices/ParserInterfaceSignatures"
import "CompilerServices/ParserTypeReferences"

// Product columnar interface parser wrapper. It keeps base-name span scratch columns inside N#,
// rejects unsupported default-method local functions, and exposes only the interface/base text
// plus method signature rows needed by the C# transition materializer.

struct ColumnarInterfaceTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
}

struct ColumnarInterfaceBaseScratchTable {
    BaseNameStarts: int[]
    BaseNameLengths: int[]
}

struct ColumnarInterfaceOutputTable {
    MethodFuncIndices: int[]
    BaseNameTexts: string[]
    InterfaceNameTexts: string[]
    MethodNameTexts: string[]
    MethodReturnTexts: string[]
    MethodParamCounts: int[]
    MethodBodyFlags: int[]
    MethodParamNameTexts: string[]
    MethodParamTypeTexts: string[]
}

struct ColumnarInterfaceResultTable {
    Values: int[]
}

func ParseColumnarInterfaceInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameTexts: string[], outInterfaceNameTexts: string[], outMethodNameTexts: string[], outMethodReturnTexts: string[], outMethodParamCounts: int[], outMethodBodyFlags: int[], outMethodParamNameTexts: string[], outMethodParamTypeTexts: string[], outResult: int[]): int {
    tokens := new ColumnarInterfaceTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    scratch := new ColumnarInterfaceBaseScratchTable { BaseNameStarts: new int[](count + 1), BaseNameLengths: new int[](count + 1) }
    outputs := new ColumnarInterfaceOutputTable { MethodFuncIndices: outMethodFuncIndices, BaseNameTexts: outBaseNameTexts, InterfaceNameTexts: outInterfaceNameTexts, MethodNameTexts: outMethodNameTexts, MethodReturnTexts: outMethodReturnTexts, MethodParamCounts: outMethodParamCounts, MethodBodyFlags: outMethodBodyFlags, MethodParamNameTexts: outMethodParamNameTexts, MethodParamTypeTexts: outMethodParamTypeTexts }
    result := new ColumnarInterfaceResultTable { Values: outResult }
    return ParseColumnarInterfaceInfoCore(source, ref tokens, interfaceIndex, ref scratch, ref outputs, ref result)
}

func ParseColumnarInterfaceInfoCore(source: string, tokens: &ColumnarInterfaceTokenTable, interfaceIndex: int, scratch: &ColumnarInterfaceBaseScratchTable, outputs: &ColumnarInterfaceOutputTable, result: &ColumnarInterfaceResultTable): int {
    signatureTokens := new ParserTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    baseOutputs := new InterfaceSignatureBaseOutputTable { BaseNameStarts: scratch.BaseNameStarts, BaseNameLengths: scratch.BaseNameLengths, BaseNameTexts: outputs.BaseNameTexts, InterfaceNameTexts: outputs.InterfaceNameTexts }
    methodOutputs := new InterfaceSignatureMethodOutputTable { FuncIndices: outputs.MethodFuncIndices, NameTexts: outputs.MethodNameTexts, ReturnTexts: outputs.MethodReturnTexts, ParamCounts: outputs.MethodParamCounts, BodyFlags: outputs.MethodBodyFlags, ParamNameTexts: outputs.MethodParamNameTexts, ParamTypeTexts: outputs.MethodParamTypeTexts }
    typeStack := new ParserArgumentStack { Values: new int[](tokens.Count + 1) }
    nodes := new ParserNodeTable { Kinds: new int[](tokens.Count + 1), ValueStarts: new int[](tokens.Count + 1), ValueLengths: new int[](tokens.Count + 1), ChildStart: new int[](tokens.Count + 1), ChildCount: new int[](tokens.Count + 1), SpanStarts: new int[](tokens.Count + 1), SpanLengths: new int[](tokens.Count + 1) }
    children := new ParserChildIndexTable { Indices: new int[](tokens.Count + 1) }
    canonicalNodes := new TypeReferenceCanonicalTable { Kinds: nodes.Kinds, ValueStarts: nodes.ValueStarts, ValueLengths: nodes.ValueLengths, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    tupleNodes := new InterfaceSignatureTupleNodeTable { Kinds: nodes.Kinds, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    parameters := new ParserFunctionParameterTable { NameStarts: new int[](tokens.Count + 1), NameLengths: new int[](tokens.Count + 1), TypeRoots: new int[](tokens.Count + 1) }
    typeParams := new ParserFunctionTypeParameterTable { Starts: new int[](tokens.Count + 1), Lengths: new int[](tokens.Count + 1) }
    whereItems := new ParserFunctionWhereTable { NameStarts: new int[](tokens.Count + 1), NameLengths: new int[](tokens.Count + 1), ItemCodes: new int[](tokens.Count + 1) }
    signatureResult := new ParserResultTable { Values: new int[](8) }
    interfaceResult := new ParserResultTable { Values: result.Values }
    methodCount := ParseInterfaceDeclarationSignatureInfoCore(source, ref signatureTokens, tokens.Count, interfaceIndex, ref baseOutputs, ref methodOutputs, ref typeStack, ref nodes, ref children, ref canonicalNodes, ref tupleNodes, ref parameters, ref typeParams, ref whereItems, ref signatureResult, ref interfaceResult)
    if methodCount < 0 {
        return -1
    }

    if ColumnarInterfaceBaseNamesDistinct(ref outputs, result.Values[2]) == 0 {
        return -1
    }
    if ColumnarInterfaceMethodNamesDistinct(ref outputs, methodCount) == 0 {
        return -1
    }
    if ColumnarInterfaceMethodParamNamesDistinct(ref outputs, methodCount) == 0 {
        return -1
    }

    localStatus := InterfaceDefaultMethodLocalFunctionStatus(source, ref tokens, ref outputs, methodCount)
    if localStatus != 0 {
        return -1
    }

    return methodCount
}

func ColumnarInterfaceBaseNamesDistinct(outputs: &ColumnarInterfaceOutputTable, baseCount: int): int {
    if baseCount < 0 {
        return 0
    }

    i := 0
    while i < baseCount {
        if outputs.BaseNameTexts[i] == "" {
            return 0
        }

        j := i + 1
        while j < baseCount {
            if outputs.BaseNameTexts[i] == outputs.BaseNameTexts[j] {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarInterfaceMethodNamesDistinct(outputs: &ColumnarInterfaceOutputTable, methodCount: int): int {
    if methodCount < 0 {
        return 0
    }

    i := 0
    while i < methodCount {
        if outputs.MethodNameTexts[i] == "" {
            return 0
        }

        j := i + 1
        while j < methodCount {
            if outputs.MethodNameTexts[i] == outputs.MethodNameTexts[j] {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarInterfaceMethodParamNamesDistinct(outputs: &ColumnarInterfaceOutputTable, methodCount: int): int {
    if methodCount < 0 {
        return 0
    }

    paramOffset := 0
    m := 0
    while m < methodCount {
        paramCount := outputs.MethodParamCounts[m]
        if paramCount < 0 {
            return 0
        }

        i := 0
        while i < paramCount {
            leftIndex := paramOffset + i
            if leftIndex < 0 || leftIndex >= outputs.MethodParamNameTexts.Length || outputs.MethodParamNameTexts[leftIndex] == "" {
                return 0
            }

            j := i + 1
            while j < paramCount {
                rightIndex := paramOffset + j
                if rightIndex < 0 || rightIndex >= outputs.MethodParamNameTexts.Length {
                    return 0
                }

                if outputs.MethodParamNameTexts[leftIndex] == outputs.MethodParamNameTexts[rightIndex] {
                    return 0
                }

                j = j + 1
            }

            i = i + 1
        }

        paramOffset = paramOffset + paramCount
        m = m + 1
    }

    return 1
}

func InterfaceDefaultMethodLocalFunctionStatus(source: string, tokens: &ColumnarInterfaceTokenTable, outputs: &ColumnarInterfaceOutputTable, methodCount: int): int {
    functionTokens := new ColumnarFunctionTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths, Count: tokens.Count }
    cap := tokens.Count + 1
    signatureOutputs := new ColumnarFunctionSignatureOutputTable {
        FunctionNameTexts: new string[](1),
        ReturnTypeTexts: new string[](1),
        ParamNameTexts: new string[](cap),
        ParamTypeTexts: new string[](cap),
        ParamTupleNameCounts: new int[](cap),
        ParamTupleNameTexts: new string[](cap),
        ReturnTupleNameTexts: new string[](cap),
        TypeParamTexts: new string[](cap),
        TypeParamSpecials: new int[](cap),
        TypeParamConstraintCounts: new int[](cap),
        TypeParamConstraintTypeTexts: new string[](cap)
    }
    body := new ColumnarFunctionBodyTable {
        NodeKinds: new int[](cap),
        ValueStarts: new int[](cap),
        ValueLengths: new int[](cap),
        ChildStart: new int[](cap),
        ChildCount: new int[](cap),
        ChildIndices: new int[](cap),
        SpanStarts: new int[](cap),
        SpanLengths: new int[](cap)
    }
    locals := new ColumnarFunctionLocalTable { NodeIndices: new int[](cap), TokenIndices: new int[](cap) }
    result := new ColumnarFunctionResultTable { Values: new int[](9) }

    for i := 0; i < methodCount; i++ {
        bodyFlag := outputs.MethodBodyFlags[i]
        if bodyFlag == 0 {
            continue
        }
        if bodyFlag != 1 {
            return -1
        }

        paramCount := ParseColumnarFunctionInfoCore(source, ref functionTokens, outputs.MethodFuncIndices[i], 0, ref signatureOutputs, ref body, ref locals, ref result)
        if paramCount < 0 {
            return -1
        }
        if result.Values[8] > 0 {
            return 1
        }
    }

    return 0
}
