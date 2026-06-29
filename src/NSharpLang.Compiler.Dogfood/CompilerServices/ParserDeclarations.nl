import System
import System.Text

// First N#-native parser slice: extract the top-level declaration KIND sequence from the
// brace-inserted parser metadata stream produced by TokenizeColumnarSourceInto, matching the
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

struct TopLevelDeclarationIndexTable {
    Indices: int[]
}

struct TopLevelStructLikeDeclarationTable {
    Indices: int[]
    ReferenceFlags: int[]
    RecordFlags: int[]
}

struct TopLevelColumnarFunctionDeclarationTable {
    Indices: int[]
    AsyncFlags: int[]
}

struct TopLevelColumnarNominalDeclarationTable {
    EnumIndices: int[]
    UnionIndices: int[]
    InterfaceIndices: int[]
}

struct TopLevelColumnarProgramDeclarationTable {
    FuncIndices: int[]
    FuncAsyncFlags: int[]
    EnumIndices: int[]
    UnionIndices: int[]
    InterfaceIndices: int[]
    StructIndices: int[]
    StructReferenceFlags: int[]
    StructRecordFlags: int[]
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

struct EnumMemberValueTable {
    Values: int[]
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

struct ParserDeclarationStartKindStream {
    Kinds: int[]
    Starts: int[]
}

struct ParserDeclarationResultTable {
    Values: int[]
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

// Parser slice 2: like TopLevelDeclarationKindsCore, but also records each declaration's NAME span.
// A declaration's name is the token immediately after its keyword (modifiers precede the keyword, so
// nothing sits between keyword and name) when that token is an Identifier (kind 0). For `test "..."`
// the token after the keyword is a string literal, so no name is recorded (outNameStart = -1) -- the
// C# TestDeclaration's string name is out of scope for this slice. The host materializes the name from
// source via outNameStarts/outNameLengths.
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

func TopLevelStructLikeDeclarationIndicesCore(tokens: &ParserDeclarationKindStream, count: int, output: &TopLevelStructLikeDeclarationTable): int {
    outCount := TopLevelStructLikeDeclarationIndicesAppend(ref tokens, count, 9, 1, 0, 0, ref output, 0)
    if outCount < 0 {
        return -1
    }

    outCount = TopLevelStructLikeDeclarationIndicesAppend(ref tokens, count, 13, 0, 1, 1, ref output, outCount)
    if outCount < 0 {
        return -1
    }

    return TopLevelStructLikeDeclarationIndicesAppend(ref tokens, count, 8, 1, 1, 0, ref output, outCount)
}

func TopLevelColumnarNominalDeclarationIndicesCore(tokens: &ParserDeclarationKindStream, count: int, outputs: &TopLevelColumnarNominalDeclarationTable, result: &ParserDeclarationResultTable): int {
    if count < 0 || count > tokens.Kinds.Length || result.Values.Length < 3 {
        return -1
    }

    enumTable := new TopLevelDeclarationIndexTable { Indices: outputs.EnumIndices }
    enumCount := TopLevelDeclarationIndicesCore(ref tokens, count, 14, 0, ref enumTable)
    if enumCount < 0 {
        return -1
    }

    unionTable := new TopLevelDeclarationIndexTable { Indices: outputs.UnionIndices }
    unionCount := TopLevelDeclarationIndicesCore(ref tokens, count, 12, 0, ref unionTable)
    if unionCount < 0 {
        return -1
    }

    interfaceTable := new TopLevelDeclarationIndexTable { Indices: outputs.InterfaceIndices }
    interfaceCount := TopLevelDeclarationIndicesCore(ref tokens, count, 10, 0, ref interfaceTable)
    if interfaceCount < 0 {
        return -1
    }

    result.Values[0] = enumCount
    result.Values[1] = unionCount
    result.Values[2] = interfaceCount
    return enumCount + unionCount + interfaceCount
}

func TopLevelColumnarProgramDeclarationIndicesInto(source: string, rawTokenKinds: int[], rawTokenStarts: int[], rawTokenValueLengths: int[], rawCount: int, compactTokenKinds: int[], compactCount: int, outFuncIndices: int[], outFuncAsyncFlags: int[], outEnumIndices: int[], outUnionIndices: int[], outInterfaceIndices: int[], outStructIndices: int[], outStructReferenceFlags: int[], outStructRecordFlags: int[], outResult: int[]): int {
    rawTokens := new ParserDeclarationTokenTable { Kinds: rawTokenKinds, Starts: rawTokenStarts, ValueLengths: rawTokenValueLengths }
    compactTokens := new ParserDeclarationKindStream { Kinds: compactTokenKinds }
    outputs := new TopLevelColumnarProgramDeclarationTable { FuncIndices: outFuncIndices, FuncAsyncFlags: outFuncAsyncFlags, EnumIndices: outEnumIndices, UnionIndices: outUnionIndices, InterfaceIndices: outInterfaceIndices, StructIndices: outStructIndices, StructReferenceFlags: outStructReferenceFlags, StructRecordFlags: outStructRecordFlags }
    result := new ParserDeclarationResultTable { Values: outResult }
    return TopLevelColumnarProgramDeclarationIndicesCore(source, ref rawTokens, rawCount, ref compactTokens, compactCount, ref outputs, ref result)
}

func TopLevelColumnarProgramDeclarationIndicesCore(source: string, rawTokens: &ParserDeclarationTokenTable, rawCount: int, compactTokens: &ParserDeclarationKindStream, compactCount: int, outputs: &TopLevelColumnarProgramDeclarationTable, result: &ParserDeclarationResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    functionOutputs := new TopLevelColumnarFunctionDeclarationTable { Indices: outputs.FuncIndices, AsyncFlags: outputs.FuncAsyncFlags }
    functionResult := new ParserDeclarationResultTable { Values: new int[](2) }
    functionCount := TopLevelColumnarFunctionDeclarationIndicesCore(source, ref rawTokens, rawCount, ref compactTokens, compactCount, ref functionOutputs, ref functionResult)
    if functionCount < 0 {
        return -1
    }

    names := new TopLevelDeclarationNameTable { Kinds: new int[](rawCount + 1), NameStarts: new int[](rawCount + 1), NameLengths: new int[](rawCount + 1) }
    nameCount := TopLevelDeclarationNameSpansCore(ref rawTokens, rawCount, ref names)
    if nameCount != functionResult.Values[0] {
        return -1
    }

    if TopLevelTypeDeclarationNamesDistinct(source, ref names, nameCount) == 0 {
        return -1
    }

    nominalOutputs := new TopLevelColumnarNominalDeclarationTable { EnumIndices: outputs.EnumIndices, UnionIndices: outputs.UnionIndices, InterfaceIndices: outputs.InterfaceIndices }
    nominalResult := new ParserDeclarationResultTable { Values: new int[](3) }
    nominalCount := TopLevelColumnarNominalDeclarationIndicesCore(ref compactTokens, compactCount, ref nominalOutputs, ref nominalResult)
    if nominalCount < 0 {
        return -1
    }

    structOutputs := new TopLevelStructLikeDeclarationTable { Indices: outputs.StructIndices, ReferenceFlags: outputs.StructReferenceFlags, RecordFlags: outputs.StructRecordFlags }
    structCount := TopLevelStructLikeDeclarationIndicesCore(ref compactTokens, compactCount, ref structOutputs)
    if structCount < 0 {
        return -1
    }

    result.Values[0] = functionResult.Values[0]
    result.Values[1] = functionCount
    result.Values[2] = nominalResult.Values[0]
    result.Values[3] = nominalResult.Values[1]
    result.Values[4] = nominalResult.Values[2]
    result.Values[5] = structCount
    return functionCount + nominalCount + structCount
}

func TopLevelTypeDeclarationNamesDistinct(source: string, decls: &TopLevelDeclarationNameTable, declCount: int): int {
    if declCount < 0 {
        return 0
    }

    i := 0
    while i < declCount {
        if IsTopLevelTypeDeclarationKind(decls.Kinds[i]) {
            if decls.NameStarts[i] < 0 || decls.NameLengths[i] <= 0 {
                return 0
            }

            j := i + 1
            while j < declCount {
                if IsTopLevelTypeDeclarationKind(decls.Kinds[j]) {
                    if decls.NameStarts[j] < 0 || decls.NameLengths[j] <= 0 {
                        return 0
                    }

                    if ParserDeclarationSourceSpansEqual(source, decls.NameStarts[i], decls.NameLengths[i], decls.NameStarts[j], decls.NameLengths[j]) {
                        return 0
                    }
                }

                j = j + 1
            }
        }

        i = i + 1
    }

    return 1
}

func IsTopLevelTypeDeclarationKind(kind: int): bool {
    return kind == 8 || kind == 9 || kind == 10 || kind == 12 || kind == 13 || kind == 14
}

func TopLevelStructLikeDeclarationIndicesAppend(tokens: &ParserDeclarationKindStream, count: int, targetKind: int, suppressWhereClause: int, isReference: int, isRecord: int, output: &TopLevelStructLikeDeclarationTable, startCount: int): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := startCount
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
            } else if kind == targetKind && (suppressWhereClause == 0 || !inWhereClause) {
                if outCount >= output.Indices.Length || outCount >= output.ReferenceFlags.Length || outCount >= output.RecordFlags.Length {
                    return -1
                }

                output.Indices[outCount] = i
                output.ReferenceFlags[outCount] = isReference
                output.RecordFlags[outCount] = isRecord
                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

func TopLevelColumnarFunctionDeclarationIndicesCore(source: string, rawTokens: &ParserDeclarationTokenTable, rawCount: int, compactTokens: &ParserDeclarationKindStream, compactCount: int, outputs: &TopLevelColumnarFunctionDeclarationTable, result: &ParserDeclarationResultTable): int {
    if rawCount < 0 || compactCount < 0 || rawCount > rawTokens.Kinds.Length || rawCount > rawTokens.Starts.Length || rawCount > rawTokens.ValueLengths.Length || compactCount > compactTokens.Kinds.Length || result.Values.Length < 2 {
        return -1
    }

    if TopLevelContextualTestDeclarationExistsCore(source, ref rawTokens, rawCount) != 0 {
        return -1
    }

    decls := new TopLevelDeclarationKindTable { Kinds: new int[](rawCount + 1) }
    rawKindStream := new ParserDeclarationKindStream { Kinds: rawTokens.Kinds }
    declCount := TopLevelDeclarationKindsCore(ref rawKindStream, rawCount, ref decls)
    if declCount <= 0 {
        return -1
    }

    i := 0
    while i < declCount {
        kind := decls.Kinds[i]
        if kind != 7 && kind != 14 && kind != 9 && kind != 13 && kind != 12 && kind != 8 && kind != 10 {
            return -1
        }

        i = i + 1
    }

    names := new TopLevelDeclarationNameTable { Kinds: new int[](rawCount + 1), NameStarts: new int[](rawCount + 1), NameLengths: new int[](rawCount + 1) }
    nameCount := TopLevelDeclarationNameSpansCore(ref rawTokens, rawCount, ref names)
    if nameCount != declCount {
        return -1
    }

    if TopLevelFunctionDeclarationNamesDistinct(source, ref names, nameCount) == 0 {
        return -1
    }

    modifiers := new TopLevelDeclarationModifierTable { Kinds: new int[](rawCount + 1), Modifiers: new int[](rawCount + 1) }
    modifierCount := TopLevelDeclarationModifiersCore(ref rawKindStream, rawCount, ref modifiers)
    if modifierCount != declCount {
        return -1
    }

    indices := new TopLevelDeclarationIndexTable { Indices: outputs.Indices }
    funcCount := TopLevelDeclarationIndicesCore(ref compactTokens, compactCount, 7, 0, ref indices)
    if funcCount < 0 || funcCount > outputs.AsyncFlags.Length {
        return -1
    }

    asyncCount := 0
    i = 0
    while i < declCount {
        if decls.Kinds[i] == 7 {
            if asyncCount >= outputs.AsyncFlags.Length {
                return -1
            }

            asyncFlag := 0
            if (modifiers.Modifiers[i] & 2048) != 0 {
                asyncFlag = 1
            }

            outputs.AsyncFlags[asyncCount] = asyncFlag
            asyncCount = asyncCount + 1
        }

        i = i + 1
    }

    if asyncCount != funcCount {
        return -1
    }

    if TopLevelFunctionPreamblesAreValidCore(ref compactTokens, compactCount, ref indices, funcCount) == 0 {
        return -1
    }

    result.Values[0] = declCount
    result.Values[1] = funcCount
    return funcCount
}

func TopLevelFunctionDeclarationNamesDistinct(source: string, decls: &TopLevelDeclarationNameTable, declCount: int): int {
    if declCount < 0 {
        return 0
    }

    i := 0
    while i < declCount {
        if decls.Kinds[i] == 7 {
            if decls.NameStarts[i] < 0 || decls.NameLengths[i] <= 0 {
                return 0
            }

            j := i + 1
            while j < declCount {
                if decls.Kinds[j] == 7 {
                    if decls.NameStarts[j] < 0 || decls.NameLengths[j] <= 0 {
                        return 0
                    }

                    if ParserDeclarationSourceSpansEqual(source, decls.NameStarts[i], decls.NameLengths[i], decls.NameStarts[j], decls.NameLengths[j]) {
                        return 0
                    }
                }

                j = j + 1
            }
        }

        i = i + 1
    }

    return 1
}

func TopLevelDeclarationIndicesCore(tokens: &ParserDeclarationKindStream, count: int, targetKind: int, suppressWhereClause: int, indices: &TopLevelDeclarationIndexTable): int {
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
            } else if kind == targetKind && (suppressWhereClause == 0 || !inWhereClause) {
                if outCount >= indices.Indices.Length {
                    return -1
                }

                indices.Indices[outCount] = i
                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

// Parser declaration safety guard for top-level functions. The declaration scans intentionally skip
// unknown depth-0 tokens, so this validates the token immediately before each `func` keyword: only
// recognized modifiers (`static`, `async`), a previous declaration close, a package/namespace import
// dotted header prefix, or a quoted file-import header may precede a top-level function. Returns 1
// when every function preamble is valid.
func TopLevelFunctionPreamblesAreValidCore(tokens: &ParserDeclarationKindStream, count: int, indices: &TopLevelDeclarationIndexTable, funcCount: int): int {
    i := 0
    while i < funcCount {
        funcIndex := indices.Indices[i]
        if funcIndex < 0 || funcIndex >= count || tokens.Kinds[funcIndex] != 7 {
            return 0
        }

        preceding := funcIndex - 1
        while preceding >= 0 && (tokens.Kinds[preceding] == 63 || tokens.Kinds[preceding] == 68) {
            preceding = preceding - 1
        }

        if preceding >= 0 && tokens.Kinds[preceding] != 130 {
            if tokens.Kinds[preceding] == 4 {
                if preceding - 1 < 0 || tokens.Kinds[preceding - 1] != 17 {
                    return 0
                }

                i = i + 1
                continue
            }

            headerWalk := preceding
            while headerWalk >= 0 && (tokens.Kinds[headerWalk] == 0 || tokens.Kinds[headerWalk] == 124) {
                headerWalk = headerWalk - 1
            }

            if headerWalk == preceding || headerWalk < 0 || (tokens.Kinds[headerWalk] != 17 && tokens.Kinds[headerWalk] != 18) {
                return 0
            }
        }

        i = i + 1
    }

    return 1
}

// Parser declaration utility: the compacted-token index of the `}` (130) that closes the `{` (129)
// at `open`, or -1 if `open` is not a left brace or the brace run is unbalanced. This keeps property
// accessor body delimiting in the N# parser path instead of leaving a C# adapter-side scanner.
func MatchingCloseBraceCore(tokens: &ParserDeclarationKindStream, count: int, open: int): int {
    if open < 0 || open >= count || tokens.Kinds[open] != 129 {
        return -1
    }

    depth := 0
    i := open
    while i < count {
        kind := tokens.Kinds[i]
        if kind == 129 {
            depth = depth + 1
        } else if kind == 130 {
            depth = depth - 1
            if depth == 0 {
                return i
            }
        }

        i = i + 1
    }

    return -1
}

// Parser declaration utility: find the compacted-token index whose kind and source start match a
// parser-node source span. Used for local-function statement nodes, where the statement parser
// records the `func` keyword span and the adapter must re-enter the declaration parser at that token.
func TokenIndexByKindStartCore(tokens: &ParserDeclarationStartKindStream, count: int, targetKind: int, targetStart: int): int {
    i := 0
    while i < count {
        if tokens.Kinds[i] == targetKind && tokens.Starts[i] == targetStart {
            return i
        }

        i = i + 1
    }

    return -1
}

// Parser declaration utility: parse one computed property accessor block already discovered by
// ParseStructDeclarationCore. Returns 0 for get-only, 1 for get/set, or -1 for unsupported shapes.
// outResult: [0]=nameStart, [1]=nameLength, [2]=typeStart, [3]=typeLength,
// [4]=getBodyBraceIndex, [5]=setBodyBraceIndex-or--1.
// Flattened ParsePropertyAccessor*Into ABIs live in the parity corpus; product callers compose this
// core through ParserColumnarProperties.nl.
func ParsePropertyAccessorInfoCore(source: string, tokens: &ParserDeclarationTokenTable, count: int, propIndex: int, result: &ParserDeclarationResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    if count < 0 {
        return -1
    }

    if count > tokens.Kinds.Length {
        return -1
    }

    if count > tokens.Starts.Length {
        return -1
    }

    if count > tokens.ValueLengths.Length {
        return -1
    }

    if propIndex < 0 || propIndex + 5 >= count {
        return -1
    }

    if tokens.Kinds[propIndex] != 0 || tokens.Kinds[propIndex + 1] != 122 || tokens.Kinds[propIndex + 2] != 0 || tokens.Kinds[propIndex + 3] != 129 {
        return -1
    }

    if tokens.Kinds[propIndex + 4] != 0 || !ParserDeclarationTokenTextEquals(source, tokens.Starts[propIndex + 4], tokens.ValueLengths[propIndex + 4], "get") {
        return -1
    }

    if tokens.Kinds[propIndex + 5] != 129 {
        return -1
    }

    getBodyBrace := propIndex + 5
    kindStream := new ParserDeclarationKindStream { Kinds: tokens.Kinds }
    getBodyEnd := MatchingCloseBraceCore(ref kindStream, count, getBodyBrace)
    if getBodyEnd < 0 {
        return -1
    }

    result.Values[0] = tokens.Starts[propIndex]
    result.Values[1] = tokens.ValueLengths[propIndex]
    result.Values[2] = tokens.Starts[propIndex + 2]
    result.Values[3] = tokens.ValueLengths[propIndex + 2]
    result.Values[4] = getBodyBrace
    result.Values[5] = -1

    after := getBodyEnd + 1
    if after < count && tokens.Kinds[after] == 130 {
        return 0
    }

    if after + 1 < count && tokens.Kinds[after] == 0 && ParserDeclarationTokenTextEquals(source, tokens.Starts[after], tokens.ValueLengths[after], "set") && tokens.Kinds[after + 1] == 129 {
        setBodyBrace := after + 1
        setBodyEnd := MatchingCloseBraceCore(ref kindStream, count, setBodyBrace)
        if setBodyEnd < 0 || setBodyEnd + 1 >= count || tokens.Kinds[setBodyEnd + 1] != 130 {
            return -1
        }

        result.Values[5] = setBodyBrace
        return 1
    }

    return -1
}

func TopLevelContextualTestDeclarationExistsCore(source: string, tokens: &ParserDeclarationTokenTable, count: int): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0

    i := 0
    while i < count {
        kind := tokens.Kinds[i]
        if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            if kind == 73 {
                return 1
            }

            if kind == 0 {
                nextKind := ParserDeclarationNextNonNewlineTokenKind(ref tokens, count, i + 1)
                atDeclarationBoundary := ParserDeclarationIsTopLevelDeclarationBoundaryBefore(ref tokens, i)
                if ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "test")
                    && (nextKind == 4 || nextKind == 129 || atDeclarationBoundary) {
                    return 1
                }

                if (ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "setup")
                        || ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "teardown"))
                    && (nextKind == 129 || atDeclarationBoundary) {
                    return 1
                }
            }
        }

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
        }

        i = i + 1
    }

    return 0
}

