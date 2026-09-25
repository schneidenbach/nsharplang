import NSharpLang.Compiler


// THE TOP-LEVEL SCAN: package and namespace spans, declaration modifiers, kinds, names and arity,
// and the index streams every later kernel addresses a declaration through.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.

// First N#-native parser slice: extract the top-level declaration KIND sequence from the
// brace-inserted parser metadata stream produced by TokenizeColumnarSourceInto. A top-level
// declaration is a declaration keyword that appears at brace/bracket/paren depth 0 -- i.e. not nested
// inside a type body ({...}), an attribute list ([...]), or a parameter/argument list ((...)). Leading
// modifiers (public/static/...) and attributes ([Foo]) are naturally skipped because they are not
// declaration keywords; `ref struct` and `duck interface` are captured at their `struct`/`interface`
// keyword. Returns the
// number of declarations and writes each declaration's keyword TokenType ordinal into outKinds.
//
// Recognized declaration keyword ordinals (TokenType, see Token.cs): Func=7, Class=8, Struct=9,
// Interface=10, Union=12, Record=13, Enum=14, Type=72, Test=73. (The contextual `setup`/`teardown`
// declarations and preprocessor declarations are intentionally out of scope for this first slice;
// corpora that exercise this kernel avoid them.)
// Parser slice 3: the file's package name span: the dotted name after a top-level `package` keyword
// (`package A.B.C`); a file has at most one. This records the
// span covering the dotted name (first identifier start through the last identifier's end, so the host
// materializes "A.B.C"). Returns 1 and fills outResult[0]=start, outResult[1]=length when a package is
// present; returns 0 otherwise. The package keyword is only
// recognized at depth 0, before any declaration body.
class NamespaceImportTable {
    NsStarts: int[]
    NsLengths: int[]
    AliasStarts: int[]
    AliasLengths: int[]
    constructor(nsStarts: int[], nsLengths: int[], aliasStarts: int[], aliasLengths: int[]) {
        NsStarts = nsStarts
        NsLengths = nsLengths
        AliasStarts = aliasStarts
        AliasLengths = aliasLengths
    }
}

class TopLevelDeclarationModifierTable {
    Kinds: int[]
    Modifiers: int[]
    constructor(kinds: int[], modifiers: int[]) {
        Kinds = kinds
        Modifiers = modifiers
    }
}

class TopLevelDeclarationKindTable {
    Kinds: int[]
    constructor(kinds: int[]) {
        Kinds = kinds
    }
}

class TopLevelDeclarationIndexTable {
    Indices: int[]
    constructor(indices: int[]) {
        Indices = indices
    }
}

class TopLevelStructLikeDeclarationTable {
    Indices: int[]
    ReferenceFlags: int[]
    RecordFlags: int[]
    constructor(indices: int[], referenceFlags: int[], recordFlags: int[]) {
        Indices = indices
        ReferenceFlags = referenceFlags
        RecordFlags = recordFlags
    }
}

class TopLevelColumnarFunctionDeclarationTable {
    Indices: int[]
    AsyncFlags: int[]
    GeneratorFlags: int[]
    constructor(indices: int[], asyncFlags: int[], generatorFlags: int[]) {
        Indices = indices
        AsyncFlags = asyncFlags
        GeneratorFlags = generatorFlags
    }
}

class TopLevelColumnarNominalDeclarationTable {
    EnumIndices: int[]
    UnionIndices: int[]
    InterfaceIndices: int[]
    constructor(enumIndices: int[], unionIndices: int[], interfaceIndices: int[]) {
        EnumIndices = enumIndices
        UnionIndices = unionIndices
        InterfaceIndices = interfaceIndices
    }
}

class TopLevelColumnarProgramDeclarationTable {
    FuncIndices: int[]
    FuncAsyncFlags: int[]
    FuncGeneratorFlags: int[]
    EnumIndices: int[]
    UnionIndices: int[]
    InterfaceIndices: int[]
    StructIndices: int[]
    StructReferenceFlags: int[]
    StructRecordFlags: int[]
    constructor(funcIndices: int[], funcAsyncFlags: int[], funcGeneratorFlags: int[], enumIndices: int[], unionIndices: int[], interfaceIndices: int[], structIndices: int[], structReferenceFlags: int[], structRecordFlags: int[]) {
        FuncIndices = funcIndices
        FuncAsyncFlags = funcAsyncFlags
        FuncGeneratorFlags = funcGeneratorFlags
        EnumIndices = enumIndices
        UnionIndices = unionIndices
        InterfaceIndices = interfaceIndices
        StructIndices = structIndices
        StructReferenceFlags = structReferenceFlags
        StructRecordFlags = structRecordFlags
    }
}

class TopLevelDeclarationNameTable {
    Kinds: int[]
    Indices: int[]
    NameStarts: int[]
    NameLengths: int[]
    constructor(kinds: int[], indices: int[], nameStarts: int[], nameLengths: int[]) {
        Kinds = kinds
        Indices = indices
        NameStarts = nameStarts
        NameLengths = nameLengths
    }
}

class InterfaceDeclarationTable {
    MethodFuncIndices: int[]
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    // `event Name: DelegateType` members, in written order. An interface event is TWO abstract
    // accessor slots plus an `EventInfo` row, so the only facts the row carries are the name and the
    // handler type — there is no body, no storage and no parameter list to record.
    EventNameStarts: int[]
    EventNameLengths: int[]
    EventTypeStarts: int[]
    EventTypeLengths: int[]
    // `Name: Type` members, in written order. An interface's VALUE member is written bare, exactly as
    // a class writes one, and what it declares is a get-only abstract property slot — so the only
    // facts a row carries are the name and the member type.
    PropertyNameStarts: int[]
    PropertyNameLengths: int[]
    PropertyTypeStarts: int[]
    PropertyTypeLengths: int[]
    Where: ParserDeclarationWhereTable
    constructor(methodFuncIndices: int[], baseNameStarts: int[], baseNameLengths: int[], typeParamStarts: int[], typeParamLengths: int[], whereTable: ParserDeclarationWhereTable, eventNameStarts: int[]? = null, eventNameLengths: int[]? = null, eventTypeStarts: int[]? = null, eventTypeLengths: int[]? = null, propertyNameStarts: int[]? = null, propertyNameLengths: int[]? = null, propertyTypeStarts: int[]? = null, propertyTypeLengths: int[]? = null) {
        MethodFuncIndices = methodFuncIndices
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
        EventNameStarts = eventNameStarts ?? new int[](0)
        EventNameLengths = eventNameLengths ?? new int[](0)
        EventTypeStarts = eventTypeStarts ?? new int[](0)
        EventTypeLengths = eventTypeLengths ?? new int[](0)
        PropertyNameStarts = propertyNameStarts ?? new int[](0)
        PropertyNameLengths = propertyNameLengths ?? new int[](0)
        PropertyTypeStarts = propertyTypeStarts ?? new int[](0)
        PropertyTypeLengths = propertyTypeLengths ?? new int[](0)
        Where = whereTable
    }
}

class EnumMemberTable {
    NameStarts: int[]
    NameLengths: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    HasValue: int[]
    // THE TOKEN INDEX OF EACH MEMBER'S NAME, which is what an attribute reader needs and a source
    // span cannot give it: `ColumnarSourceAttributes.Read` walks BACKWARD from a declaration's token
    // to collect the `[...]` groups written above it, and a member name's offset in the source says
    // nothing about where the token stream stands.
    NameTokens: int[]
    constructor(nameStarts: int[], nameLengths: int[], valueStarts: int[], valueLengths: int[], hasValue: int[], nameTokens: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        HasValue = hasValue
        NameTokens = nameTokens
    }
}

class EnumMemberValueTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

class StructDeclarationTable {
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    FieldStaticFlags: int[]
    FieldInitKinds: int[]
    FieldInitStarts: int[]
    FieldInitLengths: int[]
    // The TOKEN index of each field initializer's first token (-1 with no initializer). The source
    // span above names the initializer for metadata and diagnostics; this column is what lets the
    // static-initializer body re-enter the ordinary expression parser at exactly that token.
    FieldInitTokens: int[]
    // The TOKEN index of each field's NAME token (-1 for a field synthesized from a primary
    // constructor parameter, which has no member position of its own). An attribute written on a
    // field is read by scanning BACK from this token, exactly the way a method's, a property's and a
    // constructor's are read from theirs, so a field's `[...]` needs no second reader.
    FieldDeclTokens: int[]
    MethodFuncIndices: int[]
    MethodStaticFlags: int[]
    MethodModifierFlags: int[]
    CtorIndices: int[]
    PropIndices: int[]
    PropStaticFlags: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    Where: ParserDeclarationWhereTable
    constructor(fieldNameStarts: int[], fieldNameLengths: int[], fieldTypeStarts: int[], fieldTypeLengths: int[], fieldStaticFlags: int[], fieldInitKinds: int[], fieldInitStarts: int[], fieldInitLengths: int[], fieldInitTokens: int[], fieldDeclTokens: int[], methodFuncIndices: int[], methodStaticFlags: int[], methodModifierFlags: int[], ctorIndices: int[], propIndices: int[], propStaticFlags: int[], typeParamStarts: int[], typeParamLengths: int[], baseNameStarts: int[], baseNameLengths: int[], whereTable: ParserDeclarationWhereTable) {
        FieldNameStarts = fieldNameStarts
        FieldNameLengths = fieldNameLengths
        FieldTypeStarts = fieldTypeStarts
        FieldTypeLengths = fieldTypeLengths
        FieldStaticFlags = fieldStaticFlags
        FieldInitKinds = fieldInitKinds
        FieldInitStarts = fieldInitStarts
        FieldInitLengths = fieldInitLengths
        FieldInitTokens = fieldInitTokens
        FieldDeclTokens = fieldDeclTokens
        MethodFuncIndices = methodFuncIndices
        MethodStaticFlags = methodStaticFlags
        MethodModifierFlags = methodModifierFlags
        CtorIndices = ctorIndices
        PropIndices = propIndices
        PropStaticFlags = propStaticFlags
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
        Where = whereTable
    }
}

class PrimaryConstructorParameterTable {
    NameStarts: int[]
    NameLengths: int[]
    TypeStarts: int[]
    TypeLengths: int[]
    DefaultKinds: int[]
    DefaultStarts: int[]
    DefaultLengths: int[]
    constructor(nameStarts: int[], nameLengths: int[], typeStarts: int[], typeLengths: int[], defaultKinds: int[], defaultStarts: int[], defaultLengths: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        TypeStarts = typeStarts
        TypeLengths = typeLengths
        DefaultKinds = defaultKinds
        DefaultStarts = defaultStarts
        DefaultLengths = defaultLengths
    }
}

class ConstructorChainArgTable {
    Kinds: int[]
    Starts: int[]
    Lengths: int[]
    Names: string[]
    constructor(kinds: int[], starts: int[], lengths: int[], names: string[]) {
        Kinds = kinds
        Starts = starts
        Lengths = lengths
        Names = names
    }
}

class UnionDeclarationTable {
    CaseNameStarts: int[]
    CaseNameLengths: int[]
    CaseFieldCounts: int[]
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    Where: ParserDeclarationWhereTable
    constructor(caseNameStarts: int[], caseNameLengths: int[], caseFieldCounts: int[], fieldNameStarts: int[], fieldNameLengths: int[], fieldTypeStarts: int[], fieldTypeLengths: int[], typeParamStarts: int[], typeParamLengths: int[], whereTable: ParserDeclarationWhereTable) {
        CaseNameStarts = caseNameStarts
        CaseNameLengths = caseNameLengths
        CaseFieldCounts = caseFieldCounts
        FieldNameStarts = fieldNameStarts
        FieldNameLengths = fieldNameLengths
        FieldTypeStarts = fieldTypeStarts
        FieldTypeLengths = fieldTypeLengths
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
        Where = whereTable
    }
}

class ParserDeclarationTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    constructor(kinds: int[], starts: int[], valueLengths: int[]) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
    }
}

// One flat constraint row on a TYPE declaration: the owner type-parameter's name span, the item code,
// and — for a type item — the source span of the constraint type.
//
// The item codes are the SAME three sentinels the function-signature scan uses (-2 `class`, -3
// `struct`, -4 `new()`); 0 means "a type, read TypeStarts/TypeLengths at this row". The one thing the
// two scans do NOT share is how a constraint TYPE is captured, and that difference is forced: a
// function signature parses its types into the shared NODE TABLE (it has one), while a declaration
// core has no node table at all and captures its base/interface list as SOURCE SPANS through
// `ParseDeclarationTypeSpanCore`. A constraint type is captured exactly like a base type, which is
// the same fidelity the declaration already has for everything else it names.
class ParserDeclarationWhereTable {
    NameStarts: int[]
    NameLengths: int[]
    ItemCodes: int[]
    TypeStarts: int[]
    TypeLengths: int[]
    constructor(nameStarts: int[], nameLengths: int[], itemCodes: int[], typeStarts: int[], typeLengths: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        ItemCodes = itemCodes
        TypeStarts = typeStarts
        TypeLengths = typeLengths
    }
}

// `where T: Item, Item ... where U: Item ...` on a TYPE declaration. Answers the row count, or -1 on a
// malformed clause; `nextIndex` is the first token after the last clause (equal to `start` when there
// is no `where` at all, so a caller that has none pays one comparison).
//
// THE BRACE GATE IS WHY THIS EXISTS. Every declaration core ends its header scan with
// `if tokens.Kinds[pos] != 129 { return -1 }` — it demands `{`. A `where` (kind 53) is not one, so a
// constrained type declined the whole declaration to the recovery parser and never reached emit.
func ParseDeclarationWhereClausesCore(tokens: ParserDeclarationTokenTable, count: int, start: int, whereItems: ParserDeclarationWhereTable, out nextIndex: int): int {
    i := start
    nextIndex = start
    whereItemCount := 0
    typeSpanResult := new ParserDeclarationResultTable(new int[](2))
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
            itemCode := 0
            typeStart := 0
            typeLength := 0
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
                typeEnd := ParseDeclarationTypeSpanCore(tokens, count, i, typeSpanResult)
                if typeEnd < 0 {
                    return -1
                }

                typeStart = typeSpanResult.Values[0]
                typeLength = typeSpanResult.Values[1]
                i = typeEnd
            }

            if whereItemCount >= whereItems.ItemCodes.Length {
                return -1
            }

            whereItems.NameStarts[whereItemCount] = whereNameStart
            whereItems.NameLengths[whereItemCount] = whereNameLength
            whereItems.ItemCodes[whereItemCount] = itemCode
            whereItems.TypeStarts[whereItemCount] = typeStart
            whereItems.TypeLengths[whereItemCount] = typeLength
            whereItemCount = whereItemCount + 1

            if i < count && tokens.Kinds[i] == 134 {
                i = i + 1
            } else {
                moreItems = false
            }
        }
    }

    nextIndex = i
    return whereItemCount
}

