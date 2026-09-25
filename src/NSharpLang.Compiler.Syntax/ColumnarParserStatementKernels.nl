// STATEMENTS: blocks, the statement core, the simple-statement fan-out, and the foreach and
// deconstruction scans they need.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.
func ParseBlockStatementNodeCore(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    blockStart := tokens.Starts[st.Pos]
    st.Pos = st.Pos + 1
    argBase := st.ArgStackTop

    while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
        stmt := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if stmt < 0 {
            st.ArgStackTop = argBase
            return -1
        }

        argStack.Values[st.ArgStackTop] = stmt
        st.ArgStackTop = st.ArgStackTop + 1
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
        st.ArgStackTop = argBase
        return -1
    }

    rightBraceEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
    st.Pos = st.Pos + 1
    childCount := st.ArgStackTop - argBase
    childRunStart := st.ChildCursor
    a := argBase
    while a < st.ArgStackTop {
        AppendExpressionChild(st, children, argStack.Values[a])
        a = a + 1
    }

    st.ArgStackTop = argBase

    return EmitExpressionNode(st, nodes, 25, -1, 0, childRunStart, childCount, blockStart, rightBraceEnd - blockStart)
}

func ParseSystemsPolicyBlockStatementNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    start := st.Pos
    kind := tokens.Kinds[start]
    st.Pos = start + 1

    if kind == 144 {
        if st.Pos >= count || tokens.Kinds[st.Pos] != 127 {
            return -1
        }

        parenDepth := 1
        st.Pos = st.Pos + 1
        while st.Pos < count && parenDepth > 0 {
            if tokens.Kinds[st.Pos] == 127 {
                parenDepth = parenDepth + 1
            } else if tokens.Kinds[st.Pos] == 128 {
                parenDepth = parenDepth - 1
            }

            st.Pos = st.Pos + 1
        }

        if parenDepth != 0 {
            return -1
        }
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
        return -1
    }

    return ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
}

// WHICH `using` FORM THE TOKENS SPELL, from two of them. A bare identifier followed by `:=` (121)
// binds with an inferred type and one followed by `:` (122) binds with an annotation; every other
// continuation — `.`, `(`, `[`, an operator, `{` — is a resource EXPRESSION, so `using r { … }`,
// `using a.B() { … }` and `using Open(path) { … }` all reach the unbound arm. The optional `let` is
// consumed by the caller before this is asked.
func IsUsingDeclarationAt(tokens: ParserTokenTable, count: int, pos: int): bool {
    if pos + 1 >= count || tokens.Kinds[pos] != 0 {
        return false
    }

    next := tokens.Kinds[pos + 1]
    return next == 121 || next == 122
}

// THE INDEX OF THE `{` THAT OPENS A `using` BODY, or -1 when the statement has none. Braces nest INTO
// the depth count, so only a brace the resource expression could actually have swallowed is ever
// returned; a `)`, `]` or `}` that closes something this statement never opened ends the scan,
// because the statement cannot reach past its own enclosing block.
func UsingBodyBraceIndexAt(tokens: ParserTokenTable, count: int, pos: int): int {
    depth := 0
    index := pos
    while index < count {
        k := tokens.Kinds[index]
        if k == 127 || k == 131 {
            depth = depth + 1
        } else if k == 129 {
            if depth == 0 {
                return index
            }

            depth = depth + 1
        } else if k == 128 || k == 130 || k == 132 {
            if depth == 0 {
                return -1
            }

            depth = depth - 1
        } else if k == 135 {
            return -1
        }

        index = index + 1
    }

    return -1
}

func ParseStatementCoreNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    start := st.Pos
    if start >= count {
        return -1
    }

    kind := tokens.Kinds[start]

    if kind == 129 {
        return ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth)
    }

    if kind == 143 || kind == 144 || kind == 146 {
        return ParseSystemsPolicyBlockStatementNode(tokens, count, st, argStack, nodes, children, depth)
    }

    // `try { } [catch ... { }]* [finally { }]` (Try 38 / Catch 39 / Finally 40) -- TryStatement kind 49,
    // children [tryBlock, catch1..catchN, finallyBlock?] (variable arity -> LIFO arg-stack, like blocks;
    // the finally is a trailing kind-25 BLOCK child, distinguishable from the kind-50 catches by kind).
    // Each catch is a kind-50 CatchClause node: value span = the exception TYPE name token (-1 for a bare
    // catch), children [nameIdent?, filter?, block] -- the bound variable as a 0-child kind-6 identifier, so
    // the name reads as a USE in every name scan (the linter treats catch variables as always used), and the
    // optional exception FILTER as a kind-84 wrapper. All FOUR
    // production catch forms (Parser.cs:3016-3051): bare `catch {`, parenthesized `catch (e: T) {` /
    // `catch (T) {` / `catch (T e) {`, and paren-less `catch e: T {` -- each optionally followed by
    // `when <expr>`. The TYPE must be a single Identifier
    // token (the emitter's BCL exception whitelist needs no more). Zero catches are valid WITH a finally
    // (`try {} finally {}`); a try with neither refuses. All bodies must be `{ }` BLOCKS.
    if kind == 38 {
        tryStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
            return -1
        }

        tryBlock := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
        if tryBlock < 0 {
            return -1
        }

        tryArgBase := st.ArgStackTop
        argStack.Values[st.ArgStackTop] = tryBlock
        st.ArgStackTop = st.ArgStackTop + 1
        while st.Pos < count && tokens.Kinds[st.Pos] == 39 {
            catchStart := tokens.Starts[st.Pos]
            st.Pos = st.Pos + 1
            typeStart := 0 - 1
            typeLen := 0
            nameStart := 0 - 1
            nameLen := 0
            if st.Pos < count && tokens.Kinds[st.Pos] == 127 {
                st.Pos = st.Pos + 1
                if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
                    nameStart = tokens.Starts[st.Pos]
                    nameLen = tokens.ValueLengths[st.Pos]
                    st.Pos = st.Pos + 2
                    if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                        st.ArgStackTop = tryArgBase
                        return -1
                    }

                    typeStart = tokens.Starts[st.Pos]
                    typeLen = tokens.ValueLengths[st.Pos]
                    st.Pos = st.Pos + 1
                } else {
                    if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                        st.ArgStackTop = tryArgBase
                        return -1
                    }

                    typeStart = tokens.Starts[st.Pos]
                    typeLen = tokens.ValueLengths[st.Pos]
                    st.Pos = st.Pos + 1
                    if st.Pos < count && tokens.Kinds[st.Pos] == 0 {
                        nameStart = tokens.Starts[st.Pos]
                        nameLen = tokens.ValueLengths[st.Pos]
                        st.Pos = st.Pos + 1
                    }
                }

                if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
                    st.ArgStackTop = tryArgBase
                    return -1
                }

                st.Pos = st.Pos + 1
            } else if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
                nameStart = tokens.Starts[st.Pos]
                nameLen = tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 2
                if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                    st.ArgStackTop = tryArgBase
                    return -1
                }

                typeStart = tokens.Starts[st.Pos]
                typeLen = tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 1
            }

            // `catch <binding> when <expr> { }` -- the EXCEPTION FILTER. The guard sits between the
            // binding and the handler block, exactly where a match arm's `when` sits between its
            // pattern and its `=>`, and it is parsed by the same assignment-expression entry the
            // `for ... in <collection> {` header uses, so a `{` closes the expression rather than
            // opening an initializer. It becomes a kind-84 CatchFilterClause WRAPPER rather than a
            // bare child, because the clause's optional binding is itself a kind-6 identifier and a
            // guard may be one too (`catch e: T when running`): wrapping keeps all three child slots
            // distinguishable BY KIND, which is the same discipline kind 49 already uses to tell its
            // trailing kind-25 `finally` from its kind-50 catches.
            filterGuard := 0 - 1
            filterStart := 0 - 1
            if st.Pos < count && tokens.Kinds[st.Pos] == 54 {
                filterStart = tokens.Starts[st.Pos]
                st.Pos = st.Pos + 1
                filterGuard = ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
                if filterGuard < 0 {
                    st.ArgStackTop = tryArgBase
                    return -1
                }
            }

            if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
                st.ArgStackTop = tryArgBase
                return -1
            }

            catchBody := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
            if catchBody < 0 {
                st.ArgStackTop = tryArgBase
                return -1
            }

            catchEnd := nodes.SpanStarts[catchBody] + nodes.SpanLengths[catchBody]
            clauseChildCount := 1
            if nameStart >= 0 {
                clauseChildCount = clauseChildCount + 1
            }

            if filterGuard >= 0 {
                clauseChildCount = clauseChildCount + 1
            }

            nameNode := 0 - 1
            if nameStart >= 0 {
                nameNode = EmitExpressionNode(st, nodes, 6, nameStart, nameLen, st.ChildCursor, 0, nameStart, nameLen)
            }

            filterNode := 0 - 1
            if filterGuard >= 0 {
                filterChildRun := st.ChildCursor
                AppendExpressionChild(st, children, filterGuard)
                filterEnd := nodes.SpanStarts[filterGuard] + nodes.SpanLengths[filterGuard]
                filterNode = EmitExpressionNode(st, nodes, 84, -1, 0, filterChildRun, 1, filterStart, filterEnd - filterStart)
            }

            clauseChildRun := st.ChildCursor
            if nameNode >= 0 {
                AppendExpressionChild(st, children, nameNode)
            }

            if filterNode >= 0 {
                AppendExpressionChild(st, children, filterNode)
            }

            AppendExpressionChild(st, children, catchBody)
            clause := EmitExpressionNode(st, nodes, 50, typeStart, typeLen, clauseChildRun, clauseChildCount, catchStart, catchEnd - catchStart)
            argStack.Values[st.ArgStackTop] = clause
            st.ArgStackTop = st.ArgStackTop + 1
        }

        if st.Pos < count && tokens.Kinds[st.Pos] == 40 {
            st.Pos = st.Pos + 1
            if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
                st.ArgStackTop = tryArgBase
                return -1
            }

            finallyBlock := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
            if finallyBlock < 0 {
                st.ArgStackTop = tryArgBase
                return -1
            }

            argStack.Values[st.ArgStackTop] = finallyBlock
            st.ArgStackTop = st.ArgStackTop + 1
        }

        childTotal := st.ArgStackTop - tryArgBase
        if childTotal < 2 {
            st.ArgStackTop = tryArgBase
            return -1
        }

        lastClause := argStack.Values[st.ArgStackTop - 1]
        tryEnd := nodes.SpanStarts[lastClause] + nodes.SpanLengths[lastClause]
        tryChildRun := st.ChildCursor
        a := tryArgBase
        while a < st.ArgStackTop {
            AppendExpressionChild(st, children, argStack.Values[a])
            a = a + 1
        }

        st.ArgStackTop = tryArgBase
        return EmitExpressionNode(st, nodes, 49, -1, 0, tryChildRun, childTotal, tryStart, tryEnd - tryStart)
    }

    // `lock <expr> { }` (Lock 80) -- LockStatement kind 51, children [lockee, body]. The lockee parses
    // as a full expression; the body must be a `{ }` block.
    if kind == 80 {
        lockStart := tokens.Starts[start]
        st.Pos = start + 1
        lockee := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if lockee < 0 {
            return -1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
            return -1
        }

        lockBody := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
        if lockBody < 0 {
            return -1
        }

        lockEnd := nodes.SpanStarts[lockBody] + nodes.SpanLengths[lockBody]
        lockChildRun := st.ChildCursor
        AppendExpressionChild(st, children, lockee)
        AppendExpressionChild(st, children, lockBody)
        return EmitExpressionNode(st, nodes, 51, -1, 0, lockChildRun, 2, lockStart, lockEnd - lockStart)
    }

    // `using` (16) and `await using` (Await 69 + Using 16) -- UsingStatement kind 77, or kind 81 for
    // the asynchronous release. Children are [resource] for a using DECLARATION and [resource, body]
    // for the block form, where `resource` is a kind-24 (`x := e`) or kind-40 (`x: T := e`) local
    // DECLARATION when the statement binds its resource and an ordinary EXPRESSION when it does not.
    // Reusing the two declaration shapes rather than inventing a third is what lets the lowering
    // declare the resource local with the machinery every other local already uses; the resource is
    // told apart from the unbound form by its node KIND, which no expression can collide with.
    //
    // A block body is REQUIRED for the unbound form and optional for the bound one: an unnamed
    // resource with no block would be released at a point the reader cannot see, which is exactly why
    // C# has no such spelling either.
    //
    // The body's `{` is located BEFORE the resource parses and parked on `st.UsingBodyBrace` — see
    // that field for why the ambiguity has to be settled by token index.
    if kind == 16 || (kind == 69 && start + 1 < count && tokens.Kinds[start + 1] == 16) {
        usingStart := tokens.Starts[start]
        usingKind := 77
        usingKeyword := start
        if kind == 69 {
            usingKind = 81
            usingKeyword = start + 1
        }

        st.Pos = usingKeyword + 1
        // `let` is the optional, redundant spelling of the same binding — `using let r := e` and
        // `using r := e` are one form — so it is consumed and then forgotten.
        if st.Pos < count && tokens.Kinds[st.Pos] == 19 {
            st.Pos = st.Pos + 1
        }

        savedUsingBrace := st.UsingBodyBrace
        st.UsingBodyBrace = UsingBodyBraceIndexAt(tokens, count, st.Pos)
        usingResource := -1
        if IsUsingDeclarationAt(tokens, count, st.Pos) {
            usingResource = ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        } else {
            usingResource = ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        }

        st.UsingBodyBrace = savedUsingBrace
        if usingResource < 0 {
            return -1
        }

        usingBound := nodes.Kinds[usingResource] == 24 || nodes.Kinds[usingResource] == 40
        usingBody := -1
        if st.Pos < count && tokens.Kinds[st.Pos] == 129 {
            usingBody = ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
            if usingBody < 0 {
                return -1
            }
        } else if !usingBound {
            return -1
        }

        usingEnd := nodes.SpanStarts[usingResource] + nodes.SpanLengths[usingResource]
        usingChildCount := 1
        if usingBody >= 0 {
            usingChildCount = 2
            usingEnd = nodes.SpanStarts[usingBody] + nodes.SpanLengths[usingBody]
        }

        usingChildRun := st.ChildCursor
        AppendExpressionChild(st, children, usingResource)
        if usingBody >= 0 {
            AppendExpressionChild(st, children, usingBody)
        }

        return EmitExpressionNode(st, nodes, usingKind, -1, 0, usingChildRun, usingChildCount, usingStart, usingEnd - usingStart)
    }

    // `allow(...) { }` (Allow 144) -- AllowStatement kind 60, children [body]. The systems analyzer owns the
    // effect-list semantics; the columnar parser only validates a balanced parenthesized argument list and a
    // block body so product sources advance to the backend's explicit unsupported-statement decline.
    if kind == 144 {
        allowStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] != 127 {
            return -1
        }

        st.Pos = st.Pos + 1
        parenDepth := 1
        while st.Pos < count && parenDepth > 0 {
            if tokens.Kinds[st.Pos] == 127 {
                parenDepth = parenDepth + 1
            } else if tokens.Kinds[st.Pos] == 128 {
                parenDepth = parenDepth - 1
            }

            st.Pos = st.Pos + 1
        }

        if parenDepth != 0 {
            return -1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
            return -1
        }

        allowBody := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
        if allowBody < 0 {
            return -1
        }

        allowEnd := nodes.SpanStarts[allowBody] + nodes.SpanLengths[allowBody]
        allowChildRun := st.ChildCursor
        AppendExpressionChild(st, children, allowBody)
        return EmitExpressionNode(st, nodes, 60, -1, 0, allowChildRun, 1, allowStart, allowEnd - allowStart)
    }

    if kind == 27 {
        whileStart := tokens.Starts[start]
        st.Pos = start + 1
        condition := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if condition < 0 {
            return -1
        }

        body := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if body < 0 {
            return -1
        }

        bodyEnd := nodes.SpanStarts[body] + nodes.SpanLengths[body]
        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, condition)
        AppendExpressionChild(st, children, body)
        return EmitExpressionNode(st, nodes, 26, -1, 0, childRunStart, 2, whileStart, bodyEnd - whileStart)
    }

    if kind == 25 {
        forStart := tokens.Starts[start]
        st.Pos = start + 1

        // `for <var>: <Type> in <collection> { body }` — the ANNOTATED loop variable, TypedForeach
        // kind 76. The `Identifier :` prefix is shared with a C-style header whose initializer is
        // annotated, so the type span is scanned STRUCTURALLY to a depth-0 `in` (28) and the arm is
        // taken only when one is found; anything else falls through to the C-style parse below.
        if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 && ParserTypedForeachInIndex(tokens, count, st.Pos + 2) >= 0 {
            return ParseTypedForeachTailNode(tokens, count, st, argStack, nodes, children, depth, forStart, st.Pos)
        }

        // Production accepts Go-style `for <var> in <collection> { body }` as a foreach spelling. Reuse
        // the existing ForeachStatement node shape so lowering stays shared with the `foreach` keyword.
        if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 28 {
            forVarStart := tokens.Starts[st.Pos]
            forVarLength := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 2

            forCollection := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
            if forCollection < 0 {
                return -1
            }

            forEachBody := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if forEachBody < 0 {
                return -1
            }

            forEachBodyEnd := nodes.SpanStarts[forEachBody] + nodes.SpanLengths[forEachBody]
            forEachChildRunStart := st.ChildCursor
            AppendExpressionChild(st, children, forCollection)
            AppendExpressionChild(st, children, forEachBody)
            return EmitExpressionNode(st, nodes, 29, forVarStart, forVarLength, forEachChildRunStart, 2, forStart, forEachBodyEnd - forStart)
        }

        // C-style `for <init>; <cond>; <incr> { body }`. init/incr are simple statements (a `:=` declaration or
        // an assignment expression statement); cond is an expression. All three clauses are required (an empty
        // clause makes a sub-parse refuse -> the whole statement declines). Children, in order:
        // [init, cond, incr, body] -> ForStatement kind 28.
        initNode := ParseSimpleStatementNode(tokens, count, st, argStack, nodes, children)
        if initNode < 0 {
            return -1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 133 {
            return -1
        }

        st.Pos = st.Pos + 1

        forCondition := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if forCondition < 0 {
            return -1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 133 {
            return -1
        }

        st.Pos = st.Pos + 1

        increment := ParseSimpleStatementNode(tokens, count, st, argStack, nodes, children)
        if increment < 0 {
            return -1
        }

        forBody := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if forBody < 0 {
            return -1
        }

        forBodyEnd := nodes.SpanStarts[forBody] + nodes.SpanLengths[forBody]
        forChildRunStart := st.ChildCursor
        AppendExpressionChild(st, children, initNode)
        AppendExpressionChild(st, children, forCondition)
        AppendExpressionChild(st, children, increment)
        AppendExpressionChild(st, children, forBody)
        return EmitExpressionNode(st, nodes, 28, -1, 0, forChildRunStart, 4, forStart, forBodyEnd - forStart)
    }

    if kind == 26 {
        foreachStart := tokens.Starts[start]
        st.Pos = start + 1

        // `foreach <var> in <collection> { body }` (the no-paren, Go-style form). The loop variable name is an
        // identifier stored in the node's value span; children are [collection, body] -> ForeachStatement kind 29.
        // A parenthesised `foreach (x in y)` or a missing var/`in`/body refuses with -1 -> declines.
        if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
            return -1
        }

        // `foreach <var>: <Type> in <collection>` — the same annotated form the `for` arm reads.
        if st.Pos + 1 < count && tokens.Kinds[st.Pos + 1] == 122 {
            return ParseTypedForeachTailNode(tokens, count, st, argStack, nodes, children, depth, foreachStart, st.Pos)
        }

        foreachVarStart := tokens.Starts[st.Pos]
        foreachVarLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1

        if st.Pos >= count || tokens.Kinds[st.Pos] != 28 {
            return -1
        }

        st.Pos = st.Pos + 1

        collection := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if collection < 0 {
            return -1
        }

        foreachBody := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if foreachBody < 0 {
            return -1
        }

        foreachBodyEnd := nodes.SpanStarts[foreachBody] + nodes.SpanLengths[foreachBody]
        foreachChildRunStart := st.ChildCursor
        AppendExpressionChild(st, children, collection)
        AppendExpressionChild(st, children, foreachBody)
        return EmitExpressionNode(st, nodes, 29, foreachVarStart, foreachVarLength, foreachChildRunStart, 2, foreachStart, foreachBodyEnd - foreachStart)
    }

    // `await foreach <var> in <collection> { body }` (Await 69 DIRECTLY followed by Foreach 26 -- the
    // Parser.cs:2249 two-token dispatch) -- AwaitForeachStatement kind 73: the kind-29 shape (var name in
    // the value span, children [collection, body]) under a distinct kind so async enumeration lowers
    // separately. A parenthesised `await foreach (x in y)` refuses exactly like kind 29's parenthesised
    // form; a statement-position `await <expr>` with any other lookahead falls through to the expression
    // statement path (AwaitExpression kind 53).
    if kind == 69 && start + 1 < count && tokens.Kinds[start + 1] == 26 {
        awaitForeachStart := tokens.Starts[start]
        st.Pos = start + 2

        if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
            return -1
        }

        awaitForeachVarStart := tokens.Starts[st.Pos]
        awaitForeachVarLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1

        if st.Pos >= count || tokens.Kinds[st.Pos] != 28 {
            return -1
        }

        st.Pos = st.Pos + 1

        awaitForeachCollection := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if awaitForeachCollection < 0 {
            return -1
        }

        awaitForeachBody := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if awaitForeachBody < 0 {
            return -1
        }

        awaitForeachBodyEnd := nodes.SpanStarts[awaitForeachBody] + nodes.SpanLengths[awaitForeachBody]
        awaitForeachChildRunStart := st.ChildCursor
        AppendExpressionChild(st, children, awaitForeachCollection)
        AppendExpressionChild(st, children, awaitForeachBody)
        return EmitExpressionNode(st, nodes, 73, awaitForeachVarStart, awaitForeachVarLength, awaitForeachChildRunStart, 2, awaitForeachStart, awaitForeachBodyEnd - awaitForeachStart)
    }

    if kind == 23 {
        ifStart := tokens.Starts[start]
        st.Pos = start + 1
        condition := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if condition < 0 {
            return -1
        }

        thenNode := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if thenNode < 0 {
            return -1
        }

        endSpan := nodes.SpanStarts[thenNode] + nodes.SpanLengths[thenNode]
        elseNode := -1
        if st.Pos < count && tokens.Kinds[st.Pos] == 24 {
            st.Pos = st.Pos + 1
            elseNode = ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if elseNode < 0 {
                return -1
            }

            endSpan = nodes.SpanStarts[elseNode] + nodes.SpanLengths[elseNode]
        }

        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, condition)
        AppendExpressionChild(st, children, thenNode)
        ifChildCount := 2
        if elseNode >= 0 {
            AppendExpressionChild(st, children, elseNode)
            ifChildCount = 3
        }

        return EmitExpressionNode(st, nodes, 27, -1, 0, childRunStart, ifChildCount, ifStart, endSpan - ifStart)
    }

    return ParseSimpleStatementNode(tokens, count, st, argStack, nodes, children)
}

