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
//   RelationalPattern       -> kind 32  ( <op> <constant> at the start of a match pattern, op in {< <= > >=}
//                                         (tokens 100/101/102/103); operator in the value span, 1 child = the
//                                         operand. Appears ONLY as a match-case pattern slot (incl. under a guard). )
//   AndPattern              -> kind 33  ( <pat> and <pat> -- match-case combinator, children [left, right]. )
//   OrPattern               -> kind 34  ( <pat> or <pat>  -- match-case combinator, children [left, right]. )
//   NotPattern              -> kind 35  ( not <pat>       -- match-case combinator, 1 child [inner]. )
//   ObjectInitializer       -> kind 36  ( new <type> { Field: value, ... } -- children [typeRoot, name0 (Identifier
//                                         kind 6), value0, name1, value1, ...]. Constructs a fields-only struct. )
//   GenericCallee           -> kind 38  ( callee<T1, T2> before a `(` -- the callee identifier's name in the value
//                                         span, children = the TYPE-kernel type-argument roots. Only ever appears
//                                         as child[0] of a CallExpression; committed via the IsGenericCallTypeArgs
//                                         lookahead, the Parser.cs IsGenericMethodCall mirror. Kind 37 is
//                                         UnionCasePattern in ParserStatements. )
//   Lambda                  -> kind 39  ( `x => expr` / `() => expr` / `(x, y) => expr` -- the level ABOVE
//                                         assignment (ParseLambdaOrAssignmentExpression, Parser.cs:3660). The
//                                         `=>` token in the value span; children = [param Identifiers (kind 6,
//                                         zero or more), body expression root] -- paramCount = childCount - 1.
//                                         Params are UNTYPED by grammar (the production parser rejects `:` in a
//                                         lambda list); the body is an EXPRESSION at this level or a statement
//                                         BLOCK (kind 25, parsed by the statement kernel -- mutual recursion in
//                                         the other direction from statements-call-expressions). Parsed at the
//                                         full-expression entry and in call ARGUMENTS (the production's
//                                         ParseExpression positions modeled so far). Kind 40 is
//                                         TypedLocalDeclaration and 41 LocalFunctionDeclaration in
//                                         ParserStatements. )
//   BareNew                 -> kind 42  ( `new <type>` with neither `( args )` nor `{ inits }` -- children
//                                         [typeRoot (a TYPE-kernel subtree -- name scans must skip the whole
//                                         node, like kind 38)]. The brace-less union-case construction form
//                                         (`new Color.Red`, `new Opt.None<int>`); the emitter declines every
//                                         non-union-case type root. )
//   NamedTupleElement       -> kind 43  ( `name: value` inside a NAMED tuple literal `(x: 1, y: 2)` -- the
//                                         element NAME in the name slot, ONE child (the element value). Only
//                                         ever a kind-17 child; naming is ALL-OR-NOTHING per literal. The
//                                         name is metadata (not a value read) so scans traverse the child
//                                         normally. )
//   PostfixUnary            -> kind 44  ( `n++` / `n--` (Increment 113 / Decrement 114) -- the operator
//                                         token in the value span, ONE child [target]. Single wrap after the
//                                         postfix suffix chain; the target child is a VALUE expression the
//                                         scans traverse normally -- and a WRITE: the write scans treat a
//                                         kind-44 like a kind-14 assignment to its target. )
//   MustExpression          -> kind 45  ( `must <operand>` (Must 20) -- the prefix null-assert, ONE child;
//                                         unwraps a Nullable<T> to T or null-checks a reference, throwing
//                                         InvalidOperationException when null. )
//   IsExpression            -> kind 46  ( `value is Type` (Is 47) -- children [value, typeRoot]; the
//                                         typeRoot is a TYPE subtree (scans walk child 0 only). )
//   AsExpression            -> kind 47  ( `value as Type` (As 48) -- the null-propagating cast twin of
//                                         kind 46; same child shape. )
//   WithExpression          -> kind 52  ( `expr with { Field: value, ... }` (With 71) -- the kind-36
//                                         object-init pair layout with the RECEIVER in place of the type
//                                         root: children [receiver, name0 (kind 6), value0, ...]; zero
//                                         pairs = a pure clone. Kinds 48-51 are STATEMENT kinds
//                                         (throw/try/catch/lock). )
//   AwaitExpression         -> kind 53  ( `await <expr>` (Await 69) -- prefix unary, ONE child
//                                         [operand]. )
//   RefOutArgument          -> kind 54  ( `ref <expr>` / `out <expr>` inside a call argument list; the
//                                         modifier token lives in the value span, ONE child [target]. )
// Deferred (refused with -1, or the chain simply STOPS at them): `?.`/`?[` null-conditional access, generic
//   method calls (callee<T>(...)), named (`name:`) call arguments,
//   `is`/`as` type tests, range `..`; every other unlisted primary (this/base/default/alloc/array-literal/
//   interpolated string/...). (Tuples `(a, b)` AND named tuples `(x: 1, y: 2)` PARSE — kinds 17/43; match,
//   new-expressions, object initializers, bare-new and block-bodied lambdas have their own kinds above.)
//   Literal VALUE materialization (unescaping strings/chars) is the host's job; this kernel records the
//   value token's byte span only.
//
// Node-table columns (caller-allocated to capacity >= count+1; outChildIndices likewise):
//   nodes.Kinds[i]    : 0..7 per the list above
//   nodes.ValueStarts[i]  : byte offset of the literal/identifier value token; -1 for Null/Parenthesized
//   nodes.ValueLengths[i] : value byte length; 0 when none
//   nodes.ChildStart[i]   : index into outChildIndices for children; -1 when none
//   nodes.ChildCount[i]   : Parenthesized/MemberAccess = 1; IndexAccess = 2; Call = 1 + #args; others = 0
//   outChildIndices[]  : flattened child node-id edges (post-order; root is the last node)
//   nodes.SpanStarts[i] / nodes.SpanLengths[i] : full source byte span of the node
//   outResult[0] = root node id (== nodeCount-1), outResult[1] = token index past the consumed expression
// Returns the node count, or -1 on refusal / depth > 200.
//
// ParserState `st`: st.Pos=pos, st.NodeCursor=nodeCursor, st.ChildCursor=childCursor, st.ArgStackTop=argStackTop. Calls gather the
// callee + argument node ids on the caller-owned LIFO `argStack` (recursion is LIFO) and append the
// contiguous child run after the closing `)`, exactly as the type kernel does for generic arguments.
//
// For MemberAccess/IndexAccess the value name span (member) or the two children (object, index) are appended
// directly after the object and index are fully parsed -- both are fixed-arity, so their child runs are
// contiguous without the arg-stack.
//
// TokenType ordinals (Token.cs): Identifier 0, IntLiteral 1, FloatLiteral 2, CharLiteral 3, StringLiteral 4,
// True 44, False 45, Null 46, LeftParen 127, RightParen 128, Dot 124, LeftBracket 131, RightBracket 132.

struct ParserExpressionNodeTable {
    Kinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    SpanStarts: int[]
    SpanLengths: int[]
}

