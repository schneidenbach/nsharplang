// Parser slice 9: the first declaration-level recursive-descent kernel -- it COMPOSES the slice 6-8 type
// kernel (ParserTypeReferences.nl). Given a `func` keyword token index, ParseFunctionSignatureInto parses
// the function's signature -- name, parameter names + parameter type trees, and the return type tree --
// mirroring the C# parser's ParseFunctionDeclaration / ParseParameterList (Parser.cs:405-535, 770-840).
// All parameter type trees and the return type tree share ONE columnar node table (the same table the
// type kernel fills), so each is an independent root within it; the shared `ParserState` (`st`) carries
// the node/child cursors across the per-type parses while st.Pos (pos) is repositioned to each type's start.
//
// Scope this slice: parameter NAME + parameter TYPE (any form the type kernel supports: Simple / Generic /
// Array / Nullable / Union / ByRef), the `: ReturnType` return type (or none), an optional generic
// TYPE-PARAMETER list `<T, U>` between the name and `(` — each type parameter is a bare Identifier (an
// inline constraint `<T: Base>` or any non-identifier form returns -1) — and zero or more generic
// CONSTRAINT clauses `where T: Item, Item ...` after the return type (D-17b). Each constraint ITEM is
// recorded as a flat row: the owning type parameter's name span plus a code — a type-tree ROOT (>= 0)
// parsed into the shared node table, or a special-constraint sentinel (-2 `class`, -3 `struct`,
// -4 `new()`). Clause grouping is NOT preserved (the host groups rows by owner name, mirroring the C#
// parser's per-clause GenericConstraint records which the analyzer also flattens per parameter).
// Parameter modifiers (`ref` 78, `out` 79, `params` 82, `this` 42) and attribute lists `[...]` are
// skipped; a `= default` value is skipped (balanced) without being parsed (expression parsing is a later
// rung).
// Deferred (the corpus avoids them): `->` return-type syntax, scoped/lifetime parameter annotations,
// expression-bodied functions, and materializing default values.
//
// Output:
//   outNodeKinds/... (8 columns) + outChildIndices : the shared type node table (see ParserTypeReferences.nl)
//   outParamNameStarts[p], outParamNameLengths[p]  : byte span of parameter p's name
//   outParamTypeRoots[p]                            : node id of parameter p's type tree root
//   outTypeParamStarts[t], outTypeParamLengths[t]   : byte span of generic type parameter t's name
//   outWhereNameStarts[w], outWhereNameLengths[w]   : byte span of constraint row w's OWNER type-param name
//   outWhereItemCodes[w]                            : row w's constraint — a type root (>= 0) or a special
//                                                     sentinel (-2 class, -3 struct, -4 new())
//   outResult[0] = parameter count
//   outResult[1] = return type tree root node id, or -1 when the function has no return type
//   outResult[2] = total node count written to the shared table
//   outResult[3], outResult[4] = byte span (start, length) of the function name (start -1 if anonymous)
//   outResult[5] = generic type-parameter count (0 for a non-generic function)
//   outResult[6] = the token index immediately AFTER the parsed signature (after the `where` clauses when
//                  any exist, else after the return type / the `)`), so the host can verify what follows
//                  (the body `{`, a ctor `: this/base` initializer, or an unmodelled `=>` body to decline)
//   outResult[7] = constraint row count (0 for a function with no `where` clauses)
// Returns the parameter count, or -1 on a malformed signature / a parameter type the type kernel refuses.
//
// TokenType ordinals (Token.cs): Identifier 0, This 42, Ref 78, Out 79, Params 82, Assign 93, Func 7,
// New 41, Where 53, Class 8, Struct 9, Less 100, Greater 102, Colon 122, Comma 134, LeftParen 127,
// RightParen 128, LeftBrace 129, RightBrace 130, LeftBracket 131, RightBracket 132.

func ParseFunctionSignatureInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outParamNameStarts: int[], outParamNameLengths: int[], outParamTypeRoots: int[], outTypeParamStarts: int[], outTypeParamLengths: int[], outWhereNameStarts: int[], outWhereNameLengths: int[], outWhereItemCodes: int[], outResult: int[]): int {
    tokens := new ParserTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    typeStack := new ParserArgumentStack { Values: new int[](count + 1) }
    nodes := new ParserNodeTable { Kinds: outNodeKinds, ValueStarts: outNameStarts, ValueLengths: outNameLengths, ChildStart: outChildStart, ChildCount: outChildCount, SpanStarts: outSpanStarts, SpanLengths: outSpanLengths }
    children := new ParserChildIndexTable { Indices: outChildIndices }
    parameters := new ParserFunctionParameterTable { NameStarts: outParamNameStarts, NameLengths: outParamNameLengths, TypeRoots: outParamTypeRoots }
    typeParams := new ParserFunctionTypeParameterTable { Starts: outTypeParamStarts, Lengths: outTypeParamLengths }
    whereItems := new ParserFunctionWhereTable { NameStarts: outWhereNameStarts, NameLengths: outWhereNameLengths, ItemCodes: outWhereItemCodes }
    result := new ParserResultTable { Values: outResult }
    return ParseFunctionSignatureCore(ref tokens, count, funcIndex, ref typeStack, ref nodes, ref children, ref parameters, ref typeParams, ref whereItems, ref result)
}

func FunctionSignatureWhereOwnerIndicesInto(source: string, typeParamStarts: int[], typeParamLengths: int[], typeParamCount: int, whereNameStarts: int[], whereNameLengths: int[], whereItemCount: int, outOwnerIndices: int[]): int {
    if typeParamCount < 0 || whereItemCount < 0 || whereItemCount > outOwnerIndices.Length {
        return -1
    }

    w := 0
    while w < whereItemCount {
        ownerIndex := FunctionSignatureTypeParameterIndexOf(source, typeParamStarts, typeParamLengths, typeParamCount, whereNameStarts[w], whereNameLengths[w])
        if ownerIndex < 0 {
            return -1
        }

        outOwnerIndices[w] = ownerIndex
        w = w + 1
    }

    return whereItemCount
}

func FunctionSignatureTypeParameterIndexOf(source: string, typeParamStarts: int[], typeParamLengths: int[], typeParamCount: int, nameStart: int, nameLength: int): int {
    i := 0
    while i < typeParamCount {
        if FunctionSignatureSourceSpansEqual(source, typeParamStarts[i], typeParamLengths[i], nameStart, nameLength) {
            return i
        }

        i = i + 1
    }

    return -1
}

func FunctionSignatureSourceSpansEqual(source: string, leftStart: int, leftLength: int, rightStart: int, rightLength: int): bool {
    if leftStart < 0 || rightStart < 0 || leftLength != rightLength {
        return false
    }

    if leftStart + leftLength > source.Length || rightStart + rightLength > source.Length {
        return false
    }

    i := 0
    while i < leftLength {
        if source[leftStart + i] != source[rightStart + i] {
            return false
        }

        i = i + 1
    }

    return true
}

struct ParserFunctionParameterTable {
    NameStarts: int[]
    NameLengths: int[]
    TypeRoots: int[]
}

struct ParserFunctionTypeParameterTable {
    Starts: int[]
    Lengths: int[]
}

struct ParserFunctionWhereTable {
    NameStarts: int[]
    NameLengths: int[]
    ItemCodes: int[]
}