// THE INDEX OF THE `in` (28) THAT CLOSES AN ANNOTATED LOOP VARIABLE'S TYPE, or -1 when the tokens
// from `typeFirst` are not a type followed by one. Balanced angles (`>>` 112 closes two) and ()/[]
// groups are tracked so a `Dictionary<string, int>` or a `(int, int)` annotation is crossed whole;
// a `{` (129), a `;` (133) or end-of-file (135) at depth 0 means the header is not an annotated
// loop variable at all — which is how a C-style `for` whose initializer merely happens to be
// annotated refuses here and reaches its own arm intact, with no tokens consumed and no node built.
func ParserTypedForeachInIndex(tokens: ParserTokenTable, count: int, typeFirst: int): int {
    typedForeachScan := typeFirst
    typedForeachAngles := 0
    typedForeachGroups := 0
    while typedForeachScan < count {
        typedForeachToken := tokens.Kinds[typedForeachScan]
        if typedForeachToken == 28 && typedForeachAngles == 0 && typedForeachGroups == 0 {
            if typedForeachScan == typeFirst {
                return -1
            }

            return typedForeachScan
        }

        if typedForeachToken == 100 {
            typedForeachAngles = typedForeachAngles + 1
        } else if typedForeachToken == 102 {
            typedForeachAngles = typedForeachAngles - 1
        } else if typedForeachToken == 112 {
            typedForeachAngles = typedForeachAngles - 2
        } else if typedForeachToken == 119 || typedForeachToken == 127 || typedForeachToken == 131 {
            // `?[` (119) is one token and still opens a bracket group — the same reading the typed
            // local's annotation scan uses, for the same `string?[]` spelling.
            typedForeachGroups = typedForeachGroups + 1
        } else if typedForeachToken == 128 || typedForeachToken == 132 {
            typedForeachGroups = typedForeachGroups - 1
        } else if typedForeachAngles == 0 && typedForeachGroups == 0 && (typedForeachToken == 129 || typedForeachToken == 133 || typedForeachToken == 135) {
            return -1
        }

        if typedForeachAngles < 0 || typedForeachGroups < 0 {
            return -1
        }

        typedForeachScan = typedForeachScan + 1
    }

    return -1
}

