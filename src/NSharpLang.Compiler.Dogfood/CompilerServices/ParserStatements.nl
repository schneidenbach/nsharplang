// Parser slice 16: the first STATEMENT kernel -- the start of the last major parser subsystem (function
// bodies), the critical path for parsing the dogfood compiler kernels themselves (flat top-level functions
// whose bodies are statements). ParseStatementNodesInto parses ONE statement at a token index, dispatching
// like the C# ParseStatement (Parser.cs:2165), and COMPOSES the slice 10-15 expression kernel: statements
// and expressions share ONE columnar node table (the expression table), with the shared expression
// parser-state array `st` and `argStack`. Statement nodes use kinds 20+ so they never collide with the
// expression kinds 0-14.
//
// Supported this slice (matching the concrete C# Statement nodes):
//   ReturnStatement              -> kind 20  ( return [value]; 0 or 1 child = the value expression )
//   BreakStatement               -> kind 21  ( break; 0 children )
//   ContinueStatement            -> kind 22  ( continue; 0 children )
//   ExpressionStatement          -> kind 23  ( <expr>; 1 child = the expression, incl. assignment exprs )
//   VariableDeclarationStatement -> kind 24  ( name := init; name in the value span, 1 child = initializer )
// The `:=` (ColonAssign 121) shorthand after a BARE identifier is the variable declaration (Kind=Let,
// Type=null); `=` (Assign 93) is an assignment EXPRESSION wrapped in an ExpressionStatement.
// Deferred to later slices: control flow (if/else, while, for, foreach) and their nested blocks; let/const/
// readonly typed declarations; the typed shorthand `name: Type = init`; tuple deconstruction; throw/try/
// using/lock/switch/yield/print/assert/local-functions; and statement initializers that use a not-yet-
// supported expression form (e.g. `new`/`alloc`). The block kernel (parsing a `{ ... }` sequence) is the
// next slice; this slice parses a single statement at a known start, verified standalone.
//
// Node-table columns are the EXPRESSION table (see ParserExpressions.nl): outNodeKinds/outValueStarts/
// outValueLengths/outChildStart/outChildCount/outChildIndices/outSpanStarts/outSpanLengths.
//   outResult[0] = root statement node id (== nodeCount-1), outResult[1] = token index past the statement.
// Returns the node count, or -1 on refusal / a malformed statement / an unsupported expression part.
//
// TokenType ordinals (Token.cs): Identifier 0, Return 29, Break 35, Continue 36, ColonAssign 121,
// RightBrace 130, Eof 135, Newline 136.

func ParseStatementNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    st := new int[](4)
    st[0] = start
    st[1] = 0
    st[2] = 0
    st[3] = 0
    argStack := new int[](count + 1)

    if start >= count {
        return -1
    }

    kind := tokenKinds[start]

    if kind == 29 {
        returnStart := tokenStarts[start]
        returnEnd := tokenStarts[start] + tokenValueLengths[start]
        st[0] = start + 1

        // A return value is present unless the next token ends the statement/block.
        if st[0] < count && tokenKinds[st[0]] != 130 && tokenKinds[st[0]] != 135 && tokenKinds[st[0]] != 136 {
            valueRoot := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
            if valueRoot < 0 {
                return -1
            }

            valueEnd := outSpanStarts[valueRoot] + outSpanLengths[valueRoot]
            childRunStart := st[2]
            AppendExpressionChild(st, outChildIndices, valueRoot)
            root := EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 20, -1, 0, childRunStart, 1, returnStart, valueEnd - returnStart)
            outResult[0] = root
            outResult[1] = st[0]
            return st[1]
        }

        root := EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 20, -1, 0, -1, 0, returnStart, returnEnd - returnStart)
        outResult[0] = root
        outResult[1] = st[0]
        return st[1]
    }

    if kind == 35 {
        st[0] = start + 1
        root := EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 21, -1, 0, -1, 0, tokenStarts[start], tokenValueLengths[start])
        outResult[0] = root
        outResult[1] = st[0]
        return st[1]
    }

    if kind == 36 {
        st[0] = start + 1
        root := EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 22, -1, 0, -1, 0, tokenStarts[start], tokenValueLengths[start])
        outResult[0] = root
        outResult[1] = st[0]
        return st[1]
    }

    // Shorthand variable declaration: bare identifier followed by `:=`.
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
        root := EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 24, nameStart, nameLength, childRunStart, 1, nameStart, initEnd - nameStart)
        outResult[0] = root
        outResult[1] = st[0]
        return st[1]
    }

    // Expression statement (includes assignment expressions like `x = e`, `arr[i] = e`).
    exprRoot := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
    if exprRoot < 0 {
        return -1
    }

    exprStart := outSpanStarts[exprRoot]
    exprEnd := outSpanStarts[exprRoot] + outSpanLengths[exprRoot]
    childRunStart := st[2]
    AppendExpressionChild(st, outChildIndices, exprRoot)
    root := EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 23, -1, 0, childRunStart, 1, exprStart, exprEnd - exprStart)
    outResult[0] = root
    outResult[1] = st[0]
    return st[1]
}
