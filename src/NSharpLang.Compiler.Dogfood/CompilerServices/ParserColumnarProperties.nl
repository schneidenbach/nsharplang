// Product columnar property parser wrapper. It composes property accessor/type parsing with getter/setter
// statement-node rowsets so the C# adapter no longer binds statement parsing for property bodies.

struct ColumnarPropertyTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
}

struct ColumnarPropertyTextTable {
    NameTexts: string[]
    TypeTexts: string[]
}

struct ColumnarPropertyBodyTable {
    NodeKinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    SpanStarts: int[]
    SpanLengths: int[]
}

struct ColumnarPropertyResultTable {
    Values: int[]
}

func ParseColumnarPropertyInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, propIndex: int, outNameTexts: string[], outTypeTexts: string[], outGetNodeKinds: int[], outGetValueStarts: int[], outGetValueLengths: int[], outGetChildStart: int[], outGetChildCount: int[], outGetChildIndices: int[], outGetSpanStarts: int[], outGetSpanLengths: int[], outSetNodeKinds: int[], outSetValueStarts: int[], outSetValueLengths: int[], outSetChildStart: int[], outSetChildCount: int[], outSetChildIndices: int[], outSetSpanStarts: int[], outSetSpanLengths: int[], outResult: int[]): int {
    tokens := new ColumnarPropertyTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths, Count: count }
    texts := new ColumnarPropertyTextTable { NameTexts: outNameTexts, TypeTexts: outTypeTexts }
    getBody := new ColumnarPropertyBodyTable { NodeKinds: outGetNodeKinds, ValueStarts: outGetValueStarts, ValueLengths: outGetValueLengths, ChildStart: outGetChildStart, ChildCount: outGetChildCount, ChildIndices: outGetChildIndices, SpanStarts: outGetSpanStarts, SpanLengths: outGetSpanLengths }
    setBody := new ColumnarPropertyBodyTable { NodeKinds: outSetNodeKinds, ValueStarts: outSetValueStarts, ValueLengths: outSetValueLengths, ChildStart: outSetChildStart, ChildCount: outSetChildCount, ChildIndices: outSetChildIndices, SpanStarts: outSetSpanStarts, SpanLengths: outSetSpanLengths }
    result := new ColumnarPropertyResultTable { Values: outResult }
    return ParseColumnarPropertyInfoCore(source, ref tokens, propIndex, ref texts, ref getBody, ref setBody, ref result)
}

func ParseColumnarPropertyInfoCore(source: string, tokens: &ColumnarPropertyTokenTable, propIndex: int, texts: &ColumnarPropertyTextTable, getBody: &ColumnarPropertyBodyTable, setBody: &ColumnarPropertyBodyTable, result: &ColumnarPropertyResultTable): int {
    if result.Values.Length < 10 {
        return -1
    }

    if texts.NameTexts.Length < 1 || texts.TypeTexts.Length < 1 {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    propertyResult := new ParserDeclarationResultTable { Values: new int[](6) }
    accessorKind := ParsePropertyAccessorInfoCore(source, ref declarationTokens, tokens.Count, propIndex, ref propertyResult)
    if accessorKind < 0 {
        return -1
    }

    nameText := ParserDeclarationSpanText(source, propertyResult.Values[0], propertyResult.Values[1])
    if nameText == "" {
        return -1
    }

    typeText := ParserDeclarationCanonicalTypeText(source, propertyResult.Values[2], propertyResult.Values[3])
    if typeText == "" {
        return -1
    }

    texts.NameTexts[0] = nameText
    texts.TypeTexts[0] = typeText

    getBodyBrace := propertyResult.Values[4]
    if getBodyBrace < 0 || getBodyBrace >= tokens.Count || tokens.Kinds[getBodyBrace] != 129 {
        return -1
    }

    getBodyResult := new ColumnarPropertyResultTable { Values: new int[](2) }
    getBodyNodeCount := ParseColumnarPropertyBodyNodesInto(ref tokens, getBodyBrace, ref getBody, ref getBodyResult)
    if getBodyNodeCount <= 0 {
        return -1
    }

    getBodyRoot := getBodyResult.Values[0]
    if getBodyRoot < 0 || getBodyRoot >= getBodyNodeCount {
        return -1
    }

    setBodyRoot := -1
    setBodyNodeCount := 0
    if accessorKind == 1 {
        setBodyBrace := propertyResult.Values[5]
        if setBodyBrace < 0 || setBodyBrace >= tokens.Count || tokens.Kinds[setBodyBrace] != 129 {
            return -1
        }

        setBodyResult := new ColumnarPropertyResultTable { Values: new int[](2) }
        setBodyNodeCount = ParseColumnarPropertyBodyNodesInto(ref tokens, setBodyBrace, ref setBody, ref setBodyResult)
        if setBodyNodeCount <= 0 {
            return -1
        }

        setBodyRoot = setBodyResult.Values[0]
        if setBodyRoot < 0 || setBodyRoot >= setBodyNodeCount {
            return -1
        }
    } else if accessorKind != 0 {
        return -1
    }

    result.Values[0] = propertyResult.Values[0]
    result.Values[1] = propertyResult.Values[1]
    result.Values[2] = propertyResult.Values[2]
    result.Values[3] = propertyResult.Values[3]
    result.Values[4] = getBodyBrace
    result.Values[5] = propertyResult.Values[5]
    result.Values[6] = getBodyRoot
    result.Values[7] = getBodyNodeCount
    result.Values[8] = setBodyRoot
    result.Values[9] = setBodyNodeCount
    return accessorKind
}

func ParseColumnarPropertyBodyNodesInto(tokens: &ColumnarPropertyTokenTable, bodyBrace: int, body: &ColumnarPropertyBodyTable, result: &ColumnarPropertyResultTable): int {
    statementTokens := new ParserTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    argStack := new ParserArgumentStack { Values: new int[](tokens.Count + 1) }
    nodes := new ParserExpressionNodeTable { Kinds: body.NodeKinds, ValueStarts: body.ValueStarts, ValueLengths: body.ValueLengths, ChildStart: body.ChildStart, ChildCount: body.ChildCount, SpanStarts: body.SpanStarts, SpanLengths: body.SpanLengths }
    children := new ParserChildIndexTable { Indices: body.ChildIndices }
    statementResult := new ParserResultTable { Values: result.Values }
    return ParseStatementNodesCore(ref statementTokens, tokens.Count, bodyBrace, ref argStack, ref nodes, ref children, ref statementResult)
}
