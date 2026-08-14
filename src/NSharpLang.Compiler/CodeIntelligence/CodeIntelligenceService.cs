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
    /// <see cref="CodeIntelligenceDiagnostics"/>. Both dictionaries are rebuilt with the same
    /// OrdinalIgnoreCase comparer the project snapshot itself is built with.
    /// </remarks>
    public List<DiagnosticResult> GetDiagnostics(ProjectSnapshot snapshot, string? file = null)
        => CodeIntelligenceDiagnostics.Build(
            snapshot.ProjectRoot,
            snapshot.AllErrors.ToList(),
            snapshot.SourceFiles.ToList(),
            snapshot.CompilationUnits.ToDictionary(kvp => kvp.Key, kvp => kvp.Value, StringComparer.OrdinalIgnoreCase),
            snapshot.SourceTexts.ToDictionary(kvp => kvp.Key, kvp => kvp.Value, StringComparer.OrdinalIgnoreCase),
            file);

    // WALLED: this overload's `IReadOnlyDictionary<string, string>` parameter is the ONE shape the
    // columnar emitter's resolvable-type catalog did not carry when the family moved. It moves the
    // moment the published catalog row reaches the toolset.
    public static DiagnosticResult ToDiagnosticResult(
        CompilerError error,
        string projectRoot,
        IReadOnlyDictionary<string, string>? sourceTexts = null)
    {
        var errorFile = error.FileName ?? "unknown";
        var relativeFile = CodeIntelligenceSourceDoor.RelativePath(projectRoot, errorFile);
        var snippet = error.SourceSnippet;
        if (string.IsNullOrWhiteSpace(snippet) && error.Line > 0 && sourceTexts != null)
        {
            sourceTexts.TryGetValue(errorFile, out var errorSource);
            snippet = CodeIntelligenceSourceDoor.SourceLine(errorSource, error.Line);
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
            Suggestion: error.Suggestion ?? CodeIntelligenceDisplayText.FormatSuggestions(error.Suggestions),
            Hint: error.ContextualHint,
            ExpectedType: error.ExpectedType,
            ActualType: error.ActualType,
            DocsUrl: error.DocsUrl ?? DiagnosticCatalog.DocsUrlFor(error.DiagnosticId));
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

        var declarationType = ResolveDeclaredNameTypeAtPosition(snapshot, filePath, cu, line, col);
        if (declarationType != null)
            return declarationType;

        var typeUse = ResolveTypeUseAtPosition(snapshot, filePath, cu, semanticModel, line, col);
        if (typeUse != null)
            return typeUse;

        var expr = FindExpressionAtPositionRobust(cu, line, col);
        var candidateNames = CodeIntelligenceSourceDoor.CandidateQueryNames(
            expr, GetSourceText(snapshot, filePath), line, col);
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
                CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, declaration.File ?? string.Empty),
                declaration.Line,
                declaration.Column,
                declaration.Name.Length,
                declaration.Line > 0
                    ? CodeIntelligenceSourceDoor.SourceContext(GetSourceText(snapshot, declaration.File), declaration.Line)
                    : null,
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
                    CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, usage.File ?? string.Empty),
                    usage.Line,
                    usage.Column,
                    usage.Length,
                    usage.Line > 0
                        ? CodeIntelligenceSourceDoor.SourceContext(GetSourceText(snapshot, usage.File), usage.Line)
                        : null,
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

        // Extract doc comment from the definition site. The path is resolved first because the
        // source text can only be fetched once the absolute path is known.
        string? documentation = null;
        var definitionLine = definition?.Line ?? 0;
        if (definedIn != null && definitionLine > 1)
        {
            var docPath = CodeIntelligenceSourceDoor.ResolveAbsolutePath(snapshot.CompilationUnits.Keys, definedIn);
            if (docPath != null)
            {
                documentation = CodeIntelligenceSourceDoor.DocComment(GetSourceText(snapshot, docPath), definitionLine);
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

    private DefinitionResult ToDefinitionResult(ProjectSnapshot snapshot, SymbolDeclaration declaration)
        => new(
            declaration.Name,
            declaration.Kind,
            CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, declaration.File ?? string.Empty),
            declaration.Line,
            declaration.Column,
            declaration.Name.Length);

    private TypeResult? ResolveTypeUseAtPosition(ProjectSnapshot snapshot, string filePath, CompilationUnit currentUnit,
        SemanticModel? semanticModel, int line, int col)
    {
        var declaration = TryResolveDefinitionViaBindings(snapshot, filePath, line, col);
        if (declaration == null || !AnalyzerBindingFacts.IsTypeDeclarationKind(declaration.Kind))
            return null;

        var span = CodeIntelligenceSourceDoor.IdentifierSpanAt(GetSourceText(snapshot, filePath), line, col);
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
            typeInfo != null ? NullStateFacts.GetSchemaText(GetDefaultNullState(typeInfo)) : null);
    }

    private TypeResult? ResolveDeclaredNameTypeAtPosition(ProjectSnapshot snapshot, string filePath, CompilationUnit currentUnit,
        int line, int col)
    {
        var selectedName = CodeIntelligenceSourceDoor.WordAt(GetSourceText(snapshot, filePath), line, col);
        if (string.IsNullOrWhiteSpace(selectedName))
            return null;

        foreach (var declaration in currentUnit.Declarations)
        {
            var result = ResolveDeclaredNameTypeInDeclaration(
                snapshot,
                filePath,
                declaration,
                selectedName!,
                line);
            if (result != null)
                return result;
        }

        return null;
    }

    private TypeResult? ResolveDeclaredNameTypeInDeclaration(ProjectSnapshot snapshot, string filePath, Declaration declaration,
        string selectedName, int line)
    {
        var declarationName = DeclarationFacts.GetDeclarationName(declaration);
        if (declaration.Line == line
            && string.Equals(declarationName, selectedName, StringComparison.Ordinal)
            && TryGetDeclaredNameTypeInfo(declaration, snapshot, out var typeInfo))
        {
            var resolvedType = NullabilityMetadataReflection.FormatTypeInfo(typeInfo);
            return new TypeResult(
                selectedName,
                resolvedType,
                CodeIntelligenceDisplayText.TypeInfoToKind(typeInfo),
                new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), declaration.Line, declaration.Column),
                NullStateFacts.GetSchemaText(GetDefaultNullState(typeInfo)));
        }

        foreach (var member in DeclarationFacts.GetDeclarationMembers(declaration)?.Cast<Declaration>() ?? Enumerable.Empty<Declaration>())
        {
            var memberResult = ResolveDeclaredNameTypeInDeclaration(
                snapshot,
                filePath,
                member,
                selectedName,
                line);
            if (memberResult != null)
                return memberResult;
        }

        return null;
    }

    private bool TryGetDeclaredNameTypeInfo(Declaration declaration, ProjectSnapshot snapshot, out TypeInfo typeInfo)
    {
        switch (declaration)
        {
            case FunctionDeclaration function:
                typeInfo = function.ReturnType != null
                    ? ResolveTypeReferenceToTypeInfo(function.ReturnType, snapshot)
                    : new SimpleTypeInfo("void");
                return true;
            case FieldDeclaration { Type: { } fieldType }:
                typeInfo = ResolveTypeReferenceToTypeInfo(fieldType, snapshot);
                return true;
            case PropertyDeclaration property:
                typeInfo = ResolveTypeReferenceToTypeInfo(property.Type, snapshot);
                return true;
            case ClassDeclaration cls:
                typeInfo = NominalTypeInfoFactory.FromClassDeclaration(cls);
                return true;
            case StructDeclaration str:
                typeInfo = NominalTypeInfoFactory.FromStructDeclaration(str);
                return true;
            case RecordDeclaration record:
                typeInfo = NominalTypeInfoFactory.FromRecordDeclaration(record);
                return true;
            case InterfaceDeclaration iface:
                typeInfo = NominalTypeInfoFactory.FromInterfaceDeclaration(iface);
                return true;
            case EnumDeclaration enumDecl:
                typeInfo = EnumTypeInfoFactory.FromDeclaration(enumDecl);
                return true;
            case UnionDeclaration union:
                typeInfo = UnionTypeInfoFactory.FromDeclaration(union);
                return true;
            case TypeAliasDeclaration alias:
                typeInfo = ResolveTypeReferenceToTypeInfo(alias.Type, snapshot);
                return true;
            case NewtypeDeclaration newtype:
                typeInfo = new NewtypeInfo(newtype.Name, newtype.UnderlyingType);
                return true;
            default:
                typeInfo = BuiltInTypes.Unknown;
                return false;
        }
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
        var span = CodeIntelligenceSourceDoor.IdentifierSpanAt(GetSourceText(snapshot, filePath), line, col);
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

        foreach (var member in DeclarationFacts.GetDeclarationMembers(decl)?.Cast<Declaration>() ?? Enumerable.Empty<Declaration>())
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

    /// <summary>
    /// The snapshot's text for a file: the in-memory override when the caller supplied one (this is
    /// the LSP's unsaved-buffer path), otherwise disk.
    ///
    /// This is the ONE member of the text family that could not move to N#, and the reason is
    /// measured rather than preferred: <see cref="ProjectSnapshot.SourceTexts"/> is an
    /// IReadOnlyDictionary, and IReadOnlyDictionary&lt;K, V&gt; is absent from the columnar
    /// emitter's resolvable-type catalog — a static N# parameter of that type declines at
    /// emit.declaration.method-param. So the text crosses the boundary as a string, exactly as
    /// every CodeIntelligenceSourceTextKernels entry point already requires. It carries no policy
    /// beyond that lookup.
    /// </summary>
    private static string? GetSourceText(ProjectSnapshot snapshot, string? filePath)
    {
        if (filePath == null)
            return null;

        var fullPath = Path.GetFullPath(filePath);
        if (snapshot.SourceTexts.TryGetValue(fullPath, out var text))
            return text;

        return File.ReadAllText(fullPath);
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
