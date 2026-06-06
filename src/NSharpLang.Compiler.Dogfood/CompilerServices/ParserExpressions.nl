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
//   CallExpression          -> kind 9   ( callee(args) -- slice 12; children [callee, arg0, arg1, ...] )
//   IndexAccessExpression   -> kind 10  ( obj[index] -- slice 11; children [object, index] )
//   UnaryExpression         -> kind 11  ( prefix !/-/~/++/--/^ -- slice 13; operator token in value span )
//   BinaryExpression        -> kind 12  ( left OP right -- slice 14; operator token in value span; the full
//                                         left-associative precedence chain ?? || && | ^ & ==/!= rel << >> +- */% )
// Deferred (refused with -1, or the chain simply STOPS at them): `?.`/`?[` null-conditional access, generic
//   method calls (callee<T>(...)), named (`name:`) and ref/out call arguments, postfix `++`/`--`, `with`,
//   `is`/`as` type tests, range `..`, assignment and ternary (the levels ABOVE this chain); every other
//   primary (this/base/default/new/alloc/match/tuple/array-literal/object-initializer/interpolated string/
//   lambda/cast/...). A tuple `(a, b)` or named element `(x: e)` is refused (the parenthesized branch
//   requires a lone `)` after the inner expression). Literal VALUE materialization (unescaping strings/
//   chars) is the host's job; this kernel records the value token's byte span only.
//
// Node-table columns (caller-allocated to capacity >= count+1; outChildIndices likewise):
//   outNodeKinds[i]    : 0..7 per the list above
//   outValueStarts[i]  : byte offset of the literal/identifier value token; -1 for Null/Parenthesized
//   outValueLengths[i] : value byte length; 0 when none
//   outChildStart[i]   : index into outChildIndices for children; -1 when none
//   outChildCount[i]   : Parenthesized/MemberAccess = 1; IndexAccess = 2; Call = 1 + #args; others = 0
//   outChildIndices[]  : flattened child node-id edges (post-order; root is the last node)
//   outSpanStarts[i] / outSpanLengths[i] : full source byte span of the node
//   outResult[0] = root node id (== nodeCount-1), outResult[1] = token index past the consumed expression
// Returns the node count, or -1 on refusal / depth > 200.
//
// State array `st`: st[0]=pos, st[1]=nodeCursor, st[2]=childCursor, st[3]=argStackTop. Calls gather the
// callee + argument node ids on the caller-owned LIFO `argStack` (recursion is LIFO) and append the
// contiguous child run after the closing `)`, exactly as the type kernel does for generic arguments.
//
// For MemberAccess/IndexAccess the value name span (member) or the two children (object, index) are appended
// directly after the object and index are fully parsed -- both are fixed-arity, so their child runs are
// contiguous without the arg-stack.
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
func ParsePrimaryExpressionNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
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
        inner := ParseBinaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 1, depth + 1)
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
func ParsePostfixExpressionNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    expr := ParsePrimaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth)
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
            index := ParseBinaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 1, depth + 1)
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
        } else if pos < count && tokenKinds[pos] == 127 {
            // Call `callee(args)`: children = [callee, arg0, arg1, ...]. Like generic type arguments, the
            // callee + arg node ids are gathered on the LIFO arg-stack (each arg is a full expression that
            // appends its own descendants) and the contiguous child run is appended only after the closing
            // `)`. Named (`name:`) and ref/out arguments are deferred -> refuse.
            objSpanStart := outSpanStarts[expr]
            st[0] = pos + 1
            argBase := st[3]
            argStack[st[3]] = expr
            st[3] = st[3] + 1

            if st[0] < count && tokenKinds[st[0]] != 128 {
                if tokenKinds[st[0]] == 78 || tokenKinds[st[0]] == 79 {
                    st[3] = argBase
                    return -1
                }

                firstArg := ParseBinaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 1, depth + 1)
                if firstArg < 0 {
                    st[3] = argBase
                    return -1
                }

                argStack[st[3]] = firstArg
                st[3] = st[3] + 1

                while st[0] < count && tokenKinds[st[0]] == 134 {
                    st[0] = st[0] + 1
                    if st[0] < count && (tokenKinds[st[0]] == 78 || tokenKinds[st[0]] == 79) {
                        st[3] = argBase
                        return -1
                    }

                    nextArg := ParseBinaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 1, depth + 1)
                    if nextArg < 0 {
                        st[3] = argBase
                        return -1
                    }

                    argStack[st[3]] = nextArg
                    st[3] = st[3] + 1
                }
            }

            if st[0] >= count || tokenKinds[st[0]] != 128 {
                st[3] = argBase
                return -1
            }

            rightParenEnd := tokenStarts[st[0]] + tokenValueLengths[st[0]]
            st[0] = st[0] + 1
            childCount := st[3] - argBase
            childRunStart := st[2]
            a := argBase
            while a < st[3] {
                AppendExpressionChild(st, outChildIndices, argStack[a])
                a = a + 1
            }
            st[3] = argBase
            expr = EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 9, -1, 0, childRunStart, childCount, objSpanStart, rightParenEnd - objSpanStart)
        } else {
            matched = false
        }
    }

    return expr
}

