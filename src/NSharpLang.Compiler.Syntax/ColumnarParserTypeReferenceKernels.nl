import System.Text


// TYPE REFERENCES: the base/postfix/union type grammar and the canonical text it renders.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.

// Parser slice 6: the first N#-native RECURSIVE-DESCENT, tree-building parser kernel. Where slices 1-5
// produced flat top-level indices via single-pass token scans, this kernel implements the
// ParseTypeReference -> ParsePostfixTypeReference -> ParseBaseTypeReference recursion
// for the four dominant type-reference forms and emits a real parent->child AST as a flat columnar node
// table. It consumes the lexer's brace-inserted token kind/start/value-length arrays produced by
// TokenizeColumnarSourceInto and builds nodes in POST-ORDER (children before parents), so the
// root is the last node written.
//
// Supported forms (matching the concrete type-reference node ABI):
//   SimpleTypeReference   -> kind 0   e.g. int, string, A.B.C (dotted name folded to one name span)
//   GenericTypeReference  -> kind 1   e.g. List<int>, Dictionary<string, int>, List<List<int>>
//   ArrayTypeReference    -> kind 2   e.g. int[], List<int>[]
//   NullableTypeReference -> kind 3   e.g. int?, int?[] (=> Array(Nullable(inner)))
//   UnionTypeReference    -> kind 4   e.g. int | string, List<int> | string (slice 7; arms are postfix
//                                     types, and a union may itself be a generic argument: List<int | T>)
//   ByRefTypeReference    -> kind 5   e.g. &int, &List<int>, &int[] (slice 8; `&` prefixing a postfix type)
//   TupleTypeReference    -> kind 6   e.g. (int, int), (x: int, y: int) -- a `(` + >=2 comma-separated element
//                                     types + `)`. NAMED elements are ALL-OR-NOTHING (partial naming refuses,
//                                     the production-parser rule): each named element wraps in a kind 7 below.
//   NamedTupleElement     -> kind 7   `name: Type` inside a NAMED tuple type -- the element NAME in the name
//                                     slot, ONE child (the element type). Only ever a kind-6 child; canonicals
//                                     ERASE it (tuple identity is positional), the host extracts the names.
// Deferred to later rungs:
//   - FunctionTypeReference `Func<...>` -- this kernel has no source string (only token offsets),
//     so it cannot distinguish Func from any other
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
// Parser state is threaded through the recursion in a single caller-owned `ParserState` struct (a
// production parser state:
//   st.Pos = pos                 current token index
//   st.SplitGreaterDepth = splitGreaterDepth   owed `>` count from a split `>>` (RightShift) token
//   st.NodeCursor = nodeCursor          next free node-table slot
//   st.ChildCursor = childCursor         next free outChildIndices slot
//   st.OwedGreaterByteEnd = owedGreaterByteEnd  byte end of the owed second-half `>` while splitGreaterDepth > 0
//   st.ArgStackTop = argStackTop         top of the generic-argument id stack (see below)
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
class ParserState {
    Pos: int
    NodeCursor: int
    ChildCursor: int
    ArgStackTop: int
    SplitGreaterDepth: int
    OwedGreaterByteEnd: int
    // Source text for CONTEXTUAL keyword checks (e.g. `assert throws`). Optional: entries that
    // never need token text may leave it empty, in which case contextual forms simply do not
    // match (safe under-accept -> decline).
    Source: string
    // THE ONE TOKEN A `{` MAY NOT OPEN AN OBJECT INITIALIZER AT: the brace that opens a `using`
    // statement's BODY. `using r := new Res() { … }` is the shape the ambiguity lives in — the same
    // brace could close the resource or open the body — and the rule is the one Go and C# reach for:
    // the first `{` at paren/bracket depth zero after the resource belongs to the STATEMENT. It is
    // carried as a token INDEX rather than as a mode flag so nesting needs no bookkeeping: a brace
    // anywhere inside the expression sits at a different index and is untouched by construction.
    // -1 whenever no `using` header is being parsed.
    UsingBodyBrace: int
    constructor(pos: int, nodeCursor: int, childCursor: int, argStackTop: int, splitGreaterDepth: int, owedGreaterByteEnd: int, sourceText: string = "") {
        Pos = pos
        NodeCursor = nodeCursor
        ChildCursor = childCursor
        ArgStackTop = argStackTop
        SplitGreaterDepth = splitGreaterDepth
        OwedGreaterByteEnd = owedGreaterByteEnd
        Source = sourceText
        UsingBodyBrace = -1
    }
}