func EmitExpressionNode(st: &ParserState, nodes: &ParserExpressionNodeTable, kind: int, valueStart: int, valueLength: int, childStart: int, childCount: int, spanStart: int, spanLength: int): int {
    id := st.NodeCursor
    nodes.Kinds[id] = kind
    nodes.ValueStarts[id] = valueStart
    nodes.ValueLengths[id] = valueLength
    nodes.ChildStart[id] = childStart
    nodes.ChildCount[id] = childCount
    nodes.SpanStarts[id] = spanStart
    nodes.SpanLengths[id] = spanLength
    st.NodeCursor = id + 1
    return id
}

func AppendExpressionChild(st: &ParserState, children: &ParserChildIndexTable, childId: int): int {
    slot := st.ChildCursor
    children.Indices[slot] = childId
    st.ChildCursor = slot + 1
    return slot
}

func ParseExpressionTypeReferenceNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    typeNodes := new ParserNodeTable { Kinds: nodes.Kinds, ValueStarts: nodes.ValueStarts, ValueLengths: nodes.ValueLengths, ChildStart: nodes.ChildStart, ChildCount: nodes.ChildCount, SpanStarts: nodes.SpanStarts, SpanLengths: nodes.SpanLengths }
    return ParseUnionTypeReferenceNodeCore(ref tokens, count, ref st, ref argStack, ref typeNodes, ref children, depth)
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

// Mirrors Parser.cs IsGenericMethodCall (the `<`-after-callee disambiguation, Parser.cs:1993): from the `<` at
// `lessPos`, scan a candidate TYPE-ARGUMENT list — identifiers, dots (124), array brackets (131/132), commas
// (134), and nested `<`(100)/`>`(102)/`>>`(112) — and answer true ONLY when the matching close is followed
// DIRECTLY by `(` (127). Anything else (an operator, a literal, a `)` …) means the `<` is a comparison, not a
// type-argument list — exactly the C# parser's rule, so the kernel commits to a generic call precisely where
// the production parser does.
func IsGenericCallTypeArgs(tokens: &ParserTokenTable, count: int, lessPos: int): bool {
    i := lessPos + 1
    depth := 1
    while i < count {
        k := tokens.Kinds[i]
        if k == 0 || k == 124 || k == 134 || k == 131 || k == 132 {
            i = i + 1
        } else if k == 100 {
            depth = depth + 1
            i = i + 1
        } else if k == 102 {
            depth = depth - 1
            i = i + 1
            if depth == 0 {
                return i < count && tokens.Kinds[i] == 127
            }
        } else if k == 112 {
            depth = depth - 2
            i = i + 1
            if depth == 0 {
                return i < count && tokens.Kinds[i] == 127
            }
            if depth < 0 {
                return false
            }
        } else {
            return false
        }
    }
    return false
}

// Parse a match-case PATTERN with C# pattern precedence (Parser.cs ParsePattern): or > and > not > relational >
// primary. Returns the root node index, or -1 on failure. `and` 55 / `or` 56 / `not` 57 are CONTEXTUAL keywords
// valid only in pattern position. Combinators: OrPattern kind 34 [left,right], AndPattern kind 33 [left,right],
// NotPattern kind 35 [inner]; leaves are a RelationalPattern (kind 32) or an ordinary primary (literal/identifier).
func ParseMatchPatternNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    return ParseOrPatternNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
}

// `<and-pattern> ( or <and-pattern> )*` -> left-associative OrPattern (kind 34). `or` is token 56.
func ParseOrPatternNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    left := ParseAndPatternNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
    if left < 0 {
        return -1
    }
    while st.Pos < count && tokens.Kinds[st.Pos] == 56 {
        st.Pos = st.Pos + 1
        right := ParseAndPatternNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
        if right < 0 {
            return -1
        }
        orChildRun := st.ChildCursor
        AppendExpressionChild(ref st, ref children, left)
        AppendExpressionChild(ref st, ref children, right)
        orSpanStart := nodes.SpanStarts[left]
        orSpanEnd := nodes.SpanStarts[right] + nodes.SpanLengths[right]
        left = EmitExpressionNode(ref st, ref nodes, 34, -1, 0, orChildRun, 2, orSpanStart, orSpanEnd - orSpanStart)
    }
    return left
}

// `<not-pattern> ( and <not-pattern> )*` -> left-associative AndPattern (kind 33). `and` is token 55.
func ParseAndPatternNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    left := ParseNotPatternNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
    if left < 0 {
        return -1
    }
    while st.Pos < count && tokens.Kinds[st.Pos] == 55 {
        st.Pos = st.Pos + 1
        right := ParseNotPatternNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
        if right < 0 {
            return -1
        }
        andChildRun := st.ChildCursor
        AppendExpressionChild(ref st, ref children, left)
        AppendExpressionChild(ref st, ref children, right)
        andSpanStart := nodes.SpanStarts[left]
        andSpanEnd := nodes.SpanStarts[right] + nodes.SpanLengths[right]
        left = EmitExpressionNode(ref st, ref nodes, 33, -1, 0, andChildRun, 2, andSpanStart, andSpanEnd - andSpanStart)
    }
    return left
}

// `not <not-pattern>` -> NotPattern (kind 35, 1 child); else a relational-or-primary pattern. `not` is token 57.
func ParseNotPatternNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }
    if st.Pos < count && tokens.Kinds[st.Pos] == 57 {
        notStart := tokens.Starts[st.Pos]
        st.Pos = st.Pos + 1
        inner := ParseNotPatternNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if inner < 0 {
            return -1
        }
        notChildRun := st.ChildCursor
        AppendExpressionChild(ref st, ref children, inner)
        notSpanEnd := nodes.SpanStarts[inner] + nodes.SpanLengths[inner]
        return EmitExpressionNode(ref st, ref nodes, 35, -1, 0, notChildRun, 1, notStart, notSpanEnd - notStart)
    }
    return ParseRelationalPatternNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
}

