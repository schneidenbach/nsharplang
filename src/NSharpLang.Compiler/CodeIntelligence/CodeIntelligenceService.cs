using System.Collections.Generic;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Loads a project snapshot and forwards every question about it to N#.
/// Both the CLI (nlc query) and the LSP consume this: CLI callers load disk text,
/// while the LSP can supply in-memory open-buffer overrides for unsaved edits.
///
/// This is built BELOW the Language Server's DocumentManager. It knows nothing about
/// open documents, editor buffers, or LSP protocols.
/// </summary>
/// <remarks>
/// Reviewed zero-policy mechanical host. It holds exactly one thing that cannot move, and the
/// reason is a direction of dependency rather than a shape: <see cref="MultiFileCompiler"/> lives
/// in this assembly, so the N# owners in <c>NSharpLang.Compiler.BootstrapServices</c> — which this
/// assembly references — cannot construct one. Everything else, including
/// <see cref="ProjectSnapshot"/> itself, is N#: <c>CodeIntelligenceQueries</c> answers the queries
/// and <c>CodeIntelligenceNavigation</c> resolves the positions they are asked at.
/// </remarks>
public class CodeIntelligenceService
{
    /// <summary>
    /// Load and fully analyze a project from disk.
    /// Returns an immutable snapshot that can be queried.
    /// </summary>
    public ProjectSnapshot LoadProject(string projectRoot)
        => LoadProject(projectRoot, sourceTextOverrides: null);

    /// <summary>
    /// Load and fully analyze a project with optional in-memory source text overrides.
    /// Used by the LSP to answer semantic queries against unsaved editor buffers
    /// while still reading unchanged project files from disk.
    /// </summary>
    public ProjectSnapshot LoadProject(string projectRoot, IReadOnlyDictionary<string, string>? sourceTextOverrides)
    {
        var config = ProjectFileParser.ParseFromDirectory(projectRoot);
        return LoadProject(projectRoot, config, sourceTextOverrides);
    }

    public ProjectSnapshot LoadProject(
        string projectRoot,
        ProjectConfig? config,
        IReadOnlyDictionary<string, string>? sourceTextOverrides = null)
    {
        var compiler = new MultiFileCompiler(projectRoot, config, sourceTextOverrides);
        compiler.CompileForAnalysis();

        return new ProjectSnapshot(
            projectRoot,
            compiler.CompilationUnits,
            compiler.SemanticModels,
            compiler.AllErrors,
            compiler.SourceFiles,
            compiler.ProjectIndex,
            compiler.SourceTexts,
            compiler.PerformanceFacts,
            compiler.SystemsReport
        );
    }

    // ── Symbol Queries ──────────────────────────────────────────────────

    /// <summary>
    /// Get all symbols in the project, optionally filtered by file and/or kind.
    /// </summary>
    /// <remarks>
    /// The arity choice is a nullable-lowering adapter, not a decision: a <c>SymbolKind?</c> static
    /// parameter declines at <c>emit.declaration.method-param</c>, so the two arms are two N# entry
    /// points. Both the walk and the filter belong to <c>CodeIntelligenceQueries</c>.
    /// </remarks>
    public List<SymbolResult> GetSymbols(ProjectSnapshot snapshot, string? file = null, SymbolKind? kind = null)
        => kind == null
            ? CodeIntelligenceQueries.Symbols(snapshot, file)
            : CodeIntelligenceQueries.SymbolsOfKind(snapshot, file, kind.Value);

    /// <summary>
    /// Get the structural outline of a single file.
    /// </summary>
    public OutlineResult GetOutline(ProjectSnapshot snapshot, string file)
        => CodeIntelligenceQueries.Outline(snapshot, file);

    /// <summary>
    /// Get the structural outline of a single file using the fast path (no project analysis).
    /// </summary>
    public OutlineResult GetOutlineSingleFile(string filePath)
        => CodeIntelligenceQueries.OutlineSingleFile(filePath);

    // ── Diagnostic Queries ──────────────────────────────────────────────

    /// <summary>
    /// Get all diagnostics for the project, optionally filtered by file.
    /// Returns Elm-level rich diagnostics with explanations, suggestions, source snippets, etc.
    /// </summary>
    public List<DiagnosticResult> GetDiagnostics(ProjectSnapshot snapshot, string? file = null)
        => CodeIntelligenceQueries.Diagnostics(snapshot, file);

    // ── Navigation Queries ──────────────────────────────────────────────

    /// <summary>
    /// Get type information for the expression/symbol at a position.
    /// </summary>
    public TypeResult? GetTypeAtPosition(ProjectSnapshot snapshot, string file, int line, int col)
        => CodeIntelligenceNavigation.TypeAtPosition(snapshot, file, line, col);

    /// <summary>
    /// Find the definition of the symbol at a position (semantic, position-based).
    /// </summary>
    public DefinitionResult? FindDefinition(ProjectSnapshot snapshot, string file, int line, int col)
        => CodeIntelligenceQueries.Definition(snapshot, file, line, col);

    /// <summary>
    /// Find all semantic references to the symbol at a position.
    /// Position-based ONLY — this is a semantic operation.
    /// </summary>
    public List<ReferenceResult> FindReferences(ProjectSnapshot snapshot, string file, int line, int col)
        => CodeIntelligenceQueries.References(snapshot, file, line, col);

    /// <summary>
    /// Find references only when the selected position has a strict BindingMap declaration/binding.
    /// </summary>
    public List<ReferenceResult> FindStrictReferences(ProjectSnapshot snapshot, string file, int line, int col)
        => CodeIntelligenceQueries.References(snapshot, file, line, col);

    // ── Hover Query ─────────────────────────────────────────────────────

    /// <summary>
    /// Get hover information for the symbol at a position.
    /// Combines type info + definition location + doc comment extraction.
    /// Returns null if there is no symbol at that position.
    /// </summary>
    public HoverResult? GetHoverInfo(ProjectSnapshot snapshot, string file, int line, int col)
        => CodeIntelligenceQueries.HoverInfo(snapshot, file, line, col);

    // ── Call Graph ──────────────────────────────────────────────────────

    /// <summary>
    /// Build a call graph for the project by walking all ASTs.
    /// If functionName is provided, returns callers and callees for that function only.
    /// If functionName is null, returns all edges up to the limit.
    /// </summary>
    public CallGraphResult GetCallGraph(ProjectSnapshot snapshot, string? functionName, int limit = 100)
        => CodeIntelligenceQueries.CallGraph(snapshot, functionName, limit);

    // ── Implementors ────────────────────────────────────────────────────

    /// <summary>
    /// Find all concrete types (class, struct, record) that implement a given interface.
    /// Walks all compilation units in the project.
    /// </summary>
    public ImplementorsResult GetImplementors(ProjectSnapshot snapshot, string interfaceName)
        => CodeIntelligenceQueries.Implementors(snapshot, interfaceName);
}
