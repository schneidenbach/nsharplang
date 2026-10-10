namespace NSharpLang.LanguageServer.Models

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Represents a symbol (type, function, property, etc.) for intellisense
class SymbolInfo {
    Name: string
    Kind: SymbolKind
    TypeName: string?
    // For variables, properties, return types
    Documentation: string?
    Parameters: List<ParameterInfo>
    Members: List<SymbolInfo>
    // For types with members
    Modifiers: Modifiers

    constructor(name: string, kind: SymbolKind) {
        Name = name
        Kind = kind
        Parameters = new List<ParameterInfo>()
        Members = new List<SymbolInfo>()
    }
}

class ParameterInfo {
    Name: string
    TypeName: string
    HasDefaultValue: bool

    constructor(name: string, typeName: string, hasDefaultValue: bool = false) {
        Name = name
        TypeName = typeName
        HasDefaultValue = hasDefaultValue
    }
}

enum SymbolKind {
    Class,
    Struct,
    Record,
    Interface,
    Enum,
    Union,
    Function,
    Method,
    Property,
    Field,
    Parameter,
    LocalVariable,
    EnumMember,
    Constructor
}
