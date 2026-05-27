using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// Semantic analyzer for NewCLILang
/// Performs type checking, name resolution, and definite assignment analysis
/// </summary>
public class Analyzer : IDisposable
{
    private sealed record FlowNarrowing(string Path, TypeInfo? NarrowedType, NullState? NullState);

    private readonly List<CompilerError> _errors = new();
    private readonly Stack<Scope> _scopes = new();
    private readonly List<string> _usingNamespaces = new();
    private readonly Dictionary<string, string> _usingAliases = new(); // alias -> fullName
    private readonly Dictionary<string, List<string>> _importedSymbols = new(); // symbol -> [source paths]
    private readonly Dictionary<string, Dictionary<string, TypeInfo>> _importedSymbolsByAlias = new(); // alias -> (symbol -> TypeInfo)
    private readonly Dictionary<string, Dictionary<string, SymbolDeclaration>> _importedDeclarationsByAlias = new(); // alias -> (symbol -> declaration)
    private readonly List<FunctionDeclaration> _extensionMethods = new(); // Extension methods available in current compilation
    private List<(string Name, TypeInfo Type, int Line, int Column)> _setupSymbols = new();
    private TypeInfo? _currentReturnType;
    private FunctionDeclaration? _currentFunction;
    private bool _currentFunctionReturnTypeWasOmitted;
    private bool _currentFunctionIsAsync;
    private bool _inLoop;
    private bool _inConstructor;
    private ClassDeclaration? _currentClass;
    private string? _currentTypeName;
    private string? _currentFilePath;
    private string? _projectRoot;
    private CompilationUnit? _compilationUnit; // Current file's AST (for namespace checks)
    private TypeInfo? _currentExpectedType;  // For target-typed expressions
    private string[]? _sourceLines;  // Source code lines for error snippets
    // MetadataLoadContext-based assembly inspection (no runtime loading, no version conflicts)
    private NSharpMetadataResolver? _metadataResolver;
    private MetadataLoadContext? _mlc;
    private WellKnownTypes? _wellKnownTypes;
    private readonly List<Assembly> _mlcAssemblies = new();
    private readonly HashSet<string> _referencedPackageNames = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Type> _externalTypeCache = new(); // Cache for external type lookups
    private readonly Dictionary<string, bool> _externalNamespaceCache = new(); // Cache for namespace existence checks
    private readonly Dictionary<string, HashSet<string>> _projectNamespaceCache = new(); // project root -> declared namespaces/packages
    private readonly Dictionary<string, string?> _projectFileNamespaceCache = new(StringComparer.OrdinalIgnoreCase); // file path -> declared namespace/package
    private readonly Dictionary<string, string> _typeDeclarationFiles = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _projectSourceTexts = new(StringComparer.OrdinalIgnoreCase);
    private SemanticModel _semanticModel = new(); // Semantic model for IDE features
    private BindingMap _bindingMap = new(); // Binding map for semantic references
    private readonly Stack<int> _semanticScopeIds = new(); // Parallel scope ID stack for SemanticModel
    private int _currentLine; // Tracks last analyzed line for scope end positions
    private bool _suppressNullabilityFlowType;
    private readonly HashSet<(int Line, int Column, string Path, string Operation)> _reportedNullabilityDiagnostics = new();
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
    /// The C# exporter uses this to emit the necessary using directives.
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
        _semanticScopeIds.Clear();
        _currentLine = 0;
        _suppressNullabilityFlowType = false;
        _reportedNullabilityDiagnostics.Clear();
        _currentReturnType = null;
        _currentFunction = null;
        _currentFunctionReturnTypeWasOmitted = false;
        _currentFunctionIsAsync = false;
        _inLoop = false;
        _inConstructor = false;
        _currentFilePath = currentFilePath;
        _projectRoot = projectRoot;
        _compilationUnit = unit;
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
                    Error("Only one setup block is allowed per test file", setup.Line, setup.Column);
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
                    Error("Only one teardown block is allowed per test file", teardown.Line, teardown.Column);
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

