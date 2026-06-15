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
struct NamespaceImportTable {
    NsStarts: int[]
    NsLengths: int[]
    AliasStarts: int[]
    AliasLengths: int[]
}

struct TopLevelDeclarationModifierTable {
    Kinds: int[]
    Modifiers: int[]
}

struct TopLevelDeclarationKindTable {
    Kinds: int[]
}

struct TopLevelDeclarationNameTable {
    Kinds: int[]
    NameStarts: int[]
    NameLengths: int[]
}

struct InterfaceDeclarationTable {
    MethodFuncIndices: int[]
    BaseNameStarts: int[]
    BaseNameLengths: int[]
}

struct EnumMemberTable {
    NameStarts: int[]
    NameLengths: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    HasValue: int[]
}

struct StructDeclarationTable {
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    FieldStaticFlags: int[]
    FieldInitKinds: int[]
    FieldInitStarts: int[]
    FieldInitLengths: int[]
    MethodFuncIndices: int[]
    MethodStaticFlags: int[]
    CtorIndices: int[]
    PropIndices: int[]
    PropStaticFlags: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    BaseNameStarts: int[]
    BaseNameLengths: int[]
}

struct ConstructorChainArgTable {
    Kinds: int[]
    Starts: int[]
    Lengths: int[]
}

struct UnionDeclarationTable {
    CaseNameStarts: int[]
    CaseNameLengths: int[]
    CaseFieldCounts: int[]
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
}

struct ParserDeclarationTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
}

struct ParserDeclarationKindStream {
    Kinds: int[]
}

struct ParserDeclarationResultTable {
    Values: int[]
}

func PackageNameSpanInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return PackageNameSpanCore(ref tokens, count, ref result)
}

