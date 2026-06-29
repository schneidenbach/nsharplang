import "CompilerServices/ParserConstructorSignatures"
import "CompilerServices/ParserDeclarations"
import "CompilerServices/ParserExpressions"
import "CompilerServices/ParserFunctionSignatures"
import "CompilerServices/ParserTypeReferences"

// Product columnar constructor parser wrapper. It composes constructor signature/chain parsing with the
// statement-node rowset so the host adapter no longer orchestrates constructor body parsing.

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

    if ctorIndex >= 0 && ctorIndex < tokens.Count && (tokens.Kinds[ctorIndex] == 8 || tokens.Kinds[ctorIndex] == 9 || tokens.Kinds[ctorIndex] == 13) {
        return ParseColumnarPrimaryConstructorInfoCore(source, ref tokens, ctorIndex, ref signatureOutputs, ref body, ref result)
    }

    signatureTokens := new ParserTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    signatureOutput := new ConstructorSignatureOutputTable { ParamNameTexts: signatureOutputs.ParamNameTexts, ParamTypeTexts: signatureOutputs.ParamTypeTexts, ArgKinds: signatureOutputs.ArgKinds, ArgStarts: signatureOutputs.ArgStarts, ArgLengths: signatureOutputs.ArgLengths, ArgTexts: signatureOutputs.ArgTexts }
    typeStack := new ParserArgumentStack { Values: new int[](tokens.Count + 1) }
    nodes := new ParserNodeTable { Kinds: new int[](tokens.Count + 1), ValueStarts: new int[](tokens.Count + 1), ValueLengths: new int[](tokens.Count + 1), ChildStart: new int[](tokens.Count + 1), ChildCount: new int[](tokens.Count + 1), SpanStarts: new int[](tokens.Count + 1), SpanLengths: new int[](tokens.Count + 1) }
    children := new ParserChildIndexTable { Indices: new int[](tokens.Count + 1) }
    canonicalNodes := new TypeReferenceCanonicalTable { Kinds: nodes.Kinds, ValueStarts: nodes.ValueStarts, ValueLengths: nodes.ValueLengths, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, ChildIndices: children.Indices }
    parameters := new ParserFunctionParameterTable { NameStarts: new int[](tokens.Count + 1), NameLengths: new int[](tokens.Count + 1), TypeRoots: new int[](tokens.Count + 1) }
    typeParams := new ParserFunctionTypeParameterTable { Starts: new int[](tokens.Count + 1), Lengths: new int[](tokens.Count + 1) }
    whereItems := new ParserFunctionWhereTable { NameStarts: new int[](tokens.Count + 1), NameLengths: new int[](tokens.Count + 1), ItemCodes: new int[](tokens.Count + 1) }
    functionSignatureResult := new ParserResultTable { Values: new int[](8) }
    signatureResult := new ParserResultTable { Values: new int[](4) }
    paramCount := ParseConstructorSignatureInfoCore(source, ref signatureTokens, tokens.Count, ctorIndex, ref signatureOutput, ref typeStack, ref nodes, ref children, ref canonicalNodes, ref parameters, ref typeParams, ref whereItems, ref functionSignatureResult, ref signatureResult)
    if paramCount < 0 {
        return -1
    }
    bodyBrace := signatureResult.Values[1]
    if bodyBrace < 0 || bodyBrace >= tokens.Count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    bodyResult := new ColumnarConstructorResultTable { Values: new int[](2) }
    bodyNodeCount := ParseColumnarConstructorBodyNodesCore(ref tokens, bodyBrace, ref body, ref bodyResult)
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

func ColumnarPrimaryConstructorLiteralExpressionKind(tokenKind: int): int {
    if tokenKind == 1 {
        return 0
    }
    if tokenKind == 2 {
        return 1
    }
    if tokenKind == 3 {
        return 2
    }
    if tokenKind == 4 {
        return 3
    }
    if tokenKind == 44 || tokenKind == 45 {
        return 4
    }
    if tokenKind == 46 {
        return 5
    }

    return -1
}