// A relational operator (`<` 100, `<=` 101, `>` 102, `>=` 103) at the start -> RelationalPattern (kind 32: operator
// token in the value span, 1 child = the operand primary). Otherwise an ordinary primary. (`>=` is one token, so
// there is no `>`-split here.)
func ParseRelationalPatternNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    if st.Pos < count {
        relTok := tokens.Kinds[st.Pos]
        if relTok == 100 || relTok == 101 || relTok == 102 || relTok == 103 {
            relOpStart := tokens.Starts[st.Pos]
            relOpLen := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            relOperand := ParsePrimaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if relOperand < 0 {
                return -1
            }
            relChildRun := st.ChildCursor
            AppendExpressionChild(ref st, ref children, relOperand)
            relSpanEnd := nodes.SpanStarts[relOperand] + nodes.SpanLengths[relOperand]
            return EmitExpressionNode(ref st, ref nodes, 32, relOpStart, relOpLen, relChildRun, 1, relOpStart, relSpanEnd - relOpStart)
        }
    }
    // The non-relational pattern leaf is a POSTFIX expression (not just a primary): this is what lets an enum
    // constant `Enum.Member` parse as a MemberAccess (kind 8) in pattern position — the columnar analogue of C#'s
    // ParseRelationalPattern falling back to ParsePrimaryExpression (which in C# includes postfix member access). A
    // literal/identifier still parses as before (no postfix to apply); a call/index parses but the emitter declines
    // it as a non-constant pattern.
    leaf := ParsePostfixExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
    if leaf < 0 {
        return -1
    }

    // Union-case PROPERTY pattern: `<Union.Case> { bind0, bind1, ... }` -> UnionCasePattern (kind 37), children
    // [memberAccessNode, bind0 (Identifier kind 6), bind1, ...]. Fires only when the leaf is a qualified member
    // access (kind 8, e.g. `Result.Success`) immediately followed by `{` (129). Each binding is a BARE identifier
    // naming a case field; `,` (134) separates and `}` (130) closes. A renamed/nested/positional sub-pattern
    // (`{ field: <pat> }`) declines here (the `:` after a binding is neither `,` nor `}` -> -1), so the whole
    // program falls back to the C# pipeline. The emitter (case 37) resolves the case, `isinst`-tests it, and binds
    // each named field to a local.
    if nodes.Kinds[leaf] == 8 && st.Pos < count && tokens.Kinds[st.Pos] == 129 {
        st.Pos = st.Pos + 1
        caseArgBase := st.ArgStackTop
        argStack.Values[st.ArgStackTop] = leaf
        st.ArgStackTop = st.ArgStackTop + 1
        while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
            if tokens.Kinds[st.Pos] != 0 {
                st.ArgStackTop = caseArgBase
                return -1
            }
            bindStart := tokens.Starts[st.Pos]
            bindLen := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            bindNode := EmitExpressionNode(ref st, ref nodes, 6, bindStart, bindLen, -1, 0, bindStart, bindLen)
            argStack.Values[st.ArgStackTop] = bindNode
            st.ArgStackTop = st.ArgStackTop + 1
            if st.Pos < count && tokens.Kinds[st.Pos] != 130 {
                if tokens.Kinds[st.Pos] != 134 {
                    st.ArgStackTop = caseArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
            }
        }
        if st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
            st.ArgStackTop = caseArgBase
            return -1
        }
        caseEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        caseChildCount := st.ArgStackTop - caseArgBase
        caseChildRun := st.ChildCursor
        caseArg := caseArgBase
        while caseArg < st.ArgStackTop {
            AppendExpressionChild(ref st, ref children, argStack.Values[caseArg])
            caseArg = caseArg + 1
        }
        st.ArgStackTop = caseArgBase
        caseSpanStart := nodes.SpanStarts[leaf]
        return EmitExpressionNode(ref st, ref nodes, 37, -1, 0, caseChildRun, caseChildCount, caseSpanStart, caseEnd - caseSpanStart)
    }

    return leaf
}

