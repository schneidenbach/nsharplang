// Parser slice 10: the first EXPRESSION kernel -- the foundation of the largest parser subsystem (the
// ~17-level precedence chain in Parser.cs ParseExpression..ParsePrimaryExpression). This slice establishes
// the expression node table + the recursive structure with PRIMARY expressions only; later slices layer on
// postfix (call/index/member), unary, and the binary-operator precedence chain.
//
// Supported this slice (matching the concrete C# Expression nodes from ParsePrimaryExpression):
//   IntLiteralExpression    -> kind 0   (IntLiteral token 1)
//   FloatLiteralExpression  -> kind 1   (FloatLiteral token 2)
//   CharLiteralExpression   -> kind 2   (CharLiteral token 3)
//   StringLiteralExpression -> kind 3   (StringLiteral token 4)
//   BoolLiteralExpression   -> kind 4   (True 44 / False 45)
//   NullLiteralExpression   -> kind 5   (Null 46)
//   IdentifierExpression    -> kind 6   (Identifier 0)
//   ParenthesizedExpression -> kind 7   ( ( expr ) -- a single non-tuple parenthesized expression )
//   MemberAccessExpression  -> kind 8   ( obj.member -- slice 11; member name in the value span )
//   IndexAccessExpression   -> kind 10  ( obj[index] -- slice 11; children [object, index] )
// Deferred (refused with -1): CallExpression (kind 9, reserved -- needs the variable-arity arg-stack, a
//   later slice), `?.`/`?[` null-conditional access, generic method calls, `++`/`--`, `with`; every other
//   primary (this/base/default/new/alloc/match/tuple/array-literal/object-initializer/interpolated string/
//   lambda/cast/...); and all unary/binary structure. A tuple `(a, b)` or named element `(x: e)` is refused
//   (the parenthesized branch requires a lone `)` after the inner expression). Literal VALUE materialization
//   (unescaping strings/chars) is the host's job; this kernel records the value token's byte span only.
//
// Node-table columns (caller-allocated to capacity >= count+1; outChildIndices likewise):
//   outNodeKinds[i]    : 0..7 per the list above
//   outValueStarts[i]  : byte offset of the literal/identifier value token; -1 for Null/Parenthesized
//   outValueLengths[i] : value byte length; 0 when none
//   outChildStart[i]   : index into outChildIndices for children; -1 when none
//   outChildCount[i]   : Parenthesized/MemberAccess = 1; IndexAccess = 2; others = 0 (until later slices)
//   outChildIndices[]  : flattened child node-id edges (post-order; root is the last node)
//   outSpanStarts[i] / outSpanLengths[i] : full source byte span of the node
//   outResult[0] = root node id (== nodeCount-1), outResult[1] = token index past the consumed expression
// Returns the node count, or -1 on refusal / depth > 200.
//
// State array `st`: st[0]=pos, st[1]=nodeCursor, st[2]=childCursor.
//
// For MemberAccess/IndexAccess the value name span (member) or the two children (object, index) are appended
// directly after the object and index are fully parsed -- both are fixed-arity, so their child runs are
// contiguous without an arg-stack (unlike the variable-arity CallExpression deferred to a later slice).
//
// TokenType ordinals (Token.cs): Identifier 0, IntLiteral 1, FloatLiteral 2, CharLiteral 3, StringLiteral 4,
// True 44, False 45, Null 46, LeftParen 127, RightParen 128, Dot 124, LeftBracket 131, RightBracket 132.

func EmitExpressionNode(st: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outSpanStarts: int[], outSpanLengths: int[], kind: int, valueStart: int, valueLength: int, childStart: int, childCount: int, spanStart: int, spanLength: int): int {
    id := st[1]
    outNodeKinds[id] = kind
    outValueStarts[id] = valueStart
    outValueLengths[id] = valueLength
    outChildStart[id] = childStart
    outChildCount[id] = childCount
    outSpanStarts[id] = spanStart
    outSpanLengths[id] = spanLength
    st[1] = id + 1
    return id
}