func PackageNameSpanCore(tokens: &ParserDeclarationTokenTable, count: int, result: &ParserDeclarationResultTable): int {
    braceDepth := 0
    i := 0
    while i < count {
        kind := tokens.Kinds[i]
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
            while j < count && (tokens.Kinds[j] == 0 || tokens.Kinds[j] == 124) {
                if tokens.Kinds[j] == 0 {
                    if nameStart < 0 {
                        nameStart = tokens.Starts[j]
                    }

                    nameEnd = tokens.Starts[j] + tokens.ValueLengths[j]
                }

                j = j + 1
            }

            if nameStart >= 0 {
                result.Values[0] = nameStart
                result.Values[1] = nameEnd - nameStart
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
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    imports := new NamespaceImportTable { NsStarts: outNsStarts, NsLengths: outNsLengths, AliasStarts: outAliasStarts, AliasLengths: outAliasLengths }
    return NamespaceImportSpansCore(ref tokens, count, ref imports)
}

func NamespaceImportSpansCore(tokens: &ParserDeclarationTokenTable, count: int, imports: &NamespaceImportTable): int {
    outCount := 0
    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 136 {
            i = i + 1
            continue
        }

        if kind == 18 {
            i = i + 1
            while i < count && (tokens.Kinds[i] == 0 || tokens.Kinds[i] == 124) {
                i = i + 1
            }
            continue
        }

        if kind == 17 {
            i = i + 1
            if i < count && tokens.Kinds[i] == 0 {
                nsStart := tokens.Starts[i]
                nsEnd := tokens.Starts[i] + tokens.ValueLengths[i]
                i = i + 1
                while i < count && (tokens.Kinds[i] == 0 || tokens.Kinds[i] == 124) {
                    if tokens.Kinds[i] == 0 {
                        nsEnd = tokens.Starts[i] + tokens.ValueLengths[i]
                    }

                    i = i + 1
                }

                aliasStart := -1
                aliasLength := 0
                if i < count && tokens.Kinds[i] == 48 {
                    i = i + 1
                    if i < count && tokens.Kinds[i] == 0 {
                        aliasStart = tokens.Starts[i]
                        aliasLength = tokens.ValueLengths[i]
                        i = i + 1
                    }
                }

                imports.NsStarts[outCount] = nsStart
                imports.NsLengths[outCount] = nsEnd - nsStart
                imports.AliasStarts[outCount] = aliasStart
                imports.AliasLengths[outCount] = aliasLength
                outCount = outCount + 1
                continue
            }

            while i < count && tokens.Kinds[i] != 136 {
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
// A depth-0 `where` (53) opens a generic CONSTRAINT clause whose items may include the `class` (8) /
// `struct` (9) KEYWORDS — those are constraints, not declarations, so keyword recognition is suppressed
// from `where` until the body `{` (which also ends the signature). All three top-level scanners share
// this rule.
func TopLevelDeclarationModifiersInto(tokenKinds: int[], count: int, outKinds: int[], outModifiers: int[]): int {
    tokens := new ParserDeclarationKindStream { Kinds: tokenKinds }
    decls := new TopLevelDeclarationModifierTable { Kinds: outKinds, Modifiers: outModifiers }
    return TopLevelDeclarationModifiersCore(ref tokens, count, ref decls)
}

func TopLevelDeclarationModifiersCore(tokens: &ParserDeclarationKindStream, count: int, decls: &TopLevelDeclarationModifierTable): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    pending := 0
    outCount := 0
    inWhereClause := false

    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
            inWhereClause = false
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
            if kind == 53 {
                inWhereClause = true
            } else if !inWhereClause {
                flag := ModifierFlag(kind)
                if flag != 0 {
                    pending = pending | flag
                } else if IsTopLevelDeclarationKeyword(kind) {
                    decls.Kinds[outCount] = kind
                    decls.Modifiers[outCount] = pending
                    outCount = outCount + 1
                    pending = 0
                }
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
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decls := new TopLevelDeclarationNameTable { Kinds: outKinds, NameStarts: outNameStarts, NameLengths: outNameLengths }
    return TopLevelDeclarationNameSpansCore(ref tokens, count, ref decls)
}

func TopLevelDeclarationNameSpansCore(tokens: &ParserDeclarationTokenTable, count: int, decls: &TopLevelDeclarationNameTable): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0
    inWhereClause := false

    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
            inWhereClause = false
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
            if kind == 53 {
                inWhereClause = true
            } else if !inWhereClause && IsTopLevelDeclarationKeyword(kind) {
                decls.Kinds[outCount] = kind
                if i + 1 < count && tokens.Kinds[i + 1] == 0 {
                    decls.NameStarts[outCount] = tokens.Starts[i + 1]
                    decls.NameLengths[outCount] = tokens.ValueLengths[i + 1]
                } else {
                    decls.NameStarts[outCount] = -1
                    decls.NameLengths[outCount] = 0
                }

                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

func TopLevelDeclarationKindsInto(tokenKinds: int[], count: int, outKinds: int[]): int {
    tokens := new ParserDeclarationKindStream { Kinds: tokenKinds }
    decls := new TopLevelDeclarationKindTable { Kinds: outKinds }
    return TopLevelDeclarationKindsCore(ref tokens, count, ref decls)
}

func TopLevelDeclarationKindsCore(tokens: &ParserDeclarationKindStream, count: int, decls: &TopLevelDeclarationKindTable): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0
    inWhereClause := false

    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
            inWhereClause = false
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
            if kind == 53 {
                inWhereClause = true
            } else if !inWhereClause && IsTopLevelDeclarationKeyword(kind) {
                decls.Kinds[outCount] = kind
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
// Parse ONE top-level `interface` declaration (at compacted token index `interfaceIndex`):
// `interface Name [: Base[, ...]] { <method signatures/default methods> }`. Members are `func name(params)
// [: ret]` signatures, optionally followed by a balanced block body for a C#-8 DEFAULT method; any
// non-`func` member (bare fields, properties) is -1 (the production pipeline silently
// DROPS bare members and NL103s property bodies at emit -- declining inherits neither). Each
// member's `func` token index goes to outMethodFuncIndices (the host parses signatures via the
// shared ParseFunctionSignature kernel); outResult[0]/[1] = the interface NAME span and outResult[2]
// = base interface count, with base-name spans in outBaseNameStarts/Lengths. Returns the method
// count, -1 on any parse failure. Generic interfaces (`<` after the name) remain unmodeled -> -1.
func ParseInterfaceDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameStarts: int[], outBaseNameLengths: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decl := new InterfaceDeclarationTable { MethodFuncIndices: outMethodFuncIndices, BaseNameStarts: outBaseNameStarts, BaseNameLengths: outBaseNameLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseInterfaceDeclarationCore(ref tokens, count, interfaceIndex, ref decl, ref result)
}

func ParseInterfaceDeclarationCore(tokens: &ParserDeclarationTokenTable, count: int, interfaceIndex: int, decl: &InterfaceDeclarationTable, result: &ParserDeclarationResultTable): int {
    pos := interfaceIndex
    if pos >= count || tokens.Kinds[pos] != 10 {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }
    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    if pos < count && tokens.Kinds[pos] == 100 {
        return -1
    }

    baseCount := 0
    if pos < count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        while true {
            if pos >= count || tokens.Kinds[pos] != 0 {
                return -1
            }
            decl.BaseNameStarts[baseCount] = tokens.Starts[pos]
            decl.BaseNameLengths[baseCount] = tokens.ValueLengths[pos]
            baseCount = baseCount + 1
            pos = pos + 1

            if pos < count && tokens.Kinds[pos] == 134 {
                pos = pos + 1
                continue
            }
            break
        }
    }
    result.Values[2] = baseCount

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    methodCount := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        if tokens.Kinds[pos] != 7 {
            return -1
        }
        decl.MethodFuncIndices[methodCount] = pos
        pos = pos + 1
        while pos < count && tokens.Kinds[pos] != 7 && tokens.Kinds[pos] != 130 {
            if tokens.Kinds[pos] == 129 {
                depth := 1
                pos = pos + 1
                while pos < count && depth > 0 {
                    if tokens.Kinds[pos] == 129 {
                        depth = depth + 1
                    } else if tokens.Kinds[pos] == 130 {
                        depth = depth - 1
                    }
                    pos = pos + 1
                }
                if depth != 0 {
                    return -1
                }
                break
            }
            pos = pos + 1
        }
        methodCount = methodCount + 1
    }
    if pos >= count {
        return -1
    }
    return methodCount
}

func ParseEnumDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameStarts: int[], outNameLengths: int[], outValueStarts: int[], outValueLengths: int[], outHasValue: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    members := new EnumMemberTable { NameStarts: outNameStarts, NameLengths: outNameLengths, ValueStarts: outValueStarts, ValueLengths: outValueLengths, HasValue: outHasValue }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseEnumDeclarationCore(ref tokens, count, enumIndex, ref members, ref result)
}

func ParseEnumDeclarationCore(tokens: &ParserDeclarationTokenTable, count: int, enumIndex: int, members: &EnumMemberTable, result: &ParserDeclarationResultTable): int {
    pos := enumIndex
    if pos >= count || tokens.Kinds[pos] != 14 {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }
    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    memberCount := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        if tokens.Kinds[pos] != 0 {
            return -1
        }
        members.NameStarts[memberCount] = tokens.Starts[pos]
        members.NameLengths[memberCount] = tokens.ValueLengths[pos]
        members.HasValue[memberCount] = 0
        members.ValueStarts[memberCount] = -1
        members.ValueLengths[memberCount] = 0
        pos = pos + 1

        if pos < count && tokens.Kinds[pos] == 93 {
            pos = pos + 1
            if pos >= count || tokens.Kinds[pos] != 1 {
                return -1
            }
            members.HasValue[memberCount] = 1
            members.ValueStarts[memberCount] = tokens.Starts[pos]
            members.ValueLengths[memberCount] = tokens.ValueLengths[pos]
            pos = pos + 1
        }

        memberCount = memberCount + 1

        if pos < count && tokens.Kinds[pos] != 130 {
            if tokens.Kinds[pos] != 134 {
                return -1
            }
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 130 {
        return -1
    }
    return memberCount
}

// Parser slice (struct bodies): parse ONE fields-only struct declaration's fields into flat parallel arrays.
// `structIndex` is the compacted token index of the `struct` keyword (token 9). Reads the struct NAME (the
// Identifier after `struct`) into outResult[0]=nameStart / outResult[1]=nameLength, then an OPTIONAL single-
// identifier BASE TYPE / INTERFACE list (`: Base[, IFace...]`) into outBaseNameStarts/Lengths with
// outResult[8]=baseNameCount (outResult[5]/[6] mirror the first entry for compatibility, 0/0 when absent — the
// host resolves and validates the names; only classes may model one non-interface base), then `{` (129), then a sequence
// of FIELDS until `}` (130). Each field is `Identifier : <type>` where the type starts with an Identifier token
// (a builtin like int/double/string, which the lexer tokenizes as an Identifier, kind 0) and may have a balanced
// generic suffix plus postfix `[]`, `?`, or `?[]` suffixes. There is no field separator (newlines are stripped
// before this runs), so fields are detected by the repeating `name : type` pattern: outFieldNameStarts/Lengths[f]
// = the field name span, outFieldTypeStarts/Lengths[f] = the field TYPE span. Returns the field count (0 is legal
// for a FIELDLESS type with at least one method/ctor/property), or -1 on any unexpected token — a primary-ctor
// `(` after the name, a field initializer (`=`), a tuple/function field type, a missing name/colon/brace, or a
// fully EMPTY body — so the host declines the whole program to the C# path.
// Also used for RECORD declarations (token 13) and CLASS declarations (token 8): the `record/class Name { fields
// methods }` body syntax is identical to a struct's, so the same kernel parses all three — the host distinguishes a
// value-type struct from a reference-type record/class by which keyword index it passed in. Accepts the `struct` (9),
// `record` (13), or `class` (8) keyword. A class with a user `constructor` (slice 1b) is NOT yet parsed here: the
// `constructor` keyword is neither a field-name identifier nor `func`/`}`, so the field loop returns -1 and the host
// declines that class to the C# path until constructors are modelled.
// STATIC members: a `static func` method (token 63 `static` immediately before token 7 `func`) is recorded with
// outMethodStaticFlags[m] = 1 (the func index points at the `func` keyword, exactly like an instance method, so the
// host parses its signature/body with the same kernels); an instance method gets flag 0. A STATIC FIELD
// `static name: Type [= <literal>]` is recorded with outFieldStaticFlags[f] = 1 and — when an initializer is
// present — outFieldInitKinds[f] = the literal's token kind (IntLiteral 1 / FloatLiteral 2 / CharLiteral 3 /
// StringLiteral 4 / true 44 / false 45; an optional leading `-` (89) is admitted before a NUMERIC literal and is
// included in the recorded span) with outFieldInitStarts/Lengths[f] covering the full initializer text; no
// initializer leaves outFieldInitKinds[f] = -1. A STATIC PROPERTY `static name: Type { ... }` is recorded into
// outPropIndices (the NAME token index, exactly like an instance property) with outPropStaticFlags[p] = 1; an
// instance property gets flag 0. A GENERAL initializer expression (`= new T(...)`, `= a + b`), an initializer on
// an INSTANCE field, and `static constructor` are not yet modelled and return -1 — the host declines the whole
// program to the C# path.
func ParseStructDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, structIndex: int, outFieldNameStarts: int[], outFieldNameLengths: int[], outFieldTypeStarts: int[], outFieldTypeLengths: int[], outFieldStaticFlags: int[], outFieldInitKinds: int[], outFieldInitStarts: int[], outFieldInitLengths: int[], outMethodFuncIndices: int[], outMethodStaticFlags: int[], outCtorIndices: int[], outPropIndices: int[], outPropStaticFlags: int[], outTypeParamStarts: int[], outTypeParamLengths: int[], outBaseNameStarts: int[], outBaseNameLengths: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decl := new StructDeclarationTable { FieldNameStarts: outFieldNameStarts, FieldNameLengths: outFieldNameLengths, FieldTypeStarts: outFieldTypeStarts, FieldTypeLengths: outFieldTypeLengths, FieldStaticFlags: outFieldStaticFlags, FieldInitKinds: outFieldInitKinds, FieldInitStarts: outFieldInitStarts, FieldInitLengths: outFieldInitLengths, MethodFuncIndices: outMethodFuncIndices, MethodStaticFlags: outMethodStaticFlags, CtorIndices: outCtorIndices, PropIndices: outPropIndices, PropStaticFlags: outPropStaticFlags, TypeParamStarts: outTypeParamStarts, TypeParamLengths: outTypeParamLengths, BaseNameStarts: outBaseNameStarts, BaseNameLengths: outBaseNameLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseStructDeclarationCore(ref tokens, count, structIndex, ref decl, ref result)
}

func ParseStructDeclarationCore(tokens: &ParserDeclarationTokenTable, count: int, structIndex: int, decl: &StructDeclarationTable, result: &ParserDeclarationResultTable): int {
    pos := structIndex
    if pos >= count || (tokens.Kinds[pos] != 9 && tokens.Kinds[pos] != 13 && tokens.Kinds[pos] != 8) {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }
    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    // Optional generic TYPE-PARAMETER list `<T, U>` after the type name (Less 100, Identifier 0,
    // Comma 134, Greater 102): bare comma-separated Identifiers only, the same shape as a generic
    // FUNCTION signature's list. A declaration's list cannot nest, so no `>>` splitting is needed.
    // An inline constraint (`<T: Base>`), an empty list, or any other form returns -1 (the host
    // declines to the C# path). Name spans go to outTypeParamStarts/Lengths; the count to
    // outResult[7] (0 with no `<`).
    typeParamCount := 0
    if pos < count && tokens.Kinds[pos] == 100 {
        pos = pos + 1
        while pos < count && tokens.Kinds[pos] != 102 {
            if tokens.Kinds[pos] != 0 {
                return -1
            }
            decl.TypeParamStarts[typeParamCount] = tokens.Starts[pos]
            decl.TypeParamLengths[typeParamCount] = tokens.ValueLengths[pos]
            typeParamCount = typeParamCount + 1
            pos = pos + 1

            if pos < count && tokens.Kinds[pos] != 102 {
                if tokens.Kinds[pos] != 134 {
                    return -1
                }
                pos = pos + 1
                // A consumed comma must be FOLLOWED by another parameter name — a trailing comma
                // (`<T,>`) is a production-parser error (adversarial-review finding: the loop's
                // `!= 102` condition would otherwise exit cleanly and ACCEPT what the pipeline rejects).
                if pos >= count || tokens.Kinds[pos] != 0 {
                    return -1
                }
            }
        }
        if pos >= count || tokens.Kinds[pos] != 102 || typeParamCount == 0 {
            return -1
        }
        pos = pos + 1
    }
    result.Values[7] = typeParamCount

    // Optional BASE / INTERFACE LIST: `class D: Base, IFace {` or `struct S: IFace {` — a `:` (122) after
    // the type name followed by one or more comma-separated SINGLE Identifiers. Composed/generic bases are
    // not modelled and return -1. The host resolves names against type registries and decides which one, if
    // any, is a class base versus implemented interface.
    result.Values[5] = 0
    result.Values[6] = 0
    baseNameCount := 0
    if pos < count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        while true {
            if pos >= count || tokens.Kinds[pos] != 0 {
                return -1
            }
            decl.BaseNameStarts[baseNameCount] = tokens.Starts[pos]
            decl.BaseNameLengths[baseNameCount] = tokens.ValueLengths[pos]
            if baseNameCount == 0 {
                result.Values[5] = tokens.Starts[pos]
                result.Values[6] = tokens.ValueLengths[pos]
            }
            baseNameCount = baseNameCount + 1
            pos = pos + 1

            if pos < count && tokens.Kinds[pos] == 134 {
                pos = pos + 1
                continue
            }
            break
        }
    }
    result.Values[8] = baseNameCount

    if pos >= count || tokens.Kinds[pos] != 129 {
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
    while fieldsDone == 0 && pos < count && tokens.Kinds[pos] != 130 && tokens.Kinds[pos] != 7 {
        if tokens.Kinds[pos] == 63 && pos + 1 < count && tokens.Kinds[pos + 1] == 7 {
            fieldsDone = 1
        } else if tokens.Kinds[pos] == 63 {
            // STATIC FIELD `static name: Type [= <literal>]` or STATIC PROPERTY `static name: Type { ... }` —
            // requires id `:` id; a `{` after the type is the property form (recorded into outPropIndices with
            // outPropStaticFlags = 1, accessor block skipped like an instance property); a non-literal
            // initializer is a general expression (unmodelled, -1).
            if pos + 3 >= count || tokens.Kinds[pos + 1] != 0 || tokens.Kinds[pos + 2] != 122 || tokens.Kinds[pos + 3] != 0 {
                return -1
            }
            if pos + 4 < count && tokens.Kinds[pos + 4] == 129 {
                decl.PropIndices[propCount] = pos + 1
                decl.PropStaticFlags[propCount] = 1
                propCount = propCount + 1
                pos = pos + 4

                sdepth := 0
                sdone := 0
                while pos < count && sdone == 0 {
                    if tokens.Kinds[pos] == 129 {
                        sdepth = sdepth + 1
                    } else if tokens.Kinds[pos] == 130 {
                        sdepth = sdepth - 1
                        if sdepth == 0 {
                            sdone = 1
                        }
                    }
                    pos = pos + 1
                }
                if sdone == 0 {
                    return -1
                }
                continue
            }
            decl.FieldNameStarts[fieldCount] = tokens.Starts[pos + 1]
            decl.FieldNameLengths[fieldCount] = tokens.ValueLengths[pos + 1]
            decl.FieldTypeStarts[fieldCount] = tokens.Starts[pos + 3]
            decl.FieldTypeLengths[fieldCount] = tokens.ValueLengths[pos + 3]
            decl.FieldStaticFlags[fieldCount] = 1
            decl.FieldInitKinds[fieldCount] = -1
            decl.FieldInitStarts[fieldCount] = -1
            decl.FieldInitLengths[fieldCount] = 0
            pos = pos + 4

            if pos < count && tokens.Kinds[pos] == 93 {
                pos = pos + 1
                initStart := pos
                if pos < count && tokens.Kinds[pos] == 89 {
                    pos = pos + 1
                    if pos >= count || (tokens.Kinds[pos] != 1 && tokens.Kinds[pos] != 2) {
                        return -1
                    }
                } else {
                    if pos >= count {
                        return -1
                    }
                    k := tokens.Kinds[pos]
                    if k != 1 && k != 2 && k != 3 && k != 4 && k != 44 && k != 45 {
                        return -1
                    }
                }
                decl.FieldInitKinds[fieldCount] = tokens.Kinds[pos]
                decl.FieldInitStarts[fieldCount] = tokens.Starts[initStart]
                decl.FieldInitLengths[fieldCount] = tokens.Starts[pos] + tokens.ValueLengths[pos] - tokens.Starts[initStart]
                pos = pos + 1
            }

            fieldCount = fieldCount + 1
        } else if tokens.Kinds[pos] == 0 && pos + 1 < count && tokens.Kinds[pos + 1] == 127 {
            fieldsDone = 1
        } else if tokens.Kinds[pos] == 0 && pos + 3 < count && tokens.Kinds[pos + 1] == 122 && tokens.Kinds[pos + 2] == 0 && tokens.Kinds[pos + 3] == 129 {
            decl.PropIndices[propCount] = pos
            decl.PropStaticFlags[propCount] = 0
            propCount = propCount + 1
            pos = pos + 3

            pdepth := 0
            pdone := 0
            while pos < count && pdone == 0 {
                if tokens.Kinds[pos] == 129 {
                    pdepth = pdepth + 1
                } else if tokens.Kinds[pos] == 130 {
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
            if tokens.Kinds[pos] != 0 {
                return -1
            }
            decl.FieldNameStarts[fieldCount] = tokens.Starts[pos]
            decl.FieldNameLengths[fieldCount] = tokens.ValueLengths[pos]
            pos = pos + 1

            if pos >= count || tokens.Kinds[pos] != 122 {
                return -1
            }
            pos = pos + 1

            if pos >= count || tokens.Kinds[pos] != 0 {
                return -1
            }
            fieldTypeStart := tokens.Starts[pos]
            fieldTypeEnd := tokens.Starts[pos] + tokens.ValueLengths[pos]
            pos = pos + 1

            // Optional balanced generic suffix `<...>` after the type name (`Items: List<int>`,
            // `Dictionary<string, Pt>`, `List<List<Pt>>`): identifiers (0) and commas (134) only
            // inside; Less (100) opens, Greater (102) closes one level, and a RightShift (112)
            // closes TWO (the lexer never splits `>>` here — the span scan credits both). The
            // recorded span covers the whole composed type; the host whitespace-strips it to the
            // canonical form. Any other token inside the suffix is unmodelled (-1). TWO ADJACENT
            // identifiers (`List<i nt>`) are a production parse ERROR that the host's whitespace
            // strip would FUSE into a valid name (`int`) — reject them here (adversarial-review
            // finding, probe-confirmed over-acceptance).
            if pos < count && tokens.Kinds[pos] == 100 {
                gdepth := 0
                gdone := 0
                gprevIdent := 0
                while pos < count && gdone == 0 {
                    gk := tokens.Kinds[pos]
                    if gk == 100 {
                        gdepth = gdepth + 1
                        gprevIdent = 0
                    } else if gk == 102 {
                        gdepth = gdepth - 1
                        if gdepth == 0 {
                            gdone = 1
                        }
                        gprevIdent = 0
                    } else if gk == 112 {
                        gdepth = gdepth - 2
                        if gdepth == 0 {
                            gdone = 1
                        }
                        gprevIdent = 0
                    } else if gk == 0 {
                        if gprevIdent == 1 {
                            return -1
                        }
                        gprevIdent = 1
                    } else if gk == 134 {
                        gprevIdent = 0
                    } else {
                        return -1
                    }
                    if gdepth < 0 {
                        return -1
                    }
                    fieldTypeEnd = tokens.Starts[pos] + tokens.ValueLengths[pos]
                    pos = pos + 1
                }
                if gdone == 0 {
                    return -1
                }
            }

            // Optional postfix type suffixes: `[]`, `?`, and `?[]`. This keeps fields aligned with the
            // type-reference kernel for the table-wrapper migration while still refusing tuple/function
            // types and any malformed suffix.
            suffixDone := 0
            while suffixDone == 0 && pos < count {
                if pos + 1 < count && tokens.Kinds[pos] == 131 && tokens.Kinds[pos + 1] == 132 {
                    fieldTypeEnd = tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]
                    pos = pos + 2
                } else if pos + 1 < count && tokens.Kinds[pos] == 119 && tokens.Kinds[pos + 1] == 132 {
                    fieldTypeEnd = tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]
                    pos = pos + 2
                } else if tokens.Kinds[pos] == 115 {
                    fieldTypeEnd = tokens.Starts[pos] + tokens.ValueLengths[pos]
                    pos = pos + 1
                } else {
                    suffixDone = 1
                }
            }
            decl.FieldTypeStarts[fieldCount] = fieldTypeStart
            decl.FieldTypeLengths[fieldCount] = fieldTypeEnd - fieldTypeStart
            decl.FieldStaticFlags[fieldCount] = 0
            decl.FieldInitKinds[fieldCount] = -1
            decl.FieldInitStarts[fieldCount] = -1
            decl.FieldInitLengths[fieldCount] = 0

            fieldCount = fieldCount + 1
        }
    }

    // Members next, in any order: METHODS (`func name(...): ret { body }`) and CONSTRUCTORS (`constructor(...) {
    // body }` — lexed as an Identifier followed by `(`). DELIMIT each: record its keyword/identifier token index
    // (outMethodFuncIndices for a method, outCtorIndices for a constructor), then skip its signature to the body `{`
    // and scan to the matching `}` (balanced). The host parses the signatures/bodies via the existing function
    // kernels at the recorded indices (a constructor's `(params)` and `{body}` parse via the same signature/statement
    // kernels — it has no name token and no `: ret`, so the signature kernel yields name=-1, returnRoot=-1; a
    // constructor INITIALIZER `: this(...)`/`base(...)` is skipped by the signature kernel and parsed separately
    // via ParseConstructorChainInfoInto). A member with no `{` body declines. The host verifies each ctor
    // identifier's text is literally "constructor".
    methodCount := 0
    ctorCount := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        if tokens.Kinds[pos] == 7 {
            decl.MethodFuncIndices[methodCount] = pos
            decl.MethodStaticFlags[methodCount] = 0
            methodCount = methodCount + 1
            pos = pos + 1
        } else if tokens.Kinds[pos] == 63 && pos + 1 < count && tokens.Kinds[pos + 1] == 7 {
            decl.MethodFuncIndices[methodCount] = pos + 1
            decl.MethodStaticFlags[methodCount] = 1
            methodCount = methodCount + 1
            pos = pos + 2
        } else if tokens.Kinds[pos] == 0 && pos + 1 < count && tokens.Kinds[pos + 1] == 127 {
            decl.CtorIndices[ctorCount] = pos
            ctorCount = ctorCount + 1
            pos = pos + 1
        } else {
            return -1
        }

        while pos < count && tokens.Kinds[pos] != 129 && tokens.Kinds[pos] != 130 {
            pos = pos + 1
        }
        if pos >= count || tokens.Kinds[pos] != 129 {
            return -1
        }

        depth := 0
        bodyDone := 0
        while pos < count && bodyDone == 0 {
            if tokens.Kinds[pos] == 129 {
                depth = depth + 1
            } else if tokens.Kinds[pos] == 130 {
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

    if pos >= count || tokens.Kinds[pos] != 130 {
        return -1
    }
    // A FIELDLESS type is legal when it has at least one other member (a pure-behavior class — e.g. an
    // inheritance base with only methods). A fully EMPTY body (no fields, methods, ctors, or properties)
    // still returns -1 (unmodelled shape — the host declines to the C# path).
    if fieldCount == 0 && methodCount == 0 && ctorCount == 0 && propCount == 0 {
        return -1
    }
    result.Values[2] = methodCount
    result.Values[3] = ctorCount
    result.Values[4] = propCount
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
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    args := new ConstructorChainArgTable { Kinds: outArgKinds, Starts: outArgStarts, Lengths: outArgLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseConstructorChainInfoCore(ref tokens, count, ctorIndex, ref args, ref result)
}

func ParseConstructorChainInfoCore(tokens: &ParserDeclarationTokenTable, count: int, ctorIndex: int, args: &ConstructorChainArgTable, result: &ParserDeclarationResultTable): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    result.Values[0] = 0
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
        result.Values[0] = 1
    } else if tokenKinds[pos] == 43 {
        result.Values[0] = 2
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
        args.Kinds[argCount] = tokenKinds[pos]
        args.Starts[argCount] = tokenStarts[pos]
        args.Lengths[argCount] = tokenValueLengths[pos]
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

// Parser slice (union bodies): parse ONE `union Name[<T, U>] { Case { f: T, ... }  Case { ... } }` declaration into
// flat parallel arrays. `unionIndex` is the compacted token index of the `union` keyword (token 12). Reads the union
// NAME (the Identifier after `union`) into outResult[0]=nameStart / outResult[1]=nameLength, an OPTIONAL generic
// type-parameter list `<T, U>` (Less 100 / Identifier 0 / Comma 134 / Greater 102 — the same bare-identifier shape
// as the struct/class kernel; spans to outTypeParamStarts/Lengths, count to outResult[2], 0 with no `<`; an inline
// constraint or empty list returns -1), then `{` (129), then a sequence of CASES until the union close `}` (130).
// Each case is `CaseName { field : Type, ... }`: the case name (Identifier) into outCaseNameStarts/Lengths[case],
// its `{` (129), then a sequence of FIELDS — `Identifier : Type` where the type is a SINGLE Identifier token (a
// builtin like int/string, a bare user-type name, or one of the union's type parameters) — each delimited by an
// optional `,` (134), closed by the case `}` (130). Fields flatten ACROSS all cases into
// outFieldNameStarts/Lengths + outFieldTypeStarts/Lengths in case-then-field order; outCaseFieldCounts[case] records
// how many fields that case contributed (so the host re-segments the flat field arrays per case). Returns the case
// count, or -1 on any unexpected token — a bare case with no `{` body, a primary-ctor `(`, a composed/array/generic
// field type (a non-Identifier after `:`), a field initializer, a missing name/colon/brace, or an empty union — so
// the host declines the whole program to the C# path. Slice scope: unions whose case fields are single
// builtin/bare-name/type-param-typed (the emitter further gates each field type to a supported CLR type).
func ParseUnionDeclarationInto(tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, unionIndex: int, outCaseNameStarts: int[], outCaseNameLengths: int[], outCaseFieldCounts: int[], outFieldNameStarts: int[], outFieldNameLengths: int[], outFieldTypeStarts: int[], outFieldTypeLengths: int[], outTypeParamStarts: int[], outTypeParamLengths: int[], outResult: int[]): int {
    tokens := new ParserDeclarationTokenTable { Kinds: tokenKinds, Starts: tokenStarts, ValueLengths: tokenValueLengths }
    decl := new UnionDeclarationTable { CaseNameStarts: outCaseNameStarts, CaseNameLengths: outCaseNameLengths, CaseFieldCounts: outCaseFieldCounts, FieldNameStarts: outFieldNameStarts, FieldNameLengths: outFieldNameLengths, FieldTypeStarts: outFieldTypeStarts, FieldTypeLengths: outFieldTypeLengths, TypeParamStarts: outTypeParamStarts, TypeParamLengths: outTypeParamLengths }
    result := new ParserDeclarationResultTable { Values: outResult }
    return ParseUnionDeclarationCore(ref tokens, count, unionIndex, ref decl, ref result)
}

func ParseUnionDeclarationCore(tokens: &ParserDeclarationTokenTable, count: int, unionIndex: int, decl: &UnionDeclarationTable, result: &ParserDeclarationResultTable): int {
    tokenKinds := tokens.Kinds
    tokenStarts := tokens.Starts
    tokenValueLengths := tokens.ValueLengths
    pos := unionIndex
    if pos >= count || tokenKinds[pos] != 12 {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokenKinds[pos] != 0 {
        return -1
    }
    result.Values[0] = tokenStarts[pos]
    result.Values[1] = tokenValueLengths[pos]
    pos = pos + 1

    // Optional generic TYPE-PARAMETER list `<T, U>` after the union name — bare comma-separated
    // Identifiers only, the same shape as the struct/class declaration kernel. A declaration's list
    // cannot nest, so no `>>` splitting is needed.
    typeParamCount := 0
    if pos < count && tokenKinds[pos] == 100 {
        pos = pos + 1
        while pos < count && tokenKinds[pos] != 102 {
            if tokenKinds[pos] != 0 {
                return -1
            }
            decl.TypeParamStarts[typeParamCount] = tokenStarts[pos]
            decl.TypeParamLengths[typeParamCount] = tokenValueLengths[pos]
            typeParamCount = typeParamCount + 1
            pos = pos + 1

            if pos < count && tokenKinds[pos] != 102 {
                if tokenKinds[pos] != 134 {
                    return -1
                }
                pos = pos + 1
                // A consumed comma must be FOLLOWED by another parameter name — a trailing comma
                // (`<T,>`) is a production-parser error (adversarial-review finding: the loop's
                // `!= 102` condition would otherwise exit cleanly and ACCEPT what the pipeline rejects).
                if pos >= count || tokenKinds[pos] != 0 {
                    return -1
                }
            }
        }
        if pos >= count || tokenKinds[pos] != 102 || typeParamCount == 0 {
            return -1
        }
        pos = pos + 1
    }
    result.Values[2] = typeParamCount

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
        decl.CaseNameStarts[caseCount] = tokenStarts[pos]
        decl.CaseNameLengths[caseCount] = tokenValueLengths[pos]
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
            decl.FieldNameStarts[totalFields] = tokenStarts[pos]
            decl.FieldNameLengths[totalFields] = tokenValueLengths[pos]
            pos = pos + 1

            if pos >= count || tokenKinds[pos] != 122 {
                return -1
            }
            pos = pos + 1

            if pos >= count || tokenKinds[pos] != 0 {
                return -1
            }
            decl.FieldTypeStarts[totalFields] = tokenStarts[pos]
            decl.FieldTypeLengths[totalFields] = tokenValueLengths[pos]
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

        decl.CaseFieldCounts[caseCount] = caseFieldCount
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