class ParserNodeTable {
    Kinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    SpanStarts: int[]
    SpanLengths: int[]
    constructor(kinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], spanStarts: int[], spanLengths: int[]) {
        Kinds = kinds
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        ChildStart = childStart
        ChildCount = childCount
        SpanStarts = spanStarts
        SpanLengths = spanLengths
    }
}

class ParserTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    // THE SOURCE TEXT THE OFFSETS INDEX INTO, so the kernels can answer "does this token begin a new
    // line". A postfix chain ends at a continuation token on a new line — the production parser's rule
    // (`Current().Line > Previous().Line` in `ParsePostfix`) — and without it `x => value` followed by
    // the NEXT member's `[Attribute]` reads as `value[Attribute]`. The compacted token stream this
    // table wraps has already dropped the newline tokens (kind 136), so the gap between the previous
    // token's end and this token's start is the only remaining witness. Null in the few kernels that
    // wrap a token run without the text; those never parse a postfix chain.
    Source: string?
    constructor(kinds: int[], starts: int[], valueLengths: int[], source: string? = null) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Source = source
    }
}

class ParserArgumentStack {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

class ParserChildIndexTable {
    Indices: int[]
    constructor(indices: int[]) {
        Indices = indices
    }
}

class ParserResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

class TypeReferenceCanonicalTable {
    Kinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    constructor(kinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], childIndices: int[]) {
        Kinds = kinds
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
    }
}

class TypeReferenceTupleNameTable {
    Names: string[]
    constructor(names: string[]) {
        Names = names
    }
}

// Consume one closing `>` for a generic argument list, including split `>>` handling:
// a single `>` (Greater 102) is consumed directly;
// a `>>` (RightShift 112) is consumed once but credits ONE owed `>` so the enclosing generic close uses the
// second half without advancing past a real token. Returns the byte end of the consumed `>`, or -1 on a
// missing close.

// ParseBaseTypeReference (Parser.cs:1828-1907) restricted to identifier-led Simple/Generic forms. Reads a
// (possibly dotted) name, then optional `<...>` generic arguments. Returns the emitted node id, or -1 on
// refusal/failure. Advances st.Pos past the consumed tokens.

// ParsePostfixTypeReference (Parser.cs:1758-1812): a base type followed by any run of `[]` (array), `?[]`
// (nullable array => Array(Nullable(inner))), and `?` (nullable) suffixes. Returns the outermost node id.

// ParseUnionTypeReference (Parser.cs:1718-1756): the top of the type grammar. A postfix type, optionally
// followed by `| postfix` arms; with at least one `|` it becomes a UnionTypeReference whose arms are the
// children (gathered on the LIFO arg-stack for contiguity, like generic args). With no `|` it returns the
// single postfix node unchanged. This is the level a generic argument and the top-level entry parse, so a
// union may appear as a generic argument (e.g. List<int | string>). Returns the node id, or -1.

func TypeReferenceCanonicalTextCore(source: string, nodes: TypeReferenceCanonicalTable, root: int): string {
    if root < 0 || root >= nodes.Kinds.Length {
        return "?"
    }

    kind := nodes.Kinds[root]
    if kind == 0 {
        return source.Substring(nodes.ValueStarts[root], nodes.ValueLengths[root])
    }

    if kind == 1 {
        builder := new StringBuilder(32)
        builder.Append(source.Substring(nodes.ValueStarts[root], nodes.ValueLengths[root]))
        builder.Append('<')
        run := nodes.ChildStart[root]
        i := 0
        while i < nodes.ChildCount[root] {
            if i > 0 {
                builder.Append(',')
            }

            builder.Append(TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[run + i]))
            i = i + 1
        }

        builder.Append('>')
        return builder.ToString()
    }

    if kind == 2 {
        return TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[nodes.ChildStart[root]]) + "[]"
    }

    if kind == 3 {
        return TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[nodes.ChildStart[root]]) + "?"
    }

    if kind == 4 {
        builder := new StringBuilder(32)
        run := nodes.ChildStart[root]
        i := 0
        while i < nodes.ChildCount[root] {
            if i > 0 {
                builder.Append('|')
            }

            builder.Append(TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[run + i]))
            i = i + 1
        }

        return builder.ToString()
    }

    if kind == 5 {
        return "&" + TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[nodes.ChildStart[root]])
    }

    if kind == 6 {
        builder := new StringBuilder(32)
        builder.Append('(')
        run := nodes.ChildStart[root]
        i := 0
        while i < nodes.ChildCount[root] {
            if i > 0 {
                builder.Append(',')
            }

            elem := nodes.ChildIndices[run + i]
            if nodes.Kinds[elem] == 7 {
                elem = nodes.ChildIndices[nodes.ChildStart[elem]]
            }

            builder.Append(TypeReferenceCanonicalTextCore(source, nodes, elem))
            i = i + 1
        }

        builder.Append(')')
        return builder.ToString()
    }

    return "?"
}

