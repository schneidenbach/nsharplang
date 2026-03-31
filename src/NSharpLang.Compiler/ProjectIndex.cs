using System.Collections.Generic;

namespace NSharpLang.Compiler;

/// <summary>
/// The project-level semantic index produced after analyzing all source files.
/// Separates query/navigation data from the analysis engine itself.
///
/// Created by <see cref="MultiFileCompiler"/> after a full analysis pass.
/// Consumed by CodeIntelligenceService, QueryCommand, and the LSP layer.
/// </summary>
public class ProjectIndex
{
    private readonly Dictionary<string, string> _typeDeclarationFiles;

    /// <summary>
    /// The merged project-wide binding map: every identifier usage resolved to its declaration,
    /// and every declaration to all its usages. Foundation for semantic FindReferences and GoToDefinition.
    /// </summary>
    public BindingMap Bindings { get; }

    /// <summary>
    /// Maps type names to the source file that declares them.
    /// Enables cross-file GoToDefinition for types without walking all ASTs.
    /// </summary>
    public IReadOnlyDictionary<string, string> TypeDeclarationFiles => _typeDeclarationFiles;

    public ProjectIndex(BindingMap bindings, Dictionary<string, string> typeDeclarationFiles)
    {
        Bindings = bindings;
        _typeDeclarationFiles = typeDeclarationFiles;
    }

    /// <summary>
    /// Merge another ProjectIndex into this one during multi-file aggregation.
    /// BindingMap entries and TypeDeclarationFiles are union-merged (last writer wins per key).
    /// </summary>
    internal void Merge(ProjectIndex other)
    {
        Bindings.Merge(other.Bindings);

        foreach (var (typeName, filePath) in other._typeDeclarationFiles)
        {
            _typeDeclarationFiles[typeName] = filePath;
        }
    }
}
