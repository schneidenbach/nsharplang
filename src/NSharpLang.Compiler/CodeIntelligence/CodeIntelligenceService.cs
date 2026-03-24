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
        if (semanticModel == null) return null;

        // Find the expression at the position
        var expr = AstNodeFinder.FindExpressionAtPosition(cu, line, col);
        if (expr == null) return null;

        // Extract identifier name from expression
        var name = expr switch
        {
            IdentifierExpression id => id.Name,
            MemberAccessExpression ma => ma.MemberName,
            _ => expr.GetType().Name
        };

        // Look up type from semantic model
        var typeInfo = semanticModel.LookupIdentifier(name);
        if (typeInfo == null) return null;

        var resolvedType = FormatTypeInfo(typeInfo);
        var kind = TypeInfoToKind(typeInfo);

        // Try to find definition location
        var definition = FindDefinitionLocation(snapshot, name);

        return new TypeResult(name, resolvedType, kind, definition);
    }

    /// <summary>
    /// Find the definition of the symbol at a position (semantic, position-based).
    /// </summary>
    public DefinitionResult? FindDefinition(ProjectSnapshot snapshot, string file, int line, int col)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null) return null;

        // Find expression at position
        var expr = AstNodeFinder.FindExpressionAtPosition(cu, line, col);
        var name = expr switch
        {
            IdentifierExpression id => id.Name,
            MemberAccessExpression ma => ma.MemberName,
            _ => null
        };

        if (name == null)
        {
            // Fallback: extract word from source at position
            name = ExtractWordAtPosition(snapshot, filePath, line, col);
        }

        if (name == null) return null;

        // Search all compilation units for the declaration
        foreach (var (defFile, defCu) in snapshot.CompilationUnits)
        {
            var result = FindDeclarationInUnit(defCu, name, GetRelativePath(snapshot.ProjectRoot, defFile));
            if (result != null) return result;
        }

        return null;
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

        // Try semantic path via BindingMap first
        if (snapshot.Bindings != null)
        {
            var semanticResults = FindReferencesViaBindingMap(snapshot, filePath, line, col);
            if (semanticResults != null && semanticResults.Count > 0)
                return semanticResults;
        }

        // Fallback to text-based search (for cases where BindingMap doesn't cover)
        return FindReferencesViaTextSearch(snapshot, cu, filePath, line, col);
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

            if (!isDefinition)
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
    private List<ReferenceResult> FindReferencesViaTextSearch(ProjectSnapshot snapshot,
        CompilationUnit cu, string filePath, int line, int col)
    {
        var expr = AstNodeFinder.FindExpressionAtPosition(cu, line, col);
        var name = expr switch
        {
            IdentifierExpression id => id.Name,
            MemberAccessExpression ma => ma.MemberName,
            _ => ExtractWordAtPosition(snapshot, filePath, line, col)
        };

        if (name == null) return new List<ReferenceResult>();

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
                    m.Name, SymbolKind.EnumMember, file, 0, 0, null, null, null, null)).ToArray(),
                Parameters: null),

            UnionDeclaration u => new SymbolResult(
                u.Name, SymbolKind.Union, file, u.Line, u.Column,
                TypeName: null,
                Modifiers: FormatModifiers(u.Modifiers),
                Members: u.Cases.Select(c => new SymbolResult(
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
                if (line[i] == stringChar && (i == 0 || line[i - 1] != '\\'))
                    inString = false;
            }
        }

        return inString;
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
        FieldDeclaration => "field",
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

        return decl.Line;
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
                if (GetDeclarationName(decl) == name)
                {
                    return new LocationResult(GetRelativePath(snapshot.ProjectRoot, filePath), decl.Line, decl.Column);
                }
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
            if (col < 0 || col >= lineText.Length) return null;

            // Find word boundaries
            var start = col;
            while (start > 0 && (char.IsLetterOrDigit(lineText[start - 1]) || lineText[start - 1] == '_'))
                start--;

            var end = col;
            while (end < lineText.Length && (char.IsLetterOrDigit(lineText[end]) || lineText[end] == '_'))
                end++;

            return start < end ? lineText.Substring(start, end - start) : null;
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