// The same spelling `TypeReferenceCanonicalTextCore` produces, except that a NAMED tuple element keeps
// its label: `(Min:int,Max:int)`, `(A:int,D:(B:int,C:int))`, `List<(Min:int,Max:int)>`. The structural
// canonical deliberately discards those labels, because a tuple's element names are metadata rather
// than identity -- but `TupleElementNamesAttribute` needs them at EVERY level, including inside a
// generic argument and inside a nested tuple, which is more than the top-level
// `TypeReferenceTupleElementNamesCore` list carries. `ColumnarTupleElementNames.Flatten` reads this
// form; nothing resolves a type from it.
func TypeReferenceLabeledCanonicalTextCore(source: string, nodes: TypeReferenceCanonicalTable, root: int): string {
    if root < 0 || root >= nodes.Kinds.Length {
        return "?"
    }

    kind := nodes.Kinds[root]
    if kind == 0 {
        return source.Substring(nodes.ValueStarts[root], nodes.ValueLengths[root])
    }

    if kind == 1 {
        builder := new StringBuilder(32)
        builder.Append(source.Substring(nodes.ValueStarts[root], nodes.ValueLengths[root]))
        builder.Append('<')
        run := nodes.ChildStart[root]
        i := 0
        while i < nodes.ChildCount[root] {
            if i > 0 {
                builder.Append(',')
            }

            builder.Append(TypeReferenceLabeledCanonicalTextCore(source, nodes, nodes.ChildIndices[run + i]))
            i = i + 1
        }

        builder.Append('>')
        return builder.ToString()
    }

    if kind == 2 {
        return TypeReferenceLabeledCanonicalTextCore(source, nodes, nodes.ChildIndices[nodes.ChildStart[root]]) + "[]"
    }

    if kind == 3 {
        return TypeReferenceLabeledCanonicalTextCore(source, nodes, nodes.ChildIndices[nodes.ChildStart[root]]) + "?"
    }

    if kind == 4 {
        builder := new StringBuilder(32)
        run := nodes.ChildStart[root]
        i := 0
        while i < nodes.ChildCount[root] {
            if i > 0 {
                builder.Append('|')
            }

            builder.Append(TypeReferenceLabeledCanonicalTextCore(source, nodes, nodes.ChildIndices[run + i]))
            i = i + 1
        }

        return builder.ToString()
    }

    if kind == 5 {
        return "&" + TypeReferenceLabeledCanonicalTextCore(source, nodes, nodes.ChildIndices[nodes.ChildStart[root]])
    }

    if kind == 6 {
        builder := new StringBuilder(32)
        builder.Append('(')
        run := nodes.ChildStart[root]
        i := 0
        while i < nodes.ChildCount[root] {
            if i > 0 {
                builder.Append(',')
            }

            elem := nodes.ChildIndices[run + i]
            if nodes.Kinds[elem] == 7 {
                builder.Append(source.Substring(nodes.ValueStarts[elem], nodes.ValueLengths[elem]))
                builder.Append(':')
                elem = nodes.ChildIndices[nodes.ChildStart[elem]]
            }

            builder.Append(TypeReferenceLabeledCanonicalTextCore(source, nodes, elem))
            i = i + 1
        }

        builder.Append(')')
        return builder.ToString()
    }

    return "?"
}

// The top-level tuple's element names in source order, one slot per element. An element the source
// left POSITIONAL contributes the empty string, which is the same "no name here" the CLR attribute
// spells as a null slot -- naming is decided per element, so `(string, string, IsConstructor: bool)`
// answers three slots of which only the last is filled. Zero means the type is not a tuple at all, or
// is a tuple with nothing named; no shape is an error any more.
func TypeReferenceTupleElementNamesCore(source: string, nodes: TypeReferenceCanonicalTable, root: int, names: TypeReferenceTupleNameTable): int {
    if root < 0 || root >= nodes.Kinds.Length || nodes.Kinds[root] != 6 || nodes.ChildCount[root] == 0 {
        return 0
    }

    run := nodes.ChildStart[root]
    named := false
    i := 0
    while i < nodes.ChildCount[root] {
        elem := nodes.ChildIndices[run + i]
        if nodes.Kinds[elem] == 7 {
            names.Names[i] = source.Substring(nodes.ValueStarts[elem], nodes.ValueLengths[elem])
            named = true
        } else {
            names.Names[i] = ""
        }

        i = i + 1
    }

    if !named {
        return 0
    }

    return nodes.ChildCount[root]
}