func ColumnarPrimaryConstructorTypeIsNullable(source: string, typeStart: int, typeLength: int): bool {
    if typeStart < 0 || typeLength <= 0 || typeStart + typeLength > source.Length {
        return false
    }

    return source[typeStart + typeLength - 1] == '?'
}

func EmitColumnarPrimaryConstructorAssignmentNode(body: &ColumnarConstructorBodyTable, fieldStart: int, fieldLength: int, valueKind: int, valueStart: int, valueLength: int, eqStart: int, eqLength: int, nodeCursor: int, childCursor: int, result: &ColumnarConstructorResultTable): int {
    if result.Values.Length < 2 {
        return -1
    }
    if nodeCursor + 4 > body.NodeKinds.Length || childCursor + 3 > body.ChildIndices.Length {
        return -1
    }

    targetNode := nodeCursor
    body.NodeKinds[targetNode] = 6
    body.ValueStarts[targetNode] = fieldStart
    body.ValueLengths[targetNode] = fieldLength
    body.ChildStart[targetNode] = -1
    body.ChildCount[targetNode] = 0
    body.SpanStarts[targetNode] = fieldStart
    body.SpanLengths[targetNode] = fieldLength
    nodeCursor = nodeCursor + 1

    valueNode := nodeCursor
    body.NodeKinds[valueNode] = valueKind
    body.ValueStarts[valueNode] = valueStart
    body.ValueLengths[valueNode] = valueLength
    body.ChildStart[valueNode] = -1
    body.ChildCount[valueNode] = 0
    body.SpanStarts[valueNode] = valueStart
    body.SpanLengths[valueNode] = valueLength
    nodeCursor = nodeCursor + 1

    assignmentNode := nodeCursor
    body.NodeKinds[assignmentNode] = 14
    body.ValueStarts[assignmentNode] = eqStart
    body.ValueLengths[assignmentNode] = eqLength
    body.ChildStart[assignmentNode] = childCursor
    body.ChildCount[assignmentNode] = 2
    body.ChildIndices[childCursor] = targetNode
    body.ChildIndices[childCursor + 1] = valueNode
    body.SpanStarts[assignmentNode] = fieldStart
    if valueStart >= 0 {
        body.SpanLengths[assignmentNode] = valueStart + valueLength - fieldStart
    } else {
        body.SpanLengths[assignmentNode] = fieldLength
    }
    childCursor = childCursor + 2
    nodeCursor = nodeCursor + 1

    statementNode := nodeCursor
    body.NodeKinds[statementNode] = 23
    body.ValueStarts[statementNode] = -1
    body.ValueLengths[statementNode] = 0
    body.ChildStart[statementNode] = childCursor
    body.ChildCount[statementNode] = 1
    body.ChildIndices[childCursor] = assignmentNode
    body.SpanStarts[statementNode] = fieldStart
    if valueStart >= 0 {
        body.SpanLengths[statementNode] = valueStart + valueLength - fieldStart
    } else {
        body.SpanLengths[statementNode] = fieldLength
    }
    childCursor = childCursor + 1
    nodeCursor = nodeCursor + 1

    result.Values[0] = nodeCursor
    result.Values[1] = childCursor
    return statementNode
}

