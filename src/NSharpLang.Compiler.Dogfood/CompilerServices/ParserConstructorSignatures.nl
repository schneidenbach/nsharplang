import "CompilerServices/ParserDeclarations"
import "CompilerServices/ParserFunctionSignatures"
import "CompilerServices/ParserTypeReferences"

// Composed constructor-signature product core. ParserDeclarations.nl keeps the standalone constructor chain
// parser; this file owns the cross-file route that combines constructor parameter signatures, canonical type text,
// chaining initializer text, and body-brace validation for the columnar product adapter. The flattened
// ParseConstructorSignatureInfoInto ABI lives in the parity corpus.

struct ConstructorSignatureOutputTable {
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ArgKinds: int[]
    ArgStarts: int[]
    ArgLengths: int[]
    ArgTexts: string[]
}

func ParseConstructorSignatureInfoCore(source: string, tokens: &ParserTokenTable, count: int, ctorIndex: int, outputs: &ConstructorSignatureOutputTable, typeStack: &ParserArgumentStack, nodes: &ParserNodeTable, children: &ParserChildIndexTable, canonicalNodes: &TypeReferenceCanonicalTable, parameters: &ParserFunctionParameterTable, typeParams: &ParserFunctionTypeParameterTable, whereItems: &ParserFunctionWhereTable, signatureResult: &ParserResultTable, result: &ParserResultTable): int {
    if result.Values.Length < 4 {
        return -1
    }

    paramCount := ParseFunctionSignatureCore(ref tokens, count, ctorIndex, ref typeStack, ref nodes, ref children, ref parameters, ref typeParams, ref whereItems, ref signatureResult)
    if paramCount < 0 || signatureResult.Values[1] >= 0 || signatureResult.Values[5] != 0 || signatureResult.Values[7] != 0 {
        return -1
    }

    if paramCount > outputs.ParamNameTexts.Length || paramCount > outputs.ParamTypeTexts.Length {
        return -1
    }
    if paramCount > outputs.ArgKinds.Length || paramCount > outputs.ArgTexts.Length {
        return -1
    }

    defaultCount := ParseConstructorParameterDefaultsCore(source, ref tokens, count, ctorIndex, ref outputs)
    if defaultCount != paramCount {
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

    if ctorIndex < 0 || ctorIndex >= count {
        return -1
    }

    if tokens.Kinds[ctorIndex] != 0 {
        return -1
    }

    if !ParserDeclarationTokenTextEquals(source, tokens.Starts[ctorIndex], tokens.ValueLengths[ctorIndex], "constructor") {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    chainArgKinds := new int[](count + 1)
    chainArgStarts := new int[](count + 1)
    chainArgLengths := new int[](count + 1)
    chainArgs := new ConstructorChainArgTable { Kinds: chainArgKinds, Starts: chainArgStarts, Lengths: chainArgLengths }
    chainResult := new ParserDeclarationResultTable { Values: result.Values }
    chainArgCount := ParseConstructorChainInfoCore(ref declarationTokens, count, ctorIndex, ref chainArgs, ref chainResult)
    if chainArgCount < 0 {
        return -1
    }

    if outputs.ArgTexts.Length < paramCount + chainArgCount || outputs.ArgKinds.Length < paramCount + chainArgCount || outputs.ArgStarts.Length < paramCount + chainArgCount || outputs.ArgLengths.Length < paramCount + chainArgCount {
        return -1
    }

    chainArgIndex := 0
    while chainArgIndex < chainArgCount {
        chainOutputIndex := paramCount + chainArgIndex
        outputs.ArgKinds[chainOutputIndex] = chainArgs.Kinds[chainArgIndex]
        outputs.ArgStarts[chainOutputIndex] = chainArgs.Starts[chainArgIndex]
        outputs.ArgLengths[chainOutputIndex] = chainArgs.Lengths[chainArgIndex]
        outputs.ArgTexts[chainOutputIndex] = source.Substring(chainArgs.Starts[chainArgIndex], chainArgs.Lengths[chainArgIndex])
        chainArgIndex = chainArgIndex + 1
    }

    bodyBrace := result.Values[1]
    if bodyBrace < 0 || bodyBrace >= count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    result.Values[2] = paramCount
    result.Values[3] = chainArgCount
    return paramCount
}

func ConstructorSignatureDefaultKindSupported(kind: int): bool {
    return kind == 46 || kind == 44 || kind == 45 || kind == 1 || kind == 4
}

func ParseConstructorParameterDefaultsCore(source: string, tokens: &ParserTokenTable, count: int, ctorIndex: int, outputs: &ConstructorSignatureOutputTable): int {
    if ctorIndex < 0 || ctorIndex >= count || tokens.Kinds[ctorIndex] != 0 {
        return -1
    }

    if !ParserDeclarationTokenTextEquals(source, tokens.Starts[ctorIndex], tokens.ValueLengths[ctorIndex], "constructor") {
        return -1
    }

    pos := ctorIndex + 1
    if pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }
    pos = pos + 1

    typeStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserNodeTable { Kinds: new int[](count + 1), ValueStarts: new int[](count + 1), ValueLengths: new int[](count + 1), ChildStart: new int[](count + 1), ChildCount: new int[](count + 1), SpanStarts: new int[](count + 1), SpanLengths: new int[](count + 1) }
    children := new ParserChildIndexTable { Indices: new int[](count + 1) }
    st := new ParserState { Pos: 0, NodeCursor: 0, ChildCursor: 0, ArgStackTop: 0, SplitGreaterDepth: 0, OwedGreaterByteEnd: 0 }

    paramCount := 0
    foundDefault := 0
    while pos < count && tokens.Kinds[pos] != 128 {
        if paramCount >= outputs.ArgKinds.Length || paramCount >= outputs.ArgTexts.Length {
            return -1
        }

        while pos < count && tokens.Kinds[pos] == 131 {
            bracketDepth := 1
            pos = pos + 1
            while pos < count && bracketDepth > 0 {
                if tokens.Kinds[pos] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[pos] == 132 {
                    bracketDepth = bracketDepth - 1
                }
                pos = pos + 1
            }
        }

        while pos < count && (tokens.Kinds[pos] == 78 || tokens.Kinds[pos] == 79 || tokens.Kinds[pos] == 82 || tokens.Kinds[pos] == 42) {
            pos = pos + 1
        }

        if pos >= count || tokens.Kinds[pos] != 0 {
            return -1
        }
        pos = pos + 1

        if pos >= count || tokens.Kinds[pos] != 122 {
            return -1
        }
        pos = pos + 1

        st.Pos = pos
        st.NodeCursor = 0
        st.ChildCursor = 0
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        typeRoot := ParseUnionTypeReferenceNodeCore(ref tokens, count, ref st, ref typeStack, ref nodes, ref children, 0)
        if typeRoot < 0 {
            return -1
        }
        pos = st.Pos

        outputs.ArgKinds[paramCount] = -1
        outputs.ArgTexts[paramCount] = ""

        if pos < count && tokens.Kinds[pos] == 93 {
            foundDefault = 1
            pos = pos + 1
            if pos >= count {
                return -1
            }

            defaultKind := tokens.Kinds[pos]
            defaultStart := tokens.Starts[pos]
            defaultLength := tokens.ValueLengths[pos]
            defaultTokenCount := 0
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && pos < count {
                k := tokens.Kinds[pos]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        defaultTokenCount = defaultTokenCount + 1
                        pos = pos + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                }
            }

            if defaultTokenCount != 1 || !ConstructorSignatureDefaultKindSupported(defaultKind) {
                return -1
            }

            outputs.ArgKinds[paramCount] = defaultKind
            outputs.ArgTexts[paramCount] = FunctionSignatureSpanText(source, defaultStart, defaultLength)
        } else if foundDefault == 1 {
            return -1
        }

        paramCount = paramCount + 1

        if pos >= count || (tokens.Kinds[pos] != 134 && tokens.Kinds[pos] != 128) {
            return -1
        }

        if tokens.Kinds[pos] == 134 {
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }

    return paramCount
}