// ParseUnaryExpression (Parser.cs:4223) restricted to the prefix operators: ! (Not 106), - (Negate, Minus
// 89), ~ (BitwiseNot 110), ++ (PreIncrement 113), -- (PreDecrement 114), ^ (IndexFromEnd, BitwiseXor 109).
// A prefix operator wraps a (recursively-parsed) unary operand -> UnaryExpression (kind 11, operator token
// in the value span); otherwise the operand is a postfix expression. (Prefix `+` is invalid in N# and is
// refused via the postfix/primary fall-through. Postfix ++/-- and `must` are deferred.)
func ParseUnaryExpressionNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    if depth > 200 {
        return -1
    }

    pos := st[0]
    if pos < count {
        k := tokenKinds[pos]
        if k == 106 || k == 89 || k == 110 || k == 113 || k == 114 || k == 109 {
            opStart := tokenStarts[pos]
            opLength := tokenValueLengths[pos]
            st[0] = pos + 1
            operand := ParseUnaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
            if operand < 0 {
                return -1
            }

            operandSpanEnd := outSpanStarts[operand] + outSpanLengths[operand]
            childRunStart := st[2]
            AppendExpressionChild(st, outChildIndices, operand)
            return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 11, opStart, opLength, childRunStart, 1, opStart, operandSpanEnd - opStart)
        }
    }

    return ParsePostfixExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth)
}

// Precedence level (higher binds tighter) for a left-associative binary operator token, or 0 if the token
// is not a binary operator. Mirrors the C# precedence chain (Parser.cs:3940-4185), low->high:
// ?? (NullCoalesce) < || < && < | < ^ < & < ==,!= < <,<=,>,>= < <<,>> < +,- < *,/,%.
// `is`/`as` (type tests), range `..`, and assignment are intentionally NOT binary operators here (deferred).
func BinaryOpPrecedence(kind: int): int {
    if kind == 116 {
        return 1
    }
    if kind == 105 {
        return 2
    }
    if kind == 104 {
        return 3
    }
    if kind == 108 {
        return 4
    }
    if kind == 109 {
        return 5
    }
    if kind == 107 {
        return 6
    }
    if kind == 98 || kind == 99 {
        return 7
    }
    if kind == 100 || kind == 101 || kind == 102 || kind == 103 {
        return 8
    }
    if kind == 111 || kind == 112 {
        return 9
    }
    if kind == 88 || kind == 89 {
        return 10
    }
    if kind == 90 || kind == 91 || kind == 92 {
        return 11
    }
    return 0
}

// ParseBinaryExpression: precedence climbing over the C# binary chain (Parser.cs:3940-4185). Parses a unary
// operand, then while the next token is a binary operator whose precedence >= minPrec, consumes it and
// parses the right operand at (precedence + 1) -- the left-associative formulation, producing the same
// left-leaning BinaryExpression trees as the C# while-loop levels. Each BinaryExpression (kind 12) records
// the operator token in the value span and has children [left, right] (fixed arity -> contiguous, no
// arg-stack). `minPrec == 1` is the full-expression entry.
func ParseBinaryExpressionNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], minPrec: int, depth: int): int {
    if depth > 200 {
        return -1
    }

    left := ParseUnaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth)
    if left < 0 {
        return -1
    }

    keepGoing := true
    while keepGoing {
        opKind := -1
        if st[0] < count {
            opKind = tokenKinds[st[0]]
        }

        prec := BinaryOpPrecedence(opKind)
        if prec == 0 || prec < minPrec {
            keepGoing = false
        } else {
            opStart := tokenStarts[st[0]]
            opLength := tokenValueLengths[st[0]]
            st[0] = st[0] + 1
            right := ParseBinaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, prec + 1, depth + 1)
            if right < 0 {
                return -1
            }

            leftSpanStart := outSpanStarts[left]
            rightSpanEnd := outSpanStarts[right] + outSpanLengths[right]
            childRunStart := st[2]
            AppendExpressionChild(st, outChildIndices, left)
            AppendExpressionChild(st, outChildIndices, right)
            left = EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 12, opStart, opLength, childRunStart, 2, leftSpanStart, rightSpanEnd - leftSpanStart)
        }
    }

    return left
}

func ParseExpressionNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    st := new int[](4)
    st[0] = start
    st[1] = 0
    st[2] = 0
    st[3] = 0
    argStack := new int[](count + 1)

    root := ParseBinaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 1, 0)
    if root < 0 {
        return -1
    }

    outResult[0] = root
    outResult[1] = st[0]
    return st[1]
}