func ParseFunctionSignatureCore(
    tokens: &ParserTokenTable,
    count: int,
    funcIndex: int,
    typeStack: &ParserArgumentStack,
    nodes: &ParserNodeTable,
    children: &ParserChildIndexTable,
    parameters: &ParserFunctionParameterTable,
    typeParams: &ParserFunctionTypeParameterTable,
    whereItems: &ParserFunctionWhereTable,
    outResult: &ParserResultTable): int {
    funcNameStart := -1
    funcNameLength := 0
    i := funcIndex + 1
    if i < count && tokens.Kinds[i] == 0 {
        funcNameStart = tokens.Starts[i]
        funcNameLength = tokens.ValueLengths[i]
        i = i + 1
    }

    // Optional generic TYPE-PARAMETER list `<T, U>`: bare comma-separated Identifiers only. An inline
    // constraint (`<T: Base>`), an empty list, or any other form is unmodelled — return -1 (the host
    // declines to the C# path). With no `<`, the list is empty.
    typeParamCount := 0
    if i < count && tokens.Kinds[i] == 100 {
        i = i + 1
        while i < count && tokens.Kinds[i] != 102 {
            if tokens.Kinds[i] != 0 {
                return -1
            }
            typeParams.Starts[typeParamCount] = tokens.Starts[i]
            typeParams.Lengths[typeParamCount] = tokens.ValueLengths[i]
            typeParamCount = typeParamCount + 1
            i = i + 1

            if i < count && tokens.Kinds[i] != 102 {
                if tokens.Kinds[i] != 134 {
                    return -1
                }
                i = i + 1
                // A consumed comma must be FOLLOWED by another parameter name — a trailing comma
                // (`<T,>`) is a production-parser error (adversarial-review finding: the loop's
                // `!= 102` condition would otherwise exit cleanly and ACCEPT what the pipeline rejects).
                if i >= count || tokens.Kinds[i] != 0 {
                    return -1
                }
            }
        }
        if i >= count || tokens.Kinds[i] != 102 || typeParamCount == 0 {
            return -1
        }
        i = i + 1
    }

    // The parameter list `(` must follow the name (and optional type parameters) DIRECTLY. (Previously this
    // scanned blindly to the first `(`, silently skipping a `<T>` list — a generic function then declined
    // later at type resolution; the list is now parsed above, and anything ELSE in the gap is malformed and
    // declines at parse instead of at emit.)
    if i >= count || tokens.Kinds[i] != 127 {
        return -1
    }
    i = i + 1

    st := new ParserState { Pos: 0, NodeCursor: 0, ChildCursor: 0, ArgStackTop: 0, SplitGreaterDepth: 0, OwedGreaterByteEnd: 0 }

    paramCount := 0

    while i < count && tokens.Kinds[i] != 128 {
        // Skip attribute lists `[ ... ]` (balanced).
        while i < count && tokens.Kinds[i] == 131 {
            bracketDepth := 1
            i = i + 1
            while i < count && bracketDepth > 0 {
                if tokens.Kinds[i] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[i] == 132 {
                    bracketDepth = bracketDepth - 1
                }
                i = i + 1
            }
        }

        // Skip parameter modifiers and `this`.
        while i < count && (tokens.Kinds[i] == 78 || tokens.Kinds[i] == 79 || tokens.Kinds[i] == 82 || tokens.Kinds[i] == 42) {
            i = i + 1
        }

        if i >= count || tokens.Kinds[i] != 0 {
            return -1
        }

        paramNameStart := tokens.Starts[i]
        paramNameLength := tokens.ValueLengths[i]
        i = i + 1

        if i >= count || tokens.Kinds[i] != 122 {
            return -1
        }
        i = i + 1

        st.Pos = i
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        typeRoot := ParseUnionTypeReferenceNodeCore(ref tokens, count, ref st, ref typeStack, ref nodes, ref children, 0)
        if typeRoot < 0 {
            return -1
        }
        i = st.Pos

        parameters.NameStarts[paramCount] = paramNameStart
        parameters.NameLengths[paramCount] = paramNameLength
        parameters.TypeRoots[paramCount] = typeRoot
        paramCount = paramCount + 1

        // Skip a `= default` value without parsing it (balanced to the next depth-0 `,` or `)`).
        if i < count && tokens.Kinds[i] == 93 {
            i = i + 1
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && i < count {
                k := tokens.Kinds[i]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    i = i + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        i = i + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    i = i + 1
                }
            }
        }

        // After a parameter (and its optional default), the next token must cleanly terminate the parameter
        // -- a `,` (another parameter) or `)` (end of the list). Anything else means a malformed parameter
        // (e.g. an unbalanced default value whose depth tracking overshot the list's `)`, or a deferred
        // trailing annotation): refuse with -1 rather than silently mis-parsing the rest of the signature.
        if i >= count || (tokens.Kinds[i] != 134 && tokens.Kinds[i] != 128) {
            return -1
        }

        if tokens.Kinds[i] == 134 {
            i = i + 1
        }
    }

    if i < count && tokens.Kinds[i] == 128 {
        i = i + 1
    }

    returnRoot := -1
    if i < count && tokens.Kinds[i] == 122 {
        // A `: this(...)` / `: base(...)` CONSTRUCTOR chaining initializer is NOT a return type — leave returnRoot at
        // -1 and stop; the host parses the initializer separately (ParseConstructorChainInfoInto). A regular
        // function's `: ReturnType` always has a TYPE token after `:`, never `this` (42) / `base` (43), so this
        // branch is constructor-only and leaves function-signature parsing unchanged.
        if !(i + 1 < count && (tokens.Kinds[i + 1] == 42 || tokens.Kinds[i + 1] == 43)) {
            i = i + 1
            st.Pos = i
            st.SplitGreaterDepth = 0
            st.ArgStackTop = 0
            returnRoot = ParseUnionTypeReferenceNodeCore(ref tokens, count, ref st, ref typeStack, ref nodes, ref children, 0)
            if returnRoot < 0 {
                return -1
            }
            i = st.Pos
        }
    }

    // Generic CONSTRAINT clauses `where T: Item, Item ... where U: Item ...` (D-17b, mirroring the C#
    // parser's ParseGenericConstraints). Each item appends one flat row (owner name span + code); the
    // owner identifier is NOT validated against the declared type parameters here — the host resolves the
    // span against outTypeParamStarts/Lengths (the kernel cannot compare source text). A constraint TYPE
    // parses as another root in the shared node table, exactly like a parameter type; `new` must be
    // followed directly by `(` `)` or the signature is malformed.
    whereItemCount := 0
    while i < count && tokens.Kinds[i] == 53 {
        i = i + 1
        if i >= count || tokens.Kinds[i] != 0 {
            return -1
        }
        whereNameStart := tokens.Starts[i]
        whereNameLength := tokens.ValueLengths[i]
        i = i + 1
        if i >= count || tokens.Kinds[i] != 122 {
            return -1
        }
        i = i + 1

        moreItems := true
        while moreItems {
            itemCode := -1
            if i < count && tokens.Kinds[i] == 8 {
                itemCode = -2
                i = i + 1
            } else if i < count && tokens.Kinds[i] == 9 {
                itemCode = -3
                i = i + 1
            } else if i < count && tokens.Kinds[i] == 41 {
                if i + 2 >= count || tokens.Kinds[i + 1] != 127 || tokens.Kinds[i + 2] != 128 {
                    return -1
                }
                itemCode = -4
                i = i + 3
            } else {
                st.Pos = i
                st.SplitGreaterDepth = 0
                st.ArgStackTop = 0
                itemCode = ParseUnionTypeReferenceNodeCore(ref tokens, count, ref st, ref typeStack, ref nodes, ref children, 0)
                if itemCode < 0 {
                    return -1
                }
                i = st.Pos
            }

            whereItems.NameStarts[whereItemCount] = whereNameStart
            whereItems.NameLengths[whereItemCount] = whereNameLength
            whereItems.ItemCodes[whereItemCount] = itemCode
            whereItemCount = whereItemCount + 1

            if i < count && tokens.Kinds[i] == 134 {
                i = i + 1
            } else {
                moreItems = false
            }
        }
    }

    outResult.Values[0] = paramCount
    outResult.Values[1] = returnRoot
    outResult.Values[2] = st.NodeCursor
    outResult.Values[3] = funcNameStart
    outResult.Values[4] = funcNameLength
    outResult.Values[5] = typeParamCount
    outResult.Values[6] = i
    outResult.Values[7] = whereItemCount
    return paramCount
}
