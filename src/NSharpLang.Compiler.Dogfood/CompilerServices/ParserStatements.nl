// Parser slices 16-17: the STATEMENT kernel -- function bodies, the critical path for parsing the dogfood
// kernels (flat top-level functions whose bodies are statements). ParseStatementNodesInto parses ONE
// statement at a token index by dispatching like the C# ParseStatement (Parser.cs:2165), and COMPOSES the
// slice 10-15 expression kernel: statements and expressions share ONE columnar node table (the expression
// table), with the shared expression parser-state array `st` and `argStack`. Statement nodes use kinds 20+
// so they never collide with the expression kinds 0-14.
//
// Supported statement nodes (matching the concrete C# Statement records):
//   ReturnStatement              -> kind 20  ( return [value]; 0 or 1 child = the value expression )
//   BreakStatement               -> kind 21  ( break; 0 children )
//   ContinueStatement            -> kind 22  ( continue; 0 children )
//   ExpressionStatement          -> kind 23  ( <expr>; 1 child = the expression, incl. assignment exprs )
//   VariableDeclarationStatement -> kind 24  ( name := init; name in the value span, 1 child = initializer )
//   BlockStatement               -> kind 25  ( { stmt* }; children = the statements, variable arity )
//   WhileStatement               -> kind 26  ( while cond <body>; children [condition, body] )
//   IfStatement                  -> kind 27  ( if cond <then> [else <else>]; children [cond, then, else?] )
// `:=` (ColonAssign 121) after a BARE identifier is the variable declaration (Kind=Let, Type=null); `=`
// (Assign 93) is an assignment EXPRESSION wrapped in an ExpressionStatement. Following the C# parser, an
// if/while body is ANY statement (commonly a `{ }` block, but a single statement is also valid), so the
// bodies recurse through the statement dispatcher; `else if` chains as a nested if.
//
// Deferred: for/foreach, let/const/readonly + typed `name: Type = init` declarations, tuple deconstruction,
// throw/try/using/lock/switch/yield/print/assert/local-functions, and statements whose expression parts use
// a not-yet-supported form (e.g. `new`/`alloc`). Block statement-list gathers child node ids on the LIFO
// `argStack` (recursion is LIFO) and appends the contiguous child run after `}`, exactly as calls/generics do.
//
// Node-table columns are the EXPRESSION table (see ParserExpressions.nl).
//   outResult[0] = root statement node id (== nodeCount-1), outResult[1] = token index past the statement.
// Returns the node count, or -1 on refusal / a malformed statement / an unsupported expression part.
//
// TokenType ordinals (Token.cs): Identifier 0, If 23, Else 24, While 27, Return 29, Break 35, Continue 36,
// ColonAssign 121, LeftBrace 129, RightBrace 130, Eof 135, Newline 136.

// Parse a `{ ... }` block: a sequence of statements until the matching `}`. BlockStatement (kind 25),
// children = the contained statement node ids (variable arity -> LIFO arg-stack). st[0] must be at the `{`.
func ParseBlockStatementNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    blockStart := tokenStarts[st[0]]
    st[0] = st[0] + 1
    argBase := st[3]

    while st[0] < count && tokenKinds[st[0]] != 130 {
        stmt := ParseStatementCoreNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if stmt < 0 {
            st[3] = argBase
            return -1
        }

        argStack[st[3]] = stmt
        st[3] = st[3] + 1
    }

    if st[0] >= count || tokenKinds[st[0]] != 130 {
        st[3] = argBase
        return -1
    }

    rightBraceEnd := tokenStarts[st[0]] + tokenValueLengths[st[0]]
    st[0] = st[0] + 1
    childCount := st[3] - argBase
    childRunStart := st[2]
    a := argBase
    while a < st[3] {
        AppendExpressionChild(st, outChildIndices, argStack[a])
        a = a + 1
    }
    st[3] = argBase

    return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 25, -1, 0, childRunStart, childCount, blockStart, rightBraceEnd - blockStart)
}

