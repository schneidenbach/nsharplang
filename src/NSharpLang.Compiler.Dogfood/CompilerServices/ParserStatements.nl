// Parser slices 16-17: the STATEMENT kernel -- function bodies, the critical path for parsing the dogfood
// kernels (flat top-level functions whose bodies are statements). ParseStatementNodesInto parses ONE
// statement at a token index by dispatching like the C# ParseStatement (Parser.cs:2165), and COMPOSES the
// slice 10-15 expression kernel: statements and expressions share ONE columnar node table (the expression
// table), with the shared expression `ParserState` (`st`) and `argStack`. Statement nodes use kinds 20+
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
//                                             body through the existing kernels. )
//   ThrowStatement               -> kind 48  ( throw <expr>; 1 child = the exception expression )
//   TryStatement                 -> kind 49  ( try/catch.../finally?; children [tryBlock, catch1..catchN,
//                                             finallyBlock? (a trailing kind-25 block)] )
//   CatchClause                  -> kind 50  ( one catch; value span = the exception TYPE name token, -1 for
//                                             a bare catch; children [nameIdent (kind 6)?, block] )
//   LockStatement                -> kind 51  ( lock <expr> { }; children [lockee, body]. Kind 52 is the
//                                             expression kernel's WithExpression, 53 its AwaitExpression;
//                                             54 is the next free kind. )
// `:=` (ColonAssign 121) after a BARE identifier is the variable declaration (Kind=Let, Type=null); `=`
// (Assign 93) is an assignment EXPRESSION wrapped in an ExpressionStatement. Following the C# parser, an
// if/while body is ANY statement (commonly a `{ }` block, but a single statement is also valid), so the
// bodies recurse through the statement dispatcher; `else if` chains as a nested if.
//
// Deferred: parenthesised `foreach (x in y)`, const/readonly declarations, using/switch/yield/
// print/assert, and statements whose expression parts use a not-yet-supported form (e.g. `alloc`). Block
// statement-list gathers child node ids on the LIFO `argStack` (recursion is LIFO) and appends the
// contiguous child run after `}`, exactly as calls/generics do.
//
// Node-table columns are the EXPRESSION table (see ParserExpressions.nl).
//   outResult[0] = root statement node id (== nodeCount-1), outResult[1] = token index past the statement.
// Returns the node count, or -1 on refusal / a malformed statement / an unsupported expression part.
//
// TokenType ordinals (Token.cs): Identifier 0, If 23, Else 24, For 25, Foreach 26, While 27, In 28, Return 29,
// Break 35, Continue 36, Assign 93, ColonAssign 121, LeftBrace 129, RightBrace 130, Semicolon 133, Eof 135, Newline 136.

func ParseBlockStatementNodeCore(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    argStackValues := argStack.Values
    blockStart := tokenStarts[st.Pos]
    st.Pos = st.Pos + 1
    argBase := st.ArgStackTop

    while st.Pos < count && tokenKinds[st.Pos] != 130 {
        stmt := ParseStatementCoreNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if stmt < 0 {
            st.ArgStackTop = argBase
            return -1
        }

        argStackValues[st.ArgStackTop] = stmt
        st.ArgStackTop = st.ArgStackTop + 1
    }

    if st.Pos >= count || tokenKinds[st.Pos] != 130 {
        st.ArgStackTop = argBase
        return -1
    }

    rightBraceEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
    st.Pos = st.Pos + 1
    childCount := st.ArgStackTop - argBase
    childRunStart := st.ChildCursor
    a := argBase
    while a < st.ArgStackTop {
        AppendExpressionChild(ref st, ref children, argStackValues[a])
        a = a + 1
    }
    st.ArgStackTop = argBase

    return EmitExpressionNode(ref st, ref nodes, 25, -1, 0, childRunStart, childCount, blockStart, rightBraceEnd - blockStart)
}