// ParsePrimaryExpression (Parser.cs:4525) restricted to literals, identifiers, and ( expr ). Returns the
// emitted node id, or -1 on refusal/failure. Advances st.Pos past the consumed tokens.
func ParsePrimaryExpressionNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    argStackValues := argStack.Values
    if depth > 200 {
        return -1
    }

    pos := st.Pos
    if pos >= count {
        return -1
    }

    kind := tokenKinds[pos]
    tokenStart := tokenStarts[pos]
    tokenLength := tokenValueLengths[pos]

    if kind == 1 {
        st.Pos = pos + 1
        return EmitExpressionNode(ref st, ref nodes, 0, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 2 {
        st.Pos = pos + 1
        return EmitExpressionNode(ref st, ref nodes, 1, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 3 {
        st.Pos = pos + 1
        return EmitExpressionNode(ref st, ref nodes, 2, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 4 {
        st.Pos = pos + 1
        return EmitExpressionNode(ref st, ref nodes, 3, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 44 || kind == 45 {
        st.Pos = pos + 1
        return EmitExpressionNode(ref st, ref nodes, 4, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 46 {
        st.Pos = pos + 1
        return EmitExpressionNode(ref st, ref nodes, 5, -1, 0, -1, 0, tokenStart, tokenLength)
    }
    if kind == 0 {
        st.Pos = pos + 1
        return EmitExpressionNode(ref st, ref nodes, 6, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 31 {
        // `match <value> { <pattern> => <result>, ... }` (Match token 31, Arrow `=>` token 120). MatchExpression
        // kind 18: children = [value, pat0, res0, pat1, res1, ...] (one value, then each case as a pattern/result
        // pair). The pattern is a PRIMARY expression (a literal or a bare identifier `_`/binding); the emitter
        // gates which pattern kinds it supports (richer patterns -- union-case/property/relational/`when` guards --
        // are parsed-or-refused here and decline at emit). A comma between cases is consumed when present.
        matchStart := tokenStart
        st.Pos = pos + 1
        matchArgBase := st.ArgStackTop

        matchValue := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if matchValue < 0 {
            st.ArgStackTop = matchArgBase
            return -1
        }
        argStackValues[st.ArgStackTop] = matchValue
        st.ArgStackTop = st.ArgStackTop + 1

        if st.Pos >= count || tokenKinds[st.Pos] != 129 {
            st.ArgStackTop = matchArgBase
            return -1
        }
        st.Pos = st.Pos + 1

        matchCaseCount := 0
        while st.Pos < count && tokenKinds[st.Pos] != 130 {
            // Parse the case PATTERN via the pattern-precedence chain (or > and > not > relational > primary,
            // see ParseMatchPatternNode). This yields a literal/identifier primary, a RelationalPattern (kind 32),
            // or an And/Or/Not combinator (kinds 33/34/35) over those. The `when` guard (below) then wraps it.
            matchPattern := ParseMatchPatternNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if matchPattern < 0 {
                st.ArgStackTop = matchArgBase
                return -1
            }

            // `<pattern> when <guard>` -> GuardedPattern (kind 19): wrap the parsed pattern with its guard
            // condition so the emitter can test the pattern THEN the guard before taking the arm. The guard is a
            // full expression (it may reference a binding the pattern introduced). When absent, the bare pattern
            // node is used directly (no kind-19 wrapper), so existing match cases are unchanged.
            if st.Pos < count && tokenKinds[st.Pos] == 54 {
                st.Pos = st.Pos + 1
                matchGuard := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
                if matchGuard < 0 {
                    st.ArgStackTop = matchArgBase
                    return -1
                }
                guardChildRun := st.ChildCursor
                AppendExpressionChild(ref st, ref children, matchPattern)
                AppendExpressionChild(ref st, ref children, matchGuard)
                guardSpanStart := nodes.SpanStarts[matchPattern]
                guardSpanEnd := nodes.SpanStarts[matchGuard] + nodes.SpanLengths[matchGuard]
                matchPattern = EmitExpressionNode(ref st, ref nodes, 19, -1, 0, guardChildRun, 2, guardSpanStart, guardSpanEnd - guardSpanStart)
            }

            argStackValues[st.ArgStackTop] = matchPattern
            st.ArgStackTop = st.ArgStackTop + 1

            if st.Pos >= count || tokenKinds[st.Pos] != 120 {
                st.ArgStackTop = matchArgBase
                return -1
            }
            st.Pos = st.Pos + 1

            matchResult := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if matchResult < 0 {
                st.ArgStackTop = matchArgBase
                return -1
            }
            argStackValues[st.ArgStackTop] = matchResult
            st.ArgStackTop = st.ArgStackTop + 1
            matchCaseCount = matchCaseCount + 1

            if st.Pos < count && tokenKinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
            }
        }

        if matchCaseCount == 0 || st.Pos >= count || tokenKinds[st.Pos] != 130 {
            st.ArgStackTop = matchArgBase
            return -1
        }
        matchEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
        st.Pos = st.Pos + 1

        matchChildCount := st.ArgStackTop - matchArgBase
        matchChildRunStart := st.ChildCursor
        matchArg := matchArgBase
        while matchArg < st.ArgStackTop {
            AppendExpressionChild(ref st, ref children, argStackValues[matchArg])
            matchArg = matchArg + 1
        }
        st.ArgStackTop = matchArgBase

        return EmitExpressionNode(ref st, ref nodes, 18, -1, 0, matchChildRunStart, matchChildCount, matchStart, matchEnd - matchStart)
    }
    if kind == 41 {
        // `new <type> ( args )` -- the array/object construction form the dogfood kernels use
        // (e.g. new int[](length + 1)). COMPOSES the type kernel (the element/constructed type, via the
        // now-unified shared st + argStack) with the expression kernel (the positional constructor args).
        // NewExpression (kind 15): children = [typeRoot, arg0, arg1, ...]. The `new <type> { Field: value, ... }`
        // OBJECT INITIALIZER form is handled below (ObjectInitializerExpression kind 36). The `new <type> [size]`
        // (sized array) and target-typed `new ( ... )` forms are deferred (refused). Named / ref / out constructor
        // arguments are also refused.
        newStart := tokenStart
        st.Pos = pos + 1
        // The type kernel assumes splitGreaterDepth (st.SplitGreaterDepth) is 0 on entry (it is only set/cleared while
        // closing generics within a single type parse). A balanced type always leaves it 0, but reset it
        // explicitly before the call -- matching the function-signature kernel -- so the invariant never
        // relies on the caller's prior state. (st.ArgStackTop=argStackTop must NOT be reset here: the type's generic
        // args nest on the shared LIFO arg-stack above the enclosing expression's current base.)
        st.SplitGreaterDepth = 0
        typeRoot := ParseExpressionTypeReferenceNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if typeRoot < 0 {
            return -1
        }

        // `new <type> { Field: value, ... }` -- OBJECT INITIALIZER (ObjectInitializerExpression kind 36): children
        // [typeRoot, name0, value0, name1, value1, ...] where each nameN is an Identifier node (kind 6, the field
        // name in its value span) and valueN is the field's value expression. Used to construct a fields-only
        // struct (the emitter zero-inits the value then assigns each named field). A `:` after the name is required.
        if st.Pos < count && tokenKinds[st.Pos] == 129 {
            st.Pos = st.Pos + 1
            objArgBase := st.ArgStackTop
            argStackValues[st.ArgStackTop] = typeRoot
            st.ArgStackTop = st.ArgStackTop + 1
            while st.Pos < count && tokenKinds[st.Pos] != 130 {
                if tokenKinds[st.Pos] != 0 {
                    st.ArgStackTop = objArgBase
                    return -1
                }
                fieldNameStart := tokenStarts[st.Pos]
                fieldNameLen := tokenValueLengths[st.Pos]
                st.Pos = st.Pos + 1
                if st.Pos >= count || tokenKinds[st.Pos] != 122 {
                    st.ArgStackTop = objArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
                fieldNameNode := EmitExpressionNode(ref st, ref nodes, 6, fieldNameStart, fieldNameLen, -1, 0, fieldNameStart, fieldNameLen)
                argStackValues[st.ArgStackTop] = fieldNameNode
                st.ArgStackTop = st.ArgStackTop + 1
                fieldVal := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
                if fieldVal < 0 {
                    st.ArgStackTop = objArgBase
                    return -1
                }
                argStackValues[st.ArgStackTop] = fieldVal
                st.ArgStackTop = st.ArgStackTop + 1
                if st.Pos < count && tokenKinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                }
            }
            if st.Pos >= count || tokenKinds[st.Pos] != 130 {
                st.ArgStackTop = objArgBase
                return -1
            }
            objInitEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            objInitChildCount := st.ArgStackTop - objArgBase
            objInitChildRun := st.ChildCursor
            objArg := objArgBase
            while objArg < st.ArgStackTop {
                AppendExpressionChild(ref st, ref children, argStackValues[objArg])
                objArg = objArg + 1
            }
            st.ArgStackTop = objArgBase
            return EmitExpressionNode(ref st, ref nodes, 36, -1, 0, objInitChildRun, objInitChildCount, newStart, objInitEnd - newStart)
        }

        if st.Pos >= count || tokenKinds[st.Pos] != 127 {
            // `new <type>` with NEITHER `{ inits }` NOR `( args )` -- a BARE-NEW expression (kind 42,
            // children [typeRoot]): the brace-less construction form the pipeline accepts for union cases
            // (`new Color.Red`, `new Opt.None<int>`, `new Opt.None` adopting an expected type) -- fields
            // default. The emitter models ONLY union-case type roots for this node; every other bare-new
            // type (struct/BCL/array) declines there, so previously-unparseable programs stay declined.
            bareNewChildRun := st.ChildCursor
            AppendExpressionChild(ref st, ref children, typeRoot)
            bareNewEnd := nodes.SpanStarts[typeRoot] + nodes.SpanLengths[typeRoot]
            return EmitExpressionNode(ref st, ref nodes, 42, -1, 0, bareNewChildRun, 1, newStart, bareNewEnd - newStart)
        }
        st.Pos = st.Pos + 1

        argBase := st.ArgStackTop
        argStackValues[st.ArgStackTop] = typeRoot
        st.ArgStackTop = st.ArgStackTop + 1

        if st.Pos < count && tokenKinds[st.Pos] != 128 {
            if tokenKinds[st.Pos] == 78 || tokenKinds[st.Pos] == 79 {
                st.ArgStackTop = argBase
                return -1
            }

            firstArg := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if firstArg < 0 {
                st.ArgStackTop = argBase
                return -1
            }

            argStackValues[st.ArgStackTop] = firstArg
            st.ArgStackTop = st.ArgStackTop + 1

            while st.Pos < count && tokenKinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
                if st.Pos < count && (tokenKinds[st.Pos] == 78 || tokenKinds[st.Pos] == 79) {
                    st.ArgStackTop = argBase
                    return -1
                }

                nextArg := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
                if nextArg < 0 {
                    st.ArgStackTop = argBase
                    return -1
                }

                argStackValues[st.ArgStackTop] = nextArg
                st.ArgStackTop = st.ArgStackTop + 1
            }
        }

        if st.Pos >= count || tokenKinds[st.Pos] != 128 {
            st.ArgStackTop = argBase
            return -1
        }

        newRightParenEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        newChildCount := st.ArgStackTop - argBase
        newChildRunStart := st.ChildCursor
        na := argBase
        while na < st.ArgStackTop {
            AppendExpressionChild(ref st, ref children, argStackValues[na])
            na = na + 1
        }
        st.ArgStackTop = argBase
        return EmitExpressionNode(ref st, ref nodes, 15, -1, 0, newChildRunStart, newChildCount, newStart, newRightParenEnd - newStart)
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
        castSaveNode := st.NodeCursor
        castSaveChild := st.ChildCursor
        castSaveArg := st.ArgStackTop
        st.Pos = pos + 1
        st.SplitGreaterDepth = 0
        castType := ParseExpressionTypeReferenceNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        isCast := false
        if castType >= 0 && st.Pos < count && tokenKinds[st.Pos] == 128 {
            if st.Pos + 1 < count && IsExpressionStartKind(tokenKinds[st.Pos + 1]) {
                isCast = true
            }
        }

        if isCast {
            st.Pos = st.Pos + 1
            operand := ParseUnaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if operand < 0 {
                return -1
            }

            castSpanEnd := nodes.SpanStarts[operand] + nodes.SpanLengths[operand]
            castChildRun := st.ChildCursor
            AppendExpressionChild(ref st, ref children, castType)
            AppendExpressionChild(ref st, ref children, operand)
            return EmitExpressionNode(ref st, ref nodes, 16, -1, 0, castChildRun, 2, parenStart, castSpanEnd - parenStart)
        }

        st.NodeCursor = castSaveNode
        st.ChildCursor = castSaveChild
        st.ArgStackTop = castSaveArg
        st.SplitGreaterDepth = 0
        st.Pos = pos + 1

        // NAMED tuple literal `(x: 1, y: 2)` (TupleExpression kind 17 whose children are kind-43
        // NamedTupleElement wrappers -- element NAME in the name slot, ONE child = the element value).
        // ALL-OR-NOTHING naming (partial naming is a production-parser error, probe-pinned) and >=2
        // elements (a single named element is not a tuple) -- refuse otherwise. Detected by the
        // `Identifier :` lookahead, which no other parenthesised expression form can start with.
        if st.Pos + 1 < count && tokenKinds[st.Pos] == 0 && tokenKinds[st.Pos + 1] == 122 {
            namedTupleArgBase := st.ArgStackTop
            namedScanning := true
            while namedScanning {
                if st.Pos + 1 >= count || tokenKinds[st.Pos] != 0 || tokenKinds[st.Pos + 1] != 122 {
                    st.ArgStackTop = namedTupleArgBase
                    return -1
                }
                namedElemNameStart := tokenStarts[st.Pos]
                namedElemNameLength := tokenValueLengths[st.Pos]
                st.Pos = st.Pos + 2
                namedElemValue := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
                if namedElemValue < 0 {
                    st.ArgStackTop = namedTupleArgBase
                    return -1
                }
                namedWrapRun := st.ChildCursor
                AppendExpressionChild(ref st, ref children, namedElemValue)
                namedWrapped := EmitExpressionNode(ref st, ref nodes, 43, namedElemNameStart, namedElemNameLength, namedWrapRun, 1, namedElemNameStart, nodes.SpanStarts[namedElemValue] + nodes.SpanLengths[namedElemValue] - namedElemNameStart)
                argStackValues[st.ArgStackTop] = namedWrapped
                st.ArgStackTop = st.ArgStackTop + 1
                if st.Pos < count && tokenKinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                } else {
                    namedScanning = false
                }
            }
            if st.Pos >= count || tokenKinds[st.Pos] != 128 || st.ArgStackTop - namedTupleArgBase < 2 {
                st.ArgStackTop = namedTupleArgBase
                return -1
            }
            namedTupleEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            namedTupleChildCount := st.ArgStackTop - namedTupleArgBase
            namedTupleChildRun := st.ChildCursor
            namedTupleArg := namedTupleArgBase
            while namedTupleArg < st.ArgStackTop {
                AppendExpressionChild(ref st, ref children, argStackValues[namedTupleArg])
                namedTupleArg = namedTupleArg + 1
            }
            st.ArgStackTop = namedTupleArgBase
            return EmitExpressionNode(ref st, ref nodes, 17, -1, 0, namedTupleChildRun, namedTupleChildCount, parenStart, namedTupleEnd - parenStart)
        }

        inner := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if inner < 0 {
            return -1
        }

        // A `,` after the first parenthesised expression makes this a TUPLE `( e0, e1, ... )` (TupleExpression
        // kind 17), not a parenthesised expression. Collect the comma-separated elements on the LIFO arg-stack
        // (variable arity, exactly like a block/call), then append the contiguous child run after `)`.
        if st.Pos < count && tokenKinds[st.Pos] == 134 {
            tupleArgBase := st.ArgStackTop
            argStackValues[st.ArgStackTop] = inner
            st.ArgStackTop = st.ArgStackTop + 1
            while st.Pos < count && tokenKinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
                tupleElem := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
                if tupleElem < 0 {
                    st.ArgStackTop = tupleArgBase
                    return -1
                }

                argStackValues[st.ArgStackTop] = tupleElem
                st.ArgStackTop = st.ArgStackTop + 1
            }

            if st.Pos >= count || tokenKinds[st.Pos] != 128 {
                st.ArgStackTop = tupleArgBase
                return -1
            }

            tupleRightParenEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            tupleChildCount := st.ArgStackTop - tupleArgBase
            tupleChildRunStart := st.ChildCursor
            tupleArg := tupleArgBase
            while tupleArg < st.ArgStackTop {
                AppendExpressionChild(ref st, ref children, argStackValues[tupleArg])
                tupleArg = tupleArg + 1
            }
            st.ArgStackTop = tupleArgBase
            return EmitExpressionNode(ref st, ref nodes, 17, -1, 0, tupleChildRunStart, tupleChildCount, parenStart, tupleRightParenEnd - parenStart)
        }

        if st.Pos >= count || tokenKinds[st.Pos] != 128 {
            return -1
        }

        rightParenEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        childRunStart := st.ChildCursor
        AppendExpressionChild(ref st, ref children, inner)
        return EmitExpressionNode(ref st, ref nodes, 7, -1, 0, childRunStart, 1, parenStart, rightParenEnd - parenStart)
    }

    return -1
}

// ParsePostfixExpression (Parser.cs:4312) restricted to member access (.name) and index access ([expr]).
// A primary expression followed by any run of `.member` and `[index]` suffixes. The member name and the
// two index children are appended right after the object/index are fully parsed (fixed arity => contiguous
// child runs, no arg-stack). Index expressions recurse to this postfix level (the current expression top).
func ParsePostfixExpressionNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    argStackValues := argStack.Values
    expr := ParsePrimaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
    if expr < 0 {
        return -1
    }

    matched := true
    while matched {
        pos := st.Pos

        if pos + 1 < count && tokenKinds[pos] == 124 && tokenKinds[pos + 1] == 0 {
            objSpanStart := nodes.SpanStarts[expr]
            memberStart := tokenStarts[pos + 1]
            memberLength := tokenValueLengths[pos + 1]
            memberEnd := memberStart + memberLength
            childRunStart := st.ChildCursor
            AppendExpressionChild(ref st, ref children, expr)
            expr = EmitExpressionNode(ref st, ref nodes, 8, memberStart, memberLength, childRunStart, 1, objSpanStart, memberEnd - objSpanStart)
            st.Pos = pos + 2
        } else if pos < count && tokenKinds[pos] == 131 {
            objSpanStart := nodes.SpanStarts[expr]
            st.Pos = pos + 1
            index := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if index < 0 {
                return -1
            }

            if st.Pos >= count || tokenKinds[st.Pos] != 132 {
                return -1
            }

            rightBracketEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            childRunStart := st.ChildCursor
            AppendExpressionChild(ref st, ref children, expr)
            AppendExpressionChild(ref st, ref children, index)
            expr = EmitExpressionNode(ref st, ref nodes, 10, -1, 0, childRunStart, 2, objSpanStart, rightBracketEnd - objSpanStart)
        } else if pos < count && tokenKinds[pos] == 100 && nodes.Kinds[expr] == 6 && IsGenericCallTypeArgs(ref tokens, count, pos) {
            // Explicit generic-call TYPE ARGUMENTS `callee<T1, T2>(args)` — committed only when the callee is
            // a BARE identifier and the lookahead (the Parser.cs IsGenericMethodCall mirror above) sees a
            // well-formed type-argument list whose close is followed DIRECTLY by `(`. Each argument parses as
            // a TYPE-kernel subtree on the shared table; the result is a GenericCalleeExpression (kind 38:
            // value span = the callee identifier's name, children = the type-arg roots). The `(` branch of
            // this loop then parses the CALL with the kind-38 node as its callee, so a generic call is
            // [genericCallee, arg0, ...] exactly like a plain call. The `>>` split for a nested generic close
            // is honored via the shared st.SplitGreaterDepth owed-greater state (ConsumeGreaterForTypeNodeCore).
            calleeNameStart := nodes.ValueStarts[expr]
            calleeNameLength := nodes.ValueLengths[expr]
            objSpanStart := nodes.SpanStarts[expr]
            st.Pos = pos + 1
            gArgBase := st.ArgStackTop
            st.SplitGreaterDepth = 0
            firstTypeArg := ParseExpressionTypeReferenceNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
            if firstTypeArg < 0 {
                st.ArgStackTop = gArgBase
                return -1
            }
            argStackValues[st.ArgStackTop] = firstTypeArg
            st.ArgStackTop = st.ArgStackTop + 1

            while st.Pos < count && tokenKinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
                nextTypeArg := ParseExpressionTypeReferenceNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
                if nextTypeArg < 0 {
                    st.ArgStackTop = gArgBase
                    return -1
                }
                argStackValues[st.ArgStackTop] = nextTypeArg
                st.ArgStackTop = st.ArgStackTop + 1
            }

            closeEnd := ConsumeGreaterForTypeNodeCore(ref tokens, count, ref st)
            if closeEnd < 0 {
                st.ArgStackTop = gArgBase
                return -1
            }

            gChildCount := st.ArgStackTop - gArgBase
            gChildRunStart := st.ChildCursor
            g := gArgBase
            while g < st.ArgStackTop {
                AppendExpressionChild(ref st, ref children, argStackValues[g])
                g = g + 1
            }
            st.ArgStackTop = gArgBase
            expr = EmitExpressionNode(ref st, ref nodes, 38, calleeNameStart, calleeNameLength, gChildRunStart, gChildCount, objSpanStart, closeEnd - objSpanStart)
        } else if pos < count && tokenKinds[pos] == 127 {
            // Call `callee(args)`: children = [callee, arg0, arg1, ...]. Like generic type arguments, the
            // callee + arg node ids are gathered on the LIFO arg-stack (each arg is a full expression that
            // appends its own descendants) and the contiguous child run is appended only after the closing
            // `)`. Named (`name:`) arguments are still deferred and refuse when the argument expression
            // leaves the colon unconsumed.
            objSpanStart := nodes.SpanStarts[expr]
            st.Pos = pos + 1
            argBase := st.ArgStackTop
            argStackValues[st.ArgStackTop] = expr
            st.ArgStackTop = st.ArgStackTop + 1

            if st.Pos < count && tokenKinds[st.Pos] != 128 {
                firstArg := ParseCallArgumentNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
                if firstArg < 0 {
                    st.ArgStackTop = argBase
                    return -1
                }

                argStackValues[st.ArgStackTop] = firstArg
                st.ArgStackTop = st.ArgStackTop + 1

                while st.Pos < count && tokenKinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                    nextArg := ParseCallArgumentNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
                    if nextArg < 0 {
                        st.ArgStackTop = argBase
                        return -1
                    }

                    argStackValues[st.ArgStackTop] = nextArg
                    st.ArgStackTop = st.ArgStackTop + 1
                }
            }

            if st.Pos >= count || tokenKinds[st.Pos] != 128 {
                st.ArgStackTop = argBase
                return -1
            }

            rightParenEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            childCount := st.ArgStackTop - argBase
            childRunStart := st.ChildCursor
            a := argBase
            while a < st.ArgStackTop {
                AppendExpressionChild(ref st, ref children, argStackValues[a])
                a = a + 1
            }
            st.ArgStackTop = argBase
            expr = EmitExpressionNode(ref st, ref nodes, 9, -1, 0, childRunStart, childCount, objSpanStart, rightParenEnd - objSpanStart)
        } else if pos + 1 < count && tokenKinds[pos] == 71 && tokenKinds[pos + 1] == 129 {
            // `expr with { Field: value, ... }` (With 71) -- WithExpression kind 52: children
            // [receiver, name0 (Identifier kind 6), value0, name1, value1, ...] -- the kind-36
            // object-initializer pair layout with the RECEIVER expression in place of the type root
            // (the production parses `with` in this same postfix loop, Parser.cs:4510). Zero pairs
            // (a pure clone) are valid. Pairs gather on the LIFO arg-stack exactly as kind 36 does.
            receiverSpanStart := nodes.SpanStarts[expr]
            st.Pos = pos + 2
            wArgBase := st.ArgStackTop
            argStackValues[st.ArgStackTop] = expr
            st.ArgStackTop = st.ArgStackTop + 1
            while st.Pos < count && tokenKinds[st.Pos] != 130 {
                if tokenKinds[st.Pos] != 0 {
                    st.ArgStackTop = wArgBase
                    return -1
                }
                wNameStart := tokenStarts[st.Pos]
                wNameLen := tokenValueLengths[st.Pos]
                st.Pos = st.Pos + 1
                if st.Pos >= count || tokenKinds[st.Pos] != 122 {
                    st.ArgStackTop = wArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
                wNameNode := EmitExpressionNode(ref st, ref nodes, 6, wNameStart, wNameLen, -1, 0, wNameStart, wNameLen)
                argStackValues[st.ArgStackTop] = wNameNode
                st.ArgStackTop = st.ArgStackTop + 1
                wValue := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
                if wValue < 0 {
                    st.ArgStackTop = wArgBase
                    return -1
                }
                argStackValues[st.ArgStackTop] = wValue
                st.ArgStackTop = st.ArgStackTop + 1
                if st.Pos < count && tokenKinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                }
            }
            if st.Pos >= count || tokenKinds[st.Pos] != 130 {
                st.ArgStackTop = wArgBase
                return -1
            }
            withEnd := tokenStarts[st.Pos] + tokenValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            wChildCount := st.ArgStackTop - wArgBase
            wChildRun := st.ChildCursor
            wArg := wArgBase
            while wArg < st.ArgStackTop {
                AppendExpressionChild(ref st, ref children, argStackValues[wArg])
                wArg = wArg + 1
            }
            st.ArgStackTop = wArgBase
            expr = EmitExpressionNode(ref st, ref nodes, 52, -1, 0, wChildRun, wChildCount, receiverSpanStart, withEnd - receiverSpanStart)
        } else {
            matched = false
        }
    }

    // Postfix `++`/`--` (Increment 113 / Decrement 114) -- a SINGLE wrap after the suffix chain
    // (PostfixUnary kind 44, the operator token in the value span, ONE child [target]; `n++++` does
    // not re-enter, matching the production grammar). The emitter validates the target (a bare
    // local/param) and models C# post-semantics (the expression's value is the PRE-step value).
    if st.Pos < count {
        postOp := tokenKinds[st.Pos]
        if postOp == 113 || postOp == 114 {
            postOpStart := tokenStarts[st.Pos]
            postOpLength := tokenValueLengths[st.Pos]
            postOpEnd := postOpStart + postOpLength
            st.Pos = st.Pos + 1
            postChildRun := st.ChildCursor
            AppendExpressionChild(ref st, ref children, expr)
            postSpanStart := nodes.SpanStarts[expr]
            return EmitExpressionNode(ref st, ref nodes, 44, postOpStart, postOpLength, postChildRun, 1, postSpanStart, postOpEnd - postSpanStart)
        }
    }

    return expr
}

func ParseCallArgumentNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    if depth > 200 {
        return -1
    }

    if st.Pos < count && (tokenKinds[st.Pos] == 78 || tokenKinds[st.Pos] == 79) {
        modifierStart := tokenStarts[st.Pos]
        modifierLength := tokenValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        value := ParseLambdaOrAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if value < 0 {
            return -1
        }

        valueEnd := nodes.SpanStarts[value] + nodes.SpanLengths[value]
        childRun := st.ChildCursor
        AppendExpressionChild(ref st, ref children, value)
        return EmitExpressionNode(ref st, ref nodes, 54, modifierStart, modifierLength, childRun, 1, modifierStart, valueEnd - modifierStart)
    }

    return ParseLambdaOrAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
}

// ParseUnaryExpression (Parser.cs:4223) restricted to the prefix operators: ! (Not 106), - (Negate, Minus
// 89), ~ (BitwiseNot 110), ++ (PreIncrement 113), -- (PreDecrement 114), ^ (IndexFromEnd, BitwiseXor 109).
// A prefix operator wraps a (recursively-parsed) unary operand -> UnaryExpression (kind 11, operator token
// in the value span); otherwise the operand is a postfix expression. (Prefix `+` is invalid in N# and is
// refused via the postfix/primary fall-through. Postfix ++/-- and `must` are deferred.)
func ParseUnaryExpressionNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    if depth > 200 {
        return -1
    }

    pos := st.Pos
    if pos < count {
        k := tokenKinds[pos]
        // `must <operand>` (Must 20) -- the prefix null-assert (MustExpression kind 45, ONE child;
        // the operand recurses at THIS unary level so `must must x` chains like the production parser).
        if k == 20 {
            mustStart := tokenStarts[pos]
            st.Pos = pos + 1
            mustOperand := ParseUnaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if mustOperand < 0 {
                return -1
            }
            mustSpanEnd := nodes.SpanStarts[mustOperand] + nodes.SpanLengths[mustOperand]
            mustChildRun := st.ChildCursor
            AppendExpressionChild(ref st, ref children, mustOperand)
            return EmitExpressionNode(ref st, ref nodes, 45, -1, 0, mustChildRun, 1, mustStart, mustSpanEnd - mustStart)
        }
        // `await <operand>` (Await 69) -- the prefix await (AwaitExpression kind 53, ONE child; the
        // operand recurses at THIS unary level, mirroring the production's prefix-unary production
        // at Parser.cs ParseUnaryExpression so `await await x` chains).
        if k == 69 {
            awaitStart := tokenStarts[pos]
            st.Pos = pos + 1
            awaitOperand := ParseUnaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if awaitOperand < 0 {
                return -1
            }
            awaitSpanEnd := nodes.SpanStarts[awaitOperand] + nodes.SpanLengths[awaitOperand]
            awaitChildRun := st.ChildCursor
            AppendExpressionChild(ref st, ref children, awaitOperand)
            return EmitExpressionNode(ref st, ref nodes, 53, -1, 0, awaitChildRun, 1, awaitStart, awaitSpanEnd - awaitStart)
        }
        if k == 106 || k == 89 || k == 110 || k == 113 || k == 114 || k == 109 {
            opStart := tokenStarts[pos]
            opLength := tokenValueLengths[pos]
            st.Pos = pos + 1
            operand := ParseUnaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if operand < 0 {
                return -1
            }

            operandSpanEnd := nodes.SpanStarts[operand] + nodes.SpanLengths[operand]
            childRunStart := st.ChildCursor
            AppendExpressionChild(ref st, ref children, operand)
            return EmitExpressionNode(ref st, ref nodes, 11, opStart, opLength, childRunStart, 1, opStart, operandSpanEnd - opStart)
        }
    }

    return ParsePostfixExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
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
func ParseBinaryExpressionNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, minPrec: int, depth: int): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    if depth > 200 {
        return -1
    }

    left := ParseUnaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
    if left < 0 {
        return -1
    }

    // `is` (47) / `as` (48) TYPE tests -- a single wrap binding tighter than the comparison tier (the
    // production's relational-level is/as): children [value, typeRoot] where the typeRoot is a
    // TYPE-kernel subtree (name scans walk child 0 ONLY -- type kinds collide with expression kinds).
    // IsExpression -> kind 46, AsExpression -> kind 47. Non-chaining (a second is/as after refuses
    // naturally: the bool/result re-enters the climber and 47/48 have no precedence).
    if st.Pos < count && (tokenKinds[st.Pos] == 47 || tokenKinds[st.Pos] == 48) {
        isAsKind := 46
        if tokenKinds[st.Pos] == 48 {
            isAsKind = 47
        }
        st.Pos = st.Pos + 1
        st.SplitGreaterDepth = 0
        isAsType := ParseExpressionTypeReferenceNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 0)
        if isAsType < 0 {
            return -1
        }
        isAsSpanStart := nodes.SpanStarts[left]
        isAsSpanEnd := nodes.SpanStarts[isAsType] + nodes.SpanLengths[isAsType]
        isAsChildRun := st.ChildCursor
        AppendExpressionChild(ref st, ref children, left)
        AppendExpressionChild(ref st, ref children, isAsType)
        left = EmitExpressionNode(ref st, ref nodes, isAsKind, -1, 0, isAsChildRun, 2, isAsSpanStart, isAsSpanEnd - isAsSpanStart)
    }

    keepGoing := true
    while keepGoing {
        opKind := -1
        if st.Pos < count {
            opKind = tokenKinds[st.Pos]
        }

        prec := BinaryOpPrecedence(opKind)
        if prec == 0 || prec < minPrec {
            keepGoing = false
        } else {
            opStart := tokenStarts[st.Pos]
            opLength := tokenValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            right := ParseBinaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, prec + 1, depth + 1)
            if right < 0 {
                return -1
            }

            leftSpanStart := nodes.SpanStarts[left]
            rightSpanEnd := nodes.SpanStarts[right] + nodes.SpanLengths[right]
            childRunStart := st.ChildCursor
            AppendExpressionChild(ref st, ref children, left)
            AppendExpressionChild(ref st, ref children, right)
            left = EmitExpressionNode(ref st, ref nodes, 12, opStart, opLength, childRunStart, 2, leftSpanStart, rightSpanEnd - leftSpanStart)
        }
    }

    return left
}