// Dispatch + parse a single statement at st[0]. Returns the emitted statement node id, or -1.
func ParseStatementCoreNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    if depth > 200 {
        return -1
    }

    start := st[0]
    if start >= count {
        return -1
    }

    kind := tokenKinds[start]

    if kind == 129 {
        return ParseBlockStatementNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth)
    }

    if kind == 27 {
        whileStart := tokenStarts[start]
        st[0] = start + 1
        condition := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if condition < 0 {
            return -1
        }

        body := ParseStatementCoreNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if body < 0 {
            return -1
        }

        bodyEnd := outSpanStarts[body] + outSpanLengths[body]
        childRunStart := st[2]
        AppendExpressionChild(st, outChildIndices, condition)
        AppendExpressionChild(st, outChildIndices, body)
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 26, -1, 0, childRunStart, 2, whileStart, bodyEnd - whileStart)
    }

    if kind == 23 {
        ifStart := tokenStarts[start]
        st[0] = start + 1
        condition := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if condition < 0 {
            return -1
        }

        thenNode := ParseStatementCoreNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if thenNode < 0 {
            return -1
        }

        endSpan := outSpanStarts[thenNode] + outSpanLengths[thenNode]
        elseNode := -1
        if st[0] < count && tokenKinds[st[0]] == 24 {
            st[0] = st[0] + 1
            elseNode = ParseStatementCoreNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
            if elseNode < 0 {
                return -1
            }

            endSpan = outSpanStarts[elseNode] + outSpanLengths[elseNode]
        }

        childRunStart := st[2]
        AppendExpressionChild(st, outChildIndices, condition)
        AppendExpressionChild(st, outChildIndices, thenNode)
        ifChildCount := 2
        if elseNode >= 0 {
            AppendExpressionChild(st, outChildIndices, elseNode)
            ifChildCount = 3
        }

        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 27, -1, 0, childRunStart, ifChildCount, ifStart, endSpan - ifStart)
    }

    return ParseSimpleStatementNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths)
}

// The non-control-flow statements: return / break / continue / `:=` declaration / expression statement.
func ParseSimpleStatementNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[]): int {
    start := st[0]
    kind := tokenKinds[start]

    if kind == 29 {
        returnStart := tokenStarts[start]
        returnEnd := tokenStarts[start] + tokenValueLengths[start]
        st[0] = start + 1

        if st[0] < count && tokenKinds[st[0]] != 130 && tokenKinds[st[0]] != 135 && tokenKinds[st[0]] != 136 {
            valueRoot := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
            if valueRoot < 0 {
                return -1
            }

            valueEnd := outSpanStarts[valueRoot] + outSpanLengths[valueRoot]
            childRunStart := st[2]
            AppendExpressionChild(st, outChildIndices, valueRoot)
            return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 20, -1, 0, childRunStart, 1, returnStart, valueEnd - returnStart)
        }

        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 20, -1, 0, -1, 0, returnStart, returnEnd - returnStart)
    }

    if kind == 35 {
        st[0] = start + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 21, -1, 0, -1, 0, tokenStarts[start], tokenValueLengths[start])
    }

    if kind == 36 {
        st[0] = start + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 22, -1, 0, -1, 0, tokenStarts[start], tokenValueLengths[start])
    }

    if kind == 0 && start + 1 < count && tokenKinds[start + 1] == 121 {
        nameStart := tokenStarts[start]
        nameLength := tokenValueLengths[start]
        st[0] = start + 2
        initRoot := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if initRoot < 0 {
            return -1
        }

        initEnd := outSpanStarts[initRoot] + outSpanLengths[initRoot]
        childRunStart := st[2]
        AppendExpressionChild(st, outChildIndices, initRoot)
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 24, nameStart, nameLength, childRunStart, 1, nameStart, initEnd - nameStart)
    }

    exprRoot := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
    if exprRoot < 0 {
        return -1
    }

    exprStart := outSpanStarts[exprRoot]
    exprEnd := outSpanStarts[exprRoot] + outSpanLengths[exprRoot]
    childRunStart := st[2]
    AppendExpressionChild(st, outChildIndices, exprRoot)
    return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 23, -1, 0, childRunStart, 1, exprStart, exprEnd - exprStart)
}

func ParseStatementNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    st := new int[](6)
    st[0] = start
    st[1] = 0
    st[2] = 0
    st[3] = 0
    st[4] = 0
    st[5] = 0
    argStack := new int[](count + 1)

    root := ParseStatementCoreNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
    if root < 0 {
        return -1
    }

    outResult[0] = root
    outResult[1] = st[0]
    return st[1]
}
