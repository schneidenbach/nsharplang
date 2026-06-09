// Parser slice 6: the first N#-native RECURSIVE-DESCENT, tree-building parser kernel. Where slices 1-5
// produced flat top-level indices via single-pass token scans, this kernel reproduces the C# parser's
// ParseTypeReference -> ParsePostfixTypeReference -> ParseBaseTypeReference recursion (Parser.cs:1718-1907)
// for the four dominant type-reference forms and emits a real parent->child AST as a flat columnar node
// table. It consumes the lexer's token kind/start/value-length arrays (the output of
// TokenizeMetadataWithIndentationInto) and builds nodes in POST-ORDER (children before parents), so the
// root is the last node written.
//
// Supported forms (matching the concrete C# TypeReference nodes):
//   SimpleTypeReference   -> kind 0   e.g. int, string, A.B.C (dotted name folded to one name span)
//   GenericTypeReference  -> kind 1   e.g. List<int>, Dictionary<string, int>, List<List<int>>
//   ArrayTypeReference    -> kind 2   e.g. int[], List<int>[]
//   NullableTypeReference -> kind 3   e.g. int?, int?[] (=> Array(Nullable(inner)))
//   UnionTypeReference    -> kind 4   e.g. int | string, List<int> | string (slice 7; arms are postfix
//                                     types, and a union may itself be a generic argument: List<int | T>)
//   ByRefTypeReference    -> kind 5   e.g. &int, &List<int>, &int[] (slice 8; `&` prefixing a postfix type)
//   TupleTypeReference    -> kind 6   e.g. (int, int), (int, string)[] -- a `(` + >=2 comma-separated element
//                                     types + `)`. POSITIONAL only (named elements `(x: int, ...)` refuse).
// Deferred to later rungs:
//   - NAMED tuple elements `(x: int, ...)` -- the columnar table does not yet carry per-element name metadata.
//   - FunctionTypeReference `Func<...>` -- the C# parser special-cases the *identifier text* "Func", but
//     this kernel has no source string (only token offsets), so it cannot distinguish Func from any other
//     generic name; Func is therefore excluded from the corpus and will parse as a Generic node. Resolving
//     it needs the parser to gain source access (a later architectural step that also unlocks name-based
//     contextual keywords).
//
// Node-table columns (all caller-allocated to capacity >= count+1; outChildIndices likewise):
//   outNodeKinds[i]   : 0 Simple | 1 Generic | 2 Array | 3 Nullable | 4 Union | 5 ByRef | 6 Tuple
//   outNameStarts[i]  : source byte offset of the (dotted) name for Simple/Generic; -1 otherwise
//   outNameLengths[i] : name byte length; 0 when no name
//   outChildStart[i]  : index into outChildIndices where this node's child ids begin; -1 when no children
//   outChildCount[i]  : Generic = #type args; Union = #arms (>= 2); Array/Nullable/ByRef = 1; Simple = 0
//   outChildIndices[] : flattened child node-id pointers (the tree edges); each node's children occupy a
//                       CONTIGUOUS run (see the arg-stack note below)
//   outSpanStarts[i]  : source byte offset where the node's full text begins
//   outSpanLengths[i] : byte length of the node's full text (so source.Substring(start,len) is the type)
//   outResult[0]      : root node id (== nodeCount-1 by the post-order convention)
//   outResult[1]      : token index one past the consumed type (the caller's continuation cursor)
// Returns the number of nodes written, or -1 on refusal (non-identifier first token), parse failure
// (e.g. an unterminated generic), or generic-nesting depth > 64.
//
// Parser state is threaded through the recursion in a single caller-owned int[] `st` (a faithful analogue
// of the C# Parser's mutable _position / _splitGreaterDepth fields):
//   st[0] = pos                 current token index
//   st[4] = splitGreaterDepth   owed `>` count from a split `>>` (RightShift) token
//   st[1] = nodeCursor          next free node-table slot
//   st[2] = childCursor         next free outChildIndices slot
//   st[5] = owedGreaterByteEnd  byte end of the owed second-half `>` while splitGreaterDepth > 0
//   st[3] = argStackTop         top of the generic-argument id stack (see below)
//
// Generic arguments are gathered onto a shared LIFO `argStack` rather than appended to outChildIndices as
// they are parsed: a nested generic argument appends ITS OWN children during parsing, which would otherwise
// interleave with and fragment the outer generic's contiguous child run. Because recursion is LIFO, each
// generic records the stack top on entry, pushes each parsed argument id, then -- only after the whole
// argument list and the closing `>` are consumed -- appends that contiguous block of ids to outChildIndices
// and pops the stack. This keeps every node's children contiguous in outChildIndices with a single
// allocation per top-level parse.
//
// TokenType ordinals used (from Token.cs, sequential, zero-based): Identifier 0, Less 100, Greater 102,
// BitwiseAnd 107, BitwiseOr 108, RightShift 112, Question 115, QuestionBracket 119, Dot 124,
// LeftParen 127, LeftBracket 131, RightBracket 132, Comma 134.