func EmitColumnarPrimaryConstructorAssignmentRootNode(body: &ColumnarConstructorBodyTable, fieldStart: int, fieldLength: int, valueRoot: int, eqStart: int, eqLength: int, nodeCursor: int, childCursor: int, result: &ColumnarConstructorResultTable): int {
    if result.Values.Length < 2 {
        return -1
    }
    if valueRoot < 0 || valueRoot >= nodeCursor || nodeCursor + 3 > body.NodeKinds.Length || childCursor + 3 > body.ChildIndices.Length {
        return -1
    }

    targetNode := nodeCursor
    body.NodeKinds[targetNode] = 6
    body.ValueStarts[targetNode] = fieldStart
    body.ValueLengths[targetNode] = fieldLength
    body.ChildStart[targetNode] = -1
    body.ChildCount[targetNode] = 0
    body.SpanStarts[targetNode] = fieldStart
    body.SpanLengths[targetNode] = fieldLength
    nodeCursor = nodeCursor + 1

    assignmentNode := nodeCursor
    body.NodeKinds[assignmentNode] = 14
    body.ValueStarts[assignmentNode] = eqStart
    body.ValueLengths[assignmentNode] = eqLength
    body.ChildStart[assignmentNode] = childCursor
    body.ChildCount[assignmentNode] = 2
    body.ChildIndices[childCursor] = targetNode
    body.ChildIndices[childCursor + 1] = valueRoot
    body.SpanStarts[assignmentNode] = fieldStart
    body.SpanLengths[assignmentNode] = body.SpanStarts[valueRoot] + body.SpanLengths[valueRoot] - fieldStart
    childCursor = childCursor + 2
    nodeCursor = nodeCursor + 1

    statementNode := nodeCursor
    body.NodeKinds[statementNode] = 23
    body.ValueStarts[statementNode] = -1
    body.ValueLengths[statementNode] = 0
    body.ChildStart[statementNode] = childCursor
    body.ChildCount[statementNode] = 1
    body.ChildIndices[childCursor] = assignmentNode
    body.SpanStarts[statementNode] = fieldStart
    body.SpanLengths[statementNode] = body.SpanStarts[valueRoot] + body.SpanLengths[valueRoot] - fieldStart
    childCursor = childCursor + 1
    nodeCursor = nodeCursor + 1

    result.Values[0] = nodeCursor
    result.Values[1] = childCursor
    return statementNode
}

