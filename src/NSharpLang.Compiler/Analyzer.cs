using System;
using System.Buffers;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;

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

    private sealed record FlowNarrowing(string Path, TypeInfo? NarrowedType, NullState? NullState);

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

    private readonly List<CompilerError> _errors = new();
    private readonly Stack<Scope> _scopes = new();
    private readonly List<string> _usingNamespaces = new();
    private readonly Dictionary<string, string> _usingAliases = new(); // alias -> fullName
    private readonly Dictionary<string, List<ImportedSymbolReference>> _importedSymbols = new(); // symbol -> import references
    private readonly Dictionary<string, Dictionary<string, TypeInfo>> _importedSymbolsByAlias = new(); // alias -> (symbol -> TypeInfo)
    private readonly Dictionary<string, Dictionary<string, SymbolDeclaration>> _importedDeclarationsByAlias = new(); // alias -> (symbol -> declaration)
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
    private string? _projectRoot;
    private CompilationUnit? _compilationUnit; // Current file's AST (for namespace checks)
    private TypeInfo? _currentExpectedType;  // For target-typed expressions
    private string? _sourceText;
    private string[]? _sourceLines;  // Source code lines for error snippets
    // MetadataLoadContext-based assembly inspection (no runtime loading, no version conflicts)
    private NSharpMetadataResolver? _metadataResolver;
    private MetadataLoadContext? _mlc;
    private WellKnownTypes? _wellKnownTypes;
    private readonly List<Assembly> _mlcAssemblies = new();

    // Reference assemblies that failed to load or be inspected, keyed by identity (file path
    // or assembly name) → first failure detail. Surfaced as NL923 warnings whenever analysis
    // also produced unresolved-type errors, so a broken reference can't silently masquerade
    // as a plain "type not found".
    private readonly Dictionary<string, string> _referenceLoadFailures = new(StringComparer.Ordinal);

    // Opt-in flag: report unresolved simple type names (NL201) at declared-type positions.
    // Set only by ResolveDeclaredType — pass-1 signature collection and lazy cross-file
    // member resolution run without generic type parameters in scope and must stay lenient.
    private bool _reportUnresolvedTypes;
    private readonly HashSet<(string Name, int Line, int Column)> _reportedUnresolvedTypeRefs = new();
    private readonly HashSet<(string Name, int Line, int Column)> _reportedSoaRowTypeRefs = new();
    private readonly HashSet<string> _referencedPackageNames = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Type> _externalTypeCache = new(); // Cache for external type lookups
    private readonly Dictionary<string, bool> _externalNamespaceCache = new(); // Cache for namespace existence checks
    private readonly Dictionary<string, HashSet<string>> _projectNamespaceCache = new(); // project root -> declared namespaces/packages
    private readonly Dictionary<string, string?> _projectFileNamespaceCache = new(StringComparer.OrdinalIgnoreCase); // file path -> declared namespace/package
    private readonly Dictionary<string, string> _typeDeclarationFiles = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _projectSourceTexts = new(StringComparer.OrdinalIgnoreCase);
    private SemanticModel _semanticModel = new(); // Semantic model for IDE features
    private BindingMap _bindingMap = new(); // Binding map for semantic references
    private readonly HashSet<MemberAccessExpression> _soaColumnMemberAccesses = new(ReferenceEqualityComparer.Instance);
    private readonly Stack<int> _semanticScopeIds = new(); // Parallel scope ID stack for SemanticModel
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
    private readonly HashSet<(int Line, int Column, string Name)> _reportedCallableReferenceDiagnostics = new();
    private bool _disposed;

    // Project-level auto-discovered symbols (set once by MultiFileCompiler, persists across Analyze calls)
    private Dictionary<string, List<ProjectSymbolInfo>> _projectSymbols = new();
    private readonly HashSet<string> _autoResolvedNamespaces = new(); // Namespaces used via auto-resolution

    /// <summary>
    /// Set project-level symbols for auto-discovery across files.
    /// Called once by MultiFileCompiler after parsing all files.
    /// These symbols persist across Analyze() calls.
    /// </summary>
    public void SetProjectSymbols(Dictionary<string, List<ProjectSymbolInfo>> symbols)
    {
        _projectSymbols = symbols;
    }

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
        _projectSourceTexts.Clear();
        foreach (var (path, text) in sourceTexts)
        {
            _projectSourceTexts[Path.GetFullPath(path)] = text;
        }
    }

    /// <summary>
    /// Get the set of namespaces that were auto-resolved during the most recent Analyze() call.
    /// </summary>
    public HashSet<string> GetAutoResolvedNamespaces() => new(_autoResolvedNamespaces);

    /// <summary>
    /// Get a snapshot of the type-declaration-to-file mapping recorded during the most recent Analyze() call.
    /// Used by MultiFileCompiler to build the project-level ProjectIndex.
    /// </summary>
    public Dictionary<string, string> GetTypeDeclarationFiles() => new(_typeDeclarationFiles);

    public AnalysisResult Analyze(CompilationUnit unit)
    {
        return Analyze(unit, null, null, null);
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
        _extensionMethods.Clear();
        _semanticModel = new SemanticModel();  // Reset semantic model for new analysis
        _bindingMap = new BindingMap(); // Reset binding map for new analysis
        _soaColumnMemberAccesses.Clear();
        _semanticScopeIds.Clear();
        _currentLine = 0;
        _suppressNullabilityFlowType = false;
        _suppressErrorTupleResultUse = false;
        _reportedNullabilityDiagnostics.Clear();
        _reportedUnverifiedErrorResultDiagnostics.Clear();
        _reportedUnresolvedTypeRefs.Clear();
        _reportedSoaRowTypeRefs.Clear();
        _reportUnresolvedTypes = false;
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
        _projectRoot = projectRoot;
        _compilationUnit = unit;
        _sourceText = sourceCode;
        _sourceLines = sourceCode?.Split('\n');
        _externalNamespaceCache.Clear();
        _projectNamespaceCache.Clear();
        _projectFileNamespaceCache.Clear();
        _typeDeclarationFiles.Clear();
        _autoResolvedNamespaces.Clear(); // Reset per-file; _projectSymbols persists

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
                DeclareType(classDecl.Name, new ClassTypeInfo(classDecl), decl.Line, decl.Column);
            else if (decl is StructDeclaration structDecl)
                DeclareType(structDecl.Name, new StructTypeInfo(structDecl), decl.Line, decl.Column);
            else if (decl is RecordDeclaration recordDecl)
                DeclareType(recordDecl.Name, new RecordTypeInfo(recordDecl), decl.Line, decl.Column);
            else if (decl is SoaRecordDeclaration soaRecordDecl)
                DeclareType(soaRecordDecl.Name, new SoaRecordTypeInfo(soaRecordDecl), decl.Line, decl.Column);
            else if (decl is InterfaceDeclaration interfaceDecl)
                DeclareType(interfaceDecl.Name, new InterfaceTypeInfo(interfaceDecl), decl.Line, decl.Column);
            else if (decl is UnionDeclaration unionDecl)
                DeclareType(unionDecl.Name, new UnionTypeInfo(unionDecl), decl.Line, decl.Column);
            else if (decl is EnumDeclaration enumDecl)
                DeclareType(enumDecl.Name, new EnumTypeInfo(enumDecl), decl.Line, decl.Column);
            else if (decl is TypeAliasDeclaration aliasDecl)
                DeclareType(aliasDecl.Name, new AliasTypeInfo(aliasDecl.Type), decl.Line, decl.Column);
            else if (decl is NewtypeDeclaration newtypeDecl)
                DeclareType(newtypeDecl.Name, new NewtypeInfo(newtypeDecl.Name, newtypeDecl.UnderlyingType), decl.Line, decl.Column);
            else if (decl is FunctionDeclaration func)
            {
                // Add function signatures to enable forward references
                var funcTypeInfo = CreateFunctionTypeInfo(func);
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

        // Set end line for global scope (use source line count or last declaration)
        if (_sourceLines != null)
            _currentLine = _sourceLines.Length;

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

    /// <summary>
    /// Records a reference assembly that failed to load or be inspected. Internal so tests
    /// can exercise the NL923 surfacing contract without fabricating corrupt binaries.
    /// </summary>
    internal void RecordReferenceLoadFailure(string identity, Exception exception)
    {
        if (!_referenceLoadFailures.ContainsKey(identity))
            _referenceLoadFailures[identity] = $"{exception.GetType().Name}: {exception.Message}";
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
                ResolveDeclaredType(aliasDecl.Type);
                break;
            case NewtypeDeclaration newtypeDecl:
                ResolveDeclaredType(newtypeDecl.UnderlyingType);
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

    private enum AttributeArgumentConstantKind
    {
        Null,
        Bool,
        Integer,
        Floating,
        Char,
        String,
        Type,
        Enum,
        Array,
        UnknownStaticMember
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
                ReportAttributeTypeMustDeriveFromAttribute(attribute, FormatReflectionTypeName(nonAttributeType));
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
                ReportSoaRowTypeReferenceIfNeeded(simple.Name, simple.Line, simple.Column);
                break;
            case GenericTypeReference generic:
                ReportSoaRowTypeReferenceIfNeeded(generic.Name, generic.Line, generic.Column);
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

        ReportUnsupportedAttributeOperator(unary, GetUnaryOperatorText(unary.Operator));
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
            ReportUnsupportedAttributeOperator(binary, GetBinaryOperatorText(binary.Operator));
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

        ReportUnsupportedAttributeOperator(binary, GetBinaryOperatorText(binary.Operator));
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

        var resolvedType = ResolveTypeAlias(LookupType(containerName) ?? BuiltInTypes.Unknown);
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

        if (TryResolveBuiltInTypeKeyword(containerName) is { } builtInType)
        {
            return TryValidateAttributeRuntimeStaticMemberAccess(
                new ReflectionTypeInfo(builtInType),
                builtInType,
                memberAccess,
                out kind);
        }

        if (TryResolveExternalType(containerName) is ReflectionTypeInfo reflectionType)
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
            GetMemberNameColumn(memberAccess),
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

    private static string GetUnaryOperatorText(UnaryOperator op) => op switch
    {
        UnaryOperator.Negate => "-",
        UnaryOperator.Not => "!",
        UnaryOperator.BitwiseNot => "~",
        UnaryOperator.PreIncrement => "++",
        UnaryOperator.PreDecrement => "--",
        UnaryOperator.PostIncrement => "++",
        UnaryOperator.PostDecrement => "--",
        UnaryOperator.IndexFromEnd => "^",
        _ => op.ToString()
    };

    private void ReportUnsupportedAttributeArgument(Expression expression, string description)
    {
        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
            ? GetBinaryOperatorDiagnosticSpan(binary)
            : GetExpressionDiagnosticSpan(expression);
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
            if (TryResolveExternalType(candidate) is ReflectionTypeInfo { Type: var resolvedType }
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
            if (TryResolveExternalType(candidate) is ReflectionTypeInfo { Type: var resolvedType })
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
            var candidateType = LookupType(candidate);
            if (candidateType == null && TryResolveDottedNestedType(candidate, out var nestedType))
            {
                candidateType = nestedType;
            }

            if (candidateType != null)
            {
                candidateType = ResolveTypeAlias(candidateType);
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
        => SourceTypeDerivesFromAttribute(type, new HashSet<ClassDeclaration>(ReferenceEqualityComparer.Instance));

    private bool SourceTypeDerivesFromAttribute(TypeInfo type, HashSet<ClassDeclaration> seenClasses)
    {
        type = ResolveTypeAlias(type);
        if (type is ReflectionTypeInfo { Type: var reflectionType })
        {
            return IsClrAttributeType(reflectionType);
        }

        if (type is not ClassTypeInfo classType || classType.Declaration.BaseClass == null)
        {
            return false;
        }

        if (!seenClasses.Add(classType.Declaration))
        {
            return false;
        }

        var baseType = ResolveTypeAlias(ResolveType(classType.Declaration.BaseClass));
        return baseType is ReflectionTypeInfo { Type: var baseReflectionType } && IsClrAttributeType(baseReflectionType)
            || SourceTypeDerivesFromAttribute(baseType, seenClasses);
    }

    private void ReportAttributeTypeNotFound(AttributeNode attribute)
    {
        var (line, column, length) = GetAttributeTypeDiagnosticSpan(attribute);
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
        var (line, column, length) = GetAttributeTypeDiagnosticSpan(attribute);
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
        var (line, column, length) = GetAttributeTypeDiagnosticSpan(attribute);
        Error(
            ErrorCode.FeatureNotImplemented,
            $"Source-defined attribute '{attribute.Name}' is not supported by IL emission yet",
            line,
            column,
            "Use an attribute type from a referenced CLR assembly for now.",
            length);
    }

    private static (int Line, int Column, int Length) GetAttributeTypeDiagnosticSpan(AttributeNode attribute)
        => (attribute.Line, attribute.Column, Math.Max(1, attribute.Name.Length));

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
        var (line, column, length) = GetAttributeArgumentDiagnosticSpan(argumentInfo);
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
        var (line, column, length) = GetAttributeArgumentDiagnosticSpan(argumentInfo);
        Error(
            ErrorCode.TypeMismatch,
            $"Attribute named argument '{argumentInfo.Name}' on '{GetAttributeDisplayName(attributeType)}' expects '{FormatReflectionTypeName(memberType)}' but got '{FormatReflectionTypeName(argumentInfo.ClrType!)}'",
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
            ? GetExpressionDiagnosticSpan(positionalArguments[0].Value)
            : GetAttributeFallbackDiagnosticSpan(attribute);
        var argumentTypes = positionalArguments
            .Select(argumentInfo => FormatReflectionTypeName(argumentInfo.ClrType!))
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

    private (int Line, int Column, int Length) GetAttributeArgumentDiagnosticSpan(AttributeArgumentValidationInfo argumentInfo)
    {
        if (argumentInfo.Argument.Name == null
            && argumentInfo.Argument.Value is AssignmentExpression
            {
                Target: IdentifierExpression identifier
            })
        {
            return (identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length));
        }

        return GetExpressionDiagnosticSpan(argumentInfo.Value);
    }

    private static (int Line, int Column, int Length) GetAttributeFallbackDiagnosticSpan(AttributeNode attribute)
        => (1, 1, Math.Max(1, attribute.Name.Length));

    private bool TryInferAttributeArgumentClrType(Expression expression, out Type clrType, out bool isNull)
    {
        isNull = false;
        switch (expression)
        {
            case IntLiteralExpression intLiteral:
                return TryConvertLiteralTypeInfoToClrType(GetIntLiteralType(intLiteral.Value), out clrType);
            case FloatLiteralExpression floatLiteral:
                return TryConvertLiteralTypeInfoToClrType(GetFloatLiteralType(floatLiteral.Value), out clrType);
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
        clrType = TryConvertTypeInfoToClrType(typeInfo) ?? typeof(object);
        return clrType != typeof(object) || typeInfo == BuiltInTypes.Object;
    }

    private bool TryInferAttributeMemberAccessClrType(MemberAccessExpression memberAccess, out Type clrType)
    {
        clrType = typeof(object);
        if (!TryGetQualifiedAttributeName(memberAccess.Object, out var containerName))
        {
            return false;
        }

        if (TryResolveBuiltInTypeKeyword(containerName) is { } builtInType)
        {
            return TryGetRuntimeStaticAttributeMemberType(builtInType, memberAccess.MemberName, out clrType);
        }

        if (TryResolveExternalType(containerName) is not ReflectionTypeInfo { Type: var reflectionType })
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
                var paramType = ResolveDeclaredType(param.Type);
                tableParameterTypes.Add((param.Name, paramType));
                var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, test.Line, test.Column);
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

        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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

        if (BuiltInTypes.IsUnknown(expectedType) || BuiltInTypes.IsUnknown(actualType) || IsAssignable(expectedType, actualType))
        {
            return;
        }

        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
            return ResolveType(varDecl.Type);
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
                type = ResolveType(newType);
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
        var funcType = CreateFunctionTypeInfo(func);
        var existingSymbol = _scopes.Peek().Symbols.GetValueOrDefault(func.Name);
        if (existingSymbol == null)
        {
            DeclareSymbol(func.Name, funcType, func.Line, func.Column);
        }
        else if (existingSymbol is NSharpMethodGroupInfo group)
        {
            // Already in a method group (registered by class first pass) — skip
        }
        else if (existingSymbol is FunctionTypeInfo existingFunc
                 && existingFunc.Declaration != null
                 && funcType.Declaration != null
                 && ParameterSignaturesMatch(existingFunc.Declaration, funcType.Declaration))
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
                var typeParamInfo = new SimpleTypeInfo(tp.Name);
                _scopes.Peek().Types[tp.Name] = typeParamInfo;
                _scopes.Peek().Symbols[tp.Name] = typeParamInfo;
            }
        }

        ResolveGenericConstraintTypes(func.Constraints);
        CheckCircularGenericConstraints(func.TypeParameters, func.Constraints, func.Name, func.Line, func.Column);

        ValidateParameterDeclarations(func.Parameters, func.Line, func.Column);

        // Add parameters to scope
        foreach (var param in func.Parameters)
        {
            var paramType = ResolveDeclaredType(param.Type);
            var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, func.Line, func.Column);
            DeclareSymbol(param.Name, paramType, paramLine, paramColumn);

            // Record parameter in semantic model for IDE features (scoped)
            RecordVariableInCurrentScope(param.Name, paramType);
        }

        // Set expected return type
        var previousFunction = _currentFunction;
        var previousFunctionReturnTypeWasOmitted = _currentFunctionReturnTypeWasOmitted;
        var previousFunctionIsAsync = _currentFunctionIsAsync;
        var functionReturnType = func.ReturnType != null ? ResolveDeclaredType(func.ReturnType) : BuiltInTypes.Void;
        _currentReturnType = functionReturnType;
        _currentFunction = func;
        _currentFunctionReturnTypeWasOmitted = func.ReturnType == null;
        _currentFunctionIsAsync = func.Modifiers.HasFlag(Modifiers.Async);

        ReportGeneratorReturnTypeIfNeeded(func, functionReturnType);

        // Record function return type in semantic model for IDE features (scoped)
        RecordFunctionInCurrentScope(func.Name, functionReturnType);

        // Analyze body
        if (func.Body != null)
        {
            AnalyzeStatement(func.Body);

            // Definite-assignment for locals (NL304): reads before assignment.
            CheckLocalDefiniteAssignment(func.Body);

            // Missing return (all-paths) check for non-void functions.
            // Iterator functions (func* / async*) use yield, not explicit return.
            var isIterator = func.Modifiers.HasFlag(Modifiers.Generator);
            var isAsyncUnitTask = func.Modifiers.HasFlag(Modifiers.Async) && (IsUnitTaskLikeType(functionReturnType) || IsUnitTaskLikeTypeReference(func.ReturnType));
            if (functionReturnType != BuiltInTypes.Void && !isIterator && !isAsyncUnitTask && !StatementAlwaysReturns(func.Body))
            {
                var sourceSnippet = _sourceLines != null && func.Line > 0 && func.Line <= _sourceLines.Length
                    ? _sourceLines[func.Line - 1]
                    : null;

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
            var expectedExpressionType = !isGenerator && functionReturnType != BuiltInTypes.Void ? functionReturnType : null;
            var exprType = AnalyzeExpressionWithExpectedType(func.ExpressionBody, expectedExpressionType);
            ReportSoaRowEscapeIfNeeded(func.ExpressionBody, exprType, "returned");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(func.ExpressionBody, "returned");
            var reportedGeneratorExpressionBody = ReportGeneratorExpressionBodyIfNeeded(func);
            if (!reportedGeneratorExpressionBody && functionReturnType == BuiltInTypes.Void && exprType != BuiltInTypes.Void)
            {
                AddExpressionBodyReturnError(func, exprType);
            }
            else if (!reportedGeneratorExpressionBody && functionReturnType != BuiltInTypes.Void && !IsAssignable(functionReturnType, exprType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(func.ExpressionBody);
                var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
                    ? _sourceLines[diagnosticLine - 1]
                    : null;

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

        var (line, column, length) = GetExpressionDiagnosticSpan(func.ExpressionBody);
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

        var resolvedReturnType = ResolveTypeAlias(GetNonNullableType(returnType));
        var isAsyncGenerator = func.Modifiers.HasFlag(Modifiers.Async);
        if (BuiltInTypes.IsUnknown(resolvedReturnType)
            || IsGeneratorSequenceReturnType(resolvedReturnType, isAsyncGenerator))
        {
            return false;
        }

        var sequenceKind = isAsyncGenerator
            ? "an async enumerable sequence type"
            : "a synchronous enumerable sequence type";
        var suggestion = isAsyncGenerator
            ? "Use `IAsyncEnumerable<T>` for `async func*`."
            : "Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`.";
        var (line, column, length) = func.ReturnType != null
            ? GetSourceSpanDiagnosticSpan(
                GetTypeReferenceStartSpan(func.ReturnType),
                func.Line,
                func.Column,
                Math.Max(1, returnType.ToString().Length))
            : GetFunctionNameDiagnosticSpan(func);
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
        return type switch
        {
            GenericTypeInfo generic => IsGeneratorSequenceGenericName(generic.Name, generic.TypeArguments.Count, isAsyncGenerator),
            ReflectionTypeInfo reflection => IsGeneratorSequenceReflectionType(reflection.Type, isAsyncGenerator),
            _ => false
        };
    }

    private static bool IsGeneratorSequenceGenericName(string name, int arity, bool isAsyncGenerator)
    {
        if (arity != 1)
        {
            return false;
        }

        var unqualifiedName = GetUnqualifiedTypeName(name);
        var tickIndex = unqualifiedName.IndexOf('`', StringComparison.Ordinal);
        if (tickIndex >= 0)
        {
            unqualifiedName = unqualifiedName[..tickIndex];
        }

        if (isAsyncGenerator)
        {
            return unqualifiedName == "IAsyncEnumerable";
        }

        return unqualifiedName is
            "List" or "IEnumerable" or "ICollection" or "IList" or
            "IReadOnlyCollection" or "IReadOnlyList";
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

    private static bool IsUnitTaskLikeType(TypeInfo type)
    {
        return type switch
        {
            SimpleTypeInfo { Name: "Task" or "ValueTask" or "System.Threading.Tasks.Task" or "System.Threading.Tasks.ValueTask" } => true,
            GenericTypeInfo { Name: "Task" or "ValueTask" or "System.Threading.Tasks.Task" or "System.Threading.Tasks.ValueTask", TypeArguments.Count: 0 } => true,
            ReflectionTypeInfo { Type: var reflectionType } => reflectionType == typeof(System.Threading.Tasks.Task) || reflectionType == typeof(System.Threading.Tasks.ValueTask),
            _ when IsUnitTaskLikeName(type.ToString()) => true,
            _ => false
        };
    }

    private static bool IsUnitTaskLikeName(string name)
    {
        return name is "Task" or "ValueTask" or "System.Threading.Tasks.Task" or "System.Threading.Tasks.ValueTask"
            || name.EndsWith(".Task", StringComparison.Ordinal)
            || name.EndsWith(".ValueTask", StringComparison.Ordinal);
    }

    private static bool IsUnitTaskLikeTypeReference(TypeReference? typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => IsUnitTaskLikeName(simple.Name),
            GenericTypeReference { TypeArguments.Count: 0 } generic => IsUnitTaskLikeName(generic.Name),
            _ => false
        };
    }

    private bool TryGetTaskLikeResultType(TypeInfo type, out TypeInfo resultType)
    {
        switch (type)
        {
            case GenericTypeInfo { Name: "Task" or "ValueTask" or "System.Threading.Tasks.Task" or "System.Threading.Tasks.ValueTask", TypeArguments.Count: 1 } generic:
                resultType = generic.TypeArguments[0];
                return true;
            case ReflectionTypeInfo { Type: var reflectionType } when reflectionType.IsGenericType &&
                (reflectionType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.Task<>) || reflectionType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.ValueTask<>)):
                resultType = ConvertReflectionType(reflectionType.GetGenericArguments()[0]);
                return true;
            default:
                resultType = BuiltInTypes.Unknown;
                return false;
        }
    }

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

        PushScope(new Scope(ScopeKind.Class), classDecl.Line, classDecl.Column);

        // Add generic type parameters to both type and symbol namespaces
        if (classDecl.TypeParameters != null)
        {
            foreach (var tp in classDecl.TypeParameters)
            {
                var typeParamInfo = new SimpleTypeInfo(tp.Name);
                _scopes.Peek().Types[tp.Name] = typeParamInfo;
                _scopes.Peek().Symbols[tp.Name] = typeParamInfo;
            }
        }

        ValidateNoStaticMembersOnGenericType(classDecl.Name, classDecl.TypeParameters, classDecl.Members);

        ResolveTypeReferenceIfPresent(classDecl.BaseClass);
        ResolveTypeReferences(classDecl.Interfaces);

        // Add 'this' to scope
        var classType = new ClassTypeInfo(classDecl);
        DeclareSymbol("this", classType, classDecl.Line, classDecl.Column, recordBindingDeclaration: false);

        // Add primary constructor parameters to scope (C# 12 feature)
        if (classDecl.PrimaryConstructorParameters != null)
        {
            ValidateParameterDeclarations(classDecl.PrimaryConstructorParameters, classDecl.Line, classDecl.Column);

            foreach (var param in classDecl.PrimaryConstructorParameters)
            {
                var paramType = ResolveDeclaredType(param.Type);
                var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, classDecl.Line, classDecl.Column);
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
                var funcTypeInfo = CreateFunctionTypeInfo(func);
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

        PushScope(new Scope(ScopeKind.Struct), structDecl.Line, structDecl.Column);

        // Add generic type parameters to both type and symbol namespaces
        if (structDecl.TypeParameters != null)
        {
            foreach (var tp in structDecl.TypeParameters)
            {
                var typeParamInfo = new SimpleTypeInfo(tp.Name);
                _scopes.Peek().Types[tp.Name] = typeParamInfo;
                _scopes.Peek().Symbols[tp.Name] = typeParamInfo;
            }
        }

        ValidateNoStaticMembersOnGenericType(structDecl.Name, structDecl.TypeParameters, structDecl.Members);

        ResolveTypeReferences(structDecl.Interfaces);

        var structType = new StructTypeInfo(structDecl);
        DeclareSymbol("this", structType, structDecl.Line, structDecl.Column, recordBindingDeclaration: false);

        // Add primary constructor parameters to scope (C# 12 feature)
        if (structDecl.PrimaryConstructorParameters != null)
        {
            ValidateParameterDeclarations(structDecl.PrimaryConstructorParameters, structDecl.Line, structDecl.Column);

            foreach (var param in structDecl.PrimaryConstructorParameters)
            {
                var paramType = ResolveDeclaredType(param.Type);
                var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, structDecl.Line, structDecl.Column);
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

        PushScope(new Scope(ScopeKind.Record), recordDecl.Line, recordDecl.Column);

        // Add generic type parameters to both type and symbol namespaces
        if (recordDecl.TypeParameters != null)
        {
            foreach (var tp in recordDecl.TypeParameters)
            {
                var typeParamInfo = new SimpleTypeInfo(tp.Name);
                _scopes.Peek().Types[tp.Name] = typeParamInfo;
                _scopes.Peek().Symbols[tp.Name] = typeParamInfo;
            }
        }

        ValidateNoStaticMembersOnGenericType(recordDecl.Name, recordDecl.TypeParameters, recordDecl.Members);

        ResolveTypeReferences(recordDecl.Interfaces);

        var recordType = new RecordTypeInfo(recordDecl);
        DeclareSymbol("this", recordType, recordDecl.Line, recordDecl.Column, recordBindingDeclaration: false);

        // Add primary constructor parameters to scope (C# 12 feature)
        if (recordDecl.PrimaryConstructorParameters != null)
        {
            ValidateParameterDeclarations(recordDecl.PrimaryConstructorParameters, recordDecl.Line, recordDecl.Column);

            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var paramType = ResolveDeclaredType(param.Type);
                var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, recordDecl.Line, recordDecl.Column);
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
            columnTypes.Add((column, ResolveDeclaredType(column.Type)));
        }

        ValidateSoaColumnNames(soaRecordDecl);

        foreach (var (column, columnType) in columnTypes)
        {
            var resolvedColumnType = ResolveTypeAlias(columnType);
            if (IsSupportedSoaColumnType(resolvedColumnType))
                continue;

            var (line, columnPosition, length) = GetSoaColumnTypeDiagnosticSpan(column);
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
            var (line, columnPosition, length) = GetSoaColumnNameDiagnosticSpan(column, soaRecordDecl);
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
        var resolved = ResolveTypeAlias(type);
        if (BuiltInTypes.IsUnknown(resolved))
            return true;

        if (resolved is NullableTypeInfo nullable)
            return ResolveTypeAlias(nullable.InnerType) == BuiltInTypes.String;

        if (resolved is EnumTypeInfo enumType)
            return enumType.Declaration.Type == EnumType.Int;

        if (resolved is ReflectionTypeInfo reflectionType && reflectionType.Type.IsEnum)
            return Enum.GetUnderlyingType(reflectionType.Type) == typeof(int);

        return resolved == BuiltInTypes.Int
            || resolved == BuiltInTypes.UInt
            || resolved == BuiltInTypes.Long
            || resolved == BuiltInTypes.Bool
            || resolved == BuiltInTypes.Char
            || resolved == BuiltInTypes.String;
    }

    private static (int Line, int Column, int Length) GetSoaColumnTypeDiagnosticSpan(SoaColumnDeclaration column)
    {
        var typeSpan = GetTypeReferenceStartSpan(column.Type);
        return GetSourceSpanDiagnosticSpan(
            typeSpan,
            column.Line,
            column.Column,
            Math.Max(1, column.Name.Length));
    }

    private static (int Line, int Column, int Length) GetSoaColumnNameDiagnosticSpan(
        SoaColumnDeclaration column,
        SoaRecordDeclaration declaration)
    {
        var line = column.Line > 0 ? column.Line : declaration.Line;
        var columnPosition = column.Column > 0 ? column.Column : declaration.Column;
        return (line, columnPosition, Math.Max(1, column.Name.Length));
    }

    private void AnalyzeInterfaceDeclaration(InterfaceDeclaration interfaceDecl)
    {
        CheckVisibilityConvention(interfaceDecl.Name, interfaceDecl.Modifiers, interfaceDecl.Line, interfaceDecl.Column);

        PushScope(new Scope(ScopeKind.Interface), interfaceDecl.Line, interfaceDecl.Column);

        // Add generic type parameters to both type and symbol namespaces
        if (interfaceDecl.TypeParameters != null)
        {
            foreach (var tp in interfaceDecl.TypeParameters)
            {
                var typeParamInfo = new SimpleTypeInfo(tp.Name);
                _scopes.Peek().Types[tp.Name] = typeParamInfo;
                _scopes.Peek().Symbols[tp.Name] = typeParamInfo;
            }
        }

        ResolveTypeReferences(interfaceDecl.BaseInterfaces);

        foreach (var member in interfaceDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
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
                var typeParamInfo = new SimpleTypeInfo(tp.Name);
                _scopes.Peek().Types[tp.Name] = typeParamInfo;
                _scopes.Peek().Symbols[tp.Name] = typeParamInfo;
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
                var sourceSnippet = _sourceLines != null && caseLine > 0 && caseLine <= _sourceLines.Length
                    ? _sourceLines[caseLine - 1]
                    : null;

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
                    ResolveDeclaredType(property.Type);
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
                var sourceSnippet = _sourceLines != null && memLine > 0 && memLine <= _sourceLines.Length
                    ? _sourceLines[memLine - 1]
                    : null;

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
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(member.Value);
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
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(member.Value);
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
            fieldType = ResolveDeclaredType(field.Type);

            if (field.Initializer != null)
            {
                var previousExpectedType = _currentExpectedType;
                _currentExpectedType = fieldType;
                var initType = AnalyzeExpression(field.Initializer);
                _currentExpectedType = previousExpectedType;
                var isSoaRowInitializer = ReportSoaRowEscapeIfNeeded(field.Initializer, initType, "stored in a field");
                var isSoaDirectColumnInitializer = ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(field.Initializer, "stored in a field");
                if (!isSoaRowInitializer && !isSoaDirectColumnInitializer && !IsAssignable(fieldType, initType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                        GetExpressionDiagnosticSpan(field.Initializer);
                    var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
                        ? _sourceLines[diagnosticLine - 1]
                        : null;

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

        var propType = ResolveDeclaredType(prop.Type!);
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
            if (!IsAssignable(propType, exprType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                    GetExpressionDiagnosticSpan(prop.ExpressionBody);
                var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
                    ? _sourceLines[diagnosticLine - 1]
                    : null;

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
        var indexerType = ResolveDeclaredType(indexer.Type);
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
            var parameterType = ResolveDeclaredType(parameter.Type);
            var (parameterLine, parameterColumn) = GetParameterDeclarationPosition(
                parameter,
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
            var paramType = ResolveDeclaredType(param.Type);
            var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, ctor.Line, ctor.Column);
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
                if (field.Type != null && field.Initializer == null && !IsNullableType(ResolveType(field.Type)))
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

    private sealed class DefiniteAssignmentState
    {
        // Locals declared without an initializer that must be definitely assigned before use.
        public HashSet<string> Candidates { get; } = new(StringComparer.Ordinal);

        // Currently-definitely-assigned locals on the path being analyzed.
        public HashSet<string> Assigned { get; } = new(StringComparer.Ordinal);

        // Reads already reported, keyed by name+position, to avoid duplicate squiggles.
        public HashSet<(string Name, int Line, int Column)> Reported { get; } = new();
    }

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
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetStatementDiagnosticSpan(stmt);
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
                        && !IsAssignable(elementType, yieldedType))
                    {
                        var (line, column, length) = GetExpressionDiagnosticSpan(yieldStmt.Value);
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

    private enum DiscardedExpressionContext
    {
        ExpressionStatement,
        ForIterator
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

        var calleeName = GetCallTargetName(call);
        var (line, column, length) = GetCallDiagnosticSpan(call, calleeName ?? "call");
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
            case FunctionTypeInfo { Declaration: { } declaration } when HasMustUseAttribute(declaration.Attributes):
                reason = $"'{declaration.Name}' is marked [MustUse]";
                return true;
            case NSharpMethodGroupInfo group when group.Declarations.All(d => HasMustUseAttribute(d.Attributes)) && group.Declarations.Count > 0:
                reason = $"'{group.Declarations[0].Name}' is marked [MustUse]";
                return true;
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

    private static bool HasMustUseAttribute(IEnumerable<AttributeNode> attributes)
        => attributes.Any(attribute => IsMustUseAttributeName(attribute.Name));

    private static bool HasMustUseAttribute(MethodInfo method)
    {
        try
        {
            return method.GetCustomAttributesData()
                .Any(data => IsMustUseAttributeName(data.AttributeType.Name)
                    || IsMustUseAttributeName(data.AttributeType.FullName ?? string.Empty));
        }
        catch
        {
            return false;
        }
    }

    private static bool IsDiscardTarget(Expression target)
        => target is IdentifierExpression { Name: "_" };

    private static bool IsMustUseAttributeName(string name)
    {
        if (string.IsNullOrEmpty(name))
            return false;

        var lastDot = name.LastIndexOf('.');
        var simpleName = lastDot >= 0 ? name[(lastDot + 1)..] : name;

        return simpleName.Equals("MustUse", StringComparison.Ordinal)
            || simpleName.Equals("MustUseAttribute", StringComparison.Ordinal);
    }

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
        var (line, column, length) = GetExpressionStatementDiagnosticSpan(expression);
        var description = DescribeExpressionForDiagnostic(expression);

        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.InvalidExpressionStatement(
                _currentFilePath,
                line,
                column,
                _sourceLines[line - 1],
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
        var (line, column, length) = GetExpressionStatementDiagnosticSpan(expression);
        var description = DescribeExpressionForDiagnostic(expression);

        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.InvalidForIteratorExpression(
                _currentFilePath,
                line,
                column,
                _sourceLines[line - 1],
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

    private (int Line, int Column, int Length) GetExpressionStatementDiagnosticSpan(Expression expression)
    {
        return expression switch
        {
            IdentifierExpression identifier => (identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length)),
            MemberAccessExpression memberAccess => (memberAccess.Line, GetMemberNameColumn(memberAccess), Math.Max(1, memberAccess.MemberName.Length)),
            ParenthesizedExpression parenthesized => GetExpressionStatementDiagnosticSpan(parenthesized.Inner),
            CheckedExpression checkedExpression => GetExpressionStatementDiagnosticSpan(checkedExpression.Expression),
            UncheckedExpression uncheckedExpression => GetExpressionStatementDiagnosticSpan(uncheckedExpression.Expression),
            _ => (expression.Line, expression.Column, GetExpressionLength(expression.Line, expression.Column))
        };
    }

    private (int Line, int Column, int Length) GetStatementDiagnosticSpan(Statement statement)
    {
        return statement switch
        {
            ExpressionStatement expressionStatement => GetExpressionStatementDiagnosticSpan(expressionStatement.Expression),
            VariableDeclarationStatement variableDeclaration => GetVariableDeclarationNameDiagnosticSpan(variableDeclaration),
            LocalFunctionStatement localFunction => (
                localFunction.Line,
                localFunction.Column,
                GetTokenLength(localFunction.Line, localFunction.Column)),
            _ => (statement.Line, statement.Column, GetTokenLength(statement.Line, statement.Column))
        };
    }

    private static (int Line, int Column, int Length) GetVariableDeclarationNameDiagnosticSpan(
        VariableDeclarationStatement variableDeclaration)
        => (
            variableDeclaration.Line,
            variableDeclaration.Column,
            Math.Max(1, variableDeclaration.Name.Length));

    private (int Line, int Column, int Length) GetFunctionNameDiagnosticSpan(FunctionDeclaration function)
    {
        if (string.IsNullOrWhiteSpace(function.Name) || function.Name == "<error>")
            return (function.Line, function.Column, GetTokenLength(function.Line, function.Column));

        return (
            function.Line,
            GetDeclarationNameColumn(function.Name, function.Line, function.Column),
            Math.Max(1, function.Name.Length));
    }

    private (int Line, int Column, int Length) GetExpressionDiagnosticSpan(Expression expression)
    {
        return expression switch
        {
            IdentifierExpression identifier => (identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length)),
            ThisExpression thisExpression => (thisExpression.Line, thisExpression.Column, "this".Length),
            IntLiteralExpression literal => (literal.Line, literal.Column, Math.Max(1, literal.Value.Length)),
            FloatLiteralExpression literal => (literal.Line, literal.Column, Math.Max(1, literal.Value.Length)),
            CharLiteralExpression literal => (literal.Line, literal.Column, GetTokenLength(literal.Line, literal.Column)),
            StringLiteralExpression literal => (literal.Line, literal.Column, GetTokenLength(literal.Line, literal.Column)),
            InterpolatedStringExpression interpolated => (interpolated.Line, interpolated.Column, GetTokenLength(interpolated.Line, interpolated.Column)),
            BoolLiteralExpression literal => (literal.Line, literal.Column, literal.Value ? 4 : 5),
            NullLiteralExpression literal => (literal.Line, literal.Column, 4),
            MemberAccessExpression memberAccess when TryGetStableNullPath(memberAccess) is { } path
                => GetStablePathDiagnosticSpan(memberAccess, path, memberAccess.Line, GetMemberNameColumn(memberAccess)),
            MemberAccessExpression memberAccess => (memberAccess.Line, GetMemberNameColumn(memberAccess), Math.Max(1, memberAccess.MemberName.Length)),
            ParenthesizedExpression parenthesized => GetExpressionDiagnosticSpan(parenthesized.Inner),
            CheckedExpression checkedExpression => GetExpressionDiagnosticSpan(checkedExpression.Expression),
            UncheckedExpression uncheckedExpression => GetExpressionDiagnosticSpan(uncheckedExpression.Expression),
            AllocExpression allocExpression => GetExpressionDiagnosticSpan(allocExpression.Expression),
            CallExpression call => GetCallDiagnosticSpan(call, GetCallTargetName(call) ?? "call"),
            _ => (expression.Line, expression.Column, GetTokenLength(expression.Line, expression.Column))
        };
    }

    private (int Line, int Column, int Length) GetPatternNameDiagnosticSpan(Pattern pattern)
    {
        return pattern switch
        {
            IdentifierPattern identifier => (
                identifier.Line,
                identifier.Column,
                Math.Max(1, identifier.Name.Length)),
            UnionCasePattern unionCase => (
                unionCase.Line,
                unionCase.Column,
                Math.Max(1, unionCase.CaseName.Length)),
            TypePattern typePattern => (
                typePattern.Line,
                typePattern.Column,
                GetTypePatternNameLength(typePattern)),
            ListPattern listPattern => GetListPatternDiagnosticSpan(listPattern),
            _ => (pattern.Line, pattern.Column, GetTokenLength(pattern.Line, pattern.Column))
        };
    }

    private int GetTypePatternNameLength(TypePattern typePattern)
    {
        return typePattern.Type switch
        {
            SimpleTypeReference simple => Math.Max(1, simple.Name.Length),
            GenericTypeReference generic => Math.Max(1, generic.Name.Length),
            _ => GetTokenLength(typePattern.Line, typePattern.Column)
        };
    }

    private (int Line, int Column, int Length) GetPropertyPatternNameDiagnosticSpan(
        PropertyPattern propertyPattern,
        int fallbackLine,
        int fallbackColumn)
    {
        var line = propertyPattern.Line > 0 ? propertyPattern.Line : fallbackLine;
        var column = propertyPattern.Column > 0 ? propertyPattern.Column : fallbackColumn;
        var length = propertyPattern.Name == "<error>"
            ? GetTokenLength(line, column)
            : Math.Max(1, propertyPattern.Name.Length);

        return (line, column, length);
    }

    private (int Line, int Column, int Length) GetListPatternDiagnosticSpan(ListPattern listPattern)
        => (listPattern.Line, listPattern.Column, GetDelimitedPatternLength(listPattern.Line, listPattern.Column, '[', ']'));

    /// <summary>
    /// Computes the span for an 'is' expression covering the 'is' keyword through the
    /// tested type name (e.g. underlines <c>is string</c>). Falls back to the 'is'
    /// keyword alone when source text is unavailable.
    /// </summary>
    private (int Line, int Column, int Length) GetIsExpressionDiagnosticSpan(IsExpression isExpr)
    {
        const int IsKeywordLength = 2;

        if (_sourceLines == null || isExpr.Line <= 0 || isExpr.Line > _sourceLines.Length)
            return (isExpr.Line, isExpr.Column, IsKeywordLength);

        var sourceLine = _sourceLines[isExpr.Line - 1];
        var start = isExpr.Column - 1;
        if (start < 0 || start >= sourceLine.Length)
            return (isExpr.Line, isExpr.Column, IsKeywordLength);

        // Skip the 'is' keyword and any whitespace before the type name.
        var typeStart = start + IsKeywordLength;
        while (typeStart < sourceLine.Length && char.IsWhiteSpace(sourceLine[typeStart]))
            typeStart++;

        if (typeStart >= sourceLine.Length)
            return (isExpr.Line, isExpr.Column, IsKeywordLength);

        var typeEnd = typeStart;
        while (typeEnd < sourceLine.Length &&
               (char.IsLetterOrDigit(sourceLine[typeEnd]) || sourceLine[typeEnd] is '_' or '.' or '<' or '>' or '?' or '[' or ']'))
        {
            typeEnd++;
        }

        if (typeEnd <= typeStart)
            return (isExpr.Line, isExpr.Column, IsKeywordLength);

        return (isExpr.Line, isExpr.Column, typeEnd - start);
    }

    private int GetDelimitedPatternLength(int line, int column, char openDelimiter, char closeDelimiter)
    {
        if (_sourceLines == null || line <= 0 || line > _sourceLines.Length)
            return 1;

        var sourceLine = _sourceLines[line - 1];
        var start = column - 1;
        if (start < 0 || start >= sourceLine.Length || sourceLine[start] != openDelimiter)
            return GetTokenLength(line, column);

        var depth = 0;
        for (var i = start; i < sourceLine.Length; i++)
        {
            if (sourceLine[i] == openDelimiter)
            {
                depth++;
            }
            else if (sourceLine[i] == closeDelimiter)
            {
                depth--;
                if (depth == 0)
                    return i - start + 1;
            }
        }

        return Math.Max(1, sourceLine.TrimEnd().Length - start);
    }

    private void ReportBooleanConditionTypeMismatch(Expression condition, string owner, TypeInfo actualType)
    {
        if (BuiltInTypes.IsUnknown(actualType) || ContainsParserErrorPlaceholder(condition))
            return;

        var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(condition);
        Error(
            ErrorCode.TypeMismatch,
            $"The condition in {owner} must be a boolean, but I found '{actualType}'",
            diagnosticLine,
            diagnosticColumn,
            length: diagnosticLength);
    }

    private static string GetBinaryOperatorText(BinaryOperator op) => op switch
    {
        BinaryOperator.Add => "+",
        BinaryOperator.Subtract => "-",
        BinaryOperator.Multiply => "*",
        BinaryOperator.Divide => "/",
        BinaryOperator.Modulo => "%",
        BinaryOperator.Equal => "==",
        BinaryOperator.NotEqual => "!=",
        BinaryOperator.Less => "<",
        BinaryOperator.LessOrEqual => "<=",
        BinaryOperator.Greater => ">",
        BinaryOperator.GreaterOrEqual => ">=",
        BinaryOperator.And => "&&",
        BinaryOperator.Or => "||",
        BinaryOperator.BitwiseAnd => "&",
        BinaryOperator.BitwiseOr => "|",
        BinaryOperator.BitwiseXor => "^",
        BinaryOperator.LeftShift => "<<",
        BinaryOperator.RightShift => ">>",
        BinaryOperator.NullCoalesce => "??",
        BinaryOperator.Range => "..",
        _ => op.ToString()
    };

    private static string GetAssignmentOperatorText(AssignmentOperator op) => op switch
    {
        AssignmentOperator.Assign => "=",
        AssignmentOperator.AddAssign => "+=",
        AssignmentOperator.SubtractAssign => "-=",
        AssignmentOperator.MultiplyAssign => "*=",
        AssignmentOperator.DivideAssign => "/=",
        AssignmentOperator.NullCoalesceAssign => "??=",
        _ => op.ToString()
    };

    private (int Line, int Column, int Length) GetBinaryOperatorDiagnosticSpan(BinaryExpression expression)
        => (expression.Line, expression.Column, Math.Max(1, GetBinaryOperatorText(expression.Operator).Length));

    private static (int Line, int Column, int Length) GetSourceSpanDiagnosticSpan(
        SourceSpan span,
        int fallbackLine,
        int fallbackColumn,
        int fallbackLength = 1)
        => span.IsValid && span.StartLine == span.EndLine
            ? (span.StartLine, span.StartColumn, Math.Max(1, span.Length))
            : (fallbackLine, fallbackColumn, Math.Max(1, fallbackLength));

    private (int Line, int Column, int Length) GetBinaryOperandDiagnosticSpan(
        BinaryExpression expression,
        bool leftIsWrong,
        bool rightIsWrong)
    {
        if (leftIsWrong && !rightIsWrong)
            return GetExpressionDiagnosticSpan(expression.Left);

        if (rightIsWrong && !leftIsWrong)
            return GetExpressionDiagnosticSpan(expression.Right);

        return GetBinaryOperatorDiagnosticSpan(expression);
    }

    private (int Line, int Column, int Length) GetNullReceiverDiagnosticSpan(
        Expression receiver,
        string path,
        int fallbackLine,
        int fallbackColumn)
    {
        if (path != "this value")
            return GetStablePathDiagnosticSpan(receiver, path, fallbackLine, fallbackColumn);

        return GetExpressionDiagnosticSpan(receiver);
    }

    private (int Line, int Column, int Length) GetStablePathDiagnosticSpan(
        Expression expression,
        string path,
        int fallbackLine,
        int fallbackColumn)
    {
        var (line, column) = GetExpressionStartPosition(expression, fallbackLine, fallbackColumn);
        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length)
        {
            var sourceLine = _sourceLines[line - 1];
            var startIndex = Math.Clamp(column - 1, 0, sourceLine.Length);
            var index = sourceLine.IndexOf(path, startIndex, StringComparison.Ordinal);
            if (index < 0)
            {
                index = sourceLine.IndexOf(path, StringComparison.Ordinal);
            }

            if (index >= 0)
            {
                return (line, index + 1, Math.Max(1, path.Length));
            }
        }

        return (line, column, Math.Max(1, path.Length));
    }

    private static (int Line, int Column) GetExpressionStartPosition(Expression expression, int fallbackLine, int fallbackColumn)
    {
        return expression switch
        {
            MemberAccessExpression memberAccess => GetExpressionStartPosition(memberAccess.Object, fallbackLine, fallbackColumn),
            IndexAccessExpression indexAccess => GetExpressionStartPosition(indexAccess.Object, fallbackLine, fallbackColumn),
            CallExpression call => GetExpressionStartPosition(call.Callee, fallbackLine, fallbackColumn),
            ParenthesizedExpression parenthesized => GetExpressionStartPosition(parenthesized.Inner, fallbackLine, fallbackColumn),
            CheckedExpression checkedExpression => GetExpressionStartPosition(checkedExpression.Expression, fallbackLine, fallbackColumn),
            UncheckedExpression uncheckedExpression => GetExpressionStartPosition(uncheckedExpression.Expression, fallbackLine, fallbackColumn),
            _ when expression.Line > 0 && expression.Column > 0 => (expression.Line, expression.Column),
            _ => (fallbackLine, fallbackColumn)
        };
    }

    private int GetTokenLength(int line, int column)
    {
        if (_sourceLines == null || line <= 0 || line > _sourceLines.Length)
            return 1;

        var sourceLine = _sourceLines[line - 1];
        var start = column - 1;
        if (start < 0 || start >= sourceLine.Length)
            return 1;

        if (sourceLine[start] == '"')
            return ScanQuotedTokenLength(sourceLine, start, '"');

        if (sourceLine[start] == '\'')
            return ScanQuotedTokenLength(sourceLine, start, '\'');

        if (sourceLine[start] == '$' && start + 1 < sourceLine.Length && sourceLine[start + 1] == '"')
            return 1 + ScanQuotedTokenLength(sourceLine, start + 1, '"');

        var end = start;
        while (end < sourceLine.Length && !char.IsWhiteSpace(sourceLine[end]) && sourceLine[end] is not ',' and not ')' and not ']' and not '}')
        {
            end++;
        }

        return Math.Max(1, end - start);
    }

    private static int ScanQuotedTokenLength(string sourceLine, int quoteStart, char quote)
    {
        var index = quoteStart + 1;
        while (index < sourceLine.Length)
        {
            if (sourceLine[index] == quote && sourceLine[index - 1] != '\\')
                return index - quoteStart + 1;

            index++;
        }

        return Math.Max(1, sourceLine.Length - quoteStart);
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

    private int GetExpressionLength(int line, int column)
    {
        if (_sourceLines == null || line <= 0 || line > _sourceLines.Length)
            return 1;

        var sourceLine = _sourceLines[line - 1];
        if (column <= 0 || column > sourceLine.Length)
            return Math.Max(1, sourceLine.TrimEnd().Length);

        return Math.Max(1, sourceLine.TrimEnd().Length - column + 1);
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

        // We don't strictly require boolean type because we support various comparison patterns
    }

    private void AnalyzeAssertThrowsStatement(AssertThrowsStatement assertThrows)
    {
        var exceptionType = ResolveDeclaredType(assertThrows.ExceptionType);
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
        // This allows it to be called later in the same scope (forward references work in C#)
        var funcType = CreateFunctionTypeInfo(func);
        DeclareSymbol(func.Name, funcType, localFunc.Line, localFunc.Column);

        // Analyze the local function body in a new scope
        PushScope(new Scope(ScopeKind.Function), localFunc.Line, localFunc.Column);

        // Add generic type parameters to both type and symbol namespaces (mirrors
        // AnalyzeFunctionDeclaration) so they resolve as types inside the local function.
        if (func.TypeParameters != null)
        {
            foreach (var tp in func.TypeParameters)
            {
                var typeParamInfo = new SimpleTypeInfo(tp.Name);
                _scopes.Peek().Types[tp.Name] = typeParamInfo;
                _scopes.Peek().Symbols[tp.Name] = typeParamInfo;
            }
        }

        ValidateParameterDeclarations(func.Parameters, localFunc.Line, localFunc.Column);

        // Add parameters to scope
        foreach (var param in func.Parameters)
        {
            var paramType = ResolveDeclaredType(param.Type);
            var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, localFunc.Line, localFunc.Column);
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
        TypeInfo? returnType = func.ReturnType != null ? ResolveType(func.ReturnType) : BuiltInTypes.Void;
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
            var expectedExpressionType = !isGenerator && returnType != BuiltInTypes.Void ? returnType : null;
            var exprType = AnalyzeExpressionWithExpectedType(func.ExpressionBody, expectedExpressionType);
            ReportSoaRowEscapeIfNeeded(func.ExpressionBody, exprType, "returned");
            ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(func.ExpressionBody, "returned");
            var reportedGeneratorExpressionBody = ReportGeneratorExpressionBodyIfNeeded(func);
            // Verify expression type matches return type
            if (!reportedGeneratorExpressionBody && returnType != BuiltInTypes.Void && !IsAssignable(returnType, exprType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(func.ExpressionBody);
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
        TypeInfo? declaredType = varDecl.Type != null ? ResolveDeclaredType(varDecl.Type) : null;
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
            if (!IsAssignable(declaredType, inferredType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                    GetExpressionDiagnosticSpan(varDecl.Initializer);
                var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
                    ? _sourceLines[diagnosticLine - 1]
                    : null;

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
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetVariableDeclarationNameDiagnosticSpan(varDecl);
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
            if (inferredType == BuiltInTypes.Void)
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = varDecl.Initializer != null
                    ? GetExpressionDiagnosticSpan(varDecl.Initializer)
                    : (varDecl.Line, varDecl.Column, Math.Max(1, varDecl.Name.Length));
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
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetVariableDeclarationNameDiagnosticSpan(varDecl);
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
        SetNullStateInCurrentScope(varDecl.Name, initialNullState);
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
                RegisterErrorTupleResult(resultVar, errVar, tupleDecl.Line, tupleDecl.Column);
            }

            // Declare err variable as nullable Exception
            if (errVar != "_")
            {
                var exceptionType = new ExternalTypeInfo("Exception?");
                DeclareSymbol(errVar, exceptionType, tupleDecl.Line, tupleDecl.Column);
                RecordVariableInCurrentScope(errVar, exceptionType);
                SetNullStateInCurrentScope(errVar, NullState.MaybeNull);
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
                var (line, column, length) = GetExpressionDiagnosticSpan(tupleDecl.Initializer);
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
                var (line, column, length) = GetExpressionDiagnosticSpan(tupleDecl.Initializer);
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
        SetNullStateInCurrentScope(name, GetDefaultNullState(type));
    }

    private bool TryGetTupleDeconstructionElements(TypeInfo initType, out List<TypeInfo> elements)
    {
        var resolved = ResolveTypeAlias(initType);
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

            elements.Add(ConvertReflectionType(field.FieldType));
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
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(ifStmt.Condition);
            var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
                ? _sourceLines[diagnosticLine - 1]
                : null;

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
            if (narrowing.NullState is { } nullState)
            {
                currentScope.NullStates[narrowing.Path] = nullState;
                if (nullState == NullState.Null)
                {
                    MarkErrorTupleResultsAvailableForError(narrowing.Path);
                }
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
                if (IsSubtypeOf(narrowedType, existing))
                    currentScope.Symbols[name] = narrowedType;
                else if (!IsSubtypeOf(existing, narrowedType))
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
            var narrowedType = ResolveType(isExpr.Type);
            if (isExpr.VariableName != null)
            {
                // `x is Dog d` — declare d: Dog in then-branch
                thenNarrowings.Add(new FlowNarrowing(isExpr.VariableName, narrowedType, NullState.NotNull));
                if (TryGetStableNullPath(isExpr.Expression) is { } path
                    && !path.Contains('.', StringComparison.Ordinal)
                    && LookupSymbol(path) is UnionTypeInfo { IsAnonymous: true } sourceUnion
                    && TryRemoveAnonymousUnionArm(sourceUnion, narrowedType) is { } remainingType)
                {
                    elseNarrowings.Add(new FlowNarrowing(path, remainingType, NullState.NotNull));
                }
            }
            else if (TryGetStableNullPath(isExpr.Expression) is { } path)
            {
                // `x is Dog` — narrow x to Dog in then-branch
                thenNarrowings.Add(new FlowNarrowing(path, narrowedType, NullState.NotNull));
                if (!path.Contains('.', StringComparison.Ordinal)
                    && LookupSymbol(path) is UnionTypeInfo { IsAnonymous: true } sourceUnion
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

    private TypeInfo? TryRemoveAnonymousUnionArm(UnionTypeInfo sourceUnion, TypeInfo matchedType)
    {
        var remaining = sourceUnion.Arms
            .Where(arm => !IsAssignable(matchedType, arm))
            .ToList();

        if (remaining.Count == sourceUnion.Arms.Count)
            return null;

        return remaining.Count switch
        {
            0 => BuiltInTypes.Never,
            1 => remaining[0],
            _ => new UnionTypeInfo(remaining)
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

        var path = TryGetStableNullPath(expr);
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

        var symbolType = LookupSymbol(ident.Name);
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
            case SimpleTypeInfo simpleType when !requireAsync && simpleType == BuiltInTypes.String:
                elementType = BuiltInTypes.Char;
                return true;
            case GenericTypeInfo genericType when TryGetGenericLoopSequenceElementType(genericType, requireAsync, out elementType):
                return true;
            case ReflectionTypeInfo reflectionType when TryGetReflectionLoopSequenceElementType(reflectionType.Type, requireAsync, out elementType):
                return true;
            case ClassTypeInfo classType when TryGetSourceLoopSequenceElementType(classType.Declaration.Interfaces, requireAsync, out elementType):
                return true;
            case StructTypeInfo structType when TryGetSourceLoopSequenceElementType(structType.Declaration.Interfaces, requireAsync, out elementType):
                return true;
            case RecordTypeInfo recordType when TryGetSourceLoopSequenceElementType(recordType.Declaration.Interfaces, requireAsync, out elementType):
                return true;
            case InterfaceTypeInfo interfaceType when TryGetSourceLoopSequenceElementType(interfaceType.Declaration.BaseInterfaces, requireAsync, out elementType):
                return true;
            default:
                return false;
        }
    }

    private TypeInfo NormalizeShapeType(TypeInfo type)
    {
        var resolved = ResolveTypeAlias(GetNonNullableType(type));
        while (true)
        {
            switch (resolved)
            {
                case ObliviousTypeInfo oblivious:
                    resolved = ResolveTypeAlias(GetNonNullableType(oblivious.InnerType));
                    continue;
                case ByRefTypeInfo byRef:
                    resolved = ResolveTypeAlias(GetNonNullableType(byRef.InnerType));
                    continue;
                case SimpleTypeInfo simple when LookupType(simple.Name) is { } namedType && !ReferenceEquals(namedType, resolved):
                    resolved = ResolveTypeAlias(GetNonNullableType(namedType));
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
        var (line, column, length) = GetExpressionDiagnosticSpan(collection);
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
        elementType = BuiltInTypes.Unknown;

        var name = GetUnqualifiedTypeName(genericType.Name);
        var tickIndex = name.IndexOf('`', StringComparison.Ordinal);
        if (tickIndex >= 0)
        {
            name = name[..tickIndex];
        }

        if (requireAsync)
        {
            if (name != "IAsyncEnumerable")
            {
                return false;
            }

            elementType = genericType.TypeArguments[0];
            return true;
        }

        if (!requireAsync && IsDictionaryTypeName(name) && genericType.TypeArguments.Count == 2)
        {
            elementType = new GenericTypeInfo("KeyValuePair", genericType.TypeArguments.ToList());
            return true;
        }

        if (genericType.TypeArguments.Count != 1)
        {
            return false;
        }

        if (IsSpanTypeName(name) || IsCollectionType(genericType, out elementType))
        {
            if (BuiltInTypes.IsUnknown(elementType))
            {
                elementType = genericType.TypeArguments[0];
            }

            return true;
        }

        return false;
    }

    private static bool IsDictionaryTypeName(string name)
        => name is "Dictionary" or "IDictionary" or "IReadOnlyDictionary"
            or "SortedDictionary" or "SortedList"
            || name.EndsWith(".Dictionary", StringComparison.Ordinal)
            || name.EndsWith(".IDictionary", StringComparison.Ordinal)
            || name.EndsWith(".IReadOnlyDictionary", StringComparison.Ordinal)
            || name.EndsWith(".SortedDictionary", StringComparison.Ordinal)
            || name.EndsWith(".SortedList", StringComparison.Ordinal);

    private bool TryGetSourceLoopSequenceElementType(
        IEnumerable<TypeReference> interfaceReferences,
        bool requireAsync,
        out TypeInfo elementType)
    {
        foreach (var interfaceReference in interfaceReferences)
        {
            var interfaceType = ResolveType(interfaceReference);
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
                elementType = ConvertReflectionType(elementReflectionType);
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

        elementType = ConvertReflectionType(type.GenericTypeArguments[0]);
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

            elementType = ConvertReflectionType(sequenceInterface.GenericTypeArguments[0]);
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

            elementType = ConvertReflectionType(currentProperty.PropertyType);
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
            var expectedReturnValueType = _currentFunctionIsAsync && TryGetTaskLikeResultType(_currentReturnType, out var asyncResultType)
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
                var (line, column, length) = GetExpressionDiagnosticSpan(returnStmt.Value);
                Error(
                    ErrorCode.InvalidSyntax,
                    "Generator functions cannot return a value",
                    line,
                    column,
                    "Use `yield value` to produce sequence values, or a bare `return`/`yield break` to stop iteration.",
                    length);
                return;
            }

            if (!IsAssignable(expectedReturnValueType, returnedType))
            {
                // Use ErrorMessageBuilder for better error message
                var sourceSnippet = _sourceLines != null && returnStmt.Line > 0 && returnStmt.Line <= _sourceLines.Length
                    ? _sourceLines[returnStmt.Line - 1]
                    : null;

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
            if (_currentReturnType != BuiltInTypes.Void && !(_currentFunctionIsAsync && IsUnitTaskLikeType(_currentReturnType)))
            {
                var sourceSnippet = _sourceLines != null && returnStmt.Line > 0 && returnStmt.Line <= _sourceLines.Length
                    ? _sourceLines[returnStmt.Line - 1]
                    : null;

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
            ? GetFunctionNameDiagnosticSpan(_currentFunction)
            : returnStmt.Value != null
            ? GetExpressionDiagnosticSpan(returnStmt.Value)
            : (returnStmt.Line, returnStmt.Column, 6);
        var diagnosticSourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
            ? _sourceLines[diagnosticLine - 1]
            : sourceSnippet;

        if (_currentReturnType == BuiltInTypes.Void)
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
            ? GetFunctionNameDiagnosticSpan(func)
            : func.ExpressionBody != null
            ? GetExpressionDiagnosticSpan(func.ExpressionBody)
            : (fallbackLine ?? func.Line, fallbackColumn ?? func.Column, 1);
        var sourceSnippet = _sourceLines != null && line > 0 && line <= _sourceLines.Length
            ? _sourceLines[line - 1]
            : null;

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

        if (_currentReturnType == BuiltInTypes.Void)
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
                ? ResolveDeclaredType(catchClause.ExceptionType)
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

        var span = GetTypeReferenceStartSpan(typeReference);
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

        var span = GetTypeReferenceStartSpan(typeReference);
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

        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
        var resolved = ResolveTypeAlias(type);

        while (resolved is ObliviousTypeInfo oblivious)
        {
            resolved = ResolveTypeAlias(oblivious.InnerType);
        }

        if (resolved == BuiltInTypes.Null || resolved == BuiltInTypes.Never)
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
            return IsReflectionAssignableFrom(typeof(Exception), reflectionType.Type);
        }

        if (resolved is SimpleTypeInfo simple)
        {
            if (simple.Name is "Exception" or "System.Exception")
            {
                return true;
            }

            if (LookupType(simple.Name) is { } namedType && !ReferenceEquals(namedType, resolved))
            {
                return IsThrowableType(namedType);
            }

            if (TryConvertTypeInfoToClrType(resolved) is { } clrType)
            {
                return IsReflectionAssignableFrom(typeof(Exception), clrType);
            }

            return false;
        }

        if (resolved is ClassTypeInfo classType)
        {
            return classType.Declaration.BaseClass != null
                && IsThrowableType(ResolveType(classType.Declaration.BaseClass));
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
                && LookupSymbol(usingStmt.Declaration.Name) is { } resourceType)
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

        var (line, column, length) = GetVariableDeclarationNameDiagnosticSpan(declaration);
        ReportNonDisposableUsingResource(resourceType, line, column, length);
    }

    private void ReportNonDisposableUsingResourceIfNeeded(Expression expression, TypeInfo resourceType)
    {
        if (IsDisposableUsingResourceType(resourceType))
        {
            return;
        }

        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
        var resolved = ResolveTypeAlias(type);
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
                var innerType = ResolveTypeAlias(nullable.InnerType);
                return IsReferenceType(innerType) && IsDisposableUsingResourceType(innerType);
            case SimpleTypeInfo simple when LookupType(simple.Name) is { } namedType && !ReferenceEquals(namedType, resolved):
                return IsDisposableUsingResourceType(namedType);
            case GenericTypeInfo generic when LookupType(generic.Name) is { } genericDefinition:
                return IsDisposableUsingResourceType(genericDefinition);
        }

        return HasDisposePattern(resolved) || IsNominallyIDisposable(resolved);
    }

    private bool HasDisposePattern(TypeInfo type)
    {
        type = ResolveTypeAlias(type);
        return type switch
        {
            ClassTypeInfo classType => HasDisposePatternMember(classType.Declaration.Members),
            StructTypeInfo structType => HasDisposePatternMember(structType.Declaration.Members),
            RecordTypeInfo recordType => HasDisposePatternMember(recordType.Declaration.Members),
            InterfaceTypeInfo interfaceType => HasDisposePatternMember(interfaceType.Declaration.Members),
            ReflectionTypeInfo reflectionType => HasReflectionDisposePattern(reflectionType.Type),
            _ => false
        };
    }

    private bool HasDisposePatternMember(IEnumerable<Declaration> members)
    {
        foreach (var member in members)
        {
            if (member is not FunctionDeclaration { Name: nameof(IDisposable.Dispose) } function
                || function.Modifiers.HasFlag(Modifiers.Static)
                || function.Parameters.Count != 0)
            {
                continue;
            }

            if (function.ReturnType == null || ResolveType(function.ReturnType) == BuiltInTypes.Void)
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
        type = ResolveTypeAlias(type);
        return type switch
        {
            ReflectionTypeInfo reflectionType => IsReflectionAssignableFrom(typeof(IDisposable), reflectionType.Type),
            ClassTypeInfo or StructTypeInfo or RecordTypeInfo or InterfaceTypeInfo =>
                IsSubtypeOf(type, new ReflectionTypeInfo(typeof(IDisposable))),
            _ => false
        };
    }

    private void AnalyzeLockStatement(LockStatement lockStmt)
    {
        // NL320 (the CS0185 analog): the lockee must be a reference type. Monitor locks on object
        // IDENTITY — a value-typed lockee has none (it would be boxed into a fresh object per lock,
        // guarding nothing), and the IL emitter's `stloc` of a raw value into an object local is
        // unverifiable IL that segfaults the process inside Monitor.Enter.
        var lockeeType = ResolveTypeAlias(AnalyzeExpression(lockStmt.LockObject));

        if (lockeeType is SoaRowTypeInfo)
        {
            ReportSoaRowEscape(lockStmt.LockObject, "locked");
        }
        else if (!ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(lockStmt.LockObject, "locked")
                 && lockeeType is SimpleTypeInfo named
                 && TryGetEnclosingTypeParameter(named.Name, out var isReferenceConstrained))
        {
            // Stricter than C# by design: Roslyn boxes an unconstrained T (a lock that can never
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
        var (line, column, length) = GetExpressionDiagnosticSpan(lockee);
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
                var constraintType = ResolveTypeAlias(ResolveType(constraintTypeRef));
                var isClassConstraint = constraintType switch
                {
                    ClassTypeInfo => true,
                    RecordTypeInfo record => !record.Declaration.IsStruct,
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
    /// the inverse of <see cref="IsReferenceType"/> would false-positive: that predicate answers
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
                var resolved = LookupType(simple.Name);
                return resolved != null && resolved is not SimpleTypeInfo && IsKnownValueTypeLockee(resolved);
            case StructTypeInfo:
            case EnumTypeInfo:
            case TupleTypeInfo: // ValueTuple
                return true;
            case RecordTypeInfo record:
                return record.Declaration.IsStruct;
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
                            GetPatternNameDiagnosticSpan(identPattern);
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
                            GetPatternNameDiagnosticSpan(unionPattern);
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
                                GetPatternNameDiagnosticSpan(unionPattern);
                            Error(ErrorCode.InvalidPattern,
                                $"Union case '{caseName}' doesn't carry any data — you can't destructure it with property patterns",
                                diagnosticLine, diagnosticColumn, length: diagnosticLength);
                        }
                        else if (matchingCase.Properties.Count == 0)
                        {
                            var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                                GetPatternNameDiagnosticSpan(unionPattern);
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
                                    var propType = ResolveTypeWithSubstitution(caseProperty.Type, unionSubstitution);

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
                                            GetPropertyPatternNameDiagnosticSpan(propPattern, pattern.Line, pattern.Column);
                                        DeclareSymbol(bindingName, propType, bindingLine, bindingColumn);
                                    }
                                }
                                else
                                {
                                    var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                                        GetPropertyPatternNameDiagnosticSpan(propPattern, pattern.Line, pattern.Column);
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
                        GetListPatternDiagnosticSpan(listPattern);
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
                var targetType = ResolveType(typePattern.Type);

                // Check if pattern is provably impossible
                if (!IsPatternPossible(valueType, targetType))
                {
                    var (impossibleLine, impossibleColumn, impossibleLength) =
                        GetPatternNameDiagnosticSpan(typePattern);
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
        valueType = ResolveTypeAlias(valueType);
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
        var resolvedValueType = ResolveTypeAlias(GetNonNullableType(valueType));
        var resolvedPatternValueType = ResolveTypeAlias(GetNonNullableType(patternValueType));
        if (BuiltInTypes.IsUnknown(resolvedValueType) || BuiltInTypes.IsUnknown(resolvedPatternValueType))
        {
            return;
        }

        var allowBool = IsEqualityPatternOperator(pattern.Operator);
        if (IsNullableRelationalPatternType(valueType)
            || IsNullableRelationalPatternType(patternValueType)
            || !IsRelationalPatternComparableType(resolvedValueType, allowBool)
            || !IsRelationalPatternComparableType(resolvedPatternValueType, allowBool)
            || !IsAssignable(valueType, patternValueType))
        {
            ReportRelationalPatternTypeMismatch(pattern, valueType, patternValueType);
        }
    }

    private static bool IsEqualityPatternOperator(string op)
        => op is "==" or "!=";

    private bool IsNullableRelationalPatternType(TypeInfo type)
    {
        type = ResolveTypeAlias(type);
        return type is NullableTypeInfo
            || type is ReflectionTypeInfo reflection && Nullable.GetUnderlyingType(reflection.Type) != null;
    }

    private bool IsRelationalPatternComparableType(TypeInfo type, bool allowBool)
    {
        type = ResolveTypeAlias(GetNonNullableType(type));
        if (allowBool && IsBoolType(type))
        {
            return true;
        }

        if (type == BuiltInTypes.Decimal)
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
        // For each property pattern, validate the property exists and analyze nested patterns
        foreach (var propPattern in propertyPatterns)
        {
            // Try to resolve the property on the value type
            TypeInfo? propType = null;

            // Handle different type kinds
            if (valueType is ClassTypeInfo classType)
            {
                // Check for both field and property declarations
                var member = classType.Declaration.Members.FirstOrDefault(m =>
                    (m is FieldDeclaration fd && fd.Name == propPattern.Name) ||
                    (m is PropertyDeclaration pd && pd.Name == propPattern.Name));

                if (member is FieldDeclaration field)
                    propType = field.Type != null ? ResolveType(field.Type) : BuiltInTypes.Unknown;
                else if (member is PropertyDeclaration property)
                    propType = ResolveType(property.Type);
            }
            else if (valueType is StructTypeInfo structType)
            {
                // Check for both field and property declarations
                var member = structType.Declaration.Members.FirstOrDefault(m =>
                    (m is FieldDeclaration fd && fd.Name == propPattern.Name) ||
                    (m is PropertyDeclaration pd && pd.Name == propPattern.Name));

                if (member is FieldDeclaration field)
                    propType = field.Type != null ? ResolveType(field.Type) : BuiltInTypes.Unknown;
                else if (member is PropertyDeclaration property)
                    propType = ResolveType(property.Type);
            }
            else if (valueType is RecordTypeInfo recordType)
            {
                // Check for both field and property declarations
                var member = recordType.Declaration.Members.FirstOrDefault(m =>
                    (m is FieldDeclaration fd && fd.Name == propPattern.Name) ||
                    (m is PropertyDeclaration pd && pd.Name == propPattern.Name));

                if (member is FieldDeclaration field)
                    propType = field.Type != null ? ResolveType(field.Type) : BuiltInTypes.Unknown;
                else if (member is PropertyDeclaration property)
                    propType = ResolveType(property.Type);
            }
            else if (valueType is ReflectionTypeInfo reflectionType)
            {
                // Use reflection to find the property
                var prop = reflectionType.Type.GetProperty(propPattern.Name);
                if (prop != null)
                {
                    propType = NullabilityMetadata.ConvertProperty(prop);
                }
            }

            if (propType == null)
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                    GetPropertyPatternNameDiagnosticSpan(propPattern, line, column);
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
                    GetPropertyPatternNameDiagnosticSpan(propPattern, line, column);
                DeclareSymbol(bindingName, propType, bindingLine, bindingColumn);
            }
        }
    }

    private TypeInfo AnalyzeExpression(Expression expr)
    {
        var type = expr switch
        {
            IntLiteralExpression intLiteral => GetIntLiteralType(intLiteral.Value),
            FloatLiteralExpression floatLiteral => GetFloatLiteralType(floatLiteral.Value),
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
            ThisExpression => GetCurrentTypeScope() ?? BuiltInTypes.Unknown,
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
            && flowType is FunctionTypeInfo { Declaration: null, SyntheticName: { Length: > 0 } } syntheticSoaOperation)
        {
            ReportSyntheticSoaOperationUsedAsValue(expr, syntheticSoaOperation);
            return BuiltInTypes.Unknown;
        }

        if (!_analyzingCallCallee
            && ReportUnsupportedSoaDirectColumnArrayInstanceMethodReferenceIfNeeded(expr, flowType, isCall: false))
        {
            return BuiltInTypes.Unknown;
        }

        if (!_allowUnboundCallableReference && IsUnboundCallableReference(expr, flowType))
        {
            ReportMethodGroupUsedAsValue(expr, flowType);
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

    private bool IsUnboundCallableReference(Expression expression, TypeInfo type)
    {
        if (expression is LambdaExpression)
            return false;

        if (_currentExpectedType != null && CanBindCallableReferenceToExpectedType(_currentExpectedType))
            return false;

        var resolvedType = ResolveTypeAlias(type);
        return IsCallableReferenceType(resolvedType);
    }

    private static bool IsCallableReferenceType(TypeInfo type)
        => IsMethodGroupReferenceType(type)
            || type is FunctionTypeInfo { Declaration: not null };

    private static bool IsMethodGroupReferenceType(TypeInfo type)
        => type is ReflectionMethodInfo
            or ReflectionMethodGroupInfo
            or NSharpMethodGroupInfo;

    private void ReportSyntheticSoaOperationUsedAsValue(Expression expression, FunctionTypeInfo operation)
    {
        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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

    private bool CanBindCallableReferenceToExpectedType(TypeInfo expectedType)
    {
        var resolvedExpected = ResolveTypeAlias(expectedType);
        return resolvedExpected switch
        {
            FunctionTypeInfo => true,
            GenericTypeInfo { Name: "Func" or "Action" } => true,
            ReflectionTypeInfo reflection => IsDelegateType(reflection.Type) || IsRuntimeDelegateType(reflection.Type),
            ObliviousTypeInfo oblivious => CanBindCallableReferenceToExpectedType(oblivious.InnerType),
            NullableTypeInfo nullable => CanBindCallableReferenceToExpectedType(nullable.InnerType),
            _ => false
        };
    }

    private static bool IsRuntimeDelegateType(Type type)
        => typeof(Delegate).IsAssignableFrom(type)
            && type != typeof(Delegate)
            && type != typeof(MulticastDelegate);

    private void ReportMethodGroupUsedAsValue(Expression expression, TypeInfo type)
    {
        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
        var name = GetCallableReferenceName(expression, type);
        if (!_reportedCallableReferenceDiagnostics.Add((line, column, name)))
            return;

        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.MethodGroupUsedAsValue(
                _currentFilePath,
                line,
                column,
                _sourceLines[line - 1],
                length,
                name));
            return;
        }

        Error(
            ErrorCode.MethodGroupUsedAsValue,
            $"Method '{name}' must be called or passed to a delegate",
            line,
            column,
            $"Call `{name}(...)`, or pass `{name}` to a parameter with a delegate type.",
            length);
    }

    private static string GetCallableReferenceName(Expression expression, TypeInfo type)
    {
        return expression switch
        {
            IdentifierExpression identifier => identifier.Name,
            MemberAccessExpression memberAccess => memberAccess.MemberName,
            ParenthesizedExpression parenthesized => GetCallableReferenceName(parenthesized.Inner, type),
            CheckedExpression checkedExpression => GetCallableReferenceName(checkedExpression.Expression, type),
            UncheckedExpression uncheckedExpression => GetCallableReferenceName(uncheckedExpression.Expression, type),
            _ => type switch
            {
                ReflectionMethodInfo methodInfo => methodInfo.Method.Name,
                ReflectionMethodGroupInfo methodGroup when methodGroup.Methods.Length > 0 => methodGroup.Methods[0].Name,
                NSharpMethodGroupInfo methodGroup when methodGroup.Declarations.Count > 0 => methodGroup.Declarations[0].Name,
                FunctionTypeInfo { Declaration: { } declaration } => declaration.Name,
                _ => "method"
            }
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

        var path = TryGetStableNullPath(expr);
        if (path != null && TryLookupNullState(path, out var state))
            return state;

        return GetDefaultNullState(type);
    }

    private NullState GetDefaultNullState(TypeInfo type)
    {
        var resolved = ResolveTypeAlias(type);

        if (resolved == BuiltInTypes.Null)
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

    private static string FormatNullState(NullState state) => state switch
    {
        NullState.Unknown => "unknown",
        NullState.Null => "null",
        NullState.MaybeNull => "maybe-null",
        NullState.NotNull => "not-null",
        NullState.Oblivious => "oblivious",
        _ => "unknown"
    };

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
        var resolvedExpectedType = ResolveTypeAlias(GetNonNullableType(expectedType));
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

        var (line, column, length) = GetExpressionDiagnosticSpan(endpoint);
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

        // For spread in function calls, we expect the inner expression to be an array or enumerable
        // The C# compiler will handle validation of whether the spread is valid
        // For now, we just return the inner type (the collection type itself)
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
    {
        // Check identifiers inside interpolated strings: $"...{identifier}..."
        var value = strExpr.Value;
        if (value.StartsWith("$\""))
        {
            // Scan for {identifier} patterns and validate each identifier against scope
            for (int i = 2; i < value.Length; i++)
            {
                if (value[i] == '{' && i + 1 < value.Length && value[i + 1] != '{')
                {
                    // Extract the expression inside { }
                    int start = i + 1;
                    int depth = 1;
                    int end = start;
                    while (end < value.Length && depth > 0)
                    {
                        if (value[end] == '{') depth++;
                        else if (value[end] == '}') depth--;
                        if (depth > 0) end++;
                    }

                    if (end > start)
                    {
                        var expr = value.Substring(start, end - start).Trim();
                        // Only validate bare identifiers (e.g. {foo}, {count}).
                        // Complex expressions (method calls, member access, casts, ternaries, etc.)
                        // are left to the C# backend to validate.
                        var ident = expr;
                        var isBareIdentifier = ident.Length > 0 && char.IsLetter(ident[0]) &&
                            ident.All(c => char.IsLetterOrDigit(c) || c == '_');
                        if (isBareIdentifier && !IsKeyword(ident))
                        {
                            var col = strExpr.Column + start;
                            if (!TryResolveIdentifierBindingTarget(ident, strExpr.Line, col, out _))
                            {
                                _errors.Add(CompilerError.Create(
                                    ErrorCode.UndefinedVariable,
                                    $"Undeclared identifier '{ident}' in string interpolation",
                                    strExpr.Line,
                                    col,
                                    ErrorSeverity.Error
                                ));
                            }
                        }
                    }
                    i = end; // skip past the interpolation
                }
            }
        }
        return BuiltInTypes.String;
    }

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

    private static bool IsKeyword(string name) =>
        name is "true" or "false" or "null" or "this" or "base" or "new" or "typeof" or "nameof"
            // Built-in type names (used in casts inside interpolated strings)
            or "int" or "long" or "float" or "double" or "bool" or "string" or "object"
            or "byte" or "sbyte" or "short" or "ushort" or "uint" or "ulong" or "decimal" or "char" or "void";

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
        // e.g., string? ?? throw => string (C# infers this correctly)
        if (expr.Right is ThrowExpression)
        {
            return GetNonNullableType(leftType);
        }

        // Otherwise, the result is the right type (the fallback value)
        // In C#: T? ?? T returns T
        return rightType;
    }

    private void CheckNullCoalesceLeftOperand(BinaryExpression expression, TypeInfo leftType)
    {
        if (CanNullCoalesceCheckForNull(leftType))
        {
            return;
        }

        var (line, column, length) = GetExpressionDiagnosticSpan(expression.Left);
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
                GetBinaryOperandDiagnosticSpan(expr, leftIsWrong, rightIsWrong);
            var opText = GetBinaryOperatorText(expr.Operator);
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
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetBinaryOperatorDiagnosticSpan(expr);
            var opText = GetBinaryOperatorText(expr.Operator);
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
            if (IsAssignable(BuiltInTypes.Bool, overloadResult))
            {
                return BuiltInTypes.Bool;
            }

            var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetBinaryOperatorDiagnosticSpan(expr);
            var opText = GetBinaryOperatorText(expr.Operator);
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
                GetBinaryOperandDiagnosticSpan(expr, leftIsWrong, rightIsWrong);
            var opText = GetBinaryOperatorText(expr.Operator);
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
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetBinaryOperatorDiagnosticSpan(expr);
            var opText = GetBinaryOperatorText(expr.Operator);
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
            if (IsAssignable(BuiltInTypes.Bool, overloadResult))
            {
                return BuiltInTypes.Bool;
            }

            var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetBinaryOperatorDiagnosticSpan(expr);
            var opText = GetBinaryOperatorText(expr.Operator);
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
            GetBinaryOperandDiagnosticSpan(expr, leftIsWrong: true, rightIsWrong: true);
        var opText2 = GetBinaryOperatorText(expr.Operator);
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
    /// Maps an overloadable N# binary operator to its CLR special-method name (e.g. <c>+</c> →
    /// <c>op_Addition</c>). Operators that the analyzer does not resolve through this path return
    /// <c>null</c> so the caller leaves diagnostics unchanged.
    /// </summary>
    private static string? GetBinaryOperatorClrName(BinaryOperator op) => op switch
    {
        BinaryOperator.Add => "op_Addition",
        BinaryOperator.Subtract => "op_Subtraction",
        BinaryOperator.Multiply => "op_Multiply",
        BinaryOperator.Divide => "op_Division",
        BinaryOperator.Modulo => "op_Modulus",
        BinaryOperator.Equal => "op_Equality",
        BinaryOperator.NotEqual => "op_Inequality",
        BinaryOperator.BitwiseAnd => "op_BitwiseAnd",
        BinaryOperator.BitwiseOr => "op_BitwiseOr",
        BinaryOperator.BitwiseXor => "op_ExclusiveOr",
        BinaryOperator.LeftShift => "op_LeftShift",
        BinaryOperator.RightShift => "op_RightShift",
        BinaryOperator.Less => "op_LessThan",
        BinaryOperator.Greater => "op_GreaterThan",
        BinaryOperator.LessOrEqual => "op_LessThanOrEqual",
        BinaryOperator.GreaterOrEqual => "op_GreaterThanOrEqual",
        _ => null
    };

    private static string? GetBinaryOperatorSymbol(BinaryOperator op) => op switch
    {
        BinaryOperator.Add => "+",
        BinaryOperator.Subtract => "-",
        BinaryOperator.Multiply => "*",
        BinaryOperator.Divide => "/",
        BinaryOperator.Modulo => "%",
        BinaryOperator.Equal => "==",
        BinaryOperator.NotEqual => "!=",
        BinaryOperator.BitwiseAnd => "&",
        BinaryOperator.BitwiseOr => "|",
        BinaryOperator.BitwiseXor => "^",
        BinaryOperator.LeftShift => "<<",
        BinaryOperator.RightShift => ">>",
        BinaryOperator.Less => "<",
        BinaryOperator.Greater => ">",
        BinaryOperator.LessOrEqual => "<=",
        BinaryOperator.GreaterOrEqual => ">=",
        _ => null
    };

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

        var clrName = GetBinaryOperatorClrName(op);
        var symbol = GetBinaryOperatorSymbol(op);
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

        var members = operandType switch
        {
            ClassTypeInfo classType => classType.Declaration.Members,
            StructTypeInfo structType => structType.Declaration.Members,
            RecordTypeInfo recordType => recordType.Declaration.Members,
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
        var match = members
            .OfType<FunctionDeclaration>()
            .FirstOrDefault(member =>
                member.IsOperatorOverload
                && member.OperatorSymbol == symbol
                && member.Parameters.Count == 2
                && member.ReturnType != null
                && IsAssignable(ResolveType(member.Parameters[0].Type), left)
                && IsAssignable(ResolveType(member.Parameters[1].Type), right));

        if (match?.ReturnType == null)
        {
            return false;
        }

        result = ResolveType(match.ReturnType);
        return true;
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
            if (!IsRuntimeOperatorParameterCompatible(parameters[0].ParameterType, leftClr)
                || !IsRuntimeOperatorParameterCompatible(parameters[1].ParameterType, rightClr))
            {
                continue;
            }

            result = ConvertReflectionType(candidate.ReturnType);
            return true;
        }

        return false;
    }

    /// <summary>
    /// Resolves the CLR type for an operator operand. Falls back to an MLC lookup of the open
    /// generic definition for imported generics that <see cref="TryConvertTypeInfoToClrType"/>
    /// doesn't special-case (e.g. <c>System.Numerics.Vector&lt;T&gt;</c>), so operator-overload
    /// resolution works for arbitrary imported value types — not just the hardcoded BCL generics.
    /// </summary>
    private Type? TryResolveOperandClrType(TypeInfo operandType)
    {
        var direct = TryConvertTypeInfoToClrType(operandType);
        if (direct != null)
        {
            return direct;
        }

        if (ResolveTypeAlias(operandType) is not GenericTypeInfo generic)
        {
            return null;
        }

        // Resolve the open generic definition (e.g. "Vector`1") from the MLC assemblies, then
        // close it over the converted type arguments.
        var openDefinitionName = $"{generic.Name}`{generic.TypeArguments.Count}";
        if (TryResolveExternalType(openDefinitionName) is not ReflectionTypeInfo { Type: var openType })
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

    private static bool IsRuntimeOperatorParameterCompatible(Type parameterType, Type? argumentType)
    {
        if (argumentType == null)
        {
            // Operand CLR type unknown. We cannot prove this operator applies, and the IL backend
            // would not bind it either (it resolves against concrete argument types). Treat it as
            // incompatible so an unrelated operand can't piggy-back on a vector/struct operator
            // (e.g. `Vector<int> + SomeUserType`) and swallow a genuine type mismatch.
            return false;
        }

            return parameterType.IsAssignableFrom(argumentType)
                || parameterType == argumentType
                || (parameterType.IsByRef && parameterType.GetElementType() == argumentType);
    }

    private static string? GetUnaryOperatorClrName(UnaryOperator op) => op switch
    {
        UnaryOperator.Negate => "op_UnaryNegation",
        UnaryOperator.Not => "op_LogicalNot",
        UnaryOperator.BitwiseNot => "op_OnesComplement",
        UnaryOperator.PreIncrement or UnaryOperator.PostIncrement => "op_Increment",
        UnaryOperator.PreDecrement or UnaryOperator.PostDecrement => "op_Decrement",
        _ => null
    };

    private static string? GetUnaryOperatorSymbol(UnaryOperator op) => op switch
    {
        UnaryOperator.Negate => "-",
        UnaryOperator.Not => "!",
        UnaryOperator.BitwiseNot => "~",
        UnaryOperator.PreIncrement or UnaryOperator.PostIncrement => "++",
        UnaryOperator.PreDecrement or UnaryOperator.PostDecrement => "--",
        _ => null
    };

    private bool TryResolveUnaryOperatorOverloadResult(UnaryOperator op, TypeInfo operand, out TypeInfo result)
    {
        result = BuiltInTypes.Unknown;

        var clrName = GetUnaryOperatorClrName(op);
        var symbol = GetUnaryOperatorSymbol(op);
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

        var members = operandType switch
        {
            ClassTypeInfo classType => classType.Declaration.Members,
            StructTypeInfo structType => structType.Declaration.Members,
            RecordTypeInfo recordType => recordType.Declaration.Members,
            _ => null
        };

        if (members == null)
        {
            return false;
        }

        var match = members
            .OfType<FunctionDeclaration>()
            .FirstOrDefault(member =>
                member.IsOperatorOverload
                && member.OperatorSymbol == symbol
                && member.Parameters.Count == 1
                && member.ReturnType != null
                && IsAssignable(ResolveType(member.Parameters[0].Type), operandType));

        if (match?.ReturnType == null)
        {
            return false;
        }

        result = ResolveType(match.ReturnType);
        return true;
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

            if (!IsRuntimeOperatorParameterCompatible(parameters[0].ParameterType, clrType))
            {
                continue;
            }

            result = ConvertReflectionType(candidate.ReturnType);
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
                GetBinaryOperandDiagnosticSpan(expr, leftIsWrong, rightIsWrong);
            var opText = GetBinaryOperatorText(expr.Operator);
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
                $"changed with '{GetUnaryOperatorSymbol(unary.Operator) ?? "operator"}'"))
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
                GetUnaryOperatorSymbol(unary.Operator) ?? "operator",
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

        if (!IsAssignable(BuiltInTypes.Int, operandType))
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

        if (IsBoolType(ResolveTypeAlias(operandType)))
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

        var opText = GetUnaryOperatorSymbol(unary.Operator) ?? "operator";
        var (line, column, length) = GetExpressionDiagnosticSpan(unary.Operand);
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

        var resolved = ResolveTypeAlias(operandType);
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

            // Check file import aliases
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
                var memberColumn = GetMemberNameColumn(member);
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

            // Check namespace import aliases (handled by existing TryResolveExternalType)
        }

        var objectType = AnalyzeExpression(member.Object);

        if (TryResolveNullableMemberAccess(member, objectType, out var nullableMemberType))
        {
            return nullableMemberType;
        }

        ReportPossibleNullAccess(member.Object, objectType, member.Line, member.Column, "dereference", member.IsNullConditional);
        var receiverType = ResolveTypeAlias(GetNonNullableType(objectType));
        if (receiverType is ByRefTypeInfo byRefReceiver)
            receiverType = ResolveTypeAlias(GetNonNullableType(byRefReceiver.InnerType));

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
            && TryGetSoaColumn(soaRowType.Declaration, member.MemberName) is null)
        {
            ReportSoaRowEscape(member.Object, "used as a member receiver");
            return BuiltInTypes.Unknown;
        }

        ValidateDeclaredMemberVisibility(receiverType, member);
        TryRecordMemberBinding(receiverType, member);

        // Resolve member on type
        var includeStaticMembers = IsStaticMemberAccessTarget(member.Object);
        var memberType = ResolveMember(receiverType, member.MemberName, includeStaticMembers);
        if (BuiltInTypes.IsUnknown(memberType) && ShouldReportUndefinedMember(receiverType, member, includeStaticMembers))
        {
            ReportUndefinedMember(receiverType, member, includeStaticMembers);
        }
        else if (receiverType is SoaRecordTypeInfo soaRecordType
                 && TryGetSoaColumn(soaRecordType.Declaration, member.MemberName) != null)
        {
            _soaColumnMemberAccesses.Add(member);
        }

        return member.IsNullConditional ? MakeNullableResult(memberType) : memberType;
    }

    private TypeInfo AnalyzeIndexAccess(IndexAccessExpression index)
    {
        var objectType = AnalyzeExpression(index.Object);
        ReportPossibleNullAccess(index.Object, objectType, index.Line, index.Column, "index", index.IsNullConditional);

        var receiverType = ResolveTypeAlias(GetNonNullableType(objectType));
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
        var resolvedReceiverType = ResolveTypeAlias(receiverType);
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
        var resolvedReceiverType = ResolveTypeAlias(receiverType);
        var isArrayReceiver = resolvedReceiverType is ArrayTypeInfo
            || resolvedReceiverType is ReflectionTypeInfo { Type.IsArray: true };
        var isStringReceiver = IsStringType(resolvedReceiverType);

        if (!isArrayReceiver && !isStringReceiver)
            return true;

        if (isRangeAccess)
            return true;

        var resolvedIndexType = ResolveTypeAlias(indexType);
        if (BuiltInTypes.IsUnknown(resolvedIndexType)
            || resolvedIndexType == BuiltInTypes.Int
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

        var resolvedIndexType = ResolveTypeAlias(indexType);
        return BuiltInTypes.IsUnknown(resolvedIndexType) || resolvedIndexType == BuiltInTypes.Int;
    }

    private bool ReportNegativeSoaRowIndexIfNeeded(Expression expression, TypeInfo indexType, string targetDescription)
    {
        var resolvedIndexType = ResolveTypeAlias(indexType);
        if (resolvedIndexType != BuiltInTypes.Int
            && resolvedIndexType != BuiltInTypes.Short
            && resolvedIndexType != BuiltInTypes.SByte)
        {
            return false;
        }

        if (!IsConstantNegative(expression))
        {
            return false;
        }

        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
        var resolvedIndexType = ResolveTypeAlias(indexType);
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
        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
        var (line, column, length) = GetExpressionDiagnosticSpan(index);
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

        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
        receiverType = ResolveTypeAlias(receiverType);

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
                    ? ConvertReflectionType(type)
                    : ConvertReflectionType(type.GetElementType()!);

            var indexer = type.GetDefaultMembers()
                .OfType<PropertyInfo>()
                .FirstOrDefault(property => property.GetIndexParameters().Length > 0);

            if (indexer != null)
                return ConvertReflectionType(indexer.PropertyType);
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
        var resolved = ResolveTypeAlias(type);
        return IsIndexLikeType(resolved) || IsAssignable(BuiltInTypes.Int, resolved);
    }

    private TypeInfo GetRangeType()
        => LookupType("System.Range") ?? new ReflectionTypeInfo(typeof(Range));

    private TypeInfo GetIndexType()
        => LookupType("System.Index") ?? new ReflectionTypeInfo(typeof(Index));

    private TypeInfo GetNonNullableType(TypeInfo type)
        => ResolveTypeAlias(type) is NullableTypeInfo nullable ? nullable.InnerType : type;

    private TypeInfo MakeNullableResult(TypeInfo type)
    {
        var resolved = ResolveTypeAlias(type);
        if (resolved == BuiltInTypes.Void
            || resolved == BuiltInTypes.Never
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

        var path = TryGetStableNullPath(receiver) ?? "this value";
        var key = (line, column, path, operation);
        if (!_reportedNullabilityDiagnostics.Add(key))
            return;

        var stateLabel = FormatNullState(nullState);
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

        var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetNullReceiverDiagnosticSpan(receiver, path, line, column);
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
            && TryFindNullableOriginForIdentifier(identifier.Name, out var origin))
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
                    GetMemberNameColumn(member),
                    "Prefer 'must value' for an explicit unwrap, or use 'match value { null => ..., inner => ... }' to handle both cases.",
                    length: Math.Max(1, member.MemberName.Length));
            }

            memberType = nullableType.InnerType;
            return true;
        }

        return false;
    }

    private bool TryFindNullableOriginForIdentifier(string name, out NullableTypeInfo nullableType)
    {
        foreach (var scope in _scopes.Skip(1))
        {
            if (scope.Symbols.TryGetValue(name, out var type)
                && type is NullableTypeInfo nullable)
            {
                nullableType = nullable;
                return true;
            }
        }

        nullableType = null!;
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
            return LookupSymbol(identifier.Name) == null;

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
                if (LookupSymbol(identifier.Name) != null)
                    return false;

                type = ResolveTypeAlias(LookupType(identifier.Name) ?? BuiltInTypes.Unknown);
                if (!BuiltInTypes.IsUnknown(type))
                    return true;

                if (TryResolveBuiltInTypeKeyword(identifier.Name) is { } builtInType)
                {
                    type = new ReflectionTypeInfo(builtInType);
                    return true;
                }

                if (TryResolveExternalType(identifier.Name) is { } externalType)
                {
                    type = externalType;
                    return true;
                }

                return false;

            case MemberAccessExpression memberAccess:
                if (!TryResolveTypeValuedMemberAccess(memberAccess.Object, out var ownerType))
                    return false;

                return TryResolveNestedTypeOnOwner(ownerType, memberAccess.MemberName, out type);

            default:
                return false;
        }
    }

    private bool TryResolveNestedTypeOnOwner(TypeInfo ownerType, string memberName, out TypeInfo nestedType)
    {
        ownerType = ResolveTypeAlias(ownerType);

        var members = ownerType switch
        {
            ClassTypeInfo classType => classType.Declaration.Members,
            StructTypeInfo structType => structType.Declaration.Members,
            RecordTypeInfo recordType => recordType.Declaration.Members,
            InterfaceTypeInfo interfaceType => interfaceType.Declaration.Members,
            _ => null
        };

        if (members != null)
            return TryResolveNestedTypeMember(members, memberName, out nestedType);

        if (ownerType is ReflectionTypeInfo reflectionType
            && reflectionType.Type.GetNestedType(memberName, BindingFlags.Public | BindingFlags.NonPublic) is { } nestedReflectionType)
        {
            nestedType = new ReflectionTypeInfo(nestedReflectionType);
            return true;
        }

        nestedType = BuiltInTypes.Unknown;
        return false;
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
            ReportInaccessibleMember(member.MemberName, filePath, member.Line, GetMemberNameColumn(member));
        }
    }

    private bool TryFindMemberExportVisibility(TypeInfo objectType, string memberName, out bool isExported, out string? filePath)
    {
        isExported = false;
        filePath = null;

        switch (objectType)
        {
            case ClassTypeInfo classType:
                filePath = GetDeclarationFileForType(classType);
                if (TryFindDeclarationMemberNode(classType.Declaration.Members, memberName, out var classMember))
                {
                    isExported = IsExportedByCasingOrModifier(memberName, classMember);
                    return true;
                }
                if (classType.Declaration.BaseClass != null)
                    return TryFindMemberExportVisibility(ResolveType(classType.Declaration.BaseClass), memberName, out isExported, out filePath);
                return false;

            case StructTypeInfo structType:
                filePath = GetDeclarationFileForType(structType);
                if (TryFindDeclarationMemberNode(structType.Declaration.Members, memberName, out var structMember))
                {
                    isExported = IsExportedByCasingOrModifier(memberName, structMember);
                    return true;
                }
                return false;

            case RecordTypeInfo recordType:
                filePath = GetDeclarationFileForType(recordType);
                if (TryFindDeclarationMemberNode(recordType.Declaration.Members, memberName, out var recordMember))
                {
                    isExported = IsExportedByCasingOrModifier(memberName, recordMember);
                    return true;
                }
                return false;

            case InterfaceTypeInfo interfaceType:
                filePath = GetDeclarationFileForType(interfaceType);
                if (TryFindDeclarationMemberNode(interfaceType.Declaration.Members, memberName, out var interfaceMember))
                {
                    isExported = IsExportedByCasingOrModifier(memberName, interfaceMember);
                    return true;
                }
                return false;

            case EnumTypeInfo enumType:
                filePath = GetDeclarationFileForType(enumType);
                if (enumType.Declaration.Members.Any(enumMember => enumMember.Name == memberName))
                {
                    isExported = true;
                    return true;
                }
                return false;

            case UnionTypeInfo { IsAnonymous: false } unionType:
                filePath = GetDeclarationFileForType(unionType);
                if (unionType.Declaration!.Cases.Any(unionCase => unionCase.Name == memberName))
                {
                    isExported = VisibilityConventions.IsExportedIdentifier(memberName);
                    return true;
                }
                return false;

            case AliasTypeInfo aliasType:
                return TryFindMemberExportVisibility(ResolveType(aliasType.AliasedType), memberName, out isExported, out filePath);

            case NullableTypeInfo nullableType:
                return TryFindMemberExportVisibility(nullableType.InnerType, memberName, out isExported, out filePath);

            case ObliviousTypeInfo obliviousType:
                return TryFindMemberExportVisibility(obliviousType.InnerType, memberName, out isExported, out filePath);

            default:
                return false;
        }
    }

    private static bool TryFindDeclarationMemberNode(IEnumerable<Declaration> members, string memberName, out Declaration declaration)
    {
        foreach (var member in members)
        {
            if (GetDeclarationName(member) == memberName)
            {
                declaration = member;
                return true;
            }
        }

        declaration = null!;
        return false;
    }

    private void RecordMemberBinding(MemberAccessExpression member, SymbolDeclaration declaration)
    {
        var memberColumn = GetMemberNameColumn(member);
        _bindingMap.RecordBinding(_currentFilePath, member.Line, memberColumn, member.MemberName.Length, declaration);
    }

    private int GetMemberNameColumn(MemberAccessExpression member)
    {
        var fallbackColumn = member.Column + (member.IsNullConditional ? 2 : 1);
        if (_sourceLines == null || member.Line <= 0 || member.Line > _sourceLines.Length)
            return fallbackColumn;

        var lineText = _sourceLines[member.Line - 1];
        var searchStart = Math.Max(0, member.Column - 1);
        var index = lineText.IndexOf(member.MemberName, searchStart, StringComparison.Ordinal);
        return index >= 0 ? index + 1 : fallbackColumn;
    }

    private bool TryFindMemberDeclaration(TypeInfo objectType, string memberName, out SymbolDeclaration declaration)
    {
        declaration = null!;

        switch (objectType)
        {
            case ClassTypeInfo classType:
                if (TryFindDeclarationMember(classType.Declaration.Members, memberName, GetDeclarationFileForType(classType), out declaration))
                    return true;
                if (classType.Declaration.BaseClass != null)
                    return TryFindMemberDeclaration(ResolveType(classType.Declaration.BaseClass), memberName, out declaration);
                return false;

            case StructTypeInfo structType:
                return TryFindDeclarationMember(structType.Declaration.Members, memberName, GetDeclarationFileForType(structType), out declaration);

            case RecordTypeInfo recordType:
                return TryFindDeclarationMember(recordType.Declaration.Members, memberName, GetDeclarationFileForType(recordType), out declaration);

            case InterfaceTypeInfo interfaceType:
                return TryFindDeclarationMember(interfaceType.Declaration.Members, memberName, GetDeclarationFileForType(interfaceType), out declaration);

            case EnumTypeInfo enumType:
                var enumMember = enumType.Declaration.Members.FirstOrDefault(member => member.Name == memberName);
                if (enumMember != null)
                {
                    declaration = new SymbolDeclaration(memberName, GetDeclarationFileForType(enumType), enumMember.Line, enumMember.Column, "enumMember");
                    return true;
                }
                return false;

            case UnionTypeInfo { IsAnonymous: false } unionType:
                var unionCase = unionType.Declaration!.Cases.FirstOrDefault(unionCase => unionCase.Name == memberName);
                if (unionCase != null)
                {
                    declaration = new SymbolDeclaration(memberName, GetDeclarationFileForType(unionType), unionCase.Line, unionCase.Column, "unionCase");
                    return true;
                }
                return false;

            case AliasTypeInfo aliasType:
                return TryFindMemberDeclaration(ResolveType(aliasType.AliasedType), memberName, out declaration);

            case NullableTypeInfo nullableType:
                return TryFindMemberDeclaration(nullableType.InnerType, memberName, out declaration);

            case ObliviousTypeInfo obliviousType:
                return TryFindMemberDeclaration(obliviousType.InnerType, memberName, out declaration);

            default:
                var extension = _extensionMethods.FirstOrDefault(ext =>
                    ext.Name == memberName
                    && ext.Parameters.Count > 0
                    && IsAssignable(ResolveType(ext.Parameters[0].Type), objectType));
                if (extension != null)
                {
                    declaration = new SymbolDeclaration(extension.Name, _currentFilePath, extension.Line, extension.Column, "function");
                    return true;
                }
                return false;
        }
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
            SimpleTypeInfo simple when simple == BuiltInTypes.Object => false,
            SimpleTypeInfo simple => TryConvertTypeInfoToClrType(simple) != null
                                     || (IsKnownBuiltInReceiverWithoutReflection(simple)
                                         && !IsKnownBuiltInMemberWithoutReflection(simple, memberName, includeStaticMembers)),
            ArrayTypeInfo => TryConvertTypeInfoToClrType(receiverType) != null
                             || !IsKnownBuiltInMemberWithoutReflection(receiverType, memberName, includeStaticMembers),
            GenericTypeInfo => TryConvertTypeInfoToClrType(receiverType) != null,
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
            SimpleTypeInfo simple when simple == BuiltInTypes.String =>
                BuiltInStringInstanceMembers.Contains(memberName)
                || (includeStaticMembers && BuiltInStringStaticMembers.Contains(memberName)),
            SimpleTypeInfo simple when simple == BuiltInTypes.Bool =>
                BuiltInBooleanInstanceMembers.Contains(memberName)
                || (includeStaticMembers && BuiltInBooleanStaticMembers.Contains(memberName)),
            SimpleTypeInfo simple when IsBuiltInNumericType(simple) =>
                BuiltInNumericInstanceMembers.Contains(memberName)
                || (includeStaticMembers && BuiltInNumericStaticMembers.Contains(memberName)),
            SimpleTypeInfo simple when simple == BuiltInTypes.Char =>
                BuiltInNumericInstanceMembers.Contains(memberName)
                || (includeStaticMembers && BuiltInNumericStaticMembers.Contains(memberName)),
            ArrayTypeInfo => BuiltInArrayMembers.Contains(memberName),
            _ => false
        };
    }

    private static bool IsKnownBuiltInReceiverWithoutReflection(SimpleTypeInfo type)
        => type == BuiltInTypes.String
           || type == BuiltInTypes.Bool
           || type == BuiltInTypes.Char
           || IsBuiltInNumericType(type);

    private static bool IsBuiltInNumericType(SimpleTypeInfo type)
        => type == BuiltInTypes.Int
           || type == BuiltInTypes.Long
           || type == BuiltInTypes.Float
           || type == BuiltInTypes.Double
           || type == BuiltInTypes.Decimal
           || type == BuiltInTypes.Byte
           || type == BuiltInTypes.SByte
           || type == BuiltInTypes.Short
           || type == BuiltInTypes.UShort
           || type == BuiltInTypes.UInt
           || type == BuiltInTypes.ULong;

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
            AliasTypeInfo alias => ResolveAliasAndMetadata(ResolveType(alias.AliasedType)),
            ObliviousTypeInfo oblivious => ResolveAliasAndMetadata(oblivious.InnerType),
            _ => typeInfo
        };

    private void ReportUndefinedMember(TypeInfo receiverType, MemberAccessExpression member, bool includeStaticMembers)
        => ReportUndefinedMember(receiverType, member.MemberName, member.Line, GetMemberNameColumn(member), includeStaticMembers);

    private void ReportUndefinedMember(
        TypeInfo receiverType,
        string memberName,
        int line,
        int column,
        bool includeStaticMembers,
        string? typeNameOverride = null)
    {
        var length = Math.Max(1, memberName.Length);
        var typeName = typeNameOverride ?? NullabilityMetadata.FormatTypeInfo(receiverType);
        var similarMembers = FindSimilarMemberNames(receiverType, memberName, includeStaticMembers);

        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.UndefinedMember(
                _currentFilePath,
                line,
                column,
                _sourceLines[line - 1],
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

    private List<string> GetAvailableMemberNames(TypeInfo receiverType, bool includeStaticMembers)
    {
        receiverType = ResolveAliasAndMetadata(receiverType);

        if (receiverType is NullableTypeInfo nullableType)
        {
            var members = new List<string> { "HasValue", "Value" };
            members.AddRange(GetAvailableMemberNames(nullableType.InnerType, includeStaticMembers));
            return members;
        }

        if (receiverType is SimpleTypeInfo or GenericTypeInfo or ArrayTypeInfo)
        {
            var clrType = TryConvertTypeInfoToClrType(receiverType);
            if (clrType != null)
                return GetReflectionMemberNames(clrType, includeStaticMembers);
        }

        if (receiverType is ReflectionTypeInfo reflectionType)
        {
            return GetReflectionMemberNames(reflectionType.Type, includeStaticMembers);
        }

        if (receiverType is ClassTypeInfo classType)
        {
            var members = GetDeclaredMemberNames(classType.Declaration.Members);
            members.AddRange(GetPrimaryConstructorParameterNames(classType.Declaration.PrimaryConstructorParameters, includeStaticMembers));
            members.AddRange(GetSourceObjectMemberNames(includeStaticMembers));
            if (classType.Declaration.BaseClass != null)
                members.AddRange(GetAvailableMemberNames(ResolveType(classType.Declaration.BaseClass), includeStaticMembers));
            return members;
        }

        if (receiverType is StructTypeInfo structType)
        {
            var members = GetDeclaredMemberNames(structType.Declaration.Members);
            members.AddRange(GetPrimaryConstructorParameterNames(structType.Declaration.PrimaryConstructorParameters, includeStaticMembers));
            members.AddRange(GetSourceObjectMemberNames(includeStaticMembers));
            return members;
        }

        if (receiverType is RecordTypeInfo recordType)
        {
            var members = GetDeclaredMemberNames(recordType.Declaration.Members);
            members.AddRange(GetPrimaryConstructorParameterNames(recordType.Declaration.PrimaryConstructorParameters, includeStaticMembers));
            members.AddRange(GetSourceObjectMemberNames(includeStaticMembers));
            return members;
        }

        if (receiverType is SoaRecordTypeInfo soaRecordType)
        {
            if (includeStaticMembers)
                return new List<string> { "wrap" };

            var members = soaRecordType.Declaration.Columns.Select(column => column.Name).ToList();
            members.AddRange(new[] { "length", "capacity", "add", "clear", "ensureCapacity", "copyRow" });
            return members;
        }

        if (receiverType is SoaRowTypeInfo soaRowType)
        {
            return soaRowType.Declaration.Columns.Select(column => column.Name).ToList();
        }

        if (receiverType is InterfaceTypeInfo interfaceType)
        {
            var members = GetDeclaredMemberNames(interfaceType.Declaration.Members);
            members.AddRange(GetSourceObjectMemberNames(includeStaticMembers));
            return members;
        }

        if (receiverType is EnumTypeInfo enumType)
        {
            var members = enumType.Declaration.Members.Select(member => member.Name).ToList();
            members.AddRange(GetSourceObjectMemberNames(includeStaticMembers));
            return members;
        }

        if (receiverType is TupleTypeInfo tupleType)
        {
            var members = GetTupleMemberNames(tupleType);
            members.AddRange(GetSourceObjectMemberNames(includeStaticMembers));
            return members;
        }

        if (receiverType is UnionTypeInfo { IsAnonymous: true })
            return new List<string> { "Index", "Value" };

        if (receiverType is UnionTypeInfo { IsAnonymous: false } unionType)
            return unionType.Declaration!.Cases.Select(unionCase => unionCase.Name).ToList();

        if (receiverType is NewtypeInfo)
            return new List<string> { "Value", "ToString", "Equals", "GetHashCode" };

        return new List<string>();
    }

    private static List<string> GetDeclaredMemberNames(IEnumerable<Declaration> members)
        => members
            .Select(GetDeclarationName)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Cast<string>()
            .ToList();

    private static IEnumerable<string> GetPrimaryConstructorParameterNames(
        List<Parameter>? parameters,
        bool includeStaticMembers)
    {
        return includeStaticMembers || parameters == null
            ? Enumerable.Empty<string>()
            : parameters.Select(parameter => parameter.Name);
    }

    private static IEnumerable<string> GetSourceObjectMemberNames(bool includeStaticMembers)
        => includeStaticMembers
            ? Enumerable.Empty<string>()
            : GetReflectionMemberNames(typeof(object), includeStaticMembers);

    private static List<string> GetTupleMemberNames(TupleTypeInfo tupleType)
    {
        var members = new List<string>();
        for (var i = 0; i < tupleType.Elements.Count; i++)
        {
            members.Add($"Item{i + 1}");
            var name = tupleType.Elements[i].Name;
            if (!string.IsNullOrWhiteSpace(name))
                members.Add(name);
        }

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

    private string? GetDeclarationFileForType(TypeInfo typeInfo) => typeInfo switch
    {
        ClassTypeInfo classType => GetDeclarationFilePath(classType.Declaration.Name, classType.Declaration),
        StructTypeInfo structType => GetDeclarationFilePath(structType.Declaration.Name, structType.Declaration),
        RecordTypeInfo recordType => GetDeclarationFilePath(recordType.Declaration.Name, recordType.Declaration),
        InterfaceTypeInfo interfaceType => GetDeclarationFilePath(interfaceType.Declaration.Name, interfaceType.Declaration),
        EnumTypeInfo enumType => GetDeclarationFilePath(enumType.Declaration.Name, enumType.Declaration),
        UnionTypeInfo { IsAnonymous: false } unionType => GetDeclarationFilePath(unionType.Declaration!.Name, unionType.Declaration),
        _ => _currentFilePath
    };

    private string? GetDeclarationFilePath(string typeName, Declaration? declaration = null)
    {
        if (declaration != null
            && _projectSymbols.TryGetValue(typeName, out var symbols))
        {
            foreach (var symbol in symbols)
            {
                if (TypeInfoContainsDeclaration(symbol.Type, declaration))
                    return symbol.SourceFile;
            }
        }

        return _typeDeclarationFiles.TryGetValue(typeName, out var filePath)
            ? filePath
            : _currentFilePath;
    }

    private static bool TypeInfoContainsDeclaration(TypeInfo typeInfo, Declaration declaration) => typeInfo switch
    {
        ClassTypeInfo classType => ReferenceEquals(classType.Declaration, declaration),
        StructTypeInfo structType => ReferenceEquals(structType.Declaration, declaration),
        RecordTypeInfo recordType => ReferenceEquals(recordType.Declaration, declaration),
        InterfaceTypeInfo interfaceType => ReferenceEquals(interfaceType.Declaration, declaration),
        EnumTypeInfo enumType => ReferenceEquals(enumType.Declaration, declaration),
        UnionTypeInfo unionType => ReferenceEquals(unionType.Declaration, declaration),
        NullableTypeInfo nullableType => TypeInfoContainsDeclaration(nullableType.InnerType, declaration),
        ObliviousTypeInfo obliviousType => TypeInfoContainsDeclaration(obliviousType.InnerType, declaration),
        _ => false
    };

    private bool TryFindDeclarationMember(IEnumerable<Declaration> members, string memberName, string? filePath, out SymbolDeclaration declaration)
    {
        foreach (var member in members)
        {
            if (GetDeclarationName(member) != memberName)
                continue;

            declaration = CreateSymbolDeclaration(member, filePath);
            return true;
        }

        declaration = null!;
        return false;
    }

    private SymbolDeclaration CreateSymbolDeclaration(Declaration declaration, string? filePath)
    {
        var name = GetDeclarationName(declaration) ?? string.Empty;
        var sourceText = TryGetProjectSourceText(filePath);
        return new SymbolDeclaration(
            name,
            filePath,
            declaration.Line,
            FindIdentifierNameColumn(sourceText, name, declaration.Line, declaration.Column),
            GetDeclarationKind(declaration));
    }

    private static string? GetDeclarationName(Declaration declaration) => declaration switch
    {
        FunctionDeclaration function => function.Name,
        FieldDeclaration field => field.Name,
        PropertyDeclaration property => property.Name,
        ClassDeclaration classDecl => classDecl.Name,
        StructDeclaration structDecl => structDecl.Name,
        RecordDeclaration recordDecl => recordDecl.Name,
        SoaRecordDeclaration soaRecordDecl => soaRecordDecl.Name,
        InterfaceDeclaration interfaceDecl => interfaceDecl.Name,
        EnumDeclaration enumDecl => enumDecl.Name,
        UnionDeclaration unionDecl => unionDecl.Name,
        TypeAliasDeclaration aliasDecl => aliasDecl.Name,
        NewtypeDeclaration newtypeDecl => newtypeDecl.Name,
        _ => null
    };

    private static string GetDeclarationKind(Declaration declaration) => declaration switch
    {
        FunctionDeclaration => "function",
        FieldDeclaration => "field",
        PropertyDeclaration => "property",
        ClassDeclaration => "class",
        StructDeclaration => "struct",
        RecordDeclaration => "record",
        SoaRecordDeclaration => "soaRecord",
        InterfaceDeclaration => "interface",
        EnumDeclaration => "enum",
        UnionDeclaration => "union",
        TypeAliasDeclaration => "typeAlias",
        NewtypeDeclaration => "newtype",
        _ => "variable"
    };

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

        objectType = ResolveTypeAlias(objectType);

        if (objectType is NullableTypeInfo nullableType)
        {
            if (memberName == "HasValue")
                return BuiltInTypes.Bool;
            if (memberName == "Value")
                return nullableType.InnerType;
        }

        if (objectType is SoaRowTypeInfo soaRowType)
        {
            if (TryGetSoaColumn(soaRowType.Declaration, memberName) is { } rowColumn)
                return ResolveType(rowColumn.Type);

            return BuiltInTypes.Unknown;
        }

        if (objectType is SoaRecordTypeInfo soaRecordType)
        {
            if (!includeStaticMembers)
            {
                if (TryGetSoaColumn(soaRecordType.Declaration, memberName) is { } column)
                    return new ArrayTypeInfo(ResolveType(column.Type));

                return memberName switch
                {
                    "length" or "capacity" => BuiltInTypes.Int,
                    "add" => CreateSoaIntrinsicFunction("add", BuiltInTypes.Int),
                    "clear" => CreateSoaIntrinsicFunction("clear", BuiltInTypes.Void),
                    "ensureCapacity" => CreateSoaIntrinsicFunction("ensureCapacity", BuiltInTypes.Void, ("capacity", BuiltInTypes.Int)),
                    "copyRow" => CreateSoaIntrinsicFunction("copyRow", BuiltInTypes.Void, ("from", BuiltInTypes.Int), ("to", BuiltInTypes.Int)),
                    _ => BuiltInTypes.Unknown
                };
            }

            if (memberName == "wrap")
            {
                var parameters = soaRecordType.Declaration.Columns
                    .Select(column => (Name: column.Name, Type: new ArrayTypeInfo(ResolveType(column.Type)) as TypeInfo))
                    .Concat(new[] { (Name: "length", Type: BuiltInTypes.Int as TypeInfo) })
                    .ToList();
                return new FunctionTypeInfo(null)
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
            && objectType != BuiltInTypes.Null && objectType != BuiltInTypes.Never && objectType != BuiltInTypes.Void)
        {
            var clrType = TryConvertTypeInfoToClrType(objectType);
            if (clrType != null)
                objectType = new ReflectionTypeInfo(clrType);
        }

        if (!includeStaticMembers
            && TryResolveKnownGenericStructuralMember(objectType, memberName, out var structuralMemberType))
        {
            return structuralMemberType;
        }

        if (objectType is GenericTypeInfo or ArrayTypeInfo)
        {
            var clrType = TryConvertTypeInfoToClrType(objectType);
            if (clrType != null)
            {
                objectType = new ReflectionTypeInfo(clrType);
            }
            else
            {
                var bindingClrType = TryConvertTypeInfoToClrTypeForBinding(objectType);
                if (bindingClrType != null &&
                    TryResolveReflectionPropertyOrField(bindingClrType, memberName, includeStaticMembers, out var memberType))
                {
                    return memberType;
                }
            }
        }

        // Handle reflection-based types
        if (objectType is ReflectionTypeInfo reflectionType)
        {
            var type = reflectionType.Type;
            var memberFlags = GetReflectionMemberFlags(includeStaticMembers);

            if (TryResolveReflectionPropertyOrField(type, memberName, includeStaticMembers, out var memberType))
                return memberType;

            // Try methods (get all matching methods to handle overloads)
            var methods = type.GetMethods(memberFlags)
                .Where(m => m.Name == memberName)
                .ToArray();

            if (methods.Length > 0)
            {
                // Return a special type that represents overloaded methods
                return new ReflectionMethodGroupInfo(methods);
            }

            // No member found on reflection type, try extension methods
            return TryResolveExtensionMethod(objectType, memberName);
        }

        // Handle declared types
        if (objectType is ClassTypeInfo classType)
        {
            var resolvedMember = ResolveDeclaredMember(classType.Declaration.Members, memberName);
            if (resolvedMember != null)
                return resolvedMember;

            if (!includeStaticMembers
                && TryResolvePrimaryConstructorParameter(classType.Declaration.PrimaryConstructorParameters, memberName, out var primaryConstructorMember))
            {
                return primaryConstructorMember;
            }

            if (includeStaticMembers
                && TryResolveNestedTypeMember(classType.Declaration.Members, memberName, out var nestedTypeMember))
            {
                return nestedTypeMember;
            }

            // If member not found, check base class
            if (classType.Declaration.BaseClass != null)
            {
                var baseType = ResolveType(classType.Declaration.BaseClass);
                var baseMember = ResolveMember(baseType, memberName, includeStaticMembers);
                if (!BuiltInTypes.IsUnknown(baseMember))
                    return baseMember;
            }

            if (!includeStaticMembers && TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        if (objectType is StructTypeInfo structType)
        {
            var resolvedMember = ResolveDeclaredMember(structType.Declaration.Members, memberName);
            if (resolvedMember != null)
                return resolvedMember;

            if (!includeStaticMembers
                && TryResolvePrimaryConstructorParameter(structType.Declaration.PrimaryConstructorParameters, memberName, out var primaryConstructorMember))
            {
                return primaryConstructorMember;
            }

            if (includeStaticMembers
                && TryResolveNestedTypeMember(structType.Declaration.Members, memberName, out var nestedTypeMember))
            {
                return nestedTypeMember;
            }

            if (!includeStaticMembers && TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        if (objectType is RecordTypeInfo recordType)
        {
            var resolvedMember = ResolveDeclaredMember(recordType.Declaration.Members, memberName);
            if (resolvedMember != null)
                return resolvedMember;

            if (!includeStaticMembers
                && TryResolvePrimaryConstructorParameter(recordType.Declaration.PrimaryConstructorParameters, memberName, out var primaryConstructorMember))
            {
                return primaryConstructorMember;
            }

            if (includeStaticMembers
                && TryResolveNestedTypeMember(recordType.Declaration.Members, memberName, out var nestedTypeMember))
            {
                return nestedTypeMember;
            }

            if (!includeStaticMembers && TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        if (objectType is InterfaceTypeInfo interfaceType)
        {
            var resolvedMember = ResolveDeclaredMember(interfaceType.Declaration.Members, memberName);
            if (resolvedMember != null)
                return resolvedMember;

            if (includeStaticMembers
                && TryResolveNestedTypeMember(interfaceType.Declaration.Members, memberName, out var nestedTypeMember))
            {
                return nestedTypeMember;
            }

            if (!includeStaticMembers && TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        if (objectType is TupleTypeInfo tupleType)
        {
            if (TryResolveTupleMember(tupleType, memberName, out var tupleMember))
                return tupleMember;

            if (!includeStaticMembers && TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        if (objectType is EnumTypeInfo enumType)
        {
            if (includeStaticMembers && enumType.Declaration.Members.Any(member => member.Name == memberName))
                return objectType;

            if (!includeStaticMembers && TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        if (objectType is UnionTypeInfo { IsAnonymous: true })
        {
            return memberName switch
            {
                "Index" => BuiltInTypes.Int,
                "Value" => BuiltInTypes.Object,
                _ => TryResolveExtensionMethod(objectType, memberName)
            };
        }

        if (objectType is UnionTypeInfo { IsAnonymous: false })
        {
            return objectType;
        }

        // Handle newtype .Value access
        if (objectType is NewtypeInfo newtypeInfo)
        {
            if (memberName == "Value")
                return ResolveType(newtypeInfo.UnderlyingType);
            if (!includeStaticMembers && TryResolveSourceObjectMember(memberName, out var objectMember))
                return objectMember;
        }

        // Handle array types
        if (objectType is ArrayTypeInfo arrayType)
        {
            if (memberName == "Length")
                return BuiltInTypes.Int;
        }

        // Member not found on type, try extension methods
        return TryResolveExtensionMethod(objectType, memberName);
    }

    private static bool TryResolveKnownGenericStructuralMember(
        TypeInfo objectType,
        string memberName,
        out TypeInfo memberType)
    {
        if (objectType is GenericTypeInfo genericType
            && GetUnqualifiedGenericTypeName(genericType.Name) == "KeyValuePair"
            && genericType.TypeArguments.Count == 2)
        {
            memberType = memberName switch
            {
                "Key" => genericType.TypeArguments[0],
                "Value" => genericType.TypeArguments[1],
                _ => BuiltInTypes.Unknown
            };

            return !BuiltInTypes.IsUnknown(memberType);
        }

        memberType = BuiltInTypes.Unknown;
        return false;
    }

    private static string GetUnqualifiedGenericTypeName(string name)
    {
        name = GetUnqualifiedTypeName(name);
        var tickIndex = name.IndexOf('`', StringComparison.Ordinal);
        return tickIndex >= 0 ? name[..tickIndex] : name;
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
            memberType = NullabilityMetadata.ConvertProperty(property);
            return true;
        }

        var field = type.GetField(memberName, memberFlags);
        if (field != null)
        {
            memberType = NullabilityMetadata.ConvertField(field);
            return true;
        }

        // .NET events resolve to a distinct symbol (never a field) so that `+=`/`-=` against
        // them is rejected with a friendly diagnostic and `on`/`off` can subscribe via the
        // event's add_/remove_ accessors instead of touching the private backing field.
        var evt = type.GetEvent(memberName, memberFlags);
        if (evt != null)
        {
            memberType = new ReflectionEventInfo(evt);
            return true;
        }

        memberType = BuiltInTypes.Unknown;
        return false;
    }

    private static SoaColumnDeclaration? TryGetSoaColumn(SoaRecordDeclaration declaration, string name)
        => declaration.Columns.FirstOrDefault(column => column.Name == name);

    private static FunctionTypeInfo CreateSoaIntrinsicFunction(
        string syntheticName,
        TypeInfo returnType,
        params (string Name, TypeInfo Type)[] parameters)
    {
        return new FunctionTypeInfo(null)
        {
            SyntheticName = syntheticName,
            ParameterNames = parameters.Select(parameter => parameter.Name).ToList(),
            ParameterTypes = parameters.Select(parameter => parameter.Type).ToList(),
            ReturnType = returnType
        };
    }

    private void ReportSoaRowEscape(Expression expression, string action)
    {
        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
        var (line, column, length) = GetExpressionDiagnosticSpan(member);
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

    /// <summary>
    /// Resolves a member from a list of N#-declared members by name.
    /// Returns NSharpMethodGroupInfo when multiple function overloads exist.
    /// </summary>
    private TypeInfo? ResolveDeclaredMember(List<Declaration> members, string memberName)
    {
        // Collect all matching functions for overload resolution
        var matchingFunctions = new List<FunctionDeclaration>();
        Declaration? firstNonFunction = null;

        foreach (var m in members)
        {
            if (m is FunctionDeclaration func && func.Name == memberName)
            {
                matchingFunctions.Add(func);
            }
            else if (firstNonFunction == null &&
                     ((m is FieldDeclaration fd && fd.Name == memberName) ||
                      (m is PropertyDeclaration pd && pd.Name == memberName)))
            {
                firstNonFunction = m;
            }
        }

        // Fields and properties take priority over functions with the same name
        if (firstNonFunction is FieldDeclaration field)
            return field.Type != null ? ResolveType(field.Type) : BuiltInTypes.Unknown;
        if (firstNonFunction is PropertyDeclaration property)
            return ResolveType(property.Type);

        if (matchingFunctions.Count == 1)
            return CreateFunctionTypeInfo(matchingFunctions[0]);
        if (matchingFunctions.Count > 1)
            return new NSharpMethodGroupInfo(matchingFunctions);

        return null;
    }

    private static bool IsJsonTypeInfoGenericName(string name)
        => name is "JsonTypeInfo" or "System.Text.Json.Serialization.Metadata.JsonTypeInfo";

    private static string GetUnqualifiedTypeName(string value)
    {
        var lastDot = value.LastIndexOf('.');
        return lastDot >= 0 ? value[(lastDot + 1)..] : value;
    }

    private bool TryResolvePrimaryConstructorParameter(
        List<Parameter>? parameters,
        string memberName,
        out TypeInfo memberType)
    {
        if (parameters != null)
        {
            foreach (var parameter in parameters)
            {
                if (parameter.Name == memberName)
                {
                    memberType = ResolveType(parameter.Type);
                    return true;
                }
            }
        }

        memberType = BuiltInTypes.Unknown;
        return false;
    }

    private bool TryResolveNestedTypeMember(
        IEnumerable<Declaration> members,
        string memberName,
        out TypeInfo memberType)
    {
        foreach (var member in members)
        {
            if (!IsNestedTypeDeclaration(member) || GetDeclarationName(member) != memberName)
                continue;

            memberType = CreateTypeInfoForDeclaration(member);
            return true;
        }

        memberType = BuiltInTypes.Unknown;
        return false;
    }

    private bool TryResolveSourceObjectMember(string memberName, out TypeInfo memberType)
    {
        var flags = BindingFlags.Public | BindingFlags.Instance;

        var property = typeof(object).GetProperty(memberName, flags);
        if (property != null)
        {
            memberType = NullabilityMetadata.ConvertProperty(property);
            return true;
        }

        var field = typeof(object).GetField(memberName, flags);
        if (field != null)
        {
            memberType = NullabilityMetadata.ConvertField(field);
            return true;
        }

        var methods = typeof(object).GetMethods(flags)
            .Where(method => method.Name == memberName && !method.IsSpecialName)
            .ToArray();

        if (methods.Length == 1)
        {
            memberType = new ReflectionMethodInfo(methods[0]);
            return true;
        }

        if (methods.Length > 1)
        {
            memberType = new ReflectionMethodGroupInfo(methods);
            return true;
        }

        memberType = BuiltInTypes.Unknown;
        return false;
    }

    private static bool TryResolveTupleMember(TupleTypeInfo tupleType, string memberName, out TypeInfo memberType)
    {
        for (var i = 0; i < tupleType.Elements.Count; i++)
        {
            var element = tupleType.Elements[i];
            if (memberName == $"Item{i + 1}" || memberName == element.Name)
            {
                memberType = element.Type;
                return true;
            }
        }

        memberType = BuiltInTypes.Unknown;
        return false;
    }

    private static bool IsSystemObjectType(Type type)
        => type == typeof(object) || string.Equals(type.FullName, "System.Object", StringComparison.Ordinal);

    private static bool IsNestedTypeDeclaration(Declaration declaration)
        => declaration is ClassDeclaration
            or StructDeclaration
            or RecordDeclaration
            or SoaRecordDeclaration
            or InterfaceDeclaration
            or EnumDeclaration
            or UnionDeclaration
            or TypeAliasDeclaration
            or NewtypeDeclaration;

    private static TypeInfo CreateTypeInfoForDeclaration(Declaration declaration) => declaration switch
    {
        ClassDeclaration classDecl => new ClassTypeInfo(classDecl),
        StructDeclaration structDecl => new StructTypeInfo(structDecl),
        RecordDeclaration recordDecl => new RecordTypeInfo(recordDecl),
        SoaRecordDeclaration soaRecordDecl => new SoaRecordTypeInfo(soaRecordDecl),
        InterfaceDeclaration interfaceDecl => new InterfaceTypeInfo(interfaceDecl),
        EnumDeclaration enumDecl => new EnumTypeInfo(enumDecl),
        UnionDeclaration unionDecl => new UnionTypeInfo(unionDecl),
        TypeAliasDeclaration aliasDecl => new AliasTypeInfo(aliasDecl.Type),
        NewtypeDeclaration newtypeDecl => new NewtypeInfo(newtypeDecl.Name, newtypeDecl.UnderlyingType),
        _ => BuiltInTypes.Unknown
    };

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
                return new ReflectionMethodInfo(externalExtensions[0]);

            if (externalExtensions.Count > 1)
                return new ReflectionMethodGroupInfo(externalExtensions.ToArray());

            return BuiltInTypes.Unknown;
        }

        // Filter by matching this parameter type
        var applicableExtensions = new List<FunctionDeclaration>();
        foreach (var ext in matchingExtensions)
        {
            if (ext.Parameters.Count == 0)
                continue;

            var thisParamType = ResolveType(ext.Parameters[0].Type);

            // Check if targetType is assignable to the extension method's this parameter type
            if (IsAssignable(thisParamType, targetType))
            {
                applicableExtensions.Add(ext);
            }
        }

        if (applicableExtensions.Count == 0)
        {
            var externalExtensions = FindExternalExtensionMethods(targetType, methodName);
            if (externalExtensions.Count == 1)
                return new ReflectionMethodInfo(externalExtensions[0]);

            if (externalExtensions.Count > 1)
                return new ReflectionMethodGroupInfo(externalExtensions.ToArray());

            return BuiltInTypes.Unknown;
        }

        // If only one match, return it
        if (applicableExtensions.Count == 1)
            return CreateFunctionTypeInfo(applicableExtensions[0]);

        // Multiple matches - return method group for overload resolution
        return new NSharpMethodGroupInfo(applicableExtensions);
    }

    private List<MethodInfo> FindExternalExtensionMethods(TypeInfo targetType, string methodName)
    {
        var targetClrType = TryConvertTypeInfoToClrType(targetType)
            ?? TryConvertTypeInfoToClrTypeForBinding(targetType);
        if (targetClrType == null)
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
                    if (method.Name != methodName || !HasExtensionAttribute(method))
                        continue;

                    var parameters = method.GetParameters();
                    if (parameters.Length == 0)
                        continue;

                    if (IsExtensionParameterCompatible(parameters[0].ParameterType, targetClrType))
                        methods.Add(method);
                }
            }
        }

        return methods;
    }

    private static IEnumerable<Type> GetLoadableTypes(Assembly assembly)
    {
        try
        {
            return assembly.GetTypes();
        }
        catch (ReflectionTypeLoadException ex)
        {
            return ex.Types.Where(type => type != null)!;
        }
        catch
        {
            return Array.Empty<Type>();
        }
    }

    private static bool HasExtensionAttribute(MethodInfo method)
    {
            return method.GetCustomAttributesData()
                .Any(a => a.AttributeType.FullName == "System.Runtime.CompilerServices.ExtensionAttribute");
    }

    private bool IsExtensionParameterCompatible(Type parameterType, Type targetClrType)
    {
        if (!parameterType.ContainsGenericParameters)
            return parameterType.IsAssignableFrom(targetClrType);

        return TryFindCompatibleGenericType(parameterType, targetClrType, out _);
    }

    private bool TryFindCompatibleGenericType(Type parameterType, Type actualType, out Type? compatibleType)
    {
        compatibleType = null;

        if (!parameterType.IsGenericType)
            return false;

        var genericDefinition = parameterType.GetGenericTypeDefinition();

        if (actualType.IsGenericType && actualType.GetGenericTypeDefinition() == genericDefinition)
        {
            compatibleType = actualType;
            return true;
        }

        foreach (var iface in actualType.GetInterfaces())
        {
            if (iface.IsGenericType && iface.GetGenericTypeDefinition() == genericDefinition)
            {
                compatibleType = iface;
                return true;
            }
        }

        var currentBase = actualType.BaseType;
        while (currentBase != null)
        {
            if (currentBase.IsGenericType && currentBase.GetGenericTypeDefinition() == genericDefinition)
            {
                compatibleType = currentBase;
                return true;
            }

            currentBase = currentBase.BaseType;
        }

        return false;
    }

    private TypeInfo ConvertReflectionType(Type type)
    {
        // Handle primitive types by FullName (works with both runtime and MLC types)
        return type.FullName switch
        {
            "System.Byte" => BuiltInTypes.Byte,
            "System.SByte" => BuiltInTypes.SByte,
            "System.Int16" => BuiltInTypes.Short,
            "System.UInt16" => BuiltInTypes.UShort,
            "System.Int32" => BuiltInTypes.Int,
            "System.UInt32" => BuiltInTypes.UInt,
            "System.Int64" => BuiltInTypes.Long,
            "System.UInt64" => BuiltInTypes.ULong,
            "System.Char" => BuiltInTypes.Char,
            "System.Single" => BuiltInTypes.Float,
            "System.Double" => BuiltInTypes.Double,
            "System.Decimal" => BuiltInTypes.Decimal,
            "System.Boolean" => BuiltInTypes.Bool,
            "System.String" => BuiltInTypes.String,
            "System.Void" => BuiltInTypes.Void,
            "System.Object" => BuiltInTypes.Object,
            _ when type.IsByRef => ConvertReflectionType(type.GetElementType()!),
            _ when type.IsArray => new ArrayTypeInfo(ConvertReflectionType(type.GetElementType()!)),
            _ when type.IsGenericType => new GenericTypeInfo(
                type.Name[..type.Name.IndexOf('`')],
                type.GetGenericArguments().Select(ConvertReflectionType).ToList()),
            _ => new ReflectionTypeInfo(type)
        };
    }

    /// <summary>
    /// Converts a CLR type to TypeInfo, substituting generic parameters using TypeInfo overrides first,
    /// then falling back to CLR bindings. Used to produce correct TypeInfo for return types and
    /// delegate signatures when some generic parameters are bound to N# types.
    /// </summary>
    private TypeInfo ConvertReflectionTypeWithOverrides(
        Type type,
        Dictionary<Type, TypeInfo> typeInfoOverrides,
        Dictionary<Type, Type>? clrBindings = null)
    {
        if (typeInfoOverrides.Count == 0 && (clrBindings == null || clrBindings.Count == 0))
            return ConvertReflectionType(type);

        // Generic parameter with TypeInfo override takes priority
        if (type.IsGenericParameter && typeInfoOverrides.TryGetValue(type, out var overrideType))
            return overrideType;

        // Generic parameter with CLR binding
        if (type.IsGenericParameter && clrBindings != null && clrBindings.TryGetValue(type, out var boundClrType))
            return ConvertReflectionType(boundClrType);

        if (type.IsByRef)
            return ConvertReflectionTypeWithOverrides(type.GetElementType()!, typeInfoOverrides, clrBindings);

        if (type.IsArray)
            return new ArrayTypeInfo(ConvertReflectionTypeWithOverrides(type.GetElementType()!, typeInfoOverrides, clrBindings));

        if (type.IsGenericType)
        {
            var typeArgs = type.GetGenericArguments()
                .Select(a => ConvertReflectionTypeWithOverrides(a, typeInfoOverrides, clrBindings))
                .ToList();
            var name = type.Name.Contains('`') ? type.Name[..type.Name.IndexOf('`')] : type.Name;
            return new GenericTypeInfo(name, typeArgs);
        }

        return ConvertReflectionType(type);
    }

    /// <summary>
    /// Like TryConvertTypeInfoToClrType but uses typeof(object) as a surrogate for N# user-defined types.
    /// This enables CLR-level method binding to proceed even when some types are N#-defined.
    /// The real N# types are tracked separately via TypeInfo bindings.
    /// </summary>
    private Type? TryConvertTypeInfoToClrTypeForBinding(TypeInfo typeInfo)
    {
        var result = TryConvertTypeInfoToClrType(typeInfo);
        if (result != null) return result;

        if (_wellKnownTypes == null) return null;

        var resolvedType = ResolveTypeAlias(typeInfo);

        // N# user-defined types → object surrogate for CLR binding
        if (resolvedType is ClassTypeInfo or RecordTypeInfo or StructTypeInfo
            or InterfaceTypeInfo or UnionTypeInfo or EnumTypeInfo or NewtypeInfo)
            return _wellKnownTypes.Object;

        // Generic types with N# type arguments - construct with surrogates
        if (resolvedType is GenericTypeInfo genericType)
        {
            var wkt = _wellKnownTypes;
            var typeDefinition = genericType.Name switch
            {
                "List" when genericType.TypeArguments.Count == 1 => wkt.ListOpen,
                "IEnumerable" when genericType.TypeArguments.Count == 1 => wkt.IEnumerableOpen,
                "IQueryable" when genericType.TypeArguments.Count == 1 => wkt.IQueryableOpen,
                "ICollection" when genericType.TypeArguments.Count == 1 => wkt.ICollectionOpen,
                "IList" when genericType.TypeArguments.Count == 1 => wkt.IListOpen,
                "Dictionary" when genericType.TypeArguments.Count == 2 => wkt.DictionaryOpen,
                "IDictionary" when genericType.TypeArguments.Count == 2 => wkt.IDictionaryOpen,
                "Task" when genericType.TypeArguments.Count == 1 => wkt.TaskOpen,
                "ValueTask" when genericType.TypeArguments.Count == 1 => wkt.ValueTaskOpen,
                "Func" when genericType.TypeArguments.Count == 1 => wkt.Func1,
                "Func" when genericType.TypeArguments.Count == 2 => wkt.Func2,
                "Func" when genericType.TypeArguments.Count == 3 => wkt.Func3,
                "Func" when genericType.TypeArguments.Count == 4 => wkt.Func4,
                "Func" when genericType.TypeArguments.Count == 5 => wkt.Func5,
                "Action" when genericType.TypeArguments.Count == 1 => wkt.Action1,
                "Action" when genericType.TypeArguments.Count == 2 => wkt.Action2,
                "Action" when genericType.TypeArguments.Count == 3 => wkt.Action3,
                "Action" when genericType.TypeArguments.Count == 4 => wkt.Action4,
                _ => null
            };

            if (typeDefinition == null) return null;

            var typeArguments = new List<Type>();
            foreach (var typeArgument in genericType.TypeArguments)
            {
                var clrTypeArgument = TryConvertTypeInfoToClrTypeForBinding(typeArgument);
                if (clrTypeArgument == null) return null;
                typeArguments.Add(clrTypeArgument);
            }
            return typeDefinition.MakeGenericType(typeArguments.ToArray());
        }

        // Nullable with N# inner type
        if (resolvedType is NullableTypeInfo nullable)
        {
            var clrInnerType = TryConvertTypeInfoToClrTypeForBinding(nullable.InnerType);
            if (clrInnerType == null || _wellKnownTypes.NullableOpen == null) return null;
            return clrInnerType.IsValueType
                ? _wellKnownTypes.NullableOpen.MakeGenericType(clrInnerType)
                : clrInnerType;
        }

        // Array with N# element type
        if (resolvedType is ArrayTypeInfo array)
            return TryConvertTypeInfoToClrTypeForBinding(array.ElementType)?.MakeArrayType();

        return null;
    }

    /// <summary>
    /// Walks a CLR parameter type and a TypeInfo argument in parallel to extract TypeInfo bindings
    /// for generic parameters. Handles interface compatibility (e.g., List&lt;T&gt; matching IEnumerable&lt;TSource&gt;).
    /// </summary>
    private void PopulateTypeInfoBindingsFromType(
        Type openParameterType,
        TypeInfo argumentTypeInfo,
        Dictionary<Type, TypeInfo> typeInfoBindings)
    {
        if (openParameterType.IsGenericParameter)
        {
            if (!typeInfoBindings.ContainsKey(openParameterType))
                typeInfoBindings[openParameterType] = argumentTypeInfo;
            return;
        }

        if (!openParameterType.IsGenericType || argumentTypeInfo is not GenericTypeInfo argGeneric)
            return;

        var openParamGenDef = openParameterType.GetGenericTypeDefinition();
        var openParamArgs = openParameterType.GetGenericArguments();

        // Direct match: same generic type definition name
        var paramName = openParamGenDef.Name.Contains('`')
            ? openParamGenDef.Name[..openParamGenDef.Name.IndexOf('`')]
            : openParamGenDef.Name;

        if (argGeneric.Name == paramName && openParamArgs.Length == argGeneric.TypeArguments.Count)
        {
            for (int i = 0; i < openParamArgs.Length; i++)
                PopulateTypeInfoBindingsFromType(openParamArgs[i], argGeneric.TypeArguments[i], typeInfoBindings);
            return;
        }

        // Interface/base class match: trace through the CLR type hierarchy to map type arguments
        var argClrType = TryConvertTypeInfoToClrTypeForBinding(argumentTypeInfo);
        if (argClrType == null || !argClrType.IsGenericType) return;

        var argGenDef = argClrType.GetGenericTypeDefinition();

        // Find the interface on the open generic definition that matches the parameter type
        Type? openImpl = argGenDef.GetInterfaces()
            .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == openParamGenDef);

        if (openImpl == null)
        {
            var baseType = argGenDef.BaseType;
            while (baseType != null)
            {
                if (baseType.IsGenericType && baseType.GetGenericTypeDefinition() == openParamGenDef)
                {
                    openImpl = baseType;
                    break;
                }
                baseType = baseType.BaseType;
            }
        }

        if (openImpl == null) return;

        // Map through the interface implementation: e.g. List<T> : IEnumerable<T>
        // openImpl is IEnumerable<T_0> where T_0 is List's open type param
        var implArgs = openImpl.GetGenericArguments();
        var argDefGenArgs = argGenDef.GetGenericArguments();

        for (int i = 0; i < openParamArgs.Length && i < implArgs.Length; i++)
        {
            if (implArgs[i].IsGenericParameter)
            {
                for (int j = 0; j < argDefGenArgs.Length; j++)
                {
                    if (implArgs[i] == argDefGenArgs[j] && j < argGeneric.TypeArguments.Count)
                    {
                        PopulateTypeInfoBindingsFromType(openParamArgs[i], argGeneric.TypeArguments[j], typeInfoBindings);
                        break;
                    }
                }
            }
        }
    }

    /// <summary>
    /// Creates a FunctionTypeInfo from an open delegate type, using TypeInfo overrides for generic
    /// parameters that were bound to N# types. Falls back to CLR bindings for other parameters.
    /// </summary>
    private FunctionTypeInfo? CreateDelegateSignatureFromOpenType(
        Type openDelegateType,
        Dictionary<Type, TypeInfo> typeInfoOverrides,
        Dictionary<Type, Type> clrBindings)
    {
        var resolvedType = ApplyReflectionBindings(openDelegateType, clrBindings);
        if (TryGetExpressionTreeDelegateType(resolvedType, out var expressionDelegateType))
        {
            resolvedType = expressionDelegateType;
            openDelegateType = GetDelegateParameterTypeForLambdaTarget(openDelegateType);
        }

        if (!IsDelegateType(resolvedType))
            return null;

        if (resolvedType.IsGenericType)
        {
            var genDef = resolvedType.GetGenericTypeDefinition();
            var genDefName = genDef.FullName;

            var openTypeArgs = openDelegateType.IsGenericType
                ? openDelegateType.GetGenericArguments()
                : resolvedType.GetGenericArguments();

            var typeArgs = openTypeArgs
                .Select(a => ConvertReflectionTypeWithOverrides(a, typeInfoOverrides, clrBindings))
                .ToList();

            if (genDefName is "System.Action`1" or "System.Action`2" or "System.Action`3" or "System.Action`4")
            {
                return new FunctionTypeInfo(null)
                {
                    ParameterTypes = typeArgs,
                    ParameterModifiers = Enumerable.Repeat(Ast.ParameterModifier.None, typeArgs.Count).ToList(),
                    ReturnType = BuiltInTypes.Void
                };
            }
            if (genDefName is "System.Func`1" or "System.Func`2" or "System.Func`3" or "System.Func`4" or "System.Func`5")
            {
                return new FunctionTypeInfo(null)
                {
                    ParameterTypes = typeArgs.Take(typeArgs.Count - 1).ToList(),
                    ParameterModifiers = Enumerable.Repeat(Ast.ParameterModifier.None, Math.Max(0, typeArgs.Count - 1)).ToList(),
                    ReturnType = typeArgs[^1]
                };
            }
        }

        // Fallback: use the Invoke method on the resolved delegate type
        var invokeMethod = resolvedType.GetMethod("Invoke");
        if (invokeMethod == null)
            return new FunctionTypeInfo(null) { ReturnType = BuiltInTypes.Unknown };

        return new FunctionTypeInfo(null)
        {
            ParameterTypes = invokeMethod.GetParameters()
                .Select(p => NullabilityMetadata.ConvertParameter(
                    p,
                    type => ConvertReflectionTypeWithOverrides(type, typeInfoOverrides, clrBindings)))
                .ToList(),
            ParameterModifiers = invokeMethod.GetParameters()
                .Select(GetReflectionParameterModifier)
                .ToList(),
            ReturnType = NullabilityMetadata.ConvertReturn(
                invokeMethod,
                type => ConvertReflectionTypeWithOverrides(type, typeInfoOverrides, clrBindings))
        };
    }

    private static Type GetDelegateParameterTypeForLambdaTarget(Type parameterType)
    {
        parameterType = GetByRefElementType(parameterType);
        return TryGetExpressionTreeDelegateType(parameterType, out var expressionDelegateType)
            ? expressionDelegateType
            : parameterType;
    }

    private bool IsDelegateType(Type type)
    {
        if (_wellKnownTypes == null) return false;
        return _wellKnownTypes.Delegate.IsAssignableFrom(type)
            && type.FullName != "System.Delegate"
            && type.FullName != "System.MulticastDelegate";
    }

    private static bool TryGetExpressionTreeDelegateType(Type type, out Type delegateType)
    {
        delegateType = typeof(void);

        type = GetByRefElementType(type);
        if (!type.IsGenericType)
            return false;

        Type genericDefinition;
        try
        {
            genericDefinition = type.GetGenericTypeDefinition();
        }
        catch (NotSupportedException)
        {
            return false;
        }

        if (genericDefinition.FullName != "System.Linq.Expressions.Expression`1")
            return false;

        delegateType = type.GetGenericArguments()[0];
        return typeof(Delegate).IsAssignableFrom(delegateType) || delegateType.BaseType?.FullName == "System.MulticastDelegate";
    }

    private FunctionTypeInfo CreateFunctionTypeInfoFromDelegate(Type delegateType)
    {
        if (TryGetExpressionTreeDelegateType(delegateType, out var expressionDelegateType))
            delegateType = expressionDelegateType;

        if (delegateType.IsGenericType)
        {
            var genericDefinition = delegateType.GetGenericTypeDefinition();
            var genDefName = genericDefinition.FullName;
            var typeArguments = delegateType.GetGenericArguments()
                .Select(ConvertReflectionType)
                .ToList();

            if (genDefName is "System.Action`1" or "System.Action`2" or "System.Action`3" or "System.Action`4")
            {
                return new FunctionTypeInfo(null)
                {
                    ParameterTypes = typeArguments,
                    ParameterModifiers = Enumerable.Repeat(Ast.ParameterModifier.None, typeArguments.Count).ToList(),
                    ReturnType = BuiltInTypes.Void
                };
            }

            if (genDefName is "System.Func`1" or "System.Func`2" or "System.Func`3" or "System.Func`4" or "System.Func`5")
            {
                return new FunctionTypeInfo(null)
                {
                    ParameterTypes = typeArguments.Take(typeArguments.Count - 1).ToList(),
                    ParameterModifiers = Enumerable.Repeat(Ast.ParameterModifier.None, Math.Max(0, typeArguments.Count - 1)).ToList(),
                    ReturnType = typeArguments[^1]
                };
            }
        }

        var invokeMethod = delegateType.GetMethod("Invoke");
        if (invokeMethod == null)
            return new FunctionTypeInfo(null) { ReturnType = BuiltInTypes.Unknown };

        var invokeParameters = invokeMethod.GetParameters();

        return new FunctionTypeInfo(null)
        {
            ParameterTypes = invokeParameters
                .Select(parameter => NullabilityMetadata.ConvertParameter(parameter))
                .ToList(),
            ParameterModifiers = invokeParameters
                .Select(GetReflectionParameterModifier)
                .ToList(),
            ReturnType = NullabilityMetadata.ConvertReturn(invokeMethod)
        };
    }

    private FunctionTypeInfo CreateFunctionTypeInfo(FunctionDeclaration func)
    {
        return new FunctionTypeInfo(func)
        {
            ParameterTypes = func.Parameters.Select(parameter => ResolveType(parameter.Type)).ToList(),
            ParameterModifiers = func.Parameters.Select(parameter => parameter.Modifier).ToList(),
            ReturnType = ResolveDeclaredFunctionCallReturnType(func)
        };
    }

    private static Ast.ParameterModifier GetReflectionParameterModifier(ParameterInfo parameter)
    {
        if (!parameter.ParameterType.IsByRef)
            return Ast.ParameterModifier.None;

        return parameter.IsOut ? Ast.ParameterModifier.Out : Ast.ParameterModifier.Ref;
    }

    private Type? TryConvertTypeInfoToClrType(TypeInfo typeInfo)
    {
        var resolvedType = ResolveTypeAlias(typeInfo);
        if (resolvedType is ReflectionTypeInfo reflectionType)
            return reflectionType.Type;

        if (_wellKnownTypes == null)
            return TryConvertBuiltInTypeInfoToRuntimeClrType(resolvedType);

        return resolvedType switch
        {
            SimpleTypeInfo simple when simple == BuiltInTypes.Int => _wellKnownTypes.Int32,
            SimpleTypeInfo simple when simple == BuiltInTypes.Long => _wellKnownTypes.Int64,
            SimpleTypeInfo simple when simple == BuiltInTypes.Float => _wellKnownTypes.Single,
            SimpleTypeInfo simple when simple == BuiltInTypes.Double => _wellKnownTypes.Double,
            SimpleTypeInfo simple when simple == BuiltInTypes.Decimal => _wellKnownTypes.Decimal,
            SimpleTypeInfo simple when simple == BuiltInTypes.Byte => _wellKnownTypes.Byte,
            SimpleTypeInfo simple when simple == BuiltInTypes.SByte => _wellKnownTypes.SByte,
            SimpleTypeInfo simple when simple == BuiltInTypes.Short => _wellKnownTypes.Int16,
            SimpleTypeInfo simple when simple == BuiltInTypes.UShort => _wellKnownTypes.UInt16,
            SimpleTypeInfo simple when simple == BuiltInTypes.UInt => _wellKnownTypes.UInt32,
            SimpleTypeInfo simple when simple == BuiltInTypes.ULong => _wellKnownTypes.UInt64,
            SimpleTypeInfo simple when simple == BuiltInTypes.Char => _wellKnownTypes.Char,
            SimpleTypeInfo simple when simple == BuiltInTypes.Bool => _wellKnownTypes.Boolean,
            SimpleTypeInfo simple when simple == BuiltInTypes.String => _wellKnownTypes.String,
            SimpleTypeInfo simple when simple == BuiltInTypes.Void => _wellKnownTypes.Void,
            SimpleTypeInfo simple when simple == BuiltInTypes.Object => _wellKnownTypes.Object,
            ArrayTypeInfo array => TryConvertTypeInfoToClrType(array.ElementType)?.MakeArrayType(),
            NullableTypeInfo nullable => TryConvertNullableType(nullable.InnerType),
            ObliviousTypeInfo oblivious => TryConvertTypeInfoToClrType(oblivious.InnerType),
            GenericTypeInfo generic => TryConstructKnownGenericType(generic),
            FunctionTypeInfo function => TryConstructDelegateType(function),
            UnionTypeInfo { IsAnonymous: true } anonymousUnion => TryConstructRuntimeUnionType(anonymousUnion),
            _ => null
        };
    }

    private Type? TryConvertBuiltInTypeInfoToRuntimeClrType(TypeInfo typeInfo)
    {
        return typeInfo switch
        {
            SimpleTypeInfo simple when simple == BuiltInTypes.Int => typeof(int),
            SimpleTypeInfo simple when simple == BuiltInTypes.Long => typeof(long),
            SimpleTypeInfo simple when simple == BuiltInTypes.Float => typeof(float),
            SimpleTypeInfo simple when simple == BuiltInTypes.Double => typeof(double),
            SimpleTypeInfo simple when simple == BuiltInTypes.Decimal => typeof(decimal),
            SimpleTypeInfo simple when simple == BuiltInTypes.Byte => typeof(byte),
            SimpleTypeInfo simple when simple == BuiltInTypes.SByte => typeof(sbyte),
            SimpleTypeInfo simple when simple == BuiltInTypes.Short => typeof(short),
            SimpleTypeInfo simple when simple == BuiltInTypes.UShort => typeof(ushort),
            SimpleTypeInfo simple when simple == BuiltInTypes.UInt => typeof(uint),
            SimpleTypeInfo simple when simple == BuiltInTypes.ULong => typeof(ulong),
            SimpleTypeInfo simple when simple == BuiltInTypes.Char => typeof(char),
            SimpleTypeInfo simple when simple == BuiltInTypes.Bool => typeof(bool),
            SimpleTypeInfo simple when simple == BuiltInTypes.String => typeof(string),
            SimpleTypeInfo simple when simple == BuiltInTypes.Void => typeof(void),
            SimpleTypeInfo simple when simple == BuiltInTypes.Object => typeof(object),
            ArrayTypeInfo array => TryConvertBuiltInTypeInfoToRuntimeClrType(array.ElementType)?.MakeArrayType(),
            NullableTypeInfo nullable => TryConvertBuiltInTypeInfoToRuntimeClrType(nullable.InnerType) is { IsValueType: true } innerType
                ? typeof(Nullable<>).MakeGenericType(innerType)
                : null,
            ObliviousTypeInfo oblivious => TryConvertBuiltInTypeInfoToRuntimeClrType(oblivious.InnerType),
            _ => null
        };
    }

    private Type? TryConstructRuntimeUnionType(UnionTypeInfo unionType)
    {
        if (_wellKnownTypes?.RuntimeUnionOpen == null || unionType.Arms.Count != 2)
            return null;

        var firstArm = TryConvertTypeInfoToClrType(unionType.Arms[0]);
        var secondArm = TryConvertTypeInfoToClrType(unionType.Arms[1]);
        if (firstArm == null || secondArm == null)
            return null;

        return _wellKnownTypes.RuntimeUnionOpen.MakeGenericType(firstArm, secondArm);
    }

    private Type? TryConvertNullableType(TypeInfo innerType)
    {
        var clrInnerType = TryConvertTypeInfoToClrType(innerType);
        if (clrInnerType == null || _wellKnownTypes?.NullableOpen == null)
            return null;

        return clrInnerType.IsValueType ? _wellKnownTypes.NullableOpen.MakeGenericType(clrInnerType) : clrInnerType;
    }

    private Type? TryConstructKnownGenericType(GenericTypeInfo genericType)
    {
        var typeDefinition = TryGetKnownOpenGenericType(genericType.Name, genericType.TypeArguments.Count);

        if (typeDefinition == null)
            return null;

        var typeArguments = new List<Type>();
        foreach (var typeArgument in genericType.TypeArguments)
        {
            var clrTypeArgument = TryConvertTypeInfoToClrType(typeArgument)
                ?? (IsJsonTypeInfoGenericName(genericType.Name)
                    ? TryConvertTypeInfoToClrTypeForBinding(typeArgument)
                    : null);
            if (clrTypeArgument == null)
                return null;

            typeArguments.Add(clrTypeArgument);
        }

        return typeDefinition.MakeGenericType(typeArguments.ToArray());
    }

    /// <summary>
    /// Maps compiler-known generic type names (resolvable without imports) to their open
    /// CLR type definitions for the given arity. Shared by generic construction and by
    /// unresolved-type reporting, which must never flag these names.
    /// </summary>
    private Type? TryGetKnownOpenGenericType(string name, int arity)
    {
        if (_wellKnownTypes == null) return null;
        var wkt = _wellKnownTypes;

        return name switch
        {
            "List" when arity == 1 => wkt.ListOpen,
            "IEnumerable" when arity == 1 => wkt.IEnumerableOpen,
            "IQueryable" when arity == 1 => wkt.IQueryableOpen,
            "ICollection" when arity == 1 => wkt.ICollectionOpen,
            "IList" when arity == 1 => wkt.IListOpen,
            "Dictionary" when arity == 2 => wkt.DictionaryOpen,
            "IDictionary" when arity == 2 => wkt.IDictionaryOpen,
            "Task" when arity == 1 => wkt.TaskOpen,
            "ValueTask" when arity == 1 => wkt.ValueTaskOpen,
            "Result" when arity == 2 => wkt.RuntimeResultOpen,
            "NSharpLang.Runtime.Result" when arity == 2 => wkt.RuntimeResultOpen,
            "JsonTypeInfo" when arity == 1 => wkt.JsonTypeInfoOpen,
            "System.Text.Json.Serialization.Metadata.JsonTypeInfo" when arity == 1 => wkt.JsonTypeInfoOpen,
            "Func" when arity == 1 => wkt.Func1,
            "Func" when arity == 2 => wkt.Func2,
            "Func" when arity == 3 => wkt.Func3,
            "Func" when arity == 4 => wkt.Func4,
            "Func" when arity == 5 => wkt.Func5,
            "Action" when arity == 1 => wkt.Action1,
            "Action" when arity == 2 => wkt.Action2,
            "Action" when arity == 3 => wkt.Action3,
            "Action" when arity == 4 => wkt.Action4,
            _ => null
        };
    }

    private Type? TryConstructDelegateType(FunctionTypeInfo functionType)
    {
        if (functionType.ParameterTypes == null || functionType.ReturnType == null || _wellKnownTypes == null)
            return null;

        var clrParameterTypes = new List<Type>();
        foreach (var parameterType in functionType.ParameterTypes)
        {
            var clrParameterType = TryConvertTypeInfoToClrType(parameterType);
            if (clrParameterType == null)
                return null;

            clrParameterTypes.Add(clrParameterType);
        }

        var clrReturnType = TryConvertTypeInfoToClrType(functionType.ReturnType);
        if (clrReturnType == null)
            return null;

        var wkt = _wellKnownTypes;

        if (clrReturnType.FullName == "System.Void")
        {
            return clrParameterTypes.Count switch
            {
                0 => wkt.Action,
                1 => wkt.Action1?.MakeGenericType(clrParameterTypes.ToArray()),
                2 => wkt.Action2?.MakeGenericType(clrParameterTypes.ToArray()),
                3 => wkt.Action3?.MakeGenericType(clrParameterTypes.ToArray()),
                4 => wkt.Action4?.MakeGenericType(clrParameterTypes.ToArray()),
                _ => null
            };
        }

        var funcTypes = clrParameterTypes.Concat(new[] { clrReturnType }).ToArray();
        return clrParameterTypes.Count switch
        {
            0 => wkt.Func1?.MakeGenericType(funcTypes),
            1 => wkt.Func2?.MakeGenericType(funcTypes),
            2 => wkt.Func3?.MakeGenericType(funcTypes),
            3 => wkt.Func4?.MakeGenericType(funcTypes),
            4 => wkt.Func5?.MakeGenericType(funcTypes),
            _ => null
        };
    }

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
            if (functionType.Declaration == null
                && call.Arguments.Count == functionType.ParameterTypes.Count
                && TryBindSyntheticFunctionArguments(
                    functionType,
                    functionType.SyntheticName ?? GetCallTargetName(call) ?? "function",
                    call,
                    out var boundSyntheticArguments,
                    reportErrors: false))
            {
                syntheticParameterIndexByArgument = boundSyntheticArguments;
            }

            // An EXTENSION method's receiver is supplied by the member access, not the argument list,
            // so pairing arguments with declared parameters skips the `this` parameter (mirrors the
            // paramStartIndex shift in the argument validation below). Without the shift a lambda
            // argument pairs with the RECEIVER's type and loses its delegate-type inference source.
            var expectedParamOffset = functionType.Declaration is { } decl
                && IsReceiverStyleExtensionCall(decl, call) ? 1 : 0;
            var nsharpExpectedBindings = functionType.Declaration is { } nsharpDeclaration
                ? TryInferNSharpGenericBindings(nsharpDeclaration, call, new List<TypeInfo>())
                : null;
            for (int i = 0; i < call.Arguments.Count; i++)
            {
                var argument = call.Arguments[i];
                var argumentErrorsBefore = _errors.Count;
                Dictionary<Expression, TypeInfo>? refOutTargetExpressionTypes;
                TypeInfo? expectedType;
                if (functionType.Declaration is { } declaration)
                {
                    expectedType = GetExpectedNSharpCallArgumentType(
                        declaration,
                        call,
                        i,
                        expectedParamOffset,
                        nsharpExpectedBindings);
                }
                else
                {
                    var expectedIndex = syntheticParameterIndexByArgument != null
                        ? syntheticParameterIndexByArgument[i]
                        : i + expectedParamOffset;
                    expectedType = expectedIndex < functionType.ParameterTypes.Count
                        && expectedIndex >= 0
                        ? functionType.ParameterTypes[expectedIndex]
                        : null;
                }

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
            // If we have the function declaration, check parameter types
            if (funcType.Declaration != null)
            {
                var parameters = funcType.Declaration.Parameters;

                // Receiver-style extension calls (`value.Extension(...)`) bind the receiver to the
                // `this` parameter. Direct calls (`Extension(value, ...)`) pass it explicitly.
                var paramStartIndex = IsReceiverStyleExtensionCall(funcType.Declaration, call) ? 1 : 0;
                var effectiveParamCount = parameters.Count - paramStartIndex;

                // Check if last parameter is params
                var hasParamsParameter = parameters.Count > 0 &&
                                        parameters[^1].Modifier == Ast.ParameterModifier.Params;

                // Count required parameters (those without default values)
                // Skip 'this' parameter for extension methods and 'params' parameter
                int requiredParamCount = 0;
                for (int i = paramStartIndex; i < parameters.Count; i++)
                {
                    var param = parameters[i];
                    // Skip params parameter
                    if (param.Modifier == Ast.ParameterModifier.Params)
                        continue;
                    // Count if no default value
                    if (param.DefaultValue == null)
                        requiredParamCount++;
                }

                // Check argument count (excluding the "this" parameter for extension methods)
                int minArgs = requiredParamCount;
                if (argTypes.Count < minArgs)
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                        GetCallDiagnosticSpan(call, funcType.Declaration.Name);
                    // Use ErrorMessageBuilder for better error message
                    var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
                        ? _sourceLines[diagnosticLine - 1]
                        : null;

                    if (sourceSnippet != null && _currentFilePath != null)
                    {
                        var error = ErrorMessageBuilder.WrongArgumentCount(
                            _currentFilePath,
                            diagnosticLine,
                            diagnosticColumn,
                            sourceSnippet,
                            diagnosticLength,
                            funcType.Declaration.Name,
                            minArgs,
                            argTypes.Count
                        );
                        _errors.Add(error);
                    }
                    else
                    {
                        Error(ErrorCode.WrongArgumentCount,
                            $"'{funcType.Declaration.Name}' needs at least {minArgs} argument(s), but you passed {argTypes.Count}",
                            diagnosticLine, diagnosticColumn, length: diagnosticLength);
                    }
                }
                else if (!hasParamsParameter && argTypes.Count > effectiveParamCount)
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                        GetCallDiagnosticSpan(call, funcType.Declaration.Name);
                    // Use ErrorMessageBuilder for better error message
                    var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
                        ? _sourceLines[diagnosticLine - 1]
                        : null;

                    if (sourceSnippet != null && _currentFilePath != null)
                    {
                        var error = ErrorMessageBuilder.WrongArgumentCount(
                            _currentFilePath,
                            diagnosticLine,
                            diagnosticColumn,
                            sourceSnippet,
                            diagnosticLength,
                            funcType.Declaration.Name,
                            effectiveParamCount,
                            argTypes.Count
                        );
                        _errors.Add(error);
                    }
                    else
                    {
                        Error(ErrorCode.WrongArgumentCount,
                            $"'{funcType.Declaration.Name}' takes {effectiveParamCount} argument(s), but you passed {argTypes.Count}",
                            diagnosticLine, diagnosticColumn, length: diagnosticLength);
                    }
                }
                else
                {
                    // Infer generic bindings for single N#-declared function
                    var genericBindings = TryInferNSharpGenericBindings(funcType.Declaration, call, argTypes);
                    ValidateGenericConstraints(funcType.Declaration, call, genericBindings);

                    // Check each parameter type (non-params parameters)
                    int regularParamCount = hasParamsParameter ? effectiveParamCount - 1 : effectiveParamCount;
                    for (int i = 0; i < regularParamCount && i < argTypes.Count; i++)
                    {
                        // For extension methods, parameter index in declaration is i + paramStartIndex
                        int paramIndex = i + paramStartIndex;
                        var paramType = ResolveType(parameters[paramIndex].Type);
                        paramType = ApplyNSharpGenericBindings(paramType, genericBindings);
                        var argType = argTypes[i];

                        if (!IsNSharpArgumentAssignable(parameters[paramIndex], paramType, call.Arguments[i], argType))
                        {
                            var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                                GetExpressionDiagnosticSpan(call.Arguments[i].Value);
                            var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
                                ? _sourceLines[diagnosticLine - 1]
                                : null;

                            if (sourceSnippet != null && _currentFilePath != null)
                            {
                                var error = ErrorMessageBuilder.WrongArgumentType(
                                    _currentFilePath,
                                    diagnosticLine,
                                    diagnosticColumn,
                                    sourceSnippet,
                                    diagnosticLength,
                                    funcType.Declaration.Name,
                                    i + 1,
                                    parameters[paramIndex].Name,
                                    argType.ToString(),
                                    paramType.ToString()
                                );
                                _errors.Add(error);
                            }
                            else
                            {
                                Error(ErrorCode.TypeMismatch, $"Argument {i + 1} is '{argType}', but parameter '{parameters[paramIndex].Name}' expects '{paramType}'",
                                    diagnosticLine, diagnosticColumn, length: diagnosticLength);
                            }
                        }
                    }

                    // Check params arguments (if any)
                    if (hasParamsParameter && argTypes.Count >= effectiveParamCount)
                    {
                        var paramsParam = parameters[^1];
                        var paramsArrayType = ResolveType(paramsParam.Type);
                        paramsArrayType = ApplyNSharpGenericBindings(paramsArrayType, genericBindings);

                        // Get element type from array type
                        if (paramsArrayType is ArrayTypeInfo arrayType)
                        {
                            var isDirectParamsArrayArgument = IsSingleDirectNSharpParamsArrayArgument(
                                regularParamCount,
                                call.Arguments,
                                argTypes,
                                arrayType);

                            for (int i = regularParamCount; !isDirectParamsArrayArgument && i < argTypes.Count; i++)
                            {
                                var argType = argTypes[i];
                                var arg = call.Arguments[i];

                                // Special handling for spread expressions in params
                                // If argument is a spread expression, the argType is the collection type
                                // We need to verify it's compatible with the params array type
                                if (arg.Value is SpreadExpression)
                                {
                                    // For spread, check if the spread expression type is compatible with the params array
                                    // The spread type should be an array/collection of the same element type
                                    if (argType is ArrayTypeInfo spreadArrayType)
                                    {
                                        if (!IsAssignable(arrayType.ElementType, spreadArrayType.ElementType))
                                        {
                                            Error($"Spread argument {i + 1} contains '{spreadArrayType.ElementType}' elements, but the params array expects '{arrayType.ElementType}'",
                                                call.Line, call.Column);
                                        }
                                    }
                                    // If it's not an array type, it's an error
                                    else if (!BuiltInTypes.IsUnknown(argType))
                                    {
                                        Error($"Spread argument {i + 1} must be an array or collection, but this is '{argType}'",
                                            call.Line, call.Column);
                                    }
                                }
                                else
                                {
                                    // Regular argument (not spread) - check element type directly
                                    if (!IsAssignable(arrayType.ElementType, argType))
                                    {
                                        Error($"Argument {i + 1} is '{argType}', but the params array expects '{arrayType.ElementType}' elements",
                                            call.Line, call.Column);
                                    }
                                }
                            }
                        }
                    }
                }

                return ResolveNSharpReturnType(funcType.Declaration, call, argTypes);
            }
            else if (funcType.ParameterTypes != null)
            {
                ValidateSyntheticFunctionCall(funcType, call, argTypes);
            }
            return funcType.ReturnType ?? BuiltInTypes.Void;
        }

        // Handle reflection method calls
        if (calleeType is ReflectionMethodInfo methodInfo)
        {
            var boundCall = BindSingleReflectionMethod(methodInfo.Method, call);
            if (boundCall?.ReturnType != null)
                return boundCall.ReturnType;

            return HandleUnboundReflectionCall(call, new[] { methodInfo.Method }, argTypes);
        }

        // Handle method group (overloaded methods)
        if (calleeType is ReflectionMethodGroupInfo methodGroup)
        {
            var boundCall = BindReflectionCall(methodGroup, call);
            if (boundCall?.ReturnType != null)
                return boundCall.ReturnType;

            return HandleUnboundReflectionCall(call, methodGroup.Methods, argTypes);
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
                var underlyingType = ResolveType(newtypeInfo.UnderlyingType);
                if (!IsAssignable(underlyingType, argTypes[0]))
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
            var boundDecl = BindNSharpCall(nsharpGroup, call, argTypes);
            if (boundDecl != null)
            {
                // Keep the semantic model pinned to the selected overload, not just the
                // pre-bind method group. Later checks such as [MustUse] enforcement need
                // the exact declaration that this call resolved to.
                _semanticModel.RecordExpressionType(call.Callee.Line, call.Callee.Column, CreateFunctionTypeInfo(boundDecl));

                // Validate arguments against the selected overload
                ValidateNSharpCallArguments(boundDecl, call, argTypes);
                return ResolveNSharpReturnType(boundDecl, call, argTypes);
            }

            ReportNoMatchingNSharpOverload(nsharpGroup, call, argTypes);
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

        var previousTargetTypes = _assignmentTargetExpressionTypes;
        expressionTypes = new Dictionary<Expression, TypeInfo>(ReferenceEqualityComparer.Instance);
        _assignmentTargetExpressionTypes = expressionTypes;
        try
        {
            return AnalyzeExpressionWithExpectedType(argument.Value, expectedType, allowUnboundCallableReference);
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

        var (line, column, length) = GetExpressionDiagnosticSpan(argument.Value);
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
            var resolvedReceiverType = ResolveTypeAlias(GetNonNullableType(receiverType));
            if (resolvedReceiverType is ByRefTypeInfo byRefReceiver)
                resolvedReceiverType = ResolveTypeAlias(GetNonNullableType(byRefReceiver.InnerType));

            if (resolvedReceiverType is SoaRowTypeInfo soaRowType
                && TryGetSoaColumn(soaRowType.Declaration, member.MemberName) != null)
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

        var resolvedReceiverType = ResolveTypeAlias(GetNonNullableType(receiverType));
        var isArrayReceiver = resolvedReceiverType is ArrayTypeInfo
            || resolvedReceiverType is ReflectionTypeInfo { Type.IsArray: true };
        if (!isArrayReceiver)
            return false;

        if (!expressionTypes.TryGetValue(index.Index, out var resolvedIndexType))
            return true;

        resolvedIndexType = ResolveTypeAlias(resolvedIndexType);
        return BuiltInTypes.IsUnknown(resolvedIndexType)
            || resolvedIndexType == BuiltInTypes.Int
            || IsIndexLikeType(resolvedIndexType);
    }

    private bool? ClassifyStaticFieldMember(
        MemberAccessExpression member,
        Dictionary<Expression, TypeInfo> expressionTypes)
    {
        if (!expressionTypes.TryGetValue(member.Object, out var ownerType))
            return null;

        var owner = NormalizeMemberOwnerType(ownerType);
        return ClassifyStaticFieldMember(owner, member.MemberName);
    }

    private bool? ClassifyStaticFieldMember(TypeInfo owner, string memberName)
    {
        List<Declaration>? members = owner switch
        {
            ClassTypeInfo classType => classType.Declaration.Members,
            StructTypeInfo structType => structType.Declaration.Members,
            RecordTypeInfo recordType => recordType.Declaration.Members,
            _ => null,
        };

        if (members != null)
        {
            foreach (var declaredMember in members)
            {
                if (GetDeclarationName(declaredMember) != memberName)
                    continue;

                return declaredMember is FieldDeclaration field
                    && field.Modifiers.HasFlag(Modifiers.Static);
            }

            if (owner is ClassTypeInfo { Declaration.BaseClass: not null } classTypeWithBase)
            {
                var baseType = ResolveType(classTypeWithBase.Declaration.BaseClass);
                return BuiltInTypes.IsUnknown(baseType)
                    ? null
                    : ClassifyStaticFieldMember(baseType, memberName);
            }

            return false;
        }

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

        try
        {
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
        }
        catch (NotSupportedException)
        {
            return null;
        }

        return false;
    }

    private TypeInfo? GetExpectedNSharpCallArgumentType(
        FunctionDeclaration declaration,
        CallExpression call,
        int argumentIndex,
        int paramStartIndex,
        Dictionary<string, TypeInfo>? genericBindings)
    {
        var hasParams = declaration.Parameters.Count > 0 &&
                        declaration.Parameters[^1].Modifier == Ast.ParameterModifier.Params;
        var effectiveParamCount = declaration.Parameters.Count - paramStartIndex;
        var regularParamCount = hasParams ? effectiveParamCount - 1 : effectiveParamCount;

        if (hasParams && argumentIndex >= regularParamCount)
        {
            var paramsType = ResolveType(declaration.Parameters[^1].Type);
            paramsType = ApplyNSharpGenericBindings(paramsType, genericBindings);
            var paramsElementType = GetNSharpParamsElementType(paramsType);

            // A single array literal can be either the direct params array or one expanded
            // params element. Leave it untyped here so validation can choose by assignability.
            if (call.Arguments.Count == regularParamCount + 1
                && call.Arguments[argumentIndex].Value is ArrayLiteralExpression)
            {
                return null;
            }

            return paramsElementType ?? paramsType;
        }

        var paramIndex = argumentIndex + paramStartIndex;
        if (paramIndex < 0 || paramIndex >= declaration.Parameters.Count)
            return null;

        var expectedType = ResolveType(declaration.Parameters[paramIndex].Type);
        return ApplyNSharpGenericBindings(expectedType, genericBindings);
    }

    private TypeInfo? GetNSharpParamsElementType(TypeInfo paramsType)
    {
        return ResolveTypeAlias(paramsType) switch
        {
            ArrayTypeInfo array => array.ElementType,
            GenericTypeInfo { TypeArguments.Count: 1 } generic => generic.TypeArguments[0],
            _ => null
        };
    }

    private bool IsSingleDirectNSharpParamsArrayArgument(
        int regularParamCount,
        IReadOnlyList<Argument> arguments,
        IReadOnlyList<TypeInfo> argTypes,
        TypeInfo paramsArrayType)
    {
        return argTypes.Count == regularParamCount + 1
            && arguments[regularParamCount].Value is not SpreadExpression
            && IsAssignable(paramsArrayType, argTypes[regularParamCount]);
    }

    private void ValidateSyntheticFunctionCall(FunctionTypeInfo functionType, CallExpression call, IReadOnlyList<TypeInfo> argTypes)
    {
        if (functionType.ParameterTypes == null)
            return;

        var functionName = functionType.SyntheticName ?? GetCallTargetName(call) ?? "function";
        var expectedCount = functionType.ParameterTypes.Count;
        if (argTypes.Count != expectedCount)
        {
            var (line, column, length) = GetCallDiagnosticSpan(call, functionName);
            Error(
                ErrorCode.WrongArgumentCount,
                $"'{functionName}' takes {expectedCount} argument(s), but you passed {argTypes.Count}",
                line,
                column,
                "Check the argument count against the function signature.",
                length);
            return;
        }

        if (!TryBindSyntheticFunctionArguments(functionType, functionName, call, out var parameterIndexByArgument))
            return;

        for (var argumentIndex = 0; argumentIndex < call.Arguments.Count; argumentIndex++)
        {
            var parameterIndex = parameterIndexByArgument[argumentIndex];
            if (parameterIndex < 0 || parameterIndex >= expectedCount)
                continue;

            var expectedType = ResolveTypeAlias(functionType.ParameterTypes[parameterIndex]);
            var argType = ResolveTypeAlias(argTypes[argumentIndex]);
            if (BuiltInTypes.IsUnknown(expectedType)
                || BuiltInTypes.IsUnknown(argType)
                || argType is SoaRowTypeInfo
                || IsAssignable(expectedType, argType))
            {
                continue;
            }

            var (line, column, length) = GetExpressionDiagnosticSpan(call.Arguments[argumentIndex].Value);
            var argumentName = call.Arguments[argumentIndex].Name;
            var argumentDescription = argumentName != null
                ? $"Argument '{argumentName}'"
                : $"Argument {argumentIndex + 1}";
            Error(
                ErrorCode.TypeMismatch,
                $"{argumentDescription} to '{functionName}' is '{argType}', but this parameter expects '{expectedType}'",
                line,
                column,
                "Pass a value with the expected type, or update the function signature.",
                length);
        }

        ValidateSoaSyntheticFunctionCall(functionType, functionName, call, argTypes, parameterIndexByArgument);
    }

    private bool TryBindSyntheticFunctionArguments(
        FunctionTypeInfo functionType,
        string functionName,
        CallExpression call,
        out int[] parameterIndexByArgument,
        bool reportErrors = true)
    {
        var expectedCount = functionType.ParameterTypes?.Count ?? 0;
        parameterIndexByArgument = Enumerable.Repeat(-1, call.Arguments.Count).ToArray();

        var parameterNames = functionType.ParameterNames;
        var boundArgumentIndexByParameter = Enumerable.Repeat(-1, expectedCount).ToArray();
        var nextPositionalParameter = 0;
        var success = true;

        for (var argumentIndex = 0; argumentIndex < call.Arguments.Count; argumentIndex++)
        {
            var argument = call.Arguments[argumentIndex];
            if (argument.Name is { } argumentName)
            {
                var parameterIndex = parameterNames != null
                    ? parameterNames.FindIndex(parameterName => parameterName == argumentName)
                    : -1;
                if (parameterIndex < 0 || parameterIndex >= expectedCount)
                {
                    if (reportErrors)
                    {
                        ReportSyntheticArgumentBindingError(
                            functionType,
                            functionName,
                            argument,
                            $"'{functionName}' has no parameter named '{argumentName}'");
                    }
                    success = false;
                    continue;
                }

                if (boundArgumentIndexByParameter[parameterIndex] >= 0)
                {
                    if (reportErrors)
                    {
                        ReportSyntheticArgumentBindingError(
                            functionType,
                            functionName,
                            argument,
                            $"'{functionName}' got multiple values for parameter '{argumentName}'");
                    }
                    success = false;
                    continue;
                }

                boundArgumentIndexByParameter[parameterIndex] = argumentIndex;
                parameterIndexByArgument[argumentIndex] = parameterIndex;
                continue;
            }

            while (nextPositionalParameter < expectedCount
                   && boundArgumentIndexByParameter[nextPositionalParameter] >= 0)
            {
                nextPositionalParameter++;
            }

            if (nextPositionalParameter >= expectedCount)
            {
                if (reportErrors)
                {
                    ReportSyntheticArgumentBindingError(
                        functionType,
                        functionName,
                        argument,
                        $"'{functionName}' got more positional arguments than its signature accepts");
                }
                success = false;
                continue;
            }

            boundArgumentIndexByParameter[nextPositionalParameter] = argumentIndex;
            parameterIndexByArgument[argumentIndex] = nextPositionalParameter;
            nextPositionalParameter++;
        }

        return success;
    }

    private void ReportSyntheticArgumentBindingError(
        FunctionTypeInfo functionType,
        string functionName,
        Argument argument,
        string message)
    {
        var (line, column, length) = GetExpressionDiagnosticSpan(argument.Value);
        Error(
            ErrorCode.NoMatchingOverload,
            message,
            line,
            column,
            $"Use {FormatSyntheticFunctionSignature(functionType, functionName)}, or remove the argument name.",
            length);
    }

    private static string FormatSyntheticFunctionSignature(FunctionTypeInfo functionType, string functionName)
    {
        var parameterCount = functionType.ParameterTypes?.Count ?? 0;
        if (parameterCount == 0)
            return $"{functionName}()";

        var names = functionType.ParameterNames;
        var parameters = Enumerable.Range(0, parameterCount)
            .Select(index => names != null && index < names.Count && names[index] is { } name
                ? name
                : $"arg{index + 1}");
        return $"{functionName}({string.Join(", ", parameters)})";
    }

    private void ValidateSoaSyntheticFunctionCall(
        FunctionTypeInfo functionType,
        string functionName,
        CallExpression call,
        IReadOnlyList<TypeInfo> argTypes,
        IReadOnlyList<int> parameterIndexByArgument)
    {
        switch (functionType.SyntheticName)
        {
            case "wrap":
            {
                ValidateSoaWrapColumnArguments(functionType, functionName, call, argTypes, parameterIndexByArgument);

                var lengthParameterIndex = functionType.ParameterNames?.FindIndex(parameterName => parameterName == "length") ?? -1;
                if (lengthParameterIndex >= 0)
                {
                    ValidateSyntheticNonNegativeIntArgument(
                        functionName,
                        call,
                        argTypes,
                        parameterIndexByArgument,
                        lengthParameterIndex,
                        "SoA table wrap length must not be negative",
                        "Use zero or a valid row count no greater than the column lengths.");
                }
                break;
            }

            case "ensureCapacity":
                ValidateSyntheticNonNegativeIntArgument(
                    functionName,
                    call,
                    argTypes,
                    parameterIndexByArgument,
                    parameterIndex: 0,
                    "SoA table capacity must not be negative",
                    "Use zero or a positive capacity; the table can grow later with add or ensureCapacity.");
                break;

            case "copyRow":
                ValidateSyntheticNonNegativeIntArgument(
                    functionName,
                    call,
                    argTypes,
                    parameterIndexByArgument,
                    parameterIndex: 0,
                    "SoA table source row id must not be negative",
                    "Use zero or a valid non-negative source row id.");
                ValidateSyntheticNonNegativeIntArgument(
                    functionName,
                    call,
                    argTypes,
                    parameterIndexByArgument,
                    parameterIndex: 1,
                    "SoA table target row id must not be negative",
                    "Use zero or a valid non-negative target row id.");
                break;
        }
    }

    private void ValidateSoaWrapColumnArguments(
        FunctionTypeInfo functionType,
        string functionName,
        CallExpression call,
        IReadOnlyList<TypeInfo> argTypes,
        IReadOnlyList<int> parameterIndexByArgument)
    {
        if (functionType.ParameterTypes == null)
            return;

        for (var argumentIndex = 0; argumentIndex < call.Arguments.Count; argumentIndex++)
        {
            var parameterIndex = parameterIndexByArgument[argumentIndex];
            if (parameterIndex < 0 || parameterIndex >= functionType.ParameterTypes.Count)
            {
                continue;
            }

            var expectedType = functionType.ParameterTypes[parameterIndex];
            if (ResolveTypeAlias(expectedType) is not ArrayTypeInfo)
            {
                continue;
            }

            if (argumentIndex < argTypes.Count
                && !BuiltInTypes.IsUnknown(argTypes[argumentIndex])
                && !IsAssignable(expectedType, argTypes[argumentIndex]))
            {
                continue;
            }

            var argument = call.Arguments[argumentIndex];
            if (!IsNullOrDefaultLiteral(argument.Value))
                continue;

            var columnName = functionType.ParameterNames != null && parameterIndex < functionType.ParameterNames.Count
                ? functionType.ParameterNames[parameterIndex]
                : $"column {parameterIndex + 1}";
            var (line, column, length) = GetExpressionDiagnosticSpan(argument.Value);
            Error(
                ErrorCode.TypeMismatch,
                $"SoA table wrap column '{columnName}' cannot be null",
                line,
                column,
                $"Pass the backing '{columnName}' column array, or allocate one before calling {functionName}.",
                length);
        }
    }

    private static bool IsNullOrDefaultLiteral(Expression expression)
    {
        while (true)
        {
            expression = UnwrapTransparentExpressionWrappers(expression);
            if (expression is CastExpression cast)
            {
                expression = cast.Expression;
                continue;
            }

            return expression is NullLiteralExpression or DefaultExpression;
        }
    }

    private static Expression UnwrapTransparentExpressionWrappers(Expression expression)
    {
        while (true)
        {
            if (expression is ParenthesizedExpression parenthesized)
            {
                expression = parenthesized.Inner;
                continue;
            }

            if (expression is CheckedExpression checkedExpression)
            {
                expression = checkedExpression.Expression;
                continue;
            }

            if (expression is UncheckedExpression uncheckedExpression)
            {
                expression = uncheckedExpression.Expression;
                continue;
            }

            break;
        }

        return expression;
    }

    private void ValidateSyntheticNonNegativeIntArgument(
        string functionName,
        CallExpression call,
        IReadOnlyList<TypeInfo> argTypes,
        IReadOnlyList<int> parameterIndexByArgument,
        int parameterIndex,
        string message,
        string suggestion)
    {
        var argumentIndex = -1;
        for (var i = 0; i < parameterIndexByArgument.Count; i++)
        {
            if (parameterIndexByArgument[i] == parameterIndex)
            {
                argumentIndex = i;
                break;
            }
        }

        if (argumentIndex < 0)
            return;

        if (argumentIndex >= call.Arguments.Count || argumentIndex >= argTypes.Count)
            return;

        var argType = ResolveTypeAlias(argTypes[argumentIndex]);
        if (BuiltInTypes.IsUnknown(argType)
            || argType is SoaRowTypeInfo
            || !IsAssignable(BuiltInTypes.Int, argType))
            return;

        if (!IsConstantNegative(call.Arguments[argumentIndex].Value))
            return;

        var (line, column, length) = GetExpressionDiagnosticSpan(call.Arguments[argumentIndex].Value);
        Error(
            ErrorCode.TypeMismatch,
            message,
            line,
            column,
            $"{functionName} expects a non-negative int argument here. {suggestion}",
            length);
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

    private void ReportNoMatchingNSharpOverload(NSharpMethodGroupInfo methodGroup, CallExpression call, List<TypeInfo> argTypes)
    {
        if (methodGroup.Declarations.Count == 0)
            return;

        var functionName = GetCallTargetName(call) ?? methodGroup.Declarations[0].Name;
        var (line, column, length) = GetCallDiagnosticSpan(call, functionName);
        var argumentTypes = argTypes.Select(type => type.ToString()).ToList();
        var candidateSignatures = methodGroup.Declarations
            .Select(declaration => FormatNSharpMethodSignature(declaration, call))
            .Distinct(StringComparer.Ordinal)
            .Take(8)
            .ToList();

        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.NoMatchingOverload(
                _currentFilePath,
                line,
                column,
                _sourceLines[line - 1],
                length,
                functionName,
                call.Arguments.Count,
                argumentTypes,
                candidateSignatures));
            return;
        }

        Error(
            ErrorCode.NoMatchingOverload,
            $"No overload of '{functionName}' accepts {call.Arguments.Count} argument(s) with these types",
            line,
            column,
            "Check the argument count and types against the available overloads.",
            length);
    }

    private TypeInfo HandleUnboundReflectionCall(CallExpression call, IReadOnlyList<MethodInfo> candidateMethods, List<TypeInfo> argTypes)
    {
        if (TryGetNSharpMethodGroupArgumentName(call, out var methodGroupArgumentName))
        {
            ReportNoMatchingReflectionMethodGroupOverload(call, candidateMethods, methodGroupArgumentName);
            return BuiltInTypes.Unknown;
        }

        ReportNoMatchingReflectionOverload(call, candidateMethods, argTypes);
        return BuiltInTypes.Unknown;
    }

    private void ReportNoMatchingReflectionOverload(CallExpression call, IReadOnlyList<MethodInfo> candidateMethods, List<TypeInfo> argTypes)
    {
        if (candidateMethods.Count == 0)
            return;

        var functionName = GetCallTargetName(call) ?? candidateMethods[0].Name;
        var (line, column, length) = GetCallDiagnosticSpan(call, functionName);
        var argumentTypes = argTypes.Select(type => type.ToString()).ToList();
        var candidateSignatures = candidateMethods
            .Select(method => FormatReflectionMethodSignature(method, call))
            .Distinct(StringComparer.Ordinal)
            .Take(8)
            .ToList();

        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.NoMatchingOverload(
                _currentFilePath,
                line,
                column,
                _sourceLines[line - 1],
                length,
                functionName,
                call.Arguments.Count,
                argumentTypes,
                candidateSignatures));
            return;
        }

        Error(
            ErrorCode.NoMatchingOverload,
            $"No overload of '{functionName}' accepts {call.Arguments.Count} argument(s) with these types",
            line,
            column,
            "Check the argument count and types against the available overloads.",
            length);
    }

    private void ReportNoMatchingReflectionMethodGroupOverload(CallExpression call, IReadOnlyList<MethodInfo> candidateMethods, string methodGroupArgumentName)
    {
        if (candidateMethods.Count == 0)
            return;

        var functionName = GetCallTargetName(call) ?? candidateMethods[0].Name;
        var (line, column, length) = GetCallDiagnosticSpan(call, functionName);
        Error(
            ErrorCode.NoMatchingOverload,
            $"No overload of '{functionName}' matches method group '{methodGroupArgumentName}'",
            line,
            column,
            "Check that the method group's parameters and return type match one of the delegate parameter types.",
            length);
    }

    private static string? GetCallTargetName(CallExpression call)
    {
        return call.Callee switch
        {
            IdentifierExpression identifier => identifier.Name,
            MemberAccessExpression memberAccess => memberAccess.MemberName,
            _ => null
        };
    }

    private (int Line, int Column, int Length) GetCallDiagnosticSpan(CallExpression call, string functionName)
    {
        return call.Callee switch
        {
            IdentifierExpression identifier => (identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length)),
            MemberAccessExpression memberAccess => (memberAccess.Line, GetMemberNameColumn(memberAccess), Math.Max(1, memberAccess.MemberName.Length)),
            _ => (call.Line, call.Column, Math.Max(1, functionName.Length))
        };
    }

    private static bool IsReceiverStyleExtensionCall(FunctionDeclaration declaration, CallExpression call)
        => declaration.Parameters.Count > 0
            && declaration.Parameters[0].IsThis
            && call.Callee is MemberAccessExpression;

    private string FormatNSharpMethodSignature(FunctionDeclaration declaration, CallExpression call)
    {
        var parameterStart = call.Callee is MemberAccessExpression &&
                             declaration.Parameters.Count > 0 &&
                             declaration.Parameters[0].IsThis
            ? 1
            : 0;
        var name = declaration.IsOperatorOverload
            ? $"operator {declaration.OperatorSymbol}"
            : declaration.Name;
        var typeParameters = declaration.TypeParameters is { Count: > 0 }
            ? $"<{string.Join(", ", declaration.TypeParameters.Select(parameter => parameter.Name))}>"
            : string.Empty;
        var parameters = declaration.Parameters
            .Skip(parameterStart)
            .Select(FormatNSharpParameterSignature);
        var returnType = declaration.ReturnType != null
            ? $": {TranspileTypeReference(declaration.ReturnType)}"
            : string.Empty;

        return $"{name}{typeParameters}({string.Join(", ", parameters)}){returnType}";
    }

    private string FormatNSharpParameterSignature(Parameter parameter)
    {
        var modifier = parameter.Modifier switch
        {
            Ast.ParameterModifier.Ref => "ref ",
            Ast.ParameterModifier.Out => "out ",
            Ast.ParameterModifier.Params => "params ",
            _ => parameter.IsThis ? "this " : string.Empty
        };
        var defaultValue = parameter.DefaultValue != null ? " = ..." : string.Empty;
        return $"{modifier}{parameter.Name}: {TranspileTypeReference(parameter.Type)}{defaultValue}";
    }

    private static string FormatReflectionMethodSignature(MethodInfo method, CallExpression call)
    {
        var parameters = method.GetParameters().AsEnumerable();
        if (call.Callee is MemberAccessExpression && HasExtensionAttribute(method))
            parameters = parameters.Skip(1);

        var formattedParameters = parameters.Select(FormatReflectionParameter);
        return $"{method.Name}({string.Join(", ", formattedParameters)}): {NullabilityMetadata.FormatReturnType(method)}";
    }

    private static string FormatReflectionParameter(ParameterInfo parameter)
        => NullabilityMetadata.FormatParameter(parameter);

    private static string FormatReflectionTypeName(Type type)
        => NullabilityMetadata.FormatType(type);

    private bool TryGetNSharpMethodGroupArgumentName(CallExpression call, out string name)
    {
        name = string.Empty;

        foreach (var argument in call.Arguments)
        {
            if (argument.Value is not IdentifierExpression identifier)
                continue;

            var symbol = LookupSymbol(identifier.Name);
            if (symbol is NSharpMethodGroupInfo
                || symbol is FunctionTypeInfo { Declaration: not null })
            {
                name = identifier.Name;
                return true;
            }
        }

        return false;
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
        // matching). Record the decision on the node so the transpiler/IL backends honor this
        // scope-aware resolution instead of re-deriving it from name + expected type alone.
        if (LookupSymbol(identifier.Name) != null)
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
        if (!IsAssignable(expectedArm, actualArm))
        {
            Error(
                ErrorCode.TypeMismatch,
                $"{identifier.Name} expects '{expectedArm}', but this argument has type '{actualArm}'",
                call.Arguments[0].Value.Line,
                call.Arguments[0].Value.Column);
        }

        resultType = _currentExpectedType ?? new GenericTypeInfo("Result", new List<TypeInfo> { okType, errType });
        return true;
    }

    private static bool TryGetResultArmTypes(TypeInfo? type, out TypeInfo okType, out TypeInfo errType)
    {
        okType = BuiltInTypes.Unknown;
        errType = BuiltInTypes.Unknown;

        if (type is not GenericTypeInfo { TypeArguments.Count: 2 } generic)
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
    /// Selects the best-matching overload from a group of N#-declared methods.
    /// Uses a scoring system analogous to BindReflectionCall.
    /// Reports an ambiguity error when two overloads score equally.
    /// </summary>
    private FunctionDeclaration? BindNSharpCall(NSharpMethodGroupInfo methodGroup, CallExpression call, List<TypeInfo> argTypes)
    {
        FunctionDeclaration? bestDecl = null;
        int bestScore = -1;
        bool ambiguous = false;

        foreach (var decl in methodGroup.Declarations)
        {
            var paramStart = IsReceiverStyleExtensionCall(decl, call) ? 1 : 0;
            var effectiveParamCount = decl.Parameters.Count - paramStart;
            var hasParams = decl.Parameters.Count > 0 &&
                            decl.Parameters[^1].Modifier == Ast.ParameterModifier.Params;

            // Count required parameters
            int requiredCount = 0;
            for (int i = paramStart; i < decl.Parameters.Count; i++)
            {
                if (decl.Parameters[i].Modifier == Ast.ParameterModifier.Params)
                    continue;
                if (decl.Parameters[i].DefaultValue == null)
                    requiredCount++;
            }

            // Check arity
            if (argTypes.Count < requiredCount)
                continue;
            if (!hasParams && argTypes.Count > effectiveParamCount)
                continue;

            // Try generic inference if needed
            var genericBindings = TryInferNSharpGenericBindings(decl, call, argTypes);

            // Score each argument
            int score = 0;
            bool allMatch = true;

            int regularParamCount = hasParams ? effectiveParamCount - 1 : effectiveParamCount;
            for (int i = 0; i < argTypes.Count && i < regularParamCount; i++)
            {
                var paramType = ResolveType(decl.Parameters[i + paramStart].Type);
                paramType = ApplyNSharpGenericBindings(paramType, genericBindings);
                var argType = argTypes[i];

                if (!IsNSharpArgumentAssignable(decl.Parameters[i + paramStart], paramType, call.Arguments[i], argType))
                {
                    allMatch = false;
                    break;
                }

                score += GetNSharpArgumentMatchScore(decl.Parameters[i + paramStart], paramType, call.Arguments[i], argType);
            }

            if (!allMatch)
                continue;

            // Validate params arguments if present
            if (hasParams && argTypes.Count > regularParamCount)
            {
                var paramsParamType = ResolveType(decl.Parameters[^1].Type);
                paramsParamType = ApplyNSharpGenericBindings(paramsParamType, genericBindings);

                if (paramsParamType is ArrayTypeInfo paramsArrayType)
                {
                    bool paramsMatch = true;
                    if (IsSingleDirectNSharpParamsArrayArgument(
                        regularParamCount,
                        call.Arguments,
                        argTypes,
                        paramsArrayType))
                    {
                        score += GetNSharpMatchScore(paramsArrayType, argTypes[regularParamCount]);
                    }
                    else
                    {
                        for (int i = regularParamCount; i < argTypes.Count; i++)
                        {
                            if (!IsAssignable(paramsArrayType.ElementType, argTypes[i]))
                            {
                                paramsMatch = false;
                                break;
                            }
                            score += GetNSharpMatchScore(paramsArrayType.ElementType, argTypes[i]);
                        }
                    }

                    if (!paramsMatch)
                        continue;
                }
            }

            if (score > bestScore)
            {
                bestScore = score;
                bestDecl = decl;
                ambiguous = false;
            }
            else if (score == bestScore && bestDecl != null)
            {
                // Tie-breaking rules (C# semantics):
                // 1. Non-generic preferred over generic
                // 2. Non-params preferred over params
                // 3. More parameters (fewer defaults used) preferred
                bool currentIsGeneric = decl.TypeParameters != null && decl.TypeParameters.Count > 0;
                bool bestIsGeneric = bestDecl.TypeParameters != null && bestDecl.TypeParameters.Count > 0;
                bool currentHasParams = decl.Parameters.Count > 0 &&
                                        decl.Parameters[^1].Modifier == Ast.ParameterModifier.Params;
                bool bestHasParams = bestDecl.Parameters.Count > 0 &&
                                     bestDecl.Parameters[^1].Modifier == Ast.ParameterModifier.Params;

                if (bestIsGeneric && !currentIsGeneric)
                {
                    bestDecl = decl;
                    ambiguous = false;
                }
                else if (!bestIsGeneric && currentIsGeneric)
                {
                    // Best (non-generic) already wins
                }
                else if (bestHasParams && !currentHasParams)
                {
                    bestDecl = decl;
                    ambiguous = false;
                }
                else if (!bestHasParams && currentHasParams)
                {
                    // Best (non-params) already wins
                }
                else
                {
                    ambiguous = true;
                }
            }
        }

        if (ambiguous && bestDecl != null)
        {
            Error($"Ambiguous call to '{bestDecl.Name}' — multiple overloads match with equal specificity",
                call.Line, call.Column);
        }

        return bestDecl;
    }

    /// <summary>
    /// Scores how well an argument type matches a parameter type for N#-declared methods.
    /// Exact match = 8, MLC-equivalent match = 8, implicit numeric = 6, assignable = 4, fallback = 2.
    /// </summary>
    private int GetNSharpMatchScore(TypeInfo parameterType, TypeInfo argumentType)
    {
        var resolvedParam = ResolveTypeAlias(parameterType);
        var resolvedArg = ResolveTypeAlias(argumentType);

        if (resolvedParam == resolvedArg)
            return 8;

        // Cross-representation exact match (SimpleTypeInfo vs ReflectionTypeInfo for the same CLR type)
        var paramClr = TryConvertTypeInfoToClrType(resolvedParam);
        var argClr = TryConvertTypeInfoToClrType(resolvedArg);
        if (paramClr != null && argClr != null && paramClr == argClr)
            return 8;

        // Implicit numeric conversion (better than generic assignable, worse than exact)
        if (IsImplicitNumericConversion(resolvedArg, resolvedParam))
            return 6;

        // Assignable but not exact
        if (IsAssignable(resolvedParam, resolvedArg))
            return 4;

        return 2;
    }

    private bool IsNSharpArgumentAssignable(Parameter parameter, TypeInfo parameterType, Argument argument, TypeInfo argumentType)
    {
        var resolvedParameter = ResolveTypeAlias(parameterType);
        var resolvedArgument = ResolveTypeAlias(argumentType);
        var expectsByRefType = resolvedParameter is ByRefTypeInfo;
        var expectsByRefModifier = parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out;
        var suppliedByRef = argument.Modifier is ArgumentModifier.Ref or ArgumentModifier.Out;

        if (expectsByRefType)
        {
            if (!suppliedByRef)
                return false;

            var elementType = ((ByRefTypeInfo)resolvedParameter).InnerType;
            var argumentElementType = resolvedArgument is ByRefTypeInfo byRefArgument
                ? byRefArgument.InnerType
                : resolvedArgument;
            return IsAssignable(elementType, argumentElementType);
        }

        if (expectsByRefModifier)
        {
            if (!suppliedByRef)
                return false;

            if (parameter.Modifier == Ast.ParameterModifier.Ref && argument.Modifier != ArgumentModifier.Ref)
                return false;

            if (parameter.Modifier == Ast.ParameterModifier.Out && argument.Modifier != ArgumentModifier.Out)
                return false;
        }
        else if (suppliedByRef)
        {
            return false;
        }

        return IsAssignable(resolvedParameter, resolvedArgument);
    }

    private int GetNSharpArgumentMatchScore(Parameter parameter, TypeInfo parameterType, Argument argument, TypeInfo argumentType)
    {
        var resolvedParameter = ResolveTypeAlias(parameterType);
        if (resolvedParameter is ByRefTypeInfo byRef)
        {
            var resolvedArgument = ResolveTypeAlias(argumentType);
            var argumentElementType = resolvedArgument is ByRefTypeInfo byRefArgument
                ? byRefArgument.InnerType
                : resolvedArgument;
            return GetNSharpMatchScore(byRef.InnerType, argumentElementType);
        }

        return GetNSharpMatchScore(parameterType, argumentType);
    }

    /// <summary>
    /// Validates arguments against a selected N#-declared overload and reports type errors.
    /// </summary>
    private void ValidateNSharpCallArguments(FunctionDeclaration decl, CallExpression call, List<TypeInfo> argTypes)
    {
        var paramStart = IsReceiverStyleExtensionCall(decl, call) ? 1 : 0;
        var effectiveParamCount = decl.Parameters.Count - paramStart;
        var hasParams = decl.Parameters.Count > 0 &&
                        decl.Parameters[^1].Modifier == Ast.ParameterModifier.Params;
        var genericBindings = TryInferNSharpGenericBindings(decl, call, argTypes);
        ValidateGenericConstraints(decl, call, genericBindings);

        int regularParamCount = hasParams ? effectiveParamCount - 1 : effectiveParamCount;
        for (int i = 0; i < regularParamCount && i < argTypes.Count; i++)
        {
            int paramIndex = i + paramStart;
            var paramType = ResolveType(decl.Parameters[paramIndex].Type);
            paramType = ApplyNSharpGenericBindings(paramType, genericBindings);
            var argType = argTypes[i];

            if (!IsNSharpArgumentAssignable(decl.Parameters[paramIndex], paramType, call.Arguments[i], argType))
            {
                Error($"Argument {i + 1} is '{argType}', but parameter '{decl.Parameters[paramIndex].Name}' expects '{paramType}'",
                    call.Line, call.Column);
            }
        }

        // Validate params arguments
        if (hasParams && argTypes.Count > regularParamCount)
        {
            var paramsParamType = ResolveType(decl.Parameters[^1].Type);
            paramsParamType = ApplyNSharpGenericBindings(paramsParamType, genericBindings);

            if (paramsParamType is ArrayTypeInfo paramsArrayType)
            {
                var isDirectParamsArrayArgument = IsSingleDirectNSharpParamsArrayArgument(
                    regularParamCount,
                    call.Arguments,
                    argTypes,
                    paramsArrayType);

                for (int i = regularParamCount; !isDirectParamsArrayArgument && i < argTypes.Count; i++)
                {
                    var argType = argTypes[i];
                    if (!IsAssignable(paramsArrayType.ElementType, argType))
                    {
                        Error($"Argument {i + 1} is '{argType}', but the params array expects '{paramsArrayType.ElementType}' elements",
                            call.Line, call.Column);
                    }
                }
            }
        }
    }

    /// <summary>
    /// Validates that inferred or explicit generic bindings satisfy declared constraints.
    /// Call this from argument validation sites only (not from overload scoring or return-type resolution).
    /// </summary>
    /// <summary>
    /// Rejects DIRECT circular constraint dependencies between type parameters (`where T: T`,
    /// `where T: U where U: T`) — the CLR refuses such metadata at load, and the emitter's base-chain
    /// walks (a constrained parameter's BaseType is its constraint) would otherwise spin forever.
    /// Only BARE type-parameter constraints form edges: F-bounded shapes (`where T: IComparable&lt;T&gt;`)
    /// are legal and untouched. Mirrors C#'s CS0454.
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

    private void ValidateGenericConstraints(FunctionDeclaration decl, CallExpression call, Dictionary<string, TypeInfo>? bindings)
    {
        if (decl.Constraints == null || bindings == null || bindings.Count == 0)
            return;

        foreach (var constraint in decl.Constraints)
        {
            if (bindings.TryGetValue(constraint.TypeParameter, out var boundType))
            {
                // Underline the argument that forced this binding (e.g. the literal `42`),
                // falling back to the callee name when no single argument can be identified.
                var (line, column, length) = GetGenericConstraintDiagnosticSpan(decl, call, constraint.TypeParameter);

                // Validate special constraints
                if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.Class))
                {
                    if (!IsReferenceType(boundType))
                    {
                        Error(ErrorCode.GenericConstraintViolation,
                            $"`{boundType}` is a value type, but type parameter `{constraint.TypeParameter}` of `{decl.Name}` requires a reference type (the `class` constraint)",
                            line, column,
                            $"Pass a class instance for `{constraint.TypeParameter}`, or relax the `class` constraint on `{decl.Name}`.",
                            length);
                    }
                }

                if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.Struct))
                {
                    // CLR 'struct' constraint means non-nullable value type.
                    // Nullable<T> (NullableTypeInfo) is NOT a valid struct-constrained type.
                    if (IsReferenceType(boundType) || boundType is NullableTypeInfo)
                    {
                        Error(ErrorCode.GenericConstraintViolation,
                            $"`{boundType}` is not a non-nullable value type, but type parameter `{constraint.TypeParameter}` of `{decl.Name}` requires one (the `struct` constraint)",
                            line, column,
                            $"Pass a non-nullable value type for `{constraint.TypeParameter}`, or relax the `struct` constraint on `{decl.Name}`.",
                            length);
                    }
                }

                if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.New))
                {
                    if (!HasParameterlessConstructor(boundType))
                    {
                        Error(ErrorCode.GenericConstraintViolation,
                            $"`{boundType}` has no parameterless constructor, but type parameter `{constraint.TypeParameter}` of `{decl.Name}` requires one (the `new()` constraint)",
                            line, column,
                            $"Give `{boundType}` a parameterless constructor, or relax the `new()` constraint on `{decl.Name}`.",
                            length);
                    }
                }

                // Validate interface/type constraints
                foreach (var constraintTypeRef in constraint.Constraints)
                {
                    var constraintType = ApplyNSharpGenericBindings(ResolveType(constraintTypeRef), bindings);
                    if (!IsSubtypeOf(boundType, constraintType) && !IsAssignable(constraintType, boundType))
                    {
                        Error(ErrorCode.GenericConstraintViolation,
                            $"`{boundType}` does not implement `{constraintType}`, which type parameter `{constraint.TypeParameter}` of `{decl.Name}` requires",
                            line, column,
                            $"Implement `{constraintType}` on `{boundType}`, or relax the constraint on `{decl.Name}`.",
                            length);
                    }
                }
            }
        }
    }

    /// <summary>
    /// Locates the source span to underline for a generic-constraint violation.
    /// Prefers the single argument whose declared parameter type is exactly the offending
    /// type parameter (e.g. the literal `42` for `Identity&lt;T&gt;(value: T)`); otherwise
    /// falls back to the callee name span.
    /// </summary>
    private (int Line, int Column, int Length) GetGenericConstraintDiagnosticSpan(
        FunctionDeclaration decl,
        CallExpression call,
        string typeParameter)
    {
        var paramStart = IsReceiverStyleExtensionCall(decl, call) ? 1 : 0;

        Expression? offendingArgument = null;
        for (var i = 0; i + paramStart < decl.Parameters.Count && i < call.Arguments.Count; i++)
        {
            if (decl.Parameters[i + paramStart].Type is SimpleTypeReference simple &&
                simple.Name == typeParameter)
            {
                if (offendingArgument != null)
                {
                    // More than one argument binds this type parameter — no single token to blame.
                    offendingArgument = null;
                    break;
                }

                offendingArgument = call.Arguments[i].Value;
            }
        }

        return offendingArgument != null
            ? GetExpressionDiagnosticSpan(offendingArgument)
            : GetCallDiagnosticSpan(call, GetCallTargetName(call) ?? decl.Name);
    }

    /// <summary>
    /// Returns true if the type has an accessible parameterless constructor,
    /// which is required to satisfy a 'new()' generic constraint.
    /// </summary>
    private bool HasParameterlessConstructor(TypeInfo type)
    {
        // Structs (and record structs) always have an implicit parameterless constructor in C#
        if (type is StructTypeInfo)
            return true;

        if (type is ClassTypeInfo classType)
        {
            // A class with a primary constructor (C# 12-style `class Foo(int x)`) suppresses
            // the implicit default constructor, so it does NOT satisfy new().
            if (classType.Declaration.PrimaryConstructorParameters != null
                && classType.Declaration.PrimaryConstructorParameters.Count > 0)
                return false;

            var constructors = classType.Declaration.Members
                .OfType<ConstructorDeclaration>();
            // If no explicit constructors, the implicit default constructor is available
            return !constructors.Any() || constructors.Any(c => c.Parameters.Count == 0);
        }

        if (type is RecordTypeInfo recordType)
        {
            // Record structs always have an implicit parameterless constructor regardless of
            // whether they declare primary constructor parameters.
            if (recordType.Declaration.IsStruct)
                return true;

            // Record classes: a primary constructor with params suppresses the default ctor
            return recordType.Declaration.PrimaryConstructorParameters == null
                || recordType.Declaration.PrimaryConstructorParameters.Count == 0;
        }

        if (type is ReflectionTypeInfo refl)
        {
            // CLR value types always have a parameterless constructor even if no explicit
            // constructor is declared (they are zero-initialized), so check IsValueType first.
            return refl.Type.IsValueType || refl.Type.GetConstructor(Type.EmptyTypes) != null;
        }

        // Conservative: unknown types are assumed to satisfy the constraint
        return true;
    }

    /// <summary>
    /// Resolves the return type of an N#-declared function, applying generic bindings if needed.
    /// </summary>
    private TypeInfo ResolveNSharpReturnType(FunctionDeclaration decl, CallExpression call, List<TypeInfo> argTypes)
    {
        var returnType = decl.ReturnType != null
            ? ResolveType(decl.ReturnType)
            : BuiltInTypes.Void;
        var genericBindings = TryInferNSharpGenericBindings(decl, call, argTypes);
        returnType = ApplyNSharpGenericBindings(returnType, genericBindings);
        return ResolveFunctionCallReturnType(decl, returnType);
    }

    private TypeInfo ResolveDeclaredFunctionCallReturnType(FunctionDeclaration decl)
    {
        var sourceReturnType = decl.ReturnType != null
            ? ResolveType(decl.ReturnType)
            : BuiltInTypes.Void;

        return ResolveFunctionCallReturnType(decl, sourceReturnType);
    }

    private TypeInfo ResolveFunctionCallReturnType(FunctionDeclaration decl, TypeInfo sourceReturnType)
    {
        if (!decl.Modifiers.HasFlag(Modifiers.Async)
            || decl.Modifiers.HasFlag(Modifiers.Generator))
        {
            return sourceReturnType;
        }

        if (IsUnitTaskLikeType(sourceReturnType)
            || TryGetTaskLikeResultType(sourceReturnType, out _))
        {
            return sourceReturnType;
        }

        var usesTaskFamily = string.Equals(decl.Name, "main", StringComparison.OrdinalIgnoreCase);
        if (sourceReturnType == BuiltInTypes.Void)
        {
            return usesTaskFamily
                ? new ReflectionTypeInfo(typeof(System.Threading.Tasks.Task))
                : new ReflectionTypeInfo(typeof(System.Threading.Tasks.ValueTask));
        }

        return new GenericTypeInfo(
            usesTaskFamily ? "Task" : "ValueTask",
            new List<TypeInfo> { sourceReturnType });
    }

    /// <summary>
    /// Tries to infer generic type bindings for an N#-declared function call.
    /// Maps type parameter names to concrete TypeInfo values.
    /// </summary>
    private Dictionary<string, TypeInfo>? TryInferNSharpGenericBindings(
        FunctionDeclaration decl,
        CallExpression call,
        List<TypeInfo> argTypes)
    {
        if (decl.TypeParameters == null || decl.TypeParameters.Count == 0)
            return null;

        var bindings = new Dictionary<string, TypeInfo>();
        // Track all bounds per type parameter for LUB computation
        var allBounds = new Dictionary<string, List<TypeInfo>>();
        foreach (var tp in decl.TypeParameters)
            allBounds[tp.Name] = new List<TypeInfo>();

        // Phase 1: Use explicit type arguments if provided
        if (call.TypeArguments != null && call.TypeArguments.Count > 0)
        {
            if (call.TypeArguments.Count == decl.TypeParameters.Count)
            {
                // All type args are explicit
                for (int i = 0; i < decl.TypeParameters.Count; i++)
                {
                    bindings[decl.TypeParameters[i].Name] = ResolveType(call.TypeArguments[i]);
                }
                return bindings;
            }
            else if (call.TypeArguments.Count < decl.TypeParameters.Count)
            {
                // Partial inference: first N type args are explicit, rest are inferred
                for (int i = 0; i < call.TypeArguments.Count; i++)
                {
                    bindings[decl.TypeParameters[i].Name] = ResolveType(call.TypeArguments[i]);
                }
                // Fall through to infer the remaining type parameters from arguments
            }
            else
            {
                return null; // More type args than type params
            }
        }

        // Phase 2: Infer from argument types
        var isReceiverStyleExtension = IsReceiverStyleExtensionCall(decl, call);
        var paramStart = isReceiverStyleExtension ? 1 : 0;
        var hasParams = decl.Parameters.Count > 0 &&
                        decl.Parameters[^1].Modifier == Ast.ParameterModifier.Params;
        var effectiveParamCount = decl.Parameters.Count - paramStart;
        var regularParamCount = hasParams ? effectiveParamCount - 1 : effectiveParamCount;

        // For extension methods, infer from the receiver type (the `this` parameter)
        if (isReceiverStyleExtension && call.Callee is MemberAccessExpression memberAccess)
        {
            var receiverType = AnalyzeExpression(memberAccess.Object);
            CollectNSharpTypeParameterBounds(decl.Parameters[0].Type, receiverType, decl.TypeParameters, allBounds);
        }

        // Match regular (non-params) parameters
        for (int i = 0; i < argTypes.Count && i < regularParamCount; i++)
        {
            var paramTypeRef = decl.Parameters[i + paramStart].Type;
            CollectNSharpTypeParameterBounds(paramTypeRef, argTypes[i], decl.TypeParameters, allBounds);
        }

        // Match params arguments against the element type of the params array
        if (hasParams && argTypes.Count >= regularParamCount)
        {
            var paramsTypeRef = decl.Parameters[^1].Type;
            // Extract element type for inference:
            // - T[] → T (ArrayTypeReference)
            // - List<T>, IEnumerable<T>, etc. → T (GenericTypeReference with single type arg)
            TypeReference? paramsElementTypeRef = null;
            if (paramsTypeRef is ArrayTypeReference paramsArray)
            {
                paramsElementTypeRef = paramsArray.ElementType;
            }
            else if (paramsTypeRef is GenericTypeReference paramsGeneric && paramsGeneric.TypeArguments.Count == 1)
            {
                // Handles params List<T>, params IEnumerable<T>, params Span<T>, etc.
                paramsElementTypeRef = paramsGeneric.TypeArguments[0];
            }

            if (paramsElementTypeRef != null)
            {
                for (int i = regularParamCount; i < argTypes.Count; i++)
                {
                    CollectNSharpTypeParameterBounds(paramsElementTypeRef, argTypes[i], decl.TypeParameters, allBounds);
                }
            }
            else
            {
                // Fallback: match directly against the whole params type
                for (int i = regularParamCount; i < argTypes.Count; i++)
                {
                    CollectNSharpTypeParameterBounds(paramsTypeRef, argTypes[i], decl.TypeParameters, allBounds);
                }
            }
        }

        // Phase 3: Resolve bounds into bindings
        foreach (var tp in decl.TypeParameters)
        {
            if (bindings.ContainsKey(tp.Name))
                continue; // Already bound by explicit type arg

            var bounds = allBounds[tp.Name];
            if (bounds.Count == 0)
                continue;

            if (bounds.Count == 1)
            {
                bindings[tp.Name] = bounds[0];
            }
            else
            {
                // Compute LUB (least upper bound) of all bounds
                bindings[tp.Name] = ComputeLeastUpperBound(bounds);
            }
        }

        return bindings;
    }

    /// <summary>
    /// Computes the least upper bound (best common type) of a list of types.
    /// Used when multiple arguments constrain the same type parameter.
    /// </summary>
    private TypeInfo ComputeLeastUpperBound(List<TypeInfo> types)
    {
        if (types.Count == 0)
            return BuiltInTypes.Object;
        if (types.Count == 1)
            return types[0];

        // If all types are the same, return that type
        var first = types[0];
        if (types.All(t => TypesEqual(t, first)))
            return first;

        // Check if one type is assignable from all others (common supertype among the candidates)
        foreach (var candidate in types)
        {
            if (types.All(t => TypesEqual(t, candidate) || IsAssignable(candidate, t)))
                return candidate;
        }

        // For numeric types, find the widest numeric type
        var numericLub = TryComputeNumericLub(types);
        if (numericLub != null)
            return numericLub;

        // No common type found — use object as the safe fallback
        // (C# would fail best-common-type inference here; object is the conservative choice)
        return BuiltInTypes.Object;
    }

    /// <summary>
    /// Tries to compute the widest numeric type from a list of numeric types.
    /// </summary>
    private TypeInfo? TryComputeNumericLub(List<TypeInfo> types)
    {
        // Numeric widening order: byte < short < int < long < float < double < decimal
        var numericOrder = new[] { "byte", "short", "int", "long", "float", "double", "decimal" };

        int maxIndex = -1;
        foreach (var type in types)
        {
            var name = type.ToString().ToLowerInvariant();
            // Also handle System.* names
            name = name switch
            {
                "system.byte" => "byte",
                "system.int16" => "short",
                "system.int32" => "int",
                "system.int64" => "long",
                "system.single" => "float",
                "system.double" => "double",
                "system.decimal" => "decimal",
                _ => name
            };
            var index = Array.IndexOf(numericOrder, name);
            if (index < 0)
                return null; // Not all types are numeric
            maxIndex = Math.Max(maxIndex, index);
        }

        if (maxIndex >= 0)
        {
            return numericOrder[maxIndex] switch
            {
                "byte" => BuiltInTypes.Byte,
                "short" => BuiltInTypes.Short,
                "int" => BuiltInTypes.Int,
                "long" => BuiltInTypes.Long,
                "float" => BuiltInTypes.Float,
                "double" => BuiltInTypes.Double,
                "decimal" => BuiltInTypes.Decimal,
                _ => null
            };
        }

        return null;
    }

    /// <summary>
    /// Checks if two TypeInfo values represent the same type.
    /// </summary>
    private bool TypesEqual(TypeInfo a, TypeInfo b)
    {
        if (a == b) return true;
        if (a is ByRefTypeInfo aRef && b is ByRefTypeInfo bRef)
            return TypesEqual(aRef.InnerType, bRef.InnerType);
        if (a.ToString() == b.ToString()) return true;
        return false;
    }

    /// <summary>
    /// Collects type parameter bounds by recursively matching a parameter type reference against an argument type.
    /// Unlike direct binding, this collects ALL bounds so LUB can be computed when a type param appears multiple times.
    /// </summary>
    private void CollectNSharpTypeParameterBounds(
        TypeReference paramTypeRef,
        TypeInfo argType,
        List<TypeParameter> typeParameters,
        Dictionary<string, List<TypeInfo>> allBounds)
    {
        // Skip types that provide no inference information
        if (BuiltInTypes.IsUnknown(argType))
            return;
        if (argType == BuiltInTypes.Null)
            return; // null carries no type information for generic inference

        if (paramTypeRef is SimpleTypeReference simple)
        {
            foreach (var tp in typeParameters)
            {
                if (tp.Name == simple.Name)
                {
                    allBounds[tp.Name].Add(argType);
                    return;
                }
            }
        }
        else if (paramTypeRef is GenericTypeReference generic)
        {
            // e.g., List<T> matched against List<int> → T=int
            if (argType is GenericTypeInfo argGeneric && GenericNamesMatch(generic.Name, argGeneric.Name) &&
                generic.TypeArguments.Count == argGeneric.TypeArguments.Count)
            {
                for (int i = 0; i < generic.TypeArguments.Count; i++)
                {
                    CollectNSharpTypeParameterBounds(generic.TypeArguments[i], argGeneric.TypeArguments[i], typeParameters, allBounds);
                }
            }
            // Also match against ExternalTypeInfo that wraps a generic CLR type
            else if (argType is ExternalTypeInfo ext)
            {
                TryMatchGenericRefAgainstExternalType(generic, ext, typeParameters, allBounds);
            }
            // Match against ReflectionTypeInfo wrapping a generic CLR type
            else if (argType is ReflectionTypeInfo refl && refl.Type.IsGenericType)
            {
                var typeArgs = refl.Type.GetGenericArguments();
                if (generic.TypeArguments.Count == typeArgs.Length &&
                    GenericNamesMatch(generic.Name, refl.Type.Name.Split('`')[0]))
                {
                    for (int i = 0; i < generic.TypeArguments.Count; i++)
                    {
                        CollectNSharpTypeParameterBounds(generic.TypeArguments[i], ConvertReflectionType(typeArgs[i]), typeParameters, allBounds);
                    }
                }
            }
        }
        else if (paramTypeRef is ArrayTypeReference array)
        {
            if (argType is ArrayTypeInfo argArray)
            {
                CollectNSharpTypeParameterBounds(array.ElementType, argArray.ElementType, typeParameters, allBounds);
            }
        }
        else if (paramTypeRef is NullableTypeReference nullable)
        {
            if (argType is NullableTypeInfo argNullable)
            {
                CollectNSharpTypeParameterBounds(nullable.InnerType, argNullable.InnerType, typeParameters, allBounds);
            }
            // Also allow matching T? against a non-nullable T (infer the inner type)
            else
            {
                CollectNSharpTypeParameterBounds(nullable.InnerType, argType, typeParameters, allBounds);
            }
        }
        else if (paramTypeRef is ByRefTypeReference byRef)
        {
            var innerArgType = argType is ByRefTypeInfo byRefArg ? byRefArg.InnerType : argType;
            CollectNSharpTypeParameterBounds(byRef.InnerType, innerArgType, typeParameters, allBounds);
        }
        // Handle Func/Action delegate types for lambda inference
        else if (paramTypeRef is FunctionTypeReference funcRef)
        {
            if (argType is FunctionTypeInfo funcType)
            {
                // Match parameter types
                if (funcRef.ParameterTypes != null && funcType.ParameterTypes != null)
                {
                    for (int i = 0; i < funcRef.ParameterTypes.Count && i < funcType.ParameterTypes.Count; i++)
                    {
                        CollectNSharpTypeParameterBounds(funcRef.ParameterTypes[i], funcType.ParameterTypes[i], typeParameters, allBounds);
                    }
                }
                // Match return type
                if (funcRef.ReturnType != null && funcType.ReturnType != null)
                {
                    CollectNSharpTypeParameterBounds(funcRef.ReturnType, funcType.ReturnType, typeParameters, allBounds);
                }
            }
        }
    }

    /// <summary>
    /// Checks if two generic type names match, accounting for namespace-qualified names.
    /// e.g., "List" matches "List", and "Dictionary" matches "Dictionary".
    /// </summary>
    private static bool GenericNamesMatch(string refName, string infoName)
    {
        if (refName == infoName) return true;
        // Handle cases where one is qualified and the other isn't
        if (infoName.Contains('.'))
            return infoName.EndsWith("." + refName);
        if (refName.Contains('.'))
            return refName.EndsWith("." + infoName);
        return false;
    }

    /// <summary>
    /// Tries to match a GenericTypeReference (from a parameter declaration) against an ExternalTypeInfo (from an argument).
    /// This handles cases like matching List&lt;T&gt; against an ExternalTypeInfo("List`1") from reflection.
    /// </summary>
    private void TryMatchGenericRefAgainstExternalType(
        GenericTypeReference generic,
        ExternalTypeInfo ext,
        List<TypeParameter> typeParameters,
        Dictionary<string, List<TypeInfo>> allBounds)
    {
        // Try to resolve the ExternalTypeInfo to a CLR type for deeper matching
        var clrType = TryConvertTypeInfoToClrType(ext);
        if (clrType != null && clrType.IsGenericType)
        {
            var typeArgs = clrType.GetGenericArguments();
            if (generic.TypeArguments.Count == typeArgs.Length &&
                GenericNamesMatch(generic.Name, clrType.Name.Split('`')[0]))
            {
                for (int i = 0; i < generic.TypeArguments.Count; i++)
                {
                    CollectNSharpTypeParameterBounds(generic.TypeArguments[i], ConvertReflectionType(typeArgs[i]), typeParameters, allBounds);
                }
            }
        }
    }

    /// <summary>
    /// Applies inferred generic bindings to a resolved TypeInfo.
    /// Replaces ExternalTypeInfo/SimpleTypeInfo matching type parameter names with their bound types.
    /// </summary>
    private TypeInfo ApplyNSharpGenericBindings(TypeInfo type, Dictionary<string, TypeInfo>? bindings)
    {
        if (bindings == null || bindings.Count == 0)
            return type;

        // Check if this type is a generic parameter that should be replaced
        if (type is ExternalTypeInfo ext && bindings.TryGetValue(ext.Name, out var bound))
            return bound;
        if (type is SimpleTypeInfo simple && bindings.TryGetValue(simple.Name, out var simpleBound))
            return simpleBound;

        // Recurse into composite types
        if (type is GenericTypeInfo generic)
        {
            var newArgs = generic.TypeArguments.Select(a => ApplyNSharpGenericBindings(a, bindings)).ToList();
            return new GenericTypeInfo(generic.Name, newArgs);
        }
        if (type is ArrayTypeInfo array)
        {
            return new ArrayTypeInfo(ApplyNSharpGenericBindings(array.ElementType, bindings));
        }
        if (type is NullableTypeInfo nullable)
        {
            return new NullableTypeInfo(ApplyNSharpGenericBindings(nullable.InnerType, bindings));
        }
        if (type is ObliviousTypeInfo oblivious)
        {
            return new ObliviousTypeInfo(ApplyNSharpGenericBindings(oblivious.InnerType, bindings));
        }

        return type;
    }

    private abstract record ReflectionBoundArgument(int ParameterIndex, Type OpenParameterType);
    private sealed record SuppliedReflectionBoundArgument(int ParameterIndex, Type OpenParameterType, Argument Argument, int ArgumentIndex)
        : ReflectionBoundArgument(ParameterIndex, OpenParameterType);
    private sealed record DefaultReflectionBoundArgument(int ParameterIndex, Type OpenParameterType, ParameterInfo Parameter)
        : ReflectionBoundArgument(ParameterIndex, OpenParameterType);
    private sealed record ParamsReflectionBoundArgument(
        int ParameterIndex,
        Type OpenParameterType,
        Type OpenElementType,
        IReadOnlyList<(Argument Argument, int ArgumentIndex)> Arguments)
        : ReflectionBoundArgument(ParameterIndex, OpenParameterType);

    private FunctionTypeInfo? BindReflectionCall(ReflectionMethodGroupInfo methodGroup, CallExpression call)
    {
        TypeInfo? receiverTypeInfo = null;
        Type? receiverClrType = null;
        if (call.Callee is MemberAccessExpression memberAccess)
        {
            receiverTypeInfo = AnalyzeExpression(memberAccess.Object);
            receiverClrType = TryConvertTypeInfoToClrType(receiverTypeInfo)
                ?? TryConvertTypeInfoToClrTypeForBinding(receiverTypeInfo);
        }

        var analyzedNonLambdaArguments = new TypeInfo?[call.Arguments.Count];
        for (int i = 0; i < call.Arguments.Count; i++)
        {
            if (call.Arguments[i].Value is LambdaExpression)
                continue;

            analyzedNonLambdaArguments[i] = AnalyzeExpressionAllowingUnboundCallableReference(call.Arguments[i].Value);
        }

        var candidates = new List<(MethodInfo RuntimeMethod, MethodInfo SignatureMethod, Dictionary<Type, Type> Bindings, Dictionary<Type, TypeInfo> TypeInfoBindings,
            Dictionary<int, FunctionTypeInfo> MethodGroupArguments, IReadOnlyList<ReflectionBoundArgument> BoundArguments,
            int Score, bool UsesParams, int DefaultsUsed)>();

        foreach (var method in methodGroup.Methods)
        {
            var candidate = PreBindReflectionMethod(method, call, receiverClrType, receiverTypeInfo, analyzedNonLambdaArguments);
            if (candidate == null)
                continue;

            candidates.Add(candidate.Value);
        }

        if (candidates.Count == 0)
            return null;

        foreach (var candidate in candidates
                     .OrderByDescending(candidate => candidate.Score)
                     .ThenBy(candidate => candidate.UsesParams)
                     .ThenBy(candidate => candidate.DefaultsUsed))
        {
            var errorsBefore = _errors.Count;
            var boundCall = FinalizeBoundReflectionCall(
                candidate.RuntimeMethod,
                candidate.SignatureMethod,
                call,
                candidate.Bindings,
                candidate.TypeInfoBindings,
                candidate.MethodGroupArguments,
                candidate.BoundArguments);
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
            receiverClrType = TryConvertTypeInfoToClrType(receiverTypeInfo)
                ?? TryConvertTypeInfoToClrTypeForBinding(receiverTypeInfo);
        }

        var analyzedNonLambdaArguments = new TypeInfo?[call.Arguments.Count];
        for (int i = 0; i < call.Arguments.Count; i++)
        {
            if (call.Arguments[i].Value is LambdaExpression)
                continue;

            analyzedNonLambdaArguments[i] = AnalyzeExpressionAllowingUnboundCallableReference(call.Arguments[i].Value);
        }

        var preBound = PreBindReflectionMethod(method, call, receiverClrType, receiverTypeInfo, analyzedNonLambdaArguments);
        if (preBound == null)
            return null;

        return FinalizeBoundReflectionCall(
            preBound.Value.RuntimeMethod,
            preBound.Value.SignatureMethod,
            call,
            preBound.Value.Bindings,
            preBound.Value.TypeInfoBindings,
            preBound.Value.MethodGroupArguments,
            preBound.Value.BoundArguments);
    }

    private (MethodInfo RuntimeMethod, MethodInfo SignatureMethod, Dictionary<Type, Type> Bindings, Dictionary<Type, TypeInfo> TypeInfoBindings,
        Dictionary<int, FunctionTypeInfo> MethodGroupArguments, IReadOnlyList<ReflectionBoundArgument> BoundArguments,
        int Score, bool UsesParams, int DefaultsUsed)? PreBindReflectionMethod(
        MethodInfo method,
        CallExpression call,
        Type? receiverClrType,
        TypeInfo? receiverTypeInfo,
        TypeInfo?[] analyzedNonLambdaArguments)
    {
        var bindings = new Dictionary<Type, Type>();
        var typeInfoBindings = new Dictionary<Type, TypeInfo>();
        var methodGroupArguments = new Dictionary<int, FunctionTypeInfo>();
        var openMethod = GetOpenReflectionSignatureMethod(method);
        var parameterOffset = IsExtensionMethodCall(openMethod, call, receiverClrType) ? 1 : 0;
        var parameters = openMethod.GetParameters();
        var receiverScore = 0;

        if (parameterOffset == 1)
        {
            if (receiverClrType == null || !TryMatchReflectionParameter(parameters[0].ParameterType, receiverClrType, bindings))
                return null;

            // Track N# TypeInfo bindings from the receiver type
            if (receiverTypeInfo != null)
                PopulateTypeInfoBindingsFromType(parameters[0].ParameterType, receiverTypeInfo, typeInfoBindings);

            receiverScore = GetReflectionMatchScore(ApplyReflectionBindings(parameters[0].ParameterType, bindings), receiverClrType);
        }
        else if (receiverClrType != null
                 && receiverTypeInfo != null
                 && !TryPopulateReceiverGenericTypeBindings(openMethod.DeclaringType, receiverClrType, receiverTypeInfo, bindings, typeInfoBindings))
        {
            return null;
        }

        if (call.TypeArguments != null && call.TypeArguments.Count > 0)
        {
            if (!openMethod.IsGenericMethodDefinition)
                return null;

            var genericParameters = openMethod.GetGenericArguments();
            if (genericParameters.Length != call.TypeArguments.Count)
                return null;

            for (int i = 0; i < genericParameters.Length; i++)
            {
                var resolvedTypeInfo = ResolveType(call.TypeArguments[i]);
                var typeArgument = TryConvertTypeInfoToClrType(resolvedTypeInfo);
                if (typeArgument == null)
                {
                    // N# type - use object as CLR surrogate for binding
                    typeArgument = TryConvertTypeInfoToClrTypeForBinding(resolvedTypeInfo);
                    if (typeArgument == null)
                        return null;
                }

                bindings[genericParameters[i]] = typeArgument;
                typeInfoBindings[genericParameters[i]] = resolvedTypeInfo;
            }
        }

        if (!HasCompatibleReflectionArity(parameters, parameterOffset, call.Arguments.Count))
            return null;

        // Extension methods get a small penalty so instance methods are preferred (matches C# semantics)
        var score = (parameterOffset == 1 ? -1 : 0) + receiverScore;

        if (!TryBindReflectionArguments(
                parameters,
                parameterOffset,
                call,
                bindings,
                typeInfoBindings,
                methodGroupArguments,
                analyzedNonLambdaArguments,
                out var boundArguments,
                out var argumentScore,
                out var usesParams,
                out var defaultsUsed))
        {
            return null;
        }

        score += argumentScore;
        return (method, openMethod, bindings, typeInfoBindings, methodGroupArguments, boundArguments, score, usesParams, defaultsUsed);
    }

    private static MethodInfo GetOpenReflectionSignatureMethod(MethodInfo method)
    {
        var signatureMethod = method.IsGenericMethod ? method.GetGenericMethodDefinition() : method;
        var declaringType = signatureMethod.DeclaringType;
        if (declaringType is not { IsGenericType: true } || declaringType.IsGenericTypeDefinition)
            return signatureMethod;

            var genericDefinition = declaringType.GetGenericTypeDefinition();
            const BindingFlags flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static;
            return genericDefinition.GetMethods(flags)
                .FirstOrDefault(candidate => candidate.MetadataToken == signatureMethod.MetadataToken)
                ?? signatureMethod;
    }

    private bool TryPopulateReceiverGenericTypeBindings(
        Type? declaringType,
        Type receiverClrType,
        TypeInfo receiverTypeInfo,
        Dictionary<Type, Type> bindings,
        Dictionary<Type, TypeInfo> typeInfoBindings)
    {
        if (declaringType is not { IsGenericType: true, ContainsGenericParameters: true })
            return true;

        var receiverSignatureType = declaringType.IsGenericTypeDefinition
            ? declaringType
            : declaringType.GetGenericTypeDefinition();

        if (!TryMatchReflectionParameter(receiverSignatureType, receiverClrType, bindings))
            return false;

        PopulateTypeInfoBindingsFromType(receiverSignatureType, receiverTypeInfo, typeInfoBindings);
        return true;
    }

    private bool TryBindReflectionArguments(
        ParameterInfo[] parameters,
        int parameterOffset,
        CallExpression call,
        Dictionary<Type, Type> bindings,
        Dictionary<Type, TypeInfo> typeInfoBindings,
        Dictionary<int, FunctionTypeInfo> methodGroupArguments,
        TypeInfo?[] analyzedNonLambdaArguments,
        out IReadOnlyList<ReflectionBoundArgument> boundArguments,
        out int score,
        out bool usesParams,
        out int defaultsUsed)
    {
        boundArguments = Array.Empty<ReflectionBoundArgument>();
        score = 0;
        defaultsUsed = 0;

        var bound = new ReflectionBoundArgument?[parameters.Length];
        usesParams = parameters.Length > parameterOffset && IsParamsParameter(parameters[^1]);
        var paramsParameterIndex = usesParams ? parameters.Length - 1 : -1;
        var nextPositionalParameter = parameterOffset;
        var paramsArguments = new List<(Argument Argument, int ArgumentIndex)>();

        for (int argumentIndex = 0; argumentIndex < call.Arguments.Count; argumentIndex++)
        {
            var argument = call.Arguments[argumentIndex];
            if (argument.Name != null)
            {
                var parameterIndex = Array.FindIndex(
                    parameters,
                    parameterOffset,
                    parameters.Length - parameterOffset,
                    parameter => string.Equals(parameter.Name, argument.Name, StringComparison.Ordinal));
                if (parameterIndex < parameterOffset || parameterIndex >= parameters.Length || bound[parameterIndex] != null)
                    return false;

                bound[parameterIndex] = new SuppliedReflectionBoundArgument(
                    parameterIndex,
                    GetByRefElementType(parameters[parameterIndex].ParameterType),
                    argument,
                    argumentIndex);
                continue;
            }

            while (nextPositionalParameter < parameters.Length
                   && nextPositionalParameter != paramsParameterIndex
                   && bound[nextPositionalParameter] != null)
            {
                nextPositionalParameter++;
            }

            if (nextPositionalParameter < parameters.Length
                && nextPositionalParameter != paramsParameterIndex)
            {
                bound[nextPositionalParameter] = new SuppliedReflectionBoundArgument(
                    nextPositionalParameter,
                    GetByRefElementType(parameters[nextPositionalParameter].ParameterType),
                    argument,
                    argumentIndex);
                nextPositionalParameter++;
                continue;
            }

            if (!usesParams)
                return false;

            paramsArguments.Add((argument, argumentIndex));
        }

        var regularParameterEnd = usesParams ? paramsParameterIndex : parameters.Length;
        for (int parameterIndex = parameterOffset; parameterIndex < regularParameterEnd; parameterIndex++)
        {
            if (bound[parameterIndex] != null)
                continue;

            if (!parameters[parameterIndex].IsOptional)
                return false;

            bound[parameterIndex] = new DefaultReflectionBoundArgument(
                parameterIndex,
                GetByRefElementType(parameters[parameterIndex].ParameterType),
                parameters[parameterIndex]);
            defaultsUsed++;
        }

        if (usesParams)
        {
            if (bound[paramsParameterIndex] != null && paramsArguments.Count > 0)
                return false;

            if (bound[paramsParameterIndex] == null)
            {
                var paramsParameterType = GetByRefElementType(parameters[paramsParameterIndex].ParameterType);
                if (!TryGetReflectionParamsElementType(paramsParameterType, out var elementType))
                    return false;

                if (paramsArguments.Count == 1
                    && ShouldPassReflectionParamsArgumentDirectly(
                        paramsArguments[0].Argument,
                        paramsArguments[0].ArgumentIndex,
                        paramsParameterType,
                        bindings,
                        analyzedNonLambdaArguments))
                {
                    bound[paramsParameterIndex] = new SuppliedReflectionBoundArgument(
                        paramsParameterIndex,
                        paramsParameterType,
                        paramsArguments[0].Argument,
                        paramsArguments[0].ArgumentIndex);
                }
                else
                {
                    bound[paramsParameterIndex] = new ParamsReflectionBoundArgument(
                        paramsParameterIndex,
                        paramsParameterType,
                        elementType,
                        paramsArguments);
                }
            }
        }

        var materializedBoundArguments = new List<ReflectionBoundArgument>();
        for (int parameterIndex = parameterOffset; parameterIndex < parameters.Length; parameterIndex++)
        {
            var boundArgument = bound[parameterIndex];
            if (boundArgument == null)
                continue;

            switch (boundArgument)
            {
                case DefaultReflectionBoundArgument:
                    break;

                case SuppliedReflectionBoundArgument supplied:
                    if (!TryScoreReflectionSuppliedArgument(
                            supplied,
                            parameters[supplied.ParameterIndex],
                            bindings,
                            typeInfoBindings,
                            methodGroupArguments,
                            analyzedNonLambdaArguments,
                            out var suppliedScore))
                    {
                        return false;
                    }
                    score += suppliedScore;
                    break;

                case ParamsReflectionBoundArgument paramsBound:
                    foreach (var (argument, argumentIndex) in paramsBound.Arguments)
                    {
                        var suppliedParamsElement = new SuppliedReflectionBoundArgument(
                            paramsBound.ParameterIndex,
                            paramsBound.OpenElementType,
                            argument,
                            argumentIndex);
                        if (!TryScoreReflectionSuppliedArgument(
                                suppliedParamsElement,
                                parameters[paramsBound.ParameterIndex],
                                bindings,
                                typeInfoBindings,
                                methodGroupArguments,
                                analyzedNonLambdaArguments,
                                out var paramsElementScore,
                                expectsParamsElement: true))
                        {
                            return false;
                        }
                        score += paramsElementScore;
                    }
                    break;
            }

            materializedBoundArguments.Add(boundArgument);
        }

        boundArguments = materializedBoundArguments;
        return true;
    }

    private bool TryScoreReflectionSuppliedArgument(
        SuppliedReflectionBoundArgument supplied,
        ParameterInfo parameter,
        Dictionary<Type, Type> bindings,
        Dictionary<Type, TypeInfo> typeInfoBindings,
        Dictionary<int, FunctionTypeInfo> methodGroupArguments,
        TypeInfo?[] analyzedNonLambdaArguments,
        out int score,
        bool expectsParamsElement = false)
    {
        score = 0;

        var expectsByRef = !expectsParamsElement && parameter.ParameterType.IsByRef;
        var suppliedByRef = supplied.Argument.Modifier is ArgumentModifier.Ref or ArgumentModifier.Out;
        if (expectsByRef != suppliedByRef)
            return false;

        var openParameterType = supplied.OpenParameterType;
        var boundParameterType = ApplyReflectionBindings(openParameterType, bindings);

        if (supplied.Argument.Value is DefaultExpression)
        {
            score = 8;
            return true;
        }

        if (supplied.Argument.Value is LambdaExpression lambda)
        {
            var expectedSignature = CreateDelegateSignatureFromOpenType(
                openParameterType,
                typeInfoBindings,
                bindings);

            if (expectedSignature?.ParameterTypes == null || expectedSignature.ParameterTypes.Count != lambda.Parameters.Count)
                return false;

            score = 2 + expectedSignature.ParameterTypes.Count;
            return true;
        }

        var argumentType = analyzedNonLambdaArguments[supplied.ArgumentIndex];
        if (argumentType == null)
            return false;

        if (TryBindMethodGroupToReflectionDelegate(openParameterType, argumentType, bindings, out var selectedMethodGroup, out var methodGroupScore))
        {
            if (!TryPopulateReflectionBindingsFromMethodGroupDelegate(
                    openParameterType,
                    selectedMethodGroup,
                    bindings,
                    typeInfoBindings))
            {
                return false;
            }

            methodGroupArguments[supplied.ArgumentIndex] = selectedMethodGroup;
            score = methodGroupScore;
            return true;
        }

        var argumentClrType = TryConvertTypeInfoToClrType(argumentType)
            ?? TryConvertTypeInfoToClrTypeForBinding(argumentType);
        if (argumentClrType != null)
        {
            if (!TryMatchReflectionParameter(openParameterType, argumentClrType, bindings))
                return false;

            PopulateTypeInfoBindingsFromType(openParameterType, argumentType, typeInfoBindings);

            score = GetReflectionMatchScore(ApplyReflectionBindings(openParameterType, bindings), argumentClrType);
            return true;
        }

        var expectedType = ConvertReflectionType(boundParameterType);
        if (!IsAssignable(expectedType, argumentType))
            return false;

        score = 1;
        return true;
    }

    private static Type GetByRefElementType(Type type)
    {
        return type.IsByRef ? type.GetElementType()! : type;
    }

    private static bool TryGetReflectionParamsElementType(Type paramsParameterType, out Type elementType)
    {
        if (paramsParameterType.IsArray)
        {
            elementType = paramsParameterType.GetElementType()!;
            return true;
        }

        if (paramsParameterType.IsGenericType)
        {
            var genericDefinitionName = paramsParameterType.GetGenericTypeDefinition().FullName;
            if (genericDefinitionName is "System.ReadOnlySpan`1" or "System.Span`1"
                or "System.Collections.Generic.IEnumerable`1"
                or "System.Collections.Generic.IReadOnlyList`1"
                or "System.Collections.Generic.IReadOnlyCollection`1")
            {
                elementType = paramsParameterType.GetGenericArguments()[0];
                return true;
            }
        }

        elementType = typeof(object);
        return false;
    }

    private bool ShouldPassReflectionParamsArgumentDirectly(
        Argument argument,
        int argumentIndex,
        Type paramsParameterType,
        Dictionary<Type, Type> bindings,
        TypeInfo?[] analyzedNonLambdaArguments)
    {
        if (argument.Value is SpreadExpression)
            return false;

        if (argument.Value is DefaultExpression)
            return true;

        if (argument.Value is LambdaExpression)
            return false;

        var argumentType = analyzedNonLambdaArguments[argumentIndex];
        if (argumentType == null || BuiltInTypes.IsUnknown(argumentType))
            return false;

        var argumentClrType = TryConvertTypeInfoToClrType(argumentType)
            ?? TryConvertTypeInfoToClrTypeForBinding(argumentType);
        if (argumentClrType != null)
        {
            var trialBindings = new Dictionary<Type, Type>(bindings);
            return TryMatchReflectionParameter(paramsParameterType, argumentClrType, trialBindings);
        }

        var expectedType = ConvertReflectionType(ApplyReflectionBindings(paramsParameterType, bindings));
        return IsAssignable(expectedType, argumentType);
    }

    private bool TryBindMethodGroupToReflectionDelegate(
        Type parameterType,
        TypeInfo argumentType,
        Dictionary<Type, Type> bindings,
        out FunctionTypeInfo selectedMethodGroup,
        out int score)
    {
        selectedMethodGroup = null!;
        score = 0;

        var delegateType = ApplyReflectionBindings(parameterType, bindings);
        if (!IsDelegateType(delegateType))
            return false;

        var expectedSignature = CreateFunctionTypeInfoFromDelegate(delegateType);
        if (expectedSignature.ParameterTypes == null)
            return false;

        bool TryGetMatchScore(FunctionTypeInfo functionType, out int candidateScore)
        {
            candidateScore = 0;
            return functionType.Declaration != null
                && TryGetRuntimeDelegateMethodGroupMatchScore(functionType, expectedSignature, out candidateScore);
        }

        if (argumentType is FunctionTypeInfo functionType)
        {
            if (!TryGetMatchScore(functionType, out var candidateScore))
                return false;

            selectedMethodGroup = functionType;
            score = 4 + candidateScore;
            return true;
        }

        if (argumentType is NSharpMethodGroupInfo methodGroup)
        {
            var bestScore = -1;
            var ambiguous = false;
            FunctionTypeInfo? bestFunctionType = null;
            foreach (var declaration in methodGroup.Declarations)
            {
                var candidateType = CreateFunctionTypeInfo(declaration);
                if (!TryGetMatchScore(candidateType, out var candidateScore))
                    continue;

                var scoreWithConversion = 4 + candidateScore;
                if (scoreWithConversion > bestScore)
                {
                    bestScore = scoreWithConversion;
                    bestFunctionType = candidateType;
                    ambiguous = false;
                }
                else if (scoreWithConversion == bestScore)
                {
                    ambiguous = true;
                }
            }

            if (bestFunctionType == null || bestScore < 0 || ambiguous)
                return false;

            selectedMethodGroup = bestFunctionType;
            score = bestScore;
            return true;
        }

        return false;
    }

    private bool TryPopulateReflectionBindingsFromMethodGroupDelegate(
        Type openDelegateType,
        FunctionTypeInfo sourceFunctionType,
        Dictionary<Type, Type> bindings,
        Dictionary<Type, TypeInfo> typeInfoBindings)
    {
        try
        {
            var invokeMethod = openDelegateType.GetMethod("Invoke");
            if (invokeMethod == null)
                return false;

            var invokeParameters = invokeMethod.GetParameters();
            var sourceParameterTypes = sourceFunctionType.ParameterTypes ?? new List<TypeInfo>();
            if (invokeParameters.Length != sourceParameterTypes.Count)
                return false;

            for (int i = 0; i < invokeParameters.Length; i++)
            {
                PopulateReflectionBindingsFromTypeInfo(
                    invokeParameters[i].ParameterType,
                    sourceParameterTypes[i],
                    bindings,
                    typeInfoBindings);
            }

            if (invokeMethod.ReturnType != typeof(void) && sourceFunctionType.ReturnType != null)
            {
                PopulateReflectionBindingsFromTypeInfo(
                    invokeMethod.ReturnType,
                    sourceFunctionType.ReturnType,
                    bindings,
                    typeInfoBindings);
            }

            return true;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private void PopulateReflectionBindingsFromTypeInfo(
        Type openType,
        TypeInfo sourceType,
        Dictionary<Type, Type> bindings,
        Dictionary<Type, TypeInfo> typeInfoBindings)
    {
        openType = openType.IsByRef ? openType.GetElementType()! : openType;

        if (openType.IsGenericParameter)
        {
            if (!typeInfoBindings.ContainsKey(openType))
                typeInfoBindings[openType] = sourceType;

            if (!bindings.ContainsKey(openType))
            {
                var clrType = TryConvertTypeInfoToClrType(sourceType)
                    ?? TryConvertTypeInfoToClrTypeForBinding(sourceType);
                if (clrType != null)
                    bindings[openType] = clrType;
            }

            return;
        }

        if (openType.IsArray)
        {
            if (sourceType is ArrayTypeInfo sourceArray)
            {
                PopulateReflectionBindingsFromTypeInfo(
                    openType.GetElementType()!,
                    sourceArray.ElementType,
                    bindings,
                    typeInfoBindings);
            }

            return;
        }

        if (!openType.IsGenericType)
            return;

        PopulateTypeInfoBindingsFromType(openType, sourceType, typeInfoBindings);

        if (sourceType is GenericTypeInfo sourceGeneric)
        {
            var openName = openType.Name.Contains('`')
                ? openType.Name[..openType.Name.IndexOf('`')]
                : openType.Name;
            var openArguments = openType.GetGenericArguments();
            if (GenericNamesMatch(openName, sourceGeneric.Name)
                && openArguments.Length == sourceGeneric.TypeArguments.Count)
            {
                for (int i = 0; i < openArguments.Length; i++)
                {
                    PopulateReflectionBindingsFromTypeInfo(
                        openArguments[i],
                        sourceGeneric.TypeArguments[i],
                        bindings,
                        typeInfoBindings);
                }
            }
        }
    }

    private FunctionTypeInfo? FinalizeBoundReflectionCall(
        MethodInfo runtimeMethod,
        MethodInfo signatureMethod,
        CallExpression call,
        Dictionary<Type, Type> bindings,
        Dictionary<Type, TypeInfo> typeInfoBindings,
        Dictionary<int, FunctionTypeInfo> methodGroupArguments,
        IReadOnlyList<ReflectionBoundArgument> boundArguments)
    {
        var workingBindings = new Dictionary<Type, Type>(bindings);
        var workingTypeInfoBindings = new Dictionary<Type, TypeInfo>(typeInfoBindings);
        var openMethod = signatureMethod; // Preserve the open method for TypeInfo-based resolution
        var method = runtimeMethod;
        var hasTypeInfoOverrides = workingTypeInfoBindings.Count > 0;

        foreach (var boundArgument in EnumerateSuppliedReflectionArguments(boundArguments))
        {
            if (boundArgument.Argument.Value is not LambdaExpression lambda)
                continue;

            var expectedSignature = CreateDelegateSignatureFromOpenType(
                boundArgument.OpenParameterType,
                workingTypeInfoBindings,
                workingBindings);
            if (expectedSignature == null)
                return null;

            var lambdaType = AnalyzeLambda(
                lambda,
                expectedSignature,
                isExpressionTreeTarget: IsExpressionTreeLambdaTarget(boundArgument.OpenParameterType));
            var lambdaDelegateType = TryConstructDelegateType(lambdaType);
            if (lambdaDelegateType != null)
            {
                var delegateParameterType = GetDelegateParameterTypeForLambdaTarget(boundArgument.OpenParameterType);
                TryMatchReflectionParameter(delegateParameterType, lambdaDelegateType, workingBindings);
            }

            var lambdaReturnClrType = lambdaType.ReturnType != null
                ? (TryConvertTypeInfoToClrType(lambdaType.ReturnType)
                    ?? TryConvertTypeInfoToClrTypeForBinding(lambdaType.ReturnType))
                : null;
            if (lambdaReturnClrType != null && method.IsGenericMethodDefinition)
            {
                var remainingGenericArguments = method.GetGenericArguments()
                    .Where(argument => !workingBindings.ContainsKey(argument))
                    .ToList();

                if (remainingGenericArguments.Count == 1)
                {
                    workingBindings[remainingGenericArguments[0]] = lambdaReturnClrType;
                    if (lambdaType.ReturnType != null)
                        workingTypeInfoBindings[remainingGenericArguments[0]] = lambdaType.ReturnType;
                }
            }
        }

        if (method.IsGenericMethodDefinition)
        {
            var genericArguments = method.GetGenericArguments();
            if (genericArguments.Any(argument => !workingBindings.ContainsKey(argument)))
                return null;

            method = method.MakeGenericMethod(genericArguments.Select(argument => workingBindings[argument]).ToArray());
        }

        // Recalculate whether we have overrides (lambda return types may have added more)
        hasTypeInfoOverrides = workingTypeInfoBindings.Count > 0;

        var parameterTypes = new List<TypeInfo>();
        var validatedArgumentTypes = new List<TypeInfo>();
        var openParameters = openMethod.GetParameters();

        foreach (var boundArgument in boundArguments)
        {
            switch (boundArgument)
            {
                case DefaultReflectionBoundArgument defaultArgument:
                {
                    var defaultType = NullabilityMetadata.ConvertParameter(
                        defaultArgument.Parameter,
                        type => ConvertReflectionTypeWithOverrides(type, workingTypeInfoBindings, workingBindings));
                    parameterTypes.Add(defaultType);
                    validatedArgumentTypes.Add(defaultType);
                    break;
                }

                case SuppliedReflectionBoundArgument supplied:
                {
                    var parameter = openParameters[supplied.ParameterIndex];
                    if (!ValidateFinalReflectionSuppliedArgument(
                            supplied,
                            parameter,
                            workingBindings,
                            workingTypeInfoBindings,
                            methodGroupArguments,
                            hasTypeInfoOverrides,
                            parameterTypes,
                            validatedArgumentTypes))
                    {
                        return null;
                    }
                    break;
                }

                case ParamsReflectionBoundArgument paramsBound:
                {
                    foreach (var (argument, argumentIndex) in paramsBound.Arguments)
                    {
                        var suppliedElement = new SuppliedReflectionBoundArgument(
                            paramsBound.ParameterIndex,
                            paramsBound.OpenElementType,
                            argument,
                            argumentIndex);
                        var parameter = openParameters[paramsBound.ParameterIndex];
                        if (!ValidateFinalReflectionSuppliedArgument(
                                suppliedElement,
                                parameter,
                                workingBindings,
                                workingTypeInfoBindings,
                                methodGroupArguments,
                                hasTypeInfoOverrides,
                                parameterTypes,
                                validatedArgumentTypes))
                        {
                            return null;
                        }
                    }
                    break;
                }
            }
        }

        // Compute return type using TypeInfo overrides for the open method's return type
        var returnType = NullabilityMetadata.ConvertReturn(
            openMethod,
            type => hasTypeInfoOverrides || type.ContainsGenericParameters
                ? ConvertReflectionTypeWithOverrides(type, workingTypeInfoBindings, workingBindings)
                : ConvertReflectionType(ApplyReflectionBindings(type, workingBindings)));


        return new FunctionTypeInfo(null)
        {
            ParameterTypes = parameterTypes,
            ReturnType = returnType
        };
    }

    private IEnumerable<SuppliedReflectionBoundArgument> EnumerateSuppliedReflectionArguments(
        IReadOnlyList<ReflectionBoundArgument> boundArguments)
    {
        foreach (var boundArgument in boundArguments)
        {
            switch (boundArgument)
            {
                case SuppliedReflectionBoundArgument supplied:
                    yield return supplied;
                    break;
                case ParamsReflectionBoundArgument paramsBound:
                    foreach (var (argument, argumentIndex) in paramsBound.Arguments)
                    {
                        yield return new SuppliedReflectionBoundArgument(
                            paramsBound.ParameterIndex,
                            paramsBound.OpenElementType,
                            argument,
                            argumentIndex);
                    }
                    break;
            }
        }
    }

    private bool ValidateFinalReflectionSuppliedArgument(
        SuppliedReflectionBoundArgument supplied,
        ParameterInfo parameter,
        Dictionary<Type, Type> workingBindings,
        Dictionary<Type, TypeInfo> workingTypeInfoBindings,
        Dictionary<int, FunctionTypeInfo> methodGroupArguments,
        bool hasTypeInfoOverrides,
        List<TypeInfo> parameterTypes,
        List<TypeInfo> validatedArgumentTypes)
    {
        if (supplied.Argument.Value is LambdaExpression lambda)
        {
            var expectedSignature = CreateDelegateSignatureFromOpenType(
                supplied.OpenParameterType,
                workingTypeInfoBindings,
                workingBindings);
            parameterTypes.Add(expectedSignature ?? new FunctionTypeInfo(null) { ReturnType = BuiltInTypes.Unknown });

            if (expectedSignature == null)
                return false;

            var lambdaArgumentType = AnalyzeLambda(
                lambda,
                expectedSignature,
                isExpressionTreeTarget: IsExpressionTreeLambdaTarget(supplied.OpenParameterType));
            validatedArgumentTypes.Add(lambdaArgumentType);
            return true;
        }

        var expectedType = NullabilityMetadata.ConvertParameter(
            parameter,
            type => hasTypeInfoOverrides || type.ContainsGenericParameters
                ? ConvertReflectionTypeWithOverrides(type, workingTypeInfoBindings, workingBindings)
                : ConvertReflectionType(ApplyReflectionBindings(type, workingBindings)));
        parameterTypes.Add(expectedType);

        if (methodGroupArguments.TryGetValue(supplied.ArgumentIndex, out var selectedMethodGroup))
        {
            var expectedSignature = CreateDelegateSignatureFromOpenType(
                supplied.OpenParameterType,
                workingTypeInfoBindings,
                workingBindings);

            if (expectedSignature?.ParameterTypes == null
                || !IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(selectedMethodGroup, expectedSignature))
            {
                return false;
            }

            validatedArgumentTypes.Add(selectedMethodGroup);
            return true;
        }

        var argumentType = AnalyzeExpressionWithExpectedType(supplied.Argument.Value, expectedType);
        validatedArgumentTypes.Add(argumentType);

        return IsAssignableReflectionArgument(expectedType, argumentType);
    }

    private bool IsAssignableReflectionArgument(TypeInfo expectedType, TypeInfo argumentType)
    {
        if (IsAssignable(expectedType, argumentType))
            return true;

        var resolvedArgument = ResolveTypeAlias(argumentType);
        if (resolvedArgument is NullableTypeInfo nullableArgument
            && IsReferenceType(ResolveTypeAlias(nullableArgument.InnerType)))
        {
            return IsAssignable(expectedType, nullableArgument.InnerType);
        }

        return false;
    }

    private static bool HasCompatibleReflectionArity(ParameterInfo[] parameters, int parameterOffset, int argumentCount)
    {
        var effectiveParameters = parameters.Skip(parameterOffset).ToArray();
        var hasParams = effectiveParameters.Length > 0 && IsParamsParameter(effectiveParameters[^1]);

        var requiredParameters = effectiveParameters.Count(parameter => !parameter.IsOptional && !IsParamsParameter(parameter));
        if (argumentCount < requiredParameters)
            return false;

        if (!hasParams && argumentCount > effectiveParameters.Length)
            return false;

        return true;
    }

    private static bool IsParamsParameter(ParameterInfo parameter)
    {
            return parameter.GetCustomAttributesData()
                .Any(a => a.AttributeType.FullName == "System.ParamArrayAttribute");
    }

    private static bool IsExtensionMethodCall(MethodInfo method, CallExpression call)
    {
        return call.Callee is MemberAccessExpression && HasExtensionAttribute(method);
    }

    private bool IsExtensionMethodCall(MethodInfo method, CallExpression call, Type? receiverClrType)
    {
        if (call.Callee is not MemberAccessExpression || !HasExtensionAttribute(method))
            return false;

        var parameters = method.GetParameters();
        return receiverClrType != null
            && parameters.Length > 0
            && IsExtensionParameterCompatible(parameters[0].ParameterType, receiverClrType);
    }

    private static int GetReflectionMatchScore(Type parameterType, Type argumentType)
    {
        if (HaveSameReflectionTypeIdentity(parameterType, argumentType))
            return 8;

        if (IsImplicitNumericConversion(argumentType, parameterType))
            return 6;

        if (IsReflectionAssignableFrom(parameterType, argumentType))
            return 4;

        return 2;
    }

    private static bool IsImplicitNumericConversion(Type sourceType, Type targetType)
    {
        if (sourceType == targetType)
            return true;

        var sourceName = GetNumericTypeFullName(sourceType);
        var targetName = GetNumericTypeFullName(targetType);

        return (sourceName, targetName) switch
        {
            ("System.Byte", "System.Int16" or "System.UInt16" or "System.Int32" or "System.UInt32" or "System.Int64" or "System.UInt64" or "System.Single" or "System.Double" or "System.Decimal") => true,
            ("System.SByte", "System.Int16" or "System.Int32" or "System.Int64" or "System.Single" or "System.Double" or "System.Decimal") => true,
            ("System.Int16", "System.Int32" or "System.Int64" or "System.Single" or "System.Double" or "System.Decimal") => true,
            ("System.UInt16", "System.Int32" or "System.UInt32" or "System.Int64" or "System.UInt64" or "System.Single" or "System.Double" or "System.Decimal") => true,
            ("System.Int32", "System.Int64" or "System.Single" or "System.Double" or "System.Decimal") => true,
            ("System.UInt32", "System.Int64" or "System.UInt64" or "System.Single" or "System.Double" or "System.Decimal") => true,
            ("System.Int64", "System.Single" or "System.Double" or "System.Decimal") => true,
            ("System.UInt64", "System.Single" or "System.Double" or "System.Decimal") => true,
            ("System.Char", "System.UInt16" or "System.Int32" or "System.UInt32" or "System.Int64" or "System.UInt64" or "System.Single" or "System.Double" or "System.Decimal") => true,
            ("System.Single", "System.Double") => true,
            _ => false
        };
    }

    private static string? GetNumericTypeFullName(Type type)
    {
        var underlyingType = Nullable.GetUnderlyingType(type) ?? type;
        return underlyingType.FullName;
    }

    private Type ApplyReflectionBindings(Type type, Dictionary<Type, Type> bindings)
    {
        if (type.IsGenericParameter && bindings.TryGetValue(type, out var boundType))
            return boundType;

        if (type.IsByRef)
        {
            var elementType = ApplyReflectionBindings(type.GetElementType()!, bindings);
            return elementType.MakeByRefType();
        }

        if (type.IsArray)
        {
            var elementType = ApplyReflectionBindings(type.GetElementType()!, bindings);
            return elementType == type.GetElementType()! ? type : elementType.MakeArrayType();
        }

        if (!type.IsGenericType)
            return type;

        var typeArguments = type.GetGenericArguments();
        var appliedArguments = typeArguments.Select(argument => ApplyReflectionBindings(argument, bindings)).ToArray();
        if (appliedArguments.SequenceEqual(typeArguments))
            return type;

        return type.GetGenericTypeDefinition().MakeGenericType(appliedArguments);
    }

    private bool TryMatchReflectionParameter(Type parameterType, Type argumentType, Dictionary<Type, Type> bindings)
    {
        if (parameterType.IsByRef)
            parameterType = parameterType.GetElementType()!;

        if (parameterType.IsGenericParameter)
        {
            if (bindings.TryGetValue(parameterType, out var existingBinding))
                return HaveSameReflectionTypeIdentity(existingBinding, argumentType)
                    || IsReflectionAssignableFrom(existingBinding, argumentType)
                    || IsImplicitNumericConversion(argumentType, existingBinding);

            bindings[parameterType] = argumentType;
            return true;
        }

        if (!parameterType.ContainsGenericParameters)
            return IsReflectionAssignableFrom(parameterType, argumentType)
                || IsImplicitNumericConversion(argumentType, parameterType);

        if (parameterType.IsArray)
        {
            return argumentType.IsArray &&
                TryMatchReflectionParameter(parameterType.GetElementType()!, argumentType.GetElementType()!, bindings);
        }

        if (!parameterType.IsGenericType)
            return true;

        var comparisonType = argumentType;
        if (!TryFindCompatibleGenericType(parameterType, argumentType, out var compatibleType))
        {
            if (!argumentType.IsGenericType || argumentType.GetGenericTypeDefinition() != parameterType.GetGenericTypeDefinition())
                return false;
        }
        else if (compatibleType != null)
        {
            comparisonType = compatibleType;
        }

        var parameterArguments = parameterType.GetGenericArguments();
        var comparisonArguments = comparisonType.GetGenericArguments();
        if (parameterArguments.Length != comparisonArguments.Length)
            return false;

        for (int i = 0; i < parameterArguments.Length; i++)
        {
            if (!TryMatchReflectionParameter(parameterArguments[i], comparisonArguments[i], bindings))
                return false;
        }

        return true;
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
                var (discardLine, discardColumn, discardLength) = GetExpressionDiagnosticSpan(assignment.Target);
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
                $"assigned with '{GetAssignmentOperatorText(assignment.Operator)}'"))
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
                GetAssignmentOperatorText(assignment.Operator),
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

        var valueAssignable = IsAssignable(targetType, valueType);
        if (!valueAssignable)
        {
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(assignment.Value);
            var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
                ? _sourceLines[diagnosticLine - 1]
                : null;

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
        MarkErrorTupleResultAvailableAfterAssignment(assignment.Target);

        return targetType;
    }

    private bool ReportInvalidCompoundAssignmentIfNeeded(
        AssignmentExpression assignment,
        TypeInfo targetType,
        TypeInfo valueType)
    {
        if (!TryGetCompoundAssignmentBinaryOperator(assignment.Operator, out var binaryOperator))
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

        if (IsAssignable(targetType, resultType))
        {
            return false;
        }

        var opText = GetAssignmentOperatorText(assignment.Operator);
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

    private static bool TryGetCompoundAssignmentBinaryOperator(AssignmentOperator assignmentOperator, out BinaryOperator binaryOperator)
    {
        switch (assignmentOperator)
        {
            case AssignmentOperator.AddAssign:
                binaryOperator = BinaryOperator.Add;
                return true;
            case AssignmentOperator.SubtractAssign:
                binaryOperator = BinaryOperator.Subtract;
                return true;
            case AssignmentOperator.MultiplyAssign:
                binaryOperator = BinaryOperator.Multiply;
                return true;
            case AssignmentOperator.DivideAssign:
                binaryOperator = BinaryOperator.Divide;
                return true;
            default:
                binaryOperator = default;
                return false;
        }
    }

    private bool IsDelegateLikeAssignmentType(TypeInfo type)
    {
        var resolved = ResolveTypeAlias(type);
        return resolved switch
        {
            FunctionTypeInfo => true,
            GenericTypeInfo { Name: "Func" or "Action" } => true,
            ReflectionTypeInfo reflection => IsDelegateType(reflection.Type) || IsRuntimeDelegateType(reflection.Type),
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

        var (line, column, length) = GetExpressionDiagnosticSpan(assignment.Target);
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
        var resolved = ResolveTypeAlias(type);
        return BuiltInTypes.IsUnknown(resolved)
            || resolved is GenericTypeInfo
            || resolved is NullableTypeInfo
            || IsReferenceType(resolved)
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
                var (line, column, length) = GetExpressionDiagnosticSpan(on.Target);
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

        var addMethod = eventInfo.Event.GetAddMethod(nonPublic: true);
        var removeMethod = eventInfo.Event.GetRemoveMethod(nonPublic: true);
        var handlerDelegateType = eventInfo.Event.EventHandlerType;

        // Prove the event is actually subscribable now, with a clear diagnostic, rather than
        // letting the IL backend throw on a missing accessor or value-type receiver.
        if (addMethod == null || removeMethod == null || handlerDelegateType == null)
        {
            var (line, column, length) = GetExpressionDiagnosticSpan(on.Target);
            Error(
                ErrorCode.InvalidEventSubscription,
                $"'{eventInfo.Event.Name}' can't be subscribed to — it has no accessible add/remove accessors",
                line,
                column,
                "This usually means the event is compiler-generated or inaccessible from N#.",
                length);
            AnalyzeLambda(on.Handler, reportInferenceFailure: false);
            return subscriptionType;
        }

        if (!addMethod.IsStatic && (eventInfo.Event.DeclaringType?.IsValueType ?? false))
        {
            var (line, column, length) = GetExpressionDiagnosticSpan(on.Target);
            Error(
                ErrorCode.InvalidEventSubscription,
                $"subscribing to '{eventInfo.Event.Name}' isn't supported — it's an instance event on a value type (struct)",
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

        var (line, column, length) = GetExpressionDiagnosticSpan(off.Handle);
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
        var (line, column, length) = GetExpressionDiagnosticSpan(assignment.Target);
        var target = RenderEventTarget(assignment.Target);
        var name = eventTarget.Event.Name;

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
        var (line, column, length) = GetExpressionDiagnosticSpan(expr);
        var target = RenderEventTarget(expr);
        Error(
            ErrorCode.EventRequiresOnOff,
            $"'{eventRef.Event.Name}' is a .NET event and can only be used with `on`/`off`",
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
        var path = TryGetStableNullPath(target);
        if (path == null)
            return;

        InvalidateNullFactsForAssignment(path);

        var valueState = GetExpressionNullState(value, valueType);
        if (valueState == NullState.Unknown)
            valueState = GetDefaultNullState(targetType);

        SetNullStateInCurrentScope(path, valueState);
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

        var opText = GetAssignmentOperatorText(assignment.Operator);
        var (line, column, length) = GetExpressionDiagnosticSpan(assignment.Target);
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

        var (line, column, length) = GetExpressionDiagnosticSpan(nullConditionalTarget);
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
        var (line, column, length) = GetAssignmentTargetNameDiagnosticSpan(target, target.Line, target.Column);
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
                if (!IsCurrentTypeMemberReference(identifier.Name))
                    break;

                var currentType = GetCurrentTypeScope();
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

                receiverType = ResolveTypeAlias(receiverType);
                if (receiverType is ByRefTypeInfo byRefReceiver)
                    receiverType = ResolveTypeAlias(byRefReceiver.InnerType);

                if (receiverType is NullableTypeInfo && memberAccess.MemberName is "HasValue" or "Value")
                {
                    propertyName = memberAccess.MemberName;
                    return true;
                }

                receiverType = NormalizeMemberOwnerType(GetNonNullableType(receiverType));
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

    private bool IsCurrentTypeMemberReference(string name)
    {
        foreach (var scope in _scopes)
        {
            if (scope.Symbols.ContainsKey(name))
            {
                return scope.Kind is not (ScopeKind.Function or ScopeKind.Block);
            }

            if (scope.Kind is not (ScopeKind.Function or ScopeKind.Block))
            {
                return GetCurrentTypeScope() != null;
            }
        }

        return GetCurrentTypeScope() != null;
    }

    private bool TryIsReadOnlyPropertyMember(TypeInfo owner, string memberName, bool includeStaticMembers)
    {
        owner = ResolveTypeAlias(owner);
        if (owner is ByRefTypeInfo byRefOwner)
            owner = ResolveTypeAlias(byRefOwner.InnerType);

        if (owner is NullableTypeInfo && memberName is "HasValue" or "Value")
        {
            return true;
        }

        if (owner is SoaRecordTypeInfo or SoaRowTypeInfo)
        {
            return false;
        }

        var members = owner switch
        {
            ClassTypeInfo classType => classType.Declaration.Members,
            StructTypeInfo structType => structType.Declaration.Members,
            RecordTypeInfo recordType => recordType.Declaration.Members,
            InterfaceTypeInfo interfaceType => interfaceType.Declaration.Members,
            _ => null,
        };

        if (members != null)
        {
            foreach (var member in members)
            {
                if (GetDeclarationName(member) != memberName)
                {
                    continue;
                }

                return member is PropertyDeclaration property
                    && (property.SetBody == null || property.PropertyModifier.HasFlag(PropertyModifier.Readonly));
            }

            if (owner is ClassTypeInfo { Declaration.BaseClass: not null } classTypeWithBase)
            {
                var baseType = ResolveType(classTypeWithBase.Declaration.BaseClass);
                return !BuiltInTypes.IsUnknown(baseType)
                    && TryIsReadOnlyPropertyMember(baseType, memberName, includeStaticMembers);
            }

            return false;
        }

        owner = NormalizeMemberOwnerType(owner);
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

        try
        {
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
        }
        catch (NotSupportedException)
        {
            return false;
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

        if (ResolveTypeAlias(GetNonNullableType(receiverType)) is not SoaRecordTypeInfo soaRecordType)
            return false;

        var isColumn = TryGetSoaColumn(soaRecordType.Declaration, member.MemberName) != null;
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
        var column = GetMemberNameColumn(memberAccess);
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
        var (line, column, length) = GetExpressionDiagnosticSpan(expression);
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
        var column = GetMemberNameColumn(memberAccess);
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
        var resolvedType = ResolveTypeAlias(type);
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
                if (LookupSymbol(identifier.Name) != null)
                    return false;
                if (LookupType(identifier.Name) is { } localType)
                    return IsSystemArrayTypeInfo(ResolveTypeAlias(localType));
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
                if (LookupSymbol(system.Name) != null)
                    return false;
                if (LookupType(system.Name) != null)
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
        var resolved = ResolveTypeAlias(type);
        return TryConvertTypeInfoToClrType(resolved) == typeof(Array)
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
                    && TryGetSoaColumn(soaRecordType.Declaration, memberAccess.MemberName) != null:
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
                var resolvedType = ResolveTypeAlias(GetNonNullableType(LookupSymbol(identifier.Name) ?? BuiltInTypes.Unknown));
                if (resolvedType is ByRefTypeInfo byRefReceiver)
                    resolvedType = ResolveTypeAlias(GetNonNullableType(byRefReceiver.InnerType));
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

        var resolvedReceiverType = ResolveTypeAlias(GetNonNullableType(receiverType));
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
        var (line, column, length) = GetExpressionDiagnosticSpan(indexAccess);
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
        var (line, column, length) = GetExpressionDiagnosticSpan(indexAccess);
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
        var column = GetMemberNameColumn(member);
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
        var typeName = ResolveTypeAlias(offenderType ?? BuiltInTypes.Unknown).ToString() ?? "value";
        var (line, column, length) = GetExpressionDiagnosticSpan(offender);
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
            || !IsProvenValueTypeReceiver(ResolveTypeAlias(receiverType)))
            return null;
        switch (receiver)
        {
            case IdentifierExpression:
            case ThisExpression:
            case BaseExpression:
                return null; // a local / parameter / bare field / `this` — a real variable.
            case IndexAccessExpression arrayElement
                when expressionTypes.TryGetValue(arrayElement.Object, out var indexedType)
                     && ResolveTypeAlias(indexedType) is ArrayTypeInfo:
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
        RecordTypeInfo record => record.Declaration.IsStruct,
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
        var owner = ResolveTypeAlias(ownerType);
        if (owner is GenericTypeInfo generic)
            owner = LookupType(generic.Name) ?? owner;
        if (owner is SimpleTypeInfo or GenericTypeInfo or ArrayTypeInfo)
        {
            var clrOwner = TryConvertTypeInfoToClrType(owner);
            if (clrOwner != null)
                owner = new ReflectionTypeInfo(clrOwner);
        }
        return ClassifyInstanceFieldMember(owner, hop.MemberName);
    }

    private bool? ClassifyInstanceFieldMember(TypeInfo owner, string memberName)
    {
        List<Declaration>? members = owner switch
        {
            StructTypeInfo s => s.Declaration.Members,
            ClassTypeInfo c => c.Declaration.Members,
            RecordTypeInfo r => r.Declaration.Members,
            _ => null,
        };
        if (members != null)
        {
            foreach (var declaredMember in members)
            {
                if (GetDeclarationName(declaredMember) != memberName)
                    continue;

                return declaredMember is FieldDeclaration;
            }

            if (owner is ClassTypeInfo { Declaration.BaseClass: not null } classTypeWithBase)
            {
                var baseType = ResolveType(classTypeWithBase.Declaration.BaseClass);
                return BuiltInTypes.IsUnknown(baseType)
                    ? null
                    : ClassifyInstanceFieldMember(baseType, memberName);
            }

            return false;
        }

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

        try
        {
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
        }
        catch (NotSupportedException)
        {
            return null; // an emitted instantiation — unresolvable here.
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
            var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetAssignmentTargetNameDiagnosticSpan(target, line, column);
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

        var (instanceLine, instanceColumn, instanceLength) = GetAssignmentTargetNameDiagnosticSpan(target, line, column);
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

        var (line, column, length) = GetAssignmentTargetNameDiagnosticSpan(target, target.Line, target.Column);
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

        var opText = GetUnaryOperatorSymbol(unary.Operator) ?? "operator";
        var (line, column, length) = GetAssignmentTargetNameDiagnosticSpan(unary.Operand, unary.Line, unary.Column);
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

    private readonly record struct ReadonlyFieldTarget(string Name, bool IsStatic, bool IsCurrentInstance);

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

        if (_currentClass.BaseClass == null)
        {
            return false;
        }

        var baseType = ResolveType(_currentClass.BaseClass);
        if (!TryFindReadonlyInstanceField(baseType, fieldName, out var inheritedFieldName))
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

        var owner = NormalizeMemberOwnerType(ownerType);
        if (TryFindReadonlyStaticField(owner, target.MemberName, out var fieldName))
        {
            readonlyTarget = new ReadonlyFieldTarget(fieldName, IsStatic: true, IsCurrentInstance: false);
            return true;
        }

        return false;
    }

    private bool TryFindReadonlyStaticField(TypeInfo owner, string fieldName, out string resolvedFieldName)
    {
        resolvedFieldName = string.Empty;
        List<Declaration>? members = owner switch
        {
            ClassTypeInfo classType => classType.Declaration.Members,
            StructTypeInfo structType => structType.Declaration.Members,
            RecordTypeInfo recordType => recordType.Declaration.Members,
            _ => null,
        };

        if (members != null)
        {
            foreach (var member in members)
            {
                if (GetDeclarationName(member) != fieldName)
                {
                    continue;
                }

                if (member is FieldDeclaration field
                    && field.Modifiers.HasFlag(Modifiers.Static)
                    && field.Modifiers.HasFlag(Modifiers.Readonly))
                {
                    resolvedFieldName = field.Name;
                    return true;
                }

                return false;
            }
        }

        if (owner is ClassTypeInfo { Declaration.BaseClass: not null } classTypeWithBase)
        {
            var baseType = ResolveType(classTypeWithBase.Declaration.BaseClass);
            if (TryFindReadonlyStaticField(baseType, fieldName, out resolvedFieldName))
            {
                return true;
            }
        }

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

        try
        {
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
        }
        catch (NotSupportedException)
        {
            return false;
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

        var receiver = ResolveTypeAlias(GetNonNullableType(receiverType));
        if (receiver is ByRefTypeInfo byRefReceiver)
            receiver = ResolveTypeAlias(GetNonNullableType(byRefReceiver.InnerType));
        receiver = NormalizeMemberOwnerType(receiver);

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
        List<Declaration>? members = receiver switch
        {
            ClassTypeInfo classType => classType.Declaration.Members,
            StructTypeInfo structType => structType.Declaration.Members,
            RecordTypeInfo recordType => recordType.Declaration.Members,
            _ => null,
        };

        if (members != null)
        {
            foreach (var member in members)
            {
                if (GetDeclarationName(member) != fieldName)
                {
                    continue;
                }

                if (member is FieldDeclaration field
                    && !field.Modifiers.HasFlag(Modifiers.Static)
                    && field.Modifiers.HasFlag(Modifiers.Readonly))
                {
                    resolvedFieldName = field.Name;
                    return true;
                }

                return false;
            }
        }

        if (receiver is ClassTypeInfo { Declaration.BaseClass: not null } classTypeWithBase)
        {
            var baseType = ResolveType(classTypeWithBase.Declaration.BaseClass);
            if (TryFindReadonlyInstanceField(baseType, fieldName, out resolvedFieldName))
            {
                return true;
            }
        }

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

        try
        {
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
        }
        catch (NotSupportedException)
        {
            return false;
        }

        return false;
    }

    private TypeInfo NormalizeMemberOwnerType(TypeInfo owner)
    {
        owner = ResolveTypeAlias(owner);
        if (owner is GenericTypeInfo generic)
            owner = LookupType(generic.Name) ?? owner;
        if (owner is SimpleTypeInfo or GenericTypeInfo or ArrayTypeInfo)
        {
            var clrOwner = TryConvertTypeInfoToClrType(owner);
            if (clrOwner != null)
                owner = new ReflectionTypeInfo(clrOwner);
        }

        return owner;
    }

    private (int Line, int Column, int Length) GetAssignmentTargetNameDiagnosticSpan(Expression target, int fallbackLine, int fallbackColumn)
    {
        return target switch
        {
            IdentifierExpression identifier => (identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length)),
            MemberAccessExpression memberAccess => (memberAccess.Line, GetMemberNameColumn(memberAccess), Math.Max(1, memberAccess.MemberName.Length)),
            ParenthesizedExpression parenthesized => GetAssignmentTargetNameDiagnosticSpan(parenthesized.Inner, fallbackLine, fallbackColumn),
            _ => (fallbackLine, fallbackColumn, GetTokenLength(fallbackLine, fallbackColumn))
        };
    }

    private FunctionTypeInfo AnalyzeLambda(
        LambdaExpression lambda,
        TypeInfo? expectedType = null,
        bool reportInferenceFailure = true,
        bool isExpressionTreeTarget = false)
    {
        var expectedSignature = GetFunctionSignature(expectedType);
        var targetsExpressionTree = isExpressionTreeTarget || IsExpressionTreeLambdaTarget(expectedType);
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
                ? ResolveType(param.Type!)
                : hasInferenceSource
                    ? expectedSignature!.ParameterTypes![paramIndex]
                    : BuiltInTypes.Unknown;
            var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, lambda.Line, lambda.Column);

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

        return new FunctionTypeInfo(null)
        {
            ParameterTypes = parameterTypes,
            ReturnType = returnType
        };
    }

    private bool IsExpressionTreeLambdaTarget(TypeInfo? expectedType)
    {
        if (expectedType == null)
            return false;

        var resolvedExpectedType = ResolveTypeAlias(expectedType);
        if (resolvedExpectedType is ReflectionTypeInfo reflectionType)
            return IsExpressionTreeLambdaTarget(reflectionType.Type);

        var clrType = TryConvertTypeInfoToClrType(resolvedExpectedType);
        return clrType != null && IsExpressionTreeLambdaTarget(clrType);
    }

    private static bool IsExpressionTreeLambdaTarget(Type type)
        => TryGetExpressionTreeDelegateType(type, out _);

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
            GetTokenLength(lambda.Line, lambda.Column));
    }

    private bool ReportUnsupportedExpressionTreeExpressionIfNeeded(Expression expression, ISet<string> parameterNames)
    {
        if (FindUnsupportedExpressionTreeExpression(expression, parameterNames) is not { } unsupported)
        {
            return false;
        }

        var (line, column, length) = GetExpressionDiagnosticSpan(unsupported.Expression);
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
                if (!IsSupportedExpressionTreeBinaryOperator(binary.Operator))
                {
                    return (binary, $"binary operator '{GetBinaryOperatorText(binary.Operator)}'");
                }

                return FindUnsupportedExpressionTreeExpression(binary.Left, parameterNames)
                    ?? FindUnsupportedExpressionTreeExpression(binary.Right, parameterNames);

            case UnaryExpression unary:
                if (!IsSupportedExpressionTreeUnaryOperator(unary.Operator))
                {
                    return (unary, $"unary operator '{GetUnaryOperatorText(unary.Operator)}'");
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

        if (TryResolveBuiltInTypeKeyword(name) != null)
        {
            return true;
        }

        var resolvedType = ResolveTypeAlias(LookupType(name) ?? BuiltInTypes.Unknown);
        if (!BuiltInTypes.IsUnknown(resolvedType))
        {
            return true;
        }

        return TryResolveExternalType(name) is ReflectionTypeInfo;
    }

    private bool ExpressionTreeReceiverStartsWithValueIdentifier(Expression expression, ISet<string> parameterNames)
    {
        return expression switch
        {
            IdentifierExpression identifier => parameterNames.Contains(identifier.Name)
                || LookupSymbol(identifier.Name) != null,
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

    private static bool IsSupportedExpressionTreeBinaryOperator(BinaryOperator op)
        => op is BinaryOperator.Add
            or BinaryOperator.Subtract
            or BinaryOperator.Multiply
            or BinaryOperator.Divide
            or BinaryOperator.Modulo
            or BinaryOperator.Equal
            or BinaryOperator.NotEqual
            or BinaryOperator.Less
            or BinaryOperator.LessOrEqual
            or BinaryOperator.Greater
            or BinaryOperator.GreaterOrEqual
            or BinaryOperator.And
            or BinaryOperator.Or
            or BinaryOperator.BitwiseAnd
            or BinaryOperator.BitwiseOr
            or BinaryOperator.BitwiseXor
            or BinaryOperator.LeftShift
            or BinaryOperator.RightShift;

    private static bool IsSupportedExpressionTreeUnaryOperator(UnaryOperator op)
        => op is UnaryOperator.Not
            or UnaryOperator.Negate;

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

        var resolvedExpectedType = ResolveTypeAlias(expectedType);

        if (resolvedExpectedType is FunctionTypeInfo functionType)
            return functionType;

        if (resolvedExpectedType is ReflectionTypeInfo reflectionType
            && (IsDelegateType(reflectionType.Type) || IsExpressionTreeLambdaTarget(reflectionType.Type)))
        {
            return CreateFunctionTypeInfoFromDelegate(reflectionType.Type);
        }

        // Handle generic delegate types (Func<int, int>, Action<string>) from N# declarations
        if (resolvedExpectedType is GenericTypeInfo)
        {
            var clrType = TryConvertTypeInfoToClrType(resolvedExpectedType);
            if (clrType != null && (IsDelegateType(clrType) || IsExpressionTreeLambdaTarget(clrType)))
                return CreateFunctionTypeInfoFromDelegate(clrType);
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
        var elements = new List<(string? Name, TypeInfo Type)>(tuple.Elements.Count);

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
            elements.Add((element.Name, elementType));
        }

        return new TupleTypeInfo(elements);
    }

    private TypeInfo? GetExpectedTupleElementType(TupleExpression tuple, int elementIndex)
    {
        if (_currentExpectedType == null)
        {
            return null;
        }

        if (ResolveTypeAlias(_currentExpectedType) is not TupleTypeInfo expectedTuple
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

        var resolvedExpectedType = ResolveTypeAlias(expectedType);
        if (IsCollectionType(resolvedExpectedType, out var collectionElementType))
        {
            return (collectionElementType, "collection");
        }

        return resolvedExpectedType switch
        {
            ArrayTypeInfo arrayType => (arrayType.ElementType, "array"),
            ReflectionTypeInfo reflectionType when reflectionType.Type.IsArray && reflectionType.Type.GetElementType() != null
                => (ConvertReflectionType(reflectionType.Type.GetElementType()!), "array"),
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
                if (!IsAssignable(expectedElementType, elemType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(elem);
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
            if (!IsAssignable(firstType, elemType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(elem);
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

        var resolvedExpectedType = ResolveTypeAlias(expectedType);
        if (!IsUnsupportedCollectionExpressionTarget(resolvedExpectedType, out var targetName))
        {
            return;
        }

        var (line, column, length) = GetExpressionDiagnosticSpan(array);
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
        try
        {
            interfaces = type.GetInterfaces();
        }
        catch (NotSupportedException)
        {
            yield break;
        }

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
        try
        {
            return targetType
                .GetConstructors(BindingFlags.Public | BindingFlags.Instance)
                .Any(predicate);
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static bool HasSingleEnumerableParameter(MethodBase method, Type elementType)
    {
        try
        {
            var parameters = method.GetParameters();
            if (parameters.Length != 1)
            {
                return false;
            }

            var parameterType = parameters[0].ParameterType;
            return IsGenericDefinition(parameterType, typeof(IEnumerable<>))
                && IsReflectionAssignableFrom(parameterType, typeof(IEnumerable<>).MakeGenericType(elementType));
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException)
        {
            return false;
        }
    }

    private static bool HasCollectionExpressionMutator(Type targetType, Type elementType)
    {
        try
        {
            return targetType
                .GetMethods(BindingFlags.Public | BindingFlags.Instance)
                .Any(method => method.Name is "Add" or "Enqueue"
                    && HasSingleCollectionElementParameter(method, elementType));
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static bool HasSingleCollectionElementParameter(MethodBase method, Type elementType)
    {
        try
        {
            var parameters = method.GetParameters();
            if (parameters.Length != 1)
            {
                return false;
            }

            var parameterType = parameters[0].ParameterType;
            if (elementType.IsValueType)
            {
                return HaveSameReflectionTypeIdentity(parameterType, elementType);
            }

            return IsReflectionAssignableFrom(parameterType, elementType);
        }
        catch (NotSupportedException)
        {
            return false;
        }
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

        try
        {
            return type.GetGenericTypeDefinition().FullName;
        }
        catch (NotSupportedException)
        {
            return type.FullName;
        }
    }

    private static bool IsAssignableFromConstructed(Type targetType, Type openGenericType, Type elementType)
    {
        try
        {
            return targetType.IsAssignableFrom(openGenericType.MakeGenericType(elementType));
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException)
        {
            return false;
        }
    }

    private TypeInfo AnalyzeNewExpression(NewExpression newExpr)
    {
        TypeInfo type;

        // Set when this is a union case construction (new Result.Success<int> { ... }) —
        // initializer members then live on the case, not the union type itself.
        string? unionCaseConstructionName = null;

        // Target-typed new (C# 9): new() or new { ... }
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
            type = ResolveDeclaredType(newExpr.Type);

            // A locally-declared GENERIC type constructed without type arguments previously
            // emitted an open-type token (BadImageFormatException at runtime). N# does not
            // infer class type arguments from constructor arguments (the C# rule) — they
            // must be explicit.
            if (newExpr.Type is SimpleTypeReference bareTypeReference
                && !bareTypeReference.Name.Contains('.')
                && GetGenericHeadArity(type) > 0)
            {
                var requiredCount = GetGenericHeadArity(type);
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
                if (parts.Length == 2
                    && LookupType(parts[0]) is UnionTypeInfo { IsAnonymous: false } unionBaseType)
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
                        var caseNames = unionBaseType.Declaration!.Cases.Select(unionCase => unionCase.Name).ToList();
                        var similarCases = caseNames.Count > 0
                            ? new SmartSuggester(caseNames).SuggestSimilarNames(parts[1])
                            : new List<string>();
                        var caseSpan = GetTypeReferenceStartSpan(newExpr.Type!);
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

        var soaConstructionType = ResolveTypeAlias(GetNonNullableType(type)) as SoaRecordTypeInfo;
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
            else if (lengthType != BuiltInTypes.Int)
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
            var (line, column, length) = GetExpressionDiagnosticSpan(capacityArgument.Value);
            Error(
                ErrorCode.NoMatchingOverload,
                $"SoA table '{soaRecordType.Declaration.Name}' construction has no parameter named '{argumentName}'",
                line,
                column,
                $"Use '{expectedShape}', or rename the argument to 'capacity'.",
                length);
            return;
        }

        var capacityType = ResolveTypeAlias(constructorArgumentTypes[0]);
        if (capacityType is SoaRowTypeInfo || BuiltInTypes.IsUnknown(capacityType))
            return;

        if (!IsAssignable(BuiltInTypes.Int, capacityType))
        {
            var (line, column, length) = GetExpressionDiagnosticSpan(capacityArgument.Value);
            Error(
                ErrorCode.TypeMismatch,
                $"SoA table capacity must be int, but this argument has type '{capacityType}'",
                line,
                column,
                $"Use '{expectedShape}' with an int capacity.",
                length);
            return;
        }

        if (IsConstantNegative(capacityArgument.Value))
        {
            var (line, column, length) = GetExpressionDiagnosticSpan(capacityArgument.Value);
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
            if (expectedElementType != null && !IsAssignable(expectedElementType, initializerValueType))
            {
                var targetKind = expectedElement?.TargetKind ?? "array";
                var elementLabel = targetKind == "collection" ? "Collection initializer element" : "Array initializer element";
                var (initializerDiagnosticLine, initializerDiagnosticColumn, initializerDiagnosticLength) =
                    GetExpressionDiagnosticSpan(prop.Value);
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

        if (IsAssignable(memberType, valueType))
        {
            return;
        }

        var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(prop.Value);
        var sourceSnippet = _sourceLines != null && diagnosticLine > 0 && diagnosticLine <= _sourceLines.Length
            ? _sourceLines[diagnosticLine - 1]
            : null;

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

            memberType = ResolveTypeWithSubstitution(caseProperty.Type, unionSubstitution);
            return !BuiltInTypes.IsUnknown(memberType);
        }

        // Closed generic instantiation of a declared type (new Box<Pt> { Item: ... }):
        // resolve the member's declared type reference under the type-argument
        // substitution (Item: T on Box<Pt> expects Pt).
        if (constructedType is GenericTypeInfo generic)
        {
            if (LookupType(generic.Name) is not { } openType
                || !TryGetDeclaredTypeShape(openType, out var typeParameters, out var members, out var primaryParameters))
            {
                return false;
            }

            Dictionary<string, TypeInfo>? substitution = null;
            if (typeParameters is { Count: > 0 })
            {
                if (typeParameters.Count != generic.TypeArguments.Count)
                {
                    return false;
                }

                substitution = new Dictionary<string, TypeInfo>(StringComparer.Ordinal);
                for (var i = 0; i < typeParameters.Count; i++)
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
                var hasBaseClass = openType is ClassTypeInfo { Declaration.BaseClass: not null };
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
                        typeNameOverride: NullabilityMetadata.FormatTypeInfo(generic));
                }

                return false;
            }

            memberType = ResolveTypeWithSubstitution(memberTypeReference, substitution);
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
            || resolved is FunctionTypeInfo { Declaration: not null })
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
        if (ResolveTypeAlias(GetNonNullableType(targetType)) is not SoaRecordTypeInfo)
        {
            return false;
        }

        if (property.Name != null && property.IndexExpression == null)
        {
            return false;
        }

        var diagnosticTarget = property.IndexExpression ?? property.Value;
        var (line, column, length) = GetExpressionDiagnosticSpan(diagnosticTarget);
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
        if (ResolveTypeAlias(GetNonNullableType(constructedType)) is not SoaRecordTypeInfo soaRecordType)
        {
            return false;
        }

        var isColumn = TryGetSoaColumn(soaRecordType.Declaration, memberName) != null;
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
    /// Extracts the declaration shape (type parameters, members, primary constructor
    /// parameters) from a declared class/struct/record type info.
    /// </summary>
    private static bool TryGetDeclaredTypeShape(
        TypeInfo type,
        out List<TypeParameter>? typeParameters,
        out List<Declaration> members,
        out List<Parameter>? primaryConstructorParameters)
    {
        switch (type)
        {
            case ClassTypeInfo classInfo:
                typeParameters = classInfo.Declaration.TypeParameters;
                members = classInfo.Declaration.Members;
                primaryConstructorParameters = classInfo.Declaration.PrimaryConstructorParameters;
                return true;
            case StructTypeInfo structInfo:
                typeParameters = structInfo.Declaration.TypeParameters;
                members = structInfo.Declaration.Members;
                primaryConstructorParameters = structInfo.Declaration.PrimaryConstructorParameters;
                return true;
            case RecordTypeInfo recordInfo:
                typeParameters = recordInfo.Declaration.TypeParameters;
                members = recordInfo.Declaration.Members;
                primaryConstructorParameters = recordInfo.Declaration.PrimaryConstructorParameters;
                return true;
            default:
                typeParameters = null;
                members = null!;
                primaryConstructorParameters = null;
                return false;
        }
    }

    /// <summary>
    /// Finds the declared type reference of a field, property, or primary-constructor
    /// parameter by name on a type declaration's own members (no base walk — base
    /// members of a generic declaration would need their own substitution chain).
    /// </summary>
    private static TypeReference? FindDeclaredMemberTypeReference(
        List<Declaration> members,
        List<Parameter>? primaryConstructorParameters,
        string memberName)
    {
        foreach (var member in members)
        {
            if (member is FieldDeclaration field && field.Name == memberName)
            {
                return field.Type;
            }

            if (member is PropertyDeclaration property && property.Name == memberName)
            {
                return property.Type;
            }
        }

        return primaryConstructorParameters?.FirstOrDefault(parameter => parameter.Name == memberName)?.Type;
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
        else if (IsConstantNegative(stackAlloc.LengthExpression))
        {
            Error(ErrorCode.TypeMismatch,
                "stackalloc length must not be negative",
                stackAlloc.LengthExpression.Line,
                stackAlloc.LengthExpression.Column,
                "Use a length of zero or more.");
        }

        return new GenericTypeInfo("Span", new List<TypeInfo> { ResolveType(stackAlloc.ElementType) });
    }

    /// <summary>
    /// A stackalloc length must implicitly widen to int (matching C#'s element-count rule):
    /// int itself plus the smaller integer types. long/uint/ulong, floating point, and
    /// non-numeric types require an explicit conversion.
    /// </summary>
    private bool IsImplicitlyIntStackAllocLength(TypeInfo type)
    {
        type = ResolveTypeAlias(type);
        return type == BuiltInTypes.Int
               || type == BuiltInTypes.Short
               || type == BuiltInTypes.SByte
               || type == BuiltInTypes.Byte
               || type == BuiltInTypes.UShort
               || type == BuiltInTypes.Char;
    }

    private bool IsConstantNegative(Expression expression)
    {
        while (true)
        {
            expression = UnwrapTransparentExpressionWrappers(expression);
            if (expression is CastExpression cast && IsSignedIntegerCast(cast.TargetType))
            {
                expression = cast.Expression;
                continue;
            }

            break;
        }

        return expression is UnaryExpression
        {
            Operator: UnaryOperator.Negate,
            Operand: var operand
        }
            && TryGetUnsignedIntegerMagnitude(operand, out var magnitude)
            && magnitude != 0;
    }

    private bool TryGetUnsignedIntegerMagnitude(Expression expression, out ulong magnitude)
    {
        while (true)
        {
            expression = UnwrapTransparentExpressionWrappers(expression);
            if (expression is CastExpression cast && IsSignedIntegerCast(cast.TargetType))
            {
                expression = cast.Expression;
                continue;
            }

            break;
        }

        if (expression is IntLiteralExpression literal
            && NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(literal.Value, out magnitude))
        {
            return true;
        }

        magnitude = 0;
        return false;
    }

    private bool IsSignedIntegerCast(TypeReference type)
    {
        if (type is not SimpleTypeReference simple)
            return false;

        if (simple.Name is "int" or "short" or "sbyte")
            return true;

        var resolved = ResolveTypeAlias(LookupType(simple.Name) ?? BuiltInTypes.Unknown);
        return resolved == BuiltInTypes.Int
               || resolved == BuiltInTypes.Short
               || resolved == BuiltInTypes.SByte;
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
        var typeParameters = unionType.Declaration!.TypeParameters;
        var arity = typeParameters?.Count ?? 0;
        var typeRefSpan = GetTypeReferenceStartSpan(newExpr.Type!);

        if (typeArguments is { Count: > 0 })
        {
            var resolvedArguments = typeArguments.Select(ResolveType).ToList();
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

            return new GenericTypeInfo(unionName, resolvedArguments);
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

        if (valueType is UnionTypeInfo { IsAnonymous: false } direct)
        {
            unionType = direct;
            return true;
        }

        if (valueType is GenericTypeInfo generic
            && LookupType(generic.Name) is UnionTypeInfo { IsAnonymous: false } declared
            && declared.Declaration!.TypeParameters is { Count: > 0 } typeParameters
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
    private TypeInfo ResolveTypeWithSubstitution(TypeReference type, Dictionary<string, TypeInfo>? substitution)
    {
        if (substitution == null)
        {
            return ResolveType(type);
        }

        return type switch
        {
            SimpleTypeReference simple when substitution.TryGetValue(simple.Name, out var bound) => bound,
            GenericTypeReference generic => new GenericTypeInfo(
                generic.Name,
                generic.TypeArguments.Select(argument => ResolveTypeWithSubstitution(argument, substitution)).ToList()),
            ArrayTypeReference array => new ArrayTypeInfo(ResolveTypeWithSubstitution(array.ElementType, substitution)),
            NullableTypeReference nullable => new NullableTypeInfo(ResolveTypeWithSubstitution(nullable.InnerType, substitution)),
            _ => ResolveType(type)
        };
    }

    private TypeInfo AnalyzeIsExpression(IsExpression isExpr)
    {
        var sourceType = AnalyzeExpression(isExpr.Expression);
        var targetType = ResolveType(isExpr.Type);
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
                GetIsExpressionDiagnosticSpan(isExpr);
            Error(ErrorCode.ImpossiblePattern,
                $"This 'is {targetType}' check is always false — a '{sourceType}' is never a '{targetType}'",
                impossibleLine, impossibleColumn, length: impossibleLength);
        }

        return BuiltInTypes.Bool;
    }

    private TypeInfo AnalyzeCastExpression(CastExpression cast)
    {
        var targetType = ResolveType(cast.TargetType);
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
            var (line, column, length) = GetExpressionDiagnosticSpan(await.Expression);
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

        if (TryGetTaskLikeResultType(resolved, out resultType))
        {
            return true;
        }

        if (IsUnitTaskLikeType(resolved))
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

        try
        {
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
                : ConvertReflectionType(getResultMethod.ReturnType);
            return true;
        }
        catch (NotSupportedException)
        {
            return false;
        }
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
        ResolveType(typeofExpr.Type);
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
            var (line, column, length) = GetExpressionDiagnosticSpan(nameofExpr.Target);
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
        ResolveType(sizeofExpr.Type);
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
            if (memberType != null && !valueIsSoaRow && !valueIsSoaDirectColumn && !IsAssignable(memberType, valueType))
            {
                var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(property.Value);
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
                if (!isSoaRowGuard && !isSoaDirectColumnGuard && !IsAssignable(BuiltInTypes.Bool, guardType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(matchCase.Guard);
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
            else if (!IsAssignable(resultType, caseType) && !IsAssignable(caseType, resultType))
            {
                // Try to find a common base type (especially for reflection types like IActionResult subtypes)
                var commonType = FindCommonBaseType(resultType, caseType);
                if (commonType != null)
                {
                    resultType = commonType;
                }
                else
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(matchCase.Expression);
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
        if (valueType is UnionTypeInfo { IsAnonymous: true } anonymousUnionType)
        {
            CheckAnonymousUnionMatchExhaustiveness(match, anonymousUnionType);
        }
        else if (valueType is UnionTypeInfo { IsAnonymous: false } unionType)
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

    private void CheckAnonymousUnionMatchExhaustiveness(MatchExpression match, UnionTypeInfo unionType)
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
                    var patternType = ResolveType(typePattern.Type);
                    for (var i = 0; i < unionType.Arms.Count; i++)
                    {
                        if (IsAssignable(patternType, unionType.Arms[i]))
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
        if (unionType.IsAnonymous)
        {
            CheckAnonymousUnionMatchExhaustiveness(match, unionType);
            return;
        }

        var unionDeclaration = unionType.Declaration!;
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

                if (IsUnionCaseCoveredByPatterns(unionDeclaration.Name, unionCase, patterns, substitution, out var hints))
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
                    var sourceSnippet = _sourceLines != null && match.Line > 0 && match.Line <= _sourceLines.Length
                        ? _sourceLines[match.Line - 1]
                        : null;

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
            if (!pattern.Properties.Except(constrainedProperties).All(IsTotalPropertyPattern))
                continue;

            var caseProperty = unionCase.Properties?.FirstOrDefault(property => property.Name == constrainedProperty.Name);
            if (caseProperty == null)
                continue;

            // Apply the scrutinee's generic substitution so a `value: T` property on a
            // Result<Option<int>> scrutinee resolves to the nested union for coverage.
            var propertyType = ResolveTypeWithSubstitution(caseProperty.Type, substitution);
            if (!TryResolveDeclaredUnionType(propertyType, out var nestedUnionType, out _))
                continue;

            var nestedCaseName = GetMatchedUnionCaseName(nestedUnionType, constrainedProperty.Pattern!);

            if (nestedCaseName == null)
                continue;

            if (!nestedCoverage.TryGetValue(constrainedProperty.Name, out var coverage))
            {
                coverage = (
                    nestedUnionType.Declaration!.Name,
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
        if (unionType.IsAnonymous || unionType.Declaration is null)
            return false;

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
        if (unionType.IsAnonymous || unionType.Declaration is null)
            return false;

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
                    if (member.Value is StringLiteralExpression strLit &&
                        literalPattern.Literal is StringLiteralExpression patternStr &&
                        strLit.Value == patternStr.Value)
                    {
                        coveredMembers.Add(member.Name);
                    }
                    else if (member.Value is IntLiteralExpression intLit &&
                             literalPattern.Literal is IntLiteralExpression patternInt &&
                             intLit.Value == patternInt.Value)
                    {
                        coveredMembers.Add(member.Name);
                    }
                }
            }
        }

        // Check if all enum members are covered. The missing-member selection is owned by
        // the N# analyzer exhaustiveness kernel; do not recover with a C# duplicate.
        var missingMembers = AnalyzerExhaustivenessSelector.SelectMissingEnumMembers(
            enumType.Declaration.Members,
            coveredMembers);

        if (missingMembers.Count > 0)
        {
            var sourceSnippet = _sourceLines != null && match.Line > 0 && match.Line <= _sourceLines.Length
                ? _sourceLines[match.Line - 1]
                : null;

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
            match.IsExhaustive = true;
        }
    }

    // Type resolution
    /// <summary>
    /// Resolves a type reference at a declared-type position (parameter, return, field,
    /// property, variable annotation, type alias, or `new` expression) and reports NL201
    /// when a simple name resolves through no channel. Only these positions opt in:
    /// pass-1 signature collection and lazy cross-file member resolution run without
    /// generic type parameters in scope and must stay lenient to avoid false positives.
    /// </summary>
    private TypeInfo ResolveDeclaredType(TypeReference typeRef)
    {
        var previous = _reportUnresolvedTypes;
        _reportUnresolvedTypes = true;
        try
        {
            return ResolveType(typeRef);
        }
        finally
        {
            _reportUnresolvedTypes = previous;
        }
    }

    private TypeInfo ResolveType(TypeReference typeRef)
    {
        var resolved = typeRef switch
        {
            SimpleTypeReference simple => ResolveSimpleType(simple),
            GenericTypeReference generic => ResolveGenericType(generic),
            ArrayTypeReference array => new ArrayTypeInfo(ResolveType(array.ElementType)),
            NullableTypeReference nullable => new NullableTypeInfo(ResolveType(nullable.InnerType)),
            UnionTypeReference union => ResolveAnonymousUnionType(union),
            TupleTypeReference tuple => new TupleTypeInfo(
                tuple.Elements.Select(e => (e.Name, ResolveType(e.Type))).ToList()),
            FunctionTypeReference function => new FunctionTypeInfo(null)
            {
                ParameterTypes = function.ParameterTypes.Select(ResolveType).ToList(),
                ReturnType = ResolveType(function.ReturnType)
            },
            ByRefTypeReference byRef => new ByRefTypeInfo(ResolveType(byRef.InnerType)),
            _ => BuiltInTypes.Unknown
        };

        RecordResolvedTypeReference(typeRef, resolved);
        return resolved;
    }

    private TypeInfo ResolveSimpleType(SimpleTypeReference simple)
    {
        if (ReportSoaRowTypeReferenceIfNeeded(simple.Name, simple.Line, simple.Column))
        {
            return BuiltInTypes.Unknown;
        }

        return ResolveSimpleType(simple.Name, simple.Line, simple.Column);
    }

    private TypeInfo ResolveGenericType(GenericTypeReference generic)
    {
        if (generic.Line > 0)
        {
            if (ReportSoaRowTypeReferenceIfNeeded(generic.Name, generic.Line, generic.Column))
            {
                return BuiltInTypes.Unknown;
            }
        }

        var typeArguments = generic.TypeArguments.Select(ResolveType).ToList();

        if (generic.Line > 0)
        {
            // Resolve the open-generic name for binding/semantic-model side effects, but
            // suppress unresolved reporting here: CLR open generics carry an arity suffix
            // (List resolves as List`1), so the plain simple-name probe legitimately misses
            // external generic types.
            var previousReport = _reportUnresolvedTypes;
            _reportUnresolvedTypes = false;
            TypeInfo resolvedName;
            try
            {
                resolvedName = ResolveSimpleType(generic.Name, generic.Line, generic.Column);
            }
            finally
            {
                _reportUnresolvedTypes = previousReport;
            }

            var genericHeadArity = GetGenericHeadArity(resolvedName);
            Type? arityQualifiedExternalType = null;
            List<int>? knownGenericHeadArities = null;
            if (resolvedName is ExternalTypeInfo or ReflectionTypeInfo)
            {
                arityQualifiedExternalType = TryGetKnownOpenGenericType(generic.Name, generic.TypeArguments.Count);
                if (arityQualifiedExternalType == null
                    && TryResolveExternalType($"{generic.Name}`{generic.TypeArguments.Count}") is ReflectionTypeInfo arityQualifiedExternal)
                {
                    arityQualifiedExternalType = arityQualifiedExternal.Type;
                }

                if (arityQualifiedExternalType != null)
                {
                    genericHeadArity = generic.TypeArguments.Count;
                }
                else
                {
                    knownGenericHeadArities = GetKnownGenericHeadArities(generic.Name);
                    if (knownGenericHeadArities.Count == 1)
                    {
                        genericHeadArity = knownGenericHeadArities[0];
                    }
                }
            }

            // Report the generic name as unresolved only when it is not compiler-known
            // (Result, Task, Func, ...) and the arity-qualified external probe also misses
            // (e.g. `Lst<int>` instead of `List<int>`).
            if (previousReport &&
                resolvedName is ExternalTypeInfo &&
                !generic.Name.Contains('.') &&
                arityQualifiedExternalType == null &&
                (knownGenericHeadArities == null || knownGenericHeadArities.Count == 0) &&
                _reportedUnresolvedTypeRefs.Add((generic.Name, generic.Line, generic.Column)))
            {
                Error(
                    ErrorCode.TypeNotFound,
                    $"Type '{generic.Name}' not found",
                    generic.Line,
                    generic.Column,
                    BuildUnresolvedTypeSuggestion(generic.Name),
                    generic.Name.Length);
            }

            if (previousReport && knownGenericHeadArities is { Count: > 1 }
                && _reportedUnresolvedTypeRefs.Add((generic.Name, generic.Line, generic.Column)))
            {
                var arityList = string.Join(", ", knownGenericHeadArities);
                Error(
                    ErrorCode.InvalidTypeArgument,
                    $"Generic type '{generic.Name}' does not take {generic.TypeArguments.Count} type argument(s); available arities are {arityList}",
                    generic.Line,
                    generic.Column,
                    $"Use one of the supported type-argument counts for '{generic.Name}'.",
                    generic.Name.Length);
            }

            // Arity validation for locally-declared generic types: a wrong count previously
            // sailed through analysis and the emitter produced an unloadable assembly
            // (TypeLoadException at runtime). Reported at declared-type positions only, with
            // the same dedupe as NL201 (this resolver runs in both analysis passes).
            if (previousReport && genericHeadArity >= 0
                && genericHeadArity != generic.TypeArguments.Count
                && _reportedUnresolvedTypeRefs.Add((generic.Name, generic.Line, generic.Column)))
            {
                var message = genericHeadArity == 0
                    ? $"'{generic.Name}' is not generic, but {generic.TypeArguments.Count} type argument(s) were provided"
                    : $"Generic type '{generic.Name}' takes {genericHeadArity} type argument(s), but {generic.TypeArguments.Count} were provided";
                Error(
                    ErrorCode.InvalidTypeArgument,
                    message,
                    generic.Line,
                    generic.Column,
                    genericHeadArity == 0
                        ? $"Remove the type arguments: '{generic.Name}'"
                        : $"Match the declaration's type parameter count for '{generic.Name}'",
                    generic.Name.Length);
            }
        }

        return new GenericTypeInfo(generic.Name, typeArguments);
    }

    private bool ReportSoaRowTypeReferenceIfNeeded(string name, int line, int column)
    {
        const string rowSuffix = ".Row";
        if (!SoaFeature.IsEnabled || line <= 0 || !name.EndsWith(rowSuffix, StringComparison.Ordinal))
        {
            return false;
        }

        var tableName = name[..^rowSuffix.Length];
        if (tableName.Length == 0 || ResolveTypeAlias(LookupType(tableName) ?? BuiltInTypes.Unknown) is not SoaRecordTypeInfo)
        {
            return false;
        }

        if (_reportedSoaRowTypeRefs.Add((name, line, column)))
        {
            Error(
                ErrorCode.InvalidSyntax,
                $"SoA row type '{name}' is not part of this lowering",
                line,
                column,
                $"Pass the '{tableName}' table and an int row index instead; row views exist only as table[index].column projection syntax.",
                name.Length);
        }

        return true;
    }

    /// <summary>
    /// The generic-parameter count for a resolved type head, or -1 when the head is unresolved
    /// external text and arity cannot be validated locally.
    /// </summary>
    private static int GetGenericHeadArity(TypeInfo resolvedName)
        => resolvedName switch
        {
            SimpleTypeInfo => 0,
            ClassTypeInfo classInfo => classInfo.Declaration.TypeParameters?.Count ?? 0,
            StructTypeInfo structInfo => structInfo.Declaration.TypeParameters?.Count ?? 0,
            RecordTypeInfo recordInfo => recordInfo.Declaration.TypeParameters?.Count ?? 0,
            SoaRecordTypeInfo => 0,
            InterfaceTypeInfo interfaceInfo => interfaceInfo.Declaration.TypeParameters?.Count ?? 0,
            UnionTypeInfo { IsAnonymous: false } unionInfo => unionInfo.Declaration!.TypeParameters?.Count ?? 0,
            EnumTypeInfo => 0,
            AliasTypeInfo => 0,
            NewtypeInfo => 0,
            ReflectionTypeInfo reflectionInfo => reflectionInfo.Type.IsGenericTypeDefinition
                ? reflectionInfo.Type.GetGenericArguments().Length
                : 0,
            _ => -1
        };

    private List<int> GetKnownGenericHeadArities(string name)
    {
        const int MaxClrGenericArity = 17;
        var arities = new List<int>();

        for (var arity = 1; arity <= MaxClrGenericArity; arity++)
        {
            if (TryGetKnownOpenGenericType(name, arity) != null
                || TryResolveExternalType($"{name}`{arity}") is ReflectionTypeInfo { Type.IsGenericTypeDefinition: true })
            {
                arities.Add(arity);
            }
        }

        return arities;
    }

    private TypeInfo ResolveAnonymousUnionType(UnionTypeReference union)
    {
        var resolvedArms = new List<TypeInfo>();
        foreach (var armRef in union.Arms)
        {
            var arm = ResolveType(armRef);
            if (arm is UnionTypeInfo { IsAnonymous: true } nested)
            {
                resolvedArms.AddRange(nested.Arms);
            }
            else
            {
                resolvedArms.Add(arm);
            }
        }

        var uniqueArms = new List<TypeInfo>();
        foreach (var arm in resolvedArms)
        {
            if (uniqueArms.Any(existing => TypesEqual(existing, arm)))
            {
                var span = GetTypeReferenceStartSpan(union);
                Error(
                    ErrorCode.DuplicateDeclaration,
                    $"Anonymous union type repeats arm '{arm}'. Each arm must be unique.",
                    span.StartLine,
                    span.StartColumn,
                    "Remove the duplicate arm, or declare a named union if the repeated shape represents different cases.",
                    Math.Max(1, union.Span.IsValid ? union.Span.EndColumn - union.Span.StartColumn : 1));
                continue;
            }

            uniqueArms.Add(arm);
        }

        if (uniqueArms.Count > 2)
        {
            var span = GetTypeReferenceStartSpan(union);
            Error(
                ErrorCode.InvalidTypeArgument,
                $"Anonymous union types support exactly two arms in v1; this union has {uniqueArms.Count} arms.",
                span.StartLine,
                span.StartColumn,
                "Declare a named `union` for larger variants.",
                Math.Max(1, union.Span.IsValid ? union.Span.EndColumn - union.Span.StartColumn : 1));
        }

        return new UnionTypeInfo(uniqueArms);
    }

    private void RecordResolvedTypeReference(TypeReference typeRef, TypeInfo resolved)
    {
        var span = GetTypeReferenceStartSpan(typeRef);
        if (!span.IsValid)
            return;

        _semanticModel.RecordTypeReference(span.StartLine, span.StartColumn, resolved);
    }

    private static SourceSpan GetTypeReferenceStartSpan(TypeReference typeRef)
    {
        if (typeRef.Span.IsValid)
            return typeRef.Span;

        return typeRef switch
        {
            SimpleTypeReference simple => SourceSpan.FromStartAndLength(simple.Line, simple.Column, simple.Name.Length),
            GenericTypeReference generic => SourceSpan.FromStartAndLength(generic.Line, generic.Column, generic.Name.Length),
            ArrayTypeReference array => GetTypeReferenceStartSpan(array.ElementType),
            NullableTypeReference nullable => GetTypeReferenceStartSpan(nullable.InnerType),
            UnionTypeReference union when union.Arms.Count > 0 => GetTypeReferenceStartSpan(union.Arms[0]),
            TupleTypeReference tuple when tuple.Elements.Count > 0 => GetTypeReferenceStartSpan(tuple.Elements[0].Type),
            FunctionTypeReference function => GetTypeReferenceStartSpan(function.ReturnType),
            ByRefTypeReference byRef => GetTypeReferenceStartSpan(byRef.InnerType),
            _ => SourceSpan.None
        };
    }

    private void ResolveTypeReferenceIfPresent(TypeReference? typeReference)
    {
        if (typeReference != null)
        {
            ResolveType(typeReference);
        }
    }

    private void ResolveTypeReferences(IEnumerable<TypeReference> typeReferences)
    {
        foreach (var typeReference in typeReferences)
        {
            ResolveType(typeReference);
        }
    }

    private void ResolveGenericConstraintTypes(IEnumerable<GenericConstraint>? constraints)
    {
        if (constraints == null)
            return;

        foreach (var constraint in constraints)
        {
            ResolveTypeReferences(constraint.Constraints);
        }
    }

    private TypeInfo ResolveSimpleType(string name, int line = 0, int column = 0)
    {
        if (name == "var" && line > 0)
        {
            Error("'var' is not a type; use ':=' for type inference", line, column);
            return BuiltInTypes.Unknown;
        }

        // Check built-in types
        TypeInfo? builtInType = name switch
        {
            "int" => BuiltInTypes.Int,
            "long" => BuiltInTypes.Long,
            "float" => BuiltInTypes.Float,
            "double" => BuiltInTypes.Double,
            "decimal" => BuiltInTypes.Decimal,
            "byte" => BuiltInTypes.Byte,
            "sbyte" => BuiltInTypes.SByte,
            "short" => BuiltInTypes.Short,
            "ushort" => BuiltInTypes.UShort,
            "uint" => BuiltInTypes.UInt,
            "ulong" => BuiltInTypes.ULong,
            "char" => BuiltInTypes.Char,
            "bool" => BuiltInTypes.Bool,
            "string" => BuiltInTypes.String,
            "void" => BuiltInTypes.Void,
            "object" => BuiltInTypes.Object,
            _ => null
        };

        if (builtInType != null)
            return builtInType;

        // Check local type declarations
        var localType = LookupType(name);
        if (localType != null)
        {
            // Record a binding for this type reference so FindReferences works
            // across files (e.g., imported types used in annotations).
            if (line > 0)
            {
                TryRecordTypeBinding(name, line, column);
            }
            return localType;
        }

        if (TryResolveDottedNestedType(name, out var nestedType))
        {
            return nestedType;
        }

        // Check using aliases
        if (_usingAliases.TryGetValue(name, out var fullName))
        {
            var aliasedType = TryResolveExternalType(fullName);
            if (aliasedType != null)
                return aliasedType;
        }

        // Try to resolve as external type
        var externalType = TryResolveExternalType(name);
        if (externalType != null)
            return externalType;

        // Fall back to project-level auto-discovered types
        if (TryResolveProjectSymbol(name, line, column, out var projectType))
        {
            return projectType;
        }

        // No resolution channel recognized this name. Historically this always fell through
        // silently ("might be from a C# library"), letting typos and missing references reach
        // IL emission. At declared-type positions (ResolveDeclaredType) report undotted names
        // as NL201; dotted names stay lenient for now because namespace-qualified externals
        // and `new Union.Case` references legitimately resolve through other channels.
        if (_reportUnresolvedTypes && line > 0 && !name.Contains('.') &&
            _reportedUnresolvedTypeRefs.Add((name, line, column)))
        {
            Error(
                ErrorCode.TypeNotFound,
                $"Type '{name}' not found",
                line,
                column,
                BuildUnresolvedTypeSuggestion(name),
                name.Length);
        }

        return new ExternalTypeInfo(name);
    }

    private bool TryResolveDottedNestedType(string name, out TypeInfo type)
    {
        var parts = name.Split('.', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2)
        {
            type = BuiltInTypes.Unknown;
            return false;
        }

        type = ResolveTypeAlias(LookupType(parts[0]) ?? BuiltInTypes.Unknown);
        if (BuiltInTypes.IsUnknown(type))
        {
            return false;
        }

        for (var i = 1; i < parts.Length; i++)
        {
            if (!TryResolveNestedTypeOnOwner(type, parts[i], out type))
            {
                type = BuiltInTypes.Unknown;
                return false;
            }
        }

        return true;
    }

    private string BuildUnresolvedTypeSuggestion(string name)
    {
        string? bestCandidate = null;
        var bestDistance = int.MaxValue;
        foreach (var candidate in GetAllTypesInScope())
        {
            if (candidate.Length < 3 || candidate == name)
                continue;

            var distance = ErrorSuggestions.LevenshteinDistance(
                name.ToLowerInvariant(), candidate.ToLowerInvariant());
            if (distance < bestDistance)
            {
                bestDistance = distance;
                bestCandidate = candidate;
            }
        }

        return bestCandidate != null && bestDistance <= 2
            ? $"Did you mean '{bestCandidate}'? Otherwise add the 'import' or package reference that provides '{name}'."
            : $"Check the spelling, add the missing 'import', or add the package/project reference that provides '{name}'.";
    }

    /// <summary>
    /// Record a binding from a type reference position to the type's declaration.
    /// </summary>
    private void TryRecordTypeBinding(string name, int line, int column)
    {
        foreach (var scope in _scopes)
        {
            if (scope.Types.TryGetValue(name, out _))
            {
                var declLocation = scope.GetDeclarationLocation(name);
                if (declLocation != null)
                {
                    _bindingMap.RecordBinding(_currentFilePath, line, column, name.Length, declLocation);
                }
                return;
            }
        }
    }

    /// <summary>
    /// Maps built-in type keywords (int, string, bool, etc.) to their CLR System.Type.
    /// Enables static member access like int.Parse(), string.IsNullOrEmpty(), etc.
    /// </summary>
    private Type? TryResolveBuiltInTypeKeyword(string name)
    {
        if (_wellKnownTypes == null) return null;

        return name switch
        {
            "int" => _wellKnownTypes.Int32,
            "long" => _wellKnownTypes.Int64,
            "float" => _wellKnownTypes.Single,
            "double" => _wellKnownTypes.Double,
            "decimal" => _wellKnownTypes.Decimal,
            "byte" => _wellKnownTypes.Byte,
            "sbyte" => _wellKnownTypes.SByte,
            "short" => _wellKnownTypes.Int16,
            "ushort" => _wellKnownTypes.UInt16,
            "uint" => _wellKnownTypes.UInt32,
            "ulong" => _wellKnownTypes.UInt64,
            "char" => _wellKnownTypes.Char,
            "bool" => _wellKnownTypes.Boolean,
            "string" => _wellKnownTypes.String,
            "object" => _wellKnownTypes.Object,
            _ => null
        };
    }

    private TypeInfo? TryResolveExternalType(string name)
    {
        // Check cache first
        if (_externalTypeCache.TryGetValue(name, out var cachedType))
            return new ReflectionTypeInfo(cachedType);

        // Try with using namespaces
        foreach (var ns in _usingNamespaces)
        {
            var fullName = $"{ns}.{name}";

            // Check cache for full name
            if (_externalTypeCache.TryGetValue(fullName, out cachedType))
                return new ReflectionTypeInfo(cachedType);

            // Search all MLC-loaded assemblies
            foreach (var assembly in _mlcAssemblies)
            {
                try
                {
                    var type = assembly.GetType(fullName);
                    if (type != null)
                    {
                        _externalTypeCache[fullName] = type;
                        return new ReflectionTypeInfo(type);
                    }
                }
                catch (Exception ex)
                {
                    RecordReferenceLoadFailure(assembly.GetName().Name ?? assembly.ToString(), ex);
                    continue;
                }
            }
        }

        // Try without namespace (by simple name) in MLC assemblies
        foreach (var assembly in _mlcAssemblies)
        {
            try
            {
                var matchingType = assembly.GetExportedTypes()
                    .FirstOrDefault(t => t.Name == name || t.FullName == name);
                if (matchingType != null)
                {
                    _externalTypeCache[name] = matchingType;
                    return new ReflectionTypeInfo(matchingType);
                }
            }
            catch (Exception ex)
            {
                RecordReferenceLoadFailure(assembly.GetName().Name ?? assembly.ToString(), ex);
                continue;
            }
        }

        return null;
    }

    private TypeInfo? LookupType(string name)
    {
        foreach (var scope in _scopes)
        {
            if (scope.Types.TryGetValue(name, out var type))
                return type;
        }
        return null;
    }

    /// <summary>
    /// Looks up a symbol's type by walking the scope chain. Returns null if not found.
    /// </summary>
    private TypeInfo? LookupSymbol(string name)
    {
        foreach (var scope in _scopes)
        {
            if (scope.Symbols.TryGetValue(name, out var type))
                return type;
        }
        return null;
    }

    private bool TryLookupNullState(string path, out NullState state)
    {
        foreach (var scope in _scopes)
        {
            if (scope.NullStates.TryGetValue(path, out state))
                return true;
        }

        state = NullState.Unknown;
        return false;
    }

    private void SetNullStateInCurrentScope(string path, NullState state)
    {
        if (_scopes.Count == 0 || string.IsNullOrWhiteSpace(path))
            return;

        _scopes.Peek().NullStates[path] = state;
    }

    private void RegisterErrorTupleResult(string resultName, string errorName, int line, int column)
    {
        if (_scopes.Count == 0 || string.IsNullOrWhiteSpace(resultName) || resultName == "_")
            return;

        _scopes.Peek().ErrorTupleResults[resultName] =
            new ErrorTupleResultGuard(resultName, errorName, line, column);
    }

    private void MarkErrorTupleResultsAvailableForError(string errorName)
    {
        if (_scopes.Count == 0 || string.IsNullOrWhiteSpace(errorName) || errorName.Contains('.', StringComparison.Ordinal))
            return;

        var currentScope = _scopes.Peek();
        foreach (var scope in _scopes)
        {
            foreach (var guard in scope.ErrorTupleResults.Values)
            {
                if (guard.ErrorName == errorName)
                {
                    currentScope.AvailableErrorTupleResults.Add(guard.ResultName);
                }
            }

            if (scope.Symbols.ContainsKey(errorName))
                break;
        }
    }

    private void MarkErrorTupleResultAvailableAfterAssignment(Expression target)
    {
        if (_scopes.Count == 0 || target is not IdentifierExpression identifier)
            return;

        if (TryGetErrorTupleResultGuard(identifier.Name, out _))
        {
            _scopes.Peek().AvailableErrorTupleResults.Add(identifier.Name);
        }
    }

    private void ReportUnverifiedErrorTupleResultUseIfNeeded(string name, int line, int column)
    {
        if (_suppressErrorTupleResultUse)
            return;

        if (!TryGetErrorTupleResultGuard(name, out var guard) || IsErrorTupleResultAvailable(name))
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

    private bool TryGetErrorTupleResultGuard(string resultName, out ErrorTupleResultGuard guard)
    {
        foreach (var scope in _scopes)
        {
            if (scope.ErrorTupleResults.TryGetValue(resultName, out guard!))
                return true;

            if (scope.Symbols.ContainsKey(resultName))
                break;
        }

        guard = null!;
        return false;
    }

    private bool IsErrorTupleResultAvailable(string resultName)
    {
        foreach (var scope in _scopes)
        {
            if (scope.AvailableErrorTupleResults.Contains(resultName))
                return true;

            if (scope.ErrorTupleResults.ContainsKey(resultName))
                return false;

            if (scope.Symbols.ContainsKey(resultName))
                return true;
        }

        return true;
    }

    private void InvalidateNullFactsForAssignment(string path)
    {
        foreach (var scope in _scopes)
        {
            var keysToRemove = scope.NullStates.Keys
                .Where(key => key == path || key.StartsWith(path + ".", StringComparison.Ordinal))
                .ToList();

            foreach (var key in keysToRemove)
            {
                scope.NullStates.Remove(key);
            }
        }
    }

    private static string? TryGetStableNullPath(Expression expression)
    {
        return expression switch
        {
            IdentifierExpression identifier when identifier.Name != "<error>" => identifier.Name,
            ThisExpression => "this",
            ParenthesizedExpression parenthesized => TryGetStableNullPath(parenthesized.Inner),
            MemberAccessExpression { IsNullConditional: false } memberAccess
                when TryGetStableNullPath(memberAccess.Object) is { } receiverPath
                => $"{receiverPath}.{memberAccess.MemberName}",
            _ => null
        };
    }

    private bool TryResolveIdentifierBindingTarget(string name, int line, int column, out TypeInfo type)
    {
        // Check local symbols first
        foreach (var scope in _scopes)
        {
            if (scope.Symbols.TryGetValue(name, out type!))
            {
                var declLocation = scope.GetDeclarationLocation(name);
                if (declLocation != null)
                {
                    _bindingMap.RecordBinding(_currentFilePath, line, column, name.Length, declLocation);
                }
                return true;
            }
        }

        foreach (var scope in _scopes)
        {
            if (scope.Types.TryGetValue(name, out type!))
            {
                var declLocation = scope.GetDeclarationLocation(name);
                if (declLocation != null)
                {
                    _bindingMap.RecordBinding(_currentFilePath, line, column, name.Length, declLocation);
                }
                return true;
            }
        }

        var currentType = GetCurrentTypeScope();
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
        var builtInClrType = TryResolveBuiltInTypeKeyword(name);
        if (builtInClrType != null)
        {
            type = new ReflectionTypeInfo(builtInClrType);
            return true;
        }

        // Try to resolve as external type (for static class access like Console).
        // This intentionally happens after current-type member lookup so instance
        // members win over imported type names in instance scope.
        var externalType = TryResolveExternalType(name);
        if (externalType != null)
        {
            type = externalType;
            return true;
        }

        // Fall back to project-level auto-discovered symbols
        if (TryResolveProjectSymbol(name, line, column, out type!))
        {
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

        // Use ErrorMessageBuilder for better error message with suggestions
        var similarNames = reportMissingAsFunction
            ? FindSimilarFunctionNames(name)
            : FindSimilarVariableNames(name);
        var sourceSnippet = _sourceLines != null && line > 0 && line <= _sourceLines.Length
            ? _sourceLines[line - 1]
            : null;

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

    private TypeInfo? GetCurrentTypeScope()
    {
        foreach (var scope in _scopes)
        {
            if (scope.Symbols.TryGetValue("this", out var type))
                return type;
        }
        return null;
    }

    private TypeInfo AnalyzeBaseExpression()
    {
        var currentType = GetCurrentTypeScope();
        return currentType switch
        {
            ClassTypeInfo classType when classType.Declaration.BaseClass != null => ResolveType(classType.Declaration.BaseClass),
            _ => currentType != null ? BuiltInTypes.Object : BuiltInTypes.Unknown
        };
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
    private bool IsAssignable(TypeInfo target, TypeInfo source)
    {
        // Resolve type aliases
        var resolvedTarget = ResolveTypeAlias(target);
        var resolvedSource = ResolveTypeAlias(source);

        if (resolvedTarget == resolvedSource) return true;
        if (resolvedSource == BuiltInTypes.Null && resolvedTarget is NullableTypeInfo) return true;
        // null is assignable to any reference type (string, classes, interfaces, arrays, delegates)
        if (resolvedSource == BuiltInTypes.Null && IsReferenceType(resolvedTarget)) return true;
        if (resolvedSource == BuiltInTypes.Never) return true;

        // Unknown type handling — distinguished by kind
        // ErrorRecovery: suppress follow-on errors (an error was already reported upstream)
        // InferenceHole/DeferredExternal: accept for now but distinguishable for future tightening
        if (resolvedSource is UnknownTypeInfo || resolvedTarget is UnknownTypeInfo) return true;

        if (resolvedTarget is ByRefTypeInfo || resolvedSource is ByRefTypeInfo)
        {
            return resolvedTarget is ByRefTypeInfo targetByRef
                && resolvedSource is ByRefTypeInfo sourceByRef
                && TypesEqual(targetByRef.InnerType, sourceByRef.InnerType);
        }

        if (resolvedSource is UnionTypeInfo { IsAnonymous: true } sourceUnion
            && resolvedTarget is UnionTypeInfo { IsAnonymous: true } targetUnion)
        {
            return sourceUnion.Arms.All(sourceArm =>
                targetUnion.Arms.Any(targetArm => IsAssignable(targetArm, sourceArm)));
        }

        if (resolvedTarget is UnionTypeInfo { IsAnonymous: true } unionTarget)
            return unionTarget.Arms.Any(targetArm => IsAssignable(targetArm, resolvedSource));

        if (resolvedSource is UnionTypeInfo { IsAnonymous: true } unionSource)
            return unionSource.Arms.All(sourceArm => IsAssignable(resolvedTarget, sourceArm));

        if (resolvedSource is FunctionTypeInfo { Declaration: not null } sourceFunction)
        {
            if (!CanBindCallableReferenceToExpectedType(resolvedTarget))
                return false;

            if (resolvedTarget is ReflectionTypeInfo reflectionTarget && IsRuntimeDelegateType(reflectionTarget.Type))
            {
                var delegateSignature = CreateFunctionTypeInfoFromDelegate(reflectionTarget.Type);
                return IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(sourceFunction, delegateSignature);
            }
        }
        else if (IsMethodGroupReferenceType(resolvedSource))
        {
            return false;
        }

        if (IsCallableReferenceType(resolvedTarget))
            return false;

        // Everything is assignable to object, except bare method references which are not values.
        if (resolvedTarget == BuiltInTypes.Object) return true;

        if (IsArrayToSpanAssignable(resolvedTarget, resolvedSource)) return true;

        // Nullable widening: T -> T? and T? -> U? (inner type widening)
        if (resolvedTarget is NullableTypeInfo nullableTarget)
        {
            // Nullable<T> → Nullable<U>: check if inner types are compatible (e.g., int? → long?)
            if (resolvedSource is NullableTypeInfo nullableSource)
                return IsAssignable(nullableTarget.InnerType, nullableSource.InnerType);
            // T → T?: widening non-nullable to nullable
            return IsAssignable(nullableTarget.InnerType, resolvedSource);
        }

        // Reflection-based type checking: use CLR semantics when both sides are reflection types
        if (resolvedSource is ReflectionTypeInfo srcRefl && resolvedTarget is ReflectionTypeInfo tgtRefl)
            return IsReflectionAssignableFrom(tgtRefl.Type, srcRefl.Type);
        // Mixed: reflection target + built-in source — convert to MLC type for comparison
        if (resolvedTarget is ReflectionTypeInfo tgtRefl2 && resolvedSource is SimpleTypeInfo)
        {
            var clrType = TryConvertTypeInfoToClrType(resolvedSource);
            if (clrType != null) return tgtRefl2.Type.IsAssignableFrom(clrType);
        }
        // Mixed: built-in target + reflection source
        if (resolvedTarget is SimpleTypeInfo tgtSimple && resolvedSource is ReflectionTypeInfo srcRefl2)
        {
            var clrType = TryConvertTypeInfoToClrType(resolvedTarget);
            if (clrType != null) return clrType.IsAssignableFrom(srcRefl2.Type);
        }

        // Function type structural comparison (both sides are FunctionTypeInfo) — must come before
        // the ToString fallback because FunctionTypeInfo.ToString() is always "FunctionTypeInfo"
        if (resolvedSource is FunctionTypeInfo srcFunc && resolvedTarget is FunctionTypeInfo tgtFunc)
            return IsFunctionTypeAssignable(srcFunc, tgtFunc);

        // Same type name (string comparison fallback for types we can't structurally compare)
        if (resolvedTarget.ToString() == resolvedSource.ToString()) return true;

        if (IsKnownGenericTypeAssignable(resolvedTarget, resolvedSource)) return true;

        // CLR implicit numeric conversions
        if (IsImplicitNumericConversion(resolvedSource, resolvedTarget)) return true;

        // Nominal subtyping: walk base class chain and interface lists for N#-declared types
        if (IsSubtypeOf(resolvedSource, resolvedTarget)) return true;

        // Enum to underlying type: enum value -> string/int is allowed
        if (resolvedSource is EnumTypeInfo enumSrc)
        {
            var underlyingType = enumSrc.Declaration.Type == EnumType.String
                ? BuiltInTypes.String : BuiltInTypes.Int;
            if (IsAssignable(resolvedTarget, underlyingType)) return true;
        }

        // Lambda function types (FunctionTypeInfo) are assignable to delegate types (Func/Action)
        // with structural parameter count and type validation
        if (resolvedSource is FunctionTypeInfo funcType && resolvedTarget is GenericTypeInfo { Name: "Func" or "Action" } delegateType)
            return IsLambdaAssignableToDelegate(funcType, delegateType);

        // Duck interface structural typing
        if (resolvedTarget is InterfaceTypeInfo iface && iface.Declaration.IsDuckInterface)
        {
            return ImplementsDuckInterface(resolvedSource, iface);
        }

        // Collection expressions (C# 12): Allow array literals to be assigned to collection types
        // e.g., List<int> numbers = [1, 2, 3];
        if (resolvedSource is ArrayTypeInfo arrayType && IsCollectionType(resolvedTarget, out var collectionElementType))
        {
            // Check that the array element type is compatible with the collection element type
            return IsAssignable(collectionElementType, arrayType.ElementType);
        }

        // User-defined implicit conversions: Check if source has an implicit conversion operator to target
        if (HasImplicitConversion(resolvedSource, resolvedTarget))
        {
            return true;
        }

        return false;
    }

    private static TypeInfo GetFloatLiteralType(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.EndsWith("m", StringComparison.OrdinalIgnoreCase))
            return BuiltInTypes.Decimal;
        if (trimmed.EndsWith("f", StringComparison.OrdinalIgnoreCase))
            return BuiltInTypes.Float;
        return BuiltInTypes.Double;
    }

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
        var resolved = ResolveTypeAlias(expectedType);
        if (resolved is NullableTypeInfo nullable)
        {
            resolved = ResolveTypeAlias(nullable.InnerType);
        }

        if (resolved is SimpleTypeInfo simple
            && TryGetUnsignedIntegerLiteralMaxValue(simple.Name, out var simpleMaxValue)
            && magnitude <= simpleMaxValue)
        {
            targetType = simple;
            return true;
        }

        if (resolved is ReflectionTypeInfo reflection
            && TryGetIntegerLiteralTypeInfo(reflection.Type, out var reflectionType)
            && TryGetUnsignedIntegerLiteralMaxValue(reflectionType.Name, out var reflectionMaxValue)
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

        var resolved = ResolveTypeAlias(expectedType);
        if (resolved is NullableTypeInfo nullable)
        {
            resolved = ResolveTypeAlias(nullable.InnerType);
        }

        if (resolved is SimpleTypeInfo simple
            && TryGetNegativeIntegerLiteralMaxMagnitude(simple.Name, out var simpleMaxMagnitude)
            && magnitude <= simpleMaxMagnitude)
        {
            targetType = simple;
            return true;
        }

        if (resolved is ReflectionTypeInfo reflection
            && TryGetIntegerLiteralTypeInfo(reflection.Type, out var reflectionType)
            && TryGetNegativeIntegerLiteralMaxMagnitude(reflectionType.Name, out var reflectionMaxMagnitude)
            && magnitude <= reflectionMaxMagnitude)
        {
            targetType = reflectionType;
            return true;
        }

        return false;
    }

    private static bool TryGetIntegerLiteralTypeInfo(Type type, out SimpleTypeInfo typeInfo)
    {
        type = Nullable.GetUnderlyingType(type) ?? type;
        if (type == typeof(byte))
        {
            typeInfo = BuiltInTypes.Byte;
            return true;
        }
        if (type == typeof(sbyte))
        {
            typeInfo = BuiltInTypes.SByte;
            return true;
        }
        if (type == typeof(short))
        {
            typeInfo = BuiltInTypes.Short;
            return true;
        }
        if (type == typeof(ushort))
        {
            typeInfo = BuiltInTypes.UShort;
            return true;
        }
        if (type == typeof(int))
        {
            typeInfo = BuiltInTypes.Int;
            return true;
        }
        if (type == typeof(uint))
        {
            typeInfo = BuiltInTypes.UInt;
            return true;
        }
        if (type == typeof(long))
        {
            typeInfo = BuiltInTypes.Long;
            return true;
        }
        if (type == typeof(ulong))
        {
            typeInfo = BuiltInTypes.ULong;
            return true;
        }
        if (type == typeof(char))
        {
            typeInfo = BuiltInTypes.Char;
            return true;
        }

        typeInfo = BuiltInTypes.Int;
        return false;
    }

    private static bool TryGetNegativeIntegerLiteralMaxMagnitude(string typeName, out ulong maxMagnitude)
    {
        switch (typeName)
        {
            case "sbyte":
                maxMagnitude = (ulong)sbyte.MaxValue + 1;
                return true;
            case "short":
                maxMagnitude = (ulong)short.MaxValue + 1;
                return true;
            case "int":
                maxMagnitude = (ulong)int.MaxValue + 1;
                return true;
            case "long":
                maxMagnitude = (ulong)long.MaxValue + 1;
                return true;
            default:
                maxMagnitude = 0;
                return false;
        }
    }

    private static bool TryGetUnsignedIntegerLiteralMaxValue(string typeName, out ulong maxValue)
    {
        switch (typeName)
        {
            case "byte":
                maxValue = byte.MaxValue;
                return true;
            case "sbyte":
                maxValue = (ulong)sbyte.MaxValue;
                return true;
            case "short":
                maxValue = (ulong)short.MaxValue;
                return true;
            case "ushort":
            case "char":
                maxValue = ushort.MaxValue;
                return true;
            case "int":
                maxValue = int.MaxValue;
                return true;
            case "uint":
                maxValue = uint.MaxValue;
                return true;
            case "long":
                maxValue = long.MaxValue;
                return true;
            case "ulong":
                maxValue = ulong.MaxValue;
                return true;
            default:
                maxValue = 0;
                return false;
        }
    }

    private bool IsKnownGenericTypeAssignable(TypeInfo target, TypeInfo source)
    {
        if (target is not GenericTypeInfo targetGeneric || source is not GenericTypeInfo sourceGeneric)
            return false;

        if (targetGeneric.TypeArguments.Count != sourceGeneric.TypeArguments.Count)
            return false;

        var isKnownConversion = (targetGeneric.Name, sourceGeneric.Name) switch
        {
            ("IEnumerable", "IEnumerable" or "List" or "ICollection" or "IList" or "HashSet" or "Queue") => true,
            ("IQueryable", "IQueryable") => true,
            ("ICollection", "List" or "IList" or "HashSet") => true,
            ("IList", "List") => true,
            ("IReadOnlyCollection", "List" or "IReadOnlyList" or "HashSet" or "Queue") => true,
            ("IReadOnlyList", "List") => true,
            _ => false
        };

        if (!isKnownConversion)
            return false;

        var isCovariantTarget = targetGeneric.Name is "IEnumerable" or "IQueryable" or "IReadOnlyCollection" or "IReadOnlyList";
        for (var i = 0; i < targetGeneric.TypeArguments.Count; i++)
        {
            var targetArgument = targetGeneric.TypeArguments[i];
            var sourceArgument = sourceGeneric.TypeArguments[i];
            if (TypesEqual(targetArgument, sourceArgument))
                continue;

            if (isCovariantTarget
                && IsReferenceLikeForVariance(targetArgument)
                && IsReferenceLikeForVariance(sourceArgument)
                && IsAssignable(targetArgument, sourceArgument))
                continue;

            return false;
        }

        return true;
    }

    private bool IsArrayToSpanAssignable(TypeInfo target, TypeInfo source)
    {
        if (source is not ArrayTypeInfo array || target is not GenericTypeInfo targetGeneric)
            return false;

        if (targetGeneric.TypeArguments.Count != 1)
            return false;

        if (!IsSpanTypeName(targetGeneric.Name))
            return false;

        return TypesEqual(ResolveTypeAlias(targetGeneric.TypeArguments[0]), ResolveTypeAlias(array.ElementType));
    }

    private static bool IsSpanTypeName(string name)
        => name is "Span" or "ReadOnlySpan" or "System.Span" or "System.ReadOnlySpan";

    private bool IsReferenceLikeForVariance(TypeInfo type)
    {
        var resolved = ResolveTypeAlias(type);
        return resolved switch
        {
            NullableTypeInfo nullable => IsReferenceLikeForVariance(nullable.InnerType),
            ObliviousTypeInfo oblivious => IsReferenceLikeForVariance(oblivious.InnerType),
            _ => MayUseDelegateReferenceConversion(resolved)
        };
    }

    /// <summary>
    /// Structurally validates that a source FunctionTypeInfo is assignable to a target FunctionTypeInfo.
    /// Checks parameter count, parameter type compatibility, and return type compatibility.
    /// </summary>
    private bool IsFunctionTypeAssignable(FunctionTypeInfo source, FunctionTypeInfo target)
    {
        var srcParamCount = source.ParameterTypes?.Count ?? 0;
        var tgtParamCount = target.ParameterTypes?.Count ?? 0;

        if (srcParamCount != tgtParamCount)
            return false;

        // Validate parameter types (contravariant: target param must be assignable to source param)
        for (int i = 0; i < tgtParamCount; i++)
        {
            var srcParam = source.ParameterTypes![i];
            var tgtParam = target.ParameterTypes![i];
            if (BuiltInTypes.IsUnknown(srcParam)) continue; // Inferred — don't reject
            if (!IsAssignable(srcParam, tgtParam))
                return false;
        }

        // Validate return type (covariant: source return must be assignable to target return)
        if (source.ReturnType != null && target.ReturnType != null
            && !BuiltInTypes.IsUnknown(source.ReturnType))
        {
            if (!IsAssignable(target.ReturnType, source.ReturnType))
                return false;
        }

        return true;
    }

    private bool IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(FunctionTypeInfo source, FunctionTypeInfo target)
    {
        return TryGetRuntimeDelegateMethodGroupMatchScore(source, target, out _);
    }

    private bool TryGetRuntimeDelegateMethodGroupMatchScore(FunctionTypeInfo source, FunctionTypeInfo target, out int score)
    {
        score = 0;
        var srcParamCount = source.ParameterTypes?.Count ?? 0;
        var tgtParamCount = target.ParameterTypes?.Count ?? 0;

        if (srcParamCount != tgtParamCount)
            return false;

        for (int i = 0; i < tgtParamCount; i++)
        {
            var srcParam = source.ParameterTypes![i];
            var tgtParam = target.ParameterTypes![i];
            if (BuiltInTypes.IsUnknown(srcParam)) continue;

            var srcModifier = GetFunctionParameterModifier(source, i);
            var tgtModifier = GetFunctionParameterModifier(target, i);
            if (NormalizeDelegateParameterModifier(srcModifier) != NormalizeDelegateParameterModifier(tgtModifier))
                return false;

            if (!TryGetDelegateSignatureConversionScore(srcParam, tgtParam, out var parameterScore))
                return false;

            score += parameterScore;
        }

        if (source.ReturnType != null && target.ReturnType != null
            && !BuiltInTypes.IsUnknown(source.ReturnType))
        {
            if (!TryGetDelegateSignatureConversionScore(target.ReturnType, source.ReturnType, out var returnScore))
                return false;

            score += returnScore;
        }

        return true;
    }

    private static Ast.ParameterModifier GetFunctionParameterModifier(FunctionTypeInfo functionType, int index)
    {
        if (functionType.ParameterModifiers == null || index >= functionType.ParameterModifiers.Count)
            return Ast.ParameterModifier.None;

        return functionType.ParameterModifiers[index];
    }

    private static Ast.ParameterModifier NormalizeDelegateParameterModifier(Ast.ParameterModifier modifier)
    {
        return modifier == Ast.ParameterModifier.Params ? Ast.ParameterModifier.None : modifier;
    }

    private bool TryGetDelegateSignatureConversionScore(TypeInfo target, TypeInfo source, out int score)
    {
        score = 0;
        var resolvedTarget = ResolveTypeAlias(target);
        var resolvedSource = ResolveTypeAlias(source);

        if (resolvedTarget == resolvedSource || resolvedTarget.ToString() == resolvedSource.ToString())
        {
            score = 8;
            return true;
        }

        if (resolvedSource is UnknownTypeInfo || resolvedTarget is UnknownTypeInfo)
        {
            score = 1;
            return true;
        }

        if (resolvedTarget is ReflectionTypeInfo { Type.IsGenericParameter: true }
            || resolvedSource is ReflectionTypeInfo { Type.IsGenericParameter: true })
        {
            score = 2;
            return true;
        }

        if (!MayUseDelegateReferenceConversion(resolvedTarget)
            || !MayUseDelegateReferenceConversion(resolvedSource))
        {
            return false;
        }

        if (resolvedSource is ReflectionTypeInfo srcRefl && resolvedTarget is ReflectionTypeInfo tgtRefl)
        {
            if (!tgtRefl.Type.IsAssignableFrom(srcRefl.Type))
                return false;

            score = 4;
            return true;
        }

        if (resolvedTarget is ReflectionTypeInfo tgtRefl2)
        {
            var clrType = TryConvertTypeInfoToClrType(resolvedSource);
            if (clrType != null)
            {
                if (!tgtRefl2.Type.IsAssignableFrom(clrType))
                    return false;

                score = 4;
                return true;
            }

            if (tgtRefl2.Type == typeof(object) || IsSubtypeOf(resolvedSource, resolvedTarget))
            {
                score = 4;
                return true;
            }

            return false;
        }

        if (resolvedSource is ReflectionTypeInfo srcRefl2)
        {
            var clrType = TryConvertTypeInfoToClrType(resolvedTarget);
            if (clrType != null)
            {
                if (!clrType.IsAssignableFrom(srcRefl2.Type))
                    return false;

                score = 4;
                return true;
            }

            return false;
        }

        if (IsKnownGenericTypeAssignable(resolvedTarget, resolvedSource)
            || IsSubtypeOf(resolvedSource, resolvedTarget))
        {
            score = 4;
            return true;
        }

        return false;
    }

    private bool MayUseDelegateReferenceConversion(TypeInfo type)
    {
        var resolved = ResolveTypeAlias(type);

        if (resolved is GenericTypeInfo genericType)
            return genericType.Name != "Nullable";

        return IsReferenceType(resolved);
    }

    /// <summary>
    /// Structurally validates that a lambda (FunctionTypeInfo) is assignable to a
    /// Func/Action delegate type. Checks parameter count and, when types are known,
    /// validates parameter and return type compatibility.
    /// </summary>
    private bool IsLambdaAssignableToDelegate(FunctionTypeInfo funcType, GenericTypeInfo delegateType)
    {
        if (funcType.Declaration != null
            && TryCreateFunctionTypeInfoFromGenericDelegate(delegateType, out var delegateSignature))
        {
            return IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(funcType, delegateSignature);
        }

        var funcParamCount = funcType.ParameterTypes?.Count ?? 0;

        if (delegateType.Name == "Func")
        {
            // Func<P1, ..., Pn, R> — last type arg is return type, rest are params
            var expectedParamCount = delegateType.TypeArguments.Count - 1;
            if (funcParamCount != expectedParamCount)
                return false;

            // Validate parameter types when known (contravariant: delegate param assignable to lambda param)
            for (int i = 0; i < expectedParamCount; i++)
            {
                var lambdaParam = funcType.ParameterTypes![i];
                if (BuiltInTypes.IsUnknown(lambdaParam)) continue;
                var delegateParam = delegateType.TypeArguments[i];
                if (!IsAssignable(lambdaParam, delegateParam))
                    return false;
            }

            // Validate return type when known
            if (funcType.ReturnType != null && !BuiltInTypes.IsUnknown(funcType.ReturnType))
            {
                var delegateReturn = delegateType.TypeArguments[^1];
                if (!IsAssignable(delegateReturn, funcType.ReturnType))
                    return false;
            }

            return true;
        }
        else // Action
        {
            // Action<P1, ..., Pn> — all type args are parameters
            if (funcParamCount != delegateType.TypeArguments.Count)
                return false;

            for (int i = 0; i < delegateType.TypeArguments.Count; i++)
            {
                var lambdaParam = funcType.ParameterTypes![i];
                if (BuiltInTypes.IsUnknown(lambdaParam)) continue;
                var delegateParam = delegateType.TypeArguments[i];
                if (!IsAssignable(lambdaParam, delegateParam))
                    return false;
            }

            return true;
        }
    }

    private static bool TryCreateFunctionTypeInfoFromGenericDelegate(
        GenericTypeInfo delegateType,
        out FunctionTypeInfo signature)
    {
        signature = new FunctionTypeInfo(null)
        {
            ParameterTypes = new List<TypeInfo>(),
            ParameterModifiers = new List<Ast.ParameterModifier>(),
            ReturnType = BuiltInTypes.Unknown
        };

        if (delegateType.Name == "Func")
        {
            if (delegateType.TypeArguments.Count == 0)
                return false;

            signature.ParameterTypes = delegateType.TypeArguments.Take(delegateType.TypeArguments.Count - 1).ToList();
            signature.ParameterModifiers = Enumerable.Repeat(Ast.ParameterModifier.None, signature.ParameterTypes.Count).ToList();
            signature.ReturnType = delegateType.TypeArguments[^1];
            return true;
        }

        if (delegateType.Name == "Action")
        {
            signature.ParameterTypes = delegateType.TypeArguments.ToList();
            signature.ParameterModifiers = Enumerable.Repeat(Ast.ParameterModifier.None, signature.ParameterTypes.Count).ToList();
            signature.ReturnType = BuiltInTypes.Void;
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
            // Check if they share a common interface
            var interfacesA = reflA.Type.GetInterfaces();
            var interfacesB = new HashSet<Type>(reflB.Type.GetInterfaces());

            foreach (var iface in interfacesA)
            {
                if (interfacesB.Contains(iface))
                {
                    return new ReflectionTypeInfo(iface);
                }
            }

            // Check common base class
            var baseA = reflA.Type.BaseType;
            while (baseA != null && baseA != typeof(object))
            {
                if (baseA.IsAssignableFrom(reflB.Type))
                    return new ReflectionTypeInfo(baseA);
                baseA = baseA.BaseType;
            }
        }

        // For N# types, check if they share a common interface or base class
        // (more limited — would need to walk declaration chains)

        return null;
    }

    /// <summary>
    /// Checks whether source is a subtype of target by walking base class chains and interface lists
    /// for N#-declared types (nominal subtyping).
    /// </summary>
    private bool IsSubtypeOf(TypeInfo source, TypeInfo target)
    {
        // Class inheritance chain
        if (source is ClassTypeInfo classSource)
        {
            // Walk base class chain
            if (classSource.Declaration.BaseClass != null)
            {
                var baseType = ResolveType(classSource.Declaration.BaseClass);
                if (IsAssignable(target, baseType)) return true;
            }
            // Check implemented interfaces
            foreach (var iface in classSource.Declaration.Interfaces)
            {
                var ifaceType = ResolveType(iface);
                if (IsAssignable(target, ifaceType)) return true;
            }
        }

        // Struct interface implementation
        if (source is StructTypeInfo structSource)
        {
            foreach (var iface in structSource.Declaration.Interfaces)
            {
                var ifaceType = ResolveType(iface);
                if (IsAssignable(target, ifaceType)) return true;
            }
        }

        // Record inheritance/interfaces
        if (source is RecordTypeInfo recordSource)
        {
            foreach (var iface in recordSource.Declaration.Interfaces)
            {
                var ifaceType = ResolveType(iface);
                if (IsAssignable(target, ifaceType)) return true;
            }
        }

        // Interface inheritance
        if (source is InterfaceTypeInfo ifaceSource)
        {
            foreach (var baseIface in ifaceSource.Declaration.BaseInterfaces)
            {
                var baseType = ResolveType(baseIface);
                if (IsAssignable(target, baseType)) return true;
            }
        }

        // Reflection-backed CLR types: walk the actual CLR type hierarchy
        if (source is ReflectionTypeInfo reflSource && target is ReflectionTypeInfo reflTarget)
        {
            return !HaveSameReflectionTypeIdentity(reflSource.Type, reflTarget.Type)
                && IsReflectionAssignableFrom(reflTarget.Type, reflSource.Type);
        }

        return false;
    }

    private static bool IsReflectionAssignableFrom(Type targetType, Type sourceType)
    {
        if (HaveSameReflectionTypeIdentity(targetType, sourceType))
            return true;

        if (targetType.IsAssignableFrom(sourceType))
            return true;

        foreach (var sourceInterface in GetInterfacesSafe(sourceType))
        {
            if (HaveSameReflectionTypeIdentity(targetType, sourceInterface))
                return true;
        }

        var baseType = GetBaseTypeSafe(sourceType);
        while (baseType != null)
        {
            if (HaveSameReflectionTypeIdentity(targetType, baseType))
                return true;

            baseType = GetBaseTypeSafe(baseType);
        }

        return false;
    }

    private static bool HaveSameReflectionTypeIdentity(Type left, Type right)
    {
        if (left == right)
            return true;

        if (left.IsByRef || right.IsByRef)
        {
            return left.IsByRef
                && right.IsByRef
                && HaveSameReflectionTypeIdentity(left.GetElementType()!, right.GetElementType()!);
        }

        if (left.IsArray || right.IsArray)
        {
            return left.IsArray
                && right.IsArray
                && left.GetArrayRank() == right.GetArrayRank()
                && HaveSameReflectionTypeIdentity(left.GetElementType()!, right.GetElementType()!);
        }

        if (left.IsGenericType || right.IsGenericType)
        {
            if (!left.IsGenericType || !right.IsGenericType)
                return false;

            var leftDefinition = left.IsGenericTypeDefinition ? left : left.GetGenericTypeDefinition();
            var rightDefinition = right.IsGenericTypeDefinition ? right : right.GetGenericTypeDefinition();
            if (!HaveSameNonConstructedReflectionTypeIdentity(leftDefinition, rightDefinition))
                return false;

            if (left.IsGenericTypeDefinition || right.IsGenericTypeDefinition)
                return left.IsGenericTypeDefinition && right.IsGenericTypeDefinition;

            var leftArguments = left.GetGenericArguments();
            var rightArguments = right.GetGenericArguments();
            return leftArguments.Length == rightArguments.Length
                && leftArguments.Zip(rightArguments).All(pair => HaveSameReflectionTypeIdentity(pair.First, pair.Second));
        }

        return HaveSameNonConstructedReflectionTypeIdentity(left, right);
    }

    private static bool HaveSameNonConstructedReflectionTypeIdentity(Type left, Type right)
    {
        return string.Equals(left.FullName, right.FullName, StringComparison.Ordinal)
            && string.Equals(left.Assembly.GetName().Name, right.Assembly.GetName().Name, StringComparison.OrdinalIgnoreCase);
    }

    private static IEnumerable<Type> GetInterfacesSafe(Type type)
    {
            return type.GetInterfaces();
    }

    private static Type? GetBaseTypeSafe(Type type)
    {
            return type.BaseType;
    }

    /// <summary>
    /// CLR implicit numeric conversion table. Returns true if source can be implicitly converted to target
    /// without data loss (widening conversions only).
    /// </summary>
    private static bool IsImplicitNumericConversion(TypeInfo source, TypeInfo target)
    {
        if (source is not SimpleTypeInfo srcSimple || target is not SimpleTypeInfo tgtSimple)
            return false;

        return (srcSimple.Name, tgtSimple.Name) switch
        {
            // byte -> short, ushort, int, uint, long, ulong, float, double, decimal
            ("byte", "short" or "ushort" or "int" or "uint" or "long" or "ulong" or "float" or "double" or "decimal") => true,
            // sbyte -> short, int, long, float, double, decimal
            ("sbyte", "short" or "int" or "long" or "float" or "double" or "decimal") => true,
            // short -> int, long, float, double, decimal
            ("short", "int" or "long" or "float" or "double" or "decimal") => true,
            // ushort -> int, uint, long, ulong, float, double, decimal
            ("ushort", "int" or "uint" or "long" or "ulong" or "float" or "double" or "decimal") => true,
            // int -> long, float, double, decimal
            ("int", "long" or "float" or "double" or "decimal") => true,
            // uint -> long, ulong, float, double, decimal
            ("uint", "long" or "ulong" or "float" or "double" or "decimal") => true,
            // long -> float, double, decimal
            ("long", "float" or "double" or "decimal") => true,
            // ulong -> float, double, decimal
            ("ulong", "float" or "double" or "decimal") => true,
            // char -> ushort, int, uint, long, ulong, float, double, decimal
            ("char", "ushort" or "int" or "uint" or "long" or "ulong" or "float" or "double" or "decimal") => true,
            // float -> double
            ("float", "double") => true,
            _ => false
        };
    }

    private bool HasImplicitConversion(TypeInfo source, TypeInfo target)
    {
        // Get the members of the source type
        List<Declaration>? sourceMembers = null;

        if (source is ClassTypeInfo classType)
            sourceMembers = classType.Declaration.Members;
        else if (source is StructTypeInfo structType)
            sourceMembers = structType.Declaration.Members;
        else if (source is RecordTypeInfo recordType)
            sourceMembers = recordType.Declaration.Members;
        else
            return false; // No conversion operators for other types

        // Look for implicit conversion operators
        foreach (var member in sourceMembers)
        {
            if (member is not FunctionDeclaration func)
                continue;

            // Check if this is an implicit conversion operator
            if (!func.IsConversionOperator || !func.IsImplicitConversion)
                continue;

            // Check if it converts to the target type
            // The return type of the conversion operator is the target type
            if (func.ReturnType == null)
                continue;

            var returnType = ResolveType(func.ReturnType);
            if (IsAssignable(target, returnType))
            {
                return true;
            }
        }

        return false;
    }

    private TypeInfo ResolveTypeAlias(TypeInfo type)
    {
        if (type is AliasTypeInfo alias)
        {
            // Resolve the aliased type reference to a TypeInfo
            var resolved = ResolveType(alias.AliasedType);
            // Recursively resolve in case of nested aliases
            return ResolveTypeAlias(resolved);
        }
        if (type is ObliviousTypeInfo oblivious)
        {
            return ResolveTypeAlias(oblivious.InnerType);
        }
        return type;
    }

    /// <summary>
    /// Returns true if the type is a reference type (can be assigned null).
    /// Value types (numeric primitives, bool, char, structs, enums) return false.
    /// </summary>
    private static bool IsReferenceType(TypeInfo type)
    {
        // Known value types: all numeric built-ins, bool, char
        if (type is SimpleTypeInfo simple)
        {
            return simple.Name switch
            {
                "int" or "long" or "float" or "double" or "decimal"
                    or "byte" or "sbyte" or "short" or "ushort"
                    or "uint" or "ulong" or "char" or "bool"
                    or "void" or "null" or "never" => false,
                // string, object, and any other named types are reference types
                _ => true
            };
        }
        // Classes, interfaces, arrays, delegates, unions are reference types
        if (type is ClassTypeInfo or InterfaceTypeInfo or ArrayTypeInfo
            or FunctionTypeInfo or UnionTypeInfo)
            return true;
        // Records: reference types by default, but record struct is a value type
        if (type is RecordTypeInfo recordType)
            return !recordType.Declaration.IsStruct;
        // Structs and enums are value types
        if (type is StructTypeInfo or EnumTypeInfo or ByRefTypeInfo)
            return false;
        // GenericTypeInfo could be a reference or value type — be conservative (don't claim reference)
        // This avoids incorrectly allowing null → Span<T>, Nullable<T>, etc.
        if (type is GenericTypeInfo)
            return false;
        // Reflection types: check the CLR type
        if (type is ReflectionTypeInfo refl)
            return !refl.Type.IsValueType;
        // Nullable wrapper is already handled before this check
        // External/unknown: be conservative, don't claim reference type
        return false;
    }

    private bool IsPatternPossible(TypeInfo sourceType, TypeInfo targetType)
    {
        var resolvedSource = ResolveTypeAlias(sourceType);
        var resolvedTarget = ResolveTypeAlias(targetType);

        // Conservative: unknown/external/reflection types — don't warn
        if (resolvedSource is UnknownTypeInfo || resolvedTarget is UnknownTypeInfo) return true;
        if (resolvedSource is ReflectionTypeInfo || resolvedTarget is ReflectionTypeInfo) return true;

        // Generic type parameters — conservative, don't warn
        if (resolvedSource is GenericTypeInfo || resolvedTarget is GenericTypeInfo) return true;

        // Same type — trivially possible
        if (resolvedSource == resolvedTarget) return true;

        // Either is interface — always possible at runtime (boxing, duck typing)
        if (resolvedSource is InterfaceTypeInfo || resolvedTarget is InterfaceTypeInfo) return true;

        // Either is object — anything can be boxed to/from object
        if (resolvedSource == BuiltInTypes.Object || resolvedTarget == BuiltInTypes.Object) return true;

        // Nullable types — unwrapping is always a valid pattern
        if (resolvedSource is NullableTypeInfo || resolvedTarget is NullableTypeInfo) return true;

        // Union types — pattern matching on union cases is always valid
        if (resolvedSource is UnionTypeInfo || resolvedTarget is UnionTypeInfo) return true;

        // Both are value types and different — impossible
        // The `is` operator is a CLR runtime type-identity test (isinst), NOT a conversion.
        // Implicit numeric widening does NOT make `is` succeed: `42 is double` is always false.
        // We check this BEFORE IsAssignable because IsAssignable allows implicit numeric conversions
        // which are NOT valid for type pattern matching.
        bool sourceIsValue = !IsReferenceType(resolvedSource);
        bool targetIsValue = !IsReferenceType(resolvedTarget);
        if (sourceIsValue && targetIsValue)
        {
            return false;
        }

        // IsAssignable in either direction — covers covariance, inheritance, etc.
        // This is checked AFTER the value-type block to avoid false negatives from implicit numeric conversions.
        if (IsAssignable(resolvedTarget, resolvedSource)) return true;
        if (IsAssignable(resolvedSource, resolvedTarget)) return true;

        // Value type to non-interface, non-object reference type — impossible
        // (e.g., int is string, bool is string — these can never match)
        // Value types can box to object, and can match interfaces they implement,
        // but both of those are handled by IsAssignable above.
        if (sourceIsValue && !targetIsValue)
        {
            // Target must not be an interface (handled above via IsAssignable/interface check)
            // and must not be object (handled above)
            if (resolvedTarget is not InterfaceTypeInfo)
                return false;
        }
        if (targetIsValue && !sourceIsValue)
        {
            // Source must not be an interface and must not be object
            if (resolvedSource is not InterfaceTypeInfo)
                return false;
        }

        // Sealed class to unrelated class — impossible
        // (IsAssignable already checked above, so if we get here they're unrelated)
        if (resolvedSource is ClassTypeInfo srcClass && srcClass.Declaration.Modifiers.HasFlag(Modifiers.Sealed))
        {
            if (resolvedTarget is ClassTypeInfo) return false;
        }
        if (resolvedTarget is ClassTypeInfo tgtClass && tgtClass.Declaration.Modifiers.HasFlag(Modifiers.Sealed))
        {
            if (resolvedSource is ClassTypeInfo) return false;
        }

        // Default: conservative, assume possible
        return true;
    }

    // Check if a type is a known generic collection type (List<T>, HashSet<T>, etc.)
    private bool IsCollectionType(TypeInfo type, out TypeInfo elementType)
    {
        elementType = BuiltInTypes.Unknown;

        // Handle GenericTypeInfo (parsed generic types like List<int>)
        if (type is GenericTypeInfo genericType)
        {
            var typeName = genericType.Name;

            // Check for common generic collection types
            if (typeName == "List" ||
                typeName == "HashSet" ||
                typeName == "IList" ||
                typeName == "ICollection" ||
                typeName == "IEnumerable" ||
                typeName == "IQueryable" ||
                typeName == "ISet" ||
                typeName == "Queue" ||
                typeName == "Stack" ||
                typeName == "LinkedList" ||
                typeName == "Collection" ||
                typeName == "ObservableCollection" ||
                typeName == "SortedSet" ||
                typeName == "IReadOnlyList" ||
                typeName == "IReadOnlyCollection")
            {
                // Extract the element type from the first type argument
                if (genericType.TypeArguments.Count > 0)
                {
                    elementType = genericType.TypeArguments[0];
                    return true;
                }
            }
        }

        // Handle reflection types (external .NET types resolved via reflection)
        if (type is ReflectionTypeInfo reflectionType)
        {
            var typeName = reflectionType.Type.Name;

            // Check for common generic collection types
            if (typeName.StartsWith("List`") ||
                typeName.StartsWith("HashSet`") ||
                typeName.StartsWith("IList`") ||
                typeName.StartsWith("ICollection`") ||
                typeName.StartsWith("IEnumerable`") ||
                typeName.StartsWith("IQueryable`") ||
                typeName.StartsWith("ISet`") ||
                typeName.StartsWith("Queue`") ||
                typeName.StartsWith("Stack`") ||
                typeName.StartsWith("LinkedList`") ||
                typeName.StartsWith("Collection`") ||
                typeName.StartsWith("ObservableCollection`"))
            {
                // Extract the element type from the generic type argument
                if (reflectionType.Type.IsGenericType && reflectionType.Type.GenericTypeArguments.Length > 0)
                {
                    var elementReflectionType = reflectionType.Type.GenericTypeArguments[0];
                    elementType = new ReflectionTypeInfo(elementReflectionType);
                    return true;
                }
            }
        }

        return false;
    }

    private bool ImplementsDuckInterface(TypeInfo source, InterfaceTypeInfo duckInterface)
    {
        // Get the source type's members
        List<Declaration>? sourceMembers = null;

        if (source is ClassTypeInfo classType)
            sourceMembers = classType.Declaration.Members;
        else if (source is StructTypeInfo structType)
            sourceMembers = structType.Declaration.Members;
        else if (source is RecordTypeInfo recordType)
            sourceMembers = recordType.Declaration.Members;
        else
            return false; // Can't check structural compatibility for other types

        // For each method in the duck interface, check if source has a matching method
        foreach (var interfaceMember in duckInterface.Declaration.Members)
        {
            if (interfaceMember is not FunctionDeclaration interfaceMethod)
                continue; // Skip non-method members

            // Look for a matching method in the source type
            var found = false;
            foreach (var sourceMember in sourceMembers)
            {
                if (sourceMember is not FunctionDeclaration sourceMethod)
                    continue;

                // Check if method signatures match
                if (MethodSignaturesMatch(sourceMethod, interfaceMethod))
                {
                    found = true;
                    break;
                }
            }

            if (!found)
                return false; // Source doesn't implement this interface method
        }

        return true; // Source implements all interface methods
    }

    private bool MethodSignaturesMatch(FunctionDeclaration method1, FunctionDeclaration method2)
    {
        // Must have same name
        if (method1.Name != method2.Name)
            return false;

        // Must have same number of parameters
        if (method1.Parameters.Count != method2.Parameters.Count)
            return false;

        // Check parameter types match
        for (int i = 0; i < method1.Parameters.Count; i++)
        {
            var type1 = ResolveType(method1.Parameters[i].Type);
            var type2 = ResolveType(method2.Parameters[i].Type);

            // Simple type name comparison (could be more sophisticated)
            if (type1.ToString() != type2.ToString())
                return false;
        }

        // Check return types match
        var returnType1 = method1.ReturnType != null ? ResolveType(method1.ReturnType) : BuiltInTypes.Void;
        var returnType2 = method2.ReturnType != null ? ResolveType(method2.ReturnType) : BuiltInTypes.Void;

        if (returnType1.ToString() != returnType2.ToString())
            return false;

        return true;
    }

    private bool IsNumericType(TypeInfo type)
    {
        return type == BuiltInTypes.Int || type == BuiltInTypes.Long
            || type == BuiltInTypes.Float || type == BuiltInTypes.Double
            || type == BuiltInTypes.Decimal || type == BuiltInTypes.Byte
            || type == BuiltInTypes.SByte || type == BuiltInTypes.Short
            || type == BuiltInTypes.UShort || type == BuiltInTypes.UInt
            || type == BuiltInTypes.ULong || type == BuiltInTypes.Char;
    }

    private bool IsPrimitiveRelationalType(TypeInfo type)
    {
        var resolved = ResolveTypeAlias(type);
        if (IsNumericType(resolved) && resolved != BuiltInTypes.Decimal)
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
        var resolvedLeft = ResolveTypeAlias(left);
        var resolvedRight = ResolveTypeAlias(right);

        if (resolvedLeft == BuiltInTypes.Null || resolvedRight == BuiltInTypes.Null)
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

        return IsReferenceType(resolvedLeft) && IsReferenceType(resolvedRight);
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
        var resolved = ResolveTypeAlias(type);
        if (resolved == BuiltInTypes.Bool)
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
        return left is RecordTypeInfo { Declaration.IsStruct: true } leftRecord
            && right is RecordTypeInfo { Declaration.IsStruct: true } rightRecord
            && ReferenceEquals(leftRecord.Declaration, rightRecord.Declaration);
    }

    private bool IsIntegralType(TypeInfo type)
    {
        return type == BuiltInTypes.Int || type == BuiltInTypes.Long
            || type == BuiltInTypes.Byte || type == BuiltInTypes.SByte
            || type == BuiltInTypes.Short || type == BuiltInTypes.UShort
            || type == BuiltInTypes.UInt || type == BuiltInTypes.ULong
            || type == BuiltInTypes.Char;
    }

    private bool IsBitwiseEnumType(TypeInfo type)
    {
        var resolved = ResolveTypeAlias(type);
        return resolved is EnumTypeInfo { Declaration.Type: EnumType.Int }
            || resolved is ReflectionTypeInfo { Type.IsEnum: true };
    }

    private bool IsSameBitwiseEnumType(TypeInfo left, TypeInfo right)
    {
        var resolvedLeft = ResolveTypeAlias(left);
        var resolvedRight = ResolveTypeAlias(right);
        return (resolvedLeft, resolvedRight) switch
        {
            (EnumTypeInfo l, EnumTypeInfo r) => l.Declaration.Type == EnumType.Int
                && r.Declaration.Type == EnumType.Int
                && ReferenceEquals(l.Declaration, r.Declaration),
            (ReflectionTypeInfo l, ReflectionTypeInfo r) => l.Type.IsEnum
                && r.Type.IsEnum
                && l.Type == r.Type,
            _ => false
        };
    }

    private bool IsBoolType(TypeInfo type)
    {
        return type == BuiltInTypes.Bool;
    }

    private bool IsStringType(TypeInfo type)
    {
        return type == BuiltInTypes.String;
    }

    private bool IsNullableType(TypeInfo type)
    {
        return type is NullableTypeInfo;
    }

    /// <summary>
    /// C# binary numeric promotion rules (ECMA-334 §12.4.7).
    /// These determine the result type of arithmetic binary operations.
    /// NOTE: This is NOT the same as implicit numeric conversion (assignment context).
    /// C# promotes small types (byte, sbyte, short, ushort) to int for arithmetic.
    /// </summary>
    /// <summary>
    /// C# binary numeric promotion rules (ECMA-334 §12.4.7).
    /// Returns null for combinations that are compile-time errors in C#
    /// (decimal+float/double, ulong+signed).
    /// </summary>
    private TypeInfo? GetWiderType(TypeInfo left, TypeInfo right)
    {
        var l = GetNumericName(left);
        var r = GetNumericName(right);
        if (l == null || r == null)
            return BuiltInTypes.Int; // fallback

        // decimal cannot mix with float or double (ECMA-334 §12.4.7)
        if (l == "decimal" || r == "decimal")
        {
            var other = l == "decimal" ? r : l;
            if (other is "float" or "double")
                return null; // compile-time error
            return BuiltInTypes.Decimal;
        }

        if (l == "double" || r == "double") return BuiltInTypes.Double;
        if (l == "float" || r == "float") return BuiltInTypes.Float;

        // ulong cannot mix with signed types (ECMA-334 §12.4.7)
        if (l == "ulong" || r == "ulong")
        {
            var other = l == "ulong" ? r : l;
            if (other is "sbyte" or "short" or "int" or "long")
                return null; // compile-time error
            return BuiltInTypes.ULong;
        }

        if (l == "long" || r == "long") return BuiltInTypes.Long;

        // uint: if the other is a signed type (sbyte, short, int), promote to long
        if (l == "uint" || r == "uint")
        {
            var other = l == "uint" ? r : l;
            if (other is "sbyte" or "short" or "int")
                return BuiltInTypes.Long;
            return BuiltInTypes.UInt;
        }

        // Everything else (byte, sbyte, short, ushort, int, char) promotes to int
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
            GetBinaryOperandDiagnosticSpan(expr, leftIsWrong, rightIsWrong);
        var opText = GetBinaryOperatorText(expr.Operator);
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
        var opText = unary.Operator switch
        {
            UnaryOperator.Negate => "-",
            UnaryOperator.Not => "!",
            UnaryOperator.BitwiseNot => "~",
            UnaryOperator.PreIncrement or UnaryOperator.PostIncrement => "++",
            UnaryOperator.PreDecrement or UnaryOperator.PostDecrement => "--",
            UnaryOperator.IndexFromEnd => "^",
            _ => "operator"
        };

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

    // Scope management
    private void PushScope(Scope scope)
    {
        PushScope(scope, 0, 0);
    }

    private void PushScope(Scope scope, int startLine, int startColumn)
    {
        _scopes.Push(scope);
        var parentId = _semanticScopeIds.Count > 0 ? _semanticScopeIds.Peek() : -1;
        var scopeId = _semanticModel.OpenScope(parentId, startLine, startColumn);
        _semanticScopeIds.Push(scopeId);
    }

    private void PopScope()
    {
        _scopes.Pop();
        if (_semanticScopeIds.Count > 0)
        {
            var scopeId = _semanticScopeIds.Pop();
            _semanticModel.CloseScope(scopeId, _currentLine, int.MaxValue);
        }
    }

    /// <summary>
    /// Record a variable in the current semantic scope (for position-aware lookups).
    /// </summary>
    private void RecordVariableInCurrentScope(string name, TypeInfo type)
    {
        if (_semanticScopeIds.Count > 0)
        {
            _semanticModel.RecordScopedVariable(_semanticScopeIds.Peek(), name, type);
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
        if (_semanticScopeIds.Count > 0)
        {
            _semanticModel.RecordScopedFunction(_semanticScopeIds.Peek(), name, type);
        }
        else
        {
            _semanticModel.RecordFunction(name, type);
        }
    }

    private int GetDeclarationNameColumn(string name, int line, int fallbackColumn)
    {
        if (string.IsNullOrWhiteSpace(name))
            return fallbackColumn;

        var sourceText = _sourceLines != null
            ? _sourceText
            : TryGetProjectSourceText(_currentFilePath);

        return FindIdentifierNameColumn(sourceText, name, line, fallbackColumn);
    }

    private string? TryGetProjectSourceText(string? filePath)
    {
        if (filePath == null)
            return null;

        var fullPath = Path.GetFullPath(filePath);
        return _projectSourceTexts.TryGetValue(fullPath, out var sourceText)
            ? sourceText
            : null;
    }

    private static int FindIdentifierNameColumn(string? sourceText, string name, int line, int fallbackColumn)
    {
        if (sourceText == null)
            return fallbackColumn;

        if (CodeIntelligenceSourceTextKernels.TryFindIdentifierNameColumn(
            sourceText,
            name,
            line,
            fallbackColumn,
            out var dogfoodColumn))
        {
            return dogfoodColumn;
        }

        return fallbackColumn;
    }

    private static (int Line, int Column) GetParameterDeclarationPosition(
        Parameter parameter,
        int fallbackLine,
        int fallbackColumn)
        => (
            parameter.Line > 0 ? parameter.Line : fallbackLine,
            parameter.Column > 0 ? parameter.Column : fallbackColumn);

    private void DeclareSymbol(
        string name,
        TypeInfo type,
        int line,
        int column,
        string? declarationKind = null,
        bool recordBindingDeclaration = true)
    {
        var currentScope = _scopes.Peek();
        var nameColumn = GetDeclarationNameColumn(name, line, column);
        var shouldRecordBindingDeclaration = recordBindingDeclaration;
        if (currentScope.Symbols.TryGetValue(name, out var existing))
        {
            // Allow function overloading: merge into NSharpMethodGroupInfo
            // Only if parameter signatures differ (same name + same params = duplicate error)
            if (type is FunctionTypeInfo newFunc && newFunc.Declaration != null)
            {
                if (existing is FunctionTypeInfo existingFunc && existingFunc.Declaration != null)
                {
                    if (HasDistinctParameterSignature(newFunc.Declaration, new[] { existingFunc.Declaration }))
                    {
                        // Upgrade single function to method group
                        currentScope.Symbols[name] = new NSharpMethodGroupInfo(
                            new List<FunctionDeclaration> { existingFunc.Declaration, newFunc.Declaration });
                        if (shouldRecordBindingDeclaration)
                        {
                            var kind = declarationKind ?? TypeInfoToDeclarationKind(type);
                            var decl = new SymbolDeclaration(name, _currentFilePath, line, nameColumn, kind);
                            _bindingMap.RecordDeclaration(decl);
                        }
                        return;
                    }
                }

                if (existing is NSharpMethodGroupInfo group)
                {
                    if (HasDistinctParameterSignature(newFunc.Declaration, group.Declarations))
                    {
                        // Add to existing method group
                        group.Declarations.Add(newFunc.Declaration);
                        if (shouldRecordBindingDeclaration)
                        {
                            var kind = declarationKind ?? TypeInfoToDeclarationKind(type);
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

            var kind = declarationKind ?? TypeInfoToDeclarationKind(type);
            if (shouldRecordBindingDeclaration)
            {
                // Record declaration in binding map for semantic references
                var decl = new SymbolDeclaration(name, _currentFilePath, line, nameColumn, kind);
                _bindingMap.RecordDeclaration(decl);
                // Also record the declaration location in the scope for later lookup
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
        if (_scopes.Count == 0)
            return;

        // Discards and underscore-prefixed names are intentionally ignored (mirrors NL020).
        if (name == "_" || name.StartsWith("_", StringComparison.Ordinal))
            return;

        var currentScope = _scopes.Peek();

        // Only locals and parameters can shadow; functions, types, type parameters,
        // "this"/"value", and members declared in type scopes are out of scope.
        if (currentScope.Kind is not (ScopeKind.Function or ScopeKind.Block))
            return;
        if (!IsValueBinding(currentScope, name, type))
            return;

        // Walk enclosing scopes outward. Stop at the first non-local scope boundary
        // (class/struct/record/interface/global) — members there are not "outer locals".
        var sawCurrent = false;
        foreach (var scope in _scopes)
        {
            if (!sawCurrent)
            {
                // Skip the scope we are declaring into.
                sawCurrent = ReferenceEquals(scope, currentScope);
                continue;
            }

            if (scope.Kind is not (ScopeKind.Function or ScopeKind.Block))
                return; // reached a type/global boundary — no shadowing of an outer local

            if (scope.Symbols.TryGetValue(name, out var outerType) && IsValueBinding(scope, name, outerType))
            {
                Error(
                    ErrorCode.ShadowedDeclaration,
                    $"'{name}' shadows an existing '{name}' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs",
                    line,
                    nameColumn,
                    ErrorSuggestions.GetSuggestion(ErrorCode.ShadowedDeclaration, name),
                    Math.Max(1, name.Length));
                return;
            }
        }
    }

    /// <summary>
    /// True when the named symbol in <paramref name="scope"/> is a local variable or
    /// parameter binding (not a function, method group, type, or type parameter).
    /// </summary>
    private static bool IsValueBinding(Scope scope, string name, TypeInfo type)
    {
        // "this" is the receiver; "value" is the implicit property-setter parameter.
        // Excluding "value" avoids false shadowing reports for locals named `value`
        // inside setters (a common, harmless pattern).
        if (name is "this" or "value")
            return false;
        if (scope.Types.ContainsKey(name))
            return false; // type parameter
        return type is not (FunctionTypeInfo or NSharpMethodGroupInfo);
    }

    /// <summary>
    /// Checks if a new function declaration has a distinct parameter signature
    /// from all existing declarations (for overload validation).
    /// </summary>
    private static bool HasDistinctParameterSignature(
        FunctionDeclaration newDecl,
        IEnumerable<FunctionDeclaration> existingDecls)
    {
        foreach (var existing in existingDecls)
        {
            if (ParameterSignaturesMatch(newDecl, existing))
                return false; // Duplicate signature found
        }
        return true;
    }

    /// <summary>
    /// Compares two function declarations' parameter signatures (types only, not names).
    /// Returns true if they have the same parameter types.
    /// </summary>
    private static bool ParameterSignaturesMatch(FunctionDeclaration a, FunctionDeclaration b)
    {
        if (a.Parameters.Count != b.Parameters.Count)
            return false;

        for (int i = 0; i < a.Parameters.Count; i++)
        {
            if (GetParameterTypeSignature(a.Parameters[i].Type) != GetParameterTypeSignature(b.Parameters[i].Type))
                return false;
        }

        return true;
    }

    private static string GetParameterTypeSignature(TypeReference typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => simple.Name,
            ArrayTypeReference array => $"{GetParameterTypeSignature(array.ElementType)}[]",
            GenericTypeReference generic => $"{generic.Name}<{string.Join(",", generic.TypeArguments.Select(GetParameterTypeSignature))}>",
            NullableTypeReference nullable => $"{GetParameterTypeSignature(nullable.InnerType)}?",
            UnionTypeReference union => string.Join("|", union.Arms.Select(GetParameterTypeSignature)),
            TupleTypeReference tuple => $"({string.Join(",", tuple.Elements.Select(element => GetParameterTypeSignature(element.Type)))})",
            FunctionTypeReference function => $"({string.Join(",", function.ParameterTypes.Select(GetParameterTypeSignature))})->{GetParameterTypeSignature(function.ReturnType)}",
            ByRefTypeReference byRef => $"&{GetParameterTypeSignature(byRef.InnerType)}",
            _ => typeRef.ToString() ?? "unknown"
        };
    }

    private void DeclareType(string name, TypeInfo type, int line, int column)
    {
        var currentScope = _scopes.Peek();
        var nameColumn = GetDeclarationNameColumn(name, line, column);
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
            {
                _typeDeclarationFiles[name] = _currentFilePath;
            }

            // Record type declaration in binding map
            var kind = TypeInfoToDeclarationKind(type);
            var decl = new SymbolDeclaration(name, _currentFilePath, line, nameColumn, kind);
            _bindingMap.RecordDeclaration(decl);
            currentScope.RecordDeclarationLocation(name, _currentFilePath, line, nameColumn, kind);
        }
    }

    private static string TypeInfoToDeclarationKind(TypeInfo type) => type switch
    {
        ClassTypeInfo => "class",
        StructTypeInfo => "struct",
        RecordTypeInfo => "record",
        SoaRecordTypeInfo => "soaRecord",
        InterfaceTypeInfo => "interface",
        EnumTypeInfo => "enum",
        UnionTypeInfo => "union",
        FunctionTypeInfo => "function",
        NSharpMethodGroupInfo => "function",
        _ => "variable"
    };

    // Operator overload validation
    private void ValidateParamsParameters(List<Parameter> parameters, int line, int column)
    {
        // Find params parameters
        for (int i = 0; i < parameters.Count; i++)
        {
            var param = parameters[i];
            if (param.Modifier == Ast.ParameterModifier.Params)
            {
                var (paramLine, paramColumn, paramLength) = GetParameterDiagnosticSpan(param, line, column);

                // params must be last parameter
                if (i != parameters.Count - 1)
                {
                    Error(
                        ErrorCode.ParamsNotLast,
                        "A 'params' parameter must come last in the parameter list — move it to the end",
                        paramLine,
                        paramColumn,
                        length: paramLength);
                }

                // C# 13: params can be array, Span<T>, ReadOnlySpan<T>, or collection types
                if (!IsValidParamsType(param.Type))
                {
                    Error(
                        ErrorCode.InvalidParameter,
                        $"A 'params' parameter must be an array or collection type — '{TranspileTypeReference(param.Type)}' is not a valid params type",
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

            // Skip 'this' and 'params' parameters - they have special rules
            if (param.IsThis || param.Modifier == Ast.ParameterModifier.Params)
                continue;

            bool hasDefault = param.DefaultValue != null;

            if (hasDefault)
            {
                foundOptional = true;
                var reportedSoaDefaultParameterDiagnostic = ReportSoaDefaultParameterValueIfNeeded(param);

                // Validate that default value is a compile-time constant
                if (!reportedSoaDefaultParameterDiagnostic && !IsValidDefaultValue(param.DefaultValue!))
                {
                    var (defaultLine, defaultColumn, defaultLength) = GetExpressionDiagnosticSpan(param.DefaultValue!);
                    Error(ErrorCode.InvalidDefaultParameterValue,
                        $"The default value for '{param.Name}' must be something the compiler can evaluate — use a literal, null, or a simple constant",
                        defaultLine, defaultColumn, length: defaultLength);
                }
            }
            else
            {
                // Required parameter found after optional parameter
                if (foundOptional)
                {
                    var (paramLine, paramColumn, paramLength) = GetParameterDiagnosticSpan(param, line, column);
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

        var parameterType = ResolveDeclaredType(parameter.Type);
        if (ResolveTypeAlias(GetNonNullableType(parameterType)) is not SoaRecordTypeInfo soaRecordType)
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
        var (line, column, length) = GetExpressionDiagnosticSpan(parameter.DefaultValue);
        Error(
            ErrorCode.InvalidDefaultParameterValue,
            $"SoA table '{tableName}' cannot be used as a default parameter value — optional parameter defaults are metadata constants, but SoA tables must be constructed or wrapped at runtime",
            line,
            column,
            $"Use an overload that creates the table with 'new {tableName}(capacity)' or accepts a '{tableName}.wrap(...)' value from the caller.",
            length);
        return true;
    }

    private static (int Line, int Column, int Length) GetParameterDiagnosticSpan(
        Parameter parameter,
        int fallbackLine,
        int fallbackColumn)
    {
        var line = parameter.Line > 0 ? parameter.Line : fallbackLine;
        var column = parameter.Column > 0 ? parameter.Column : fallbackColumn;
        return (line, column, Math.Max(1, parameter.Name.Length));
    }

    private bool IsValidDefaultValue(Expression expr)
    {
        return expr switch
        {
            IntLiteralExpression => true,
            FloatLiteralExpression => true,
            CharLiteralExpression => true,
            BoolLiteralExpression => true,
            StringLiteralExpression => true,
            NullLiteralExpression => true,

            UnaryExpression unary when IsValidDefaultValue(unary.Operand) => true,
            BinaryExpression binary when IsValidDefaultValue(binary.Left) && IsValidDefaultValue(binary.Right) => true,
            ArrayLiteralExpression arrayLit => arrayLit.Elements.All(IsValidDefaultValue),

            _ => false
        };
    }

    private bool IsValidParamsType(TypeReference typeRef)
    {
        // Arrays are always valid (original C# behavior)
        if (typeRef is ArrayTypeReference)
            return true;

        // Check for generic types (Span<T>, ReadOnlySpan<T>, List<T>, IEnumerable<T>, etc.)
        if (typeRef is GenericTypeReference generic)
        {
            var typeName = generic.Name;

            // C# 13 specifically allows these types
            var validTypes = new HashSet<string>
            {
                "Span", "ReadOnlySpan",
                "IEnumerable", "IReadOnlyCollection", "IReadOnlyList",
                "ICollection", "IList",
                "List", "HashSet", "Queue", "Stack",
                "ArraySegment", "Memory", "ReadOnlyMemory"
            };

            return validTypes.Contains(typeName);
        }

        return false;
    }

    private string TranspileTypeReference(TypeReference typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => simple.Name,
            ArrayTypeReference array => TranspileTypeReference(array.ElementType) + "[]",
            GenericTypeReference generic => $"{generic.Name}<{string.Join(", ", generic.TypeArguments.Select(TranspileTypeReference))}>",
            NullableTypeReference nullable => TranspileTypeReference(nullable.InnerType) + "?",
            UnionTypeReference union => string.Join(" | ", union.Arms.Select(TranspileTypeReference)),
            ByRefTypeReference byRef => $"&{TranspileTypeReference(byRef.InnerType)}",
            _ => typeRef.ToString() ?? "unknown"
        };
    }

    private void ValidateOperatorOverload(FunctionDeclaration func)
    {
        var (operatorKeywordLine, operatorKeywordColumn, operatorKeywordLength) = GetSourceSpanDiagnosticSpan(
            func.OperatorKeywordSpan,
            func.Line,
            func.Column,
            "operator".Length);
        var (operatorSymbolLine, operatorSymbolColumn, operatorSymbolLength) = GetSourceSpanDiagnosticSpan(
            func.OperatorSymbolSpan,
            func.Line,
            func.Column,
            func.OperatorSymbol?.Length ?? 1);

        // Operator overloads must be static
        if (!func.Modifiers.HasFlag(Modifiers.Static))
        {
            Error(
                ErrorCode.InvalidOperatorOverload,
                "Operator overloads must be declared 'static' — they don't belong to a specific instance",
                operatorKeywordLine,
                operatorKeywordColumn,
                length: operatorKeywordLength);
        }

        // Get expected parameter count
        var expectedParams = func.OperatorSymbol switch
        {
            // Unary operators
            "!" or "~" or "++" or "--" or "true" or "false" => 1,
            // Binary operators
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

        // Note: +/- can be both unary and binary, so we allow 1 or 2 parameters
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

    // Error reporting
    private void Error(string message, int line, int column)
    {
        Error(ErrorCode.InvalidSyntax, message, line, column);
    }

    private void Error(ErrorCode code, string message, int line, int column, string? suggestion = null, int length = 0)
    {
        CompilerError error;

        var sourceSnippet = GetSourceSnippet(line);
        if (sourceSnippet != null && _currentFilePath != null)
        {
            error = CompilerError.WithSnippet(
                code,
                message,
                _currentFilePath,
                line,
                column,
                sourceSnippet,
                length,
                suggestion ?? ErrorSuggestions.GetSuggestion(code),
                ErrorSeverity.Error
            );
        }
        else
        {
            error = CompilerError.Create(code, message, line, column, ErrorSeverity.Error) with
            {
                FileName = _currentFilePath,
                Length = Math.Max(1, length),
                Suggestion = suggestion ?? ErrorSuggestions.GetSuggestion(code)
            };
        }

        _errors.Add(error);
    }

    private void Warning(string message, int line, int column)
    {
        Warning(ErrorCode.UnusedVariable, message, line, column);
    }

    private void Warning(ErrorCode code, string message, int line, int column, string? suggestion = null, int length = 0)
    {
        CompilerError warning;

        var sourceSnippet = GetSourceSnippet(line);
        if (sourceSnippet != null && _currentFilePath != null)
        {
            warning = CompilerError.WithSnippet(
                code,
                message,
                _currentFilePath,
                line,
                column,
                sourceSnippet,
                length,
                suggestion ?? ErrorSuggestions.GetSuggestion(code),
                ErrorSeverity.Warning
            );
        }
        else
        {
            warning = CompilerError.Create(code, message, line, column, ErrorSeverity.Warning) with
            {
                FileName = _currentFilePath,
                Length = Math.Max(1, length),
                Suggestion = suggestion ?? ErrorSuggestions.GetSuggestion(code)
            };
        }

        _errors.Add(warning);
    }

    private string? GetSourceSnippet(int line)
    {
        if (line <= 0)
            return null;

        if (_sourceText != null &&
            CodeIntelligenceSourceTextKernels.TryExtractSourceLine(_sourceText, line, out var dogfoodLine))
        {
            return dogfoodLine;
        }

        return _sourceLines != null && line <= _sourceLines.Length
            ? _sourceLines[line - 1]
            : null;
    }

    // Package validation
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

        // First character must be letter or underscore
        if (!char.IsLetter(name[0]) && name[0] != '_')
            return false;

        // Rest must be letters, digits, or underscores
        for (int i = 1; i < name.Length; i++)
        {
            if (!char.IsLetterOrDigit(name[i]) && name[i] != '_')
                return false;
        }

        return true;
    }

    // Import processing
    private void ProcessImports(List<Statement> imports)
    {
        if (_currentFilePath == null || _projectRoot == null)
        {
            // If file paths not provided, skip import processing
            // This happens when Analyze() is called without paths (e.g., in tests)
            return;
        }

        var fileResolver = new FileResolver(_projectRoot, _currentFilePath);

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
        // Resolve the file path
        var resolvedPath = ResolveFileImportPath(resolver, import.Path, out var errorMessage);
        if (resolvedPath == null)
        {
            // Use ErrorMessageBuilder for better error message
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

        // Check for self-import (file importing itself)
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

        // Parse the imported file
        CompilationUnit? importedUnit = null;
        string? importedSource = null;
        try
        {
            importedSource = TryGetProjectSourceText(resolvedPath) ?? System.IO.File.ReadAllText(resolvedPath);
            var lexer = new Lexer(importedSource, resolvedPath);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, resolvedPath, importedSource);  // Pass source code
            var parseResult = parser.ParseCompilationUnit();
            importedUnit = parseResult.CompilationUnit;

            // Report parse errors
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

        // Check imported file's own file imports for cycles back to the current file (A→B→A detection)
        if (importedUnit.FileImports.Count > 0 && _projectRoot != null && _currentFilePath != null)
        {
            var currentNormalized = Path.GetFullPath(_currentFilePath);
            var importedFileResolver = new FileResolver(_projectRoot, resolvedPath);
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

        // Extract public symbols from the imported file
        var symbols = ExtractPublicSymbols(importedUnit, resolvedPath, importedSource);

        // Add symbols to scope
        if (import.Alias != null)
        {
            // With alias: symbols accessed via Alias.Symbol
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
                if (IsTypeDeclarationKind(symbol.Declaration.Kind))
                {
                    _typeDeclarationFiles[symbol.Name] = symbol.Declaration.File!;
                }
            }
        }
        else
        {
            // Without alias: symbols directly available
            foreach (var symbol in symbols)
            {
                // Track collision detection
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

                // Add to global scope
                var globalScope = _scopes.Last(); // Global scope is at the bottom of stack
                if (symbol.Declaration.Kind == "function")
                {
                    globalScope.Symbols[symbol.Name] = symbol.Type;
                }
                else
                {
                    globalScope.Types[symbol.Name] = symbol.Type;
                    _semanticModel.RecordType(symbol.Name, symbol.Type);
                    if (IsTypeDeclarationKind(symbol.Declaration.Kind))
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
        if (_projectSourceTexts.ContainsKey(resolvedPath) || System.IO.File.Exists(resolvedPath))
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

    /// <summary>
    /// Try to resolve a symbol from the project-level auto-discovered symbols.
    /// This is the last-resort fallback after local scope, explicit imports, and external types.
    /// </summary>
    private bool TryResolveProjectSymbol(string name, int line, int column, out TypeInfo type)
    {
        type = BuiltInTypes.Unknown;

        if (!_projectSymbols.TryGetValue(name, out var candidates))
            return false;

        // Filter out symbols from the current file (already in scope from local declarations)
        var externalCandidates = _currentFilePath != null
            ? candidates.Where(c => !string.Equals(c.SourceFile, _currentFilePath, StringComparison.OrdinalIgnoreCase)).ToList()
            : candidates;

        if (externalCandidates.Count == 0)
            return false;

        // Prefer symbols made visible by the current package/namespace or its imports before
        // falling back to the historical project-wide ambiguity behavior. This keeps
        // unrelated packages with the same local name from changing diagnostics for an
        // explicitly imported package.
        var currentNamespace = GetUnitNamespace(_compilationUnit);
        var visibleCandidates = externalCandidates
            .Where(candidate => IsProjectSymbolInResolutionScope(candidate, currentNamespace))
            .ToList();
        if (visibleCandidates.Count > 0)
        {
            externalCandidates = visibleCandidates;
        }

        if (externalCandidates.Count > 1)
        {
            // Multiple candidates from different files — ambiguous
            var sources = string.Join(", ", externalCandidates.Select(c => Path.GetFileName(c.SourceFile)));
            Error($"'{name}' is defined in multiple files ({sources}) — add an explicit file import to tell me which one you mean", line, column);
            return false;
        }

        var resolved = externalCandidates[0];
        if (!resolved.IsExported && IsCrossPackageFile(resolved.SourceFile))
        {
            ReportInaccessibleProjectSymbol(resolved, line, column);
            type = new UnknownTypeInfo(UnknownKind.ErrorRecovery);
            return true;
        }

        type = resolved.Type;

        // Track the namespace for project-wide semantic lookup.
        if (resolved.Namespace != null)
        {
            // Get the current file's namespace to compare
            var currentNs = GetUnitNamespace(_compilationUnit);
            if (currentNs == null || !string.Equals(resolved.Namespace, currentNs, StringComparison.Ordinal))
            {
                _autoResolvedNamespaces.Add(resolved.Namespace);
            }
        }

        // Record binding for semantic features (def/refs)
        _bindingMap.RecordDeclaration(resolved.Declaration);
        if (line > 0)
        {
            _bindingMap.RecordBinding(_currentFilePath, line, column, name.Length, resolved.Declaration);
        }

        // Ensure the type declaration file is tracked so that subsequent member access
        // (e.g. service.GetPeople()) can resolve the member to the correct source file.
        // This must happen unconditionally — not only when a namespace is present.
        if (resolved.Declaration.File != null && IsTypeDeclarationKind(resolved.Declaration.Kind))
        {
            _typeDeclarationFiles[name] = resolved.Declaration.File;
        }

        return true;
    }

    private bool IsProjectSymbolInResolutionScope(ProjectSymbolInfo candidate, string? currentNamespace)
    {
        if (string.Equals(candidate.Namespace, currentNamespace, StringComparison.Ordinal))
        {
            return true;
        }

        return candidate.Namespace != null && _usingNamespaces.Contains(candidate.Namespace);
    }

    private void RegisterNamespaceImport(string namespaceName, string? alias, int line, int column)
    {
        var importDirective = new ImportDirective(namespaceName, alias, line, column);

        // Load referenced assemblies before validating the namespace so imports
        // from project dependencies can be recognized.
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

        var importedType = TryResolveExactExternalType(namespaceName);
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

    private Type? TryResolveExactExternalType(string fullName)
    {
        if (_externalTypeCache.TryGetValue(fullName, out var cachedType))
        {
            return cachedType;
        }

        // Search MLC assemblies for the exact fully-qualified type name
        foreach (var assembly in _mlcAssemblies)
        {
            try
            {
                var resolved = assembly.GetType(fullName, throwOnError: false, ignoreCase: false);
                if (resolved != null)
                {
                    _externalTypeCache[fullName] = resolved;
                    return resolved;
                }
            }
            catch (Exception ex)
            {
                RecordReferenceLoadFailure(assembly.GetName().Name ?? assembly.ToString(), ex);
                continue;
            }
        }

        return null;
    }

    private bool NamespaceExists(string namespaceName)
    {
        if (ProjectNamespaceExists(namespaceName))
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
            try
            {
                exportedTypes = assembly.GetExportedTypes();
            }
            catch (ReflectionTypeLoadException ex)
            {
                exportedTypes = ex.Types.Where(t => t != null).Cast<Type>();
            }
            catch
            {
                continue;
            }

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

    private bool ProjectNamespaceExists(string namespaceName)
    {
        if (string.IsNullOrWhiteSpace(_projectRoot) || !Directory.Exists(_projectRoot))
        {
            return false;
        }

        var projectNamespaces = GetProjectNamespaces(_projectRoot);
        return projectNamespaces.Contains(namespaceName);
    }

    private HashSet<string> GetProjectNamespaces(string projectRoot)
    {
        if (_projectNamespaceCache.TryGetValue(projectRoot, out var cachedNamespaces))
        {
            return cachedNamespaces;
        }

        var namespaces = new HashSet<string>(StringComparer.Ordinal);

        foreach (var filePath in ProjectConfig.EnumerateSourceFiles(projectRoot))
        {
            try
            {
                var source = File.ReadAllText(filePath);
                var lexer = new Lexer(source, filePath);
                var parser = new Parser(lexer.Tokenize(), filePath, source);
                var parseResult = parser.ParseCompilationUnit();
                var declaredNamespace = GetUnitNamespace(parseResult.CompilationUnit);
                if (!string.IsNullOrWhiteSpace(declaredNamespace))
                {
                    namespaces.Add(declaredNamespace);
                }
            }
            catch
            {
                // Namespace validation is best-effort; syntax issues will be reported elsewhere.
            }
        }

        _projectNamespaceCache[projectRoot] = namespaces;
        return namespaces;
    }

    private string? GetNamespaceForFile(string? filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath))
        {
            return null;
        }

        var fullPath = Path.GetFullPath(filePath);
        if (_projectFileNamespaceCache.TryGetValue(fullPath, out var cachedNamespace))
        {
            return cachedNamespace;
        }

        if (!File.Exists(fullPath))
        {
            _projectFileNamespaceCache[fullPath] = null;
            return null;
        }

        try
        {
            var source = File.ReadAllText(fullPath);
            var lexer = new Lexer(source, fullPath);
            var parser = new Parser(lexer.Tokenize(), fullPath, source);
            var parseResult = parser.ParseCompilationUnit();
            var declaredNamespace = GetUnitNamespace(parseResult.CompilationUnit);
            _projectFileNamespaceCache[fullPath] = declaredNamespace;
            return declaredNamespace;
        }
        catch
        {
            _projectFileNamespaceCache[fullPath] = null;
            return null;
        }
    }

    private static string? GetUnitNamespace(CompilationUnit? unit)
    {
        return unit?.Package?.Name ?? unit?.Namespace?.Name;
    }

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

        var currentNamespace = GetUnitNamespace(_compilationUnit) ?? GetNamespaceForFile(currentPath);
        var declarationNamespace = GetNamespaceForFile(declarationPath);
        return !string.Equals(currentNamespace, declarationNamespace, StringComparison.Ordinal);
    }

    private static bool IsExportedByCasingOrModifier(string name, Declaration declaration)
    {
        return VisibilityConventions.IsExportedIdentifier(name, GetDeclarationModifiers(declaration));
    }

    private bool ReportInaccessibleProjectSymbol(ProjectSymbolInfo symbol, int line, int column)
    {
        Error(
            ErrorCode.InaccessibleMember,
            $"'{symbol.Name}' is not exported from package/namespace '{symbol.Namespace ?? "<global>"}' — use PascalCase for cross-package visibility or keep camelCase names inside the declaring package",
            line,
            column,
            length: Math.Max(1, symbol.Name.Length));
        return true;
    }

    private bool ReportInaccessibleMember(string memberName, string? declarationFile, int line, int column)
    {
        var declaringNamespace = GetNamespaceForFile(declarationFile) ?? "<global>";
        Error(
            ErrorCode.InaccessibleMember,
            $"'{memberName}' is not exported from package/namespace '{declaringNamespace}' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package",
            line,
            column,
            length: Math.Max(1, memberName.Length));
        return true;
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
            var name = decl switch
            {
                ClassDeclaration c => c.Name,
                StructDeclaration s => s.Name,
                RecordDeclaration r => r.Name,
                SoaRecordDeclaration soa => soa.Name,
                InterfaceDeclaration i => i.Name,
                UnionDeclaration u => u.Name,
                EnumDeclaration e => e.Name,
                TypeAliasDeclaration a => a.Name,
                NewtypeDeclaration n => n.Name,
                FunctionDeclaration f => f.Name,
                _ => null
            };

            if (name != null && IsExportedDeclaration(decl, name))
            {
                var typeInfo = decl switch
                {
                    ClassDeclaration c => new ClassTypeInfo(c) as TypeInfo,
                    StructDeclaration s => new StructTypeInfo(s),
                    RecordDeclaration r => new RecordTypeInfo(r),
                    SoaRecordDeclaration soa => new SoaRecordTypeInfo(soa),
                    InterfaceDeclaration i => new InterfaceTypeInfo(i),
                    UnionDeclaration u => new UnionTypeInfo(u),
                    EnumDeclaration e => new EnumTypeInfo(e),
                    TypeAliasDeclaration a => new AliasTypeInfo(a.Type),
                    NewtypeDeclaration n => new NewtypeInfo(n.Name, n.UnderlyingType),
                    FunctionDeclaration f => CreateFunctionTypeInfo(f),
                    _ => null
                };

                if (typeInfo != null)
                {
                    symbols.Add(new ImportedSymbolInfo(
                        name,
                        typeInfo,
                        new SymbolDeclaration(
                            name,
                            filePath,
                            decl.Line,
                            FindIdentifierNameColumn(sourceText, name, decl.Line, decl.Column),
                            GetDeclarationKind(decl))));
                }
            }
        }

        return symbols;
    }

    private static bool IsTypeDeclarationKind(string kind) =>
        kind is "class" or "struct" or "record" or "soaRecord" or "interface" or "enum" or "union" or "typeAlias" or "newtype";

    private static bool IsExportedDeclaration(Declaration declaration, string name)
    {
        return VisibilityConventions.IsExportedIdentifier(name, GetDeclarationModifiers(declaration));
    }

    private static Modifiers GetDeclarationModifiers(Declaration declaration)
    {
        return declaration switch
        {
            ClassDeclaration c => c.Modifiers,
            StructDeclaration s => s.Modifiers,
            RecordDeclaration r => r.Modifiers,
            SoaRecordDeclaration soa => soa.Modifiers,
            InterfaceDeclaration i => i.Modifiers,
            UnionDeclaration u => u.Modifiers,
            EnumDeclaration e => e.Modifiers,
            FunctionDeclaration f => f.Modifiers,
            FieldDeclaration f => f.Modifiers,
            PropertyDeclaration p => p.Modifiers,
            ConstructorDeclaration c => c.Modifiers,
            IndexerDeclaration i => i.Modifiers,
            _ => Modifiers.None
        };
    }

    /// <summary>
    /// Extract all public (PascalCase) symbols from a compilation unit for project-level auto-discovery.
    /// Static method that doesn't require analyzer state — used by MultiFileCompiler.
    /// </summary>
    public static List<ProjectSymbolInfo> ExtractProjectSymbols(CompilationUnit unit, string filePath, string? sourceText = null)
    {
        var symbols = new List<ProjectSymbolInfo>();
        var ns = GetUnitNamespace(unit);

        foreach (var decl in unit.Declarations)
        {
            var name = decl switch
            {
                ClassDeclaration c => c.Name,
                StructDeclaration s => s.Name,
                RecordDeclaration r => r.Name,
                SoaRecordDeclaration soa => soa.Name,
                InterfaceDeclaration i => i.Name,
                UnionDeclaration u => u.Name,
                EnumDeclaration e => e.Name,
                TypeAliasDeclaration a => a.Name,
                NewtypeDeclaration n => n.Name,
                FunctionDeclaration f => f.Name,
                _ => null
            };

            if (name != null && !string.IsNullOrEmpty(name))
            {
                var typeInfo = decl switch
                {
                    ClassDeclaration c => new ClassTypeInfo(c) as TypeInfo,
                    StructDeclaration s => new StructTypeInfo(s),
                    RecordDeclaration r => new RecordTypeInfo(r),
                    SoaRecordDeclaration soa => new SoaRecordTypeInfo(soa),
                    InterfaceDeclaration i => new InterfaceTypeInfo(i),
                    UnionDeclaration u => new UnionTypeInfo(u),
                    EnumDeclaration e => new EnumTypeInfo(e),
                    TypeAliasDeclaration a => new AliasTypeInfo(a.Type),
                    NewtypeDeclaration n => new NewtypeInfo(n.Name, n.UnderlyingType),
                    FunctionDeclaration f => new FunctionTypeInfo(f)
                    {
                        ParameterTypes = new List<TypeInfo>(), // Resolved during analysis
                        ReturnType = BuiltInTypes.Void
                    },
                    _ => null
                };

                if (typeInfo != null)
                {
                    symbols.Add(new ProjectSymbolInfo(
                        name,
                        typeInfo,
                        new SymbolDeclaration(
                            name,
                            filePath,
                            decl.Line,
                            FindIdentifierNameColumn(sourceText, name, decl.Line, decl.Column),
                            GetDeclarationKind(decl)),
                        filePath,
                        ns,
                        IsExportedByCasingOrModifier(name, decl)));
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
            if (sourceSnippet != null && _currentFilePath != null)
            {
                var error = CompilerError.WithSnippet(
                    ErrorCode.ImportCollision,
                    message,
                    _currentFilePath,
                    duplicate.Line,
                    duplicate.Column,
                    sourceSnippet,
                    duplicate.Length,
                    suggestion,
                    ErrorSeverity.Error) with
                {
                    HumanExplanation = humanExplanation,
                    ContextualHint = contextualHint,
                    DocsUrl = "https://docs.n-sharp.dev/errors/NL702"
                };

                _errors.Add(error);
                continue;
            }

            _errors.Add(CompilerError.Create(
                ErrorCode.ImportCollision,
                message,
                duplicate.Line,
                duplicate.Column,
                ErrorSeverity.Error) with
            {
                FileName = _currentFilePath ?? duplicate.SourcePath,
                Length = Math.Max(1, duplicate.Length),
                Suggestion = suggestion,
                HumanExplanation = humanExplanation,
                ContextualHint = contextualHint,
                DocsUrl = "https://docs.n-sharp.dev/errors/NL702"
            });
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
        try
        {
            var fullPath = Path.GetFullPath(assemblyPath);
            _metadataResolver?.AddSearchDirectory(Path.GetDirectoryName(fullPath)!);

            if (IsMetadataAssemblyPathAlreadyLoaded(fullPath))
            {
                return;
            }

            AssemblyName assemblyName;
            try
            {
                assemblyName = AssemblyName.GetAssemblyName(fullPath);
            }
            catch (BadImageFormatException)
            {
                // Non-managed assets are irrelevant for metadata analysis.
                return;
            }

            if (IsMetadataAssemblyAlreadyLoaded(assemblyName))
            {
                return;
            }

            var assembly = _mlc.LoadFromAssemblyPath(fullPath);
            RegisterMetadataAssembly(assembly);
        }
        catch (FileLoadException ex) when (IsDuplicateMetadataAssemblyLoad(ex))
        {
            // MetadataLoadContext rejects duplicate identities; suppress to keep machine-readable
            // output like `nlc check --json` clean when ResolveReferences returns overlapping facades.
        }
        catch (Exception ex)
        {
            RecordReferenceLoadFailure(assemblyPath, ex);
            Console.Error.WriteLine($"Warning: Could not load assembly from {assemblyPath}: {ex.Message}");
        }
    }

    /// <summary>
    /// Load a .NET assembly by name (e.g., "System.Runtime") for type resolution (metadata-only via MLC)
    /// </summary>
    public void LoadReferencedAssemblyByName(string assemblyName)
    {
        if (_mlc == null) return;
        try
        {
            if (IsMetadataAssemblyAlreadyLoaded(assemblyName))
            {
                return;
            }

            var assembly = _mlc.LoadFromAssemblyName(assemblyName);
            RegisterMetadataAssembly(assembly);
        }
        catch
        {
            // Assembly not found — the MLC resolver already searched all configured paths
        }
    }

    private void RegisterMetadataAssembly(Assembly assembly)
    {
        if (_mlcAssemblies.Any(loadedAssembly =>
        {
            try
            {
                return AssemblyName.ReferenceMatchesDefinition(loadedAssembly.GetName(), assembly.GetName());
            }
            catch
            {
                return false;
            }
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
            try
            {
                return AssemblyName.ReferenceMatchesDefinition(loadedAssembly.GetName(), assemblyName);
            }
            catch
            {
                return false;
            }
        });
    }

    private bool IsMetadataAssemblyAlreadyLoaded(string assemblyName)
    {
        return _mlcAssemblies.Any(loadedAssembly =>
        {
            try
            {
                return string.Equals(loadedAssembly.GetName().Name, assemblyName, StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        });
    }

    private bool IsMetadataAssemblyPathAlreadyLoaded(string assemblyPath)
    {
        var normalizedPath = Path.GetFullPath(assemblyPath);
        return _mlcAssemblies.Any(loadedAssembly =>
        {
            try
            {
                return string.Equals(
                    Path.GetFullPath(loadedAssembly.Location),
                    normalizedPath,
                    StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        });
    }

    private static bool IsDuplicateMetadataAssemblyLoad(FileLoadException exception)
    {
        return exception.Message.Contains("already loaded into this MetadataLoadContext", StringComparison.OrdinalIgnoreCase)
            || exception.Message.Contains("already loaded been loaded into this MetadataLoadContext", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Load system assemblies that are commonly used (initializes MetadataLoadContext)
    /// </summary>
    public void LoadSystemAssemblies()
    {
        // Initialize MetadataLoadContext with search directories
        _metadataResolver = new NSharpMetadataResolver();

        // Add .NET shared framework directories
        var runtimeDir = RuntimeEnvironment.GetRuntimeDirectory();
        _metadataResolver.AddSearchDirectory(runtimeDir);
        _metadataResolver.AddSearchDirectory(AppContext.BaseDirectory);

        // Find and add ASP.NET Core and other shared framework directories
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
                    // Add all version directories so transitive deps can be resolved
                    foreach (var versionDir in Directory.GetDirectories(fwPath).OrderByDescending(d => d))
                        _metadataResolver.AddSearchDirectory(versionDir);
                }
                break;
            }
        }

        // Create MetadataLoadContext
        _mlc = new MetadataLoadContext(_metadataResolver, "System.Runtime");

        // Load common assemblies — with MLC we need to be explicit about which assemblies
        // to load since there's no automatic type forwarding like runtime reflection
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

        // Initialize well-known types from MLC
        _wellKnownTypes = new WellKnownTypes(_mlc);
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            _mlc?.Dispose();
            _mlc = null;
            _wellKnownTypes = null;
            _mlcAssemblies.Clear();
            _disposed = true;
        }
    }

    /// <summary>
    /// Load assemblies from project configuration (References and Dependencies)
    /// </summary>
    public void LoadFromProjectConfig(ProjectConfig? config, string? projectDirectory = null)
    {
        if (config == null)
            return;

        projectDirectory ??= Environment.CurrentDirectory;

        // Load dependencies
        if (config.Dependencies != null && config.Dependencies.Count > 0)
        {
            foreach (var reference in config.Dependencies)
            {
                if (!string.IsNullOrWhiteSpace(reference.Nuget))
                {
                    _referencedPackageNames.Add(reference.Nuget);
                }

                try
                {
                    LoadProjectReference(reference, projectDirectory, config.TargetFramework);
                }
                catch (Exception ex)
                {
                    RecordReferenceLoadFailure(
                        reference.Nuget ?? reference.Project ?? reference.ToString() ?? "<unknown reference>",
                        ex);
                    Console.Error.WriteLine($"Warning: Failed to load reference: {ex.Message}");
                }
            }
        }

        // Load test dependencies
        if (config.TestDependencies != null && config.TestDependencies.Count > 0)
        {
            foreach (var dependency in config.TestDependencies.Where(r => r.Type == ReferenceType.NuGet))
            {
                if (!string.IsNullOrWhiteSpace(dependency.Nuget))
                {
                    _referencedPackageNames.Add(dependency.Nuget);
                }

                if (dependency.Nuget != null)
                    LoadReferencedAssemblyByName(dependency.Nuget);
            }
        }

        // For ASP.NET projects, load common ASP.NET assemblies
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
                // Framework references like Microsoft.AspNetCore.App are implicit
                // Just record them, they're provided by the runtime
                break;
        }
    }

    /// <summary>
    /// Load a NuGet package assembly
    /// </summary>
    private void LoadNuGetPackage(string packageName, string? version, string targetFramework, string projectDirectory)
    {
        // Try to find package in:
        // 1. bin/Debug/net10.0/ (after restore)
        // 2. ~/.nuget/packages/packagename/version/
        // 3. Load by name (runtime resolution)

        var binPath = Path.Combine(projectDirectory, "bin", "Debug", targetFramework, $"{packageName}.dll");
        if (File.Exists(binPath))
        {
            LoadReferencedAssembly(binPath);
            return;
        }

        // Try NuGet cache
        var nugetCache = Path.Combine(GetNuGetPackagesRoot(), packageName.ToLowerInvariant());

        if (Directory.Exists(nugetCache))
        {
            var versionDir = version != null
                ? Path.Combine(nugetCache, version)
                : Directory.GetDirectories(nugetCache).OrderByDescending(d => d).FirstOrDefault();

            if (versionDir != null && Directory.Exists(versionDir))
            {
                // Try common paths for the DLL
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

    /// <summary>
    /// Load a project reference (either .csproj or project.yml)
    /// </summary>
    private void LoadProjectReferenceFile(string projectPath, string targetFramework)
    {
        var projectDir = Path.GetDirectoryName(projectPath)!;

        // Handle .csproj
        if (projectPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
        {
            var projectName = Path.GetFileNameWithoutExtension(projectPath);
            var outputPath = Path.Combine(projectDir, "bin", "Debug", targetFramework, $"{projectName}.dll");

            if (File.Exists(outputPath))
            {
                LoadReferencedAssembly(outputPath);
            }
            else
            {
                Console.Error.WriteLine($"Warning: Project reference '{projectName}' has not been built. Expected: {outputPath}");
            }
        }
        // Handle project.yml (N# project)
        else if (projectPath.EndsWith(".yml", StringComparison.OrdinalIgnoreCase))
        {
            var nsharpProject = ProjectFileParser.Parse(projectPath);
            var outputPath = Path.Combine(projectDir, "bin", "Debug", targetFramework, $"{nsharpProject.EffectiveName}.dll");

            if (File.Exists(outputPath))
            {
                LoadReferencedAssembly(outputPath);
            }
            else
            {
                Console.Error.WriteLine($"Warning: N# project reference '{nsharpProject.EffectiveName}' has not been built. Expected: {outputPath}");
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
        // Common namespace -> assembly mappings
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
        else
        {
            // Try the namespace as assembly name (common pattern)
            var baseNamespace = import.Namespace.Split('.')[0];
            if (baseNamespace.Length > 0)
            {
                LoadReferencedAssemblyByName(import.Namespace);
                if (import.Namespace.Contains('.'))
                {
                    LoadReferencedAssemblyByName(baseNamespace);
                }
            }
        }
    }

    // Helper methods for improved error messages

    /// <summary>
    /// Find similar variable names in current scope
    /// </summary>
    private List<string> FindSimilarVariableNames(string typo)
    {
        var candidates = new List<string>();

        // Collect all variable names from all scopes
        foreach (var scope in _scopes)
        {
            candidates.AddRange(scope.Symbols.Keys);
        }

        // Use SmartSuggester to find similar names
        var suggester = new SmartSuggester(candidates);
        return suggester.SuggestSimilarNames(typo);
    }

    /// <summary>
    /// Find similar function, method, or callable value names in current resolution scope.
    /// </summary>
    private List<string> FindSimilarFunctionNames(string typo)
    {
        var candidates = new List<string>();

        foreach (var scope in _scopes)
        {
            candidates.AddRange(scope.Symbols
                .Where(symbol => IsCallableReferenceType(symbol.Value))
                .Select(symbol => symbol.Key));
        }

        candidates.AddRange(_projectSymbols.Values
            .SelectMany(symbols => symbols)
            .Where(symbol => IsCallableReferenceType(symbol.Type))
            .Select(symbol => symbol.Name));

        candidates.AddRange(_extensionMethods.Select(method => method.Name));

        var suggester = new SmartSuggester(candidates.Distinct(StringComparer.Ordinal).ToList());
        return suggester.SuggestSimilarNames(typo);
    }

    /// <summary>
    /// Get all type names currently in scope
    /// </summary>
    private List<string> GetAllTypesInScope()
    {
        var types = new List<string>();
        foreach (var scope in _scopes)
        {
            types.AddRange(scope.Types.Keys);
        }
        return types;
    }

    /// <summary>
    /// Custom MetadataAssemblyResolver that dynamically searches directories for assemblies.
    /// Replaces the old AppDomain.AssemblyResolve-based AssemblyResolver.
    /// </summary>
    internal sealed class NSharpMetadataResolver : MetadataAssemblyResolver
    {
        private static readonly string[] Tfms = { "net10.0", "net9.0", "net8.0", "net7.0", "net6.0", "netstandard2.1", "netstandard2.0" };

        private readonly List<string> _searchDirectories = new();

        // Candidate assembly files that existed on disk but failed to load, keyed by path →
        // first failure detail. Drained by Analyzer.ReportReferenceLoadFailures (NL923).
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

        public override Assembly? Resolve(MetadataLoadContext context, AssemblyName assemblyName)
        {
            var simpleName = assemblyName.Name;
            if (simpleName == null) return null;

            // Search configured directories
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

            // Search NuGet cache
            var nugetRoot = Analyzer.GetNuGetPackagesRoot();

            var nugetExact = Path.Combine(nugetRoot, simpleName.ToLowerInvariant());
            var found = TryLoadFromNuGetPackageDir(context, nugetExact, simpleName);
            if (found != null) return found;

            // Prefix search in NuGet cache
            if (Directory.Exists(nugetRoot))
            {
                try
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
                catch { /* NuGet prefix search failed */ }
            }

            return null;
        }

        private Assembly? TryLoadFromNuGetPackageDir(MetadataLoadContext context, string packageDir, string simpleName)
        {
            if (!Directory.Exists(packageDir)) return null;

            var versionDir = Directory.GetDirectories(packageDir)
                .OrderByDescending(d => d)
                .FirstOrDefault();
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
    }

    /// <summary>
    /// Caches well-known CLR types from the MetadataLoadContext for use in type comparisons
    /// and generic type construction. Replaces all typeof() references.
    /// </summary>
    internal sealed class WellKnownTypes
    {
        // Primitives (non-nullable — guaranteed to exist in any .NET runtime)
        public readonly Type Int32;
        public readonly Type Int64;
        public readonly Type Single;
        public readonly Type Double;
        public readonly Type Decimal;
        public readonly Type Byte;
        public readonly Type SByte;
        public readonly Type Int16;
        public readonly Type UInt16;
        public readonly Type UInt32;
        public readonly Type UInt64;
        public readonly Type Char;
        public readonly Type Boolean;
        public readonly Type String;
        public readonly Type Void;
        public readonly Type Object;

        // System.Type (for typeof expressions)
        public readonly Type SystemType;

        // Delegate hierarchy
        public readonly Type Delegate;

        // Nullable
        public readonly Type? NullableOpen;

        // Collections
        public readonly Type? ListOpen;
        public readonly Type? IEnumerableOpen;
        public readonly Type? IQueryableOpen;
        public readonly Type? ICollectionOpen;
        public readonly Type? IListOpen;
        public readonly Type? DictionaryOpen;
        public readonly Type? IDictionaryOpen;

        // Tasks
        public readonly Type? TaskOpen;
        public readonly Type? ValueTaskOpen;

        // N# runtime
        public readonly Type? RuntimeUnionOpen;
        public readonly Type? RuntimeResultOpen;

        // System.Text.Json
        public readonly Type? JsonTypeInfoOpen;

        // Action/Func delegates
        public readonly Type? Action;
        public readonly Type? Action1;
        public readonly Type? Action2;
        public readonly Type? Action3;
        public readonly Type? Action4;
        public readonly Type? Func1;
        public readonly Type? Func2;
        public readonly Type? Func3;
        public readonly Type? Func4;
        public readonly Type? Func5;

        public WellKnownTypes(MetadataLoadContext mlc)
        {
            var core = mlc.CoreAssembly ?? throw new InvalidOperationException("MLC core assembly not loaded");

            // Some types may be defined in System.Private.CoreLib rather than System.Runtime
            // (depending on framework layout). Try both to be safe.
            Assembly? coreLib = null;
            try { coreLib = mlc.LoadFromAssemblyName("System.Private.CoreLib"); } catch { }

            Type? Resolve(string fullName) =>
                core.GetType(fullName) ?? coreLib?.GetType(fullName);

            // Primitives — these must exist in any .NET runtime
            Int32 = Resolve("System.Int32") ?? throw new InvalidOperationException("System.Int32 not found in MLC");
            Int64 = Resolve("System.Int64") ?? throw new InvalidOperationException("System.Int64 not found in MLC");
            Single = Resolve("System.Single") ?? throw new InvalidOperationException("System.Single not found in MLC");
            Double = Resolve("System.Double") ?? throw new InvalidOperationException("System.Double not found in MLC");
            Decimal = Resolve("System.Decimal") ?? throw new InvalidOperationException("System.Decimal not found in MLC");
            Byte = Resolve("System.Byte") ?? throw new InvalidOperationException("System.Byte not found in MLC");
            SByte = Resolve("System.SByte") ?? throw new InvalidOperationException("System.SByte not found in MLC");
            Int16 = Resolve("System.Int16") ?? throw new InvalidOperationException("System.Int16 not found in MLC");
            UInt16 = Resolve("System.UInt16") ?? throw new InvalidOperationException("System.UInt16 not found in MLC");
            UInt32 = Resolve("System.UInt32") ?? throw new InvalidOperationException("System.UInt32 not found in MLC");
            UInt64 = Resolve("System.UInt64") ?? throw new InvalidOperationException("System.UInt64 not found in MLC");
            Char = Resolve("System.Char") ?? throw new InvalidOperationException("System.Char not found in MLC");
            Boolean = Resolve("System.Boolean") ?? throw new InvalidOperationException("System.Boolean not found in MLC");
            String = Resolve("System.String") ?? throw new InvalidOperationException("System.String not found in MLC");
            Void = Resolve("System.Void") ?? throw new InvalidOperationException("System.Void not found in MLC");
            Object = Resolve("System.Object") ?? throw new InvalidOperationException("System.Object not found in MLC");
            Delegate = Resolve("System.Delegate") ?? throw new InvalidOperationException("System.Delegate not found in MLC");
            SystemType = Resolve("System.Type") ?? throw new InvalidOperationException("System.Type not found in MLC");

            NullableOpen = Resolve("System.Nullable`1");
            Action = Resolve("System.Action");
            Action1 = Resolve("System.Action`1");
            Action2 = Resolve("System.Action`2");
            Action3 = Resolve("System.Action`3");
            Action4 = Resolve("System.Action`4");
            Func1 = Resolve("System.Func`1");
            Func2 = Resolve("System.Func`2");
            Func3 = Resolve("System.Func`3");
            Func4 = Resolve("System.Func`4");
            Func5 = Resolve("System.Func`5");

            try
            {
                var runtime = mlc.LoadFromAssemblyName("NSharpLang.Runtime");
                RuntimeUnionOpen = runtime.GetType("NSharpLang.Runtime.Union`2");
                RuntimeResultOpen = runtime.GetType("NSharpLang.Runtime.Result`2");
            }
            catch { /* runtime assembly not available in analysis-only contexts */ }

            try
            {
                var json = mlc.LoadFromAssemblyName("System.Text.Json");
                JsonTypeInfoOpen = json.GetType("System.Text.Json.Serialization.Metadata.JsonTypeInfo`1");
            }
            catch { /* System.Text.Json assembly not available in analysis-only contexts */ }

            // Collections — may be in a separate assembly
            try
            {
                var collections = mlc.LoadFromAssemblyName("System.Collections");
                ListOpen = collections.GetType("System.Collections.Generic.List`1") ?? Resolve("System.Collections.Generic.List`1");
                ICollectionOpen = collections.GetType("System.Collections.Generic.ICollection`1") ?? Resolve("System.Collections.Generic.ICollection`1");
                IListOpen = collections.GetType("System.Collections.Generic.IList`1") ?? Resolve("System.Collections.Generic.IList`1");
                DictionaryOpen = collections.GetType("System.Collections.Generic.Dictionary`2") ?? Resolve("System.Collections.Generic.Dictionary`2");
                IDictionaryOpen = collections.GetType("System.Collections.Generic.IDictionary`2") ?? Resolve("System.Collections.Generic.IDictionary`2");
            }
            catch { /* collections assembly not available */ }
            ListOpen ??= Resolve("System.Collections.Generic.List`1");
            ICollectionOpen ??= Resolve("System.Collections.Generic.ICollection`1");
            IListOpen ??= Resolve("System.Collections.Generic.IList`1");
            DictionaryOpen ??= Resolve("System.Collections.Generic.Dictionary`2");
            IDictionaryOpen ??= Resolve("System.Collections.Generic.IDictionary`2");

            // IEnumerable<T> is in System.Runtime
            IEnumerableOpen = Resolve("System.Collections.Generic.IEnumerable`1");

            try
            {
                var expressions = mlc.LoadFromAssemblyName("System.Linq.Expressions");
                IQueryableOpen = expressions.GetType("System.Linq.IQueryable`1");
            }
            catch { /* System.Linq.Expressions assembly not available */ }

            // Tasks — try core first, then dedicated assembly
            TaskOpen = Resolve("System.Threading.Tasks.Task`1");
            ValueTaskOpen = Resolve("System.Threading.Tasks.ValueTask`1");
            if (TaskOpen == null || ValueTaskOpen == null)
            {
                try
                {
                    var threading = mlc.LoadFromAssemblyName("System.Threading.Tasks");
                    TaskOpen ??= threading.GetType("System.Threading.Tasks.Task`1");
                    ValueTaskOpen ??= threading.GetType("System.Threading.Tasks.ValueTask`1");
                }
                catch { /* threading assembly not available */ }
            }
        }
    }
}

// Supporting types - now in ErrorReporting.cs

public class Scope
{
    public ScopeKind Kind { get; }
    public Dictionary<string, TypeInfo> Symbols { get; } = new();
    public Dictionary<string, TypeInfo> Types { get; } = new();
    public Dictionary<string, NullState> NullStates { get; } = new(StringComparer.Ordinal);
    internal Dictionary<string, ErrorTupleResultGuard> ErrorTupleResults { get; } = new(StringComparer.Ordinal);
    internal HashSet<string> AvailableErrorTupleResults { get; } = new(StringComparer.Ordinal);

    // Declaration locations for binding map (name → declaration info)
    private readonly Dictionary<string, SymbolDeclaration> _declarationLocations = new();

    public Scope(ScopeKind kind)
    {
        Kind = kind;
    }

    /// <summary>
    /// Record where a symbol was declared in this scope (for binding map lookups).
    /// </summary>
    public void RecordDeclarationLocation(string name, string? file, int line, int column, string kind)
    {
        _declarationLocations[name] = new SymbolDeclaration(name, file, line, column, kind);
    }

    /// <summary>
    /// Get the declaration location for a symbol in this scope.
    /// </summary>
    public SymbolDeclaration? GetDeclarationLocation(string name)
    {
        return _declarationLocations.TryGetValue(name, out var decl) ? decl : null;
    }
}

public enum ScopeKind
{
    Global,
    Class,
    Struct,
    Record,
    Interface,
    Function,
    Block
}

public enum NullState
{
    Unknown,
    Null,
    MaybeNull,
    NotNull,
    Oblivious
}

internal sealed record ErrorTupleResultGuard(string ResultName, string ErrorName, int Line, int Column);

internal sealed record ImportedSymbolInfo(string Name, TypeInfo Type, SymbolDeclaration Declaration);

internal sealed record ImportedSymbolReference(
    string SourcePath,
    string ImportPath,
    int Line,
    int Column,
    int Length);

/// <summary>
/// A symbol discovered from another file in the same project.
/// Used for automatic cross-file symbol resolution (Go-style package visibility).
/// </summary>
public sealed record ProjectSymbolInfo(
    string Name,
    TypeInfo Type,
    SymbolDeclaration Declaration,
    string SourceFile,
    string? Namespace, // The namespace/package the symbol is declared in (for using-directive generation)
    bool IsExported
);

// Type system
public abstract record TypeInfo
{
    public override string ToString() => GetType().Name;
}

public enum UnknownKind
{
    /// <summary>Type is unknown because an earlier error already reported the issue. Suppresses follow-on errors.</summary>
    ErrorRecovery,
    /// <summary>Type needs to be inferred but inference hasn't resolved it yet.</summary>
    InferenceHole,
    /// <summary>Type comes from an external assembly that hasn't been loaded.</summary>
    DeferredExternal
}

public record UnknownTypeInfo(UnknownKind Kind) : TypeInfo
{
    public override string ToString() => "unknown";
}

public record SimpleTypeInfo(string Name) : TypeInfo
{
    public override string ToString() => Name;
}

public record GenericTypeInfo(string Name, List<TypeInfo> TypeArguments) : TypeInfo
{
    public override string ToString() => $"{Name}<{string.Join(", ", TypeArguments)}>";
}

public record ArrayTypeInfo(TypeInfo ElementType) : TypeInfo
{
    public override string ToString() => $"{ElementType}[]";
}

public record NullableTypeInfo(TypeInfo InnerType) : TypeInfo
{
    public override string ToString() => $"{InnerType}?";
}

/// <summary>
/// Represents external CLR reference nullability that had no C# nullable metadata.
/// </summary>
public record ObliviousTypeInfo(TypeInfo InnerType) : TypeInfo
{
    public override string ToString() => $"{InnerType}!";
}

public record TupleTypeInfo(List<(string? Name, TypeInfo Type)> Elements) : TypeInfo;

public record FunctionTypeInfo(FunctionDeclaration? Declaration) : TypeInfo
{
    public string? SyntheticName { get; set; }
    public List<string>? ParameterNames { get; set; }
    public List<TypeInfo>? ParameterTypes { get; set; }
    public List<Ast.ParameterModifier>? ParameterModifiers { get; set; }
    public TypeInfo? ReturnType { get; set; }
}

public record ByRefTypeInfo(TypeInfo InnerType) : TypeInfo
{
    public override string ToString() => $"&{InnerType}";
}

public record ClassTypeInfo(ClassDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record StructTypeInfo(StructDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record RecordTypeInfo(RecordDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record SoaRecordTypeInfo(SoaRecordDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record SoaRowTypeInfo(SoaRecordDeclaration Declaration) : TypeInfo
{
    public override string ToString() => $"{Declaration.Name}.Row";
}

public record InterfaceTypeInfo(InterfaceDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record UnionTypeInfo : TypeInfo
{
    public UnionDeclaration? Declaration { get; }
    public IReadOnlyList<TypeInfo> Arms { get; }
    public bool IsAnonymous => Declaration is null;

    public UnionTypeInfo(UnionDeclaration declaration)
    {
        Declaration = declaration;
        Arms = Array.Empty<TypeInfo>();
    }

    public UnionTypeInfo(IReadOnlyList<TypeInfo> arms)
    {
        Declaration = null;
        Arms = arms;
    }

    public override string ToString()
        => IsAnonymous ? string.Join(" | ", Arms.Select(a => a.ToString())) : Declaration!.Name;
}

public record EnumTypeInfo(EnumDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record AliasTypeInfo(TypeReference AliasedType) : TypeInfo;

/// <summary>
/// Represents a newtype (distinct wrapper type).
/// Unlike AliasTypeInfo, newtypes are NOT transparent — they are distinct from their underlying type.
/// </summary>
public record NewtypeInfo(string Name, TypeReference UnderlyingType) : TypeInfo
{
    public override string ToString() => Name;
}

/// <summary>
/// Represents a type resolved via .NET reflection (external types like System.Console)
/// </summary>
public record ReflectionTypeInfo(Type Type) : TypeInfo
{
    public override string ToString() => Type.Name;
}

/// <summary>
/// Represents a method resolved via .NET reflection
/// </summary>
public record ReflectionMethodInfo(MethodInfo Method) : TypeInfo
{
    public override string ToString() => $"{Method.Name}(...)";
}

/// <summary>
/// Represents a .NET event resolved via reflection. N# does not model events as fields;
/// they are subscribed/unsubscribed exclusively through the <c>on</c>/<c>off</c> keywords.
/// </summary>
public record ReflectionEventInfo(System.Reflection.EventInfo Event) : TypeInfo
{
    public override string ToString() => $"event {Event.Name}";
}

/// <summary>
/// Represents a group of overloaded methods resolved via .NET reflection
/// </summary>
public record ReflectionMethodGroupInfo(MethodInfo[] Methods) : TypeInfo
{
    public override string ToString() => Methods.Length > 0 ? $"{Methods[0].Name}(...)" : "method group";
}

/// <summary>
/// Represents a group of overloaded N#-declared methods
/// </summary>
public record NSharpMethodGroupInfo(List<FunctionDeclaration> Declarations) : TypeInfo
{
    public override string ToString() => Declarations.Count > 0 ? $"{Declarations[0].Name}(...)" : "method group";
}

/// <summary>
/// Represents an external type that couldn't be fully resolved
/// </summary>
public record ExternalTypeInfo(string Name) : TypeInfo
{
    public override string ToString() => Name;
}

public static class BuiltInTypes
{
    public static readonly SimpleTypeInfo Int = new("int");
    public static readonly SimpleTypeInfo Long = new("long");
    public static readonly SimpleTypeInfo Float = new("float");
    public static readonly SimpleTypeInfo Double = new("double");
    public static readonly SimpleTypeInfo Decimal = new("decimal");
    public static readonly SimpleTypeInfo Byte = new("byte");
    public static readonly SimpleTypeInfo SByte = new("sbyte");
    public static readonly SimpleTypeInfo Short = new("short");
    public static readonly SimpleTypeInfo UShort = new("ushort");
    public static readonly SimpleTypeInfo UInt = new("uint");
    public static readonly SimpleTypeInfo ULong = new("ulong");
    public static readonly SimpleTypeInfo Char = new("char");
    public static readonly SimpleTypeInfo Bool = new("bool");
    public static readonly SimpleTypeInfo String = new("string");
    public static readonly SimpleTypeInfo Void = new("void");
    public static readonly SimpleTypeInfo Object = new("object");
    public static readonly SimpleTypeInfo Null = new("null");
    public static readonly SimpleTypeInfo Never = new("never");
    public static readonly UnknownTypeInfo Unknown = new(UnknownKind.ErrorRecovery);
    public static readonly UnknownTypeInfo InferenceHole = new(UnknownKind.InferenceHole);
    public static readonly UnknownTypeInfo DeferredExternal = new(UnknownKind.DeferredExternal);

    /// <summary>Check if a TypeInfo is any kind of Unknown.</summary>
    public static bool IsUnknown(TypeInfo type) => type is UnknownTypeInfo;
}