// THE ANNOTATED LOOP VARIABLE'S TAIL, shared by `for` and `foreach`. `nameIndex` is the loop
// variable's token (a `:` follows it), and `keywordStart` is the loop keyword's byte offset, which
// anchors the statement's span. The TYPE rides as a SOURCE SPAN in the value slot, delimited
// structurally (balanced angles — `>>` 112 closes two — and ()/[] groups) and ending at the first
// depth-0 `in` (28), exactly as kind 40 delimits a typed local's annotation at its depth-0 `=`.
// Returns the TypedForeach node id (kind 76), or -1 when the shape is not one.
func ParseTypedForeachTailNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int, keywordStart: int, nameIndex: int): int {
    typedLoopNameStart := tokens.Starts[nameIndex]
    typedLoopNameLength := tokens.ValueLengths[nameIndex]
    typedLoopTypeFirst := nameIndex + 2
    typedLoopScan := ParserTypedForeachInIndex(tokens, count, typedLoopTypeFirst)
    if typedLoopScan < 0 {
        return -1
    }

    typedLoopTypeStart := tokens.Starts[typedLoopTypeFirst]
    typedLoopTypeEnd := tokens.Starts[typedLoopScan - 1] + tokens.ValueLengths[typedLoopScan - 1]
    st.Pos = typedLoopScan + 1
    typedLoopCollection := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
    if typedLoopCollection < 0 {
        return -1
    }

    typedLoopBody := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
    if typedLoopBody < 0 {
        return -1
    }

    typedLoopNameNode := EmitExpressionNode(st, nodes, 6, typedLoopNameStart, typedLoopNameLength, -1, 0, typedLoopNameStart, typedLoopNameLength)
    typedLoopBodyEnd := nodes.SpanStarts[typedLoopBody] + nodes.SpanLengths[typedLoopBody]
    typedLoopChildRunStart := st.ChildCursor
    AppendExpressionChild(st, children, typedLoopNameNode)
    AppendExpressionChild(st, children, typedLoopCollection)
    AppendExpressionChild(st, children, typedLoopBody)
    return EmitExpressionNode(st, nodes, 76, typedLoopTypeStart, typedLoopTypeEnd - typedLoopTypeStart, typedLoopChildRunStart, 3, keywordStart, typedLoopBodyEnd - keywordStart)
}

