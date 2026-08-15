using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Performance;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Core code intelligence service. Operates on project snapshots.
/// Both the CLI (nlc query) and the LSP consume this: CLI callers load disk text,
/// while the LSP can supply in-memory open-buffer overrides for unsaved edits.
///
/// This is built BELOW the Language Server's DocumentManager. It knows nothing about
/// open documents, editor buffers, or LSP protocols. It receives optional source text
/// overrides from callers, parses/analyzes the resulting project snapshot, and answers
/// semantic queries.
/// </summary>
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
            compiler.SharedAnalyzer,
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
    public List<SymbolResult> GetSymbols(ProjectSnapshot snapshot, string? file = null, SymbolKind? kind = null)
    {
        var results = new List<SymbolResult>();

        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            if (file != null && !CodeIntelligenceResultKernels.MatchesFilePath(filePath, file))
                continue;

            var relativeFile = CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath);
            results.AddRange(CodeIntelligenceDeclarationProjection.Symbols(cu.Declarations, relativeFile));
        }

        if (kind != null)
        {
            results = CodeIntelligenceSymbolKernels.FilterSymbolsByKind(results, kind.Value);
        }

        return results;
    }

    /// <summary>
    /// Get the structural outline of a single file.
    /// </summary>
    public OutlineResult GetOutline(ProjectSnapshot snapshot, string file)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null)
        {
            return new OutlineResult(file, Array.Empty<string>(), Array.Empty<OutlineEntry>());
        }

        var imports = cu.Imports.Select(i => i.Namespace).ToArray();
        var outline = CodeIntelligenceDeclarationProjection.OutlineEntries(cu.Declarations);

        return new OutlineResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), imports, outline);
    }

    /// <summary>
    /// Get the structural outline of a single file using the fast path (no project analysis).
    /// </summary>
    public OutlineResult GetOutlineSingleFile(string filePath)
    {
        var source = File.ReadAllText(filePath);
        var parseResult = NSharpLang.Compiler.Columnar.ColumnarParserRecovery.ParseFileAst(source, filePath);

        if (parseResult.CompilationUnit == null)
        {
            return new OutlineResult(filePath, Array.Empty<string>(), Array.Empty<OutlineEntry>());
        }

        var cu = parseResult.CompilationUnit;
        var imports = cu.Imports.Select(i => i.Namespace).ToArray();
        var outline = CodeIntelligenceDeclarationProjection.OutlineEntries(cu.Declarations);

        return new OutlineResult(filePath, imports, outline);
    }

    // ── Diagnostic Queries ──────────────────────────────────────────────

    /// <summary>
    /// Get all diagnostics for the project, optionally filtered by file.
    /// Returns Elm-level rich diagnostics with explanations, suggestions, source snippets, etc.
    /// </summary>
    /// <remarks>
    /// Mechanical driver: <see cref="ProjectSnapshot"/> is a C# type this assembly declares, so the
    /// five reads it carries are materialised here and every diagnostic decision belongs to
    /// <see cref="CodeIntelligenceDiagnostics"/>. The snapshot's own collections cross unchanged —
    /// the published IReadOnlyDictionary catalog row removed the two per-call rebuilds this driver
    /// used to need, which is a real saving on the LSP's publish path.
    /// </remarks>
    public List<DiagnosticResult> GetDiagnostics(ProjectSnapshot snapshot, string? file = null)
        => CodeIntelligenceDiagnostics.Build(
            snapshot.ProjectRoot,
            snapshot.AllErrors,
            snapshot.SourceFiles,
            snapshot.CompilationUnits,
            snapshot.SourceTexts,
            file);

    // ── Navigation Queries ──────────────────────────────────────────────

    /// <summary>
    /// Get type information for the expression/symbol at a position.
    /// Uses AstNodeFinder + SemanticModel for semantic resolution.
    /// </summary>
    /// <remarks>
    /// The three routes below are tried in order and every type-info decision inside them belongs to
    /// <see cref="CodeIntelligenceTypeResolution"/>. What survives here is the ORDER, the position
    /// plumbing, and the <see cref="ProjectSnapshot"/> reads that assembly declares.
    /// </remarks>
    public TypeResult? GetTypeAtPosition(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null) return null;

        snapshot.SemanticModels.TryGetValue(filePath, out var semanticModel);

        var declarationType = ResolveDeclaredNameTypeAtPosition(snapshot, filePath, cu, line, col);
        if (declarationType != null)
            return declarationType;

        var typeUse = ResolveTypeUseAtPosition(snapshot, filePath, cu, semanticModel, line, col);
        if (typeUse != null)
            return typeUse;

        var expr = FindExpressionAtPositionRobust(cu, line, col);
        var candidateNames = CodeIntelligenceSourceDoor.CandidateQueryNames(
            expr, CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, filePath), line, col);
        var name = candidateNames.FirstOrDefault();
        var typeInfo = ResolveTypeInfoAtPosition(expr, candidateNames, semanticModel, snapshot, cu, out var resolvedName);
        if (typeInfo == null) return null;

        var resolvedType = NullabilityMetadataReflection.FormatTypeInfo(typeInfo);
        var kind = CodeIntelligenceDisplayText.TypeInfoToKind(typeInfo);
        var definition = resolvedName != null ? FindDefinitionLocation(snapshot, resolvedName) : null;
        var displayName = resolvedName ?? name ?? CodeIntelligenceDisplayText.GetTypeDisplayName(typeInfo, resolvedType);
        var nullability = GetNullabilityForExpression(semanticModel, expr, typeInfo);

        return new TypeResult(displayName, resolvedType, kind, definition, nullability);
    }

    /// <summary>
    /// Find the definition of the symbol at a position (semantic, position-based).
    /// </summary>
    public DefinitionResult? FindDefinition(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var declaration = ResolveDefinitionSymbolAtPosition(snapshot, file, line, col);
        return declaration != null ? CodeIntelligenceReferenceResults.ToDefinition(snapshot.ProjectRoot, declaration) : null;
    }

    /// <summary>
    /// Find all semantic references to the symbol at a position.
    /// Position-based ONLY — this is a semantic operation.
    /// </summary>
    public List<ReferenceResult> FindReferences(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null || snapshot.Bindings == null)
            return new List<ReferenceResult>();

        var declaration = ResolveStrictReferenceDeclaration(snapshot, filePath, line, col);
        return declaration != null
            ? CodeIntelligenceReferenceResults.FromDeclaration(snapshot.ProjectRoot, snapshot.SourceTexts, snapshot.Bindings, declaration)
            : new List<ReferenceResult>();
    }

    /// <summary>
    /// Find references only when the selected position has a strict BindingMap declaration/binding.
    /// </summary>
    public List<ReferenceResult> FindStrictReferences(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null || snapshot.Bindings == null)
            return new List<ReferenceResult>();

        var declaration = ResolveStrictReferenceDeclaration(snapshot, filePath, line, col);
        if (declaration == null)
            return new List<ReferenceResult>();

        return CodeIntelligenceReferenceResults.FromDeclaration(
            snapshot.ProjectRoot, snapshot.SourceTexts, snapshot.Bindings, declaration);
    }

    private SymbolDeclaration? ResolveStrictReferenceDeclaration(ProjectSnapshot snapshot, string filePath, int line, int col)
    {
        var declaration = TryResolveDefinitionViaBindings(snapshot, filePath, line, col);
        if (declaration != null)
            return declaration;

            return null;
    }

    // ── Hover Query ─────────────────────────────────────────────────────

    /// <summary>
    /// Get hover information for the symbol at a position.
    /// Combines type info + definition location + doc comment extraction.
    /// Returns null if there is no symbol at that position.
    /// </summary>
    public HoverResult? GetHoverInfo(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var type = GetTypeAtPosition(snapshot, file, line, col);
        var definition = FindDefinition(snapshot, file, line, col);

        if (type == null && definition == null)
            return null;

        var kind = definition?.Kind ?? type?.Kind ?? "unknown";
        var name = definition?.Name ?? type?.Name ?? "unknown";
        var definedIn = definition?.File;

        // Build a human-readable signature
        var signature = CodeIntelligenceSignatureKernels.GetFallbackSignatureText(kind, name, type?.ResolvedType);

        // Extract doc comment from the definition site. The path is resolved first because the
        // source text can only be fetched once the absolute path is known.
        string? documentation = null;
        var definitionLine = definition?.Line ?? 0;
        if (definedIn != null && definitionLine > 1)
        {
            var docPath = CodeIntelligenceSourceDoor.ResolveAbsolutePath(snapshot.CompilationUnits.Keys, definedIn);
            if (docPath != null)
            {
                documentation = CodeIntelligenceSourceDoor.DocComment(CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, docPath), definitionLine);
            }
        }

        return new HoverResult(signature, documentation, definedIn, kind);
    }

    // ── Call Graph ──────────────────────────────────────────────────────

    /// <summary>
    /// Build a call graph for the project by walking all ASTs.
    /// If functionName is provided, returns callers and callees for that function only.
    /// If functionName is null, returns all edges up to the limit.
    /// </summary>
    public CallGraphResult GetCallGraph(ProjectSnapshot snapshot, string? functionName, int limit = 100)
    {
        var units = new List<CompilationUnit>();
        var relativeFiles = new List<string>();

        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            units.Add(cu);
            relativeFiles.Add(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath));
        }

        return CodeIntelligenceCallGraph.Build(units, relativeFiles, functionName, limit);
    }

    // ── Implementors ────────────────────────────────────────────────────

    /// <summary>
    /// Find all concrete types (class, struct, record) that implement a given interface.
    /// Walks all compilation units in the project.
    /// </summary>
    /// <remarks>
    /// Mechanical driver: the walk and the answer belong to <see cref="CodeIntelligenceImplementors"/>.
    /// </remarks>
    public ImplementorsResult GetImplementors(ProjectSnapshot snapshot, string interfaceName)
    {
        var units = new List<CompilationUnit>();
        var relativeFiles = new List<string>();

        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            units.Add(cu);
            relativeFiles.Add(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath));
        }

        return CodeIntelligenceImplementors.Build(units, relativeFiles, interfaceName);
    }

    private TypeResult? ResolveTypeUseAtPosition(ProjectSnapshot snapshot, string filePath, CompilationUnit currentUnit,
        SemanticModel? semanticModel, int line, int col)
    {
        var declaration = TryResolveDefinitionViaBindings(snapshot, filePath, line, col);
        if (declaration == null || !AnalyzerBindingFacts.IsTypeDeclarationKind(declaration.Kind))
            return null;

        var span = CodeIntelligenceSourceDoor.IdentifierSpanAt(CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, filePath), line, col);
        var typeInfo = span != null
            ? semanticModel?.LookupTypeReferenceAtPosition(line, span.Value.Item1)
            : null;

        var resolvedType = typeInfo != null ? NullabilityMetadataReflection.FormatTypeInfo(typeInfo) : declaration.Name;
        return new TypeResult(
            declaration.Name,
            resolvedType,
            declaration.Kind,
            new LocationResult(
                CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, declaration.File ?? string.Empty),
                declaration.Line,
                declaration.Column),
            typeInfo != null ? NullStateFacts.GetSchemaText(CodeIntelligenceTypeResolution.DefaultNullState(typeInfo)) : null);
    }

    private TypeResult? ResolveDeclaredNameTypeAtPosition(ProjectSnapshot snapshot, string filePath, CompilationUnit currentUnit,
        int line, int col)
    {
        var selectedName = CodeIntelligenceSourceDoor.WordAt(CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, filePath), line, col);
        if (string.IsNullOrWhiteSpace(selectedName))
            return null;

        foreach (var declaration in currentUnit.Declarations)
        {
            var result = CodeIntelligenceTypeResolution.DeclaredNameTypeInDeclaration(
                snapshot.ProjectRoot,
                snapshot.CompilationUnits,
                filePath,
                declaration,
                selectedName!,
                line);
            if (result != null)
                return result;
        }

        return null;
    }

    private SymbolDeclaration? ResolveDefinitionSymbolAtPosition(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null) return null;

        var binding = TryResolveDefinitionViaBindings(snapshot, filePath, line, col);
        if (binding != null)
            return binding;

        return null;
    }

    private SymbolDeclaration? TryResolveDefinitionViaBindings(ProjectSnapshot snapshot, string filePath, int line, int col)
    {
        if (snapshot.Bindings == null)
            return null;

        var candidateColumns = GetBindingCandidateColumns(snapshot, filePath, line, col);
        if (BindingLookupKernels.TryResolveBindingDeclaration(
                snapshot.Bindings,
                filePath,
                line,
                candidateColumns,
                out var dogfoodDeclaration))
        {
            return dogfoodDeclaration;
        }

        return null;
    }

    private static int[] GetBindingCandidateColumns(ProjectSnapshot snapshot, string filePath, int line, int col)
    {
        var span = CodeIntelligenceSourceDoor.IdentifierSpanAt(CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, filePath), line, col);
        if (!BindingLookupKernels.TryGetBindingCandidateColumns(col, span, out var dogfoodCandidateColumns))
            throw new InvalidOperationException("N# binding candidate column kernel rejected the source.");

        return dogfoodCandidateColumns;
    }

    // ── Private Helpers ──────────────────────────────────────────────────

    private (string filePath, CompilationUnit? cu) FindCompilationUnit(ProjectSnapshot snapshot, string file)
    {
        // Try exact match first, respecting path segment boundaries
        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            if (CodeIntelligenceResultKernels.MatchesFilePath(filePath, file))
                return (filePath, cu);
        }

        // Try with project root prepended
        var fullPath = Path.GetFullPath(Path.Combine(snapshot.ProjectRoot, file));
        if (snapshot.CompilationUnits.TryGetValue(fullPath, out var found))
            return (fullPath, found);

        return (file, null);
    }

    private static Expression? FindExpressionAtPositionRobust(CompilationUnit cu, int line, int col)
    {
        foreach (var candidateColumn in CodeIntelligenceSourceDoor.NearbyColumns(col, 3))
        {
            // CLI positions are 1-based. AstNodeFinder historically expected 0-based coordinates,
            // so try both until all callers are aligned.
            var expression = AstNodeFinder.FindExpressionAtPosition(cu, line - 1, candidateColumn - 1)
                ?? AstNodeFinder.FindExpressionAtPosition(cu, line, candidateColumn);
            if (expression != null)
                return expression;
        }

        return null;
    }

    private TypeInfo? ResolveTypeInfoAtPosition(Expression? expr, IReadOnlyList<string> candidateNames,
        SemanticModel? semanticModel, ProjectSnapshot snapshot, CompilationUnit currentUnit, out string? resolvedName)
    {
        resolvedName = CodeIntelligenceDisplayText.GetExpressionQueryName(expr);
        var fromExpression = CodeIntelligenceTypeResolution.TypeInfoFromExpression(
            expr, semanticModel, snapshot.CompilationUnits, currentUnit);
        if (fromExpression != null)
            return fromExpression;

        foreach (var candidateName in candidateNames)
        {
            var typeInfo = CodeIntelligenceTypeResolution.TypeInfoByName(
                candidateName, semanticModel, snapshot.CompilationUnits, currentUnit);
            if (typeInfo != null)
            {
                resolvedName = candidateName;
                return typeInfo;
            }
        }

        return null;
    }

    private static string GetNullabilityForExpression(SemanticModel? semanticModel, Expression? expression, TypeInfo typeInfo)
    {
        if (expression != null
            && semanticModel != null
            && semanticModel.ExpressionNullStates.TryGetValue((expression.Line, expression.Column), out var state))
        {
            return NullStateFacts.GetSchemaText(state);
        }

        return NullStateFacts.GetSchemaText(CodeIntelligenceTypeResolution.DefaultNullState(typeInfo));
    }

    private LocationResult? FindDefinitionLocation(ProjectSnapshot snapshot, string name)
    {
        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            foreach (var decl in cu.Declarations)
            {
                var location = FindDefinitionLocationInDeclaration(snapshot, filePath, decl, name);
                if (location != null)
                    return location;
            }
        }
        return null;
    }

    private LocationResult? FindDefinitionLocationInDeclaration(ProjectSnapshot snapshot, string filePath, Declaration decl, string name)
    {
        if (DeclarationFacts.GetDeclarationName(decl) == name)
            return new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), decl.Line, decl.Column);

        foreach (var member in DeclarationFacts.GetDeclarationMembers(decl)?.Cast<Declaration>() ?? Enumerable.Empty<Declaration>())
        {
            var location = FindDefinitionLocationInDeclaration(snapshot, filePath, member, name);
            if (location != null)
                return location;
        }

        if (decl is EnumDeclaration enumDecl)
        {
            foreach (var member in enumDecl.Members)
            {
                if (member.Name == name)
                    return new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), enumDecl.Line, enumDecl.Column);
            }
        }

        if (decl is UnionDeclaration unionDecl)
        {
            foreach (var unionCase in unionDecl.Cases)
            {
                if (unionCase.Name == name)
                    return new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), unionDecl.Line, unionDecl.Column);
            }
        }

        return null;
    }


}

