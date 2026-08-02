using System;
using System.Buffers;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Columnar;

namespace NSharpLang.Compiler;

/// <summary>
/// Semantic analyzer for NewCLILang
/// Performs type checking, name resolution, and definite assignment analysis
/// </summary>
public class Analyzer : IDisposable
{
    /// <summary>
    /// Length of the <c>match</c> keyword. Non-exhaustive-match diagnostics underline
    /// the <c>match</c> keyword so the squiggle lands on the construct that is incomplete.
    /// </summary>
    private const int MatchKeywordLength = 5;

    private static readonly HashSet<string> BuiltInObjectMembers = new(StringComparer.Ordinal)
    {
        "ToString",
        "Equals",
        "GetHashCode",
        "GetType"
    };

    private static readonly HashSet<string> BuiltInStringInstanceMembers = new(StringComparer.Ordinal)
    {
        "Length",
        "Chars",
        "CompareTo",
        "Contains",
        "EndsWith",
        "Equals",
        "IndexOf",
        "LastIndexOf",
        "Replace",
        "Split",
        "StartsWith",
        "Substring",
        "ToCharArray",
        "ToLower",
        "ToLowerInvariant",
        "ToUpper",
        "ToUpperInvariant",
        "Trim",
        "TrimEnd",
        "TrimStart"
    };

    private static readonly HashSet<string> BuiltInStringStaticMembers = new(StringComparer.Ordinal)
    {
        "Compare",
        "Concat",
        "Copy",
        "Equals",
        "Format",
        "IsNullOrEmpty",
        "IsNullOrWhiteSpace",
        "Join"
    };

    private static readonly HashSet<string> BuiltInNumericStaticMembers = new(StringComparer.Ordinal)
    {
        "MaxValue",
        "MinValue",
        "Parse",
        "TryParse"
    };

    private static readonly HashSet<string> BuiltInNumericInstanceMembers = new(StringComparer.Ordinal)
    {
        "CompareTo",
        "Equals",
        "ToString"
    };

    private static readonly HashSet<string> BuiltInBooleanStaticMembers = new(StringComparer.Ordinal)
    {
        "FalseString",
        "Parse",
        "TrueString",
        "TryParse"
    };

    private static readonly HashSet<string> BuiltInBooleanInstanceMembers = new(StringComparer.Ordinal)
    {
        "CompareTo",
        "Equals",
        "GetHashCode",
        "ToString"
    };

    private static readonly HashSet<string> BuiltInArrayMembers = new(StringComparer.Ordinal)
    {
        "Length",
        "LongLength",
        "Rank",
        "GetLength",
        "GetLowerBound",
        "GetUpperBound",
        "GetValue",
        "SetValue",
        "Clone",
        "CopyTo"
    };

    private static readonly HashSet<string> SupportedSoaDirectColumnStaticArrayMethods = new(StringComparer.Ordinal)
    {
        "Fill",
        "Copy",
        "Clear"
    };

    private static readonly HashSet<string> DedicatedSoaDirectColumnStaticArrayDiagnostics = new(StringComparer.Ordinal)
    {
        "Resize",
        "Sort",
        "Reverse"
    };

    private static List<FunctionTypeInfo> GetNSharpMethodGroupFunctions(NSharpMethodGroupInfo methodGroup)
        => NSharpMethodGroupInfoFactory.GetFunctions(methodGroup);

    private readonly List<CompilerError> _errors = new();
    private readonly AnalyzerScopeStack _scopes = new();
    private readonly List<string> _usingNamespaces = new();
    private readonly Dictionary<string, string> _usingAliases = new(); // alias -> fullName
    private readonly Dictionary<string, List<ImportedSymbolReference>> _importedSymbols = new(); // symbol -> import references
    private readonly Dictionary<string, Dictionary<string, TypeInfo>> _importedSymbolsByAlias = new(); // alias -> (symbol -> TypeInfo)
    private readonly Dictionary<string, Dictionary<string, SymbolDeclaration>> _importedDeclarationsByAlias = new(); // alias -> (symbol -> declaration)
    private readonly AnalyzerDeclarationContext _declarationContext = new();
    private readonly List<FunctionDeclaration> _extensionMethods = new(); // Extension methods available in current compilation
    private List<(string Name, TypeInfo Type, int Line, int Column)> _setupSymbols = new();
    private TypeInfo? _currentReturnType;
    private FunctionDeclaration? _currentFunction;
    private bool _currentFunctionReturnTypeWasOmitted;
    private bool _currentFunctionIsAsync;
    private bool _inLoop;
    // NL319: nesting depth of `finally` blocks currently being analyzed (finallys nest), plus the depth
    // recorded when the innermost break/continue target was entered. A `return` at depth > 0 — or a
    // `break`/`continue` whose target loop/switch was entered at a SHALLOWER depth — would have to exit
    // the finally handler, which ECMA-335 forbids (a finally may only complete via its own end; the
    // emitted `leave` is invalid IL and crashes with InvalidProgramException on every call). All three
    // reset at nested-body boundaries (lambdas, local functions): a return there exits the nested body,
    // not the finally, which is legal. The loop context resets there too; break/continue cannot target
    // an enclosing method's loop from a nested method body.
    private int _finallyDepth;
    private int _breakTargetFinallyDepth;
    private int _continueTargetFinallyDepth;
    private bool _inConstructor;
    private ClassDeclaration? _currentClass;
    private string? _currentTypeName;
    private string? _currentFilePath;
    private string? _declarationContextFilePath;
    private CompilationUnit? _compilationUnit; // Current file's AST (for namespace checks)
    private TypeInfo? _currentExpectedType;  // For target-typed expressions
    private string? _sourceText;
    // MetadataLoadContext-based assembly inspection (no runtime loading, no version conflicts)
    private NSharpMetadataResolver? _metadataResolver;
    private MetadataLoadContext? _mlc;
    private AnalyzerWellKnownTypes? _wellKnownTypes;
    // Rebuilt, not mutated, whenever _wellKnownTypes changes: the owner's own fields never change
    // after construction.
    private AnalyzerClrTypeConversion _clrTypeConversion;
    private AnalyzerAssignabilityFacts _assignabilityFacts;
    private readonly List<Assembly> _mlcAssemblies = new();

    // Reference assemblies that failed to load or be inspected, keyed by identity (file path
    // or assembly name) → first failure detail. Surfaced as NL923 warnings whenever analysis
    // also produced unresolved-type errors, so a broken reference can't silently masquerade
    // as a plain "type not found".
    private readonly Dictionary<string, string> _referenceLoadFailures = new(StringComparer.Ordinal);

    private readonly HashSet<string> _referencedPackageNames = new(StringComparer.Ordinal);
    private readonly Dictionary<string, IReadOnlyDictionary<string, string>> _restoredPackageVersionsByProject = new(StringComparer.Ordinal);
    // The analyzer's external (MetadataLoadContext) type probe. Constructed once and never
    // rebuilt: it owns the resolution cache, and that cache participates in the probe ORDER.
    private readonly AnalyzerExternalTypeProbe _externalTypeProbe;
    private readonly Dictionary<string, bool> _externalNamespaceCache = new(); // Cache for namespace existence checks
    private readonly Dictionary<string, string> _typeDeclarationFiles = new(StringComparer.Ordinal);
    // The project's sources, parsed units and declared namespaces, and the project-discovery walk
    // over them. Both are constructed once and never rebuilt: the provider's parsed-unit cache and
    // source snapshot outlive a single Analyze call.
    private readonly AnalyzerProjectSourceProvider _projectSources = new();
    private readonly AnalyzerProjectTypeDiscovery _projectDiscovery;
    // Every semantic diagnostic is constructed here, and every type reference is resolved here. The
    // sink appends to the SAME _errors list the remaining shell reports use, so report order does not
    // depend on which side of the boundary produced a diagnostic. Both are constructed once: the
    // resolver owns the per-analysis dedupe sets and the report opt-in.
    private readonly AnalyzerDiagnosticSink _diagnostics;

    // WHERE A SEMANTIC DIAGNOSTIC POINTS. Constructed over the sink so the span and the rendered
    // snippet are computed against one resolution of the analysed file's text.
    private readonly AnalyzerDiagnosticSpans _spans;

    // The source binder's placement walk plus its reporting arm, both N#-owned.
    private readonly AnalyzerSyntheticCallReporter _syntheticCallReporter;
    // Overload selection, match scoring and generic inference for a call to an N#-declared function,
    // plus the span its constraint reports anchor on. Rebuilt with the owners it reads.
    private AnalyzerSyntheticCallWalk _syntheticCallWalk;
    // Everything the analyzer SAYS about a call to an N#-declared function once the walk has chosen
    // one: arity, argument types, generic constraints, the no-matching-overload report, the SoA
    // intrinsics' value checks and the call's return type. Rebuilt with the walk it reads.
    private AnalyzerSyntheticCallValidator _syntheticCallValidator;
    // Literal and constant SHAPE — the null/default literal and the written negative constant. Reads
    // only the scope stack and the declaration context, both of which outlive every rebuild.
    private readonly AnalyzerConstantExpressionFacts _constantExpressionFacts;
    private readonly AnalyzerTypeResolver _typeResolver;
    // The substitution-aware half of the resolution surface, and the two assignability arms that
    // consult it and the metadata probe. Both are constructed once: neither reads the well-known-type
    // bag, so neither is rebuilt when that bag is built or torn down.
    private readonly AnalyzerTypeSubstitution _typeSubstitution;
    private readonly AnalyzerStructuralAssignability _structuralAssignability;
    // Every FunctionTypeInfo the analyzer builds is built by the factory; assignability is the whole
    // SCC. The factory reads no well-known types and is constructed once; the SCC holds the two
    // owners that ARE rebuilt when the bag changes, so it is rebuilt with them. The re-entrancy
    // guard for user-defined conversions is deliberately NOT part of that rebuild — it is the one
    // piece of state that must outlive an owner.
    private readonly AnalyzerFunctionTypeFactory _functionTypeFactory;
    // What a member NAME resolves to on a declared shape: a declared function's type or method
    // group, the inherited `object` surface, and the SoA table's synthesised intrinsics. Reads only
    // the factory, which is constructed once and never rebuilt, so neither is this.
    private readonly AnalyzerMemberResolution _memberResolution;
    private readonly AnalyzerImplicitConversionGuard _implicitConversionGuard = new();
    private AnalyzerAssignability _assignability;
    // Whether a source extension method accepts a receiver. Rebuilt with the SCC — it holds the
    // assignability owner, which is. The analyzer's own `_extensionMethods`, `_usingNamespaces` and
    // `_mlcAssemblies` are deliberately NOT handed over yet: the members that read them cannot move
    // until `Assembly.GetTypes` is on the columnar surface.
    private AnalyzerExtensionMethodResolution _extensionMethodResolution;
    // The overload scoring kernel's collaborator-backed half. Rebuilt with the SCC: it holds the
    // conversion funnel, the assignability owner and the well-known-type bag, all three of which are.
    private AnalyzerOverloadScoring _overloadScoring;
    // The reflection binder's pure interior: which argument fills which parameter position, how well
    // the candidate matches, and the generic inference that falls out of it. Rebuilt with the SCC —
    // it holds the conversion funnel, the assignability owner, the assignability facts and the
    // scoring kernel, and all four of those are.
    private AnalyzerReflectionArgumentBinder _reflectionArgumentBinder;
    // The source binder's collaborator-backed half: the params comparison shapes, the least upper
    // bound and the generic-inference collecting walk. Rebuilt with the SCC — it holds the
    // declaration context, the scoring kernel, the assignability owner and the conversion funnel.
    private AnalyzerSyntheticCallBinder _syntheticCallBinder;
    private SemanticModel _semanticModel = new(); // Semantic model for IDE features
    private BindingMap _bindingMap = new(); // Binding map for semantic references
    private readonly HashSet<MemberAccessExpression> _soaColumnMemberAccesses = new(ReferenceEqualityComparer.Instance);
    private int _currentLine; // Tracks last analyzed line for scope end positions
    private bool _suppressNullabilityFlowType;
    private bool _suppressErrorTupleResultUse;
    private bool _allowUnboundCallableReference;
    private bool _allowSyntheticSoaOperationReference;
    private bool _analyzingCallCallee;
    // When false (the default), a bare reference to a .NET event is an error — events may only
    // be used with `on`/`off`. AnalyzeOnSubscription and AnalyzeAssignment flip this while
    // resolving the event member so they can emit their own, more specific diagnostics.
    private bool _allowEventReference;
    private readonly HashSet<(int Line, int Column, string Path, string Operation)> _reportedNullabilityDiagnostics = new();
    private readonly HashSet<(int Line, int Column, string Name)> _reportedUnverifiedErrorResultDiagnostics = new();
    // The NL411 report log. Like the implicit-conversion guard above it, this is deliberately NOT
    // part of the toolset rebuild: a log rebuilt with its reader would forget what it had already
    // said and report the same method group twice.
    private readonly AnalyzerCallableReferenceReportLog _callableReferenceReportLog = new();
    // What the analyzer says about a reflected call that bound to nothing, and about a method named
    // where a value is required. Rebuilt with the SCC — it holds the assignability facts.
    private AnalyzerReflectionCallReporter _reflectionCallReporter;
    private bool _disposed;

    public Analyzer()
    {
        _externalTypeProbe = new AnalyzerExternalTypeProbe(_mlcAssemblies, _usingNamespaces);
        _projectDiscovery = new AnalyzerProjectTypeDiscovery(
            _projectSources, _declarationContext, _usingNamespaces, _typeDeclarationFiles);
        _clrTypeConversion = new AnalyzerClrTypeConversion(_declarationContext, _wellKnownTypes);
        _assignabilityFacts = new AnalyzerAssignabilityFacts(_declarationContext, _wellKnownTypes);
        _diagnostics = new AnalyzerDiagnosticSink(_errors, _projectSources);
        _spans = new AnalyzerDiagnosticSpans(_diagnostics);
        _syntheticCallReporter = new AnalyzerSyntheticCallReporter(_diagnostics, _spans);
        _typeResolver = new AnalyzerTypeResolver(
            _scopes,
            _declarationContext,
            _projectDiscovery,
            _externalTypeProbe,
            _diagnostics,
            _usingAliases,
            _importedSymbolsByAlias,
            _importedDeclarationsByAlias,
            _semanticModel,
            _bindingMap);
        _typeSubstitution = new AnalyzerTypeSubstitution(_scopes, _declarationContext, _typeResolver);
        _structuralAssignability = new AnalyzerStructuralAssignability(_typeResolver, _externalTypeProbe);
        _functionTypeFactory = new AnalyzerFunctionTypeFactory(_declarationContext, _typeSubstitution);
        _memberResolution = new AnalyzerMemberResolution(_functionTypeFactory);
        _assignability = CreateAssignability();
        _extensionMethodResolution = CreateExtensionMethodResolution();
        _overloadScoring = CreateOverloadScoring();
        _reflectionArgumentBinder = CreateReflectionArgumentBinder();
        _syntheticCallBinder = CreateSyntheticCallBinder();
        _syntheticCallWalk = CreateSyntheticCallWalk();
        _constantExpressionFacts = new AnalyzerConstantExpressionFacts(_scopes, _declarationContext);
        _syntheticCallValidator = CreateSyntheticCallValidator();
        _reflectionCallReporter = CreateReflectionCallReporter();
    }

    private AnalyzerReflectionCallReporter CreateReflectionCallReporter()
        => new(
            _scopes,
            _declarationContext,
            _assignabilityFacts,
            _spans,
            _diagnostics,
            _callableReferenceReportLog);

    private AnalyzerSyntheticCallValidator CreateSyntheticCallValidator()
        => new(
            _declarationContext,
            _typeResolver,
            _assignability,
            _overloadScoring,
            _syntheticCallWalk,
            _syntheticCallReporter,
            _spans,
            _diagnostics,
            _constantExpressionFacts);

    private AnalyzerSyntheticCallBinder CreateSyntheticCallBinder()
        => new(
            _declarationContext,
            _overloadScoring,
            _assignability,
            _clrTypeConversion);

    private AnalyzerSyntheticCallWalk CreateSyntheticCallWalk()
        => new(
            _typeResolver,
            _syntheticCallBinder,
            _syntheticCallReporter,
            _overloadScoring,
            _assignability,
            _spans,
            _diagnostics);

    private AnalyzerReflectionArgumentBinder CreateReflectionArgumentBinder()
        => new(
            _clrTypeConversion,
            _assignability,
            _assignabilityFacts,
            _overloadScoring,
            _typeResolver);

    private AnalyzerExtensionMethodResolution CreateExtensionMethodResolution()
        => new(_typeResolver, _assignability);

    private AnalyzerAssignability CreateAssignability()
        => new(
            _declarationContext,
            _assignabilityFacts,
            _structuralAssignability,
            _typeSubstitution,
            _clrTypeConversion,
            _implicitConversionGuard);

    private AnalyzerOverloadScoring CreateOverloadScoring()
        => new(
            _declarationContext,
            _clrTypeConversion,
            _assignability,
            _typeResolver,
            _wellKnownTypes);

    private static string GetNuGetPackagesRoot()
    {
        var configuredRoot = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        if (!string.IsNullOrWhiteSpace(configuredRoot))
        {
            return Path.GetFullPath(configuredRoot);
        }

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".nuget",
            "packages");
    }

    /// <summary>
    /// Sets the source texts used by the current project snapshot. This lets semantic
    /// declarations point at identifier spans even when a referenced file is only
    /// present through an unsaved editor buffer.
    /// </summary>
    public void SetProjectSourceTexts(IReadOnlyDictionary<string, string> sourceTexts)
    {
        _projectSources.ResetSourceTexts();
        foreach (var (path, text) in sourceTexts)
        {
            _projectSources.AddSourceText(path, text);
        }
    }

    /// <summary>
    /// Get a snapshot of the type-declaration-to-file mapping recorded during the most recent Analyze() call.
    /// Used by MultiFileCompiler to build the project-level ProjectIndex.
    /// </summary>
    public Dictionary<string, string> GetTypeDeclarationFiles() => new(_typeDeclarationFiles);

    public AnalysisResult Analyze(CompilationUnit unit)
    {
        return Analyze(unit, null, null, null);
    }

    private void InitializeDeclarationContext(
        CompilationUnit unit,
        string? currentFilePath,
        string? projectRoot)
    {
        var contextRoot = !string.IsNullOrWhiteSpace(projectRoot)
            ? projectRoot
            : !string.IsNullOrWhiteSpace(currentFilePath)
                ? Path.GetDirectoryName(Path.GetFullPath(currentFilePath))
                : null;
        var effectiveRoot = contextRoot ?? Directory.GetCurrentDirectory();
        _declarationContextFilePath = !string.IsNullOrWhiteSpace(currentFilePath)
            ? Path.GetFullPath(currentFilePath)
            : Path.Combine(effectiveRoot, ".nsharp-analyzer-memory.nl");
        _declarationContext.Reset(effectiveRoot, _mlcAssemblies);
        _declarationContext.AddCompilationUnit(_declarationContextFilePath, unit);

        _projectSources.AddProjectUnitsTo(_declarationContext);
    }

    public AnalysisResult Analyze(CompilationUnit unit, string? currentFilePath, string? projectRoot, string? sourceCode = null)
    {
        _errors.Clear();
        _scopes.Clear();
        _usingNamespaces.Clear();
        _usingAliases.Clear();
        _importedSymbols.Clear();
        _importedSymbolsByAlias.Clear();
        _importedDeclarationsByAlias.Clear();
        _implicitConversionGuard.Clear();
        _extensionMethods.Clear();
        _semanticModel = new SemanticModel();  // Reset semantic model for new analysis
        _bindingMap = new BindingMap(); // Reset binding map for new analysis
        _soaColumnMemberAccesses.Clear();
        _currentLine = 0;
        _suppressNullabilityFlowType = false;
        _suppressErrorTupleResultUse = false;
        _reportedNullabilityDiagnostics.Clear();
        _reportedUnverifiedErrorResultDiagnostics.Clear();
        _currentReturnType = null;
        _currentFunction = null;
        _currentFunctionReturnTypeWasOmitted = false;
        _currentFunctionIsAsync = false;
        _inLoop = false;
        _finallyDepth = 0;
        _breakTargetFinallyDepth = 0;
        _continueTargetFinallyDepth = 0;
        _inConstructor = false;
        _currentFilePath = currentFilePath;
        _projectSources.BeginAnalysis(projectRoot);
        _compilationUnit = unit;
        _sourceText = sourceCode;
        _diagnostics.BeginAnalysis(currentFilePath, sourceCode);
        _typeResolver.BeginAnalysis(currentFilePath, unit, _semanticModel, _bindingMap);
        _externalNamespaceCache.Clear();
        _typeDeclarationFiles.Clear();

        InitializeDeclarationContext(unit, currentFilePath, projectRoot);

        // Process import directives
        foreach (var importDirective in unit.Imports)
        {
            RegisterNamespaceImport(importDirective.Namespace, importDirective.Alias, importDirective.Line, importDirective.Column);
        }

        // Validate package declaration if present
        if (unit.Package != null)
        {
            ValidatePackageName(unit.Package);
        }

        // Create global scope first (needed for adding imported symbols)
        PushScope(new Scope(ScopeKind.Global), 1, 1);

        // Process file imports (adds symbols to global scope)
        if (unit.FileImports.Count > 0)
        {
            ProcessImports(unit.FileImports);
        }

        // Check for import collisions
        CheckImportCollisions();

        // First pass: collect all type declarations and function signatures
        foreach (var decl in unit.Declarations)
        {
            if (decl is ClassDeclaration classDecl)
                DeclareType(classDecl.Name, NominalTypeInfoFactory.FromClassDeclaration(classDecl), decl.Line, decl.Column);
            else if (decl is StructDeclaration structDecl)
                DeclareType(structDecl.Name, NominalTypeInfoFactory.FromStructDeclaration(structDecl), decl.Line, decl.Column);
            else if (decl is RecordDeclaration recordDecl)
                DeclareType(recordDecl.Name, NominalTypeInfoFactory.FromRecordDeclaration(recordDecl), decl.Line, decl.Column);
            else if (decl is SoaRecordDeclaration soaRecordDecl)
                DeclareType(soaRecordDecl.Name, SoaTypeInfoFactory.FromDeclaration(soaRecordDecl), decl.Line, decl.Column);
            else if (decl is InterfaceDeclaration interfaceDecl)
                DeclareType(interfaceDecl.Name, NominalTypeInfoFactory.FromInterfaceDeclaration(interfaceDecl), decl.Line, decl.Column);
            else if (decl is UnionDeclaration unionDecl)
                DeclareType(unionDecl.Name, UnionTypeInfoFactory.FromDeclaration(unionDecl), decl.Line, decl.Column);
            else if (decl is EnumDeclaration enumDecl)
                DeclareType(enumDecl.Name, EnumTypeInfoFactory.FromDeclaration(enumDecl), decl.Line, decl.Column);
            else if (decl is TypeAliasDeclaration aliasDecl)
                DeclareType(aliasDecl.Name, new AliasTypeInfo(aliasDecl.Type), decl.Line, decl.Column);
            else if (decl is NewtypeDeclaration newtypeDecl)
                DeclareType(newtypeDecl.Name, new NewtypeInfo(newtypeDecl.Name, newtypeDecl.UnderlyingType), decl.Line, decl.Column);
            else if (decl is FunctionDeclaration func)
            {
                // Add function signatures to enable forward references
                var funcTypeInfo = _functionTypeFactory.CreateFromDeclaration(func, _currentTypeName);
                DeclareSymbol(func.Name, funcTypeInfo, func.Line, func.Column);
            }
        }

        // Validate and collect setup/teardown blocks (only one of each allowed)
        _setupSymbols = new List<(string Name, TypeInfo Type, int Line, int Column)>();
        bool foundSetup = false;
        bool foundTeardown = false;
        foreach (var decl in unit.Declarations)
        {
            if (decl is SetupDeclaration setup)
            {
                if (foundSetup)
                {
                    Error(
                        ErrorCode.DuplicateDeclaration,
                        "Only one setup block is allowed per test file",
                        setup.Line,
                        setup.Column,
                        length: "setup".Length);
                }
                else
                {
                    foundSetup = true;
                    CollectSetupSymbols(setup);
                }
            }
            else if (decl is TeardownDeclaration teardown)
            {
                if (foundTeardown)
                {
                    Error(
                        ErrorCode.DuplicateDeclaration,
                        "Only one teardown block is allowed per test file",
                        teardown.Line,
                        teardown.Column,
                        length: "teardown".Length);
                }
                foundTeardown = true;
            }
        }

        // Second pass: analyze all declarations
        foreach (var decl in unit.Declarations)
        {
            _currentLine = decl.Line;
            AnalyzeDeclaration(decl);
        }

        PopScope();

        ReportReferenceLoadFailures();

        return new AnalysisResult(_errors, _semanticModel, _bindingMap);
    }

    /// <summary>
    /// Surfaces recorded reference-load failures as NL923 warnings, but only when this
    /// analysis also produced unresolved-type errors. A reference assembly that fails to
    /// load is the classic root cause behind misleading "type not found" diagnostics; pairing
    /// the two makes the failure diagnosable. Healthy compilations stay quiet even if a
    /// best-effort probe failed along the way.
    /// </summary>
    private void ReportReferenceLoadFailures()
    {
        var resolverFailures = _metadataResolver?.LoadFailures;
        if (_referenceLoadFailures.Count == 0 && (resolverFailures == null || resolverFailures.Count == 0))
            return;

        var hasUnresolvedTypeError = _errors.Any(e =>
            e.Severity == ErrorSeverity.Error &&
            e.Code is ErrorCode.TypeNotFound
                or ErrorCode.CannotResolveType
                or ErrorCode.UndefinedType
                or ErrorCode.UndefinedVariable);
        if (!hasUnresolvedTypeError)
            return;

        var failures = new SortedDictionary<string, string>(_referenceLoadFailures, StringComparer.Ordinal);
        if (resolverFailures != null)
        {
            foreach (var (identity, detail) in resolverFailures)
                failures.TryAdd(identity, detail);
        }

        foreach (var (identity, detail) in failures)
        {
            Warning(
                ErrorCode.ReferenceLoadFailure,
                $"Reference assembly '{identity}' could not be loaded or fully inspected ({detail}); types from it may be reported as not found.",
                1, 1);
        }
    }

    private void AnalyzeDeclaration(Declaration decl)
    {
        ValidateDeclarationAttributeArguments(decl);

        switch (decl)
        {
            case TestDeclaration test:
                AnalyzeTestDeclaration(test);
                break;
            case SetupDeclaration setup:
                AnalyzeSetupDeclaration(setup);
                break;
            case TeardownDeclaration teardown:
                AnalyzeTeardownDeclaration(teardown);
                break;
            case FunctionDeclaration func:
                AnalyzeFunctionDeclaration(func);
                break;
            case ClassDeclaration classDecl:
                AnalyzeClassDeclaration(classDecl);
                break;
            case StructDeclaration structDecl:
                AnalyzeStructDeclaration(structDecl);
                break;
            case RecordDeclaration recordDecl:
                AnalyzeRecordDeclaration(recordDecl);
                break;
            case SoaRecordDeclaration soaRecordDecl:
                AnalyzeSoaRecordDeclaration(soaRecordDecl);
                break;
            case InterfaceDeclaration interfaceDecl:
                AnalyzeInterfaceDeclaration(interfaceDecl);
                break;
            case UnionDeclaration unionDecl:
                AnalyzeUnionDeclaration(unionDecl);
                break;
            case EnumDeclaration enumDecl:
                AnalyzeEnumDeclaration(enumDecl);
                break;
            case TypeAliasDeclaration aliasDecl:
                _typeResolver.ResolveDeclaredType(aliasDecl.Type);
                break;
            case NewtypeDeclaration newtypeDecl:
                _typeResolver.ResolveDeclaredType(newtypeDecl.UnderlyingType);
                break;
            case FieldDeclaration field:
                AnalyzeFieldDeclaration(field);
                break;
            case PropertyDeclaration prop:
                AnalyzePropertyDeclaration(prop);
                break;
            case ConstructorDeclaration ctor:
                AnalyzeConstructorDeclaration(ctor);
                break;
            case IndexerDeclaration indexer:
                AnalyzeIndexerDeclaration(indexer);
                break;
            case PreprocessorDeclaration:
                // Preprocessor directives don't need analysis - they're pass-through
                break;
        }
    }

    private sealed record AttributeArgumentValidationInfo(
        Argument Argument,
        string? Name,
        Expression Value,
        Type? ClrType,
        bool IsNull);

    private void ValidateDeclarationAttributeArguments(Declaration decl)
    {
        switch (decl)
        {
            case TestDeclaration test:
                ValidateParameterAttributeArguments(test.TableParameters);
                break;
            case FunctionDeclaration func:
                ValidateAttributeArguments(func.Attributes);
                ValidateParameterAttributeArguments(func.Parameters);
                break;
            case ClassDeclaration classDecl:
                ValidateAttributeArguments(classDecl.Attributes);
                ValidateParameterAttributeArguments(classDecl.PrimaryConstructorParameters);
                break;
            case StructDeclaration structDecl:
                ValidateAttributeArguments(structDecl.Attributes);
                ValidateParameterAttributeArguments(structDecl.PrimaryConstructorParameters);
                break;
            case RecordDeclaration recordDecl:
                ValidateAttributeArguments(recordDecl.Attributes);
                ValidateParameterAttributeArguments(recordDecl.PrimaryConstructorParameters);
                break;
            case SoaRecordDeclaration soaRecordDecl:
                ValidateAttributeArguments(soaRecordDecl.Attributes);
                break;
            case InterfaceDeclaration interfaceDecl:
                ValidateAttributeArguments(interfaceDecl.Attributes);
                break;
            case UnionDeclaration unionDecl:
                ValidateAttributeArguments(unionDecl.Attributes);
                break;
            case EnumDeclaration enumDecl:
                ValidateAttributeArguments(enumDecl.Attributes);
                break;
            case FieldDeclaration field:
                ValidateAttributeArguments(field.Attributes);
                break;
            case PropertyDeclaration prop:
                ValidateAttributeArguments(prop.Attributes);
                break;
            case ConstructorDeclaration ctor:
                ValidateAttributeArguments(ctor.Attributes);
                ValidateParameterAttributeArguments(ctor.Parameters);
                break;
            case IndexerDeclaration indexer:
                ValidateAttributeArguments(indexer.Attributes);
                ValidateParameterAttributeArguments(indexer.Parameters);
                break;
        }
    }

    private void ValidateParameterAttributeArguments(IEnumerable<Parameter>? parameters)
    {
        if (parameters == null)
        {
            return;
        }

        foreach (var parameter in parameters)
        {
            ValidateAttributeArguments(parameter.Attributes);
        }
    }

    private void ValidateAttributeArguments(IEnumerable<AttributeNode>? attributes)
    {
        if (attributes == null)
        {
            return;
        }

        foreach (var attribute in attributes)
        {
            if (IsSystemsPolicyAttribute(attribute))
            {
                continue;
            }

            var argumentInfos = new List<AttributeArgumentValidationInfo>(attribute.Arguments.Count);
            var allConstantsValid = true;
            foreach (var argument in attribute.Arguments)
            {
                var (argumentName, valueExpression) = NormalizeAttributeArgument(argument);
                if (!TryValidateAttributeArgumentExpression(valueExpression, out _))
                {
                    allConstantsValid = false;
                    argumentInfos.Add(new AttributeArgumentValidationInfo(argument, argumentName, valueExpression, null, false));
                    continue;
                }

                var hasClrType = TryInferAttributeArgumentClrType(valueExpression, out var clrType, out var isNull);
                argumentInfos.Add(new AttributeArgumentValidationInfo(
                    argument,
                    argumentName,
                    valueExpression,
                    hasClrType ? clrType : null,
                    isNull));
            }

            if (TryResolveClrAttributeType(attribute.Name, out var attributeType))
            {
                if (allConstantsValid)
                {
                    ValidateClrAttributeArguments(attribute, attributeType, argumentInfos);
                }
            }
            else if (TryResolveNonAttributeClrAttributeCandidate(attribute.Name, out var nonAttributeType))
            {
                ReportAttributeTypeMustDeriveFromAttribute(attribute, NullabilityMetadataReflection.FormatType(nonAttributeType));
            }
            else if (TryResolveSourceAttributeCandidate(attribute.Name, out var sourceType))
            {
                if (SourceTypeDerivesFromAttribute(sourceType))
                {
                    ReportSourceDefinedAttributeUnsupported(attribute);
                }
                else
                {
                    ReportAttributeTypeMustDeriveFromAttribute(attribute, sourceType.ToString() ?? attribute.Name);
                }
            }
            else
            {
                ReportAttributeTypeNotFound(attribute);
            }
        }
    }

    private static bool IsSystemsPolicyAttribute(AttributeNode attribute)
    {
        var policyName = attribute.Name;
        if (policyName.Contains('.', StringComparison.Ordinal))
        {
            return false;
        }

        if (policyName.EndsWith("Attribute", StringComparison.Ordinal))
        {
            policyName = policyName[..^"Attribute".Length];
        }

        return policyName is "hot" or "boundary" or "alloc" or "allow" or "trusted" or "memory" or "aotSafe" or "MustUse";
    }

    private static (string? Name, Expression Value) NormalizeAttributeArgument(Argument argument)
    {
        var argumentName = argument.Name;
        var valueExpression = argument.Value;
        if (argumentName == null
            && valueExpression is AssignmentExpression assignment
            && assignment.Target is IdentifierExpression identifier)
        {
            argumentName = identifier.Name;
            valueExpression = assignment.Value;
        }

        return (argumentName, valueExpression);
    }

    private bool TryValidateAttributeArgumentExpression(
        Expression expression,
        out AttributeArgumentConstantKind kind)
    {
        switch (expression)
        {
            case IntLiteralExpression:
                kind = AttributeArgumentConstantKind.Integer;
                return true;
            case FloatLiteralExpression:
                kind = AttributeArgumentConstantKind.Floating;
                return true;
            case CharLiteralExpression:
                kind = AttributeArgumentConstantKind.Char;
                return true;
            case StringLiteralExpression:
                kind = AttributeArgumentConstantKind.String;
                return true;
            case BoolLiteralExpression:
                kind = AttributeArgumentConstantKind.Bool;
                return true;
            case NullLiteralExpression:
                kind = AttributeArgumentConstantKind.Null;
                return true;
            case TypeOfExpression typeOfExpression:
                ReportSoaRowTypeReferencesInAttributeTypeof(typeOfExpression.Type);
                kind = AttributeArgumentConstantKind.Type;
                return true;
            case NameofExpression nameofExpression:
                if (IsSupportedNameofAttributeTarget(nameofExpression.Target))
                {
                    kind = AttributeArgumentConstantKind.String;
                    return true;
                }

                ReportUnsupportedAttributeArgument(nameofExpression.Target, "nameof target");
                kind = AttributeArgumentConstantKind.String;
                return false;
            case MemberAccessExpression memberAccess:
                return TryValidateAttributeMemberAccess(memberAccess, out kind);
            case ArrayLiteralExpression arrayLiteral:
                return TryValidateAttributeArrayArgument(arrayLiteral, out kind);
            case UnaryExpression unary:
                return TryValidateAttributeUnaryArgument(unary, out kind);
            case BinaryExpression binary:
                return TryValidateAttributeBinaryArgument(binary, out kind);
            default:
                ReportUnsupportedAttributeArgument(expression, DescribeAttributeArgumentForDiagnostic(expression));
                kind = AttributeArgumentConstantKind.UnknownStaticMember;
                return false;
        }
    }

    private void ReportSoaRowTypeReferencesInAttributeTypeof(TypeReference typeReference)
    {
        switch (typeReference)
        {
            case SimpleTypeReference simple:
                _typeResolver.ReportSoaRowTypeReferenceIfNeeded(simple.Name, simple.Line, simple.Column);
                break;
            case GenericTypeReference generic:
                _typeResolver.ReportSoaRowTypeReferenceIfNeeded(generic.Name, generic.Line, generic.Column);
                foreach (var argument in generic.TypeArguments)
                {
                    ReportSoaRowTypeReferencesInAttributeTypeof(argument);
                }
                break;
            case ArrayTypeReference array:
                ReportSoaRowTypeReferencesInAttributeTypeof(array.ElementType);
                break;
            case NullableTypeReference nullable:
                ReportSoaRowTypeReferencesInAttributeTypeof(nullable.InnerType);
                break;
            case UnionTypeReference union:
                foreach (var arm in union.Arms)
                {
                    ReportSoaRowTypeReferencesInAttributeTypeof(arm);
                }
                break;
            case TupleTypeReference tuple:
                foreach (var element in tuple.Elements)
                {
                    ReportSoaRowTypeReferencesInAttributeTypeof(element.Type);
                }
                break;
            case FunctionTypeReference function:
                foreach (var parameterType in function.ParameterTypes)
                {
                    ReportSoaRowTypeReferencesInAttributeTypeof(parameterType);
                }

                ReportSoaRowTypeReferencesInAttributeTypeof(function.ReturnType);
                break;
            case ByRefTypeReference byRef:
                ReportSoaRowTypeReferencesInAttributeTypeof(byRef.InnerType);
                break;
        }
    }

    private bool TryValidateAttributeArrayArgument(
        ArrayLiteralExpression arrayLiteral,
        out AttributeArgumentConstantKind kind)
    {
        kind = AttributeArgumentConstantKind.Array;
        AttributeArgumentConstantKind? elementKind = null;
        var valid = true;
        foreach (var element in arrayLiteral.Elements)
        {
            if (!TryValidateAttributeArgumentExpression(element, out var currentKind))
            {
                valid = false;
                continue;
            }

            if (currentKind == AttributeArgumentConstantKind.Null)
            {
                continue;
            }

            elementKind ??= currentKind;
            if (elementKind != currentKind)
            {
                ReportUnsupportedAttributeArgument(
                    element,
                    "mixed-type array element");
                valid = false;
            }
        }

        return valid;
    }

    private bool TryValidateAttributeUnaryArgument(
        UnaryExpression unary,
        out AttributeArgumentConstantKind kind)
    {
        if (!TryValidateAttributeArgumentExpression(unary.Operand, out var operandKind))
        {
            kind = operandKind;
            return false;
        }

        if (unary.Operator == UnaryOperator.Negate
            && operandKind is AttributeArgumentConstantKind.Integer or AttributeArgumentConstantKind.Floating)
        {
            kind = operandKind;
            return true;
        }

        if (unary.Operator == UnaryOperator.Not && operandKind == AttributeArgumentConstantKind.Bool)
        {
            kind = AttributeArgumentConstantKind.Bool;
            return true;
        }

        if (unary.Operator == UnaryOperator.BitwiseNot && operandKind == AttributeArgumentConstantKind.Integer)
        {
            kind = AttributeArgumentConstantKind.Integer;
            return true;
        }

        ReportUnsupportedAttributeOperator(unary, OperatorFacts.GetUnaryText(unary.Operator));
        kind = operandKind;
        return false;
    }

    private bool TryValidateAttributeBinaryArgument(
        BinaryExpression binary,
        out AttributeArgumentConstantKind kind)
    {
        var leftValid = TryValidateAttributeArgumentExpression(binary.Left, out var leftKind);
        var rightValid = TryValidateAttributeArgumentExpression(binary.Right, out var rightKind);
        kind = leftKind;
        if (!leftValid || !rightValid)
        {
            return false;
        }

        if (binary.Operator is not (BinaryOperator.BitwiseOr or BinaryOperator.BitwiseAnd or BinaryOperator.BitwiseXor))
        {
            ReportUnsupportedAttributeOperator(binary, OperatorFacts.GetBinaryText(binary.Operator));
            return false;
        }

        if ((leftKind == AttributeArgumentConstantKind.Integer && rightKind == AttributeArgumentConstantKind.Integer)
            || (leftKind == AttributeArgumentConstantKind.Enum && rightKind == AttributeArgumentConstantKind.Enum)
            || leftKind == AttributeArgumentConstantKind.UnknownStaticMember
            || rightKind == AttributeArgumentConstantKind.UnknownStaticMember)
        {
            kind = leftKind == AttributeArgumentConstantKind.Enum || rightKind == AttributeArgumentConstantKind.Enum
                ? AttributeArgumentConstantKind.Enum
                : AttributeArgumentConstantKind.Integer;
            return true;
        }

        ReportUnsupportedAttributeOperator(binary, OperatorFacts.GetBinaryText(binary.Operator));
        return false;
    }

    private bool TryValidateAttributeMemberAccess(
        MemberAccessExpression memberAccess,
        out AttributeArgumentConstantKind kind)
    {
        if (!TryGetQualifiedAttributeName(memberAccess.Object, out var containerName))
        {
            ReportUnsupportedAttributeArgument(memberAccess, "member access");
            kind = AttributeArgumentConstantKind.UnknownStaticMember;
            return false;
        }

        var resolvedType = _declarationContext.ResolveDeclaredAlias(_scopes.LookupType(containerName) ?? BuiltInTypes.Unknown);
        if (resolvedType is EnumTypeInfo enumType)
        {
            if (!HasSourceEnumMember(enumType, memberAccess.MemberName))
            {
                ReportUndefinedAttributeStaticMember(enumType, memberAccess);
                kind = AttributeArgumentConstantKind.UnknownStaticMember;
                return false;
            }

            kind = AttributeArgumentConstantKind.Enum;
            return true;
        }

        if (AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(_wellKnownTypes, containerName) is { } builtInType)
        {
            return TryValidateAttributeRuntimeStaticMemberAccess(
                new ReflectionTypeInfo(builtInType),
                builtInType,
                memberAccess,
                out kind);
        }

        if (_externalTypeProbe.ResolveExternalType(containerName) is ReflectionTypeInfo reflectionType)
        {
            return TryValidateAttributeRuntimeStaticMemberAccess(
                reflectionType,
                reflectionType.Type,
                memberAccess,
                out kind);
        }

        if (!BuiltInTypes.IsUnknown(resolvedType))
        {
            kind = AttributeArgumentConstantKind.UnknownStaticMember;
            return true;
        }

        ReportUnsupportedAttributeArgument(memberAccess, "member access");
        kind = AttributeArgumentConstantKind.UnknownStaticMember;
        return false;
    }

    private bool TryValidateAttributeRuntimeStaticMemberAccess(
        ReflectionTypeInfo receiverType,
        Type runtimeType,
        MemberAccessExpression memberAccess,
        out AttributeArgumentConstantKind kind)
    {
        if (IsRuntimeEnumType(runtimeType))
        {
            if (!HasRuntimeEnumMember(runtimeType, memberAccess.MemberName))
            {
                ReportUndefinedAttributeStaticMember(receiverType, memberAccess);
                kind = AttributeArgumentConstantKind.UnknownStaticMember;
                return false;
            }

            kind = AttributeArgumentConstantKind.Enum;
            return true;
        }

        if (!TryGetRuntimeStaticAttributeMemberType(runtimeType, memberAccess.MemberName, out var memberType))
        {
            ReportUndefinedAttributeStaticMember(receiverType, memberAccess);
            kind = AttributeArgumentConstantKind.UnknownStaticMember;
            return false;
        }

        kind = ClassifyAttributeRuntimeType(memberType);
        return true;
    }

    private static bool HasSourceEnumMember(EnumTypeInfo enumType, string memberName)
        => enumType.Declaration.Members.Any(member => string.Equals(member.Name, memberName, StringComparison.Ordinal));

    private static bool HasRuntimeEnumMember(Type enumType, string memberName)
        => enumType.GetField(memberName, BindingFlags.Public | BindingFlags.Static) != null;

    private void ReportUndefinedAttributeStaticMember(TypeInfo receiverType, MemberAccessExpression memberAccess)
        => ReportUndefinedMember(
            receiverType,
            memberAccess.MemberName,
            memberAccess.Line,
            _spans.GetMemberNameColumn(memberAccess),
            includeStaticMembers: true);

    private static AttributeArgumentConstantKind ClassifyAttributeRuntimeType(Type type)
    {
        if (type.IsArray)
        {
            return AttributeArgumentConstantKind.Array;
        }

        if (IsRuntimeEnumType(type))
        {
            return AttributeArgumentConstantKind.Enum;
        }

        return type.FullName switch
        {
            "System.Boolean" => AttributeArgumentConstantKind.Bool,
            "System.Byte" or "System.SByte" or "System.Int16" or "System.UInt16"
                or "System.Int32" or "System.UInt32" or "System.Int64" or "System.UInt64" => AttributeArgumentConstantKind.Integer,
            "System.Single" or "System.Double" or "System.Decimal" => AttributeArgumentConstantKind.Floating,
            "System.Char" => AttributeArgumentConstantKind.Char,
            "System.String" => AttributeArgumentConstantKind.String,
            "System.Type" => AttributeArgumentConstantKind.Type,
            _ => AttributeArgumentConstantKind.UnknownStaticMember
        };
    }

    private static bool IsRuntimeEnumType(Type type)
        => type.IsEnum || type.BaseType?.FullName == "System.Enum";

    private static bool IsSupportedNameofAttributeTarget(Expression target)
        => target switch
        {
            IdentifierExpression => true,
            MemberAccessExpression { IsNullConditional: false } memberAccess => IsSupportedNameofAttributeTarget(memberAccess.Object),
            _ => false
        };

    private static bool TryGetQualifiedAttributeName(Expression expression, out string name)
    {
        switch (expression)
        {
            case IdentifierExpression identifier:
                name = identifier.Name;
                return true;
            case MemberAccessExpression { IsNullConditional: false } memberAccess
                when TryGetQualifiedAttributeName(memberAccess.Object, out var parentName):
                name = $"{parentName}.{memberAccess.MemberName}";
                return true;
            default:
                name = string.Empty;
                return false;
        }
    }

    private void ReportUnsupportedAttributeArgument(Expression expression, string description)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.ConstantRequired,
            $"Attribute arguments must be compile-time constants; {description} is not supported here",
            line,
            column,
            "Use a literal, typeof(...), nameof(...), enum/static constant, or an array of those constants.",
            length);
    }

    private string DescribeAttributeArgumentForDiagnostic(Expression expression)
    {
        var description = DescribeExpressionForDiagnostic(expression);
        return expression switch
        {
            IdentifierExpression => "identifier",
            MemberAccessExpression => "member access",
            _ when description.Contains(' ', StringComparison.Ordinal) => description,
            _ => $"{char.ToLowerInvariant(description[0])}{description[1..]} expression"
        };
    }

    private void ReportUnsupportedAttributeOperator(Expression expression, string operatorText)
    {
        var (line, column, length) = expression is BinaryExpression binary
            ? AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(binary)
            : _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.ConstantRequired,
            $"Attribute arguments must be compile-time constants; operator '{operatorText}' is not supported here",
            line,
            column,
            "Use a literal, typeof(...), nameof(...), enum/static constant, or an array of those constants.",
            length);
    }

    private bool TryResolveClrAttributeType(string attributeName, [NotNullWhen(true)] out Type? attributeType)
    {
        foreach (var candidate in GetClrAttributeNameCandidates(attributeName))
        {
            if (_externalTypeProbe.ResolveExternalType(candidate) is ReflectionTypeInfo { Type: var resolvedType }
                && IsClrAttributeType(resolvedType))
            {
                attributeType = resolvedType;
                return true;
            }
        }

        attributeType = null;
        return false;
    }

    private bool TryResolveNonAttributeClrAttributeCandidate(string attributeName, [NotNullWhen(true)] out Type? type)
    {
        foreach (var candidate in GetClrAttributeNameCandidates(attributeName))
        {
            if (_externalTypeProbe.ResolveExternalType(candidate) is ReflectionTypeInfo { Type: var resolvedType })
            {
                type = resolvedType;
                return true;
            }
        }

        type = null;
        return false;
    }

    private bool TryResolveSourceAttributeCandidate(string attributeName, [NotNullWhen(true)] out TypeInfo? type)
    {
        foreach (var candidate in GetClrAttributeNameCandidates(attributeName))
        {
            var candidateType = _scopes.LookupType(candidate);
            if (candidateType == null && _typeResolver.TryResolveDottedNestedType(candidate, out var nestedType))
            {
                candidateType = nestedType;
            }

            if (candidateType != null)
            {
                candidateType = _declarationContext.ResolveDeclaredAlias(candidateType);
                if (IsSourceDeclaredAttributeCandidate(candidateType))
                {
                    type = candidateType;
                    return true;
                }
            }
        }

        type = null;
        return false;
    }

    private static bool IsSourceDeclaredAttributeCandidate(TypeInfo type)
        => type is ClassTypeInfo
            or StructTypeInfo
            or RecordTypeInfo
            or InterfaceTypeInfo
            or UnionTypeInfo
            or EnumTypeInfo
            or SoaRecordTypeInfo
            or NewtypeInfo;

    private static bool IsClrAttributeType(Type type)
    {
        for (var current = type; current != null; current = current.BaseType)
        {
            if (string.Equals(current.FullName, "System.Attribute", StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private static IEnumerable<string> GetClrAttributeNameCandidates(string attributeName)
    {
        yield return attributeName;
        if (!attributeName.EndsWith("Attribute", StringComparison.Ordinal))
        {
            yield return attributeName + "Attribute";
        }
    }

    private bool SourceTypeDerivesFromAttribute(TypeInfo type)
        => SourceTypeDerivesFromAttribute(type, new HashSet<object>());

    private bool SourceTypeDerivesFromAttribute(TypeInfo type, HashSet<object> seenClasses)
    {
        type = _declarationContext.ResolveDeclaredAlias(type);
        if (type is ReflectionTypeInfo { Type: var reflectionType })
        {
            return IsClrAttributeType(reflectionType);
        }

        if (type is not ClassTypeInfo classType)
        {
            return false;
        }

        if (!seenClasses.Add(classType)
            || !_declarationContext.TryGetSourceMemberShape(classType, null, out var shape)
            || shape.BaseType == null)
        {
            return false;
        }

        var baseType = _declarationContext.ResolveDeclaredAlias(shape.BaseType);
        return baseType is ReflectionTypeInfo { Type: var baseReflectionType } && IsClrAttributeType(baseReflectionType)
            || SourceTypeDerivesFromAttribute(baseType, seenClasses);
    }

    private void ReportAttributeTypeNotFound(AttributeNode attribute)
    {
        var (line, column, length) = AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute);
        var suggestedAttributeName = attribute.Name.EndsWith("Attribute", StringComparison.Ordinal)
            ? attribute.Name
            : attribute.Name + "Attribute";
        Error(
            ErrorCode.TypeNotFound,
            $"Attribute type '{attribute.Name}' not found",
            line,
            column,
            $"Check the spelling, add the missing 'import', or define an attribute class named '{suggestedAttributeName}'.",
            length);
    }

    private void ReportAttributeTypeMustDeriveFromAttribute(AttributeNode attribute, string typeName)
    {
        var (line, column, length) = AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute);
        Error(
            ErrorCode.TypeMismatch,
            $"Attribute type '{typeName}' must derive from System.Attribute",
            line,
            column,
            "Use a CLR attribute type or define a class that inherits System.Attribute.",
            length);
    }

    private void ReportSourceDefinedAttributeUnsupported(AttributeNode attribute)
    {
        var (line, column, length) = AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute);
        Error(
            ErrorCode.FeatureNotImplemented,
            $"Source-defined attribute '{attribute.Name}' is not supported by IL emission yet",
            line,
            column,
            "Use an attribute type from a referenced CLR assembly for now.",
            length);
    }

    private void ValidateClrAttributeArguments(
        AttributeNode attribute,
        Type attributeType,
        IReadOnlyList<AttributeArgumentValidationInfo> argumentInfos)
    {
        foreach (var argumentInfo in argumentInfos)
        {
            if (argumentInfo.Name == null)
            {
                continue;
            }

            if (!TryGetSettableAttributeNamedMemberType(attributeType, argumentInfo.Name, out var memberType))
            {
                ReportUnknownAttributeNamedArgument(attributeType, argumentInfo);
                continue;
            }

            if (argumentInfo.ClrType != null
                && !IsAttributeArgumentCompatible(memberType, argumentInfo.ClrType, argumentInfo.IsNull))
            {
                ReportAttributeNamedArgumentTypeMismatch(attributeType, argumentInfo, memberType);
            }
        }

        var positionalArguments = argumentInfos
            .Where(argumentInfo => argumentInfo.Name == null)
            .ToList();
        if (positionalArguments.Any(argumentInfo => argumentInfo.ClrType == null))
        {
            return;
        }

        if (!HasMatchingAttributeConstructor(attributeType, positionalArguments))
        {
            ReportNoMatchingAttributeConstructor(attribute, attributeType, positionalArguments);
        }
    }

    private static bool TryGetSettableAttributeNamedMemberType(
        Type attributeType,
        string memberName,
        [NotNullWhen(true)] out Type? memberType)
    {
        var property = attributeType.GetProperty(memberName, BindingFlags.Public | BindingFlags.Instance);
        if (property is { SetMethod.IsPublic: true } && property.GetIndexParameters().Length == 0)
        {
            memberType = property.PropertyType;
            return true;
        }

        var field = attributeType.GetField(memberName, BindingFlags.Public | BindingFlags.Instance);
        if (field != null && !field.IsInitOnly && !field.IsLiteral)
        {
            memberType = field.FieldType;
            return true;
        }

        memberType = null;
        return false;
    }

    private static bool HasMatchingAttributeConstructor(
        Type attributeType,
        IReadOnlyList<AttributeArgumentValidationInfo> positionalArguments)
    {
        foreach (var constructor in attributeType.GetConstructors(BindingFlags.Public | BindingFlags.Instance))
        {
            var parameters = constructor.GetParameters();
            if (parameters.Length != positionalArguments.Count)
            {
                continue;
            }

            var matches = true;
            for (var i = 0; i < parameters.Length; i++)
            {
                if (!IsAttributeArgumentCompatible(
                    parameters[i].ParameterType,
                    positionalArguments[i].ClrType!,
                    positionalArguments[i].IsNull))
                {
                    matches = false;
                    break;
                }
            }

            if (matches)
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsAttributeArgumentCompatible(Type parameterType, Type argumentType, bool isNull)
    {
        if (isNull)
        {
            return !parameterType.IsValueType || Nullable.GetUnderlyingType(parameterType) != null;
        }

        if (parameterType == argumentType || parameterType.IsAssignableFrom(argumentType))
        {
            return true;
        }

        if (TryGetRuntimeEnumUnderlyingType(parameterType) == argumentType)
        {
            return true;
        }

        if (parameterType.IsArray && argumentType.IsArray)
        {
            var parameterElementType = parameterType.GetElementType()!;
            var argumentElementType = argumentType.GetElementType()!;
            return parameterElementType == argumentElementType
                || parameterElementType.IsAssignableFrom(argumentElementType)
                || TryGetRuntimeEnumUnderlyingType(parameterElementType) == argumentElementType;
        }

        return false;
    }

    private static Type? TryGetRuntimeEnumUnderlyingType(Type type)
        => type.IsEnum ? Enum.GetUnderlyingType(type) : null;

    private void ReportUnknownAttributeNamedArgument(Type attributeType, AttributeArgumentValidationInfo argumentInfo)
    {
        var (line, column, length) = _spans.GetAttributeArgumentDiagnosticSpan(argumentInfo.Argument, argumentInfo.Value);
        Error(
            ErrorCode.UndefinedMember,
            $"Attribute '{GetAttributeDisplayName(attributeType)}' has no public settable property or field named '{argumentInfo.Name}'",
            line,
            column,
            "Use a named argument exposed by the attribute type.",
            length);
    }

    private void ReportAttributeNamedArgumentTypeMismatch(
        Type attributeType,
        AttributeArgumentValidationInfo argumentInfo,
        Type memberType)
    {
        var (line, column, length) = _spans.GetAttributeArgumentDiagnosticSpan(argumentInfo.Argument, argumentInfo.Value);
        Error(
            ErrorCode.TypeMismatch,
            $"Attribute named argument '{argumentInfo.Name}' on '{GetAttributeDisplayName(attributeType)}' expects '{NullabilityMetadataReflection.FormatType(memberType)}' but got '{NullabilityMetadataReflection.FormatType(argumentInfo.ClrType!)}'",
            line,
            column,
            "Use a value whose type matches the attribute property or field.",
            length);
    }

    private void ReportNoMatchingAttributeConstructor(
        AttributeNode attribute,
        Type attributeType,
        IReadOnlyList<AttributeArgumentValidationInfo> positionalArguments)
    {
        var (line, column, length) = positionalArguments.Count > 0
            ? _spans.GetExpressionDiagnosticSpan(positionalArguments[0].Value)
            : AnalyzerDiagnosticSpanFacts.GetAttributeFallbackDiagnosticSpan(attribute);
        var argumentTypes = positionalArguments
            .Select(argumentInfo => NullabilityMetadataReflection.FormatType(argumentInfo.ClrType!))
            .ToList();
        Error(
            ErrorCode.NoMatchingOverload,
            $"No constructor of attribute '{GetAttributeDisplayName(attributeType)}' accepts {positionalArguments.Count} positional argument(s) with these types: {string.Join(", ", argumentTypes)}",
            line,
            column,
            "Check the attribute constructor argument count and types.",
            length);
    }

    private static string GetAttributeDisplayName(Type attributeType)
        => attributeType.FullName ?? attributeType.Name;

    private bool TryInferAttributeArgumentClrType(Expression expression, out Type clrType, out bool isNull)
    {
        isNull = false;
        switch (expression)
        {
            case IntLiteralExpression intLiteral:
                return TryConvertLiteralTypeInfoToClrType(GetIntLiteralType(intLiteral.Value), out clrType);
            case FloatLiteralExpression floatLiteral:
                return TryConvertLiteralTypeInfoToClrType(NumericLiteralFacts.GetFloatLiteralTypeInfo(floatLiteral.Value), out clrType);
            case CharLiteralExpression:
                return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.Char, out clrType);
            case StringLiteralExpression:
                return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.String, out clrType);
            case BoolLiteralExpression:
                return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.Bool, out clrType);
            case NullLiteralExpression:
                isNull = true;
                return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.Object, out clrType);
            case TypeOfExpression:
                clrType = _wellKnownTypes?.SystemType ?? typeof(Type);
                return true;
            case NameofExpression:
                return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.String, out clrType);
            case MemberAccessExpression memberAccess:
                return TryInferAttributeMemberAccessClrType(memberAccess, out clrType);
            case ArrayLiteralExpression arrayLiteral:
                return TryInferAttributeArrayClrType(arrayLiteral, out clrType);
            case UnaryExpression unary:
                return TryInferAttributeUnaryClrType(unary, out clrType, out isNull);
            case BinaryExpression binary:
                return TryInferAttributeBinaryClrType(binary, out clrType);
            default:
                clrType = typeof(object);
                return false;
        }
    }

    private bool TryConvertLiteralTypeInfoToClrType(TypeInfo typeInfo, out Type clrType)
    {
        clrType = _clrTypeConversion.TryConvertTypeInfoToClrType(typeInfo) ?? typeof(object);
        return clrType != typeof(object) || BuiltInTypes.Is(typeInfo, BuiltInTypes.Object);
    }

    private bool TryInferAttributeMemberAccessClrType(MemberAccessExpression memberAccess, out Type clrType)
    {
        clrType = typeof(object);
        if (!TryGetQualifiedAttributeName(memberAccess.Object, out var containerName))
        {
            return false;
        }

        if (AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(_wellKnownTypes, containerName) is { } builtInType)
        {
            return TryGetRuntimeStaticAttributeMemberType(builtInType, memberAccess.MemberName, out clrType);
        }

        if (_externalTypeProbe.ResolveExternalType(containerName) is not ReflectionTypeInfo { Type: var reflectionType })
        {
            return false;
        }

        if (IsRuntimeEnumType(reflectionType))
        {
            clrType = reflectionType;
            return true;
        }

        return TryGetRuntimeStaticAttributeMemberType(reflectionType, memberAccess.MemberName, out clrType);
    }

    private static bool TryGetRuntimeStaticAttributeMemberType(Type containerType, string memberName, out Type memberType)
    {
        const BindingFlags flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static;
        var field = containerType.GetField(memberName, flags);
        if (field != null)
        {
            memberType = field.FieldType;
            return true;
        }

        var property = containerType.GetProperty(memberName, flags);
        if (property?.GetMethod != null)
        {
            memberType = property.PropertyType;
            return true;
        }

        memberType = typeof(object);
        return false;
    }

    private bool TryInferAttributeArrayClrType(ArrayLiteralExpression arrayLiteral, out Type clrType)
    {
        Type? elementType = null;
        foreach (var element in arrayLiteral.Elements)
        {
            if (!TryInferAttributeArgumentClrType(element, out var currentType, out var isNull))
            {
                clrType = typeof(object);
                return false;
            }

            if (isNull)
            {
                continue;
            }

            elementType ??= currentType;
            if (elementType != currentType)
            {
                clrType = typeof(object);
                return false;
            }
        }

        if (elementType == null && !TryConvertLiteralTypeInfoToClrType(BuiltInTypes.Object, out elementType))
        {
            clrType = typeof(object);
            return false;
        }

        clrType = elementType.MakeArrayType();
        return true;
    }

    private bool TryInferAttributeUnaryClrType(UnaryExpression unary, out Type clrType, out bool isNull)
    {
        isNull = false;
        if (!TryInferAttributeArgumentClrType(unary.Operand, out clrType, out var operandIsNull) || operandIsNull)
        {
            return false;
        }

        return unary.Operator switch
        {
            UnaryOperator.Negate => IsClrType(clrType, typeof(int))
                || IsClrType(clrType, typeof(long))
                || IsClrType(clrType, typeof(float))
                || IsClrType(clrType, typeof(double)),
            UnaryOperator.Not => IsClrType(clrType, typeof(bool)),
            UnaryOperator.BitwiseNot => IsClrType(clrType, typeof(int)) || IsClrType(clrType, typeof(long)),
            _ => false
        };
    }

    private bool TryInferAttributeBinaryClrType(BinaryExpression binary, out Type clrType)
    {
        clrType = typeof(object);
        if (binary.Operator is not (BinaryOperator.BitwiseOr or BinaryOperator.BitwiseAnd or BinaryOperator.BitwiseXor)
            || !TryInferAttributeArgumentClrType(binary.Left, out var leftType, out var leftIsNull)
            || !TryInferAttributeArgumentClrType(binary.Right, out var rightType, out var rightIsNull)
            || leftIsNull
            || rightIsNull)
        {
            return false;
        }

        if (leftType == rightType
            && (IsClrType(leftType, typeof(int))
                || IsClrType(leftType, typeof(long))
                || IsRuntimeEnumType(leftType)))
        {
            clrType = leftType;
            return true;
        }

        return false;
    }

    private static bool IsClrType(Type type, Type runtimeType)
        => type == runtimeType || string.Equals(type.FullName, runtimeType.FullName, StringComparison.Ordinal);

    private void AnalyzeTestDeclaration(TestDeclaration test)
    {
        // Tests are similar to functions - create scope and analyze body
        PushScope(new Scope(ScopeKind.Function), test.Line, test.Column);

        // Inject setup symbols so tests can reference setup-declared variables
        foreach (var (name, type, line, column) in _setupSymbols)
        {
            DeclareSymbol(name, type, line, column);
            RecordVariableInCurrentScope(name, type);
        }

        // If table-driven, declare parameters in scope
        if (test.TableParameters != null)
        {
            ValidateParameterDeclarations(test.TableParameters, test.Line, test.Column);

            var tableParameterTypes = new List<(string Name, TypeInfo Type)>(test.TableParameters.Count);
            foreach (var param in test.TableParameters)
            {
                var paramType = _typeResolver.ResolveDeclaredType(param.Type);
                tableParameterTypes.Add((param.Name, paramType));
                var (paramLine, paramColumn) = AnalyzerBindingFacts.GetParameterDeclarationPosition(
                    param.Line,
                    param.Column,
                    test.Line,
                    test.Column);
                DeclareSymbol(param.Name, paramType, paramLine, paramColumn);
                RecordVariableInCurrentScope(param.Name, paramType);
            }

            // Validate test case row counts match parameter count
            if (test.TableCases != null)
            {
                foreach (var row in test.TableCases)
                {
                    if (row.Count != test.TableParameters.Count)
                    {
                        Error(
                            ErrorCode.TypeMismatch,
                            $"This test case has {row.Count} values but the table header declares {test.TableParameters.Count} parameters — each row must have exactly one value per parameter",
                            test.Line, test.Column);
                    }

                    var valuesToValidate = Math.Min(row.Count, tableParameterTypes.Count);
                    for (var i = 0; i < row.Count; i++)
                    {
                        var value = row[i];
                        if (!ValidateTableCaseValue(value) || i >= valuesToValidate)
                        {
                            continue;
                        }

                        var (name, type) = tableParameterTypes[i];
                        ValidateTableCaseValueType(value, type, name);
                    }
                }
            }
        }

        AnalyzeStatements(test.Body.Statements);

        PopScope();
    }

    private bool ValidateTableCaseValue(Expression expression)
    {
        if (IsSupportedTableCaseValue(expression))
        {
            return true;
        }

        var errorsBefore = _errors.Count;
        if (expression is TypeOfExpression typeOfExpression)
        {
            ReportSoaRowTypeReferencesInAttributeTypeof(typeOfExpression.Type);
        }

        if (_errors.Count != errorsBefore)
        {
            return false;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.ConstantRequired,
            $"Table-driven test case values must be compile-time constants; {DescribeTableCaseValueForDiagnostic(expression)} is not supported here",
            line,
            column,
            "Use literal int, float, char, string, bool, or null values in table rows.",
            length);
        return false;
    }

    private void ValidateTableCaseValueType(Expression expression, TypeInfo expectedType, string parameterName)
    {
        var previousExpectedType = _currentExpectedType;
        TypeInfo actualType;
        try
        {
            _currentExpectedType = expectedType;
            actualType = AnalyzeExpression(expression);
        }
        finally
        {
            _currentExpectedType = previousExpectedType;
        }

        if (BuiltInTypes.IsUnknown(expectedType) || BuiltInTypes.IsUnknown(actualType) || _assignability.IsAssignable(expectedType, actualType))
        {
            return;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.TypeMismatch,
            $"Table-driven test case value for '{parameterName}' is '{actualType}', but the table header declares '{expectedType}'",
            line,
            column,
            $"Change the literal or the '{parameterName}' parameter type so the row value matches.",
            length);
    }

    private static bool IsSupportedTableCaseValue(Expression expression)
    {
        return expression switch
        {
            IntLiteralExpression
                or FloatLiteralExpression
                or CharLiteralExpression
                or StringLiteralExpression
                or BoolLiteralExpression
                or NullLiteralExpression => true,
            ParenthesizedExpression parenthesized => IsSupportedTableCaseValue(parenthesized.Inner),
            UnaryExpression { Operator: UnaryOperator.Negate, Operand: IntLiteralExpression or FloatLiteralExpression } => true,
            _ => false
        };
    }

    private string DescribeTableCaseValueForDiagnostic(Expression expression)
    {
        var description = DescribeExpressionForDiagnostic(expression);
        return expression switch
        {
            CallExpression => "call",
            TypeOfExpression => "typeof expression",
            _ when description.Contains(' ', StringComparison.Ordinal) => description,
            _ => $"{char.ToLowerInvariant(description[0])}{description[1..]} expression"
        };
    }

    private void AnalyzeSetupDeclaration(SetupDeclaration setup)
    {
        // Analyze setup body in its own scope (validates the code),
        // but symbols are already collected via CollectSetupSymbols
        PushScope(new Scope(ScopeKind.Function), setup.Line, setup.Column);

        AnalyzeStatements(setup.Body.Statements);

        PopScope();
    }

    private void AnalyzeTeardownDeclaration(TeardownDeclaration teardown)
    {
        // Analyze teardown body in its own scope
        // Inject setup symbols so teardown can reference setup-created variables
        PushScope(new Scope(ScopeKind.Function), teardown.Line, teardown.Column);

        foreach (var (name, type, line, column) in _setupSymbols)
        {
            DeclareSymbol(name, type, line, column);
            RecordVariableInCurrentScope(name, type);
        }

        AnalyzeStatements(teardown.Body.Statements);

        PopScope();
    }

    private void CollectSetupSymbols(SetupDeclaration setup)
    {
        // Extract variable declarations from setup block so they can be
        // injected into each test's scope during analysis
        foreach (var stmt in setup.Body.Statements)
        {
            if (stmt is VariableDeclarationStatement varDecl)
            {
                var type = ResolveSetupSymbolType(varDecl);
                _setupSymbols.Add((varDecl.Name, type, varDecl.Line, varDecl.Column));
            }
        }
    }

    private TypeInfo ResolveSetupSymbolType(VariableDeclarationStatement varDecl)
    {
        if (varDecl.Type != null)
        {
            return _typeResolver.ResolveType(varDecl.Type);
        }

        if (varDecl.Initializer != null
            && TryInferSetupInitializerType(varDecl.Initializer, out var inferredType))
        {
            return inferredType;
        }

        return BuiltInTypes.Object;
    }

    private bool TryInferSetupInitializerType(Expression expression, out TypeInfo type)
    {
        switch (expression)
        {
            case IntLiteralExpression:
                type = BuiltInTypes.Int;
                return true;
            case FloatLiteralExpression:
                type = BuiltInTypes.Double;
                return true;
            case CharLiteralExpression:
                type = BuiltInTypes.Char;
                return true;
            case StringLiteralExpression or InterpolatedStringExpression:
                type = BuiltInTypes.String;
                return true;
            case BoolLiteralExpression:
                type = BuiltInTypes.Bool;
                return true;
            case NullLiteralExpression:
                type = BuiltInTypes.Null;
                return true;
            case NewExpression { Type: { } newType }:
                type = _typeResolver.ResolveType(newType);
                return !BuiltInTypes.IsUnknown(type);
            case ArrayLiteralExpression { Elements.Count: > 0 } array
                when TryInferSetupInitializerType(array.Elements[0], out var elementType):
                type = new ArrayTypeInfo(elementType);
                return true;
            case ParenthesizedExpression parenthesized:
                return TryInferSetupInitializerType(parenthesized.Inner, out type);
            case CheckedExpression checkedExpression:
                return TryInferSetupInitializerType(checkedExpression.Expression, out type);
            case UncheckedExpression uncheckedExpression:
                return TryInferSetupInitializerType(uncheckedExpression.Expression, out type);
            default:
                type = BuiltInTypes.Unknown;
                return false;
        }
    }

    private void AnalyzeFunctionDeclaration(FunctionDeclaration func)
    {
        // Validate operator overloads
        if (func.IsOperatorOverload)
        {
            ValidateOperatorOverload(func);
        }

        // Declare function in current scope if not already registered (e.g., by a first pass).
        // DeclareSymbol handles overload merging into NSharpMethodGroupInfo.
        var funcType = _functionTypeFactory.CreateFromDeclaration(func, _currentTypeName);
        var existingSymbol = _scopes.CurrentScopeSymbol(func.Name);
        if (existingSymbol == null)
        {
            DeclareSymbol(func.Name, funcType, func.Line, func.Column);
        }
        else if (existingSymbol is NSharpMethodGroupInfo group)
        {
            // Already in a method group (registered by class first pass) — skip
        }
        else if (existingSymbol is FunctionTypeInfo existingFunction
                 && AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(existingFunction, funcType))
        {
            // Same function already declared (by class first pass) — skip
        }
        else
        {
            // Not yet declared (struct/record/top-level) — declare now
            DeclareSymbol(func.Name, funcType, func.Line, func.Column);
        }

        // Track extension methods (first parameter has IsThis = true)
        if (func.Parameters.Count > 0 && func.Parameters[0].IsThis)
        {
            _extensionMethods.Add(func);
        }

        // Check visibility convention (skip for operator overloads - they must be public static)
        if (!func.IsOperatorOverload)
        {
            CheckVisibilityConvention(func.Name, func.Modifiers, func.Line, func.Column);
        }

        PushScope(new Scope(ScopeKind.Function), func.Line, func.Column);

        // Add generic type parameters to both type and symbol namespaces
        // so they are resolvable as types (via LookupType) and as identifiers
        if (func.TypeParameters != null)
        {
            foreach (var tp in func.TypeParameters)
            {
                _scopes.DeclareTypeParameter(tp.Name);
            }
        }

        _typeResolver.ResolveGenericConstraintTypes(func.Constraints);
        CheckCircularGenericConstraints(func.TypeParameters, func.Constraints, func.Name, func.Line, func.Column);

        ValidateParameterDeclarations(func.Parameters, func.Line, func.Column);

        // Add parameters to scope
        foreach (var param in func.Parameters)
        {
            var paramType = _typeResolver.ResolveDeclaredType(param.Type);
            var (paramLine, paramColumn) = AnalyzerBindingFacts.GetParameterDeclarationPosition(
                param.Line,
                param.Column,
                func.Line,
                func.Column);
            DeclareSymbol(param.Name, paramType, paramLine, paramColumn);

            // Record parameter in semantic model for IDE features (scoped)
            RecordVariableInCurrentScope(param.Name, paramType);
        }

        // Set expected return type
        var previousFunction = _currentFunction;
        var previousFunctionReturnTypeWasOmitted = _currentFunctionReturnTypeWasOmitted;
        var previousFunctionIsAsync = _currentFunctionIsAsync;
        var functionReturnType = func.ReturnType != null ? _typeResolver.ResolveDeclaredType(func.ReturnType) : BuiltInTypes.Void;
        _currentReturnType = functionReturnType;
        _currentFunction = func;
        _currentFunctionReturnTypeWasOmitted = func.ReturnType == null;
        _currentFunctionIsAsync = func.Modifiers.HasFlag(Modifiers.Async);

        ReportGeneratorReturnTypeIfNeeded(func, functionReturnType);

        // Record full function facts in the semantic model for IDE/tooling features.
        RecordFunctionInCurrentScope(func.Name, funcType);

        // Analyze body
        if (func.Body != null)
        {
            AnalyzeStatement(func.Body);

            // Definite-assignment for locals (NL304): reads before assignment.
            CheckLocalDefiniteAssignment(func.Body);

            // Missing return (all-paths) check for non-void functions.
            // Iterator functions (func* / async*) use yield, not explicit return.
            var isIterator = func.Modifiers.HasFlag(Modifiers.Generator);
            var isAsyncUnitTask = func.Modifiers.HasFlag(Modifiers.Async) && (AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(functionReturnType) || IsUnitTaskLikeTypeReference(func.ReturnType));
            if (BuiltInTypes.IsNot(functionReturnType, BuiltInTypes.Void) && !isIterator && !isAsyncUnitTask && !StatementAlwaysReturns(func.Body))
            {
                var sourceSnippet = GetSourceSnippet(func.Line);

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.MissingReturn(
                        _currentFilePath,
                        func.Line,
                        func.Column,
                        sourceSnippet,
                        func.Name.Length + 5, // "func " + name
                        functionReturnType.ToString()
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error(
                        ErrorCode.MissingReturn,
                        $"This function should return '{functionReturnType}', but not all code paths return a value — make sure every branch ends with a 'return'",
                        func.Line,
                        func.Column);
                }
            }
        }
        else if (func.ExpressionBody != null)
        {
            // Expression-bodied method: check expression type matches return type
            var isGenerator = func.Modifiers.HasFlag(Modifiers.Generator);
            var expectedExpressionType = !isGenerator && BuiltInTypes.IsNot(functionReturnType, BuiltInTypes.Void) ? functionReturnType : null;
            var exprType = AnalyzeExpressionWithExpectedType(func.ExpressionBody, expectedExpressionType);
            ReportSoaRowEscapeIfNeeded(func.ExpressionBody, exprType, "returned");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(func.ExpressionBody, "returned");
            var reportedGeneratorExpressionBody = ReportGeneratorExpressionBodyIfNeeded(func);
            if (!reportedGeneratorExpressionBody && BuiltInTypes.Is(functionReturnType, BuiltInTypes.Void) && BuiltInTypes.IsNot(exprType, BuiltInTypes.Void))
            {
                AddExpressionBodyReturnError(func, exprType);
            }
            else if (!reportedGeneratorExpressionBody && BuiltInTypes.IsNot(functionReturnType, BuiltInTypes.Void) && !_assignability.IsAssignable(functionReturnType, exprType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(func.ExpressionBody);
                var sourceSnippet = GetSourceSnippet(diagnosticLine);

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.ReturnTypeMismatch(
                        _currentFilePath,
                        diagnosticLine,
                        diagnosticColumn,
                        sourceSnippet,
                        diagnosticLength,
                        func.Name,
                        exprType.ToString(),
                        functionReturnType.ToString()
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error(ErrorCode.TypeMismatch, $"This function should return '{functionReturnType}', but the expression body gives '{exprType}'", func.Line, func.Column);
                }
            }
        }

        _currentReturnType = null;
        _currentFunction = previousFunction;
        _currentFunctionReturnTypeWasOmitted = previousFunctionReturnTypeWasOmitted;
        _currentFunctionIsAsync = previousFunctionIsAsync;
        PopScope();
    }

    private bool ReportGeneratorExpressionBodyIfNeeded(FunctionDeclaration func)
    {
        if (!func.Modifiers.HasFlag(Modifiers.Generator) || func.ExpressionBody == null)
        {
            return false;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(func.ExpressionBody);
        Error(
            ErrorCode.InvalidSyntax,
            "Generator functions must use a block body",
            line,
            column,
            "Use `{ yield value }` to produce sequence values from a generator.",
            length);
        return true;
    }

    private bool ReportGeneratorReturnTypeIfNeeded(FunctionDeclaration func, TypeInfo returnType)
    {
        if (!func.Modifiers.HasFlag(Modifiers.Generator))
        {
            return false;
        }

        var resolvedReturnType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(returnType));
        var isAsyncGenerator = func.Modifiers.HasFlag(Modifiers.Async);
        if (BuiltInTypes.IsUnknown(resolvedReturnType)
            || IsGeneratorSequenceReturnType(resolvedReturnType, isAsyncGenerator))
        {
            return false;
        }

        var sequenceKind = GeneratorSequenceTypeFacts.ExpectedSequenceKind(isAsyncGenerator);
        var suggestion = GeneratorSequenceTypeFacts.ReturnTypeSuggestion(isAsyncGenerator);
        var (line, column, length) = func.ReturnType != null
            ? AnalyzerDiagnosticSpanFacts.GetSourceSpanDiagnosticSpan(
                TypeReferenceFacts.GetStartSpan(func.ReturnType),
                func.Line,
                func.Column,
                Math.Max(1, returnType.ToString().Length))
            : _spans.GetFunctionNameDiagnosticSpan(func);
        Error(
            ErrorCode.TypeMismatch,
            $"Generator function '{func.Name}' must return {sequenceKind}, but it returns '{returnType}'",
            line,
            column,
            suggestion,
            length);
        return true;
    }

    private bool IsGeneratorSequenceReturnType(TypeInfo type, bool isAsyncGenerator)
    {
        if (GeneratorSequenceTypeFacts.IsSequenceReturnType(type, isAsyncGenerator))
            return true;

        return type is ReflectionTypeInfo reflection
            && IsGeneratorSequenceReflectionType(reflection.Type, isAsyncGenerator);
    }

    private static bool IsGeneratorSequenceReflectionType(Type type, bool isAsyncGenerator)
    {
        if (type.IsArray || !type.IsGenericType)
        {
            return false;
        }

        var definition = type.GetGenericTypeDefinition();
        if (isAsyncGenerator)
        {
            return definition == typeof(IAsyncEnumerable<>);
        }

        return definition == typeof(List<>)
            || definition == typeof(IEnumerable<>)
            || definition == typeof(ICollection<>)
            || definition == typeof(IList<>)
            || definition == typeof(IReadOnlyCollection<>)
            || definition == typeof(IReadOnlyList<>);
    }

    private static bool IsUnitTaskLikeTypeReference(TypeReference? typeRef)
        => TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(typeRef);

    private static bool StatementAlwaysReturns(Statement statement)
    {
        switch (statement)
        {
            case ReturnStatement { Value: { } value }:
                return !ContainsParserErrorPlaceholder(value);

            case ReturnStatement:
                return true;

            case ThrowStatement throwStmt:
                return !ContainsParserErrorPlaceholder(throwStmt.Expression);

            case BlockStatement block:
                // If any statement always returns, the remainder of the block is unreachable,
                // so the block always returns.
                foreach (var stmt in block.Statements)
                {
                    if (StatementAlwaysReturns(stmt))
                        return true;
                }
                return false;

            case AllocBlockStatement allocBlock:
                return StatementAlwaysReturns(allocBlock.Body);

            case AllowStatement allow:
                return StatementAlwaysReturns(allow.Body);

            case UnsafeBlockStatement unsafeBlock:
                return StatementAlwaysReturns(unsafeBlock.Body);

            case IfStatement ifStmt:
                return ifStmt.ElseStatement != null &&
                       StatementAlwaysReturns(ifStmt.ThenStatement) &&
                       StatementAlwaysReturns(ifStmt.ElseStatement);

            case LockStatement lockStmt:
                return StatementAlwaysReturns(lockStmt.Body);

            case SwitchStatement switchStmt:
                // Switch always returns if it has a default case and all cases return
                var hasDefault = switchStmt.Cases.Any(c => c.Pattern == null);
                return hasDefault && switchStmt.Cases.All(c =>
                    c.Statements.Any(s => StatementAlwaysReturns(s)));

            case TryStatement tryStmt:
                // Try always returns if the try block returns and all catch blocks return
                if (!StatementAlwaysReturns(tryStmt.TryBlock))
                    return false;
                if (tryStmt.CatchClauses.Count == 0)
                    return false;
                return tryStmt.CatchClauses.All(c => StatementAlwaysReturns(c.Block));

            default:
                return false;
        }
    }

    private void AnalyzeClassDeclaration(ClassDeclaration classDecl)
    {
        var previousClass = _currentClass;
        var previousTypeName = _currentTypeName;
        _currentClass = classDecl;
        _currentTypeName = classDecl.Name;

        CheckVisibilityConvention(classDecl.Name, classDecl.Modifiers, classDecl.Line, classDecl.Column);

        var declaredClassType = _scopes.LookupType(classDecl.Name);
        PushScope(new Scope(ScopeKind.Class), classDecl.Line, classDecl.Column);

        // Add generic type parameters to both type and symbol namespaces
        if (classDecl.TypeParameters != null)
        {
            foreach (var tp in classDecl.TypeParameters)
            {
                _scopes.DeclareTypeParameter(tp.Name);
            }
        }

        ValidateNoStaticMembersOnGenericType(classDecl.Name, classDecl.TypeParameters, classDecl.Members);

        _typeResolver.ResolveTypeIfPresent(classDecl.BaseClass);
        _typeResolver.ResolveTypeReferences(classDecl.Interfaces);

        // Add 'this' to scope
        var classType = declaredClassType
            ?? NominalTypeInfoFactory.FromClassDeclaration(classDecl);
        DeclareNestedTypesInCurrentScope(classType);
        DeclareSymbol("this", classType, classDecl.Line, classDecl.Column, recordBindingDeclaration: false);

        // Add primary constructor parameters to scope.
        if (classDecl.PrimaryConstructorParameters != null)
        {
            ValidateParameterDeclarations(classDecl.PrimaryConstructorParameters, classDecl.Line, classDecl.Column);

            foreach (var param in classDecl.PrimaryConstructorParameters)
            {
                var paramType = _typeResolver.ResolveDeclaredType(param.Type);
                var (paramLine, paramColumn) = AnalyzerBindingFacts.GetParameterDeclarationPosition(
                    param.Line,
                    param.Column,
                    classDecl.Line,
                    classDecl.Column);
                DeclareSymbol(param.Name, paramType, paramLine, paramColumn);
                RecordVariableInCurrentScope(param.Name, paramType);
            }
        }

        // Two-pass analysis for forward references
        // First pass: Collect all function signatures (including overloads)
        foreach (var member in classDecl.Members)
        {
            if (member is FunctionDeclaration func)
            {
                // Add function to scope so it can be referenced by other members.
                // DeclareSymbol handles overload merging into NSharpMethodGroupInfo.
                var funcTypeInfo = _functionTypeFactory.CreateFromDeclaration(func, classDecl.Name);
                DeclareSymbol(func.Name, funcTypeInfo, func.Line, func.Column);
            }
        }

        // Second pass: Analyze all members
        foreach (var member in classDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
        _currentClass = previousClass;
        _currentTypeName = previousTypeName;
    }

    private void AnalyzeStructDeclaration(StructDeclaration structDecl)
    {
        var previousTypeName = _currentTypeName;
        _currentTypeName = structDecl.Name;

        CheckVisibilityConvention(structDecl.Name, structDecl.Modifiers, structDecl.Line, structDecl.Column);

        var declaredStructType = _scopes.LookupType(structDecl.Name);
        PushScope(new Scope(ScopeKind.Struct), structDecl.Line, structDecl.Column);

        // Add generic type parameters to both type and symbol namespaces
        if (structDecl.TypeParameters != null)
        {
            foreach (var tp in structDecl.TypeParameters)
            {
                _scopes.DeclareTypeParameter(tp.Name);
            }
        }

        ValidateNoStaticMembersOnGenericType(structDecl.Name, structDecl.TypeParameters, structDecl.Members);

        _typeResolver.ResolveTypeReferences(structDecl.Interfaces);

        var structType = declaredStructType
            ?? NominalTypeInfoFactory.FromStructDeclaration(structDecl);
        DeclareNestedTypesInCurrentScope(structType);
        DeclareSymbol("this", structType, structDecl.Line, structDecl.Column, recordBindingDeclaration: false);

        // Add primary constructor parameters to scope.
        if (structDecl.PrimaryConstructorParameters != null)
        {
            ValidateParameterDeclarations(structDecl.PrimaryConstructorParameters, structDecl.Line, structDecl.Column);

            foreach (var param in structDecl.PrimaryConstructorParameters)
            {
                var paramType = _typeResolver.ResolveDeclaredType(param.Type);
                var (paramLine, paramColumn) = AnalyzerBindingFacts.GetParameterDeclarationPosition(
                    param.Line,
                    param.Column,
                    structDecl.Line,
                    structDecl.Column);
                DeclareSymbol(param.Name, paramType, paramLine, paramColumn);
                RecordVariableInCurrentScope(param.Name, paramType);
            }
        }

        foreach (var member in structDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
        _currentTypeName = previousTypeName;
    }

    private void AnalyzeRecordDeclaration(RecordDeclaration recordDecl)
    {
        var previousTypeName = _currentTypeName;
        _currentTypeName = recordDecl.Name;

        CheckVisibilityConvention(recordDecl.Name, recordDecl.Modifiers, recordDecl.Line, recordDecl.Column);

        var declaredRecordType = _scopes.LookupType(recordDecl.Name);
        PushScope(new Scope(ScopeKind.Record), recordDecl.Line, recordDecl.Column);

        // Add generic type parameters to both type and symbol namespaces
        if (recordDecl.TypeParameters != null)
        {
            foreach (var tp in recordDecl.TypeParameters)
            {
                _scopes.DeclareTypeParameter(tp.Name);
            }
        }

        ValidateNoStaticMembersOnGenericType(recordDecl.Name, recordDecl.TypeParameters, recordDecl.Members);

        _typeResolver.ResolveTypeReferences(recordDecl.Interfaces);

        var recordType = declaredRecordType
            ?? NominalTypeInfoFactory.FromRecordDeclaration(recordDecl);
        DeclareNestedTypesInCurrentScope(recordType);
        DeclareSymbol("this", recordType, recordDecl.Line, recordDecl.Column, recordBindingDeclaration: false);

        // Add primary constructor parameters to scope.
        if (recordDecl.PrimaryConstructorParameters != null)
        {
            ValidateParameterDeclarations(recordDecl.PrimaryConstructorParameters, recordDecl.Line, recordDecl.Column);

            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var paramType = _typeResolver.ResolveDeclaredType(param.Type);
                var (paramLine, paramColumn) = AnalyzerBindingFacts.GetParameterDeclarationPosition(
                    param.Line,
                    param.Column,
                    recordDecl.Line,
                    recordDecl.Column);
                DeclareSymbol(param.Name, paramType, paramLine, paramColumn);
                RecordVariableInCurrentScope(param.Name, paramType);
            }
        }

        foreach (var member in recordDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
        _currentTypeName = previousTypeName;
    }

    private void ValidateNoStaticMembersOnGenericType(
        string typeName,
        IReadOnlyList<TypeParameter>? typeParameters,
        IEnumerable<Declaration> members)
    {
        if (typeParameters == null || typeParameters.Count == 0)
        {
            return;
        }

        foreach (var member in members)
        {
            switch (member)
            {
                case FieldDeclaration field when field.Modifiers.HasFlag(Modifiers.Static):
                    ReportUnsupportedGenericStaticMember(typeName, typeParameters, "field", field.Name, field.Line, field.Column);
                    break;
                case PropertyDeclaration property when property.Modifiers.HasFlag(Modifiers.Static):
                    ReportUnsupportedGenericStaticMember(typeName, typeParameters, "property", property.Name, property.Line, property.Column);
                    break;
                case FunctionDeclaration function when function.Modifiers.HasFlag(Modifiers.Static):
                    ReportUnsupportedGenericStaticMember(typeName, typeParameters, "method", function.Name, function.Line, function.Column);
                    break;
            }
        }
    }

    private void ReportUnsupportedGenericStaticMember(
        string typeName,
        IReadOnlyList<TypeParameter> typeParameters,
        string memberKind,
        string memberName,
        int line,
        int column)
    {
        var typeDisplay = $"{typeName}<{string.Join(", ", typeParameters.Select(parameter => parameter.Name))}>";
        Error(
            ErrorCode.FeatureNotImplemented,
            $"Static {memberKind} '{memberName}' is not supported on generic type '{typeDisplay}' yet",
            line,
            column,
            "Move the static member to a non-generic helper type, or make it an instance member.",
            Math.Max(1, memberName.Length));
    }

    private void AnalyzeSoaRecordDeclaration(SoaRecordDeclaration soaRecordDecl)
    {
        if (!SoaFeature.IsEnabled)
        {
            Error(
                ErrorCode.FeatureNotImplemented,
                $"soa record '{soaRecordDecl.Name}' is parsed but not available in production builds yet",
                soaRecordDecl.Line,
                soaRecordDecl.Column,
                suggestion: "Set NSHARP_EXPERIMENTAL_SOA=1 only for the compiler table migration gate; otherwise keep using regular records",
                length: "soa".Length);
            return;
        }

        if (_currentTypeName != null)
        {
            Error(
                ErrorCode.FeatureNotImplemented,
                $"nested soa record '{soaRecordDecl.Name}' is not part of the experimental lowering slice yet",
                soaRecordDecl.Line,
                soaRecordDecl.Column,
                suggestion: "Move the soa record to top level while the wrapper ABI is being proven",
                length: "soa".Length);
            return;
        }

        var columnTypes = new List<(SoaColumnDeclaration Column, TypeInfo Type)>(soaRecordDecl.Columns.Count);
        foreach (var column in soaRecordDecl.Columns)
        {
            columnTypes.Add((column, _typeResolver.ResolveDeclaredType(column.Type)));
        }

        ValidateSoaColumnNames(soaRecordDecl);

        foreach (var (column, columnType) in columnTypes)
        {
            var resolvedColumnType = _declarationContext.ResolveDeclaredAlias(columnType);
            if (IsSupportedSoaColumnType(resolvedColumnType))
                continue;

            var (line, columnPosition, length) = AnalyzerDiagnosticSpanFacts.GetSoaColumnTypeDiagnosticSpan(column);
            Error(
                ErrorCode.FeatureNotImplemented,
                $"SoA column type '{resolvedColumnType}' is not supported in this lowering",
                line,
                columnPosition,
                "Use int, uint, long, bool, char, string, string?, or int-backed enum columns until this table " +
                "migration verifies another element shape",
                length);
        }
    }

    private void ValidateSoaColumnNames(SoaRecordDeclaration soaRecordDecl)
    {
        var columnNames = new HashSet<string>(StringComparer.Ordinal);
        foreach (var column in soaRecordDecl.Columns)
        {
            var (line, columnPosition, length) = AnalyzerDiagnosticSpanFacts.GetSoaColumnNameDiagnosticSpan(column, soaRecordDecl);
            if (!columnNames.Add(column.Name))
            {
                Error(
                    ErrorCode.DuplicateDeclaration,
                    $"SoA column '{column.Name}' is already defined — each column in a soa record must have a unique name",
                    line,
                    columnPosition,
                    "Rename one of the columns so every table member has one storage slot.",
                    length);
            }

            if (IsReservedSoaTableMemberName(column.Name))
            {
                Error(
                    ErrorCode.DuplicateDeclaration,
                    $"SoA column '{column.Name}' conflicts with a generated table member",
                    line,
                    columnPosition,
                    "Rename the column; SoA tables reserve length, capacity, add, clear, ensureCapacity, copyRow, and wrap.",
                    length);
            }
        }
    }

    private static bool IsReservedSoaTableMemberName(string name)
        => name is "length" or "capacity" or "add" or "clear" or "ensureCapacity" or "copyRow" or "wrap";

    private bool IsSupportedSoaColumnType(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        if (BuiltInTypes.IsUnknown(resolved))
            return true;

        if (resolved is NullableTypeInfo nullable)
            return BuiltInTypes.Is(_declarationContext.ResolveDeclaredAlias(nullable.InnerType), BuiltInTypes.String);

        if (resolved is EnumTypeInfo enumType)
            return enumType.Declaration.Type == EnumType.Int;

        if (resolved is ReflectionTypeInfo reflectionType
            && TypeInfoIdentityFacts.IsInt32BackedRuntimeEnum(reflectionType.Type))
            return true;

        return BuiltInTypes.Is(resolved, BuiltInTypes.Int)
            || BuiltInTypes.Is(resolved, BuiltInTypes.UInt)
            || BuiltInTypes.Is(resolved, BuiltInTypes.Long)
            || BuiltInTypes.Is(resolved, BuiltInTypes.Bool)
            || BuiltInTypes.Is(resolved, BuiltInTypes.Char)
            || BuiltInTypes.Is(resolved, BuiltInTypes.String);
    }

    private void AnalyzeInterfaceDeclaration(InterfaceDeclaration interfaceDecl)
    {
        var previousTypeName = _currentTypeName;
        _currentTypeName = interfaceDecl.Name;

        CheckVisibilityConvention(interfaceDecl.Name, interfaceDecl.Modifiers, interfaceDecl.Line, interfaceDecl.Column);

        var declaredInterfaceType = _scopes.LookupType(interfaceDecl.Name);
        PushScope(new Scope(ScopeKind.Interface), interfaceDecl.Line, interfaceDecl.Column);

        // Add generic type parameters to both type and symbol namespaces
        if (interfaceDecl.TypeParameters != null)
        {
            foreach (var tp in interfaceDecl.TypeParameters)
            {
                _scopes.DeclareTypeParameter(tp.Name);
            }
        }

        _typeResolver.ResolveTypeReferences(interfaceDecl.BaseInterfaces);
        DeclareNestedTypesInCurrentScope(
            declaredInterfaceType ?? NominalTypeInfoFactory.FromInterfaceDeclaration(interfaceDecl));

        foreach (var member in interfaceDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
        _currentTypeName = previousTypeName;
    }

    private void DeclareNestedTypesInCurrentScope(TypeInfo owner)
    {
        if (!_declarationContext.TryGetSourceMemberShape(owner, null, out var shape))
            return;

        foreach (var nested in shape.NestedTypes)
            _scopes.DeclareNestedTypeIfAbsent(nested.Name, nested.Type);
    }

    private void AnalyzeUnionDeclaration(UnionDeclaration unionDecl)
    {
        CheckVisibilityConvention(unionDecl.Name, unionDecl.Modifiers, unionDecl.Line, unionDecl.Column);

        PushScope(new Scope(ScopeKind.Block), unionDecl.Line, unionDecl.Column);

        // Add generic type parameters to both type and symbol namespaces
        if (unionDecl.TypeParameters != null)
        {
            foreach (var tp in unionDecl.TypeParameters)
            {
                _scopes.DeclareTypeParameter(tp.Name);
            }
        }

        // Validate union cases
        var caseNames = new HashSet<string>();
        foreach (var unionCase in unionDecl.Cases)
        {
            if (!caseNames.Add(unionCase.Name))
            {
                var caseLine = unionCase.Line > 0 ? unionCase.Line : unionDecl.Line;
                var caseCol = unionCase.Column > 0 ? unionCase.Column : unionDecl.Column;
                var sourceSnippet = GetSourceSnippet(caseLine);

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.DuplicateDeclaration(
                        _currentFilePath,
                        caseLine,
                        caseCol,
                        sourceSnippet,
                        unionCase.Name.Length,
                        unionCase.Name,
                        "union case"
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error(ErrorCode.DuplicateDeclaration, $"Union case '{unionCase.Name}' is already defined — each case in a union must have a unique name", caseLine, caseCol, length: Math.Max(1, unionCase.Name.Length));
                }
            }

            if (unionCase.Properties != null)
            {
                foreach (var property in unionCase.Properties)
                {
                    _typeResolver.ResolveDeclaredType(property.Type);
                }
            }
        }

        PopScope();
    }

    private void AnalyzeEnumDeclaration(EnumDeclaration enumDecl)
    {
        CheckVisibilityConvention(enumDecl.Name, enumDecl.Modifiers, enumDecl.Line, enumDecl.Column);

        // Validate enum members
        var memberNames = new HashSet<string>();
        foreach (var member in enumDecl.Members)
        {
            if (!memberNames.Add(member.Name))
            {
                var memLine = member.Line > 0 ? member.Line : enumDecl.Line;
                var memCol = member.Column > 0 ? member.Column : enumDecl.Column;
                var sourceSnippet = GetSourceSnippet(memLine);

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.DuplicateDeclaration(
                        _currentFilePath,
                        memLine,
                        memCol,
                        sourceSnippet,
                        member.Name.Length,
                        member.Name,
                        "enum member"
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error(ErrorCode.DuplicateDeclaration, $"Enum member '{member.Name}' is already defined — each member in an enum must have a unique name", memLine, memCol, length: Math.Max(1, member.Name.Length));
                }
            }

            // Type check initializers
            if (member.Value != null)
            {
                var valueType = AnalyzeExpression(member.Value);
                if (enumDecl.Type == EnumType.Int && !IsNumericType(valueType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(member.Value);
                    Error(
                        ErrorCode.TypeMismatch,
                        $"Enum member '{member.Name}' must have a numeric value — this enum uses int values",
                        diagnosticLine,
                        diagnosticColumn,
                        $"Use a numeric value for '{member.Name}', or change the enum backing type to 'string'",
                        diagnosticLength);
                }
                else if (enumDecl.Type == EnumType.String && !IsStringType(valueType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(member.Value);
                    Error(
                        ErrorCode.TypeMismatch,
                        $"Enum member '{member.Name}' must have a string value — this enum uses string values",
                        diagnosticLine,
                        diagnosticColumn,
                        $"Use a string value for '{member.Name}', or change the enum backing type to 'int'",
                        diagnosticLength);
                }
            }
        }
    }

    private void AnalyzeFieldDeclaration(FieldDeclaration field)
    {
        CheckVisibilityConvention(field.Name, field.Modifiers, field.Line, field.Column);

        TypeInfo fieldType;

        // Handle type inference (when Type is null and Initializer exists)
        if (field.Type == null)
        {
            if (field.Initializer == null)
            {
                Error($"I can't determine the type of '{field.Name}' — give it a type annotation or an initial value so I know what it is", field.Line, field.Column);
                fieldType = BuiltInTypes.Unknown;
            }
            else
            {
                // Infer type from initializer
                fieldType = AnalyzeExpression(field.Initializer);

                if (ReportSoaRowEscapeIfNeeded(field.Initializer, fieldType, "stored in a field"))
                {
                    fieldType = BuiltInTypes.Unknown;
                }
                else if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(field.Initializer, "stored in a field"))
                {
                    fieldType = BuiltInTypes.Unknown;
                }
                else if (BuiltInTypes.IsUnknown(fieldType))
                {
                    Error($"I can't figure out the type of '{field.Name}' from its initializer — try adding an explicit type annotation", field.Line, field.Column);
                }
            }
        }
        else
        {
            fieldType = _typeResolver.ResolveDeclaredType(field.Type);

            if (field.Initializer != null)
            {
                var previousExpectedType = _currentExpectedType;
                _currentExpectedType = fieldType;
                var initType = AnalyzeExpression(field.Initializer);
                _currentExpectedType = previousExpectedType;
                var isSoaRowInitializer = ReportSoaRowEscapeIfNeeded(field.Initializer, initType, "stored in a field");
                var isSoaDirectColumnInitializer = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(field.Initializer, "stored in a field");
                if (!isSoaRowInitializer && !isSoaDirectColumnInitializer && !_assignability.IsAssignable(fieldType, initType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                        _spans.GetExpressionDiagnosticSpan(field.Initializer);
                    var sourceSnippet = GetSourceSnippet(diagnosticLine);

                    if (sourceSnippet != null && _currentFilePath != null)
                    {
                        var error = ErrorMessageBuilder.TypeMismatch(
                            _currentFilePath,
                            diagnosticLine,
                            diagnosticColumn,
                            sourceSnippet,
                            diagnosticLength,
                            initType.ToString(),
                            fieldType.ToString()
                        );
                        _errors.Add(error);
                    }
                    else
                    {
                        Error($"Field '{field.Name}' is typed as '{fieldType}', but the initializer gives '{initType}'", field.Line, field.Column);
                    }
                }
            }
        }

        DeclareSymbol(field.Name, fieldType, field.Line, field.Column);

        // Record field type into SemanticModel for completion support
        if (_currentTypeName != null)
        {
            _semanticModel.RecordTypeMember(_currentTypeName, field.Name, fieldType);
        }

        // Also record in top-level Fields dict so LookupIdentifier can find it
        _semanticModel.RecordField(field.Name, fieldType);
    }

    private void AnalyzePropertyDeclaration(PropertyDeclaration prop)
    {
        CheckVisibilityConvention(prop.Name, prop.Modifiers, prop.Line, prop.Column);

        var propType = _typeResolver.ResolveDeclaredType(prop.Type!);
        DeclareSymbol(prop.Name, propType, prop.Line, prop.Column);

        // Record property type into SemanticModel for completion support
        if (_currentTypeName != null)
        {
            _semanticModel.RecordTypeMember(_currentTypeName, prop.Name, propType);
        }

        // Also record in top-level Properties dict so LookupIdentifier can find it
        _semanticModel.RecordProperty(prop.Name, propType);

        // Expression-bodied property: validate expression type matches property type
        if (prop.ExpressionBody != null)
        {
            var exprType = AnalyzeExpressionWithExpectedType(prop.ExpressionBody, propType);
            ReportSoaRowEscapeIfNeeded(prop.ExpressionBody, exprType, "returned");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(prop.ExpressionBody, "returned");
            if (!_assignability.IsAssignable(propType, exprType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                    _spans.GetExpressionDiagnosticSpan(prop.ExpressionBody);
                var sourceSnippet = GetSourceSnippet(diagnosticLine);

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.TypeMismatch(
                        _currentFilePath,
                        diagnosticLine,
                        diagnosticColumn,
                        sourceSnippet,
                        diagnosticLength,
                        exprType.ToString(),
                        propType.ToString()
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error($"Property '{prop.Name}' is typed as '{propType}', but the expression body returns '{exprType}'", prop.Line, prop.Column);
                }
            }
        }

        // Analyze getter
        if (prop.GetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function), prop.Line, prop.Column);
            var prevReturnType = _currentReturnType;
            _currentReturnType = propType; // Getter should return the property type
            AnalyzeStatement(prop.GetBody);
            _currentReturnType = prevReturnType;
            PopScope();
        }

        // Analyze setter
        if (prop.SetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function), prop.Line, prop.Column);
            var prevReturnType = _currentReturnType;
            _currentReturnType = BuiltInTypes.Void; // Setter returns void
            // Implicitly declare 'value' parameter
            DeclareSymbol("value", propType, prop.Line, prop.Column, recordBindingDeclaration: false);
            RecordVariableInCurrentScope("value", propType);
            AnalyzeStatement(prop.SetBody);
            _currentReturnType = prevReturnType;
            PopScope();
        }
    }

    private void AnalyzeIndexerDeclaration(IndexerDeclaration indexer)
    {
        var indexerType = _typeResolver.ResolveDeclaredType(indexer.Type);
        ValidateParameterDeclarations(indexer.Parameters, indexer.Line, indexer.Column);

        if (indexer.GetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function), indexer.Line, indexer.Column);
            DeclareIndexerParameters(indexer);

            var previousReturnType = _currentReturnType;
            _currentReturnType = indexerType;
            AnalyzeStatement(indexer.GetBody);
            _currentReturnType = previousReturnType;

            PopScope();
        }

        if (indexer.SetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function), indexer.Line, indexer.Column);
            DeclareIndexerParameters(indexer);

            var previousReturnType = _currentReturnType;
            _currentReturnType = BuiltInTypes.Void;
            DeclareSymbol("value", indexerType, indexer.Line, indexer.Column, recordBindingDeclaration: false);
            RecordVariableInCurrentScope("value", indexerType);
            AnalyzeStatement(indexer.SetBody);
            _currentReturnType = previousReturnType;

            PopScope();
        }
    }

    private void DeclareIndexerParameters(IndexerDeclaration indexer)
    {
        foreach (var parameter in indexer.Parameters)
        {
            var parameterType = _typeResolver.ResolveDeclaredType(parameter.Type);
            var (parameterLine, parameterColumn) = AnalyzerBindingFacts.GetParameterDeclarationPosition(
                parameter.Line,
                parameter.Column,
                indexer.Line,
                indexer.Column);
            DeclareSymbol(parameter.Name, parameterType, parameterLine, parameterColumn);
            RecordVariableInCurrentScope(parameter.Name, parameterType);
        }
    }

    private void AnalyzeConstructorDeclaration(ConstructorDeclaration ctor)
    {
        _inConstructor = true;
        PushScope(new Scope(ScopeKind.Function), ctor.Line, ctor.Column);

        ValidateParameterDeclarations(ctor.Parameters, ctor.Line, ctor.Column);

        // Add parameters to scope
        foreach (var param in ctor.Parameters)
        {
            var paramType = _typeResolver.ResolveDeclaredType(param.Type);
            var (paramLine, paramColumn) = AnalyzerBindingFacts.GetParameterDeclarationPosition(
                param.Line,
                param.Column,
                ctor.Line,
                ctor.Column);
            DeclareSymbol(param.Name, paramType, paramLine, paramColumn);
            RecordVariableInCurrentScope(param.Name, paramType);
        }

        // Analyze initializer if present
        if (ctor.Initializer != null)
        {
            AnalyzeExpression(ctor.Initializer);
        }

        // Analyze body
        AnalyzeStatement(ctor.Body);

        // Check definite assignment only if no initializer (this/base handles assignment)
        if (_currentClass != null && ctor.Initializer == null)
        {
            CheckDefiniteAssignment(ctor, _currentClass);
        }

        PopScope();
        _inConstructor = false;
    }

    private void CheckDefiniteAssignment(ConstructorDeclaration ctor, ClassDeclaration classDecl)
    {
        // Collect all non-nullable fields without initializers
        var uninitializedFields = new HashSet<string>();
        foreach (var member in classDecl.Members)
        {
            if (member is FieldDeclaration field)
            {
                // Skip STATIC fields: they are not part of any instance constructor's contract — a static field
                // is .cctor-initialized (or CLR zero/null), so NL304 must never demand a ctor assignment for it.
                if (field.Modifiers.HasFlag(Modifiers.Static))
                {
                    continue;
                }

                // Skip fields with type inference (they always have initializers)
                if (field.Type != null && field.Initializer == null && !IsNullableType(_typeResolver.ResolveType(field.Type)))
                {
                    uninitializedFields.Add(field.Name);
                }
            }
        }

        // Check if constructor assigns all required fields
        var assignedFields = GetAssignedFields(ctor.Body);
        foreach (var field in uninitializedFields)
        {
            if (!assignedFields.Contains(field))
            {
                Error(ErrorCode.DefiniteAssignmentError, $"Field '{field}' is non-nullable but isn't assigned in this constructor — either assign it here or give it a default value in its declaration", ctor.Line, ctor.Column, length: "constructor".Length);
            }
        }
    }

    private HashSet<string> GetAssignedFields(BlockStatement block)
    {
        var assigned = new HashSet<string>();
        CollectAssignedFields(block.Statements, assigned);
        return assigned;
    }

    private void CollectAssignedFields(IEnumerable<Statement> statements, HashSet<string> assigned)
    {
        foreach (var stmt in statements)
        {
            switch (stmt)
            {
                case ExpressionStatement { Expression: AssignmentExpression assignment }:
                    if (assignment.Target is MemberAccessExpression { Object: ThisExpression } memberAccess)
                        assigned.Add(memberAccess.MemberName);
                    else if (assignment.Target is IdentifierExpression ident)
                        assigned.Add(ident.Name);
                    break;

                case BlockStatement block:
                    CollectAssignedFields(block.Statements, assigned);
                    break;

                case IfStatement ifStmt:
                    // Only count as assigned if BOTH branches assign (definite assignment)
                    if (ifStmt.ElseStatement != null)
                    {
                        var thenAssigned = new HashSet<string>();
                        var elseAssigned = new HashSet<string>();
                        CollectAssignedFields(new[] { ifStmt.ThenStatement }, thenAssigned);
                        CollectAssignedFields(new[] { ifStmt.ElseStatement }, elseAssigned);
                        // Fields assigned in both branches are definitely assigned
                        thenAssigned.IntersectWith(elseAssigned);
                        assigned.UnionWith(thenAssigned);
                    }
                    // Single-branch if: assignments are not definite, but still recurse
                    // to catch assignments that happen unconditionally inside
                    break;

                // try, for, foreach, while, using, lock bodies are NOT guaranteed
                // to execute (loop may run 0 times, try may throw before assignment),
                // so assignments inside them do NOT count as definite assignment.
                case TryStatement:
                case ForStatement:
                case ForeachStatement:
                case WhileStatement:
                case UsingStatement:
                case LockStatement:
                    break;
            }
        }
    }

    // ── Definite assignment for locals (NL304) ─────────────────────────────
    //
    // A read of a local that was declared without an initializer is an error
    // unless the local is definitely assigned on every path that reaches the
    // read. Modeled after Roslyn's DataFlowPass: we thread an "assigned" set
    // through the control-flow graph, intersecting at merge points (if/else,
    // switch) and treating loop bodies conservatively (they may run zero times).
    // The squiggle lands on the offending READ of the variable.

    /// <summary>
    /// Run definite-assignment analysis over a function/constructor body, reporting
    /// NL304 on reads of locals that are not definitely assigned on all paths.
    /// </summary>
    private void CheckLocalDefiniteAssignment(BlockStatement body)
    {
        var state = new DefiniteAssignmentState();
        AnalyzeDefiniteAssignmentBlock(body, state);
    }

    // Returns true if the statement (and therefore the path through it) always
    // exits the enclosing flow via return/throw/break/continue.
    private bool AnalyzeDefiniteAssignmentStatement(Statement stmt, DefiniteAssignmentState state)
    {
        switch (stmt)
        {
            case BlockStatement block:
                return AnalyzeDefiniteAssignmentBlock(block, state);

            case AllocBlockStatement allocBlock:
                return AnalyzeDefiniteAssignmentBlock(allocBlock.Body, state);

            case AllowStatement allow:
                return AnalyzeDefiniteAssignmentBlock(allow.Body, state);

            case UnsafeBlockStatement unsafeBlock:
                return AnalyzeDefiniteAssignmentBlock(unsafeBlock.Body, state);

            case VariableDeclarationStatement varDecl:
                if (varDecl.Initializer != null)
                {
                    AnalyzeDefiniteAssignmentExpression(varDecl.Initializer, state);
                    state.Assigned.Add(varDecl.Name);
                }
                else
                {
                    // Declared without initializer: must be assigned before use.
                    state.Candidates.Add(varDecl.Name);
                    state.Assigned.Remove(varDecl.Name);
                }
                return false;

            case TupleDeconstructionStatement tupleDecl:
                AnalyzeDefiniteAssignmentExpression(tupleDecl.Initializer, state);
                foreach (var name in tupleDecl.Names)
                {
                    if (name != "_")
                        state.Assigned.Add(name);
                }
                return false;

            case ExpressionStatement exprStmt:
                AnalyzeDefiniteAssignmentExpression(exprStmt.Expression, state);
                return false;

            case PrintStatement printStmt:
                AnalyzeDefiniteAssignmentExpression(printStmt.Value, state);
                return false;

            case ReturnStatement returnStmt:
                if (returnStmt.Value != null)
                    AnalyzeDefiniteAssignmentExpression(returnStmt.Value, state);
                return true;

            case YieldStatement yieldStmt:
                if (yieldStmt.Value != null)
                    AnalyzeDefiniteAssignmentExpression(yieldStmt.Value, state);
                return false;

            case ThrowStatement throwStmt:
                AnalyzeDefiniteAssignmentExpression(throwStmt.Expression, state);
                return true;

            case BreakStatement:
            case ContinueStatement:
                return true;

            case IfStatement ifStmt:
                return AnalyzeDefiniteAssignmentIf(ifStmt, state);

            case WhileStatement whileStmt:
                AnalyzeDefiniteAssignmentExpression(whileStmt.Condition, state);
                AnalyzeDefiniteAssignmentLoopBody(whileStmt.Body, state);
                return false;

            case ForStatement forStmt:
                if (forStmt.Initializer != null)
                    AnalyzeDefiniteAssignmentStatement(forStmt.Initializer, state);
                if (forStmt.Condition != null)
                    AnalyzeDefiniteAssignmentExpression(forStmt.Condition, state);
                AnalyzeDefiniteAssignmentLoopBody(forStmt.Body, state, forStmt.Iterator);
                return false;

            case ForeachStatement foreachStmt:
                AnalyzeDefiniteAssignmentExpression(foreachStmt.Collection, state);
                AnalyzeDefiniteAssignmentLoopBody(foreachStmt.Body, state);
                return false;

            case AwaitForEachStatement awaitForeach:
                AnalyzeDefiniteAssignmentExpression(awaitForeach.Collection, state);
                AnalyzeDefiniteAssignmentLoopBody(awaitForeach.Body, state);
                return false;

            case SwitchStatement switchStmt:
                return AnalyzeDefiniteAssignmentSwitch(switchStmt, state);

            case TryStatement tryStmt:
                return AnalyzeDefiniteAssignmentTry(tryStmt, state);

            case UsingStatement usingStmt:
                if (usingStmt.Declaration != null)
                    AnalyzeDefiniteAssignmentStatement(usingStmt.Declaration, state);
                if (usingStmt.Expression != null)
                    AnalyzeDefiniteAssignmentExpression(usingStmt.Expression, state);
                if (usingStmt.Body != null)
                    return AnalyzeDefiniteAssignmentStatement(usingStmt.Body, state);
                return false;

            case LockStatement lockStmt:
                AnalyzeDefiniteAssignmentExpression(lockStmt.LockObject, state);
                AnalyzeDefiniteAssignmentBlock(lockStmt.Body, state);
                return false;

            case AssertStatement assertStmt:
                AnalyzeDefiniteAssignmentExpression(assertStmt.Condition, state);
                if (assertStmt.Message != null)
                    AnalyzeDefiniteAssignmentExpression(assertStmt.Message, state);
                return false;

            // Local functions have their own bodies analyzed independently; do not
            // flow the enclosing assignment state into them.
            case LocalFunctionStatement:
            default:
                return false;
        }
    }

    private bool AnalyzeDefiniteAssignmentBlock(BlockStatement block, DefiniteAssignmentState state)
    {
        foreach (var statement in block.Statements)
        {
            if (AnalyzeDefiniteAssignmentStatement(statement, state))
                return true;
        }
        return false;
    }

    private bool AnalyzeDefiniteAssignmentIf(IfStatement ifStmt, DefiniteAssignmentState state)
    {
        AnalyzeDefiniteAssignmentExpression(ifStmt.Condition, state);

        var beforeBranches = new HashSet<string>(state.Assigned, StringComparer.Ordinal);

        var thenAlwaysExits = AnalyzeDefiniteAssignmentStatement(ifStmt.ThenStatement, state);
        var afterThen = new HashSet<string>(state.Assigned, StringComparer.Ordinal);

        // Reset to pre-branch state for the else path.
        state.Assigned.Clear();
        state.Assigned.UnionWith(beforeBranches);

        bool elseAlwaysExits;
        HashSet<string> afterElse;
        if (ifStmt.ElseStatement != null)
        {
            elseAlwaysExits = AnalyzeDefiniteAssignmentStatement(ifStmt.ElseStatement, state);
            afterElse = new HashSet<string>(state.Assigned, StringComparer.Ordinal);
        }
        else
        {
            elseAlwaysExits = false;
            afterElse = beforeBranches;
        }

        // Merge: a variable is assigned afterward only if it is assigned on every
        // path that can fall through. A path that always exits contributes nothing.
        state.Assigned.Clear();
        if (thenAlwaysExits && elseAlwaysExits)
        {
            // Both paths exit — code after the if is unreachable; keep pre-branch state.
            state.Assigned.UnionWith(beforeBranches);
            return true;
        }
        if (thenAlwaysExits)
        {
            state.Assigned.UnionWith(afterElse);
        }
        else if (elseAlwaysExits)
        {
            state.Assigned.UnionWith(afterThen);
        }
        else
        {
            afterThen.IntersectWith(afterElse);
            state.Assigned.UnionWith(afterThen);
        }
        return false;
    }

    private void AnalyzeDefiniteAssignmentLoopBody(
        Statement body,
        DefiniteAssignmentState state,
        Expression? iterator = null)
    {
        // The body may execute zero times, so assignments inside it are not
        // definite afterward. Analyze reads against a snapshot, then restore.
        var before = new HashSet<string>(state.Assigned, StringComparer.Ordinal);
        AnalyzeDefiniteAssignmentStatement(body, state);
        if (iterator != null)
            AnalyzeDefiniteAssignmentExpression(iterator, state);
        state.Assigned.Clear();
        state.Assigned.UnionWith(before);
    }

    private bool AnalyzeDefiniteAssignmentSwitch(SwitchStatement switchStmt, DefiniteAssignmentState state)
    {
        AnalyzeDefiniteAssignmentExpression(switchStmt.Value, state);

        var before = new HashSet<string>(state.Assigned, StringComparer.Ordinal);
        HashSet<string>? merged = null;
        var hasDefault = false;
        var allCasesExit = true;

        foreach (var switchCase in switchStmt.Cases)
        {
            if (switchCase.Pattern == null)
                hasDefault = true;

            state.Assigned.Clear();
            state.Assigned.UnionWith(before);

            var caseExits = false;
            foreach (var statement in switchCase.Statements)
            {
                if (AnalyzeDefiniteAssignmentStatement(statement, state))
                {
                    caseExits = true;
                    break;
                }
            }

            if (!caseExits)
            {
                allCasesExit = false;
                var afterCase = new HashSet<string>(state.Assigned, StringComparer.Ordinal);
                if (merged == null)
                    merged = afterCase;
                else
                    merged.IntersectWith(afterCase);
            }
        }

        state.Assigned.Clear();
        if (hasDefault && allCasesExit)
            return true;
        // Without a default case, the value may fall through unmatched, so only
        // the pre-switch assignments are guaranteed.
        state.Assigned.UnionWith(hasDefault && merged != null ? merged : before);
        return false;
    }

    private bool AnalyzeDefiniteAssignmentTry(TryStatement tryStmt, DefiniteAssignmentState state)
    {
        var before = new HashSet<string>(state.Assigned, StringComparer.Ordinal);

        // The try block may throw partway through, so its assignments are not
        // guaranteed to reach the catch/finally. Analyze reads, then discard.
        AnalyzeDefiniteAssignmentBlock(tryStmt.TryBlock, state);
        state.Assigned.Clear();
        state.Assigned.UnionWith(before);

        foreach (var catchClause in tryStmt.CatchClauses)
        {
            var catchState = new HashSet<string>(before, StringComparer.Ordinal);
            state.Assigned.Clear();
            state.Assigned.UnionWith(catchState);
            AnalyzeDefiniteAssignmentBlock(catchClause.Block, state);
        }

        state.Assigned.Clear();
        state.Assigned.UnionWith(before);
        if (tryStmt.FinallyBlock != null)
            AnalyzeDefiniteAssignmentBlock(tryStmt.FinallyBlock, state);
        return false;
    }

    private void AnalyzeDefiniteAssignmentExpression(Expression? expr, DefiniteAssignmentState state)
    {
        switch (expr)
        {
            case null:
                return;

            case IdentifierExpression identifier:
                ReportIfReadBeforeAssigned(identifier, state);
                return;

            case AssignmentExpression assignment:
                // Compound assignment (+=, etc.) reads the target first.
                if (assignment.Operator != AssignmentOperator.Assign
                    && assignment.Target is IdentifierExpression compoundTarget)
                {
                    ReportIfReadBeforeAssigned(compoundTarget, state);
                }
                else if (assignment.Target is not IdentifierExpression)
                {
                    AnalyzeDefiniteAssignmentExpression(assignment.Target, state);
                }

                AnalyzeDefiniteAssignmentExpression(assignment.Value, state);

                if (assignment.Target is IdentifierExpression assignTarget)
                    state.Assigned.Add(assignTarget.Name);
                return;

            case BinaryExpression binary:
                AnalyzeDefiniteAssignmentExpression(binary.Left, state);
                AnalyzeDefiniteAssignmentExpression(binary.Right, state);
                return;

            case UnaryExpression unary:
                AnalyzeDefiniteAssignmentExpression(unary.Operand, state);
                return;

            case MemberAccessExpression member:
                AnalyzeDefiniteAssignmentExpression(member.Object, state);
                return;

            case IndexAccessExpression index:
                AnalyzeDefiniteAssignmentExpression(index.Object, state);
                AnalyzeDefiniteAssignmentExpression(index.Index, state);
                return;

            case CallExpression call:
                AnalyzeDefiniteAssignmentExpression(call.Callee, state);
                foreach (var argument in call.Arguments)
                {
                    // out arguments assign the target rather than reading it.
                    if (argument.Modifier == ArgumentModifier.Out
                        && argument.Value is IdentifierExpression outTarget)
                    {
                        state.Assigned.Add(outTarget.Name);
                    }
                    else
                    {
                        AnalyzeDefiniteAssignmentExpression(argument.Value, state);
                    }
                }
                return;

            case TernaryExpression ternary:
                AnalyzeDefiniteAssignmentExpression(ternary.Condition, state);
                AnalyzeDefiniteAssignmentExpression(ternary.ThenExpression, state);
                AnalyzeDefiniteAssignmentExpression(ternary.ElseExpression, state);
                return;

            case ParenthesizedExpression parenthesized:
                AnalyzeDefiniteAssignmentExpression(parenthesized.Inner, state);
                return;

            case CastExpression cast:
                AnalyzeDefiniteAssignmentExpression(cast.Expression, state);
                return;

            case IsExpression isExpr:
                AnalyzeDefiniteAssignmentExpression(isExpr.Expression, state);
                return;

            case AwaitExpression await:
                AnalyzeDefiniteAssignmentExpression(await.Expression, state);
                return;

            case MustExpression must:
                AnalyzeDefiniteAssignmentExpression(must.Expression, state);
                return;

            case ThrowExpression throwExpr:
                AnalyzeDefiniteAssignmentExpression(throwExpr.Expression, state);
                return;

            case CheckedExpression checkedExpr:
                AnalyzeDefiniteAssignmentExpression(checkedExpr.Expression, state);
                return;

            case UncheckedExpression uncheckedExpr:
                AnalyzeDefiniteAssignmentExpression(uncheckedExpr.Expression, state);
                return;

            case AllocExpression alloc:
                AnalyzeDefiniteAssignmentExpression(alloc.Expression, state);
                return;

            case StackAllocExpression stackAlloc:
                AnalyzeDefiniteAssignmentExpression(stackAlloc.LengthExpression, state);
                return;

            case RangeExpression range:
                AnalyzeDefiniteAssignmentExpression(range.Start, state);
                AnalyzeDefiniteAssignmentExpression(range.End, state);
                return;

            case ArrayLiteralExpression array:
                foreach (var element in array.Elements)
                    AnalyzeDefiniteAssignmentExpression(element, state);
                return;

            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                    AnalyzeDefiniteAssignmentExpression(element.Value, state);
                return;

            case InterpolatedStringExpression interpolated:
                foreach (var part in interpolated.Parts)
                {
                    if (part is InterpolatedStringHole hole)
                        AnalyzeDefiniteAssignmentExpression(hole.Expression, state);
                }
                return;

            case NewExpression newExpr:
                foreach (var argument in newExpr.ConstructorArguments)
                    AnalyzeDefiniteAssignmentExpression(argument.Value, state);
                AnalyzeDefiniteAssignmentExpression(newExpr.ArrayLengthExpression, state);
                if (newExpr.Initializer != null)
                {
                    foreach (var property in newExpr.Initializer.Properties)
                    {
                        AnalyzeDefiniteAssignmentExpression(property.IndexExpression, state);
                        AnalyzeDefiniteAssignmentExpression(property.Value, state);
                    }
                }
                return;

            case SpreadExpression spread:
                AnalyzeDefiniteAssignmentExpression(spread.Expression, state);
                return;

            case WithExpression with:
                AnalyzeDefiniteAssignmentExpression(with.Target, state);
                foreach (var property in with.Properties)
                {
                    AnalyzeDefiniteAssignmentExpression(property.IndexExpression, state);
                    AnalyzeDefiniteAssignmentExpression(property.Value, state);
                }
                return;

            case NameofExpression:
                // nameof does not read the value of its operand.
                return;

            // Lambdas capture by reference and may run later; their bodies are
            // analyzed independently and must not consume the enclosing flow state.
            case LambdaExpression:
            default:
                return;
        }
    }

    private void ReportIfReadBeforeAssigned(IdentifierExpression identifier, DefiniteAssignmentState state)
    {
        var name = identifier.Name;
        if (!state.Candidates.Contains(name) || state.Assigned.Contains(name))
            return;

        var key = (name, identifier.Line, identifier.Column);
        if (!state.Reported.Add(key))
            return;

        Error(
            ErrorCode.DefiniteAssignmentError,
            $"'{name}' is used here before it has been assigned a value on every path that reaches this point",
            identifier.Line,
            identifier.Column,
            $"Give '{name}' an initial value where you declare it, or assign it on every branch before this use.",
            Math.Max(1, name.Length));
    }

    private void AnalyzeStatements(IReadOnlyList<Statement> statements)
    {
        var terminated = false;
        foreach (var stmt in statements)
        {
            if (terminated)
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetStatementDiagnosticSpan(stmt);
                Error(
                    ErrorCode.UnreachableStatement,
                    "This code will never run — there's a 'return' or 'throw' above it",
                    diagnosticLine,
                    diagnosticColumn,
                    length: diagnosticLength);
                break;
            }
            AnalyzeStatement(stmt);
            if (StatementAlwaysReturns(stmt))
                terminated = true;
        }
    }

    private void AnalyzeStatement(Statement stmt)
    {
        _currentLine = stmt.Line;
        switch (stmt)
        {
            case ExpressionStatement exprStmt:
                AnalyzeExpressionStatement(exprStmt);
                break;
            case VariableDeclarationStatement varDecl:
                AnalyzeVariableDeclaration(varDecl);
                break;
            case TupleDeconstructionStatement tupleDecl:
                AnalyzeTupleDeconstruction(tupleDecl);
                break;
            case BlockStatement block:
                PushScope(new Scope(ScopeKind.Block), block.Line, block.Column);
                AnalyzeStatements(block.Statements);
                PopScope();
                break;
            case AllocBlockStatement allocBlock:
                AnalyzeStatement(allocBlock.Body);
                break;
            case AllowStatement allow:
                AnalyzeStatement(allow.Body);
                break;
            case UnsafeBlockStatement unsafeBlock:
                AnalyzeStatement(unsafeBlock.Body);
                break;
            case IfStatement ifStmt:
                AnalyzeIfStatement(ifStmt);
                break;
            case ForStatement forStmt:
                AnalyzeForStatement(forStmt);
                break;
            case ForeachStatement foreachStmt:
                AnalyzeForeachStatement(foreachStmt);
                break;
            case AwaitForEachStatement awaitForeachStmt:
                AnalyzeAwaitForeachStatement(awaitForeachStmt);
                break;
            case WhileStatement whileStmt:
                var condType = AnalyzeExpression(whileStmt.Condition);
                var (whileThenNarrowings, _) = ExtractFlowNarrowings(whileStmt.Condition);
                var isSoaRowCondition = ReportSoaRowEscapeIfNeeded(whileStmt.Condition, condType, "used as a 'while' condition");
                var isSoaDirectColumnCondition = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(whileStmt.Condition, "used as a 'while' condition");
                if (!isSoaRowCondition && !isSoaDirectColumnCondition && !IsBoolType(condType))
                {
                    ReportBooleanConditionTypeMismatch(whileStmt.Condition, "a 'while' loop", condType);
                }
                var wasInLoop = _inLoop;
                var whileBreakDepth = _breakTargetFinallyDepth;
                var whileContinueDepth = _continueTargetFinallyDepth;
                _inLoop = true;
                _breakTargetFinallyDepth = _finallyDepth;
                _continueTargetFinallyDepth = _finallyDepth;
                if (whileThenNarrowings.Count > 0)
                {
                    PushScope(new Scope(ScopeKind.Block), whileStmt.Body.Line, whileStmt.Body.Column);
                    ApplyNarrowingsToScope(whileThenNarrowings);
                    AnalyzeStatement(whileStmt.Body);
                    PopScope();
                }
                else
                {
                    AnalyzeStatement(whileStmt.Body);
                }
                _inLoop = wasInLoop;
                _breakTargetFinallyDepth = whileBreakDepth;
                _continueTargetFinallyDepth = whileContinueDepth;
                break;
            case YieldStatement yieldStmt:
                var isGeneratorYield = _currentFunction?.Modifiers.HasFlag(Modifiers.Generator) == true;
                if (!isGeneratorYield)
                {
                    Error(
                        ErrorCode.InvalidSyntax,
                        "'yield' can only be used inside a generator function",
                        yieldStmt.Line,
                        yieldStmt.Column,
                        "Mark the function as `func*`/`async func*`, or replace `yield` with `return` in an ordinary function.",
                        "yield".Length);
                }
                if (yieldStmt.Value != null)
                {
                    var yieldedType = AnalyzeExpression(yieldStmt.Value);
                    var isSoaRowYield = ReportSoaRowEscapeIfNeeded(yieldStmt.Value, yieldedType, "yielded");
                    var isSoaDirectColumnYield = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(yieldStmt.Value, "yielded");
                    if (isGeneratorYield
                        && !isSoaRowYield
                        && !isSoaDirectColumnYield
                        && _currentReturnType != null
                        && TryGetGeneratorYieldElementType(_currentReturnType, out var elementType)
                        && !BuiltInTypes.IsUnknown(yieldedType)
                        && !BuiltInTypes.IsUnknown(elementType)
                        && !_assignability.IsAssignable(elementType, yieldedType))
                    {
                        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(yieldStmt.Value);
                        Error(
                            ErrorCode.TypeMismatch,
                            $"Generator yield value is '{yieldedType}', but the sequence element type is '{elementType}'",
                            line,
                            column,
                            $"Yield a value assignable to '{elementType}', or change the generator return type.",
                            length);
                    }
                }
                break;
            case ReturnStatement returnStmt:
                AnalyzeReturnStatement(returnStmt);
                break;
            case BreakStatement:
                if (!_inLoop)
                {
                    Error(
                        ErrorCode.InvalidSyntax,
                        "'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here",
                        stmt.Line,
                        stmt.Column,
                        "Move this `break` inside a loop, or remove it if there is no loop to exit.",
                        "break".Length);
                }
                else if (_finallyDepth > _breakTargetFinallyDepth)
                {
                    ReportControlTransferOutOfFinally("break", stmt.Line, stmt.Column);
                }
                break;
            case ContinueStatement:
                if (!_inLoop)
                {
                    Error(
                        ErrorCode.InvalidSyntax,
                        "'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here",
                        stmt.Line,
                        stmt.Column,
                        "Move this `continue` inside a loop, or remove it if there is no loop to continue.",
                        "continue".Length);
                }
                else if (_finallyDepth > _continueTargetFinallyDepth)
                {
                    ReportControlTransferOutOfFinally("continue", stmt.Line, stmt.Column);
                }
                break;
            case ThrowStatement throwStmt:
                var thrownType = AnalyzeExpression(throwStmt.Expression);
                if (!ReportSoaRowEscapeIfNeeded(throwStmt.Expression, thrownType, "thrown")
                    && !ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(throwStmt.Expression, "thrown"))
                {
                    ReportNonThrowableThrowOperandIfNeeded(throwStmt.Expression, thrownType);
                }
                break;
            case TryStatement tryStmt:
                AnalyzeTryStatement(tryStmt);
                break;
            case UsingStatement usingStmt:
                AnalyzeUsingStatement(usingStmt);
                break;
            case LockStatement lockStmt:
                AnalyzeLockStatement(lockStmt);
                break;
            case SwitchStatement switchStmt:
                AnalyzeSwitchStatement(switchStmt);
                break;
            case PrintStatement printStmt:
                var printValueType = AnalyzeExpression(printStmt.Value);
                ReportSoaRowEscapeIfNeeded(printStmt.Value, printValueType, "printed");
                ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(printStmt.Value, "printed");
                break;
            case OffStatement off:
                AnalyzeOffStatement(off);
                break;
            case AssertStatement assertStmt:
                AnalyzeAssertStatement(assertStmt);
                break;
            case AssertThrowsStatement assertThrows:
                AnalyzeAssertThrowsStatement(assertThrows);
                break;
            case PreprocessorDirective:
                // Preprocessor directives don't need analysis - they're pass-through
                break;
            case LocalFunctionStatement localFunc:
                AnalyzeLocalFunction(localFunc);
                break;
        }
    }

    private void AnalyzeExpressionStatement(ExpressionStatement exprStmt)
        => AnalyzeDiscardedExpression(
            exprStmt.Expression,
            soaUsage: "discarded",
            DiscardedExpressionContext.ExpressionStatement);

    private void AnalyzeDiscardedExpression(
        Expression expression,
        string soaUsage,
        DiscardedExpressionContext context)
    {
        var errorsBefore = _errors.Count;
        var expressionType = AnalyzeExpression(expression);

        if (ContainsParserErrorPlaceholder(expression))
            return;

        if (_errors.Count == errorsBefore && ReportSoaRowEscapeIfNeeded(expression, expressionType, soaUsage))
            return;

        if (_errors.Count == errorsBefore && ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expression, soaUsage))
            return;

        if (!IsValidExpressionStatement(expression) && _errors.Count == errorsBefore)
        {
            ReportInvalidDiscardedExpression(expression, context);
            return;
        }

        if (_errors.Count == errorsBefore)
        {
            ReportDiscardedMustUseResultIfNeeded(expression);
        }
    }

    /// <summary>
    /// Enforces the must-use policy: a bare call whose result is "must-use" (annotated
    /// with [MustUse]) cannot be discarded silently as an expression statement. The result
    /// must be used or discarded explicitly with `_ = call()`.
    /// </summary>
    private void ReportDiscardedMustUseResultIfNeeded(Expression expression)
    {
        var call = UnwrapMustUseCandidate(expression);
        if (call is null)
            return;

        if (!TryGetMustUseReason(call, out var reason))
            return;

        var calleeName = AnalyzerSyntheticCallFacts.GetCallTargetName(call);
        var (line, column, length) = _spans.GetCallDiagnosticSpan(call, calleeName ?? "call");
        var subject = calleeName != null ? $"the result of '{calleeName}'" : "this result";

        Error(
            ErrorCode.DiscardedMustUseResult,
            $"You're discarding {subject}, but {reason} — its result must be used",
            line,
            column,
            "Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.",
            length);
    }

    /// <summary>
    /// Returns the underlying call expression if the statement is a bare call whose result
    /// would be silently discarded. Explicit discards (`_ = call()`) and any other use of
    /// the value are intentionally excluded.
    /// </summary>
    private static CallExpression? UnwrapMustUseCandidate(Expression expression)
    {
        return expression switch
        {
            CallExpression call => call,
            ParenthesizedExpression parenthesized => UnwrapMustUseCandidate(parenthesized.Inner),
            CheckedExpression checkedExpression => UnwrapMustUseCandidate(checkedExpression.Expression),
            UncheckedExpression uncheckedExpression => UnwrapMustUseCandidate(uncheckedExpression.Expression),
            _ => null
        };
    }

    private bool TryGetMustUseReason(CallExpression call, out string reason)
    {
        reason = string.Empty;

        // The call was already analyzed above, so the callee's resolved type is recorded in the
        // semantic model. Reuse it instead of re-analyzing the AST, which would double-record
        // bindings/references and corrupt find-references.
        if (!_semanticModel.ExpressionTypes.TryGetValue(
                (call.Callee.Line, call.Callee.Column), out var calleeType))
        {
            return false;
        }

        switch (calleeType)
        {
            case FunctionTypeInfo { HasMustUseAttribute: true } functionType:
                reason = $"'{AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call)}' is marked [MustUse]";
                return true;
            case NSharpMethodGroupInfo group:
                {
                    var functions = GetNSharpMethodGroupFunctions(group);
                    if (functions.Count > 0 && functions.All(function => function.HasMustUseAttribute))
                    {
                        reason = $"'{functions[0].SyntheticName ?? "function"}' is marked [MustUse]";
                        return true;
                    }
                    return false;
                }
            case ReflectionMethodInfo method when HasMustUseAttribute(method.Method):
                reason = $"'{method.Method.Name}' is marked [MustUse]";
                return true;
            case ReflectionMethodGroupInfo methodGroup when methodGroup.Methods.Length > 0 && methodGroup.Methods.All(HasMustUseAttribute):
                reason = $"'{methodGroup.Methods[0].Name}' is marked [MustUse]";
                return true;
            default:
                return false;
        }
    }

    private static bool HasMustUseAttribute(MethodInfo method)
    {
            return method.GetCustomAttributesData()
                .Any(data => NominalTypeInfoFactory.IsMustUseAttributeName(data.AttributeType.Name)
                    || NominalTypeInfoFactory.IsMustUseAttributeName(data.AttributeType.FullName ?? string.Empty));
    }

    private static bool IsDiscardTarget(Expression target)
        => target is IdentifierExpression { Name: "_" };

    private static bool ContainsParserErrorPlaceholder(Expression expression)
    {
        return expression switch
        {
            IdentifierExpression { Name: "<error>" } => true,
            MemberAccessExpression { MemberName: "<error>" } => true,
            InterpolatedStringExpression interpolatedString => interpolatedString.Parts
                .OfType<InterpolatedStringHole>()
                .Any(hole => ContainsParserErrorPlaceholder(hole.Expression)),
            RangeExpression range => (range.Start != null && ContainsParserErrorPlaceholder(range.Start)) ||
                                     (range.End != null && ContainsParserErrorPlaceholder(range.End)),
            MemberAccessExpression memberAccess => ContainsParserErrorPlaceholder(memberAccess.Object),
            CallExpression call => ContainsParserErrorPlaceholder(call.Callee) ||
                                   call.Arguments.Any(arg => ContainsParserErrorPlaceholder(arg.Value)),
            BinaryExpression binary => ContainsParserErrorPlaceholder(binary.Left) ||
                                       ContainsParserErrorPlaceholder(binary.Right),
            AssignmentExpression assignment => ContainsParserErrorPlaceholder(assignment.Target) ||
                                               ContainsParserErrorPlaceholder(assignment.Value),
            LambdaExpression lambda => lambda.ExpressionBody != null &&
                                       ContainsParserErrorPlaceholder(lambda.ExpressionBody),
            UnaryExpression unary => ContainsParserErrorPlaceholder(unary.Operand),
            MustExpression must => ContainsParserErrorPlaceholder(must.Expression),
            ParenthesizedExpression parenthesized => ContainsParserErrorPlaceholder(parenthesized.Inner),
            CheckedExpression checkedExpression => ContainsParserErrorPlaceholder(checkedExpression.Expression),
            UncheckedExpression uncheckedExpression => ContainsParserErrorPlaceholder(uncheckedExpression.Expression),
            AllocExpression allocExpression => ContainsParserErrorPlaceholder(allocExpression.Expression),
            StackAllocExpression stackAllocExpression => ContainsParserErrorPlaceholder(stackAllocExpression.LengthExpression),
            IndexAccessExpression indexAccess => ContainsParserErrorPlaceholder(indexAccess.Object) ||
                                                 ContainsParserErrorPlaceholder(indexAccess.Index),
            CastExpression cast => ContainsParserErrorPlaceholder(cast.Expression),
            IsExpression isExpression => ContainsParserErrorPlaceholder(isExpression.Expression),
            AwaitExpression awaitExpression => ContainsParserErrorPlaceholder(awaitExpression.Expression),
            ThrowExpression throwExpression => ContainsParserErrorPlaceholder(throwExpression.Expression),
            TernaryExpression ternary => ContainsParserErrorPlaceholder(ternary.Condition) ||
                                         ContainsParserErrorPlaceholder(ternary.ThenExpression) ||
                                         ContainsParserErrorPlaceholder(ternary.ElseExpression),
            ArrayLiteralExpression array => array.Elements.Any(ContainsParserErrorPlaceholder),
            TupleExpression tuple => tuple.Elements.Any(element => ContainsParserErrorPlaceholder(element.Value)),
            NewExpression @new => @new.ConstructorArguments.Any(arg => ContainsParserErrorPlaceholder(arg.Value)) ||
                                  (@new.Initializer != null && ContainsParserErrorPlaceholder(@new.Initializer)) ||
                                  (@new.ArrayLengthExpression != null && ContainsParserErrorPlaceholder(@new.ArrayLengthExpression)),
            ObjectInitializerExpression initializer => initializer.Properties.Any(property =>
                (property.IndexExpression != null && ContainsParserErrorPlaceholder(property.IndexExpression)) ||
                ContainsParserErrorPlaceholder(property.Value)),
            WithExpression withExpression => ContainsParserErrorPlaceholder(withExpression.Target) ||
                                             withExpression.Properties.Any(property =>
                                                 (property.IndexExpression != null && ContainsParserErrorPlaceholder(property.IndexExpression)) ||
                                                 ContainsParserErrorPlaceholder(property.Value)),
            SpreadExpression spread => ContainsParserErrorPlaceholder(spread.Expression),
            MatchExpression match => ContainsParserErrorPlaceholder(match.Value) ||
                                     match.Cases.Any(matchCase =>
                                         ContainsParserErrorPlaceholder(matchCase.Pattern) ||
                                         (matchCase.Guard != null && ContainsParserErrorPlaceholder(matchCase.Guard)) ||
                                         ContainsParserErrorPlaceholder(matchCase.Expression)),
            NameofExpression nameofExpression => ContainsParserErrorPlaceholder(nameofExpression.Target),
            _ => false
        };
    }

    private static bool ContainsParserErrorPlaceholder(Pattern pattern)
    {
        return pattern switch
        {
            LiteralPattern literal => ContainsParserErrorPlaceholder(literal.Literal),
            RelationalPattern relational => ContainsParserErrorPlaceholder(relational.Value),
            UnionCasePattern unionCase => unionCase.Properties?.Any(ContainsParserErrorPlaceholder) == true,
            ObjectPattern objectPattern => objectPattern.Properties.Any(ContainsParserErrorPlaceholder),
            ListPattern listPattern => listPattern.Elements.Any(ContainsParserErrorPlaceholder),
            AndPattern andPattern => ContainsParserErrorPlaceholder(andPattern.Left) ||
                                     ContainsParserErrorPlaceholder(andPattern.Right),
            OrPattern orPattern => ContainsParserErrorPlaceholder(orPattern.Left) ||
                                   ContainsParserErrorPlaceholder(orPattern.Right),
            NotPattern notPattern => ContainsParserErrorPlaceholder(notPattern.Pattern),
            PositionalPattern positional => positional.Patterns.Any(ContainsParserErrorPlaceholder),
            _ => false
        };
    }

    private static bool ContainsParserErrorPlaceholder(PropertyPattern property)
        => property.Pattern != null && ContainsParserErrorPlaceholder(property.Pattern);

    private static bool IsValidExpressionStatement(Expression expression)
    {
        return expression switch
        {
            AssignmentExpression => true,
            CallExpression => true,
            NewExpression => true,
            OnSubscriptionExpression => true, // subscribing to an event is a side effect
            AllocExpression alloc => IsValidExpressionStatement(alloc.Expression),
            AwaitExpression => true,
            UnaryExpression { Operator: UnaryOperator.PreIncrement or UnaryOperator.PreDecrement
                or UnaryOperator.PostIncrement or UnaryOperator.PostDecrement } => true,
            ParenthesizedExpression parenthesized => IsValidExpressionStatement(parenthesized.Inner),
            CheckedExpression checkedExpression => IsValidExpressionStatement(checkedExpression.Expression),
            UncheckedExpression uncheckedExpression => IsValidExpressionStatement(uncheckedExpression.Expression),
            _ => false
        };
    }

    private void ReportInvalidExpressionStatement(Expression expression)
    {
        var (line, column, length) = _spans.GetExpressionStatementDiagnosticSpan(expression);
        var description = DescribeExpressionForDiagnostic(expression);

        var sourceSnippet = GetSourceSnippet(line);
        if (sourceSnippet != null && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.InvalidExpressionStatement(
                _currentFilePath,
                line,
                column,
                sourceSnippet,
                length,
                description));
            return;
        }

        Error(
            ErrorCode.InvalidExpressionStatement,
            "This expression statement has no effect",
            line,
            column,
            "Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.",
            length);
    }

    private void ReportInvalidDiscardedExpression(Expression expression, DiscardedExpressionContext context)
    {
        if (context == DiscardedExpressionContext.ForIterator)
        {
            ReportInvalidForIteratorExpression(expression);
            return;
        }

        ReportInvalidExpressionStatement(expression);
    }

    private void ReportInvalidForIteratorExpression(Expression expression)
    {
        var (line, column, length) = _spans.GetExpressionStatementDiagnosticSpan(expression);
        var description = DescribeExpressionForDiagnostic(expression);

        var sourceSnippet = GetSourceSnippet(line);
        if (sourceSnippet != null && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.InvalidForIteratorExpression(
                _currentFilePath,
                line,
                column,
                sourceSnippet,
                length,
                description));
            return;
        }

        Error(
            ErrorCode.InvalidExpressionStatement,
            "This for-loop iterator has no effect",
            line,
            column,
            "Use an assignment, call, increment, decrement, await expression, or object construction in the iterator clause, or remove the iterator.",
            length);
    }

    private void ReportBooleanConditionTypeMismatch(Expression condition, string owner, TypeInfo actualType)
    {
        if (BuiltInTypes.IsUnknown(actualType) || ContainsParserErrorPlaceholder(condition))
            return;

        var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(condition);
        Error(
            ErrorCode.TypeMismatch,
            $"The condition in {owner} must be a boolean, but I found '{actualType}'",
            diagnosticLine,
            diagnosticColumn,
            length: diagnosticLength);
    }

    private string DescribeExpressionForDiagnostic(Expression expression)
    {
        return expression switch
        {
            IdentifierExpression identifier => identifier.Name,
            MemberAccessExpression memberAccess => memberAccess.MemberName,
            ParenthesizedExpression parenthesized => DescribeExpressionForDiagnostic(parenthesized.Inner),
            CheckedExpression checkedExpression => DescribeExpressionForDiagnostic(checkedExpression.Expression),
            UncheckedExpression uncheckedExpression => DescribeExpressionForDiagnostic(uncheckedExpression.Expression),
            BinaryExpression => "binary expression",
            IndexAccessExpression => "index access",
            MatchExpression => "match expression",
            _ => expression.GetType().Name.Replace("Expression", "", StringComparison.Ordinal)
        };
    }

    private void AnalyzeAssertStatement(AssertStatement assertStmt)
    {
        // Analyze the condition expression
        var condType = AnalyzeExpression(assertStmt.Condition);
        ReportSoaRowEscapeIfNeeded(assertStmt.Condition, condType, "asserted");
        ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(assertStmt.Condition, "asserted");

        // Analyze optional message expression
        if (assertStmt.Message != null)
        {
            var messageType = AnalyzeExpression(assertStmt.Message);
            ReportSoaRowEscapeIfNeeded(assertStmt.Message, messageType, "used as an assertion message");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(assertStmt.Message, "used as an assertion message");
        }

        // We don't strictly require boolean type because we support various comparison patterns.
    }

    private void AnalyzeAssertThrowsStatement(AssertThrowsStatement assertThrows)
    {
        var exceptionType = _typeResolver.ResolveDeclaredType(assertThrows.ExceptionType);
        ReportNonThrowableAssertThrowsTypeIfNeeded(assertThrows.ExceptionType, exceptionType);

        // Analyze the body block
        PushScope(new Scope(ScopeKind.Block), assertThrows.Line, assertThrows.Column);
        AnalyzeStatements(assertThrows.Body.Statements);
        PopScope();
    }

    private void AnalyzeLocalFunction(LocalFunctionStatement localFunc)
    {
        var func = localFunc.Function;

        // Register the local function in the current scope
        // This allows it to be called later in the same scope.
        var funcType = _functionTypeFactory.CreateFromDeclaration(func, _currentTypeName);
        DeclareSymbol(func.Name, funcType, localFunc.Line, localFunc.Column);

        // Analyze the local function body in a new scope
        PushScope(new Scope(ScopeKind.Function), localFunc.Line, localFunc.Column);

        // Add generic type parameters to both type and symbol namespaces (mirrors
        // AnalyzeFunctionDeclaration) so they resolve as types inside the local function.
        if (func.TypeParameters != null)
        {
            foreach (var tp in func.TypeParameters)
            {
                _scopes.DeclareTypeParameter(tp.Name);
            }
        }

        ValidateParameterDeclarations(func.Parameters, localFunc.Line, localFunc.Column);

        // Add parameters to scope
        foreach (var param in func.Parameters)
        {
            var paramType = _typeResolver.ResolveDeclaredType(param.Type);
            var (paramLine, paramColumn) = AnalyzerBindingFacts.GetParameterDeclarationPosition(
                param.Line,
                param.Column,
                localFunc.Line,
                localFunc.Column);
            DeclareSymbol(param.Name, paramType, paramLine, paramColumn);
            RecordVariableInCurrentScope(param.Name, paramType);
        }

        // Save current function context
        var previousReturnType = _currentReturnType;
        var previousFunction = _currentFunction;
        var previousFunctionReturnTypeWasOmitted = _currentFunctionReturnTypeWasOmitted;
        var previousFunctionIsAsync = _currentFunctionIsAsync;
        var previousInLoop = _inLoop;
        var previousFinallyDepth = _finallyDepth;
        var previousBreakTargetFinallyDepth = _breakTargetFinallyDepth;
        var previousContinueTargetFinallyDepth = _continueTargetFinallyDepth;
        TypeInfo? returnType = func.ReturnType != null ? _typeResolver.ResolveType(func.ReturnType) : BuiltInTypes.Void;
        _currentReturnType = returnType;
        _currentFunction = func;
        _currentFunctionReturnTypeWasOmitted = func.ReturnType == null;
        _currentFunctionIsAsync = func.Modifiers.HasFlag(Modifiers.Async);
        // NL319 context resets at the nested-body boundary: a return here exits the local
        // function, not any finally the declaration happens to sit inside — that is legal.
        // Break/continue targets reset for the same reason: they cannot branch to loops in the
        // enclosing method body.
        _inLoop = false;
        _finallyDepth = 0;
        _breakTargetFinallyDepth = 0;
        _continueTargetFinallyDepth = 0;

        ReportGeneratorReturnTypeIfNeeded(func, returnType);

        // Analyze body
        if (func.Body != null)
        {
            AnalyzeStatements(func.Body.Statements);
            CheckLocalDefiniteAssignment(func.Body);
        }
        else if (func.ExpressionBody != null)
        {
            var isGenerator = func.Modifiers.HasFlag(Modifiers.Generator);
            var expectedExpressionType = !isGenerator && BuiltInTypes.IsNot(returnType, BuiltInTypes.Void) ? returnType : null;
            var exprType = AnalyzeExpressionWithExpectedType(func.ExpressionBody, expectedExpressionType);
            ReportSoaRowEscapeIfNeeded(func.ExpressionBody, exprType, "returned");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(func.ExpressionBody, "returned");
            var reportedGeneratorExpressionBody = ReportGeneratorExpressionBodyIfNeeded(func);
            // Verify expression type matches return type
            if (!reportedGeneratorExpressionBody && BuiltInTypes.IsNot(returnType, BuiltInTypes.Void) && !_assignability.IsAssignable(returnType, exprType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(func.ExpressionBody);
                Error(ErrorCode.TypeMismatch, $"Function '{func.Name}' should return '{returnType}' but the expression body gives '{exprType}'",
                    diagnosticLine, diagnosticColumn, length: diagnosticLength);
            }
        }

        // Restore function context
        _currentReturnType = previousReturnType;
        _currentFunction = previousFunction;
        _currentFunctionReturnTypeWasOmitted = previousFunctionReturnTypeWasOmitted;
        _currentFunctionIsAsync = previousFunctionIsAsync;
        _inLoop = previousInLoop;
        _finallyDepth = previousFinallyDepth;
        _breakTargetFinallyDepth = previousBreakTargetFinallyDepth;
        _continueTargetFinallyDepth = previousContinueTargetFinallyDepth;

        PopScope();
    }

    private void AnalyzeVariableDeclaration(VariableDeclarationStatement varDecl)
    {
        TypeInfo? declaredType = varDecl.Type != null ? _typeResolver.ResolveDeclaredType(varDecl.Type) : null;
        TypeInfo? inferredType = null;

        if (varDecl.Initializer != null)
        {
            // Set expected type for target-typed expressions (like new())
            var previousExpectedType = _currentExpectedType;
            _currentExpectedType = declaredType;

            inferredType = AnalyzeExpression(varDecl.Initializer);

            // Restore previous expected type
            _currentExpectedType = previousExpectedType;
        }

        // Determine final type
        TypeInfo finalType;
        if (declaredType != null && inferredType != null && varDecl.Initializer != null)
        {
            // Both specified - check compatibility
            if (!_assignability.IsAssignable(declaredType, inferredType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                    _spans.GetExpressionDiagnosticSpan(varDecl.Initializer);
                var sourceSnippet = GetSourceSnippet(diagnosticLine);

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.TypeMismatch(
                        _currentFilePath,
                        diagnosticLine,
                        diagnosticColumn,
                        sourceSnippet,
                        diagnosticLength,
                        inferredType.ToString(),
                        declaredType.ToString()
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error(ErrorCode.TypeMismatch, $"Variable '{varDecl.Name}' is typed as '{declaredType}', but the value is '{inferredType}'", varDecl.Line, varDecl.Column);
                }
            }
            finalType = declaredType;
        }
        else if (declaredType != null)
        {
            // Type specified but no initializer
            if (varDecl.Kind == VariableKind.Const)
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(varDecl);
                Error(
                    ErrorCode.InvalidSyntax,
                    "A 'const' must have an initial value — the compiler needs to know its value at compile time",
                    diagnosticLine,
                    diagnosticColumn,
                    $"Add an initializer, for example `const {varDecl.Name}: {declaredType} = 42`.",
                    diagnosticLength);
            }
            finalType = declaredType;
        }
        else if (inferredType != null)
        {
            // void cannot be used as a value (e.g., x := DoStuff() where DoStuff returns void)
            if (BuiltInTypes.Is(inferredType, BuiltInTypes.Void))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = varDecl.Initializer != null
                    ? _spans.GetExpressionDiagnosticSpan(varDecl.Initializer)
                    : new DiagnosticSpan(varDecl.Line, varDecl.Column, Math.Max(1, varDecl.Name.Length));
                Error(ErrorCode.TypeMismatch, "This expression doesn't return a value (it's void) — you can't assign it to a variable",
                    diagnosticLine, diagnosticColumn, length: diagnosticLength);
                finalType = BuiltInTypes.Unknown;
            }
            else
            {
                // Inferred from initializer
                finalType = inferredType;
            }
        }
        else
        {
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(varDecl);
            Error(
                ErrorCode.InvalidSyntax,
                "I can't determine the type of this variable — give it a type annotation or an initial value",
                diagnosticLine,
                diagnosticColumn,
                $"Add a type annotation like `let {varDecl.Name}: int`, or add an initializer like `let {varDecl.Name} := 0`.",
                diagnosticLength);
            finalType = BuiltInTypes.Unknown;
        }

        if (finalType is SoaRowTypeInfo && varDecl.Initializer != null)
        {
            ReportSoaRowEscape(varDecl.Initializer, "stored in a variable");
        }
        else if (varDecl.Initializer != null)
        {
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(varDecl.Initializer, "stored in a variable");
        }

        DeclareSymbol(varDecl.Name, finalType, varDecl.Line, varDecl.Column, "local");

        // Record in semantic model for IDE features (scoped)
        RecordVariableInCurrentScope(varDecl.Name, finalType);

        var initialNullState = finalType is NullableTypeInfo
            ? varDecl.Initializer is NullLiteralExpression ? NullState.Null : NullState.MaybeNull
            : varDecl.Initializer != null
                ? GetExpressionNullState(varDecl.Initializer, inferredType ?? finalType)
                : GetDefaultNullState(finalType);
        _scopes.SetNullStateInCurrentScope(varDecl.Name, initialNullState);
    }

    private void AnalyzeTupleDeconstruction(TupleDeconstructionStatement tupleDecl)
    {
        // Check if this is error handling pattern: (result, err := Function())
        bool isErrorHandling = tupleDecl.Names.Count == 2 && tupleDecl.Names[1] == "err";

        if (isErrorHandling)
        {
            // Error handling pattern
            var resultVar = tupleDecl.Names[0];
            var errVar = tupleDecl.Names[1];

            // Analyze the initializer expression to ensure it's valid
            var initType = AnalyzeExpression(tupleDecl.Initializer);
            if (ReportSoaRowEscapeIfNeeded(tupleDecl.Initializer, initType, "deconstructed")
                || ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(tupleDecl.Initializer, "deconstructed"))
            {
                initType = BuiltInTypes.Unknown;
            }

            // Declare result variable with inferred type (or Unknown if can't infer)
            if (resultVar != "_")
            {
                DeclareSymbol(resultVar, initType, tupleDecl.Line, tupleDecl.Column);
                RecordVariableInCurrentScope(resultVar, initType);
                _scopes.RegisterErrorTupleResult(resultVar, errVar, tupleDecl.Line, tupleDecl.Column);
            }

            // Declare err variable as nullable Exception
            if (errVar != "_")
            {
                var exceptionType = new ExternalTypeInfo("Exception?");
                DeclareSymbol(errVar, exceptionType, tupleDecl.Line, tupleDecl.Column);
                RecordVariableInCurrentScope(errVar, exceptionType);
                _scopes.SetNullStateInCurrentScope(errVar, NullState.MaybeNull);
            }
        }
        else
        {
            // Normal tuple deconstruction
            // Analyze the initializer expression
            var initType = AnalyzeExpression(tupleDecl.Initializer);
            if (ReportSoaRowEscapeIfNeeded(tupleDecl.Initializer, initType, "deconstructed")
                || ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(tupleDecl.Initializer, "deconstructed"))
            {
                initType = BuiltInTypes.Unknown;
            }

            if (BuiltInTypes.IsUnknown(initType))
            {
                DeclareTupleDeconstructionTargets(tupleDecl, BuiltInTypes.Unknown);
                return;
            }

            if (!TryGetTupleDeconstructionElements(initType, out var elements))
            {
                var (line, column, length) = _spans.GetExpressionDiagnosticSpan(tupleDecl.Initializer);
                Error(
                    ErrorCode.InvalidSyntax,
                    $"Tuple deconstruction needs a tuple value, but this initializer is '{initType}'",
                    line,
                    column,
                    "Return or construct a tuple with the same number of elements as the deconstruction targets.",
                    length);
                DeclareTupleDeconstructionTargets(tupleDecl, BuiltInTypes.Unknown);
                return;
            }

            if (elements.Count != tupleDecl.Names.Count)
            {
                var (line, column, length) = _spans.GetExpressionDiagnosticSpan(tupleDecl.Initializer);
                Error(
                    ErrorCode.InvalidSyntax,
                    $"Tuple deconstruction has {tupleDecl.Names.Count} target(s), but the initializer has {elements.Count} element(s)",
                    line,
                    column,
                    "Match the number of target names to the tuple element count.",
                    length);
                DeclareTupleDeconstructionTargets(tupleDecl, BuiltInTypes.Unknown);
                return;
            }

            for (var i = 0; i < tupleDecl.Names.Count; i++)
            {
                DeclareTupleDeconstructionTarget(tupleDecl, tupleDecl.Names[i], elements[i]);
            }
        }
    }

    private void DeclareTupleDeconstructionTargets(TupleDeconstructionStatement tupleDecl, TypeInfo fallbackType)
    {
        foreach (var name in tupleDecl.Names)
        {
            DeclareTupleDeconstructionTarget(tupleDecl, name, fallbackType);
        }
    }

    private void DeclareTupleDeconstructionTarget(TupleDeconstructionStatement tupleDecl, string name, TypeInfo type)
    {
        if (name == "_")
        {
            return;
        }

        DeclareSymbol(name, type, tupleDecl.Line, tupleDecl.Column);
        RecordVariableInCurrentScope(name, type);
        _scopes.SetNullStateInCurrentScope(name, GetDefaultNullState(type));
    }

    private bool TryGetTupleDeconstructionElements(TypeInfo initType, out List<TypeInfo> elements)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(initType);
        switch (resolved)
        {
            case TupleTypeInfo tupleType:
                elements = tupleType.Elements.Select(element => element.Type).ToList();
                return true;
            case GenericTypeInfo { Name: "ValueTuple" } valueTuple:
                elements = valueTuple.TypeArguments.ToList();
                return true;
            case ReflectionTypeInfo reflectionType when TryGetReflectionValueTupleElements(reflectionType.Type, out elements):
                return true;
            default:
                elements = new List<TypeInfo>();
                return false;
        }
    }

    private bool TryGetReflectionValueTupleElements(Type type, out List<TypeInfo> elements)
    {
        elements = new List<TypeInfo>();

        var valueTupleType = Nullable.GetUnderlyingType(type) ?? type;
        if (!valueTupleType.IsValueType
            || !valueTupleType.IsGenericType
            || valueTupleType.GetGenericTypeDefinition().FullName is not { } genericDefinitionName
            || !genericDefinitionName.StartsWith("System.ValueTuple`", StringComparison.Ordinal))
        {
            return false;
        }

        var fields = valueTupleType.GetFields(BindingFlags.Public | BindingFlags.Instance);
        for (var i = 1; ; i++)
        {
            var field = fields.FirstOrDefault(candidate => candidate.Name == $"Item{i}");
            if (field == null)
            {
                break;
            }

            elements.Add(AnalyzerReflectionTypeConversion.ConvertReflectionType(field.FieldType));
        }

        return elements.Count > 0;
    }

    private void AnalyzeIfStatement(IfStatement ifStmt)
    {
        var condType = AnalyzeExpression(ifStmt.Condition);
        // Allow unknown types (they might be boolean from external methods we can't fully resolve)
        // Extract flow-sensitive type narrowings from the condition (null checks, is-patterns, && chains)
        var (thenNarrowings, elseNarrowings) = ExtractFlowNarrowings(ifStmt.Condition);
        var isSoaRowCondition = ReportSoaRowEscapeIfNeeded(ifStmt.Condition, condType, "used as an 'if' condition");
        var isSoaDirectColumnCondition = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(ifStmt.Condition, "used as an 'if' condition");

        if (!isSoaRowCondition && !isSoaDirectColumnCondition && !IsBoolType(condType) && !BuiltInTypes.IsUnknown(condType) && !ContainsParserErrorPlaceholder(ifStmt.Condition))
        {
            // Use ErrorMessageBuilder for better error message
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(ifStmt.Condition);
            var sourceSnippet = GetSourceSnippet(diagnosticLine);

            if (sourceSnippet != null && _currentFilePath != null)
            {
                var error = ErrorMessageBuilder.TypeMismatch(
                    _currentFilePath,
                    diagnosticLine,
                    diagnosticColumn,
                    sourceSnippet,
                    diagnosticLength,
                    condType.ToString(),
                    "bool"
                );
                _errors.Add(error);
            }
            else
            {
                Error(ErrorCode.TypeMismatch, $"The condition in an 'if' must be a boolean, but I found '{condType}'",
                    diagnosticLine, diagnosticColumn, length: diagnosticLength);
            }
        }

        // Apply then-branch narrowings (null checks, is-patterns, && chains)
        if (thenNarrowings.Count > 0)
        {
            PushScope(new Scope(ScopeKind.Block), ifStmt.ThenStatement.Line, ifStmt.ThenStatement.Column);
            ApplyNarrowingsToScope(thenNarrowings);
            AnalyzeStatement(ifStmt.ThenStatement);
            PopScope();
        }
        else
        {
            AnalyzeStatement(ifStmt.ThenStatement);
        }

        if (ifStmt.ElseStatement != null)
        {
            // Apply else-branch narrowings (from == null checks, || chains)
            if (elseNarrowings.Count > 0)
            {
                PushScope(new Scope(ScopeKind.Block), ifStmt.ElseStatement.Line, ifStmt.ElseStatement.Column);
                ApplyNarrowingsToScope(elseNarrowings);
                AnalyzeStatement(ifStmt.ElseStatement);
                PopScope();
            }
            else
            {
                AnalyzeStatement(ifStmt.ElseStatement);
            }
        }

        var thenAlwaysReturns = StatementAlwaysReturns(ifStmt.ThenStatement);
        var elseAlwaysReturns = ifStmt.ElseStatement != null && StatementAlwaysReturns(ifStmt.ElseStatement);

        // Guard clauses are experienced after the if, not inside it:
        // if x == null { return } x.Member
        // If the null branch exits, the surviving path inherits the opposite facts.
        if (thenAlwaysReturns && !elseAlwaysReturns && elseNarrowings.Count > 0)
        {
            ApplyNarrowingsToScope(elseNarrowings);
        }
        else if (elseAlwaysReturns && thenNarrowings.Count > 0)
        {
            ApplyNarrowingsToScope(thenNarrowings);
        }
    }

    /// <summary>
    /// Applies narrowings to the current scope, intersecting duplicate symbols
    /// (keeping the most specific/derived type rather than last-one-wins).
    /// </summary>
    private void ApplyNarrowingsToScope(List<FlowNarrowing> narrowings)
    {
        var currentScope = _scopes.Peek();
        foreach (var narrowing in narrowings)
        {
            var nullState = narrowing.NullState;
            currentScope.NullStates[narrowing.Path] = nullState;
            if (nullState == NullState.Null)
            {
                _scopes.MarkErrorTupleResultsAvailableForError(narrowing.Path);
            }

            if (narrowing.NarrowedType is not { } narrowedType)
                continue;

            // Type narrowings currently apply to simple symbols. Stable member-path
            // null facts are tracked above without rewriting the declared member type.
            if (narrowing.Path.Contains('.', StringComparison.Ordinal))
                continue;

            var name = narrowing.Path;
            if (currentScope.Symbols.TryGetValue(name, out var existing))
            {
                // If new type is more specific (subtype of existing), use it.
                // If existing is more specific (subtype of new), keep existing.
                // Otherwise (unrelated types), keep the new one (it came from a later condition).
                if (_assignability.IsSubtypeOf(narrowedType, existing))
                    currentScope.Symbols[name] = narrowedType;
                else if (!_assignability.IsSubtypeOf(existing, narrowedType))
                    currentScope.Symbols[name] = narrowedType;
            }
            else
            {
                currentScope.Symbols[name] = narrowedType;
            }
        }
    }

    /// <summary>
    /// Extracts flow-sensitive type narrowings from a condition expression.
    /// Returns separate narrowing lists for then-branch and else-branch.
    /// Handles: null checks (!=null, ==null), is-type patterns, and && chains.
    /// </summary>
    private (List<FlowNarrowing> Then, List<FlowNarrowing> Else)
        ExtractFlowNarrowings(Expression condition)
    {
        var thenNarrowings = new List<FlowNarrowing>();
        var elseNarrowings = new List<FlowNarrowing>();

        if (condition is BinaryExpression binary)
        {
            // x != null → narrow x to non-nullable in then-branch
            if (binary.Operator == BinaryOperator.NotEqual)
            {
                TryExtractNullNarrowing(binary.Left, binary.Right, thenNarrowings, elseNarrowings, notEqual: true);
                TryExtractNullNarrowing(binary.Right, binary.Left, thenNarrowings, elseNarrowings, notEqual: true);
            }
            // x == null → narrow x to non-nullable in else-branch
            else if (binary.Operator == BinaryOperator.Equal)
            {
                TryExtractNullNarrowing(binary.Left, binary.Right, thenNarrowings, elseNarrowings, notEqual: false);
                TryExtractNullNarrowing(binary.Right, binary.Left, thenNarrowings, elseNarrowings, notEqual: false);
            }
            // a && b → both sides hold in then-branch; else = !a || !b (can't narrow)
            else if (binary.Operator == BinaryOperator.And)
            {
                var (leftThen, _) = ExtractFlowNarrowings(binary.Left);
                var (rightThen, _) = ExtractFlowNarrowings(binary.Right);
                thenNarrowings.AddRange(leftThen);
                thenNarrowings.AddRange(rightThen);
                // else-branch gets nothing for compound && (negation is disjunction)
            }
            // a || b → both sides must be false in else-branch; then = a || b (can't narrow)
            else if (binary.Operator == BinaryOperator.Or)
            {
                var (_, leftElse) = ExtractFlowNarrowings(binary.Left);
                var (_, rightElse) = ExtractFlowNarrowings(binary.Right);
                elseNarrowings.AddRange(leftElse);
                elseNarrowings.AddRange(rightElse);
                // then-branch gets nothing for compound || (only one side needs to be true)
            }
        }
        // x is Type varName → narrow/declare in then-branch
        else if (condition is IsExpression isExpr)
        {
            var narrowedType = _typeResolver.ResolveType(isExpr.Type);
            if (isExpr.VariableName != null)
            {
                // `x is Dog d` — declare d: Dog in then-branch
                thenNarrowings.Add(new FlowNarrowing(isExpr.VariableName, narrowedType, NullState.NotNull));
                if (AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(isExpr.Expression) is { } path
                    && !path.Contains('.', StringComparison.Ordinal)
                    && _scopes.LookupSymbol(path) is AnonymousUnionTypeInfo sourceUnion
                    && TryRemoveAnonymousUnionArm(sourceUnion, narrowedType) is { } remainingType)
                {
                    elseNarrowings.Add(new FlowNarrowing(path, remainingType, NullState.NotNull));
                }
            }
            else if (AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(isExpr.Expression) is { } path)
            {
                // `x is Dog` — narrow x to Dog in then-branch
                thenNarrowings.Add(new FlowNarrowing(path, narrowedType, NullState.NotNull));
                if (!path.Contains('.', StringComparison.Ordinal)
                    && _scopes.LookupSymbol(path) is AnonymousUnionTypeInfo sourceUnion
                    && TryRemoveAnonymousUnionArm(sourceUnion, narrowedType) is { } remainingType)
                {
                    elseNarrowings.Add(new FlowNarrowing(path, remainingType, NullState.NotNull));
                }
            }
        }
        else if (condition is MemberAccessExpression hasValueAccess
                 && TryExtractHasValueNarrowing(hasValueAccess, thenNarrowings))
        {
        }
        else if (condition is UnaryExpression { Operator: UnaryOperator.Not, Operand: MemberAccessExpression negatedHasValue }
                 && TryExtractHasValueNarrowing(negatedHasValue, elseNarrowings))
        {
        }

        return (thenNarrowings, elseNarrowings);
    }

    private TypeInfo? TryRemoveAnonymousUnionArm(AnonymousUnionTypeInfo sourceUnion, TypeInfo matchedType)
    {
        var remaining = sourceUnion.Arms
            .Where(arm => !_assignability.IsAssignable(matchedType, arm))
            .ToList();

        if (remaining.Count == sourceUnion.Arms.Count)
            return null;

        return remaining.Count switch
        {
            0 => BuiltInTypes.Never,
            1 => remaining[0],
            _ => new AnonymousUnionTypeInfo(remaining)
        };
    }

    private void TryExtractNullNarrowing(
        Expression expr,
        Expression other,
        List<FlowNarrowing> thenNarrowings,
        List<FlowNarrowing> elseNarrowings,
        bool notEqual)
    {
        if (other is not NullLiteralExpression)
            return;

        var path = AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(expr);
        if (path == null)
            return;

        if (notEqual)
        {
            thenNarrowings.Add(new FlowNarrowing(path, null, NullState.NotNull));
            elseNarrowings.Add(new FlowNarrowing(path, null, NullState.Null));
        }
        else
        {
            thenNarrowings.Add(new FlowNarrowing(path, null, NullState.Null));
            elseNarrowings.Add(new FlowNarrowing(path, null, NullState.NotNull));
        }
    }

    private bool TryExtractHasValueNarrowing(MemberAccessExpression memberAccess, List<FlowNarrowing> narrowings)
    {
        if (memberAccess.MemberName != "HasValue" || memberAccess.Object is not IdentifierExpression ident)
        {
            return false;
        }

        var symbolType = _scopes.LookupSymbol(ident.Name);
        if (symbolType is not NullableTypeInfo nullable)
        {
            return false;
        }

        narrowings.Add(new FlowNarrowing(ident.Name, nullable.InnerType, NullState.NotNull));
        return true;
    }

    private void AnalyzeForStatement(ForStatement forStmt)
    {
        PushScope(new Scope(ScopeKind.Block), forStmt.Line, forStmt.Column);

        if (forStmt.Initializer != null)
            AnalyzeStatement(forStmt.Initializer);

        if (forStmt.Condition != null)
        {
            var condType = AnalyzeExpression(forStmt.Condition);
            var isSoaRowCondition = ReportSoaRowEscapeIfNeeded(forStmt.Condition, condType, "used as a 'for' condition");
            var isSoaDirectColumnCondition = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(forStmt.Condition, "used as a 'for' condition");
            if (!isSoaRowCondition && !isSoaDirectColumnCondition && !IsBoolType(condType))
            {
                ReportBooleanConditionTypeMismatch(forStmt.Condition, "a 'for' loop", condType);
            }
        }

        if (forStmt.Iterator != null)
        {
            AnalyzeDiscardedExpression(
                forStmt.Iterator,
                soaUsage: "used as a 'for' iterator",
                DiscardedExpressionContext.ForIterator);
        }

        var wasInLoop = _inLoop;
        var savedBreakDepth = _breakTargetFinallyDepth;
        var savedContinueDepth = _continueTargetFinallyDepth;
        _inLoop = true;
        _breakTargetFinallyDepth = _finallyDepth;
        _continueTargetFinallyDepth = _finallyDepth;
        if (forStmt.Condition != null)
        {
            var (bodyNarrowings, _) = ExtractFlowNarrowings(forStmt.Condition);
            if (bodyNarrowings.Count > 0)
            {
                PushScope(new Scope(ScopeKind.Block), forStmt.Body.Line, forStmt.Body.Column);
                ApplyNarrowingsToScope(bodyNarrowings);
                AnalyzeStatement(forStmt.Body);
                PopScope();
            }
            else
            {
                AnalyzeStatement(forStmt.Body);
            }
        }
        else
        {
            AnalyzeStatement(forStmt.Body);
        }
        _inLoop = wasInLoop;
        _breakTargetFinallyDepth = savedBreakDepth;
        _continueTargetFinallyDepth = savedContinueDepth;

        PopScope();
    }

    private void AnalyzeForeachStatement(ForeachStatement foreachStmt)
    {
        var collectionType = AnalyzeExpression(foreachStmt.Collection);
        if (ReportSoaRowEscapeIfNeeded(foreachStmt.Collection, collectionType, "used as a foreach collection"))
        {
            collectionType = BuiltInTypes.Unknown;
        }
        else if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(foreachStmt.Collection, "used as a foreach collection"))
        {
            collectionType = BuiltInTypes.Unknown;
        }

        TypeInfo elementType = BuiltInTypes.Unknown;
        if (!TryGetLoopSequenceElementType(collectionType, requireAsync: false, out elementType)
            && ShouldReportLoopSequenceTypeMismatch(collectionType))
        {
            ReportLoopSequenceTypeMismatch(
                foreachStmt.Collection,
                collectionType,
                "foreach",
                "enumerable",
                "Use an array, Span<T>, or IEnumerable<T> value as the foreach collection.");
        }

        PushScope(new Scope(ScopeKind.Block), foreachStmt.Line, foreachStmt.Column);

        DeclareSymbol(foreachStmt.VariableName, elementType, foreachStmt.Line, foreachStmt.Column);

        // Record in semantic model for IDE features (hover, completion, scoped)
        RecordVariableInCurrentScope(foreachStmt.VariableName, elementType);

        var wasInLoop = _inLoop;
        var savedBreakDepth = _breakTargetFinallyDepth;
        var savedContinueDepth = _continueTargetFinallyDepth;
        _inLoop = true;
        _breakTargetFinallyDepth = _finallyDepth;
        _continueTargetFinallyDepth = _finallyDepth;
        AnalyzeStatement(foreachStmt.Body);
        _inLoop = wasInLoop;
        _breakTargetFinallyDepth = savedBreakDepth;
        _continueTargetFinallyDepth = savedContinueDepth;

        PopScope();
    }

    private void AnalyzeAwaitForeachStatement(AwaitForEachStatement awaitForeachStmt)
    {
        var collectionType = AnalyzeExpression(awaitForeachStmt.Collection);
        if (ReportSoaRowEscapeIfNeeded(awaitForeachStmt.Collection, collectionType, "used as an async foreach collection"))
        {
            collectionType = BuiltInTypes.Unknown;
        }
        else if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(awaitForeachStmt.Collection, "used as an async foreach collection"))
        {
            collectionType = BuiltInTypes.Unknown;
        }

        TypeInfo elementType = BuiltInTypes.Unknown;
        if (!TryGetLoopSequenceElementType(collectionType, requireAsync: true, out elementType)
            && ShouldReportLoopSequenceTypeMismatch(collectionType))
        {
            ReportLoopSequenceTypeMismatch(
                awaitForeachStmt.Collection,
                collectionType,
                "await foreach",
                "async enumerable",
                "Use an IAsyncEnumerable<T> value as the await foreach collection.");
        }

        PushScope(new Scope(ScopeKind.Block), awaitForeachStmt.Line, awaitForeachStmt.Column);

        DeclareSymbol(awaitForeachStmt.VariableName, elementType, awaitForeachStmt.Line, awaitForeachStmt.Column);

        // Record in semantic model for IDE features (hover, completion, scoped)
        RecordVariableInCurrentScope(awaitForeachStmt.VariableName, elementType);

        var wasInLoop = _inLoop;
        var savedBreakDepth = _breakTargetFinallyDepth;
        var savedContinueDepth = _continueTargetFinallyDepth;
        _inLoop = true;
        _breakTargetFinallyDepth = _finallyDepth;
        _continueTargetFinallyDepth = _finallyDepth;
        AnalyzeStatement(awaitForeachStmt.Body);
        _inLoop = wasInLoop;
        _breakTargetFinallyDepth = savedBreakDepth;
        _continueTargetFinallyDepth = savedContinueDepth;

        PopScope();
    }

    private bool TryGetLoopSequenceElementType(TypeInfo collectionType, bool requireAsync, out TypeInfo elementType)
    {
        elementType = BuiltInTypes.Unknown;

        var resolved = NormalizeShapeType(collectionType);
        switch (resolved)
        {
            case ArrayTypeInfo arrayType when !requireAsync:
                elementType = arrayType.ElementType;
                return true;
            case SimpleTypeInfo simpleType when !requireAsync && BuiltInTypes.Is(simpleType, BuiltInTypes.String):
                elementType = BuiltInTypes.Char;
                return true;
            case GenericTypeInfo genericType when TryGetGenericLoopSequenceElementType(genericType, requireAsync, out elementType):
                return true;
            case ReflectionTypeInfo reflectionType when TryGetReflectionLoopSequenceElementType(reflectionType.Type, requireAsync, out elementType):
                return true;
            case ClassTypeInfo classType when TryGetSourceLoopSequenceElementType(classType.Interfaces, requireAsync, out elementType):
                return true;
            case StructTypeInfo structType when TryGetSourceLoopSequenceElementType(structType.Interfaces, requireAsync, out elementType):
                return true;
            case RecordTypeInfo recordType when TryGetSourceLoopSequenceElementType(recordType.Interfaces, requireAsync, out elementType):
                return true;
            case InterfaceTypeInfo interfaceType when TryGetSourceLoopSequenceElementType(interfaceType.BaseInterfaces, requireAsync, out elementType):
                return true;
            default:
                return false;
        }
    }

    private TypeInfo NormalizeShapeType(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(type));
        while (true)
        {
            switch (resolved)
            {
                case ObliviousTypeInfo oblivious:
                    resolved = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(oblivious.InnerType));
                    continue;
                case ByRefTypeInfo byRef:
                    resolved = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(byRef.InnerType));
                    continue;
                case SimpleTypeInfo simple when _scopes.LookupType(simple.Name) is { } namedType && !ReferenceEquals(namedType, resolved):
                    resolved = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(namedType));
                    continue;
                default:
                    return resolved;
            }
        }
    }

    private bool ShouldReportLoopSequenceTypeMismatch(TypeInfo collectionType)
    {
        var resolved = NormalizeShapeType(collectionType);
        return !BuiltInTypes.IsUnknown(resolved) && resolved is not ExternalTypeInfo;
    }

    private void ReportLoopSequenceTypeMismatch(
        Expression collection,
        TypeInfo collectionType,
        string loopKind,
        string expectedKind,
        string suggestion)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(collection);
        Error(
            ErrorCode.TypeMismatch,
            $"{loopKind} collection must be {expectedKind}, but this collection is '{collectionType}'",
            line,
            column,
            suggestion,
            length);
    }

    private bool TryGetGenericLoopSequenceElementType(GenericTypeInfo genericType, bool requireAsync, out TypeInfo elementType)
    {
        var sourceElementType = LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(genericType, requireAsync);
        if (sourceElementType != null)
        {
            elementType = sourceElementType;
            return true;
        }

        elementType = BuiltInTypes.Unknown;
        return false;
    }

    private bool TryGetSourceLoopSequenceElementType(
        IEnumerable<TypeReference> interfaceReferences,
        bool requireAsync,
        out TypeInfo elementType)
    {
        foreach (var interfaceReference in interfaceReferences)
        {
            var interfaceType = _typeResolver.ResolveType(interfaceReference);
            if (TryGetLoopSequenceElementType(interfaceType, requireAsync, out elementType))
            {
                return true;
            }
        }

        elementType = BuiltInTypes.Unknown;
        return false;
    }

    private bool TryGetReflectionLoopSequenceElementType(Type type, bool requireAsync, out TypeInfo elementType)
    {
        elementType = BuiltInTypes.Unknown;

        var runtimeType = Nullable.GetUnderlyingType(type) ?? type;
        if (!requireAsync && runtimeType.IsArray)
        {
            var elementReflectionType = runtimeType.GetElementType();
            if (elementReflectionType != null)
            {
                elementType = AnalyzerReflectionTypeConversion.ConvertReflectionType(elementReflectionType);
                return true;
            }
        }

        if (!requireAsync && TryGetReflectionGenericElementType(runtimeType, "System.Span`1", out elementType))
        {
            return true;
        }

        if (!requireAsync && TryGetReflectionGenericElementType(runtimeType, "System.ReadOnlySpan`1", out elementType))
        {
            return true;
        }

        var expectedInterface = requireAsync ? typeof(IAsyncEnumerable<>) : typeof(IEnumerable<>);
        if (TryGetReflectionInterfaceElementType(runtimeType, expectedInterface, out elementType))
        {
            return true;
        }

        if (!requireAsync && TryGetReflectionEnumeratorPatternElementType(runtimeType, out elementType))
        {
            return true;
        }

        if (!requireAsync && typeof(System.Collections.IEnumerable).IsAssignableFrom(runtimeType))
        {
            elementType = BuiltInTypes.Object;
            return true;
        }

        return false;
    }

    private bool TryGetReflectionGenericElementType(Type type, string genericDefinitionFullName, out TypeInfo elementType)
    {
        elementType = BuiltInTypes.Unknown;
        if (!type.IsGenericType
            || type.GetGenericTypeDefinition().FullName != genericDefinitionFullName
            || type.GenericTypeArguments.Length != 1)
        {
            return false;
        }

        elementType = AnalyzerReflectionTypeConversion.ConvertReflectionType(type.GenericTypeArguments[0]);
        return true;
    }

    private bool TryGetReflectionInterfaceElementType(Type type, Type expectedInterfaceDefinition, out TypeInfo elementType)
    {
        elementType = BuiltInTypes.Unknown;
            var sequenceInterface = type.IsGenericType && type.GetGenericTypeDefinition() == expectedInterfaceDefinition
                ? type
                : type.GetInterfaces()
                    .FirstOrDefault(candidate =>
                        candidate.IsGenericType && candidate.GetGenericTypeDefinition() == expectedInterfaceDefinition);

            if (sequenceInterface == null || sequenceInterface.GenericTypeArguments.Length != 1)
            {
                return false;
            }

            elementType = AnalyzerReflectionTypeConversion.ConvertReflectionType(sequenceInterface.GenericTypeArguments[0]);
            return true;
    }

    private bool TryGetReflectionEnumeratorPatternElementType(Type type, out TypeInfo elementType)
    {
        elementType = BuiltInTypes.Unknown;
            var getEnumeratorMethod = type.GetMethod(
                "GetEnumerator",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
                binder: null,
                types: Type.EmptyTypes,
                modifiers: null);
            if (getEnumeratorMethod == null)
            {
                return false;
            }

            var enumeratorType = getEnumeratorMethod.ReturnType;
            var moveNextMethod = enumeratorType.GetMethod(
                "MoveNext",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
                binder: null,
                types: Type.EmptyTypes,
                modifiers: null);
            var currentProperty = enumeratorType.GetProperty(
                "Current",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (moveNextMethod?.ReturnType != typeof(bool) || currentProperty?.GetMethod == null)
            {
                return false;
            }

            elementType = AnalyzerReflectionTypeConversion.ConvertReflectionType(currentProperty.PropertyType);
            return true;
    }

    private bool TryGetGeneratorYieldElementType(TypeInfo returnType, out TypeInfo elementType)
    {
        var isAsyncGenerator = _currentFunction?.Modifiers.HasFlag(Modifiers.Async) == true;
        return TryGetLoopSequenceElementType(returnType, isAsyncGenerator, out elementType);
    }

    private void AnalyzeReturnStatement(ReturnStatement returnStmt)
    {
        if (_currentReturnType == null)
        {
            Error(
                ErrorCode.InvalidSyntax,
                "'return' can only be used inside a function — there's no function to return from here",
                returnStmt.Line,
                returnStmt.Column,
                "Move this `return` inside a function, or remove it if there is no function to return from.",
                "return".Length);
            return;
        }

        // NL319: a return anywhere inside a finally block exits the handler — illegal IL. Depth, not
        // immediate-parent: a return inside a try/lock/using nested in the finally still leaves it.
        // (_finallyDepth resets at lambda/local-function boundaries, where a return is legal.)
        if (_finallyDepth > 0)
        {
            ReportControlTransferOutOfFinally("return", returnStmt.Line, returnStmt.Column);
        }

        if (returnStmt.Value != null)
        {
            var previousExpectedType = _currentExpectedType;
            var expectedReturnValueType = _currentFunctionIsAsync && AnalyzerFunctionTypeFactory.TryGetTaskLikeResultTypeInfo(_currentReturnType, out var asyncResultType)
                ? asyncResultType
                : _currentReturnType;
            _currentExpectedType = expectedReturnValueType;
            var returnedType = AnalyzeExpression(returnStmt.Value);
            _currentExpectedType = previousExpectedType;
            if (returnedType is SoaRowTypeInfo)
            {
                ReportSoaRowEscape(returnStmt.Value, "returned");
            }
            else
            {
                ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(returnStmt.Value, "returned");
            }

            if (_currentFunction?.Modifiers.HasFlag(Modifiers.Generator) == true)
            {
                var (line, column, length) = _spans.GetExpressionDiagnosticSpan(returnStmt.Value);
                Error(
                    ErrorCode.InvalidSyntax,
                    "Generator functions cannot return a value",
                    line,
                    column,
                    "Use `yield value` to produce sequence values, or a bare `return`/`yield break` to stop iteration.",
                    length);
                return;
            }

            if (!_assignability.IsAssignable(expectedReturnValueType, returnedType))
            {
                // Use ErrorMessageBuilder for better error message
                var sourceSnippet = GetSourceSnippet(returnStmt.Line);

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    AddReturnValueMismatchError(returnStmt, sourceSnippet, returnedType, expectedReturnValueType);
                }
                else
                {
                    Error(ErrorCode.TypeMismatch, FormatReturnValueMismatchMessage(returnedType, expectedReturnValueType),
                        returnStmt.Line, returnStmt.Column);
                }
            }
        }
        else
        {
            if (BuiltInTypes.IsNot(_currentReturnType, BuiltInTypes.Void) && !(_currentFunctionIsAsync && AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(_currentReturnType)))
            {
                var sourceSnippet = GetSourceSnippet(returnStmt.Line);

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.MissingReturn(
                        _currentFilePath,
                        returnStmt.Line,
                        returnStmt.Column,
                        sourceSnippet,
                        6, // "return" keyword length
                        _currentReturnType.ToString()
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error(ErrorCode.MissingReturn, $"This function should return '{_currentReturnType}', but this 'return' doesn't provide a value", returnStmt.Line, returnStmt.Column);
                }
            }
        }
    }

    private void AddReturnValueMismatchError(
        ReturnStatement returnStmt,
        string sourceSnippet,
        TypeInfo returnedType,
        TypeInfo expectedReturnValueType)
    {
        var functionName = _currentFunction?.Name ?? "this function";
        CompilerError error;
        var (diagnosticLine, diagnosticColumn, diagnosticLength) = _currentFunctionReturnTypeWasOmitted && _currentFunction != null
            ? _spans.GetFunctionNameDiagnosticSpan(_currentFunction)
            : returnStmt.Value != null
            ? _spans.GetExpressionDiagnosticSpan(returnStmt.Value)
            : new DiagnosticSpan(returnStmt.Line, returnStmt.Column, 6);
        var diagnosticSourceSnippet = GetSourceSnippet(diagnosticLine) ?? sourceSnippet;

        if (BuiltInTypes.Is(_currentReturnType, BuiltInTypes.Void))
        {
            error = _currentFunctionReturnTypeWasOmitted
                ? ErrorMessageBuilder.ReturnValueRequiresReturnType(
                    _currentFilePath!,
                    diagnosticLine,
                    diagnosticColumn,
                    diagnosticSourceSnippet,
                    diagnosticLength,
                    functionName,
                    returnedType.ToString())
                : ErrorMessageBuilder.ReturnValueInVoidFunction(
                    _currentFilePath!,
                    diagnosticLine,
                    diagnosticColumn,
                    diagnosticSourceSnippet,
                    diagnosticLength,
                    functionName,
                    returnedType.ToString());
        }
        else
        {
            error = ErrorMessageBuilder.ReturnTypeMismatch(
                _currentFilePath!,
                diagnosticLine,
                diagnosticColumn,
                diagnosticSourceSnippet,
                diagnosticLength,
                functionName,
                returnedType.ToString(),
                expectedReturnValueType.ToString());
        }

        _errors.Add(error);
    }

    private void AddExpressionBodyReturnError(FunctionDeclaration func, TypeInfo expressionType, int? fallbackLine = null, int? fallbackColumn = null)
    {
        var (line, column, length) = _currentFunctionReturnTypeWasOmitted
            ? _spans.GetFunctionNameDiagnosticSpan(func)
            : func.ExpressionBody != null
            ? _spans.GetExpressionDiagnosticSpan(func.ExpressionBody)
            : new DiagnosticSpan(fallbackLine ?? func.Line, fallbackColumn ?? func.Column, 1);
        var sourceSnippet = GetSourceSnippet(line);

        if (sourceSnippet != null && _currentFilePath != null)
        {
            var error = _currentFunctionReturnTypeWasOmitted
                ? ErrorMessageBuilder.ReturnValueRequiresReturnType(
                    _currentFilePath,
                    line,
                    column,
                    sourceSnippet,
                    length,
                    func.Name,
                    expressionType.ToString())
                : ErrorMessageBuilder.ReturnValueInVoidFunction(
                    _currentFilePath,
                    line,
                    column,
                    sourceSnippet,
                    length,
                    func.Name,
                    expressionType.ToString());
            _errors.Add(error);
        }
        else
        {
            Error(ErrorCode.TypeMismatch, FormatReturnValueMismatchMessage(expressionType, BuiltInTypes.Void), line, column);
        }
    }

    private string FormatReturnValueMismatchMessage(TypeInfo returnedType, TypeInfo expectedReturnValueType)
    {
        var functionName = _currentFunction?.Name ?? "this function";

        if (BuiltInTypes.Is(_currentReturnType, BuiltInTypes.Void))
        {
            return _currentFunctionReturnTypeWasOmitted
                ? $"Function '{functionName}' has no return type annotation, so it is treated as 'void', but this code gives back '{returnedType}'"
                : $"Function '{functionName}' is declared to return 'void', but this code gives back '{returnedType}'";
        }

        return $"Function '{functionName}' should return '{expectedReturnValueType}', but this return statement gives back '{returnedType}'";
    }

    private void AnalyzeTryStatement(TryStatement tryStmt)
    {
        AnalyzeStatement(tryStmt.TryBlock);

        foreach (var catchClause in tryStmt.CatchClauses)
        {
            PushScope(new Scope(ScopeKind.Block), tryStmt.Line, tryStmt.Column);

            var exceptionType = catchClause.ExceptionType != null
                ? _typeResolver.ResolveDeclaredType(catchClause.ExceptionType)
                : new SimpleTypeInfo("Exception");
            if (catchClause.ExceptionType != null)
            {
                ReportNonThrowableCatchTypeIfNeeded(catchClause.ExceptionType, exceptionType);
            }

            if (catchClause.VariableName != null)
            {
                DeclareSymbol(catchClause.VariableName, exceptionType, tryStmt.Line, tryStmt.Column);
                RecordVariableInCurrentScope(catchClause.VariableName, exceptionType);
            }

            AnalyzeStatement(catchClause.Block);
            PopScope();
        }

        if (tryStmt.FinallyBlock != null)
        {
            // NL319 context: any return — or break/continue targeting a loop/switch entered at a
            // shallower depth — inside this block would leave the finally handler (illegal IL).
            _finallyDepth++;
            AnalyzeStatement(tryStmt.FinallyBlock);
            _finallyDepth--;
        }
    }

    private void ReportControlTransferOutOfFinally(string keyword, int line, int column)
    {
        var sourceSnippet = GetSourceSnippet(line);
        if (sourceSnippet != null && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.ControlTransferOutOfFinally(
                _currentFilePath, line, column, sourceSnippet, keyword.Length, keyword));
        }
        else
        {
            Error(
                ErrorCode.ControlTransferOutOfFinally,
                $"Control cannot leave a 'finally' block with '{keyword}'",
                line,
                column,
                $"Move the `{keyword}` outside the `finally` block.",
                keyword.Length);
        }
    }

    private void ReportNonThrowableCatchTypeIfNeeded(TypeReference typeReference, TypeInfo exceptionType)
    {
        if (IsThrowableType(exceptionType))
        {
            return;
        }

        var span = TypeReferenceFacts.GetStartSpan(typeReference);
        Error(
            ErrorCode.TypeMismatch,
            $"Catch type must be assignable to System.Exception, but this type is '{exceptionType}'",
            span.StartLine,
            span.StartColumn,
            "Catch Exception or an Exception-derived type, or use a bare catch for all exceptions.",
            span.Length);
    }

    private void ReportNonThrowableAssertThrowsTypeIfNeeded(TypeReference typeReference, TypeInfo exceptionType)
    {
        if (IsThrowableType(exceptionType))
        {
            return;
        }

        var span = TypeReferenceFacts.GetStartSpan(typeReference);
        Error(
            ErrorCode.TypeMismatch,
            $"Assert throws type must be assignable to System.Exception, but this type is '{exceptionType}'",
            span.StartLine,
            span.StartColumn,
            "Assert an Exception-derived type, or use a broader exception type such as Exception.",
            span.Length);
    }

    private void ReportNonThrowableThrowOperandIfNeeded(Expression expression, TypeInfo thrownType)
    {
        if (IsThrowableType(thrownType))
        {
            return;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.TypeMismatch,
            $"Throw expressions must be assignable to System.Exception, but this expression is '{thrownType}'",
            line,
            column,
            "Throw an Exception-derived value, or wrap this value in an exception type.",
            length);
    }

    private bool IsThrowableType(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);

        while (resolved is ObliviousTypeInfo oblivious)
        {
            resolved = _declarationContext.ResolveDeclaredAlias(oblivious.InnerType);
        }

        if (BuiltInTypes.Is(resolved, BuiltInTypes.Null) || BuiltInTypes.Is(resolved, BuiltInTypes.Never))
        {
            return true;
        }

        if (BuiltInTypes.IsUnknown(resolved) || resolved is ExternalTypeInfo)
        {
            return true;
        }

        if (resolved is NullableTypeInfo nullable)
        {
            return IsThrowableType(nullable.InnerType);
        }

        if (resolved is ReflectionTypeInfo reflectionType)
        {
            return AnalyzerConversionFacts.IsReflectionAssignableFrom(typeof(Exception), reflectionType.Type);
        }

        if (resolved is SimpleTypeInfo simple)
        {
            if (simple.Name is "Exception" or "System.Exception")
            {
                return true;
            }

            if (_scopes.LookupType(simple.Name) is { } namedType && !ReferenceEquals(namedType, resolved))
            {
                return IsThrowableType(namedType);
            }

            if (_clrTypeConversion.TryConvertTypeInfoToClrType(resolved) is { } clrType)
            {
                return AnalyzerConversionFacts.IsReflectionAssignableFrom(typeof(Exception), clrType);
            }

            return false;
        }

        if (resolved is ClassTypeInfo classType)
        {
            return classType.BaseClass != null
                && IsThrowableType(_typeSubstitution.ResolveTypeForSourceOwner(
                    classType.BaseClass,
                    classType,
                    substitution: null));
        }

        return false;
    }

    private void AnalyzeUsingStatement(UsingStatement usingStmt)
    {
        PushScope(new Scope(ScopeKind.Block), usingStmt.Line, usingStmt.Column);

        if (usingStmt.Declaration != null)
        {
            var resourceErrorsBefore = _errors.Count;
            AnalyzeVariableDeclaration(usingStmt.Declaration);
            if (_errors.Count == resourceErrorsBefore
                && _scopes.LookupSymbol(usingStmt.Declaration.Name) is { } resourceType)
            {
                ReportNonDisposableUsingResourceIfNeeded(usingStmt.Declaration, resourceType);
            }
        }
        else if (usingStmt.Expression != null)
        {
            var resourceType = AnalyzeExpression(usingStmt.Expression);
            if (!ReportSoaRowEscapeIfNeeded(usingStmt.Expression, resourceType, "used as a using resource")
                && !ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(usingStmt.Expression, "used as a using resource"))
            {
                ReportNonDisposableUsingResourceIfNeeded(usingStmt.Expression, resourceType);
            }
        }

        if (usingStmt.Body != null)
        {
            AnalyzeStatement(usingStmt.Body);
        }

        PopScope();
    }

    private void ReportNonDisposableUsingResourceIfNeeded(VariableDeclarationStatement declaration, TypeInfo resourceType)
    {
        if (IsDisposableUsingResourceType(resourceType))
        {
            return;
        }

        var (line, column, length) = AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(declaration);
        ReportNonDisposableUsingResource(resourceType, line, column, length);
    }

    private void ReportNonDisposableUsingResourceIfNeeded(Expression expression, TypeInfo resourceType)
    {
        if (IsDisposableUsingResourceType(resourceType))
        {
            return;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        ReportNonDisposableUsingResource(resourceType, line, column, length);
    }

    private void ReportNonDisposableUsingResource(TypeInfo resourceType, int line, int column, int length)
    {
        Error(
            ErrorCode.InvalidSyntax,
            $"Using resource of type '{resourceType}' must implement IDisposable or provide Dispose(): void",
            line,
            column,
            "Use a resource type with a parameterless void Dispose method, or remove the using statement.",
            length);
    }

    private bool IsDisposableUsingResourceType(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        if (BuiltInTypes.IsUnknown(resolved))
        {
            return true;
        }

        switch (resolved)
        {
            case ObliviousTypeInfo oblivious:
                return IsDisposableUsingResourceType(oblivious.InnerType);
            case ByRefTypeInfo byRef:
                return IsDisposableUsingResourceType(byRef.InnerType);
            case NullableTypeInfo nullable:
                var innerType = _declarationContext.ResolveDeclaredAlias(nullable.InnerType);
                return AnalyzerConversionFacts.IsReferenceType(innerType) && IsDisposableUsingResourceType(innerType);
            case SimpleTypeInfo simple when _scopes.LookupType(simple.Name) is { } namedType && !ReferenceEquals(namedType, resolved):
                return IsDisposableUsingResourceType(namedType);
            case GenericTypeInfo generic when _typeSubstitution.ResolveGenericDefinition(generic) is { } genericDefinition:
                return IsDisposableUsingResourceType(genericDefinition);
        }

        return HasDisposePattern(resolved) || IsNominallyIDisposable(resolved);
    }

    private bool HasDisposePattern(TypeInfo type)
    {
        type = _declarationContext.ResolveDeclaredAlias(type);
        return type switch
        {
            ClassTypeInfo classType => HasDisposePatternMember(classType.DeclaredMembers),
            StructTypeInfo structType => HasDisposePatternMember(structType.DeclaredMembers),
            RecordTypeInfo recordType => HasDisposePatternMember(recordType.DeclaredMembers),
            InterfaceTypeInfo interfaceType => HasDisposePatternMember(interfaceType.DeclaredMembers),
            ReflectionTypeInfo reflectionType => HasReflectionDisposePattern(reflectionType.Type),
            _ => false
        };
    }

    private bool HasDisposePatternMember(IEnumerable<DeclaredMemberInfo> members)
    {
        foreach (var member in members)
        {
            if (member.Kind != DeclaredMemberKind.Function
                || member.Name != nameof(IDisposable.Dispose)
                || member.IsStatic
                || member.ParameterCount != 0)
            {
                continue;
            }

            if (member.ReturnType == null || BuiltInTypes.Is(_typeResolver.ResolveType(member.ReturnType), BuiltInTypes.Void))
            {
                return true;
            }
        }

        return false;
    }

    private static bool HasReflectionDisposePattern(Type type)
    {
            var dispose = type.GetMethod(
                nameof(IDisposable.Dispose),
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
                binder: null,
                types: Type.EmptyTypes,
                modifiers: null);
            return dispose is { IsStatic: false, ReturnType: { } returnType }
                && returnType == typeof(void);
    }

    private bool IsNominallyIDisposable(TypeInfo type)
    {
        type = _declarationContext.ResolveDeclaredAlias(type);
        return type switch
        {
            ReflectionTypeInfo reflectionType => AnalyzerConversionFacts.IsReflectionAssignableFrom(typeof(IDisposable), reflectionType.Type),
            ClassTypeInfo or StructTypeInfo or RecordTypeInfo or InterfaceTypeInfo =>
                _assignability.IsSubtypeOf(type, new ReflectionTypeInfo(typeof(IDisposable))),
            _ => false
        };
    }

    private void AnalyzeLockStatement(LockStatement lockStmt)
    {
        // NL320 (the CS0185 analog): the lockee must be a reference type. Monitor locks on object
        // IDENTITY — a value-typed lockee has none (it would be boxed into a fresh object per lock,
        // guarding nothing), and the IL emitter's `stloc` of a raw value into an object local is
        // unverifiable IL that segfaults the process inside Monitor.Enter.
        var lockeeType = _declarationContext.ResolveDeclaredAlias(AnalyzeExpression(lockStmt.LockObject));

        if (lockeeType is SoaRowTypeInfo)
        {
            ReportSoaRowEscape(lockStmt.LockObject, "locked");
        }
        else if (!ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(lockStmt.LockObject, "locked")
                 && lockeeType is SimpleTypeInfo named
                 && TryGetEnclosingTypeParameter(named.Name, out var isReferenceConstrained))
        {
            // Stricter by design: an unconstrained T would require boxing and could never
            // provide mutual exclusion); N# requires the type parameter to be provably a reference.
            if (!isReferenceConstrained)
            {
                ReportLockRequiresReferenceType(lockStmt.LockObject, named.Name, isTypeParameter: true);
            }
        }
        else if (IsKnownValueTypeLockee(lockeeType))
        {
            ReportLockRequiresReferenceType(lockStmt.LockObject, lockeeType.ToString(), isTypeParameter: false);
        }

        // Analyze the body with a new scope
        PushScope(new Scope(ScopeKind.Block), lockStmt.Line, lockStmt.Column);
        AnalyzeStatement(lockStmt.Body);
        PopScope();
    }

    private void ReportLockRequiresReferenceType(Expression lockee, string typeName, bool isTypeParameter)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(lockee);
        var sourceSnippet = GetSourceSnippet(line);
        if (sourceSnippet != null && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.LockRequiresReferenceType(
                _currentFilePath, line, column, sourceSnippet, length, typeName, isTypeParameter));
        }
        else
        {
            Error(
                ErrorCode.LockRequiresReferenceType,
                $"'{typeName}' is not a reference type as required by the lock statement",
                line,
                column,
                isTypeParameter
                    ? $"Constrain `{typeName}` to a reference type (`where {typeName}: class`), or lock on a dedicated `object` field instead: `sync: object = new object()`"
                    : "Lock on a dedicated `object` field instead: `sync: object = new object()`",
                length);
        }
    }

    /// <summary>
    /// Whether <paramref name="name"/> is a generic type parameter of the enclosing function or type,
    /// and if so whether its constraints prove it is a reference type (`where T: class`, or a base
    /// CLASS constraint — interface constraints prove nothing, since structs implement interfaces).
    /// </summary>
    private bool TryGetEnclosingTypeParameter(string name, out bool isReferenceConstrained)
    {
        isReferenceConstrained = false;

        var declaredOnFunction = _currentFunction?.TypeParameters?.Any(tp => tp.Name == name) == true;
        var declaredOnType = _currentClass?.TypeParameters?.Any(tp => tp.Name == name) == true;
        if (!declaredOnFunction && !declaredOnType)
            return false;

        var constraint = declaredOnFunction
            ? _currentFunction?.Constraints?.FirstOrDefault(c => c.TypeParameter == name)
            : null;
        if (constraint != null)
        {
            if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.Class))
            {
                isReferenceConstrained = true;
                return true;
            }

            foreach (var constraintTypeRef in constraint.Constraints)
            {
                var constraintType = _declarationContext.ResolveDeclaredAlias(_typeResolver.ResolveType(constraintTypeRef));
                var isClassConstraint = constraintType switch
                {
                    ClassTypeInfo => true,
                    RecordTypeInfo record => !record.IsStruct,
                    ReflectionTypeInfo refl => refl.Type.IsClass,
                    _ => false
                };
                if (isClassConstraint)
                {
                    isReferenceConstrained = true;
                    return true;
                }
            }
        }

        return true;
    }

    /// <summary>
    /// Whether the type is a KNOWN value type for the NL320 lockee check. Deliberately conservative —
    /// the inverse of <see cref="AnalyzerConversionFacts.IsReferenceType"/> would false-positive: that predicate answers
    /// "can this be assigned null" and returns false for Unknown/External/GenericTypeInfo, which must
    /// stay SILENT here (rejecting a type the analyzer cannot classify would break locks on external
    /// .NET reference types).
    /// </summary>
    private bool IsKnownValueTypeLockee(TypeInfo type)
    {
        switch (type)
        {
            case SimpleTypeInfo simple:
                if (simple.Name is "int" or "long" or "float" or "double" or "decimal"
                    or "byte" or "sbyte" or "short" or "ushort"
                    or "uint" or "ulong" or "char" or "bool" or "void")
                {
                    return true;
                }
                // A bare name can reach here for a user struct/enum the expression analysis did not
                // materialize into its declaration-backed TypeInfo — resolve it and re-classify.
                var resolved = _scopes.LookupType(simple.Name);
                return resolved != null && resolved is not SimpleTypeInfo && IsKnownValueTypeLockee(resolved);
            case StructTypeInfo:
            case EnumTypeInfo:
            case TupleTypeInfo: // ValueTuple
                return true;
            case RecordTypeInfo record:
                return record.IsStruct;
            case NullableTypeInfo nullable:
                // `T?` over a value type is Nullable<T> — itself a struct. Over a reference type it
                // is only a nullability annotation.
                return IsKnownValueTypeLockee(nullable.InnerType);
            case ObliviousTypeInfo oblivious:
                return IsKnownValueTypeLockee(oblivious.InnerType);
            case ByRefTypeInfo byRef:
                // The byref loads the referenced value when used as an expression.
                return IsKnownValueTypeLockee(byRef.InnerType);
            case ReflectionTypeInfo refl:
                return refl.Type.IsValueType;
            default:
                // Unknown / External / GenericTypeInfo / class-like: stay silent.
                return false;
        }
    }

    private void AnalyzeSwitchStatement(SwitchStatement switchStmt)
    {
        var valueType = AnalyzeExpression(switchStmt.Value);
        if (ReportSoaRowEscapeIfNeeded(switchStmt.Value, valueType, "used as a switch value")
            || ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(switchStmt.Value, "used as a switch value"))
        {
            valueType = BuiltInTypes.Unknown;
        }

        // A `break` in a case body targets the switch itself (the emitter pushes a break label per
        // switch), so for NL319 the break target's finally depth is the switch's entry depth.
        // `continue` still targets the enclosing loop, so its depth is untouched.
        var savedBreakDepth = _breakTargetFinallyDepth;
        _breakTargetFinallyDepth = _finallyDepth;

        foreach (var switchCase in switchStmt.Cases)
        {
            PushScope(new Scope(ScopeKind.Block), switchStmt.Line, switchStmt.Column);

            // Analyze pattern if present
            if (switchCase.Pattern != null)
            {
                AnalyzePattern(switchCase.Pattern, valueType);
            }

            AnalyzeStatements(switchCase.Statements);

            PopScope();
        }

        _breakTargetFinallyDepth = savedBreakDepth;
    }

    private void AnalyzePattern(Pattern pattern, TypeInfo valueType)
    {
        switch (pattern)
        {
            case IdentifierPattern identPattern:
                // Check if this is a qualified union case name (e.g., "Result.Success")
                if (valueType is NullableTypeInfo nullableValueType && !identPattern.Name.Contains('.'))
                {
                    if (identPattern.Name != "_")
                    {
                        DeclareSymbol(identPattern.Name, nullableValueType.InnerType, identPattern.Line, identPattern.Column);
                    }
                }
                else if (identPattern.Name.Contains('.')
                    && TryResolveDeclaredUnionType(valueType, out var ut, out _))
                {
                    if (!TryGetUnionCaseForPattern(ut, identPattern.Name, out _))
                    {
                        var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                            _spans.GetPatternNameDiagnosticSpan(identPattern);
                        Error(ErrorCode.InvalidPattern,
                            $"'{identPattern.Name}' is not a case of union '{ut}' — check the union definition for available cases",
                            diagnosticLine, diagnosticColumn, length: diagnosticLength);
                    }
                    // For union cases without properties, no variables to bind
                }
                else
                {
                    // Regular identifier pattern - bind the identifier to the value type
                    DeclareSymbol(identPattern.Name, valueType, identPattern.Line, identPattern.Column);
                }
                break;

            case LiteralPattern literalPattern:
                // Just analyze the literal expression for type checking
                var literalType = AnalyzeExpression(literalPattern.Literal);
                ReportSoaRowEscapeIfNeeded(literalPattern.Literal, literalType, "used as a pattern value");
                ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(literalPattern.Literal, "used as a pattern value");
                break;

            case UnionCasePattern unionPattern:
                // Verify the union case exists if matching against a union type
                // (including a closed generic instantiation like Result<int>).
                if (TryResolveDeclaredUnionType(valueType, out var unionType, out var unionSubstitution))
                {
                    var caseName = GetUnionCaseName(unionPattern.CaseName);

                    if (!TryGetUnionCaseForPattern(unionType, unionPattern.CaseName, out var matchingCase))
                    {
                        var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                            _spans.GetPatternNameDiagnosticSpan(unionPattern);
                        Error(ErrorCode.InvalidPattern,
                            $"'{unionPattern.CaseName}' is not a case of union '{unionType}' — check the union definition for available cases",
                            diagnosticLine, diagnosticColumn, length: diagnosticLength);
                    }
                    else if (unionPattern.Properties != null)
                    {
                        // Bind property patterns to their types
                        if (matchingCase.Properties == null)
                        {
                            var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                                _spans.GetPatternNameDiagnosticSpan(unionPattern);
                            Error(ErrorCode.InvalidPattern,
                                $"Union case '{caseName}' doesn't carry any data — you can't destructure it with property patterns",
                                diagnosticLine, diagnosticColumn, length: diagnosticLength);
                        }
                        else if (matchingCase.Properties.Count == 0)
                        {
                            var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                                _spans.GetPatternNameDiagnosticSpan(unionPattern);
                            Error(ErrorCode.InvalidPattern,
                                $"Union case '{caseName}' doesn't carry any data — you can't destructure it with property patterns",
                                diagnosticLine, diagnosticColumn, length: diagnosticLength);
                        }
                        else
                        {
                            // Analyze each property pattern (supports nested patterns)
                            foreach (var propPattern in unionPattern.Properties)
                            {
                                var caseProperty = matchingCase.Properties
                                    .FirstOrDefault(p => p.Name == propPattern.Name);

                                if (caseProperty != null)
                                {
                                    var propType = _typeSubstitution.ResolveTypeForSourceOwner(
                                        caseProperty.Type,
                                        unionType,
                                        unionSubstitution);

                                    // If there's a nested pattern, analyze it recursively
                                    if (propPattern.Pattern != null)
                                    {
                                        AnalyzePattern(propPattern.Pattern, propType);
                                    }
                                    else
                                    {
                                        // Simple binding
                                        var bindingName = propPattern.BindingName ?? propPattern.Name;
                                        var (bindingLine, bindingColumn, _) =
                                            _spans.GetPropertyPatternNameDiagnosticSpan(propPattern, pattern.Line, pattern.Column);
                                        DeclareSymbol(bindingName, propType, bindingLine, bindingColumn);
                                    }
                                }
                                else
                                {
                                    var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                                        _spans.GetPropertyPatternNameDiagnosticSpan(propPattern, pattern.Line, pattern.Column);
                                    Error(ErrorCode.InvalidPattern,
                                        $"Union case '{caseName}' doesn't have a property named '{propPattern.Name}' — check the case definition for available properties",
                                        diagnosticLine, diagnosticColumn, length: diagnosticLength);
                                }
                            }
                        }
                    }
                }
                break;

            case RelationalPattern relationalPattern:
                var relationalValueType = AnalyzeExpression(relationalPattern.Value);
                if (!ReportSoaRowEscapeIfNeeded(relationalPattern.Value, relationalValueType, "used as a relational pattern value")
                    && !ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(relationalPattern.Value, "used as a relational pattern value"))
                {
                    ValidateRelationalPattern(relationalPattern, valueType, relationalValueType);
                }
                break;

            case AndPattern andPattern:
                // Both patterns must be valid for the value type
                AnalyzePattern(andPattern.Left, valueType);
                AnalyzePattern(andPattern.Right, valueType);
                break;

            case OrPattern orPattern:
                // Either pattern must be valid for the value type
                AnalyzePattern(orPattern.Left, valueType);
                AnalyzePattern(orPattern.Right, valueType);
                break;

            case NotPattern notPattern:
                // The inner pattern must be valid for the value type
                AnalyzePattern(notPattern.Pattern, valueType);
                break;

            case PositionalPattern positionalPattern:
                // For tuple types, analyze each pattern against the corresponding element type
                // For now, we'll just analyze each pattern with the same value type
                foreach (var p in positionalPattern.Patterns)
                {
                    AnalyzePattern(p, valueType);
                }
                break;

            case ObjectPattern objectPattern:
                // Object pattern matches properties on any type (not just unions)
                AnalyzePropertyPatterns(objectPattern.Properties, valueType, pattern.Line, pattern.Column);
                break;

            case ListPattern listPattern:
                // List pattern lowering requires a stable Count/Length and int indexer.
                if (!TryGetListPatternElementType(valueType, out var elementType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                        _spans.GetListPatternDiagnosticSpan(listPattern);
                    Error(ErrorCode.PatternTypeMismatch,
                        $"A list pattern can only match arrays or indexable collections, but this value is '{valueType}'",
                        diagnosticLine, diagnosticColumn, length: diagnosticLength);
                    elementType = BuiltInTypes.Unknown; // fallback to avoid cascading errors
                }

                // Analyze each element pattern
                foreach (var elemPattern in listPattern.Elements)
                {
                    if (elemPattern is SlicePattern slicePattern)
                    {
                        // Slice pattern captures an array/list of elements
                        if (slicePattern.BindingName != null)
                        {
                            // Bind the slice to an array of the element type
                            var sliceType = new ArrayTypeInfo(elementType);
                            DeclareSymbol(slicePattern.BindingName, sliceType, pattern.Line, pattern.Column);
                        }
                    }
                    else
                    {
                        // Regular pattern - analyze with element type
                        AnalyzePattern(elemPattern, elementType);
                    }
                }
                break;

            case SlicePattern slicePattern:
                // Slice patterns should only appear within list patterns
                // This case shouldn't be reached, but handle it gracefully
                if (slicePattern.BindingName != null)
                {
                    // Bind to array type (best guess)
                    DeclareSymbol(slicePattern.BindingName, new ArrayTypeInfo(valueType), pattern.Line, pattern.Column);
                }
                break;

            case TypePattern typePattern:
                // Type pattern checks if value is of a specific type and binds it
                var targetType = _typeResolver.ResolveType(typePattern.Type);

                // Check if pattern is provably impossible
                if (!IsPatternPossible(valueType, targetType))
                {
                    var (impossibleLine, impossibleColumn, impossibleLength) =
                        _spans.GetPatternNameDiagnosticSpan(typePattern);
                    Error(ErrorCode.ImpossiblePattern,
                        $"This '{targetType}' pattern can never match — a '{valueType}' is never a '{targetType}'",
                        impossibleLine, impossibleColumn, length: impossibleLength);
                }

                // Bind the variable if a binding name is provided
                if (typePattern.BindingName != null)
                {
                    DeclareSymbol(typePattern.BindingName, targetType, pattern.Line, pattern.Column);
                }
                break;
        }
    }

    private bool TryGetListPatternElementType(TypeInfo valueType, out TypeInfo elementType)
    {
        valueType = _declarationContext.ResolveDeclaredAlias(valueType);
        elementType = BuiltInTypes.Unknown;

        if (valueType is ArrayTypeInfo arrayType)
        {
            elementType = arrayType.ElementType;
            return true;
        }

        if (valueType is GenericTypeInfo genericType && IsIndexableGenericListPatternType(genericType.Name))
        {
            elementType = genericType.TypeArguments.Count > 0
                ? genericType.TypeArguments[0]
                : BuiltInTypes.Unknown;
            return true;
        }

        if (valueType is ReflectionTypeInfo reflectionType)
        {
            return TryGetReflectionListPatternElementType(reflectionType.Type, out elementType);
        }

        return false;
    }

    private void ValidateRelationalPattern(
        RelationalPattern pattern,
        TypeInfo valueType,
        TypeInfo patternValueType)
    {
        var resolvedValueType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(valueType));
        var resolvedPatternValueType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(patternValueType));
        if (BuiltInTypes.IsUnknown(resolvedValueType) || BuiltInTypes.IsUnknown(resolvedPatternValueType))
        {
            return;
        }

        var allowBool = IsEqualityPatternOperator(pattern.Operator);
        if (IsNullableRelationalPatternType(valueType)
            || IsNullableRelationalPatternType(patternValueType)
            || !IsRelationalPatternComparableType(resolvedValueType, allowBool)
            || !IsRelationalPatternComparableType(resolvedPatternValueType, allowBool)
            || !_assignability.IsAssignable(valueType, patternValueType))
        {
            ReportRelationalPatternTypeMismatch(pattern, valueType, patternValueType);
        }
    }

    private static bool IsEqualityPatternOperator(string op)
        => op is "==" or "!=";

    private bool IsNullableRelationalPatternType(TypeInfo type)
    {
        type = _declarationContext.ResolveDeclaredAlias(type);
        return type is NullableTypeInfo
            || type is ReflectionTypeInfo reflection && Nullable.GetUnderlyingType(reflection.Type) != null;
    }

    private bool IsRelationalPatternComparableType(TypeInfo type, bool allowBool)
    {
        type = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(type));
        if (allowBool && IsBoolType(type))
        {
            return true;
        }

        if (BuiltInTypes.Is(type, BuiltInTypes.Decimal))
        {
            return false;
        }

        if (IsNumericType(type))
        {
            return true;
        }

        if (type is ReflectionTypeInfo reflection)
        {
            var runtimeType = Nullable.GetUnderlyingType(reflection.Type) ?? reflection.Type;
            if (allowBool && runtimeType == typeof(bool))
            {
                return true;
            }

            return runtimeType != typeof(decimal)
                && (runtimeType == typeof(byte)
                    || runtimeType == typeof(sbyte)
                    || runtimeType == typeof(short)
                    || runtimeType == typeof(ushort)
                    || runtimeType == typeof(int)
                    || runtimeType == typeof(uint)
                    || runtimeType == typeof(long)
                    || runtimeType == typeof(ulong)
                    || runtimeType == typeof(float)
                    || runtimeType == typeof(double)
                    || runtimeType == typeof(char));
        }

        return false;
    }

    private void ReportRelationalPatternTypeMismatch(
        RelationalPattern pattern,
        TypeInfo valueType,
        TypeInfo patternValueType)
    {
        Error(
            ErrorCode.TypeMismatch,
            $"Relational pattern '{pattern.Operator}' can't compare '{valueType}' with '{patternValueType}' before IL emission",
            pattern.Line,
            pattern.Column,
            "Use numeric operands with a supported common type, use a literal pattern for string equality, or move custom comparisons into a match guard.",
            Math.Max(1, pattern.Operator.Length));
    }

    private static bool IsIndexableGenericListPatternType(string name)
        => name is "List" or "IList" or "IReadOnlyList";

    private static bool TryGetReflectionListPatternElementType(Type type, out TypeInfo elementType)
    {
        elementType = BuiltInTypes.Unknown;
        if (type.IsArray)
        {
            var arrayElementType = type.GetElementType();
            if (arrayElementType == null)
            {
                return false;
            }

            elementType = new ReflectionTypeInfo(arrayElementType);
            return true;
        }

        const BindingFlags bindingFlags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
            var shapeTypes = GetListPatternShapeTypes(type).ToArray();
            var lengthProperty = shapeTypes
                .Select(shapeType => shapeType.GetProperty("Count", bindingFlags)
                    ?? shapeType.GetProperty("Length", bindingFlags))
                .FirstOrDefault(property => property?.GetMethod != null && property.PropertyType == typeof(int));
            if (lengthProperty?.GetMethod == null || lengthProperty.PropertyType != typeof(int))
            {
                return false;
            }

            var indexerProperty = shapeTypes
                .SelectMany(shapeType => shapeType.GetProperties(bindingFlags))
                .FirstOrDefault(property =>
                {
                    if (property.GetMethod == null)
                    {
                        return false;
                    }

                    var parameters = property.GetIndexParameters();
                    return parameters.Length == 1 && parameters[0].ParameterType == typeof(int);
                });

            if (indexerProperty?.GetMethod == null)
            {
                return false;
            }

            elementType = new ReflectionTypeInfo(indexerProperty.PropertyType);
            return true;
    }

    private static IEnumerable<Type> GetListPatternShapeTypes(Type type)
    {
        yield return type;

        if (!type.IsInterface)
        {
            yield break;
        }

        foreach (var inheritedInterface in type.GetInterfaces())
        {
            yield return inheritedInterface;
        }
    }

    private void AnalyzePropertyPatterns(List<PropertyPattern> propertyPatterns, TypeInfo valueType, int line, int column)
    {
        var declarationOwner = valueType;
        Dictionary<string, TypeInfo>? substitution = null;
        if (valueType is GenericTypeInfo genericValue
            && _typeSubstitution.ResolveGenericDefinition(genericValue) is { } genericDefinition)
        {
            declarationOwner = genericDefinition;
            substitution = _declarationContext.CreateGenericSubstitution(
                genericDefinition,
                genericValue.TypeArguments);
        }

        // For each property pattern, validate the property exists and analyze nested patterns
        foreach (var propPattern in propertyPatterns)
        {
            // Try to resolve the property on the value type
            TypeInfo? propType = null;
            if (_declarationContext.TryGetSourceMemberShape(
                    declarationOwner, substitution, out var sourceShape)
                && _declarationContext.TryResolveDeclaredValueMember(
                    sourceShape.Owner,
                    sourceShape.DeclaredMembers,
                    propPattern.Name,
                    substitution,
                    out var resolvedPropertyType))
            {
                propType = resolvedPropertyType;
            }

            if (propType == null && valueType is ReflectionTypeInfo reflectionType)
            {
                // Use reflection to find the property
                var prop = reflectionType.Type.GetProperty(propPattern.Name);
                if (prop != null)
                {
                    propType = NullabilityMetadataReflection.ConvertProperty(prop);
                }
            }

            if (propType == null)
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                    _spans.GetPropertyPatternNameDiagnosticSpan(propPattern, line, column);
                Error(ErrorCode.InvalidPattern,
                    $"'{valueType}' doesn't have a property named '{propPattern.Name}'",
                    diagnosticLine, diagnosticColumn, length: diagnosticLength);
                continue;
            }

            // If there's a nested pattern, analyze it recursively
            if (propPattern.Pattern != null)
            {
                AnalyzePattern(propPattern.Pattern, propType);
            }
            else
            {
                // Simple binding - use BindingName if provided, otherwise use property Name
                var bindingName = propPattern.BindingName ?? propPattern.Name;
                var (bindingLine, bindingColumn, _) =
                    _spans.GetPropertyPatternNameDiagnosticSpan(propPattern, line, column);
                DeclareSymbol(bindingName, propType, bindingLine, bindingColumn);
            }
        }
    }

    private TypeInfo AnalyzeExpression(Expression expr)
    {
        var type = expr switch
        {
            IntLiteralExpression intLiteral => GetIntLiteralType(intLiteral.Value),
            FloatLiteralExpression floatLiteral => NumericLiteralFacts.GetFloatLiteralTypeInfo(floatLiteral.Value),
            CharLiteralExpression => BuiltInTypes.Char,
            StringLiteralExpression strExpr => AnalyzeStringLiteral(strExpr),
            InterpolatedStringExpression interpolated => AnalyzeInterpolatedString(interpolated),
            BoolLiteralExpression => BuiltInTypes.Bool,
            NullLiteralExpression => BuiltInTypes.Null,
            IdentifierExpression ident => ResolveIdentifier(ident.Name, ident.Line, ident.Column),
            BinaryExpression binary => AnalyzeBinaryExpression(binary),
            UnaryExpression unary => AnalyzeUnaryExpression(unary),
            MustExpression must => AnalyzeMustExpression(must),
            MemberAccessExpression member => AnalyzeMemberAccess(member),
            IndexAccessExpression index => AnalyzeIndexAccess(index),
            CallExpression call => AnalyzeCall(call),
            AssignmentExpression assignment => AnalyzeAssignment(assignment),
            OnSubscriptionExpression on => AnalyzeOnSubscription(on),
            LambdaExpression lambda => AnalyzeLambda(lambda, _currentExpectedType),
            TernaryExpression ternary => AnalyzeTernary(ternary),
            TupleExpression tuple => AnalyzeTupleExpression(tuple),
            ArrayLiteralExpression array => AnalyzeArrayLiteral(array),
            NewExpression newExpr => AnalyzeNewExpression(newExpr),
            AllocExpression alloc => AnalyzeAllocExpression(alloc),
            StackAllocExpression stackAlloc => AnalyzeStackAllocExpression(stackAlloc),
            CastExpression cast => AnalyzeCastExpression(cast),
            IsExpression isExpr => AnalyzeIsExpression(isExpr),
            AwaitExpression await => AnalyzeAwaitExpression(await),
            ThrowExpression throwExpr => AnalyzeThrowExpression(throwExpr),
            ThisExpression => _scopes.CurrentTypeScope() ?? BuiltInTypes.Unknown,
            BaseExpression => AnalyzeBaseExpression(),
            MatchExpression match => AnalyzeMatchExpression(match),
            TypeOfExpression typeofExpr => AnalyzeTypeofExpression(typeofExpr),
            NameofExpression nameofExpr => AnalyzeNameofExpression(nameofExpr),
            SizeOfExpression sizeofExpr => AnalyzeSizeofExpression(sizeofExpr),
            CheckedExpression checkedExpr => AnalyzeCheckedExpression(checkedExpr),
            UncheckedExpression uncheckedExpr => AnalyzeUncheckedExpression(uncheckedExpr),
            RangeExpression range => AnalyzeRangeExpression(range),
            SpreadExpression spread => AnalyzeSpreadExpression(spread),
            WithExpression with => AnalyzeWithExpression(with),
            ParenthesizedExpression paren => AnalyzeExpression(paren.Inner),
            DefaultExpression defaultExpr => AnalyzeDefaultExpression(defaultExpr),
            _ => BuiltInTypes.Unknown
        };

        var nullState = GetExpressionNullState(expr, type);
        var flowType = ApplyNullabilityFlowType(expr, type, nullState);

        _semanticModel.RecordExpressionType(expr.Line, expr.Column, flowType);
        _semanticModel.RecordExpressionNullState(expr.Line, expr.Column, nullState);

        // While an ASSIGNMENT TARGET is being analyzed, record every sub-expression's resolved type
        // (reference-keyed — the semantic model's line/column keys collide for nested chains sharing
        // a start position). The NL322 receiver-chain classifier reads these instead of re-analyzing,
        // which would duplicate every diagnostic the receiver produces.
        if (_assignmentTargetExpressionTypes != null)
            _assignmentTargetExpressionTypes[expr] = flowType;

        if (!_allowSyntheticSoaOperationReference
            && flowType is FunctionTypeInfo { SyntheticName: { Length: > 0 } } syntheticSoaOperation
            && !AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(syntheticSoaOperation))
        {
            ReportSyntheticSoaOperationUsedAsValue(expr, syntheticSoaOperation);
            return BuiltInTypes.Unknown;
        }

        if (!_analyzingCallCallee
            && ReportUnsupportedSoaDirectColumnArrayInstanceMethodReferenceIfNeeded(expr, flowType, isCall: false))
        {
            return BuiltInTypes.Unknown;
        }

        if (!_allowUnboundCallableReference
            && _reflectionCallReporter.IsUnboundCallableReference(expr, flowType, _currentExpectedType))
        {
            _reflectionCallReporter.ReportMethodGroupUsedAsValue(expr, flowType);
            return BuiltInTypes.Unknown;
        }

        // A .NET event can only be touched via `on`/`off`. Catch every other use of it as a value
        // here (the `on`/`off`/assignment paths set _allowEventReference to opt out and emit their
        // own tailored diagnostics).
        if (!_allowEventReference && flowType is ReflectionEventInfo bareEvent)
        {
            ReportEventUsedAsValue(expr, bareEvent);
            return BuiltInTypes.Unknown;
        }

        return flowType;
    }

    private TypeInfo AnalyzeExpressionAllowingUnboundCallableReference(Expression expression)
    {
        var previous = _allowUnboundCallableReference;
        _allowUnboundCallableReference = true;
        try
        {
            return AnalyzeExpression(expression);
        }
        finally
        {
            _allowUnboundCallableReference = previous;
        }
    }

    private TypeInfo AnalyzeCallCalleeExpression(Expression expression)
    {
        var previousAllowUnbound = _allowUnboundCallableReference;
        var previousAllowSyntheticSoaOperation = _allowSyntheticSoaOperationReference;
        var previousAnalyzingCallCallee = _analyzingCallCallee;
        _allowUnboundCallableReference = true;
        _allowSyntheticSoaOperationReference = true;
        _analyzingCallCallee = true;
        try
        {
            return AnalyzeExpression(expression);
        }
        finally
        {
            _analyzingCallCallee = previousAnalyzingCallCallee;
            _allowSyntheticSoaOperationReference = previousAllowSyntheticSoaOperation;
            _allowUnboundCallableReference = previousAllowUnbound;
        }
    }

    private TypeInfo AnalyzeExpressionPreservingNullabilityFlowType(Expression expression)
    {
        var previous = _suppressNullabilityFlowType;
        _suppressNullabilityFlowType = true;
        try
        {
            return AnalyzeExpression(expression);
        }
        finally
        {
            _suppressNullabilityFlowType = previous;
        }
    }

    private void ReportSyntheticSoaOperationUsedAsValue(Expression expression, FunctionTypeInfo operation)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        var operationName = operation.SyntheticName ?? "operation";
        var callTarget = RenderSyntheticSoaOperationTarget(expression, operationName);
        var callShape = operation.ParameterTypes is { Count: 0 }
            ? $"{callTarget}()"
            : $"{callTarget}(...)";
        Error(
            ErrorCode.InvalidSyntax,
            $"SoA table generated operation '{operationName}' cannot be used as a value",
            line,
            column,
            $"Call {callShape} directly; generated SoA operations mutate table storage and are not delegate values.",
            length);
    }

    private static string RenderSyntheticSoaOperationTarget(Expression expression, string fallbackName)
    {
        return expression switch
        {
            MemberAccessExpression memberAccess => RenderEventTarget(memberAccess),
            ParenthesizedExpression parenthesized => RenderSyntheticSoaOperationTarget(parenthesized.Inner, fallbackName),
            CheckedExpression checkedExpression => RenderSyntheticSoaOperationTarget(checkedExpression.Expression, fallbackName),
            UncheckedExpression uncheckedExpression => RenderSyntheticSoaOperationTarget(uncheckedExpression.Expression, fallbackName),
            _ => fallbackName
        };
    }

    private TypeInfo ApplyNullabilityFlowType(Expression expr, TypeInfo type, NullState nullState)
    {
        if (_suppressNullabilityFlowType)
            return type;

        return nullState == NullState.NotNull && type is NullableTypeInfo nullable
            ? nullable.InnerType
            : type;
    }

    private NullState GetExpressionNullState(Expression expr, TypeInfo type)
    {
        if (expr is NullLiteralExpression)
            return NullState.Null;

        if (expr is NewExpression or ArrayLiteralExpression or LambdaExpression or InterpolatedStringExpression)
            return NullState.NotNull;

        if (expr is StringLiteralExpression or IntLiteralExpression or FloatLiteralExpression
            or CharLiteralExpression or BoolLiteralExpression or TypeOfExpression or NameofExpression)
        {
            return NullState.NotNull;
        }

        if (expr is ParenthesizedExpression parenthesized)
            return GetExpressionNullState(parenthesized.Inner, type);

        if (expr is MemberAccessExpression { IsNullConditional: true }
            || expr is IndexAccessExpression { IsNullConditional: true })
        {
            return NullState.MaybeNull;
        }

        var path = AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(expr);
        if (path != null && _scopes.HasNullState(path))
            return _scopes.NullStateOrUnknown(path);

        return GetDefaultNullState(type);
    }

    private NullState GetDefaultNullState(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);

        if (BuiltInTypes.Is(resolved, BuiltInTypes.Null))
            return NullState.Null;

        if (resolved is NullableTypeInfo)
            return NullState.MaybeNull;

        if (resolved is UnknownTypeInfo)
            return NullState.Unknown;

        if (resolved is ReflectionTypeInfo reflectionType)
        {
            return reflectionType.Type.IsValueType && Nullable.GetUnderlyingType(reflectionType.Type) == null
                ? NullState.NotNull
                : NullState.Oblivious;
        }

        return NullState.NotNull;
    }

    private static bool IsUnsafeNullState(NullState state)
        => state is NullState.Null or NullState.MaybeNull;

    private TypeInfo AnalyzeDefaultExpression(DefaultExpression defaultExpr)
    {
        // Target-typed: use _currentExpectedType if available
        if (_currentExpectedType != null)
        {
            if (ReportSoaDefaultValueIfNeeded(defaultExpr, _currentExpectedType))
            {
                return BuiltInTypes.Unknown;
            }

            return _currentExpectedType;
        }

        // If no expected type context, report an error
        Error(
            ErrorCode.CannotInferType,
            "I can't figure out what type 'default' should be here — add a type annotation so I know what you mean (e.g., 'let x: int = default')",
            defaultExpr.Line,
            defaultExpr.Column,
            length: "default".Length);
        return BuiltInTypes.Unknown;
    }

    private bool ReportSoaDefaultValueIfNeeded(DefaultExpression defaultExpr, TypeInfo expectedType)
    {
        var resolvedExpectedType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(expectedType));
        if (resolvedExpectedType is not SoaRecordTypeInfo soaRecordType)
            return false;

        Error(
            ErrorCode.InvalidSyntax,
            $"SoA table '{soaRecordType.Declaration.Name}' cannot be default-initialized",
            defaultExpr.Line,
            defaultExpr.Column,
            $"Use new {soaRecordType.Declaration.Name}(capacity) or {soaRecordType.Declaration.Name}.wrap(..., length: count) so every backing column array is valid.",
            "default".Length);
        return true;
    }

    private static bool IsAnonymousObjectCreation(NewExpression newExpr)
        => newExpr.Type == null
            && newExpr.ConstructorArguments.Count == 0
            && newExpr.Initializer != null
            && newExpr.Initializer.Properties.All(property =>
                property.Name != null
                && property.IndexExpression == null);

    private void ReportCannotInferTargetTypedNew(NewExpression newExpr)
    {
        var shape = newExpr.ConstructorArguments.Count == 0 ? "new()" : "new(...)";
        Error(
            ErrorCode.CannotInferType,
            $"I can't figure out what type '{shape}' should create here — add a type annotation or write the type after 'new'",
            newExpr.Line,
            newExpr.Column,
            "For example, use `value: Person = new()` when the target type is clear, or `new Person()` when it is not.",
            "new".Length);
    }

    private TypeInfo AnalyzeRangeExpression(RangeExpression range)
    {
        // Analyze start if present
        if (range.Start != null)
        {
            var startType = AnalyzeExpression(range.Start);
            if (!ReportSoaRowEscapeIfNeeded(range.Start, startType, "used as a range bound")
                && !ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(range.Start, "used as a range bound"))
            {
                CheckRangeEndpoint(range.Start, startType);
            }
        }

        // Analyze end if present
        if (range.End != null)
        {
            var endType = AnalyzeExpression(range.End);
            if (!ReportSoaRowEscapeIfNeeded(range.End, endType, "used as a range bound")
                && !ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(range.End, "used as a range bound"))
            {
                CheckRangeEndpoint(range.End, endType);
            }
        }

        // All range expressions return System.Range
        return GetRangeType();
    }

    private void CheckRangeEndpoint(Expression endpoint, TypeInfo endpointType)
    {
        if (BuiltInTypes.IsUnknown(endpointType) || IsRangeEndpointType(endpointType))
        {
            return;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(endpoint);
        Error(
            ErrorCode.TypeMismatch,
            $"Range bounds must be int or System.Index, but this bound has type '{endpointType}'",
            line,
            column,
            "Use an int bound, '^n' with an int count, or convert the value before building the range.",
            length);
    }

    private TypeInfo AnalyzeSpreadExpression(SpreadExpression spread)
    {
        // Analyze the inner expression
        var innerType = AnalyzeExpression(spread.Expression);
        if (ReportSoaRowEscapeIfNeeded(spread.Expression, innerType, "spread"))
        {
            return BuiltInTypes.Unknown;
        }
        if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(spread.Expression, "spread"))
        {
            return BuiltInTypes.Unknown;
        }

        // For spread in function calls, we expect the inner expression to be an array or enumerable.
        // Later validation reports invalid spread shapes; for now, return the inner collection type.
        return innerType;
    }

    private TypeInfo AnalyzeAllocExpression(AllocExpression alloc)
    {
        var innerType = AnalyzeExpression(alloc.Expression);
        if (innerType is SoaRowTypeInfo)
        {
            ReportSoaRowHiddenAllocation(alloc.Expression);
            return BuiltInTypes.Unknown;
        }
        if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(alloc.Expression, "used in an alloc expression"))
        {
            return BuiltInTypes.Unknown;
        }

        return innerType;
    }

    private TypeInfo AnalyzeStringLiteral(StringLiteralExpression strExpr)
        => BuiltInTypes.String;

    private TypeInfo AnalyzeInterpolatedString(InterpolatedStringExpression expr)
    {
        foreach (var part in expr.Parts)
        {
            if (part is InterpolatedStringHole hole)
            {
                var holeType = AnalyzeExpression(hole.Expression);
                ReportSoaRowEscapeIfNeeded(hole.Expression, holeType, "formatted in an interpolated string");
                ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(hole.Expression, "formatted in an interpolated string");
            }
        }
        return BuiltInTypes.String;
    }

    private TypeInfo AnalyzeBinaryExpression(BinaryExpression binary)
    {
        // For && (short-circuit AND), apply left-side then-narrowings while analyzing the RHS.
        // This handles: if (x != null && x.Length > 0) — x is non-nullable on the RHS.
        if (binary.Operator == BinaryOperator.And)
        {
            var leftType = AnalyzeExpression(binary.Left);
            var (leftThenNarrowings, _) = ExtractFlowNarrowings(binary.Left);

            TypeInfo rightType;
            if (leftThenNarrowings.Count > 0)
            {
                PushScope(new Scope(ScopeKind.Block), binary.Right.Line, binary.Right.Column);
                ApplyNarrowingsToScope(leftThenNarrowings);
                rightType = AnalyzeExpression(binary.Right);
                PopScope();
            }
            else
            {
                rightType = AnalyzeExpression(binary.Right);
            }
            if (ReportSoaRowEscapeIfNeeded(binary.Left, leftType, "used as an operator operand")
                | ReportSoaRowEscapeIfNeeded(binary.Right, rightType, "used as an operator operand")
                | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binary.Left, "used as an operator operand")
                | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binary.Right, "used as an operator operand"))
            {
                return BuiltInTypes.Unknown;
            }
            return AnalyzeLogicalOp(leftType, rightType, binary);
        }

        // For || (short-circuit OR), apply left-side else-narrowings while analyzing the RHS.
        // This handles: if (x == null || useX(x)) — x is non-nullable on the RHS.
        if (binary.Operator == BinaryOperator.Or)
        {
            var leftType = AnalyzeExpression(binary.Left);
            var (_, leftElseNarrowings) = ExtractFlowNarrowings(binary.Left);

            TypeInfo rightType;
            if (leftElseNarrowings.Count > 0)
            {
                PushScope(new Scope(ScopeKind.Block), binary.Right.Line, binary.Right.Column);
                ApplyNarrowingsToScope(leftElseNarrowings);
                rightType = AnalyzeExpression(binary.Right);
                PopScope();
            }
            else
            {
                rightType = AnalyzeExpression(binary.Right);
            }
            if (ReportSoaRowEscapeIfNeeded(binary.Left, leftType, "used as an operator operand")
                | ReportSoaRowEscapeIfNeeded(binary.Right, rightType, "used as an operator operand")
                | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binary.Left, "used as an operator operand")
                | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binary.Right, "used as an operator operand"))
            {
                return BuiltInTypes.Unknown;
            }
            return AnalyzeLogicalOp(leftType, rightType, binary);
        }

        if (binary.Operator == BinaryOperator.NullCoalesce)
        {
            var coalesceLeftType = AnalyzeExpressionPreservingNullabilityFlowType(binary.Left);
            var coalesceRightType = AnalyzeExpression(binary.Right);
            if (ReportSoaRowEscapeIfNeeded(binary.Left, coalesceLeftType, "used as an operator operand")
                | ReportSoaRowEscapeIfNeeded(binary.Right, coalesceRightType, "used as an operator operand")
                | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binary.Left, "used as an operator operand")
                | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binary.Right, "used as an operator operand"))
            {
                return BuiltInTypes.Unknown;
            }

            return AnalyzeNullCoalesceOp(coalesceLeftType, coalesceRightType, binary);
        }

        var leftT = AnalyzeExpression(binary.Left);
        var rightT = AnalyzeExpression(binary.Right);
        if (ReportSoaRowEscapeIfNeeded(binary.Left, leftT, "used as an operator operand")
            | ReportSoaRowEscapeIfNeeded(binary.Right, rightT, "used as an operator operand")
            | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binary.Left, "used as an operator operand")
            | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binary.Right, "used as an operator operand"))
        {
            return BuiltInTypes.Unknown;
        }

        return binary.Operator switch
        {
            BinaryOperator.Add or BinaryOperator.Subtract or BinaryOperator.Multiply
                or BinaryOperator.Divide or BinaryOperator.Modulo => AnalyzeArithmeticOp(leftT, rightT, binary),
            BinaryOperator.BitwiseAnd or BinaryOperator.BitwiseOr or BinaryOperator.BitwiseXor
                => AnalyzeBitwiseOp(leftT, rightT, binary),
            BinaryOperator.LeftShift or BinaryOperator.RightShift
                => AnalyzeShiftOp(leftT, rightT, binary),
            BinaryOperator.Equal or BinaryOperator.NotEqual
                => AnalyzeEqualityOp(leftT, rightT, binary),
            BinaryOperator.Less or BinaryOperator.LessOrEqual or BinaryOperator.Greater or BinaryOperator.GreaterOrEqual
                => AnalyzeRelationalOp(leftT, rightT, binary),
            BinaryOperator.Range => GetRangeType(),
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo AnalyzeNullCoalesceOp(TypeInfo leftType, TypeInfo rightType, BinaryExpression expr)
    {
        CheckNullCoalesceLeftOperand(expr, leftType);

        // If right side is a throw expression, the result type is the left type
        // e.g., string? ?? throw => string
        if (expr.Right is ThrowExpression)
        {
            return GetNonNullableType(leftType);
        }

        // Otherwise, the result is the right type (the fallback value)
        // In N#: T? ?? T returns T
        return rightType;
    }

    private void CheckNullCoalesceLeftOperand(BinaryExpression expression, TypeInfo leftType)
    {
        if (CanNullCoalesceCheckForNull(leftType))
        {
            return;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression.Left);
        Error(
            ErrorCode.TypeMismatch,
            $"The left side of '??' has type '{leftType}', which can't be null",
            line,
            column,
            "Use the value directly, or make the left side nullable before using '??'.",
            length);
    }

    private TypeInfo AnalyzeArithmeticOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
        // Special case: string concatenation
        if (expr.Operator == BinaryOperator.Add && (IsStringType(left) || IsStringType(right)))
        {
            return BuiltInTypes.String;
        }

        // If either operand is Unknown, we can't check but assume it's okay
        if (BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right))
        {
            return BuiltInTypes.Unknown;
        }

        if (!IsNumericType(left) || !IsNumericType(right))
        {
            // Before rejecting, see if a user-declared or runtime operator overload applies
            // (e.g. `Vector<int> + Vector<int>`, or a struct with `static func operator +`).
            // The IL backend already binds these via the static op_* methods; the analyzer must
            // agree so the program type-checks.
            if (TryResolveBinaryOperatorOverloadResult(expr.Operator, left, right, out var overloadResult))
            {
                return overloadResult;
            }

            var leftIsWrong = !IsNumericType(left);
            var rightIsWrong = !IsNumericType(right);
            var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                _spans.GetBinaryOperandDiagnosticSpan(expr, leftIsWrong, rightIsWrong);
            var opText = OperatorFacts.GetBinaryText(expr.Operator);
            var sideText = leftIsWrong == rightIsWrong
                ? $"I found '{left}' and '{right}'"
                : leftIsWrong
                    ? $"the left side is '{left}'"
                    : $"the right side is '{right}'";
            Error(
                ErrorCode.TypeMismatch,
                $"The '{opText}' operator doesn't work with '{left}' and '{right}' — both sides need numeric values, but {sideText}",
                diagnosticLine,
                diagnosticColumn,
                "Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.",
                diagnosticLength);
            return BuiltInTypes.Unknown;
        }

        // Return promoted type (null means invalid combination per ECMA-334)
        var result = GetWiderType(left, right);
        if (result == null)
        {
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(expr);
            var opText = OperatorFacts.GetBinaryText(expr.Operator);
            Error(
                ErrorCode.TypeMismatch,
                $"The '{opText}' operator doesn't work with '{left}' and '{right}'",
                diagnosticLine,
                diagnosticColumn,
                "Use numeric operands with a compatible common type, or add an explicit conversion.",
                diagnosticLength);
            return BuiltInTypes.Unknown;
        }
        return result;
    }

    private TypeInfo AnalyzeBitwiseOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
        if (BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right))
        {
            return BuiltInTypes.Unknown;
        }

        if (IsBoolType(left) && IsBoolType(right))
        {
            return BuiltInTypes.Bool;
        }

        if (IsSameBitwiseEnumType(left, right))
        {
            return left;
        }

        if (IsIntegralType(left) && IsIntegralType(right))
        {
            var result = GetWiderType(left, right);
            if (result != null)
            {
                return result;
            }

            ReportBinaryOperatorOperandMismatch(
                expr,
                left,
                right,
                "both sides need compatible integral values");
            return BuiltInTypes.Unknown;
        }

        if (TryResolveBinaryOperatorOverloadResult(expr.Operator, left, right, out var overloadResult))
        {
            return overloadResult;
        }

        ReportBinaryOperatorOperandMismatch(
            expr,
            left,
            right,
            "both sides need integral values, or both sides need booleans");
        return BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeShiftOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
        if (BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right))
        {
            return BuiltInTypes.Unknown;
        }

        if (IsIntegralType(left) && IsIntegralType(right))
        {
            return GetUnaryNumericPromotionType(left) ?? BuiltInTypes.Unknown;
        }

        if (TryResolveBinaryOperatorOverloadResult(expr.Operator, left, right, out var overloadResult))
        {
            return overloadResult;
        }

        ReportBinaryOperatorOperandMismatch(
            expr,
            left,
            right,
            "the left side needs an integral value, and the shift count needs an integral value");
        return BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeRelationalOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
        if (BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right))
        {
            return BuiltInTypes.Unknown;
        }

        if (TryResolveBinaryOperatorOverloadResult(expr.Operator, left, right, out var overloadResult))
        {
            if (_assignability.IsAssignable(BuiltInTypes.Bool, overloadResult))
            {
                return BuiltInTypes.Bool;
            }

            var (diagnosticLine, diagnosticColumn, diagnosticLength) = AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(expr);
            var opText = OperatorFacts.GetBinaryText(expr.Operator);
            Error(
                ErrorCode.TypeMismatch,
                $"The '{opText}' operator on '{left}' and '{right}' returns '{overloadResult}', but comparison operators must return 'bool'",
                diagnosticLine,
                diagnosticColumn,
                "Change the operator overload to return bool.",
                diagnosticLength);
            return BuiltInTypes.Unknown;
        }

        if (!IsPrimitiveRelationalType(left) || !IsPrimitiveRelationalType(right))
        {
            var leftIsWrong = !IsPrimitiveRelationalType(left);
            var rightIsWrong = !IsPrimitiveRelationalType(right);
            var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                _spans.GetBinaryOperandDiagnosticSpan(expr, leftIsWrong, rightIsWrong);
            var opText = OperatorFacts.GetBinaryText(expr.Operator);
            var sideText = leftIsWrong == rightIsWrong
                ? $"I found '{left}' and '{right}'"
                : leftIsWrong
                    ? $"the left side is '{left}'"
                    : $"the right side is '{right}'";
            Error(
                ErrorCode.TypeMismatch,
                $"The '{opText}' operator doesn't work with '{left}' and '{right}' — both sides need primitive numeric values or a comparison operator overload, but {sideText}",
                diagnosticLine,
                diagnosticColumn,
                "Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.",
                diagnosticLength);
            return BuiltInTypes.Unknown;
        }

        if (GetWiderType(left, right) == null)
        {
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(expr);
            var opText = OperatorFacts.GetBinaryText(expr.Operator);
            Error(
                ErrorCode.TypeMismatch,
                $"The '{opText}' operator doesn't work with '{left}' and '{right}'",
                diagnosticLine,
                diagnosticColumn,
                "Use numeric operands with a compatible common type, or add an explicit conversion.",
                diagnosticLength);
            return BuiltInTypes.Unknown;
        }

        return BuiltInTypes.Bool;
    }

    private TypeInfo AnalyzeEqualityOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
        if (BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right))
        {
            return BuiltInTypes.Unknown;
        }

        if (TryResolveBinaryOperatorOverloadResult(expr.Operator, left, right, out var overloadResult))
        {
            if (_assignability.IsAssignable(BuiltInTypes.Bool, overloadResult))
            {
                return BuiltInTypes.Bool;
            }

            var (diagnosticLine, diagnosticColumn, diagnosticLength) = AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(expr);
            var opText = OperatorFacts.GetBinaryText(expr.Operator);
            Error(
                ErrorCode.TypeMismatch,
                $"The '{opText}' operator on '{left}' and '{right}' returns '{overloadResult}', but equality operators must return 'bool'",
                diagnosticLine,
                diagnosticColumn,
                "Change the operator overload to return bool.",
                diagnosticLength);
            return BuiltInTypes.Unknown;
        }

        if (CanCompareWithEqualityOperator(left, right))
        {
            return BuiltInTypes.Bool;
        }

        var (diagnosticLine2, diagnosticColumn2, diagnosticLength2) =
            _spans.GetBinaryOperandDiagnosticSpan(expr, leftIsWrong: true, rightIsWrong: true);
        var opText2 = OperatorFacts.GetBinaryText(expr.Operator);
        Error(
            ErrorCode.TypeMismatch,
            $"The '{opText2}' operator doesn't work with '{left}' and '{right}' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload",
            diagnosticLine2,
            diagnosticColumn2,
            "Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.",
            diagnosticLength2);
        return BuiltInTypes.Unknown;
    }

    /// <summary>
    /// Attempts to resolve a binary operator to a user-declared or runtime operator overload
    /// (<c>op_Addition</c>, <c>op_BitwiseAnd</c>, and friends). On success, <paramref name="result"/>
    /// is the operator's result type. This keeps the analyzer in step with the IL backend, which binds
    /// these operators directly. The check is conservative: it requires a binary (two-parameter)
    /// operator whose parameters accept the operand types.
    /// </summary>
    private bool TryResolveBinaryOperatorOverloadResult(
        BinaryOperator op,
        TypeInfo left,
        TypeInfo right,
        out TypeInfo result)
    {
        result = BuiltInTypes.Unknown;

        var clrName = OperatorFacts.GetBinaryClrName(op);
        var symbol = OperatorFacts.GetBinarySymbol(op);
        if (clrName == null || symbol == null)
        {
            return false;
        }

        // Search both operand types (the operator may be declared on either side).
        foreach (var operandType in new[] { left, right })
        {
            if (TryResolveDeclaredBinaryOperator(operandType, symbol, left, right, out result)
                || TryResolveRuntimeBinaryOperator(operandType, clrName, left, right, out result))
            {
                return true;
            }
        }

        return false;
    }

    private bool TryResolveDeclaredBinaryOperator(
        TypeInfo operandType,
        string symbol,
        TypeInfo left,
        TypeInfo right,
        out TypeInfo result)
    {
        result = BuiltInTypes.Unknown;
        var declarationOwner = _typeSubstitution.GetSourceDeclarationOwner(operandType, out var substitution);

        var members = declarationOwner switch
        {
            ClassTypeInfo classType => classType.DeclaredMembers,
            StructTypeInfo structType => structType.DeclaredMembers,
            RecordTypeInfo recordType => recordType.DeclaredMembers,
            _ => null
        };

        if (members == null)
        {
            return false;
        }

        // Require a binary operator whose declared parameter types actually accept the operands.
        // Without this check `Vec + Vec` would bind to *any* `static func operator +` on the type
        // (e.g. one declared as `operator +(a: int, b: int)`), swallowing a real type mismatch and
        // diverging from the IL backend, which resolves operators against the actual argument types.
        foreach (var member in members)
        {
            if (member.Kind != DeclaredMemberKind.Function
                || !member.IsOperatorOverload
                || member.OperatorSymbol != symbol
                || member.ParameterCount != 2
                || member.ParameterTypes.Length != 2
                || member.ReturnType == null
                || !_assignability.IsAssignable(
                    _typeSubstitution.ResolveTypeForSourceOwner(member.ParameterTypes[0], declarationOwner, substitution),
                    left)
                || !_assignability.IsAssignable(
                    _typeSubstitution.ResolveTypeForSourceOwner(member.ParameterTypes[1], declarationOwner, substitution),
                    right))
            {
                continue;
            }

            result = _typeSubstitution.ResolveTypeForSourceOwner(member.ReturnType, declarationOwner, substitution);
            return true;
        }

        return false;
    }

    private bool TryResolveRuntimeBinaryOperator(
        TypeInfo operandType,
        string clrName,
        TypeInfo left,
        TypeInfo right,
        out TypeInfo result)
    {
        result = BuiltInTypes.Unknown;

        var clrType = TryResolveOperandClrType(operandType);
        if (clrType == null)
        {
            return false;
        }

        var leftClr = TryResolveOperandClrType(left);
        var rightClr = TryResolveOperandClrType(right);

        MethodInfo[] candidates;
            candidates = clrType.GetMethods(BindingFlags.Public | BindingFlags.Static);

        foreach (var candidate in candidates)
        {
            if (candidate.Name != clrName)
            {
                continue;
            }

            var parameters = candidate.GetParameters();
            if (parameters.Length != 2)
            {
                continue;
            }

            // Require BOTH operand CLR types to resolve and be assignable to the operator's
            // parameter types. The IL backend resolves operators against the actual argument types,
            // so the analyzer must too: if an operand's CLR type is unknown, or doesn't match the
            // parameter, this is not the operator we want — keep looking, and ultimately let a real
            // type mismatch surface rather than silently binding (e.g. `Vector<int> + Box`).
            if (!AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(parameters[0].ParameterType, leftClr)
                || !AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(parameters[1].ParameterType, rightClr))
            {
                continue;
            }

            result = AnalyzerReflectionTypeConversion.ConvertReflectionType(candidate.ReturnType);
            return true;
        }

        return false;
    }

    /// <summary>
    /// Resolves the CLR type for an operator operand. Falls back to an MLC lookup of the open
    /// generic definition for imported generics that
    /// <see cref="AnalyzerClrTypeConversion.TryConvertTypeInfoToClrType"/>
    /// doesn't special-case (e.g. <c>System.Numerics.Vector&lt;T&gt;</c>), so operator-overload
    /// resolution works for arbitrary imported value types — not just the hardcoded BCL generics.
    /// </summary>
    private Type? TryResolveOperandClrType(TypeInfo operandType)
    {
        var direct = _clrTypeConversion.TryConvertTypeInfoToClrType(operandType);
        if (direct != null)
        {
            return direct;
        }

        if (_declarationContext.ResolveDeclaredAlias(operandType) is not GenericTypeInfo generic)
        {
            return null;
        }

        // Resolve the open generic definition (e.g. "Vector`1") from the MLC assemblies, then
        // close it over the converted type arguments.
        var openDefinitionName = $"{generic.Name}`{generic.TypeArguments.Count}";
        if (_externalTypeProbe.ResolveExternalType(openDefinitionName) is not ReflectionTypeInfo { Type: var openType })
        {
            return null;
        }

        if (!openType.IsGenericTypeDefinition)
        {
            return null;
        }

        var typeArguments = new Type[generic.TypeArguments.Count];
        for (int i = 0; i < typeArguments.Length; i++)
        {
            var argumentClr = TryResolveOperandClrType(generic.TypeArguments[i]);
            if (argumentClr == null)
            {
                return null;
            }

            typeArguments[i] = argumentClr;
        }

            return openType.MakeGenericType(typeArguments);
    }

    private bool TryResolveUnaryOperatorOverloadResult(UnaryOperator op, TypeInfo operand, out TypeInfo result)
    {
        result = BuiltInTypes.Unknown;

        var clrName = OperatorFacts.GetUnaryClrName(op);
        var symbol = OperatorFacts.GetUnarySymbol(op);
        if (clrName == null || symbol == null)
        {
            return false;
        }

        return TryResolveDeclaredUnaryOperator(operand, symbol, out result)
            || TryResolveRuntimeUnaryOperator(operand, clrName, out result);
    }

    private bool TryResolveDeclaredUnaryOperator(
        TypeInfo operandType,
        string symbol,
        out TypeInfo result)
    {
        result = BuiltInTypes.Unknown;
        var declarationOwner = _typeSubstitution.GetSourceDeclarationOwner(operandType, out var substitution);

        var members = declarationOwner switch
        {
            ClassTypeInfo classType => classType.DeclaredMembers,
            StructTypeInfo structType => structType.DeclaredMembers,
            RecordTypeInfo recordType => recordType.DeclaredMembers,
            _ => null
        };

        if (members == null)
        {
            return false;
        }

        foreach (var member in members)
        {
            if (member.Kind != DeclaredMemberKind.Function
                || !member.IsOperatorOverload
                || member.OperatorSymbol != symbol
                || member.ParameterCount != 1
                || member.ParameterTypes.Length != 1
                || member.ReturnType == null
                || !_assignability.IsAssignable(
                    _typeSubstitution.ResolveTypeForSourceOwner(member.ParameterTypes[0], declarationOwner, substitution),
                    operandType))
            {
                continue;
            }

            result = _typeSubstitution.ResolveTypeForSourceOwner(member.ReturnType, declarationOwner, substitution);
            return true;
        }

        return false;
    }

    private bool TryResolveRuntimeUnaryOperator(TypeInfo operandType, string clrName, out TypeInfo result)
    {
        result = BuiltInTypes.Unknown;

        var clrType = TryResolveOperandClrType(operandType);
        if (clrType == null)
        {
            return false;
        }

        MethodInfo[] candidates;
            candidates = clrType.GetMethods(BindingFlags.Public | BindingFlags.Static);

        foreach (var candidate in candidates)
        {
            if (candidate.Name != clrName)
            {
                continue;
            }

            var parameters = candidate.GetParameters();
            if (parameters.Length != 1)
            {
                continue;
            }

            if (!AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(parameters[0].ParameterType, clrType))
            {
                continue;
            }

            result = AnalyzerReflectionTypeConversion.ConvertReflectionType(candidate.ReturnType);
            return true;
        }

        return false;
    }

    private TypeInfo AnalyzeLogicalOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
        if (BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right))
        {
            return BuiltInTypes.Unknown;
        }

        if (!IsBoolType(left) || !IsBoolType(right))
        {
            var leftIsWrong = !IsBoolType(left);
            var rightIsWrong = !IsBoolType(right);
            var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                _spans.GetBinaryOperandDiagnosticSpan(expr, leftIsWrong, rightIsWrong);
            var opText = OperatorFacts.GetBinaryText(expr.Operator);
            var sideText = leftIsWrong == rightIsWrong
                ? $"I found '{left}' and '{right}'"
                : leftIsWrong
                    ? $"the left side is '{left}'"
                    : $"the right side is '{right}'";
            Error(
                ErrorCode.TypeMismatch,
                $"Both sides of '{opText}' must be booleans, but {sideText}",
                diagnosticLine,
                diagnosticColumn,
                "Use boolean expressions on both sides of the operator.",
                diagnosticLength);
        }
        return BuiltInTypes.Bool;
    }

    private TypeInfo AnalyzeUnaryExpression(UnaryExpression unary)
    {
        var isIncrementOrDecrement = unary.Operator is UnaryOperator.PreIncrement or UnaryOperator.PreDecrement
            or UnaryOperator.PostIncrement or UnaryOperator.PostDecrement;
        if (isIncrementOrDecrement
            && ReportNullConditionalWriteTargetIfNeeded(
                unary.Operand,
                $"changed with '{OperatorFacts.GetUnarySymbol(unary.Operator) ?? "operator"}'"))
        {
            return BuiltInTypes.Unknown;
        }

        Dictionary<Expression, TypeInfo>? targetExpressionTypes = null;
        TypeInfo operandType;
        if (isIncrementOrDecrement && IsWriteTargetNeedingExpressionTypes(unary.Operand))
        {
            var previousAssignmentTargetExpressionTypes = _assignmentTargetExpressionTypes;
            targetExpressionTypes = new Dictionary<Expression, TypeInfo>(ReferenceEqualityComparer.Instance);
            _assignmentTargetExpressionTypes = targetExpressionTypes;
            try
            {
                operandType = AnalyzeExpression(unary.Operand);
            }
            finally
            {
                _assignmentTargetExpressionTypes = previousAssignmentTargetExpressionTypes;
            }
        }
        else
        {
            operandType = AnalyzeExpression(unary.Operand);
        }

        if (ReportSoaRowEscapeIfNeeded(unary.Operand, operandType, "used as a unary operand"))
        {
            return BuiltInTypes.Unknown;
        }

        if (isIncrementOrDecrement
            && ReportSoaTableMemberMutationIfNeeded(unary.Operand, targetExpressionTypes, "incremented or decremented directly"))
        {
            return BuiltInTypes.Unknown;
        }

        if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(unary.Operand, "used as a unary operand"))
        {
            return BuiltInTypes.Unknown;
        }

        if (isIncrementOrDecrement
            && ReportUnsupportedBuiltInIndexedMutationIfNeeded(unary.Operand, targetExpressionTypes, "incremented or decremented"))
        {
            return BuiltInTypes.Unknown;
        }

        if (isIncrementOrDecrement && ReportReadonlyFieldIncrementOrDecrementIfNeeded(unary, targetExpressionTypes))
        {
            return BuiltInTypes.Unknown;
        }

        if (isIncrementOrDecrement && ReportInvalidIncrementOrDecrementTargetIfNeeded(unary))
        {
            return BuiltInTypes.Unknown;
        }

        if (isIncrementOrDecrement
            && ReportReadOnlyPropertyWriteTargetIfNeeded(
                unary.Operand,
                OperatorFacts.GetUnarySymbol(unary.Operator) ?? "operator",
                targetExpressionTypes))
        {
            return BuiltInTypes.Unknown;
        }

        return unary.Operator switch
        {
            UnaryOperator.Negate => AnalyzeUnaryNegation(operandType, unary),
            UnaryOperator.Not => AnalyzeLogicalNot(operandType, unary),
            UnaryOperator.BitwiseNot => AnalyzeUnaryBitwiseNot(operandType, unary),
            UnaryOperator.PreIncrement or UnaryOperator.PreDecrement
                or UnaryOperator.PostIncrement or UnaryOperator.PostDecrement => AnalyzeIncrementOrDecrement(operandType, unary),
            UnaryOperator.IndexFromEnd => AnalyzeIndexFromEnd(operandType, unary),
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo AnalyzeIndexFromEnd(TypeInfo operandType, UnaryExpression unary)
    {
        if (BuiltInTypes.IsUnknown(operandType))
        {
            return BuiltInTypes.Unknown;
        }

        if (!_assignability.IsAssignable(BuiltInTypes.Int, operandType))
        {
            ReportUnaryOperatorOperandMismatch(
                unary,
                operandType,
                "the from-end index count must be an int-compatible value");
            return BuiltInTypes.Unknown;
        }

        return GetIndexType();
    }

    private TypeInfo AnalyzeLogicalNot(TypeInfo operandType, UnaryExpression unary)
    {
        if (BuiltInTypes.IsUnknown(operandType))
        {
            return BuiltInTypes.Unknown;
        }

        if (TryResolveUnaryOperatorOverloadResult(unary.Operator, operandType, out var overloadResult))
        {
            return overloadResult;
        }

        if (IsBoolType(_declarationContext.ResolveDeclaredAlias(operandType)))
        {
            return BuiltInTypes.Bool;
        }

        ReportUnaryOperatorOperandMismatch(unary, operandType, "the operand needs a boolean value");
        return BuiltInTypes.Unknown;
    }

    private bool ReportInvalidIncrementOrDecrementTargetIfNeeded(UnaryExpression unary)
    {
        if (IsIncrementOrDecrementTarget(unary.Operand))
        {
            return false;
        }

        var opText = OperatorFacts.GetUnarySymbol(unary.Operator) ?? "operator";
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(unary.Operand);
        Error(
            ErrorCode.InvalidSyntax,
            $"The '{opText}' operator needs an assignable target",
            line,
            column,
            "Use a variable, field, property, or indexed element as the operand.",
            length);
        return true;
    }

    private static bool IsIncrementOrDecrementTarget(Expression expression) => expression switch
    {
        ParenthesizedExpression parenthesized => IsIncrementOrDecrementTarget(parenthesized.Inner),
        IdentifierExpression identifier => !IsDiscardTarget(identifier),
        MemberAccessExpression => true,
        IndexAccessExpression => true,
        _ => false
    };

    private TypeInfo AnalyzeIncrementOrDecrement(TypeInfo operandType, UnaryExpression unary)
    {
        if (BuiltInTypes.IsUnknown(operandType))
        {
            return BuiltInTypes.Unknown;
        }

        var resolved = _declarationContext.ResolveDeclaredAlias(operandType);
        if (IsIntegralType(resolved) || IsBitwiseEnumType(resolved))
        {
            return operandType;
        }

        ReportUnaryOperatorOperandMismatch(
            unary,
            operandType,
            "the operand needs an integral numeric value");
        return BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeUnaryNegation(TypeInfo operandType, UnaryExpression unary)
    {
        if (BuiltInTypes.IsUnknown(operandType))
        {
            return BuiltInTypes.Unknown;
        }

        if (TryResolveUnaryOperatorOverloadResult(unary.Operator, operandType, out var overloadResult))
        {
            return overloadResult;
        }

        if (unary.Operand is IntLiteralExpression intLiteral
            && TryGetExpectedNegativeIntegerLiteralType(_currentExpectedType, intLiteral.Value, out var targetTypedLiteralType))
        {
            return targetTypedLiteralType;
        }

        var promotedType = GetUnaryNegationType(operandType);
        if (promotedType != null)
        {
            return promotedType;
        }

        ReportUnaryOperatorOperandMismatch(
            unary,
            operandType,
            "the operand needs a signed numeric value, a floating-point value, decimal, or uint");
        return BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeUnaryBitwiseNot(TypeInfo operandType, UnaryExpression unary)
    {
        if (BuiltInTypes.IsUnknown(operandType))
        {
            return BuiltInTypes.Unknown;
        }

        if (TryResolveUnaryOperatorOverloadResult(unary.Operator, operandType, out var overloadResult))
        {
            return overloadResult;
        }

        if (IsBitwiseEnumType(operandType))
        {
            return operandType;
        }

        var promotedType = GetUnaryNumericPromotionType(operandType);
        if (promotedType != null && IsIntegralType(promotedType))
        {
            return promotedType;
        }

        ReportUnaryOperatorOperandMismatch(unary, operandType, "the operand needs an integral value");
        return BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeMustExpression(MustExpression must)
    {
        var operandType = AnalyzeExpression(must.Expression);
        if (ReportSoaRowEscapeIfNeeded(must.Expression, operandType, "unwrapped with 'must'"))
        {
            return BuiltInTypes.Unknown;
        }
        if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(must.Expression, "unwrapped with 'must'"))
        {
            return BuiltInTypes.Unknown;
        }

        if (operandType is NullableTypeInfo nullable)
        {
            return nullable.InnerType;
        }

        if (BuiltInTypes.IsUnknown(operandType))
        {
            return BuiltInTypes.Unknown;
        }

        Error(
            ErrorCode.NullabilityWarning,
            $"This 'must' unwrap is redundant — the expression is already known to be '{operandType}'",
            must.Line,
            must.Column,
            "Remove the 'must' keyword, or keep the original nullable value until the point where you need to unwrap it.",
            length: 4);
        return operandType;
    }

    private TypeInfo AnalyzeMemberAccess(MemberAccessExpression member)
    {
        // Check if this is an aliased import access (Alias.Symbol)
        if (member.Object is IdentifierExpression identifier)
        {
            var aliasName = identifier.Name;

            if (_importedSymbolsByAlias.TryGetValue(aliasName, out var symbols))
            {
                if (symbols.TryGetValue(member.MemberName, out var symbolType))
                {
                    if (_importedDeclarationsByAlias.TryGetValue(aliasName, out var declarations)
                        && declarations.TryGetValue(member.MemberName, out var declaration))
                    {
                        RecordMemberBinding(member, declaration);
                    }
                    return symbolType;
                }
                var memberColumn = _spans.GetMemberNameColumn(member);
                var similarSymbols = symbols.Count == 0
                    ? new List<string>()
                    : new SmartSuggester(symbols.Keys.ToList()).SuggestSimilarNames(member.MemberName);
                Error(
                    ErrorCode.UndefinedMember,
                    $"'{member.MemberName}' doesn't exist in import alias '{aliasName}' — check the import for available symbols",
                    member.Line,
                    memberColumn,
                    similarSymbols.Count > 0 ? $"Did you mean '{similarSymbols[0]}'?" : null,
                    Math.Max(1, member.MemberName.Length));
                return BuiltInTypes.Unknown;
            }
        }

        var objectType = TryResolveQualifiedExternalType(member.Object, out var typeReceiver) ? typeReceiver : AnalyzeExpression(member.Object);
        if (TryResolveNullableMemberAccess(member, objectType, out var nullableMemberType))
        {
            return nullableMemberType;
        }

        ReportPossibleNullAccess(member.Object, objectType, member.Line, member.Column, "dereference", member.IsNullConditional);
        var receiverType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(objectType));
        if (receiverType is ByRefTypeInfo byRefReceiver)
            receiverType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(byRefReceiver.InnerType));

        if (receiverType is SoaRecordTypeInfo && member.IsNullConditional)
        {
            ReportSoaTableNullConditionalAccess(member);
            return BuiltInTypes.Unknown;
        }

        if (receiverType is SoaRowTypeInfo
            && member.IsNullConditional)
        {
            ReportSoaRowEscape(member.Object, "used with null-conditional member access");
            return BuiltInTypes.Unknown;
        }

        if (member.IsNullConditional
            && ReportSoaDirectColumnNullConditionalAccessIfNeeded(member, member.Object, "member access"))
        {
            return BuiltInTypes.Unknown;
        }

        if (receiverType is SoaRowTypeInfo soaRowType
            && AnalyzerMemberResolution.TryGetSoaColumn(soaRowType.Declaration, member.MemberName) is null)
        {
            ReportSoaRowEscape(member.Object, "used as a member receiver");
            return BuiltInTypes.Unknown;
        }

        ValidateDeclaredMemberVisibility(receiverType, member);
        TryRecordMemberBinding(receiverType, member);

        var includeStaticMembers = IsStaticMemberAccessTarget(member.Object);
        var memberType = ResolveMember(receiverType, member.MemberName, includeStaticMembers);
        if (BuiltInTypes.IsUnknown(memberType) && ShouldReportUndefinedMember(receiverType, member, includeStaticMembers))
        {
            ReportUndefinedMember(receiverType, member, includeStaticMembers);
        }
        else if (receiverType is SoaRecordTypeInfo soaRecordType
                 && AnalyzerMemberResolution.TryGetSoaColumn(soaRecordType.Declaration, member.MemberName) != null)
        {
            _soaColumnMemberAccesses.Add(member);
        }

        return member.IsNullConditional ? MakeNullableResult(memberType) : memberType;
    }

    private TypeInfo AnalyzeIndexAccess(IndexAccessExpression index)
    {
        var objectType = AnalyzeExpression(index.Object);
        ReportPossibleNullAccess(index.Object, objectType, index.Line, index.Column, "index", index.IsNullConditional);

        var receiverType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(objectType));
        var previousExpectedIndexType = _currentExpectedType;
        if (ShouldUseIntExpectedTypeForIndex(receiverType))
        {
            _currentExpectedType = BuiltInTypes.Int;
        }

        var indexType = AnalyzeExpression(index.Index);
        _currentExpectedType = previousExpectedIndexType;
        if (receiverType is SoaRecordTypeInfo && index.IsNullConditional)
        {
            ReportSoaRowEscape(index, "used with null-conditional indexing");
            return BuiltInTypes.Unknown;
        }

        if (index.IsNullConditional
            && ReportSoaDirectColumnNullConditionalAccessIfNeeded(index, index.Object, "index access"))
        {
            return BuiltInTypes.Unknown;
        }

        var isSoaRowReceiver = receiverType is SoaRowTypeInfo;
        var isSoaRowIndex = ReportSoaRowEscapeIfNeeded(index.Index, indexType, "used as an index value");
        var isSoaDirectColumnIndex = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(index.Index, "used as an index value");
        if (isSoaRowReceiver)
        {
            ReportSoaRowEscape(index.Object, "used as an index receiver");
        }

        if (isSoaRowReceiver || isSoaRowIndex || isSoaDirectColumnIndex)
        {
            return BuiltInTypes.Unknown;
        }

        var isRangeAccess = index.Index is RangeExpression || IsRangeLikeType(indexType);
        if (receiverType is SoaRecordTypeInfo
            && ReportNegativeSoaRowIndexIfNeeded(index.Index, indexType, "table row"))
        {
            return BuiltInTypes.Unknown;
        }
        if (receiverType is SoaRecordTypeInfo && !IsValidSoaRowIndex(indexType, isRangeAccess))
        {
            ReportInvalidSoaRowIndex(index.Index, indexType, isRangeAccess);
            return BuiltInTypes.Unknown;
        }

        if (isRangeAccess
            && _assignmentTargetExpressionTypes == null
            && IsSoaColumnMemberAccess(index.Object))
        {
            ReportSoaColumnSliceHiddenAllocation(index);
            return BuiltInTypes.Unknown;
        }
        if (!isRangeAccess
            && IsSoaColumnMemberAccess(index.Object)
            && ReportNegativeSoaRowIndexIfNeeded(index.Index, indexType, "column row"))
        {
            return BuiltInTypes.Unknown;
        }

        if (!ValidateBuiltInIndexAccess(index, receiverType, indexType, isRangeAccess))
        {
            return BuiltInTypes.Unknown;
        }

        var elementType = ResolveIndexElementType(receiverType, indexType, isRangeAccess);

        return index.IsNullConditional ? MakeNullableResult(elementType) : elementType;
    }

    private bool ShouldUseIntExpectedTypeForIndex(TypeInfo receiverType)
    {
        var resolvedReceiverType = _declarationContext.ResolveDeclaredAlias(receiverType);
        return resolvedReceiverType is SoaRecordTypeInfo
            || resolvedReceiverType is ArrayTypeInfo
            || resolvedReceiverType is ReflectionTypeInfo { Type.IsArray: true }
            || IsStringType(resolvedReceiverType);
    }

    private bool ValidateBuiltInIndexAccess(
        IndexAccessExpression index,
        TypeInfo receiverType,
        TypeInfo indexType,
        bool isRangeAccess)
    {
        var resolvedReceiverType = _declarationContext.ResolveDeclaredAlias(receiverType);
        var isArrayReceiver = resolvedReceiverType is ArrayTypeInfo
            || resolvedReceiverType is ReflectionTypeInfo { Type.IsArray: true };
        var isStringReceiver = IsStringType(resolvedReceiverType);

        if (!isArrayReceiver && !isStringReceiver)
            return true;

        if (isRangeAccess)
            return true;

        var resolvedIndexType = _declarationContext.ResolveDeclaredAlias(indexType);
        if (BuiltInTypes.IsUnknown(resolvedIndexType)
            || BuiltInTypes.Is(resolvedIndexType, BuiltInTypes.Int)
            || IsIndexLikeType(resolvedIndexType))
        {
            return true;
        }

        ReportInvalidBuiltInIndex(index.Index, resolvedIndexType, isStringReceiver ? "String" : "Array");
        return false;
    }

    private bool IsValidSoaRowIndex(TypeInfo indexType, bool isRangeAccess)
    {
        if (isRangeAccess)
            return false;

        var resolvedIndexType = _declarationContext.ResolveDeclaredAlias(indexType);
        return BuiltInTypes.IsUnknown(resolvedIndexType) || BuiltInTypes.Is(resolvedIndexType, BuiltInTypes.Int);
    }

    private bool ReportNegativeSoaRowIndexIfNeeded(Expression expression, TypeInfo indexType, string targetDescription)
    {
        var resolvedIndexType = _declarationContext.ResolveDeclaredAlias(indexType);
        if (BuiltInTypes.IsNot(resolvedIndexType, BuiltInTypes.Int)
            && BuiltInTypes.IsNot(resolvedIndexType, BuiltInTypes.Short)
            && BuiltInTypes.IsNot(resolvedIndexType, BuiltInTypes.SByte))
        {
            return false;
        }

        if (!_constantExpressionFacts.IsConstantNegative(expression))
        {
            return false;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.TypeMismatch,
            $"SoA {targetDescription} indexes must not be negative",
            line,
            column,
            "Use zero or a valid non-negative row id.",
            length);
        return true;
    }

    private void ReportInvalidSoaRowIndex(Expression expression, TypeInfo indexType, bool isRangeAccess)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        var resolvedIndexType = _declarationContext.ResolveDeclaredAlias(indexType);
        var indexDescription = isRangeAccess
            ? "a range"
            : IsIndexLikeType(resolvedIndexType)
                ? "'System.Index'"
                : $"'{indexType}'";
        Error(
            ErrorCode.TypeMismatch,
            $"SoA table indexes must be int row ids, but this index has type {indexDescription}",
            line,
            column,
            "Use an int row index and read or write a column with table[index].column.",
            length);
    }

    private void ReportInvalidBuiltInIndex(Expression expression, TypeInfo indexType, string receiverDescription)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.TypeMismatch,
            $"{receiverDescription} indexes must be int, System.Index, or System.Range, but this index has type '{indexType}'",
            line,
            column,
            "Use an int element index, '^n' for from-end access, or a '..' range for slicing.",
            length);
    }

    private bool IsSoaColumnMemberAccess(Expression expression) => expression switch
    {
        MemberAccessExpression member => _soaColumnMemberAccesses.Contains(member),
        ParenthesizedExpression parenthesized => IsSoaColumnMemberAccess(parenthesized.Inner),
        CheckedExpression checkedExpression => IsSoaColumnMemberAccess(checkedExpression.Expression),
        UncheckedExpression uncheckedExpression => IsSoaColumnMemberAccess(uncheckedExpression.Expression),
        _ => false
    };

    private void ReportSoaColumnSliceHiddenAllocation(IndexAccessExpression index)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(index);
        Error(
            ErrorCode.InvalidSyntax,
            "SoA column range slices allocate arrays; use explicit element indexing instead",
            line,
            column,
            "Iterate with int row indexes over table.column[row], or add an allocation-free view lowering with IL-shape evidence before using slices in compiler table kernels.",
            length);
    }

    private bool ReportSoaDirectColumnNullConditionalAccessIfNeeded(
        Expression expression,
        Expression receiver,
        string accessKind)
    {
        if (!TryGetSoaColumnMemberAccess(receiver, out var columnMember))
        {
            return false;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.InvalidSyntax,
            $"SoA table member '{columnMember.MemberName}' cannot use null-conditional {accessKind} directly",
            line,
            column,
            "Direct columns are non-null table storage; use direct column access such as table.column[row] or table.column.Length.",
            length);
        return true;
    }

    private TypeInfo ResolveIndexElementType(TypeInfo receiverType, TypeInfo indexType, bool isRangeAccess)
    {
        receiverType = _declarationContext.ResolveDeclaredAlias(receiverType);

        if (receiverType is ArrayTypeInfo arrayType)
        {
            return isRangeAccess
                ? receiverType
                : arrayType.ElementType;
        }

        if (!isRangeAccess && receiverType is SoaRecordTypeInfo soaRecordType)
        {
            return new SoaRowTypeInfo(soaRecordType.Declaration);
        }

        if (IsStringType(receiverType))
        {
            return isRangeAccess
                ? BuiltInTypes.String
                : BuiltInTypes.Char;
        }

        if (receiverType is GenericTypeInfo genericType)
        {
            var name = genericType.Name;
            if (name.EndsWith("Dictionary", StringComparison.Ordinal) && genericType.TypeArguments.Count >= 2)
                return genericType.TypeArguments[1];

            if (genericType.TypeArguments.Count == 1
                && (name.EndsWith("List", StringComparison.Ordinal)
                    || name.EndsWith("IList", StringComparison.Ordinal)
                    || name.EndsWith("IReadOnlyList", StringComparison.Ordinal)
                    || name.EndsWith("Collection", StringComparison.Ordinal)))
            {
                return genericType.TypeArguments[0];
            }
        }

        if (receiverType is ReflectionTypeInfo reflectionType)
        {
            var type = reflectionType.Type;
            if (type.IsArray)
                return isRangeAccess
                    ? AnalyzerReflectionTypeConversion.ConvertReflectionType(type)
                    : AnalyzerReflectionTypeConversion.ConvertReflectionType(type.GetElementType()!);

            var indexer = type.GetDefaultMembers()
                .OfType<PropertyInfo>()
                .FirstOrDefault(property => property.GetIndexParameters().Length > 0);

            if (indexer != null)
                return AnalyzerReflectionTypeConversion.ConvertReflectionType(indexer.PropertyType);
        }

        return BuiltInTypes.Unknown;
    }

    private static bool IsRangeLikeType(TypeInfo type)
        => type is ReflectionTypeInfo { Type.FullName: "System.Range" }
           || type is SimpleTypeInfo { Name: "Range" or "System.Range" };

    private static bool IsIndexLikeType(TypeInfo type)
        => type is ReflectionTypeInfo { Type.FullName: "System.Index" }
           || type is SimpleTypeInfo { Name: "Index" or "System.Index" };

    private bool IsRangeEndpointType(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        return IsIndexLikeType(resolved) || _assignability.IsAssignable(BuiltInTypes.Int, resolved);
    }

    private TypeInfo GetRangeType()
        => _scopes.LookupType("System.Range") ?? new ReflectionTypeInfo(typeof(Range));

    private TypeInfo GetIndexType()
        => _scopes.LookupType("System.Index") ?? new ReflectionTypeInfo(typeof(Index));

    private TypeInfo GetNonNullableType(TypeInfo type)
        => _declarationContext.ResolveDeclaredAlias(type) is NullableTypeInfo nullable ? nullable.InnerType : type;

    private TypeInfo MakeNullableResult(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        if (BuiltInTypes.Is(resolved, BuiltInTypes.Void)
            || BuiltInTypes.Is(resolved, BuiltInTypes.Never)
            || resolved is UnknownTypeInfo
            || resolved is NullableTypeInfo)
        {
            return type;
        }

        return new NullableTypeInfo(type);
    }

    private void ReportPossibleNullAccess(
        Expression receiver,
        TypeInfo receiverType,
        int line,
        int column,
        string operation,
        bool isNullConditional)
    {
        if (isNullConditional)
            return;

        var nullState = GetExpressionNullState(receiver, receiverType);
        if (!IsUnsafeNullState(nullState))
            return;

        var path = AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(receiver) ?? "this value";
        var key = (line, column, path, operation);
        if (!_reportedNullabilityDiagnostics.Add(key))
            return;

        var stateLabel = NullStateFacts.GetDiagnosticText(nullState);
        var message = operation == "call"
            ? $"Possible null call: `{path}` is {stateLabel}"
            : $"Possible null {operation}: `{path}` is {stateLabel}";
        var suggestion = operation switch
        {
            "dereference" => $"Use '?.', add a '??' fallback, guard with 'if {path} == null {{ return }}', or explicitly assert after proving '{path}' is not null.",
            "index" => $"Use '?[', add a '??' fallback, guard with 'if {path} == null {{ return }}', or explicitly assert after proving '{path}' is not null.",
            "call" => $"Guard with 'if {path} == null {{ return }}', use '?.' when calling through a member, or explicitly assert after proving '{path}' is not null.",
            _ => $"Guard with 'if {path} == null {{ return }}' or add a fallback before using '{path}'."
        };

        var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetNullReceiverDiagnosticSpan(receiver, path, line, column);
        Error(ErrorCode.PossibleNullAccess, message, diagnosticLine, diagnosticColumn, suggestion, diagnosticLength);
    }

    private bool TryResolveNullableMemberAccess(MemberAccessExpression member, TypeInfo objectType, out TypeInfo memberType)
    {
        memberType = BuiltInTypes.Unknown;

        var nullableType = objectType as NullableTypeInfo;
        var isNarrowedNullableOrigin = false;
        if (nullableType == null
            && member.Object is IdentifierExpression identifier
            && IsPrimitiveLikeType(objectType)
            && _scopes.FindEnclosingNullableSymbol(identifier.Name) is { } origin)
        {
            nullableType = origin;
            isNarrowedNullableOrigin = true;
        }

        if (nullableType == null)
        {
            return false;
        }

        if (member.MemberName == "HasValue")
        {
            memberType = BuiltInTypes.Bool;
            return true;
        }

        if (member.MemberName == "Value")
        {
            if (!isNarrowedNullableOrigin)
            {
                Error(
                    ErrorCode.NullabilityWarning,
                    "This '.Value' access can throw when the nullable value is absent",
                    member.Line,
                    _spans.GetMemberNameColumn(member),
                    "Prefer 'must value' for an explicit unwrap, or use 'match value { null => ..., inner => ... }' to handle both cases.",
                    length: Math.Max(1, member.MemberName.Length));
            }

            memberType = nullableType.InnerType;
            return true;
        }

        return false;
    }

    private static bool IsPrimitiveLikeType(TypeInfo type)
    {
        return type is SimpleTypeInfo or ReflectionTypeInfo;
    }

    private bool IsStaticMemberAccessTarget(Expression target)
    {
        if (target is ParenthesizedExpression parenthesized)
            return IsStaticMemberAccessTarget(parenthesized.Inner);

        if (target is IdentifierExpression identifier)
            return _scopes.LookupSymbol(identifier.Name) == null;

        return TryResolveTypeValuedMemberAccess(target, out _);
    }

    private bool TryResolveTypeValuedMemberAccess(Expression expression, out TypeInfo type)
    {
        type = BuiltInTypes.Unknown;
        switch (expression)
        {
            case ParenthesizedExpression parenthesized:
                return TryResolveTypeValuedMemberAccess(parenthesized.Inner, out type);

            case IdentifierExpression identifier:
                if (_scopes.LookupSymbol(identifier.Name) != null)
                    return false;
                type = _declarationContext.ResolveDeclaredAlias(_scopes.LookupType(identifier.Name) ?? BuiltInTypes.Unknown);
                if (!BuiltInTypes.IsUnknown(type))
                    return true;
                type = AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(_wellKnownTypes, identifier.Name) is { } builtInType ? new ReflectionTypeInfo(builtInType) : _externalTypeProbe.ResolveExternalType(identifier.Name) ?? BuiltInTypes.Unknown;
                return !BuiltInTypes.IsUnknown(type);

            case MemberAccessExpression memberAccess:
                if (TryResolveQualifiedExternalType(memberAccess, out type))
                    return true;
                return TryResolveTypeValuedMemberAccess(memberAccess.Object, out var ownerType) && _declarationContext.TryResolveNestedType(ownerType, memberAccess.MemberName, requireExported: false, out type);

            default:
                return false;
        }
    }

    private bool TryResolveQualifiedExternalType(Expression expression, out TypeInfo type)
    {
        type = BuiltInTypes.Unknown;
        if (expression is not MemberAccessExpression || !TryGetQualifiedExpressionTreeName(expression, out var qualifiedName))
            return false;
        var rootName = ExternalQualifiedTypeResolver.RootName(qualifiedName);
        var currentType = _scopes.CurrentTypeScope();
        var separator = qualifiedName.LastIndexOf('.');
        var currentUnitNamespace = GetUnitNamespace(_compilationUnit);
        foreach (var visibleNamespace in AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(currentUnitNamespace, _usingNamespaces))
            if (_projectDiscovery.TryResolveProjectTypeInNamespace(rootName, visibleNamespace, currentUnitNamespace, out _, out _)) return false;
        if (_scopes.LookupSymbol(rootName) != null || _scopes.LookupType(rootName) != null || _usingAliases.ContainsKey(rootName)
            || _importedSymbolsByAlias.ContainsKey(rootName) || (currentType != null && !BuiltInTypes.IsUnknown(ResolveMember(currentType, rootName)))
            || TryResolveVisibleProjectFunction(rootName, out _, out _) || (separator > 0 && _projectDiscovery.TryResolveProjectTypeInNamespace(qualifiedName[(separator + 1)..], qualifiedName[..separator], currentUnitNamespace, out _, out _))
            || !ExternalQualifiedTypeResolver.TryResolve(_mlcAssemblies, qualifiedName, out var runtimeType))
            return false;
        type = new ReflectionTypeInfo(runtimeType);
        return true;
    }

    private void TryRecordMemberBinding(TypeInfo objectType, MemberAccessExpression member)
    {
        if (TryFindMemberDeclaration(objectType, member.MemberName, out var declaration))
        {
            RecordMemberBinding(member, declaration);
        }
    }

    private void ValidateDeclaredMemberVisibility(TypeInfo objectType, MemberAccessExpression member)
    {
        if (TryFindMemberExportVisibility(objectType, member.MemberName, out var isExported, out var filePath)
            && IsCrossPackageFile(filePath)
            && !isExported)
        {
            _diagnostics.ReportInaccessibleMember(member.MemberName, filePath, member.Line, _spans.GetMemberNameColumn(member));
        }
    }

    private bool TryFindMemberExportVisibility(
        TypeInfo objectType,
        string memberName,
        out bool isExported,
        out string? filePath)
    {
        objectType = _declarationContext.ResolveDeclaredAlias(objectType);
        if (_declarationContext.TryFindMember(objectType, memberName, out var selection))
        {
            isExported = selection.IsExported;
            filePath = selection.FilePath;
            return true;
        }
        isExported = false;
        filePath = null;
        return false;
    }

    private void RecordMemberBinding(MemberAccessExpression member, SymbolDeclaration declaration)
    {
        var memberColumn = _spans.GetMemberNameColumn(member);
        _bindingMap.RecordBinding(_currentFilePath, member.Line, memberColumn, member.MemberName.Length, declaration);
    }

    private bool TryFindMemberDeclaration(
        TypeInfo objectType,
        string memberName,
        out SymbolDeclaration declaration)
    {
        objectType = _declarationContext.ResolveDeclaredAlias(objectType);
        if (_declarationContext.TryFindMember(objectType, memberName, out var selection))
        {
            declaration = selection.Member != null
                ? CreateSymbolDeclaration(selection.Member, selection.FilePath)
                : new SymbolDeclaration(
                    memberName,
                    selection.FilePath,
                    selection.Line,
                    selection.Column,
                    selection.KindName);
            return true;
        }

        var extension = _extensionMethods.FirstOrDefault(candidate =>
            candidate.Name == memberName
            && _extensionMethodResolution.IsExtensionReceiverApplicable(candidate, objectType));
        if (extension != null)
        {
            declaration = new SymbolDeclaration(
                extension.Name, _currentFilePath, extension.Line, extension.Column, "function");
            return true;
        }
        declaration = null!;
        return false;
    }

    private bool ShouldReportUndefinedMember(TypeInfo receiverType, MemberAccessExpression member, bool includeStaticMembers)
        => ShouldReportUndefinedMember(receiverType, member.MemberName, includeStaticMembers);

    private bool ShouldReportUndefinedMember(TypeInfo receiverType, string memberName, bool includeStaticMembers)
    {
        if (string.IsNullOrWhiteSpace(memberName) || memberName == "<error>")
            return false;

        receiverType = ResolveAliasAndMetadata(receiverType);
        return receiverType switch
        {
            SimpleTypeInfo simple when BuiltInTypes.Is(simple, BuiltInTypes.Object) => false,
            SimpleTypeInfo simple => _clrTypeConversion.TryConvertTypeInfoToClrType(simple) != null
                                     || (IsKnownBuiltInReceiverWithoutReflection(simple)
                                         && !IsKnownBuiltInMemberWithoutReflection(simple, memberName, includeStaticMembers)),
            ArrayTypeInfo => _clrTypeConversion.TryConvertTypeInfoToClrType(receiverType) != null
                             || !IsKnownBuiltInMemberWithoutReflection(receiverType, memberName, includeStaticMembers),
            GenericTypeInfo generic =>
                (_typeSubstitution.ResolveGenericDefinition(generic) is { } genericDefinition
                 && genericDefinition is not ReflectionTypeInfo)
                || _clrTypeConversion.TryConvertTypeInfoToClrType(receiverType) != null,
            ReflectionTypeInfo reflection when IsSystemObjectType(reflection.Type) => false,
            ReflectionTypeInfo reflection => HasReliableReflectionMemberSet(reflection.Type),
            ClassTypeInfo or StructTypeInfo or RecordTypeInfo or SoaRecordTypeInfo or SoaRowTypeInfo
                or InterfaceTypeInfo or EnumTypeInfo or UnionTypeInfo or NewtypeInfo
                or TupleTypeInfo => true,
            NullableTypeInfo nullable => ShouldReportUndefinedMember(nullable.InnerType, memberName, includeStaticMembers),
            ObliviousTypeInfo oblivious => ShouldReportUndefinedMember(oblivious.InnerType, memberName, includeStaticMembers),
            _ => false
        };
    }

    private static bool IsKnownBuiltInMemberWithoutReflection(TypeInfo receiverType, string memberName, bool includeStaticMembers)
    {
        if (BuiltInObjectMembers.Contains(memberName))
            return true;

        return receiverType switch
        {
            SimpleTypeInfo simple when BuiltInTypes.Is(simple, BuiltInTypes.String) =>
                BuiltInStringInstanceMembers.Contains(memberName)
                || (includeStaticMembers && BuiltInStringStaticMembers.Contains(memberName)),
            SimpleTypeInfo simple when BuiltInTypes.Is(simple, BuiltInTypes.Bool) =>
                BuiltInBooleanInstanceMembers.Contains(memberName)
                || (includeStaticMembers && BuiltInBooleanStaticMembers.Contains(memberName)),
            SimpleTypeInfo simple when IsBuiltInNumericType(simple) =>
                BuiltInNumericInstanceMembers.Contains(memberName)
                || (includeStaticMembers && BuiltInNumericStaticMembers.Contains(memberName)),
            SimpleTypeInfo simple when BuiltInTypes.Is(simple, BuiltInTypes.Char) =>
                BuiltInNumericInstanceMembers.Contains(memberName)
                || (includeStaticMembers && BuiltInNumericStaticMembers.Contains(memberName)),
            ArrayTypeInfo => BuiltInArrayMembers.Contains(memberName),
            _ => false
        };
    }

    private static bool IsKnownBuiltInReceiverWithoutReflection(SimpleTypeInfo type)
        => BuiltInTypes.Is(type, BuiltInTypes.String)
           || BuiltInTypes.Is(type, BuiltInTypes.Bool)
           || BuiltInTypes.Is(type, BuiltInTypes.Char)
           || IsBuiltInNumericType(type);

    private static bool IsBuiltInNumericType(SimpleTypeInfo type)
        => BuiltInTypes.Is(type, BuiltInTypes.Int)
           || BuiltInTypes.Is(type, BuiltInTypes.Long)
           || BuiltInTypes.Is(type, BuiltInTypes.Float)
           || BuiltInTypes.Is(type, BuiltInTypes.Double)
           || BuiltInTypes.Is(type, BuiltInTypes.Decimal)
           || BuiltInTypes.Is(type, BuiltInTypes.Byte)
           || BuiltInTypes.Is(type, BuiltInTypes.SByte)
           || BuiltInTypes.Is(type, BuiltInTypes.Short)
           || BuiltInTypes.Is(type, BuiltInTypes.UShort)
           || BuiltInTypes.Is(type, BuiltInTypes.UInt)
           || BuiltInTypes.Is(type, BuiltInTypes.ULong);

    private static bool HasReliableReflectionMemberSet(Type type)
    {
        var assembly = type.Assembly;
        return assembly == typeof(object).Assembly
            || assembly == typeof(Console).Assembly
            || assembly == typeof(Enumerable).Assembly
            || (type.Namespace?.StartsWith("System.", StringComparison.Ordinal) == true && !type.IsInterface);
    }

    private TypeInfo ResolveAliasAndMetadata(TypeInfo typeInfo)
        => typeInfo switch
        {
            AliasTypeInfo alias => ResolveAliasAndMetadata(_declarationContext.ResolveDeclaredAlias(alias)),
            ObliviousTypeInfo oblivious => ResolveAliasAndMetadata(oblivious.InnerType),
            _ => typeInfo
        };

    private void ReportUndefinedMember(TypeInfo receiverType, MemberAccessExpression member, bool includeStaticMembers)
        => ReportUndefinedMember(receiverType, member.MemberName, member.Line, _spans.GetMemberNameColumn(member), includeStaticMembers);

    private void ReportUndefinedMember(
        TypeInfo receiverType,
        string memberName,
        int line,
        int column,
        bool includeStaticMembers,
        string? typeNameOverride = null)
    {
        var length = Math.Max(1, memberName.Length);
        var typeName = typeNameOverride ?? NullabilityMetadataReflection.FormatTypeInfo(receiverType);
        var similarMembers = FindSimilarMemberNames(receiverType, memberName, includeStaticMembers);

        var sourceSnippet = GetSourceSnippet(line);
        if (sourceSnippet != null && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.UndefinedMember(
                _currentFilePath,
                line,
                column,
                sourceSnippet,
                length,
                memberName,
                typeName,
                similarMembers));
            return;
        }

        Error(
            ErrorCode.UndefinedMember,
            $"Member '{memberName}' not found on type '{typeName}'",
            line,
            column,
            similarMembers.Count > 0 ? $"Did you mean '{similarMembers[0]}'?" : null,
            length);
    }

    private List<string> FindSimilarMemberNames(TypeInfo receiverType, string memberName, bool includeStaticMembers)
    {
        var candidates = GetAvailableMemberNames(receiverType, includeStaticMembers)
            .Distinct(StringComparer.Ordinal)
            .ToList();

        return candidates.Count == 0
            ? new List<string>()
            : new SmartSuggester(candidates).SuggestSimilarNames(memberName);
    }

    private List<string> GetAvailableMemberNames(
        TypeInfo receiverType,
        bool includeStaticMembers)
    {
        receiverType = ResolveAliasAndMetadata(receiverType);
        if (receiverType is NullableTypeInfo nullableType)
        {
            var nullableMembers = new List<string> { "HasValue", "Value" };
            nullableMembers.AddRange(GetAvailableMemberNames(nullableType.InnerType, includeStaticMembers));
            return nullableMembers;
        }

        if (receiverType is SimpleTypeInfo or GenericTypeInfo or ArrayTypeInfo)
        {
            var clrType = _clrTypeConversion.TryConvertTypeInfoToClrType(receiverType);
            if (clrType != null)
                return GetReflectionMemberNames(clrType, includeStaticMembers);
        }
        if (receiverType is ReflectionTypeInfo reflectionType)
            return GetReflectionMemberNames(reflectionType.Type, includeStaticMembers);

        var members = _declarationContext.GetAvailableSourceMemberNames(
            receiverType, includeStaticMembers);
        if (!includeStaticMembers && _declarationContext.SourceObjectMembersApply(receiverType))
            members.AddRange(GetReflectionMemberNames(typeof(object), includeStaticMembers: false));
        return members;
    }

    private static List<string> GetReflectionMemberNames(Type type, bool includeStaticMembers)
    {
        var flags = BindingFlags.Public | BindingFlags.Instance;
        if (includeStaticMembers)
            flags |= BindingFlags.Static;

        return type.GetProperties(flags).Select(property => property.Name)
            .Concat(type.GetFields(flags).Select(field => field.Name))
            .Concat(type.GetMethods(flags)
                .Where(method => !method.IsSpecialName)
                .Select(method => method.Name))
            .Distinct(StringComparer.Ordinal)
            .ToList();
    }

    private SymbolDeclaration CreateSymbolDeclaration(DeclaredMemberInfo member, string? filePath)
    {
        var sourceText = _projectSources.TryGetProjectSourceText(filePath);
        return new SymbolDeclaration(
            member.Name,
            filePath,
            member.Line,
            AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(sourceText, member.Name, member.Line, member.Column),
            member.KindName);
    }

    private TypeInfo ResolveMember(TypeInfo objectType, string memberName, bool includeStaticMembers = true)
    {
        if (objectType is ObliviousTypeInfo obliviousType)
        {
            objectType = obliviousType.InnerType;
        }

        if (objectType is ByRefTypeInfo byRefType)
        {
            objectType = byRefType.InnerType;
        }

        objectType = _declarationContext.ResolveDeclaredAlias(objectType);
        var extensionReceiverType = objectType;
        Dictionary<string, TypeInfo>? sourceGenericSubstitution = null;

        if (objectType is NullableTypeInfo nullableType)
        {
            if (memberName == "HasValue")
                return BuiltInTypes.Bool;
            if (memberName == "Value")
                return nullableType.InnerType;
        }

        if (objectType is SoaRowTypeInfo soaRowType)
        {
            if (AnalyzerMemberResolution.TryGetSoaColumn(soaRowType.Declaration, memberName) is { } rowColumn)
            {
                return _declarationContext.TryGetSoaType(
                    soaRowType.Declaration,
                    out var soaOwner)
                    ? _typeSubstitution.ResolveTypeForSourceOwner(
                        rowColumn.Type,
                        soaOwner,
                        substitution: null)
                    : _typeResolver.ResolveType(rowColumn.Type);
            }

            return BuiltInTypes.Unknown;
        }

        if (objectType is SoaRecordTypeInfo soaRecordType)
        {
            if (!includeStaticMembers)
            {
                if (AnalyzerMemberResolution.TryGetSoaColumn(soaRecordType.Declaration, memberName) is { } column)
                    return new ArrayTypeInfo(_typeSubstitution.ResolveTypeForSourceOwner(
                        column.Type,
                        soaRecordType,
                        substitution: null));

                return memberName switch
                {
                    "length" or "capacity" => BuiltInTypes.Int,
                    "add" => AnalyzerMemberResolution.CreateSoaIntrinsic("add", BuiltInTypes.Int),
                    "clear" => AnalyzerMemberResolution.CreateSoaIntrinsic("clear", BuiltInTypes.Void),
                    "ensureCapacity" => AnalyzerMemberResolution.CreateSoaIntrinsicWithParameter("ensureCapacity", BuiltInTypes.Void, "capacity", BuiltInTypes.Int),
                    "copyRow" => AnalyzerMemberResolution.CreateSoaIntrinsicWithTwoParameters("copyRow", BuiltInTypes.Void, "from", BuiltInTypes.Int, "to", BuiltInTypes.Int),
                    _ => BuiltInTypes.Unknown
                };
            }

            if (memberName == "wrap")
            {
                var parameters = soaRecordType.Declaration.Columns
                    .Select(column => (Name: column.Name, Type: new ArrayTypeInfo(
                        _typeSubstitution.ResolveTypeForSourceOwner(
                            column.Type,
                            soaRecordType,
                            substitution: null)) as TypeInfo))
                    .Concat(new[] { (Name: "length", Type: BuiltInTypes.Int as TypeInfo) })
                    .ToList();
                return new FunctionTypeInfo()
                {
                    SyntheticName = "wrap",
                    ParameterNames = parameters.Select(parameter => parameter.Name).ToList(),
                    ParameterTypes = parameters.Select(parameter => parameter.Type).ToList(),
                    ReturnType = soaRecordType
                };
            }

            return BuiltInTypes.Unknown;
        }

        // Convert built-in simple types to reflection types for full CLR member resolution.
        // This enables member access on literals and built-in types (e.g., 5.ToString(), "hello".Length)
        if (objectType is SimpleTypeInfo && !BuiltInTypes.IsUnknown(objectType)
            && BuiltInTypes.IsNot(objectType, BuiltInTypes.Null) && BuiltInTypes.IsNot(objectType, BuiltInTypes.Never) && BuiltInTypes.IsNot(objectType, BuiltInTypes.Void))
        {
            var clrType = _clrTypeConversion.TryConvertTypeInfoToClrType(objectType);
            if (clrType != null)
                objectType = new ReflectionTypeInfo(clrType);
        }

        if (objectType is GenericTypeInfo sourceGeneric
            && _typeSubstitution.ResolveGenericDefinition(sourceGeneric) is { } sourceGenericDefinition
            && sourceGenericDefinition is not ReflectionTypeInfo)
        {
            sourceGenericSubstitution = _declarationContext.CreateGenericSubstitution(
                sourceGenericDefinition,
                sourceGeneric.TypeArguments);
            objectType = sourceGenericDefinition;
        }
        else
        {
            if (!includeStaticMembers
                && _declarationContext.TryResolveKnownArrayExtensionMember(
                    objectType,
                    memberName,
                    _usingNamespaces.Contains("System"),
                    out var arrayExtensionMemberType))
            {
                return arrayExtensionMemberType;
            }

            if (!includeStaticMembers
                && _declarationContext.TryResolveKnownGenericStructuralMember(
                    objectType, memberName, out var structuralMemberType))
            {
                return structuralMemberType;
            }

            if (objectType is GenericTypeInfo or ArrayTypeInfo)
            {
                var clrType = _clrTypeConversion.TryConvertTypeInfoToClrType(objectType);
                if (clrType != null)
                {
                    objectType = new ReflectionTypeInfo(clrType);
                }
                else
                {
                    var bindingClrType = _clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(objectType);
                    if (bindingClrType != null &&
                        TryResolveReflectionPropertyOrField(bindingClrType, memberName, includeStaticMembers, out var memberType))
                    {
                        return memberType;
                    }
                }
            }
        }

        // Handle reflection-based types
        if (objectType is ReflectionTypeInfo reflectionType)
        {
            var type = reflectionType.Type;
            var memberFlags = GetReflectionMemberFlags(includeStaticMembers);

            if (_declarationContext.TryResolveRuntimeInterfaceMethodMember(
                    type,
                    memberName,
                    includeStaticMembers,
                    out var interfaceMemberType))
            {
                return interfaceMemberType;
            }

            if (TryResolveReflectionPropertyOrField(type, memberName, includeStaticMembers, out var memberType))
                return memberType;

            // Try methods (get all matching methods to handle overloads)
            var methods = type.GetMethods(memberFlags)
                .Where(m => m.Name == memberName)
                .ToArray();

            if (methods.Length > 0)
            {
                // Return a special type that represents overloaded methods
                return new ReflectionMethodGroupInfo(methods, $"{methods[0].Name}(...)");
            }

            // No member found on reflection type, try extension methods against the source receiver shape.
            return TryResolveExtensionMethod(extensionReceiverType, memberName);
        }

        if (_declarationContext.TryGetSourceMemberShape(
                objectType, sourceGenericSubstitution, out var sourceShape))
        {
            TypeInfo? resolvedMember = null;
            if (_declarationContext.TryResolveDeclaredValueMember(
                    sourceShape.Owner,
                    sourceShape.DeclaredMembers,
                    memberName,
                    sourceGenericSubstitution,
                    out var resolvedValueMember))
            {
                resolvedMember = resolvedValueMember;
            }
            resolvedMember ??= _memberResolution.ResolveDeclaredFunctionMember(
                sourceShape.DeclaredMembers, memberName, sourceGenericSubstitution, sourceShape.Owner);
            if (resolvedMember != null)
                return resolvedMember;

            if (!includeStaticMembers
                && sourceShape.SupportsPrimaryParameters
                && _declarationContext.TryResolvePrimaryParameter(
                    sourceShape.Owner,
                    sourceShape.PrimaryParameters,
                    memberName,
                    sourceGenericSubstitution,
                    out var primaryConstructorMember))
            {
                return primaryConstructorMember;
            }
            if (includeStaticMembers
                && _declarationContext.TryResolveNestedType(
                    sourceShape.Owner, memberName, requireExported: false, out var nestedTypeMember))
            {
                return nestedTypeMember;
            }
            if (sourceShape.BaseType != null)
            {
                var baseMember = ResolveMember(
                    sourceShape.BaseType, memberName, includeStaticMembers);
                if (!BuiltInTypes.IsUnknown(baseMember))
                    return baseMember;
            }
            if (!includeStaticMembers
                && sourceShape.SupportsObjectMembers
                && AnalyzerMemberResolution.TryResolveSourceObjectMember(memberName, out var objectMember))
            {
                return objectMember;
            }
        }

        if (objectType is TupleTypeInfo tupleType)
        {
            if (_declarationContext.TryResolveTupleMember(tupleType, memberName, out var tupleMember))
                return tupleMember;

            if (!includeStaticMembers && AnalyzerMemberResolution.TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        if (objectType is EnumTypeInfo enumType)
        {
            if (includeStaticMembers && enumType.Declaration.Members.Any(member => member.Name == memberName))
                return objectType;

            if (!includeStaticMembers && AnalyzerMemberResolution.TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        if (objectType is AnonymousUnionTypeInfo)
        {
            return memberName switch
            {
                "Index" => BuiltInTypes.Int,
                "Value" => BuiltInTypes.Object,
                _ => TryResolveExtensionMethod(objectType, memberName)
            };
        }

        if (objectType is UnionTypeInfo)
        {
            return objectType;
        }

        // Handle newtype .Value access
        if (objectType is NewtypeInfo newtypeInfo)
        {
            if (memberName == "Value")
                return _typeSubstitution.ResolveTypeForSourceOwner(
                    newtypeInfo.UnderlyingType,
                    newtypeInfo,
                    substitution: null);
            if (!includeStaticMembers && AnalyzerMemberResolution.TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        // Handle array types
        if (objectType is ArrayTypeInfo arrayType)
        {
            if (memberName == "Length")
                return BuiltInTypes.Int;
        }

        // Member not found on type, try extension methods
        return TryResolveExtensionMethod(extensionReceiverType, memberName);
    }

    private static BindingFlags GetReflectionMemberFlags(bool includeStaticMembers)
    {
        var memberFlags = BindingFlags.Public | BindingFlags.Instance;
        if (includeStaticMembers)
            memberFlags |= BindingFlags.Static;
        return memberFlags;
    }

    private static bool TryResolveReflectionPropertyOrField(
        Type type,
        string memberName,
        bool includeStaticMembers,
        out TypeInfo memberType)
    {
        var memberFlags = GetReflectionMemberFlags(includeStaticMembers);

        var property = type.GetProperty(memberName, memberFlags);
        if (property != null)
        {
            memberType = NullabilityMetadataReflection.ConvertProperty(property);
            return true;
        }

        var field = type.GetField(memberName, memberFlags);
        if (field != null)
        {
            memberType = NullabilityMetadataReflection.ConvertField(field);
            return true;
        }

        // .NET events resolve to a distinct symbol (never a field) so that `+=`/`-=` against
        // them is rejected with a friendly diagnostic and `on`/`off` can subscribe via the
        // event's add_/remove_ accessors instead of touching the private backing field.
        var evt = type.GetEvent(memberName, memberFlags);
        if (evt != null)
        {
            memberType = new ReflectionEventInfo(
                evt.Name,
                evt.GetAddMethod(nonPublic: true),
                evt.GetRemoveMethod(nonPublic: true),
                evt.EventHandlerType,
                evt.DeclaringType,
                $"event {evt.Name}");
            return true;
        }

        memberType = BuiltInTypes.Unknown;
        return false;
    }

    private void ReportSoaRowEscape(Expression expression, string action)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.InvalidSyntax,
            $"SoA row views cannot be {action}; use the table and row index instead",
            line,
            column,
            "Read or write a column with table[index].column in the same expression.",
            length);
    }

    private void ReportSoaRowHiddenAllocation(Expression expression)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.InvalidSyntax,
            "this operation would allocate row objects; use column access instead",
            line,
            column,
            "Read or write a column with table[index].column in the same expression.",
            length);
    }

    private void ReportSoaTableNullConditionalAccess(MemberAccessExpression member)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(member);
        Error(
            ErrorCode.InvalidSyntax,
            "SoA tables cannot use null-conditional member access",
            line,
            column,
            "SoA table wrappers are value views; use direct table.member access.",
            length);
    }

    private bool ReportSoaRowEscapeIfNeeded(Expression expression, TypeInfo type, string action)
    {
        if (type is SoaRowTypeInfo)
        {
            ReportSoaRowEscape(expression, action);
            return true;
        }

        return false;
    }

    private static bool IsSystemObjectType(Type type)
        => type == typeof(object) || string.Equals(type.FullName, "System.Object", StringComparison.Ordinal);

    private TypeInfo TryResolveExtensionMethod(TypeInfo targetType, string methodName)
    {
        // Find all extension methods with matching name
        var matchingExtensions = _extensionMethods
            .Where(em => em.Name == methodName)
            .ToList();

        if (matchingExtensions.Count == 0)
        {
            var externalExtensions = FindExternalExtensionMethods(targetType, methodName);
            if (externalExtensions.Count == 1)
                return new ReflectionMethodInfo(externalExtensions[0], $"{externalExtensions[0].Name}(...)");

            if (externalExtensions.Count > 1)
                return new ReflectionMethodGroupInfo(externalExtensions.ToArray(), $"{externalExtensions[0].Name}(...)");

            return BuiltInTypes.Unknown;
        }

        // Filter by matching this parameter type
        var applicableExtensions = new List<FunctionDeclaration>();
        foreach (var ext in matchingExtensions)
        {
            if (ext.Parameters.Count == 0)
                continue;

            if (_extensionMethodResolution.IsExtensionReceiverApplicable(ext, targetType))
            {
                applicableExtensions.Add(ext);
            }
        }

        if (applicableExtensions.Count == 0)
        {
            var externalExtensions = FindExternalExtensionMethods(targetType, methodName);
            if (externalExtensions.Count == 1)
                return new ReflectionMethodInfo(externalExtensions[0], $"{externalExtensions[0].Name}(...)");

            if (externalExtensions.Count > 1)
                return new ReflectionMethodGroupInfo(externalExtensions.ToArray(), $"{externalExtensions[0].Name}(...)");

            return BuiltInTypes.Unknown;
        }

        // If only one match, return it
        if (applicableExtensions.Count == 1)
            return _functionTypeFactory.CreateFromDeclaration(applicableExtensions[0], _currentTypeName);

        // Multiple matches - return fact-backed method group for overload resolution
        return NSharpMethodGroupInfoFactory.FromFunctions(
            applicableExtensions.Select(declaration =>
                _functionTypeFactory.CreateFromDeclaration(declaration, _currentTypeName)).ToList());
    }

    private List<MethodInfo> FindExternalExtensionMethods(TypeInfo targetType, string methodName)
    {
        var exactClrType = _clrTypeConversion.TryConvertTypeInfoToClrType(targetType);
        var targetClrType = exactClrType ?? _clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(targetType);
        if (targetClrType == null)
            return new List<MethodInfo>();

        // Only the SURROGATE receiver type exists here, so the instance surface was never searched and
        // an instance method that hides this name must still win. See HasRuntimeInstanceMethod.
        if (exactClrType == null && _declarationContext.HasRuntimeInstanceMethod(targetClrType, methodName))
            return new List<MethodInfo>();

        var methods = new List<MethodInfo>();

        foreach (var assembly in _mlcAssemblies)
        {
            foreach (var type in GetLoadableTypes(assembly))
            {
                if (type.Namespace == null || !_usingNamespaces.Contains(type.Namespace))
                    continue;

                if (!(type.IsSealed && type.IsAbstract))
                    continue;

                foreach (var method in type.GetMethods(BindingFlags.Public | BindingFlags.Static))
                {
                    if (method.Name != methodName || !AnalyzerOverloadFacts.HasExtensionAttribute(method))
                        continue;

                    var parameters = method.GetParameters();
                    if (parameters.Length == 0)
                        continue;

                    if (AnalyzerOverloadFacts.IsExtensionParameterCompatible(parameters[0].ParameterType, targetClrType))
                        methods.Add(method);
                }
            }
        }

        return methods;
    }

    private static IEnumerable<Type> GetLoadableTypes(Assembly assembly)
    {
            return assembly.GetTypes();
    }

    /// <summary>
    /// Walks a CLR parameter type and a TypeInfo argument in parallel to extract TypeInfo bindings
    /// for generic parameters. Handles interface compatibility (e.g., List&lt;T&gt; matching IEnumerable&lt;TSource&gt;).
    /// </summary>
    private TypeInfo AnalyzeCall(CallExpression call)
    {
        if (TryAnalyzeResultConstructorCall(call, out var resultType))
            return resultType;

        var calleeType = AnalyzeCallCallee(call.Callee);
        ReportPossibleNullAccess(call.Callee, calleeType, call.Line, call.Column, "call", isNullConditional: false);

        // Analyze arguments
        var argTypes = new List<TypeInfo>();
        if (calleeType is FunctionTypeInfo functionType && functionType.ParameterTypes != null)
        {
            int[]? syntheticParameterIndexByArgument = null;
            var parameterStartIndex = AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call);
            if (_syntheticCallReporter.TryBindAndReport(
                    functionType,
                    AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call),
                    call,
                    out var boundSyntheticArguments,
                    parameterStartIndex,
                    reportErrors: false))
            {
                syntheticParameterIndexByArgument = boundSyntheticArguments;
            }

            // Receiver-style extension calls supply the first source parameter from the member
            // access receiver, not the argument list.
            var syntheticExpectedBindings = _syntheticCallWalk.InferGenericBindings(
                functionType, call, Array.Empty<TypeInfo>(), AnalyzeSyntheticCallReceiver(functionType, call));
            for (int i = 0; i < call.Arguments.Count; i++)
            {
                var argument = call.Arguments[i];
                var argumentErrorsBefore = _errors.Count;
                Dictionary<Expression, TypeInfo>? refOutTargetExpressionTypes;
                var expectedIndex = syntheticParameterIndexByArgument != null
                    ? syntheticParameterIndexByArgument[i]
                    : i + parameterStartIndex;
                var expectedType = _syntheticCallValidator.GetExpectedArgumentType(
                    functionType,
                    call,
                    i,
                    expectedIndex,
                    syntheticExpectedBindings);

                argTypes.Add(AnalyzeRefOutArgumentExpression(argument, expectedType, out refOutTargetExpressionTypes));
                ReportInvalidRefOutArgumentTargetIfNeeded(argument, argumentErrorsBefore, refOutTargetExpressionTypes);
            }
        }
        else
        {
            // When the callee is a method group, lambdas will be analyzed later during
            // method binding with proper delegate type context. Analyzing them here with
            // null expected type would give lambda parameters 'unknown' type, producing
            // spurious errors for operators like || and && inside the lambda body.
            var isMethodGroup = calleeType is ReflectionMethodGroupInfo or NSharpMethodGroupInfo
                or ReflectionMethodInfo;
            foreach (var arg in call.Arguments)
            {
                var argumentErrorsBefore = _errors.Count;
                if (isMethodGroup && arg.Value is LambdaExpression)
                {
                    argTypes.Add(BuiltInTypes.Unknown);
                    ReportInvalidRefOutArgumentTargetIfNeeded(arg, argumentErrorsBefore, expressionTypes: null);
                    continue;
                }
                argTypes.Add(AnalyzeRefOutArgumentExpression(
                    arg,
                    expectedType: null,
                    out var refOutTargetExpressionTypes,
                    allowUnboundCallableReference: isMethodGroup));
                ReportInvalidRefOutArgumentTargetIfNeeded(arg, argumentErrorsBefore, refOutTargetExpressionTypes);
            }
        }

        for (var i = 0; i < argTypes.Count; i++)
        {
            if (argTypes[i] is SoaRowTypeInfo)
            {
                ReportSoaRowEscape(call.Arguments[i].Value, "passed as an argument");
            }
        }

        if (ReportSoaDirectColumnMutatingArrayCallIfNeeded(call))
            return BuiltInTypes.Unknown;
        if (ReportUnsupportedSoaDirectColumnStaticArrayCallIfNeeded(call))
            return BuiltInTypes.Unknown;
        if (ReportUnsupportedSoaDirectColumnArrayInstanceCallIfNeeded(call, calleeType))
            return BuiltInTypes.Unknown;
        if (ReportUnsupportedSoaDirectColumnCallArgumentIfNeeded(call, calleeType))
            return BuiltInTypes.Unknown;

        // Resolve return type from function type
        if (calleeType is FunctionTypeInfo funcType)
        {
            if (funcType.ParameterTypes != null)
            {
                _syntheticCallValidator.ValidateCall(
                    funcType, call, argTypes, AnalyzeSyntheticCallReceiver(funcType, call));
                return _syntheticCallValidator.ResolveReturnType(
                    funcType, call, argTypes, AnalyzeSyntheticCallReceiver(funcType, call));
            }
            return funcType.ReturnType ?? BuiltInTypes.Void;
        }

        // Handle reflection method calls
        if (calleeType is ReflectionMethodInfo methodInfo)
        {
            var boundCall = BindSingleReflectionMethod(methodInfo.Method, call);
            if (boundCall?.ReturnType != null)
                return boundCall.ReturnType;

            return _reflectionCallReporter.ReportUnboundCall(call, new[] { methodInfo.Method }, argTypes);
        }

        // Handle method group (overloaded methods)
        if (calleeType is ReflectionMethodGroupInfo methodGroup)
        {
            var boundCall = BindReflectionCall(methodGroup, call);
            if (boundCall?.ReturnType != null)
                return boundCall.ReturnType;

            return _reflectionCallReporter.ReportUnboundCall(call, methodGroup.Methods, argTypes);
        }

        // Handle newtype construction: UserId(42)
        if (calleeType is NewtypeInfo newtypeInfo)
        {
            if (call.Arguments.Count != 1)
            {
                Error($"Newtype '{newtypeInfo.Name}' constructor expects exactly 1 argument but got {call.Arguments.Count}",
                    call.Line, call.Column);
            }
            else
            {
                var underlyingType = _typeSubstitution.ResolveTypeForSourceOwner(
                    newtypeInfo.UnderlyingType,
                    newtypeInfo,
                    substitution: null);
                if (!_assignability.IsAssignable(underlyingType, argTypes[0]))
                {
                    Error(ErrorCode.TypeMismatch,
                        $"Cannot construct '{newtypeInfo.Name}': argument of type '{argTypes[0]}' is not assignable to underlying type '{underlyingType}'",
                        call.Line, call.Column);
                }
            }
            return newtypeInfo;
        }

        // Handle N#-declared method group (overloaded N# methods)
        if (calleeType is NSharpMethodGroupInfo nsharpGroup)
        {
            var functions = GetNSharpMethodGroupFunctions(nsharpGroup);
            if (functions.Count > 0)
            {
                var boundFunction = _syntheticCallWalk.BindNSharpCall(
                    functions, call, argTypes, AnalyzeSyntheticCallReceiver(functions, call, argTypes));
                if (boundFunction != null)
                {
                    _semanticModel.RecordExpressionType(call.Callee.Line, call.Callee.Column, boundFunction);
                    _syntheticCallValidator.ValidateCall(
                        boundFunction, call, argTypes, AnalyzeSyntheticCallReceiver(boundFunction, call));
                    return _syntheticCallValidator.ResolveReturnType(
                        boundFunction, call, argTypes, AnalyzeSyntheticCallReceiver(boundFunction, call));
                }

                _syntheticCallValidator.ReportNoMatchingOverload(functions, call, argTypes);
                return BuiltInTypes.Unknown;
            }
        }

        return BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeRefOutArgumentExpression(
        Argument argument,
        TypeInfo? expectedType,
        out Dictionary<Expression, TypeInfo>? expressionTypes,
        bool allowUnboundCallableReference = false)
    {
        expressionTypes = null;
        if (argument.Modifier is not (ArgumentModifier.Ref or ArgumentModifier.Out))
        {
            return AnalyzeExpressionWithExpectedType(argument.Value, expectedType, allowUnboundCallableReference);
        }

        var modifier = argument.Modifier == ArgumentModifier.Ref ? "ref" : "out";
        if (ReportNullConditionalWriteTargetIfNeeded(argument.Value, $"used as the {modifier} argument"))
        {
            return BuiltInTypes.Unknown;
        }

        var targetExpectedType = expectedType is ByRefTypeInfo expectedByRef
            ? expectedByRef.InnerType
            : expectedType;
        var previousTargetTypes = _assignmentTargetExpressionTypes;
        expressionTypes = new Dictionary<Expression, TypeInfo>(ReferenceEqualityComparer.Instance);
        _assignmentTargetExpressionTypes = expressionTypes;
        try
        {
            var targetType = AnalyzeExpressionWithExpectedType(argument.Value, targetExpectedType, allowUnboundCallableReference);
            return BuiltInTypes.IsUnknown(targetType)
                ? targetType
                : new ByRefTypeInfo(targetType);
        }
        finally
        {
            _assignmentTargetExpressionTypes = previousTargetTypes;
        }
    }

    private bool ReportInvalidRefOutArgumentTargetIfNeeded(
        Argument argument,
        int argumentErrorsBefore,
        Dictionary<Expression, TypeInfo>? expressionTypes)
    {
        if (argument.Modifier is not (ArgumentModifier.Ref or ArgumentModifier.Out)
            || _errors.Count != argumentErrorsBefore)
        {
            return false;
        }

        var modifier = argument.Modifier == ArgumentModifier.Ref ? "ref" : "out";
        var action = $"used as the {modifier} argument";
        if (ReportNullConditionalWriteTargetIfNeeded(argument.Value, action))
        {
            return true;
        }

        if (ReportSoaTableMemberMutationIfNeeded(argument.Value, expressionTypes, action)
            || ReportUnsupportedBuiltInIndexedMutationIfNeeded(argument.Value, expressionTypes, action))
        {
            return true;
        }
        if (ReportReadonlyFieldRefOutArgumentIfNeeded(argument.Value, modifier, expressionTypes))
        {
            return true;
        }

        if (IsRefOutArgumentTarget(argument.Value, expressionTypes))
        {
            return false;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(argument.Value);
        Error(
            ErrorCode.InvalidSyntax,
            $"The '{modifier}' argument needs an assignable target",
            line,
            column,
            $"Use a variable, field, or indexed array/SoA column element as the {modifier} argument.",
            length);
        return true;
    }

    private bool IsRefOutArgumentTarget(
        Expression expression,
        Dictionary<Expression, TypeInfo>? expressionTypes) => expression switch
    {
        IdentifierExpression => true,
        MemberAccessExpression memberAccess => IsAddressableRefOutMember(memberAccess, expressionTypes),
        IndexAccessExpression indexAccess => IsAddressableRefOutIndex(indexAccess, expressionTypes),
        ParenthesizedExpression parenthesized => IsRefOutArgumentTarget(parenthesized.Inner, expressionTypes),
        _ => false
    };

    private bool IsAddressableRefOutMember(
        MemberAccessExpression member,
        Dictionary<Expression, TypeInfo>? expressionTypes)
    {
        if (expressionTypes == null)
            return true;

        if (expressionTypes.TryGetValue(member.Object, out var receiverType))
        {
            var resolvedReceiverType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(receiverType));
            if (resolvedReceiverType is ByRefTypeInfo byRefReceiver)
                resolvedReceiverType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(byRefReceiver.InnerType));

            if (resolvedReceiverType is SoaRowTypeInfo soaRowType
                && AnalyzerMemberResolution.TryGetSoaColumn(soaRowType.Declaration, member.MemberName) != null)
            {
                return true;
            }

            if (resolvedReceiverType is SoaRecordTypeInfo)
            {
                return false;
            }
        }

        if (IsStaticMemberAccessTarget(member.Object))
        {
            var staticClassification = ClassifyStaticFieldMember(member, expressionTypes);
            return staticClassification != false;
        }

        var instanceClassification = ClassifyInstanceFieldHop(member, expressionTypes);
        return instanceClassification != false;
    }

    private bool IsAddressableRefOutIndex(
        IndexAccessExpression index,
        Dictionary<Expression, TypeInfo>? expressionTypes)
    {
        if (expressionTypes == null)
            return true;

        var isRangeAccess = index.Index is RangeExpression
            || (expressionTypes.TryGetValue(index.Index, out var indexType) && IsRangeLikeType(indexType));
        if (isRangeAccess)
            return false;

        if (IsSoaColumnMemberAccess(index.Object))
            return true;

        if (!expressionTypes.TryGetValue(index.Object, out var receiverType))
            return true;

        var resolvedReceiverType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(receiverType));
        var isArrayReceiver = resolvedReceiverType is ArrayTypeInfo
            || resolvedReceiverType is ReflectionTypeInfo { Type.IsArray: true };
        if (!isArrayReceiver)
            return false;

        if (!expressionTypes.TryGetValue(index.Index, out var resolvedIndexType))
            return true;

        resolvedIndexType = _declarationContext.ResolveDeclaredAlias(resolvedIndexType);
        return BuiltInTypes.IsUnknown(resolvedIndexType)
            || BuiltInTypes.Is(resolvedIndexType, BuiltInTypes.Int)
            || IsIndexLikeType(resolvedIndexType);
    }

    private bool? ClassifyStaticFieldMember(
        MemberAccessExpression member,
        Dictionary<Expression, TypeInfo> expressionTypes)
    {
        if (!expressionTypes.TryGetValue(member.Object, out var ownerType))
            return null;

        return ClassifyStaticFieldMember(ownerType, member.MemberName);
    }

    private bool? ClassifyStaticFieldMember(TypeInfo owner, string memberName)
    {
        owner = _declarationContext.ResolveDeclaredAlias(owner);
        if (_declarationContext.TryFindMember(owner, memberName, out var selection))
        {
            return selection.Member is { } member
                && member.Kind == DeclaredMemberKind.Field
                && member.IsStatic;
        }

        var sourceOwner = _typeSubstitution.GetSourceDeclarationOwner(owner, out _);
        if (_declarationContext.TryGetSourceMemberShape(sourceOwner, null, out _))
            return false;

        owner = NormalizeReflectionMemberOwnerType(owner);
        if (owner is ReflectionTypeInfo reflected && reflected.Type is not System.Reflection.Emit.TypeBuilder
            && !reflected.Type.IsGenericTypeDefinition)
        {
            return ClassifyReflectionStaticFieldMember(reflected.Type, memberName);
        }

        return null;
    }

    private static bool? ClassifyReflectionStaticFieldMember(Type type, string memberName)
    {
        const BindingFlags flags = BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly;

            for (var current = type; current != null; current = current.BaseType)
            {
                if (current.GetFields(flags).Any(field => field.Name == memberName))
                {
                    return true;
                }

                if (current.GetProperties(flags).Any(property => property.Name == memberName)
                    || current.GetMethods(flags).Any(method => !method.IsSpecialName && method.Name == memberName)
                    || current.GetEvents(flags).Any(@event => @event.Name == memberName))
                {
                    return false;
                }
            }

        return false;
    }

    private TypeInfo AnalyzeCallCallee(Expression callee)
    {
        if (callee is IdentifierExpression identifier)
            return AnalyzeIdentifierCallTarget(identifier);

        return AnalyzeCallCalleeExpression(callee);
    }

    private TypeInfo AnalyzeIdentifierCallTarget(IdentifierExpression identifier)
    {
        var type = ResolveIdentifier(identifier.Name, identifier.Line, identifier.Column, reportMissingAsFunction: true);
        var nullState = GetExpressionNullState(identifier, type);
        var flowType = ApplyNullabilityFlowType(identifier, type, nullState);

        _semanticModel.RecordExpressionType(identifier.Line, identifier.Column, flowType);
        _semanticModel.RecordExpressionNullState(identifier.Line, identifier.Column, nullState);

        return flowType;
    }

    private TypeInfo AnalyzeExpressionWithExpectedType(
        Expression expression,
        TypeInfo? expectedType,
        bool allowUnboundCallableReference = false)
    {
        if (expression is LambdaExpression lambda)
            return AnalyzeLambda(lambda, expectedType);

        var previousExpectedType = _currentExpectedType;
        var previousAllowUnboundCallableReference = _allowUnboundCallableReference;
        if (expectedType != null)
            _currentExpectedType = expectedType;
        if (allowUnboundCallableReference)
            _allowUnboundCallableReference = true;

        try
        {
            return AnalyzeExpression(expression);
        }
        finally
        {
            _currentExpectedType = previousExpectedType;
            _allowUnboundCallableReference = previousAllowUnboundCallableReference;
        }
    }

    private TypeInfo AnalyzeExpressionWithoutExpectedType(Expression expression)
    {
        var previousExpectedType = _currentExpectedType;
        _currentExpectedType = null;

        try
        {
            return AnalyzeExpression(expression);
        }
        finally
        {
            _currentExpectedType = previousExpectedType;
        }
    }

    private bool TryAnalyzeResultConstructorCall(CallExpression call, out TypeInfo resultType)
    {
        resultType = BuiltInTypes.Unknown;

        if (call.Callee is not IdentifierExpression { Name: "Ok" or "Err" } identifier)
            return false;

        // Only meaningful in a Result-typed context; otherwise this is an ordinary call and the
        // factory decision does not apply (leave the annotation null).
        var isOk = identifier.Name == "Ok";
        if (!TryGetResultArmTypes(_currentExpectedType, out var okType, out var errType))
            return false;

        // In a Result context, `Ok`/`Err` are the compiler-known factory ONLY when the name is not
        // bound to a real in-scope symbol. If the user declared their own `Ok`/`Err` (function,
        // local, parameter, or import), defer to normal call resolution so we bind their symbol
        // instead of silently hijacking the call (C1: resolution must be semantic, not string
        if (_scopes.LookupSymbol(identifier.Name) != null)
        {
            call.IsResultFactory = false;
            return false;
        }

        call.IsResultFactory = true;

        if (call.Arguments.Count != 1)
        {
            Error(
                ErrorCode.WrongArgumentCount,
                $"{identifier.Name} needs exactly 1 argument, but you passed {call.Arguments.Count}",
                call.Line,
                call.Column,
                length: identifier.Name.Length);
            resultType = _currentExpectedType ?? BuiltInTypes.Unknown;
            return true;
        }

        var expectedArm = isOk ? okType : errType;
        var actualArm = AnalyzeExpressionWithExpectedType(call.Arguments[0].Value, expectedArm);
        if (!_assignability.IsAssignable(expectedArm, actualArm))
        {
            Error(
                ErrorCode.TypeMismatch,
                $"{identifier.Name} expects '{expectedArm}', but this argument has type '{actualArm}'",
                call.Arguments[0].Value.Line,
                call.Arguments[0].Value.Column);
        }

        resultType = _currentExpectedType ?? new GenericTypeInfo(
            "Result",
            new List<TypeInfo> { okType, errType },
            new ReflectionTypeInfo(typeof(NSharpLang.Runtime.Result<,>)));
        return true;
    }

    private static bool TryGetResultArmTypes(TypeInfo? type, out TypeInfo okType, out TypeInfo errType)
    {
        okType = BuiltInTypes.Unknown;
        errType = BuiltInTypes.Unknown;

        if (type is not GenericTypeInfo
            {
                TypeArguments.Count: 2,
                GenericDefinition: ReflectionTypeInfo definition,
            } generic
            || !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
                definition.Type,
                typeof(NSharpLang.Runtime.Result<,>)))
            return false;

        var name = generic.Name;
        if (!string.Equals(name, "Result", StringComparison.Ordinal)
            && !string.Equals(name, "NSharpLang.Runtime.Result", StringComparison.Ordinal)
            && !string.Equals(name, "NSharpLang.Runtime.Result`2", StringComparison.Ordinal))
            return false;

        okType = generic.TypeArguments[0];
        errType = generic.TypeArguments[1];
        return true;
    }

    /// <summary>
    /// Rejects DIRECT circular constraint dependencies between type parameters (`where T: T`,
    /// `where T: U where U: T`) — the CLR refuses such metadata at load, and the emitter's base-chain
    /// walks (a constrained parameter's BaseType is its constraint) would otherwise spin forever.
    /// Only BARE type-parameter constraints form edges: F-bounded shapes (`where T: IComparable&lt;T&gt;`)
    /// are legal and untouched. Mirrors N#'s CS0454.
    /// </summary>
    private void CheckCircularGenericConstraints(
        List<TypeParameter>? typeParameters, List<GenericConstraint>? constraints, string declName, int line, int column)
    {
        if (typeParameters == null || typeParameters.Count == 0 || constraints == null || constraints.Count == 0)
            return;

        // successor[i] = the type parameters parameter i is DIRECTLY constrained to (bare names only).
        var names = new List<string>(typeParameters.Count);
        foreach (var tp in typeParameters)
            names.Add(tp.Name);
        var successors = new List<int>[names.Count];
        foreach (var constraint in constraints)
        {
            var from = names.IndexOf(constraint.TypeParameter);
            if (from < 0)
                continue;
            foreach (var constraintTypeRef in constraint.Constraints)
            {
                if (constraintTypeRef is SimpleTypeReference simple)
                {
                    var to = names.IndexOf(simple.Name);
                    if (to >= 0)
                        (successors[from] ??= new List<int>()).Add(to);
                }
            }
        }

        // A successor chain longer than the parameter count must revisit a node — a cycle. Walking
        // every simple path is exponential in pathological cases, so mark each parameter that can
        // reach itself via a bounded depth-first walk over at most N distinct steps per path.
        var reported = false;
        for (var start = 0; start < names.Count && !reported; start++)
        {
            var stack = new Stack<(int Node, int Depth)>();
            stack.Push((start, 0));
            while (stack.Count > 0)
            {
                var (node, depth) = stack.Pop();
                if (depth >= names.Count)
                    continue;
                var next = successors[node];
                if (next == null)
                    continue;
                foreach (var to in next)
                {
                    if (to == start)
                    {
                        Error(ErrorCode.GenericConstraintViolation,
                            $"Type parameter `{names[start]}` of `{declName}` has a circular constraint dependency",
                            line, column,
                            $"Remove the cycle in the `where` clauses of `{declName}` — a type parameter cannot be constrained to itself, directly or through other type parameters.");
                        reported = true;
                        stack.Clear();
                        break;
                    }
                    stack.Push((to, depth + 1));
                }
            }
        }
    }

    /// <summary>
    /// The member-access RECEIVER's type, for the one inference arm that needs it — and only when the
    /// N#-owned walk says it will read one. The walk cannot re-enter the expression walk from across
    /// the boundary and a provider would be a callback, so the analysis happens here and the type
    /// crosses as a value; the DECISION stays in <see cref="AnalyzerSyntheticCallWalk.NeedsReceiverType"/>,
    /// which is the walk's own guard.
    /// </summary>
    private TypeInfo? AnalyzeSyntheticCallReceiver(FunctionTypeInfo functionType, CallExpression call)
        => AnalyzerSyntheticCallWalk.NeedsReceiverType(functionType, call)
            && call.Callee is MemberAccessExpression memberAccess
                ? AnalyzeExpression(memberAccess.Object)
                : null;

    private TypeInfo? AnalyzeSyntheticCallReceiver(
        IReadOnlyList<FunctionTypeInfo> candidates, CallExpression call, IReadOnlyList<TypeInfo> argTypes)
        => _syntheticCallWalk.AnyCandidateNeedsReceiverType(candidates, call, argTypes)
            && call.Callee is MemberAccessExpression memberAccess
                ? AnalyzeExpression(memberAccess.Object)
                : null;

    private TypeInfo ResolveDeclaredFunctionCallReturnType(FunctionDeclaration decl)
    {
        var sourceReturnType = decl.ReturnType != null
            ? _typeResolver.ResolveType(decl.ReturnType)
            : BuiltInTypes.Void;

        return AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType(
            decl.Name,
            decl.Modifiers.HasFlag(Modifiers.Async),
            decl.Modifiers.HasFlag(Modifiers.Generator),
            sourceReturnType);
    }

    private TypeInfo ResolveDeclaredFunctionCallReturnType(DeclaredMemberInfo member)
    {
        var sourceReturnType = member.ReturnType != null
            ? _typeResolver.ResolveType(member.ReturnType)
            : BuiltInTypes.Void;

        return AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType(
            member.Name, member.IsAsync, member.IsGenerator, sourceReturnType);
    }

    private FunctionTypeInfo? BindReflectionCall(ReflectionMethodGroupInfo methodGroup, CallExpression call)
    {
        TypeInfo? receiverTypeInfo = null;
        Type? receiverClrType = null;
        if (call.Callee is MemberAccessExpression memberAccess)
        {
            receiverTypeInfo = AnalyzeExpression(memberAccess.Object);
            receiverClrType = _clrTypeConversion.TryConvertTypeInfoToClrType(receiverTypeInfo)
                ?? _clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(receiverTypeInfo);
        }

        var analyzedNonLambdaArguments = new TypeInfo?[call.Arguments.Count];
        for (int i = 0; i < call.Arguments.Count; i++)
        {
            if (call.Arguments[i].Value is LambdaExpression)
                continue;

            analyzedNonLambdaArguments[i] = AnalyzeExpressionAllowingUnboundCallableReference(call.Arguments[i].Value);
        }

        var candidates = new List<ReflectionPreBoundCandidate>();

        foreach (var method in methodGroup.Methods)
        {
            var candidate = _reflectionArgumentBinder.PreBindReflectionMethod(
                method, call, receiverClrType, receiverTypeInfo, analyzedNonLambdaArguments);
            if (candidate == null)
                continue;

            candidates.Add(candidate);
        }

        if (candidates.Count == 0)
            return null;

        foreach (var candidate in candidates
                     .OrderByDescending(candidate => candidate.Score)
                     .ThenBy(candidate => candidate.UsesParams)
                     .ThenBy(candidate => candidate.DefaultsUsed))
        {
            var errorsBefore = _errors.Count;
            var boundCall = FinalizeBoundReflectionCall(candidate);
            if (boundCall != null)
                return boundCall;

            if (_errors.Count > errorsBefore)
            {
                _errors.RemoveRange(errorsBefore, _errors.Count - errorsBefore);
            }
        }

        return null;
    }

    private FunctionTypeInfo? BindSingleReflectionMethod(MethodInfo method, CallExpression call)
    {
        TypeInfo? receiverTypeInfo = null;
        Type? receiverClrType = null;
        if (call.Callee is MemberAccessExpression memberAccess)
        {
            receiverTypeInfo = AnalyzeExpression(memberAccess.Object);
            receiverClrType = _clrTypeConversion.TryConvertTypeInfoToClrType(receiverTypeInfo)
                ?? _clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(receiverTypeInfo);
        }

        var analyzedNonLambdaArguments = new TypeInfo?[call.Arguments.Count];
        for (int i = 0; i < call.Arguments.Count; i++)
        {
            if (call.Arguments[i].Value is LambdaExpression)
                continue;

            analyzedNonLambdaArguments[i] = AnalyzeExpressionAllowingUnboundCallableReference(call.Arguments[i].Value);
        }

        var preBound = _reflectionArgumentBinder.PreBindReflectionMethod(
            method, call, receiverClrType, receiverTypeInfo, analyzedNonLambdaArguments);
        if (preBound == null)
            return null;

        return FinalizeBoundReflectionCall(preBound);
    }

    /// <summary>
    /// The one step the N#-owned finalising walk cannot take for itself: analysing an expression.
    /// The walk runs in <see cref="AnalyzerReflectionArgumentBinder"/>, suspends at each analysis it
    /// needs and resumes with the answer, because a later lambda's expected signature is read from
    /// bindings an EARLIER lambda's answer produced — so no schedule can be computed up front. Which
    /// node, which entry point, which expected type, which expression-tree flag and whether to
    /// continue at all are the walk's decisions; this loop only performs the analysis it is handed.
    /// </summary>
    private FunctionTypeInfo? FinalizeBoundReflectionCall(ReflectionPreBoundCandidate candidate)
    {
        var state = _reflectionArgumentBinder.BeginFinalizeReflectionCall(candidate);
        for (var request = _reflectionArgumentBinder.NextReflectionAnalysis(state);
             request != null;
             request = _reflectionArgumentBinder.NextReflectionAnalysis(state))
        {
            _reflectionArgumentBinder.SupplyReflectionAnalysis(
                state,
                request.Lambda != null
                    ? AnalyzeLambda(
                        request.Lambda,
                        request.ExpectedType,
                        isExpressionTreeTarget: request.IsExpressionTreeTarget)
                    : AnalyzeExpressionWithExpectedType(request.Expression, request.ExpectedType));
        }

        return state.Result;
    }

    private TypeInfo AnalyzeAssignment(AssignmentExpression assignment)
    {
        // Discard assignment: `_ = expr` explicitly throws away a value. The discard is the
        // sanctioned escape hatch for must-use results, so the target binds nothing and we
        // only analyze the right-hand side.
        if (IsDiscardTarget(assignment.Target))
        {
            if (assignment.Operator != AssignmentOperator.Assign)
            {
                var (discardLine, discardColumn, discardLength) = _spans.GetExpressionDiagnosticSpan(assignment.Target);
                Error(
                    ErrorCode.InvalidSyntax,
                    "The discard `_` can only be used with a plain `=` assignment",
                    discardLine,
                    discardColumn,
                    "Use `_ = expr` to discard a value, or assign to a named variable for compound operators.",
                    discardLength);
            }

            var discardedType = AnalyzeExpression(assignment.Value);
            ReportSoaRowEscapeIfNeeded(assignment.Value, discardedType, "discarded");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(assignment.Value, "discarded");
            return discardedType;
        }

        if (ReportNullConditionalWriteTargetIfNeeded(
                assignment.Target,
                $"assigned with '{OperatorFacts.GetAssignmentText(assignment.Operator)}'"))
        {
            var invalidValueType = AnalyzeExpression(assignment.Value);
            if (invalidValueType is SoaRowTypeInfo)
            {
                ReportSoaRowEscape(assignment.Value, "assigned");
            }

            return BuiltInTypes.Unknown;
        }

        var previousSuppressNullabilityFlowType = _suppressNullabilityFlowType;
        var previousSuppressErrorTupleResultUse = _suppressErrorTupleResultUse;
        var previousAllowEventReference = _allowEventReference;
        Dictionary<Expression, TypeInfo>? targetExpressionTypes = null;
        TypeInfo targetType;
        try
        {
            _suppressNullabilityFlowType = true;
            _suppressErrorTupleResultUse = assignment.Operator == AssignmentOperator.Assign;
            // Resolve the target without the bare-event guard so we can give a tailored
            // "use on/off" message instead of the generic one.
            _allowEventReference = true;
            if (IsWriteTargetNeedingExpressionTypes(assignment.Target))
            {
                // Collect the target chain's sub-expression types for write-target classifiers below.
                targetExpressionTypes = new Dictionary<Expression, TypeInfo>(ReferenceEqualityComparer.Instance);
                _assignmentTargetExpressionTypes = targetExpressionTypes;
            }
            targetType = AnalyzeExpression(assignment.Target);
        }
        finally
        {
            _assignmentTargetExpressionTypes = null;
            _allowEventReference = previousAllowEventReference;
            _suppressErrorTupleResultUse = previousSuppressErrorTupleResultUse;
            _suppressNullabilityFlowType = previousSuppressNullabilityFlowType;
        }

        if (targetType is SoaRowTypeInfo)
        {
            ReportSoaRowEscape(assignment.Target, "assigned");
            var previousExpectedTypeForInvalidTarget = _currentExpectedType;
            _currentExpectedType = targetType;
            var invalidValueType = AnalyzeExpression(assignment.Value);
            _currentExpectedType = previousExpectedTypeForInvalidTarget;
            if (invalidValueType is SoaRowTypeInfo)
            {
                ReportSoaRowEscape(assignment.Value, "assigned");
            }

            return BuiltInTypes.Unknown;
        }

        // `event += handler` / `-=` / `=` silently compiled to direct backing-field access before,
        // then threw FieldAccessException at runtime. N# never assigns events — subscribe with
        // `on`, unsubscribe with `off`. (A `+=` on a real Func/Action field is NOT an event and
        // falls through to the normal delegate-combine path below.)
        if (targetType is ReflectionEventInfo eventTarget)
        {
            ReportEventAssignment(assignment, eventTarget);
            // Still analyze the value so handler-body errors surface too.
            AnalyzeExpression(assignment.Value);
            // Return an error-recovery type (not the event) so the caller's bare-event guard
            // doesn't pile on a second diagnostic for the same assignment.
            return BuiltInTypes.Unknown;
        }

        if (ReportSoaTableMemberMutationIfNeeded(assignment.Target, targetExpressionTypes, "assigned directly"))
        {
            var previousExpectedTypeForInvalidTarget = _currentExpectedType;
            _currentExpectedType = targetType;
            var invalidValueType = AnalyzeExpression(assignment.Value);
            _currentExpectedType = previousExpectedTypeForInvalidTarget;
            if (invalidValueType is SoaRowTypeInfo)
            {
                ReportSoaRowEscape(assignment.Value, "assigned");
            }

            return BuiltInTypes.Unknown;
        }

        if (ReportUnsupportedBuiltInIndexedMutationIfNeeded(assignment.Target, targetExpressionTypes, "assigned"))
        {
            var previousExpectedTypeForInvalidTarget = _currentExpectedType;
            _currentExpectedType = targetType;
            var invalidValueType = AnalyzeExpression(assignment.Value);
            _currentExpectedType = previousExpectedTypeForInvalidTarget;
            if (invalidValueType is SoaRowTypeInfo)
            {
                ReportSoaRowEscape(assignment.Value, "assigned");
            }

            return BuiltInTypes.Unknown;
        }

        if (ReportInvalidAssignmentTargetIfNeeded(assignment))
        {
            var invalidValueType = AnalyzeExpression(assignment.Value);
            if (invalidValueType is SoaRowTypeInfo)
            {
                ReportSoaRowEscape(assignment.Value, "assigned");
            }

            return BuiltInTypes.Unknown;
        }

        if (ReportReadOnlyPropertyWriteTargetIfNeeded(
                assignment.Target,
                OperatorFacts.GetAssignmentText(assignment.Operator),
                targetExpressionTypes))
        {
            var invalidValueType = AnalyzeExpression(assignment.Value);
            if (invalidValueType is SoaRowTypeInfo)
            {
                ReportSoaRowEscape(assignment.Value, "assigned");
            }

            return BuiltInTypes.Unknown;
        }

        CheckNullCoalesceAssignmentTarget(assignment, targetType);

        // NL322 (the CS1612 analog), paired with the EmitAddressableExpression chain fix (defect
        // #22): a member write whose receiver chain passes through a VALUE-typed hop must be rooted
        // in real storage — a local/param/`this` (or a bare field of one), a FIELD chain over one of
        // those, or an array element. Every other value-typed receiver (a List indexer result, a
        // call result, a property result) is a temporary COPY: the store would land in the copy and
        // be silently discarded. Applies to compound operators too (they read-modify-write through
        // the same receiver). Reference-typed receivers are storage handles — any shape works.
        if (assignment.Target is MemberAccessExpression memberWriteTarget && targetExpressionTypes != null)
            CheckMemberWriteReceiverIsVariable(memberWriteTarget, targetExpressionTypes);

        var previousExpectedType = _currentExpectedType;
        _currentExpectedType = targetType;
        var valueType = AnalyzeExpression(assignment.Value);
        _currentExpectedType = previousExpectedType;
        if (valueType is SoaRowTypeInfo)
        {
            ReportSoaRowEscape(assignment.Value, "assigned");
        }
        else
        {
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(assignment.Value, "assigned");
        }

        // Check for readonly field assignment outside constructor
        CheckReadonlyFieldAssignment(assignment.Target, assignment.Line, assignment.Column, targetExpressionTypes);

        var valueAssignable = _assignability.IsAssignable(targetType, valueType);
        if (!valueAssignable)
        {
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(assignment.Value);
            var sourceSnippet = GetSourceSnippet(diagnosticLine);

            if (sourceSnippet != null && _currentFilePath != null)
            {
                var error = ErrorMessageBuilder.TypeMismatch(
                    _currentFilePath,
                    diagnosticLine,
                    diagnosticColumn,
                    sourceSnippet,
                    diagnosticLength,
                    valueType.ToString(),
                    targetType.ToString()
                );
                _errors.Add(error);
            }
            else
            {
                Error(ErrorCode.TypeMismatch, $"Type mismatch in assignment — expected '{targetType}' but got '{valueType}'",
                    diagnosticLine, diagnosticColumn, length: diagnosticLength);
            }
        }
        else if (ReportInvalidCompoundAssignmentIfNeeded(assignment, targetType, valueType))
        {
            return BuiltInTypes.Unknown;
        }

        UpdateNullStateAfterAssignment(assignment.Target, assignment.Value, targetType, valueType);
        _scopes.MarkErrorTupleResultAvailableAfterAssignment(assignment.Target);

        return targetType;
    }

    private bool ReportInvalidCompoundAssignmentIfNeeded(
        AssignmentExpression assignment,
        TypeInfo targetType,
        TypeInfo valueType)
    {
        if (!OperatorFacts.TryGetCompoundAssignmentBinaryOperator(assignment.Operator, out var binaryOperator))
        {
            return false;
        }

        if (BuiltInTypes.IsUnknown(targetType) || BuiltInTypes.IsUnknown(valueType))
        {
            return false;
        }

        if ((assignment.Operator is AssignmentOperator.AddAssign or AssignmentOperator.SubtractAssign)
            && IsDelegateLikeAssignmentType(targetType))
        {
            return false;
        }

        var operatorExpression = new BinaryExpression(
            assignment.Target,
            binaryOperator,
            assignment.Value,
            assignment.Line,
            assignment.Column);
        var resultType = AnalyzeCompoundAssignmentOperatorResult(binaryOperator, targetType, valueType, operatorExpression);
        if (BuiltInTypes.IsUnknown(resultType))
        {
            return true;
        }

        if (_assignability.IsAssignable(targetType, resultType))
        {
            return false;
        }

        var opText = OperatorFacts.GetAssignmentText(assignment.Operator);
        Error(
            ErrorCode.TypeMismatch,
            $"The '{opText}' assignment produces '{resultType}', which can't be stored in '{targetType}'",
            assignment.Line,
            assignment.Column,
            "Use an explicit assignment with a conversion, or choose operands whose operator result is assignable to the target.",
            Math.Max(1, opText.Length));
        return true;
    }

    private TypeInfo AnalyzeCompoundAssignmentOperatorResult(
        BinaryOperator binaryOperator,
        TypeInfo targetType,
        TypeInfo valueType,
        BinaryExpression operatorExpression)
    {
        return binaryOperator switch
        {
            BinaryOperator.Add or BinaryOperator.Subtract or BinaryOperator.Multiply or BinaryOperator.Divide
                => AnalyzeArithmeticOp(targetType, valueType, operatorExpression),
            _ => BuiltInTypes.Unknown
        };
    }

    private bool IsDelegateLikeAssignmentType(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        return resolved switch
        {
            FunctionTypeInfo => true,
            GenericTypeInfo { Name: "Func" or "Action" } => true,
            ReflectionTypeInfo reflection => _assignabilityFacts.IsDelegateType(reflection.Type) || AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(reflection.Type),
            ObliviousTypeInfo oblivious => IsDelegateLikeAssignmentType(oblivious.InnerType),
            NullableTypeInfo nullable => IsDelegateLikeAssignmentType(nullable.InnerType),
            _ => false
        };
    }

    private void CheckNullCoalesceAssignmentTarget(AssignmentExpression assignment, TypeInfo targetType)
    {
        if (assignment.Operator != AssignmentOperator.NullCoalesceAssign)
        {
            return;
        }

        if (CanNullCoalesceCheckForNull(targetType))
        {
            return;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(assignment.Target);
        Error(
            ErrorCode.TypeMismatch,
            $"The left side of '??=' has type '{targetType}', which can't be null",
            line,
            column,
            "Use '=' for values that are always present, or make the target nullable before using '??='.",
            length);
    }

    private bool CanNullCoalesceCheckForNull(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        return BuiltInTypes.IsUnknown(resolved)
            || resolved is GenericTypeInfo
            || resolved is NullableTypeInfo
            || AnalyzerConversionFacts.IsReferenceType(resolved)
            || (resolved is ReflectionTypeInfo reflection
                && Nullable.GetUnderlyingType(reflection.Type) != null);
    }

    private TypeInfo AnalyzeOnSubscription(OnSubscriptionExpression on)
    {
        var subscriptionType = new ReflectionTypeInfo(typeof(NSharpLang.Runtime.NSharpEventSubscription));

        var previousAllow = _allowEventReference;
        TypeInfo targetType;
        try
        {
            // Resolve the target without the bare-event guard so the diagnostics below are the
            // ones the user sees. Restored even if analysis throws.
            _allowEventReference = true;
            targetType = AnalyzeExpression(on.Target);
        }
        finally
        {
            _allowEventReference = previousAllow;
        }

        if (targetType is not ReflectionEventInfo eventInfo)
        {
            if (ReportSoaRowEscapeIfNeeded(on.Target, targetType, "used as an event target"))
            {
                AnalyzeLambda(on.Handler, reportInferenceFailure: false);
                return subscriptionType;
            }
            if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(on.Target, "used as an event target"))
            {
                AnalyzeLambda(on.Handler, reportInferenceFailure: false);
                return subscriptionType;
            }

            // Don't pile a "not an event" error on top of an already-reported resolution failure.
            if (!BuiltInTypes.IsUnknown(targetType))
            {
                var (line, column, length) = _spans.GetExpressionDiagnosticSpan(on.Target);
                Error(
                    ErrorCode.InvalidEventSubscription,
                    "`on` can only subscribe to a .NET event",
                    line,
                    column,
                    "Write `on <object>.<Event> (sender, args) => { ... }`. To combine plain delegates, use `+=` on a Func/Action field instead.",
                    length);
            }

            AnalyzeLambda(on.Handler, reportInferenceFailure: false);
            return subscriptionType;
        }

        var addMethod = eventInfo.AddMethod;
        var removeMethod = eventInfo.RemoveMethod;
        var handlerDelegateType = eventInfo.HandlerDelegateType;

        // Prove the event is actually subscribable now, with a clear diagnostic, rather than
        // letting the IL backend throw on a missing accessor or value-type receiver.
        if (addMethod == null || removeMethod == null || handlerDelegateType == null)
        {
            var (line, column, length) = _spans.GetExpressionDiagnosticSpan(on.Target);
            Error(
                ErrorCode.InvalidEventSubscription,
                $"'{eventInfo.Name}' can't be subscribed to — it has no accessible add/remove accessors",
                line,
                column,
                "This usually means the event is compiler-generated or inaccessible from N#.",
                length);
            AnalyzeLambda(on.Handler, reportInferenceFailure: false);
            return subscriptionType;
        }

        if (!addMethod.IsStatic && (eventInfo.DeclaringType?.IsValueType ?? false))
        {
            var (line, column, length) = _spans.GetExpressionDiagnosticSpan(on.Target);
            Error(
                ErrorCode.InvalidEventSubscription,
                $"subscribing to '{eventInfo.Name}' isn't supported — it's an instance event on a value type (struct)",
                line,
                column,
                "Events on struct receivers can't be bound safely. Subscribe through a reference-type instance instead.",
                length);
            AnalyzeLambda(on.Handler, new ReflectionTypeInfo(handlerDelegateType));
            return subscriptionType;
        }

        AnalyzeLambda(on.Handler, new ReflectionTypeInfo(handlerDelegateType));
        return subscriptionType;
    }

    private void AnalyzeOffStatement(OffStatement off)
    {
        var handleType = AnalyzeExpression(off.Handle);

        if (ReportSoaRowEscapeIfNeeded(off.Handle, handleType, "used as an off handle"))
        {
            return;
        }
        if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(off.Handle, "used as an off handle"))
        {
            return;
        }

        if (BuiltInTypes.IsUnknown(handleType))
        {
            return; // an earlier error already explained the problem
        }

        if (handleType is ReflectionTypeInfo reflection
            && typeof(NSharpLang.Runtime.NSharpEventSubscription).IsAssignableFrom(reflection.Type))
        {
            return;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(off.Handle);
        Error(
            ErrorCode.InvalidEventSubscription,
            "`off` expects a subscription returned by `on`",
            line,
            column,
            "Capture the subscription first (`sub := on <object>.<Event> handler`), then detach it with `off sub`.",
            length);
    }

    private void ReportEventAssignment(AssignmentExpression assignment, ReflectionEventInfo eventTarget)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(assignment.Target);
        var target = RenderEventTarget(assignment.Target);
        var name = eventTarget.Name;

        string message;
        string hint;
        if (assignment.Operator == AssignmentOperator.SubtractAssign)
        {
            message = $"'{name}' is a .NET event — it can't be unsubscribed with '-='";
            hint = $"Capture the subscription when you subscribe (`sub := on {target} handler`), then detach it with `off sub`.";
        }
        else if (assignment.Operator == AssignmentOperator.AddAssign)
        {
            message = $"'{name}' is a .NET event — it can't be subscribed to with '+='";
            hint = $"Subscribe with `on {target} (sender, args) => {{ ... }}`; it returns a subscription you can later pass to `off`.";
        }
        else
        {
            message = $"'{name}' is a .NET event — it can't be assigned with '='";
            hint = $"Subscribe with `on {target} (sender, args) => {{ ... }}` and unsubscribe with `off`.";
        }

        Error(ErrorCode.EventRequiresOnOff, message, line, column, hint, length);
    }

    private void ReportEventUsedAsValue(Expression expr, ReflectionEventInfo eventRef)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expr);
        var target = RenderEventTarget(expr);
        Error(
            ErrorCode.EventRequiresOnOff,
            $"'{eventRef.Name}' is a .NET event and can only be used with `on`/`off`",
            line,
            column,
            $"Subscribe with `on {target} (sender, args) => {{ ... }}`; the result is a subscription you can later pass to `off`.",
            length);
    }

    private static string RenderEventTarget(Expression expr) => expr switch
    {
        IdentifierExpression identifier => identifier.Name,
        ThisExpression => "this",
        BaseExpression => "base",
        MemberAccessExpression member => $"{RenderEventTarget(member.Object)}.{member.MemberName}",
        ParenthesizedExpression parenthesized => RenderEventTarget(parenthesized.Inner),
        CastExpression cast => RenderEventTarget(cast.Expression),
        _ => "<event>"
    };

    private void UpdateNullStateAfterAssignment(Expression target, Expression value, TypeInfo targetType, TypeInfo valueType)
    {
        var path = AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(target);
        if (path == null)
            return;

        _scopes.InvalidateNullFactsForAssignment(path);

        var valueState = GetExpressionNullState(value, valueType);
        if (valueState == NullState.Unknown)
            valueState = GetDefaultNullState(targetType);

        _scopes.SetNullStateInCurrentScope(path, valueState);
    }

    private static bool IsMemberAccessWriteTarget(Expression expression) => expression switch
    {
        MemberAccessExpression => true,
        ParenthesizedExpression parenthesized => IsMemberAccessWriteTarget(parenthesized.Inner),
        CheckedExpression checkedExpression => IsMemberAccessWriteTarget(checkedExpression.Expression),
        UncheckedExpression uncheckedExpression => IsMemberAccessWriteTarget(uncheckedExpression.Expression),
        _ => false
    };

    private static bool IsIndexAccessWriteTarget(Expression expression) => expression switch
    {
        IndexAccessExpression => true,
        ParenthesizedExpression parenthesized => IsIndexAccessWriteTarget(parenthesized.Inner),
        CheckedExpression checkedExpression => IsIndexAccessWriteTarget(checkedExpression.Expression),
        UncheckedExpression uncheckedExpression => IsIndexAccessWriteTarget(uncheckedExpression.Expression),
        _ => false
    };

    private static bool IsWriteTargetNeedingExpressionTypes(Expression expression)
        => IsMemberAccessWriteTarget(expression) || IsIndexAccessWriteTarget(expression);

    private static bool IsAssignmentTarget(Expression expression) => expression switch
    {
        IdentifierExpression => true,
        MemberAccessExpression => true,
        IndexAccessExpression => true,
        ParenthesizedExpression parenthesized => IsAssignmentTarget(parenthesized.Inner),
        _ => false
    };

    private bool ReportInvalidAssignmentTargetIfNeeded(AssignmentExpression assignment)
    {
        if (IsAssignmentTarget(assignment.Target))
        {
            return false;
        }

        var opText = OperatorFacts.GetAssignmentText(assignment.Operator);
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(assignment.Target);
        Error(
            ErrorCode.InvalidSyntax,
            $"The '{opText}' assignment needs an assignable target",
            line,
            column,
            "Use a variable, field, property, indexed element, or `_` discard as the left side.",
            length);
        return true;
    }

    private bool ReportNullConditionalWriteTargetIfNeeded(Expression target, string action)
    {
        if (!TryFindNullConditionalWriteTarget(target, out var nullConditionalTarget, out var targetKind))
        {
            return false;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(nullConditionalTarget);
        Error(
            ErrorCode.InvalidSyntax,
            $"Null-conditional {targetKind} can't be {action}",
            line,
            column,
            "Store the receiver in a local, guard it for null, then write through a normal member or index target.",
            length);
        return true;
    }

    private static bool TryFindNullConditionalWriteTarget(
        Expression target,
        out Expression nullConditionalTarget,
        out string targetKind)
    {
        switch (target)
        {
            case ParenthesizedExpression parenthesized:
                return TryFindNullConditionalWriteTarget(parenthesized.Inner, out nullConditionalTarget, out targetKind);
            case MemberAccessExpression { IsNullConditional: true } memberAccess:
                nullConditionalTarget = memberAccess;
                targetKind = "member access";
                return true;
            case MemberAccessExpression memberAccess:
                return TryFindNullConditionalWriteTarget(memberAccess.Object, out nullConditionalTarget, out targetKind);
            case IndexAccessExpression { IsNullConditional: true } indexAccess:
                nullConditionalTarget = indexAccess;
                targetKind = "index access";
                return true;
            case IndexAccessExpression indexAccess:
                return TryFindNullConditionalWriteTarget(indexAccess.Object, out nullConditionalTarget, out targetKind);
            default:
                nullConditionalTarget = target;
                targetKind = string.Empty;
                return false;
        }
    }

    private bool ReportReadOnlyPropertyWriteTargetIfNeeded(
        Expression target,
        string opText,
        Dictionary<Expression, TypeInfo>? expressionTypes)
    {
        if (!TryFindReadOnlyPropertyWriteTarget(target, expressionTypes, out var propertyName))
        {
            return false;
        }

        var action = opText is "++" or "--"
            ? $"changed with '{opText}'"
            : $"assigned with '{opText}'";
        var (line, column, length) = _spans.GetAssignmentTargetNameDiagnosticSpan(target, target.Line, target.Column);
        Error(
            ErrorCode.InvalidSyntax,
            $"Property '{propertyName}' is read-only — it can't be {action}",
            line,
            column,
            "Use a variable, field, settable property, or indexed element as the target.",
            length);
        return true;
    }

    private bool TryFindReadOnlyPropertyWriteTarget(
        Expression target,
        Dictionary<Expression, TypeInfo>? expressionTypes,
        out string propertyName)
    {
        switch (target)
        {
            case ParenthesizedExpression parenthesized:
                return TryFindReadOnlyPropertyWriteTarget(parenthesized.Inner, expressionTypes, out propertyName);

            case IdentifierExpression identifier:
                if (!_scopes.IsCurrentTypeMemberReference(identifier.Name))
                    break;

                var currentType = _scopes.CurrentTypeScope();
                if (currentType != null
                    && TryIsReadOnlyPropertyMember(currentType, identifier.Name, includeStaticMembers: false))
                {
                    propertyName = identifier.Name;
                    return true;
                }
                break;

            case MemberAccessExpression memberAccess:
                if (expressionTypes == null
                    || !expressionTypes.TryGetValue(memberAccess.Object, out var receiverType))
                {
                    break;
                }

                receiverType = _declarationContext.ResolveDeclaredAlias(receiverType);
                if (receiverType is ByRefTypeInfo byRefReceiver)
                    receiverType = _declarationContext.ResolveDeclaredAlias(byRefReceiver.InnerType);

                if (receiverType is NullableTypeInfo && memberAccess.MemberName is "HasValue" or "Value")
                {
                    propertyName = memberAccess.MemberName;
                    return true;
                }

                receiverType = GetNonNullableType(receiverType);
                if (TryIsReadOnlyPropertyMember(
                        receiverType,
                        memberAccess.MemberName,
                        includeStaticMembers: IsStaticMemberAccessTarget(memberAccess.Object)))
                {
                    propertyName = memberAccess.MemberName;
                    return true;
                }
                break;
        }

        propertyName = string.Empty;
        return false;
    }

    private bool TryIsReadOnlyPropertyMember(TypeInfo owner, string memberName, bool includeStaticMembers)
    {
        owner = _declarationContext.ResolveDeclaredAlias(owner);
        if (owner is ByRefTypeInfo byRefOwner)
            owner = _declarationContext.ResolveDeclaredAlias(byRefOwner.InnerType);

        if (owner is NullableTypeInfo && memberName is "HasValue" or "Value")
        {
            return true;
        }

        if (owner is SoaRecordTypeInfo or SoaRowTypeInfo)
        {
            return false;
        }

        if (_declarationContext.TryFindMember(owner, memberName, out var selection))
        {
            var member = selection.Member;
            return member != null
                && member.Kind == DeclaredMemberKind.Property
                && member.IsStatic == includeStaticMembers
                && (!member.HasSetter || member.IsReadonly);
        }

        var sourceOwner = _typeSubstitution.GetSourceDeclarationOwner(owner, out _);
        if (_declarationContext.TryGetSourceMemberShape(sourceOwner, null, out _))
            return false;

        owner = NormalizeReflectionMemberOwnerType(owner);
        if (owner is ReflectionTypeInfo reflected
            && reflected.Type is not System.Reflection.Emit.TypeBuilder
            && !reflected.Type.IsGenericTypeDefinition)
        {
            return TryIsReadOnlyReflectionProperty(reflected.Type, memberName, includeStaticMembers);
        }

        return false;
    }

    private static bool TryIsReadOnlyReflectionProperty(Type type, string memberName, bool includeStaticMembers)
    {
        var flags = BindingFlags.Public
            | BindingFlags.DeclaredOnly
            | (includeStaticMembers ? BindingFlags.Static : BindingFlags.Instance);

            for (var current = type; current != null; current = current.BaseType)
            {
                if (current.GetFields(flags).Any(field => field.Name == memberName))
                {
                    return false;
                }

                var property = current.GetProperties(flags).FirstOrDefault(candidate => candidate.Name == memberName);
                if (property != null)
                {
                    return property.GetSetMethod(nonPublic: false) == null;
                }

                if (current.GetMethods(flags).Any(method => !method.IsSpecialName && method.Name == memberName)
                    || current.GetEvents(flags).Any(@event => @event.Name == memberName))
                {
                    return false;
                }
            }

        return false;
    }

    // Sub-expression types of the assignment/unary-write TARGET currently being analyzed (reference-keyed;
    // populated at the AnalyzeExpression tail, consumed by write-target classifiers).
    private Dictionary<Expression, TypeInfo>? _assignmentTargetExpressionTypes;

    private bool ReportSoaTableMemberMutationIfNeeded(
        Expression target,
        Dictionary<Expression, TypeInfo>? expressionTypes,
        string action)
    {
        if (target is ParenthesizedExpression parenthesized)
            return ReportSoaTableMemberMutationIfNeeded(parenthesized.Inner, expressionTypes, action);
        if (target is CheckedExpression checkedExpression)
            return ReportSoaTableMemberMutationIfNeeded(checkedExpression.Expression, expressionTypes, action);
        if (target is UncheckedExpression uncheckedExpression)
            return ReportSoaTableMemberMutationIfNeeded(uncheckedExpression.Expression, expressionTypes, action);

        if (target is not MemberAccessExpression member
            || expressionTypes == null
            || !expressionTypes.TryGetValue(member.Object, out var receiverType))
        {
            return false;
        }

        if (_declarationContext.ResolveDeclaredAlias(GetNonNullableType(receiverType)) is not SoaRecordTypeInfo soaRecordType)
            return false;

        var isColumn = AnalyzerMemberResolution.TryGetSoaColumn(soaRecordType.Declaration, member.MemberName) != null;
        var isBookkeepingField = member.MemberName is "length" or "capacity";
        if (!isColumn && !isBookkeepingField)
            return false;

        ReportSoaTableMemberMutation(member, action, isColumn);
        return true;
    }

    private bool ReportSoaDirectColumnMutatingArrayCallIfNeeded(CallExpression call)
    {
        if (call.Arguments.Count == 0
            || call.Callee is not MemberAccessExpression memberAccess)
        {
            return false;
        }

        var action = memberAccess.MemberName switch
        {
            "Sort" => "sorted directly",
            "Reverse" => "reversed directly",
            _ => null
        };
        if (action == null)
            return false;

        if (!IsStaticArrayTarget(memberAccess.Object))
            return false;

        if (!TryGetSoaMutatingArrayCallColumnArgument(call, memberAccess.MemberName, out var columnMember))
            return false;

        ReportSoaTableMemberMutation(columnMember, action, isColumn: true);
        return true;
    }

    private bool TryGetSoaMutatingArrayCallColumnArgument(
        CallExpression call,
        string methodName,
        out MemberAccessExpression member)
    {
        for (var i = 0; i < call.Arguments.Count; i++)
        {
            var argument = call.Arguments[i];
            if (IsSoaMutatingArrayParameter(call, methodName, argument, i)
                && TryGetSoaColumnMemberAccess(argument.Value, out member))
            {
                return true;
            }
        }

        member = null!;
        return false;
    }

    private static bool IsSoaMutatingArrayParameter(
        CallExpression call,
        string methodName,
        Argument argument,
        int positionalIndex)
    {
        if (argument.Name != null)
        {
            return methodName switch
            {
                "Sort" => argument.Name is "array" or "keys" or "items",
                "Reverse" => argument.Name == "array",
                _ => false
            };
        }

        return methodName switch
        {
            "Sort" => IsPositionalArraySortParameter(call.Arguments.Count, positionalIndex),
            "Reverse" => positionalIndex == 0,
            _ => false
        };
    }

    private static bool IsPositionalArraySortParameter(int argumentCount, int positionalIndex)
        => argumentCount switch
        {
            1 => positionalIndex == 0,
            2 => positionalIndex is 0 or 1,
            3 => positionalIndex == 0,
            4 => positionalIndex is 0 or 1,
            _ => false
        };

    private bool ReportUnsupportedSoaDirectColumnStaticArrayCallIfNeeded(CallExpression call)
    {
        if (call.Arguments.Count == 0
            || call.Callee is not MemberAccessExpression memberAccess
            || !IsStaticArrayTarget(memberAccess.Object)
            || !TryGetUnsupportedSoaColumnStaticArrayArgument(call, memberAccess.MemberName, out var columnMember))
        {
            return false;
        }

        var line = memberAccess.Line;
        var column = _spans.GetMemberNameColumn(memberAccess);
        var length = Math.Max(1, memberAccess.MemberName.Length);
        Error(
            ErrorCode.InvalidSyntax,
            $"SoA table member '{columnMember.MemberName}' cannot be passed to Array method '{memberAccess.MemberName}' directly",
            line,
            column,
            "Use table.column[row] for element access, or Array.Fill, Array.Copy, and Array.Clear for supported whole-column operations.",
            length);
        return true;
    }

    private bool TryGetUnsupportedSoaColumnStaticArrayArgument(
        CallExpression call,
        string methodName,
        out MemberAccessExpression member)
    {
        for (var i = 0; i < call.Arguments.Count; i++)
        {
            var argument = call.Arguments[i];
            if (TryGetSoaColumnMemberAccess(argument.Value, out member)
                && !IsHandledSoaDirectColumnStaticArrayParameter(call, methodName, argument, i))
            {
                return true;
            }
        }

        member = null!;
        return false;
    }

    private static bool IsHandledSoaDirectColumnStaticArrayParameter(
        CallExpression call,
        string methodName,
        Argument argument,
        int positionalIndex)
        => IsPinnedSoaDirectColumnArrayParameter(call, methodName, argument, positionalIndex)
           || IsDedicatedSoaDirectColumnArrayDiagnosticParameter(call, methodName, argument, positionalIndex);

    private static bool IsPinnedSoaDirectColumnArrayParameter(
        CallExpression call,
        string methodName,
        Argument argument,
        int positionalIndex)
    {
        if (!SupportedSoaDirectColumnStaticArrayMethods.Contains(methodName))
            return false;

        if (argument.Name != null)
        {
            return methodName switch
            {
                "Fill" or "Clear" => argument.Name == "array",
                "Copy" => argument.Name is "sourceArray" or "destinationArray",
                _ => false
            };
        }

        return methodName switch
        {
            "Fill" or "Clear" => positionalIndex == 0,
            "Copy" when call.Arguments.Count == 3 => positionalIndex is 0 or 1,
            "Copy" when call.Arguments.Count == 5 => positionalIndex is 0 or 2,
            _ => false
        };
    }

    private static bool IsDedicatedSoaDirectColumnArrayDiagnosticParameter(
        CallExpression call,
        string methodName,
        Argument argument,
        int positionalIndex)
    {
        if (!DedicatedSoaDirectColumnStaticArrayDiagnostics.Contains(methodName))
            return false;

        if (argument.Name != null)
        {
            return methodName switch
            {
                "Resize" => argument.Name == "array",
                "Sort" => argument.Name is "array" or "keys" or "items",
                "Reverse" => argument.Name == "array",
                _ => false
            };
        }

        return methodName switch
        {
            "Resize" => positionalIndex == 0,
            "Sort" => IsPositionalArraySortParameter(call.Arguments.Count, positionalIndex),
            "Reverse" => positionalIndex == 0,
            _ => false
        };
    }

    private bool ReportUnsupportedSoaDirectColumnCallArgumentIfNeeded(CallExpression call, TypeInfo calleeType)
    {
        if (IsAllowedSoaDirectColumnCall(call, calleeType))
        {
            return false;
        }

        if (call.Callee is MemberAccessExpression memberAccess
            && !BuiltInTypes.IsUnknown(calleeType)
            && TryGetSoaColumnMemberAccess(memberAccess.Object, out var receiverColumn))
        {
            ReportUnsupportedSoaDirectColumnValueEscape(
                memberAccess.Object,
                receiverColumn,
                $"used as the receiver for '{memberAccess.MemberName}'");
            return true;
        }

        foreach (var argument in call.Arguments)
        {
            if (argument.Modifier is ArgumentModifier.Ref or ArgumentModifier.Out)
            {
                continue;
            }

            if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(argument.Value, "passed as an argument"))
            {
                return true;
            }
        }

        return false;
    }

    private bool IsAllowedSoaDirectColumnCall(CallExpression call, TypeInfo calleeType)
        => calleeType is FunctionTypeInfo { SyntheticName: "wrap" }
           || call.Callee is MemberAccessExpression memberAccess && IsStaticArrayTarget(memberAccess.Object);

    private bool ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(Expression expression, string action)
    {
        if (!TryGetSoaColumnMemberAccess(expression, out var columnMember))
        {
            return false;
        }

        ReportUnsupportedSoaDirectColumnValueEscape(expression, columnMember, action);
        return true;
    }

    private void ReportUnsupportedSoaDirectColumnValueEscape(
        Expression expression,
        MemberAccessExpression columnMember,
        string action)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(expression);
        Error(
            ErrorCode.InvalidSyntax,
            $"SoA table member '{columnMember.MemberName}' cannot be {action} directly",
            line,
            column,
            "Use table.column[row] for element access, Table.wrap for table views, or Array.Fill, Array.Copy, and Array.Clear for supported whole-column operations.",
            length);
    }

    private bool ReportUnsupportedSoaDirectColumnArrayInstanceCallIfNeeded(CallExpression call, TypeInfo calleeType)
        => ReportUnsupportedSoaDirectColumnArrayInstanceMethodReferenceIfNeeded(call.Callee, calleeType, isCall: true);

    private bool ReportUnsupportedSoaDirectColumnArrayInstanceMethodReferenceIfNeeded(
        Expression expression,
        TypeInfo type,
        bool isCall)
    {
        if (expression is not MemberAccessExpression memberAccess
            || !IsRuntimeArrayInstanceMethodReference(type)
            || !TryGetSoaColumnMemberAccess(memberAccess.Object, out var columnMember))
        {
            return false;
        }

        var line = memberAccess.Line;
        var column = _spans.GetMemberNameColumn(memberAccess);
        var length = Math.Max(1, memberAccess.MemberName.Length);
        var action = isCall ? "call" : "use";
        var suffix = isCall ? " directly" : " as a value";
        Error(
            ErrorCode.InvalidSyntax,
            $"SoA table member '{columnMember.MemberName}' cannot {action} array method '{memberAccess.MemberName}'{suffix}",
            line,
            column,
            "Use table.column[row] for element access, or Array.Fill, Array.Copy, and Array.Clear for supported whole-column operations.",
            length);
        return true;
    }

    private bool IsRuntimeArrayInstanceMethodReference(TypeInfo type)
    {
        var resolvedType = _declarationContext.ResolveDeclaredAlias(type);
        return resolvedType switch
        {
            ReflectionMethodInfo methodInfo => IsRuntimeArrayInstanceMethod(methodInfo.Method),
            ReflectionMethodGroupInfo methodGroup => methodGroup.Methods.Length > 0
                && methodGroup.Methods.All(IsRuntimeArrayInstanceMethod),
            _ => false
        };
    }

    private static bool IsRuntimeArrayInstanceMethod(MethodInfo method)
        => !method.IsStatic;

    private bool IsStaticArrayTarget(Expression expression)
    {
        switch (expression)
        {
            case ParenthesizedExpression parenthesized:
                return IsStaticArrayTarget(parenthesized.Inner);
            case IdentifierExpression identifier:
                if (_scopes.LookupSymbol(identifier.Name) != null)
                    return false;
                if (_scopes.LookupType(identifier.Name) is { } localType)
                    return IsSystemArrayTypeInfo(_declarationContext.ResolveDeclaredAlias(localType));
                if (TryResolveTypeValuedMemberAccess(identifier, out var identifierType)
                    && IsSystemArrayTypeInfo(identifierType))
                {
                    return true;
                }
                if (identifier.Name == "Array")
                {
                    return true;
                }
                return false;
            case MemberAccessExpression { Object: IdentifierExpression { Name: "System" } system, MemberName: "Array" }:
                if (_scopes.LookupSymbol(system.Name) != null)
                    return false;
                if (_scopes.LookupType(system.Name) != null)
                {
                    return TryResolveTypeValuedMemberAccess(expression, out var systemArrayType)
                        && IsSystemArrayTypeInfo(systemArrayType);
                }
                if (TryResolveTypeValuedMemberAccess(expression, out var resolvedSystemArrayType))
                {
                    return IsSystemArrayTypeInfo(resolvedSystemArrayType);
                }
                return true;
            default:
                if (TryResolveTypeValuedMemberAccess(expression, out var ownerType))
                {
                    return IsSystemArrayTypeInfo(ownerType);
                }
                return false;
        }
    }

    private bool IsSystemArrayTypeInfo(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        return _clrTypeConversion.TryConvertTypeInfoToClrType(resolved) == typeof(Array)
            || resolved is ExternalTypeInfo { Name: "Array" or "System.Array" };
    }

    private bool TryGetSoaColumnMemberAccess(Expression expression, out MemberAccessExpression member)
    {
        switch (expression)
        {
            case MemberAccessExpression memberAccess when _soaColumnMemberAccesses.Contains(memberAccess):
                member = memberAccess;
                return true;
            case MemberAccessExpression memberAccess
                when TryGetSoaRecordReceiverType(memberAccess.Object, out var soaRecordType)
                    && AnalyzerMemberResolution.TryGetSoaColumn(soaRecordType.Declaration, memberAccess.MemberName) != null:
                member = memberAccess;
                return true;
            case ParenthesizedExpression parenthesized:
                return TryGetSoaColumnMemberAccess(parenthesized.Inner, out member);
            case CheckedExpression checkedExpression:
                return TryGetSoaColumnMemberAccess(checkedExpression.Expression, out member);
            case UncheckedExpression uncheckedExpression:
                return TryGetSoaColumnMemberAccess(uncheckedExpression.Expression, out member);
            default:
                member = null!;
                return false;
        }
    }

    private bool TryGetSoaRecordReceiverType(Expression expression, out SoaRecordTypeInfo soaRecordType)
    {
        switch (expression)
        {
            case IdentifierExpression identifier:
                var resolvedType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(_scopes.LookupSymbol(identifier.Name) ?? BuiltInTypes.Unknown));
                if (resolvedType is ByRefTypeInfo byRefReceiver)
                    resolvedType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(byRefReceiver.InnerType));
                if (resolvedType is SoaRecordTypeInfo receiverSoaRecordType)
                {
                    soaRecordType = receiverSoaRecordType;
                    return true;
                }
                break;
            case ParenthesizedExpression parenthesized:
                return TryGetSoaRecordReceiverType(parenthesized.Inner, out soaRecordType);
            case CheckedExpression checkedExpression:
                return TryGetSoaRecordReceiverType(checkedExpression.Expression, out soaRecordType);
            case UncheckedExpression uncheckedExpression:
                return TryGetSoaRecordReceiverType(uncheckedExpression.Expression, out soaRecordType);
        }

        soaRecordType = null!;
        return false;
    }

    private bool ReportUnsupportedBuiltInIndexedMutationIfNeeded(
        Expression target,
        Dictionary<Expression, TypeInfo>? expressionTypes,
        string action)
    {
        if (target is ParenthesizedExpression parenthesized)
            return ReportUnsupportedBuiltInIndexedMutationIfNeeded(parenthesized.Inner, expressionTypes, action);
        if (target is CheckedExpression checkedExpression)
            return ReportUnsupportedBuiltInIndexedMutationIfNeeded(checkedExpression.Expression, expressionTypes, action);
        if (target is UncheckedExpression uncheckedExpression)
            return ReportUnsupportedBuiltInIndexedMutationIfNeeded(uncheckedExpression.Expression, expressionTypes, action);

        if (target is not IndexAccessExpression indexAccess
            || expressionTypes == null
            || !expressionTypes.TryGetValue(indexAccess.Object, out var receiverType))
        {
            return false;
        }

        var resolvedReceiverType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(receiverType));
        var isRangeAccess = indexAccess.Index is RangeExpression
            || (expressionTypes.TryGetValue(indexAccess.Index, out var indexType) && IsRangeLikeType(indexType));
        if (isRangeAccess && IsSoaColumnMemberAccess(indexAccess.Object))
        {
            ReportSoaColumnSliceHiddenAllocation(indexAccess);
            return true;
        }

        if (IsStringType(resolvedReceiverType))
        {
            ReportUnsupportedStringIndexedMutation(indexAccess, action);
            return true;
        }

        var isArrayReceiver = resolvedReceiverType is ArrayTypeInfo
            || resolvedReceiverType is ReflectionTypeInfo { Type.IsArray: true };
        if (!isArrayReceiver)
            return false;

        if (!isRangeAccess)
            return false;

        ReportUnsupportedArraySliceMutation(indexAccess, action);
        return true;
    }

    private void ReportUnsupportedArraySliceMutation(IndexAccessExpression indexAccess, string action)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(indexAccess);
        Error(
            ErrorCode.InvalidSyntax,
            $"Array slices cannot be {action}",
            line,
            column,
            "Assign individual elements, or construct a replacement array value explicitly.",
            length);
    }

    private void ReportUnsupportedStringIndexedMutation(IndexAccessExpression indexAccess, string action)
    {
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(indexAccess);
        Error(
            ErrorCode.InvalidSyntax,
            $"String characters and slices cannot be {action}",
            line,
            column,
            "Create a new string value instead; strings are immutable.",
            length);
    }

    private void ReportSoaTableMemberMutation(MemberAccessExpression member, string action, bool isColumn)
    {
        var line = member.Line;
        var column = _spans.GetMemberNameColumn(member);
        var length = Math.Max(1, member.MemberName.Length);
        var suggestion = isColumn
            ? "Write individual rows with table[index].column, or construct/wrap the table with the desired column arrays."
            : "Use add, clear, ensureCapacity, or copyRow so length and capacity stay consistent with the columns.";
        Error(
            ErrorCode.InvalidSyntax,
            $"SoA table member '{member.MemberName}' cannot be {action}",
            line,
            column,
            suggestion,
            length);
    }

    // NL322: report when a member write's receiver chain bottoms out in a value-typed expression
    // that is NOT a variable. CONSERVATIVE by design — hops whose types or members cannot be
    // resolved here never fire (under-enforcement keeps unmodelled shapes compiling as before).
    private void CheckMemberWriteReceiverIsVariable(MemberAccessExpression target, Dictionary<Expression, TypeInfo> expressionTypes)
    {
        var offender = FindValueCopyReceiver(target.Object, expressionTypes);
        if (offender == null)
            return;
        expressionTypes.TryGetValue(offender, out var offenderType);
        var receiverDescription = offender switch
        {
            IndexAccessExpression => "an indexer result (a copy of the element)",
            CallExpression => "a call result (a copy of the return value)",
            MemberAccessExpression => "a property result (a copy of the value)",
            _ => "a temporary value (a copy)",
        };
        var typeName = _declarationContext.ResolveDeclaredAlias(offenderType ?? BuiltInTypes.Unknown).ToString() ?? "value";
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(offender);
        var sourceSnippet = GetSourceSnippet(line);
        if (sourceSnippet != null && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.MemberWriteThroughValueCopy(
                _currentFilePath, line, column, sourceSnippet, length, target.MemberName, typeName, receiverDescription));
        }
        else
        {
            Error(
                ErrorCode.MemberWriteThroughValueCopy,
                $"Cannot assign to '{target.MemberName}' because its receiver is a temporary copy of '{typeName}', not a variable",
                line,
                column,
                $"Copy the value into a local first, modify the local, then store the whole value back",
                length);
        }
    }

    // Returns the offending non-variable VALUE-typed receiver in the chain, or null when the chain
    // is rooted in addressable storage (or is reference-typed / unresolvable — conservative).
    private Expression? FindValueCopyReceiver(Expression receiver, Dictionary<Expression, TypeInfo> expressionTypes)
    {
        if (receiver is ParenthesizedExpression paren)
            return FindValueCopyReceiver(paren.Inner, expressionTypes);
        if (!expressionTypes.TryGetValue(receiver, out var receiverType)
            || !IsProvenValueTypeReceiver(_declarationContext.ResolveDeclaredAlias(receiverType)))
            return null;
        switch (receiver)
        {
            case IdentifierExpression:
            case ThisExpression:
            case BaseExpression:
                return null; // a local / parameter / bare field / `this` — a real variable.
            case IndexAccessExpression arrayElement
                when expressionTypes.TryGetValue(arrayElement.Object, out var indexedType)
                     && _declarationContext.ResolveDeclaredAlias(indexedType) is ArrayTypeInfo:
                return null; // an ARRAY element is a variable (the emitter addresses it via ldelema).
            case MemberAccessExpression hop:
            {
                var isFieldHop = ClassifyInstanceFieldHop(hop, expressionTypes);
                if (isFieldHop == null)
                    return null; // unresolvable owner — stay silent.
                if (isFieldHop == false)
                    return receiver; // a property/method result — a temporary copy.
                return FindValueCopyReceiver(hop.Object, expressionTypes); // FIELD hop — the root decides.
            }
            default:
                return receiver; // a call result / indexer copy / any other rvalue.
        }
    }

    // Whether a TypeInfo is PROVABLY a value type (user structs, record structs, external CLR value
    // types). Anything unresolved or reference-like answers false so the NL322 rule never fires on
    // shapes it cannot prove.
    private static bool IsProvenValueTypeReceiver(TypeInfo type) => type switch
    {
        StructTypeInfo => true,
        RecordTypeInfo record => record.IsStruct,
        ReflectionTypeInfo reflected => reflected.Type.IsValueType,
        _ => false,
    };

    // Whether `hop.MemberName` names an instance FIELD of `hop.Object`'s type: true/false when the
    // owner's declaration is resolvable (generic owners resolve by NAME via LookupType), null when
    // it is not (the classifier stays silent on those).
    private bool? ClassifyInstanceFieldHop(MemberAccessExpression hop, Dictionary<Expression, TypeInfo> expressionTypes)
    {
        if (!expressionTypes.TryGetValue(hop.Object, out var ownerType))
            return null;
        return ClassifyInstanceFieldMember(ownerType, hop.MemberName);
    }

    private bool? ClassifyInstanceFieldMember(TypeInfo owner, string memberName)
    {
        owner = _declarationContext.ResolveDeclaredAlias(owner);
        if (_declarationContext.TryFindMember(owner, memberName, out var selection))
        {
            return selection.Member is { } member
                && member.Kind == DeclaredMemberKind.Field
                && !member.IsStatic;
        }

        var sourceOwner = _typeSubstitution.GetSourceDeclarationOwner(owner, out _);
        if (_declarationContext.TryGetSourceMemberShape(sourceOwner, null, out _))
            return false;

        owner = NormalizeReflectionMemberOwnerType(owner);
        if (owner is ReflectionTypeInfo reflected && reflected.Type is not System.Reflection.Emit.TypeBuilder
            && !reflected.Type.IsGenericTypeDefinition)
        {
            return ClassifyReflectionInstanceFieldMember(reflected.Type, memberName);
        }

        return null;
    }

    private static bool? ClassifyReflectionInstanceFieldMember(Type type, string memberName)
    {
        const BindingFlags flags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly;

            for (var current = type; current != null; current = current.BaseType)
            {
                if (current.GetFields(flags).Any(field => field.Name == memberName))
                {
                    return true;
                }

                if (current.GetProperties(flags).Any(property => property.Name == memberName)
                    || current.GetMethods(flags).Any(method => !method.IsSpecialName && method.Name == memberName)
                    || current.GetEvents(flags).Any(@event => @event.Name == memberName))
                {
                    return false;
                }
            }

        return false;
    }

    private void CheckReadonlyFieldAssignment(
        Expression target,
        int line,
        int column,
        Dictionary<Expression, TypeInfo>? expressionTypes)
    {
        if (!TryGetReadonlyFieldTarget(target, expressionTypes, out var readonlyTarget))
        {
            return;
        }

        if (readonlyTarget.IsStatic)
        {
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetAssignmentTargetNameDiagnosticSpan(target, line, column);
            Error(
                ErrorCode.ReadonlyAssignment,
                $"Field '{readonlyTarget.Name}' is static readonly — it can only be initialized at its declaration",
                diagnosticLine,
                diagnosticColumn,
                "Move this value into the field initializer, or remove `readonly` if the static field needs to change later.",
                diagnosticLength);
            return;
        }

        // Instance readonly fields may be assigned by their owning constructor.
        if (_inConstructor && readonlyTarget.IsCurrentInstance)
            return;

        var (instanceLine, instanceColumn, instanceLength) = _spans.GetAssignmentTargetNameDiagnosticSpan(target, line, column);
        var message = _inConstructor
            ? $"Field '{readonlyTarget.Name}' is readonly — constructors can only assign readonly fields on the current instance"
            : $"Field '{readonlyTarget.Name}' is readonly — it can only be assigned in a constructor";
        var suggestion = _inConstructor
            ? "Assign the current instance field directly, or remove `readonly` if other instances must be mutated."
            : "Move this assignment into a constructor, or remove `readonly` if the field needs to change later.";
        Error(
            ErrorCode.ReadonlyAssignment,
            message,
            instanceLine,
            instanceColumn,
            suggestion,
            instanceLength);
    }

    private bool ReportReadonlyFieldRefOutArgumentIfNeeded(
        Expression target,
        string modifier,
        Dictionary<Expression, TypeInfo>? expressionTypes)
    {
        if (!TryGetReadonlyFieldTarget(target, expressionTypes, out var readonlyTarget))
        {
            return false;
        }

        if (!readonlyTarget.IsStatic && _inConstructor && readonlyTarget.IsCurrentInstance)
        {
            return false;
        }

        var (line, column, length) = _spans.GetAssignmentTargetNameDiagnosticSpan(target, target.Line, target.Column);
        var fieldKind = readonlyTarget.IsStatic ? "static readonly" : "readonly";
        var suggestion = readonlyTarget.IsStatic
            ? "Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`."
            : "Assign readonly fields inside a constructor, or remove `readonly` if this field must be passed by reference.";
        Error(
            ErrorCode.ReadonlyAssignment,
            $"Field '{readonlyTarget.Name}' is {fieldKind} — it can't be used as a {modifier} argument",
            line,
            column,
            suggestion,
            length);
        return true;
    }

    private bool ReportReadonlyFieldIncrementOrDecrementIfNeeded(
        UnaryExpression unary,
        Dictionary<Expression, TypeInfo>? expressionTypes)
    {
        if (!TryGetReadonlyFieldTarget(unary.Operand, expressionTypes, out var readonlyTarget))
        {
            return false;
        }

        if (!readonlyTarget.IsStatic && _inConstructor && readonlyTarget.IsCurrentInstance)
        {
            return false;
        }

        var opText = OperatorFacts.GetUnarySymbol(unary.Operator) ?? "operator";
        var (line, column, length) = _spans.GetAssignmentTargetNameDiagnosticSpan(unary.Operand, unary.Line, unary.Column);
        var fieldKind = readonlyTarget.IsStatic ? "static readonly" : "readonly";
        var suggestion = readonlyTarget.IsStatic
            ? "Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`."
            : _inConstructor
                ? "Assign the current instance field directly, or remove `readonly` if other instances must be mutated."
                : "Move this mutation into a constructor assignment, or remove `readonly` if the field needs to change later.";
        Error(
            ErrorCode.ReadonlyAssignment,
            $"Field '{readonlyTarget.Name}' is {fieldKind} — it can't be changed with '{opText}'",
            line,
            column,
            suggestion,
            length);
        return true;
    }

    private bool TryGetReadonlyFieldTarget(
        Expression target,
        Dictionary<Expression, TypeInfo>? expressionTypes,
        out ReadonlyFieldTarget readonlyTarget)
    {
        if (target is ParenthesizedExpression parenthesized)
            return TryGetReadonlyFieldTarget(parenthesized.Inner, expressionTypes, out readonlyTarget);

        if (target is MemberAccessExpression memberAccess
            && TryGetStaticReadonlyFieldTarget(memberAccess, expressionTypes, out readonlyTarget))
        {
            return true;
        }

        if (target is MemberAccessExpression instanceMemberAccess
            && TryGetInstanceReadonlyFieldTarget(instanceMemberAccess, expressionTypes, out readonlyTarget))
        {
            return true;
        }

        var fieldName = target switch
        {
            MemberAccessExpression { Object: ThisExpression } thisMemberAccess => thisMemberAccess.MemberName,
            IdentifierExpression ident => ident.Name,
            _ => string.Empty
        };

        if (fieldName.Length == 0 || _currentClass == null)
        {
            readonlyTarget = default;
            return false;
        }

        return TryGetCurrentOrInheritedReadonlyFieldTarget(fieldName, out readonlyTarget);
    }

    private bool TryGetCurrentOrInheritedReadonlyFieldTarget(
        string fieldName,
        out ReadonlyFieldTarget readonlyTarget)
    {
        readonlyTarget = default;
        if (_currentClass == null)
        {
            return false;
        }

        foreach (var member in _currentClass.Members)
        {
            if (member is FieldDeclaration field && field.Name == fieldName)
            {
                if (!field.Modifiers.HasFlag(Modifiers.Readonly))
                {
                    return false;
                }

                readonlyTarget = new ReadonlyFieldTarget(
                    field.Name,
                    field.Modifiers.HasFlag(Modifiers.Static),
                    IsCurrentInstance: !field.Modifiers.HasFlag(Modifiers.Static));
                return true;
            }

            if (member is PropertyDeclaration property && property.Name == fieldName)
            {
                return false;
            }
        }

        var currentType = _scopes.LookupType(_currentClass.Name);
        if (currentType == null
            || !TryFindReadonlyInstanceField(currentType, fieldName, out var inheritedFieldName))
        {
            return false;
        }

        readonlyTarget = new ReadonlyFieldTarget(
            inheritedFieldName,
            IsStatic: false,
            IsCurrentInstance: false);
        return true;
    }

    private bool TryGetStaticReadonlyFieldTarget(
        MemberAccessExpression target,
        Dictionary<Expression, TypeInfo>? expressionTypes,
        out ReadonlyFieldTarget readonlyTarget)
    {
        readonlyTarget = default;
        if (!IsStaticMemberAccessTarget(target.Object) || expressionTypes == null)
        {
            return false;
        }

        if (!expressionTypes.TryGetValue(target.Object, out var ownerType))
        {
            return false;
        }

        if (TryFindReadonlyStaticField(ownerType, target.MemberName, out var fieldName))
        {
            readonlyTarget = new ReadonlyFieldTarget(fieldName, IsStatic: true, IsCurrentInstance: false);
            return true;
        }

        return false;
    }

    private bool TryFindReadonlyStaticField(TypeInfo owner, string fieldName, out string resolvedFieldName)
    {
        resolvedFieldName = string.Empty;
        owner = _declarationContext.ResolveDeclaredAlias(owner);
        if (_declarationContext.TryFindReadonlyField(
                owner,
                fieldName,
                requireStatic: true,
                out resolvedFieldName,
                out var sourceMemberClaimed))
        {
            return true;
        }
        if (sourceMemberClaimed)
        {
            return false;
        }

        owner = NormalizeReflectionMemberOwnerType(owner);
        if (owner is ReflectionTypeInfo reflected && reflected.Type is not System.Reflection.Emit.TypeBuilder
            && !reflected.Type.IsGenericTypeDefinition)
        {
            return TryFindReadonlyReflectionStaticField(reflected.Type, fieldName, out resolvedFieldName);
        }

        return false;
    }

    private static bool TryFindReadonlyReflectionStaticField(Type type, string fieldName, out string resolvedFieldName)
    {
        const BindingFlags flags = BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly;
        resolvedFieldName = string.Empty;

            for (var current = type; current != null; current = current.BaseType)
            {
                var field = current.GetFields(flags).FirstOrDefault(candidate => candidate.Name == fieldName);
                if (field != null)
                {
                    if (field is not ({ IsInitOnly: true } or { IsLiteral: true }))
                    {
                        return false;
                    }

                    resolvedFieldName = field.Name;
                    return true;
                }

                if (current.GetProperties(flags).Any(property => property.Name == fieldName)
                    || current.GetMethods(flags).Any(method => !method.IsSpecialName && method.Name == fieldName)
                    || current.GetEvents(flags).Any(@event => @event.Name == fieldName))
                {
                    return false;
                }
            }

        return false;
    }

    private bool TryGetInstanceReadonlyFieldTarget(
        MemberAccessExpression target,
        Dictionary<Expression, TypeInfo>? expressionTypes,
        out ReadonlyFieldTarget readonlyTarget)
    {
        readonlyTarget = default;
        if (target.Object is ThisExpression || IsStaticMemberAccessTarget(target.Object) || expressionTypes == null)
        {
            return false;
        }

        if (!expressionTypes.TryGetValue(target.Object, out var receiverType))
        {
            return false;
        }

        var receiver = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(receiverType));
        if (receiver is ByRefTypeInfo byRefReceiver)
            receiver = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(byRefReceiver.InnerType));

        if (!TryFindReadonlyInstanceField(receiver, target.MemberName, out var fieldName))
        {
            return false;
        }

        readonlyTarget = new ReadonlyFieldTarget(fieldName, IsStatic: false, IsCurrentInstance: false);
        return true;
    }

    private bool TryFindReadonlyInstanceField(TypeInfo receiver, string fieldName, out string resolvedFieldName)
    {
        resolvedFieldName = string.Empty;
        receiver = _declarationContext.ResolveDeclaredAlias(receiver);
        if (_declarationContext.TryFindReadonlyField(
                receiver,
                fieldName,
                requireStatic: false,
                out resolvedFieldName,
                out var sourceMemberClaimed))
        {
            return true;
        }
        if (sourceMemberClaimed)
        {
            return false;
        }

        receiver = NormalizeReflectionMemberOwnerType(receiver);
        if (receiver is ReflectionTypeInfo reflected && reflected.Type is not System.Reflection.Emit.TypeBuilder
            && !reflected.Type.IsGenericTypeDefinition)
        {
            return TryFindReadonlyReflectionInstanceField(reflected.Type, fieldName, out resolvedFieldName);
        }

        return false;
    }

    private static bool TryFindReadonlyReflectionInstanceField(Type type, string fieldName, out string resolvedFieldName)
    {
        const BindingFlags flags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly;
        resolvedFieldName = string.Empty;

            for (var current = type; current != null; current = current.BaseType)
            {
                var field = current.GetFields(flags).FirstOrDefault(candidate => candidate.Name == fieldName);
                if (field != null)
                {
                    if (!field.IsInitOnly)
                    {
                        return false;
                    }

                    resolvedFieldName = field.Name;
                    return true;
                }

                if (current.GetProperties(flags).Any(property => property.Name == fieldName)
                    || current.GetMethods(flags).Any(method => !method.IsSpecialName && method.Name == fieldName)
                    || current.GetEvents(flags).Any(@event => @event.Name == fieldName))
                {
                    return false;
                }
            }

        return false;
    }

    private TypeInfo NormalizeReflectionMemberOwnerType(TypeInfo owner)
    {
        var runtimeType = owner is GenericTypeInfo ? _clrTypeConversion.TryConvertTypeInfoToClrType(owner) : null;
        return runtimeType != null ? new ReflectionTypeInfo(runtimeType) : NormalizeMemberOwnerType(owner);
    }

    private TypeInfo NormalizeMemberOwnerType(TypeInfo owner)
    {
        owner = _declarationContext.ResolveDeclaredAlias(owner);
        if (owner is GenericTypeInfo generic)
            owner = _typeSubstitution.ResolveGenericDefinition(generic) ?? owner;
        if (owner is SimpleTypeInfo or GenericTypeInfo or ArrayTypeInfo)
        {
            var clrOwner = _clrTypeConversion.TryConvertTypeInfoToClrType(owner);
            if (clrOwner != null)
                owner = new ReflectionTypeInfo(clrOwner);
        }

        return owner;
    }

    private FunctionTypeInfo AnalyzeLambda(
        LambdaExpression lambda,
        TypeInfo? expectedType = null,
        bool reportInferenceFailure = true,
        bool isExpressionTreeTarget = false)
    {
        var expectedSignature = GetFunctionSignature(expectedType);
        var targetsExpressionTree = isExpressionTreeTarget
            || AnalyzerFunctionTypeFactory.IsExpressionTreeLambdaTargetTypeInfo(
                expectedType, _declarationContext, _clrTypeConversion);
        PushScope(new Scope(ScopeKind.Function), lambda.Line, lambda.Column);
        var parameterTypes = new List<TypeInfo>();
        var reportedParameterInferenceFailure = false;

        foreach (var param in lambda.Parameters)
        {
            // Parser uses `var` as the placeholder type for untyped lambda parameters,
            // so only treat the parameter as explicit when it is something other than `var`.
            var paramIndex = parameterTypes.Count;
            var hasExplicitType = param.Type is not null
                && param.Type is not SimpleTypeReference { Name: "var" };
            var hasInferenceSource = expectedSignature?.ParameterTypes != null
                && paramIndex < expectedSignature.ParameterTypes.Count;

            var paramType = hasExplicitType
                ? _typeResolver.ResolveType(param.Type!)
                : hasInferenceSource
                    ? expectedSignature!.ParameterTypes![paramIndex]
                    : BuiltInTypes.Unknown;
            var (paramLine, paramColumn) = AnalyzerBindingFacts.GetParameterDeclarationPosition(
                param.Line,
                param.Column,
                lambda.Line,
                lambda.Column);

            // An untyped parameter with NO inference source (`f := x => x + 1` — nothing names the
            // delegate type) must be a compile-time error: letting the Unknown type flow on emits a
            // delegate with a garbage signature whose invocation CORRUPTS MEMORY at runtime
            // (AccessViolationException — probe-proven). Reported once per lambda; suppressed on
            // error-recovery paths that already diagnosed the surrounding statement.
            if (!hasExplicitType && !hasInferenceSource
                && reportInferenceFailure && !reportedParameterInferenceFailure)
            {
                Error(
                    ErrorCode.CannotInferType,
                    $"I can't figure out the type of lambda parameter '{param.Name}' — nothing here names the lambda's delegate type",
                    paramLine,
                    paramColumn,
                    $"Give the lambda a typed home (e.g., 'let f: Func<int, int> = {param.Name} => ...') or pass it directly where a delegate type is expected.",
                    param.Name.Length);
                reportedParameterInferenceFailure = true;
            }

            DeclareSymbol(param.Name, paramType, paramLine, paramColumn);
            RecordVariableInCurrentScope(param.Name, paramType);
            parameterTypes.Add(paramType);
        }

        TypeInfo returnType;
        if (lambda.ExpressionBody != null)
        {
            var errorsBeforeBody = _errors.Count;
            returnType = AnalyzeExpressionWithExpectedType(lambda.ExpressionBody, expectedSignature?.ReturnType);
            ReportSoaRowEscapeIfNeeded(lambda.ExpressionBody, returnType, "returned");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(lambda.ExpressionBody, "returned");
            if (targetsExpressionTree && _errors.Count == errorsBeforeBody)
            {
                var parameterNames = lambda.Parameters
                    .Select(parameter => parameter.Name)
                    .ToHashSet(StringComparer.Ordinal);
                ReportUnsupportedExpressionTreeExpressionIfNeeded(lambda.ExpressionBody, parameterNames);
            }
        }
        else if (lambda.BlockBody != null)
        {
            if (targetsExpressionTree)
            {
                ReportExpressionTreeBlockLambdaIfNeeded(lambda);
            }

            var previousReturnType = _currentReturnType;
            var previousFunction = _currentFunction;
            var previousFunctionReturnTypeWasOmitted = _currentFunctionReturnTypeWasOmitted;
            var previousFunctionIsAsync = _currentFunctionIsAsync;
            var previousInLoop = _inLoop;
            var previousFinallyDepth = _finallyDepth;
            var previousBreakTargetFinallyDepth = _breakTargetFinallyDepth;
            var previousContinueTargetFinallyDepth = _continueTargetFinallyDepth;
            _currentReturnType = expectedSignature?.ReturnType ?? BuiltInTypes.Unknown;
            _currentFunction = null;
            _currentFunctionReturnTypeWasOmitted = false;
            _currentFunctionIsAsync = false;
            // NL319 context resets at the nested-body boundary: a return here exits the lambda,
            // not any finally the lambda happens to sit inside — that is legal. Branch targets
            // reset too; break/continue cannot target loops in the enclosing method.
            _inLoop = false;
            _finallyDepth = 0;
            _breakTargetFinallyDepth = 0;
            _continueTargetFinallyDepth = 0;
            try
            {
                AnalyzeStatement(lambda.BlockBody);
            }
            finally
            {
                _currentReturnType = previousReturnType;
                _currentFunction = previousFunction;
                _currentFunctionReturnTypeWasOmitted = previousFunctionReturnTypeWasOmitted;
                _currentFunctionIsAsync = previousFunctionIsAsync;
                _inLoop = previousInLoop;
                _finallyDepth = previousFinallyDepth;
                _breakTargetFinallyDepth = previousBreakTargetFinallyDepth;
                _continueTargetFinallyDepth = previousContinueTargetFinallyDepth;
            }
            returnType = expectedSignature?.ReturnType ?? BuiltInTypes.Unknown;
        }
        else
        {
            returnType = BuiltInTypes.Unknown;
        }

        PopScope();

        return new FunctionTypeInfo()
        {
            ParameterTypes = parameterTypes,
            ReturnType = returnType
        };
    }

    private void ReportExpressionTreeBlockLambdaIfNeeded(LambdaExpression lambda)
    {
        const string message = "Expression-tree lambdas must use an expression body; block bodies are not supported";
        if (_errors.Any(error =>
                error.Code == ErrorCode.FeatureNotImplemented
                && error.Line == lambda.Line
                && error.Column == lambda.Column
                && error.Message == message))
        {
            return;
        }

        Error(
            ErrorCode.FeatureNotImplemented,
            message,
            lambda.Line,
            lambda.Column,
            "Use 'x => expression' for expression-tree targets, or assign the block lambda to a delegate type such as Func or Action.",
            _spans.GetTokenLength(lambda.Line, lambda.Column));
    }

    private bool ReportUnsupportedExpressionTreeExpressionIfNeeded(Expression expression, ISet<string> parameterNames)
    {
        if (FindUnsupportedExpressionTreeExpression(expression, parameterNames) is not { } unsupported)
        {
            return false;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(unsupported.Expression);
        var message = $"Expression-tree lambda body contains unsupported {unsupported.Description}";
        if (_errors.Any(error =>
                error.Code == ErrorCode.FeatureNotImplemented
                && error.Line == line
                && error.Column == column
                && error.Message == message))
        {
            return false;
        }

        Error(
            ErrorCode.FeatureNotImplemented,
            message,
            line,
            column,
            "Use a lambda parameter, member access, literal, conditional expression, supported binary expression, supported unary expression, positional instance/static call, or anonymous-object projection.",
            length);
        return true;
    }

    private (Expression Expression, string Description)? FindUnsupportedExpressionTreeExpression(
        Expression expression,
        ISet<string> parameterNames)
    {
        switch (expression)
        {
            case IdentifierExpression identifier:
                return parameterNames.Contains(identifier.Name)
                    ? null
                    : (identifier, $"captured or static identifier '{identifier.Name}'");

            case MemberAccessExpression { IsNullConditional: true } memberAccess:
                return (memberAccess, "null-conditional member access");

            case MemberAccessExpression memberAccess:
                return FindUnsupportedExpressionTreeExpression(memberAccess.Object, parameterNames);

            case IndexAccessExpression { IsNullConditional: true } indexAccess:
                return (indexAccess, "null-conditional index access");

            case IndexAccessExpression indexAccess:
                return FindUnsupportedExpressionTreeExpression(indexAccess.Object, parameterNames)
                    ?? FindUnsupportedExpressionTreeExpression(indexAccess.Index, parameterNames);

            case ParenthesizedExpression parenthesized:
                return FindUnsupportedExpressionTreeExpression(parenthesized.Inner, parameterNames);

            case IntLiteralExpression
                or FloatLiteralExpression
                or CharLiteralExpression
                or StringLiteralExpression
                or BoolLiteralExpression
                or NullLiteralExpression
                or DefaultExpression
                or NameofExpression
                or TypeOfExpression:
                return null;

            case BinaryExpression binary:
                if (!OperatorFacts.IsSupportedExpressionTreeBinaryOperator(binary.Operator))
                {
                    return (binary, $"binary operator '{OperatorFacts.GetBinaryText(binary.Operator)}'");
                }

                return FindUnsupportedExpressionTreeExpression(binary.Left, parameterNames)
                    ?? FindUnsupportedExpressionTreeExpression(binary.Right, parameterNames);

            case UnaryExpression unary:
                if (!OperatorFacts.IsSupportedExpressionTreeUnaryOperator(unary.Operator))
                {
                    return (unary, $"unary operator '{OperatorFacts.GetUnaryText(unary.Operator)}'");
                }

                return FindUnsupportedExpressionTreeExpression(unary.Operand, parameterNames);

            case TernaryExpression ternary:
                return FindUnsupportedExpressionTreeExpression(ternary.Condition, parameterNames)
                    ?? FindUnsupportedExpressionTreeExpression(ternary.ThenExpression, parameterNames)
                    ?? FindUnsupportedExpressionTreeExpression(ternary.ElseExpression, parameterNames);

            case CastExpression cast:
                if (cast.Kind is not (CastKind.Hard or CastKind.Safe))
                {
                    return (cast, "cast expression");
                }

                return FindUnsupportedExpressionTreeExpression(cast.Expression, parameterNames);

            case CallExpression call:
                if (call.Callee is not MemberAccessExpression memberCall)
                {
                    return (call, "non-instance method call");
                }

                if (memberCall.IsNullConditional)
                {
                    return (memberCall, "null-conditional method call");
                }

                if (call.TypeArguments is { Count: > 0 })
                {
                    return (call, "generic method call");
                }

                if (call.Arguments.Any(argument => argument.Modifier != ArgumentModifier.None))
                {
                    return (call, "ref/out method argument");
                }

                if (call.Arguments.Any(argument => argument.Name != null))
                {
                    return (call, "named method argument");
                }

                foreach (var argument in call.Arguments)
                {
                    var unsupported = FindUnsupportedExpressionTreeExpression(argument.Value, parameterNames);
                    if (unsupported != null)
                    {
                        return unsupported;
                    }
                }

                return IsExpressionTreeStaticCallReceiver(memberCall.Object, parameterNames)
                    ? null
                    : FindUnsupportedExpressionTreeExpression(memberCall.Object, parameterNames);

            case NewExpression newExpression:
                if (!IsExpressionTreeAnonymousObjectCreation(newExpression))
                {
                    return (newExpression, "object construction");
                }

                foreach (var property in newExpression.Initializer!.Properties)
                {
                    var unsupported = FindUnsupportedExpressionTreeExpression(property.Value, parameterNames);
                    if (unsupported != null)
                    {
                        return unsupported;
                    }
                }

                return null;

            default:
                return (expression, GetExpressionTreeExpressionDescription(expression));
        }
    }

    private bool IsExpressionTreeStaticCallReceiver(Expression expression, ISet<string> parameterNames)
    {
        if (ExpressionTreeReceiverStartsWithValueIdentifier(expression, parameterNames))
        {
            return false;
        }

        if (!TryGetQualifiedExpressionTreeName(expression, out var name))
        {
            return false;
        }

        if (AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(_wellKnownTypes, name) != null)
        {
            return true;
        }

        var resolvedType = _declarationContext.ResolveDeclaredAlias(_scopes.LookupType(name) ?? BuiltInTypes.Unknown);
        if (!BuiltInTypes.IsUnknown(resolvedType))
        {
            return true;
        }

        return _externalTypeProbe.ResolveExternalType(name) is ReflectionTypeInfo;
    }

    private bool ExpressionTreeReceiverStartsWithValueIdentifier(Expression expression, ISet<string> parameterNames)
    {
        return expression switch
        {
            IdentifierExpression identifier => parameterNames.Contains(identifier.Name)
                || _scopes.LookupSymbol(identifier.Name) != null,
            MemberAccessExpression { IsNullConditional: false } memberAccess =>
                ExpressionTreeReceiverStartsWithValueIdentifier(memberAccess.Object, parameterNames),
            _ => false
        };
    }

    private static bool TryGetQualifiedExpressionTreeName(Expression expression, out string name)
    {
        switch (expression)
        {
            case IdentifierExpression identifier:
                name = identifier.Name;
                return true;
            case MemberAccessExpression { IsNullConditional: false } memberAccess
                when TryGetQualifiedExpressionTreeName(memberAccess.Object, out var parentName):
                name = $"{parentName}.{memberAccess.MemberName}";
                return true;
            default:
                name = string.Empty;
                return false;
        }
    }

    private static bool IsExpressionTreeAnonymousObjectCreation(NewExpression newExpression)
        => newExpression.Type == null
            && newExpression.ConstructorArguments.Count == 0
            && newExpression.Initializer != null
            && newExpression.Initializer.Properties.All(property =>
                property.Name != null
                && property.IndexExpression == null);

    private static string GetExpressionTreeExpressionDescription(Expression expression)
        => expression switch
        {
            AssignmentExpression => "assignment expression",
            AwaitExpression => "await expression",
            CastExpression => "cast expression",
            CheckedExpression => "checked expression",
            DefaultExpression => "default expression",
            InterpolatedStringExpression => "interpolated string",
            LambdaExpression => "nested lambda",
            MatchExpression => "match expression",
            MustExpression => "must expression",
            NameofExpression => "nameof expression",
            RangeExpression => "range expression",
            SizeOfExpression => "sizeof expression",
            SpreadExpression => "spread expression",
            ThrowExpression => "throw expression",
            TupleExpression => "tuple expression",
            TypeOfExpression => "typeof expression",
            UncheckedExpression => "unchecked expression",
            WithExpression => "with expression",
            _ => expression.GetType().Name
        };

    private FunctionTypeInfo? GetFunctionSignature(TypeInfo? expectedType)
    {
        if (expectedType == null)
            return null;

        var resolvedExpectedType = _declarationContext.ResolveDeclaredAlias(expectedType);

        if (resolvedExpectedType is FunctionTypeInfo functionType)
            return functionType;

        if (resolvedExpectedType is ReflectionTypeInfo reflectionType
            && (_assignabilityFacts.IsDelegateType(reflectionType.Type) || AnalyzerFunctionTypeFactory.IsExpressionTreeLambdaTarget(reflectionType.Type)))
        {
            return AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(reflectionType.Type);
        }

        // Handle generic delegate types (Func<int, int>, Action<string>) from N# declarations
        if (resolvedExpectedType is GenericTypeInfo)
        {
            var clrType = _clrTypeConversion.TryConvertTypeInfoToClrType(resolvedExpectedType);
            if (clrType != null && (_assignabilityFacts.IsDelegateType(clrType) || AnalyzerFunctionTypeFactory.IsExpressionTreeLambdaTarget(clrType)))
                return AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(clrType);
        }

        return null;
    }

    private TypeInfo AnalyzeTernary(TernaryExpression ternary)
    {
        var expectedResultType = _currentExpectedType;
        var condType = AnalyzeExpressionWithExpectedType(ternary.Condition, BuiltInTypes.Bool);
        var isSoaRowCondition = ReportSoaRowEscapeIfNeeded(ternary.Condition, condType, "used as a ternary condition");
        var isSoaDirectColumnCondition = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(ternary.Condition, "used as a ternary condition");
        if (!isSoaRowCondition && !isSoaDirectColumnCondition && !IsBoolType(condType))
        {
            ReportBooleanConditionTypeMismatch(ternary.Condition, "a ternary expression", condType);
        }

        var thenType = AnalyzeExpressionWithExpectedType(ternary.ThenExpression, expectedResultType);
        var elseType = AnalyzeExpressionWithExpectedType(ternary.ElseExpression, expectedResultType);
        if (ReportSoaRowEscapeIfNeeded(ternary.ThenExpression, thenType, "used as a ternary result")
            | ReportSoaRowEscapeIfNeeded(ternary.ElseExpression, elseType, "used as a ternary result")
            | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(ternary.ThenExpression, "used as a ternary result")
            | ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(ternary.ElseExpression, "used as a ternary result"))
        {
            return BuiltInTypes.Unknown;
        }

        // Return common type
        return GetCommonType(thenType, elseType);
    }

    private TypeInfo AnalyzeTupleExpression(TupleExpression tuple)
    {
        var elements = new List<TupleTypeElementInfo>(tuple.Elements.Count);

        for (var i = 0; i < tuple.Elements.Count; i++)
        {
            var element = tuple.Elements[i];
            var expectedElementType = GetExpectedTupleElementType(tuple, i);
            var previousExpectedType = _currentExpectedType;
            if (expectedElementType != null)
            {
                _currentExpectedType = expectedElementType;
            }

            var elementType = AnalyzeExpression(element.Value);
            _currentExpectedType = previousExpectedType;
            ReportSoaRowEscapeIfNeeded(element.Value, elementType, "stored in a tuple");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(element.Value, "stored in a tuple");
            elements.Add(new TupleTypeElementInfo(element.Name, elementType));
        }

        return new TupleTypeInfo(elements);
    }

    private TypeInfo? GetExpectedTupleElementType(TupleExpression tuple, int elementIndex)
    {
        if (_currentExpectedType == null)
        {
            return null;
        }

        if (_declarationContext.ResolveDeclaredAlias(_currentExpectedType) is not TupleTypeInfo expectedTuple
            || elementIndex >= expectedTuple.Elements.Count)
        {
            return null;
        }

        var element = tuple.Elements[elementIndex];
        if (element.Name != null)
        {
            foreach (var expectedElement in expectedTuple.Elements)
            {
                if (expectedElement.Name == element.Name)
                {
                    return expectedElement.Type;
                }
            }
        }

        return expectedTuple.Elements[elementIndex].Type;
    }

    private (TypeInfo ElementType, string TargetKind)? GetExpectedElementType(TypeInfo? expectedType)
    {
        if (expectedType == null)
        {
            return null;
        }

        var resolvedExpectedType = _declarationContext.ResolveDeclaredAlias(expectedType);
        if (_assignabilityFacts.TryGetCollectionElementType(resolvedExpectedType, out var collectionElementType))
        {
            return (collectionElementType, "collection");
        }

        return resolvedExpectedType switch
        {
            ArrayTypeInfo arrayType => (arrayType.ElementType, "array"),
            ReflectionTypeInfo reflectionType when reflectionType.Type.IsArray && reflectionType.Type.GetElementType() != null
                => (AnalyzerReflectionTypeConversion.ConvertReflectionType(reflectionType.Type.GetElementType()!), "array"),
            _ => null
        };
    }

    private TypeInfo AnalyzeArrayLiteral(ArrayLiteralExpression array)
    {
        var expectedElement = GetExpectedElementType(_currentExpectedType);
        var expectedElementType = expectedElement?.ElementType;
        ReportUnsupportedCollectionExpressionTargetIfNeeded(array, _currentExpectedType);
        if (array.Elements.Count == 0)
        {
            return new ArrayTypeInfo(expectedElementType ?? BuiltInTypes.Unknown);
        }

        if (expectedElementType != null)
        {
            var targetKind = expectedElement?.TargetKind ?? "array";
            var elementLabel = targetKind == "collection" ? "Collection element" : "Array element";
            var storageContext = targetKind == "collection" ? "stored in a collection literal" : "stored in an array";

            foreach (var elem in array.Elements)
            {
                var previousExpectedType = _currentExpectedType;
                _currentExpectedType = expectedElementType;
                var elemType = AnalyzeExpression(elem);
                _currentExpectedType = previousExpectedType;

                ReportSoaRowEscapeIfNeeded(elem, elemType, storageContext);
                ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(elem, storageContext);
                if (!_assignability.IsAssignable(expectedElementType, elemType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(elem);
                    Error(ErrorCode.TypeMismatch,
                        $"{elementLabel} is '{elemType}', but the target {targetKind} expects '{expectedElementType}'",
                        diagnosticLine,
                        diagnosticColumn,
                        length: diagnosticLength);
                }
            }

            return new ArrayTypeInfo(expectedElementType);
        }

        var firstType = AnalyzeExpression(array.Elements[0]);
        ReportSoaRowEscapeIfNeeded(array.Elements[0], firstType, "stored in an array");
        ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(array.Elements[0], "stored in an array");
        foreach (var elem in array.Elements.Skip(1))
        {
            var elemType = AnalyzeExpression(elem);
            ReportSoaRowEscapeIfNeeded(elem, elemType, "stored in an array");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(elem, "stored in an array");
            if (!_assignability.IsAssignable(firstType, elemType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(elem);
                Error(ErrorCode.TypeMismatch,
                    $"All elements in an array must be the same type — the first element is '{firstType}' but I found '{elemType}'",
                    diagnosticLine, diagnosticColumn, length: diagnosticLength);
            }
        }

        return new ArrayTypeInfo(firstType);
    }

    private void ReportUnsupportedCollectionExpressionTargetIfNeeded(ArrayLiteralExpression array, TypeInfo? expectedType)
    {
        if (expectedType == null)
        {
            return;
        }

        var resolvedExpectedType = _declarationContext.ResolveDeclaredAlias(expectedType);
        if (!IsUnsupportedCollectionExpressionTarget(resolvedExpectedType, out var targetName))
        {
            return;
        }

        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(array);
        Error(
            ErrorCode.FeatureNotImplemented,
            $"Collection expressions for '{targetName}' are not implemented yet",
            line,
            column,
            "Use an array, List<T>, HashSet<T>, Queue<T>, or construct the queryable value explicitly.",
            length);
    }

    private static bool IsUnsupportedCollectionExpressionTarget(TypeInfo type, out string targetName)
    {
        targetName = type.ToString();
        return type switch
        {
            GenericTypeInfo { Name: "IQueryable" } => true,
            ReflectionTypeInfo reflectionType when IsIQueryableType(reflectionType.Type) => true,
            ReflectionTypeInfo reflectionType
                when IsReflectionCollectionExpressionTarget(reflectionType.Type)
                     && !CanMaterializeReflectionCollectionExpressionTarget(reflectionType.Type) => true,
            _ => false
        };
    }

    private static bool IsIQueryableType(Type type)
        => IsGenericDefinition(type, typeof(IQueryable<>));

    private static bool IsReflectionCollectionExpressionTarget(Type type)
        => TryGetReflectionCollectionExpressionElementType(type, out _);

    private static bool CanMaterializeReflectionCollectionExpressionTarget(Type targetType)
    {
        if (targetType == typeof(object))
        {
            return false;
        }

        if (targetType.IsArray)
        {
            return true;
        }

        if (!TryGetReflectionCollectionExpressionElementType(targetType, out var elementType))
        {
            return false;
        }

        if (!targetType.IsInterface && !targetType.IsAbstract)
        {
            return HasSingleEnumerableConstructor(targetType, elementType)
                || (HasParameterlessConstructor(targetType) && HasCollectionExpressionMutator(targetType, elementType));
        }

        return IsSupportedCollectionExpressionInterfaceTarget(targetType)
            || IsAssignableFromConstructed(targetType, typeof(List<>), elementType)
            || IsAssignableFromConstructed(targetType, typeof(HashSet<>), elementType)
            || IsAssignableFromConstructed(targetType, typeof(Queue<>), elementType);
    }

    private static bool TryGetReflectionCollectionExpressionElementType(Type type, out Type elementType)
    {
        elementType = typeof(object);
        if (type.IsArray)
        {
            elementType = type.GetElementType() ?? typeof(object);
            return true;
        }

        foreach (var candidate in EnumerateReflectionCollectionExpressionSequenceTypes(type))
        {
            if (!candidate.IsGenericType)
            {
                continue;
            }

            if (IsGenericDefinition(candidate, typeof(IEnumerable<>))
                || IsGenericDefinition(candidate, typeof(ICollection<>))
                || IsGenericDefinition(candidate, typeof(IList<>))
                || IsGenericDefinition(candidate, typeof(IReadOnlyCollection<>))
                || IsGenericDefinition(candidate, typeof(IReadOnlyList<>))
                || IsGenericDefinition(candidate, typeof(IEnumerator<>))
                || IsGenericDefinition(candidate, typeof(IAsyncEnumerable<>))
                || IsGenericDefinition(candidate, typeof(IAsyncEnumerator<>)))
            {
                elementType = candidate.GetGenericArguments()[0];
                return true;
            }
        }

        return false;
    }

    private static IEnumerable<Type> EnumerateReflectionCollectionExpressionSequenceTypes(Type type)
    {
        yield return type;

        Type[] interfaces;
            interfaces = type.GetInterfaces();

        foreach (var interfaceType in interfaces)
        {
            yield return interfaceType;
        }
    }

    private static bool HasParameterlessConstructor(Type targetType)
        => HasPublicInstanceConstructor(targetType, constructor => constructor.GetParameters().Length == 0);

    private static bool HasSingleEnumerableConstructor(Type targetType, Type elementType)
        => HasPublicInstanceConstructor(targetType, method => HasSingleEnumerableParameter(method, elementType));

    private static bool HasPublicInstanceConstructor(Type targetType, Func<ConstructorInfo, bool> predicate)
    {
            return targetType
                .GetConstructors(BindingFlags.Public | BindingFlags.Instance)
                .Any(predicate);
    }

    private static bool HasSingleEnumerableParameter(MethodBase method, Type elementType)
    {
            var parameters = method.GetParameters();
            if (parameters.Length != 1)
            {
                return false;
            }

            var parameterType = parameters[0].ParameterType;
            return IsGenericDefinition(parameterType, typeof(IEnumerable<>))
                && AnalyzerConversionFacts.IsReflectionAssignableFrom(parameterType, typeof(IEnumerable<>).MakeGenericType(elementType));
    }

    private static bool HasCollectionExpressionMutator(Type targetType, Type elementType)
    {
            return targetType
                .GetMethods(BindingFlags.Public | BindingFlags.Instance)
                .Any(method => method.Name is "Add" or "Enqueue"
                    && HasSingleCollectionElementParameter(method, elementType));
    }

    private static bool HasSingleCollectionElementParameter(MethodBase method, Type elementType)
    {
            var parameters = method.GetParameters();
            if (parameters.Length != 1)
            {
                return false;
            }

            var parameterType = parameters[0].ParameterType;
            if (elementType.IsValueType)
            {
                return TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(parameterType, elementType);
            }

            return AnalyzerConversionFacts.IsReflectionAssignableFrom(parameterType, elementType);
    }

    private static bool IsSupportedCollectionExpressionInterfaceTarget(Type targetType)
    {
        if (!targetType.IsInterface)
        {
            return false;
        }

        var definitionName = GetGenericDefinitionFullName(targetType);
        return definitionName is
            "System.Collections.Generic.IEnumerable`1" or
            "System.Collections.Generic.ICollection`1" or
            "System.Collections.Generic.IList`1" or
            "System.Collections.Generic.IReadOnlyCollection`1" or
            "System.Collections.Generic.IReadOnlyList`1" or
            "System.Collections.Generic.ISet`1" or
            "System.Collections.Generic.IReadOnlySet`1";
    }

    private static bool IsGenericDefinition(Type type, Type openGenericType)
        => string.Equals(
            GetGenericDefinitionFullName(type),
            openGenericType.FullName,
            StringComparison.Ordinal);

    private static string? GetGenericDefinitionFullName(Type type)
    {
        if (!type.IsGenericType)
        {
            return null;
        }

            return type.GetGenericTypeDefinition().FullName;
    }

    private static bool IsAssignableFromConstructed(Type targetType, Type openGenericType, Type elementType)
    {
            return targetType.IsAssignableFrom(openGenericType.MakeGenericType(elementType));
    }

    private TypeInfo AnalyzeNewExpression(NewExpression newExpr)
    {
        TypeInfo type;

        // Set when this is a union case construction (new Result.Success<int> { ... }) —
        // initializer members then live on the case, not the union type itself.
        string? unionCaseConstructionName = null;

        // Target-typed new (): new() or new { ... }
        if (newExpr.Type == null)
        {
            // Try to infer type from context (expected type)
            // For now, we'll use _currentExpectedType if available, otherwise Unknown
            if (_currentExpectedType == null && !IsAnonymousObjectCreation(newExpr))
            {
                ReportCannotInferTargetTypedNew(newExpr);
            }

            type = _currentExpectedType ?? BuiltInTypes.Unknown;

            // Anonymous object creation is intentionally allowed without an expected type; the
            // backend synthesizes the concrete anonymous shape from the initializer.
        }
        else
        {
            type = _typeResolver.ResolveDeclaredType(newExpr.Type);

            // A locally-declared GENERIC type constructed without type arguments previously
            // emitted an open-type token (BadImageFormatException at runtime). N# does not
            // infer class type arguments from constructor arguments (the  rule) — they
            // must be explicit.
            if (newExpr.Type is SimpleTypeReference bareTypeReference
                && !bareTypeReference.Name.Contains('.')
                && AnalyzerTypeReferenceFacts.GenericHeadArity(type) > 0)
            {
                var requiredCount = AnalyzerTypeReferenceFacts.GenericHeadArity(type);
                Error(
                    ErrorCode.InvalidTypeArgument,
                    $"Generic type '{bareTypeReference.Name}' requires {requiredCount} type argument(s)",
                    bareTypeReference.Line,
                    bareTypeReference.Column,
                    $"Specify them explicitly: 'new {bareTypeReference.Name}<...>(...)'",
                    bareTypeReference.Name.Length);
            }

            // Special case: if the type is a qualified name like "Result.Success",
            // it might be a union case. Check if the base type is a union. A generic
            // union takes its type arguments after the case name
            // (new Result.Success<int> { ... }) or infers them from the expected type
            // (return new Option.None on a function returning Option<User>).
            var (qualifiedCaseName, unionCaseTypeArguments) = newExpr.Type switch
            {
                SimpleTypeReference simpleCaseRef when simpleCaseRef.Name.Contains('.')
                    => (simpleCaseRef.Name, (List<TypeReference>?)null),
                GenericTypeReference genericCaseRef when genericCaseRef.Name.Contains('.')
                    => (genericCaseRef.Name, genericCaseRef.TypeArguments),
                _ => (null, null)
            };
            if (qualifiedCaseName != null)
            {
                var parts = qualifiedCaseName.Split('.');
                // The union may live in another file/namespace with no import — project
                // auto-discovery resolves it exactly like a bare type reference would.
                var unionBaseLookup = parts.Length == 2 ? _scopes.LookupType(parts[0]) as UnionTypeInfo : null;
                if (unionBaseLookup == null && parts.Length == 2)
                {
                    if (_projectDiscovery.ResolveVisibleProjectType(
                            parts[0],
                            GetUnitNamespace(_compilationUnit),
                            newExpr.Line > 0,
                            out var projectUnionCandidate,
                            out _,
                            out var inaccessibleUnionFile))
                    {
                        if (projectUnionCandidate is UnionTypeInfo projectUnionType)
                        {
                            unionBaseLookup = projectUnionType;
                        }
                    }
                    else if (inaccessibleUnionFile != null)
                    {
                        _diagnostics.ReportInaccessibleMember(parts[0], inaccessibleUnionFile, newExpr.Line, newExpr.Column);
                        _typeResolver.MarkUnresolvedTypeReported(parts[0], newExpr.Line, newExpr.Column);
                    }
                }
                if (parts.Length == 2 && unionBaseLookup is UnionTypeInfo unionBaseType)
                {
                    if (TryGetUnionCaseForPattern(unionBaseType, qualifiedCaseName, out _))
                    {
                        // This is a union case instantiation - the variable should have the union type
                        type = ResolveUnionCaseConstructionType(newExpr, unionBaseType, parts[0], qualifiedCaseName, unionCaseTypeArguments);
                        unionCaseConstructionName = qualifiedCaseName;
                    }
                    else
                    {
                        // Constructing a case the union doesn't declare used to surface as
                        // an internal emit failure; report it like the pattern path does.
                        var caseNames = unionBaseType.Declaration.Cases.Select(unionCase => unionCase.Name).ToList();
                        var similarCases = caseNames.Count > 0
                            ? new SmartSuggester(caseNames).SuggestSimilarNames(parts[1])
                            : new List<string>();
                        var caseSpan = TypeReferenceFacts.GetStartSpan(newExpr.Type!);
                        Error(
                            ErrorCode.UndefinedMember,
                            $"'{parts[1]}' is not a case of union '{parts[0]}' — check the union definition for available cases",
                            caseSpan.StartLine,
                            caseSpan.StartColumn,
                            similarCases.Count > 0 ? $"Did you mean '{parts[0]}.{similarCases[0]}'?" : null,
                            qualifiedCaseName.Length);
                        type = unionBaseType;
                    }
                }
            }
        }

        var soaConstructionType = _declarationContext.ResolveDeclaredAlias(GetNonNullableType(type)) as SoaRecordTypeInfo;
        var constructorArgumentTypes = new List<TypeInfo>(newExpr.ConstructorArguments.Count);
        for (var i = 0; i < newExpr.ConstructorArguments.Count; i++)
        {
            var arg = newExpr.ConstructorArguments[i];
            var previousExpectedType = _currentExpectedType;
            if (soaConstructionType != null && newExpr.ConstructorArguments.Count == 1 && i == 0)
            {
                _currentExpectedType = BuiltInTypes.Int;
            }

            var argType = AnalyzeExpression(arg.Value);
            _currentExpectedType = previousExpectedType;
            constructorArgumentTypes.Add(argType);
            ReportSoaRowEscapeIfNeeded(arg.Value, argType, "passed as a constructor argument");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(arg.Value, "passed as a constructor argument");
        }

        if (soaConstructionType != null)
        {
            ValidateSoaRecordConstruction(newExpr, soaConstructionType, constructorArgumentTypes);
        }

        if (newExpr.ArrayLengthExpression != null)
        {
            if (newExpr.ConstructorArguments.Count != 0)
            {
                Error(
                    ErrorCode.InvalidSizedArrayConstructorArguments,
                    "Sized array allocation cannot also pass constructor arguments",
                    newExpr.Line,
                    newExpr.Column,
                    "Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.",
                    "new".Length);
            }

            var lengthType = AnalyzeExpression(newExpr.ArrayLengthExpression);
            if (ReportSoaRowEscapeIfNeeded(newExpr.ArrayLengthExpression, lengthType, "used as an array length")
                || ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(newExpr.ArrayLengthExpression, "used as an array length"))
            {
                // A SoA-specific diagnostic is more useful than the generic int-length mismatch.
            }
            else if (BuiltInTypes.IsNot(lengthType, BuiltInTypes.Int))
            {
                Error(ErrorCode.TypeMismatch,
                    $"Array length must be an int, not '{lengthType}'",
                    newExpr.ArrayLengthExpression.Line,
                    newExpr.ArrayLengthExpression.Column);
            }
        }

        // Analyze initializer
        if (newExpr.Initializer != null)
        {
            foreach (var prop in newExpr.Initializer.Properties)
            {
                // Analyze index expression if this is an indexer initializer
                if (prop.IndexExpression != null)
                {
                    var indexType = AnalyzeExpression(prop.IndexExpression);
                    ReportSoaRowEscapeIfNeeded(prop.IndexExpression, indexType, "used as an initializer index");
                    ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(prop.IndexExpression, "used as an initializer index");
                }

                AnalyzeObjectInitializerPropertyValue(type, unionCaseConstructionName, prop);
            }
        }

        return type;
    }

    private void ValidateSoaRecordConstruction(
        NewExpression newExpr,
        SoaRecordTypeInfo soaRecordType,
        IReadOnlyList<TypeInfo> constructorArgumentTypes)
    {
        var expectedShape = $"new {soaRecordType.Declaration.Name}(capacity)";
        if (newExpr.ConstructorArguments.Count != 1)
        {
            Error(
                ErrorCode.NoMatchingOverload,
                $"SoA table '{soaRecordType.Declaration.Name}' construction expects exactly one int capacity argument, but {newExpr.ConstructorArguments.Count} were provided",
                newExpr.Line,
                newExpr.Column,
                $"Use '{expectedShape}' with a non-negative int capacity.",
                "new".Length);
            return;
        }

        var capacityArgument = newExpr.ConstructorArguments[0];
        if (capacityArgument.Name is { } argumentName && argumentName != "capacity")
        {
            var (line, column, length) = _spans.GetExpressionDiagnosticSpan(capacityArgument.Value);
            Error(
                ErrorCode.NoMatchingOverload,
                $"SoA table '{soaRecordType.Declaration.Name}' construction has no parameter named '{argumentName}'",
                line,
                column,
                $"Use '{expectedShape}', or rename the argument to 'capacity'.",
                length);
            return;
        }

        var capacityType = _declarationContext.ResolveDeclaredAlias(constructorArgumentTypes[0]);
        if (capacityType is SoaRowTypeInfo || BuiltInTypes.IsUnknown(capacityType))
            return;

        if (!_assignability.IsAssignable(BuiltInTypes.Int, capacityType))
        {
            var (line, column, length) = _spans.GetExpressionDiagnosticSpan(capacityArgument.Value);
            Error(
                ErrorCode.TypeMismatch,
                $"SoA table capacity must be int, but this argument has type '{capacityType}'",
                line,
                column,
                $"Use '{expectedShape}' with an int capacity.",
                length);
            return;
        }

        if (_constantExpressionFacts.IsConstantNegative(capacityArgument.Value))
        {
            var (line, column, length) = _spans.GetExpressionDiagnosticSpan(capacityArgument.Value);
            Error(
                ErrorCode.TypeMismatch,
                "SoA table capacity must not be negative",
                line,
                column,
                "Use zero or a positive capacity; the table can grow later with add or ensureCapacity.",
                length);
        }
    }

    /// <summary>
    /// Analyzes one object-initializer entry's value, type-checking a named member
    /// assignment (new T { Member: value }) against the member's declared type. This is
    /// the assignment-compatibility gate for initializer writes — without it a mismatched
    /// closed-generic value (Items: List&lt;Rs&gt; into a List&lt;Pt&gt; field) passes
    /// analysis and the IL backend stores it unchecked, producing type-confused reads at
    /// runtime. Member types that cannot be resolved reliably skip the check rather than
    /// risk a false diagnostic; indexer entries and collection-initializer elements keep
    /// plain expression analysis (they bind to set_Item/Add, not to a declared member).
    /// </summary>
    private void AnalyzeObjectInitializerPropertyValue(
        TypeInfo constructedType,
        string? unionCaseName,
        PropertyInitializer prop)
    {
        if (prop.Name == null || prop.IndexExpression != null)
        {
            ReportUnsupportedSoaTableInitializerShapeIfNeeded(constructedType, prop, "object-initializer");
            var expectedElement = prop.Name == null && prop.IndexExpression == null
                ? GetExpectedElementType(constructedType)
                : null;
            var expectedElementType = expectedElement?.ElementType;
            var previousInitializerExpectedType = _currentExpectedType;
            if (expectedElementType != null)
            {
                _currentExpectedType = expectedElementType;
            }

            var initializerValueType = AnalyzeExpression(prop.Value);
            _currentExpectedType = previousInitializerExpectedType;
            ReportSoaRowEscapeIfNeeded(prop.Value, initializerValueType, "stored in an initializer");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(prop.Value, "stored in an initializer");
            if (expectedElementType != null && !_assignability.IsAssignable(expectedElementType, initializerValueType))
            {
                var targetKind = expectedElement?.TargetKind ?? "array";
                var elementLabel = targetKind == "collection" ? "Collection initializer element" : "Array initializer element";
                var (initializerDiagnosticLine, initializerDiagnosticColumn, initializerDiagnosticLength) =
                    _spans.GetExpressionDiagnosticSpan(prop.Value);
                Error(ErrorCode.TypeMismatch,
                    $"{elementLabel} is '{initializerValueType}', but the target {targetKind} expects '{expectedElementType}'",
                    initializerDiagnosticLine,
                    initializerDiagnosticColumn,
                    length: initializerDiagnosticLength);
            }

            return;
        }

        // Diagnostics point at the member name when the parser recorded it; ASTs built
        // without positions fall back to the value's span.
        var (nameLine, nameColumn) = prop.NameLine > 0
            ? (prop.NameLine, prop.NameColumn)
            : (prop.Value.Line, prop.Value.Column);

        if (ReportSoaTableNamedInitializerIfNeeded(constructedType, prop.Name, nameLine, nameColumn))
        {
            AnalyzeExpression(prop.Value);
            return;
        }

        CheckReadonlyObjectInitializerField(constructedType, prop.Name, nameLine, nameColumn);

        if (!TryResolveObjectInitializerMemberType(constructedType, unionCaseName, prop.Name, nameLine, nameColumn, out var memberType))
        {
            AnalyzeExpression(prop.Value);
            return;
        }

        // The member's declared type is the expected type for the value (target-typed
        // new, integer literal sizing, lambda inference, generic union case inference).
        var previousExpectedType = _currentExpectedType;
        _currentExpectedType = memberType;
        var valueType = AnalyzeExpression(prop.Value);
        _currentExpectedType = previousExpectedType;
        if (valueType is SoaRowTypeInfo)
        {
            ReportSoaRowEscape(prop.Value, "stored in an object initializer");
        }
        else
        {
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(prop.Value, "stored in an object initializer");
        }

        if (_assignability.IsAssignable(memberType, valueType))
        {
            return;
        }

        var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(prop.Value);
        var sourceSnippet = GetSourceSnippet(diagnosticLine);

        if (sourceSnippet != null && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.TypeMismatch(
                _currentFilePath,
                diagnosticLine,
                diagnosticColumn,
                sourceSnippet,
                diagnosticLength,
                valueType.ToString(),
                memberType.ToString()));
            return;
        }

        Error(
            ErrorCode.TypeMismatch,
            $"'{prop.Name}' is typed as '{memberType}', but the value is '{valueType}'",
            diagnosticLine,
            diagnosticColumn,
            length: diagnosticLength);
    }

    private void CheckReadonlyObjectInitializerField(
        TypeInfo constructedType,
        string memberName,
        int line,
        int column)
    {
        var owner = GetNonNullableType(constructedType);
        if (!TryFindReadonlyInstanceField(owner, memberName, out var readonlyFieldName))
        {
            return;
        }

        Error(
            ErrorCode.ReadonlyAssignment,
            $"Field '{readonlyFieldName}' is readonly — it can only be assigned in a constructor",
            line,
            column,
            "Move this assignment into a constructor, or remove `readonly` if the field needs to change later.",
            Math.Max(1, memberName.Length));
    }

    /// <summary>
    /// Resolves the declared type of a named member assigned in an object initializer.
    /// Returns false when the member's type cannot be determined reliably — unknown or
    /// non-member-bearing receivers, members inherited past an open generic declaration,
    /// method groups — so the caller skips the assignability check instead of guessing.
    /// When the member is conclusively absent from the constructed type (it used to
    /// surface as an internal emit failure), reports UndefinedMember with suggestions.
    /// </summary>
    private bool TryResolveObjectInitializerMemberType(
        TypeInfo constructedType,
        string? unionCaseName,
        string memberName,
        int nameLine,
        int nameColumn,
        out TypeInfo memberType)
    {
        memberType = BuiltInTypes.Unknown;

        // Union case construction (new Result.Success<int> { Value: ... }): members live
        // on the case, typed under the closed instantiation's substitution (Value: T on
        // Result<int> expects int). Checked before the generic branch — a generic union
        // construction is a GenericTypeInfo over the union's name.
        if (unionCaseName != null)
        {
            if (!TryResolveDeclaredUnionType(constructedType, out var unionType, out var unionSubstitution)
                || !TryGetUnionCaseForPattern(unionType, unionCaseName, out var unionCase))
            {
                return false;
            }

            var caseProperty = unionCase.Properties?.FirstOrDefault(property => property.Name == memberName);
            if (caseProperty == null)
            {
                var caseDisplayName = GetUnionCaseName(unionCaseName);
                var casePropertyNames = unionCase.Properties?.Select(property => property.Name).ToList() ?? new List<string>();
                var similarProperties = casePropertyNames.Count > 0
                    ? new SmartSuggester(casePropertyNames).SuggestSimilarNames(memberName)
                    : new List<string>();
                Error(
                    ErrorCode.UndefinedMember,
                    $"Union case '{caseDisplayName}' doesn't have a property named '{memberName}' — check the case definition for available properties",
                    nameLine,
                    nameColumn,
                    similarProperties.Count > 0 ? $"Did you mean '{similarProperties[0]}'?" : null,
                    Math.Max(1, memberName.Length));
                return false;
            }

            memberType = _typeSubstitution.ResolveTypeForSourceOwner(
                caseProperty.Type,
                unionType,
                unionSubstitution);
            return !BuiltInTypes.IsUnknown(memberType);
        }

        // Closed generic instantiation of a declared type (new Box<Pt> { Item: ... }):
        // resolve the member's declared type reference under the type-argument
        // substitution (Item: T on Box<Pt> expects Pt).
        if (constructedType is GenericTypeInfo generic)
        {
            if (_typeSubstitution.ResolveGenericDefinition(generic) is not { } openType
                || !TryGetDeclaredTypeShape(openType, out var typeParameters, out var members, out var primaryParameters))
            {
                return false;
            }

            Dictionary<string, TypeInfo>? substitution = null;
            if (typeParameters.Length > 0)
            {
                if (typeParameters.Length != generic.TypeArguments.Count)
                {
                    return false;
                }

                substitution = new Dictionary<string, TypeInfo>(StringComparer.Ordinal);
                for (var i = 0; i < typeParameters.Length; i++)
                {
                    substitution[typeParameters[i].Name] = generic.TypeArguments[i];
                }
            }

            var memberTypeReference = FindDeclaredMemberTypeReference(members, primaryParameters, memberName);
            if (memberTypeReference == null)
            {
                // Same-named functions, generated members, and inherited members resolve
                // on the open type — only a conclusively absent member reports (a base
                // class would need its own substitution chain, so it suppresses instead).
                var hasBaseClass = openType is ClassTypeInfo openClassType && openClassType.BaseClass != null;
                if (!hasBaseClass
                    && BuiltInTypes.IsUnknown(ResolveMember(openType, memberName, includeStaticMembers: false))
                    && ShouldReportUndefinedMember(openType, memberName, includeStaticMembers: false))
                {
                    ReportUndefinedMember(
                        openType,
                        memberName,
                        nameLine,
                        nameColumn,
                        includeStaticMembers: false,
                        typeNameOverride: NullabilityMetadataReflection.FormatTypeInfo(generic));
                }

                return false;
            }

            memberType = _typeSubstitution.ResolveTypeForSourceOwner(
                memberTypeReference,
                openType,
                substitution);
            return !BuiltInTypes.IsUnknown(memberType);
        }

        // Other receiver kinds (enums, tuples, newtypes, ...) have no assignable members;
        // ResolveMember's fallbacks for them don't model member-assignment semantics.
        if (constructedType is not (ClassTypeInfo or StructTypeInfo or RecordTypeInfo or ReflectionTypeInfo))
        {
            return false;
        }

        var resolved = ResolveMember(constructedType, memberName, includeStaticMembers: false);
        if (BuiltInTypes.IsUnknown(resolved))
        {
            if (ShouldReportUndefinedMember(constructedType, memberName, includeStaticMembers: false))
            {
                ReportUndefinedMember(constructedType, memberName, nameLine, nameColumn, includeStaticMembers: false);
            }

            return false;
        }

        if (resolved is NSharpMethodGroupInfo or ReflectionMethodGroupInfo or ReflectionMethodInfo or ReflectionEventInfo
            || resolved is FunctionTypeInfo functionType && AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(functionType))
        {
            return false;
        }

        memberType = resolved;
        return true;
    }

    private bool ReportUnsupportedSoaTableInitializerShapeIfNeeded(
        TypeInfo targetType,
        PropertyInitializer property,
        string initializerKind)
    {
        if (_declarationContext.ResolveDeclaredAlias(GetNonNullableType(targetType)) is not SoaRecordTypeInfo)
        {
            return false;
        }

        if (property.Name != null && property.IndexExpression == null)
        {
            return false;
        }

        var diagnosticTarget = property.IndexExpression ?? property.Value;
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(diagnosticTarget);
        var initializerShape = property.IndexExpression != null
            ? "indexer initializers"
            : "collection initializer entries";
        Error(
            ErrorCode.InvalidSyntax,
            $"SoA tables cannot use {initializerKind} {initializerShape}",
            line,
            column,
            "Construct the table with new Table(capacity) or Table.wrap(...), then write individual columns with table[index].column.",
            length);
        return true;
    }

    private bool ReportSoaTableNamedInitializerIfNeeded(
        TypeInfo constructedType,
        string memberName,
        int nameLine,
        int nameColumn)
    {
        if (_declarationContext.ResolveDeclaredAlias(GetNonNullableType(constructedType)) is not SoaRecordTypeInfo soaRecordType)
        {
            return false;
        }

        var isColumn = AnalyzerMemberResolution.TryGetSoaColumn(soaRecordType.Declaration, memberName) != null;
        var isBookkeepingField = memberName is "length" or "capacity";
        if (isColumn || isBookkeepingField)
        {
            ReportSoaTableMemberInitializer(memberName, nameLine, nameColumn, isColumn);
        }
        else if (ShouldReportUndefinedMember(soaRecordType, memberName, includeStaticMembers: false))
        {
            ReportUndefinedMember(soaRecordType, memberName, nameLine, nameColumn, includeStaticMembers: false);
        }

        return true;
    }

    private void ReportSoaTableMemberInitializer(string memberName, int line, int column, bool isColumn)
    {
        var suggestion = isColumn
            ? "Write individual rows with table[index].column, or construct/wrap the table with the desired column arrays."
            : "Use new Table(capacity), add, clear, ensureCapacity, or copyRow so length and capacity stay consistent with the columns.";
        Error(
            ErrorCode.InvalidSyntax,
            $"SoA table member '{memberName}' cannot be initialized directly",
            line,
            column,
            suggestion,
            Math.Max(1, memberName.Length));
    }

    /// <summary>
    /// Extracts the declaration shape (type parameters, declared member facts, primary
    /// constructor parameters) from a declared class/struct/record type info.
    /// </summary>
    private static bool TryGetDeclaredTypeShape(
        TypeInfo type,
        out TypeParameter[] typeParameters,
        out DeclaredMemberInfo[] members,
        out ParameterDeclarationInfo[] primaryConstructorParameters)
    {
        switch (type)
        {
            case ClassTypeInfo classInfo:
                typeParameters = classInfo.TypeParameters;
                members = classInfo.DeclaredMembers;
                primaryConstructorParameters = classInfo.PrimaryConstructorParameters;
                return true;
            case StructTypeInfo structInfo:
                typeParameters = structInfo.TypeParameters;
                members = structInfo.DeclaredMembers;
                primaryConstructorParameters = structInfo.PrimaryConstructorParameters;
                return true;
            case RecordTypeInfo recordInfo:
                typeParameters = recordInfo.TypeParameters;
                members = recordInfo.DeclaredMembers;
                primaryConstructorParameters = recordInfo.PrimaryConstructorParameters;
                return true;
            default:
                typeParameters = Array.Empty<TypeParameter>();
                members = Array.Empty<DeclaredMemberInfo>();
                primaryConstructorParameters = Array.Empty<ParameterDeclarationInfo>();
                return false;
        }
    }

    /// <summary>
    /// Finds the declared type reference of a field, property, or primary-constructor
    /// parameter by name on a type declaration's own members (no base walk — base
    /// members of a generic declaration would need their own substitution chain).
    /// </summary>
    private static TypeReference? FindDeclaredMemberTypeReference(
        DeclaredMemberInfo[] members,
        ParameterDeclarationInfo[] primaryConstructorParameters,
        string memberName)
    {
        foreach (var member in members)
        {
            if (member.Name == memberName
                && member.Kind is DeclaredMemberKind.Field or DeclaredMemberKind.Property)
            {
                return member.Type;
            }
        }

        return primaryConstructorParameters.FirstOrDefault(parameter => parameter.Name == memberName)?.Type;
    }

    /// <summary>
    /// Analyzes a stackalloc expression. The length subtree gets full semantic analysis (name
    /// resolution, type recording) like any other expression — the systems policy gate (NSYS080)
    /// layers on top of these semantic checks and can be downgraded to a warning inside
    /// [boundary]/audit code, so undefined names and non-int lengths must be rejected here
    /// before either backend can see them.
    /// </summary>
    private TypeInfo AnalyzeStackAllocExpression(StackAllocExpression stackAlloc)
    {
        var lengthType = AnalyzeExpression(stackAlloc.LengthExpression);
        if (ReportSoaRowEscapeIfNeeded(stackAlloc.LengthExpression, lengthType, "used as a stackalloc length")
            || ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(stackAlloc.LengthExpression, "used as a stackalloc length"))
        {
            // A SoA-specific diagnostic is more useful than the generic int-length mismatch.
        }
        else if (!BuiltInTypes.IsUnknown(lengthType) && !IsImplicitlyIntStackAllocLength(lengthType))
        {
            Error(ErrorCode.TypeMismatch,
                $"stackalloc length must be an int, but this is a '{lengthType}'",
                stackAlloc.LengthExpression.Line,
                stackAlloc.LengthExpression.Column,
                "Use an int-typed length, or cast explicitly with '(int)' if the value is known to fit.");
        }
        else if (_constantExpressionFacts.IsConstantNegative(stackAlloc.LengthExpression))
        {
            Error(ErrorCode.TypeMismatch,
                "stackalloc length must not be negative",
                stackAlloc.LengthExpression.Line,
                stackAlloc.LengthExpression.Column,
                "Use a length of zero or more.");
        }

        return new GenericTypeInfo(
            "Span",
            new List<TypeInfo> { _typeResolver.ResolveType(stackAlloc.ElementType) },
            new ReflectionTypeInfo(typeof(Span<>)));
    }

    /// <summary>
    /// A stackalloc length must implicitly widen to int (matching N#'s element-count rule):
    /// int itself plus the smaller integer types. long/uint/ulong, floating point, and
    /// non-numeric types require an explicit conversion.
    /// </summary>
    private bool IsImplicitlyIntStackAllocLength(TypeInfo type)
    {
        type = _declarationContext.ResolveDeclaredAlias(type);
        return BuiltInTypes.Is(type, BuiltInTypes.Int)
               || BuiltInTypes.Is(type, BuiltInTypes.Short)
               || BuiltInTypes.Is(type, BuiltInTypes.SByte)
               || BuiltInTypes.Is(type, BuiltInTypes.Byte)
               || BuiltInTypes.Is(type, BuiltInTypes.UShort)
               || BuiltInTypes.Is(type, BuiltInTypes.Char);
    }

    /// <summary>
    /// The static type of a union case construction (new Union.Case { ... }). For a
    /// non-generic union that is the union itself; for a generic union the type
    /// arguments come after the case name (new Result.Success&lt;int&gt; { ... }) or are
    /// inferred from the expected type, and the result is the closed instantiation
    /// (GenericTypeInfo) so it lines up with Result&lt;int&gt; annotations.
    /// </summary>
    private TypeInfo ResolveUnionCaseConstructionType(
        NewExpression newExpr,
        UnionTypeInfo unionType,
        string unionName,
        string qualifiedCaseName,
        List<TypeReference>? typeArguments)
    {
        var typeParameters = unionType.Declaration.TypeParameters;
        var arity = typeParameters?.Count ?? 0;
        var typeRefSpan = TypeReferenceFacts.GetStartSpan(newExpr.Type!);

        if (typeArguments is { Count: > 0 })
        {
            var resolvedArguments = typeArguments.Select(_typeResolver.ResolveType).ToList();
            if (resolvedArguments.Count != arity)
            {
                var message = arity == 0
                    ? $"Union '{unionName}' is not generic, but {resolvedArguments.Count} type argument(s) were provided"
                    : $"Generic union '{unionName}' takes {arity} type argument(s), but {resolvedArguments.Count} were provided";
                Error(
                    ErrorCode.InvalidTypeArgument,
                    message,
                    typeRefSpan.StartLine,
                    typeRefSpan.StartColumn,
                    arity == 0
                        ? $"Remove the type arguments: 'new {qualifiedCaseName} {{ ... }}'"
                        : $"Match the declaration's type parameter count for '{unionName}'",
                    qualifiedCaseName.Length);
                return unionType;
            }

            return new GenericTypeInfo(unionName, resolvedArguments, unionType);
        }

        if (arity == 0)
        {
            return unionType;
        }

        // No explicit type arguments on a generic union case: adopt the expected
        // type's arguments when the context provides a closed instantiation.
        if (_currentExpectedType is GenericTypeInfo expected
            && expected.Name == unionName
            && expected.TypeArguments.Count == arity)
        {
            return expected;
        }

        Error(
            ErrorCode.InvalidTypeArgument,
            $"Generic union '{unionName}' requires {arity} type argument(s)",
            typeRefSpan.StartLine,
            typeRefSpan.StartColumn,
            $"Specify them after the case name: 'new {qualifiedCaseName}<...> {{ ... }}'",
            qualifiedCaseName.Length);
        return unionType;
    }

    /// <summary>
    /// Resolves the declared union behind a scrutinee or constructed value. Handles
    /// both the bare union type (UnionTypeInfo) and a closed generic instantiation
    /// (GenericTypeInfo whose name is a declared generic union, e.g. Result&lt;int&gt;),
    /// producing the type-parameter substitution map for case property types in the
    /// latter case.
    /// </summary>
    private bool TryResolveDeclaredUnionType(
        TypeInfo valueType,
        [NotNullWhen(true)] out UnionTypeInfo? unionType,
        out Dictionary<string, TypeInfo>? substitution)
    {
        substitution = null;

        if (valueType is UnionTypeInfo direct)
        {
            unionType = direct;
            return true;
        }

        if (valueType is GenericTypeInfo generic
            && _typeSubstitution.ResolveGenericDefinition(generic) is UnionTypeInfo declared
            && declared.Declaration.TypeParameters is { Count: > 0 } typeParameters
            && typeParameters.Count == generic.TypeArguments.Count)
        {
            substitution = new Dictionary<string, TypeInfo>(StringComparer.Ordinal);
            for (var i = 0; i < typeParameters.Count; i++)
            {
                substitution[typeParameters[i].Name] = generic.TypeArguments[i];
            }

            unionType = declared;
            return true;
        }

        unionType = null;
        return false;
    }

    /// <summary>
    /// Resolves a declared member type at a use site under a generic substitution map
    /// (value: T on Result&lt;int&gt; or Item: T on Box&lt;Pt&gt; resolve to the closed
    /// argument). Used for union case property bindings and object-initializer member
    /// type checks on closed generic instantiations.
    /// </summary>
    private TypeInfo AnalyzeIsExpression(IsExpression isExpr)
    {
        var sourceType = AnalyzeExpression(isExpr.Expression);
        var targetType = _typeResolver.ResolveType(isExpr.Type);
        if (ReportSoaRowEscapeIfNeeded(isExpr.Expression, sourceType, "tested with 'is'"))
        {
            return BuiltInTypes.Bool;
        }
        if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(isExpr.Expression, "tested with 'is'"))
        {
            return BuiltInTypes.Bool;
        }

        if (!IsPatternPossible(sourceType, targetType))
        {
            var (impossibleLine, impossibleColumn, impossibleLength) =
                _spans.GetIsExpressionDiagnosticSpan(isExpr);
            Error(ErrorCode.ImpossiblePattern,
                $"This 'is {targetType}' check is always false — a '{sourceType}' is never a '{targetType}'",
                impossibleLine, impossibleColumn, length: impossibleLength);
        }

        return BuiltInTypes.Bool;
    }

    private TypeInfo AnalyzeCastExpression(CastExpression cast)
    {
        var targetType = _typeResolver.ResolveType(cast.TargetType);
        var sourceType = ShouldUseCastTargetExpectedType(cast)
            ? AnalyzeExpressionWithExpectedType(cast.Expression, targetType)
            : AnalyzeExpression(cast.Expression);
        if (ReportSoaRowEscapeIfNeeded(cast.Expression, sourceType, "cast"))
        {
            return BuiltInTypes.Unknown;
        }
        if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(cast.Expression, "cast"))
        {
            return BuiltInTypes.Unknown;
        }

        return targetType;
    }

    private static bool ShouldUseCastTargetExpectedType(CastExpression cast)
        => cast.Kind == CastKind.Hard
            && (cast.Expression is DefaultExpression
                or NewExpression { Type: null });

    private TypeInfo AnalyzeAwaitExpression(AwaitExpression await)
    {
        var exprType = AnalyzeExpression(await.Expression);
        if (ReportSoaRowEscapeIfNeeded(await.Expression, exprType, "awaited"))
        {
            return BuiltInTypes.Unknown;
        }
        if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(await.Expression, "awaited"))
        {
            return BuiltInTypes.Unknown;
        }

        if (TryGetAwaitExpressionResultType(exprType, out var resultType))
        {
            return resultType;
        }

        if (ShouldReportAwaitExpressionTypeMismatch(exprType))
        {
            var (line, column, length) = _spans.GetExpressionDiagnosticSpan(await.Expression);
            Error(
                ErrorCode.TypeMismatch,
                $"await expression needs an awaitable value, but this expression is '{exprType}'",
                line,
                column,
                "Await a Task, ValueTask, or another value with a GetAwaiter() pattern.",
                length);
        }

        return BuiltInTypes.Unknown;
    }

    private bool TryGetAwaitExpressionResultType(TypeInfo awaitableType, out TypeInfo resultType)
    {
        resultType = BuiltInTypes.Unknown;

        var resolved = NormalizeShapeType(awaitableType);
        if (BuiltInTypes.IsUnknown(resolved) || resolved is ExternalTypeInfo)
        {
            return false;
        }

        if (AnalyzerFunctionTypeFactory.TryGetTaskLikeResultTypeInfo(resolved, out resultType))
        {
            return true;
        }

        if (AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(resolved))
        {
            resultType = BuiltInTypes.Void;
            return true;
        }

        if (resolved is ReflectionTypeInfo reflectionType
            && TryGetReflectionAwaitResultType(reflectionType.Type, out resultType))
        {
            return true;
        }

        return false;
    }

    private bool ShouldReportAwaitExpressionTypeMismatch(TypeInfo awaitableType)
    {
        var resolved = NormalizeShapeType(awaitableType);
        return !BuiltInTypes.IsUnknown(resolved)
            && resolved is not ClassTypeInfo
            && resolved is not StructTypeInfo
            && resolved is not RecordTypeInfo
            && resolved is not InterfaceTypeInfo;
    }

    private bool TryGetReflectionAwaitResultType(Type type, out TypeInfo resultType)
    {
        resultType = BuiltInTypes.Unknown;

            var runtimeType = Nullable.GetUnderlyingType(type) ?? type;
            var getAwaiterMethod = runtimeType.GetMethod(
                "GetAwaiter",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
                binder: null,
                types: Type.EmptyTypes,
                modifiers: null);
            if (getAwaiterMethod == null)
            {
                return false;
            }

            var awaiterType = getAwaiterMethod.ReturnType;
            var getResultMethod = awaiterType.GetMethod(
                "GetResult",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
                binder: null,
                types: Type.EmptyTypes,
                modifiers: null);
            if (getResultMethod == null)
            {
                return false;
            }

            resultType = getResultMethod.ReturnType == typeof(void)
                ? BuiltInTypes.Void
                : AnalyzerReflectionTypeConversion.ConvertReflectionType(getResultMethod.ReturnType);
            return true;
    }

    private TypeInfo AnalyzeThrowExpression(ThrowExpression throwExpr)
    {
        var thrownType = AnalyzeExpression(throwExpr.Expression);
        ReportSoaRowEscapeIfNeeded(throwExpr.Expression, thrownType, "thrown");
        ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(throwExpr.Expression, "thrown");
        return BuiltInTypes.Never;
    }

    private TypeInfo AnalyzeTypeofExpression(TypeOfExpression typeofExpr)
    {
        // Validate the type exists
        _typeResolver.ResolveType(typeofExpr.Type);
        // typeof always returns System.Type
        return _wellKnownTypes != null
            ? new ReflectionTypeInfo(_wellKnownTypes.SystemType)
            : BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeNameofExpression(NameofExpression nameofExpr)
    {
        // Analyze the target expression to ensure it's valid, then keep the analyzer
        // contract aligned with the IL backend: nameof lowers to a string literal for
        // identifiers and member accesses only.
        var targetType = AnalyzeExpression(nameofExpr.Target);
        if (ReportSoaRowEscapeIfNeeded(nameofExpr.Target, targetType, "used as a nameof target"))
        {
            return BuiltInTypes.String;
        }

        if (nameofExpr.Target is not (IdentifierExpression or MemberAccessExpression))
        {
            var (line, column, length) = _spans.GetExpressionDiagnosticSpan(nameofExpr.Target);
            Error(
                ErrorCode.InvalidSyntax,
                "nameof can only name an identifier or member access",
                line,
                column,
                "Use nameof(value) or nameof(value.Member).",
                length);
        }

        // nameof always returns string
        return BuiltInTypes.String;
    }

    private TypeInfo AnalyzeSizeofExpression(SizeOfExpression sizeofExpr)
    {
        _typeResolver.ResolveType(sizeofExpr.Type);
        return BuiltInTypes.Int;
    }

    private TypeInfo AnalyzeCheckedExpression(CheckedExpression checkedExpr)
    {
        // Analyze the inner expression - type is preserved
        var innerType = AnalyzeExpressionWithExpectedType(checkedExpr.Expression, _currentExpectedType);
        if (ReportSoaRowEscapeIfNeeded(checkedExpr.Expression, innerType, "used in a checked expression"))
        {
            return BuiltInTypes.Unknown;
        }

        return innerType;
    }

    private TypeInfo AnalyzeUncheckedExpression(UncheckedExpression uncheckedExpr)
    {
        // Analyze the inner expression - type is preserved
        var innerType = AnalyzeExpressionWithExpectedType(uncheckedExpr.Expression, _currentExpectedType);
        if (ReportSoaRowEscapeIfNeeded(uncheckedExpr.Expression, innerType, "used in an unchecked expression"))
        {
            return BuiltInTypes.Unknown;
        }

        return innerType;
    }

    private TypeInfo AnalyzeWithExpression(WithExpression with)
    {
        var targetType = AnalyzeExpression(with.Target);
        var targetIsSoaRow = ReportSoaRowEscapeIfNeeded(with.Target, targetType, "used as a with target");
        var targetIsSoaDirectColumn = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(with.Target, "used as a with target");
        if (targetIsSoaRow || targetIsSoaDirectColumn)
        {
            targetType = BuiltInTypes.Unknown;
        }

        foreach (var property in with.Properties)
        {
            var unsupportedSoaTableInitializerShape =
                ReportUnsupportedSoaTableInitializerShapeIfNeeded(targetType, property, "`with`");
            if (property.IndexExpression != null)
            {
                var indexType = AnalyzeExpression(property.IndexExpression);
                ReportSoaRowEscapeIfNeeded(property.IndexExpression, indexType, "used as a with initializer index");
                ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(property.IndexExpression, "used as a with initializer index");
            }

            TypeInfo? memberType = null;
            if (!unsupportedSoaTableInitializerShape && property.Name != null && property.IndexExpression == null)
            {
                var (nameLine, nameColumn) = property.NameLine > 0
                    ? (property.NameLine, property.NameColumn)
                    : (property.Value.Line, property.Value.Column);

                if (!ReportSoaTableNamedInitializerIfNeeded(targetType, property.Name, nameLine, nameColumn)
                    && TryResolveObjectInitializerMemberType(targetType, unionCaseName: null, property.Name, nameLine, nameColumn, out var resolvedMemberType))
                {
                    memberType = resolvedMemberType;
                }
            }

            var valueType = memberType != null
                ? AnalyzeExpressionWithExpectedType(property.Value, memberType)
                : AnalyzeExpression(property.Value);
            var valueIsSoaRow = ReportSoaRowEscapeIfNeeded(property.Value, valueType, "stored in a with expression");
            var valueIsSoaDirectColumn = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(property.Value, "stored in a with expression");
            if (memberType != null && !valueIsSoaRow && !valueIsSoaDirectColumn && !_assignability.IsAssignable(memberType, valueType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(property.Value);
                Error(
                    ErrorCode.TypeMismatch,
                    $"'{property.Name}' is typed as '{memberType}', but the value is '{valueType}'",
                    diagnosticLine,
                    diagnosticColumn,
                    length: diagnosticLength);
            }
        }

        return targetIsSoaRow || targetIsSoaDirectColumn ? BuiltInTypes.Unknown : targetType;
    }

    private TypeInfo AnalyzeMatchExpression(MatchExpression match)
    {
        var expectedResultType = _currentExpectedType;

        // Analyze the value being matched
        var valueType = AnalyzeExpressionWithoutExpectedType(match.Value);
        if (ReportSoaRowEscapeIfNeeded(match.Value, valueType, "used as a match value"))
        {
            valueType = BuiltInTypes.Unknown;
        }
        else if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(match.Value, "used as a match value"))
        {
            valueType = BuiltInTypes.Unknown;
        }

        // Analyze each case and track variable bindings
        TypeInfo? resultType = null;
        foreach (var matchCase in match.Cases)
        {
            // Create new scope for pattern bindings
            PushScope(new Scope(ScopeKind.Block), matchCase.Pattern.Line, matchCase.Pattern.Column);

            // Analyze pattern and bind variables
            AnalyzePattern(matchCase.Pattern, valueType);

            // Analyze guard expression if present
            if (matchCase.Guard != null)
            {
                var guardType = AnalyzeExpressionWithExpectedType(matchCase.Guard, BuiltInTypes.Bool);
                var isSoaRowGuard = ReportSoaRowEscapeIfNeeded(matchCase.Guard, guardType, "used as a match guard");
                var isSoaDirectColumnGuard = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(matchCase.Guard, "used as a match guard");
                if (!isSoaRowGuard && !isSoaDirectColumnGuard && !_assignability.IsAssignable(BuiltInTypes.Bool, guardType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(matchCase.Guard);
                    Error(ErrorCode.GuardNotBoolean, $"A match guard must be a boolean, but this expression is '{guardType}'",
                        diagnosticLine, diagnosticColumn, length: diagnosticLength);
                }
            }

            // Analyze the case expression
            var caseType = AnalyzeExpressionWithExpectedType(matchCase.Expression, expectedResultType);
            if (ReportSoaRowEscapeIfNeeded(matchCase.Expression, caseType, "used as a match result"))
            {
                caseType = BuiltInTypes.Unknown;
            }
            else if (ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(matchCase.Expression, "used as a match result"))
            {
                caseType = BuiltInTypes.Unknown;
            }

            // Ensure all cases return compatible types
            if (resultType == null)
            {
                resultType = caseType;
            }
            else if (!_assignability.IsAssignable(resultType, caseType) && !_assignability.IsAssignable(caseType, resultType))
            {
                // Try to find a common base type (especially for reflection types like IActionResult subtypes)
                var commonType = FindCommonBaseType(resultType, caseType);
                if (commonType != null)
                {
                    resultType = commonType;
                }
                else
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = _spans.GetExpressionDiagnosticSpan(matchCase.Expression);
                    Error(ErrorCode.TypeMismatch,
                        $"All match arms must return the same type — the first arm returns '{resultType}', but this arm returns '{caseType}'",
                        diagnosticLine, diagnosticColumn, length: diagnosticLength);
                }
            }

            PopScope();
        }

        // Check exhaustiveness for union types and enum types
        // Guarded arms only partially cover their pattern, so unguarded arms (or a wildcard) are
        // still required for full coverage.
        if (valueType is AnonymousUnionTypeInfo anonymousUnionType)
        {
            CheckAnonymousUnionMatchExhaustiveness(match, anonymousUnionType);
        }
        else if (valueType is UnionTypeInfo unionType)
        {
            CheckMatchExhaustiveness(match, unionType);
        }
        else if (valueType is GenericTypeInfo
            && TryResolveDeclaredUnionType(valueType, out var genericUnionType, out var genericUnionSubstitution))
        {
            CheckMatchExhaustiveness(match, genericUnionType, genericUnionSubstitution);
        }
        else if (valueType is EnumTypeInfo enumType)
        {
            CheckEnumMatchExhaustiveness(match, enumType);
        }
        else if (valueType is NullableTypeInfo nullableType)
        {
            CheckNullableMatchExhaustiveness(match, nullableType);
        }
        else
        {
            // For non-union/non-enum types, mark exhaustive if there's a wildcard or catch-all
            foreach (var matchCase in match.Cases)
            {
                if (matchCase.Guard != null) continue;
                if (matchCase.Pattern is IdentifierPattern id &&
                    (id.Name == "_" || !id.Name.Contains('.')))
                {
                    match.IsExhaustive = true;
                    break;
                }
            }
        }

        return resultType ?? BuiltInTypes.Unknown;
    }

    private void CheckNullableMatchExhaustiveness(MatchExpression match, NullableTypeInfo nullableType)
    {
        var coversNull = false;
        var coversPresent = false;

        foreach (var matchCase in match.Cases)
        {
            if (matchCase.Guard != null)
            {
                continue;
            }

            switch (matchCase.Pattern)
            {
                case IdentifierPattern identifier when identifier.Name == "_":
                    match.IsExhaustive = true;
                    return;

                case LiteralPattern { Literal: NullLiteralExpression }:
                    coversNull = true;
                    break;

                case IdentifierPattern identifier when !identifier.Name.Contains('.'):
                    coversPresent = true;
                    break;

                case TypePattern:
                case ObjectPattern:
                case PositionalPattern:
                case ListPattern:
                    coversPresent = true;
                    break;
            }
        }

        if (coversNull && coversPresent)
        {
            match.IsExhaustive = true;
            return;
        }

        var missing = new List<string>();
        if (!coversNull)
        {
            missing.Add("null");
        }
        if (!coversPresent)
        {
            missing.Add($"present {nullableType.InnerType}");
        }

        var missingText = string.Join(" and ", missing);
        Error(
            ErrorCode.NonExhaustiveMatch,
            $"This nullable match doesn't cover {missingText} — handle both 'null' and a non-null value arm",
            match.Line,
            match.Column,
            "Use `null => ...` for the absent case and `value => ...` to bind the non-null value.",
            length: MatchKeywordLength);
    }

    private void CheckAnonymousUnionMatchExhaustiveness(MatchExpression match, AnonymousUnionTypeInfo unionType)
    {
        var covered = new bool[unionType.Arms.Count];

        foreach (var matchCase in match.Cases)
        {
            if (matchCase.Guard != null)
                continue;

            switch (matchCase.Pattern)
            {
                case IdentifierPattern identifier when identifier.Name == "_" || !identifier.Name.Contains('.'):
                    match.IsExhaustive = true;
                    return;

                case TypePattern typePattern:
                    var patternType = _typeResolver.ResolveType(typePattern.Type);
                    for (var i = 0; i < unionType.Arms.Count; i++)
                    {
                        if (_assignability.IsAssignable(patternType, unionType.Arms[i]))
                            covered[i] = true;
                    }
                    break;
            }
        }

        var missingArms = unionType.Arms
            .Where((_, index) => !covered[index])
            .Select(arm => arm.ToString())
            .ToList();

        if (missingArms.Count == 0)
        {
            match.IsExhaustive = true;
            return;
        }

        Error(
            ErrorCode.NonExhaustiveMatch,
            $"This match doesn't cover all anonymous union arms — missing: {string.Join(", ", missingArms)}",
            match.Line,
            match.Column,
            "Add an arm for each missing type, or add a wildcard `_` arm.",
            length: MatchKeywordLength);
    }

    private void CheckMatchExhaustiveness(
        MatchExpression match,
        UnionTypeInfo unionType,
        Dictionary<string, TypeInfo>? substitution = null)
    {
        var unionDeclaration = unionType.Declaration;
        var unionCases = unionDeclaration.Cases;
        var caseCount = unionCases.Count;
        var coveredFlags = ArrayPool<int>.Shared.Rent(caseCount);
        var partialFlags = ArrayPool<int>.Shared.Rent(caseCount);

        try
        {
            Array.Clear(coveredFlags, 0, caseCount);
            Array.Clear(partialFlags, 0, caseCount);

            // Collect all union case names that are covered by UNGUARDED arms.
            // Guarded arms only partially cover their pattern (the guard may be false at runtime),
            // so they don't count toward exhaustiveness.
            var caseIndexByName = new Dictionary<string, int>(caseCount, StringComparer.Ordinal);
            for (var caseIndex = 0; caseIndex < caseCount; caseIndex++)
            {
                caseIndexByName.TryAdd(unionCases[caseIndex].Name, caseIndex);
            }

            var unionCasePatterns = new Dictionary<string, List<UnionCasePattern>>();
            var partialCoverageHints = new Dictionary<string, List<string>>();

            foreach (var matchCase in match.Cases)
            {
                // Skip guarded arms — they only partially cover their pattern
                if (matchCase.Guard != null)
                    continue;

                if (matchCase.Pattern is UnionCasePattern unionPattern)
                {
                    if (TryGetUnionCaseForPattern(unionType, unionPattern.CaseName, out var matchedCase))
                    {
                        if (!unionCasePatterns.TryGetValue(matchedCase.Name, out var patterns))
                        {
                            patterns = new List<UnionCasePattern>();
                            unionCasePatterns[matchedCase.Name] = patterns;
                        }

                        patterns.Add(unionPattern);
                    }
                }
                else if (matchCase.Pattern is IdentifierPattern identPattern)
                {
                    if (identPattern.Name == "_")
                    {
                        // Unguarded wildcard pattern covers all remaining cases
                        match.IsExhaustive = true;
                        return;
                    }
                    else if (identPattern.Name.Contains('.'))
                    {
                        // Qualified union case name without properties
                        if (TryGetUnionCaseForPattern(unionType, identPattern.Name, out var matchedCase) &&
                            caseIndexByName.TryGetValue(matchedCase.Name, out var matchedCaseIndex))
                        {
                            coveredFlags[matchedCaseIndex] = 1;
                        }
                    }
                    else
                    {
                        // Unqualified, non-wildcard identifier is a catch-all binding (e.g., `other =>`)
                        // that matches everything at runtime — treat it the same as `_`
                        match.IsExhaustive = true;
                        return;
                    }
                }
            }

            // Check if all union cases are covered
            for (var caseIndex = 0; caseIndex < caseCount; caseIndex++)
            {
                var unionCase = unionCases[caseIndex];
                if (!unionCasePatterns.TryGetValue(unionCase.Name, out var patterns))
                    continue;

                if (IsUnionCaseCoveredByPatterns(
                        unionType,
                        unionDeclaration.Name,
                        unionCase,
                        patterns,
                        substitution,
                        out var hints))
                {
                    coveredFlags[caseIndex] = 1;
                }
                else
                {
                    partialFlags[caseIndex] = 1;
                    if (hints.Count > 0)
                    {
                        partialCoverageHints[unionCase.Name] = hints;
                    }
                }
            }

            AnalyzerExhaustivenessSelector.SelectMissingUnionCasesFromFlags(
                unionCases,
                coveredFlags,
                partialFlags,
                caseCount,
                out var missingCases,
                out var partialMissingCases,
                out var neverCoveredCases);

            if (missingCases.Any())
            {
                if (partialMissingCases.Any())
                {
                    var messageParts = new List<string>();
                    if (neverCoveredCases.Any())
                    {
                        messageParts.Add($"missing: {string.Join(", ", neverCoveredCases)}");
                    }

                    messageParts.Add($"partially covered: {FormatPartialCoverageCases(partialMissingCases, partialCoverageHints)}");

                    var partialHint = string.Join("; ", partialMissingCases.Select(caseName =>
                    {
                        if (partialCoverageHints.TryGetValue(caseName, out var hints) && hints.Count > 0)
                        {
                            return $"add '{hints[0]}', an unconstrained '{unionDeclaration.Name}.{caseName}' arm, or a wildcard '_' arm";
                        }

                        return $"add an unconstrained '{unionDeclaration.Name}.{caseName}' arm or a wildcard '_' arm";
                    }));
                    Error(ErrorCode.NonExhaustiveMatch,
                        $"This match doesn't cover all cases — {string.Join("; ", messageParts)}. {partialHint}.",
                        match.Line,
                        match.Column,
                        ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, string.Join(", ", missingCases)),
                        length: MatchKeywordLength);
                }
                else
                {
                    var sourceSnippet = GetSourceSnippet(match.Line);

                    if (sourceSnippet != null && _currentFilePath != null)
                    {
                        var error = ErrorMessageBuilder.NonExhaustiveMatch(
                            _currentFilePath,
                            match.Line,
                            match.Column,
                            sourceSnippet,
                            MatchKeywordLength,
                            missingCases
                        );
                        _errors.Add(error);
                    }
                    else
                    {
                        var missingCasesStr = string.Join(", ", missingCases);
                        Error(ErrorCode.NonExhaustiveMatch, $"This match doesn't cover all cases — missing: {missingCasesStr}",
                            match.Line, match.Column, ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, missingCasesStr),
                            length: MatchKeywordLength);
                    }
                }
            }
            else
            {
                // All union cases covered by unguarded arms.
                match.IsExhaustive = true;
            }
        }
        finally
        {
            ArrayPool<int>.Shared.Return(coveredFlags, clearArray: false);
            ArrayPool<int>.Shared.Return(partialFlags, clearArray: false);
        }
    }

    private static string FormatPartialCoverageCases(
        List<string> partialMissingCases,
        Dictionary<string, List<string>> partialCoverageHints)
    {
        return string.Join(", ", partialMissingCases.Select(caseName =>
        {
            if (partialCoverageHints.TryGetValue(caseName, out var hints) && hints.Count > 0)
            {
                return $"{caseName} (missing nested arm: {hints[0]})";
            }

            return caseName;
        }));
    }

    private bool IsUnionCaseCoveredByPatterns(
        UnionTypeInfo unionType,
        string unionName,
        UnionCase unionCase,
        List<UnionCasePattern> patterns,
        Dictionary<string, TypeInfo>? substitution,
        out List<string> partialCoverageHints)
    {
        partialCoverageHints = new List<string>();

        if (patterns.Any(IsTotalUnionCasePattern))
        {
            return true;
        }

        var nestedCoverage = new Dictionary<string, (string UnionName, HashSet<string> AllCases, HashSet<string> CoveredCases, HashSet<string> ConstrainedCases)>();
        foreach (var pattern in patterns)
        {
            if (pattern.Properties == null)
                continue;

            var constrainedProperties = pattern.Properties
                .Where(property => property.Pattern != null && !IsCatchAllPattern(property.Pattern))
                .ToList();
            if (constrainedProperties.Count != 1)
                continue;

            var constrainedProperty = constrainedProperties[0];
            if (!pattern.Properties.Where(p => !ReferenceEquals(p, constrainedProperty)).All(IsTotalPropertyPattern))
                continue;

            var caseProperty = unionCase.Properties?.FirstOrDefault(property => property.Name == constrainedProperty.Name);
            if (caseProperty == null)
                continue;

            // Apply the scrutinee's generic substitution so a `value: T` property on a
            // Result<Option<int>> scrutinee resolves to the nested union for coverage.
            var propertyType = _typeSubstitution.ResolveTypeForSourceOwner(
                caseProperty.Type,
                unionType,
                substitution);
            if (!TryResolveDeclaredUnionType(propertyType, out var nestedUnionType, out _))
                continue;

            var nestedCaseName = GetMatchedUnionCaseName(nestedUnionType, constrainedProperty.Pattern!);

            if (nestedCaseName == null)
                continue;

            if (!nestedCoverage.TryGetValue(constrainedProperty.Name, out var coverage))
            {
                coverage = (
                    nestedUnionType.Declaration.Name,
                    nestedUnionType.Declaration.Cases.Select(c => c.Name).ToHashSet(),
                    new HashSet<string>(),
                    new HashSet<string>());
                nestedCoverage[constrainedProperty.Name] = coverage;
            }

            coverage.CoveredCases.Add(nestedCaseName);
            if (!IsTotalNestedUnionPattern(constrainedProperty.Pattern!))
            {
                coverage.ConstrainedCases.Add(nestedCaseName);
            }
        }

        foreach (var (propertyName, coverage) in nestedCoverage)
        {
            if (coverage.AllCases.IsSubsetOf(coverage.CoveredCases) && coverage.ConstrainedCases.Count == 0)
            {
                return true;
            }

            foreach (var missingNestedCase in coverage.AllCases.Except(coverage.CoveredCases).Concat(coverage.ConstrainedCases).Distinct())
            {
                partialCoverageHints.Add(
                    $"{unionName}.{unionCase.Name} {{ {propertyName}: {coverage.UnionName}.{missingNestedCase} }}");
            }
        }

        return false;
    }

    private static string? GetMatchedUnionCaseName(UnionTypeInfo unionType, Pattern pattern)
    {
        return pattern switch
        {
            UnionCasePattern nestedUnionPattern when TryGetUnionCaseForPattern(unionType, nestedUnionPattern.CaseName, out var unionCase)
                => unionCase.Name,
            IdentifierPattern nestedIdentifierPattern when nestedIdentifierPattern.Name.Contains('.')
                && TryGetUnionCaseForPattern(unionType, nestedIdentifierPattern.Name, out var unionCase)
                => unionCase.Name,
            _ => null
        };
    }

    private static bool IsTotalNestedUnionPattern(Pattern pattern)
    {
        return pattern switch
        {
            UnionCasePattern nestedUnionPattern => IsTotalUnionCasePattern(nestedUnionPattern),
            IdentifierPattern nestedIdentifierPattern => nestedIdentifierPattern.Name.Contains('.'),
            _ => false
        };
    }

    private static bool TryGetUnionCaseForPattern(UnionTypeInfo unionType, string patternName, out UnionCase unionCase)
    {
        unionCase = null!;
        if (!IsUnionCaseQualifierCompatible(unionType, patternName))
            return false;

        var caseName = GetUnionCaseName(patternName);
        var matchedCase = unionType.Declaration.Cases.FirstOrDefault(c => c.Name == caseName);
        if (matchedCase == null)
            return false;

        unionCase = matchedCase;
        return true;
    }

    private static bool IsUnionCaseQualifierCompatible(UnionTypeInfo unionType, string patternName)
    {
        var lastDot = patternName.LastIndexOf('.');
        if (lastDot < 0)
            return true;

        var qualifier = patternName[..lastDot];
        var declaredName = unionType.Declaration.Name;
        var simpleName = declaredName.Contains('.')
            ? declaredName.Substring(declaredName.LastIndexOf('.') + 1)
            : declaredName;

        return qualifier == declaredName
            || qualifier == simpleName
            || declaredName.EndsWith($".{qualifier}", StringComparison.Ordinal);
    }

    private static string GetUnionCaseName(string patternName)
    {
        return patternName.Contains('.')
            ? patternName.Substring(patternName.LastIndexOf('.') + 1)
            : patternName;
    }

    private static bool IsTotalUnionCasePattern(UnionCasePattern pattern)
    {
        if (pattern.Properties == null || pattern.Properties.Count == 0)
        {
            return true;
        }

        return pattern.Properties.All(IsTotalPropertyPattern);
    }

    private static bool IsTotalPropertyPattern(PropertyPattern propertyPattern)
    {
        return propertyPattern.Pattern == null || IsCatchAllPattern(propertyPattern.Pattern);
    }

    private static bool IsCatchAllPattern(Pattern pattern)
    {
        return pattern is IdentifierPattern identifierPattern
            && (identifierPattern.Name == "_" || !identifierPattern.Name.Contains('.'));
    }

    /// <summary>
    /// Checks exhaustiveness for enum types in match expressions.
    /// Both string enums and int enums participate in exhaustiveness checking.
    /// </summary>
    private void CheckEnumMatchExhaustiveness(MatchExpression match, EnumTypeInfo enumType)
    {
        var coveredMembers = new HashSet<string>();

        foreach (var matchCase in match.Cases)
        {
            // Skip guarded arms
            if (matchCase.Guard != null)
                continue;

            if (matchCase.Pattern is IdentifierPattern identPattern)
            {
                if (identPattern.Name == "_")
                {
                    match.IsExhaustive = true;
                    return; // Wildcard covers all
                }

                // Check for qualified enum member (e.g., Status.Active)
                if (identPattern.Name.Contains('.'))
                {
                    var parts = identPattern.Name.Split('.');
                    var qualifier = parts[0];
                    var memberName = parts[^1];
                    // Only count if the qualifier matches the enum type name
                    if (qualifier == enumType.Declaration.Name &&
                        enumType.Declaration.Members.Any(m => m.Name == memberName))
                    {
                        coveredMembers.Add(memberName);
                    }
                }
                else
                {
                    // Unqualified non-wildcard identifier — catch-all binding
                    match.IsExhaustive = true;
                    return;
                }
            }
            else if (matchCase.Pattern is LiteralPattern literalPattern)
            {
                // Check if literal matches an enum member value
                foreach (var member in enumType.Declaration.Members)
                {
                    if (member.ValueKind == EnumMemberValueKind.String &&
                        literalPattern.Literal is StringLiteralExpression patternStr &&
                        member.ValueText == patternStr.Value)
                    {
                        coveredMembers.Add(member.Name);
                    }
                    else if (member.ValueKind == EnumMemberValueKind.Integer &&
                             literalPattern.Literal is IntLiteralExpression patternInt &&
                             member.ValueText == patternInt.Value)
                    {
                        coveredMembers.Add(member.Name);
                    }
                }
            }
        }

        // Check if all enum members are covered. The missing-member selection is owned by
        // the N# analyzer exhaustiveness kernel; do not recover with a duplicate.
        var missingMembers = AnalyzerExhaustivenessSelector.SelectMissingEnumMembers(
            enumType.Declaration.Members,
            coveredMembers);

        if (missingMembers.Count > 0)
        {
            var sourceSnippet = GetSourceSnippet(match.Line);

            if (sourceSnippet != null && _currentFilePath != null)
            {
                var error = ErrorMessageBuilder.NonExhaustiveMatch(
                    _currentFilePath,
                    match.Line,
                    match.Column,
                    sourceSnippet,
                    5, // "match" keyword length
                    missingMembers
                );
                _errors.Add(error);
            }
            else
            {
                var missingStr = string.Join(", ", missingMembers);
                Error(ErrorCode.NonExhaustiveMatch, $"This match doesn't cover all enum members — missing: {missingStr}",
                    match.Line, match.Column, ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, missingStr),
                    length: MatchKeywordLength);
            }
        }
        else
        {
            // All enum members covered by unguarded arms.
            match.IsExhaustive = true;
        }
    }

    // The function half of project auto-discovery: exported (PascalCase) top-level functions
    // are visible project-wide within visible namespaces without a file import, mirroring the
    // type half in AnalyzerProjectTypeDiscovery. Non-exported top-level functions stay
    // file-private, so they intentionally fall through to the undefined/inaccessible diagnostics.
    private bool TryResolveVisibleProjectFunction(string name, out TypeInfo type, out SymbolDeclaration declaration)
    {
        if (_projectDiscovery.TryResolveVisibleProjectFunction(
                name,
                GetUnitNamespace(_compilationUnit),
                out var declarationFile,
                out var functionDeclaration,
                out var functionSymbol))
        {
            type = _functionTypeFactory.CreateFromDeclarationInFile(functionDeclaration!, declarationFile!);
            declaration = functionSymbol!;
            return true;
        }

        type = BuiltInTypes.Unknown;
        declaration = null!;
        return false;
    }

    private void ReportUnverifiedErrorTupleResultUseIfNeeded(string name, int line, int column)
    {
        if (_suppressErrorTupleResultUse)
            return;

        if (_scopes.FindErrorTupleResultGuard(name) is not { } guard || _scopes.IsErrorTupleResultAvailable(name))
            return;

        var key = (line, column, name);
        if (!_reportedUnverifiedErrorResultDiagnostics.Add(key))
            return;

        Error(
            ErrorCode.UnverifiedErrorResult,
            $"Result '{name}' may be unavailable because '{guard.ErrorName}' can be non-null",
            line,
            column,
            $"Use '{name}' only after `if {guard.ErrorName} == null`, or return/throw from an `if {guard.ErrorName} != null` error branch before the result is used.",
            Math.Max(1, name.Length));
    }

    private bool TryResolveIdentifierBindingTarget(string name, int line, int column, out TypeInfo type)
    {
        // Check local symbols first, then local types
        if (_scopes.ResolveBindingTarget(_bindingMap, _currentFilePath, name, line, column) is { } scopeBinding)
        {
            type = scopeBinding;
            return true;
        }

        var currentType = _scopes.CurrentTypeScope();
        if (currentType != null)
        {
            var memberType = ResolveMember(currentType, name);
            if (!BuiltInTypes.IsUnknown(memberType))
            {
                type = memberType;
                return true;
            }
        }

        // Resolve built-in type keywords (int, string, bool, etc.) for static member access
        // e.g., int.Parse(...), string.IsNullOrEmpty(...), int.TryParse(...)
        var builtInClrType = AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(_wellKnownTypes, name);
        if (builtInClrType != null)
        {
            type = new ReflectionTypeInfo(builtInClrType);
            return true;
        }

        if (_projectDiscovery.ResolveVisibleProjectType(
                name,
                GetUnitNamespace(_compilationUnit),
                line > 0,
                out var projectType,
                out var projectDeclaration,
                out var inaccessibleProjectFile))
        {
            type = projectType;
            _bindingMap.RecordBinding(_currentFilePath, line, column, name.Length, projectDeclaration);
            _semanticModel.RecordType(name, projectType);
            return true;
        }

        if (inaccessibleProjectFile != null)
        {
            _diagnostics.ReportInaccessibleMember(name, inaccessibleProjectFile, line, column);
            _typeResolver.MarkUnresolvedTypeReported(name, line, column);
        }

        if (TryResolveVisibleProjectFunction(name, out var projectFunctionType, out var projectFunctionDeclaration))
        {
            type = projectFunctionType;
            _bindingMap.RecordBinding(_currentFilePath, line, column, name.Length, projectFunctionDeclaration);
            return true;
        }

        // Try to resolve as external type (for static class access like Console).
        // This intentionally happens after current-type member lookup so instance
        // members win over imported type names in instance scope.
        var externalType = _externalTypeProbe.ResolveExternalType(name);
        if (externalType != null)
        {
            type = externalType;
            return true;
        }

        type = BuiltInTypes.Unknown;
        return false;
    }

    private TypeInfo ResolveIdentifier(string name, int line, int column, bool reportMissingAsFunction = false)
    {
        if (name == "<error>")
            return BuiltInTypes.Unknown;

        if (TryResolveIdentifierBindingTarget(name, line, column, out var type))
        {
            ReportUnverifiedErrorTupleResultUseIfNeeded(name, line, column);
            return type;
        }

        if (reportMissingAsFunction
            && line > 0
            && _projectDiscovery.TryFindInaccessibleVisibleFunction(
                name,
                GetUnitNamespace(_compilationUnit),
                out var inaccessibleFunctionFile))
        {
            _diagnostics.ReportInaccessibleMember(name, inaccessibleFunctionFile!, line, column);
            return BuiltInTypes.Unknown;
        }

        // Use ErrorMessageBuilder for better error message with suggestions
        var similarNames = reportMissingAsFunction
            ? _scopes.SuggestSimilarCallableNames(name, _extensionMethods.Select(method => method.Name).ToList())
            : _scopes.SuggestSimilarVariableNames(name);
        var sourceSnippet = GetSourceSnippet(line);

        if (sourceSnippet != null && _currentFilePath != null)
        {
            var error = reportMissingAsFunction
                ? ErrorMessageBuilder.UndefinedFunction(
                    _currentFilePath,
                    line,
                    column,
                    sourceSnippet,
                    name.Length,
                    name,
                    similarNames
                )
                : ErrorMessageBuilder.UndefinedVariable(
                    _currentFilePath,
                    line,
                    column,
                    sourceSnippet,
                    name.Length,
                    name,
                    similarNames
                );
            _errors.Add(error);
        }
        else
        {
            // Fallback to simple error
            if (reportMissingAsFunction)
            {
                Error(ErrorCode.UndefinedFunction, $"Function '{name}' not found", line, column, length: name.Length);
            }
            else
            {
                Error(ErrorCode.UndefinedVariable, $"I can't find '{name}' — it hasn't been declared in this scope", line, column);
            }
        }

        return BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeBaseExpression()
    {
        var currentType = _scopes.CurrentTypeScope();
        if (currentType != null
            && _declarationContext.TryGetSourceMemberShape(currentType, null, out var shape)
            && shape.BaseType != null)
            return shape.BaseType;

        return currentType != null ? BuiltInTypes.Object : BuiltInTypes.Unknown;
    }

    // Convention-based visibility checking
    private void CheckVisibilityConvention(string name, Modifiers modifiers, int line, int column)
    {
        if (string.IsNullOrEmpty(name) || VisibilityConventions.HasExplicitVisibility(modifiers))
            return;

        // Check convention: PascalCase = public/exported, camelCase = private/unexported.
        if (VisibilityConventions.IsExportedIdentifier(name) || char.IsLower(name[0]))
            return;

        Error(
            ErrorCode.VisibilityConventionWarning,
            $"Identifier '{name}' starts with a non-letter character — in N#, PascalCase means public and camelCase means private",
            line,
            column,
            length: Math.Max(1, name.Length));
    }

    // Type checking helpers
    private TypeInfo GetIntLiteralType(string value)
    {
        if (!NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(value, out var magnitude))
        {
            return BuiltInTypes.Int;
        }

        var suffix = NumericLiteralFacts.GetIntegerSuffix(value);
        if (suffix.HasUnsigned && suffix.HasLong)
        {
            return BuiltInTypes.ULong;
        }

        if (suffix.HasUnsigned)
        {
            return magnitude <= uint.MaxValue ? BuiltInTypes.UInt : BuiltInTypes.ULong;
        }

        if (suffix.HasLong)
        {
            return magnitude <= long.MaxValue ? BuiltInTypes.Long : BuiltInTypes.ULong;
        }

        if (_currentExpectedType != null
            && TryGetExpectedIntegerLiteralType(_currentExpectedType, magnitude, out var targetType))
        {
            return targetType;
        }

        return BuiltInTypes.Int;
    }

    private bool TryGetExpectedIntegerLiteralType(TypeInfo expectedType, ulong magnitude, out TypeInfo targetType)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(expectedType);
        if (resolved is NullableTypeInfo nullable)
        {
            resolved = _declarationContext.ResolveDeclaredAlias(nullable.InnerType);
        }

        if (resolved is SimpleTypeInfo simple
            && NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue(simple.Name, out var simpleMaxValue)
            && magnitude <= simpleMaxValue)
        {
            targetType = simple;
            return true;
        }

        if (resolved is ReflectionTypeInfo reflection
            && NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(Nullable.GetUnderlyingType(reflection.Type) ?? reflection.Type, out var reflectionType)
            && NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue(reflectionType.Name, out var reflectionMaxValue)
            && magnitude <= reflectionMaxValue)
        {
            targetType = reflectionType;
            return true;
        }

        targetType = BuiltInTypes.Int;
        return false;
    }

    private bool TryGetExpectedNegativeIntegerLiteralType(
        TypeInfo? expectedType,
        string literalText,
        out TypeInfo targetType)
    {
        targetType = BuiltInTypes.Int;
        if (expectedType == null)
        {
            return false;
        }

        var suffix = NumericLiteralFacts.GetIntegerSuffix(literalText);
        if (suffix.HasUnsigned || suffix.HasLong)
        {
            return false;
        }

        if (!NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(literalText, out var magnitude))
        {
            return false;
        }

        var resolved = _declarationContext.ResolveDeclaredAlias(expectedType);
        if (resolved is NullableTypeInfo nullable)
        {
            resolved = _declarationContext.ResolveDeclaredAlias(nullable.InnerType);
        }

        if (resolved is SimpleTypeInfo simple
            && NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude(simple.Name, out var simpleMaxMagnitude)
            && magnitude <= simpleMaxMagnitude)
        {
            targetType = simple;
            return true;
        }

        if (resolved is ReflectionTypeInfo reflection
            && NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(Nullable.GetUnderlyingType(reflection.Type) ?? reflection.Type, out var reflectionType)
            && NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude(reflectionType.Name, out var reflectionMaxMagnitude)
            && magnitude <= reflectionMaxMagnitude)
        {
            targetType = reflectionType;
            return true;
        }

        return false;
    }

    /// <summary>
    /// Finds a common base type between two types, if one exists.
    /// For reflection types, walks the CLR type hierarchy and interface list.
    /// </summary>
    private TypeInfo? FindCommonBaseType(TypeInfo a, TypeInfo b)
    {
        if (a is ReflectionTypeInfo reflA && b is ReflectionTypeInfo reflB)
        {
            var interfacesA = reflA.Type.GetInterfaces();
            var interfacesB = new HashSet<Type>(reflB.Type.GetInterfaces());

            foreach (var iface in interfacesA)
            {
                if (interfacesB.Contains(iface))
                {
                    return new ReflectionTypeInfo(iface);
                }
            }

            var baseA = reflA.Type.BaseType;
            while (baseA != null && baseA != typeof(object))
            {
                if (baseA.IsAssignableFrom(reflB.Type))
                    return new ReflectionTypeInfo(baseA);
                baseA = baseA.BaseType;
            }
        }


        return null;
    }

    private bool IsPatternPossible(TypeInfo sourceType, TypeInfo targetType)
    {
        var resolvedSource = _declarationContext.ResolveDeclaredAlias(sourceType);
        var resolvedTarget = _declarationContext.ResolveDeclaredAlias(targetType);

        if (resolvedSource is UnknownTypeInfo || resolvedTarget is UnknownTypeInfo) return true;
        if (resolvedSource is ReflectionTypeInfo || resolvedTarget is ReflectionTypeInfo) return true;

        if (resolvedSource is GenericTypeInfo || resolvedTarget is GenericTypeInfo) return true;

        if (resolvedSource == resolvedTarget) return true;
        if (resolvedSource is SimpleTypeInfo simplePatternSource && resolvedTarget is SimpleTypeInfo simplePatternTarget
            && simplePatternSource.Equals(simplePatternTarget)) return true;

        if (resolvedSource is InterfaceTypeInfo || resolvedTarget is InterfaceTypeInfo) return true;

        if (BuiltInTypes.Is(resolvedSource, BuiltInTypes.Object) || BuiltInTypes.Is(resolvedTarget, BuiltInTypes.Object)) return true;

        if (resolvedSource is NullableTypeInfo || resolvedTarget is NullableTypeInfo) return true;

        if (resolvedSource is UnionTypeInfo or AnonymousUnionTypeInfo
            || resolvedTarget is UnionTypeInfo or AnonymousUnionTypeInfo)
            return true;

        bool sourceIsValue = !AnalyzerConversionFacts.IsReferenceType(resolvedSource);
        bool targetIsValue = !AnalyzerConversionFacts.IsReferenceType(resolvedTarget);
        if (sourceIsValue && targetIsValue)
        {
            return false;
        }

        if (_assignability.IsAssignable(resolvedTarget, resolvedSource)) return true;
        if (_assignability.IsAssignable(resolvedSource, resolvedTarget)) return true;

        if (sourceIsValue && !targetIsValue)
        {
            if (resolvedTarget is not InterfaceTypeInfo)
                return false;
        }
        if (targetIsValue && !sourceIsValue)
        {
            if (resolvedSource is not InterfaceTypeInfo)
                return false;
        }

        if (resolvedSource is ClassTypeInfo srcClass && srcClass.IsSealed)
        {
            if (resolvedTarget is ClassTypeInfo) return false;
        }
        if (resolvedTarget is ClassTypeInfo tgtClass && tgtClass.IsSealed)
        {
            if (resolvedSource is ClassTypeInfo) return false;
        }

        return true;
    }

    private bool IsNumericType(TypeInfo type)
    {
        return BuiltInTypes.Is(type, BuiltInTypes.Int) || BuiltInTypes.Is(type, BuiltInTypes.Long)
            || BuiltInTypes.Is(type, BuiltInTypes.Float) || BuiltInTypes.Is(type, BuiltInTypes.Double)
            || BuiltInTypes.Is(type, BuiltInTypes.Decimal) || BuiltInTypes.Is(type, BuiltInTypes.Byte)
            || BuiltInTypes.Is(type, BuiltInTypes.SByte) || BuiltInTypes.Is(type, BuiltInTypes.Short)
            || BuiltInTypes.Is(type, BuiltInTypes.UShort) || BuiltInTypes.Is(type, BuiltInTypes.UInt)
            || BuiltInTypes.Is(type, BuiltInTypes.ULong) || BuiltInTypes.Is(type, BuiltInTypes.Char);
    }

    private bool IsPrimitiveRelationalType(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        if (IsNumericType(resolved) && BuiltInTypes.IsNot(resolved, BuiltInTypes.Decimal))
        {
            return true;
        }

        if (resolved is SimpleTypeInfo simple && IsPrimitiveRelationalTypeName(simple.Name))
        {
            return true;
        }

        return resolved is ReflectionTypeInfo reflection
            && IsPrimitiveRelationalClrType(reflection.Type);
    }

    private static bool IsPrimitiveRelationalTypeName(string name)
    {
        return name is "byte" or "Byte"
            or "sbyte" or "SByte"
            or "short" or "Int16"
            or "ushort" or "UInt16"
            or "int" or "Int32"
            or "uint" or "UInt32"
            or "long" or "Int64"
            or "ulong" or "UInt64"
            or "char" or "Char"
            or "float" or "Single"
            or "double" or "Double";
    }

    private static bool IsPrimitiveRelationalClrType(Type type)
    {
        return type == typeof(byte)
            || type == typeof(sbyte)
            || type == typeof(short)
            || type == typeof(ushort)
            || type == typeof(int)
            || type == typeof(uint)
            || type == typeof(long)
            || type == typeof(ulong)
            || type == typeof(char)
            || type == typeof(float)
            || type == typeof(double);
    }

    private bool CanCompareWithEqualityOperator(TypeInfo left, TypeInfo right)
    {
        var resolvedLeft = _declarationContext.ResolveDeclaredAlias(left);
        var resolvedRight = _declarationContext.ResolveDeclaredAlias(right);

        if (BuiltInTypes.Is(resolvedLeft, BuiltInTypes.Null) || BuiltInTypes.Is(resolvedRight, BuiltInTypes.Null))
        {
            return true;
        }

        if (ArePrimitiveEqualityTypesCompatible(resolvedLeft, resolvedRight))
        {
            return true;
        }

        if (IsSameBitwiseEnumType(resolvedLeft, resolvedRight))
        {
            return true;
        }

        if (IsSameRecordStructType(resolvedLeft, resolvedRight))
        {
            return true;
        }

        return AnalyzerConversionFacts.IsReferenceType(resolvedLeft) && AnalyzerConversionFacts.IsReferenceType(resolvedRight);
    }

    private bool ArePrimitiveEqualityTypesCompatible(TypeInfo left, TypeInfo right)
    {
        var leftIsBool = IsBoolLikeType(left);
        var rightIsBool = IsBoolLikeType(right);
        if (leftIsBool || rightIsBool)
        {
            return leftIsBool && rightIsBool;
        }

        if (!IsPrimitiveRelationalType(left) || !IsPrimitiveRelationalType(right))
        {
            return false;
        }

        return GetWiderType(left, right) != null;
    }

    private bool IsBoolLikeType(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        if (BuiltInTypes.Is(resolved, BuiltInTypes.Bool))
        {
            return true;
        }

        if (resolved is SimpleTypeInfo { Name: "bool" or "Boolean" })
        {
            return true;
        }

        return resolved is ReflectionTypeInfo { Type: var typeInfoType }
            && typeInfoType == typeof(bool);
    }

    private static bool IsSameRecordStructType(TypeInfo left, TypeInfo right)
    {
        return ReferenceEquals(left, right)
            && left is RecordTypeInfo { IsStruct: true };
    }

    private bool IsIntegralType(TypeInfo type)
    {
        return BuiltInTypes.Is(type, BuiltInTypes.Int) || BuiltInTypes.Is(type, BuiltInTypes.Long)
            || BuiltInTypes.Is(type, BuiltInTypes.Byte) || BuiltInTypes.Is(type, BuiltInTypes.SByte)
            || BuiltInTypes.Is(type, BuiltInTypes.Short) || BuiltInTypes.Is(type, BuiltInTypes.UShort)
            || BuiltInTypes.Is(type, BuiltInTypes.UInt) || BuiltInTypes.Is(type, BuiltInTypes.ULong)
            || BuiltInTypes.Is(type, BuiltInTypes.Char);
    }

    private bool IsBitwiseEnumType(TypeInfo type)
    {
        var resolved = _declarationContext.ResolveDeclaredAlias(type);
        return resolved is EnumTypeInfo { Declaration.Type: EnumType.Int }
            || resolved is ReflectionTypeInfo { Type.IsEnum: true };
    }

    private bool IsSameBitwiseEnumType(TypeInfo left, TypeInfo right)
    {
        var resolvedLeft = _declarationContext.ResolveDeclaredAlias(left);
        var resolvedRight = _declarationContext.ResolveDeclaredAlias(right);
        return (resolvedLeft, resolvedRight) switch
        {
            (EnumTypeInfo l, EnumTypeInfo r) => l.Declaration.Type == EnumType.Int
                && r.Declaration.Type == EnumType.Int
                && ReferenceEquals(l, r),
            (ReflectionTypeInfo l, ReflectionTypeInfo r) => l.Type.IsEnum
                && r.Type.IsEnum
                && l.Type == r.Type,
            _ => false
        };
    }

    private bool IsBoolType(TypeInfo type)
    {
        return BuiltInTypes.Is(type, BuiltInTypes.Bool);
    }

    private bool IsStringType(TypeInfo type)
    {
        return BuiltInTypes.Is(type, BuiltInTypes.String);
    }

    private bool IsNullableType(TypeInfo type)
    {
        return type is NullableTypeInfo;
    }

    /// <summary>
    /// N# binary numeric promotion rules. These determine the result type of arithmetic binary
    /// operations. NOTE: This is NOT the same as implicit numeric conversion (assignment context).
    /// N# promotes small types (byte, sbyte, short, ushort) to int for arithmetic. Returns null for
    /// combinations that are compile-time errors in (decimal+float/double, ulong+signed).
    /// </summary>
    private TypeInfo? GetWiderType(TypeInfo left, TypeInfo right)
    {
        var l = GetNumericName(left);
        var r = GetNumericName(right);
        if (l == null || r == null)
            return BuiltInTypes.Int; // fallback

        if (l == "decimal" || r == "decimal")
        {
            var other = l == "decimal" ? r : l;
            if (other is "float" or "double")
                return null; // compile-time error
            return BuiltInTypes.Decimal;
        }

        if (l == "double" || r == "double") return BuiltInTypes.Double;
        if (l == "float" || r == "float") return BuiltInTypes.Float;

        if (l == "ulong" || r == "ulong")
        {
            var other = l == "ulong" ? r : l;
            if (other is "sbyte" or "short" or "int" or "long")
                return null; // compile-time error
            return BuiltInTypes.ULong;
        }

        if (l == "long" || r == "long") return BuiltInTypes.Long;

        if (l == "uint" || r == "uint")
        {
            var other = l == "uint" ? r : l;
            if (other is "sbyte" or "short" or "int")
                return BuiltInTypes.Long;
            return BuiltInTypes.UInt;
        }

        return BuiltInTypes.Int;
    }

    private TypeInfo? GetUnaryNumericPromotionType(TypeInfo operand)
    {
        return GetNumericName(operand) switch
        {
            "byte" or "sbyte" or "short" or "ushort" or "char" => BuiltInTypes.Int,
            "int" => BuiltInTypes.Int,
            "uint" => BuiltInTypes.UInt,
            "long" => BuiltInTypes.Long,
            "ulong" => BuiltInTypes.ULong,
            "float" => BuiltInTypes.Float,
            "double" => BuiltInTypes.Double,
            "decimal" => BuiltInTypes.Decimal,
            _ => null
        };
    }

    private TypeInfo? GetUnaryNegationType(TypeInfo operand)
    {
        return GetNumericName(operand) switch
        {
            "byte" or "sbyte" or "short" or "ushort" or "char" => BuiltInTypes.Int,
            "int" => BuiltInTypes.Int,
            "uint" => BuiltInTypes.Long,
            "long" => BuiltInTypes.Long,
            "float" => BuiltInTypes.Float,
            "double" => BuiltInTypes.Double,
            "decimal" => BuiltInTypes.Decimal,
            _ => null
        };
    }

    private static string? GetNumericName(TypeInfo type)
    {
        if (type is SimpleTypeInfo simple)
            return simple.Name;
        return null;
    }

    private void ReportBinaryOperatorOperandMismatch(
        BinaryExpression expr,
        TypeInfo left,
        TypeInfo right,
        string requirement)
    {
        var leftIsWrong = !IsIntegralType(left) && !IsBoolType(left);
        var rightIsWrong = !IsIntegralType(right) && !IsBoolType(right);
        if (expr.Operator is BinaryOperator.LeftShift or BinaryOperator.RightShift)
        {
            leftIsWrong = !IsIntegralType(left);
            rightIsWrong = !IsIntegralType(right);
        }

        var (diagnosticLine, diagnosticColumn, diagnosticLength) =
            _spans.GetBinaryOperandDiagnosticSpan(expr, leftIsWrong, rightIsWrong);
        var opText = OperatorFacts.GetBinaryText(expr.Operator);
        var sideText = leftIsWrong == rightIsWrong
            ? $"I found '{left}' and '{right}'"
            : leftIsWrong
                ? $"the left side is '{left}'"
                : $"the right side is '{right}'";

        Error(
            ErrorCode.TypeMismatch,
            $"The '{opText}' operator doesn't work with '{left}' and '{right}' — {requirement}, but {sideText}",
            diagnosticLine,
            diagnosticColumn,
            "Use compatible operands, convert the non-compatible value, or define an operator overload for this type.",
            diagnosticLength);
    }

    private void ReportUnaryOperatorOperandMismatch(UnaryExpression unary, TypeInfo operandType, string requirement)
    {
        var opText = OperatorFacts.GetUnaryText(unary.Operator);
        Error(
            ErrorCode.TypeMismatch,
            $"The '{opText}' operator doesn't work with '{operandType}' — {requirement}",
            unary.Line,
            unary.Column,
            "Use a compatible operand, convert the value, or define an operator overload for this type.",
            opText.Length);
    }

    private TypeInfo GetCommonType(TypeInfo left, TypeInfo right)
    {
        if (left == right) return left;
        if (IsNumericType(left) && IsNumericType(right)) return GetWiderType(left, right) ?? BuiltInTypes.Unknown;
        return BuiltInTypes.Unknown;
    }

    private void PushScope(Scope scope)
    {
        PushScope(scope, 0, 0);
    }

    private void PushScope(Scope scope, int startLine, int startColumn)
    {
        _scopes.Push(_semanticModel, scope, startLine, startColumn);
    }

    private void PopScope()
    {
        _scopes.Pop(_semanticModel, _currentLine);
    }

    /// <summary>
    /// Record a variable in the current semantic scope (for position-aware lookups).
    /// </summary>
    private void RecordVariableInCurrentScope(string name, TypeInfo type)
    {
        if (_scopes.HasSemanticScope())
        {
            _semanticModel.RecordScopedVariable(_scopes.CurrentSemanticScopeId(), name, type);
        }
        else
        {
            _semanticModel.RecordVariable(name, type);
        }
    }

    /// <summary>
    /// Record a function in the current semantic scope (for position-aware lookups).
    /// </summary>
    private void RecordFunctionInCurrentScope(string name, TypeInfo type)
    {
        if (_scopes.HasSemanticScope())
        {
            _semanticModel.RecordScopedFunction(_scopes.CurrentSemanticScopeId(), name, type);
        }
        else
        {
            _semanticModel.RecordFunction(name, type);
        }
    }

    private void DeclareSymbol(
        string name,
        TypeInfo type,
        int line,
        int column,
        string? declarationKind = null,
        bool recordBindingDeclaration = true)
    {
        var currentScope = _scopes.Peek();
        var nameColumn = _spans.GetDeclarationNameColumn(name, line, column);
        var shouldRecordBindingDeclaration = recordBindingDeclaration;
        if (currentScope.Symbols.TryGetValue(name, out var existing))
        {
            if (type is FunctionTypeInfo newFunction && AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(newFunction))
            {
                if (existing is FunctionTypeInfo existingFunction && AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(existingFunction))
                {
                    if (AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(newFunction, new[] { existingFunction }))
                    {
                        currentScope.Symbols[name] = NSharpMethodGroupInfoFactory.FromFunctions(
                            new[] { existingFunction, newFunction });
                        if (shouldRecordBindingDeclaration)
                        {
                            var kind = declarationKind ?? AnalyzerBindingFacts.TypeInfoToDeclarationKind(type);
                            var decl = new SymbolDeclaration(name, _currentFilePath, line, nameColumn, kind);
                            _bindingMap.RecordDeclaration(decl);
                        }
                        return;
                    }
                }

                if (existing is NSharpMethodGroupInfo group)
                {
                    var functions = GetNSharpMethodGroupFunctions(group);
                    if (functions.All(AnalyzerOverloadSignatureFacts.HasSourceParameterSignature)
                        && AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(newFunction, functions))
                    {
                        NSharpMethodGroupInfoFactory.AddFunction(group, newFunction);
                        if (shouldRecordBindingDeclaration)
                        {
                            var kind = declarationKind ?? AnalyzerBindingFacts.TypeInfoToDeclarationKind(type);
                            var decl = new SymbolDeclaration(name, _currentFilePath, line, nameColumn, kind);
                            _bindingMap.RecordDeclaration(decl);
                        }
                        return;
                    }
                }
            }

            Error(
                ErrorCode.DuplicateDeclaration,
                $"'{name}' is already declared in this scope — each name must be unique within the same scope",
                line,
                nameColumn,
                length: Math.Max(1, name.Length));
        }
        else
        {
            CheckShadowedDeclaration(name, type, line, nameColumn);

            currentScope.Symbols[name] = type;
            currentScope.NullStates[name] = GetDefaultNullState(type);

            var kind = declarationKind ?? AnalyzerBindingFacts.TypeInfoToDeclarationKind(type);
            if (shouldRecordBindingDeclaration)
            {
                var decl = new SymbolDeclaration(name, _currentFilePath, line, nameColumn, kind);
                _bindingMap.RecordDeclaration(decl);
                currentScope.RecordDeclarationLocation(name, _currentFilePath, line, nameColumn, kind);
            }
        }
    }

    /// <summary>
    /// Compiler-level shadowing guarantee (NL316). A local or parameter declaration
    /// that shadows a local/parameter from an enclosing function/block scope is a hard,
    /// build-blocking error. This is authoritative: when it fires the file has a compiler
    /// error, which suppresses the linter's NL020 for the same file (see
    /// CodeIntelligenceService.GetDiagnostics), so the user sees exactly one diagnostic.
    /// </summary>
    private void CheckShadowedDeclaration(string name, TypeInfo type, int line, int nameColumn)
    {
        if (!_scopes.ShadowsEnclosingValueBinding(name, type))
            return;

        Error(
            ErrorCode.ShadowedDeclaration,
            $"'{name}' shadows an existing '{name}' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs",
            line,
            nameColumn,
            ErrorSuggestions.GetSuggestion(ErrorCode.ShadowedDeclaration, name),
            Math.Max(1, name.Length));
    }

    private void DeclareType(string name, TypeInfo type, int line, int column)
    {
        if (_declarationContextFilePath != null && type is not AliasTypeInfo)
        {
            if (_declarationContext.TryGetCanonicalType(
                    _declarationContextFilePath,
                    name,
                    out var canonicalType)
                && !BuiltInTypes.IsUnknown(canonicalType))
            {
                type = canonicalType;
            }
        }

        var currentScope = _scopes.Peek();
        var nameColumn = _spans.GetDeclarationNameColumn(name, line, column);
        if (currentScope.Types.ContainsKey(name))
        {
            Error(
                ErrorCode.DuplicateDeclaration,
                $"A type named '{name}' already exists — each type name must be unique",
                line,
                nameColumn,
                length: Math.Max(1, name.Length));
        }
        else
        {
            currentScope.Types[name] = type;
            _semanticModel.RecordType(name, type);
            if (!string.IsNullOrEmpty(_currentFilePath))
                _typeDeclarationFiles[name] = _currentFilePath;
            if (_declarationContextFilePath != null)
            {
                if (type is AliasTypeInfo declaredAlias)
                    _declarationContext.RegisterDeclaredAlias(_declarationContextFilePath, declaredAlias);
                else
                    _declarationContext.RegisterCanonicalType(_declarationContextFilePath, name, type);
            }

            var kind = AnalyzerBindingFacts.TypeInfoToDeclarationKind(type);
            var decl = new SymbolDeclaration(name, _currentFilePath, line, nameColumn, kind);
            _bindingMap.RecordDeclaration(decl);
            currentScope.RecordDeclarationLocation(name, _currentFilePath, line, nameColumn, kind);
        }
    }

    private void ValidateParamsParameters(List<Parameter> parameters, int line, int column)
    {
        for (int i = 0; i < parameters.Count; i++)
        {
            var param = parameters[i];
            if (param.Modifier == Ast.ParameterModifier.Params)
            {
                var (paramLine, paramColumn, paramLength) = AnalyzerDiagnosticSpanFacts.GetParameterDiagnosticSpan(param, line, column);

                if (i != parameters.Count - 1)
                {
                    Error(
                        ErrorCode.ParamsNotLast,
                        "A 'params' parameter must come last in the parameter list — move it to the end",
                        paramLine,
                        paramColumn,
                        length: paramLength);
                }

                if (!TypeReferenceFacts.IsValidParamsType(param.Type))
                {
                    Error(
                        ErrorCode.InvalidParameter,
                        $"A 'params' parameter must be an array or collection type — '{TypeReferenceFacts.GetDisplayName(param.Type)}' is not a valid params type",
                        paramLine,
                        paramColumn,
                        length: paramLength);
                }
            }
        }
    }

    private void ValidateParameterDeclarations(List<Parameter> parameters, int line, int column)
    {
        ValidateParamsParameters(parameters, line, column);
        ValidateDefaultParameters(parameters, line, column);
    }

    private void ValidateDefaultParameters(List<Parameter> parameters, int line, int column)
    {
        bool foundOptional = false;

        for (int i = 0; i < parameters.Count; i++)
        {
            var param = parameters[i];

            if (param.IsThis || param.Modifier == Ast.ParameterModifier.Params)
                continue;

            bool hasDefault = param.DefaultValue != null;

            if (hasDefault)
            {
                foundOptional = true;
                var reportedSoaDefaultParameterDiagnostic = ReportSoaDefaultParameterValueIfNeeded(param);

                if (!reportedSoaDefaultParameterDiagnostic
                    && !IsValidDefaultValue(param.DefaultValue!, param.Type))
                {
                    var (defaultLine, defaultColumn, defaultLength) = _spans.GetExpressionDiagnosticSpan(param.DefaultValue!);
                    Error(ErrorCode.InvalidDefaultParameterValue,
                        $"The default value for '{param.Name}' must be something the compiler can evaluate — use a literal, null, or a simple constant",
                        defaultLine, defaultColumn, length: defaultLength);
                }
            }
            else
            {
                if (foundOptional)
                {
                    var (paramLine, paramColumn, paramLength) = AnalyzerDiagnosticSpanFacts.GetParameterDiagnosticSpan(param, line, column);
                    Error(ErrorCode.RequiredParameterAfterOptional,
                        $"Required parameter '{param.Name}' can't come after optional parameters — move it before the optional ones, or give it a default value too",
                        paramLine, paramColumn, length: paramLength);
                }
            }
        }
    }

    private bool ReportSoaDefaultParameterValueIfNeeded(Parameter parameter)
    {
        if (!SoaFeature.IsEnabled || parameter.DefaultValue == null)
        {
            return false;
        }

        var parameterType = _typeResolver.ResolveDeclaredType(parameter.Type);
        if (_declarationContext.ResolveDeclaredAlias(GetNonNullableType(parameterType)) is not SoaRecordTypeInfo soaRecordType)
        {
            return false;
        }

        var errorsBefore = _errors.Count;
        AnalyzeExpressionWithExpectedType(parameter.DefaultValue, parameterType);
        if (_errors.Count > errorsBefore)
        {
            return true;
        }

        var tableName = soaRecordType.Declaration.Name;
        var (line, column, length) = _spans.GetExpressionDiagnosticSpan(parameter.DefaultValue);
        Error(
            ErrorCode.InvalidDefaultParameterValue,
            $"SoA table '{tableName}' cannot be used as a default parameter value — optional parameter defaults are metadata constants, but SoA tables must be constructed or wrapped at runtime",
            line,
            column,
            $"Use an overload that creates the table with 'new {tableName}(capacity)' or accepts a '{tableName}.wrap(...)' value from the caller.",
            length);
        return true;
    }

    private bool IsValidDefaultValue(Expression expr, TypeReference expectedType)
    {
        return expr switch
        {
            IntLiteralExpression => true,
            FloatLiteralExpression => true,
            CharLiteralExpression => true,
            BoolLiteralExpression => true,
            StringLiteralExpression => true,
            NullLiteralExpression => true,

            MemberAccessExpression memberAccess when IsMatchingEnumMemberDefault(memberAccess, expectedType) => true,
            UnaryExpression unary when IsValidDefaultValue(unary.Operand, expectedType) => true,
            BinaryExpression binary when IsValidDefaultValue(binary.Left, expectedType)
                                                && IsValidDefaultValue(binary.Right, expectedType) => true,
            ArrayLiteralExpression arrayLit => arrayLit.Elements.All(element => IsValidDefaultValue(element, expectedType)),

            _ => false
        };
    }

    private bool IsMatchingEnumMemberDefault(MemberAccessExpression memberAccess, TypeReference expectedType)
    {
        if (memberAccess.IsNullConditional
            || !TryGetQualifiedAttributeName(memberAccess.Object, out var ownerName))
        {
            return false;
        }

        var ownerType = _declarationContext.ResolveDeclaredAlias(ResolveDefaultEnumTypeName(ownerName));
        var resolvedExpectedType = _declarationContext.ResolveDeclaredAlias(
            expectedType is SimpleTypeReference simple
                ? ResolveDefaultEnumTypeName(simple.Name)
                : _typeResolver.ResolveDeclaredType(expectedType));
        if (!TypeInfoIdentityFacts.AreEqual(ownerType, resolvedExpectedType))
        {
            return false;
        }

        return ownerType switch
        {
            EnumTypeInfo sourceEnum => HasSourceEnumMember(sourceEnum, memberAccess.MemberName),
            ReflectionTypeInfo { Type: var runtimeEnum }
                when TypeInfoIdentityFacts.IsInt32BackedRuntimeEnum(runtimeEnum)
                => HasRuntimeEnumMember(runtimeEnum, memberAccess.MemberName),
            _ => false
        };
    }

    private TypeInfo ResolveDefaultEnumTypeName(string name)
    {
        var separator = name.IndexOf('.');
        if (separator <= 0 || separator >= name.Length - 1)
            return _typeResolver.ResolveSimpleType(name, 0, 0);

        var root = name[..separator];
        var remainder = name[(separator + 1)..];
        if (_declarationContext.TryResolveFileImportAliasType(
                name, _currentFilePath, _importedSymbolsByAlias, _importedDeclarationsByAlias,
                out var importedType, out _, out var fileAliasClaimed))
            return _declarationContext.ResolveDeclaredAlias(importedType);
        if (fileAliasClaimed)
            return BuiltInTypes.Unknown;

        if (_usingAliases.TryGetValue(root, out var namespaceName))
        {
            if (_projectDiscovery.TryResolveProjectTypeInNamespace(remainder, namespaceName, GetUnitNamespace(_compilationUnit), out var projectType, out _))
                return projectType;
            var expandedName = namespaceName + "." + remainder;
            if (ExternalQualifiedTypeResolver.TryResolve(_mlcAssemblies, expandedName, out var aliasedRuntimeType))
                return new ReflectionTypeInfo(aliasedRuntimeType);
            return _typeResolver.ResolveSimpleType(expandedName, 0, 0);
        }

        if (ExternalQualifiedTypeResolver.TryResolve(_mlcAssemblies, name, out var runtimeType))
            return new ReflectionTypeInfo(runtimeType);
        return _typeResolver.ResolveSimpleType(name, 0, 0);
    }

    private void ValidateOperatorOverload(FunctionDeclaration func)
    {
        var (operatorKeywordLine, operatorKeywordColumn, operatorKeywordLength) = AnalyzerDiagnosticSpanFacts.GetSourceSpanDiagnosticSpan(
            func.OperatorKeywordSpan,
            func.Line,
            func.Column,
            "operator".Length);
        var (operatorSymbolLine, operatorSymbolColumn, operatorSymbolLength) = AnalyzerDiagnosticSpanFacts.GetSourceSpanDiagnosticSpan(
            func.OperatorSymbolSpan,
            func.Line,
            func.Column,
            func.OperatorSymbol?.Length ?? 1);

        if (!func.Modifiers.HasFlag(Modifiers.Static))
        {
            Error(
                ErrorCode.InvalidOperatorOverload,
                "Operator overloads must be declared 'static' — they don't belong to a specific instance",
                operatorKeywordLine,
                operatorKeywordColumn,
                length: operatorKeywordLength);
        }

        var expectedParams = func.OperatorSymbol switch
        {
            "!" or "~" or "++" or "--" or "true" or "false" => 1,
            "+" or "-" or "*" or "/" or "%" or
            "==" or "!=" or "<" or ">" or "<=" or ">=" or
            "&" or "|" or "^" or "<<" or ">>" => 2,
            _ => -1 // Unknown operator
        };

        if (expectedParams == -1)
        {
            Error(
                ErrorCode.InvalidOperatorOverload,
                $"The operator '{func.OperatorSymbol}' cannot be overloaded — only arithmetic, comparison, bitwise, and logical operators are supported",
                operatorSymbolLine,
                operatorSymbolColumn,
                length: operatorSymbolLength);
            return;
        }

        if (func.OperatorSymbol is "+" or "-")
        {
            if (func.Parameters.Count != 1 && func.Parameters.Count != 2)
            {
                Error(
                    ErrorCode.OperatorParameterCount,
                    $"Operator '{func.OperatorSymbol}' can be unary (1 parameter) or binary (2 parameters), but you declared {func.Parameters.Count}",
                    operatorSymbolLine,
                    operatorSymbolColumn,
                    length: operatorSymbolLength);
            }
        }
        else if (func.Parameters.Count != expectedParams)
        {
            Error(
                ErrorCode.OperatorParameterCount,
                $"Operator '{func.OperatorSymbol}' requires exactly {expectedParams} parameter(s), but you declared {func.Parameters.Count}",
                operatorSymbolLine,
                operatorSymbolColumn,
                length: operatorSymbolLength);
        }
    }

    private void Error(string message, int line, int column)
    {
        Error(ErrorCode.InvalidSyntax, message, line, column);
    }

    private void Error(ErrorCode code, string message, int line, int column, string? suggestion = null, int length = 0)
        => _diagnostics.Report(code, message, line, column, suggestion, length);

    private void Warning(string message, int line, int column)
    {
        Warning(ErrorCode.UnusedVariable, message, line, column);
    }

    private void Warning(ErrorCode code, string message, int line, int column, string? suggestion = null, int length = 0)
        => _diagnostics.Warn(code, message, line, column, suggestion, length);

    private string? GetSourceSnippet(int line) => _diagnostics.SourceSnippet(line);

    private void ValidatePackageName(PackageDeclaration package)
    {
        var parts = package.Name.Split('.');
        foreach (var part in parts)
        {
            if (!IsValidIdentifier(part))
            {
                Error($"Package name '{part}' is not a valid identifier — package names must start with a letter and contain only letters, digits, and underscores", package.Line, package.Column);
            }
        }
    }

    private bool IsValidIdentifier(string name)
    {
        if (string.IsNullOrEmpty(name))
            return false;

        if (!char.IsLetter(name[0]) && name[0] != '_')
            return false;

        for (int i = 1; i < name.Length; i++)
        {
            if (!char.IsLetterOrDigit(name[i]) && name[i] != '_')
                return false;
        }

        return true;
    }

    private void ProcessImports(List<Statement> imports)
    {
        var projectRoot = _projectSources.ProjectRoot;
        if (_currentFilePath == null || projectRoot == null)
        {
            return;
        }

        var fileResolver = new FileResolver(projectRoot, _currentFilePath);

        foreach (var import in imports)
        {
            if (import is FileImport fileImport)
            {
                ProcessFileImport(fileImport, fileResolver);
            }
            else if (import is NamespaceImport nsImport)
            {
                ProcessNamespaceImport(nsImport);
            }
        }
    }

    private void ProcessFileImport(FileImport import, FileResolver resolver)
    {
        var resolvedPath = ResolveFileImportPath(resolver, import.Path, out var errorMessage);
        if (resolvedPath == null)
        {
            var sourceSnippet = GetSourceSnippet(import.Line);

            if (sourceSnippet != null && _currentFilePath != null)
            {
                var error = ErrorMessageBuilder.ImportNotFound(
                    _currentFilePath,
                    import.Line,
                    import.DiagnosticColumn,
                    sourceSnippet,
                    import.DiagnosticLength,
                    import.Path
                );
                _errors.Add(error);
            }
            else
            {
                Error(
                    ErrorCode.ImportNotFound,
                    errorMessage!,
                    import.Line,
                    import.DiagnosticColumn,
                    ErrorSuggestions.GetSuggestion(ErrorCode.ImportNotFound),
                    import.DiagnosticLength);
            }
            return;
        }

        if (_currentFilePath != null &&
            string.Equals(Path.GetFullPath(resolvedPath), Path.GetFullPath(_currentFilePath), StringComparison.OrdinalIgnoreCase))
        {
            var sourceSnippet = GetSourceSnippet(import.Line);

            if (sourceSnippet != null)
            {
                var error = ErrorMessageBuilder.CircularImport(
                    _currentFilePath,
                    import.Line,
                    import.DiagnosticColumn,
                    sourceSnippet,
                    import.DiagnosticLength,
                    import.Path);
                _errors.Add(error);
            }
            else
            {
                Error(ErrorCode.CircularImport, $"'{import.Path}' imports itself — circular imports aren't allowed",
                    import.Line, import.DiagnosticColumn,
                    ErrorSuggestions.GetSuggestion(ErrorCode.CircularImport),
                    import.DiagnosticLength);
            }
            return;
        }

        CompilationUnit? importedUnit = null;
        string? importedSource = null;
        try
        {
            importedSource = _projectSources.TryGetProjectSourceText(resolvedPath) ?? System.IO.File.ReadAllText(resolvedPath);
            var parseResult = ColumnarParserRecovery.ParseFileAst(importedSource, resolvedPath);
            importedUnit = parseResult.CompilationUnit;

            foreach (var error in parseResult.Errors)
            {
                Error(
                    ErrorCode.InvalidSyntax,
                    $"The imported file '{import.Path}' has a syntax error — {error.Message}",
                    import.Line,
                    import.DiagnosticColumn,
                    length: import.DiagnosticLength);
            }

            if (importedUnit == null)
            {
                return;  // Can't continue without compilation unit
            }
        }
        catch (Exception ex)
        {
            Error(
                ErrorCode.InvalidSyntax,
                $"I couldn't read the imported file '{import.Path}' — {ex.Message}",
                import.Line,
                import.DiagnosticColumn,
                length: import.DiagnosticLength);
            return;
        }

        _declarationContext.AddCompilationUnit(resolvedPath, importedUnit);

        if (importedUnit.FileImports.Count > 0 && _projectSources.ProjectRoot != null && _currentFilePath != null)
        {
            var currentNormalized = Path.GetFullPath(_currentFilePath);
            var importedFileResolver = new FileResolver(_projectSources.ProjectRoot, resolvedPath);
            foreach (var nestedImport in importedUnit.FileImports)
            {
                if (nestedImport is FileImport nestedFileImport)
                {
                    var nestedPath = ResolveFileImportPath(importedFileResolver, nestedFileImport.Path, out _);
                    if (nestedPath != null &&
                        string.Equals(Path.GetFullPath(nestedPath), currentNormalized, StringComparison.OrdinalIgnoreCase))
                    {
                        var sourceSnippet = GetSourceSnippet(import.Line);

                        if (sourceSnippet != null)
                        {
                            var error = ErrorMessageBuilder.CircularImport(
                                _currentFilePath,
                                import.Line,
                                import.DiagnosticColumn,
                                sourceSnippet,
                                import.DiagnosticLength,
                                import.Path);
                            _errors.Add(error);
                        }
                        else
                        {
                            Error(ErrorCode.CircularImport,
                                $"Circular import: '{import.Path}' imports '{nestedFileImport.Path}' which imports this file back — break the cycle by restructuring your imports",
                                import.Line, import.DiagnosticColumn,
                                ErrorSuggestions.GetSuggestion(ErrorCode.CircularImport),
                                import.DiagnosticLength);
                        }
                        return;
                    }
                }
            }
        }

        var symbols = ExtractPublicSymbols(importedUnit, resolvedPath, importedSource);

        if (import.Alias != null)
        {
            if (!_importedSymbolsByAlias.ContainsKey(import.Alias))
            {
                _importedSymbolsByAlias[import.Alias] = new Dictionary<string, TypeInfo>();
            }
            if (!_importedDeclarationsByAlias.ContainsKey(import.Alias))
            {
                _importedDeclarationsByAlias[import.Alias] = new Dictionary<string, SymbolDeclaration>();
            }

            foreach (var symbol in symbols)
            {
                _importedSymbolsByAlias[import.Alias][symbol.Name] = symbol.Type;
                _importedDeclarationsByAlias[import.Alias][symbol.Name] = symbol.Declaration;
                if (AnalyzerBindingFacts.IsTypeDeclarationKind(symbol.Declaration.Kind))
                {
                    _typeDeclarationFiles[symbol.Name] = symbol.Declaration.File!;
                }
            }
        }
        else
        {
            foreach (var symbol in symbols)
            {
                if (!_importedSymbols.ContainsKey(symbol.Name))
                {
                    _importedSymbols[symbol.Name] = new List<ImportedSymbolReference>();
                }
                _importedSymbols[symbol.Name].Add(new ImportedSymbolReference(
                    resolvedPath,
                    import.Path,
                    import.Line,
                    import.DiagnosticColumn,
                    import.DiagnosticLength));

                var globalScope = _scopes.GlobalScope();
                if (symbol.Declaration.Kind == "function")
                {
                    globalScope.Symbols[symbol.Name] = symbol.Type;
                }
                else
                {
                    globalScope.Types[symbol.Name] = symbol.Type;
                    _semanticModel.RecordType(symbol.Name, symbol.Type);
                    if (AnalyzerBindingFacts.IsTypeDeclarationKind(symbol.Declaration.Kind))
                    {
                        _typeDeclarationFiles[symbol.Name] = symbol.Declaration.File!;
                    }
                }

                globalScope.RecordDeclarationLocation(
                    symbol.Name,
                    symbol.Declaration.File,
                    symbol.Declaration.Line,
                    symbol.Declaration.Column,
                    symbol.Declaration.Kind);
                _bindingMap.RecordDeclaration(symbol.Declaration);
            }
        }
    }

    private string? ResolveFileImportPath(FileResolver resolver, string importPath, out string? errorMessage)
    {
        var resolvedPath = Path.GetFullPath(resolver.ResolveFilePath(importPath));
        if (_projectSources.ContainsSourceText(resolvedPath) || System.IO.File.Exists(resolvedPath))
        {
            errorMessage = null;
            return resolvedPath;
        }

        errorMessage = $"Imported file not found: {importPath} (resolved to {resolvedPath})";
        return null;
    }

    private void ProcessNamespaceImport(NamespaceImport import)
    {
        RegisterNamespaceImport(import.Namespace, import.Alias, import.Line, import.Column);
    }

    private void RegisterNamespaceImport(string namespaceName, string? alias, int line, int column)
    {
        var importDirective = new ImportDirective(namespaceName, alias, line, column);

        ProcessImportForAssemblyLoading(importDirective);

        if (!ValidateNamespaceImport(namespaceName, line, column))
        {
            return;
        }

        if (alias != null)
        {
            _usingAliases[alias] = namespaceName;
        }
        else if (!_usingNamespaces.Contains(namespaceName))
        {
            _usingNamespaces.Add(namespaceName);
        }
    }

    private bool ValidateNamespaceImport(string namespaceName, int line, int column)
    {
        var diagnosticColumn = FindNamespaceImportColumn(namespaceName, line, column);

        var importedType = _externalTypeProbe.ResolveExactExternalType(namespaceName);
        if (importedType != null)
        {
            var suggestion = !string.IsNullOrWhiteSpace(importedType.Namespace)
                ? $"Import '{importedType.Namespace}' instead."
                : "Import a namespace instead of a type name.";

            Error(
                ErrorCode.NamespaceNotFound,
                $"'{namespaceName}' is a type, not a namespace — you can only import namespaces",
                line,
                diagnosticColumn,
                suggestion,
                namespaceName.Length);
            return false;
        }

        if (NamespaceExists(namespaceName))
        {
            return true;
        }

        if (NamespaceMatchesReferencedPackage(namespaceName))
        {
            return true;
        }

        Error(
            ErrorCode.NamespaceNotFound,
            $"I can't find namespace '{namespaceName}' — check the spelling and make sure the assembly is referenced",
            line,
            diagnosticColumn,
            "Check the namespace spelling and project references.",
            namespaceName.Length);
        return false;
    }

    private int FindNamespaceImportColumn(string namespaceName, int line, int fallbackColumn)
    {
        string? sourceLine = null;

        sourceLine = GetSourceSnippet(line);
        if (sourceLine == null && !string.IsNullOrWhiteSpace(_currentFilePath) && File.Exists(_currentFilePath))
        {
            sourceLine = File.ReadLines(_currentFilePath).Skip(line - 1).FirstOrDefault();
        }

        if (string.IsNullOrEmpty(sourceLine))
        {
            return fallbackColumn;
        }

        var importIndex = sourceLine.IndexOf("import", StringComparison.Ordinal);
        var searchStart = importIndex >= 0 ? importIndex + "import".Length : 0;
        var namespaceIndex = sourceLine.IndexOf(namespaceName, searchStart, StringComparison.Ordinal);
        return namespaceIndex >= 0 ? namespaceIndex + 1 : fallbackColumn;
    }

    private bool NamespaceExists(string namespaceName)
    {
        if (_projectSources.ProjectNamespaceExists(namespaceName))
        {
            _externalNamespaceCache[namespaceName] = true;
            return true;
        }

        if (_externalNamespaceCache.TryGetValue(namespaceName, out var exists))
        {
            return exists;
        }

        foreach (var assembly in GetExternalSearchAssemblies())
        {
            IEnumerable<Type> exportedTypes;
                exportedTypes = assembly.GetExportedTypes();

            if (exportedTypes.Any(t => string.Equals(t.Namespace, namespaceName, StringComparison.Ordinal)))
            {
                _externalNamespaceCache[namespaceName] = true;
                return true;
            }
        }

        _externalNamespaceCache[namespaceName] = false;
        return false;
    }

    private bool NamespaceMatchesReferencedPackage(string namespaceName)
    {
        if (namespaceName.Count(c => c == '.') < 1)
        {
            return false;
        }

        return _referencedPackageNames.Any(packageName =>
            string.Equals(packageName, namespaceName, StringComparison.Ordinal) ||
            packageName.StartsWith(namespaceName + ".", StringComparison.Ordinal));
    }

    private static string? GetUnitNamespace(CompilationUnit? unit)
        => AnalyzerProjectSourceProvider.UnitNamespace(unit);

    private bool IsCrossPackageFile(string? declarationFile)
    {
        if (string.IsNullOrWhiteSpace(declarationFile) || string.IsNullOrWhiteSpace(_currentFilePath))
        {
            return false;
        }

        var currentPath = Path.GetFullPath(_currentFilePath);
        var declarationPath = Path.GetFullPath(declarationFile);
        if (string.Equals(currentPath, declarationPath, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var currentNamespace = GetUnitNamespace(_compilationUnit) ?? _projectSources.GetNamespaceForFile(currentPath);
        var declarationNamespace = _projectSources.GetNamespaceForFile(declarationPath);
        return !string.Equals(currentNamespace, declarationNamespace, StringComparison.Ordinal);
    }

    private IEnumerable<Assembly> GetExternalSearchAssemblies()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var assembly in _mlcAssemblies)
        {
            var assemblyName = assembly.FullName ?? assembly.GetName().Name;
            if (!string.IsNullOrEmpty(assemblyName) && seen.Add(assemblyName))
            {
                yield return assembly;
            }
        }
    }

    private List<ImportedSymbolInfo> ExtractPublicSymbols(CompilationUnit unit, string filePath, string? sourceText)
    {
        var symbols = new List<ImportedSymbolInfo>();

        foreach (var decl in unit.Declarations)
        {
            var name = DeclarationFacts.GetDeclarationName(decl);

            if (name != null && DeclarationFacts.IsExportedDeclaration(decl, name))
            {
                var typeInfo = AnalyzerProjectTypeDiscovery.IsTopLevelTypeDeclaration(decl)
                    ? _declarationContext.ResolveDeclarationType(decl, filePath)
                    : decl is FunctionDeclaration function
                        ? _functionTypeFactory.CreateFromDeclarationInFile(function, filePath)
                        : null;

                if (typeInfo != null)
                {
                    symbols.Add(new ImportedSymbolInfo(
                        name,
                        typeInfo,
                        new SymbolDeclaration(
                            name,
                            filePath,
                            decl.Line,
                            AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(sourceText, name, decl.Line, decl.Column),
                            DeclarationFacts.GetDeclarationKind(decl))));
                }
            }
        }

        return symbols;
    }

    private void CheckImportCollisions()
    {
        foreach (var (symbol, imports) in _importedSymbols)
        {
            if (imports.Count <= 1)
                continue;

            var duplicate = imports[1];
            var importList = FormatImportCollisionSources(imports);
            var message = $"Imported symbol '{symbol}' is defined by multiple file imports";
            var suggestion = $"Add an alias to one import, such as `import \"{duplicate.ImportPath}\" as Alias`, and qualify the symbol.";
            var humanExplanation = $"The symbol '{symbol}' is imported more than once, so N# cannot choose which definition to use.";
            var contextualHint =
                $"N# found '{symbol}' in these file imports: {importList}.\n" +
                "Unaliased file imports place their exported symbols directly in scope. Use an alias on one import to make the reference explicit.";

            var sourceSnippet = GetSourceSnippet(duplicate.Line);
            _errors.Add(AnalyzerDiagnostics.CreateImportCollision(
                message,
                _currentFilePath,
                duplicate.SourcePath,
                duplicate.Line,
                duplicate.Column,
                sourceSnippet,
                duplicate.Length,
                suggestion,
                humanExplanation,
                contextualHint));
        }
    }

    private static string FormatImportCollisionSources(IEnumerable<ImportedSymbolReference> imports)
        => string.Join(", ", imports
            .Select(import => $"\"{import.ImportPath}\"")
            .Distinct(StringComparer.OrdinalIgnoreCase));

    /// <summary>
    /// Load a .NET assembly by file path for type resolution (metadata-only via MLC)
    /// </summary>
    public void LoadReferencedAssembly(string assemblyPath)
    {
        if (_mlc == null) return;
        {
            var fullPath = Path.GetFullPath(assemblyPath);
            _metadataResolver?.AddSearchDirectory(Path.GetDirectoryName(fullPath)!);

            if (IsMetadataAssemblyPathAlreadyLoaded(fullPath))
            {
                return;
            }

            AssemblyName assemblyName;
            {
                assemblyName = AssemblyName.GetAssemblyName(fullPath);
            }

            if (IsMetadataAssemblyAlreadyLoaded(assemblyName))
            {
                return;
            }

            var alreadyLoaded = _mlc.GetAssemblies().FirstOrDefault(loadedAssembly =>
                AssemblyName.ReferenceMatchesDefinition(loadedAssembly.GetName(), assemblyName));
            if (alreadyLoaded != null)
            {
                RegisterMetadataAssembly(alreadyLoaded);
                return;
            }

            var assembly = _mlc.LoadFromAssemblyPath(fullPath);
            RegisterMetadataAssembly(assembly);
        }
    }

    /// <summary>
    /// Load a .NET assembly by name (e.g., "System.Runtime") for type resolution (metadata-only via MLC)
    /// </summary>
    public void LoadReferencedAssemblyByName(string assemblyName)
    {
        if (_mlc == null) return;
            if (IsMetadataAssemblyAlreadyLoaded(assemblyName))
            {
                return;
            }

            var assembly = _mlc.LoadFromAssemblyName(assemblyName);
            RegisterMetadataAssembly(assembly);
    }

    private void RegisterMetadataAssembly(Assembly assembly)
    {
        if (_mlcAssemblies.Any(loadedAssembly =>
        {
                return AssemblyName.ReferenceMatchesDefinition(loadedAssembly.GetName(), assembly.GetName());
        }))
        {
            return;
        }

        _mlcAssemblies.Add(assembly);
    }

    private bool IsMetadataAssemblyAlreadyLoaded(AssemblyName assemblyName)
    {
        return _mlcAssemblies.Any(loadedAssembly =>
        {
                return AssemblyName.ReferenceMatchesDefinition(loadedAssembly.GetName(), assemblyName);
        });
    }

    private bool IsMetadataAssemblyAlreadyLoaded(string assemblyName)
    {
        return _mlcAssemblies.Any(loadedAssembly =>
        {
                return string.Equals(loadedAssembly.GetName().Name, assemblyName, StringComparison.OrdinalIgnoreCase);
        });
    }

    private bool IsMetadataAssemblyPathAlreadyLoaded(string assemblyPath)
    {
        var normalizedPath = Path.GetFullPath(assemblyPath);
        return _mlcAssemblies.Any(loadedAssembly =>
        {
                return string.Equals(
                    Path.GetFullPath(loadedAssembly.Location),
                    normalizedPath,
                    StringComparison.OrdinalIgnoreCase);
        });
    }

    /// <summary>
    /// Load system assemblies that are commonly used (initializes MetadataLoadContext)
    /// </summary>
    public void LoadSystemAssemblies()
    {
        _metadataResolver = new NSharpMetadataResolver();

        var runtimeDir = RuntimeEnvironment.GetRuntimeDirectory();
        _metadataResolver.AddSearchDirectory(runtimeDir);
        _metadataResolver.AddSearchDirectory(AppContext.BaseDirectory);

        var searchDir = runtimeDir;
        for (int i = 0; i < 5; i++)
        {
            searchDir = Path.GetDirectoryName(searchDir);
            if (searchDir == null) break;
            if (Path.GetFileName(searchDir) == "shared")
            {
                foreach (var fwDir in new[] { "Microsoft.AspNetCore.App", "Microsoft.NETCore.App" })
                {
                    var fwPath = Path.Combine(searchDir, fwDir);
                    if (!Directory.Exists(fwPath)) continue;
                    foreach (var versionDir in Directory.GetDirectories(fwPath)
                                 .OrderByDescending(Path.GetFileName, NuGetVersionComparer.Instance))
                        _metadataResolver.AddSearchDirectory(versionDir);
                }
                break;
            }
        }

        _mlc = new MetadataLoadContext(_metadataResolver, "System.Runtime");

        var commonAssemblies = new[]
        {
            "System.Runtime",
            "System.Console",
            "System.Collections",
            "System.Linq",
            "System.Linq.Queryable",
            "System.Net.Http",
            "System.Text.Json",
            "System.Threading",
            "System.Threading.Tasks",
            "System.IO.FileSystem",
            "System.Text.RegularExpressions",
            "System.ComponentModel.Annotations",
            "System.Collections.Concurrent",
            "System.Diagnostics.Debug",
            "System.Diagnostics.Process",
            "System.Runtime.InteropServices",
            "System.ObjectModel",
            "System.Linq.Expressions",
            "System.Memory",
            "System.IO.Pipes",
            "System.Net.Primitives",
            "System.Net.Sockets",
            "System.Security.Cryptography",
            "System.Text.Encoding.Extensions",
            "System.Xml.ReaderWriter",
            "System.Private.CoreLib"
        };

        foreach (var assemblyName in commonAssemblies)
        {
            LoadReferencedAssemblyByName(assemblyName);
        }

        _wellKnownTypes = new AnalyzerWellKnownTypes(
            _mlc,
            _mlc.CoreAssembly ?? throw new InvalidOperationException("MLC core assembly not loaded"));
        _clrTypeConversion = new AnalyzerClrTypeConversion(_declarationContext, _wellKnownTypes);
        _assignabilityFacts = new AnalyzerAssignabilityFacts(_declarationContext, _wellKnownTypes);
        _assignability = CreateAssignability();
        _extensionMethodResolution = CreateExtensionMethodResolution();
        _overloadScoring = CreateOverloadScoring();
        _reflectionArgumentBinder = CreateReflectionArgumentBinder();
        _syntheticCallBinder = CreateSyntheticCallBinder();
        _syntheticCallWalk = CreateSyntheticCallWalk();
        _syntheticCallValidator = CreateSyntheticCallValidator();
        _reflectionCallReporter = CreateReflectionCallReporter();
        _typeResolver.SetWellKnownTypes(_wellKnownTypes);
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            _mlc?.Dispose();
            _mlc = null;
            _wellKnownTypes = null;
            _clrTypeConversion = new AnalyzerClrTypeConversion(_declarationContext, null);
            _assignabilityFacts = new AnalyzerAssignabilityFacts(_declarationContext, null);
            _assignability = CreateAssignability();
            _extensionMethodResolution = CreateExtensionMethodResolution();
            _overloadScoring = CreateOverloadScoring();
            _reflectionArgumentBinder = CreateReflectionArgumentBinder();
            _syntheticCallBinder = CreateSyntheticCallBinder();
            _syntheticCallWalk = CreateSyntheticCallWalk();
            _syntheticCallValidator = CreateSyntheticCallValidator();
            _reflectionCallReporter = CreateReflectionCallReporter();
            _typeResolver.SetWellKnownTypes(null);
            _mlcAssemblies.Clear();
            _disposed = true;
        }
    }

    /// <summary>
    /// Load assemblies from project configuration (References and Dependencies)
    /// </summary>
    public void LoadFromProjectConfig(ProjectConfig config, string? projectDirectory = null)
    {
        projectDirectory ??= Environment.CurrentDirectory;

        foreach (var (packageName, packageVersion) in GetRestoredPackageVersions(projectDirectory))
        {
            _metadataResolver?.PinPackageVersion(packageName, packageVersion);
        }

        if (config.Dependencies != null && config.Dependencies.Count > 0)
        {
            foreach (var reference in config.Dependencies.Where(r => r.Type != ReferenceType.NuGet))
            {
                LoadProjectReference(reference, projectDirectory, config.TargetFramework);
            }

            foreach (var reference in config.Dependencies.Where(r => r.Type == ReferenceType.NuGet))
            {
                if (!string.IsNullOrWhiteSpace(reference.Nuget))
                {
                    _referencedPackageNames.Add(reference.Nuget);
                }

                LoadProjectReference(reference, projectDirectory, config.TargetFramework);
            }
        }

        if (config.TestDependencies != null && config.TestDependencies.Count > 0)
        {
            foreach (var dependency in config.TestDependencies.Where(r => r.Type == ReferenceType.NuGet))
            {
                if (!string.IsNullOrWhiteSpace(dependency.Nuget))
                {
                    _referencedPackageNames.Add(dependency.Nuget);
                }

                if (dependency.Nuget != null)
                {
                    try
                    {
                        LoadReferencedAssemblyByName(dependency.Nuget);
                    }
                    catch (FileNotFoundException)
                    {
                    }
                }
            }
        }

        if (config.Sdk?.Contains("Web") == true)
        {
            var aspNetAssemblies = new[]
            {
                "Microsoft.AspNetCore",
                "Microsoft.AspNetCore.Http",
                "Microsoft.AspNetCore.Http.Abstractions",
                "Microsoft.AspNetCore.Mvc.Core",
                "Microsoft.AspNetCore.Mvc.Abstractions",
                "Microsoft.AspNetCore.Routing",
                "Microsoft.Extensions.DependencyInjection",
                "Microsoft.Extensions.DependencyInjection.Abstractions"
            };

            foreach (var assembly in aspNetAssemblies)
            {
                LoadReferencedAssemblyByName(assembly);
            }
        }
    }

    /// <summary>
    /// Load a single project reference based on its type
    /// </summary>
    private void LoadProjectReference(Reference reference, string projectDirectory, string targetFramework)
    {
        switch (reference.Type)
        {
            case ReferenceType.NuGet:
                LoadNuGetPackage(reference.Nuget!, reference.Version, targetFramework, projectDirectory);
                break;

            case ReferenceType.Dll:
                var dllPath = Path.IsPathRooted(reference.Dll!)
                    ? reference.Dll!
                    : Path.Combine(projectDirectory, reference.Dll!);
                LoadReferencedAssembly(dllPath);
                break;

            case ReferenceType.Project:
                var projectPath = Path.IsPathRooted(reference.Project!)
                    ? reference.Project!
                    : Path.Combine(projectDirectory, reference.Project!);
                LoadProjectReferenceFile(projectPath, targetFramework);
                break;

            case ReferenceType.Framework:
                break;
        }
    }

    /// <summary>
    /// Load a NuGet package assembly
    /// </summary>
    private void LoadNuGetPackage(string packageName, string? version, string targetFramework, string projectDirectory)
    {

        var binPath = Path.Combine(projectDirectory, "bin", "Debug", targetFramework, $"{packageName}.dll");
        if (File.Exists(binPath))
        {
            LoadReferencedAssembly(binPath);
            return;
        }

        version ??= TryGetRestoredPackageVersion(projectDirectory, packageName);

        var nugetCache = Path.Combine(GetNuGetPackagesRoot(), packageName.ToLowerInvariant());

        if (Directory.Exists(nugetCache))
        {
            var versionDir = version != null
                ? Path.Combine(nugetCache, version)
                : NuGetVersionOrder.PickHighestVersionDirectory(Directory.GetDirectories(nugetCache));

            if (versionDir != null && Directory.Exists(versionDir))
            {
                var possiblePaths = new[]
                {
                    Path.Combine(versionDir, "lib", targetFramework, $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "net10.0", $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "net9.0", $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "net8.0", $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "netstandard2.1", $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "netstandard2.0", $"{packageName}.dll")
                };

                foreach (var path in possiblePaths)
                {
                    if (File.Exists(path))
                    {
                        LoadReferencedAssembly(path);
                        return;
                    }
                }
            }
        }

    }

    private string? TryGetRestoredPackageVersion(string projectDirectory, string packageName)
        => GetRestoredPackageVersions(projectDirectory).TryGetValue(packageName, out var version)
            ? version
            : null;

    /// <summary>
    /// Reads the package versions the project restored from <c>obj/project.assets.json</c>,
    /// keyed by package name. Returns an empty map when the project has no restore output.
    /// </summary>
    private IReadOnlyDictionary<string, string> GetRestoredPackageVersions(string projectDirectory)
    {
        if (_restoredPackageVersionsByProject.TryGetValue(projectDirectory, out var cached))
        {
            return cached;
        }

        var versions = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var assetsPath = Path.Combine(projectDirectory, "obj", "project.assets.json");
        if (File.Exists(assetsPath))
        {
            try
            {
                using var assets = JsonDocument.Parse(File.ReadAllText(assetsPath));
                if (assets.RootElement.TryGetProperty("libraries", out var libraries) &&
                    libraries.ValueKind == JsonValueKind.Object)
                {
                    foreach (var library in libraries.EnumerateObject())
                    {
                        var separator = library.Name.IndexOf('/');
                        if (separator > 0 && separator < library.Name.Length - 1)
                        {
                            versions[library.Name[..separator]] = library.Name[(separator + 1)..];
                        }
                    }
                }
            }
            catch (IOException)
            {
            }
            catch (JsonException)
            {
            }
        }

        _restoredPackageVersionsByProject[projectDirectory] = versions;
        return versions;
    }

    /// <summary>
    /// Load a project reference (either .csproj or project.yml)
    /// </summary>
    private void LoadProjectReferenceFile(string projectPath, string targetFramework)
    {
        var projectDir = Path.GetDirectoryName(projectPath)!;

        if (projectPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
        {
            var projectName = Path.GetFileNameWithoutExtension(projectPath);
            var outputPath = Path.Combine(projectDir, "bin", "Debug", targetFramework, $"{projectName}.dll");

            {
                LoadReferencedAssembly(outputPath);
            }
        }
        else if (projectPath.EndsWith(".yml", StringComparison.OrdinalIgnoreCase))
        {
            var nsharpProject = ProjectFileParser.Parse(projectPath);
            var outputPath = Path.Combine(projectDir, "bin", "Debug", targetFramework, $"{nsharpProject.EffectiveName}.dll");

            {
                LoadReferencedAssembly(outputPath);
            }
        }
        else
        {
            Console.Error.WriteLine($"Warning: Unknown project reference type: {projectPath}");
        }
    }

    /// <summary>
    /// Process an import directive and attempt to load the corresponding assembly
    /// </summary>
    public void ProcessImportForAssemblyLoading(ImportDirective import)
    {
        var assemblyMappings = new Dictionary<string, string[]>
        {
            ["System"] = new[] { "System.Runtime" },
            ["System.Collections.Generic"] = new[] { "System.Collections" },
            ["System.Collections"] = new[] { "System.Collections" },
            ["System.Threading.Tasks"] = new[] { "System.Runtime" },
            ["System.Linq"] = new[] { "System.Linq" },
            ["System.IO"] = new[] { "System.Runtime" },
            ["System.Text"] = new[] { "System.Runtime" },
            ["System.Net.Http"] = new[] { "System.Net.Http" },
            ["System.Text.Json"] = new[] { "System.Text.Json" },
            ["System.ComponentModel.DataAnnotations"] = new[] { "System.ComponentModel.Annotations" },
            ["Microsoft.AspNetCore.Builder"] = new[] { "Microsoft.AspNetCore", "Microsoft.AspNetCore.Http.Abstractions" },
            ["Microsoft.AspNetCore.Mvc"] = new[] { "Microsoft.AspNetCore.Mvc.Core", "Microsoft.AspNetCore.Mvc.Abstractions" },
            ["Microsoft.AspNetCore.Http"] = new[] { "Microsoft.AspNetCore.Http", "Microsoft.AspNetCore.Http.Abstractions" },
            ["Microsoft.Extensions.DependencyInjection"] = new[] { "Microsoft.Extensions.DependencyInjection.Abstractions", "Microsoft.Extensions.DependencyInjection" },
            ["Microsoft.Extensions.Hosting"] = new[] { "Microsoft.Extensions.Hosting.Abstractions", "Microsoft.Extensions.Hosting" },
            ["Microsoft.EntityFrameworkCore"] = new[] { "Microsoft.EntityFrameworkCore", "Microsoft.EntityFrameworkCore.Abstractions" }
        };

        if (assemblyMappings.TryGetValue(import.Namespace, out var assemblies))
        {
            foreach (var assemblyName in assemblies)
            {
                LoadReferencedAssemblyByName(assemblyName);
            }
        }
    }


    /// <summary>
    /// Custom MetadataAssemblyResolver that dynamically searches directories for assemblies.
    /// Replaces the old AppDomain.AssemblyResolve-based AssemblyResolver.
    /// </summary>
    internal sealed class NSharpMetadataResolver : MetadataAssemblyResolver
    {
        private static readonly string[] Tfms = { "net10.0", "net9.0", "net8.0", "net7.0", "net6.0", "netstandard2.1", "netstandard2.0" };

        private readonly List<string> _searchDirectories = new();
        private readonly Dictionary<string, string> _pinnedPackageVersions = new(StringComparer.OrdinalIgnoreCase);

        internal Dictionary<string, string> LoadFailures { get; } = new(StringComparer.Ordinal);

        private void RecordLoadFailure(string path, Exception exception)
        {
            if (!LoadFailures.ContainsKey(path))
                LoadFailures[path] = $"{exception.GetType().Name}: {exception.Message}";
        }

        public void AddSearchDirectory(string directory)
        {
            if (!string.IsNullOrEmpty(directory) && Directory.Exists(directory) && !_searchDirectories.Contains(directory))
                _searchDirectories.Add(directory);
        }

        /// <summary>
        /// Records the package version a project restored. NuGet-cache fallback scans bind
        /// the pinned version instead of the highest extracted one.
        /// </summary>
        public void PinPackageVersion(string packageName, string version)
        {
            _pinnedPackageVersions[packageName] = version;
        }

        public override Assembly? Resolve(MetadataLoadContext context, AssemblyName assemblyName)
        {
            var simpleName = assemblyName.Name;
            if (simpleName == null) return null;

            foreach (var loadedAssembly in context.GetAssemblies())
            {
                if (string.Equals(loadedAssembly.GetName().Name, simpleName, StringComparison.OrdinalIgnoreCase))
                    return loadedAssembly;
            }

            foreach (var dir in _searchDirectories)
            {
                var dllPath = Path.Combine(dir, $"{simpleName}.dll");
                if (File.Exists(dllPath))
                {
                    try { return context.LoadFromAssemblyPath(dllPath); }
                    catch (Exception ex)
                    {
                        RecordLoadFailure(dllPath, ex);
                        continue;
                    }
                }
            }

            var nugetRoot = Analyzer.GetNuGetPackagesRoot();

            var nugetExact = Path.Combine(nugetRoot, simpleName.ToLowerInvariant());
            var found = TryLoadFromNuGetPackageDir(context, nugetExact, simpleName);
            if (found != null) return found;

            if (Directory.Exists(nugetRoot))
            {
                    var prefix = simpleName.ToLowerInvariant();
                    foreach (var pkgDir in Directory.GetDirectories(nugetRoot))
                    {
                        var dirName = Path.GetFileName(pkgDir);
                        if (dirName != null && dirName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                        {
                            var result = TryLoadFromNuGetPackageDir(context, pkgDir, simpleName);
                            if (result != null) return result;
                        }
                    }
            }

            return null;
        }

        private Assembly? TryLoadFromNuGetPackageDir(MetadataLoadContext context, string packageDir, string simpleName)
        {
            if (!Directory.Exists(packageDir)) return null;

            var versionDir = PickPackageVersionDirectory(packageDir);
            if (versionDir == null) return null;

            foreach (var tfm in Tfms)
            {
                var dllPath = Path.Combine(versionDir, "lib", tfm, $"{simpleName}.dll");
                if (File.Exists(dllPath))
                {
                    try { return context.LoadFromAssemblyPath(dllPath); }
                    catch (Exception ex)
                    {
                        RecordLoadFailure(dllPath, ex);
                        continue;
                    }
                }
            }
            return null;
        }

        private string? PickPackageVersionDirectory(string packageDir)
        {
            var packageName = Path.GetFileName(packageDir);
            if (packageName != null &&
                _pinnedPackageVersions.TryGetValue(packageName, out var pinnedVersion))
            {
                var pinnedDir = Path.Combine(packageDir, pinnedVersion);
                if (Directory.Exists(pinnedDir))
                    return pinnedDir;
            }

            return NuGetVersionOrder.PickHighestVersionDirectory(Directory.GetDirectories(packageDir));
        }
    }

    /// <summary>
    /// Orders NuGet package version folder names by SemVer precedence: numeric parts compare
    /// numerically and a release outranks its prereleases — unlike ordinal string ordering,
    /// which ranks "0.1.0-beta" above "0.1.0" and "0.10.0" below "0.9.0".
    /// </summary>
    internal static class NuGetVersionOrder
    {
        public static string? PickHighestVersionDirectory(string[] versionDirectories)
            => versionDirectories
                .OrderByDescending(Path.GetFileName, NuGetVersionComparer.Instance)
                .FirstOrDefault();
    }

    internal sealed class NuGetVersionComparer : IComparer<string?>
    {
        public static readonly NuGetVersionComparer Instance = new();

        public int Compare(string? x, string? y)
        {
            if (ReferenceEquals(x, y)) return 0;
            if (x == null) return -1;
            if (y == null) return 1;

            var parsedX = TryParse(x, out var numbersX, out var prereleaseX);
            var parsedY = TryParse(y, out var numbersY, out var prereleaseY);
            if (!parsedX || !parsedY)
            {
                return parsedX == parsedY ? string.CompareOrdinal(x, y) : (parsedX ? 1 : -1);
            }

            for (var i = 0; i < numbersX.Length; i++)
            {
                var byNumber = numbersX[i].CompareTo(numbersY[i]);
                if (byNumber != 0) return byNumber;
            }

            if (prereleaseX.Length == 0) return prereleaseY.Length == 0 ? 0 : 1;
            if (prereleaseY.Length == 0) return -1;
            return ComparePrereleaseIdentifiers(prereleaseX, prereleaseY);
        }

        private static bool TryParse(string version, out long[] numbers, out string prerelease)
        {
            numbers = new long[4];
            prerelease = string.Empty;

            var metadataStart = version.IndexOf('+');
            if (metadataStart >= 0)
                version = version[..metadataStart];

            var prereleaseStart = version.IndexOf('-');
            if (prereleaseStart >= 0)
            {
                prerelease = version[(prereleaseStart + 1)..];
                version = version[..prereleaseStart];
            }

            var parts = version.Split('.');
            if (parts.Length is < 1 or > 4) return false;

            for (var i = 0; i < parts.Length; i++)
            {
                if (!long.TryParse(parts[i], NumberStyles.None, CultureInfo.InvariantCulture, out numbers[i]))
                    return false;
            }

            return true;
        }

        private static int ComparePrereleaseIdentifiers(string x, string y)
        {
            var identifiersX = x.Split('.');
            var identifiersY = y.Split('.');
            for (var i = 0; i < Math.Max(identifiersX.Length, identifiersY.Length); i++)
            {
                if (i >= identifiersX.Length) return -1;
                if (i >= identifiersY.Length) return 1;

                var numericX = long.TryParse(identifiersX[i], NumberStyles.None, CultureInfo.InvariantCulture, out var numberX);
                var numericY = long.TryParse(identifiersY[i], NumberStyles.None, CultureInfo.InvariantCulture, out var numberY);
                if (numericX && numericY)
                {
                    var byNumber = numberX.CompareTo(numberY);
                    if (byNumber != 0) return byNumber;
                }
                else if (numericX != numericY)
                {
                    return numericX ? -1 : 1;
                }
                else
                {
                    var byText = string.CompareOrdinal(identifiersX[i], identifiersY[i]);
                    if (byText != 0) return byText;
                }
            }

            return 0;
        }
    }
}