func ParserDeclarationNextNonNewlineTokenKind(tokens: &ParserDeclarationTokenTable, count: int, startIndex: int): int {
    i := startIndex
    while i < count {
        if tokens.Kinds[i] != 136 {
            return tokens.Kinds[i]
        }

        i = i + 1
    }

    return -1
}

func ParserDeclarationIsTopLevelDeclarationBoundaryBefore(tokens: &ParserDeclarationTokenTable, index: int): bool {
    if index <= 0 {
        return true
    }

    previousKind := tokens.Kinds[index - 1]
    return previousKind == 136 || previousKind == 130 || previousKind == 133
}

func ParserDeclarationTokenTextEquals(source: string, start: int, length: int, expected: string): bool {
    if start < 0 || length != expected.Length || start + length > source.Length {
        return false
    }

    i := 0
    while i < length {
        if source[start + i] != expected[i] {
            return false
        }

        i = i + 1
    }

    return true
}

// Product interface declaration core. Flattened ParseInterfaceDeclaration* ABIs live in the
// parity corpus; product callers compose this core through ParserInterfaceSignatures.nl.
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

func ParseEnumMemberValuesCore(source: string, members: &EnumMemberTable, memberCount: int, values: &EnumMemberValueTable): bool {
    if memberCount < 0 || memberCount > values.Values.Length {
        return false
    }

    nextValue := 0
    i := 0
    while i < memberCount {
        value := nextValue
        if members.HasValue[i] != 0 {
            if !ParserDeclarationTryParseIntLiteralCore(source, members.ValueStarts[i], members.ValueLengths[i], ref values, i) {
                return false
            }
            value = values.Values[i]
        } else {
            values.Values[i] = value
        }

        nextValue = ParserDeclarationNextEnumValue(value)
        i = i + 1
    }

    return true
}

