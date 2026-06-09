// First N#-native parser slice: extract the top-level declaration KIND sequence from the
// brace-inserted token-kind stream (the output of TokenizeMetadataWithIndentationInto), matching the
// C# parser's CompilationUnit.Declarations dispatch (Parser.cs ParseDeclaration). A top-level
// declaration is a declaration keyword that appears at brace/bracket/paren depth 0 -- i.e. not nested
// inside a type body ({...}), an attribute list ([...]), or a parameter/argument list ((...)). Leading
// modifiers (public/static/...) and attributes ([Foo]) are naturally skipped because they are not
// declaration keywords; `ref struct` and `duck interface` are captured at their `struct`/`interface`
// keyword exactly as the C# dispatch produces StructDeclaration/InterfaceDeclaration. Returns the
// number of declarations and writes each declaration's keyword TokenType ordinal into outKinds.
//
// Recognized declaration keyword ordinals (TokenType, see Token.cs): Func=7, Class=8, Struct=9,
// Interface=10, Union=12, Record=13, Enum=14, Type=72, Test=73. (The contextual `setup`/`teardown`
// declarations and preprocessor declarations are intentionally out of scope for this first slice;
// corpora that exercise this kernel avoid them.)
// Parser slice 3: the file's package name span. The C# parser's CompilationUnit.Package is the dotted
// name after a top-level `package` keyword (`package A.B.C`); a file has at most one. This records the
// span covering the dotted name (first identifier start through the last identifier's end, so the host
// materializes "A.B.C"). Returns 1 and fills outResult[0]=start, outResult[1]=length when a package is
// present; returns 0 otherwise (matching CompilationUnit.Package == null). The package keyword is only
// recognized at depth 0, before any declaration body.
func PackageNameSpanInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outResult: int[]): int {
    braceDepth := 0
    i := 0
    while i < count {
        kind := tokenKinds[i]
        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if braceDepth == 0 && kind == 18 {
            // `package` keyword: collect the dotted name that follows (identifier (. identifier)*).
            j := i + 1
            nameStart := -1
            nameEnd := -1
            while j < count && (tokenKinds[j] == 0 || tokenKinds[j] == 124) {
                if tokenKinds[j] == 0 {
                    if nameStart < 0 {
                        nameStart = tokenStarts[j]
                    }

                    nameEnd = tokenStarts[j] + tokenValueLengths[j]
                }

                j = j + 1
            }

            if nameStart >= 0 {
                outResult[0] = nameStart
                outResult[1] = nameEnd - nameStart
                return 1
            }

            return 0
        }

        i = i + 1
    }

    return 0
}

// Parser slice 4: namespace imports. The C# parser processes a prefix of `package`/`import` lines
// before declarations (Parser.cs:52-81); an `import` whose first token is an Identifier is a
// NamespaceImport (`import A.B.C [as X]`) routed to CompilationUnit.Imports, while one followed by a
// string is a FileImport routed elsewhere and skipped here. This walks that header prefix linearly
// (imports/package are at depth 0, before any brace) and records each namespace import's dotted-name
// span and optional alias span (alias start = -1 when none). The host materializes the strings.
func NamespaceImportSpansInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outNsStarts: int[], outNsLengths: int[], outAliasStarts: int[], outAliasLengths: int[]): int {
    outCount := 0
    i := 0
    while i < count {
        kind := tokenKinds[i]

        if kind == 136 {
            i = i + 1
            continue
        }

        if kind == 18 {
            i = i + 1
            while i < count && (tokenKinds[i] == 0 || tokenKinds[i] == 124) {
                i = i + 1
            }
            continue
        }

        if kind == 17 {
            i = i + 1
            if i < count && tokenKinds[i] == 0 {
                nsStart := tokenStarts[i]
                nsEnd := tokenStarts[i] + tokenValueLengths[i]
                i = i + 1
                while i < count && (tokenKinds[i] == 0 || tokenKinds[i] == 124) {
                    if tokenKinds[i] == 0 {
                        nsEnd = tokenStarts[i] + tokenValueLengths[i]
                    }

                    i = i + 1
                }

                aliasStart := -1
                aliasLength := 0
                if i < count && tokenKinds[i] == 48 {
                    i = i + 1
                    if i < count && tokenKinds[i] == 0 {
                        aliasStart = tokenStarts[i]
                        aliasLength = tokenValueLengths[i]
                        i = i + 1
                    }
                }

                outNsStarts[outCount] = nsStart
                outNsLengths[outCount] = nsEnd - nsStart
                outAliasStarts[outCount] = aliasStart
                outAliasLengths[outCount] = aliasLength
                outCount = outCount + 1
                continue
            }

            while i < count && tokenKinds[i] != 136 {
                i = i + 1
            }
            continue
        }

        break
    }

    return outCount
}