// ParseTernaryExpression (Parser.cs:3916): a binary-chain condition, optionally followed by `? then : else`
// (TernaryExpression, kind 13, children [condition, then, else]). The then/else branches are full
// expressions (assignment level), making the ternary right-associative in the else branch.
func ParseTernaryExpressionNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    tokenKinds := tokens.Kinds
    condition := ParseBinaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, 1, depth)
    if condition < 0 {
        return -1
    }

    if st.Pos < count && tokenKinds[st.Pos] == 115 {
        conditionSpanStart := nodes.SpanStarts[condition]
        st.Pos = st.Pos + 1
        thenNode := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if thenNode < 0 {
            return -1
        }

        if st.Pos >= count || tokenKinds[st.Pos] != 122 {
            return -1
        }
        st.Pos = st.Pos + 1

        elseNode := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
        if elseNode < 0 {
            return -1
        }

        elseSpanEnd := nodes.SpanStarts[elseNode] + nodes.SpanLengths[elseNode]
        childRunStart := st.ChildCursor
        AppendExpressionChild(ref st, ref children, condition)
        AppendExpressionChild(ref st, ref children, thenNode)
        AppendExpressionChild(ref st, ref children, elseNode)
        return EmitExpressionNode(ref st, ref nodes, 13, -1, 0, childRunStart, 3, conditionSpanStart, elseSpanEnd - conditionSpanStart)
    }

    return condition
}

