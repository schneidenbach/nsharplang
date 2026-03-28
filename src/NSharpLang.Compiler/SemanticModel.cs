using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler;

/// <summary>
/// Stores semantic information from analysis for use by IDE features.
/// Maps identifiers to their resolved types.
/// </summary>
public class SemanticModel
{
    /// <summary>
    /// Maps expression positions to their resolved types.
    /// Key: (line, column), Value: resolved TypeInfo
    /// </summary>
    public Dictionary<(int Line, int Column), TypeInfo> ExpressionTypes { get; } = new();

    /// <summary>
    /// Maps variable/parameter names to their resolved types.
    /// Key: variable name, Value: resolved TypeInfo
    /// </summary>
    public Dictionary<string, TypeInfo> Variables { get; } = new();

    /// <summary>
    /// Maps function names to their return types.
    /// Key: function name, Value: return TypeInfo
    /// </summary>
    public Dictionary<string, TypeInfo> Functions { get; } = new();

    /// <summary>
    /// Maps property names to their types.
    /// Key: property name, Value: property TypeInfo
    /// </summary>
    public Dictionary<string, TypeInfo> Properties { get; } = new();

    /// <summary>
    /// Maps field names to their types.
    /// Key: field name, Value: field TypeInfo
    /// </summary>
    public Dictionary<string, TypeInfo> Fields { get; } = new();

    /// <summary>
    /// All type declarations in the current compilation unit.
    /// Key: type name, Value: TypeInfo
    /// </summary>
    public Dictionary<string, TypeInfo> Types { get; } = new();

    /// <summary>
    /// Maps type name → member name → resolved TypeInfo.
    /// Stores semantically resolved member types for class/struct/record declarations.
    /// </summary>
    public Dictionary<string, Dictionary<string, TypeInfo>> TypeMembers { get; } = new();

    /// <summary>
    /// Record a variable and its type
    /// </summary>
    public void RecordVariable(string name, TypeInfo type)
    {
        Variables[name] = type;
    }

    /// <summary>
    /// Record a function and its return type
    /// </summary>
    public void RecordFunction(string name, TypeInfo returnType)
    {
        Functions[name] = returnType;
    }

    /// <summary>
    /// Record a property and its type
    /// </summary>
    public void RecordProperty(string name, TypeInfo type)
    {
        Properties[name] = type;
    }

    /// <summary>
    /// Record a field and its type
    /// </summary>
    public void RecordField(string name, TypeInfo type)
    {
        Fields[name] = type;
    }

    /// <summary>
    /// Record a type declaration
    /// </summary>
    public void RecordType(string name, TypeInfo type)
    {
        Types[name] = type;
    }

    /// <summary>
    /// Record a member (field or property) of a type with its resolved type.
    /// </summary>
    public void RecordTypeMember(string typeName, string memberName, TypeInfo memberType)
    {
        if (!TypeMembers.TryGetValue(typeName, out var members))
        {
            members = new Dictionary<string, TypeInfo>();
            TypeMembers[typeName] = members;
        }
        members[memberName] = memberType;
    }

    /// <summary>
    /// Get all recorded members for a type. Returns null if no members are recorded.
    /// </summary>
    public Dictionary<string, TypeInfo>? GetTypeMembers(string typeName)
    {
        return TypeMembers.TryGetValue(typeName, out var members) ? members : null;
    }

    /// <summary>
    /// Record the resolved type for an expression at a specific source position.
    /// </summary>
    public void RecordExpressionType(int line, int column, TypeInfo type)
    {
        ExpressionTypes[(line, column)] = type;
    }

    /// <summary>
    /// Try to find the type of an identifier (variable, parameter, property, field, or function)
    /// </summary>
    public TypeInfo? LookupIdentifier(string name)
    {
        // Try variables first (most common for member access)
        if (Variables.TryGetValue(name, out var varType))
            return varType;

        // Try properties
        if (Properties.TryGetValue(name, out var propType))
            return propType;

        // Try fields
        if (Fields.TryGetValue(name, out var fieldType))
            return fieldType;

        // Try functions (for function pointers/delegates)
        if (Functions.TryGetValue(name, out var funcType))
            return funcType;

        // Try types
        if (Types.TryGetValue(name, out var type))
            return type;

        return null;
    }

    /// <summary>
    /// Try to find the resolved type recorded for an expression at a source position.
    /// </summary>
    public TypeInfo? LookupTypeAtPosition(int line, int column)
    {
        return ExpressionTypes.TryGetValue((line, column), out var type) ? type : null;
    }
}
