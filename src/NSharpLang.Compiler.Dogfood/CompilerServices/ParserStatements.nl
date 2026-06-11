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
//   ForStatement                 -> kind 28  ( for <init>; <cond>; <incr> <body>; children [init, cond, incr, body] )
//   ForeachStatement             -> kind 29  ( foreach <var> in <coll> <body>; var in the value span, children [coll, body] )
//   TupleDeconstructionStatement -> kind 30  ( n0, n1, ... := <tuple>; children [name0..nameN-1 (Identifier kind 6), value] )
//   TypedLocalDeclaration        -> kind 40  ( [let] name: Type = init; the TYPE's source span in the VALUE slot
//                                             (type trees cannot share this table — kind spaces collide), children
//                                             [name Identifier (kind 6), init root]. Kinds 31-39 belong to the
//                                             expression/pattern kernel. )
//   LocalFunctionDeclaration     -> kind 41  ( `func name(...) ... { body }` as a STATEMENT. The kernel records
//                                             ONLY the `func` keyword's byte span (value slot, no children) and
//                                             SKIPS the whole declaration (first depth-0 `{`, balanced to its
//                                             close — the struct kernel's method-skip discipline); the host
//                                             re-locates the keyword by byte offset and parses the signature +
//                                             body through the existing kernels. 42 is the next free kind. )
// `:=` (ColonAssign 121) after a BARE identifier is the variable declaration (Kind=Let, Type=null); `=`
// (Assign 93) is an assignment EXPRESSION wrapped in an ExpressionStatement. Following the C# parser, an
// if/while body is ANY statement (commonly a `{ }` block, but a single statement is also valid), so the
// bodies recurse through the statement dispatcher; `else if` chains as a nested if.
//
// Deferred: parenthesised `foreach (x in y)`, let/const/readonly + typed `name: Type = init` declarations,
// throw/try/using/lock/switch/yield/print/assert/local-functions, and statements whose expression parts use
// a not-yet-supported form (e.g. `new`/`alloc`). Block statement-list gathers child node ids on the LIFO
// `argStack` (recursion is LIFO) and appends the contiguous child run after `}`, exactly as calls/generics do.
//
// Node-table columns are the EXPRESSION table (see ParserExpressions.nl).
//   outResult[0] = root statement node id (== nodeCount-1), outResult[1] = token index past the statement.
// Returns the node count, or -1 on refusal / a malformed statement / an unsupported expression part.
//
// TokenType ordinals (Token.cs): Identifier 0, If 23, Else 24, For 25, Foreach 26, While 27, In 28, Return 29,
// Break 35, Continue 36, Assign 93, ColonAssign 121, LeftBrace 129, RightBrace 130, Semicolon 133, Eof 135, Newline 136.

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

    if kind == 25 {
        forStart := tokenStarts[start]
        st[0] = start + 1

        // C-style `for <init>; <cond>; <incr> { body }`. init/incr are simple statements (a `:=` declaration or
        // an assignment expression statement); cond is an expression. All three clauses are required (an empty
        // clause makes a sub-parse refuse -> the whole statement declines to the C# parser). Children, in order:
        // [init, cond, incr, body] -> ForStatement kind 28.
        initNode := ParseSimpleStatementNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths)
        if initNode < 0 {
            return -1
        }

        if st[0] >= count || tokenKinds[st[0]] != 133 {
            return -1
        }
        st[0] = st[0] + 1

        forCondition := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if forCondition < 0 {
            return -1
        }

        if st[0] >= count || tokenKinds[st[0]] != 133 {
            return -1
        }
        st[0] = st[0] + 1

        increment := ParseSimpleStatementNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths)
        if increment < 0 {
            return -1
        }

        forBody := ParseStatementCoreNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if forBody < 0 {
            return -1
        }

        forBodyEnd := outSpanStarts[forBody] + outSpanLengths[forBody]
        forChildRunStart := st[2]
        AppendExpressionChild(st, outChildIndices, initNode)
        AppendExpressionChild(st, outChildIndices, forCondition)
        AppendExpressionChild(st, outChildIndices, increment)
        AppendExpressionChild(st, outChildIndices, forBody)
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 28, -1, 0, forChildRunStart, 4, forStart, forBodyEnd - forStart)
    }

    if kind == 26 {
        foreachStart := tokenStarts[start]
        st[0] = start + 1

        // `foreach <var> in <collection> { body }` (the no-paren, Go-style form). The loop variable name is an
        // identifier stored in the node's value span; children are [collection, body] -> ForeachStatement kind 29.
        // A parenthesised `foreach (x in y)` or a missing var/`in`/body refuses with -1 -> declines to the C# parser.
        if st[0] >= count || tokenKinds[st[0]] != 0 {
            return -1
        }
        foreachVarStart := tokenStarts[st[0]]
        foreachVarLength := tokenValueLengths[st[0]]
        st[0] = st[0] + 1

        if st[0] >= count || tokenKinds[st[0]] != 28 {
            return -1
        }
        st[0] = st[0] + 1

        collection := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if collection < 0 {
            return -1
        }

        foreachBody := ParseStatementCoreNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if foreachBody < 0 {
            return -1
        }

        foreachBodyEnd := outSpanStarts[foreachBody] + outSpanLengths[foreachBody]
        foreachChildRunStart := st[2]
        AppendExpressionChild(st, outChildIndices, collection)
        AppendExpressionChild(st, outChildIndices, foreachBody)
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 29, foreachVarStart, foreachVarLength, foreachChildRunStart, 2, foreachStart, foreachBodyEnd - foreachStart)
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

    // `throw <expr>` (Throw 37) -- ThrowStatement kind 48, ONE child [the exception expression].
    // A bare `throw` (rethrow, catch-only) is unmodeled (-1) until the catch rung lands. Throw
    // ALWAYS EXITS: both AlwaysReturns mirrors (the emitter's and ColumnarDiagnosticsPass's) treat
    // kind 48 like Return -- added in the SAME slice (the pass's faithfulness is by construction).
    if kind == 37 {
        throwStart := tokenStarts[start]
        st[0] = start + 1
        if st[0] >= count || tokenKinds[st[0]] == 130 || tokenKinds[st[0]] == 135 || tokenKinds[st[0]] == 136 {
            return -1
        }
        throwValue := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if throwValue < 0 {
            return -1
        }
        throwEnd := outSpanStarts[throwValue] + outSpanLengths[throwValue]
        throwChildRun := st[2]
        AppendExpressionChild(st, outChildIndices, throwValue)
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 48, -1, 0, throwChildRun, 1, throwStart, throwEnd - throwStart)
    }

    if kind == 35 {
        st[0] = start + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 21, -1, 0, -1, 0, tokenStarts[start], tokenValueLengths[start])
    }

    if kind == 36 {
        st[0] = start + 1
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 22, -1, 0, -1, 0, tokenStarts[start], tokenValueLengths[start])
    }

    // Tuple DECONSTRUCTION `n0, n1, ... := <tuple>` (>= 2 names): an identifier FOLLOWED BY a comma. Each target
    // is a bare identifier (or `_` discard) emitted as an Identifier node (kind 6); the value follows `:=`. The
    // node is TupleDeconstructionStatement kind 30, children = [name0, ..., nameN-1, value]. A malformed list
    // (a non-identifier target, a missing `:=` or value) refuses with -1 -> declines to the C# parser.
    if kind == 0 && start + 1 < count && tokenKinds[start + 1] == 134 {
        deconStart := tokenStarts[start]
        deconArgBase := st[3]

        firstName := EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 6, tokenStarts[start], tokenValueLengths[start], -1, 0, tokenStarts[start], tokenValueLengths[start])
        argStack[st[3]] = firstName
        st[3] = st[3] + 1
        st[0] = start + 1

        while st[0] < count && tokenKinds[st[0]] == 134 {
            st[0] = st[0] + 1
            if st[0] >= count || tokenKinds[st[0]] != 0 {
                st[3] = deconArgBase
                return -1
            }

            nextName := EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 6, tokenStarts[st[0]], tokenValueLengths[st[0]], -1, 0, tokenStarts[st[0]], tokenValueLengths[st[0]])
            argStack[st[3]] = nextName
            st[3] = st[3] + 1
            st[0] = st[0] + 1
        }

        if st[0] >= count || tokenKinds[st[0]] != 121 {
            st[3] = deconArgBase
            return -1
        }
        st[0] = st[0] + 1

        deconValue := ParseAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if deconValue < 0 {
            st[3] = deconArgBase
            return -1
        }

        argStack[st[3]] = deconValue
        st[3] = st[3] + 1
        deconValueEnd := outSpanStarts[deconValue] + outSpanLengths[deconValue]
        deconChildCount := st[3] - deconArgBase
        deconChildRunStart := st[2]
        deconIdx := deconArgBase
        while deconIdx < st[3] {
            AppendExpressionChild(st, outChildIndices, argStack[deconIdx])
            deconIdx = deconIdx + 1
        }
        st[3] = deconArgBase

        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 30, -1, 0, deconChildRunStart, deconChildCount, deconStart, deconValueEnd - deconStart)
    }

    // LOCAL FUNCTION declaration (kind 41): `func name(...) ... { body }` as a statement. Record the
    // `func` keyword's byte span and SKIP the declaration: scan to the first depth-0 `{` (the signature
    // contains no braces in modeled forms; a `{` inside a default value mis-anchors the skip and the
    // resulting parse fails downstream — a safe refusal), then balanced to its close.
    if kind == 7 {
        localFuncSpanStart := tokenStarts[start]
        localFuncSpanLength := tokenValueLengths[start]
        funcScan := start + 1
        while funcScan < count && tokenKinds[funcScan] != 129 {
            funcScan = funcScan + 1
        }
        if funcScan >= count {
            return -1
        }
        localFuncDepth := 1
        funcScan = funcScan + 1
        while funcScan < count && localFuncDepth > 0 {
            if tokenKinds[funcScan] == 129 {
                localFuncDepth = localFuncDepth + 1
            } else if tokenKinds[funcScan] == 130 {
                localFuncDepth = localFuncDepth - 1
            }
            funcScan = funcScan + 1
        }
        if localFuncDepth != 0 {
            return -1
        }
        st[0] = funcScan
        localFuncEnd := tokenStarts[funcScan - 1] + tokenValueLengths[funcScan - 1]
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 41, localFuncSpanStart, localFuncSpanLength, -1, 0, localFuncSpanStart, localFuncEnd - localFuncSpanStart)
    }

    // TYPED local declaration (kind 40): `let name: Type = init` (Let 19) or bare `name: Type = init`.
    // Type TREES cannot share the statement node table (the type kernel's kind space 0-6 collides with
    // expression kinds), so the TYPE rides as a SOURCE SPAN in the kind-40 node's VALUE slot — the host
    // canonicalizes the span text. The span is delimited STRUCTURALLY: balanced angles (`>>` 112 closes
    // two) and ()/[] groups, ending at the first depth-0 `=` (93). Children = [name Identifier (kind 6),
    // init root]; the initializer parses at the LAMBDA level (so `let f: Func<int, int> = x => x + 1`
    // carries a kind-39 initializer the emitter types from the DECLARED type). A typed declaration with
    // no initializer never finds a depth-0 `=` and refuses; `let name := init` is unmodeled (-1).
    isTypedLocal := false
    typedNameIndex := start
    if kind == 19 && start + 2 < count && tokenKinds[start + 1] == 0 && tokenKinds[start + 2] == 122 {
        isTypedLocal = true
        typedNameIndex = start + 1
    } else if kind == 0 && start + 1 < count && tokenKinds[start + 1] == 122 {
        isTypedLocal = true
    }
    if isTypedLocal {
        typedNameStart := tokenStarts[typedNameIndex]
        typedNameLength := tokenValueLengths[typedNameIndex]
        typeFirst := typedNameIndex + 2
        // The BARE form's type span must not start with `(` -- the production grammar REJECTS a bare
        // tuple-typed local (`t: (int, int) = ...` is a parse error; only `let t: (...)` parses --
        // probe-pinned; accepting it was a routed over-accept). The `let` form is unaffected.
        if kind == 0 && typeFirst < count && tokenKinds[typeFirst] == 127 {
            return -1
        }
        scanPos := typeFirst
        angleDepth := 0
        groupDepth := 0
        scanning := true
        while scanning {
            if scanPos >= count {
                return -1
            }
            k := tokenKinds[scanPos]
            if k == 93 && angleDepth == 0 && groupDepth == 0 {
                scanning = false
            } else {
                if k == 100 {
                    angleDepth = angleDepth + 1
                } else if k == 102 {
                    angleDepth = angleDepth - 1
                } else if k == 112 {
                    angleDepth = angleDepth - 2
                } else if k == 127 || k == 131 {
                    groupDepth = groupDepth + 1
                } else if k == 128 || k == 132 {
                    groupDepth = groupDepth - 1
                }
                if angleDepth < 0 || groupDepth < 0 {
                    return -1
                }
                scanPos = scanPos + 1
            }
        }
        if scanPos == typeFirst {
            return -1
        }
        typeSpanStart := tokenStarts[typeFirst]
        typeSpanEnd := tokenStarts[scanPos - 1] + tokenValueLengths[scanPos - 1]
        st[0] = scanPos + 1
        typedInit := ParseLambdaOrAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if typedInit < 0 {
            return -1
        }
        typedNameNode := EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 6, typedNameStart, typedNameLength, -1, 0, typedNameStart, typedNameLength)
        typedInitEnd := outSpanStarts[typedInit] + outSpanLengths[typedInit]
        typedChildRunStart := st[2]
        AppendExpressionChild(st, outChildIndices, typedNameNode)
        AppendExpressionChild(st, outChildIndices, typedInit)
        declStart := tokenStarts[start]
        return EmitExpressionNode(st, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 40, typeSpanStart, typeSpanEnd - typeSpanStart, typedChildRunStart, 2, declStart, typedInitEnd - declStart)
    }

    if kind == 0 && start + 1 < count && tokenKinds[start + 1] == 121 {
        nameStart := tokenStarts[start]
        nameLength := tokenValueLengths[start]
        st[0] = start + 2
        // The `:=` initializer parses at the LAMBDA level (the full-expression entry) so `zero := () => 99`
        // yields a Lambda (kind 39) initializer; all non-lambda shapes fall through to assignment unchanged.
        initRoot := ParseLambdaOrAssignmentExpressionNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
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