// Parser slice 5: per-top-level-declaration modifier flags. Mirrors the C# Modifiers flags enum
// (Declarations.cs:271) and ParseModifiers (Parser.cs) which recognizes, before a declaration keyword,
// Public/Private/Static/Internal/Protected/Virtual/Override/Abstract/Sealed/Partial/Async/File. Returns
// 0 for non-modifier tokens. (Readonly/Const/Required/Init are member-level, not declaration modifiers.)
func ModifierFlag(kind: int): int {
    if kind == 64 {
        return 1
    }
    if kind == 65 {
        return 2
    }
    if kind == 66 {
        return 4
    }
    if kind == 67 {
        return 8
    }
    if kind == 63 {
        return 16
    }
    if kind == 58 {
        return 32
    }
    if kind == 60 {
        return 64
    }
    if kind == 61 {
        return 128
    }
    if kind == 62 {
        return 256
    }
    if kind == 68 {
        return 2048
    }
    if kind == 81 {
        return 32768
    }
    if kind == 59 {
        return 65536
    }
    return 0
}

// For each top-level declaration, record its keyword kind and its accumulated modifier flags (the
// modifier keywords appearing at depth 0 between the previous declaration and this one's keyword;
// attributes are inside brackets so they do not interfere). Matches (int)Declaration.Modifiers.
func TopLevelDeclarationModifiersInto(tokenKinds: int[], count: int, outKinds: int[], outModifiers: int[]): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    pending := 0
    outCount := 0

    i := 0
    while i < count {
        kind := tokenKinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            flag := ModifierFlag(kind)
            if flag != 0 {
                pending = pending | flag
            } else if IsTopLevelDeclarationKeyword(kind) {
                outKinds[outCount] = kind
                outModifiers[outCount] = pending
                outCount = outCount + 1
                pending = 0
            }
        }

        i = i + 1
    }

    return outCount
}

func IsTopLevelDeclarationKeyword(kind: int): bool {
    return kind == 7 || kind == 8 || kind == 9 || kind == 10 || kind == 12 || kind == 13 || kind == 14 || kind == 72 || kind == 73
}

