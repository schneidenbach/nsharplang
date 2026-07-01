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

            var relativeFile = GetRelativePath(snapshot.ProjectRoot, filePath);
            ExtractDeclarationSymbols(cu.Declarations, relativeFile, results);
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
        var outline = cu.Declarations
            .Select(d => DeclarationToOutlineEntry(d))
            .Where(e => e != null)
            .Cast<OutlineEntry>()
            .ToArray();

        return new OutlineResult(GetRelativePath(snapshot.ProjectRoot, filePath), imports, outline);
    }

    /// <summary>
    /// Get the structural outline of a single file using the fast path (no project analysis).
    /// </summary>
    public OutlineResult GetOutlineSingleFile(string filePath)
    {
        var source = File.ReadAllText(filePath);
        var lexer = new Lexer(source, filePath);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, filePath, source);
        var parseResult = parser.ParseCompilationUnit();

        if (parseResult.CompilationUnit == null)
        {
            return new OutlineResult(filePath, Array.Empty<string>(), Array.Empty<OutlineEntry>());
        }

        var cu = parseResult.CompilationUnit;
        var imports = cu.Imports.Select(i => i.Namespace).ToArray();
        var outline = cu.Declarations
            .Select(d => DeclarationToOutlineEntry(d))
            .Where(e => e != null)
            .Cast<OutlineEntry>()
            .ToArray();

        return new OutlineResult(filePath, imports, outline);
    }

    // ── Diagnostic Queries ──────────────────────────────────────────────

    /// <summary>
    /// Get all diagnostics for the project, optionally filtered by file.
    /// Returns Elm-level rich diagnostics with explanations, suggestions, source snippets, etc.
    /// </summary>
    public List<DiagnosticResult> GetDiagnostics(ProjectSnapshot snapshot, string? file = null)
    {
        var sourceTexts = snapshot.SourceTexts.ToDictionary(kvp => kvp.Key, kvp => kvp.Value, StringComparer.OrdinalIgnoreCase);

        var results = new List<DiagnosticResult>();
        var filesWithCompilerShadowingErrors = GetCompilerShadowingErrorFiles(snapshot);

        foreach (var error in snapshot.AllErrors)
        {
            var errorFile = error.FileName ?? "unknown";
            if (file != null && !CodeIntelligenceResultKernels.MatchesFilePath(errorFile, file))
                continue;

            var relativeFile = GetRelativePath(snapshot.ProjectRoot, errorFile);

            // Try to extract source snippet if not already provided
            var snippet = error.SourceSnippet;
            if (string.IsNullOrWhiteSpace(snippet) && error.Line > 0)
            {
                snippet = ExtractSourceLine(snapshot, errorFile, error.Line);
            }

            results.Add(new DiagnosticResult(
                Code: error.DiagnosticId,
                Severity: error.Severity switch
                {
                    ErrorSeverity.Error => "error",
                    ErrorSeverity.Warning => "warning",
                    _ => "info"
                },
                Message: error.Message,
                File: relativeFile,
                Line: error.Line,
                Column: error.Column,
                Length: error.Length,
                SourceSnippet: snippet,
                Explanation: error.HumanExplanation,
                Suggestion: error.Suggestion ?? FormatSuggestions(error.Suggestions),
                Hint: error.ContextualHint,
                ExpectedType: error.ExpectedType,
                ActualType: error.ActualType,
                DocsUrl: error.DocsUrl
            ));
        }

        var lintDiagnostics = GetLintDiagnostics(snapshot.ProjectRoot, snapshot.SourceFiles, snapshot.CompilationUnits, sourceTexts, file);
        if (filesWithCompilerShadowingErrors.Count > 0)
        {
            lintDiagnostics = SuppressLintShadowingDiagnostics(lintDiagnostics, filesWithCompilerShadowingErrors);
        }

        results.AddRange(lintDiagnostics);

        return DeduplicateDiagnostics(results);
    }

    private static List<string> GetCompilerShadowingErrorFiles(ProjectSnapshot snapshot)
    {
        var files = new List<string>();
        foreach (var error in snapshot.AllErrors)
        {
            if (error.Code == ErrorCode.ShadowedDeclaration && !string.IsNullOrWhiteSpace(error.FileName))
            {
                files.Add(GetRelativePath(snapshot.ProjectRoot, error.FileName!));
            }
        }

        return files;
    }

    private static List<DiagnosticResult> SuppressLintShadowingDiagnostics(
        List<DiagnosticResult> lintDiagnostics,
        IReadOnlyList<string> filesWithCompilerShadowingErrors)
    {
        return CodeIntelligenceResultKernels.SuppressLintShadowingDiagnosticResults(
            lintDiagnostics,
            filesWithCompilerShadowingErrors);
    }

    public static DiagnosticResult ToDiagnosticResult(
        CompilerError error,
        string projectRoot,
        IReadOnlyDictionary<string, string>? sourceTexts = null)
    {
        var errorFile = error.FileName ?? "unknown";
        var relativeFile = GetRelativePath(projectRoot, errorFile);
        var snippet = error.SourceSnippet;
        if (string.IsNullOrWhiteSpace(snippet) && error.Line > 0 && sourceTexts != null)
        {
            snippet = ExtractSourceLine(sourceTexts, errorFile, error.Line);
        }

        return new DiagnosticResult(
            Code: error.DiagnosticId,
            Severity: error.Severity switch
            {
                ErrorSeverity.Error => "error",
                ErrorSeverity.Warning => "warning",
                _ => "info"
            },
            Message: error.Message,
            File: relativeFile,
            Line: error.Line,
            Column: error.Column,
            Length: error.Length,
            SourceSnippet: snippet,
            Explanation: error.HumanExplanation,
            Suggestion: error.Suggestion ?? FormatSuggestions(error.Suggestions),
            Hint: error.ContextualHint,
            ExpectedType: error.ExpectedType,
            ActualType: error.ActualType,
            DocsUrl: error.DocsUrl ?? DiagnosticCatalog.DocsUrlFor(error.DiagnosticId));
    }

    public static DiagnosticResult ToDiagnosticResult(Diagnostic diagnostic, string projectRoot, string sourceFile, string? source)
    {
        return new DiagnosticResult(
            diagnostic.Code,
            diagnostic.Severity switch
            {
                DiagnosticSeverity.Error => "error",
                DiagnosticSeverity.Warning => "warning",
                _ => "info"
            },
            diagnostic.Message,
            GetRelativePath(projectRoot, sourceFile),
            diagnostic.Location.Line,
            diagnostic.Location.Column,
            Math.Max(diagnostic.Length, 1),
            source != null ? ExtractSourceLine(source, diagnostic.Location.Line) : null,
            null,
            diagnostic.Suggestion,
            null,
            null,
            null,
            DiagnosticCatalog.DocsUrlFor(diagnostic.Code));
    }

    public static string? ExtractSourceLineForDiagnostics(string source, int line) =>
        ExtractSourceLine(source, line);

    private static List<DiagnosticResult> GetLintDiagnostics(
        string projectRoot,
        IReadOnlyList<string> sourceFiles,
        IReadOnlyDictionary<string, CompilationUnit> compilationUnits,
        IReadOnlyDictionary<string, string> sourceTexts,
        string? file = null)
    {
        var results = new List<DiagnosticResult>();

        foreach (var sourceFile in sourceFiles)
        {
            var fullPath = Path.GetFullPath(sourceFile);
            if (file != null && !CodeIntelligenceResultKernels.MatchesFilePath(fullPath, file))
                continue;

            if (!sourceTexts.TryGetValue(fullPath, out var source))
            {
                    source = File.ReadAllText(fullPath);
            }

            var fileDir = Path.GetDirectoryName(fullPath) ?? projectRoot;
            var linter = new Linter(LinterConfig.FromEditorConfig(fileDir));
            if (!compilationUnits.TryGetValue(fullPath, out var compilationUnit))
            {
                continue;
            }

            var diagnostics = linter.Lint(compilationUnit, fullPath, source);

            results.AddRange(diagnostics.Select(diagnostic => ToDiagnosticResult(diagnostic, projectRoot, fullPath, source)));
        }

        return results;
    }

    private static List<DiagnosticResult> DeduplicateDiagnostics(List<DiagnosticResult> diagnostics)
    {
        return CodeIntelligenceResultKernels.DeduplicateDiagnosticsPreservingOrderResults(diagnostics);
    }

    // ── Navigation Queries ──────────────────────────────────────────────

    /// <summary>
    /// Get type information for the expression/symbol at a position.
    /// Uses AstNodeFinder + SemanticModel for semantic resolution.
    /// </summary>
    public TypeResult? GetTypeAtPosition(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null) return null;

        snapshot.SemanticModels.TryGetValue(filePath, out var semanticModel);

        var typeUse = ResolveTypeUseAtPosition(snapshot, filePath, cu, semanticModel, line, col);
        if (typeUse != null)
            return typeUse;

        var expr = FindExpressionAtPositionRobust(cu, line, col);
        var candidateNames = GetCandidateQueryNames(expr, snapshot, filePath, line, col);
        var name = candidateNames.FirstOrDefault();
        var typeInfo = ResolveTypeInfoAtPosition(expr, candidateNames, semanticModel, snapshot, cu, out var resolvedName);
        if (typeInfo == null) return null;

        var resolvedType = NullabilityMetadata.FormatTypeInfo(typeInfo);
        var kind = TypeInfoToKind(typeInfo);
        var definition = resolvedName != null ? FindDefinitionLocation(snapshot, resolvedName) : null;
        var displayName = resolvedName ?? name ?? GetTypeDisplayName(typeInfo, resolvedType);
        var nullability = GetNullabilityForExpression(semanticModel, expr, typeInfo);

        return new TypeResult(displayName, resolvedType, kind, definition, nullability);
    }

    /// <summary>
    /// Find the definition of the symbol at a position (semantic, position-based).
    /// </summary>
    public DefinitionResult? FindDefinition(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var declaration = ResolveDefinitionSymbolAtPosition(snapshot, file, line, col);
        return declaration != null ? ToDefinitionResult(snapshot, declaration) : null;
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
            ? BuildReferenceResultsFromDeclaration(snapshot, declaration)
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

        return BuildReferenceResultsFromDeclaration(snapshot, declaration);
    }

    private SymbolDeclaration? ResolveStrictReferenceDeclaration(ProjectSnapshot snapshot, string filePath, int line, int col)
    {
        var declaration = TryResolveDefinitionViaBindings(snapshot, filePath, line, col);
        if (declaration != null)
            return declaration;

            return null;
    }

    private List<ReferenceResult> BuildReferenceResultsFromDeclaration(ProjectSnapshot snapshot, SymbolDeclaration declaration)
    {
        var results = new List<ReferenceResult>
        {
            new(
                GetRelativePath(snapshot.ProjectRoot, declaration.File ?? string.Empty),
                declaration.Line,
                declaration.Column,
                declaration.Name.Length,
                GetSourceContext(snapshot, declaration.File, declaration.Line),
                IsDefinition: true)
        };

        if (snapshot.Bindings != null)
        {
            foreach (var usage in snapshot.Bindings.GetReferences(declaration))
            {
                var isDefinition = usage.File == declaration.File
                    && usage.Line == declaration.Line
                    && usage.Column == declaration.Column;
                var overlapsDefinitionName = usage.File == declaration.File
                    && usage.Line == declaration.Line
                    && usage.Column >= declaration.Column
                    && usage.Column < declaration.Column + declaration.Name.Length;

                if (isDefinition || overlapsDefinitionName)
                {
                    continue;
                }

                results.Add(new ReferenceResult(
                    GetRelativePath(snapshot.ProjectRoot, usage.File ?? string.Empty),
                    usage.Line,
                    usage.Column,
                    usage.Length,
                    GetSourceContext(snapshot, usage.File, usage.Line),
                    IsDefinition: false));
            }
        }

        return DeduplicateAndSortReferenceResults(results);
    }

    private static List<ReferenceResult> DeduplicateAndSortReferenceResults(IReadOnlyList<ReferenceResult> results)
    {
        return CodeIntelligenceResultKernels.DeduplicateReferenceResults(results);
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

        // Extract doc comment from the definition site
        var documentation = definedIn != null
            ? ExtractDocComment(snapshot, definedIn, definition?.Line ?? 0)
            : null;

        return new HoverResult(signature, documentation, definedIn, kind);
    }

    private string? ExtractDocComment(ProjectSnapshot snapshot, string relativeFile, int definitionLine)
    {
        if (definitionLine <= 1) return null;

        // Find the absolute path
        string? absolutePath = null;
        foreach (var (filePath, _) in snapshot.CompilationUnits)
        {
            if (CodeIntelligenceResultKernels.MatchesFilePath(filePath, relativeFile))
            {
                absolutePath = filePath;
                break;
            }
        }

        if (absolutePath == null) return null;

        var source = GetSourceText(snapshot, absolutePath);
        if (source == null)
            return null;

        if (!CodeIntelligenceSourceTextKernels.TryExtractDocComment(
                snapshot,
                absolutePath,
                source,
                definitionLine,
                out var dogfoodDocumentation))
            throw new InvalidOperationException("N# doc comment kernel rejected the source.");

        return dogfoodDocumentation;
    }

    // ── Call Graph ──────────────────────────────────────────────────────

    /// <summary>
    /// Build a call graph for the project by walking all ASTs.
    /// If functionName is provided, returns callers and callees for that function only.
    /// If functionName is null, returns all edges up to the limit.
    /// </summary>
    public CallGraphResult GetCallGraph(ProjectSnapshot snapshot, string? functionName, int limit = 100)
    {
        // Build the complete per-function call map by walking all compilation units
        var callSites = new Dictionary<string, List<(string Callee, string? File, int Line, int Col)>>(StringComparer.Ordinal);

        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            var relFile = GetRelativePath(snapshot.ProjectRoot, filePath);
            CollectCallSites(cu, relFile, callSites);
        }

        if (functionName == null)
        {
            // Return all callers + callees up to the limit
            var allCallees = new List<CallSiteResult>();
            var allCallers = new List<CallSiteResult>();
            var truncated = false;

            foreach (var (caller, calleeList) in callSites)
            {
                foreach (var (callee, file, line, col) in calleeList)
                {
                    if (allCallees.Count >= limit)
                    {
                        truncated = true;
                        break;
                    }
                    allCallees.Add(new CallSiteResult(callee, file, line, col));
                }
                if (truncated) break;
            }

            return new CallGraphResult(null, allCallers, allCallees, truncated);
        }

        // Function-specific: find direct callees
        var callees = new List<CallSiteResult>();
        if (callSites.TryGetValue(functionName, out var directCallees))
        {
            foreach (var (callee, file, line, col) in directCallees)
            {
                callees.Add(new CallSiteResult(callee, file, line, col));
            }
        }

        // Find callers (functions that call functionName)
        var callerResults = new List<CallSiteResult>();
        foreach (var (caller, calleeList) in callSites)
        {
            foreach (var (callee, file, line, col) in calleeList)
            {
                if (string.Equals(callee, functionName, StringComparison.Ordinal))
                {
                    callerResults.Add(new CallSiteResult(caller, file, line, col));
                }
            }
        }

        var totalCount = callees.Count + callerResults.Count;
        var isTruncated = totalCount > limit;

        if (isTruncated)
        {
            callees = callees.Take(limit / 2).ToList();
            callerResults = callerResults.Take(limit / 2).ToList();
        }

        return new CallGraphResult(functionName, callerResults, callees, isTruncated);
    }

    /// <summary>
    /// Walk all declarations in a compilation unit, recording caller->callee edges.
    /// </summary>
    private static void CollectCallSites(
        CompilationUnit cu,
        string relativeFile,
        Dictionary<string, List<(string Callee, string? File, int Line, int Col)>> callSites)
    {
        foreach (var decl in cu.Declarations)
        {
            CollectCallSitesInDeclaration(decl, null, relativeFile, callSites);
        }
    }

    private static void CollectCallSitesInDeclaration(
        Declaration decl,
        string? ownerContext,
        string relativeFile,
        Dictionary<string, List<(string Callee, string? File, int Line, int Col)>> callSites)
    {
        switch (decl)
        {
            case FunctionDeclaration func:
            {
                var callerName = ownerContext != null ? $"{ownerContext}.{func.Name}" : func.Name;
                if (!callSites.ContainsKey(callerName))
                    callSites[callerName] = new List<(string, string?, int, int)>();

                if (func.Body != null)
                    CollectCallSitesInStatement(func.Body, callerName, relativeFile, callSites);
                if (func.ExpressionBody != null)
                    CollectCallSitesInExpression(func.ExpressionBody, callerName, relativeFile, callSites);
                break;
            }
            case ClassDeclaration cls:
                foreach (var member in cls.Members)
                    CollectCallSitesInDeclaration(member, cls.Name, relativeFile, callSites);
                break;
            case StructDeclaration str:
                foreach (var member in str.Members)
                    CollectCallSitesInDeclaration(member, str.Name, relativeFile, callSites);
                break;
            case RecordDeclaration rec:
                foreach (var member in rec.Members)
                    CollectCallSitesInDeclaration(member, rec.Name, relativeFile, callSites);
                break;
            case InterfaceDeclaration iface:
                foreach (var member in iface.Members)
                    CollectCallSitesInDeclaration(member, iface.Name, relativeFile, callSites);
                break;
        }
    }

    private static void CollectCallSitesInStatement(
        Statement stmt,
        string callerName,
        string relativeFile,
        Dictionary<string, List<(string Callee, string? File, int Line, int Col)>> callSites)
    {
        switch (stmt)
        {
            case BlockStatement block:
                foreach (var s in block.Statements)
                    CollectCallSitesInStatement(s, callerName, relativeFile, callSites);
                break;
            case ExpressionStatement exprStmt:
                CollectCallSitesInExpression(exprStmt.Expression, callerName, relativeFile, callSites);
                break;
            case ReturnStatement ret when ret.Value != null:
                CollectCallSitesInExpression(ret.Value, callerName, relativeFile, callSites);
                break;
            case VariableDeclarationStatement varDecl when varDecl.Initializer != null:
                CollectCallSitesInExpression(varDecl.Initializer, callerName, relativeFile, callSites);
                break;
            case IfStatement ifStmt:
                CollectCallSitesInExpression(ifStmt.Condition, callerName, relativeFile, callSites);
                CollectCallSitesInStatement(ifStmt.ThenStatement, callerName, relativeFile, callSites);
                if (ifStmt.ElseStatement != null)
                    CollectCallSitesInStatement(ifStmt.ElseStatement, callerName, relativeFile, callSites);
                break;
            case WhileStatement whileStmt:
                CollectCallSitesInExpression(whileStmt.Condition, callerName, relativeFile, callSites);
                CollectCallSitesInStatement(whileStmt.Body, callerName, relativeFile, callSites);
                break;
            case ForeachStatement forEachStmt:
                CollectCallSitesInExpression(forEachStmt.Collection, callerName, relativeFile, callSites);
                CollectCallSitesInStatement(forEachStmt.Body, callerName, relativeFile, callSites);
                break;
        }
    }

    private static void CollectCallSitesInExpression(
        Expression expr,
        string callerName,
        string relativeFile,
        Dictionary<string, List<(string Callee, string? File, int Line, int Col)>> callSites)
    {
        switch (expr)
        {
            case CallExpression call:
                var calleeName = ExtractCalleeName(call.Callee);
                if (calleeName != null)
                {
                    callSites[callerName].Add((calleeName, relativeFile, call.Line, call.Column));
                }
                // Recurse into arguments
                foreach (var arg in call.Arguments)
                    CollectCallSitesInExpression(arg.Value, callerName, relativeFile, callSites);
                // Recurse into callee (for chained calls)
                CollectCallSitesInExpression(call.Callee, callerName, relativeFile, callSites);
                break;
            case MemberAccessExpression member:
                CollectCallSitesInExpression(member.Object, callerName, relativeFile, callSites);
                break;
            case AssignmentExpression assign:
                CollectCallSitesInExpression(assign.Value, callerName, relativeFile, callSites);
                break;
            case BinaryExpression bin:
                CollectCallSitesInExpression(bin.Left, callerName, relativeFile, callSites);
                CollectCallSitesInExpression(bin.Right, callerName, relativeFile, callSites);
                break;
            case InterpolatedStringExpression interp:
                foreach (var part in interp.Parts)
                    if (part is InterpolatedStringHole hole)
                        CollectCallSitesInExpression(hole.Expression, callerName, relativeFile, callSites);
                break;
        }
    }

    private static string? ExtractCalleeName(Expression callee) => callee switch
    {
        IdentifierExpression id => id.Name,
        MemberAccessExpression ma => ma.MemberName,
        _ => null
    };

    // ── Implementors ────────────────────────────────────────────────────

    /// <summary>
    /// Find all concrete types (class, struct, record) that implement a given interface.
    /// Walks all compilation units in the project.
    /// </summary>
    public ImplementorsResult GetImplementors(ProjectSnapshot snapshot, string interfaceName)
    {
        var results = new List<ImplementorResult>();

        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            var relFile = GetRelativePath(snapshot.ProjectRoot, filePath);
            CollectImplementors(cu, interfaceName, relFile, results);
        }

        return new ImplementorsResult(interfaceName, results);
    }

    private static void CollectImplementors(
        CompilationUnit cu,
        string interfaceName,
        string relativeFile,
        List<ImplementorResult> results)
    {
        foreach (var decl in cu.Declarations)
        {
            switch (decl)
            {
                case ClassDeclaration cls:
                    // BaseClass holds the first colon-separated type (may be an interface when there is no actual base class)
                    // Interfaces holds additional comma-separated types
                    if ((cls.BaseClass != null && InterfaceNameMatches(cls.BaseClass, interfaceName))
                        || cls.Interfaces.Any(i => InterfaceNameMatches(i, interfaceName)))
                    {
                        results.Add(new ImplementorResult(cls.Name, "class", relativeFile, cls.Line, cls.Column));
                    }
                    break;
                case StructDeclaration str:
                    if (str.Interfaces.Any(i => InterfaceNameMatches(i, interfaceName)))
                    {
                        results.Add(new ImplementorResult(str.Name, "struct", relativeFile, str.Line, str.Column));
                    }
                    break;
                case RecordDeclaration rec:
                    if (rec.Interfaces.Any(i => InterfaceNameMatches(i, interfaceName)))
                    {
                        results.Add(new ImplementorResult(rec.Name, "record", relativeFile, rec.Line, rec.Column));
                    }
                    break;
            }
        }
    }

    private static bool InterfaceNameMatches(TypeReference typeRef, string interfaceName)
    {
        return typeRef switch
        {
            SimpleTypeReference s => string.Equals(s.Name, interfaceName, StringComparison.Ordinal),
            GenericTypeReference g => string.Equals(g.Name, interfaceName, StringComparison.Ordinal),
            _ => false
        };
    }

    private string? GetSourceContext(ProjectSnapshot snapshot, string? filePath, int line)
    {
        if (filePath == null || line <= 0) return null;

        var source = GetSourceText(snapshot, filePath);
        if (source == null) return null;

        if (CodeIntelligenceSourceTextKernels.TryExtractSourceContext(
                snapshot,
                filePath,
                source,
                line,
                out var dogfoodContext))
        {
            return dogfoodContext;
        }

        return null;
    }

    private DefinitionResult ToDefinitionResult(ProjectSnapshot snapshot, SymbolDeclaration declaration)
        => new(
            declaration.Name,
            declaration.Kind,
            GetRelativePath(snapshot.ProjectRoot, declaration.File ?? string.Empty),
            declaration.Line,
            declaration.Column,
            declaration.Name.Length);

    private TypeResult? ResolveTypeUseAtPosition(ProjectSnapshot snapshot, string filePath, CompilationUnit currentUnit,
        SemanticModel? semanticModel, int line, int col)
    {
        var declaration = TryResolveDefinitionViaBindings(snapshot, filePath, line, col);
        if (declaration == null || !IsTypeDeclarationKind(declaration.Kind))
            return null;

        var span = ExtractIdentifierSpanAtPosition(snapshot, filePath, line, col);
        var typeInfo = span != null
            ? semanticModel?.LookupTypeReferenceAtPosition(line, span.Value.StartColumn)
            : null;

        var resolvedType = typeInfo != null ? NullabilityMetadata.FormatTypeInfo(typeInfo) : declaration.Name;
        return new TypeResult(
            declaration.Name,
            resolvedType,
            declaration.Kind,
            new LocationResult(
                GetRelativePath(snapshot.ProjectRoot, declaration.File ?? string.Empty),
                declaration.Line,
                declaration.Column),
            typeInfo != null ? NullStateFacts.GetSchemaText(GetDefaultNullState(typeInfo)) : null);
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
        var span = ExtractIdentifierSpanAtPosition(snapshot, filePath, line, col);
        if (!BindingLookupKernels.TryGetBindingCandidateColumns(col, span, out var dogfoodCandidateColumns))
            throw new InvalidOperationException("N# binding candidate column kernel rejected the source.");

        return dogfoodCandidateColumns;
    }

    // ── Private Helpers ──────────────────────────────────────────────────

    private void ExtractDeclarationSymbols(List<Declaration> declarations, string file, List<SymbolResult> results)
    {
        foreach (var decl in declarations)
        {
            if (!IsPublicSurfaceDeclaration(decl))
            {
                continue;
            }

            var symbol = DeclarationToSymbol(decl, file);
            if (symbol != null)
            {
                results.Add(symbol);
            }
        }
    }

    private SymbolResult? DeclarationToSymbol(Declaration decl, string file)
    {
        return decl switch
        {
            FunctionDeclaration f => new SymbolResult(
                f.Name, SymbolKind.Function, file, f.Line, f.Column,
                TypeName: FormatTypeReference(f.ReturnType),
                Modifiers: FormatModifiers(f.Modifiers),
                Members: null,
                Parameters: f.Parameters.Select(p => new ParameterResult(
                    p.Name,
                    FormatTypeReference(p.Type),
                    p.DefaultValue != null,
                    p.DefaultValue?.ToString()
                )).ToArray()),

            ClassDeclaration c => new SymbolResult(
                c.Name, SymbolKind.Class, file, c.Line, c.Column,
                TypeName: null,
                Modifiers: FormatModifiers(c.Modifiers),
                Members: c.Members.Where(IsPublicSurfaceDeclaration).Select(m => DeclarationToSymbol(m, file)).Where(s => s != null).Cast<SymbolResult>().ToArray(),
                Parameters: null),

            StructDeclaration s => new SymbolResult(
                s.Name, SymbolKind.Struct, file, s.Line, s.Column,
                TypeName: null,
                Modifiers: FormatModifiers(s.Modifiers),
                Members: s.Members.Where(IsPublicSurfaceDeclaration).Select(m => DeclarationToSymbol(m, file)).Where(s2 => s2 != null).Cast<SymbolResult>().ToArray(),
                Parameters: null),

            RecordDeclaration r => new SymbolResult(
                r.Name, SymbolKind.Record, file, r.Line, r.Column,
                TypeName: null,
                Modifiers: FormatModifiers(r.Modifiers),
                Members: r.Members.Where(IsPublicSurfaceDeclaration).Select(m => DeclarationToSymbol(m, file)).Where(s => s != null).Cast<SymbolResult>().ToArray(),
                Parameters: null),

            SoaRecordDeclaration soa => new SymbolResult(
                soa.Name, SymbolKind.Record, file, soa.Line, soa.Column,
                TypeName: "soa",
                Modifiers: FormatModifiers(soa.Modifiers),
                Members: soa.Columns.Select(c => new SymbolResult(
                    c.Name,
                    SymbolKind.Field,
                    file,
                    c.Line,
                    c.Column,
                    FormatTypeReference(c.Type),
                    null,
                    null,
                    null)).ToArray(),
                Parameters: null),

            InterfaceDeclaration i => new SymbolResult(
                i.Name, SymbolKind.Interface, file, i.Line, i.Column,
                TypeName: null,
                Modifiers: FormatModifiers(i.Modifiers),
                Members: i.Members.Where(IsPublicSurfaceDeclaration).Select(m => DeclarationToSymbol(m, file)).Where(s => s != null).Cast<SymbolResult>().ToArray(),
                Parameters: null),

            EnumDeclaration e => new SymbolResult(
                e.Name, SymbolKind.Enum, file, e.Line, e.Column,
                TypeName: null,
                Modifiers: FormatModifiers(e.Modifiers),
                Members: e.Members.Select(m => new SymbolResult(
                    m.Name, SymbolKind.EnumMember, file, 0, 0, null, null, null, null)).ToArray(),
                Parameters: null),

            UnionDeclaration u => new SymbolResult(
                u.Name, SymbolKind.Union, file, u.Line, u.Column,
                TypeName: null,
                Modifiers: FormatModifiers(u.Modifiers),
                Members: u.Cases.Where(c => IsPublicSurfaceName(c.Name, Modifiers.None)).Select(c => new SymbolResult(
                    c.Name, SymbolKind.EnumMember, file, 0, 0, null, null, null, null)).ToArray(),
                Parameters: null),

            FieldDeclaration fd => new SymbolResult(
                fd.Name,
                fd.Modifiers.HasFlag(Ast.Modifiers.Static) ? SymbolKind.Field : SymbolKind.Property,
                file, fd.Line, fd.Column,
                TypeName: FormatTypeReference(fd.Type),
                Modifiers: FormatModifiers(fd.Modifiers),
                Members: null,
                Parameters: null),

            PropertyDeclaration pd => new SymbolResult(
                pd.Name, SymbolKind.Property, file, pd.Line, pd.Column,
                TypeName: FormatTypeReference(pd.Type),
                Modifiers: FormatModifiers(pd.Modifiers),
                Members: null,
                Parameters: null),

            ConstructorDeclaration cd => new SymbolResult(
                "constructor", SymbolKind.Constructor, file, cd.Line, cd.Column,
                TypeName: null,
                Modifiers: FormatModifiers(cd.Modifiers),
                Members: null,
                Parameters: cd.Parameters.Select(p => new ParameterResult(
                    p.Name, FormatTypeReference(p.Type), p.DefaultValue != null, null)).ToArray()),

            TypeAliasDeclaration ta => new SymbolResult(
                ta.Name, SymbolKind.TypeAlias, file, ta.Line, ta.Column,
                TypeName: FormatTypeReference(ta.Type),
                Modifiers: null,
                Members: null,
                Parameters: null),

            NewtypeDeclaration nt => new SymbolResult(
                nt.Name, SymbolKind.Struct, file, nt.Line, nt.Column,
                TypeName: FormatTypeReference(nt.UnderlyingType),
                Modifiers: null,
                Members: null,
                Parameters: null),

            TestDeclaration td => new SymbolResult(
                td.Description, SymbolKind.Test, file, td.Line, td.Column,
                TypeName: null,
                Modifiers: null,
                Members: null,
                Parameters: null),

            _ => null
        };
    }

    private OutlineEntry? DeclarationToOutlineEntry(Declaration decl)
    {
        return decl switch
        {
            FunctionDeclaration f => new OutlineEntry(
                f.Name, SymbolKind.Function, f.Line, EstimateEndLine(f),
                ReturnType: FormatTypeReference(f.ReturnType),
                TypeName: null,
                Children: null),

            ClassDeclaration c => new OutlineEntry(
                c.Name, SymbolKind.Class, c.Line, EstimateEndLine(c),
                ReturnType: null,
                TypeName: null,
                Children: c.Members.Select(m => DeclarationToOutlineEntry(m)).Where(e => e != null).Cast<OutlineEntry>().ToArray()),

            StructDeclaration s => new OutlineEntry(
                s.Name, SymbolKind.Struct, s.Line, EstimateEndLine(s),
                ReturnType: null,
                TypeName: null,
                Children: s.Members.Select(m => DeclarationToOutlineEntry(m)).Where(e => e != null).Cast<OutlineEntry>().ToArray()),

            RecordDeclaration r => new OutlineEntry(
                r.Name, SymbolKind.Record, r.Line, EstimateEndLine(r),
                ReturnType: null,
                TypeName: null,
                Children: r.Members.Select(m => DeclarationToOutlineEntry(m)).Where(e => e != null).Cast<OutlineEntry>().ToArray()),

            SoaRecordDeclaration soa => new OutlineEntry(
                soa.Name, SymbolKind.Record, soa.Line, EstimateEndLine(soa),
                ReturnType: null,
                TypeName: "soa",
                Children: soa.Columns.Select(c => new OutlineEntry(
                    c.Name,
                    SymbolKind.Field,
                    c.Line,
                    c.Line,
                    ReturnType: null,
                    TypeName: FormatTypeReference(c.Type),
                    Children: null)).ToArray()),

            InterfaceDeclaration i => new OutlineEntry(
                i.Name, SymbolKind.Interface, i.Line, EstimateEndLine(i),
                ReturnType: null,
                TypeName: null,
                Children: i.Members.Select(m => DeclarationToOutlineEntry(m)).Where(e => e != null).Cast<OutlineEntry>().ToArray()),

            EnumDeclaration e => new OutlineEntry(
                e.Name, SymbolKind.Enum, e.Line, e.Line,
                ReturnType: null,
                TypeName: null,
                Children: null),

            UnionDeclaration u => new OutlineEntry(
                u.Name, SymbolKind.Union, u.Line, u.Line,
                ReturnType: null,
                TypeName: null,
                Children: null),

            FieldDeclaration fd => new OutlineEntry(
                fd.Name, SymbolKind.Property, fd.Line, fd.Line,
                ReturnType: null,
                TypeName: FormatTypeReference(fd.Type),
                Children: null),

            PropertyDeclaration pd => new OutlineEntry(
                pd.Name, SymbolKind.Property, pd.Line, pd.Line,
                ReturnType: null,
                TypeName: FormatTypeReference(pd.Type),
                Children: null),

            TestDeclaration td => new OutlineEntry(
                td.Description, SymbolKind.Test, td.Line, td.Line,
                ReturnType: null,
                TypeName: null,
                Children: null),

            _ => null
        };
    }

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

    private static string? GetDeclarationName(Declaration decl) => decl switch
    {
        FunctionDeclaration f => f.Name,
        ClassDeclaration c => c.Name,
        StructDeclaration s => s.Name,
        RecordDeclaration r => r.Name,
        SoaRecordDeclaration soa => soa.Name,
        InterfaceDeclaration i => i.Name,
        EnumDeclaration e => e.Name,
        UnionDeclaration u => u.Name,
        FieldDeclaration fd => fd.Name,
        PropertyDeclaration pd => pd.Name,
        TypeAliasDeclaration ta => ta.Name,
        NewtypeDeclaration nt => nt.Name,
        TestDeclaration td => td.Description,
        SetupDeclaration => "setup",
        _ => null
    };

    private static Ast.Modifiers GetDeclarationModifiers(Declaration decl) => decl switch
    {
        FunctionDeclaration f => f.Modifiers,
        ClassDeclaration c => c.Modifiers,
        StructDeclaration s => s.Modifiers,
        RecordDeclaration r => r.Modifiers,
        SoaRecordDeclaration soa => soa.Modifiers,
        InterfaceDeclaration i => i.Modifiers,
        EnumDeclaration e => e.Modifiers,
        UnionDeclaration u => u.Modifiers,
        FieldDeclaration fd => fd.Modifiers,
        PropertyDeclaration pd => pd.Modifiers,
        ConstructorDeclaration cd => cd.Modifiers,
        _ => Ast.Modifiers.None
    };

    private static bool IsPublicSurfaceDeclaration(Declaration decl)
    {
        var name = GetDeclarationName(decl);
        if (name == null)
        {
            return false;
        }

        return IsPublicSurfaceName(name, GetDeclarationModifiers(decl));
    }

    private static bool IsPublicSurfaceName(string name, Ast.Modifiers modifiers)
    {
        return VisibilityConventions.IsExportedIdentifier(name, modifiers);
    }

    private static bool IsTypeDeclarationKind(string kind)
        => kind is "class" or "struct" or "record" or "soaRecord" or "interface" or "enum" or "union" or "typeAlias" or "newtype";

    private static List<Declaration>? GetDeclarationMembers(Declaration decl) => decl switch
    {
        ClassDeclaration c => c.Members,
        StructDeclaration s => s.Members,
        RecordDeclaration r => r.Members,
        InterfaceDeclaration i => i.Members,
        _ => null
    };

    private static int EstimateEndLine(Declaration decl)
    {
        // Estimate end line based on member/body positions
        var members = GetDeclarationMembers(decl);
        if (members is { Count: > 0 })
        {
            return members.Max(m => m.Line) + 1;
        }

        if (decl is FunctionDeclaration f && f.Body?.Statements.Count > 0)
        {
            return f.Body.Statements.Max(s => s.Line) + 1;
        }

        if (decl is SoaRecordDeclaration soa && soa.Columns.Count > 0)
        {
            return soa.Columns.Max(c => c.Line) + 1;
        }

        return decl.Line;
    }

    private static Expression? FindExpressionAtPositionRobust(CompilationUnit cu, int line, int col)
    {
        foreach (var candidateColumn in GetNearbyColumns(col, maxDistance: 3))
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
        resolvedName = GetExpressionQueryName(expr);
        var fromExpression = ResolveTypeInfoFromExpression(expr, semanticModel, snapshot, currentUnit);
        if (fromExpression != null)
            return fromExpression;

        foreach (var candidateName in candidateNames)
        {
            var typeInfo = ResolveTypeInfoByName(candidateName, semanticModel, snapshot, currentUnit);
            if (typeInfo != null)
            {
                resolvedName = candidateName;
                return typeInfo;
            }
        }

        return null;
    }

    private static List<string> GetCandidateQueryNames(Expression? expr, ProjectSnapshot snapshot, string filePath,
        int line, int col)
    {
        var names = new List<string>();

        AddCandidateName(names, GetExpressionQueryName(expr));
        AddCandidateName(names, ExtractWordAtPosition(snapshot, filePath, line, col));
        AddCandidateName(names, ExtractWordAtPosition(snapshot, filePath, line, Math.Max(0, col - 1)));
        AddCandidateName(names, ExtractWordAtPosition(snapshot, filePath, line, col + 1));
        AddCandidateName(names, ExtractVariableDeclarationNameAtPosition(snapshot, filePath, line));

        return names;
    }

    private static void AddCandidateName(List<string> names, string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
            return;

        if (!names.Contains(name, StringComparer.Ordinal))
            names.Add(name);
    }

    private TypeInfo? ResolveTypeInfoFromExpression(Expression? expr, SemanticModel? semanticModel,
        ProjectSnapshot snapshot, CompilationUnit currentUnit)
    {
        if (expr != null && semanticModel != null)
        {
            var resolved = semanticModel.LookupTypeAtPosition(expr.Line, expr.Column);
            if (resolved != null && !BuiltInTypes.IsUnknown(resolved))
                return resolved;
        }

        return expr switch
        {
            IdentifierExpression id => ResolveTypeInfoByName(id.Name, semanticModel, snapshot, currentUnit),
            MemberAccessExpression ma => ResolveMemberTypeInfo(ma, semanticModel, snapshot, currentUnit)
                ?? ResolveTypeInfoByName(ma.MemberName, semanticModel, snapshot, currentUnit),
            CallExpression call => ResolveTypeInfoFromExpression(call.Callee, semanticModel, snapshot, currentUnit),
            NewExpression newExpr when newExpr.Type != null => ResolveTypeReferenceToTypeInfo(newExpr.Type, snapshot),
            WithExpression withExpr => ResolveTypeInfoFromExpression(withExpr.Target, semanticModel, snapshot, currentUnit),
            AwaitExpression awaitExpr => ResolveTypeInfoFromExpression(awaitExpr.Expression, semanticModel, snapshot, currentUnit),
            CastExpression castExpr => ResolveTypeReferenceToTypeInfo(castExpr.TargetType, snapshot),
            ParenthesizedExpression paren => ResolveTypeInfoFromExpression(paren.Inner, semanticModel, snapshot, currentUnit),
            IntLiteralExpression => new SimpleTypeInfo("int"),
            FloatLiteralExpression => new SimpleTypeInfo("double"),
            CharLiteralExpression => new SimpleTypeInfo("char"),
            StringLiteralExpression => new SimpleTypeInfo("string"),
            InterpolatedStringExpression => new SimpleTypeInfo("string"),
            BoolLiteralExpression => new SimpleTypeInfo("bool"),
            NullLiteralExpression => new SimpleTypeInfo("object"),
            _ => null
        };
    }

    private TypeInfo? ResolveMemberTypeInfo(MemberAccessExpression memberAccess, SemanticModel? semanticModel,
        ProjectSnapshot snapshot, CompilationUnit currentUnit)
    {
        var receiverType = ResolveTypeInfoFromExpression(memberAccess.Object, semanticModel, snapshot, currentUnit);
        if (receiverType == null && memberAccess.Object is IdentifierExpression receiverId)
            receiverType = ResolveTypeInfoByName(receiverId.Name, semanticModel, snapshot, currentUnit);

        if (receiverType == null)
            return null;

        return FindMemberTypeInfo(snapshot, receiverType, memberAccess.MemberName);
    }

    private TypeInfo? FindMemberTypeInfo(ProjectSnapshot snapshot, TypeInfo receiverType, string memberName)
    {
        if (receiverType is ClassTypeInfo classType)
        {
            return FindMemberTypeInfo(snapshot, classType.DeclaredMembers, memberName)
                ?? (classType.BaseClass != null
                    ? FindMemberTypeInfo(snapshot, ResolveTypeReferenceToTypeInfo(classType.BaseClass, snapshot), memberName)
                    : null);
        }

        return receiverType switch
        {
            StructTypeInfo structType => FindMemberTypeInfo(snapshot, structType.DeclaredMembers, memberName),
            RecordTypeInfo recordType => FindMemberTypeInfo(snapshot, recordType.DeclaredMembers, memberName),
            InterfaceTypeInfo interfaceType => FindMemberTypeInfo(snapshot, interfaceType.DeclaredMembers, memberName),
            EnumTypeInfo => receiverType,
            AnonymousUnionTypeInfo => receiverType,
            UnionTypeInfo => receiverType,
            AliasTypeInfo aliasType => FindMemberTypeInfo(snapshot, ResolveTypeReferenceToTypeInfo(aliasType.AliasedType, snapshot), memberName),
            NullableTypeInfo nullableType => FindMemberTypeInfo(snapshot, nullableType.InnerType, memberName),
            ObliviousTypeInfo obliviousType => FindMemberTypeInfo(snapshot, obliviousType.InnerType, memberName),
            _ => null
        };
    }

    private TypeInfo? FindMemberTypeInfo(ProjectSnapshot snapshot, IReadOnlyList<DeclaredMemberInfo> members, string memberName)
    {
        foreach (var member in members)
        {
            if (member.Name != memberName)
                continue;

            return member.Kind switch
            {
                DeclaredMemberKind.Field when member.Type != null => ResolveTypeReferenceToTypeInfo(member.Type, snapshot),
                DeclaredMemberKind.Property when member.Type != null => ResolveTypeReferenceToTypeInfo(member.Type, snapshot),
                DeclaredMemberKind.Function => member.ReturnType != null
                    ? ResolveTypeReferenceToTypeInfo(member.ReturnType, snapshot)
                    : new SimpleTypeInfo("void"),
                _ => null
            };
        }

        return null;
    }

    private TypeInfo? ResolveTypeInfoByName(string name, SemanticModel? semanticModel,
        ProjectSnapshot snapshot, CompilationUnit currentUnit)
    {
        var typeInfo = semanticModel?.LookupIdentifier(name);
        if (typeInfo != null)
            return typeInfo;

        return FindTypeInfoByName(snapshot, currentUnit, name);
    }

    private TypeInfo? FindTypeInfoByName(ProjectSnapshot snapshot, CompilationUnit currentUnit, string name)
    {
        var currentNamespace = currentUnit.Namespace?.Name;
        var importedNamespaces = currentUnit.Imports.Select(i => i.Namespace).ToHashSet(StringComparer.Ordinal);

        foreach (var (_, cu) in snapshot.CompilationUnits)
        {
            var namespaceName = cu.Namespace?.Name;
            if (!string.Equals(namespaceName, currentNamespace, StringComparison.Ordinal) &&
                (namespaceName == null || !importedNamespaces.Contains(namespaceName)))
            {
                continue;
            }

            foreach (var decl in cu.Declarations)
            {
                var typeInfo = FindTypeInfoInDeclaration(decl, name, snapshot);
                if (typeInfo != null)
                    return typeInfo;
            }
        }

        return null;
    }

    private TypeInfo? FindTypeInfoInDeclaration(Declaration decl, string name, ProjectSnapshot snapshot)
    {
        var directMatch = TryGetTypeInfoFromDeclaration(decl, name, snapshot);
        if (directMatch != null)
            return directMatch;

        foreach (var member in GetDeclarationMembers(decl) ?? Enumerable.Empty<Declaration>())
        {
            var memberMatch = FindTypeInfoInDeclaration(member, name, snapshot);
            if (memberMatch != null)
                return memberMatch;
        }

        if (decl is EnumDeclaration enumDecl && enumDecl.Members.Any(m => m.Name == name))
            return EnumTypeInfoFactory.FromDeclaration(enumDecl);

        if (decl is UnionDeclaration unionDecl && unionDecl.Cases.Any(c => c.Name == name))
            return UnionTypeInfoFactory.FromDeclaration(unionDecl);

        return null;
    }

    private TypeInfo? TryGetTypeInfoFromDeclaration(Declaration decl, string name, ProjectSnapshot snapshot)
    {
        return decl switch
        {
            FunctionDeclaration f when f.Name == name => f.ReturnType != null
                ? ResolveTypeReferenceToTypeInfo(f.ReturnType, snapshot)
                : new SimpleTypeInfo("void"),
            ClassDeclaration c when c.Name == name => NominalTypeInfoFactory.FromClassDeclaration(c),
            StructDeclaration s when s.Name == name => NominalTypeInfoFactory.FromStructDeclaration(s),
            RecordDeclaration r when r.Name == name => NominalTypeInfoFactory.FromRecordDeclaration(r),
            SoaRecordDeclaration soa when soa.Name == name => SoaTypeInfoFactory.FromDeclaration(soa),
            InterfaceDeclaration i when i.Name == name => NominalTypeInfoFactory.FromInterfaceDeclaration(i),
            EnumDeclaration e when e.Name == name => EnumTypeInfoFactory.FromDeclaration(e),
            UnionDeclaration u when u.Name == name => UnionTypeInfoFactory.FromDeclaration(u),
            FieldDeclaration fd when fd.Name == name && fd.Type != null => ResolveTypeReferenceToTypeInfo(fd.Type, snapshot),
            PropertyDeclaration pd when pd.Name == name => ResolveTypeReferenceToTypeInfo(pd.Type, snapshot),
            TypeAliasDeclaration ta when ta.Name == name => ResolveTypeReferenceToTypeInfo(ta.Type, snapshot),
            NewtypeDeclaration nt when nt.Name == name => new NewtypeInfo(nt.Name, nt.UnderlyingType),
            _ => null
        };
    }

    private TypeInfo ResolveTypeReferenceToTypeInfo(TypeReference typeRef, ProjectSnapshot snapshot)
    {
        return typeRef switch
        {
            SimpleTypeReference s => FindNamedTypeInfo(snapshot, s.Name) ?? new SimpleTypeInfo(s.Name),
            GenericTypeReference g => new GenericTypeInfo(g.Name,
                g.TypeArguments.Select(t => ResolveTypeReferenceToTypeInfo(t, snapshot)).ToList()),
            ArrayTypeReference a => new ArrayTypeInfo(ResolveTypeReferenceToTypeInfo(a.ElementType, snapshot)),
            NullableTypeReference n => new NullableTypeInfo(ResolveTypeReferenceToTypeInfo(n.InnerType, snapshot)),
            UnionTypeReference u => new AnonymousUnionTypeInfo(FlattenUnionTypeReference(u).Select(t => ResolveTypeReferenceToTypeInfo(t, snapshot)).ToList()),
            _ => new SimpleTypeInfo(typeRef.ToString() ?? "unknown")
        };
    }

    private static IEnumerable<TypeReference> FlattenUnionTypeReference(TypeReference typeRef)
    {
        if (typeRef is UnionTypeReference union)
        {
            foreach (var arm in union.Arms)
            {
                foreach (var nested in FlattenUnionTypeReference(arm))
                    yield return nested;
            }
        }
        else
        {
            yield return typeRef;
        }
    }

    private TypeInfo? FindNamedTypeInfo(ProjectSnapshot snapshot, string name)
    {
        foreach (var (_, cu) in snapshot.CompilationUnits)
        {
            foreach (var decl in cu.Declarations)
            {
                var typeInfo = decl switch
                {
                    ClassDeclaration c when c.Name == name => NominalTypeInfoFactory.FromClassDeclaration(c),
                    StructDeclaration s when s.Name == name => NominalTypeInfoFactory.FromStructDeclaration(s),
                    RecordDeclaration r when r.Name == name => NominalTypeInfoFactory.FromRecordDeclaration(r),
                    SoaRecordDeclaration soa when soa.Name == name => SoaTypeInfoFactory.FromDeclaration(soa),
                    InterfaceDeclaration i when i.Name == name => NominalTypeInfoFactory.FromInterfaceDeclaration(i),
                    EnumDeclaration e when e.Name == name => EnumTypeInfoFactory.FromDeclaration(e),
                    UnionDeclaration u when u.Name == name => UnionTypeInfoFactory.FromDeclaration(u),
                    TypeAliasDeclaration ta when ta.Name == name => ResolveTypeReferenceToTypeInfo(ta.Type, snapshot),
                    NewtypeDeclaration nt when nt.Name == name => new NewtypeInfo(nt.Name, nt.UnderlyingType),
                    _ => null
                };

                if (typeInfo != null)
                    return typeInfo;
            }
        }

        return null;
    }

    private static string? GetExpressionQueryName(Expression? expr)
    {
        return expr switch
        {
            IdentifierExpression id => id.Name,
            MemberAccessExpression ma => ma.MemberName,
            CallExpression call => GetExpressionQueryName(call.Callee),
            NewExpression newExpr when newExpr.Type != null => GetTypeReferenceName(newExpr.Type),
            WithExpression withExpr => GetExpressionQueryName(withExpr.Target),
            AwaitExpression awaitExpr => GetExpressionQueryName(awaitExpr.Expression),
            CastExpression castExpr => GetTypeReferenceName(castExpr.TargetType),
            ParenthesizedExpression paren => GetExpressionQueryName(paren.Inner),
            _ => null
        };
    }

    private static string? GetTypeReferenceName(TypeReference? typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference s => s.Name,
            GenericTypeReference g => g.Name,
            NullableTypeReference n => GetTypeReferenceName(n.InnerType),
            ArrayTypeReference a => GetTypeReferenceName(a.ElementType),
            UnionTypeReference u => string.Join(" | ", u.Arms.Select(FormatTypeReference)),
            _ => null
        };
    }

    private static string GetTypeDisplayName(TypeInfo typeInfo, string fallback)
    {
        return typeInfo switch
        {
            ClassTypeInfo c => c.Name,
            StructTypeInfo s => s.Name,
            RecordTypeInfo r => r.Name,
            SoaRecordTypeInfo soa => soa.Declaration.Name,
            InterfaceTypeInfo i => i.Name,
            EnumTypeInfo e => e.Declaration.Name,
            AnonymousUnionTypeInfo u => string.Join(" | ", u.Arms.Select(NullabilityMetadata.FormatTypeInfo)),
            UnionTypeInfo u => u.Declaration.Name,
            ReflectionTypeInfo r => r.Type.Name,
            _ => fallback
        };
    }

    /// <summary>
    /// Public accessor for type reference formatting (used by CompletionEngine).
    /// </summary>
    public static string FormatTypeReferencePublic(TypeReference? typeRef)
        => TypeReferenceFacts.GetDisplayNameOrVoid(typeRef);

    private static string FormatTypeReference(TypeReference? typeRef)
        => TypeReferenceFacts.GetDisplayNameOrVoid(typeRef);

    private static string GetNullabilityForExpression(SemanticModel? semanticModel, Expression? expression, TypeInfo typeInfo)
    {
        if (expression != null
            && semanticModel != null
            && semanticModel.ExpressionNullStates.TryGetValue((expression.Line, expression.Column), out var state))
        {
            return NullStateFacts.GetSchemaText(state);
        }

        return NullStateFacts.GetSchemaText(GetDefaultNullState(typeInfo));
    }

    private static NullState GetDefaultNullState(TypeInfo typeInfo)
    {
        return typeInfo switch
        {
            NullableTypeInfo => NullState.MaybeNull,
            UnknownTypeInfo => NullState.Unknown,
            ReflectionTypeInfo reflectionType => reflectionType.Type.IsValueType && Nullable.GetUnderlyingType(reflectionType.Type) == null
                ? NullState.NotNull
                : NullState.Oblivious,
            SimpleTypeInfo { Name: "null" } => NullState.Null,
            _ => NullState.NotNull
        };
    }

    private static string TypeInfoToKind(TypeInfo typeInfo) => typeInfo switch
    {
        ClassTypeInfo => "class",
        StructTypeInfo => "struct",
        RecordTypeInfo => "record",
        SoaRecordTypeInfo => "soaRecord",
        InterfaceTypeInfo => "interface",
        EnumTypeInfo => "enum",
        AnonymousUnionTypeInfo => "union",
        UnionTypeInfo => "union",
        FunctionTypeInfo => "function",
        GenericTypeInfo => "generic",
        ArrayTypeInfo => "array",
        NullableTypeInfo => "nullable",
        ObliviousTypeInfo => "oblivious",
        ReflectionTypeInfo r => r.Type.IsEnum ? "enum" : (r.Type.IsValueType ? "struct" : "class"),
        ReflectionMethodInfo => "method",
        ReflectionMethodGroupInfo => "method",
        SimpleTypeInfo => "primitive",
        _ => "unknown"
    };

    private static string[]? FormatModifiers(Ast.Modifiers modifiers)
    {
        if (modifiers == Ast.Modifiers.None) return null;

        var result = new List<string>();
        if (modifiers.HasFlag(Ast.Modifiers.Public)) result.Add("pub");
        if (modifiers.HasFlag(Ast.Modifiers.Private)) result.Add("priv");
        if (modifiers.HasFlag(Ast.Modifiers.Internal)) result.Add("internal");
        if (modifiers.HasFlag(Ast.Modifiers.Protected)) result.Add("protected");
        if (modifiers.HasFlag(Ast.Modifiers.Static)) result.Add("static");
        if (modifiers.HasFlag(Ast.Modifiers.Virtual)) result.Add("virtual");
        if (modifiers.HasFlag(Ast.Modifiers.Abstract)) result.Add("abstract");
        if (modifiers.HasFlag(Ast.Modifiers.Sealed)) result.Add("sealed");
        if (modifiers.HasFlag(Ast.Modifiers.Async)) result.Add("async");
        if (modifiers.HasFlag(Ast.Modifiers.Override)) result.Add("override");
        if (modifiers.HasFlag(Ast.Modifiers.Readonly)) result.Add("readonly");

        return result.Count > 0 ? result.ToArray() : null;
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
        if (GetDeclarationName(decl) == name)
            return new LocationResult(GetRelativePath(snapshot.ProjectRoot, filePath), decl.Line, decl.Column);

        foreach (var member in GetDeclarationMembers(decl) ?? Enumerable.Empty<Declaration>())
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
                    return new LocationResult(GetRelativePath(snapshot.ProjectRoot, filePath), enumDecl.Line, enumDecl.Column);
            }
        }

        if (decl is UnionDeclaration unionDecl)
        {
            foreach (var unionCase in unionDecl.Cases)
            {
                if (unionCase.Name == name)
                    return new LocationResult(GetRelativePath(snapshot.ProjectRoot, filePath), unionDecl.Line, unionDecl.Column);
            }
        }

        return null;
    }

    private static string? GetSourceText(ProjectSnapshot snapshot, string filePath)
    {
        var fullPath = Path.GetFullPath(filePath);
        if (snapshot.SourceTexts.TryGetValue(fullPath, out var text))
            return text;

            return File.ReadAllText(fullPath);
    }

    private static string? ExtractWordAtPosition(ProjectSnapshot snapshot, string filePath, int line, int col)
    {
            var source = GetSourceText(snapshot, filePath);
            if (source == null)
                return null;

            if (CodeIntelligenceSourceTextKernels.TryExtractIdentifierName(
                    snapshot,
                    filePath,
                    source,
                    line,
                    col,
                    out var dogfoodName))
            {
                return dogfoodName;
            }

            return null;
    }

    private static (int StartColumn, int EndColumn)? ExtractIdentifierSpanAtPosition(ProjectSnapshot snapshot, string filePath, int line, int col)
    {
            var source = GetSourceText(snapshot, filePath);
            if (source == null)
                return null;

            if (CodeIntelligenceSourceTextKernels.TryExtractIdentifierSpan(
                    snapshot,
                    filePath,
                    source,
                    line,
                    col,
                    out var dogfoodSpan))
            {
                return dogfoodSpan;
            }

            return null;
    }

    private static IEnumerable<int> GetNearbyColumns(int col, int maxDistance)
    {
        if (col > 0)
            yield return col;

        for (int distance = 1; distance <= maxDistance; distance++)
        {
            if (col - distance > 0)
                yield return col - distance;

            yield return col + distance;
        }
    }

    private static string? ExtractVariableDeclarationNameAtPosition(ProjectSnapshot snapshot, string filePath, int line)
    {
            var source = GetSourceText(snapshot, filePath);
            if (source == null)
                return null;

            if (CodeIntelligenceSourceTextKernels.TryExtractVariableDeclarationName(
                    snapshot,
                    filePath,
                    source,
                    line,
                    out var dogfoodName))
            {
                return dogfoodName;
            }

            return null;
    }

    private static string? ExtractSourceLine(IReadOnlyDictionary<string, string> sourceTexts, string filePath, int line)
    {
        if (!sourceTexts.TryGetValue(filePath, out var source)) return null;
        return ExtractSourceLine(source, line);
    }

    private static string? ExtractSourceLine(ProjectSnapshot snapshot, string filePath, int line)
    {
        var source = GetSourceText(snapshot, filePath);
        if (source == null)
            return null;

        if (!CodeIntelligenceSourceTextKernels.TryExtractSourceLine(
                snapshot,
                filePath,
                source,
                line,
                out var dogfoodLine))
            throw new InvalidOperationException("N# source line kernel rejected the source.");

        return dogfoodLine;
    }

    private static string? ExtractSourceLine(string source, int line)
    {
        if (!CodeIntelligenceSourceTextKernels.TryExtractSourceLine(source, line, out var dogfoodLine))
            throw new InvalidOperationException("N# source line kernel rejected the source.");

        return dogfoodLine;
    }

    private static string? FormatSuggestions(List<string>? suggestions)
    {
        if (suggestions == null || suggestions.Count == 0) return null;
        return string.Join("; ", suggestions);
    }

    private static string GetRelativePath(string projectRoot, string filePath)
    {
        try
        {
            return Path.GetRelativePath(projectRoot, filePath);
        }
        catch
        {
            return filePath;
        }
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
