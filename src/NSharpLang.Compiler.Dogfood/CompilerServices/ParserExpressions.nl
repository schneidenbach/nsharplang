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
//   TernaryExpression       -> kind 13  ( cond ? then : else -- slice 15; children [cond, then, else] )
//   AssignmentExpression    -> kind 14  ( target OP value -- slice 15; = += -= *= /= ??=; right-associative )
//   NewExpression           -> kind 15  ( new <type> ( args ) -- slice 19; children [typeRoot, arg0, ...];
//                                         the type child is a TYPE-kernel subtree (kinds 0-5), args are
//                                         expression subtrees -- the host walks child[0] as a type and the
//                                         rest as expressions. Composes the type kernel via the unified st. )
//   CastExpression          -> kind 16  ( ( <type> ) operand -- hard cast; children [typeRoot, operand];
//                                         operand is a unary expression. Detected by speculatively parsing a
//                                         type after `(` and requiring `) <expr-start>` (Parser.cs
//                                         IsCastExpression); otherwise the `(` is a parenthesized expression. )
//   TupleExpression         -> kind 17  ( ( e0, e1, ... ) -- a `,` after the first parenthesised expression;
//                                         children = the element expressions (variable arity). Positional only. )
//   MatchExpression         -> kind 18  ( match <value> { <pat> => <res>, ... }; children [value, pat0, res0, ...].
//                                         Each pattern is a PRIMARY expr (literal or bare identifier). `=>` = 120. )
//   GuardedPattern          -> kind 19  ( <pattern> when <guard> -- a `when` (token 54) after a match pattern;
//                                         children [pattern, guard]. Appears ONLY as a match-case pattern slot.
//                                         The emitter tests the inner pattern, then the guard, before the result. )
// Deferred (refused with -1, or the chain simply STOPS at them): `?.`/`?[` null-conditional access, generic
//   method calls (callee<T>(...)), named (`name:`) and ref/out call arguments, postfix `++`/`--`, `with`,
//   `is`/`as` type tests, range `..`, lambdas (the level above assignment); every other primary (this/base/
//   default/new/alloc/match/tuple/array-literal/object-initializer/interpolated string/...). A tuple
//   `(a, b)` or named element `(x: e)` is refused (the parenthesized branch requires a lone `)` after the
//   inner expression). Literal VALUE materialization (unescaping strings/chars) is the host's job; this
//   kernel records the value token's byte span only.
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

