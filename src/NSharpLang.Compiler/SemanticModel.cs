using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler;

/// <summary>
/// Represents a scope with position range for position-aware identifier lookups.
/// Scopes form a tree: each scope has a parent (except the root).
/// </summary>
public class ScopeInfo
{
    public int Id { get; }
    public int ParentId { get; }
    public int StartLine { get; }
    public int StartColumn { get; }
    public int EndLine { get; internal set; }
    public int EndColumn { get; internal set; }
    public Dictionary<string, TypeInfo> Variables { get; } = new();
    public Dictionary<string, TypeInfo> Functions { get; } = new();

    public ScopeInfo(int id, int parentId, int startLine, int startColumn)
    {
        Id = id;
        ParentId = parentId;
        StartLine = startLine;
        StartColumn = startColumn;
    }

    /// <summary>
    /// Returns true if the given position falls within this scope's range.
    /// </summary>
    public bool ContainsPosition(int line, int column)
    {
        if (EndLine == 0) return false; // scope not yet closed

        if (line < StartLine || line > EndLine) return false;
        if (line == StartLine && column < StartColumn) return false;
        if (line == EndLine && column > EndColumn) return false;
        return true;
    }
}

/// <summary>
/// Stores semantic information from analysis for use by IDE features.
/// Maps identifiers to their resolved types with optional position-aware scope tracking.
/// </summary>
public class SemanticModel
{
    /// <summary>
    /// Maps expression positions to their resolved types.
    /// Key: (line, column), Value: resolved TypeInfo
    /// </summary>
    public Dictionary<(int Line, int Column), TypeInfo> ExpressionTypes { get; } = new();

    /// <summary>
    /// Maps call expression positions to the CLR method selected by overload resolution.
    /// Key: (line, column), Value: selected method.
    /// </summary>
    public Dictionary<(int Line, int Column), System.Reflection.MethodInfo> ReflectionCallTargets { get; } = new();

    /// <summary>
    /// Maps variable/parameter names to their resolved types (flat, last-write-wins).
    /// Use LookupIdentifierAtPosition for scope-aware lookups.
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

    // ── Scope tracking ──────────────────────────────────────────────────

    private readonly List<ScopeInfo> _scopes = new();

    /// <summary>
    /// All recorded scopes, for testing and inspection.
    /// </summary>
    public IReadOnlyList<ScopeInfo> Scopes => _scopes;

    /// <summary>
    /// Open a new scope at the given source position. Returns the scope ID.
    /// </summary>
    public int OpenScope(int parentId, int startLine, int startColumn)
    {
        var id = _scopes.Count;
        _scopes.Add(new ScopeInfo(id, parentId, startLine, startColumn));
        return id;
    }

    /// <summary>
    /// Close a previously opened scope, recording where it ends.
    /// </summary>
    public void CloseScope(int scopeId, int endLine, int endColumn)
    {
        if (scopeId >= 0 && scopeId < _scopes.Count)
        {
            _scopes[scopeId].EndLine = endLine;
            _scopes[scopeId].EndColumn = endColumn;
        }
    }

    /// <summary>
    /// Record a variable in a specific scope (for position-aware lookups).
    /// Also records in the flat Variables dict for backward compatibility.
    /// </summary>
    public void RecordScopedVariable(int scopeId, string name, TypeInfo type)
    {
        if (scopeId >= 0 && scopeId < _scopes.Count)
        {
            _scopes[scopeId].Variables[name] = type;
        }
        Variables[name] = type;
    }

    /// <summary>
    /// Record a function in a specific scope (for position-aware lookups).
    /// Also records in the flat Functions dict for backward compatibility.
    /// </summary>
    public void RecordScopedFunction(int scopeId, string name, TypeInfo type)
    {
        if (scopeId >= 0 && scopeId < _scopes.Count)
        {
            _scopes[scopeId].Functions[name] = type;
        }
        Functions[name] = type;
    }

    // ── Recording (flat, backward-compatible) ───────────────────────────

    /// <summary>
    /// Record a variable and its type (flat, last-write-wins)
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
    /// Record the CLR method selected for a call expression.
    /// </summary>
    public void RecordReflectionCallTarget(int line, int column, System.Reflection.MethodInfo method)
    {
        ReflectionCallTargets[(line, column)] = method;
    }

    // ── Lookups ─────────────────────────────────────────────────────────