        return new AnalysisResult(_errors, _semanticModel, _bindingMap);
    }

    private void AnalyzeDeclaration(Declaration decl)
    {
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
                ResolveType(aliasDecl.Type);
                break;
            case NewtypeDeclaration newtypeDecl:
                ResolveType(newtypeDecl.UnderlyingType);
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
            case PreprocessorDeclaration:
                // Preprocessor directives don't need analysis - they're pass-through
                break;
        }
    }

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
            foreach (var param in test.TableParameters)
            {
                var paramType = ResolveType(param.Type);
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
                }
            }
        }

        AnalyzeStatements(test.Body.Statements);

        PopScope();
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
                TypeInfo type;
                if (varDecl.Type != null)
                {
                    type = ResolveType(varDecl.Type);
                }
                else
                {
                    // Inferred type — use a generic object type since we can't fully
                    // resolve the initializer without a scope. The C# exporter handles
                    // the actual type via C#'s var keyword.
                    type = BuiltInTypes.Object;
                }
                _setupSymbols.Add((varDecl.Name, type, varDecl.Line, varDecl.Column));
            }
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

        // Validate params parameters
        ValidateParamsParameters(func.Parameters, func.Line, func.Column);

        // Validate default parameters
        ValidateDefaultParameters(func.Parameters, func.Line, func.Column);

        // Add parameters to scope
        foreach (var param in func.Parameters)
        {
            var paramType = ResolveType(param.Type);
            var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, func.Line, func.Column);
            DeclareSymbol(param.Name, paramType, paramLine, paramColumn);

            // Record parameter in semantic model for IDE features (scoped)
            RecordVariableInCurrentScope(param.Name, paramType);
        }

        // Set expected return type
        var previousFunction = _currentFunction;
        var previousFunctionReturnTypeWasOmitted = _currentFunctionReturnTypeWasOmitted;
        var previousFunctionIsAsync = _currentFunctionIsAsync;
        var functionReturnType = func.ReturnType != null ? ResolveType(func.ReturnType) : BuiltInTypes.Void;
        _currentReturnType = functionReturnType;
        _currentFunction = func;
        _currentFunctionReturnTypeWasOmitted = func.ReturnType == null;
        _currentFunctionIsAsync = func.Modifiers.HasFlag(Modifiers.Async);

        // Record function return type in semantic model for IDE features (scoped)
        RecordFunctionInCurrentScope(func.Name, functionReturnType);

        // Analyze body
        if (func.Body != null)
        {
            AnalyzeStatement(func.Body);

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
            var exprType = AnalyzeExpression(func.ExpressionBody);
            if (functionReturnType == BuiltInTypes.Void && exprType != BuiltInTypes.Void)
            {
                AddExpressionBodyReturnError(func, exprType);
            }
            else if (functionReturnType != BuiltInTypes.Void && !IsAssignable(functionReturnType, exprType))
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

    private static bool IsUnitTaskLikeType(TypeInfo type)
    {
        return type switch
        {
            SimpleTypeInfo { Name: "Task" or "ValueTask" or "System.Threading.Tasks.Task" or "System.Threading.Tasks.ValueTask" } => true,
            GenericTypeInfo { Name: "Task" or "ValueTask" or "System.Threading.Tasks.Task" or "System.Threading.Tasks.ValueTask", TypeArguments.Count: 0 } => true,
            ReflectionTypeInfo { Type: var reflectionType } => reflectionType == typeof(System.Threading.Tasks.Task) || reflectionType == typeof(System.Threading.Tasks.ValueTask),
            ExternalTypeInfo { Name: "Task" or "ValueTask" or "System.Threading.Tasks.Task" or "System.Threading.Tasks.ValueTask" } => true,
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

        ResolveTypeReferenceIfPresent(classDecl.BaseClass);
        ResolveTypeReferences(classDecl.Interfaces);

        // Add 'this' to scope
        var classType = new ClassTypeInfo(classDecl);
        DeclareSymbol("this", classType, classDecl.Line, classDecl.Column, recordBindingDeclaration: false);

        // Add primary constructor parameters to scope (C# 12 feature)
        if (classDecl.PrimaryConstructorParameters != null)
        {
            foreach (var param in classDecl.PrimaryConstructorParameters)
            {
                var paramType = ResolveType(param.Type);
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

        ResolveTypeReferences(structDecl.Interfaces);

        var structType = new StructTypeInfo(structDecl);
        DeclareSymbol("this", structType, structDecl.Line, structDecl.Column, recordBindingDeclaration: false);

        // Add primary constructor parameters to scope (C# 12 feature)
        if (structDecl.PrimaryConstructorParameters != null)
        {
            foreach (var param in structDecl.PrimaryConstructorParameters)
            {
                var paramType = ResolveType(param.Type);
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

        ResolveTypeReferences(recordDecl.Interfaces);

        var recordType = new RecordTypeInfo(recordDecl);
        DeclareSymbol("this", recordType, recordDecl.Line, recordDecl.Column, recordBindingDeclaration: false);

        // Add primary constructor parameters to scope (C# 12 feature)
        if (recordDecl.PrimaryConstructorParameters != null)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var paramType = ResolveType(param.Type);
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
                    ResolveType(property.Type);
                }
            }
        }
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

                if (BuiltInTypes.IsUnknown(fieldType))
                {
                    Error($"I can't figure out the type of '{field.Name}' from its initializer — try adding an explicit type annotation", field.Line, field.Column);
                }
            }
        }
        else
        {
            fieldType = ResolveType(field.Type);

            if (field.Initializer != null)
            {
                var previousExpectedType = _currentExpectedType;
                _currentExpectedType = fieldType;
                var initType = AnalyzeExpression(field.Initializer);
                _currentExpectedType = previousExpectedType;
                if (!IsAssignable(fieldType, initType))
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

        var propType = ResolveType(prop.Type!);
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
            var exprType = AnalyzeExpression(prop.ExpressionBody);
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

    private void AnalyzeConstructorDeclaration(ConstructorDeclaration ctor)
    {
        _inConstructor = true;
        PushScope(new Scope(ScopeKind.Function), ctor.Line, ctor.Column);

        // Add parameters to scope
        foreach (var param in ctor.Parameters)
        {
            var paramType = ResolveType(param.Type);
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
                Error(ErrorCode.DefiniteAssignmentError, $"Field '{field}' is non-nullable but isn't assigned in this constructor — either assign it here or give it a default value in its declaration", ctor.Line, ctor.Column);
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

    private void AnalyzeStatements(IReadOnlyList<Statement> statements)
    {
        var terminated = false;
        foreach (var stmt in statements)
        {
            if (terminated)
            {
                Error(ErrorCode.UnreachableStatement, "This code will never run — there's a 'return' or 'throw' above it", stmt.Line, stmt.Column);
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
                if (!IsBoolType(condType))
                {
                    ReportBooleanConditionTypeMismatch(whileStmt.Condition, "a 'while' loop", condType);
                }
                var wasInLoop = _inLoop;
                _inLoop = true;
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
                break;
            case ThrowStatement throwStmt:
                AnalyzeExpression(throwStmt.Expression);
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
                AnalyzeExpression(printStmt.Value);
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
    {
        var errorsBefore = _errors.Count;
        AnalyzeExpression(exprStmt.Expression);

        if (ContainsParserErrorPlaceholder(exprStmt.Expression))
            return;

        if (!IsValidExpressionStatement(exprStmt.Expression) && _errors.Count == errorsBefore)
        {
            ReportInvalidExpressionStatement(exprStmt.Expression);
        }
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
                                  (@new.Initializer != null && ContainsParserErrorPlaceholder(@new.Initializer)),
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

    private (int Line, int Column, int Length) GetBinaryOperatorDiagnosticSpan(BinaryExpression expression)
        => (expression.Line, expression.Column, Math.Max(1, GetBinaryOperatorText(expression.Operator).Length));

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

        // Analyze optional message expression
        if (assertStmt.Message != null)
        {
            AnalyzeExpression(assertStmt.Message);
        }

        // We don't strictly require boolean type because we support various comparison patterns
        // The C# exporter will convert different expression types to appropriate Assert calls
    }

    private void AnalyzeAssertThrowsStatement(AssertThrowsStatement assertThrows)
    {
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

        // Add parameters to scope
        foreach (var param in func.Parameters)
        {
            var paramType = ResolveType(param.Type);
            var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, localFunc.Line, localFunc.Column);
            DeclareSymbol(param.Name, paramType, paramLine, paramColumn);
            RecordVariableInCurrentScope(param.Name, paramType);
        }

        // Save current function context
        var previousReturnType = _currentReturnType;
        var previousFunction = _currentFunction;
        var previousFunctionReturnTypeWasOmitted = _currentFunctionReturnTypeWasOmitted;
        var previousFunctionIsAsync = _currentFunctionIsAsync;
        TypeInfo? returnType = func.ReturnType != null ? ResolveType(func.ReturnType) : BuiltInTypes.Void;
        _currentReturnType = returnType;
        _currentFunction = func;
        _currentFunctionReturnTypeWasOmitted = func.ReturnType == null;
        _currentFunctionIsAsync = func.Modifiers.HasFlag(Modifiers.Async);

        // Analyze body
        if (func.Body != null)
        {
            AnalyzeStatements(func.Body.Statements);
        }
        else if (func.ExpressionBody != null)
        {
            var exprType = AnalyzeExpression(func.ExpressionBody);
            // Verify expression type matches return type
            if (returnType != BuiltInTypes.Void && !IsAssignable(returnType, exprType))
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

        PopScope();
    }

    private void AnalyzeVariableDeclaration(VariableDeclarationStatement varDecl)
    {
        TypeInfo? declaredType = varDecl.Type != null ? ResolveType(varDecl.Type) : null;
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
                Error("A 'const' must have an initial value — the compiler needs to know its value at compile time", varDecl.Line, varDecl.Column);
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
            Error("I can't determine the type of this variable — give it a type annotation or an initial value", varDecl.Line, varDecl.Column);
            finalType = BuiltInTypes.Unknown;
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

            // Declare result variable with inferred type (or Unknown if can't infer)
            if (resultVar != "_")
            {
                DeclareSymbol(resultVar, initType, tupleDecl.Line, tupleDecl.Column);
                RecordVariableInCurrentScope(resultVar, initType);
            }

            // Declare err variable as nullable Exception
            if (errVar != "_")
            {
                var exceptionType = new ExternalTypeInfo("Exception?");
                DeclareSymbol(errVar, exceptionType, tupleDecl.Line, tupleDecl.Column);
                RecordVariableInCurrentScope(errVar, exceptionType);
            }
        }
        else
        {
            // Normal tuple deconstruction
            // Analyze the initializer expression
            var initType = AnalyzeExpression(tupleDecl.Initializer);

            // TODO: Check if initType is a tuple type and has the right number of elements
            // For now, just declare all variables with Unknown type
            foreach (var name in tupleDecl.Names)
            {
                if (name != "_")  // Skip discard
                {
                    DeclareSymbol(name, BuiltInTypes.InferenceHole, tupleDecl.Line, tupleDecl.Column);
                    RecordVariableInCurrentScope(name, BuiltInTypes.InferenceHole);
                }
            }
        }
    }

    private void AnalyzeIfStatement(IfStatement ifStmt)
    {
        var condType = AnalyzeExpression(ifStmt.Condition);
        // Allow unknown types (they might be boolean from external methods we can't fully resolve)
        // Extract flow-sensitive type narrowings from the condition (null checks, is-patterns, && chains)
        var (thenNarrowings, elseNarrowings) = ExtractFlowNarrowings(ifStmt.Condition);

        if (!IsBoolType(condType) && !BuiltInTypes.IsUnknown(condType))
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
            if (!IsBoolType(condType))
            {
                ReportBooleanConditionTypeMismatch(forStmt.Condition, "a 'for' loop", condType);
            }
        }

        if (forStmt.Iterator != null)
            AnalyzeExpression(forStmt.Iterator);

        var wasInLoop = _inLoop;
        _inLoop = true;
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

        PopScope();
    }

    private void AnalyzeForeachStatement(ForeachStatement foreachStmt)
    {
        var collectionType = AnalyzeExpression(foreachStmt.Collection);

        // Check if collection is enumerable
        // For now, just check if it's an array or has a known collection type
        // TODO: More sophisticated enumerable checking

        PushScope(new Scope(ScopeKind.Block), foreachStmt.Line, foreachStmt.Column);

        // Infer element type
        TypeInfo elementType = InferElementType(collectionType);

        DeclareSymbol(foreachStmt.VariableName, elementType, foreachStmt.Line, foreachStmt.Column);

        // Record in semantic model for IDE features (hover, completion, scoped)
        RecordVariableInCurrentScope(foreachStmt.VariableName, elementType);

        var wasInLoop = _inLoop;
        _inLoop = true;
        AnalyzeStatement(foreachStmt.Body);
        _inLoop = wasInLoop;

        PopScope();
    }

    private void AnalyzeAwaitForeachStatement(AwaitForEachStatement awaitForeachStmt)
    {
        var collectionType = AnalyzeExpression(awaitForeachStmt.Collection);

        // Check if collection is IAsyncEnumerable<T>
        // For now, similar to regular foreach, we'll check for async enumerable types
        // TODO: More sophisticated async enumerable checking

        PushScope(new Scope(ScopeKind.Block), awaitForeachStmt.Line, awaitForeachStmt.Column);

        // Infer element type
        TypeInfo elementType = InferElementType(collectionType);

        DeclareSymbol(awaitForeachStmt.VariableName, elementType, awaitForeachStmt.Line, awaitForeachStmt.Column);

        // Record in semantic model for IDE features (hover, completion, scoped)
        RecordVariableInCurrentScope(awaitForeachStmt.VariableName, elementType);

        var wasInLoop = _inLoop;
        _inLoop = true;
        AnalyzeStatement(awaitForeachStmt.Body);
        _inLoop = wasInLoop;

        PopScope();
    }

    /// <summary>
    /// Infer the element type from a collection type for foreach loops
    /// </summary>
    private TypeInfo InferElementType(TypeInfo collectionType)
    {
        // Handle arrays: Employee[] → Employee
        if (collectionType is ArrayTypeInfo arrayType)
        {
            return arrayType.ElementType;
        }

        // Handle generic collections: List<Employee> → Employee
        // This also handles IEnumerable<T>, ICollection<T>, etc.
        if (IsCollectionType(collectionType, out var elementType))
        {
            return elementType;
        }

        // Handle .NET reflection types that implement IEnumerable<T>
        if (collectionType is ReflectionTypeInfo reflectionType)
        {
            var type = reflectionType.Type;

            // Check if it's an array
            if (type.IsArray)
            {
                var elementReflectionType = type.GetElementType();
                if (elementReflectionType != null)
                {
                    return new ReflectionTypeInfo(elementReflectionType);
                }
            }

            // Check if type implements IEnumerable<T>
            var enumerableInterface = type.GetInterfaces()
                .FirstOrDefault(i => i.IsGenericType &&
                                   i.GetGenericTypeDefinition().FullName == "System.Collections.Generic.IEnumerable`1");

            if (enumerableInterface != null)
            {
                var elementReflectionType = enumerableInterface.GetGenericArguments()[0];
                return new ReflectionTypeInfo(elementReflectionType);
            }
        }

        return BuiltInTypes.Unknown;
    }

    private void AnalyzeReturnStatement(ReturnStatement returnStmt)
    {
        if (_currentReturnType == null)
        {
            Error("'return' can only be used inside a function — there's no function to return from here", returnStmt.Line, returnStmt.Column);
            return;
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
        var (diagnosticLine, diagnosticColumn, diagnosticLength) = returnStmt.Value != null
            ? GetExpressionDiagnosticSpan(returnStmt.Value)
            : (returnStmt.Line, returnStmt.Column, 6);

        if (_currentReturnType == BuiltInTypes.Void)
        {
            error = _currentFunctionReturnTypeWasOmitted
                ? ErrorMessageBuilder.ReturnValueRequiresReturnType(
                    _currentFilePath!,
                    diagnosticLine,
                    diagnosticColumn,
                    sourceSnippet,
                    diagnosticLength,
                    functionName,
                    returnedType.ToString())
                : ErrorMessageBuilder.ReturnValueInVoidFunction(
                    _currentFilePath!,
                    diagnosticLine,
                    diagnosticColumn,
                    sourceSnippet,
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
                sourceSnippet,
                diagnosticLength,
                functionName,
                returnedType.ToString(),
                expectedReturnValueType.ToString());
        }

        _errors.Add(error);
    }

    private void AddExpressionBodyReturnError(FunctionDeclaration func, TypeInfo expressionType, int? fallbackLine = null, int? fallbackColumn = null)
    {
        var (line, column, length) = func.ExpressionBody != null
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

            if (catchClause.VariableName != null)
            {
                var exceptionType = catchClause.ExceptionType != null
                    ? ResolveType(catchClause.ExceptionType)
                    : new SimpleTypeInfo("Exception");
                DeclareSymbol(catchClause.VariableName, exceptionType, tryStmt.Line, tryStmt.Column);
                RecordVariableInCurrentScope(catchClause.VariableName, exceptionType);
            }

            AnalyzeStatement(catchClause.Block);
            PopScope();
        }

        if (tryStmt.FinallyBlock != null)
        {
            AnalyzeStatement(tryStmt.FinallyBlock);
        }
    }

    private void AnalyzeUsingStatement(UsingStatement usingStmt)
    {
        PushScope(new Scope(ScopeKind.Block), usingStmt.Line, usingStmt.Column);

        if (usingStmt.Declaration != null)
        {
            AnalyzeVariableDeclaration(usingStmt.Declaration);
            // TODO: Check if type implements IDisposable
        }
        else if (usingStmt.Expression != null)
        {
            AnalyzeExpression(usingStmt.Expression);
            // TODO: Check if type implements IDisposable
        }

        if (usingStmt.Body != null)
        {
            AnalyzeStatement(usingStmt.Body);
        }

        PopScope();
    }

    private void AnalyzeLockStatement(LockStatement lockStmt)
    {
        // Analyze the lock object expression
        AnalyzeExpression(lockStmt.LockObject);

        // Analyze the body with a new scope
        PushScope(new Scope(ScopeKind.Block), lockStmt.Line, lockStmt.Column);
        AnalyzeStatement(lockStmt.Body);
        PopScope();
    }

    private void AnalyzeSwitchStatement(SwitchStatement switchStmt)
    {
        var valueType = AnalyzeExpression(switchStmt.Value);

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
                else if (valueType is UnionTypeInfo { IsAnonymous: false } ut && identPattern.Name.Contains('.'))
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
                AnalyzeExpression(literalPattern.Literal);
                break;

            case UnionCasePattern unionPattern:
                // Verify the union case exists if matching against a union type
                if (valueType is UnionTypeInfo { IsAnonymous: false } unionType)
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
                                    var propType = ResolveType(caseProperty.Type);

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
                // Analyze the value expression and ensure it's compatible with valueType
                var relationalValueType = AnalyzeExpression(relationalPattern.Value);
                // The value type should be comparable (numeric, string, etc.)
                // For now, we'll allow any relational pattern without strict type checking
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
                // List pattern matches arrays and IEnumerable<T> types
                // Determine element type
                TypeInfo? elementType = null;

                if (valueType is ArrayTypeInfo arrayType)
                {
                    elementType = arrayType.ElementType;
                }
                else if (valueType is GenericTypeInfo genericType &&
                         (genericType.Name == "IEnumerable" || genericType.Name == "List"))
                {
                    // Extract generic type parameter
                    elementType = genericType.TypeArguments.Count > 0
                        ? genericType.TypeArguments[0]
                        : BuiltInTypes.Unknown;
                }
                else if (valueType is ReflectionTypeInfo reflType && reflType.Type.IsArray)
                {
                    elementType = new ReflectionTypeInfo(reflType.Type.GetElementType()!);
                }
                else
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) =
                        GetListPatternDiagnosticSpan(listPattern);
                    Error(ErrorCode.PatternTypeMismatch,
                        $"A list pattern can only match arrays or collections, but this value is '{valueType}'",
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
                    Warning(ErrorCode.ImpossiblePattern,
                        $"This 'is {targetType}' pattern will never match — a '{valueType}' can never be '{targetType}'",
                        pattern.Line, pattern.Column);
                }

                // Bind the variable if a binding name is provided
                if (typePattern.BindingName != null)
                {
                    DeclareSymbol(typePattern.BindingName, targetType, pattern.Line, pattern.Column);
                }
                break;
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
            IntLiteralExpression => BuiltInTypes.Int,
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
            LambdaExpression lambda => AnalyzeLambda(lambda, _currentExpectedType),
            TernaryExpression ternary => AnalyzeTernary(ternary),
            ArrayLiteralExpression array => AnalyzeArrayLiteral(array),
            NewExpression newExpr => AnalyzeNewExpression(newExpr),
            CastExpression cast => ResolveType(cast.TargetType),
            IsExpression isExpr => AnalyzeIsExpression(isExpr),
            AwaitExpression await => AnalyzeAwaitExpression(await),
            ThrowExpression => BuiltInTypes.Never,
            ThisExpression => GetCurrentTypeScope() ?? BuiltInTypes.Unknown,
            MatchExpression match => AnalyzeMatchExpression(match),
            TypeOfExpression typeofExpr => AnalyzeTypeofExpression(typeofExpr),
            NameofExpression nameofExpr => AnalyzeNameofExpression(nameofExpr),
            CheckedExpression checkedExpr => AnalyzeCheckedExpression(checkedExpr),
            UncheckedExpression uncheckedExpr => AnalyzeUncheckedExpression(uncheckedExpr),
            RangeExpression range => AnalyzeRangeExpression(range),
            OutVariableDeclarationExpression outVar => AnalyzeOutVariableDeclaration(outVar),
            SpreadExpression spread => AnalyzeSpreadExpression(spread),
            ParenthesizedExpression paren => AnalyzeExpression(paren.Inner),
            DefaultExpression defaultExpr => AnalyzeDefaultExpression(defaultExpr),
            _ => BuiltInTypes.Unknown
        };

        var nullState = GetExpressionNullState(expr, type);
        var flowType = ApplyNullabilityFlowType(expr, type, nullState);

        _semanticModel.RecordExpressionType(expr.Line, expr.Column, flowType);
        _semanticModel.RecordExpressionNullState(expr.Line, expr.Column, nullState);
        return flowType;
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

        if (resolved is ExternalTypeInfo)
            return NullState.Oblivious;

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
            return _currentExpectedType;
        }

        // If no expected type context, report an error
        Error("I can't figure out what type 'default' should be here — add a type annotation so I know what you mean (e.g., 'let x: int = default')",
            defaultExpr.Line, defaultExpr.Column);
        return BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeRangeExpression(RangeExpression range)
    {
        // Analyze start if present
        if (range.Start != null)
        {
            AnalyzeExpression(range.Start);
        }

        // Analyze end if present
        if (range.End != null)
        {
            AnalyzeExpression(range.End);
        }

        // All range expressions return System.Range
        return GetRangeType();
    }

    private TypeInfo AnalyzeOutVariableDeclaration(OutVariableDeclarationExpression outVar)
    {
        // Determine the type
        TypeInfo varType;
        if (outVar.Type != null)
        {
            // Explicit type: out int x
            varType = ResolveType(outVar.Type);
        }
        else
        {
            // Type inference: out var x
            // The type will be inferred from the parameter type in AnalyzeCall
            // For now, we mark it as Unknown - it will be updated when analyzing the call
            varType = BuiltInTypes.Unknown;
        }

        // Declare the variable in the current scope (skip if already declared,
        // since BindReflectionCall may re-analyze arguments)
        var existingSymbol = LookupSymbol(outVar.VariableName);
        if (existingSymbol == null)
        {
            DeclareSymbol(outVar.VariableName, varType, outVar.Line, outVar.Column);
            RecordVariableInCurrentScope(outVar.VariableName, varType);
        }

        return existingSymbol ?? varType;
    }

    private TypeInfo AnalyzeSpreadExpression(SpreadExpression spread)
    {
        // Analyze the inner expression
        var innerType = AnalyzeExpression(spread.Expression);

        // For spread in function calls, we expect the inner expression to be an array or enumerable
        // The C# compiler will handle validation of whether the spread is valid
        // For now, we just return the inner type (the collection type itself)
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
                AnalyzeExpression(hole.Expression);
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
            return AnalyzeLogicalOp(leftType, rightType, binary);
        }

        var leftT = AnalyzeExpression(binary.Left);
        var rightT = AnalyzeExpression(binary.Right);

        return binary.Operator switch
        {
            BinaryOperator.Add or BinaryOperator.Subtract or BinaryOperator.Multiply
                or BinaryOperator.Divide or BinaryOperator.Modulo => AnalyzeArithmeticOp(leftT, rightT, binary),
            BinaryOperator.Equal or BinaryOperator.NotEqual or BinaryOperator.Less
                or BinaryOperator.LessOrEqual or BinaryOperator.Greater or BinaryOperator.GreaterOrEqual => BuiltInTypes.Bool,
            BinaryOperator.NullCoalesce => AnalyzeNullCoalesceOp(leftT, rightT, binary),
            BinaryOperator.Range => GetRangeType(),
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo AnalyzeNullCoalesceOp(TypeInfo leftType, TypeInfo rightType, BinaryExpression expr)
    {
        // If right side is a throw expression, the result type is the left type
        // e.g., string? ?? throw => string (C# infers this correctly)
        if (expr.Right is ThrowExpression)
        {
            return leftType;
        }

        // Otherwise, the result is the right type (the fallback value)
        // In C#: T? ?? T returns T
        return rightType;
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

    private TypeInfo AnalyzeLogicalOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
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
        var operandType = AnalyzeExpression(unary.Operand);

        return unary.Operator switch
        {
            UnaryOperator.Negate => operandType,
            UnaryOperator.Not => BuiltInTypes.Bool,
            UnaryOperator.PreIncrement or UnaryOperator.PreDecrement
                or UnaryOperator.PostIncrement or UnaryOperator.PostDecrement => operandType,
            UnaryOperator.IndexFromEnd => LookupType("System.Index") ?? BuiltInTypes.DeferredExternal,
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo AnalyzeMustExpression(MustExpression must)
    {
        var operandType = AnalyzeExpression(must.Expression);

        if (operandType is NullableTypeInfo nullable)
        {
            return nullable.InnerType;
        }

        if (BuiltInTypes.IsUnknown(operandType))
        {
            return BuiltInTypes.Unknown;
        }

        Warning(
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
                // Symbol not found in alias
                Error($"'{member.MemberName}' doesn't exist in '{aliasName}' — check the import for available symbols", member.Line, member.Column);
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
        var receiverType = GetNonNullableType(objectType);

        ValidateDeclaredMemberVisibility(receiverType, member);
        TryRecordMemberBinding(receiverType, member);

        // Resolve member on type
        var includeStaticMembers = IsStaticMemberAccessTarget(member.Object);
        var memberType = ResolveMember(receiverType, member.MemberName, includeStaticMembers);
        if (BuiltInTypes.IsUnknown(memberType) && ShouldReportUndefinedMember(receiverType, member))
        {
            ReportUndefinedMember(receiverType, member, includeStaticMembers);
        }

        return member.IsNullConditional ? MakeNullableResult(memberType) : memberType;
    }

    private TypeInfo AnalyzeIndexAccess(IndexAccessExpression index)
    {
        var objectType = AnalyzeExpression(index.Object);
        ReportPossibleNullAccess(index.Object, objectType, index.Line, index.Column, "index", index.IsNullConditional);

        var indexType = AnalyzeExpression(index.Index);
        var receiverType = GetNonNullableType(objectType);
        var isRangeAccess = index.Index is RangeExpression || IsRangeLikeType(indexType);
        var elementType = ResolveIndexElementType(receiverType, indexType, isRangeAccess);

        return index.IsNullConditional ? MakeNullableResult(elementType) : elementType;
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

    private TypeInfo GetRangeType()
        => LookupType("System.Range") ?? new ReflectionTypeInfo(typeof(Range));

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
                Warning(
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
        return target is IdentifierExpression identifier && LookupSymbol(identifier.Name) == null;
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

    private bool ShouldReportUndefinedMember(TypeInfo receiverType, MemberAccessExpression member)
    {
        if (string.IsNullOrWhiteSpace(member.MemberName) || member.MemberName == "<error>")
            return false;

        receiverType = ResolveAliasAndMetadata(receiverType);
        if (BuiltInTypes.IsUnknown(receiverType)
            || receiverType == BuiltInTypes.Null
            || receiverType == BuiltInTypes.Never
            || receiverType == BuiltInTypes.Void
            || receiverType is FunctionTypeInfo or NSharpMethodGroupInfo or ReflectionMethodGroupInfo
                or ReflectionMethodInfo or ExternalTypeInfo)
        {
            return false;
        }

        return receiverType switch
        {
            SimpleTypeInfo simple when simple == BuiltInTypes.Object => false,
            SimpleTypeInfo simple => TryConvertTypeInfoToClrType(simple) != null,
            GenericTypeInfo or ArrayTypeInfo => TryConvertTypeInfoToClrType(receiverType) != null,
            ReflectionTypeInfo reflection when IsSystemObjectType(reflection.Type) => false,
            ReflectionTypeInfo reflection => HasReliableReflectionMemberSet(reflection.Type),
            ClassTypeInfo or StructTypeInfo or RecordTypeInfo
                or InterfaceTypeInfo or EnumTypeInfo or UnionTypeInfo or NewtypeInfo
                or TupleTypeInfo => true,
            NullableTypeInfo nullable => ShouldReportUndefinedMember(nullable.InnerType, member),
            ObliviousTypeInfo oblivious => ShouldReportUndefinedMember(oblivious.InnerType, member),
            _ => false
        };
    }

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
    {
        var memberColumn = GetMemberNameColumn(member);
        var length = Math.Max(1, member.MemberName.Length);
        var typeName = NullabilityMetadata.FormatTypeInfo(receiverType);
        var similarMembers = FindSimilarMemberNames(receiverType, member.MemberName, includeStaticMembers);

        if (_sourceLines != null && member.Line > 0 && member.Line <= _sourceLines.Length && _currentFilePath != null)
        {
            _errors.Add(ErrorMessageBuilder.UndefinedMember(
                _currentFilePath,
                member.Line,
                memberColumn,
                _sourceLines[member.Line - 1],
                length,
                member.MemberName,
                typeName,
                similarMembers));
            return;
        }

        Error(
            ErrorCode.UndefinedMember,
            $"Member '{member.MemberName}' not found on type '{typeName}'",
            member.Line,
            memberColumn,
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

        if (receiverType is InterfaceTypeInfo interfaceType)
        {
            var members = GetDeclaredMemberNames(interfaceType.Declaration.Members);
            members.AddRange(GetSourceObjectMemberNames(includeStaticMembers));
            return members;
        }

        if (receiverType is EnumTypeInfo enumType)
            return enumType.Declaration.Members.Select(member => member.Name).ToList();

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

        if (objectType is NullableTypeInfo nullableType)
        {
            if (memberName == "HasValue")
                return BuiltInTypes.Bool;
            if (memberName == "Value")
                return nullableType.InnerType;
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

        if (objectType is GenericTypeInfo or ArrayTypeInfo)
        {
            var clrType = TryConvertTypeInfoToClrType(objectType);
            if (clrType != null)
                objectType = new ReflectionTypeInfo(clrType);
        }

        // Handle reflection-based types
        if (objectType is ReflectionTypeInfo reflectionType)
        {
            var type = reflectionType.Type;

            // Try property
            var memberFlags = BindingFlags.Public | BindingFlags.Instance;
            if (includeStaticMembers)
                memberFlags |= BindingFlags.Static;

            var property = type.GetProperty(memberName, memberFlags);
            if (property != null)
                return NullabilityMetadata.ConvertProperty(property);

            // Try field
            var field = type.GetField(memberName, memberFlags);
            if (field != null)
                return NullabilityMetadata.ConvertField(field);

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

        if (objectType is EnumTypeInfo)
        {
            return objectType;
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
        try
        {
            return method.GetCustomAttributesData()
                .Any(a => a.AttributeType.FullName == "System.Runtime.CompilerServices.ExtensionAttribute");
        }
        catch { return false; }
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
            "System.Int32" => BuiltInTypes.Int,
            "System.Int64" => BuiltInTypes.Long,
            "System.Single" => BuiltInTypes.Float,
            "System.Double" => BuiltInTypes.Double,
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
            ReturnType = func.ReturnType != null ? ResolveType(func.ReturnType) : BuiltInTypes.Void
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
        if (_wellKnownTypes == null) return null;
        var resolvedType = ResolveTypeAlias(typeInfo);

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
            ReflectionTypeInfo reflection => reflection.Type,
            ArrayTypeInfo array => TryConvertTypeInfoToClrType(array.ElementType)?.MakeArrayType(),
            NullableTypeInfo nullable => TryConvertNullableType(nullable.InnerType),
            ObliviousTypeInfo oblivious => TryConvertTypeInfoToClrType(oblivious.InnerType),
            GenericTypeInfo generic => TryConstructKnownGenericType(generic),
            FunctionTypeInfo function => TryConstructDelegateType(function),
            UnionTypeInfo { IsAnonymous: true } anonymousUnion => TryConstructRuntimeUnionType(anonymousUnion),
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
        if (_wellKnownTypes == null) return null;
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

        if (typeDefinition == null)
            return null;

        var typeArguments = new List<Type>();
        foreach (var typeArgument in genericType.TypeArguments)
        {
            var clrTypeArgument = TryConvertTypeInfoToClrType(typeArgument);
            if (clrTypeArgument == null)
                return null;

            typeArguments.Add(clrTypeArgument);
        }

        return typeDefinition.MakeGenericType(typeArguments.ToArray());
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
        var calleeType = AnalyzeExpression(call.Callee);
        ReportPossibleNullAccess(call.Callee, calleeType, call.Line, call.Column, "call", isNullConditional: false);

        // Analyze arguments
        var argTypes = new List<TypeInfo>();
        if (calleeType is FunctionTypeInfo functionType && functionType.ParameterTypes != null)
        {
            for (int i = 0; i < call.Arguments.Count; i++)
            {
                var expectedType = i < functionType.ParameterTypes.Count ? functionType.ParameterTypes[i] : null;
                argTypes.Add(AnalyzeExpressionWithExpectedType(call.Arguments[i].Value, expectedType));
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
                if (isMethodGroup && arg.Value is LambdaExpression)
                {
                    argTypes.Add(BuiltInTypes.Unknown);
                    continue;
                }
                argTypes.Add(AnalyzeExpressionWithExpectedType(arg.Value, null));
            }
        }

        // Resolve return type from function type
        if (calleeType is FunctionTypeInfo funcType)
        {
            // If we have the function declaration, check parameter types
            if (funcType.Declaration != null)
            {
                var parameters = funcType.Declaration.Parameters;

                // Check if this is an extension method (first param has IsThis = true)
                var isExtensionMethod = parameters.Count > 0 && parameters[0].IsThis;

                // For extension methods, skip the first parameter (the "this" parameter)
                var paramStartIndex = isExtensionMethod ? 1 : 0;
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

                        if (!IsAssignable(paramType, argType))
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
                            for (int i = regularParamCount; i < argTypes.Count; i++)
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

                // Return the declared return type, with generic bindings applied
                if (funcType.Declaration.ReturnType != null)
                {
                    var returnType = ResolveType(funcType.Declaration.ReturnType);
                    var genericBindingsForReturn = TryInferNSharpGenericBindings(funcType.Declaration, call, argTypes);
                    return ApplyNSharpGenericBindings(returnType, genericBindingsForReturn);
                }
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
                // Validate arguments against the selected overload
                ValidateNSharpCallArguments(boundDecl, call, argTypes);
                return boundDecl.ReturnType != null
                    ? ResolveNSharpReturnType(boundDecl, call, argTypes)
                    : BuiltInTypes.Void;
            }

            // No matching overload found
            Error(ErrorCode.NoMatchingOverload,
                $"None of the overloads of '{nsharpGroup.Declarations[0].Name}' accept {argTypes.Count} argument(s) with these types — check the function signature",
                call.Line, call.Column);
        }

        return BuiltInTypes.Unknown;
    }

    private TypeInfo HandleUnboundReflectionCall(CallExpression call, IReadOnlyList<MethodInfo> candidateMethods, List<TypeInfo> argTypes)
    {
        if (TryGetNSharpMethodGroupArgumentName(call, out var methodGroupArgumentName))
        {
            ReportNoMatchingReflectionMethodGroupOverload(call, candidateMethods, methodGroupArgumentName);
            return BuiltInTypes.Unknown;
        }

        if (ShouldSuppressReflectionOverloadDiagnostic(call, candidateMethods, argTypes))
            return GetFallbackReflectionReturnType(call, candidateMethods);

        ReportNoMatchingReflectionOverload(call, candidateMethods, argTypes);
        return BuiltInTypes.Unknown;
    }

    private static bool ShouldSuppressReflectionOverloadDiagnostic(CallExpression call, IReadOnlyList<MethodInfo> candidateMethods, List<TypeInfo> argTypes)
    {
        if (candidateMethods.Count == 0)
            return true;

        var hasCompatibleArity = candidateMethods.Any(method =>
            HasCompatibleReflectionArity(
                method.GetParameters(),
                IsExtensionMethodCall(method, call) ? 1 : 0,
                call.Arguments.Count));

        if (!hasCompatibleArity)
            return false;

        return argTypes.Any(BuiltInTypes.IsUnknown)
            || call.Arguments.Any(argument => argument.Value is LambdaExpression);
    }

    private TypeInfo GetFallbackReflectionReturnType(CallExpression call, IReadOnlyList<MethodInfo> candidateMethods)
    {
        var fallbackMethod = candidateMethods.FirstOrDefault(method =>
            HasCompatibleReflectionArity(
                method.GetParameters(),
                IsExtensionMethodCall(method, call) ? 1 : 0,
                call.Arguments.Count))
            ?? candidateMethods.FirstOrDefault();

        return fallbackMethod != null
            ? NullabilityMetadata.ConvertReturn(fallbackMethod)
            : BuiltInTypes.Unknown;
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

    private TypeInfo AnalyzeExpressionWithExpectedType(Expression expression, TypeInfo? expectedType)
    {
        if (expression is LambdaExpression lambda)
            return AnalyzeLambda(lambda, expectedType);

        var previousExpectedType = _currentExpectedType;
        if (expectedType != null)
            _currentExpectedType = expectedType;

        try
        {
            return AnalyzeExpression(expression);
        }
        finally
        {
            _currentExpectedType = previousExpectedType;
        }
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
            var isExtension = decl.Parameters.Count > 0 && decl.Parameters[0].IsThis;
            var paramStart = isExtension ? 1 : 0;
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

                if (!IsAssignable(paramType, argType))
                {
                    allMatch = false;
                    break;
                }

                score += GetNSharpMatchScore(paramType, argType);
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
                    for (int i = regularParamCount; i < argTypes.Count; i++)
                    {
                        if (!IsAssignable(paramsArrayType.ElementType, argTypes[i]))
                        {
                            paramsMatch = false;
                            break;
                        }
                        score += GetNSharpMatchScore(paramsArrayType.ElementType, argTypes[i]);
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

        // Exact match by reference or string representation
        if (resolvedParam == resolvedArg)
            return 8;
        if (resolvedParam.ToString() == resolvedArg.ToString())
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

    /// <summary>
    /// Validates arguments against a selected N#-declared overload and reports type errors.
    /// </summary>
    private void ValidateNSharpCallArguments(FunctionDeclaration decl, CallExpression call, List<TypeInfo> argTypes)
    {
        var isExtension = decl.Parameters.Count > 0 && decl.Parameters[0].IsThis;
        var paramStart = isExtension ? 1 : 0;
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

            if (!IsAssignable(paramType, argType))
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
                for (int i = regularParamCount; i < argTypes.Count; i++)
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
    private void ValidateGenericConstraints(FunctionDeclaration decl, CallExpression call, Dictionary<string, TypeInfo>? bindings)
    {
        if (decl.Constraints == null || bindings == null || bindings.Count == 0)
            return;

        foreach (var constraint in decl.Constraints)
        {
            if (bindings.TryGetValue(constraint.TypeParameter, out var boundType))
            {
                // Validate special constraints
                if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.Class))
                {
                    if (!IsReferenceType(boundType))
                    {
                        Error(ErrorCode.GenericConstraintViolation,
                            $"'{boundType}' is a value type, but type parameter '{constraint.TypeParameter}' requires a reference type (class constraint)",
                            call.Line, call.Column);
                    }
                }

                if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.Struct))
                {
                    // CLR 'struct' constraint means non-nullable value type.
                    // Nullable<T> (NullableTypeInfo) is NOT a valid struct-constrained type.
                    if (IsReferenceType(boundType) || boundType is NullableTypeInfo)
                    {
                        Error(ErrorCode.GenericConstraintViolation,
                            $"'{boundType}' is not a non-nullable value type, but type parameter '{constraint.TypeParameter}' requires one (struct constraint)",
                            call.Line, call.Column);
                    }
                }

                if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.New))
                {
                    if (!HasParameterlessConstructor(boundType))
                    {
                        Error(ErrorCode.GenericConstraintViolation,
                            $"'{boundType}' doesn't have a parameterless constructor, but type parameter '{constraint.TypeParameter}' requires one (new() constraint)",
                            call.Line, call.Column);
                    }
                }

                // Validate interface/type constraints
                foreach (var constraintTypeRef in constraint.Constraints)
                {
                    var constraintType = ApplyNSharpGenericBindings(ResolveType(constraintTypeRef), bindings);
                    if (!IsSubtypeOf(boundType, constraintType) && !IsAssignable(constraintType, boundType))
                    {
                        Error($"'{boundType}' doesn't implement '{constraintType}', which is required by type parameter '{constraint.TypeParameter}'",
                            call.Line, call.Column);
                    }
                }
            }
        }
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
        if (decl.ReturnType == null)
            return BuiltInTypes.Void;

        var returnType = ResolveType(decl.ReturnType);
        var genericBindings = TryInferNSharpGenericBindings(decl, call, argTypes);
        return ApplyNSharpGenericBindings(returnType, genericBindings);
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
        var isExtension = decl.Parameters.Count > 0 && decl.Parameters[0].IsThis;
        var paramStart = isExtension ? 1 : 0;
        var hasParams = decl.Parameters.Count > 0 &&
                        decl.Parameters[^1].Modifier == Ast.ParameterModifier.Params;
        var effectiveParamCount = decl.Parameters.Count - paramStart;
        var regularParamCount = hasParams ? effectiveParamCount - 1 : effectiveParamCount;

        // For extension methods, infer from the receiver type (the `this` parameter)
        if (isExtension && call.Callee is MemberAccessExpression memberAccess)
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

            analyzedNonLambdaArguments[i] = AnalyzeExpression(call.Arguments[i].Value);
        }

        var candidates = new List<(MethodInfo Method, Dictionary<Type, Type> Bindings, Dictionary<Type, TypeInfo> TypeInfoBindings,
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
                candidate.Method,
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

            analyzedNonLambdaArguments[i] = AnalyzeExpression(call.Arguments[i].Value);
        }

        var preBound = PreBindReflectionMethod(method, call, receiverClrType, receiverTypeInfo, analyzedNonLambdaArguments);
        if (preBound == null)
            return null;

        return FinalizeBoundReflectionCall(
            preBound.Value.Method,
            call,
            preBound.Value.Bindings,
            preBound.Value.TypeInfoBindings,
            preBound.Value.MethodGroupArguments,
            preBound.Value.BoundArguments);
    }

    private (MethodInfo Method, Dictionary<Type, Type> Bindings, Dictionary<Type, TypeInfo> TypeInfoBindings,
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
        var openMethod = method.IsGenericMethod ? method.GetGenericMethodDefinition() : method;
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
        return (openMethod, bindings, typeInfoBindings, methodGroupArguments, boundArguments, score, usesParams, defaultsUsed);
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

        if (supplied.Argument.Value is OutVariableDeclarationExpression outVariable)
        {
            if (outVariable.Type != null)
            {
                var declaredType = ResolveType(outVariable.Type);
                var expectedTypeInfo = ConvertReflectionType(boundParameterType);
                if (!IsAssignable(expectedTypeInfo, declaredType))
                    return false;
            }

            score = 8;
            return true;
        }

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
        MethodInfo method, CallExpression call,
        Dictionary<Type, Type> bindings,
        Dictionary<Type, TypeInfo> typeInfoBindings,
        Dictionary<int, FunctionTypeInfo> methodGroupArguments,
        IReadOnlyList<ReflectionBoundArgument> boundArguments)
    {
        var workingBindings = new Dictionary<Type, Type>(bindings);
        var workingTypeInfoBindings = new Dictionary<Type, TypeInfo>(typeInfoBindings);
        var openMethod = method; // Preserve the open method for TypeInfo-based resolution
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

            var lambdaType = AnalyzeLambda(lambda, expectedSignature);
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

        _semanticModel.RecordReflectionCallTarget(call.Line, call.Column, method);

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

            var lambdaArgumentType = AnalyzeLambda(lambda, expectedSignature);
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
        try
        {
            return parameter.GetCustomAttributesData()
                .Any(a => a.AttributeType.FullName == "System.ParamArrayAttribute");
        }
        catch { return false; }
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
                return existingBinding == argumentType;

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
        var previousSuppressNullabilityFlowType = _suppressNullabilityFlowType;
        _suppressNullabilityFlowType = true;
        var targetType = AnalyzeExpression(assignment.Target);
        _suppressNullabilityFlowType = previousSuppressNullabilityFlowType;

        var previousExpectedType = _currentExpectedType;
        _currentExpectedType = targetType;
        var valueType = AnalyzeExpression(assignment.Value);
        _currentExpectedType = previousExpectedType;

        // Check for readonly field assignment outside constructor
        CheckReadonlyFieldAssignment(assignment.Target, assignment.Line, assignment.Column);

        if (!IsAssignable(targetType, valueType))
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

        UpdateNullStateAfterAssignment(assignment.Target, assignment.Value, targetType, valueType);

        return targetType;
    }

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

    private void CheckReadonlyFieldAssignment(Expression target, int line, int column)
    {
        // Only check if we're not in a constructor
        if (_inConstructor)
            return;

        // Check if target is a field access on 'this'
        string? fieldName = null;
        if (target is MemberAccessExpression { Object: ThisExpression } memberAccess)
        {
            fieldName = memberAccess.MemberName;
        }
        else if (target is IdentifierExpression ident)
        {
            // Direct field assignment (implicitly on 'this' in class context)
            fieldName = ident.Name;
        }

        if (fieldName != null && _currentClass != null)
        {
            // Check if this is a readonly field
            var field = _currentClass.Members.OfType<FieldDeclaration>()
                .FirstOrDefault(f => f.Name == fieldName);

            if (field != null && field.Modifiers.HasFlag(Modifiers.Readonly))
            {
                Error($"Field '{fieldName}' is readonly — it can only be assigned in a constructor", line, column);
            }
        }
    }

    private FunctionTypeInfo AnalyzeLambda(LambdaExpression lambda, TypeInfo? expectedType = null)
    {
        var expectedSignature = GetFunctionSignature(expectedType);
        PushScope(new Scope(ScopeKind.Function), lambda.Line, lambda.Column);
        var parameterTypes = new List<TypeInfo>();

        foreach (var param in lambda.Parameters)
        {
            // Parser uses `var` as the placeholder type for untyped lambda parameters,
            // so only treat the parameter as explicit when it is something other than `var`.
            var paramIndex = parameterTypes.Count;
            var hasExplicitType = param.Type is not null
                && param.Type is not SimpleTypeReference { Name: "var" };

            var paramType = hasExplicitType
                ? ResolveType(param.Type!)
                : expectedSignature?.ParameterTypes != null && paramIndex < expectedSignature.ParameterTypes.Count
                    ? expectedSignature.ParameterTypes[paramIndex]
                    : BuiltInTypes.Unknown;
            var (paramLine, paramColumn) = GetParameterDeclarationPosition(param, lambda.Line, lambda.Column);
            DeclareSymbol(param.Name, paramType, paramLine, paramColumn);
            RecordVariableInCurrentScope(param.Name, paramType);
            parameterTypes.Add(paramType);
        }

        TypeInfo returnType;
        if (lambda.ExpressionBody != null)
        {
            returnType = AnalyzeExpressionWithExpectedType(lambda.ExpressionBody, expectedSignature?.ReturnType);
        }
        else if (lambda.BlockBody != null)
        {
            var previousReturnType = _currentReturnType;
            var previousFunction = _currentFunction;
            var previousFunctionReturnTypeWasOmitted = _currentFunctionReturnTypeWasOmitted;
            var previousFunctionIsAsync = _currentFunctionIsAsync;
            _currentReturnType = expectedSignature?.ReturnType ?? BuiltInTypes.Unknown;
            _currentFunction = null;
            _currentFunctionReturnTypeWasOmitted = false;
            _currentFunctionIsAsync = false;
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

    private FunctionTypeInfo? GetFunctionSignature(TypeInfo? expectedType)
    {
        if (expectedType == null)
            return null;

        var resolvedExpectedType = ResolveTypeAlias(expectedType);

        if (resolvedExpectedType is FunctionTypeInfo functionType)
            return functionType;

        if (resolvedExpectedType is ReflectionTypeInfo reflectionType && IsDelegateType(reflectionType.Type))
            return CreateFunctionTypeInfoFromDelegate(reflectionType.Type);

        // Handle generic delegate types (Func<int, int>, Action<string>) from N# declarations
        if (resolvedExpectedType is GenericTypeInfo)
        {
            var clrType = TryConvertTypeInfoToClrType(resolvedExpectedType);
            if (clrType != null && IsDelegateType(clrType))
                return CreateFunctionTypeInfoFromDelegate(clrType);
        }

        return null;
    }

    private TypeInfo AnalyzeTernary(TernaryExpression ternary)
    {
        var condType = AnalyzeExpression(ternary.Condition);
        if (!IsBoolType(condType))
        {
            ReportBooleanConditionTypeMismatch(ternary.Condition, "a ternary expression", condType);
        }

        var thenType = AnalyzeExpression(ternary.ThenExpression);
        var elseType = AnalyzeExpression(ternary.ElseExpression);

        // Return common type
        return GetCommonType(thenType, elseType);
    }

    private TypeInfo AnalyzeArrayLiteral(ArrayLiteralExpression array)
    {
        if (array.Elements.Count == 0)
        {
            return new ArrayTypeInfo(BuiltInTypes.Unknown);
        }

        var firstType = AnalyzeExpression(array.Elements[0]);
        foreach (var elem in array.Elements.Skip(1))
        {
            var elemType = AnalyzeExpression(elem);
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

    private TypeInfo AnalyzeNewExpression(NewExpression newExpr)
    {
        TypeInfo type;

        // Target-typed new (C# 9): new() or new { ... }
        if (newExpr.Type == null)
        {
            // Try to infer type from context (expected type)
            // For now, we'll use _currentExpectedType if available, otherwise Unknown
            type = _currentExpectedType ?? BuiltInTypes.Unknown;

            // If we couldn't infer the type, that's an error in some contexts
            // but we'll let it slide for now to avoid breaking existing code
        }
        else
        {
            type = ResolveType(newExpr.Type);

            // Special case: if the type is a qualified name like "Result.Success",
            // it might be a union case. Check if the base type is a union.
            if (newExpr.Type is SimpleTypeReference simpleRef && simpleRef.Name.Contains('.'))
            {
                var parts = simpleRef.Name.Split('.');
                if (parts.Length == 2)
                {
                    var baseTypeName = parts[0];
                    var baseType = LookupType(baseTypeName);
                    if (baseType is UnionTypeInfo { IsAnonymous: false })
                    {
                        // This is a union case instantiation - the variable should have the union type
                        type = baseType;
                    }
                }
            }
        }

        // Analyze constructor arguments
        foreach (var arg in newExpr.ConstructorArguments)
        {
            AnalyzeExpression(arg.Value);
        }

        // Analyze initializer
        if (newExpr.Initializer != null)
        {
            foreach (var prop in newExpr.Initializer.Properties)
            {
                // Analyze index expression if this is an indexer initializer
                if (prop.IndexExpression != null)
                {
                    AnalyzeExpression(prop.IndexExpression);
                }

                // Analyze the value
                AnalyzeExpression(prop.Value);
            }
        }

        return type;
    }

    private TypeInfo AnalyzeIsExpression(IsExpression isExpr)
    {
        var sourceType = AnalyzeExpression(isExpr.Expression);
        var targetType = ResolveType(isExpr.Type);

        if (!IsPatternPossible(sourceType, targetType))
        {
            Warning(ErrorCode.ImpossiblePattern,
                $"This 'is {targetType}' check will always be false — a '{sourceType}' can never be '{targetType}'",
                isExpr.Line, isExpr.Column);
        }

        return BuiltInTypes.Bool;
    }

    private TypeInfo AnalyzeAwaitExpression(AwaitExpression await)
    {
        var exprType = AnalyzeExpression(await.Expression);
        // TODO: Unwrap Task<T> to get T
        return BuiltInTypes.Unknown;
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
        // Analyze the target expression to ensure it's valid
        AnalyzeExpression(nameofExpr.Target);
        // nameof always returns string
        return BuiltInTypes.String;
    }

    private TypeInfo AnalyzeCheckedExpression(CheckedExpression checkedExpr)
    {
        // Analyze the inner expression - type is preserved
        return AnalyzeExpression(checkedExpr.Expression);
    }

    private TypeInfo AnalyzeUncheckedExpression(UncheckedExpression uncheckedExpr)
    {
        // Analyze the inner expression - type is preserved
        return AnalyzeExpression(uncheckedExpr.Expression);
    }

    private TypeInfo AnalyzeMatchExpression(MatchExpression match)
    {
        // Analyze the value being matched
        var valueType = AnalyzeExpression(match.Value);

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
                var guardType = AnalyzeExpression(matchCase.Guard);
                if (!IsAssignable(BuiltInTypes.Bool, guardType))
                {
                    var (diagnosticLine, diagnosticColumn, diagnosticLength) = GetExpressionDiagnosticSpan(matchCase.Guard);
                    Error(ErrorCode.GuardNotBoolean, $"A match guard must be a boolean, but this expression is '{guardType}'",
                        diagnosticLine, diagnosticColumn, length: diagnosticLength);
                }
            }

            // Analyze the case expression
            var caseType = AnalyzeExpression(matchCase.Expression);

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
            "Use `null => ...` for the absent case and `value => ...` to bind the non-null value.");
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
            "Add an arm for each missing type, or add a wildcard `_` arm.");
    }

    private void CheckMatchExhaustiveness(MatchExpression match, UnionTypeInfo unionType)
    {
        if (unionType.IsAnonymous)
        {
            CheckAnonymousUnionMatchExhaustiveness(match, unionType);
            return;
        }

        // Collect all union case names that are covered by UNGUARDED arms.
        // Guarded arms only partially cover their pattern (the guard may be false at runtime),
        // so they don't count toward exhaustiveness.
        var coveredCases = new HashSet<string>();
        var partiallyCoveredCases = new HashSet<string>();
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
                    if (TryGetUnionCaseForPattern(unionType, identPattern.Name, out var matchedCase))
                    {
                        coveredCases.Add(matchedCase.Name);
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
        foreach (var unionCase in unionType.Declaration!.Cases)
        {
            if (!unionCasePatterns.TryGetValue(unionCase.Name, out var patterns))
                continue;

            if (IsUnionCaseCoveredByPatterns(unionType.Declaration.Name, unionCase, patterns, out var hints))
            {
                coveredCases.Add(unionCase.Name);
            }
            else
            {
                partiallyCoveredCases.Add(unionCase.Name);
                if (hints.Count > 0)
                {
                    partialCoverageHints[unionCase.Name] = hints;
                }
            }
        }

        var allCases = unionType.Declaration.Cases.Select(c => c.Name).ToHashSet();
        var missingCases = allCases.Except(coveredCases).ToList();
        var partialMissingCases = missingCases.Where(partiallyCoveredCases.Contains).ToList();
        var neverCoveredCases = missingCases.Except(partialMissingCases).ToList();

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
                        return $"add '{hints[0]}', an unconstrained '{unionType.Declaration.Name}.{caseName}' arm, or a wildcard '_' arm";
                    }

                    return $"add an unconstrained '{unionType.Declaration.Name}.{caseName}' arm or a wildcard '_' arm";
                }));
                Error(ErrorCode.NonExhaustiveMatch,
                    $"This match doesn't cover all cases — {string.Join("; ", messageParts)}. {partialHint}.",
                    match.Line,
                    match.Column,
                    ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, string.Join(", ", missingCases)));
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
                        5, // "match" keyword length
                        missingCases
                    );
                    _errors.Add(error);
                }
                else
                {
                    var missingCasesStr = string.Join(", ", missingCases);
                    Error(ErrorCode.NonExhaustiveMatch, $"This match doesn't cover all cases — missing: {missingCasesStr}",
                        match.Line, match.Column, ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, missingCasesStr));
                }
            }
        }
        else
        {
            // All union cases covered by unguarded arms — mark exhaustive so the C# exporter
            // emits a discard arm instead of relying on C# exhaustiveness analysis
            match.IsExhaustive = true;
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

            var propertyType = ResolveType(caseProperty.Type);
            if (propertyType is not UnionTypeInfo { IsAnonymous: false } nestedUnionType)
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

        // Check if all enum members are covered
        var allMembers = enumType.Declaration.Members.Select(m => m.Name).ToHashSet();
        var missingMembers = allMembers.Except(coveredMembers).ToList();

        if (missingMembers.Any())
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
                    match.Line, match.Column, ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, missingStr));
            }
        }
        else
        {
            // All enum members covered by unguarded arms — mark exhaustive so the C# exporter
            // emits a discard arm instead of relying on C# exhaustiveness analysis
            match.IsExhaustive = true;
        }
    }

    // Type resolution
    private TypeInfo ResolveType(TypeReference typeRef)
    {
        var resolved = typeRef switch
        {
            SimpleTypeReference simple => ResolveSimpleType(simple.Name, simple.Line, simple.Column),
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
            _ => BuiltInTypes.Unknown
        };

        RecordResolvedTypeReference(typeRef, resolved);
        return resolved;
    }

    private TypeInfo ResolveGenericType(GenericTypeReference generic)
    {
        var typeArguments = generic.TypeArguments.Select(ResolveType).ToList();

        if (generic.Line > 0)
        {
            _ = ResolveSimpleType(generic.Name, generic.Line, generic.Column);
        }

        return new GenericTypeInfo(generic.Name, typeArguments);
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

        for (var i = 0; i < uniqueArms.Count; i++)
        {
            for (var j = 0; j < uniqueArms.Count; j++)
            {
                if (i == j)
                    continue;

                var wider = uniqueArms[i];
                var narrower = uniqueArms[j];
                if (IsAssignable(wider, narrower))
                {
                    var span = GetTypeReferenceStartSpan(union);
                    Warning(
                        ErrorCode.UnnecessaryTypeAnnotation,
                        $"Anonymous union arm '{narrower}' is already covered by '{wider}'.",
                        span.StartLine,
                        span.StartColumn,
                        $"Prefer '{wider}', or declare a named union if these cases must stay distinct.",
                        Math.Max(1, union.Span.IsValid ? union.Span.EndColumn - union.Span.StartColumn : 1));
                }
            }
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
            "var" => BuiltInTypes.InferenceHole, // Treat 'var' as inference hole
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

        // Return unknown type (not an error - might be from C# library)
        return new ExternalTypeInfo(name);
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
                catch { continue; }
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
            catch { continue; }
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

    private TypeInfo ResolveIdentifier(string name, int line, int column)
    {
        if (name == "<error>")
            return BuiltInTypes.Unknown;

        if (TryResolveIdentifierBindingTarget(name, line, column, out var type))
            return type;

        // Use ErrorMessageBuilder for better error message with suggestions
        var similarNames = FindSimilarVariableNames(name);
        var sourceSnippet = _sourceLines != null && line > 0 && line <= _sourceLines.Length
            ? _sourceLines[line - 1]
            : null;

        if (sourceSnippet != null && _currentFilePath != null)
        {
            var error = ErrorMessageBuilder.UndefinedVariable(
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
            Error(ErrorCode.UndefinedVariable, $"I can't find '{name}' — it hasn't been declared in this scope", line, column);
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

    // Convention-based visibility checking
    private void CheckVisibilityConvention(string name, Modifiers modifiers, int line, int column)
    {
        if (string.IsNullOrEmpty(name) || VisibilityConventions.HasExplicitVisibility(modifiers))
            return;

        // Check convention: PascalCase = public/exported, camelCase = private/unexported.
        if (VisibilityConventions.IsExportedIdentifier(name) || char.IsLower(name[0]))
            return;

        Warning($"Identifier '{name}' starts with a non-letter character — in N#, PascalCase means public and camelCase means private",
            line, column);
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

        // Everything is assignable to object
        if (resolvedTarget == BuiltInTypes.Object) return true;

        // Nullable widening: T -> T? and T? -> U? (inner type widening)
        if (resolvedTarget is NullableTypeInfo nullableTarget)
        {
            // Nullable<T> → Nullable<U>: check if inner types are compatible (e.g., int? → long?)
            if (resolvedSource is NullableTypeInfo nullableSource)
                return IsAssignable(nullableTarget.InnerType, nullableSource.InnerType);
            // T → T?: widening non-nullable to nullable
            return IsAssignable(nullableTarget.InnerType, resolvedSource);
        }

        // Handle external types that couldn't be fully resolved (placeholder names)
        if (resolvedSource is ExternalTypeInfo || resolvedTarget is ExternalTypeInfo) return true;

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
        // One side is reflection, other is N#-declared — accept for now (C# compiler will verify)
        if (resolvedSource is ReflectionTypeInfo || resolvedTarget is ReflectionTypeInfo) return true;
        // Method types are callable, not assignable in the normal sense
        if (resolvedSource is ReflectionMethodInfo || resolvedTarget is ReflectionMethodInfo) return true;
        if (resolvedSource is ReflectionMethodGroupInfo || resolvedTarget is ReflectionMethodGroupInfo) return true;

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

    private bool IsDelegateSignatureAssignableWithoutConversion(TypeInfo target, TypeInfo source)
    {
        return TryGetDelegateSignatureConversionScore(target, source, out _);
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

        if (resolved is UnknownTypeInfo or ExternalTypeInfo)
            return true;

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
    /// Maps a built-in N# type name to the corresponding CLR System.Type for reflection-based assignability.
    /// </summary>
    private static Type? MapBuiltInToClrType(string name) => name switch
    {
        "int" => typeof(int),
        "long" => typeof(long),
        "float" => typeof(float),
        "double" => typeof(double),
        "decimal" => typeof(decimal),
        "bool" => typeof(bool),
        "string" => typeof(string),
        "char" => typeof(char),
        "byte" => typeof(byte),
        "sbyte" => typeof(sbyte),
        "short" => typeof(short),
        "ushort" => typeof(ushort),
        "uint" => typeof(uint),
        "ulong" => typeof(ulong),
        "object" => typeof(object),
        "void" => typeof(void),
        _ => null
    };

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
        try
        {
            return type.GetInterfaces();
        }
        catch
        {
            return Array.Empty<Type>();
        }
    }

    private static Type? GetBaseTypeSafe(Type type)
    {
        try
        {
            return type.BaseType;
        }
        catch
        {
            return null;
        }
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
        if (type is StructTypeInfo or EnumTypeInfo)
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
        if (resolvedSource is ExternalTypeInfo || resolvedTarget is ExternalTypeInfo) return true;
        if (resolvedSource is ReflectionTypeInfo || resolvedTarget is ReflectionTypeInfo) return true;

        // Generic type parameters — conservative, don't warn
        if (resolvedSource is GenericTypeInfo || resolvedTarget is GenericTypeInfo) return true;

        // Same type — trivially possible
        if (resolvedSource == resolvedTarget) return true;
        if (resolvedSource.ToString() == resolvedTarget.ToString()) return true;

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

        // Handle external type info (qualified names we couldn't fully resolve)
        if (type is ExternalTypeInfo externalType)
        {
            var typeName = externalType.Name;

            // Check common patterns
            if (typeName.Contains("List<") ||
                typeName.Contains("HashSet<") ||
                typeName.Contains("IList<") ||
                typeName.Contains("ICollection<") ||
                typeName.Contains("IEnumerable<"))
            {
                // We can't easily extract the element type here, so we'll accept Unknown
                elementType = BuiltInTypes.Unknown;
                return true;
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

    private static string? GetNumericName(TypeInfo type)
    {
        if (type is SimpleTypeInfo simple)
            return simple.Name;
        return null;
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
            ? string.Join('\n', _sourceLines)
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
        if (string.IsNullOrWhiteSpace(sourceText) || line <= 0)
            return fallbackColumn;

        var lines = sourceText.Split('\n');
        if (line > lines.Length)
            return fallbackColumn;

        var lineText = lines[line - 1].TrimEnd('\r');
        if (lineText.Length == 0)
            return fallbackColumn;

        var start = Math.Clamp(fallbackColumn - 1, 0, lineText.Length);
        var index = FindWholeIdentifier(lineText, name, start);
        if (index < 0)
        {
            index = FindWholeIdentifier(lineText, name, 0);
        }

        return index >= 0 ? index + 1 : fallbackColumn;
    }

    private static int FindWholeIdentifier(string line, string name, int startIndex)
    {
        var searchStart = Math.Clamp(startIndex, 0, line.Length);
        while (searchStart <= line.Length)
        {
            var index = line.IndexOf(name, searchStart, StringComparison.Ordinal);
            if (index < 0)
                return -1;

            var before = index > 0 ? line[index - 1] : '\0';
            var afterIndex = index + name.Length;
            var after = afterIndex < line.Length ? line[afterIndex] : '\0';
            if (!IsIdentifierCharacter(before) && !IsIdentifierCharacter(after))
                return index;

            searchStart = index + Math.Max(1, name.Length);
        }

        return -1;
    }

    private static bool IsIdentifierCharacter(char value)
        => char.IsLetterOrDigit(value) || value == '_';

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

                // Validate that default value is a compile-time constant
                if (!IsValidDefaultValue(param.DefaultValue!))
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
        // Valid default values are compile-time constants
        // We check for common literal types and allow the C# compiler to validate more complex cases
        return expr switch
        {
            // Literals are always valid
            IntLiteralExpression => true,
            FloatLiteralExpression => true,
            CharLiteralExpression => true,
            BoolLiteralExpression => true,
            StringLiteralExpression => true,
            NullLiteralExpression => true,

            // Unary expressions with literal operands (e.g., -5, +3.14)
            UnaryExpression unary when IsValidDefaultValue(unary.Operand) => true,

            // Binary expressions with literal operands (e.g., 2 + 3)
            BinaryExpression binary when IsValidDefaultValue(binary.Left) && IsValidDefaultValue(binary.Right) => true,

            // Allow identifiers and member access - C# compiler will validate if they're const
            // This covers: enum values, const fields, etc.
            IdentifierExpression => true,
            MemberAccessExpression => true,

            // Allow new expressions - C# compiler will validate compile-time constructibility
            NewExpression newExpr when HasConstantArguments(newExpr) => true,

            // Array literals with constant elements
            ArrayLiteralExpression arrayLit => arrayLit.Elements.All(IsValidDefaultValue),

            _ => false
        };
    }

    private bool HasConstantArguments(NewExpression newExpr)
    {
        // Check if all constructor arguments are valid default values
        if (newExpr.ConstructorArguments != null)
        {
            foreach (var arg in newExpr.ConstructorArguments)
            {
                if (!IsValidDefaultValue(arg.Value))
                    return false;
            }
        }

        return true;
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
            _ => typeRef.ToString() ?? "unknown"
        };
    }

    private void ValidateOperatorOverload(FunctionDeclaration func)
    {
        // Operator overloads must be static
        if (!func.Modifiers.HasFlag(Modifiers.Static))
        {
            Error("Operator overloads must be declared 'static' — they don't belong to a specific instance", func.Line, func.Column);
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
            Error($"The operator '{func.OperatorSymbol}' cannot be overloaded — only arithmetic, comparison, bitwise, and logical operators are supported", func.Line, func.Column);
            return;
        }

        // Note: +/- can be both unary and binary, so we allow 1 or 2 parameters
        if (func.OperatorSymbol is "+" or "-")
        {
            if (func.Parameters.Count != 1 && func.Parameters.Count != 2)
            {
                Error($"Operator '{func.OperatorSymbol}' can be unary (1 parameter) or binary (2 parameters), but you declared {func.Parameters.Count}", func.Line, func.Column);
            }
        }
        else if (func.Parameters.Count != expectedParams)
        {
            Error($"Operator '{func.OperatorSymbol}' requires exactly {expectedParams} parameter(s), but you declared {func.Parameters.Count}", func.Line, func.Column);
        }
    }

    // Error reporting
    private void Error(string message, int line, int column)
    {
        Error(ErrorCode.InvalidSyntax, message, line, column);
    }

    private void Error(ErrorCode code, string message, int line, int column, string? suggestion = null, int length = 1)
    {
        CompilerError error;

        // If we have source lines and the line is valid, include snippet
        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length && _currentFilePath != null)
        {
            var sourceSnippet = _sourceLines[line - 1]; // Lines are 1-indexed
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
                Suggestion = suggestion ?? ErrorSuggestions.GetSuggestion(code)
            };
        }

        _errors.Add(error);
    }

    private void Warning(string message, int line, int column)
    {
        Warning(ErrorCode.UnusedVariable, message, line, column);
    }

    private void Warning(ErrorCode code, string message, int line, int column, string? suggestion = null, int length = 1)
    {
        CompilerError warning;

        // If we have source lines and the line is valid, include snippet
        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length && _currentFilePath != null)
        {
            var sourceSnippet = _sourceLines[line - 1]; // Lines are 1-indexed
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
                Suggestion = suggestion ?? ErrorSuggestions.GetSuggestion(code)
            };
        }

        _errors.Add(warning);
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
        var resolvedPath = resolver.ValidateImportPath(import.Path, out var errorMessage);
        if (resolvedPath == null)
        {
            // Use ErrorMessageBuilder for better error message
            var sourceSnippet = _sourceLines != null && import.Line > 0 && import.Line <= _sourceLines.Length
                ? _sourceLines[import.Line - 1]
                : null;

            if (sourceSnippet != null && _currentFilePath != null)
            {
                var error = ErrorMessageBuilder.ImportNotFound(
                    _currentFilePath,
                    import.Line,
                    import.Column,
                    sourceSnippet,
                    import.Path.Length,
                    import.Path
                );
                _errors.Add(error);
            }
            else
            {
                Error(errorMessage!, import.Line, import.Column);
            }
            return;
        }

        // Check for self-import (file importing itself)
        if (_currentFilePath != null &&
            string.Equals(Path.GetFullPath(resolvedPath), Path.GetFullPath(_currentFilePath), StringComparison.OrdinalIgnoreCase))
        {
            var sourceSnippet = _sourceLines != null && import.Line > 0 && import.Line <= _sourceLines.Length
                ? _sourceLines[import.Line - 1]
                : null;

            if (sourceSnippet != null)
            {
                var error = ErrorMessageBuilder.CircularImport(
                    _currentFilePath,
                    import.Line,
                    import.Column,
                    sourceSnippet,
                    import.Path.Length,
                    import.Path);
                _errors.Add(error);
            }
            else
            {
                Error(ErrorCode.CircularImport, $"'{import.Path}' imports itself — circular imports aren't allowed",
                    import.Line, import.Column,
                    ErrorSuggestions.GetSuggestion(ErrorCode.CircularImport));
            }
            return;
        }

        // Parse the imported file
        CompilationUnit? importedUnit = null;
        string? importedSource = null;
        try
        {
            importedSource = System.IO.File.ReadAllText(resolvedPath);
            var lexer = new Lexer(importedSource, resolvedPath);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, resolvedPath, importedSource);  // Pass source code
            var parseResult = parser.ParseCompilationUnit();
            importedUnit = parseResult.CompilationUnit;

            // Report parse errors
            foreach (var error in parseResult.Errors)
            {
                Error($"The imported file '{import.Path}' has a syntax error — {error.Message}", import.Line, import.Column);
            }

            if (importedUnit == null)
            {
                return;  // Can't continue without compilation unit
            }
        }
        catch (Exception ex)
        {
            Error($"I couldn't read the imported file '{import.Path}' — {ex.Message}", import.Line, import.Column);
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
                    var nestedPath = importedFileResolver.ValidateImportPath(nestedFileImport.Path, out _);
                    if (nestedPath != null &&
                        string.Equals(Path.GetFullPath(nestedPath), currentNormalized, StringComparison.OrdinalIgnoreCase))
                    {
                        var sourceSnippet = _sourceLines != null && import.Line > 0 && import.Line <= _sourceLines.Length
                            ? _sourceLines[import.Line - 1]
                            : null;

                        if (sourceSnippet != null)
                        {
                            var error = ErrorMessageBuilder.CircularImport(
                                _currentFilePath,
                                import.Line,
                                import.Column,
                                sourceSnippet,
                                import.Path.Length,
                                import.Path);
                            _errors.Add(error);
                        }
                        else
                        {
                            Error(ErrorCode.CircularImport,
                                $"Circular import: '{import.Path}' imports '{nestedFileImport.Path}' which imports this file back — break the cycle by restructuring your imports",
                                import.Line, import.Column,
                                ErrorSuggestions.GetSuggestion(ErrorCode.CircularImport));
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
                    _importedSymbols[symbol.Name] = new List<string>();
                }
                _importedSymbols[symbol.Name].Add(resolvedPath);

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

        // Track the namespace for C# export using-directive generation
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

        if (_sourceLines != null && line > 0 && line <= _sourceLines.Length)
        {
            sourceLine = _sourceLines[line - 1];
        }
        else if (!string.IsNullOrWhiteSpace(_currentFilePath) && File.Exists(_currentFilePath))
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
            catch { continue; }
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
            $"'{symbol.Name}' is not exported from package/namespace '{symbol.Namespace ?? "<global>"}' — use PascalCase for cross-package visibility or keep camelCase names inside the declaring package",
            line,
            column);
        return true;
    }

    private bool ReportInaccessibleMember(string memberName, string? declarationFile, int line, int column)
    {
        var declaringNamespace = GetNamespaceForFile(declarationFile) ?? "<global>";
        Error(
            $"'{memberName}' is not exported from package/namespace '{declaringNamespace}' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package",
            line,
            column);
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
        kind is "class" or "struct" or "record" or "interface" or "enum" or "union" or "typeAlias" or "newtype";

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
        foreach (var (symbol, sources) in _importedSymbols)
        {
            if (sources.Count > 1)
            {
                Error($"'{symbol}' is imported from multiple sources ({string.Join(", ", sources)}) — use an alias to resolve the conflict", 0, 0);
            }
        }
    }

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

        // Fallback: try to load by name (runtime will resolve)
        LoadReferencedAssemblyByName(packageName);
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
    /// Find similar type names in current scope
    /// </summary>
    private List<string> FindSimilarTypeNames(string typo)
    {
        var candidates = new List<string>();

        // Collect all type names from all scopes
        foreach (var scope in _scopes)
        {
            candidates.AddRange(scope.Types.Keys);
        }

        // Add common external types
        candidates.AddRange(new[] {
            "Console", "String", "Int32", "Boolean", "Double", "DateTime",
            "List", "Dictionary", "Task", "Guid", "TimeSpan"
        });

        // Use SmartSuggester to find similar names
        var suggester = new SmartSuggester(candidates);
        return suggester.SuggestSimilarNames(typo);
    }

    /// <summary>
    /// Get all variable names currently in scope
    /// </summary>
    private List<string> GetAllVariablesInScope()
    {
        var variables = new List<string>();
        foreach (var scope in _scopes)
        {
            variables.AddRange(scope.Symbols.Keys);
        }
        return variables;
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
                    catch { continue; }
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

        private static Assembly? TryLoadFromNuGetPackageDir(MetadataLoadContext context, string packageDir, string simpleName)
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
                    catch { continue; }
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
            }
            catch { /* runtime assembly not available in analysis-only contexts */ }

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

internal sealed record ImportedSymbolInfo(string Name, TypeInfo Type, SymbolDeclaration Declaration);

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
    public List<TypeInfo>? ParameterTypes { get; set; }
    public List<Ast.ParameterModifier>? ParameterModifiers { get; set; }
    public TypeInfo? ReturnType { get; set; }
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