func EmitTypeReferenceNode(st: int[], outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outSpanStarts: int[], outSpanLengths: int[], kind: int, nameStart: int, nameLength: int, childStart: int, childCount: int, spanStart: int, spanLength: int): int {
    id := st[1]
    outNodeKinds[id] = kind
    outNameStarts[id] = nameStart
    outNameLengths[id] = nameLength
    outChildStart[id] = childStart
    outChildCount[id] = childCount
    outSpanStarts[id] = spanStart
    outSpanLengths[id] = spanLength
    st[1] = id + 1
    return id
}

func AppendTypeReferenceChild(st: int[], outChildIndices: int[], childId: int): int {
    slot := st[2]
    outChildIndices[slot] = childId
    st[2] = slot + 1
    return slot
}

// Consume one closing `>` for a generic argument list, mirroring C# ConsumeGreater + the _splitGreaterDepth
// mechanism (Parser.cs:2047-2065, 5918-5932, 6083-6091): a single `>` (Greater 102) is consumed directly;
// a `>>` (RightShift 112) is consumed once but credits ONE owed `>` so the enclosing generic close uses the
// second half without advancing past a real token. Returns the byte end of the consumed `>`, or -1 on a
// missing close.
func ConsumeGreaterForTypeNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[]): int {
    if st[4] > 0 {
        st[4] = st[4] - 1
        return st[5]
    }

    pos := st[0]
    if pos < count && tokenKinds[pos] == 102 {
        st[0] = pos + 1
        return tokenStarts[pos] + tokenValueLengths[pos]
    }

    if pos < count && tokenKinds[pos] == 112 {
        st[0] = pos + 1
        st[4] = st[4] + 1
        st[5] = tokenStarts[pos] + 2
        return tokenStarts[pos] + 1
    }

    return -1
}

