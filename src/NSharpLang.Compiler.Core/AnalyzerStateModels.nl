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