class ParserDeclarationKindStream {
    Kinds: int[]
    constructor(kinds: int[]) {
        Kinds = kinds
    }
}

class ParserDeclarationStartKindStream {
    Kinds: int[]
    Starts: int[]
    constructor(kinds: int[], starts: int[]) {
        Kinds = kinds
        Starts = starts
    }
}

class ParserDeclarationResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

// Parser slice 4: namespace imports. The parser processes a prefix of `package`/`import` lines
// before declarations; an `import` whose first token is an Identifier is a
// NamespaceImport (`import A.B.C [as X]`) routed to CompilationUnit.Imports, while one followed by a
// string is a FileImport routed elsewhere and skipped here. This walks that header prefix linearly
// (imports/package are at depth 0, before any brace) and records each namespace import's dotted-name
// span and optional alias span (alias start = -1 when none). The host materializes the strings.

// Parser slice 5: per-top-level-declaration modifier flags. Uses the shared modifier flag layout and
// recognizes, before a declaration keyword,
// Public/Private/Static/Internal/Protected/Virtual/Override/Abstract/Sealed/Partial/Async/File. Returns
// 0 for non-modifier tokens. (Readonly/Const/Required/Init are member-level, not declaration modifiers.)

// For each top-level declaration, record its keyword kind and its accumulated modifier flags (the
// modifier keywords appearing at depth 0 between the previous declaration and this one's keyword;
// attributes are inside brackets so they do not interfere). Matches (int)Declaration.Modifiers.
// A depth-0 `where` (53) opens a generic CONSTRAINT clause whose items may include the `class` (8) /
// `struct` (9) KEYWORDS — those are constraints, not declarations, so keyword recognition is suppressed
// from `where` until the body `{` (which also ends the signature). All three top-level scanners share
// this rule.

// Parser slice 2: like TopLevelDeclarationKindsCore, but also records each declaration's NAME span.
// A declaration's name is the token immediately after its keyword (modifiers precede the keyword, so
// nothing sits between keyword and name) when that token is an Identifier (kind 0). For `test "..."`
// the token after the keyword is a string literal, so no name is recorded (outNameStart = -1) -- the
// test string name is out of scope for this slice. The host materializes the name from
// source via outNameStarts/outNameLengths.

// Parser declaration safety guard for top-level functions. The declaration scans intentionally skip
// unknown depth-0 tokens, so this validates the token immediately before each `func` keyword: only
// recognized modifiers (`static`, `async`), a previous declaration close, a package/namespace import
// dotted header prefix, or a quoted file-import header may precede a top-level function. Returns 1
// when every function preamble is valid.

// Parser declaration utility: the compacted-token index of the `}` (130) that closes the `{` (129)
// at `open`, or -1 if `open` is not a left brace or the brace run is unbalanced. This keeps property
// accessor body delimiting in the N# parser path instead of leaving a host adapter-side scanner.

// Parser declaration utility: find the compacted-token index whose kind and source start match a
// parser-node source span. Used for local-function statement nodes, where the statement parser
// records the `func` keyword span and the adapter must re-enter the declaration parser at that token.

// Parser declaration utility: parse one computed property accessor block already discovered by
// ParseStructDeclarationCore. Returns 0 for get-only, 1 for get/set, or -1 for unsupported shapes.
// outResult: [0]=nameStart, [1]=nameLength, [2]=typeStart, [3]=typeLength,
// [4]=getBodyBraceIndex, [5]=setBodyBraceIndex-or--1.
// Flattened ParsePropertyAccessor*Into ABIs live in the parity corpus; product callers compose this
// core through ParserColumnarProperties.nl.

// Product interface declaration core. Flattened ParseInterfaceDeclaration* ABIs live in the
// parity corpus; product callers compose this core through ParserInterfaceSignatures.nl.

// Product enum declaration core. Flattened ParseEnumDeclaration* ABIs live in the parity corpus;
// product callers compose this core through ParserColumnarEnums.nl.

// Parse one struct/class/record declaration into wrapper-owned declaration tables. The flattened
// ParseStructDeclaration* ABIs live in the parity corpus; product callers compose this core directly.

// Parse a CONSTRUCTOR's chaining initializer `: this(args)` / `: base(args)`, given the constructor's identifier
// token index (`ctorIndex`, the "constructor" identifier). Scans past the param list `(...)` (balanced) to the
// optional `:`; with no `:` (or no `(` params) returns 0 with outResult[0] = 0 (no initializer). For `: this(`
// (this = 42) / `: base(` (base = 43), parses each chained ARG through the ordinary expression grammar and
// records its complete span in outArgKinds/outArgStarts/outArgLengths, separated by `,` (134), closed by `)`
// (128). outResult[0] = the initializer kind (0 = none, 1 = this, 2 = base);
// outResult[1] = the constructor BODY `{` token index, or -1 if it is missing. Returns the chained-arg count, or
// -1 on a malformed initializer or expression. Argument spans stay in source order so product materialization can
// build the ordinary expression-node shape without reconstructing a grammar decision.
// Product constructor-chain core. Flattened ParseConstructor*Into ABIs live in the parity corpus;
// product callers compose this core through ParserConstructorSignatures.nl.

// Parser slice (union bodies): parse ONE `union Name[<T, U>] { Case { f: T, ... }  Case { ... } }` declaration into
// flat parallel arrays. `unionIndex` is the compacted token index of the `union` keyword (token 12). Reads the union
// NAME (the Identifier after `union`) into outResult[0]=nameStart / outResult[1]=nameLength, an OPTIONAL generic
// type-parameter list `<T, U>` (Less 100 / Identifier 0 / Comma 134 / Greater 102 — the same bare-identifier shape
// as the struct/class kernel; spans to outTypeParamStarts/Lengths, count to outResult[2], 0 with no `<`; an inline
// constraint or empty list returns -1), then `{` (129), then a sequence of CASES until the union close `}` (130).
// Each case is either bare `CaseName` or `CaseName { field : Type, ... }`: the case name (Identifier) into
// outCaseNameStarts/Lengths[case], then either no payload or a `{` (129) containing a sequence of FIELDS —
// `Identifier : Type` where the type is a SINGLE Identifier token (a builtin like int/string, a bare user-type
// name, or one of the union's type parameters) — each delimited by an optional `,` (134), closed by the case `}`
// (130). Fields flatten ACROSS all cases into
// outFieldNameStarts/Lengths + outFieldTypeStarts/Lengths in case-then-field order; outCaseFieldCounts[case] records
// how many fields that case contributed (so the host re-segments the flat field arrays per case). Returns the case
// count, or -1 on any unexpected token — a primary-ctor `(`, a composed/array/generic field type (a non-Identifier
// after `:`), a field initializer, a missing name/colon/brace, or an empty union — so
// the host declines the whole program to the N# backend path. Slice scope: unions whose case fields are single
// builtin/bare-name/type-param-typed (the emitter further gates each field type to a supported CLR type).