func AppendExpressionChild(st: int[], outChildIndices: int[], childId: int): int {
    slot := st[2]
    outChildIndices[slot] = childId
    st[2] = slot + 1
    return slot
}

// ParsePrimaryExpression (Parser.cs:4525) restricted to literals, identifiers, and ( expr ). Returns the
// emitted node id, or -1 on refusal/failure. Advances st[0] past the consumed tokens.
func ParsePrimaryExpressionNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    if depth > 200 {
        return -1
    }

    pos := st[0]
    if pos >= count {
        return -1
    }

    kind := tokenKinds[pos]
    tokenStart := tokenStarts[pos]
    tokenLength := tokenValueLengths[pos]

    if kind == 1 {
        st[0] = pos + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 0, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 2 {
        st[0] = pos + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 1, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 3 {
        st[0] = pos + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 2, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 4 {
        st[0] = pos + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 3, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 44 || kind == 45 {
        st[0] = pos + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 4, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 46 {
        st[0] = pos + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 5, -1, 0, -1, 0, tokenStart, tokenLength)
    }
    if kind == 0 {
        st[0] = pos + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 6, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 127 {
        parenStart := tokenStart
        st[0] = pos + 1
        inner := ParsePostfixExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if inner < 0 {
            return -1
        }

        if st[0] >= count || tokenKinds[st[0]] != 128 {
            return -1
        }

        rightParenEnd := tokenStarts[st[0]] + tokenValueLengths[st[0]]
        st[0] = st[0] + 1
        childRunStart := st[2]
        AppendExpressionChild(st, outChildIndices, inner)
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 7, -1, 0, childRunStart, 1, parenStart, rightParenEnd - parenStart)
    }

    return -1
}

// ParsePostfixExpression (Parser.cs:4312) restricted to member access (.name) and index access ([expr]).
// A primary expression followed by any run of `.member` and `[index]` suffixes. The member name and the
// two index children are appended right after the object/index are fully parsed (fixed arity => contiguous
// child runs, no arg-stack). Index expressions recurse to this postfix level (the current expression top).
func ParsePostfixExpressionNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    expr := ParsePrimaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth)
    if expr < 0 {
        return -1
    }

    matched := true
    while matched {
        pos := st[0]

        if pos + 1 < count && tokenKinds[pos] == 124 && tokenKinds[pos + 1] == 0 {
            objSpanStart := outSpanStarts[expr]
            memberStart := tokenStarts[pos + 1]
            memberLength := tokenValueLengths[pos + 1]
            memberEnd := memberStart + memberLength
            childRunStart := st[2]
            AppendExpressionChild(st, outChildIndices, expr)
            expr = EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 8, memberStart, memberLength, childRunStart, 1, objSpanStart, memberEnd - objSpanStart)
            st[0] = pos + 2
        } else if pos < count && tokenKinds[pos] == 131 {
            objSpanStart := outSpanStarts[expr]
            st[0] = pos + 1
            index := ParsePostfixExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
            if index < 0 {
                return -1
            }

            if st[0] >= count || tokenKinds[st[0]] != 132 {
                return -1
            }

            rightBracketEnd := tokenStarts[st[0]] + tokenValueLengths[st[0]]
            st[0] = st[0] + 1
            childRunStart := st[2]
            AppendExpressionChild(st, outChildIndices, expr)
            AppendExpressionChild(st, outChildIndices, index)
            expr = EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 10, -1, 0, childRunStart, 2, objSpanStart, rightBracketEnd - objSpanStart)
        } else {
            matched = false
        }
    }

    return expr
}

func ParseExpressionNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    st := new int[](3)
    st[0] = start
    st[1] = 0
    st[2] = 0

    root := ParsePostfixExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
    if root < 0 {
        return -1
    }

    outResult[0] = root
    outResult[1] = st[0]
    return st[1]
}