// Mirrors Parser.cs IsExpressionStart: the set of token kinds that can begin an expression. Used by the cast
// detection in ParsePrimaryExpressionNode to disambiguate `( <type> ) <expr>` (a hard cast) from a
// parenthesized expression -- the C# parser only treats `(...)` as a cast when an expression-start token
// follows the `)`. Kinds (TokenType ordinals, see Token.cs): Identifier 0, IntLiteral 1, FloatLiteral 2,
// CharLiteral 3, StringLiteral 4, TripleQuoteStringLiteral 5, InterpolatedRawStringLiteral 6, Must 20,
// Match 31, Default 34, Throw 37, New 41, This 42, Base 43, True 44, False 45, Null 46, Typeof 49, Nameof 50,
// Sizeof 51, Await 69, Immutable 70, Checked 83, Unchecked 84, Plus 88, Minus 89, Not 106, BitwiseNot 110,
// Increment 113, Decrement 114, LeftParen 127, LeftBracket 131, Alloc 143, Stackalloc 145.
func IsExpressionStartKind(kind: int): bool {
    if kind >= 0 && kind <= 6 {
        return true
    }
    return kind == 20 || kind == 31 || kind == 34 || kind == 37 || kind == 41 || kind == 42 || kind == 43 || kind == 44 || kind == 45 || kind == 46 || kind == 49 || kind == 50 || kind == 51 || kind == 69 || kind == 70 || kind == 83 || kind == 84 || kind == 88 || kind == 89 || kind == 106 || kind == 110 || kind == 113 || kind == 114 || kind == 127 || kind == 131 || kind == 143 || kind == 145
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
    if kind == 31 {
        // `match <value> { <pattern> => <result>, ... }` (Match token 31, Arrow `=>` token 120). MatchExpression
        // kind 18: children = [value, pat0, res0, pat1, res1, ...] (one value, then each case as a pattern/result
        // pair). The pattern is a PRIMARY expression (a literal or a bare identifier `_`/binding); the emitter
        // gates which pattern kinds it supports (richer patterns -- union-case/property/relational/`when` guards --
        // are parsed-or-refused here and decline at emit). A comma between cases is consumed when present.
        matchStart := tokenStart
        st[0] = pos + 1
        matchArgBase := st[3]

        matchValue := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if matchValue < 0 {
            st[3] = matchArgBase
            return -1
        }
        argStack[st[3]] = matchValue
        st[3] = st[3] + 1

        if st[0] >= count || tokenKinds[st[0]] != 129 {
            st[3] = matchArgBase
            return -1
        }
        st[0] = st[0] + 1

        matchCaseCount := 0
        while st[0] < count && tokenKinds[st[0]] != 130 {
            matchPattern := ParsePrimaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
            if matchPattern < 0 {
                st[3] = matchArgBase
                return -1
            }

            // `<pattern> when <guard>` -> GuardedPattern (kind 19): wrap the parsed pattern with its guard
            // condition so the emitter can test the pattern THEN the guard before taking the arm. The guard is a
            // full expression (it may reference a binding the pattern introduced). When absent, the bare pattern
            // node is used directly (no kind-19 wrapper), so existing match cases are unchanged.
            if st[0] < count && tokenKinds[st[0]] == 54 {
                st[0] = st[0] + 1
                matchGuard := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
                if matchGuard < 0 {
                    st[3] = matchArgBase
                    return -1
                }
                guardChildRun := st[2]
                AppendExpressionChild(st, outChildIndices, matchPattern)
                AppendExpressionChild(st, outChildIndices, matchGuard)
                guardSpanStart := outSpanStarts[matchPattern]
                guardSpanEnd := outSpanStarts[matchGuard] + outSpanLengths[matchGuard]
                matchPattern = EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 19, -1, 0, guardChildRun, 2, guardSpanStart, guardSpanEnd - guardSpanStart)
            }

            argStack[st[3]] = matchPattern
            st[3] = st[3] + 1

            if st[0] >= count || tokenKinds[st[0]] != 120 {
                st[3] = matchArgBase
                return -1
            }
            st[0] = st[0] + 1

            matchResult := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
            if matchResult < 0 {
                st[3] = matchArgBase
                return -1
            }
            argStack[st[3]] = matchResult
            st[3] = st[3] + 1
            matchCaseCount = matchCaseCount + 1

            if st[0] < count && tokenKinds[st[0]] == 134 {
                st[0] = st[0] + 1
            }
        }

        if matchCaseCount == 0 || st[0] >= count || tokenKinds[st[0]] != 130 {
            st[3] = matchArgBase
            return -1
        }
        matchEnd := tokenStarts[st[0]] + tokenValueLengths[st[0]]
        st[0] = st[0] + 1

        matchChildCount := st[3] - matchArgBase
        matchChildRunStart := st[2]
        matchArg := matchArgBase
        while matchArg < st[3] {
            AppendExpressionChild(st, outChildIndices, argStack[matchArg])
            matchArg = matchArg + 1
        }
        st[3] = matchArgBase

        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 18, -1, 0, matchChildRunStart, matchChildCount, matchStart, matchEnd - matchStart)
    }
    if kind == 41 {
        // `new <type> ( args )` -- the array/object construction form the dogfood kernels use
        // (e.g. new int[](length + 1)). COMPOSES the type kernel (the element/constructed type, via the
        // now-unified shared st + argStack) with the expression kernel (the positional constructor args).
        // NewExpression (kind 15): children = [typeRoot, arg0, arg1, ...]. The `new <type> [size]` (sized
        // array) and `new <type> { init }` (object initializer) and target-typed `new ( ... )` forms are
        // deferred (refused). Named / ref / out constructor arguments are also refused.
        newStart := tokenStart
        st[0] = pos + 1
        // The type kernel assumes splitGreaterDepth (st[4]) is 0 on entry (it is only set/cleared while
        // closing generics within a single type parse). A balanced type always leaves it 0, but reset it
        // explicitly before the call -- matching the function-signature kernel -- so the invariant never
        // relies on the caller's prior state. (st[3]=argStackTop must NOT be reset here: the type's generic
        // args nest on the shared LIFO arg-stack above the enclosing expression's current base.)
        st[4] = 0
        typeRoot := ParseUnionTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if typeRoot < 0 {
            return -1
        }

        if st[0] >= count || tokenKinds[st[0]] != 127 {
            return -1
        }
        st[0] = st[0] + 1

        argBase := st[3]
        argStack[st[3]] = typeRoot
        st[3] = st[3] + 1

        if st[0] < count && tokenKinds[st[0]] != 128 {
            if tokenKinds[st[0]] == 78 || tokenKinds[st[0]] == 79 {
                st[3] = argBase
                return -1
            }

            firstArg := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
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

                nextArg := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
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

        newRightParenEnd := tokenStarts[st[0]] + tokenValueLengths[st[0]]
        st[0] = st[0] + 1
        newChildCount := st[3] - argBase
        newChildRunStart := st[2]
        na := argBase
        while na < st[3] {
            AppendExpressionChild(st, outChildIndices, argStack[na])
            na = na + 1
        }
        st[3] = argBase
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 15, -1, 0, newChildRunStart, newChildCount, newStart, newRightParenEnd - newStart)
    }

    if kind == 127 {
        parenStart := tokenStart

        // Cast expression (Parser.cs ParsePrimaryExpression + IsCastExpression): `( <type> ) <operand>`,
        // where an expression-start token follows the `)`, is a hard cast. SPECULATIVELY parse a type from
        // after the `(`; if it is followed by `)` and an expression-start, emit a CastExpression (kind 16):
        // children = [typeRoot, operand], operand parsed as a unary expression (matching C#). Otherwise roll
        // back the speculatively-emitted type nodes / child run / arg-stack and parse as a parenthesized
        // expression. The type kernel refuses type forms it does not support, which rolls back to the paren
        // path (and typically refuses there too) -- never a silently-wrong tree.
        castSaveNode := st[1]
        castSaveChild := st[2]
        castSaveArg := st[3]
        st[0] = pos + 1
        st[4] = 0
        castType := ParseUnionTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        isCast := false
        if castType >= 0 && st[0] < count && tokenKinds[st[0]] == 128 {
            if st[0] + 1 < count && IsExpressionStartKind(tokenKinds[st[0] + 1]) {
                isCast = true
            }
        }

        if isCast {
            st[0] = st[0] + 1
            operand := ParseUnaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
            if operand < 0 {
                return -1
            }

            castSpanEnd := outSpanStarts[operand] + outSpanLengths[operand]
            castChildRun := st[2]
            AppendExpressionChild(st, outChildIndices, castType)
            AppendExpressionChild(st, outChildIndices, operand)
            return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 16, -1, 0, castChildRun, 2, parenStart, castSpanEnd - parenStart)
        }

        st[1] = castSaveNode
        st[2] = castSaveChild
        st[3] = castSaveArg
        st[4] = 0
        st[0] = pos + 1
        inner := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if inner < 0 {
            return -1
        }

        // A `,` after the first parenthesised expression makes this a TUPLE `( e0, e1, ... )` (TupleExpression
        // kind 17), not a parenthesised expression. Collect the comma-separated elements on the LIFO arg-stack
        // (variable arity, exactly like a block/call), then append the contiguous child run after `)`.
        if st[0] < count && tokenKinds[st[0]] == 134 {
            tupleArgBase := st[3]
            argStack[st[3]] = inner
            st[3] = st[3] + 1
            while st[0] < count && tokenKinds[st[0]] == 134 {
                st[0] = st[0] + 1
                tupleElem := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
                if tupleElem < 0 {
                    st[3] = tupleArgBase
                    return -1
                }

                argStack[st[3]] = tupleElem
                st[3] = st[3] + 1
            }

            if st[0] >= count || tokenKinds[st[0]] != 128 {
                st[3] = tupleArgBase
                return -1
            }

            tupleRightParenEnd := tokenStarts[st[0]] + tokenValueLengths[st[0]]
            st[0] = st[0] + 1
            tupleChildCount := st[3] - tupleArgBase
            tupleChildRunStart := st[2]
            tupleArg := tupleArgBase
            while tupleArg < st[3] {
                AppendExpressionChild(st, outChildIndices, argStack[tupleArg])
                tupleArg = tupleArg + 1
            }
            st[3] = tupleArgBase
            return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 17, -1, 0, tupleChildRunStart, tupleChildCount, parenStart, tupleRightParenEnd - parenStart)
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
            index := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
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

                firstArg := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
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

                    nextArg := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
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