func PackageNameSpanCore(tokens: ParserDeclarationTokenTable, count: int, result: ParserDeclarationResultTable): int {
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

func NamespaceImportSpansCore(tokens: ParserDeclarationTokenTable, count: int, imports: NamespaceImportTable): int {
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

    if kind == 21 {
        return 1024
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

    if kind == 59 {
        return 65536
    }

    // `required` and `init` — `Modifiers.Required` (8192) and `Modifiers.Init` (16384) in
    // DeclarationEnums.nl, the same two bits the recovery parser hangs on the declaration node.
    if kind == 76 {
        return 8192
    }

    if kind == 77 {
        return 16384
    }

    return 0
}

func TopLevelDeclarationModifiersCore(source: string, tokens: ParserDeclarationTokenTable, count: int, decls: TopLevelDeclarationModifierTable): int {
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
            if kind == 120 {
                // A CONSTRAINT CLAUSE ENDS AT THE BODY, and an EXPRESSION body opens with `=>`, not `{`.
                // Only the brace used to clear this latch, so `func F<T>(x: T): T where T : class => x`
                // left it set for the rest of the file and every later declaration went unseen — the
                // whole source then declined at `parse.declaration-scan`.
                inWhereClause = false
            }

            if kind == 53 {
                inWhereClause = true
            } else if !inWhereClause {
                // ASKED ONCE, AT DEPTH ZERO ONLY. A type ALIAS head is an identifier plus two more
                // tokens, so the question cannot be answered from `kind` alone; reading it here keeps
                // the cost off every token inside a declaration body.
                headKind := TopLevelDeclarationHeadKind(source, tokens, count, i)
                flag := ModifierFlag(kind)
                if flag != 0 {
                    pending = pending | flag
                } else if headKind != 0 && !IsRecordStructTailToken(tokens.Kinds, i) {
                    decls.Kinds[outCount] = headKind
                    decls.Modifiers[outCount] = pending
                    outCount = outCount + 1
                    pending = 0
                } else if kind != 136 {
                    // A DECLARATION'S MODIFIERS ARE THE RUN IMMEDIATELY BEFORE ITS KEYWORD, and anything
                    // else at depth zero ends that run. Brace depth alone cannot enforce it: an
                    // EXPRESSION-BODIED top-level function has no braces, so its body's tokens are read
                    // here too — and `func F(): Func<Task<int>> => async () => 1` left `async` pending,
                    // which the NEXT function then wore. That was not a parse error: the following
                    // function silently became `async`, its signature grew a `ValueTask<T>` wrap, and its
                    // body was emitted inside the async fault guard, so a `throw` it raised turned into a
                    // faulted task nobody awaited. Newlines (136) carry no meaning between a modifier and
                    // its keyword, so they alone do not end the run.
                    pending = 0
                }
            }
        }

        i = i + 1
    }

    return outCount
}

// `type` (72) IS NOT HERE, because `type` is a CONTEXTUAL keyword: the columnar lexer writes an
// ordinary identifier (0) for it, so no token KIND says "type alias" on its own. Ask
// `TopLevelDeclarationHeadKind` instead — it answers the alias by its three-token head and still
// reports 72 as the declaration KIND, which is the value every downstream walker and whitelist in
// this file already speaks.
func IsTopLevelDeclarationKeyword(kind: int): bool {
    return kind == 7 || kind == 8 || kind == 9 || kind == 10 || kind == 12 || kind == 13 || kind == 14 || kind == 73
}

// THE DECLARATION KIND OF A TOP-LEVEL DECLARATION HEAD, or 0 (Identifier) when the token at `index`
// opens no declaration. A type ALIAS answers 72 although its token is an identifier; that is the one
// and only place the contextual reading enters the columnar declaration walkers, so all three of
// them agree about where a declaration begins by construction.
func TopLevelDeclarationHeadKind(source: string, tokens: ParserDeclarationTokenTable, count: int, index: int): int {
    kind := tokens.Kinds[index]
    if IsTopLevelDeclarationKeyword(kind) {
        return kind
    }

    if TypeAliasKeywordFacts.IsAliasDeclarationHeadAt(source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, count, index) {
        return 72
    }

    return 0
}

// `record struct` is ONE declaration: the Struct(9) token directly after a Record(13) token is
// the record-struct TAIL, never its own declaration head. Every declaration walker must apply
// this so counts, names, and modifiers stay aligned.
func IsRecordStructTailToken(kinds: int[], index: int): bool {
    return kinds[index] == 9 && index > 0 && kinds[index - 1] == 13
}