func ParserDeclarationSpanText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    return source.Substring(start, length)
}

func ParserDeclarationSourceSpansEqual(source: string, leftStart: int, leftLength: int, rightStart: int, rightLength: int): bool {
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

func ParserDeclarationNextEnumValue(value: int): int {
    if value == 2147483647 {
        return 0 - 2147483647 - 1
    }

    return value + 1
}

func ParserDeclarationTryParseIntLiteralCore(source: string, start: int, length: int, result: &EnumMemberValueTable, resultIndex: int): bool {
    if start < 0 || length <= 0 || start + length > source.Length || resultIndex < 0 || resultIndex >= result.Values.Length {
        return false
    }

    negative := false
    index := start
    end := start + length
    if source[index] == '+' || source[index] == '-' {
        negative = source[index] == '-'
        index = index + 1
        if index >= end {
            return false
        }
    }

    value := 0
    while index < end {
        ch := source[index]
        if ch < '0' || ch > '9' {
            return false
        }

        digit := ch - '0'
        if value > 214748364 {
            return false
        }

        if value == 214748364 {
            if negative {
                if digit == 8 && index == end - 1 {
                    result.Values[resultIndex] = 0 - 2147483647 - 1
                    return true
                }

                return false
            }

            if digit > 7 {
                return false
            }
        }

        value = value * 10 + digit
        index = index + 1
    }

    if negative {
        result.Values[resultIndex] = 0 - value
    } else {
        result.Values[resultIndex] = value
    }

    return true
}

// Product enum declaration core. Flattened ParseEnumDeclaration* ABIs live in the parity corpus;
// product callers compose this core through ParserColumnarEnums.nl.
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

func ParserDeclarationCanonicalTypeText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    hasGenericSuffix := false
    i := 0
    while i < length {
        if source[start + i] == '<' {
            hasGenericSuffix = true
            break
        }

        i = i + 1
    }

    if !hasGenericSuffix {
        return source.Substring(start, length)
    }

    builder := new StringBuilder(length)
    i = 0
    while i < length {
        ch := source[start + i]
        if !Char.IsWhiteSpace(ch) {
            builder.Append(ch)
        }

        i = i + 1
    }

    return builder.ToString()
}