/// <summary>
/// Immutable snapshot of a fully analyzed project.
/// Created by CodeIntelligenceService.LoadProject().
/// </summary>
public class ProjectSnapshot
{
    public string ProjectRoot { get; }
    public IReadOnlyDictionary<string, CompilationUnit> CompilationUnits { get; }
    public IReadOnlyDictionary<string, SemanticModel> SemanticModels { get; }
    public IReadOnlyList<CompilerError> AllErrors { get; }
    public Analyzer SharedAnalyzer { get; }
    public IReadOnlyList<string> SourceFiles { get; }
    public IReadOnlyDictionary<string, string> SourceTexts { get; }
    public PerformanceFactStore? PerformanceFacts { get; }
    public SystemsReport SystemsReport { get; }

    /// <summary>
    /// The project-level semantic index: merged BindingMap plus type-declaration-to-file mapping.
    /// Null when the snapshot was constructed without a full analysis pass (e.g. in tests).
    /// </summary>
    public ProjectIndex? Index { get; }

    /// <summary>
    /// Convenience accessor for the merged BindingMap. Null when Index is null.
    /// </summary>
    public BindingMap? Bindings => Index?.Bindings;

    public ProjectSnapshot(
        string projectRoot,
        IReadOnlyDictionary<string, CompilationUnit> compilationUnits,
        IReadOnlyDictionary<string, SemanticModel> semanticModels,
        IReadOnlyList<CompilerError> allErrors,
        Analyzer sharedAnalyzer,
        IReadOnlyList<string> sourceFiles,
        ProjectIndex? index = null,
        IReadOnlyDictionary<string, string>? sourceTexts = null,
        PerformanceFactStore? performanceFacts = null,
        SystemsReport? systemsReport = null)
    {
        ProjectRoot = projectRoot;
        CompilationUnits = compilationUnits;
        SemanticModels = semanticModels;
        AllErrors = allErrors;
        SharedAnalyzer = sharedAnalyzer;
        SourceFiles = sourceFiles;
        Index = index;
        SourceTexts = sourceTexts ?? new Dictionary<string, string>();
        PerformanceFacts = performanceFacts;
        SystemsReport = systemsReport ?? SystemsReport.Empty(null);
    }
}
