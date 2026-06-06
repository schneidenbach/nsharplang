// Parser slice 9: the first declaration-level recursive-descent kernel -- it COMPOSES the slice 6-8 type
// kernel (ParserTypeReferences.nl). Given a `func` keyword token index, ParseFunctionSignatureInto parses
// the function's signature -- name, parameter names + parameter type trees, and the return type tree --
// mirroring the C# parser's ParseFunctionDeclaration / ParseParameterList (Parser.cs:405-535, 770-840).
// All parameter type trees and the return type tree share ONE columnar node table (the same table the
// type kernel fills), so each is an independent root within it; the shared parser-state array `st` carries
// the node/child cursors across the per-type parses while st[0] (pos) is repositioned to each type's start.
//
// Scope this slice: parameter NAME + parameter TYPE (any form the type kernel supports: Simple / Generic /
// Array / Nullable / Union / ByRef), and the `: ReturnType` return type (or none). Parameter modifiers
// (`ref` 78, `out` 79, `params` 82, `this` 42) and attribute lists `[...]` are skipped; a `= default` value
// is skipped (balanced) without being parsed (expression parsing is a later rung); optional `<TypeParams>`
// between the name and `(` is skipped by scanning to the first `(`.
// Deferred (the corpus avoids them): `->` return-type syntax, scoped/lifetime parameter annotations,
// generic constraints, expression-bodied functions, and materializing default values.
//
// Output:
//   outNodeKinds/... (8 columns) + outChildIndices : the shared type node table (see ParserTypeReferences.nl)
//   outParamNameStarts[p], outParamNameLengths[p]  : byte span of parameter p's name
//   outParamTypeRoots[p]                            : node id of parameter p's type tree root
//   outResult[0] = parameter count
//   outResult[1] = return type tree root node id, or -1 when the function has no return type
//   outResult[2] = total node count written to the shared table
//   outResult[3], outResult[4] = byte span (start, length) of the function name (start -1 if anonymous)
// Returns the parameter count, or -1 on a malformed signature / a parameter type the type kernel refuses.
//
// TokenType ordinals (Token.cs): Identifier 0, This 42, Ref 78, Out 79, Params 82, Assign 93, Func 7,
// Colon 122, Comma 134, LeftParen 127, RightParen 128, LeftBrace 129, RightBrace 130, LeftBracket 131,
// RightBracket 132.

func ParseFunctionSignatureInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, outNodeKinds: int[], outNameStarts: int[], outNameLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outParamNameStarts: int[], outParamNameLengths: int[], outParamTypeRoots: int[], outResult: int[]): int {
    funcNameStart := -1
    funcNameLength := 0
    if funcIndex + 1 < count && tokenKinds[funcIndex + 1] == 0 {
        funcNameStart = tokenStarts[funcIndex + 1]
        funcNameLength = tokenValueLengths[funcIndex + 1]
    }

    // Scan to the parameter list `(`. Optional <TypeParams> between the name and `(` contain no `(`, so the
    // first LeftParen after the keyword is unambiguously the parameter list.
    i := funcIndex + 1
    while i < count && tokenKinds[i] != 127 {
        i = i + 1
    }
    if i >= count {
        return -1
    }
    i = i + 1

    st := new int[](6)
    st[0] = 0
    st[4] = 0
    st[1] = 0
    st[2] = 0
    st[5] = 0
    st[3] = 0
    argStack := new int[](count + 1)

    paramCount := 0

    while i < count && tokenKinds[i] != 128 {
        // Skip attribute lists `[ ... ]` (balanced).
        while i < count && tokenKinds[i] == 131 {
            bracketDepth := 1
            i = i + 1
            while i < count && bracketDepth > 0 {
                if tokenKinds[i] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokenKinds[i] == 132 {
                    bracketDepth = bracketDepth - 1
                }
                i = i + 1
            }
        }

        // Skip parameter modifiers and `this`.
        while i < count && (tokenKinds[i] == 78 || tokenKinds[i] == 79 || tokenKinds[i] == 82 || tokenKinds[i] == 42) {
            i = i + 1
        }

        if i >= count || tokenKinds[i] != 0 {
            return -1
        }

        paramNameStart := tokenStarts[i]
        paramNameLength := tokenValueLengths[i]
        i = i + 1

        if i >= count || tokenKinds[i] != 122 {
            return -1
        }
        i = i + 1

        st[0] = i
        st[4] = 0
        st[3] = 0
        typeRoot := ParseUnionTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if typeRoot < 0 {
            return -1
        }
        i = st[0]

        outParamNameStarts[paramCount] = paramNameStart
        outParamNameLengths[paramCount] = paramNameLength
        outParamTypeRoots[paramCount] = typeRoot
        paramCount = paramCount + 1

        // Skip a `= default` value without parsing it (balanced to the next depth-0 `,` or `)`).
        if i < count && tokenKinds[i] == 93 {
            i = i + 1
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && i < count {
                k := tokenKinds[i]
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
        if i >= count || (tokenKinds[i] != 134 && tokenKinds[i] != 128) {
            return -1
        }

        if tokenKinds[i] == 134 {
            i = i + 1
        }
    }

    if i < count && tokenKinds[i] == 128 {
        i = i + 1
    }

    returnRoot := -1
    if i < count && tokenKinds[i] == 122 {
        i = i + 1
        st[0] = i
        st[4] = 0
        st[3] = 0
        returnRoot = ParseUnionTypeReferenceNode(tokenKinds, tokenStarts, tokenValueLengths, count, st, argStack, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths, 0)
        if returnRoot < 0 {
            return -1
        }
        i = st[0]
    }

    outResult[0] = paramCount
    outResult[1] = returnRoot
    outResult[2] = st[1]
    outResult[3] = funcNameStart
    outResult[4] = funcNameLength
    return paramCount
}
