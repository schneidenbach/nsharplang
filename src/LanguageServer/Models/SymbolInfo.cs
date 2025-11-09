using System.Collections.Generic;
using NewCLILang.Compiler.Ast;

namespace LanguageServer.Models;

/// <summary>
/// Represents a symbol (type, function, property, etc.) for intellisense
/// </summary>
public class SymbolInfo
{
    public string Name { get; init; }
    public SymbolKind Kind { get; init; }
    public string? TypeName { get; init; }  // For variables, properties, return types
    public string? Documentation { get; init; }
    public List<ParameterInfo> Parameters { get; init; } = new();
    public List<SymbolInfo> Members { get; init; } = new();  // For types with members
    public Modifiers Modifiers { get; init; }

    public SymbolInfo(string name, SymbolKind kind)
    {
        Name = name;
        Kind = kind;
    }
}

public class ParameterInfo
{
    public string Name { get; init; }
    public string TypeName { get; init; }
    public bool HasDefaultValue { get; init; }

    public ParameterInfo(string name, string typeName, bool hasDefaultValue = false)
    {
        Name = name;
        TypeName = typeName;
        HasDefaultValue = hasDefaultValue;
    }
}

public enum SymbolKind
{
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
