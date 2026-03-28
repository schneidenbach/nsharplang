using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler;

/// <summary>
/// Represents a symbol declaration — the place where a symbol is defined.
/// Uniquely identified by (File, Line, Column).
/// </summary>
public record SymbolDeclaration(
    string Name,
    string? File,
    int Line,
    int Column,
    string Kind);

/// <summary>
/// Represents a usage/reference of a symbol.
/// </summary>
public record SymbolUsage(
    string? File,
    int Line,
    int Column,
    int Length);

/// <summary>
/// Records semantic binding decisions made during analysis.
/// Maps each identifier usage to the declaration it resolves to,
/// and provides reverse lookup (declaration → all usages).
///
/// This is the foundation for semantic FindReferences — instead of grep,
/// we can find all expressions that resolve to the same declaration.
/// </summary>
public class BindingMap
{
    // Forward map: usage location → the declaration it binds to
    private readonly Dictionary<(string? File, int Line, int Col), SymbolDeclaration> _bindings = new();

    // Reverse map: declaration location → all usages
    private readonly Dictionary<(string? File, int Line, int Col), List<SymbolUsage>> _references = new();

    // All declarations recorded
    private readonly Dictionary<(string? File, int Line, int Col), SymbolDeclaration> _declarations = new();

    /// <summary>
    /// Record that the identifier at (usageFile, usageLine, usageCol) resolves to the given declaration.
    /// </summary>
    public void RecordBinding(string? usageFile, int usageLine, int usageCol, int usageLength,
                              SymbolDeclaration declaration)
    {
        var usageKey = (usageFile, usageLine, usageCol);

        // If this usage was previously bound to a different declaration,
        // remove it from the old declaration's reference list.
        if (_bindings.TryGetValue(usageKey, out var oldDecl))
        {
            var oldDeclKey = (oldDecl.File, oldDecl.Line, oldDecl.Column);
            var newDeclKey = (declaration.File, declaration.Line, declaration.Column);
            if (oldDeclKey != newDeclKey && _references.TryGetValue(oldDeclKey, out var oldUsages))
            {
                oldUsages.RemoveAll(u => u.File == usageFile && u.Line == usageLine && u.Column == usageCol);
            }
        }

        _bindings[usageKey] = declaration;

        // Record the declaration itself
        var declKey = (declaration.File, declaration.Line, declaration.Column);
        _declarations[declKey] = declaration;

        // Add to reverse map
        if (!_references.TryGetValue(declKey, out var usages))
        {
            usages = new List<SymbolUsage>();
            _references[declKey] = usages;
        }

        usages.Add(new SymbolUsage(usageFile, usageLine, usageCol, usageLength));
    }

    /// <summary>
    /// Record a declaration without a usage (for the declaration site itself).
    /// </summary>
    public void RecordDeclaration(SymbolDeclaration declaration)
    {
        var key = (declaration.File, declaration.Line, declaration.Column);

        // Don't overwrite a type declaration (class, struct, record, etc.) with
        // internal symbols like "this" that share the same position.
        if (_declarations.TryGetValue(key, out var existing))
        {
            var existingIsType = existing.Kind is "class" or "struct" or "record" or "interface" or "enum" or "union";
            var newIsInternal = declaration.Name is "this" or "value";
            if (existingIsType && newIsInternal)
            {
                // Keep the type declaration, skip the internal symbol
                return;
            }
        }

        _declarations[key] = declaration;

        if (!_references.ContainsKey(key))
        {
            _references[key] = new List<SymbolUsage>();
        }
    }

    /// <summary>
    /// Get the declaration that the identifier at this position resolves to.
    /// Returns null if no binding was recorded at this position.
    /// </summary>
    public SymbolDeclaration? GetBindingAt(string? file, int line, int col)
    {
        // First check if this position IS a declaration
        if (_declarations.TryGetValue((file, line, col), out var decl))
            return decl;

        // Then check if there's a binding at this position
        if (_bindings.TryGetValue((file, line, col), out var binding))
            return binding;

        return null;
    }

    /// <summary>
    /// Get all usages of a declaration (by its location).
    /// </summary>
    public List<SymbolUsage> GetReferences(SymbolDeclaration declaration)
    {
        var key = (declaration.File, declaration.Line, declaration.Column);
        return _references.TryGetValue(key, out var usages) ? usages : new List<SymbolUsage>();
    }

    /// <summary>
    /// Get all usages of whatever is declared/referenced at this position.
    /// This is the main API for FindReferences: give me a position,
    /// I'll find what it resolves to, then return all other positions that resolve to the same thing.
    /// </summary>
    public (SymbolDeclaration? Declaration, List<SymbolUsage> Usages) FindAllReferences(string? file, int line, int col)
    {
        var declaration = GetBindingAt(file, line, col);
        if (declaration == null)
            return (null, new List<SymbolUsage>());

        var usages = GetReferences(declaration);
        return (declaration, usages);
    }

    /// <summary>
    /// Find a declaration by name. Returns all declarations with matching name.
    /// Used as fallback when position-based lookup doesn't find a binding.
    /// </summary>
    public List<SymbolDeclaration> FindDeclarationsByName(string name)
    {
        return _declarations.Values
            .Where(d => d.Name == name)
            .Distinct()
            .ToList();
    }

    /// <summary>
    /// Get all declarations in this binding map.
    /// </summary>
    public IReadOnlyCollection<SymbolDeclaration> AllDeclarations => _declarations.Values;

    /// <summary>
    /// Get the total number of bindings recorded.
    /// </summary>
    public int BindingCount => _bindings.Count;

    /// <summary>
    /// Merge another BindingMap into this one (for multi-file aggregation).
    /// </summary>
    public void Merge(BindingMap other)
    {
        foreach (var (key, decl) in other._declarations)
        {
            _declarations[key] = decl;
        }

        foreach (var (key, binding) in other._bindings)
        {
            _bindings[key] = binding;
        }

        foreach (var (key, usages) in other._references)
        {
            if (!_references.TryGetValue(key, out var existing))
            {
                existing = new List<SymbolUsage>();
                _references[key] = existing;
            }
            existing.AddRange(usages);
        }
    }
}
