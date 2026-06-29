namespace NSharpLang.Compiler

import System.Collections.Generic

public enum AttributeArgumentConstantKind {
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

public enum DiscardedExpressionContext {
    ExpressionStatement,
    ForIterator
}

public class FlowNarrowing {
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

public class Scope {
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

    public func RecordDeclarationLocation(name: string, filePath: string?, line: int, column: int, kind: string) {
        declarationLocations[name] = new SymbolDeclaration(name, filePath, line, column, kind)
    }

    public func GetDeclarationLocation(name: string): SymbolDeclaration? {
        if declarationLocations.ContainsKey(name) {
            return declarationLocations[name]
        }

        return null
    }
}

public class ErrorTupleResultGuard {
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