func ParseColumnarPrimaryConstructorInfoCore(source: string, tokens: &ColumnarConstructorTokenTable, ctorIndex: int, signatureOutputs: &ColumnarConstructorSignatureOutputTable, body: &ColumnarConstructorBodyTable, result: &ColumnarConstructorResultTable): int {
    pos := ctorIndex + 1
    if pos >= tokens.Count || tokens.Kinds[pos] != 0 {
        return -1
    }
    pos = pos + 1

    if pos < tokens.Count && tokens.Kinds[pos] == 100 {
        gdepth := 0
        gdone := 0
        while pos < tokens.Count && gdone == 0 {
            if tokens.Kinds[pos] == 100 {
                gdepth = gdepth + 1
            } else if tokens.Kinds[pos] == 102 {
                gdepth = gdepth - 1
                if gdepth == 0 {
                    gdone = 1
                }
            } else if tokens.Kinds[pos] == 112 {
                gdepth = gdepth - 2
                if gdepth == 0 {
                    gdone = 1
                }
            }
            if gdepth < 0 {
                return -1
            }
            pos = pos + 1
        }
        if gdone == 0 {
            return -1
        }
    }

    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    primaryParameters := new PrimaryConstructorParameterTable {
        NameStarts: new int[](tokens.Count + 1),
        NameLengths: new int[](tokens.Count + 1),
        TypeStarts: new int[](tokens.Count + 1),
        TypeLengths: new int[](tokens.Count + 1),
        DefaultKinds: new int[](tokens.Count + 1),
        DefaultStarts: new int[](tokens.Count + 1),
        DefaultLengths: new int[](tokens.Count + 1)
    }
    primaryResult := new ParserDeclarationResultTable { Values: new int[](1) }
    paramCount := 0
    if pos < tokens.Count && tokens.Kinds[pos] == 127 {
        paramCount = ParsePrimaryConstructorParameterSpansCore(source, ref declarationTokens, tokens.Count, pos, ref primaryParameters, ref primaryResult)
    } else {
        primaryResult.Values[0] = pos
    }
    if paramCount < 0 || paramCount > signatureOutputs.ParamNameTexts.Length || paramCount > signatureOutputs.ParamTypeTexts.Length || paramCount > signatureOutputs.ArgKinds.Length || paramCount > signatureOutputs.ArgTexts.Length {
        return -1
    }

    p := 0
    while p < paramCount {
        paramName := ParserDeclarationSpanText(source, primaryParameters.NameStarts[p], primaryParameters.NameLengths[p])
        paramType := ParserDeclarationCanonicalTypeText(source, primaryParameters.TypeStarts[p], primaryParameters.TypeLengths[p])
        if paramName == "" || paramType == "" {
            return -1
        }

        signatureOutputs.ParamNameTexts[p] = paramName
        signatureOutputs.ParamTypeTexts[p] = paramType
        signatureOutputs.ArgKinds[p] = primaryParameters.DefaultKinds[p]
        if primaryParameters.DefaultKinds[p] >= 0 {
            signatureOutputs.ArgTexts[p] = ParserDeclarationSpanText(source, primaryParameters.DefaultStarts[p], primaryParameters.DefaultLengths[p])
        } else {
            signatureOutputs.ArgTexts[p] = ""
        }
        p = p + 1
    }

    pos = primaryResult.Values[0]
    if pos < tokens.Count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        while true {
            if pos >= tokens.Count || tokens.Kinds[pos] != 0 {
                return -1
            }
            pos = pos + 1
            if pos < tokens.Count && tokens.Kinds[pos] == 134 {
                pos = pos + 1
                continue
            }
            break
        }
    }

    bodyBrace := pos
    if bodyBrace < 0 || bodyBrace >= tokens.Count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    statementIndices := new int[](tokens.Count + 1)
    assignedFlags := new int[](tokens.Count + 1)
    nodeCursor := 0
    childCursor := 0
    assignmentCount := 0
    cursorResult := new ColumnarConstructorResultTable { Values: new int[](2) }
    typeResult := new ParserDeclarationResultTable { Values: new int[](2) }
    memberModifierValues := new int[](2)
    memberModifiers := new ParserDeclarationResultTable { Values: memberModifierValues }
    expressionTokens := new ParserTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    expressionNodes := new ParserExpressionNodeTable { Kinds: body.NodeKinds, ValueStarts: body.ValueStarts, ValueLengths: body.ValueLengths, ChildStart: body.ChildStart, ChildCount: body.ChildCount, SpanStarts: body.SpanStarts, SpanLengths: body.SpanLengths }
    expressionChildren := new ParserChildIndexTable { Indices: body.ChildIndices }
    expressionStack := new ParserArgumentStack { Values: new int[](tokens.Count + 1) }

    scan := bodyBrace + 1
    scanDone := 0
    while scanDone == 0 && scan < tokens.Count && tokens.Kinds[scan] != 130 && tokens.Kinds[scan] != 7 {
        memberStart := ParseMemberModifierPrefixCore(ref declarationTokens, tokens.Count, scan, ref memberModifiers)
        if memberStart < 0 || memberStart >= tokens.Count {
            return -1
        }

        if tokens.Kinds[memberStart] == 7 || (tokens.Kinds[memberStart] == 0 && memberStart + 1 < tokens.Count && tokens.Kinds[memberStart + 1] == 127) {
            scanDone = 1
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 1 < tokens.Count && tokens.Kinds[memberStart + 1] == 122 {
            fieldNameStart := tokens.Starts[memberStart]
            fieldNameLength := tokens.ValueLengths[memberStart]
            scan = memberStart + 2
            scan = ParseDeclarationTypeSpanCore(ref declarationTokens, tokens.Count, scan, ref typeResult)
            if scan < 0 {
                return -1
            }

            if scan < tokens.Count && tokens.Kinds[scan] == 129 {
                pdepth := 0
                pdone := 0
                while scan < tokens.Count && pdone == 0 {
                    if tokens.Kinds[scan] == 129 {
                        pdepth = pdepth + 1
                    } else if tokens.Kinds[scan] == 130 {
                        pdepth = pdepth - 1
                        if pdepth == 0 {
                            pdone = 1
                        }
                    }
                    scan = scan + 1
                }
                if pdone == 0 {
                    return -1
                }
            } else if scan < tokens.Count && tokens.Kinds[scan] == 120 {
                while scan < tokens.Count && tokens.Kinds[scan] != 136 && tokens.Kinds[scan] != 130 {
                    scan = scan + 1
                }
                if scan < tokens.Count && tokens.Kinds[scan] == 136 {
                    scan = scan + 1
                }
            } else {
                valueKind := -1
                valueStart := -1
                valueLength := 0
                eqStart := -1
                eqLength := 1
                valueRoot := -1
                if scan < tokens.Count && tokens.Kinds[scan] == 93 {
                    eqStart = tokens.Starts[scan]
                    eqLength = tokens.ValueLengths[scan]
                    scan = scan + 1
                    if scan >= tokens.Count {
                        return -1
                    }
                    if tokens.Kinds[scan] == 0 {
                        paramIndex := PrimaryConstructorParameterIndexOf(source, ref primaryParameters, paramCount, tokens.Starts[scan], tokens.ValueLengths[scan])
                        if paramIndex >= 0 {
                            assignedFlags[paramIndex] = 1
                            valueKind = 6
                            valueStart = tokens.Starts[scan]
                            valueLength = tokens.ValueLengths[scan]
                            scan = scan + 1
                        } else {
                            expressionState := new ParserState { Pos: scan, NodeCursor: nodeCursor, ChildCursor: childCursor, ArgStackTop: 0, SplitGreaterDepth: 0, OwedGreaterByteEnd: 0 }
                            valueRoot = ParseLambdaOrAssignmentExpressionNode(ref expressionTokens, tokens.Count, ref expressionState, ref expressionStack, ref expressionNodes, ref expressionChildren, 0)
                            if valueRoot < 0 || expressionState.Pos <= scan {
                                return -1
                            }
                            nodeCursor = expressionState.NodeCursor
                            childCursor = expressionState.ChildCursor
                            scan = expressionState.Pos
                        }
                    } else {
                        valueKind = ColumnarPrimaryConstructorLiteralExpressionKind(tokens.Kinds[scan])
                        if valueKind >= 0 {
                            valueStart = tokens.Starts[scan]
                            valueLength = tokens.ValueLengths[scan]
                            scan = scan + 1
                        } else {
                            expressionState := new ParserState { Pos: scan, NodeCursor: nodeCursor, ChildCursor: childCursor, ArgStackTop: 0, SplitGreaterDepth: 0, OwedGreaterByteEnd: 0 }
                            valueRoot = ParseLambdaOrAssignmentExpressionNode(ref expressionTokens, tokens.Count, ref expressionState, ref expressionStack, ref expressionNodes, ref expressionChildren, 0)
                            if valueRoot < 0 || expressionState.Pos <= scan {
                                return -1
                            }
                            nodeCursor = expressionState.NodeCursor
                            childCursor = expressionState.ChildCursor
                            scan = expressionState.Pos
                        }
                    }
                } else if ColumnarPrimaryConstructorTypeIsNullable(source, typeResult.Values[0], typeResult.Values[1]) {
                    valueKind = 5
                } else {
                    matchedParam := PrimaryConstructorParameterIndexOf(source, ref primaryParameters, paramCount, fieldNameStart, fieldNameLength)
                    if matchedParam >= 0 {
                        assignedFlags[matchedParam] = 1
                        valueKind = 6
                        valueStart = primaryParameters.NameStarts[matchedParam]
                        valueLength = primaryParameters.NameLengths[matchedParam]
                    }
                }

                if valueKind >= 0 && memberModifiers.Values[0] == 0 {
                    statementNode := EmitColumnarPrimaryConstructorAssignmentNode(ref body, fieldNameStart, fieldNameLength, valueKind, valueStart, valueLength, eqStart, eqLength, nodeCursor, childCursor, ref cursorResult)
                    if statementNode < 0 || assignmentCount >= statementIndices.Length {
                        return -1
                    }
                    nodeCursor = cursorResult.Values[0]
                    childCursor = cursorResult.Values[1]
                    statementIndices[assignmentCount] = statementNode
                    assignmentCount = assignmentCount + 1
                } else if valueRoot >= 0 && memberModifiers.Values[0] == 0 {
                    statementNode := EmitColumnarPrimaryConstructorAssignmentRootNode(ref body, fieldNameStart, fieldNameLength, valueRoot, eqStart, eqLength, nodeCursor, childCursor, ref cursorResult)
                    if statementNode < 0 || assignmentCount >= statementIndices.Length {
                        return -1
                    }
                    nodeCursor = cursorResult.Values[0]
                    childCursor = cursorResult.Values[1]
                    statementIndices[assignmentCount] = statementNode
                    assignmentCount = assignmentCount + 1
                }
            }
        } else {
            return -1
        }
    }

    if tokens.Kinds[ctorIndex] == 8 || tokens.Kinds[ctorIndex] == 13 {
        p = 0
        while p < paramCount {
            if assignedFlags[p] == 0 {
                statementNode := EmitColumnarPrimaryConstructorAssignmentNode(ref body, primaryParameters.NameStarts[p], primaryParameters.NameLengths[p], 6, primaryParameters.NameStarts[p], primaryParameters.NameLengths[p], -1, 1, nodeCursor, childCursor, ref cursorResult)
                if statementNode < 0 || assignmentCount >= statementIndices.Length {
                    return -1
                }
                nodeCursor = cursorResult.Values[0]
                childCursor = cursorResult.Values[1]
                statementIndices[assignmentCount] = statementNode
                assignmentCount = assignmentCount + 1
            }

            p = p + 1
        }
    }

    if nodeCursor >= body.NodeKinds.Length || childCursor + assignmentCount > body.ChildIndices.Length {
        return -1
    }
    root := nodeCursor
    body.NodeKinds[root] = 25
    body.ValueStarts[root] = -1
    body.ValueLengths[root] = 0
    body.ChildStart[root] = childCursor
    body.ChildCount[root] = assignmentCount
    body.SpanStarts[root] = tokens.Starts[bodyBrace]
    body.SpanLengths[root] = tokens.ValueLengths[bodyBrace]
    i := 0
    while i < assignmentCount {
        body.ChildIndices[childCursor + i] = statementIndices[i]
        i = i + 1
    }
    nodeCursor = nodeCursor + 1

    result.Values[0] = 0
    result.Values[1] = bodyBrace
    result.Values[2] = paramCount
    result.Values[3] = 0
    result.Values[4] = root
    result.Values[5] = nodeCursor
    return paramCount
}

func ParseColumnarConstructorBodyNodesCore(tokens: &ColumnarConstructorTokenTable, bodyBrace: int, body: &ColumnarConstructorBodyTable, result: &ColumnarConstructorResultTable): int {
    statementTokens := new ParserTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    argStack := new ParserArgumentStack { Values: new int[](tokens.Count + 1) }
    nodes := new ParserExpressionNodeTable { Kinds: body.NodeKinds, ValueStarts: body.ValueStarts, ValueLengths: body.ValueLengths, ChildStart: body.ChildStart, ChildCount: body.ChildCount, SpanStarts: body.SpanStarts, SpanLengths: body.SpanLengths }
    children := new ParserChildIndexTable { Indices: body.ChildIndices }
    statementResult := new ParserResultTable { Values: result.Values }
    return ParseStatementNodesCore(ref statementTokens, tokens.Count, bodyBrace, ref argStack, ref nodes, ref children, ref statementResult)
}