func TopLevelDeclarationNameSpansCore(source: string, tokens: ParserDeclarationTokenTable, count: int, decls: TopLevelDeclarationNameTable): int {
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
            if kind == 120 {
                // A CONSTRAINT CLAUSE ENDS AT THE BODY, and an EXPRESSION body opens with `=>`, not `{`.
                // Only the brace used to clear this latch, so `func F<T>(x: T): T where T : class => x`
                // left it set for the rest of the file and every later declaration went unseen — the
                // whole source then declined at `parse.declaration-scan`.
                inWhereClause = false
            }

            if kind == 53 {
                inWhereClause = true
            } else if !inWhereClause && TopLevelDeclarationHeadKind(source, tokens, count, i) != 0 && !IsRecordStructTailToken(tokens.Kinds, i) {
                // A type ALIAS reports the declaration KIND `TokenType.Type` (72) although its token
                // is an ordinary identifier, which is what lets the name read below and every
                // downstream whitelist stay exactly as they were.
                kind = TopLevelDeclarationHeadKind(source, tokens, count, i)
                decls.Kinds[outCount] = kind
                decls.Indices[outCount] = i
                nameIndex := i + 1
                // Iterator declarations spell the generator marker as `func*`: skip the `*` (Star 90)
                // so the name span reads the identifier that follows, exactly as a normal `func` does.
                if kind == 7 && nameIndex < count && tokens.Kinds[nameIndex] == 90 {
                    nameIndex = nameIndex + 1
                }
                if kind == 13 && nameIndex < count && tokens.Kinds[nameIndex] == 9 {
                    nameIndex = nameIndex + 1
                }

                if nameIndex < count && tokens.Kinds[nameIndex] == 0 {
                    decls.NameStarts[outCount] = tokens.Starts[nameIndex]
                    decls.NameLengths[outCount] = tokens.ValueLengths[nameIndex]
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

func TopLevelDeclarationKindsCore(source: string, tokens: ParserDeclarationTokenTable, count: int, decls: TopLevelDeclarationKindTable): int {
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
            if kind == 120 {
                // A CONSTRAINT CLAUSE ENDS AT THE BODY, and an EXPRESSION body opens with `=>`, not `{`.
                // Only the brace used to clear this latch, so `func F<T>(x: T): T where T : class => x`
                // left it set for the rest of the file and every later declaration went unseen — the
                // whole source then declined at `parse.declaration-scan`.
                inWhereClause = false
            }

            if kind == 53 {
                inWhereClause = true
            } else if !inWhereClause && TopLevelDeclarationHeadKind(source, tokens, count, i) != 0 && !IsRecordStructTailToken(tokens.Kinds, i) {
                decls.Kinds[outCount] = TopLevelDeclarationHeadKind(source, tokens, count, i)
                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

func TopLevelStructLikeDeclarationIndicesCore(tokens: ParserDeclarationKindStream, count: int, output: TopLevelStructLikeDeclarationTable): int {
    outCount := TopLevelStructLikeDeclarationIndicesAppend(tokens, count, 9, 1, 0, 0, output, 0)
    if outCount < 0 {
        return -1
    }

    outCount = TopLevelStructLikeDeclarationIndicesAppend(tokens, count, 13, 0, 1, 1, output, outCount)
    if outCount < 0 {
        return -1
    }

    return TopLevelStructLikeDeclarationIndicesAppend(tokens, count, 8, 1, 1, 0, output, outCount)
}

func TopLevelColumnarNominalDeclarationIndicesCore(tokens: ParserDeclarationKindStream, count: int, outputs: TopLevelColumnarNominalDeclarationTable, result: ParserDeclarationResultTable): int {
    if count < 0 || count > tokens.Kinds.Length || result.Values.Length < 3 {
        return -1
    }

    enumTable := new TopLevelDeclarationIndexTable(outputs.EnumIndices)
    enumCount := ColumnarEnumDeclarationIndicesCore(tokens, count, enumTable)
    if enumCount < 0 {
        return -1
    }

    unionTable := new TopLevelDeclarationIndexTable(outputs.UnionIndices)
    unionCount := TopLevelDeclarationIndicesCore(tokens, count, 12, 0, unionTable)
    if unionCount < 0 {
        return -1
    }

    interfaceTable := new TopLevelDeclarationIndexTable(outputs.InterfaceIndices)
    interfaceCount := TopLevelDeclarationIndicesCore(tokens, count, 10, 0, interfaceTable)
    if interfaceCount < 0 {
        return -1
    }

    result.Values[0] = enumCount
    result.Values[1] = unionCount
    result.Values[2] = interfaceCount
    return enumCount + unionCount + interfaceCount
}

func ColumnarEnumDeclarationIndicesCore(tokens: ParserDeclarationKindStream, count: int, indices: TopLevelDeclarationIndexTable): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0

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
        } else if (braceDepth == 0 || braceDepth == 1) && bracketDepth == 0 && parenDepth == 0 && kind == 14 {
            if outCount >= indices.Indices.Length {
                return -1
            }

            indices.Indices[outCount] = i
            outCount = outCount + 1
        }

        i = i + 1
    }

    return outCount
}

// The declaration table already carries the source type's modifier word alongside its index. Keep
// the visibility bits consumed by nested-type planning, the explicit `sealed` bit consumed by
// reference-type planning, and the `readonly` bit consumed by readonly-struct attribute planning.
// Other member modifiers have their own columns and must not leak into this metadata word.
//
// `readonly` reaches this word through `ParserDeclarationMemberModifierFlag`, not `ModifierFlag`:
// the latter answers the parser's own modifier table, which deliberately has no `readonly` row
// because a member-level `readonly X: int` is carried by the field columns instead.
func ColumnarStructDeclarationMetadataModifierFlagsAt(tokenKinds: int[], declarationIndex: int): int {
    if declarationIndex < 0 || declarationIndex >= tokenKinds.Length {
        return 0
    }

    declarationKind := tokenKinds[declarationIndex]
    modifierIndex := declarationIndex - 1
    if declarationKind == 9 && modifierIndex >= 0 && tokenKinds[modifierIndex] == 78 {
        modifierIndex = modifierIndex - 1
    }

    flags := 0
    while modifierIndex >= 0 && ParserDeclarationMemberModifierKind(tokenKinds[modifierIndex]) != 0 {
        modifierFlag := ParserDeclarationMemberModifierFlag(tokenKinds[modifierIndex])
        // The words that reach METADATA: the four visibility words, `sealed` (128), `abstract` (64)
        // and `readonly` (512). `abstract` is here because `abstract class C` is a
        // TypeAttributes bit the CLR itself enforces — it refuses to load a type that declares an
        // abstract method without it — not merely a source-level promise the analyzer checks.
        if modifierFlag == 1 || modifierFlag == 2 || modifierFlag == 4 || modifierFlag == 8 || modifierFlag == 64 || modifierFlag == 128 || modifierFlag == 512 {
            flags = flags | modifierFlag
        }
        modifierIndex = modifierIndex - 1
    }
    return flags
}

// Explicit constructors are represented by the contextual `constructor` identifier rather than a
// dedicated token kind. Recover the visibility word from the already-validated member prefix while
// retaining the existing constructor-input ABI used by the bootstrap compiler. Attributes and
// modifiers may be interleaved in that prefix, so walk across balanced attribute brackets as well
// as modifier tokens. Synthetic primary/initializer constructors point at a type declaration token
// and therefore retain the language's public synthesized-constructor default.
func ColumnarConstructorDeclarationMetadataModifierFlagsAt(tokenKinds: int[], constructorIndex: int): int {
    if constructorIndex < 0 || constructorIndex >= tokenKinds.Length || tokenKinds[constructorIndex] != 0 {
        return 0
    }

    flags := 0
    scan := constructorIndex - 1
    scanning := true
    while scan >= 0 && scanning {
        modifierKind := ParserDeclarationMemberModifierKind(tokenKinds[scan])
        if modifierKind != 0 {
            modifierFlag := ParserDeclarationMemberModifierFlag(tokenKinds[scan])
            if modifierFlag == 1 || modifierFlag == 2 || modifierFlag == 4 || modifierFlag == 8 || modifierFlag == 32768 {
                flags = flags | modifierFlag
            }
            scan = scan - 1
        } else if tokenKinds[scan] == 132 {
            bracketDepth := 1
            scan = scan - 1
            while scan >= 0 && bracketDepth > 0 {
                if tokenKinds[scan] == 132 {
                    bracketDepth = bracketDepth + 1
                } else if tokenKinds[scan] == 131 {
                    bracketDepth = bracketDepth - 1
                }
                scan = scan - 1
            }
            if bracketDepth != 0 {
                scanning = false
            }
        } else {
            scanning = false
        }
    }
    return flags
}

func ColumnarProgramDeclarationIndicesInto(source: string, rawTokenKinds: int[], rawTokenStarts: int[], rawTokenValueLengths: int[], rawCount: int, compactTokenKinds: int[], compactTokenStarts: int[], compactTokenValueLengths: int[], compactCount: int, outFuncIndices: int[], outFuncAsyncFlags: int[], outFuncGeneratorFlags: int[], outEnumIndices: int[], outUnionIndices: int[], outInterfaceIndices: int[], outStructIndices: int[], outStructReferenceFlags: int[], outStructRecordFlags: int[], outStructVisibilityFlags: int[], outStructEnclosingTypeNames: string[], outResult: int[]): int {
    rawTokens := new ParserDeclarationTokenTable(rawTokenKinds, rawTokenStarts, rawTokenValueLengths)
    compactTokens := new ParserDeclarationTokenTable(compactTokenKinds, compactTokenStarts, compactTokenValueLengths)
    outputs := new TopLevelColumnarProgramDeclarationTable(outFuncIndices, outFuncAsyncFlags, outFuncGeneratorFlags, outEnumIndices, outUnionIndices, outInterfaceIndices, outStructIndices, outStructReferenceFlags, outStructRecordFlags)
    result := new ParserDeclarationResultTable(outResult)
    declarationCount := TopLevelColumnarProgramDeclarationIndicesCore(source, rawTokens, rawCount, compactTokens, compactCount, outputs, result)
    if declarationCount < 0 {
        return declarationCount
    }

    topLevelStructCount := outResult[5]
    if outStructIndices == null || outStructVisibilityFlags == null || topLevelStructCount < 0 || topLevelStructCount > outStructIndices.Length || topLevelStructCount > outStructVisibilityFlags.Length {
        return -6
    }
    topLevelStructIndex := 0
    while topLevelStructIndex < topLevelStructCount {
        outStructVisibilityFlags[topLevelStructIndex] = ColumnarStructDeclarationMetadataModifierFlagsAt(compactTokenKinds, outStructIndices[topLevelStructIndex])
        topLevelStructIndex = topLevelStructIndex + 1
    }

    nestedCount := NestedColumnarStructDeclarationIndicesInto(source, compactTokenKinds, compactTokenStarts, compactTokenValueLengths, compactCount, outStructIndices, outStructReferenceFlags, outStructRecordFlags, outStructVisibilityFlags, outStructEnclosingTypeNames, outResult[5])
    if nestedCount < 0 {
        return -6
    }
    outResult[5] = outResult[5] + nestedCount
    return declarationCount + nestedCount
}

// Collect struct-like declarations that are direct members of a source type. The top-level
// declaration scanner intentionally stops at brace depth zero; this companion keeps an explicit
// type-owner stack so a `class` token in a function body or constraint can never masquerade as a
// nested declaration. Enclosing names are source-qualified (`Outer.Middle`) rather than CLR
// metadata names (`Outer+Middle`); the assembly owner uses them only to select the already-defined
// enclosing TypeBuilder.
func NestedColumnarStructDeclarationIndicesInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outStructIndices: int[], outStructReferenceFlags: int[], outStructRecordFlags: int[], outStructVisibilityFlags: int[], outEnclosingTypeNames: string[], outputOffset: int = 0): int {
    if source == null || tokenKinds == null || tokenStarts == null || tokenValueLengths == null || outStructIndices == null || outStructReferenceFlags == null || outStructRecordFlags == null || outStructVisibilityFlags == null || outEnclosingTypeNames == null || count < 0 || outputOffset < 0 || count > tokenKinds.Length || count > tokenStarts.Length || count > tokenValueLengths.Length {
        return -1
    }

    ownerNames := new string[](count + 1)
    ownerBodyDepths := new int[](count + 1)
    ownerCount := 0
    pendingOwnerName := ""
    pendingOwnerDepth := -1
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outputCount := 0

    index := 0
    while index < count {
        kind := tokenKinds[index]
        declarationScope := bracketDepth == 0 && parenDepth == 0 && (braceDepth == 0 || ownerCount > 0 && braceDepth == ownerBodyDepths[ownerCount - 1])
        if declarationScope && IsTopLevelTypeDeclarationKind(kind) && !IsRecordStructTailToken(tokenKinds, index) {
            nameIndex := index + 1
            if kind == 13 && nameIndex < count && tokenKinds[nameIndex] == 9 {
                nameIndex = nameIndex + 1
            }
            if nameIndex < count && tokenKinds[nameIndex] == 0 {
                declarationName := source.Substring(tokenStarts[nameIndex], tokenValueLengths[nameIndex])
                enclosingName := ""
                if ownerCount > 0 {
                    enclosingName = ownerNames[ownerCount - 1]
                    pendingOwnerName = enclosingName + "." + declarationName
                } else {
                    pendingOwnerName = declarationName
                }
                pendingOwnerDepth = braceDepth

                if ownerCount > 0 && (kind == 8 || kind == 9 || kind == 13) {
                    outputIndex := outputOffset + outputCount
                    if outputIndex >= outStructIndices.Length || outputIndex >= outStructReferenceFlags.Length || outputIndex >= outStructRecordFlags.Length || outputIndex >= outStructVisibilityFlags.Length || outputIndex >= outEnclosingTypeNames.Length {
                        return -1
                    }
                    outStructIndices[outputIndex] = index
                    isRecord := kind == 13
                    isReference := kind == 8 || isRecord
                    if isRecord && index + 1 < count && tokenKinds[index + 1] == 9 {
                        isReference = false
                    }
                    outStructReferenceFlags[outputIndex] = isReference ? 1 : 0
                    outStructRecordFlags[outputIndex] = isRecord ? 1 : 0
                    outStructVisibilityFlags[outputIndex] = ColumnarStructDeclarationMetadataModifierFlagsAt(tokenKinds, index)
                    outEnclosingTypeNames[outputIndex] = enclosingName
                    outputCount = outputCount + 1
                }
            }
        }

        if kind == 129 {
            braceDepth = braceDepth + 1
            if pendingOwnerName.Length > 0 && pendingOwnerDepth == braceDepth - 1 {
                ownerNames[ownerCount] = pendingOwnerName
                ownerBodyDepths[ownerCount] = braceDepth
                ownerCount = ownerCount + 1
                pendingOwnerName = ""
                pendingOwnerDepth = -1
            }
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
            while ownerCount > 0 && braceDepth < ownerBodyDepths[ownerCount - 1] {
                ownerCount = ownerCount - 1
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
        index = index + 1
    }

    if braceDepth != 0 || bracketDepth != 0 || parenDepth != 0 || ownerCount != 0 || pendingOwnerName.Length > 0 {
        return -1
    }
    return outputCount
}

func TopLevelColumnarProgramDeclarationIndicesCore(source: string, rawTokens: ParserDeclarationTokenTable, rawCount: int, compactTokens: ParserDeclarationTokenTable, compactCount: int, outputs: TopLevelColumnarProgramDeclarationTable, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    functionOutputs := new TopLevelColumnarFunctionDeclarationTable(outputs.FuncIndices, outputs.FuncAsyncFlags, outputs.FuncGeneratorFlags)
    functionResult := new ParserDeclarationResultTable(new int[](2))
    functionCount := TopLevelColumnarFunctionDeclarationIndicesCore(source, rawTokens, rawCount, compactTokens, compactCount, functionOutputs, functionResult)
    if functionCount < 0 {
        return -2
    }

    names := new TopLevelDeclarationNameTable(new int[](rawCount + 1), new int[](rawCount + 1), new int[](rawCount + 1), new int[](rawCount + 1))
    nameCount := TopLevelDeclarationNameSpansCore(source, rawTokens, rawCount, names)
    if nameCount != functionResult.Values[0] {
        return -3
    }

    if TopLevelTypeDeclarationNamesDistinct(source, rawTokens, rawCount, names, nameCount) == 0 {
        return -4
    }

    nominalOutputs := new TopLevelColumnarNominalDeclarationTable(outputs.EnumIndices, outputs.UnionIndices, outputs.InterfaceIndices)
    nominalResult := new ParserDeclarationResultTable(new int[](3))
    compactKindStream := new ParserDeclarationKindStream(compactTokens.Kinds)
    nominalCount := TopLevelColumnarNominalDeclarationIndicesCore(compactKindStream, compactCount, nominalOutputs, nominalResult)
    if nominalCount < 0 {
        return -5
    }

    structOutputs := new TopLevelStructLikeDeclarationTable(outputs.StructIndices, outputs.StructReferenceFlags, outputs.StructRecordFlags)
    structCount := TopLevelStructLikeDeclarationIndicesCore(compactKindStream, compactCount, structOutputs)
    if structCount < 0 {
        return -6
    }

    result.Values[0] = functionResult.Values[0]
    result.Values[1] = functionCount
    result.Values[2] = nominalResult.Values[0]
    result.Values[3] = nominalResult.Values[1]
    result.Values[4] = nominalResult.Values[2]
    result.Values[5] = structCount
    return functionCount + nominalCount + structCount
}

// THE GENERIC ARITY WRITTEN ON A TOP-LEVEL DECLARATION, straight off the token stream.
//
// A CLR type is identified by its name AND its type-parameter count, so the duplicate-name check
// below needs the count as well as the name. It is read here rather than carried on the name table
// because the name table is built by a scan that never looks past the identifier.
//
// The list is the tokens between the `<` that IMMEDIATELY follows the name and its matching `>`,
// counting top-level commas. `>>` closes two levels at once (`Box<List<int>>`), which is why the
// right-shift token is subtracted rather than treated as one `>`.
func TopLevelDeclarationGenericArityCore(tokens: ParserDeclarationTokenTable, count: int, declarationIndex: int, declarationKind: int): int {
    if declarationIndex < 0 || declarationIndex >= count {
        return 0
    }

    nameIndex := declarationIndex + 1
    if declarationKind == 7 && nameIndex < count && tokens.Kinds[nameIndex] == 90 {
        nameIndex = nameIndex + 1
    }
    if declarationKind == 13 && nameIndex < count && tokens.Kinds[nameIndex] == 9 {
        nameIndex = nameIndex + 1
    }
    if nameIndex >= count || tokens.Kinds[nameIndex] != 0 {
        return 0
    }

    i := nameIndex + 1
    if i >= count || tokens.Kinds[i] != 100 {
        return 0
    }

    depth := 0
    arity := 1
    while i < count {
        kind := tokens.Kinds[i]
        if kind == 100 {
            depth = depth + 1
        } else if kind == 102 {
            depth = depth - 1
            if depth <= 0 {
                return arity
            }
        } else if kind == 112 {
            depth = depth - 2
            if depth <= 0 {
                return arity
            }
        } else if kind == 134 && depth == 1 {
            arity = arity + 1
        } else if kind == 129 || kind == 130 {
            return 0
        }

        i = i + 1
    }

    return 0
}

func TopLevelTypeDeclarationNamesDistinct(source: string, tokens: ParserDeclarationTokenTable, count: int, decls: TopLevelDeclarationNameTable, declCount: int): int {
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

                    // SAME NAME IS NOT SAME TYPE. `Subscription` and `Subscription<T>` are two CLR
                    // types and may be declared side by side; only a repeated (name, arity) in one
                    // namespace is the duplicate this scan refuses.
                    if ParserDeclarationSourceSpansEqual(source, decls.NameStarts[i], decls.NameLengths[i], decls.NameStarts[j], decls.NameLengths[j]) && TopLevelDeclarationGenericArityCore(tokens, count, decls.Indices[i], decls.Kinds[i]) == TopLevelDeclarationGenericArityCore(tokens, count, decls.Indices[j], decls.Kinds[j]) {
                        namespaceMatch := ParserDeclarationNamespacesEqual(source, tokens, count, decls.Indices[i], decls.Indices[j])
                        if namespaceMatch != 0 {
                            return 0
                        }
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

func TopLevelStructLikeDeclarationIndicesAppend(tokens: ParserDeclarationKindStream, count: int, targetKind: int, suppressWhereClause: int, isReference: int, isRecord: int, output: TopLevelStructLikeDeclarationTable, startCount: int): int {
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
            if kind == 120 {
                // A CONSTRAINT CLAUSE ENDS AT THE BODY, and an EXPRESSION body opens with `=>`, not `{`.
                // Only the brace used to clear this latch, so `func F<T>(x: T): T where T : class => x`
                // left it set for the rest of the file and every later declaration went unseen — the
                // whole source then declined at `parse.declaration-scan`.
                inWhereClause = false
            }

            if kind == 53 {
                inWhereClause = true
            } else if kind == targetKind && (suppressWhereClause == 0 || !inWhereClause) && !IsRecordStructTailToken(tokens.Kinds, i) {
                if outCount >= output.Indices.Length || outCount >= output.ReferenceFlags.Length || outCount >= output.RecordFlags.Length {
                    return -1
                }

                declReferenceFlag := isReference
                if kind == 13 && i + 1 < count && tokens.Kinds[i + 1] == 9 {
                    declReferenceFlag = 0
                }

                output.Indices[outCount] = i
                output.ReferenceFlags[outCount] = declReferenceFlag
                output.RecordFlags[outCount] = isRecord
                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

func TopLevelColumnarFunctionDeclarationIndicesCore(source: string, rawTokens: ParserDeclarationTokenTable, rawCount: int, compactTokens: ParserDeclarationTokenTable, compactCount: int, outputs: TopLevelColumnarFunctionDeclarationTable, result: ParserDeclarationResultTable): int {
    if rawCount < 0 || compactCount < 0 || rawCount > rawTokens.Kinds.Length || rawCount > rawTokens.Starts.Length || rawCount > rawTokens.ValueLengths.Length || compactCount > compactTokens.Kinds.Length || compactCount > compactTokens.Starts.Length || compactCount > compactTokens.ValueLengths.Length || result.Values.Length < 2 {
        return -1
    }

    if TopLevelUnmodeledTestShapeExistsCore(source, rawTokens, rawCount) != 0 {
        return -1
    }

    decls := new TopLevelDeclarationKindTable(new int[](rawCount + 1))
    declCount := TopLevelDeclarationKindsCore(source, rawTokens, rawCount, decls)
    if declCount < 0 {
        return -1
    }

    // A file whose only top-level declarations are PLAIN test declarations (a `.tests.nl` file)
    // has zero declaration keywords; that is a valid empty function list, not a refusal.
    if declCount == 0 {
        testOnlyIndices := new int[](rawCount + 1)
        testOnlyResult := new int[](1)
        if TopLevelColumnarTestDeclarationIndicesInto(source, rawTokens.Kinds, rawTokens.Starts, rawTokens.ValueLengths, rawCount, testOnlyIndices, testOnlyResult) <= 0 {
            return -1
        }

        result.Values[0] = 0
        result.Values[1] = 0
        return 0
    }

    i := 0
    while i < declCount {
        kind := decls.Kinds[i]
        if kind != 7 && kind != 14 && kind != 9 && kind != 13 && kind != 12 && kind != 8 && kind != 10 && kind != 72 {
            return -1
        }

        i = i + 1
    }

    names := new TopLevelDeclarationNameTable(new int[](rawCount + 1), new int[](rawCount + 1), new int[](rawCount + 1), new int[](rawCount + 1))
    nameCount := TopLevelDeclarationNameSpansCore(source, rawTokens, rawCount, names)
    if nameCount != declCount {
        return -1
    }

    if TopLevelFunctionDeclarationNamesDistinct(source, names, nameCount) == 0 {
        return -1
    }

    modifiers := new TopLevelDeclarationModifierTable(new int[](rawCount + 1), new int[](rawCount + 1))
    modifierCount := TopLevelDeclarationModifiersCore(source, rawTokens, rawCount, modifiers)
    if modifierCount != declCount {
        return -1
    }

    compactKindStream := new ParserDeclarationKindStream(compactTokens.Kinds)
    indices := new TopLevelDeclarationIndexTable(outputs.Indices)
    funcCount := TopLevelDeclarationIndicesCore(compactKindStream, compactCount, 7, 0, indices)
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

    // Generator (`func*`) fact, parallel to AsyncFlags: a top-level function is a generator when a `*`
    // (Star 90) immediately follows its `func` keyword in the compact stream. The decision lives here in
    // N#; the host only routes the flag into ColumnarFunctionInput.ModifierFlags (|= 4096).
    gi := 0
    while gi < funcCount {
        if gi >= outputs.GeneratorFlags.Length {
            return -1
        }

        generatorFlag := 0
        funcTokenIndex := outputs.Indices[gi]
        if funcTokenIndex + 1 < compactCount && compactTokens.Kinds[funcTokenIndex + 1] == 90 {
            generatorFlag = 1
        }

        outputs.GeneratorFlags[gi] = generatorFlag
        gi = gi + 1
    }

    if TopLevelFunctionPreamblesAreValidCore(source, compactTokens, compactCount, indices, funcCount) == 0 {
        return -1
    }

    result.Values[0] = declCount
    result.Values[1] = funcCount
    return funcCount
}

func TopLevelFunctionDeclarationNamesDistinct(source: string, decls: TopLevelDeclarationNameTable, declCount: int): int {
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

func TopLevelDeclarationIndicesCore(tokens: ParserDeclarationKindStream, count: int, targetKind: int, suppressWhereClause: int, indices: TopLevelDeclarationIndexTable): int {
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
            if kind == 120 {
                // A CONSTRAINT CLAUSE ENDS AT THE BODY, and an EXPRESSION body opens with `=>`, not `{`.
                // Only the brace used to clear this latch, so `func F<T>(x: T): T where T : class => x`
                // left it set for the rest of the file and every later declaration went unseen — the
                // whole source then declined at `parse.declaration-scan`.
                inWhereClause = false
            }

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

func TopLevelFunctionPreamblePreviousToken(tokens: ParserDeclarationTokenTable, start: int): int {
    pos := start
    changed := true
    while changed {
        changed = false

        while pos >= 0 && ModifierFlag(tokens.Kinds[pos]) != 0 {
            pos = pos - 1
            changed = true
        }

        if pos >= 0 && tokens.Kinds[pos] == 132 {
            open := TopLevelFunctionPreambleAttributeOpen(tokens, pos)
            if open < 0 {
                return pos
            }

            pos = open - 1
            changed = true
        }
    }

    return pos
}

// THE INDEX OF THE `]` THAT CLOSES THE `[` AT `openIndex`, or -1 when the group never closes.
// The twin of `TopLevelFunctionPreambleAttributeOpen`, which answers the same question backward.
func ParserDeclarationAttributeGroupClose(tokens: ParserDeclarationTokenTable, count: int, openIndex: int): int {
    depth := 0
    pos := openIndex
    while pos < count {
        kind := tokens.Kinds[pos]
        if kind == 131 {
            depth = depth + 1
        } else if kind == 132 {
            depth = depth - 1
            if depth == 0 {
                return pos
            }
        }

        pos = pos + 1
    }

    return -1
}

func TopLevelFunctionPreambleAttributeOpen(tokens: ParserDeclarationTokenTable, closeIndex: int): int {
    depth := 0
    pos := closeIndex
    while pos >= 0 {
        kind := tokens.Kinds[pos]
        if kind == 132 {
            depth = depth + 1
        } else if kind == 131 {
            depth = depth - 1
            if depth == 0 {
                return pos
            }
        }

        pos = pos - 1
    }

    return -1
}

func TopLevelFunctionPreamblesAreValidCore(source: string, tokens: ParserDeclarationTokenTable, count: int, indices: TopLevelDeclarationIndexTable, funcCount: int): int {
    i := 0
    while i < funcCount {
        funcIndex := indices.Indices[i]
        if funcIndex < 0 || funcIndex >= count || tokens.Kinds[funcIndex] != 7 {
            return 0
        }

        preceding := TopLevelFunctionPreamblePreviousToken(tokens, funcIndex - 1)

        if preceding >= 0 && tokens.Kinds[preceding] != 130 {
            if tokens.Kinds[preceding] == 4 {
                if preceding - 1 < 0 || tokens.Kinds[preceding - 1] != 17 {
                    if i == 0 || TopLevelExpressionBodiedFunctionEndsAt(source, tokens, count, indices.Indices[i - 1], funcIndex) == 0 {
                        return 0
                    }
                }

                i = i + 1
                continue
            }

            aliasWalk := preceding
            while aliasWalk >= 0 && TopLevelDeclarationHeadKind(source, tokens, count, aliasWalk) == 0 && tokens.Kinds[aliasWalk] != 15 && tokens.Kinds[aliasWalk] != 17 && tokens.Kinds[aliasWalk] != 18 {
                aliasWalk = aliasWalk - 1
            }

            if aliasWalk >= 0 && TopLevelDeclarationHeadKind(source, tokens, count, aliasWalk) == 72 {
                i = i + 1
                continue
            }

            headerWalk := preceding
            while headerWalk >= 0 && (tokens.Kinds[headerWalk] == 0 || tokens.Kinds[headerWalk] == 124 || tokens.Kinds[headerWalk] == 48) {
                headerWalk = headerWalk - 1
            }

            // Valid header prefixes: `namespace A.B` / `import A.B[.C] [as X]` / `package A`, or a
            // FILE import with an alias — `import "path" as X` — whose walk stops at the string.
            isAliasedFileImportHeader := headerWalk >= 0 && tokens.Kinds[headerWalk] == 4 && headerWalk - 1 >= 0 && tokens.Kinds[headerWalk - 1] == 17

            if headerWalk == preceding || headerWalk < 0 || (tokens.Kinds[headerWalk] != 15 && tokens.Kinds[headerWalk] != 17 && tokens.Kinds[headerWalk] != 18 && !isAliasedFileImportHeader) {
                if i == 0 || TopLevelExpressionBodiedFunctionEndsAt(source, tokens, count, indices.Indices[i - 1], funcIndex) == 0 {
                    return 0
                }
            }
        }

        i = i + 1
    }

    return 1
}

// DOES THE PRECEDING FUNCTION'S EXPRESSION BODY END WHERE THE NEXT DECLARATION'S PREAMBLE BEGINS?
// The body's end is measured FORWARD to the next `func` keyword: everything between them must be
// that declaration's own preamble — modifiers and attribute groups, an optional `;` after the body.
// Measuring to the keyword alone made every arrow-bodied function followed by a modified one look
// like an unterminated body; measuring to a BACKWARD-walked preamble start read the `]` of an
// indexer body (`=> items[0]`) as an attribute group's close and declined the file the same way.
func TopLevelExpressionBodiedFunctionEndsAt(source: string, tokens: ParserDeclarationTokenTable, count: int, funcIndex: int, nextFuncIndex: int): int {
    if funcIndex < 0 || funcIndex >= count || nextFuncIndex <= funcIndex || nextFuncIndex > count || tokens.Kinds[funcIndex] != 7 {
        return 0
    }

    signatureEnd := ParseDeclarationFunctionSignatureEndCore(source, tokens, count, funcIndex)
    if signatureEnd < 0 || signatureEnd >= count || tokens.Kinds[signatureEnd] != 120 {
        return 0
    }

    expressionEnd := ParseDeclarationExpressionBodyEndCore(source, tokens, count, signatureEnd)
    if expressionEnd < 0 {
        return 0
    }

    pos := expressionEnd
    if pos < count && tokens.Kinds[pos] == 133 {
        pos = pos + 1
    }

    while pos < nextFuncIndex {
        kind := tokens.Kinds[pos]
        if ModifierFlag(kind) != 0 {
            pos = pos + 1
        } else if kind == 131 {
            close := TopLevelFunctionPreambleAttributeClose(tokens, count, pos)
            if close < 0 || close >= nextFuncIndex {
                return 0
            }

            pos = close + 1
        } else {
            return 0
        }
    }

    if pos == nextFuncIndex {
        return 1
    }

    return 0
}

func TopLevelFunctionPreambleAttributeClose(tokens: ParserDeclarationTokenTable, count: int, openIndex: int): int {
    depth := 0
    pos := openIndex
    while pos < count {
        kind := tokens.Kinds[pos]
        if kind == 131 {
            depth = depth + 1
        } else if kind == 132 {
            depth = depth - 1
            if depth == 0 {
                return pos
            }
        }

        pos = pos + 1
    }

    return -1
}

func MatchingCloseBraceCore(tokens: ParserDeclarationKindStream, count: int, open: int): int {
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

func TokenIndexByKindStartCore(tokens: ParserDeclarationStartKindStream, count: int, targetKind: int, targetStart: int): int {
    i := 0
    while i < count {
        if tokens.Kinds[i] == targetKind && tokens.Starts[i] == targetStart {
            return i
        }

        i = i + 1
    }

    return -1
}