// ParseTernaryExpression (Parser.cs:3916): a binary-chain condition, optionally followed by `? then : else`
// (TernaryExpression, kind 13, children [condition, then, else]). The then/else branches are full
// expressions (assignment level), making the ternary right-associative in the else branch.
func ParseTernaryExpressionNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    condition := ParseBinaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 1, depth)
    if condition < 0 {
        return -1
    }

    if st[0] < count && tokenKinds[st[0]] == 115 {
        conditionSpanStart := outSpanStarts[condition]
        st[0] = st[0] + 1
        thenNode := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if thenNode < 0 {
            return -1
        }

        if st[0] >= count || tokenKinds[st[0]] != 122 {
            return -1
        }
        st[0] = st[0] + 1

        elseNode := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if elseNode < 0 {
            return -1
        }

        elseSpanEnd := outSpanStarts[elseNode] + outSpanLengths[elseNode]
        childRunStart := st[2]
        AppendExpressionChild(st, outChildIndices, condition)
        AppendExpressionChild(st, outChildIndices, thenNode)
        AppendExpressionChild(st, outChildIndices, elseNode)
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 13, -1, 0, childRunStart, 3, conditionSpanStart, elseSpanEnd - conditionSpanStart)
    }

    return condition
}

// ParseAssignmentExpression (Parser.cs:3599): a ternary target, optionally followed by an assignment
// operator (= += -= *= /= ??=) and a right-hand value (AssignmentExpression, kind 14, operator token in the
// value span, children [target, value]). Right-associative: the value recurses to the assignment level, so
// a = b = c parses as a = (b = c). This is the full-expression entry (minus lambdas, deferred).
func ParseAssignmentExpressionNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    if depth > 200 {
        return -1
    }

    target := ParseTernaryExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth)
    if target < 0 {
        return -1
    }

    if st[0] < count {
        op := tokenKinds[st[0]]
        if op == 93 || op == 94 || op == 95 || op == 96 || op == 97 || op == 117 {
            opStart := tokenStarts[st[0]]
            opLength := tokenValueLengths[st[0]]
            st[0] = st[0] + 1
            value := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
            if value < 0 {
                return -1
            }

            targetSpanStart := outSpanStarts[target]
            valueSpanEnd := outSpanStarts[value] + outSpanLengths[value]
            childRunStart := st[2]
            AppendExpressionChild(st, outChildIndices, target)
            AppendExpressionChild(st, outChildIndices, value)
            return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 14, opStart, opLength, childRunStart, 2, targetSpanStart, valueSpanEnd - targetSpanStart)
        }
    }

    return target
}

func ParseExpressionNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    st := new int[](6)
    st[0] = start
    st[1] = 0
    st[2] = 0
    st[3] = 0
    st[4] = 0
    st[5] = 0
    argStack := new int[](count + 1)

    root := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
    if root < 0 {
        return -1
    }

    outResult[0] = root
    outResult[1] = st[0]
    return st[1]
}