// The index of the `:=` / `=` that follows a parenthesised DECONSTRUCTION TARGET LIST opened at `open`,
// or -1 when what follows the `(` is not one. This is a pure lookahead and it commits to nothing: a `(`
// that opens an ordinary parenthesised expression -- a tuple literal statement, a grouped call -- must
// still be read as one, so the target-list branch may not consume a token until the whole shape is
// confirmed.
func ScanTupleDeconstructionTargetList(tokens: ParserTokenTable, count: int, open: int): int {
    scan := open + 1
    if scan + 1 >= count || tokens.Kinds[scan] != 0 || tokens.Kinds[scan + 1] != 134 {
        return -1
    }

    scan = scan + 1
    while scan < count && tokens.Kinds[scan] == 134 {
        scan = scan + 1
        if scan >= count || tokens.Kinds[scan] != 0 {
            return -1
        }

        scan = scan + 1
    }

    if scan >= count || tokens.Kinds[scan] != 128 {
        return -1
    }

    scan = scan + 1
    if scan >= count || (tokens.Kinds[scan] != 121 && tokens.Kinds[scan] != 93) {
        return -1
    }

    return scan
}

func ParseSimpleStatementNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable): int {
    start := st.Pos
    kind := tokens.Kinds[start]

    // `off <handle>` -- OffStatement kind 80, ONE child [handle]. The handle parses at the assignment
    // level, so `off subs[0]` and `off this.sub` reach the same slot as a bare name.
    if ParserTokenIsOffKeyword(tokens, count, st, start) {
        offStart := tokens.Starts[start]
        st.Pos = start + 1
        offHandle := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if offHandle < 0 {
            return -1
        }

        offEnd := nodes.SpanStarts[offHandle] + nodes.SpanLengths[offHandle]
        offChildRun := st.ChildCursor
        AppendExpressionChild(st, children, offHandle)
        return EmitExpressionNode(st, nodes, 80, -1, 0, offChildRun, 1, offStart, offEnd - offStart)
    }

    // A BARE `on <target> <handler>` STATEMENT -- the subscription whose handle is discarded. It reaches
    // the statement door ahead of the expression fall-through below because that one parses at the
    // ASSIGNMENT level, one rung under the lambda level `on` needs for its handler.
    if ParserTokenIsOnKeyword(tokens, count, st, start) {
        onRoot := ParseOnSubscriptionNode(tokens, count, st, argStack, nodes, children, 0)
        if onRoot < 0 {
            return -1
        }

        onSpanStart := nodes.SpanStarts[onRoot]
        onSpanEnd := onSpanStart + nodes.SpanLengths[onRoot]
        onChildRun := st.ChildCursor
        AppendExpressionChild(st, children, onRoot)
        return EmitExpressionNode(st, nodes, 23, -1, 0, onChildRun, 1, onSpanStart, onSpanEnd - onSpanStart)
    }

    if kind == 29 {
        returnStart := tokens.Starts[start]
        returnEnd := tokens.Starts[start] + tokens.ValueLengths[start]
        st.Pos = start + 1

        if st.Pos < count && tokens.Kinds[st.Pos] != 130 && tokens.Kinds[st.Pos] != 135 && tokens.Kinds[st.Pos] != 136 {
            // THE LAMBDA LEVEL, not the assignment one: `return x => …` and `return async () => …`
            // are a delegate-returning function's ordinary body, and the lambda level falls through to
            // assignment for everything that is not one.
            valueRoot := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
            if valueRoot < 0 {
                return -1
            }

            valueEnd := nodes.SpanStarts[valueRoot] + nodes.SpanLengths[valueRoot]
            childRunStart := st.ChildCursor
            AppendExpressionChild(st, children, valueRoot)
            return EmitExpressionNode(st, nodes, 20, -1, 0, childRunStart, 1, returnStart, valueEnd - returnStart)
        }

        return EmitExpressionNode(st, nodes, 20, -1, 0, -1, 0, returnStart, returnEnd - returnStart)
    }

    // `yield <expr>` / `yield break` (Yield 30) -- YieldStatement kind 72. ZERO children = `yield break`
    // (terminates the iterator; AlwaysReturns treats it like return/throw); ONE child = the yielded value
    // expression (produces a value and continues). Only legal inside a generator (`func*`); the analyzer
    // enforces that. ColumnarIteratorPlanner lowers kind 72 into the iterator state machine.
    if kind == 30 {
        yieldStart := tokens.Starts[start]
        st.Pos = start + 1

        if st.Pos < count && tokens.Kinds[st.Pos] == 35 {
            breakEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            return EmitExpressionNode(st, nodes, 72, -1, 0, -1, 0, yieldStart, breakEnd - yieldStart)
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] == 130 || tokens.Kinds[st.Pos] == 135 || tokens.Kinds[st.Pos] == 136 {
            return -1
        }

        // THE LAMBDA LEVEL, not the assignment one — the same choice `return` above makes, and for
        // the same reason: `yield () => v` and `yield async () => v` are the ordinary bodies of a
        // generator whose element type is a delegate, and the lambda level falls through to
        // assignment for everything that is not one. Parsing a yielded value at the assignment level
        // made `yield x => …` a PARSE failure of the whole function (`parse.function`), which is the
        // one diagnostic that cannot say what it did not understand.
        yieldValue := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if yieldValue < 0 {
            return -1
        }

        yieldValueEnd := nodes.SpanStarts[yieldValue] + nodes.SpanLengths[yieldValue]
        yieldChildRun := st.ChildCursor
        AppendExpressionChild(st, children, yieldValue)
        return EmitExpressionNode(st, nodes, 72, -1, 0, yieldChildRun, 1, yieldStart, yieldValueEnd - yieldStart)
    }

    // `throw <expr>` (Throw 37) -- ThrowStatement kind 48, ONE child [the exception expression].
    // ZERO children = a bare `throw`, the RETHROW: it re-raises the exception the enclosing `catch`
    // handler is running for, preserving its original stack trace (IL `rethrow`). The analyzer owns
    // the placement rule (NL336); the emitter refuses a bare throw it cannot place in a handler.
    // Throw ALWAYS EXITS in either shape: the emitter's AlwaysReturns mirror treats kind 48 like Return.
    if kind == 37 {
        throwStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] == 130 || tokens.Kinds[st.Pos] == 135 || tokens.Kinds[st.Pos] == 136 {
            throwKeywordEnd := tokens.Starts[start] + tokens.ValueLengths[start]
            return EmitExpressionNode(st, nodes, 48, -1, 0, -1, 0, throwStart, throwKeywordEnd - throwStart)
        }

        throwValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if throwValue < 0 {
            return -1
        }

        throwEnd := nodes.SpanStarts[throwValue] + nodes.SpanLengths[throwValue]
        throwChildRun := st.ChildCursor
        AppendExpressionChild(st, children, throwValue)
        return EmitExpressionNode(st, nodes, 48, -1, 0, throwChildRun, 1, throwStart, throwEnd - throwStart)
    }

    // `print <expr>` (Print 52) -- PrintStatement kind 56, ONE child [the printed expression]. The value
    // expression is REQUIRED (Parser.cs ParsePrintStatement demands one).
    if kind == 52 {
        printStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] == 130 || tokens.Kinds[st.Pos] == 135 || tokens.Kinds[st.Pos] == 136 {
            return -1
        }

        printValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if printValue < 0 {
            return -1
        }

        printEnd := nodes.SpanStarts[printValue] + nodes.SpanLengths[printValue]
        printChildRun := st.ChildCursor
        AppendExpressionChild(st, children, printValue)
        return EmitExpressionNode(st, nodes, 56, -1, 0, printChildRun, 1, printStart, printEnd - printStart)
    }

    // `assert <cond> [, <msg>]` (Assert 74) -- AssertStatement kind 61, children [condition, message?].
    // `assert throws <TypeName> { body }` -- AssertThrowsStatement kind 62, the exception TYPE name
    // token in the value span, ONE child [body block]. `throws` is a CONTEXTUAL identifier compared
    // via st.Source (Parser.cs ParseAssertStatement checks the identifier text the same way); an
    // entry with no source text cannot match, so the throws form declines there (under-accept).
    if kind == 74 {
        assertStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] == 130 || tokens.Kinds[st.Pos] == 135 || tokens.Kinds[st.Pos] == 136 {
            return -1
        }

        if tokens.Kinds[st.Pos] == 0 && st.Source.Length > 0 && ParserDeclarationTokenTextEquals(st.Source, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos], "throws") {
            st.Pos = st.Pos + 1
            if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                return -1
            }

            throwsTypeStart := tokens.Starts[st.Pos]
            throwsTypeLength := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            while st.Pos < count && tokens.Kinds[st.Pos] == 136 {
                st.Pos = st.Pos + 1
            }

            if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
                return -1
            }

            throwsBody := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, 1)
            if throwsBody < 0 {
                return -1
            }

            throwsEnd := nodes.SpanStarts[throwsBody] + nodes.SpanLengths[throwsBody]
            throwsChildRun := st.ChildCursor
            AppendExpressionChild(st, children, throwsBody)
            return EmitExpressionNode(st, nodes, 62, throwsTypeStart, throwsTypeLength, throwsChildRun, 1, assertStart, throwsEnd - assertStart)
        }

        assertCondition := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if assertCondition < 0 {
            return -1
        }

        assertEnd := nodes.SpanStarts[assertCondition] + nodes.SpanLengths[assertCondition]
        assertMessage := -1
        if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
            st.Pos = st.Pos + 1
            assertMessage = ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
            if assertMessage < 0 {
                return -1
            }

            assertEnd = nodes.SpanStarts[assertMessage] + nodes.SpanLengths[assertMessage]
        }

        assertChildRun := st.ChildCursor
        AppendExpressionChild(st, children, assertCondition)
        assertChildCount := 1
        if assertMessage >= 0 {
            AppendExpressionChild(st, children, assertMessage)
            assertChildCount = 2
        }

        return EmitExpressionNode(st, nodes, 61, -1, 0, assertChildRun, assertChildCount, assertStart, assertEnd - assertStart)
    }

    if kind == 35 {
        st.Pos = start + 1
        return EmitExpressionNode(st, nodes, 21, -1, 0, -1, 0, tokens.Starts[start], tokens.ValueLengths[start])
    }

    if kind == 36 {
        st.Pos = start + 1
        return EmitExpressionNode(st, nodes, 22, -1, 0, -1, 0, tokens.Starts[start], tokens.ValueLengths[start])
    }

    // Tuple DECONSTRUCTION, in BOTH spellings the language has: the bare `n0, n1, ... := <tuple>` and the
    // parenthesised `(n0, n1, ...) := <tuple>` the language tour documents, each with `=` as well as `:=`.
    // Every target is a bare identifier (or `_` discard) emitted as an Identifier node (kind 6); the value
    // follows the operator. The node is TupleDeconstructionStatement kind 30, children =
    // [name0, ..., nameN-1, value], and the OPERATOR TOKEN rides in the value span because it is meaning
    // rather than style: `:=` declares the targets and `=` writes targets that already exist. A malformed
    // list (a non-identifier target, a missing operator or value) refuses with -1 -> declines.
    //
    // THE PARENTHESISED FORM USED TO REACH NO KERNEL AT ALL. `(a, b) := t` was read as an expression
    // statement, and the whole enclosing function declined at `parse.function` even though the recovery
    // parser -- the analyser's front end -- has parsed that spelling since the beginning, so the shape
    // type-checked and then could not be emitted.
    if (kind == 0 && start + 1 < count && tokens.Kinds[start + 1] == 134) || (kind == 127 && ScanTupleDeconstructionTargetList(tokens, count, start) >= 0) {
        deconStart := tokens.Starts[start]
        deconParenthesised := kind == 127
        deconNameStart := start
        if deconParenthesised {
            deconNameStart = start + 1
        }

        deconArgBase := st.ArgStackTop

        firstName := EmitExpressionNode(st, nodes, 6, tokens.Starts[deconNameStart], tokens.ValueLengths[deconNameStart], -1, 0, tokens.Starts[deconNameStart], tokens.ValueLengths[deconNameStart])
        argStack.Values[st.ArgStackTop] = firstName
        st.ArgStackTop = st.ArgStackTop + 1
        st.Pos = deconNameStart + 1

        while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
            st.Pos = st.Pos + 1
            if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                st.ArgStackTop = deconArgBase
                return -1
            }

            nextName := EmitExpressionNode(st, nodes, 6, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos], -1, 0, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos])
            argStack.Values[st.ArgStackTop] = nextName
            st.ArgStackTop = st.ArgStackTop + 1
            st.Pos = st.Pos + 1
        }

        if deconParenthesised {
            if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
                st.ArgStackTop = deconArgBase
                return -1
            }

            st.Pos = st.Pos + 1
        }

        if st.Pos >= count || (tokens.Kinds[st.Pos] != 121 && tokens.Kinds[st.Pos] != 93) {
            st.ArgStackTop = deconArgBase
            return -1
        }

        deconOperator := st.Pos
        st.Pos = st.Pos + 1

        deconValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if deconValue < 0 {
            st.ArgStackTop = deconArgBase
            return -1
        }

        argStack.Values[st.ArgStackTop] = deconValue
        st.ArgStackTop = st.ArgStackTop + 1
        deconValueEnd := nodes.SpanStarts[deconValue] + nodes.SpanLengths[deconValue]
        deconChildCount := st.ArgStackTop - deconArgBase
        deconChildRunStart := st.ChildCursor
        deconIdx := deconArgBase
        while deconIdx < st.ArgStackTop {
            AppendExpressionChild(st, children, argStack.Values[deconIdx])
            deconIdx = deconIdx + 1
        }

        st.ArgStackTop = deconArgBase

        return EmitExpressionNode(st, nodes, 30, tokens.Starts[deconOperator], tokens.ValueLengths[deconOperator], deconChildRunStart, deconChildCount, deconStart, deconValueEnd - deconStart)
    }

    // LOCAL FUNCTION declaration (kind 41): `[static|async]* func name(...) ... { body }` — or
    // `... => expression` — as a statement. The VALUE span stays on the `func` keyword because
    // DirectLocalFunctionTokenIndicesCore maps that start back to the real function token; the SOURCE
    // span covers any modifier prefix.
    if kind == 7 || ((kind == 63 || kind == 68) && start + 1 < count && tokens.Kinds[start + 1] == 7) {
        localFuncSourceStart := tokens.Starts[start]
        funcTokenIndex := start
        if kind != 7 {
            funcTokenIndex = start + 1
        }

        localFuncValueStart := tokens.Starts[funcTokenIndex]
        localFuncValueLength := tokens.ValueLengths[funcTokenIndex]
        // THE BODY OPENS WITH `{` OR WITH `=>`, and the scan stops at whichever comes first at depth
        // zero. Depth matters because a parameter DEFAULT may itself be a lambda — `f: Func<int, int>
        // = x => x + 1` — and that arrow belongs to the signature, not to the body.
        funcScan := funcTokenIndex + 1
        localFuncParenDepth := 0
        localFuncBracketDepth := 0
        localFuncBodyIndex := -1
        while funcScan < count && localFuncBodyIndex < 0 {
            scanKind := tokens.Kinds[funcScan]
            if scanKind == 127 {
                localFuncParenDepth = localFuncParenDepth + 1
            } else if scanKind == 128 {
                if localFuncParenDepth > 0 {
                    localFuncParenDepth = localFuncParenDepth - 1
                }
            } else if scanKind == 131 {
                localFuncBracketDepth = localFuncBracketDepth + 1
            } else if scanKind == 132 {
                if localFuncBracketDepth > 0 {
                    localFuncBracketDepth = localFuncBracketDepth - 1
                }
            } else if localFuncParenDepth == 0 && localFuncBracketDepth == 0 && (scanKind == 129 || scanKind == 120) {
                localFuncBodyIndex = funcScan
            }

            if localFuncBodyIndex < 0 {
                funcScan = funcScan + 1
            }
        }

        if localFuncBodyIndex < 0 {
            return -1
        }

        // AN EXPRESSION BODY ENDS WHERE ITS EXPRESSION ENDS, which only the expression parser knows —
        // the same answer the top-level expression-bodied function scan asks for. Without it a local
        // function could only ever be written with braces, and `func inner(v: string?): string => v ??
        // "d"` declined its WHOLE enclosing function at `parse.function`.
        if tokens.Kinds[localFuncBodyIndex] == 120 {
            localFuncSource := tokens.Source
            if localFuncSource == null {
                return -1
            }

            localFuncEndIndex := ParseDeclarationExpressionBodyEndCore(
                localFuncSource,
                new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths),
                count,
                localFuncBodyIndex
            )
            if localFuncEndIndex <= localFuncBodyIndex + 1 || localFuncEndIndex > count {
                return -1
            }

            st.Pos = localFuncEndIndex
            localFuncExpressionEnd := tokens.Starts[localFuncEndIndex - 1] + tokens.ValueLengths[localFuncEndIndex - 1]
            return EmitExpressionNode(st, nodes, 41, localFuncValueStart, localFuncValueLength, -1, 0, localFuncSourceStart, localFuncExpressionEnd - localFuncSourceStart)
        }

        localFuncDepth := 1
        funcScan = funcScan + 1
        while funcScan < count && localFuncDepth > 0 {
            if tokens.Kinds[funcScan] == 129 {
                localFuncDepth = localFuncDepth + 1
            } else if tokens.Kinds[funcScan] == 130 {
                localFuncDepth = localFuncDepth - 1
            }

            funcScan = funcScan + 1
        }

        if localFuncDepth != 0 {
            return -1
        }

        st.Pos = funcScan
        localFuncEnd := tokens.Starts[funcScan - 1] + tokens.ValueLengths[funcScan - 1]
        return EmitExpressionNode(st, nodes, 41, localFuncValueStart, localFuncValueLength, -1, 0, localFuncSourceStart, localFuncEnd - localFuncSourceStart)
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
    if kind == 19 && start + 2 < count && tokens.Kinds[start + 1] == 0 && tokens.Kinds[start + 2] == 122 {
        isTypedLocal = true
        typedNameIndex = start + 1
    } else if kind == 0 && start + 1 < count && tokens.Kinds[start + 1] == 122 {
        isTypedLocal = true
    }

    if isTypedLocal {
        typedNameStart := tokens.Starts[typedNameIndex]
        typedNameLength := tokens.ValueLengths[typedNameIndex]
        typeFirst := typedNameIndex + 2
        // A TUPLE TYPE STARTS THE SPAN IN BOTH FORMS. The bare form used to refuse a type span opening
        // with `(`, because the production parser's typed-declaration lookahead admitted only a type
        // starting with an IDENTIFIER and read `t: (int, int) = …` as an expression statement instead.
        // That lookahead now admits the `(` of a tuple, so the two forms agree again and the refusal
        // would only recreate the gap on the emit side.
        scanPos := typeFirst
        angleDepth := 0
        groupDepth := 0
        scanning := true
        hasTypedInitializer := true
        typedTerminatorConsumed := false
        while scanning {
            if scanPos >= count {
                return -1
            }

            k := tokens.Kinds[scanPos]
            // `=` (93) and `:=` (121) both end an annotation: the production parser accepts either
            // after a written type (`let x: int = 5` and `let x: int := 5` are one declaration), and a
            // type can contain neither, so both are unambiguous terminators.
            if ParserTokenBeginsLine(tokens, scanPos) && angleDepth == 0 && groupDepth == 0 {
                hasTypedInitializer = false
                scanning = false
            } else if (k == 93 || k == 121) && angleDepth == 0 && groupDepth == 0 {
                scanning = false
            } else if k == 133 && angleDepth == 0 && groupDepth == 0 {
                hasTypedInitializer = false
                typedTerminatorConsumed = true
                scanning = false
            } else {
                if k == 100 {
                    angleDepth = angleDepth + 1
                } else if k == 102 {
                    angleDepth = angleDepth - 1
                } else if k == 112 {
                    angleDepth = angleDepth - 2
                } else if k == 119 || k == 127 || k == 131 {
                    // `?[` (119) IS ONE TOKEN AND STILL OPENS A BRACKET GROUP. The lexer folds the
                    // `?` and `[` of `string?[]` into a single QuestionBracket, so a scan that counted
                    // only `[` (131) saw the closing `]` with nothing open, drove the depth negative
                    // and refused the whole function — while the same spelling in a PARAMETER or a
                    // RETURN type, which are scanned by the type kernel rather than by this delimiter
                    // walk, parsed. The element-may-be-null array annotation is one of the two
                    // spellings the nullability rules give, and a local wears it like any other.
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

        typeSpanStart := tokens.Starts[typeFirst]
        typeSpanEnd := tokens.Starts[scanPos - 1] + tokens.ValueLengths[scanPos - 1]
        if !hasTypedInitializer {
            typedNameNode := EmitExpressionNode(st, nodes, 6, typedNameStart, typedNameLength, -1, 0, typedNameStart, typedNameLength)
            typedChildRunStart := st.ChildCursor
            AppendExpressionChild(st, children, typedNameNode)
            st.Pos = typedTerminatorConsumed ? scanPos + 1 : scanPos
            declStart := tokens.Starts[start]
            typeEnd := tokens.Starts[scanPos - 1] + tokens.ValueLengths[scanPos - 1]
            return EmitExpressionNode(st, nodes, 40, typeSpanStart, typeSpanEnd - typeSpanStart, typedChildRunStart, 1, declStart, typeEnd - declStart)
        }

        st.Pos = scanPos + 1
        typedInit := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if typedInit < 0 {
            return -1
        }

        typedNameNode := EmitExpressionNode(st, nodes, 6, typedNameStart, typedNameLength, -1, 0, typedNameStart, typedNameLength)
        typedInitEnd := nodes.SpanStarts[typedInit] + nodes.SpanLengths[typedInit]
        typedChildRunStart := st.ChildCursor
        AppendExpressionChild(st, children, typedNameNode)
        AppendExpressionChild(st, children, typedInit)
        declStart := tokens.Starts[start]
        return EmitExpressionNode(st, nodes, 40, typeSpanStart, typeSpanEnd - typeSpanStart, typedChildRunStart, 2, declStart, typedInitEnd - declStart)
    }

    if kind == 0 && start + 1 < count && tokens.Kinds[start + 1] == 121 {
        nameStart := tokens.Starts[start]
        nameLength := tokens.ValueLengths[start]
        st.Pos = start + 2
        // The `:=` initializer parses at the LAMBDA level (the full-expression entry) so `zero := () => 99`
        // yields a Lambda (kind 39) initializer; all non-lambda shapes fall through to assignment unchanged.
        initRoot := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if initRoot < 0 {
            return -1
        }

        initEnd := nodes.SpanStarts[initRoot] + nodes.SpanLengths[initRoot]
        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, initRoot)
        return EmitExpressionNode(st, nodes, 24, nameStart, nameLength, childRunStart, 1, nameStart, initEnd - nameStart)
    }

    exprRoot := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
    if exprRoot < 0 {
        return -1
    }

    exprStart := nodes.SpanStarts[exprRoot]
    exprEnd := nodes.SpanStarts[exprRoot] + nodes.SpanLengths[exprRoot]
    childRunStart := st.ChildCursor
    AppendExpressionChild(st, children, exprRoot)
    return EmitExpressionNode(st, nodes, 23, -1, 0, childRunStart, 1, exprStart, exprEnd - exprStart)
}

func ParseStatementNodesCore(source: string, tokens: ParserTokenTable, count: int, start: int, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, outResult: ParserResultTable): int {
    st := new ParserState(start, 0, 0, 0, 0, 0, source)

    root := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, 0)
    if root < 0 {
        return -1
    }

    outResult.Values[0] = root
    outResult.Values[1] = st.Pos
    return st.NodeCursor
}

func ParseColumnarExpressionInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    if outResult.Length < 3 {
        return -1
    }

    if count < 0 {
        return -1
    }

    parseCount := count
    if parseCount > 0 && tokenKinds[parseCount - 1] == 135 {
        parseCount = parseCount - 1
    }

    if parseCount <= 0 {
        return -1
    }

    tokens := new ParserTokenTable(tokenKinds, tokenStarts, tokenValueLengths, source)
    argStack := new ParserArgumentStack(new int[](parseCount + 1))
    nodes := new ParserExpressionNodeTable(outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths)
    children := new ParserChildIndexTable(outChildIndices)
    st := new ParserState(0, 0, 0, 0, 0, 0, source)

    root := ParseLambdaOrAssignmentExpressionNode(tokens, parseCount, st, argStack, nodes, children, 0)
    if root < 0 || st.Pos != parseCount {
        return -1
    }

    outResult[0] = root
    outResult[1] = st.NodeCursor
    outResult[2] = st.ChildCursor
    return st.NodeCursor
}