// Parser slice 2: like TopLevelDeclarationKindsInto, but also records each declaration's NAME span.
// A declaration's name is the token immediately after its keyword (modifiers precede the keyword, so
// nothing sits between keyword and name) when that token is an Identifier (kind 0). For `test "..."`
// the token after the keyword is a string literal, so no name is recorded (outNameStart = -1) -- the
// C# TestDeclaration's string name is out of scope for this slice. The host materializes the name from
// source via outNameStarts/outNameLengths.
func TopLevelDeclarationNameSpansInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outKinds: int[], outNameStarts: int[], outNameLengths: int[]): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0

    i := 0
    while i < count {
        kind := tokenKinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            if IsTopLevelDeclarationKeyword(kind) {
                outKinds[outCount] = kind
                if i + 1 < count && tokenKinds[i + 1] == 0 {
                    outNameStarts[outCount] = tokenStarts[i + 1]
                    outNameLengths[outCount] = tokenValueLengths[i + 1]
                } else {
                    outNameStarts[outCount] = -1
                    outNameLengths[outCount] = 0
                }

                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

func TopLevelDeclarationKindsInto(tokenKinds: int[], count: int, outKinds: int[]): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0

    i := 0
    while i < count {
        kind := tokenKinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            if IsTopLevelDeclarationKeyword(kind) {
                outKinds[outCount] = kind
                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

// Parser slice (enum bodies): parse ONE enum declaration's members into flat parallel arrays. `enumIndex` is the
// compacted token index of the `enum` keyword (token 14). Reads the enum NAME (the Identifier immediately after
// `enum`) into outResult[0]=nameStart / outResult[1]=nameLength, then `{` (129), then comma-separated members until
// `}` (130). Each member is an Identifier (token 0) optionally followed by `= <int-literal>` (Assign 93 then a
// number literal, token 1): outNameStarts[m]/outNameLengths[m] = the member name span; outHasValue[m] = 1 with
// outValueStarts[m]/outValueLengths[m] = the literal span when explicit, else outHasValue[m] = 0. A comma is
// required between members (a trailing comma before `}` is allowed). Returns the member count, or -1 on any
// unexpected token (a non-int member value, a `:` underlying-type annotation, attributes, a missing name/brace) so
// the host declines the whole program to the C# path. Mirrors Parser.cs ParseEnumDeclaration for the int-enum subset.
func ParseEnumDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameStarts: int[], outNameLengths: int[], outValueStarts: int[], outValueLengths: int[], outHasValue: int[], outResult: int[]): int {
    pos := enumIndex
    if pos >= count || tokenKinds[pos] != 14 {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokenKinds[pos] != 0 {
        return -1
    }
    outResult[0] = tokenStarts[pos]
    outResult[1] = tokenValueLengths[pos]
    pos = pos + 1

    if pos >= count || tokenKinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    memberCount := 0
    while pos < count && tokenKinds[pos] != 130 {
        if tokenKinds[pos] != 0 {
            return -1
        }
        outNameStarts[memberCount] = tokenStarts[pos]
        outNameLengths[memberCount] = tokenValueLengths[pos]
        outHasValue[memberCount] = 0
        outValueStarts[memberCount] = -1
        outValueLengths[memberCount] = 0
        pos = pos + 1

        if pos < count && tokenKinds[pos] == 93 {
            pos = pos + 1
            if pos >= count || tokenKinds[pos] != 1 {
                return -1
            }
            outHasValue[memberCount] = 1
            outValueStarts[memberCount] = tokenStarts[pos]
            outValueLengths[memberCount] = tokenValueLengths[pos]
            pos = pos + 1
        }

        memberCount = memberCount + 1

        if pos < count && tokenKinds[pos] != 130 {
            if tokenKinds[pos] != 134 {
                return -1
            }
            pos = pos + 1
        }
    }

    if pos >= count || tokenKinds[pos] != 130 {
        return -1
    }
    return memberCount
}

// Parser slice (struct bodies): parse ONE fields-only struct declaration's fields into flat parallel arrays.
// `structIndex` is the compacted token index of the `struct` keyword (token 9). Reads the struct NAME (the
// Identifier after `struct`) into outResult[0]=nameStart / outResult[1]=nameLength, then `{` (129), then a sequence
// of FIELDS until `}` (130). Each field is `Identifier : <type-name>` where the type is a SINGLE Identifier token
// (a builtin like int/double/string, which the lexer tokenizes as an Identifier, kind 0). There is no field
// separator (newlines are stripped before this runs), so fields are detected by the repeating `name : type`
// pattern: outFieldNameStarts/Lengths[f] = the field name span, outFieldTypeStarts/Lengths[f] = the field
// TYPE-name span. Returns the field count, or -1 on any unexpected token — a primary-ctor `(` after the name, a
// method (`func`), a field initializer (`=`), a composed/array/tuple field type (a non-Identifier after `:`), a
// missing name/colon/brace, or an empty body — so the host declines the whole program to the C# path. Slice-1
// scope: fields-only structs with single-builtin-token field types.
// Also used for RECORD declarations (token 13) and CLASS declarations (token 8): the `record/class Name { fields
// methods }` body syntax is identical to a struct's, so the same kernel parses all three — the host distinguishes a
// value-type struct from a reference-type record/class by which keyword index it passed in. Accepts the `struct` (9),
// `record` (13), or `class` (8) keyword. A class with a user `constructor` (slice 1b) is NOT yet parsed here: the
// `constructor` keyword is neither a field-name identifier nor `func`/`}`, so the field loop returns -1 and the host
// declines that class to the C# path until constructors are modelled.
func ParseStructDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, structIndex: int, outFieldNameStarts: int[], outFieldNameLengths: int[], outFieldTypeStarts: int[], outFieldTypeLengths: int[], outMethodFuncIndices: int[], outCtorIndices: int[], outPropIndices: int[], outResult: int[]): int {
    pos := structIndex
    if pos >= count || (tokenKinds[pos] != 9 && tokenKinds[pos] != 13 && tokenKinds[pos] != 8) {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokenKinds[pos] != 0 {
        return -1
    }
    outResult[0] = tokenStarts[pos]
    outResult[1] = tokenValueLengths[pos]
    pos = pos + 1

    if pos >= count || tokenKinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    // Fields first (`Name : Type`), stopping at the type close `}` (130), the first method `func` (7), or a
    // CONSTRUCTOR member — an Identifier (0) immediately followed by `(` (127). A field is `id : type` (a `:` after
    // the name), so an `id (` is unambiguously a constructor, not a field, and ends the field section. A PROPERTY
    // `id : type { get {…} [set {…}] }` — an `id : type` followed by `{` (129) — is recorded (its name token index in
    // outPropIndices) and its `{ … }` block skipped; the host parses the accessor bodies. (A field is just `id :
    // type`; the trailing `{` disambiguates a property from a field.) Single-token property types only (a composed
    // type would not present `{` at pos+3, so it falls to the field path and declines).
    fieldCount := 0
    propCount := 0
    fieldsDone := 0
    while fieldsDone == 0 && pos < count && tokenKinds[pos] != 130 && tokenKinds[pos] != 7 {
        if tokenKinds[pos] == 0 && pos + 1 < count && tokenKinds[pos + 1] == 127 {
            fieldsDone = 1
        } else if tokenKinds[pos] == 0 && pos + 3 < count && tokenKinds[pos + 1] == 122 && tokenKinds[pos + 2] == 0 && tokenKinds[pos + 3] == 129 {
            outPropIndices[propCount] = pos
            propCount = propCount + 1
            pos = pos + 3

            pdepth := 0
            pdone := 0
            while pos < count && pdone == 0 {
                if tokenKinds[pos] == 129 {
                    pdepth = pdepth + 1
                } else if tokenKinds[pos] == 130 {
                    pdepth = pdepth - 1
                    if pdepth == 0 {
                        pdone = 1
                    }
                }
                pos = pos + 1
            }
            if pdone == 0 {
                return -1
            }
        } else {
            if tokenKinds[pos] != 0 {
                return -1
            }
            outFieldNameStarts[fieldCount] = tokenStarts[pos]
            outFieldNameLengths[fieldCount] = tokenValueLengths[pos]
            pos = pos + 1

            if pos >= count || tokenKinds[pos] != 122 {
                return -1
            }
            pos = pos + 1

            if pos >= count || tokenKinds[pos] != 0 {
                return -1
            }
            outFieldTypeStarts[fieldCount] = tokenStarts[pos]
            outFieldTypeLengths[fieldCount] = tokenValueLengths[pos]
            pos = pos + 1

            fieldCount = fieldCount + 1
        }
    }

    // Members next, in any order: METHODS (`func name(...): ret { body }`) and CONSTRUCTORS (`constructor(...) {
    // body }` — lexed as an Identifier followed by `(`). DELIMIT each: record its keyword/identifier token index
    // (outMethodFuncIndices for a method, outCtorIndices for a constructor), then skip its signature to the body `{`
    // and scan to the matching `}` (balanced). The host parses the signatures/bodies via the existing function
    // kernels at the recorded indices (a constructor's `(params)` and `{body}` parse via the same signature/statement
    // kernels — it has no name token and no `: ret`, so the signature kernel yields name=-1, returnRoot=-1; a
    // constructor INITIALIZER `: this(...)`/`base(...)` makes the signature kernel's return-type parse fail, so a
    // chained ctor declines). A member with no `{` body declines. The host verifies each ctor identifier's text is
    // literally "constructor".
    methodCount := 0
    ctorCount := 0
    while pos < count && tokenKinds[pos] != 130 {
        if tokenKinds[pos] == 7 {
            outMethodFuncIndices[methodCount] = pos
            methodCount = methodCount + 1
            pos = pos + 1
        } else if tokenKinds[pos] == 0 && pos + 1 < count && tokenKinds[pos + 1] == 127 {
            outCtorIndices[ctorCount] = pos
            ctorCount = ctorCount + 1
            pos = pos + 1
        } else {
            return -1
        }

        while pos < count && tokenKinds[pos] != 129 && tokenKinds[pos] != 130 {
            pos = pos + 1
        }
        if pos >= count || tokenKinds[pos] != 129 {
            return -1
        }

        depth := 0
        bodyDone := 0
        while pos < count && bodyDone == 0 {
            if tokenKinds[pos] == 129 {
                depth = depth + 1
            } else if tokenKinds[pos] == 130 {
                depth = depth - 1
                if depth == 0 {
                    bodyDone = 1
                }
            }
            pos = pos + 1
        }
        if bodyDone == 0 {
            return -1
        }
    }

    if pos >= count || tokenKinds[pos] != 130 {
        return -1
    }
    if fieldCount == 0 {
        return -1
    }
    outResult[2] = methodCount
    outResult[3] = ctorCount
    outResult[4] = propCount
    return fieldCount
}

// Parse a CONSTRUCTOR's chaining initializer `: this(args)` / `: base(args)`, given the constructor's identifier
// token index (`ctorIndex`, the "constructor" identifier). Scans past the param list `(...)` (balanced) to the
// optional `:`; with no `:` (or no `(` params) returns 0 with outResult[0] = 0 (no initializer). For `: this(`
// (this = 42) / `: base(` (base = 43), records each chained ARG — restricted to a SINGLE token, either a param
// IDENTIFIER (kind 0) or an INT LITERAL (kind 1) — into outArgKinds/outArgStarts/outArgLengths, separated by `,`
// (134), closed by `)` (128). outResult[0] = the initializer kind (0 = none, 1 = this, 2 = base). Returns the
// chained-arg count, or -1 on a malformed initializer or a non-{identifier,int-literal} arg (a complex expression /
// string / other literal — the host declines such a chaining ctor to the C# path).
func ParseConstructorChainInfoInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outResult: int[]): int {
    outResult[0] = 0
    pos := ctorIndex + 1
    if pos >= count || tokenKinds[pos] != 127 {
        return 0
    }

    pdepth := 0
    pdone := 0
    while pos < count && pdone == 0 {
        if tokenKinds[pos] == 127 {
            pdepth = pdepth + 1
        } else if tokenKinds[pos] == 128 {
            pdepth = pdepth - 1
            if pdepth == 0 {
                pdone = 1
            }
        }
        pos = pos + 1
    }
    if pdone == 0 {
        return 0
    }

    if pos >= count || tokenKinds[pos] != 122 {
        return 0
    }
    pos = pos + 1

    if pos >= count {
        return -1
    }
    if tokenKinds[pos] == 42 {
        outResult[0] = 1
    } else if tokenKinds[pos] == 43 {
        outResult[0] = 2
    } else {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokenKinds[pos] != 127 {
        return -1
    }
    pos = pos + 1

    argCount := 0
    while pos < count && tokenKinds[pos] != 128 {
        if tokenKinds[pos] != 0 && tokenKinds[pos] != 1 {
            return -1
        }
        outArgKinds[argCount] = tokenKinds[pos]
        outArgStarts[argCount] = tokenStarts[pos]
        outArgLengths[argCount] = tokenValueLengths[pos]
        argCount = argCount + 1
        pos = pos + 1

        if pos < count && tokenKinds[pos] != 128 {
            if tokenKinds[pos] != 134 {
                return -1
            }
            pos = pos + 1
        }
    }

    if pos >= count || tokenKinds[pos] != 128 {
        return -1
    }
    return argCount
}

// Parser slice (union bodies): parse ONE `union Name { Case { f: T, ... }  Case { ... } }` declaration into flat
// parallel arrays. `unionIndex` is the compacted token index of the `union` keyword (token 12). Reads the union NAME
// (the Identifier after `union`) into outResult[0]=nameStart / outResult[1]=nameLength, then `{` (129), then a
// sequence of CASES until the union close `}` (130). Each case is `CaseName { field : Type, ... }`: the case name
// (Identifier) into outCaseNameStarts/Lengths[case], its `{` (129), then a sequence of FIELDS — `Identifier : Type`
// where the type is a SINGLE Identifier token (a builtin like int/string, or a bare user-type name) — each delimited
// by an optional `,` (134), closed by the case `}` (130). Fields flatten ACROSS all cases into
// outFieldNameStarts/Lengths + outFieldTypeStarts/Lengths in case-then-field order; outCaseFieldCounts[case] records
// how many fields that case contributed (so the host re-segments the flat field arrays per case). Returns the case
// count, or -1 on any unexpected token — a bare case with no `{` body, a primary-ctor `(`, a composed/array/generic
// field type (a non-Identifier after `:`), a field initializer, a missing name/colon/brace, or an empty union — so
// the host declines the whole program to the C# path. Slice scope: non-generic unions whose case fields are single
// builtin/bare-name-typed (the emitter further gates each field type to a supported CLR type).
func ParseUnionDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, unionIndex: int, outCaseNameStarts: int[], outCaseNameLengths: int[], outCaseFieldCounts: int[], outFieldNameStarts: int[], outFieldNameLengths: int[], outFieldTypeStarts: int[], outFieldTypeLengths: int[], outResult: int[]): int {
    pos := unionIndex
    if pos >= count || tokenKinds[pos] != 12 {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokenKinds[pos] != 0 {
        return -1
    }
    outResult[0] = tokenStarts[pos]
    outResult[1] = tokenValueLengths[pos]
    pos = pos + 1

    if pos >= count || tokenKinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    caseCount := 0
    totalFields := 0
    while pos < count && tokenKinds[pos] != 130 {
        if tokenKinds[pos] != 0 {
            return -1
        }
        outCaseNameStarts[caseCount] = tokenStarts[pos]
        outCaseNameLengths[caseCount] = tokenValueLengths[pos]
        pos = pos + 1

        if pos >= count || tokenKinds[pos] != 129 {
            return -1
        }
        pos = pos + 1

        caseFieldCount := 0
        while pos < count && tokenKinds[pos] != 130 {
            if tokenKinds[pos] != 0 {
                return -1
            }
            outFieldNameStarts[totalFields] = tokenStarts[pos]
            outFieldNameLengths[totalFields] = tokenValueLengths[pos]
            pos = pos + 1

            if pos >= count || tokenKinds[pos] != 122 {
                return -1
            }
            pos = pos + 1

            if pos >= count || tokenKinds[pos] != 0 {
                return -1
            }
            outFieldTypeStarts[totalFields] = tokenStarts[pos]
            outFieldTypeLengths[totalFields] = tokenValueLengths[pos]
            pos = pos + 1

            totalFields = totalFields + 1
            caseFieldCount = caseFieldCount + 1

            if pos < count && tokenKinds[pos] != 130 {
                if tokenKinds[pos] != 134 {
                    return -1
                }
                pos = pos + 1
            }
        }

        if pos >= count || tokenKinds[pos] != 130 {
            return -1
        }
        pos = pos + 1

        outCaseFieldCounts[caseCount] = caseFieldCount
        caseCount = caseCount + 1
    }

    if pos >= count || tokenKinds[pos] != 130 {
        return -1
    }
    if caseCount == 0 {
        return -1
    }
    return caseCount
}
