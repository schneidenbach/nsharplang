using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Core code intelligence service. Operates on project-on-disk snapshots — NOT editor state.
/// Both the CLI (nlc query) and eventually the LSP can consume this.
///
/// This is built BELOW the Language Server's DocumentManager. It knows nothing about
/// open documents, editor buffers, or LSP protocols. It reads files from disk,
/// parses and analyzes them, and answers semantic queries.
/// </summary>
public class CodeIntelligenceService
{
    /// <summary>
    /// Load and fully analyze a project from disk.
    /// Returns an immutable snapshot that can be queried.
    /// </summary>
    public ProjectSnapshot LoadProject(string projectRoot)
    {
        var config = ProjectFileParser.ParseFromDirectory(projectRoot);
        var compiler = new MultiFileCompiler(projectRoot, config);
        compiler.CompileForAnalysis();

        return new ProjectSnapshot(
            projectRoot,
            compiler.CompilationUnits,
            compiler.SemanticModels,
            compiler.AllErrors,
            compiler.SharedAnalyzer,
            compiler.SourceFiles,
            compiler.ProjectBindings
        );
    }

    /// <summary>
    /// Analyze a single file (fast path for outline, single-file diagnostics).
    /// Does not require project context.
    /// </summary>
    public SingleFileSnapshot AnalyzeFile(string filePath)
    {
        var source = File.ReadAllText(filePath);
        var lexer = new Lexer(source, filePath);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, filePath, source);
        var parseResult = parser.ParseCompilationUnit();

        var errors = new List<CompilerError>(parseResult.Errors);
        SemanticModel? semanticModel = null;

        if (parseResult.CompilationUnit != null && !errors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            var analyzer = new Analyzer();
            analyzer.LoadSystemAssemblies();
            var analysisResult = analyzer.Analyze(parseResult.CompilationUnit, filePath, Path.GetDirectoryName(filePath), source);
            semanticModel = analysisResult.SemanticModel;
            errors.AddRange(analysisResult.Errors);
        }

        return new SingleFileSnapshot(filePath, source, parseResult.CompilationUnit, semanticModel, errors);
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
            if (file != null && !MatchesFilePath(filePath, file))
                continue;

