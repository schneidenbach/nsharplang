namespace NSharpLang.Compiler

import System
import System.Collections.Generic

enum AttributeArgumentConstantKind {
    Null,
    Bool,
    Integer,
    Floating,
    Char,
    String,
    Type,
    Enum,
    Array,
    UnknownStaticMember
}

enum DiscardedExpressionContext {
    ExpressionStatement,
    ForIterator
}

class FlowNarrowing {
    pathValue: string
    narrowedTypeValue: TypeInfo?
    nullStateValue: NullState

    Path: string => pathValue
    NarrowedType: TypeInfo? => narrowedTypeValue
    NullState: NullState => nullStateValue

    constructor(path: string, narrowedType: TypeInfo?, nullState: NullState) {
        pathValue = path
        narrowedTypeValue = narrowedType
        nullStateValue = nullState
    }
}

class ImportedSymbolInfo {
    nameValue: string
    typeValue: TypeInfo
    declarationValue: SymbolDeclaration

    Name: string => nameValue
    Type: TypeInfo => typeValue
    Declaration: SymbolDeclaration => declarationValue

    constructor(name: string, symbolType: TypeInfo, declaration: SymbolDeclaration) {
        nameValue = name
        typeValue = symbolType
        declarationValue = declaration
    }
}

class Scope {
    kindValue: ScopeKind
    symbolsValue: Dictionary<string, TypeInfo>
    typesValue: Dictionary<string, TypeInfo>
    nullStatesValue: Dictionary<string, NullState>
    errorTupleResultsValue: Dictionary<string, ErrorTupleResultGuard>
    availableErrorTupleResultsValue: HashSet<string>
    declarationLocations: Dictionary<string, SymbolDeclaration>
    typeAritiesValue: Dictionary<string, List<int>>
    hoistedLocalFunctionsValue: HashSet<string>
    typeParameterConstraintsValue: Dictionary<string, List<TypeInfo>>
    structConstrainedTypeParametersValue: HashSet<string>

    // THE NAMES THIS SCOPE BOUND THAT MAY NOT BE WRITTEN AGAIN. Today exactly one thing fills it: a
    // `using` resource, which the statement disposes at the end of its region and therefore has to
    // still be holding. It is a SCOPE field because the region is a scope — the block form marks the
    // name in the scope the statement opened, the DECLARATION form marks it in the enclosing block —
    // so the mark expires exactly when the guarantee does, with no separate bookkeeping to unwind.
    readOnlyNamesValue: HashSet<string>

    Kind: ScopeKind => kindValue
    Symbols: Dictionary<string, TypeInfo> => symbolsValue

    // KEYED BY IDENTITY, NOT BY NAME. A key is the written name for a non-generic type and
    // `Name``N for a generic one (`TypeArityNames.Key`), so `Subscription` and `Subscription<T>`
    // occupy two entries. Write through `DeclareType` rather than into the dictionary directly:
    // the arity index below is what answers "which arities of this name are in scope?" and it is
    // maintained there.
    Types: Dictionary<string, TypeInfo> => typesValue

    // Every arity declared for a bare name, in declaration order. The resolver's fallback and the
    // arity-mismatch diagnostic both read it; a name with one non-generic declaration has the single
    // entry 0.
    TypeArities: Dictionary<string, List<int>> => typeAritiesValue
    // THE CONSTRAINT TYPES OF EVERY TYPE PARAMETER THIS SCOPE DECLARES. A type parameter is a
    // `SimpleTypeInfo` of its own name and carries nothing else, so the one place its `where` clause
    // can live is beside the declaration that introduced it — and it leaves scope with that
    // declaration, which is why this is a scope field rather than a walk-lifetime map.
    TypeParameterConstraints: Dictionary<string, List<TypeInfo>> => typeParameterConstraintsValue

    // THE `struct` HALF OF THE SAME `where` CLAUSE, which is a SPECIAL constraint and names no type,
    // so the dictionary above cannot hold it. It is what makes `T?` a real `Nullable<T>` rather than
    // a reference annotation, and therefore what a read of `a.HasValue` inside the declaration has
    // to consult: a type parameter is a `SimpleTypeInfo` and every reader that asks "is this a
    // reference type?" of a bare name answers YES.
    StructConstrainedTypeParameters: HashSet<string> => structConstrainedTypeParametersValue
    NullStates: Dictionary<string, NullState> => nullStatesValue
    ErrorTupleResults: Dictionary<string, ErrorTupleResultGuard> => errorTupleResultsValue
    AvailableErrorTupleResults: HashSet<string> => availableErrorTupleResultsValue