    /// <summary>
    /// Try to find the type of an identifier (variable, parameter, property, field, or function).
    /// Flat lookup — does not consider position/scope. Use LookupIdentifierAtPosition for scope awareness.
    /// </summary>
    public TypeInfo? LookupIdentifier(string name)
    {
        if (Variables.TryGetValue(name, out var varType))
            return varType;

        if (Properties.TryGetValue(name, out var propType))
            return propType;

        if (Fields.TryGetValue(name, out var fieldType))
            return fieldType;

        if (Functions.TryGetValue(name, out var funcType))
            return funcType;

        if (Types.TryGetValue(name, out var type))
            return type;

        return null;
    }

    /// <summary>
    /// Position-aware identifier lookup that respects variable shadowing and scope boundaries.
    /// Finds the innermost scope containing (line, col) that has a binding for the name.
    /// Falls back to flat lookup if no scoped binding is found.
    /// </summary>
    public TypeInfo? LookupIdentifierAtPosition(string name, int line, int column)
    {
        if (_scopes.Count == 0)
            return LookupIdentifier(name);

        // Collect all scopes that contain this position
        // Then find the innermost one that has a binding for the name
        TypeInfo? best = null;
        int bestDepth = -1;

        foreach (var scope in _scopes)
        {
            if (!scope.ContainsPosition(line, column)) continue;

            var depth = GetScopeDepth(scope.Id);
            if (depth <= bestDepth) continue;

            if (scope.Variables.TryGetValue(name, out var varType))
            {
                best = varType;
                bestDepth = depth;
            }
            else if (scope.Functions.TryGetValue(name, out var funcType))
            {
                best = funcType;
                bestDepth = depth;
            }
        }

        if (best != null) return best;

        // Fall back to non-variable lookups (properties, fields, types)
        if (Properties.TryGetValue(name, out var propType))
            return propType;
        if (Fields.TryGetValue(name, out var fieldType))
            return fieldType;
        if (Types.TryGetValue(name, out var type))
            return type;

        return null;
    }

    /// <summary>
    /// Get all variables visible at a given source position, respecting scope boundaries.
    /// For each variable name, returns the binding from the innermost scope.
    /// Falls back to flat Variables dict if no scopes are recorded.
    /// </summary>
    public Dictionary<string, TypeInfo> GetVisibleVariablesAtPosition(int line, int column)
    {
        if (_scopes.Count == 0)
            return new Dictionary<string, TypeInfo>(Variables);

        // Collect containing scopes sorted by depth (deepest first)
        var containingScopes = new List<ScopeInfo>();
        foreach (var scope in _scopes)
        {
            if (scope.ContainsPosition(line, column))
                containingScopes.Add(scope);
        }

        if (containingScopes.Count == 0)
            return new Dictionary<string, TypeInfo>(Variables);

        // Sort by depth (deepest first) so inner bindings shadow outer ones
        containingScopes.Sort((a, b) => GetScopeDepth(b.Id).CompareTo(GetScopeDepth(a.Id)));

        var result = new Dictionary<string, TypeInfo>();
        foreach (var scope in containingScopes)
        {
            foreach (var (name, type) in scope.Variables)
            {
                result.TryAdd(name, type); // first (innermost) wins
            }
            foreach (var (name, type) in scope.Functions)
            {
                result.TryAdd(name, type);
            }
        }

        return result;
    }

    /// <summary>
    /// Try to find the resolved type recorded for an expression at a source position.
    /// </summary>
    public TypeInfo? LookupTypeAtPosition(int line, int column)
    {
        return ExpressionTypes.TryGetValue((line, column), out var type) ? type : null;
    }

    /// <summary>
    /// Try to find the CLR method selected for a call expression at a source position.
    /// </summary>
    public System.Reflection.MethodInfo? LookupReflectionCallTarget(int line, int column)
    {
        return ReflectionCallTargets.TryGetValue((line, column), out var method) ? method : null;
    }

    // ── Internal helpers ────────────────────────────────────────────────

    private int GetScopeDepth(int scopeId)
    {
        int depth = 0;
        var current = scopeId;
        while (current >= 0 && current < _scopes.Count)
        {
            var parentId = _scopes[current].ParentId;
            if (parentId < 0 || parentId == current) break;
            depth++;
            current = parentId;
        }
        return depth;
    }
}