// Parse one struct/class/record declaration into wrapper-owned declaration tables. The flattened
// ParseStructDeclaration* ABIs live in the parity corpus; product callers compose this core directly.
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
    // via ParseConstructorChainInfoCore, with the composed constructor core verifying the identifier text.
    // A member with no `{` body declines.
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
// (134), closed by `)` (128). outResult[0] = the initializer kind (0 = none, 1 = this, 2 = base);
// outResult[1] = the constructor BODY `{` token index, or -1 if it is missing. Returns the chained-arg count, or
// -1 on a malformed initializer or a non-{identifier,int-literal} arg (a complex expression / string /
// other literal — the host declines such a chaining ctor to the C# path).
// Product constructor-chain core. Flattened ParseConstructor*Into ABIs live in the parity corpus;
// product callers compose this core through ParserConstructorSignatures.nl.
func ParseConstructorChainInfoCore(tokens: &ParserDeclarationTokenTable, count: int, ctorIndex: int, args: &ConstructorChainArgTable, result: &ParserDeclarationResultTable): int {
    result.Values[0] = 0
    result.Values[1] = -1
    pos := ctorIndex + 1
    if pos >= count || tokens.Kinds[pos] != 127 {
        return 0
    }

    pdepth := 0
    pdone := 0
    while pos < count && pdone == 0 {
        if tokens.Kinds[pos] == 127 {
            pdepth = pdepth + 1
        } else if tokens.Kinds[pos] == 128 {
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

    if pos >= count || tokens.Kinds[pos] != 122 {
        if pos < count && tokens.Kinds[pos] == 129 {
            result.Values[1] = pos
        }
        return 0
    }
    pos = pos + 1

    if pos >= count {
        return -1
    }
    if tokens.Kinds[pos] == 42 {
        result.Values[0] = 1
    } else if tokens.Kinds[pos] == 43 {
        result.Values[0] = 2
    } else {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }
    pos = pos + 1

    argCount := 0
    while pos < count && tokens.Kinds[pos] != 128 {
        if tokens.Kinds[pos] != 0 && tokens.Kinds[pos] != 1 {
            return -1
        }
        args.Kinds[argCount] = tokens.Kinds[pos]
        args.Starts[argCount] = tokens.Starts[pos]
        args.Lengths[argCount] = tokens.ValueLengths[pos]
        argCount = argCount + 1
        pos = pos + 1

        if pos < count && tokens.Kinds[pos] != 128 {
            if tokens.Kinds[pos] != 134 {
                return -1
            }
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }
    pos = pos + 1
    if pos < count && tokens.Kinds[pos] == 129 {
        result.Values[1] = pos
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
func ParseUnionDeclarationCore(tokens: &ParserDeclarationTokenTable, count: int, unionIndex: int, decl: &UnionDeclarationTable, result: &ParserDeclarationResultTable): int {
    pos := unionIndex
    if pos >= count || tokens.Kinds[pos] != 12 {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }
    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    // Optional generic TYPE-PARAMETER list `<T, U>` after the union name — bare comma-separated
    // Identifiers only, the same shape as the struct/class declaration kernel. A declaration's list
    // cannot nest, so no `>>` splitting is needed.
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
    result.Values[2] = typeParamCount

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    caseCount := 0
    totalFields := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        if tokens.Kinds[pos] != 0 {
            return -1
        }
        decl.CaseNameStarts[caseCount] = tokens.Starts[pos]
        decl.CaseNameLengths[caseCount] = tokens.ValueLengths[pos]
        pos = pos + 1

        if pos >= count || tokens.Kinds[pos] != 129 {
            return -1
        }
        pos = pos + 1

        caseFieldCount := 0
        while pos < count && tokens.Kinds[pos] != 130 {
            if tokens.Kinds[pos] != 0 {
                return -1
            }
            decl.FieldNameStarts[totalFields] = tokens.Starts[pos]
            decl.FieldNameLengths[totalFields] = tokens.ValueLengths[pos]
            pos = pos + 1

            if pos >= count || tokens.Kinds[pos] != 122 {
                return -1
            }
            pos = pos + 1

            if pos >= count || tokens.Kinds[pos] != 0 {
                return -1
            }
            decl.FieldTypeStarts[totalFields] = tokens.Starts[pos]
            decl.FieldTypeLengths[totalFields] = tokens.ValueLengths[pos]
            pos = pos + 1

            totalFields = totalFields + 1
            caseFieldCount = caseFieldCount + 1

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
        pos = pos + 1

        decl.CaseFieldCounts[caseCount] = caseFieldCount
        caseCount = caseCount + 1
    }

    if pos >= count || tokens.Kinds[pos] != 130 {
        return -1
    }
    if caseCount == 0 {
        return -1
    }
    return caseCount
}