// ParseAssignmentExpression (Parser.cs:3599): a ternary target, optionally followed by an assignment
// operator (= += -= *= /= ??=) and a right-hand value (AssignmentExpression, kind 14, operator token in the
// value span, children [target, value]). Right-associative: the value recurses to the assignment level, so
// a = b = c parses as a = (b = c). The full-expression entry is ParseLambdaOrAssignmentExpressionNode (the
// lambda level above this one).
func ParseAssignmentExpressionNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    if depth > 200 {
        return -1
    }

    target := ParseTernaryExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
    if target < 0 {
        return -1
    }

    if st.Pos < count {
        op := tokenKinds[st.Pos]
        if op == 93 || op == 94 || op == 95 || op == 96 || op == 97 || op == 117 {
            opStart := tokenStarts[st.Pos]
            opLength := tokenValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            value := ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
            if value < 0 {
                return -1
            }

            targetSpanStart := nodes.SpanStarts[target]
            valueSpanEnd := nodes.SpanStarts[value] + nodes.SpanLengths[value]
            childRunStart := st.ChildCursor
            AppendExpressionChild(ref st, ref children, target)
            AppendExpressionChild(ref st, ref children, value)
            return EmitExpressionNode(ref st, ref nodes, 14, opStart, opLength, childRunStart, 2, targetSpanStart, valueSpanEnd - targetSpanStart)
        }
    }

    return target
}