func EmitTypeReferenceNode(st: ParserState, nodes: ParserNodeTable, kind: int, nameStart: int, nameLength: int, childStart: int, childCount: int, spanStart: int, spanLength: int): int {
    id := st.NodeCursor
    nodes.Kinds[id] = kind
    nodes.ValueStarts[id] = nameStart
    nodes.ValueLengths[id] = nameLength
    nodes.ChildStart[id] = childStart
    nodes.ChildCount[id] = childCount
    nodes.SpanStarts[id] = spanStart
    nodes.SpanLengths[id] = spanLength
    st.NodeCursor = id + 1
    return id
}

func AppendTypeReferenceChild(st: ParserState, outChildIndices: ParserChildIndexTable, childId: int): int {
    slot := st.ChildCursor
    outChildIndices.Indices[slot] = childId
    st.ChildCursor = slot + 1
    return slot
}

func ConsumeGreaterForTypeNodeCore(tokens: ParserTokenTable, count: int, st: ParserState): int {
    if st.SplitGreaterDepth > 0 {
        st.SplitGreaterDepth = st.SplitGreaterDepth - 1
        return st.OwedGreaterByteEnd
    }

    pos := st.Pos
    if pos < count && tokens.Kinds[pos] == 102 {
        st.Pos = pos + 1
        return tokens.Starts[pos] + tokens.ValueLengths[pos]
    }

    if pos < count && tokens.Kinds[pos] == 112 {
        st.Pos = pos + 1
        st.SplitGreaterDepth = st.SplitGreaterDepth + 1
        st.OwedGreaterByteEnd = tokens.Starts[pos] + 2
        return tokens.Starts[pos] + 1
    }

    return -1
}