// ParseBaseTypeReference (Parser.cs:1828-1907) restricted to identifier-led Simple/Generic forms. Reads a
// (possibly dotted) name, then optional `<...>` generic arguments. Returns the emitted node id, or -1 on
// refusal/failure. Advances st[0] past the consumed tokens.
func ParseBaseTypeReferenceNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    if depth > 64 {
        return -1
    }

    pos := st[0]
    if pos >= count {
        return -1
    }

    // ByRef `&T` (Parser.cs:1830-1840): `&` prefixing a postfix type. The C# parser puts this in
    // ParseBaseTypeReference, so a byref can appear wherever a base type can (a union arm, a generic
    // argument). depth+1 bounds the (degenerate) `& & T` chain even though the C# parser does not cap it.
    if tokenKinds[pos] == 107 {
        ampStart := tokenStarts[pos]
        st[0] = pos + 1
        inner := ParsePostfixTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if inner < 0 {
            return -1
        }

        spanEnd := outSpanStarts[inner] + outSpanLengths[inner]
        childRunStart := st[2]
        AppendTypeReferenceChild(st, outChildIndices, inner)
        return EmitTypeReferenceNode(st, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 5, -1, 0, childRunStart, 1, ampStart, spanEnd - ampStart)
    }

    // Tuple type `(T0, T1, ...)` (TupleTypeReference -> kind 6): a `(` introducing a comma-separated list of at
    // least TWO postfix/union element types, closed by `)`. Positional only (named elements `(x: int, ...)` are
    // not modelled -- the `:` after the first element makes the comma form refuse). A single `(T)` is not a tuple
    // (no comma) -> refuse. Variable arity via the LIFO arg-stack, exactly like the generic argument list.
    if tokenKinds[pos] == 127 {
        tupleTypeStart := tokenStarts[pos]
        st[0] = pos + 1
        tupleArgBase := st[3]

        firstElem := ParseUnionTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if firstElem < 0 {
            st[3] = tupleArgBase
            return -1
        }

        argStack[st[3]] = firstElem
        st[3] = st[3] + 1

        if st[0] >= count || tokenKinds[st[0]] != 134 {
            st[3] = tupleArgBase
            return -1
        }

        while st[0] < count && tokenKinds[st[0]] == 134 {
            st[0] = st[0] + 1
            nextElem := ParseUnionTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
            if nextElem < 0 {
                st[3] = tupleArgBase
                return -1
            }

            argStack[st[3]] = nextElem
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
        tupleElemIdx := tupleArgBase
        while tupleElemIdx < st[3] {
            AppendTypeReferenceChild(st, outChildIndices, argStack[tupleElemIdx])
            tupleElemIdx = tupleElemIdx + 1
        }
        st[3] = tupleArgBase

        return EmitTypeReferenceNode(st, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 6, -1, 0, tupleChildRunStart, tupleChildCount, tupleTypeStart, tupleRightParenEnd - tupleTypeStart)
    }

    if tokenKinds[pos] != 0 {
        return -1
    }

    nameStart := tokenStarts[pos]
    nameEnd := tokenStarts[pos] + tokenValueLengths[pos]
    pos = pos + 1

    while pos + 1 < count && tokenKinds[pos] == 124 && tokenKinds[pos + 1] == 0 {
        nameEnd = tokenStarts[pos + 1] + tokenValueLengths[pos + 1]
        pos = pos + 2
    }

    st[0] = pos

    if pos < count && tokenKinds[pos] == 100 {
        st[0] = pos + 1
        argBase := st[3]

        firstArg := ParseUnionTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
        if firstArg < 0 {
            return -1
        }

        argStack[st[3]] = firstArg
        st[3] = st[3] + 1

        while st[0] < count && tokenKinds[st[0]] == 134 {
            st[0] = st[0] + 1
            nextArg := ParseUnionTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth + 1)
            if nextArg < 0 {
                return -1
            }

            argStack[st[3]] = nextArg
            st[3] = st[3] + 1
        }

        greaterEnd := ConsumeGreaterForTypeNode(tokenKinds, tokenStarts, tokenValueLengths, count, st)
        if greaterEnd < 0 {
            return -1
        }

        childCount := st[3] - argBase
        childRunStart := st[2]
        a := argBase
        while a < st[3] {
            AppendTypeReferenceChild(st, outChildIndices, argStack[a])
            a = a + 1
        }
        st[3] = argBase

        return EmitTypeReferenceNode(st, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 1, nameStart, nameEnd - nameStart, childRunStart, childCount, nameStart, greaterEnd - nameStart)
    }

    return EmitTypeReferenceNode(st, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 0, nameStart, nameEnd - nameStart, -1, 0, nameStart, nameEnd - nameStart)
}