    constructor(kind: ScopeKind) {
        kindValue = kind
        symbolsValue = new Dictionary<string, TypeInfo>()
        typesValue = new Dictionary<string, TypeInfo>()
        nullStatesValue = new Dictionary<string, NullState>(StringComparer.Ordinal)
        errorTupleResultsValue = new Dictionary<string, ErrorTupleResultGuard>(StringComparer.Ordinal)
        availableErrorTupleResultsValue = new HashSet<string>(StringComparer.Ordinal)
        declarationLocations = new Dictionary<string, SymbolDeclaration>()
        typeAritiesValue = new Dictionary<string, List<int>>(StringComparer.Ordinal)
        hoistedLocalFunctionsValue = new HashSet<string>(StringComparer.Ordinal)
        typeParameterConstraintsValue = new Dictionary<string, List<TypeInfo>>(StringComparer.Ordinal)
        structConstrainedTypeParametersValue = new HashSet<string>(StringComparer.Ordinal)
        readOnlyNamesValue = new HashSet<string>(StringComparer.Ordinal)
    }

    func MarkReadOnly(name: string) {
        readOnlyNamesValue.Add(name)
    }

    func IsReadOnly(name: string): bool {
        return readOnlyNamesValue.Contains(name)
    }

    // THE LOCAL FUNCTIONS THIS SCOPE ALREADY BOUND BEFORE ITS FIRST STATEMENT RAN. A local
    // function's name is in scope throughout the block that declares it, so the block binds every
    // one of them up front; when the walk later reaches the declaration STATEMENT it must not
    // declare the name a second time and report itself as a duplicate. This set is that memory, and
    // it is per-scope because visibility is per-block: an inner block's local functions are not
    // visible outside it and its set dies with it.
    func RecordHoistedLocalFunction(name: string) {
        hoistedLocalFunctionsValue.Add(name)
    }

    func HasHoistedLocalFunction(name: string): bool {
        return hoistedLocalFunctionsValue.Contains(name)
    }

    // The one write path for a type binding. `key` is an identity key; the arity index is derived
    // from it so the two tables cannot drift apart.
    func DeclareType(key: string, typeInfo: TypeInfo) {
        typesValue[key] = typeInfo

        displayName := TypeArityNames.Display(key)
        arity := TypeArityNames.ArityOf(key)
        arities := new List<int>()
        if !typeAritiesValue.TryGetValue(displayName, out arities) {
            arities = new List<int>()
            typeAritiesValue[displayName] = arities
        }

        if !arities.Contains(arity) {
            arities.Add(arity)
        }
    }

    // Whether this scope binds a bare name as a TYPE at any arity. The predicate every "is this name
    // a type here?" question asks, because a generic type's identity key is not its written name.
    func BindsTypeName(name: string): bool {
        return typeAritiesValue.ContainsKey(name) || typesValue.ContainsKey(name)
    }

    // Every arity declared in THIS scope for a bare name, in declaration order. An empty list means
    // the name is not declared here at all.
    func AritiesFor(name: string): List<int> {
        arities := new List<int>()
        if typeAritiesValue.TryGetValue(name, out arities) {
            return arities
        }

        return new List<int>()
    }

    // A declaration location is recorded under the IDENTITY key, so a generic type and a non-generic
    // one of the same name keep their own go-to-definition targets; the SymbolDeclaration itself
    // carries the name as written, because that is what an editor shows and underlines.
    func RecordDeclarationLocation(name: string, filePath: string?, line: int, column: int, kind: string) {
        declarationLocations[name] = new SymbolDeclaration(TypeArityNames.Display(name), filePath, line, column, kind)
    }

    func GetDeclarationLocation(name: string): SymbolDeclaration? {
        if declarationLocations.ContainsKey(name) {
            return declarationLocations[name]
        }

        return null
    }
}

class ErrorTupleResultGuard {
    ResultName: string
    ErrorName: string
    Line: int
    Column: int

    constructor(ResultName: string, ErrorName: string, Line: int, Column: int) {
        this.ResultName = ResultName
        this.ErrorName = ErrorName
        this.Line = Line
        this.Column = Column
    }
}