func ParseBaseTypeReferenceNodeCore(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserNodeTable, outChildIndices: ParserChildIndexTable, depth: int): int {
    if depth > 64 {
        return -1
    }

    pos := st.Pos
    if pos >= count {
        return -1
    }

    // ByRef `&T`: `&` prefixing a postfix type. A byref can appear wherever a base type can
    // (a union arm, a generic argument). depth+1 bounds the degenerate `& & T` chain.
    if tokens.Kinds[pos] == 107 {
        ampStart := tokens.Starts[pos]
        st.Pos = pos + 1
        inner := ParsePostfixTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
        if inner < 0 {
            return -1
        }

        spanEnd := nodes.SpanStarts[inner] + nodes.SpanLengths[inner]
        childRunStart := st.ChildCursor
        AppendTypeReferenceChild(st, outChildIndices, inner)
        return EmitTypeReferenceNode(st, nodes, 5, -1, 0, childRunStart, 1, ampStart, spanEnd - ampStart)
    }

    // Tuple type `(T0, T1, ...)` (TupleTypeReference -> kind 6): a `(` introducing a comma-separated list of at
    // least TWO postfix/union element types, closed by `)`. A single `(T)` is not a tuple (no comma) -> refuse.
    // Variable arity via the LIFO arg-stack, exactly like the generic argument list.
    //
    // A NAMED element `x: int` wraps its element type in a NamedTupleElement node (kind 7, the element NAME
    // in the name slot, ONE child = the element type), and naming is decided PER ELEMENT: the production
    // parser takes each `Identifier :` prefix on its own, so `(string, string, IsConstructor: bool)` is an
    // ordinary three-element tuple type whose third element is named, and the all-or-nothing reading this
    // replaced declined the whole enclosing function for it. Names are ERASED from canonicals (tuple identity
    // is positional -- .NET semantics); the host extracts them for the emitter's name->ItemN member mapping.
    if tokens.Kinds[pos] == 127 {
        tupleTypeStart := tokens.Starts[pos]
        st.Pos = pos + 1
        tupleArgBase := st.ArgStackTop

        firstElemNameStart := 0 - 1
        firstElemNameLength := 0
        firstElemNamed := st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122
        if firstElemNamed {
            firstElemNameStart = tokens.Starts[st.Pos]
            firstElemNameLength = tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 2
        }

        firstElem := ParseUnionTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
        if firstElem < 0 {
            st.ArgStackTop = tupleArgBase
            return -1
        }

        if firstElemNamed {
            firstWrapRun := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, firstElem)
            firstElem = EmitTypeReferenceNode(st, nodes, 7, firstElemNameStart, firstElemNameLength, firstWrapRun, 1, firstElemNameStart, nodes.SpanStarts[firstElem] + nodes.SpanLengths[firstElem] - firstElemNameStart)
        }

        argStack.Values[st.ArgStackTop] = firstElem
        st.ArgStackTop = st.ArgStackTop + 1

        if st.Pos >= count || tokens.Kinds[st.Pos] != 134 {
            st.ArgStackTop = tupleArgBase
            return -1
        }

        while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
            st.Pos = st.Pos + 1
            elemNameStart := 0 - 1
            elemNameLength := 0
            elemNamed := st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122
            if elemNamed {
                elemNameStart = tokens.Starts[st.Pos]
                elemNameLength = tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 2
            }

            nextElem := ParseUnionTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
            if nextElem < 0 {
                st.ArgStackTop = tupleArgBase
                return -1
            }

            if elemNamed {
                wrapRun := st.ChildCursor
                AppendTypeReferenceChild(st, outChildIndices, nextElem)
                nextElem = EmitTypeReferenceNode(st, nodes, 7, elemNameStart, elemNameLength, wrapRun, 1, elemNameStart, nodes.SpanStarts[nextElem] + nodes.SpanLengths[nextElem] - elemNameStart)
            }

            argStack.Values[st.ArgStackTop] = nextElem
            st.ArgStackTop = st.ArgStackTop + 1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
            st.ArgStackTop = tupleArgBase
            return -1
        }

        tupleRightParenEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        tupleChildCount := st.ArgStackTop - tupleArgBase
        tupleChildRunStart := st.ChildCursor
        tupleElemIdx := tupleArgBase
        while tupleElemIdx < st.ArgStackTop {
            AppendTypeReferenceChild(st, outChildIndices, argStack.Values[tupleElemIdx])
            tupleElemIdx = tupleElemIdx + 1
        }

        st.ArgStackTop = tupleArgBase

        return EmitTypeReferenceNode(st, nodes, 6, -1, 0, tupleChildRunStart, tupleChildCount, tupleTypeStart, tupleRightParenEnd - tupleTypeStart)
    }

    if tokens.Kinds[pos] != 0 {
        return -1
    }

    nameStart := tokens.Starts[pos]
    nameEnd := tokens.Starts[pos] + tokens.ValueLengths[pos]
    pos = pos + 1

    while pos + 1 < count && tokens.Kinds[pos] == 124 && tokens.Kinds[pos + 1] == 0 {
        nameEnd = tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]
        pos = pos + 2
    }

    st.Pos = pos

    if pos < count && tokens.Kinds[pos] == 100 {
        st.Pos = pos + 1
        argBase := st.ArgStackTop

        firstArg := ParseUnionTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
        if firstArg < 0 {
            return -1
        }

        argStack.Values[st.ArgStackTop] = firstArg
        st.ArgStackTop = st.ArgStackTop + 1

        // While a `>` is owed from a split `>>` (st.SplitGreaterDepth > 0), the owed `>` is the
        // effective current token — the raw cursor already sits PAST the `>>`, so reading it here
        // would let a following `,` (e.g. a parameter separator after `Dict<a, Dict<b, c>>`) be
        // consumed as another type argument. The owed close must reach ConsumeGreaterForTypeNodeCore.
        while st.SplitGreaterDepth == 0 && st.Pos < count && tokens.Kinds[st.Pos] == 134 {
            st.Pos = st.Pos + 1
            nextArg := ParseUnionTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
            if nextArg < 0 {
                return -1
            }

            argStack.Values[st.ArgStackTop] = nextArg
            st.ArgStackTop = st.ArgStackTop + 1
        }

        greaterEnd := ConsumeGreaterForTypeNodeCore(tokens, count, st)
        if greaterEnd < 0 {
            return -1
        }

        childCount := st.ArgStackTop - argBase
        childRunStart := st.ChildCursor
        a := argBase
        while a < st.ArgStackTop {
            AppendTypeReferenceChild(st, outChildIndices, argStack.Values[a])
            a = a + 1
        }

        st.ArgStackTop = argBase

        return EmitTypeReferenceNode(st, nodes, 1, nameStart, nameEnd - nameStart, childRunStart, childCount, nameStart, greaterEnd - nameStart)
    }

    return EmitTypeReferenceNode(st, nodes, 0, nameStart, nameEnd - nameStart, -1, 0, nameStart, nameEnd - nameStart)
}

