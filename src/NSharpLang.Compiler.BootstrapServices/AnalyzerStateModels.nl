namespace NSharpLang.Compiler

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

    Kind: ScopeKind => kindValue
    Symbols: Dictionary<string, TypeInfo> => symbolsValue
    Types: Dictionary<string, TypeInfo> => typesValue
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
    }

    func RecordDeclarationLocation(name: string, filePath: string?, line: int, column: int, kind: string) {
        declarationLocations[name] = new SymbolDeclaration(name, filePath, line, column, kind)
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