// Dispatch + parse a single statement at st.Pos. Returns the emitted statement node id, or -1.
func ParseStatementCoreNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    argStackValues := argStack.Values
    if depth > 200 {
        return -1
    }

    start := st.Pos
    if start >= count {
        return -1
    }

    kind := tokenKinds[start]

    if kind == 129 {
        return ParseBlockStatementNodeCore(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
    }

    // `try { } [catch ... { }]* [finally { }]` (Try 38 / Catch 39 / Finally 40) -- TryStatement kind 49,
    // children [tryBlock, catch1..catchN, finallyBlock?] (variable arity -> LIFO arg-stack, like blocks;
    // the finally is a trailing kind-25 BLOCK child, distinguishable from the kind-50 catches by kind).
    // Each catch is a kind-50 CatchClause node: value span = the exception TYPE name token (-1 for a bare
    // catch), children [nameIdent?, block] -- the bound variable as a 0-child kind-6 identifier, so the
    // name reads as a USE in every name scan (the linter treats catch variables as always used). All FOUR
    // production catch forms (Parser.cs:3016-3051): bare `catch {`, parenthesized `catch (e: T) {` /
    // `catch (T) {` / `catch (T e) {`, and paren-less `catch e: T {`. The TYPE must be a single Identifier
    // token (the emitter's BCL exception whitelist needs no more). Zero catches are valid WITH a finally
    // (`try {} finally {}`); a try with neither refuses. All bodies must be `{ }` BLOCKS.
    if kind == 38 {
        tryStart := tokenStarts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokenKinds[st.Pos] != 129 {
            return -1
        }
        tryBlock := ParseBlockStatementNodeCore(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if tryBlock < 0 {
            return -1
        }
        tryArgBase := st.ArgStackTop
        argStackValues[st.ArgStackTop] = tryBlock
        st.ArgStackTop = st.ArgStackTop + 1
        while st.Pos < count && tokenKinds[st.Pos] == 39 {
            catchStart := tokenStarts[st.Pos]
            st.Pos = st.Pos + 1
            typeStart := 0 - 1
            typeLen := 0
            nameStart := 0 - 1
            nameLen := 0
            if st.Pos < count && tokenKinds[st.Pos] == 127 {
                st.Pos = st.Pos + 1
                if st.Pos + 1 < count && tokenKinds[st.Pos] == 0 && tokenKinds[st.Pos + 1] == 122 {
                    nameStart = tokenStarts[st.Pos]
                    nameLen = tokenValueLengths[st.Pos]
                    st.Pos = st.Pos + 2
                    if st.Pos >= count || tokenKinds[st.Pos] != 0 {
                        st.ArgStackTop = tryArgBase
                        return -1
                    }
                    typeStart = tokenStarts[st.Pos]
                    typeLen = tokenValueLengths[st.Pos]
                    st.Pos = st.Pos + 1
                } else {
                    if st.Pos >= count || tokenKinds[st.Pos] != 0 {
                        st.ArgStackTop = tryArgBase
                        return -1
                    }
                    typeStart = tokenStarts[st.Pos]
                    typeLen = tokenValueLengths[st.Pos]
                    st.Pos = st.Pos + 1
                    if st.Pos < count && tokenKinds[st.Pos] == 0 {
                        nameStart = tokenStarts[st.Pos]
                        nameLen = tokenValueLengths[st.Pos]
                        st.Pos = st.Pos + 1
                    }
                }
                if st.Pos >= count || tokenKinds[st.Pos] != 128 {
                    st.ArgStackTop = tryArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
            } else if st.Pos + 1 < count && tokenKinds[st.Pos] == 0 && tokenKinds[st.Pos + 1] == 122 {
                nameStart = tokenStarts[st.Pos]
                nameLen = tokenValueLengths[st.Pos]
                st.Pos = st.Pos + 2
                if st.Pos >= count || tokenKinds[st.Pos] != 0 {
                    st.ArgStackTop = tryArgBase
                    return -1
                }
                typeStart = tokenStarts[st.Pos]
                typeLen = tokenValueLengths[st.Pos]
                st.Pos = st.Pos + 1
            }
            if st.Pos >= count || tokenKinds[st.Pos] != 129 {
                st.ArgStackTop = tryArgBase
                return -1
            }
            catchBody := ParseBlockStatementNodeCore(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if catchBody < 0 {
                st.ArgStackTop = tryArgBase
                return -1
            }
            catchEnd := nodes.SpanStarts[catchBody] + nodes.SpanLengths[catchBody]
            clauseChildCount := 1
            if nameStart >= 0 {
                clauseChildCount = 2
            }
            nameNode := 0 - 1
            if nameStart >= 0 {
                nameNode = EmitExpressionNode(ref st, ref nodes, 6, nameStart, nameLen, st.ChildCursor, 0, nameStart, nameLen)
            }
            clauseChildRun := st.ChildCursor
            if nameNode >= 0 {
                AppendExpressionChild(ref st, ref children, nameNode)
            }
            AppendExpressionChild(ref st, ref children, catchBody)
            clause := EmitExpressionNode(ref st, ref nodes, 50, typeStart, typeLen, clauseChildRun, clauseChildCount, catchStart, catchEnd - catchStart)
            argStackValues[st.ArgStackTop] = clause
            st.ArgStackTop = st.ArgStackTop + 1
        }
        if st.Pos < count && tokenKinds[st.Pos] == 40 {
            st.Pos = st.Pos + 1
            if st.Pos >= count || tokenKinds[st.Pos] != 129 {
                st.ArgStackTop = tryArgBase
                return -1
            }
            finallyBlock := ParseBlockStatementNodeCore(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if finallyBlock < 0 {
                st.ArgStackTop = tryArgBase
                return -1
            }
            argStackValues[st.ArgStackTop] = finallyBlock
            st.ArgStackTop = st.ArgStackTop + 1
        }
        childTotal := st.ArgStackTop - tryArgBase
        if childTotal < 2 {
            st.ArgStackTop = tryArgBase
            return -1
        }
        lastClause := argStackValues[st.ArgStackTop - 1]
        tryEnd := nodes.SpanStarts[lastClause] + nodes.SpanLengths[lastClause]
        tryChildRun := st.ChildCursor
        a := tryArgBase
        while a < st.ArgStackTop {
            AppendExpressionChild(ref st, ref children, argStackValues[a])
            a = a + 1
        }
        st.ArgStackTop = tryArgBase
        return EmitExpressionNode(ref st, ref nodes, 49, -1, 0, tryChildRun, childTotal, tryStart, tryEnd - tryStart)
    }

    // `lock <expr> { }` (Lock 80) -- LockStatement kind 51, children [lockee, body]. The lockee parses
    // as a full expression; the body must be a `{ }` block. `using` (16) stays deferred — the columnar
    // type surface has no IDisposable values to model.
    if kind == 80 {
        lockStart := tokenStarts[start]
        st.Pos = start + 1
        lockee := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if lockee < 0 {
            return -1
        }
        if st.Pos >= count || tokenKinds[st.Pos] != 129 {
            return -1
        }
        lockBody := ParseBlockStatementNodeCore(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if lockBody < 0 {
            return -1
        }
        lockEnd := nodes.SpanStarts[lockBody] + nodes.SpanLengths[lockBody]
        lockChildRun := st.ChildCursor
        AppendExpressionChild(ref st, ref children, lockee)
        AppendExpressionChild(ref st, ref children, lockBody)
        return EmitExpressionNode(ref st, ref nodes, 51, -1, 0, lockChildRun, 2, lockStart, lockEnd - lockStart)
    }

    if kind == 27 {
        whileStart := tokenStarts[start]
        st.Pos = start + 1
        condition := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if condition < 0 {
            return -1
        }

        body := ParseStatementCoreNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if body < 0 {
            return -1
        }

        bodyEnd := nodes.SpanStarts[body] + nodes.SpanLengths[body]
        childRunStart := st.ChildCursor
        AppendExpressionChild(ref st, ref children, condition)
        AppendExpressionChild(ref st, ref children, body)
        return EmitExpressionNode(ref st, ref nodes, 26, -1, 0, childRunStart, 2, whileStart, bodyEnd - whileStart)
    }

    if kind == 25 {
        forStart := tokenStarts[start]
        st.Pos = start + 1

        // C-style `for <init>; <cond>; <incr> { body }`. init/incr are simple statements (a `:=` declaration or
        // an assignment expression statement); cond is an expression. All three clauses are required (an empty
        // clause makes a sub-parse refuse -> the whole statement declines to the C# parser). Children, in order:
        // [init, cond, incr, body] -> ForStatement kind 28.
        initNode := ParseSimpleStatementNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children)
        if initNode < 0 {
            return -1
        }

        if st.Pos >= count || tokenKinds[st.Pos] != 133 {
            return -1
        }
        st.Pos = st.Pos + 1

        forCondition := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if forCondition < 0 {
            return -1
        }

        if st.Pos >= count || tokenKinds[st.Pos] != 133 {
            return -1
        }
        st.Pos = st.Pos + 1

        increment := ParseSimpleStatementNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children)
        if increment < 0 {
            return -1
        }

        forBody := ParseStatementCoreNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if forBody < 0 {
            return -1
        }

        forBodyEnd := nodes.SpanStarts[forBody] + nodes.SpanLengths[forBody]
        forChildRunStart := st.ChildCursor
        AppendExpressionChild(ref st, ref children, initNode)
        AppendExpressionChild(ref st, ref children, forCondition)
        AppendExpressionChild(ref st, ref children, increment)
        AppendExpressionChild(ref st, ref children, forBody)
        return EmitExpressionNode(ref st, ref nodes, 28, -1, 0, forChildRunStart, 4, forStart, forBodyEnd - forStart)
    }

    if kind == 26 {
        foreachStart := tokenStarts[start]
        st.Pos = start + 1

        // `foreach <var> in <collection> { body }` (the no-paren, Go-style form). The loop variable name is an
        // identifier stored in the node's value span; children are [collection, body] -> ForeachStatement kind 29.
        // A parenthesised `foreach (x in y)` or a missing var/`in`/body refuses with -1 -> declines to the C# parser.
        if st.Pos >= count || tokenKinds[st.Pos] != 0 {
            return -1
        }
        foreachVarStart := tokenStarts[st.Pos]
        foreachVarLength := tokenValueLengths[st.Pos]
        st.Pos = st.Pos + 1

        if st.Pos >= count || tokenKinds[st.Pos] != 28 {
            return -1
        }
        st.Pos = st.Pos + 1

        collection := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if collection < 0 {
            return -1
        }

        foreachBody := ParseStatementCoreNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if foreachBody < 0 {
            return -1
        }

        foreachBodyEnd := nodes.SpanStarts[foreachBody] + nodes.SpanLengths[foreachBody]
        foreachChildRunStart := st.ChildCursor
        AppendExpressionChild(ref st, ref children, collection)
        AppendExpressionChild(ref st, ref children, foreachBody)
        return EmitExpressionNode(ref st, ref nodes, 29, foreachVarStart, foreachVarLength, foreachChildRunStart, 2, foreachStart, foreachBodyEnd - foreachStart)
    }

    if kind == 23 {
        ifStart := tokenStarts[start]
        st.Pos = start + 1
        condition := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if condition < 0 {
            return -1
        }

        thenNode := ParseStatementCoreNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if thenNode < 0 {
            return -1
        }

        endSpan := nodes.SpanStarts[thenNode] + nodes.SpanLengths[thenNode]
        elseNode := -1
        if st.Pos < count && tokenKinds[st.Pos] == 24 {
            st.Pos = st.Pos + 1
            elseNode = ParseStatementCoreNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if elseNode < 0 {
                return -1
            }

            endSpan = nodes.SpanStarts[elseNode] + nodes.SpanLengths[elseNode]
        }

        childRunStart := st.ChildCursor
        AppendExpressionChild(ref st, ref children, condition)
        AppendExpressionChild(ref st, ref children, thenNode)
        ifChildCount := 2
        if elseNode >= 0 {
            AppendExpressionChild(ref st, ref children, elseNode)
            ifChildCount = 3
        }

        return EmitExpressionNode(ref st, ref nodes, 27, -1, 0, childRunStart, ifChildCount, ifStart, endSpan - ifStart)
    }

    return ParseSimpleStatementNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children)
}

// The non-control-flow statements: return / break / continue / `:=` declaration / expression statement.
func ParseSimpleStatementNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    argStackValues := argStack.Values
    start := st.Pos
    kind := tokenKinds[start]

    if kind == 29 {
        returnStart := tokenStarts[start]
        returnEnd := tokenStarts[start] + tokenValueLengths[start]
        st.Pos = start + 1

        if st.Pos < count && tokenKinds[st.Pos] != 130 && tokenKinds[st.Pos] != 135 && tokenKinds[st.Pos] != 136 {
            valueRoot := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
            if valueRoot < 0 {
                return -1
            }

            valueEnd := nodes.SpanStarts[valueRoot] + nodes.SpanLengths[valueRoot]
            childRunStart := st.ChildCursor
            AppendExpressionChild(ref st, ref children, valueRoot)
            return EmitExpressionNode(ref st, ref nodes, 20, -1, 0, childRunStart, 1, returnStart, valueEnd - returnStart)
        }

        return EmitExpressionNode(ref st, ref nodes, 20, -1, 0, -1, 0, returnStart, returnEnd - returnStart)
    }

    // `throw <expr>` (Throw 37) -- ThrowStatement kind 48, ONE child [the exception expression].
    // A bare `throw` (rethrow, catch-only) is unmodeled (-1) until the catch rung lands. Throw
    // ALWAYS EXITS: both AlwaysReturns mirrors (the emitter's and ColumnarDiagnosticsPass's) treat
    // kind 48 like Return -- added in the SAME slice (the pass's faithfulness is by construction).
    if kind == 37 {
        throwStart := tokenStarts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokenKinds[st.Pos] == 130 || tokenKinds[st.Pos] == 135 || tokenKinds[st.Pos] == 136 {
            return -1
        }
        throwValue := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if throwValue < 0 {
            return -1
        }
        throwEnd := nodes.SpanStarts[throwValue] + nodes.SpanLengths[throwValue]
        throwChildRun := st.ChildCursor
        AppendExpressionChild(ref st, ref children, throwValue)
        return EmitExpressionNode(ref st, ref nodes, 48, -1, 0, throwChildRun, 1, throwStart, throwEnd - throwStart)
    }

    if kind == 35 {
        st.Pos = start + 1
        return EmitExpressionNode(ref st, ref nodes, 21, -1, 0, -1, 0, tokenStarts[start], tokenValueLengths[start])
    }

    if kind == 36 {
        st.Pos = start + 1
        return EmitExpressionNode(ref st, ref nodes, 22, -1, 0, -1, 0, tokenStarts[start], tokenValueLengths[start])
    }

    // Tuple DECONSTRUCTION `n0, n1, ... := <tuple>` (>= 2 names): an identifier FOLLOWED BY a comma. Each target
    // is a bare identifier (or `_` discard) emitted as an Identifier node (kind 6); the value follows `:=`. The
    // node is TupleDeconstructionStatement kind 30, children = [name0, ..., nameN-1, value]. A malformed list
    // (a non-identifier target, a missing `:=` or value) refuses with -1 -> declines to the C# parser.
    if kind == 0 && start + 1 < count && tokenKinds[start + 1] == 134 {
        deconStart := tokenStarts[start]
        deconArgBase := st.ArgStackTop

        firstName := EmitExpressionNode(ref st, ref nodes, 6, tokenStarts[start], tokenValueLengths[start], -1, 0, tokenStarts[start], tokenValueLengths[start])
        argStackValues[st.ArgStackTop] = firstName
        st.ArgStackTop = st.ArgStackTop + 1
        st.Pos = start + 1

        while st.Pos < count && tokenKinds[st.Pos] == 134 {
            st.Pos = st.Pos + 1
            if st.Pos >= count || tokenKinds[st.Pos] != 0 {
                st.ArgStackTop = deconArgBase
                return -1
            }

            nextName := EmitExpressionNode(ref st, ref nodes, 6, tokenStarts[st.Pos], tokenValueLengths[st.Pos], -1, 0, tokenStarts[st.Pos], tokenValueLengths[st.Pos])
            argStackValues[st.ArgStackTop] = nextName
            st.ArgStackTop = st.ArgStackTop + 1
            st.Pos = st.Pos + 1
        }

        if st.Pos >= count || tokenKinds[st.Pos] != 121 {
            st.ArgStackTop = deconArgBase
            return -1
        }
        st.Pos = st.Pos + 1

        deconValue := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if deconValue < 0 {
            st.ArgStackTop = deconArgBase
            return -1
        }

        argStackValues[st.ArgStackTop] = deconValue
        st.ArgStackTop = st.ArgStackTop + 1
        deconValueEnd := nodes.SpanStarts[deconValue] + nodes.SpanLengths[deconValue]
        deconChildCount := st.ArgStackTop - deconArgBase
        deconChildRunStart := st.ChildCursor
        deconIdx := deconArgBase
        while deconIdx < st.ArgStackTop {
            AppendExpressionChild(ref st, ref children, argStackValues[deconIdx])
            deconIdx = deconIdx + 1
        }
        st.ArgStackTop = deconArgBase

        return EmitExpressionNode(ref st, ref nodes, 30, -1, 0, deconChildRunStart, deconChildCount, deconStart, deconValueEnd - deconStart)
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
        st.Pos = funcScan
        localFuncEnd := tokenStarts[funcScan - 1] + tokenValueLengths[funcScan - 1]
        return EmitExpressionNode(ref st, ref nodes, 41, localFuncSpanStart, localFuncSpanLength, -1, 0, localFuncSpanStart, localFuncEnd - localFuncSpanStart)
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
        st.Pos = scanPos + 1
        typedInit := ParseLambdaOrAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if typedInit < 0 {
            return -1
        }
        typedNameNode := EmitExpressionNode(ref st, ref nodes, 6, typedNameStart, typedNameLength, -1, 0, typedNameStart, typedNameLength)
        typedInitEnd := nodes.SpanStarts[typedInit] + nodes.SpanLengths[typedInit]
        typedChildRunStart := st.ChildCursor
        AppendExpressionChild(ref st, ref children, typedNameNode)
        AppendExpressionChild(ref st, ref children, typedInit)
        declStart := tokenStarts[start]
        return EmitExpressionNode(ref st, ref nodes, 40, typeSpanStart, typeSpanEnd - typeSpanStart, typedChildRunStart, 2, declStart, typedInitEnd - declStart)
    }

    if kind == 0 && start + 1 < count && tokenKinds[start + 1] == 121 {
        nameStart := tokenStarts[start]
        nameLength := tokenValueLengths[start]
        st.Pos = start + 2
        // The `:=` initializer parses at the LAMBDA level (the full-expression entry) so `zero := () => 99`
        // yields a Lambda (kind 39) initializer; all non-lambda shapes fall through to assignment unchanged.
        initRoot := ParseLambdaOrAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if initRoot < 0 {
            return -1
        }

        initEnd := nodes.SpanStarts[initRoot] + nodes.SpanLengths[initRoot]
        childRunStart := st.ChildCursor
        AppendExpressionChild(ref st, ref children, initRoot)
        return EmitExpressionNode(ref st, ref nodes, 24, nameStart, nameLength, childRunStart, 1, nameStart, initEnd - nameStart)
    }

    exprRoot := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
    if exprRoot < 0 {
        return -1
    }

    exprStart := nodes.SpanStarts[exprRoot]
    exprEnd := nodes.SpanStarts[exprRoot] + nodes.SpanLengths[exprRoot]
    childRunStart := st.ChildCursor
    AppendExpressionChild(ref st, ref children, exprRoot)
    return EmitExpressionNode(ref st, ref nodes, 23, -1, 0, childRunStart, 1, exprStart, exprEnd - exprStart)
}

func ParseStatementNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    argStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserExpressionNodeTable { Kinds: outNodeKinds, ValueStarts: outValueStarts, ValueLengths: outValueLengths, ChildStart: outChildStart, ChildCount: outChildCount, SpanStarts: outSpanStarts, SpanLengths: outSpanLengths }
    children := new ParserChildIndexTable { Indices: outChildIndices }
    result := new ParserResultTable { Values: outResult }
    return ParseStatementNodesCore(ref tokens, count, start, ref argStack, ref nodes, ref children, ref result)
}

func ParseStatementNodesCore(tokens: &ParserTokenTable, count: int, start: int, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, outResult: &ParserResultTable): int {
    st := new ParserState { Pos: start, NodeCursor: 0, ChildCursor: 0, ArgStackTop: 0, SplitGreaterDepth: 0, OwedGreaterByteEnd: 0 }

    root := ParseStatementCoreNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
    if root < 0 {
        return -1
    }

    outResult.Values[0] = root
    outResult.Values[1] = st.Pos
    return st.NodeCursor
}