func ParsePostfixTypeReferenceNodeCore(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserNodeTable, outChildIndices: ParserChildIndexTable, depth: int): int {
    baseNode := ParseBaseTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth)
    if baseNode < 0 {
        return -1
    }

    // A base type whose last generic close split a `>>` still owes the enclosing generic a `>` —
    // the owed `>` is the effective current token, so no suffix can follow HERE. Reading the raw
    // cursor would bind a `?` after `Dict<a, List<b>>?` to the INNER type (the recovery parser had
    // the same desync). The suffix belongs to the ENCLOSING type after its ConsumeGreater.
    matched := st.SplitGreaterDepth == 0
    while matched {
        pos := st.Pos

        if pos + 1 < count && tokens.Kinds[pos] == 131 && tokens.Kinds[pos + 1] == 132 {
            spanStart := nodes.SpanStarts[baseNode]
            rightBracketEnd := tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]
            childRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, baseNode)
            baseNode = EmitTypeReferenceNode(st, nodes, 2, -1, 0, childRunStart, 1, spanStart, rightBracketEnd - spanStart)
            st.Pos = pos + 2
        } else if pos + 1 < count && tokens.Kinds[pos] == 119 && tokens.Kinds[pos + 1] == 132 {
            spanStart := nodes.SpanStarts[baseNode]
            questionBracketStart := tokens.Starts[pos]
            rightBracketEnd := tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]

            nullableRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, baseNode)
            nullableNode := EmitTypeReferenceNode(st, nodes, 3, -1, 0, nullableRunStart, 1, spanStart, (questionBracketStart + 1) - spanStart)

            arrayRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, nullableNode)
            baseNode = EmitTypeReferenceNode(st, nodes, 2, -1, 0, arrayRunStart, 1, spanStart, rightBracketEnd - spanStart)
            st.Pos = pos + 2
        } else if pos < count && tokens.Kinds[pos] == 115 {
            spanStart := nodes.SpanStarts[baseNode]
            questionEnd := tokens.Starts[pos] + tokens.ValueLengths[pos]
            childRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, baseNode)
            baseNode = EmitTypeReferenceNode(st, nodes, 3, -1, 0, childRunStart, 1, spanStart, questionEnd - spanStart)
            st.Pos = pos + 1
        } else {
            matched = false
        }
    }

    return baseNode
}

func ParseUnionTypeReferenceNodeCore(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserNodeTable, outChildIndices: ParserChildIndexTable, depth: int): int {
    firstArm := ParsePostfixTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth)
    if firstArm < 0 {
        return -1
    }

    // Same owed-`>` discipline as the postfix suffixes: while st.SplitGreaterDepth > 0 the effective
    // current token is the owed `>`, never a union `|`.
    if !(st.SplitGreaterDepth == 0 && st.Pos < count && tokens.Kinds[st.Pos] == 108) {
        return firstArm
    }

    argBase := st.ArgStackTop
    argStack.Values[st.ArgStackTop] = firstArm
    st.ArgStackTop = st.ArgStackTop + 1

    while st.SplitGreaterDepth == 0 && st.Pos < count && tokens.Kinds[st.Pos] == 108 {
        st.Pos = st.Pos + 1
        nextArm := ParsePostfixTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth)
        if nextArm < 0 {
            return -1
        }

        argStack.Values[st.ArgStackTop] = nextArm
        st.ArgStackTop = st.ArgStackTop + 1
    }

    lastArm := argStack.Values[st.ArgStackTop - 1]
    childCount := st.ArgStackTop - argBase
    childRunStart := st.ChildCursor
    a := argBase
    while a < st.ArgStackTop {
        AppendTypeReferenceChild(st, outChildIndices, argStack.Values[a])
        a = a + 1
    }

    st.ArgStackTop = argBase

    spanStart := nodes.SpanStarts[firstArm]
    spanEnd := nodes.SpanStarts[lastArm] + nodes.SpanLengths[lastArm]
    return EmitTypeReferenceNode(st, nodes, 4, -1, 0, childRunStart, childCount, spanStart, spanEnd - spanStart)
}