// ParseLambdaOrAssignmentExpression (Parser.cs:3660): LAMBDA literals sit at the level ABOVE assignment.
// Modeled shapes (Lambda kind 39, the `=>` token in the value span, children = [param Identifiers..., body]):
//   `x => expr`     -- a bare Identifier DIRECTLY followed by Arrow 120 (the Parser.cs:3672 lookahead);
//   `() => expr`    -- empty parenthesized list (`( ) =>`);
//   `(x, y) => expr`-- a parenthesized BARE-identifier list, committed via a pure speculative scan mirroring
//                      Parser.cs IsLambdaExpression (identifiers separated by commas to `)`, then `=>`) --
//                      anything else in the list (a type annotation `:`, a default, a non-identifier) falls
//                      through to the assignment level, where `(x, y)` refuses as an unmodeled tuple.
// The BODY is an expression parsed at THIS level (a lambda can return a lambda, as in the production
// ParseExpression recursion); a BLOCK body (`=> {`) makes the body parse refuse (-1) -- statement-bodied
// lambdas are a later rung, and the refusal declines the whole program (safe under-acceptance).
func ParseLambdaOrAssignmentExpressionNode(tokens: &ParserTokenTable, count: int, st: &ParserState, argStack: &ParserArgumentStack, nodes: &ParserExpressionNodeTable, children: &ParserChildIndexTable, depth: int): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    argStackValues := argStack.Values
    if depth > 200 {
        return -1
    }

    pos := st.Pos
    isLambda := false
    if pos + 1 < count && tokenKinds[pos] == 0 && tokenKinds[pos + 1] == 120 {
        isLambda = true
    } else if pos < count && tokenKinds[pos] == 127 {
        scan := pos + 1
        valid := true
        if scan < count && tokenKinds[scan] == 128 {
            scan = scan + 1
        } else {
            scanning := true
            while scanning {
                if scan >= count || tokenKinds[scan] != 0 {
                    valid = false
                    scanning = false
                } else {
                    scan = scan + 1
                    if scan < count && tokenKinds[scan] == 128 {
                        scan = scan + 1
                        scanning = false
                    } else if scan < count && tokenKinds[scan] == 134 {
                        scan = scan + 1
                    } else {
                        valid = false
                        scanning = false
                    }
                }
            }
        }
        if valid && scan < count && tokenKinds[scan] == 120 {
            isLambda = true
        }
    }

    if !isLambda {
        return ParseAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth)
    }

    spanStart := tokenStarts[st.Pos]
    argBase := st.ArgStackTop
    if tokenKinds[st.Pos] == 0 {
        paramNode := EmitExpressionNode(ref st, ref nodes, 6, tokenStarts[st.Pos], tokenValueLengths[st.Pos], -1, 0, tokenStarts[st.Pos], tokenValueLengths[st.Pos])
        argStackValues[st.ArgStackTop] = paramNode
        st.ArgStackTop = st.ArgStackTop + 1
        st.Pos = st.Pos + 1
    } else {
        st.Pos = st.Pos + 1
        while st.Pos < count && tokenKinds[st.Pos] != 128 {
            paramNode := EmitExpressionNode(ref st, ref nodes, 6, tokenStarts[st.Pos], tokenValueLengths[st.Pos], -1, 0, tokenStarts[st.Pos], tokenValueLengths[st.Pos])
            argStackValues[st.ArgStackTop] = paramNode
            st.ArgStackTop = st.ArgStackTop + 1
            st.Pos = st.Pos + 1
            if st.Pos < count && tokenKinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
            }
        }
        st.Pos = st.Pos + 1
    }

    arrowStart := tokenStarts[st.Pos]
    arrowLength := tokenValueLengths[st.Pos]
    st.Pos = st.Pos + 1

    // BLOCK body `x => { ... }`: a statement BLOCK (kind 25) parsed by the statement kernel — the two
    // kernels share the node table and the st/argStack conventions, and statements already call back into
    // expressions, so this is the same mutual recursion in the other direction. Otherwise the body is an
    // expression parsed at THIS level (a lambda can return a lambda).
    body := -1
    if st.Pos < count && tokenKinds[st.Pos] == 129 {
        body = ParseBlockStatementNodeCore(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
    } else {
        body = ParseLambdaOrAssignmentExpressionNode(ref tokens, count, ref st, ref argStack, ref nodes, ref children, depth + 1)
    }
    if body < 0 {
        st.ArgStackTop = argBase
        return -1
    }
    argStackValues[st.ArgStackTop] = body
    st.ArgStackTop = st.ArgStackTop + 1

    childRunStart := st.ChildCursor
    a := argBase
    while a < st.ArgStackTop {
        AppendExpressionChild(ref st, ref children, argStackValues[a])
        a = a + 1
    }
    childCount := st.ArgStackTop - argBase
    st.ArgStackTop = argBase
    bodySpanEnd := nodes.SpanStarts[body] + nodes.SpanLengths[body]
    return EmitExpressionNode(ref st, ref nodes, 39, arrowStart, arrowLength, childRunStart, childCount, spanStart, bodySpanEnd - spanStart)
}