// ParsePostfixTypeReference (Parser.cs:1758-1812): a base type followed by any run of `[]` (array), `?[]`
// (nullable array => Array(Nullable(inner))), and `?` (nullable) suffixes. Returns the outermost node id.
func ParsePostfixTypeReferenceNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    baseNode := ParseBaseTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth)
    if baseNode < 0 {
        return -1
    }

    matched := true
    while matched {
        pos := st[0]

        if pos + 1 < count && tokenKinds[pos] == 131 && tokenKinds[pos + 1] == 132 {
            spanStart := outSpanStarts[baseNode]
            rightBracketEnd := tokenStarts[pos + 1] + tokenValueLengths[pos + 1]
            childRunStart := st[2]
            AppendTypeReferenceChild(st, outChildIndices, baseNode)
            baseNode = EmitTypeReferenceNode(st, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 2, -1, 0, childRunStart, 1, spanStart, rightBracketEnd - spanStart)
            st[0] = pos + 2
        } else if pos + 1 < count && tokenKinds[pos] == 119 && tokenKinds[pos + 1] == 132 {
            spanStart := outSpanStarts[baseNode]
            questionBracketStart := tokenStarts[pos]
            rightBracketEnd := tokenStarts[pos + 1] + tokenValueLengths[pos + 1]

            nullableRunStart := st[2]
            AppendTypeReferenceChild(st, outChildIndices, baseNode)
            nullableNode := EmitTypeReferenceNode(st, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 3, -1, 0, nullableRunStart, 1, spanStart, (questionBracketStart + 1) - spanStart)

            arrayRunStart := st[2]
            AppendTypeReferenceChild(st, outChildIndices, nullableNode)
            baseNode = EmitTypeReferenceNode(st, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 2, -1, 0, arrayRunStart, 1, spanStart, rightBracketEnd - spanStart)
            st[0] = pos + 2
        } else if pos < count && tokenKinds[pos] == 115 {
            spanStart := outSpanStarts[baseNode]
            questionEnd := tokenStarts[pos] + tokenValueLengths[pos]
            childRunStart := st[2]
            AppendTypeReferenceChild(st, outChildIndices, baseNode)
            baseNode = EmitTypeReferenceNode(st, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 3, -1, 0, childRunStart, 1, spanStart, questionEnd - spanStart)
            st[0] = pos + 1
        } else {
            matched = false
        }
    }

    return baseNode
}

// ParseUnionTypeReference (Parser.cs:1718-1756): the top of the type grammar. A postfix type, optionally
// followed by `| postfix` arms; with at least one `|` it becomes a UnionTypeReference whose arms are the
// children (gathered on the LIFO arg-stack for contiguity, like generic args). With no `|` it returns the
// single postfix node unchanged. This is the level a generic argument and the top-level entry parse, so a
// union may appear as a generic argument (e.g. List<int | string>). Returns the node id, or -1.
func ParseUnionTypeReferenceNode(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, st: int[], argStack: int[], outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], depth: int): int {
    firstArm := ParsePostfixTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth)
    if firstArm < 0 {
        return -1
    }

    if !(st[0] < count && tokenKinds[st[0]] == 108) {
        return firstArm
    }

    argBase := st[3]
    argStack[st[3]] = firstArm
    st[3] = st[3] + 1

    while st[0] < count && tokenKinds[st[0]] == 108 {
        st[0] = st[0] + 1
        nextArm := ParsePostfixTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, depth)
        if nextArm < 0 {
            return -1
        }

        argStack[st[3]] = nextArm
        st[3] = st[3] + 1
    }

    lastArm := argStack[st[3] - 1]
    childCount := st[3] - argBase
    childRunStart := st[2]
    a := argBase
    while a < st[3] {
        AppendTypeReferenceChild(st, outChildIndices, argStack[a])
        a = a + 1
    }
    st[3] = argBase

    spanStart := outSpanStarts[firstArm]
    spanEnd := outSpanStarts[lastArm] + outSpanLengths[lastArm]
    return EmitTypeReferenceNode(st, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths, 4, -1, 0, childRunStart, childCount, spanStart, spanEnd - spanStart)
}

func ParseTypeReferenceNodesInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, start: int, outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    st := new int[](6)
    st[0] = start
    st[4] = 0
    st[1] = 0
    st[2] = 0
    st[5] = 0
    st[3] = 0
    argStack := new int[](count + 1)

    root := ParseUnionTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
    if root < 0 {
        return -1
    }

    outResult[0] = root
    outResult[1] = st[0]
    return st[1]
}