            var relativeFile = GetRelativePath(snapshot.ProjectRoot, filePath);
            ExtractDeclarationSymbols(cu.Declarations, relativeFile, results);
        }

        if (kind != null)
        {
            results = results.Where(s => s.Kind == kind.Value).ToList();
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
        var sourceText = File.ReadAllText(filePath);
        var outline = BuildOutline(cu, sourceText);

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
        var outline = BuildOutline(cu, source);

        return new OutlineResult(filePath, imports, outline);
    }

    // ── Diagnostic Queries ──────────────────────────────────────────────

    /// <summary>
    /// Get all diagnostics for the project, optionally filtered by file.
    /// Returns Elm-level rich diagnostics with explanations, suggestions, source snippets, etc.
    /// </summary>
    public List<DiagnosticResult> GetDiagnostics(ProjectSnapshot snapshot, string? file = null)
    {
        var sourceTexts = new Dictionary<string, string>();
        foreach (var filePath in snapshot.SourceFiles)
        {
            try { sourceTexts[filePath] = File.ReadAllText(filePath); }
            catch { /* file may have been deleted since analysis */ }
        }

        var results = new List<DiagnosticResult>();

        foreach (var error in snapshot.AllErrors)
        {
            var errorFile = error.FileName ?? "unknown";
            if (file != null && !MatchesFilePath(errorFile, file))
                continue;

            var relativeFile = GetRelativePath(snapshot.ProjectRoot, errorFile);

            // Try to extract source snippet if not already provided
            var snippet = error.SourceSnippet;
            if (string.IsNullOrWhiteSpace(snippet) && error.Line > 0)
            {
                snippet = ExtractSourceLine(sourceTexts, errorFile, error.Line);
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

        return results;
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

        var expr = FindExpressionAtPositionRobust(cu, line, col);
        var candidateNames = GetCandidateQueryNames(expr, snapshot, filePath, line, col);
        var name = candidateNames.FirstOrDefault();
        var typeInfo = ResolveTypeInfoAtPosition(expr, candidateNames, semanticModel, snapshot, cu, out var resolvedName);
        if (typeInfo == null) return null;

        var resolvedType = FormatTypeInfo(typeInfo);
        var kind = TypeInfoToKind(typeInfo);
        var definition = resolvedName != null ? FindDefinitionLocation(snapshot, resolvedName) : null;
        var displayName = resolvedName ?? name ?? GetTypeDisplayName(typeInfo, resolvedType);

        return new TypeResult(displayName, resolvedType, kind, definition);
    }

    /// <summary>
    /// Find the definition of the symbol at a position (semantic, position-based).
    /// </summary>
    public DefinitionResult? FindDefinition(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null) return null;
        return ResolveDefinitionAtPosition(snapshot, filePath, cu, line, col);
    }

    /// <summary>
    /// Find definitions by name (search sugar — explicitly returns a list).
    /// </summary>
    public List<DefinitionResult> FindDefinitionByName(ProjectSnapshot snapshot, string name)
    {
        var results = new List<DefinitionResult>();

        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            var relativeFile = GetRelativePath(snapshot.ProjectRoot, filePath);
            FindAllDeclarationsInUnit(cu, name, relativeFile, results);
        }

        return results;
    }

    /// <summary>
    /// Find all semantic references to the symbol at a position.
    /// Position-based ONLY — this is a semantic operation.
    ///
    /// Uses the BindingMap when available (semantic resolution).
    /// Falls back to text-based search when BindingMap has no data for the position.
    /// </summary>
    public List<ReferenceResult> FindReferences(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null) return new List<ReferenceResult>();

        var resolvedDefinition = ResolveDefinitionAtPosition(snapshot, filePath, cu, line, col);
        List<ReferenceResult>? semanticResults = null;

        // Try semantic path via BindingMap first
        if (snapshot.Bindings != null)
        {
            semanticResults = FindReferencesViaBindingMap(snapshot, filePath, line, col);
            // Only use semantic results if we found actual usages (not just the declaration itself).
            // If the BindingMap only returns the declaration, fall through to text-based search
            // which can find cross-file references that the import resolution path didn't record.
            if (semanticResults != null && semanticResults.Count > 1)
                return semanticResults;
        }

        // Fallback to text-based search only when we resolved a concrete symbol.
        // Returning an empty set is better than returning unrelated results.
        if (resolvedDefinition == null)
            return semanticResults ?? new List<ReferenceResult>();

        var textResults = FindReferencesViaTextSearch(snapshot, resolvedDefinition.Name);
        return MergeReferenceResults(semanticResults, textResults);
    }

    /// <summary>
    /// Semantic FindReferences via BindingMap — resolves the declaration at position,
    /// then returns all recorded usages of that declaration.
    /// </summary>
    private List<ReferenceResult>? FindReferencesViaBindingMap(ProjectSnapshot snapshot, string filePath, int line, int col)
    {
        var bindings = snapshot.Bindings!;
        var (declaration, usages) = bindings.FindAllReferences(filePath, line, col);

        if (declaration == null)
        {
            // Try to find by name as a fallback (position might not match exactly)
            var name = ExtractWordAtPosition(snapshot, filePath, line, col);
            if (name == null) return null;

            var declarations = bindings.FindDeclarationsByName(name);
            if (declarations.Count == 0) return null;

            // Use the first matching declaration
            declaration = declarations[0];
            usages = bindings.GetReferences(declaration);
        }

        if (usages.Count == 0 && declaration != null)
        {
            // Return just the declaration itself
            var relFile = GetRelativePath(snapshot.ProjectRoot, declaration.File ?? "");
            var context = GetSourceContext(declaration.File, declaration.Line);
            return new List<ReferenceResult>
            {
                new(relFile, declaration.Line, declaration.Column, declaration.Name.Length, context, IsDefinition: true)
            };
        }

        // Build source text cache for context extraction
        var sourceCache = new Dictionary<string, string[]>();

        var results = new List<ReferenceResult>();

        // Add the declaration itself
        if (declaration != null)
        {
            var relFile = GetRelativePath(snapshot.ProjectRoot, declaration.File ?? "");
            var context = GetSourceContext(declaration.File, declaration.Line);
            results.Add(new ReferenceResult(relFile, declaration.Line, declaration.Column,
                declaration.Name.Length, context, IsDefinition: true));
        }

        // Add all usages
        foreach (var usage in usages)
        {
            var relFile = GetRelativePath(snapshot.ProjectRoot, usage.File ?? "");
            var context = GetSourceContext(usage.File, usage.Line);

            // Don't add if it's the same location as the declaration
            var isDefinition = declaration != null &&
                usage.File == declaration.File &&
                usage.Line == declaration.Line &&
                usage.Column == declaration.Column;

            var overlapsDefinitionName = declaration != null &&
                usage.File == declaration.File &&
                usage.Line == declaration.Line &&
                usage.Column >= declaration.Column &&
                usage.Column < declaration.Column + declaration.Name.Length;

            if (!isDefinition && !overlapsDefinitionName)
            {
                results.Add(new ReferenceResult(relFile, usage.Line, usage.Column,
                    usage.Length, context, IsDefinition: false));
            }
        }

        // Deduplicate and sort
        results = results
            .GroupBy(r => (r.File, r.Line, r.Column))
            .Select(g => g.First())
            .OrderBy(r => r.File)
            .ThenBy(r => r.Line)
            .ThenBy(r => r.Column)
            .ToList();

        return results;
    }

    /// <summary>
    /// Fallback text-based FindReferences (used when BindingMap doesn't cover the position).
    /// </summary>
    private List<ReferenceResult> FindReferencesViaTextSearch(ProjectSnapshot snapshot, string name)
    {
        var results = new List<ReferenceResult>();

        foreach (var (refFile, refCu) in snapshot.CompilationUnits)
        {
            var relativeFile = GetRelativePath(snapshot.ProjectRoot, refFile);
            string? sourceText = null;
            try { sourceText = File.ReadAllText(refFile); }
            catch { continue; }

            var lines = sourceText.Split('\n');

            // Check declarations
            foreach (var decl in refCu.Declarations)
            {
                var declName = GetDeclarationName(decl);
                if (declName == name)
                {
                    var context = decl.Line > 0 && decl.Line <= lines.Length ? lines[decl.Line - 1].Trim() : null;
                    results.Add(new ReferenceResult(relativeFile, decl.Line, decl.Column, name.Length, context, IsDefinition: true));
                }

                if (decl is ClassDeclaration cls)
                    FindReferencesInMembers(cls.Members, name, relativeFile, lines, results);
                else if (decl is StructDeclaration str)
                    FindReferencesInMembers(str.Members, name, relativeFile, lines, results);
                else if (decl is RecordDeclaration rec)
                    FindReferencesInMembers(rec.Members, name, relativeFile, lines, results);
                else if (decl is InterfaceDeclaration iface)
                    FindReferencesInMembers(iface.Members, name, relativeFile, lines, results);
            }

            FindIdentifierUsagesInSource(sourceText, name, relativeFile, lines, results);
        }

        var definitionSpans = results
            .Where(r => r.IsDefinition)
            .Select(r => (r.File, r.Line, r.Column, r.Length))
            .ToList();

        results = results
            .Where(r => r.IsDefinition || !definitionSpans.Any(d =>
                d.File == r.File &&
                d.Line == r.Line &&
                r.Column >= d.Column &&
                r.Column < d.Column + d.Length))
            .ToList();

        results = results
            .GroupBy(r => (r.File, r.Line, r.Column))
            .Select(g => g.First())
            .OrderBy(r => r.File)
            .ThenBy(r => r.Line)
            .ThenBy(r => r.Column)
            .ToList();

        return results;
    }

    private string? GetSourceContext(string? filePath, int line)
    {
        if (filePath == null || line <= 0) return null;
        try
        {
            var source = File.ReadAllText(filePath);
            var lines = source.Split('\n');
            if (line <= lines.Length)
                return lines[line - 1].Trim();
        }
        catch { }
        return null;
    }

    // ── Private Helpers ──────────────────────────────────────────────────

    private void ExtractDeclarationSymbols(List<Declaration> declarations, string file, List<SymbolResult> results)
    {
        foreach (var decl in declarations)
        {
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
                Members: c.Members.Select(m => DeclarationToSymbol(m, file)).Where(s => s != null).Cast<SymbolResult>().ToArray(),
                Parameters: null),

            StructDeclaration s => new SymbolResult(
                s.Name, SymbolKind.Struct, file, s.Line, s.Column,
                TypeName: null,
                Modifiers: FormatModifiers(s.Modifiers),
                Members: s.Members.Select(m => DeclarationToSymbol(m, file)).Where(s2 => s2 != null).Cast<SymbolResult>().ToArray(),
                Parameters: null),

            RecordDeclaration r => new SymbolResult(
                r.Name, SymbolKind.Record, file, r.Line, r.Column,
                TypeName: null,
                Modifiers: FormatModifiers(r.Modifiers),
                Members: r.Members.Select(m => DeclarationToSymbol(m, file)).Where(s => s != null).Cast<SymbolResult>().ToArray(),
                Parameters: null),

            InterfaceDeclaration i => new SymbolResult(
                i.Name, SymbolKind.Interface, file, i.Line, i.Column,
                TypeName: null,
                Modifiers: FormatModifiers(i.Modifiers),
                Members: i.Members.Select(m => DeclarationToSymbol(m, file)).Where(s => s != null).Cast<SymbolResult>().ToArray(),
                Parameters: null),

            EnumDeclaration e => new SymbolResult(
                e.Name, SymbolKind.Enum, file, e.Line, e.Column,
                TypeName: null,
                Modifiers: FormatModifiers(e.Modifiers),
                Members: e.Members.Select(m => new SymbolResult(
                    m.Name, SymbolKind.EnumMember, file, m.Line, m.Column, null, null, null, null)).ToArray(),
                Parameters: null),

            UnionDeclaration u => new SymbolResult(
                u.Name, SymbolKind.Union, file, u.Line, u.Column,
                TypeName: null,
                Modifiers: FormatModifiers(u.Modifiers),
                Members: u.Cases.Select(c => new SymbolResult(
                    c.Name, SymbolKind.EnumMember, file, c.Line, c.Column, null, null, null, null)).ToArray(),
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

            TestDeclaration td => new SymbolResult(
                td.Description, SymbolKind.Test, file, td.Line, td.Column,
                TypeName: null,
                Modifiers: null,
                Members: null,
                Parameters: null),

            _ => null
        };
    }

    private OutlineEntry[] BuildOutline(CompilationUnit cu, string sourceText)
    {
        var lines = sourceText.Split('\n');
        return cu.Declarations
            .Select(d => DeclarationToOutlineEntry(d, lines))
            .Where(e => e != null)
            .Cast<OutlineEntry>()
            .ToArray();
    }

    private OutlineEntry? DeclarationToOutlineEntry(Declaration decl, string[] sourceLines)
    {
        return decl switch
        {
            FunctionDeclaration f => new OutlineEntry(
                f.Name, SymbolKind.Function, f.Line, EstimateEndLine(f, sourceLines),
                ReturnType: FormatTypeReference(f.ReturnType),
                TypeName: null,
                Children: null),

            ClassDeclaration c => new OutlineEntry(
                c.Name, SymbolKind.Class, c.Line, EstimateEndLine(c, sourceLines),
                ReturnType: null,
                TypeName: null,
                Children: c.Members.Select(m => DeclarationToOutlineEntry(m, sourceLines)).Where(e => e != null).Cast<OutlineEntry>().ToArray()),

            StructDeclaration s => new OutlineEntry(
                s.Name, SymbolKind.Struct, s.Line, EstimateEndLine(s, sourceLines),
                ReturnType: null,
                TypeName: null,
                Children: s.Members.Select(m => DeclarationToOutlineEntry(m, sourceLines)).Where(e => e != null).Cast<OutlineEntry>().ToArray()),

            RecordDeclaration r => new OutlineEntry(
                r.Name, SymbolKind.Record, r.Line, EstimateEndLine(r, sourceLines),
                ReturnType: null,
                TypeName: null,
                Children: r.Members.Select(m => DeclarationToOutlineEntry(m, sourceLines)).Where(e => e != null).Cast<OutlineEntry>().ToArray()),

            InterfaceDeclaration i => new OutlineEntry(
                i.Name, SymbolKind.Interface, i.Line, EstimateEndLine(i, sourceLines),
                ReturnType: null,
                TypeName: null,
                Children: i.Members.Select(m => DeclarationToOutlineEntry(m, sourceLines)).Where(e => e != null).Cast<OutlineEntry>().ToArray()),

            EnumDeclaration e => new OutlineEntry(
                e.Name, SymbolKind.Enum, e.Line, EstimateEndLine(e, sourceLines),
                ReturnType: null,
                TypeName: null,
                Children: e.Members.Select(m => new OutlineEntry(
                    m.Name, SymbolKind.EnumMember, m.Line, m.Line,
                    ReturnType: null,
                    TypeName: null,
                    Children: null)).ToArray()),

            UnionDeclaration u => new OutlineEntry(
                u.Name, SymbolKind.Union, u.Line, EstimateEndLine(u, sourceLines),
                ReturnType: null,
                TypeName: null,
                Children: u.Cases.Select(c => new OutlineEntry(
                    c.Name, SymbolKind.EnumMember, c.Line, c.Line,
                    ReturnType: null,
                    TypeName: null,
                    Children: null)).ToArray()),

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

    private DefinitionResult? FindDeclarationInUnit(CompilationUnit cu, string name, string file)
    {
        foreach (var decl in cu.Declarations)
        {
            var declName = GetDeclarationName(decl);
            if (declName == name)
            {
                var kind = GetDeclarationKind(decl);
                return new DefinitionResult(name, kind, file, decl.Line, decl.Column, name.Length);
            }

            // Search inside type members
            var members = GetDeclarationMembers(decl);
            if (members != null)
            {
                foreach (var member in members)
                {
                    var memberName = GetDeclarationName(member);
                    if (memberName == name)
                    {
                        var kind = GetDeclarationKind(member);
                        return new DefinitionResult(name, kind, file, member.Line, member.Column, name.Length);
                    }
                }
            }

            if (decl is EnumDeclaration enumDecl)
            {
                foreach (var member in enumDecl.Members)
                {
                    if (member.Name == name)
                        return new DefinitionResult(name, "enumMember", file, member.Line, member.Column, name.Length);
                }
            }

            if (decl is UnionDeclaration unionDecl)
            {
                foreach (var unionCase in unionDecl.Cases)
                {
                    if (unionCase.Name == name)
                        return new DefinitionResult(name, "enumMember", file, unionCase.Line, unionCase.Column, name.Length);
                }
            }
        }
        return null;
    }

    private void FindAllDeclarationsInUnit(CompilationUnit cu, string name, string file, List<DefinitionResult> results)
    {
        foreach (var decl in cu.Declarations)
        {
            var declName = GetDeclarationName(decl);
            if (declName != null && (name == "*" || declName.Contains(name, StringComparison.OrdinalIgnoreCase)))
            {
                results.Add(new DefinitionResult(declName, GetDeclarationKind(decl), file, decl.Line, decl.Column, declName.Length));
            }

            var members = GetDeclarationMembers(decl);
            if (members != null)
            {
                foreach (var member in members)
                {
                    var memberName = GetDeclarationName(member);
                    if (memberName != null && (name == "*" || memberName.Contains(name, StringComparison.OrdinalIgnoreCase)))
                    {
                        results.Add(new DefinitionResult(memberName, GetDeclarationKind(member), file, member.Line, member.Column, memberName.Length));
                    }
                }
            }

            if (decl is EnumDeclaration enumDecl)
            {
                foreach (var member in enumDecl.Members)
                {
                    if (name == "*" || member.Name.Contains(name, StringComparison.OrdinalIgnoreCase))
                    {
                        results.Add(new DefinitionResult(member.Name, "enumMember", file, member.Line, member.Column, member.Name.Length));
                    }
                }
            }

            if (decl is UnionDeclaration unionDecl)
            {
                foreach (var unionCase in unionDecl.Cases)
                {
                    if (name == "*" || unionCase.Name.Contains(name, StringComparison.OrdinalIgnoreCase))
                    {
                        results.Add(new DefinitionResult(unionCase.Name, "enumMember", file, unionCase.Line, unionCase.Column, unionCase.Name.Length));
                    }
                }
            }
        }
    }

    private void FindReferencesInMembers(List<Declaration> members, string name, string file, string[] lines, List<ReferenceResult> results)
    {
        foreach (var member in members)
        {
            var memberName = GetDeclarationName(member);
            if (memberName == name)
            {
                var context = member.Line > 0 && member.Line <= lines.Length ? lines[member.Line - 1].Trim() : null;
                results.Add(new ReferenceResult(file, member.Line, member.Column, name.Length, context, IsDefinition: true));
            }
        }
    }

    private DefinitionResult? ResolveDefinitionAtPosition(ProjectSnapshot snapshot, string filePath,
        CompilationUnit cu, int line, int col)
    {
        snapshot.SemanticModels.TryGetValue(filePath, out var semanticModel);

        var expr = FindExpressionAtPositionRobust(cu, line, col);
        var memberDefinition = TryResolveMemberDefinition(snapshot, cu, semanticModel, expr);
        if (memberDefinition != null)
            return memberDefinition;

        var sourceMemberDefinition = TryResolveMemberDefinitionFromSource(snapshot, filePath, cu, semanticModel, line, col);
        if (sourceMemberDefinition != null)
            return sourceMemberDefinition;

        if (snapshot.Bindings?.GetBindingAt(filePath, line, col) is { } binding)
            return BindingToDefinition(snapshot, binding);

        var candidateNames = GetCandidateQueryNames(expr, snapshot, filePath, line, col);
        foreach (var name in candidateNames)
        {
            if (snapshot.Bindings != null)
            {
                var bindingDecl = snapshot.Bindings.FindDeclarationsByName(name).FirstOrDefault();
                if (bindingDecl != null)
                    return BindingToDefinition(snapshot, bindingDecl);
            }

            foreach (var (defFile, defCu) in snapshot.CompilationUnits)
            {
                var result = FindDeclarationInUnit(defCu, name, GetRelativePath(snapshot.ProjectRoot, defFile));
                if (result != null)
                    return result;
            }
        }

        return null;
    }

    private DefinitionResult? TryResolveMemberDefinition(ProjectSnapshot snapshot, CompilationUnit currentUnit,
        SemanticModel? semanticModel, Expression? expr)
    {
        return expr switch
        {
            MemberAccessExpression memberAccess => ResolveMemberDefinitionFromAccess(snapshot, currentUnit, semanticModel, memberAccess),
            CallExpression call => TryResolveMemberDefinition(snapshot, currentUnit, semanticModel, call.Callee),
            _ => null
        };
    }

    private DefinitionResult? ResolveMemberDefinitionFromAccess(ProjectSnapshot snapshot, CompilationUnit currentUnit,
        SemanticModel? semanticModel, MemberAccessExpression memberAccess)
    {
        var receiverType = ResolveTypeInfoFromExpression(memberAccess.Object, semanticModel, snapshot, currentUnit);
        if (receiverType == null)
            return null;

        return FindMemberDefinitionForType(snapshot, receiverType, memberAccess.MemberName);
    }

    private DefinitionResult? TryResolveMemberDefinitionFromSource(ProjectSnapshot snapshot, string filePath,
        CompilationUnit currentUnit, SemanticModel? semanticModel, int line, int col)
    {
        var memberAccess = ExtractMemberAccessAtPosition(snapshot, filePath, line, col);
        if (memberAccess == null)
            return null;

        var receiverType = ResolveTypeInfoByName(memberAccess.Value.Receiver, semanticModel, snapshot, currentUnit);
        if (receiverType == null)
            return null;

        return FindMemberDefinitionForType(snapshot, receiverType, memberAccess.Value.Member);
    }

    private DefinitionResult? FindMemberDefinitionForType(ProjectSnapshot snapshot, TypeInfo typeInfo, string memberName)
    {
        return typeInfo switch
        {
            ClassTypeInfo classType => FindMemberDefinitionInDeclarations(snapshot, classType.Declaration, classType.Declaration.Members, memberName),
            StructTypeInfo structType => FindMemberDefinitionInDeclarations(snapshot, structType.Declaration, structType.Declaration.Members, memberName),
            RecordTypeInfo recordType => FindMemberDefinitionInDeclarations(snapshot, recordType.Declaration, recordType.Declaration.Members, memberName),
            InterfaceTypeInfo interfaceType => FindMemberDefinitionInDeclarations(snapshot, interfaceType.Declaration, interfaceType.Declaration.Members, memberName),
            EnumTypeInfo enumType => FindEnumMemberDefinition(snapshot, enumType.Declaration, memberName),
            UnionTypeInfo unionType => FindUnionCaseDefinition(snapshot, unionType.Declaration, memberName),
            GenericTypeInfo genericType => FindNamedTypeInfo(snapshot, genericType.Name) is { } namedType
                ? FindMemberDefinitionForType(snapshot, namedType, memberName)
                : null,
            NullableTypeInfo nullableType => FindMemberDefinitionForType(snapshot, nullableType.InnerType, memberName),
            _ => null
        };
    }

    private DefinitionResult? FindMemberDefinitionInDeclarations(ProjectSnapshot snapshot, Declaration owner,
        List<Declaration> members, string memberName)
    {
        var member = members.FirstOrDefault(m => GetDeclarationName(m) == memberName);
        if (member == null)
            return null;

        return CreateDefinitionForDeclaration(snapshot, member, memberName, GetDeclarationKind(member));
    }

    private DefinitionResult? FindEnumMemberDefinition(ProjectSnapshot snapshot, EnumDeclaration enumDecl, string memberName)
    {
        var member = enumDecl.Members.FirstOrDefault(m => m.Name == memberName);
        if (member == null)
            return null;

        var relativeFile = TryFindDeclarationFile(snapshot, enumDecl);
        if (relativeFile == null)
            return null;

        return new DefinitionResult(member.Name, "enumMember", relativeFile, member.Line, member.Column, member.Name.Length);
    }

    private DefinitionResult? FindUnionCaseDefinition(ProjectSnapshot snapshot, UnionDeclaration unionDecl, string memberName)
    {
        var unionCase = unionDecl.Cases.FirstOrDefault(c => c.Name == memberName);
        if (unionCase == null)
            return null;

        var relativeFile = TryFindDeclarationFile(snapshot, unionDecl);
        if (relativeFile == null)
            return null;

        return new DefinitionResult(unionCase.Name, "enumMember", relativeFile, unionCase.Line, unionCase.Column, unionCase.Name.Length);
    }

    private DefinitionResult? CreateDefinitionForDeclaration(ProjectSnapshot snapshot, Declaration decl, string name, string kind)
    {
        var relativeFile = TryFindDeclarationFile(snapshot, decl);
        if (relativeFile == null)
            return null;

        return new DefinitionResult(name, kind, relativeFile, decl.Line, decl.Column, name.Length);
    }

    private string? TryFindDeclarationFile(ProjectSnapshot snapshot, Declaration target)
    {
        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            if (ContainsDeclaration(cu.Declarations, target))
                return GetRelativePath(snapshot.ProjectRoot, filePath);
        }

        return null;
    }

    private static bool ContainsDeclaration(IEnumerable<Declaration> declarations, Declaration target)
    {
        foreach (var decl in declarations)
        {
            if (DeclarationMatches(decl, target))
                return true;

            if (ContainsDeclaration(GetDeclarationMembers(decl) ?? Enumerable.Empty<Declaration>(), target))
                return true;
        }

        return false;
    }

    private static bool DeclarationMatches(Declaration candidate, Declaration target)
    {
        if (ReferenceEquals(candidate, target))
            return true;

        return candidate.GetType() == target.GetType() &&
               candidate.Line == target.Line &&
               candidate.Column == target.Column &&
               string.Equals(GetDeclarationName(candidate), GetDeclarationName(target), StringComparison.Ordinal);
    }

    private static List<ReferenceResult> MergeReferenceResults(List<ReferenceResult>? primary, List<ReferenceResult> secondary)
    {
        return (primary ?? new List<ReferenceResult>())
            .Concat(secondary)
            .GroupBy(r => (r.File, r.Line, r.Column))
            .Select(g => g.OrderByDescending(r => r.IsDefinition).First())
            .OrderBy(r => r.File)
            .ThenBy(r => r.Line)
            .ThenBy(r => r.Column)
            .ToList();
    }

    private static DefinitionResult BindingToDefinition(ProjectSnapshot snapshot, SymbolDeclaration declaration)
    {
        var file = declaration.File == null
            ? "unknown"
            : GetRelativePath(snapshot.ProjectRoot, declaration.File);
        return new DefinitionResult(declaration.Name, declaration.Kind, file, declaration.Line, declaration.Column, declaration.Name.Length);
    }

    private void FindIdentifierUsagesInSource(string source, string name, string file, string[] lines, List<ReferenceResult> results)
    {
        for (int i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            var idx = 0;
            while ((idx = line.IndexOf(name, idx, StringComparison.Ordinal)) >= 0)
            {
                // Check word boundaries
                var before = idx > 0 ? line[idx - 1] : ' ';
                var after = idx + name.Length < line.Length ? line[idx + name.Length] : ' ';

                if (!char.IsLetterOrDigit(before) && before != '_' &&
                    !char.IsLetterOrDigit(after) && after != '_')
                {
                    // Skip if inside a string literal or comment (basic heuristic)
                    if (!IsInsideStringOrComment(line, idx))
                    {
                        var context = line.Trim();
                        // idx + 1 for 1-based column to match AST positions
                        results.Add(new ReferenceResult(file, i + 1, idx + 1, name.Length, context, IsDefinition: false));
                    }
                }

                idx += name.Length;
            }
        }
    }

    private static bool IsInsideStringOrComment(string line, int index)
    {
        // Simple heuristic: check if we're inside a string or comment
        var inString = false;
        var stringChar = '\0';
        var interpolationDepth = 0;

        for (int i = 0; i < index && i < line.Length; i++)
        {
            if (!inString)
            {
                if (line[i] == '/' && i + 1 < line.Length && line[i + 1] == '/')
                    return true; // Rest of line is comment
                if (line[i] == '"' || line[i] == '\'')
                {
                    inString = true;
                    stringChar = line[i];
                }
            }
            else
            {
                if (stringChar == '"' && line[i] == '{' && (i == 0 || line[i - 1] != '\\'))
                {
                    interpolationDepth++;
                    continue;
                }

                if (stringChar == '"' && line[i] == '}' && interpolationDepth > 0)
                {
                    interpolationDepth--;
                    continue;
                }

                if (interpolationDepth == 0 && line[i] == stringChar && (i == 0 || line[i - 1] != '\\'))
                    inString = false;
            }
        }

        return inString && interpolationDepth == 0;
    }

    private (string filePath, CompilationUnit? cu) FindCompilationUnit(ProjectSnapshot snapshot, string file)
    {
        // Try exact match first, respecting path segment boundaries
        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            if (MatchesFilePath(filePath, file))
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
        InterfaceDeclaration i => i.Name,
        EnumDeclaration e => e.Name,
        UnionDeclaration u => u.Name,
        FieldDeclaration fd => fd.Name,
        PropertyDeclaration pd => pd.Name,
        TypeAliasDeclaration ta => ta.Name,
        TestDeclaration td => td.Description,
        _ => null
    };

    private static string GetDeclarationKind(Declaration decl) => decl switch
    {
        FunctionDeclaration => "function",
        ClassDeclaration => "class",
        StructDeclaration => "struct",
        RecordDeclaration => "record",
        InterfaceDeclaration => "interface",
        EnumDeclaration => "enum",
        UnionDeclaration => "union",
        FieldDeclaration => "property",
        PropertyDeclaration => "property",
        ConstructorDeclaration => "constructor",
        TypeAliasDeclaration => "typeAlias",
        TestDeclaration => "test",
        _ => "unknown"
    };

    private static List<Declaration>? GetDeclarationMembers(Declaration decl) => decl switch
    {
        ClassDeclaration c => c.Members,
        StructDeclaration s => s.Members,
        RecordDeclaration r => r.Members,
        InterfaceDeclaration i => i.Members,
        _ => null
    };

    private static int EstimateEndLine(Declaration decl, string[] sourceLines)
    {
        var blockEnd = FindBlockEndLine(sourceLines, decl.Line, decl.Column);
        if (blockEnd != null)
            return blockEnd.Value;

        var members = GetDeclarationMembers(decl);
        if (members is { Count: > 0 })
        {
            return members.Max(m => EstimateEndLine(m, sourceLines)) + 1;
        }

        return decl switch
        {
            EnumDeclaration e when e.Members.Count > 0 => e.Members.Max(m => m.Line) + 1,
            UnionDeclaration u when u.Cases.Count > 0 => u.Cases.Max(c => c.Line) + 1,
            FunctionDeclaration f when f.ExpressionBody != null => f.ExpressionBody.Line,
            FunctionDeclaration f when f.Body?.Statements.Count > 0 => f.Body.Statements.Max(s => s.Line) + 1,
            _ => decl.Line
        };
    }

    private static int? FindBlockEndLine(string[] sourceLines, int startLine, int startColumn)
    {
        if (startLine <= 0 || startLine > sourceLines.Length)
            return null;

        var depth = 0;
        var sawOpeningBrace = false;

        for (var lineIndex = startLine - 1; lineIndex < sourceLines.Length; lineIndex++)
        {
            var line = sourceLines[lineIndex];
            var charIndex = lineIndex == startLine - 1 ? Math.Max(0, startColumn - 1) : 0;
            var inString = false;
            var stringDelimiter = '\0';

            for (var i = charIndex; i < line.Length; i++)
            {
                var ch = line[i];

                if (!inString)
                {
                    if (ch == '/' && i + 1 < line.Length && line[i + 1] == '/')
                        break;

                    if (ch == '"' || ch == '\'')
                    {
                        inString = true;
                        stringDelimiter = ch;
                        continue;
                    }

                    if (ch == '{')
                    {
                        depth++;
                        sawOpeningBrace = true;
                        continue;
                    }

                    if (ch == '}' && sawOpeningBrace)
                    {
                        depth--;
                        if (depth == 0)
                            return lineIndex + 1;
                    }
                }
                else if (ch == stringDelimiter && (i == 0 || line[i - 1] != '\\'))
                {
                    inString = false;
                }
            }
        }

        return null;
    }

    private static Expression? FindExpressionAtPositionRobust(CompilationUnit cu, int line, int col)
    {
        // CLI positions are 1-based. AstNodeFinder historically expected 0-based coordinates,
        // so try both until all callers are aligned.
        return AstNodeFinder.FindExpressionAtPosition(cu, line - 1, col - 1)
            ?? AstNodeFinder.FindExpressionAtPosition(cu, line, col);
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
        AddCandidateName(names, ExtractWordAtPosition(snapshot, filePath, line, Math.Max(1, col - 1)));
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
        return expr switch
        {
            IdentifierExpression id => ResolveTypeInfoByName(id.Name, semanticModel, snapshot, currentUnit),
            MemberAccessExpression ma => ResolveTypeInfoByName(ma.MemberName, semanticModel, snapshot, currentUnit),
            CallExpression call => ResolveTypeInfoFromExpression(call.Callee, semanticModel, snapshot, currentUnit),
            NewExpression newExpr when newExpr.Type != null => ResolveTypeReferenceToTypeInfo(newExpr.Type, snapshot),
            WithExpression withExpr => ResolveTypeInfoFromExpression(withExpr.Target, semanticModel, snapshot, currentUnit),
            AwaitExpression awaitExpr => ResolveTypeInfoFromExpression(awaitExpr.Expression, semanticModel, snapshot, currentUnit),
            CastExpression castExpr => ResolveTypeReferenceToTypeInfo(castExpr.TargetType, snapshot),
            IntLiteralExpression => new SimpleTypeInfo("int"),
            FloatLiteralExpression => new SimpleTypeInfo("double"),
            StringLiteralExpression => new SimpleTypeInfo("string"),
            BoolLiteralExpression => new SimpleTypeInfo("bool"),
            NullLiteralExpression => new SimpleTypeInfo("object"),
            _ => null
        };
    }

    private TypeInfo? ResolveTypeInfoByName(string name, SemanticModel? semanticModel,
        ProjectSnapshot snapshot, CompilationUnit currentUnit)
    {
        var typeInfo = semanticModel?.LookupIdentifier(name);
        if (typeInfo != null)
            return typeInfo;

        var localType = FindLocalVariableTypeInfo(currentUnit, name, snapshot);
        if (localType != null)
            return localType;

        return FindTypeInfoByName(snapshot, name);
    }

    private TypeInfo? FindLocalVariableTypeInfo(CompilationUnit cu, string name, ProjectSnapshot snapshot)
    {
        foreach (var decl in cu.Declarations)
        {
            var typeInfo = FindLocalVariableTypeInfoInDeclaration(cu, decl, name, snapshot);
            if (typeInfo != null)
                return typeInfo;
        }

        return null;
    }

    private TypeInfo? FindLocalVariableTypeInfoInDeclaration(CompilationUnit currentUnit, Declaration decl, string name,
        ProjectSnapshot snapshot)
    {
        if (decl is FunctionDeclaration func)
        {
            var fromBody = FindLocalVariableTypeInfoInStatement(currentUnit, func.Body, name, snapshot);
            if (fromBody != null)
                return fromBody;
        }

        foreach (var member in GetDeclarationMembers(decl) ?? Enumerable.Empty<Declaration>())
        {
            var memberType = FindLocalVariableTypeInfoInDeclaration(currentUnit, member, name, snapshot);
            if (memberType != null)
                return memberType;
        }

        return null;
    }

    private TypeInfo? FindLocalVariableTypeInfoInStatement(CompilationUnit currentUnit, Statement? stmt, string name,
        ProjectSnapshot snapshot)
    {
        if (stmt == null) return null;

        switch (stmt)
        {
            case BlockStatement block:
                foreach (var child in block.Statements)
                {
                    var childType = FindLocalVariableTypeInfoInStatement(currentUnit, child, name, snapshot);
                    if (childType != null)
                        return childType;
                }
                break;

            case VariableDeclarationStatement varDecl when varDecl.Name == name:
                if (varDecl.Type != null)
                    return ResolveTypeReferenceToTypeInfo(varDecl.Type, snapshot);
                if (varDecl.Initializer != null)
                    return ResolveTypeInfoFromExpression(varDecl.Initializer, null, snapshot, currentUnit);
                break;

            case IfStatement ifStmt:
                {
                    var thenType = FindLocalVariableTypeInfoInStatement(currentUnit, ifStmt.ThenStatement, name, snapshot);
                    if (thenType != null)
                        return thenType;
                    return FindLocalVariableTypeInfoInStatement(currentUnit, ifStmt.ElseStatement, name, snapshot);
                }

            case WhileStatement whileStmt:
                return FindLocalVariableTypeInfoInStatement(currentUnit, whileStmt.Body, name, snapshot);

            case ForStatement forStmt:
                {
                    var initType = FindLocalVariableTypeInfoInStatement(currentUnit, forStmt.Initializer, name, snapshot);
                    if (initType != null)
                        return initType;
                    return FindLocalVariableTypeInfoInStatement(currentUnit, forStmt.Body, name, snapshot);
                }

            case ForeachStatement foreachStmt when foreachStmt.VariableName == name:
                if (foreachStmt.Collection is IdentifierExpression id)
                {
                    var collectionType = FindTypeInfoByName(snapshot, id.Name);
                    if (collectionType is ArrayTypeInfo arrayType)
                        return arrayType.ElementType;
                    if (collectionType is GenericTypeInfo genericType && genericType.TypeArguments.Count > 0)
                        return genericType.TypeArguments[0];
                }
                break;

            case TryStatement tryStmt:
                {
                    var tryType = FindLocalVariableTypeInfoInStatement(currentUnit, tryStmt.TryBlock, name, snapshot);
                    if (tryType != null)
                        return tryType;
                    foreach (var catchClause in tryStmt.CatchClauses)
                    {
                        var catchType = FindLocalVariableTypeInfoInStatement(currentUnit, catchClause.Block, name, snapshot);
                        if (catchType != null)
                            return catchType;
                    }
                    return FindLocalVariableTypeInfoInStatement(currentUnit, tryStmt.FinallyBlock, name, snapshot);
                }
        }

        return null;
    }

    private TypeInfo? FindTypeInfoByName(ProjectSnapshot snapshot, string name)
    {
        foreach (var (_, cu) in snapshot.CompilationUnits)
        {
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
            return new EnumTypeInfo(enumDecl);

        if (decl is UnionDeclaration unionDecl && unionDecl.Cases.Any(c => c.Name == name))
            return new UnionTypeInfo(unionDecl);

        return null;
    }

    private TypeInfo? TryGetTypeInfoFromDeclaration(Declaration decl, string name, ProjectSnapshot snapshot)
    {
        return decl switch
        {
            FunctionDeclaration f when f.Name == name => f.ReturnType != null
                ? ResolveTypeReferenceToTypeInfo(f.ReturnType, snapshot)
                : new SimpleTypeInfo("void"),
            ClassDeclaration c when c.Name == name => new ClassTypeInfo(c),
            StructDeclaration s when s.Name == name => new StructTypeInfo(s),
            RecordDeclaration r when r.Name == name => new RecordTypeInfo(r),
            InterfaceDeclaration i when i.Name == name => new InterfaceTypeInfo(i),
            EnumDeclaration e when e.Name == name => new EnumTypeInfo(e),
            UnionDeclaration u when u.Name == name => new UnionTypeInfo(u),
            FieldDeclaration fd when fd.Name == name && fd.Type != null => ResolveTypeReferenceToTypeInfo(fd.Type, snapshot),
            PropertyDeclaration pd when pd.Name == name => ResolveTypeReferenceToTypeInfo(pd.Type, snapshot),
            TypeAliasDeclaration ta when ta.Name == name => ResolveTypeReferenceToTypeInfo(ta.Type, snapshot),
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
            _ => new SimpleTypeInfo(typeRef.ToString() ?? "unknown")
        };
    }

    private TypeInfo? FindNamedTypeInfo(ProjectSnapshot snapshot, string name)
    {
        foreach (var (_, cu) in snapshot.CompilationUnits)
        {
            foreach (var decl in cu.Declarations)
            {
                var typeInfo = decl switch
                {
                    ClassDeclaration c when c.Name == name => new ClassTypeInfo(c),
                    StructDeclaration s when s.Name == name => new StructTypeInfo(s),
                    RecordDeclaration r when r.Name == name => new RecordTypeInfo(r),
                    InterfaceDeclaration i when i.Name == name => new InterfaceTypeInfo(i),
                    EnumDeclaration e when e.Name == name => new EnumTypeInfo(e),
                    UnionDeclaration u when u.Name == name => new UnionTypeInfo(u),
                    TypeAliasDeclaration ta when ta.Name == name => ResolveTypeReferenceToTypeInfo(ta.Type, snapshot),
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
            _ => null
        };
    }

    private static string GetTypeDisplayName(TypeInfo typeInfo, string fallback)
    {
        return typeInfo switch
        {
            ClassTypeInfo c => c.Declaration.Name,
            StructTypeInfo s => s.Declaration.Name,
            RecordTypeInfo r => r.Declaration.Name,
            InterfaceTypeInfo i => i.Declaration.Name,
            EnumTypeInfo e => e.Declaration.Name,
            UnionTypeInfo u => u.Declaration.Name,
            ReflectionTypeInfo r => r.Type.Name,
            _ => fallback
        };
    }

    /// <summary>
    /// Public accessor for type reference formatting (used by CompletionEngine).
    /// </summary>
    public static string FormatTypeReferencePublic(TypeReference? typeRef) => FormatTypeReference(typeRef);

    private static string FormatTypeReference(TypeReference? typeRef) => typeRef switch
    {
        null => "void",
        SimpleTypeReference s => s.Name,
        GenericTypeReference g => $"{g.Name}<{string.Join(", ", g.TypeArguments.Select(t => FormatTypeReference(t)))}>",
        ArrayTypeReference a => $"{FormatTypeReference(a.ElementType)}[]",
        NullableTypeReference n => $"{FormatTypeReference(n.InnerType)}?",
        TupleTypeReference t => $"({string.Join(", ", t.Elements.Select(e => e.Name != null ? $"{e.Name}: {FormatTypeReference(e.Type)}" : FormatTypeReference(e.Type)))})",
        FunctionTypeReference f => $"({string.Join(", ", f.ParameterTypes.Select(FormatTypeReference))}) -> {FormatTypeReference(f.ReturnType)}",
        _ => typeRef.ToString() ?? "unknown"
    };

    private static string FormatTypeInfo(TypeInfo typeInfo) => typeInfo switch
    {
        SimpleTypeInfo s => s.Name,
        ClassTypeInfo c => c.Declaration.Name,
        StructTypeInfo s => s.Declaration.Name,
        RecordTypeInfo r => r.Declaration.Name,
        InterfaceTypeInfo i => i.Declaration.Name,
        EnumTypeInfo e => e.Declaration.Name,
        UnionTypeInfo u => u.Declaration.Name,
        FunctionTypeInfo f => f.Declaration?.Name ?? "function",
        GenericTypeInfo g => $"{g.Name}<{string.Join(", ", g.TypeArguments.Select(FormatTypeInfo))}>",
        ArrayTypeInfo a => $"{FormatTypeInfo(a.ElementType)}[]",
        NullableTypeInfo n => $"{FormatTypeInfo(n.InnerType)}?",
        ReflectionTypeInfo r => r.Type.Name,
        _ => typeInfo.ToString() ?? "unknown"
    };

    private static string TypeInfoToKind(TypeInfo typeInfo) => typeInfo switch
    {
        ClassTypeInfo => "class",
        StructTypeInfo => "struct",
        RecordTypeInfo => "record",
        InterfaceTypeInfo => "interface",
        EnumTypeInfo => "enum",
        UnionTypeInfo => "union",
        FunctionTypeInfo => "function",
        GenericTypeInfo => "generic",
        ArrayTypeInfo => "array",
        NullableTypeInfo => "nullable",
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
                    return new LocationResult(GetRelativePath(snapshot.ProjectRoot, filePath), member.Line, member.Column);
            }
        }

        if (decl is UnionDeclaration unionDecl)
        {
            foreach (var unionCase in unionDecl.Cases)
            {
                if (unionCase.Name == name)
                    return new LocationResult(GetRelativePath(snapshot.ProjectRoot, filePath), unionCase.Line, unionCase.Column);
            }
        }

        return null;
    }

    private static string? ExtractWordAtPosition(ProjectSnapshot snapshot, string filePath, int line, int col)
    {
        try
        {
            var source = File.ReadAllText(filePath);
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length) return null;

            var lineText = lines[line - 1];
            if (lineText.Length == 0 || col <= 0 || col > lineText.Length) return null;

            var index = col - 1;
            if (!IsIdentifierChar(lineText[index]) && index > 0 && IsIdentifierChar(lineText[index - 1]))
            {
                index--;
            }

            if (!IsIdentifierChar(lineText[index]))
                return null;

            var start = index;
            while (start > 0 && IsIdentifierChar(lineText[start - 1]))
                start--;

            var end = index + 1;
            while (end < lineText.Length && IsIdentifierChar(lineText[end]))
                end++;

            return start < end ? lineText[start..end] : null;
        }
        catch
        {
            return null;
        }
    }

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';

    private static (string Receiver, string Member)? ExtractMemberAccessAtPosition(ProjectSnapshot snapshot,
        string filePath, int line, int col)
    {
        try
        {
            var source = File.ReadAllText(filePath);
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            if (lineText.Length == 0 || col <= 0 || col > lineText.Length)
                return null;

            var index = col - 1;
            if (!IsIdentifierChar(lineText[index]) && index > 0 && IsIdentifierChar(lineText[index - 1]))
                index--;

            if (!IsIdentifierChar(lineText[index]))
                return null;

            var memberStart = index;
            while (memberStart > 0 && IsIdentifierChar(lineText[memberStart - 1]))
                memberStart--;

            var memberEnd = index + 1;
            while (memberEnd < lineText.Length && IsIdentifierChar(lineText[memberEnd]))
                memberEnd++;

            var dotIndex = memberStart - 1;
            while (dotIndex >= 0 && char.IsWhiteSpace(lineText[dotIndex]))
                dotIndex--;

            if (dotIndex < 0 || lineText[dotIndex] != '.')
                return null;

            var receiverEnd = dotIndex - 1;
            while (receiverEnd >= 0 && char.IsWhiteSpace(lineText[receiverEnd]))
                receiverEnd--;

            if (receiverEnd < 0 || !IsIdentifierChar(lineText[receiverEnd]))
                return null;

            var receiverStart = receiverEnd;
            while (receiverStart > 0 && IsIdentifierChar(lineText[receiverStart - 1]))
                receiverStart--;

            var receiver = lineText[receiverStart..(receiverEnd + 1)];
            var member = lineText[memberStart..memberEnd];
            return (receiver, member);
        }
        catch
        {
            return null;
        }
    }

    private static string? ExtractVariableDeclarationNameAtPosition(ProjectSnapshot snapshot, string filePath, int line)
    {
        try
        {
            var source = File.ReadAllText(filePath);
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length) return null;

            var lineText = lines[line - 1];
            var assignIndex = lineText.IndexOf(":=", StringComparison.Ordinal);
            if (assignIndex <= 0) return null;

            var end = assignIndex - 1;
            while (end >= 0 && char.IsWhiteSpace(lineText[end]))
                end--;
            if (end < 0) return null;

            var start = end;
            while (start >= 0 && (char.IsLetterOrDigit(lineText[start]) || lineText[start] == '_'))
                start--;

            start++;
            return start <= end ? lineText.Substring(start, end - start + 1) : null;
        }
        catch
        {
            return null;
        }
    }

    private static string? ExtractSourceLine(Dictionary<string, string> sourceTexts, string filePath, int line)
    {
        if (!sourceTexts.TryGetValue(filePath, out var source)) return null;
        var lines = source.Split('\n');
        if (line > 0 && line <= lines.Length)
            return lines[line - 1];
        return null;
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

    private static string NormalizePath(string path)
    {
        return path.Replace('\\', '/');
    }

    /// <summary>
    /// Matches a full file path against a query file path, respecting path segment boundaries.
    /// "Program.nl" matches "/project/Program.nl" but NOT "/project/OldProgram.nl".
    /// </summary>
    private static bool MatchesFilePath(string fullPath, string queryPath)
    {
        var normalizedFull = NormalizePath(fullPath);
        var normalizedQuery = NormalizePath(queryPath);

        if (normalizedFull.Equals(normalizedQuery, StringComparison.OrdinalIgnoreCase))
            return true;

        if (!normalizedFull.EndsWith(normalizedQuery, StringComparison.OrdinalIgnoreCase))
            return false;

        // Ensure match is at a path segment boundary
        var charBefore = normalizedFull[normalizedFull.Length - normalizedQuery.Length - 1];
        return charBefore == '/';
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
    public BindingMap? Bindings { get; }

    public ProjectSnapshot(
        string projectRoot,
        IReadOnlyDictionary<string, CompilationUnit> compilationUnits,
        IReadOnlyDictionary<string, SemanticModel> semanticModels,
        IReadOnlyList<CompilerError> allErrors,
        Analyzer sharedAnalyzer,
        IReadOnlyList<string> sourceFiles,
        BindingMap? bindings = null)
    {
        ProjectRoot = projectRoot;
        CompilationUnits = compilationUnits;
        SemanticModels = semanticModels;
        AllErrors = allErrors;
        SharedAnalyzer = sharedAnalyzer;
        SourceFiles = sourceFiles;
        Bindings = bindings;
    }
}

/// <summary>
/// Snapshot of a single analyzed file (fast path).
/// </summary>
public class SingleFileSnapshot
{
    public string FilePath { get; }
    public string Source { get; }
    public CompilationUnit? CompilationUnit { get; }
    public SemanticModel? SemanticModel { get; }
    public IReadOnlyList<CompilerError> Errors { get; }

    public SingleFileSnapshot(string filePath, string source, CompilationUnit? compilationUnit,
        SemanticModel? semanticModel, IReadOnlyList<CompilerError> errors)
    {
        FilePath = filePath;
        Source = source;
        CompilationUnit = compilationUnit;
        SemanticModel = semanticModel;
        Errors = errors;
    }
}
