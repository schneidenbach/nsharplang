using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Threading;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// Semantic analyzer for NewCLILang
/// Performs type checking, name resolution, and definite assignment analysis
/// </summary>
public class Analyzer
{
    private readonly List<CompilerError> _errors = new();
    private readonly Stack<Scope> _scopes = new();
    private readonly List<string> _usingNamespaces = new();
    private readonly Dictionary<string, string> _usingAliases = new(); // alias -> fullName
    private readonly Dictionary<string, List<string>> _importedSymbols = new(); // symbol -> [source paths]
    private readonly Dictionary<string, Dictionary<string, TypeInfo>> _importedSymbolsByAlias = new(); // alias -> (symbol -> TypeInfo)
    private readonly Dictionary<string, Dictionary<string, SymbolDeclaration>> _importedDeclarationsByAlias = new(); // alias -> (symbol -> declaration)
    private readonly List<FunctionDeclaration> _extensionMethods = new(); // Extension methods available in current compilation
    private TypeInfo? _currentReturnType;
    private bool _inLoop;
    private bool _inConstructor;
    private ClassDeclaration? _currentClass;
    private string? _currentFilePath;
    private string? _projectRoot;
    private TypeInfo? _currentExpectedType;  // For target-typed expressions
    private string[]? _sourceLines;  // Source code lines for error snippets
    private readonly List<Assembly> _referencedAssemblies = new(); // External assemblies for type resolution
    private readonly HashSet<string> _referencedPackageNames = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Type> _externalTypeCache = new(); // Cache for external type lookups
    private readonly Dictionary<string, bool> _externalNamespaceCache = new(); // Cache for namespace existence checks
    private readonly Dictionary<string, HashSet<string>> _projectNamespaceCache = new(); // project root -> declared namespaces
    private readonly Dictionary<string, string> _typeDeclarationFiles = new(StringComparer.Ordinal);
    private SemanticModel _semanticModel = new(); // Semantic model for IDE features
    private BindingMap _bindingMap = new(); // Binding map for semantic references
    // Static assembly resolver — registered once per process, shared across all Analyzer instances.
    // This avoids leaking per-instance handlers on AppDomain.CurrentDomain.AssemblyResolve.
    private static readonly AssemblyResolver s_assemblyResolver = new();

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
        _currentReturnType = null;
        _inLoop = false;
        _inConstructor = false;
        _currentFilePath = currentFilePath;
        _projectRoot = projectRoot;
        _sourceLines = sourceCode?.Split('\n');
        _externalNamespaceCache.Clear();
        _typeDeclarationFiles.Clear();

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
        PushScope(new Scope(ScopeKind.Global));

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
            else if (decl is FunctionDeclaration func)
            {
                // Add function signatures to enable forward references
                var funcTypeInfo = CreateFunctionTypeInfo(func);
                DeclareSymbol(func.Name, funcTypeInfo, func.Line, func.Column);
            }
        }

        // Second pass: analyze all declarations
        foreach (var decl in unit.Declarations)
        {
            AnalyzeDeclaration(decl);
        }

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
        PushScope(new Scope(ScopeKind.Function));

        foreach (var stmt in test.Body.Statements)
        {
            AnalyzeStatement(stmt);
        }

        PopScope();
    }

    private void AnalyzeFunctionDeclaration(FunctionDeclaration func)
    {
        // Validate operator overloads
        if (func.IsOperatorOverload)
        {
            ValidateOperatorOverload(func);
        }

        // Declare function in current scope (if not already declared in first pass)
        var funcType = CreateFunctionTypeInfo(func);
        var existingSymbol = _scopes.Peek().Symbols.GetValueOrDefault(func.Name);
        if (existingSymbol == null)
        {
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

        PushScope(new Scope(ScopeKind.Function));

        // Validate params parameters
        ValidateParamsParameters(func.Parameters, func.Line, func.Column);

        // Validate default parameters
        ValidateDefaultParameters(func.Parameters, func.Line, func.Column);

        // Add parameters to scope
        foreach (var param in func.Parameters)
        {
            var paramType = ResolveType(param.Type);
            DeclareSymbol(param.Name, paramType, func.Line, func.Column);

            // Record parameter in semantic model for IDE features
            _semanticModel.RecordVariable(param.Name, paramType);
        }

        // Set expected return type
        _currentReturnType = func.ReturnType != null ? ResolveType(func.ReturnType) : BuiltInTypes.Void;

        // Record function return type in semantic model for IDE features
        _semanticModel.RecordFunction(func.Name, _currentReturnType);

        // Analyze body
        if (func.Body != null)
        {
            AnalyzeStatement(func.Body);

            // Missing return (all-paths) check for non-void functions.
            // Iterator functions (func* / async*) use yield, not explicit return.
            var isIterator = func.Modifiers.HasFlag(Modifiers.Generator);
            if (_currentReturnType != BuiltInTypes.Void && !isIterator && !StatementAlwaysReturns(func.Body))
            {
                Error(
                    ErrorCode.MissingReturn,
                    $"Not all code paths return a value of type '{_currentReturnType}'",
                    func.Line,
                    func.Column);
            }
        }
        else if (func.ExpressionBody != null)
        {
            // Expression-bodied method: check expression type matches return type
            var exprType = AnalyzeExpression(func.ExpressionBody);
            if (_currentReturnType != BuiltInTypes.Void && !IsAssignable(_currentReturnType, exprType))
            {
                var sourceSnippet = _sourceLines != null && func.Line > 0 && func.Line <= _sourceLines.Length
                    ? _sourceLines[func.Line - 1]
                    : null;

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.TypeMismatch(
                        _currentFilePath,
                        func.Line,
                        func.Column,
                        sourceSnippet,
                        func.ExpressionBody.ToString().Length,
                        exprType.ToString(),
                        _currentReturnType.ToString()
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error(ErrorCode.TypeMismatch, $"Expression body type '{exprType}' does not match return type '{_currentReturnType}'", func.Line, func.Column);
                }
            }
        }

        _currentReturnType = null;
        PopScope();
    }

    private static bool StatementAlwaysReturns(Statement statement)
    {
        switch (statement)
        {
            case ReturnStatement:
            case ThrowStatement:
                return true;

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

            default:
                return false;
        }
    }

    private void AnalyzeClassDeclaration(ClassDeclaration classDecl)
    {
        var previousClass = _currentClass;
        _currentClass = classDecl;

        CheckVisibilityConvention(classDecl.Name, classDecl.Modifiers, classDecl.Line, classDecl.Column);

        PushScope(new Scope(ScopeKind.Class));

        // Add 'this' to scope
        var classType = new ClassTypeInfo(classDecl);
        DeclareSymbol("this", classType, classDecl.Line, classDecl.Column);

        // Add primary constructor parameters to scope (C# 12 feature)
        if (classDecl.PrimaryConstructorParameters != null)
        {
            foreach (var param in classDecl.PrimaryConstructorParameters)
            {
                var paramType = ResolveType(param.Type);
                DeclareSymbol(param.Name, paramType, classDecl.Line, classDecl.Column);
            }
        }

        // Two-pass analysis for forward references
        // First pass: Collect all function signatures
        foreach (var member in classDecl.Members)
        {
            if (member is FunctionDeclaration func)
            {
                // Add function to scope so it can be referenced by other members
                var funcTypeInfo = CreateFunctionTypeInfo(func);
                // Only declare if not already declared (avoid duplicates)
                var existingType = _scopes.Peek().Symbols.GetValueOrDefault(func.Name);
                if (existingType == null)
                {
                    DeclareSymbol(func.Name, funcTypeInfo, func.Line, func.Column);
                }
            }
        }

        // Second pass: Analyze all members
        foreach (var member in classDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
        _currentClass = previousClass;
    }

    private void AnalyzeStructDeclaration(StructDeclaration structDecl)
    {
        CheckVisibilityConvention(structDecl.Name, structDecl.Modifiers, structDecl.Line, structDecl.Column);

        PushScope(new Scope(ScopeKind.Struct));

        var structType = new StructTypeInfo(structDecl);
        DeclareSymbol("this", structType, structDecl.Line, structDecl.Column);

        // Add primary constructor parameters to scope (C# 12 feature)
        if (structDecl.PrimaryConstructorParameters != null)
        {
            foreach (var param in structDecl.PrimaryConstructorParameters)
            {
                var paramType = ResolveType(param.Type);
                DeclareSymbol(param.Name, paramType, structDecl.Line, structDecl.Column);
            }
        }

        foreach (var member in structDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
    }

    private void AnalyzeRecordDeclaration(RecordDeclaration recordDecl)
    {
        CheckVisibilityConvention(recordDecl.Name, recordDecl.Modifiers, recordDecl.Line, recordDecl.Column);

        PushScope(new Scope(ScopeKind.Record));

        var recordType = new RecordTypeInfo(recordDecl);
        DeclareSymbol("this", recordType, recordDecl.Line, recordDecl.Column);

        // Add primary constructor parameters to scope (C# 12 feature)
        if (recordDecl.PrimaryConstructorParameters != null)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var paramType = ResolveType(param.Type);
                DeclareSymbol(param.Name, paramType, recordDecl.Line, recordDecl.Column);
            }
        }

        foreach (var member in recordDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
    }

    private void AnalyzeInterfaceDeclaration(InterfaceDeclaration interfaceDecl)
    {
        CheckVisibilityConvention(interfaceDecl.Name, interfaceDecl.Modifiers, interfaceDecl.Line, interfaceDecl.Column);

        PushScope(new Scope(ScopeKind.Interface));

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
                Error($"Duplicate union case '{unionCase.Name}'", unionDecl.Line, unionDecl.Column);
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
                Error($"Duplicate enum member '{member.Name}'", enumDecl.Line, enumDecl.Column);
            }

            // Type check initializers
            if (member.Value != null)
            {
                var valueType = AnalyzeExpression(member.Value);
                if (enumDecl.Type == EnumType.Int && !IsNumericType(valueType))
                {
                    Error($"Enum member value must be numeric", enumDecl.Line, enumDecl.Column);
                }
                else if (enumDecl.Type == EnumType.String && !IsStringType(valueType))
                {
                    Error($"Enum member value must be string", enumDecl.Line, enumDecl.Column);
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
                Error($"Property '{field.Name}' must have either a type or an initializer", field.Line, field.Column);
                fieldType = BuiltInTypes.Unknown;
            }
            else
            {
                // Infer type from initializer
                fieldType = AnalyzeExpression(field.Initializer);

                if (fieldType == BuiltInTypes.Unknown)
                {
                    Error($"Cannot infer type for property '{field.Name}' from initializer", field.Line, field.Column);
                }
            }
        }
        else
        {
            fieldType = ResolveType(field.Type);

            if (field.Initializer != null)
            {
                var initType = AnalyzeExpression(field.Initializer);
                if (!IsAssignable(fieldType, initType))
                {
                    var sourceSnippet = _sourceLines != null && field.Line > 0 && field.Line <= _sourceLines.Length
                        ? _sourceLines[field.Line - 1]
                        : null;

                    if (sourceSnippet != null && _currentFilePath != null)
                    {
                        var error = ErrorMessageBuilder.TypeMismatch(
                            _currentFilePath,
                            field.Line,
                            field.Column,
                            sourceSnippet,
                            field.Name.Length,
                            initType.ToString(),
                            fieldType.ToString()
                        );
                        _errors.Add(error);
                    }
                    else
                    {
                        Error($"Cannot assign '{initType}' to '{fieldType}'", field.Line, field.Column);
                    }
                }
            }
        }

        DeclareSymbol(field.Name, fieldType, field.Line, field.Column);
    }

    private void AnalyzePropertyDeclaration(PropertyDeclaration prop)
    {
        CheckVisibilityConvention(prop.Name, prop.Modifiers, prop.Line, prop.Column);

        var propType = ResolveType(prop.Type!);
        DeclareSymbol(prop.Name, propType, prop.Line, prop.Column);

        // Expression-bodied property: validate expression type matches property type
        if (prop.ExpressionBody != null)
        {
            var exprType = AnalyzeExpression(prop.ExpressionBody);
            if (!IsAssignable(propType, exprType))
            {
                var sourceSnippet = _sourceLines != null && prop.Line > 0 && prop.Line <= _sourceLines.Length
                    ? _sourceLines[prop.Line - 1]
                    : null;

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.TypeMismatch(
                        _currentFilePath,
                        prop.Line,
                        prop.Column,
                        sourceSnippet,
                        prop.Name.Length,
                        exprType.ToString(),
                        propType.ToString()
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error($"Cannot assign '{exprType}' to '{propType}' in expression-bodied property", prop.Line, prop.Column);
                }
            }
        }

        // Analyze getter
        if (prop.GetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function));
            var prevReturnType = _currentReturnType;
            _currentReturnType = propType; // Getter should return the property type
            AnalyzeStatement(prop.GetBody);
            _currentReturnType = prevReturnType;
            PopScope();
        }

        // Analyze setter
        if (prop.SetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function));
            var prevReturnType = _currentReturnType;
            _currentReturnType = BuiltInTypes.Void; // Setter returns void
            // Implicitly declare 'value' parameter
            DeclareSymbol("value", propType, prop.Line, prop.Column);
            AnalyzeStatement(prop.SetBody);
            _currentReturnType = prevReturnType;
            PopScope();
        }
    }

    private void AnalyzeConstructorDeclaration(ConstructorDeclaration ctor)
    {
        _inConstructor = true;
        PushScope(new Scope(ScopeKind.Function));

        // Add parameters to scope
        foreach (var param in ctor.Parameters)
        {
            var paramType = ResolveType(param.Type);
            DeclareSymbol(param.Name, paramType, ctor.Line, ctor.Column);
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
                Error(ErrorCode.DefiniteAssignmentError, $"Non-nullable field '{field}' must be assigned in constructor", ctor.Line, ctor.Column);
            }
        }
    }

    private HashSet<string> GetAssignedFields(BlockStatement block)
    {
        var assigned = new HashSet<string>();
        foreach (var stmt in block.Statements)
        {
            if (stmt is ExpressionStatement { Expression: AssignmentExpression assignment })
            {
                if (assignment.Target is MemberAccessExpression { Object: ThisExpression } memberAccess)
                {
                    assigned.Add(memberAccess.MemberName);
                }
                else if (assignment.Target is IdentifierExpression ident)
                {
                    assigned.Add(ident.Name);
                }
            }
        }
        return assigned;
    }

    private void AnalyzeStatement(Statement stmt)
    {
        switch (stmt)
        {
            case ExpressionStatement exprStmt:
                AnalyzeExpression(exprStmt.Expression);
                break;
            case VariableDeclarationStatement varDecl:
                AnalyzeVariableDeclaration(varDecl);
                break;
            case TupleDeconstructionStatement tupleDecl:
                AnalyzeTupleDeconstruction(tupleDecl);
                break;
            case BlockStatement block:
                PushScope(new Scope(ScopeKind.Block));
                foreach (var s in block.Statements)
                    AnalyzeStatement(s);
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
                if (!IsBoolType(condType))
                {
                    Error($"While condition must be boolean", whileStmt.Line, whileStmt.Column);
                }
                var wasInLoop = _inLoop;
                _inLoop = true;
                AnalyzeStatement(whileStmt.Body);
                _inLoop = wasInLoop;
                break;
            case ReturnStatement returnStmt:
                AnalyzeReturnStatement(returnStmt);
                break;
            case BreakStatement:
                if (!_inLoop)
                {
                    Error("Break statement outside of loop", stmt.Line, stmt.Column);
                }
                break;
            case ContinueStatement:
                if (!_inLoop)
                {
                    Error("Continue statement outside of loop", stmt.Line, stmt.Column);
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
            case PreprocessorDirective:
                // Preprocessor directives don't need analysis - they're pass-through
                break;
            case LocalFunctionStatement localFunc:
                AnalyzeLocalFunction(localFunc);
                break;
        }
    }

    private void AnalyzeAssertStatement(AssertStatement assertStmt)
    {
        // Analyze the condition expression
        var condType = AnalyzeExpression(assertStmt.Condition);

        // We don't strictly require boolean type because we support various comparison patterns
        // The transpiler will convert different expression types to appropriate Assert calls
    }

    private void AnalyzeLocalFunction(LocalFunctionStatement localFunc)
    {
        var func = localFunc.Function;

        // Register the local function in the current scope
        // This allows it to be called later in the same scope (forward references work in C#)
        var funcType = CreateFunctionTypeInfo(func);
        DeclareSymbol(func.Name, funcType, localFunc.Line, localFunc.Column);

        // Analyze the local function body in a new scope
        PushScope(new Scope(ScopeKind.Function));

        // Add parameters to scope
        foreach (var param in func.Parameters)
        {
            var paramType = ResolveType(param.Type);
            DeclareSymbol(param.Name, paramType, localFunc.Line, localFunc.Column);
        }

        // Save current function context
        var previousReturnType = _currentReturnType;
        TypeInfo? returnType = func.ReturnType != null ? ResolveType(func.ReturnType) : BuiltInTypes.Void;
        _currentReturnType = returnType;

        // Analyze body
        if (func.Body != null)
        {
            foreach (var stmt in func.Body.Statements)
            {
                AnalyzeStatement(stmt);
            }
        }
        else if (func.ExpressionBody != null)
        {
            var exprType = AnalyzeExpression(func.ExpressionBody);
            // Verify expression type matches return type
            if (returnType != BuiltInTypes.Void && !IsAssignable(returnType, exprType))
            {
                Error($"Expression body type '{exprType}' is not assignable to return type '{returnType}'",
                    localFunc.Line, localFunc.Column);
            }
        }

        // Restore function context
        _currentReturnType = previousReturnType;

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
        if (declaredType != null && inferredType != null)
        {
            // Both specified - check compatibility
            if (!IsAssignable(declaredType, inferredType))
            {
                var sourceSnippet = _sourceLines != null && varDecl.Line > 0 && varDecl.Line <= _sourceLines.Length
                    ? _sourceLines[varDecl.Line - 1]
                    : null;

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.TypeMismatch(
                        _currentFilePath,
                        varDecl.Line,
                        varDecl.Column,
                        sourceSnippet,
                        varDecl.Name.Length,
                        inferredType.ToString(),
                        declaredType.ToString()
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error(ErrorCode.TypeMismatch, $"Cannot assign '{inferredType}' to '{declaredType}'", varDecl.Line, varDecl.Column);
                }
            }
            finalType = declaredType;
        }
        else if (declaredType != null)
        {
            // Type specified but no initializer
            if (varDecl.Kind == VariableKind.Const)
            {
                Error("Const variables must have an initializer", varDecl.Line, varDecl.Column);
            }
            finalType = declaredType;
        }
        else if (inferredType != null)
        {
            // Inferred from initializer
            finalType = inferredType;
        }
        else
        {
            Error("Variable must have either a type annotation or an initializer", varDecl.Line, varDecl.Column);
            finalType = BuiltInTypes.Unknown;
        }

        DeclareSymbol(varDecl.Name, finalType, varDecl.Line, varDecl.Column);

        // Record in semantic model for IDE features
        _semanticModel.RecordVariable(varDecl.Name, finalType);
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
            }

            // Declare err variable as nullable Exception
            if (errVar != "_")
            {
                var exceptionType = new ExternalTypeInfo("Exception?");
                DeclareSymbol(errVar, exceptionType, tupleDecl.Line, tupleDecl.Column);
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
                    DeclareSymbol(name, BuiltInTypes.Unknown, tupleDecl.Line, tupleDecl.Column);
                }
            }
        }
    }

    private void AnalyzeIfStatement(IfStatement ifStmt)
    {
        var condType = AnalyzeExpression(ifStmt.Condition);
        // Allow unknown types (they might be boolean from external methods we can't fully resolve)
        if (!IsBoolType(condType) && condType != BuiltInTypes.Unknown)
        {
            // Use ErrorMessageBuilder for better error message
            var sourceSnippet = _sourceLines != null && ifStmt.Line > 0 && ifStmt.Line <= _sourceLines.Length
                ? _sourceLines[ifStmt.Line - 1]
                : null;

            if (sourceSnippet != null && _currentFilePath != null)
            {
                var error = ErrorMessageBuilder.TypeMismatch(
                    _currentFilePath,
                    ifStmt.Line,
                    ifStmt.Column,
                    sourceSnippet,
                    3, // "if" keyword length
                    condType.ToString(),
                    "bool"
                );
                _errors.Add(error);
            }
            else
            {
                Error(ErrorCode.TypeMismatch, $"If condition must be boolean, got '{condType}'", ifStmt.Line, ifStmt.Column);
            }
        }

        AnalyzeStatement(ifStmt.ThenStatement);
        if (ifStmt.ElseStatement != null)
        {
            AnalyzeStatement(ifStmt.ElseStatement);
        }
    }

    private void AnalyzeForStatement(ForStatement forStmt)
    {
        PushScope(new Scope(ScopeKind.Block));

        if (forStmt.Initializer != null)
            AnalyzeStatement(forStmt.Initializer);

        if (forStmt.Condition != null)
        {
            var condType = AnalyzeExpression(forStmt.Condition);
            if (!IsBoolType(condType))
            {
                Error($"For condition must be boolean", forStmt.Line, forStmt.Column);
            }
        }

        if (forStmt.Iterator != null)
            AnalyzeExpression(forStmt.Iterator);

        var wasInLoop = _inLoop;
        _inLoop = true;
        AnalyzeStatement(forStmt.Body);
        _inLoop = wasInLoop;

        PopScope();
    }

    private void AnalyzeForeachStatement(ForeachStatement foreachStmt)
    {
        var collectionType = AnalyzeExpression(foreachStmt.Collection);

        // Check if collection is enumerable
        // For now, just check if it's an array or has a known collection type
        // TODO: More sophisticated enumerable checking

        PushScope(new Scope(ScopeKind.Block));

        // Infer element type
        TypeInfo elementType = InferElementType(collectionType);

        DeclareSymbol(foreachStmt.VariableName, elementType, foreachStmt.Line, foreachStmt.Column);

        // Record in semantic model for IDE features (hover, completion)
        _semanticModel.RecordVariable(foreachStmt.VariableName, elementType);

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

        PushScope(new Scope(ScopeKind.Block));

        // Infer element type
        TypeInfo elementType = InferElementType(collectionType);

        DeclareSymbol(awaitForeachStmt.VariableName, elementType, awaitForeachStmt.Line, awaitForeachStmt.Column);

        // Record in semantic model for IDE features (hover, completion)
        _semanticModel.RecordVariable(awaitForeachStmt.VariableName, elementType);

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
                                   i.GetGenericTypeDefinition() == typeof(System.Collections.Generic.IEnumerable<>));

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
            Error("Return statement outside of function", returnStmt.Line, returnStmt.Column);
            return;
        }

        if (returnStmt.Value != null)
        {
            var returnedType = AnalyzeExpression(returnStmt.Value);
            if (!IsAssignable(_currentReturnType, returnedType))
            {
                // Use ErrorMessageBuilder for better error message
                var sourceSnippet = _sourceLines != null && returnStmt.Line > 0 && returnStmt.Line <= _sourceLines.Length
                    ? _sourceLines[returnStmt.Line - 1]
                    : null;

                if (sourceSnippet != null && _currentFilePath != null)
                {
                    var error = ErrorMessageBuilder.TypeMismatch(
                        _currentFilePath,
                        returnStmt.Line,
                        returnStmt.Column,
                        sourceSnippet,
                        6, // "return" keyword length
                        returnedType.ToString(),
                        _currentReturnType.ToString()
                    );
                    _errors.Add(error);
                }
                else
                {
                    Error(ErrorCode.TypeMismatch, $"Cannot return '{returnedType}' from function returning '{_currentReturnType}'",
                        returnStmt.Line, returnStmt.Column);
                }
            }
        }
        else
        {
            if (_currentReturnType != BuiltInTypes.Void)
            {
                Error(ErrorCode.MissingReturn, $"Function must return a value of type '{_currentReturnType}'", returnStmt.Line, returnStmt.Column);
            }
        }
    }

    private void AnalyzeTryStatement(TryStatement tryStmt)
    {
        AnalyzeStatement(tryStmt.TryBlock);

        foreach (var catchClause in tryStmt.CatchClauses)
        {
            PushScope(new Scope(ScopeKind.Block));

            if (catchClause.VariableName != null)
            {
                var exceptionType = catchClause.ExceptionType != null
                    ? ResolveType(catchClause.ExceptionType)
                    : new SimpleTypeInfo("Exception");
                DeclareSymbol(catchClause.VariableName, exceptionType, tryStmt.Line, tryStmt.Column);
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
        PushScope(new Scope(ScopeKind.Block));

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
        PushScope(new Scope(ScopeKind.Block));
        AnalyzeStatement(lockStmt.Body);
        PopScope();
    }

    private void AnalyzeSwitchStatement(SwitchStatement switchStmt)
    {
        var valueType = AnalyzeExpression(switchStmt.Value);

        foreach (var switchCase in switchStmt.Cases)
        {
            PushScope(new Scope(ScopeKind.Block));

            // Analyze pattern if present
            if (switchCase.Pattern != null)
            {
                AnalyzePattern(switchCase.Pattern, valueType);
            }

            foreach (var stmt in switchCase.Statements)
            {
                AnalyzeStatement(stmt);
            }

            PopScope();
        }
    }

    private void AnalyzePattern(Pattern pattern, TypeInfo valueType)
    {
        switch (pattern)
        {
            case IdentifierPattern identPattern:
                // Check if this is a qualified union case name (e.g., "Result.Success")
                if (valueType is UnionTypeInfo ut && identPattern.Name.Contains('.'))
                {
                    var caseName = identPattern.Name.Contains('.')
                        ? identPattern.Name.Substring(identPattern.Name.LastIndexOf('.') + 1)
                        : identPattern.Name;

                    var matchingCase = ut.Declaration.Cases
                        .FirstOrDefault(c => c.Name == caseName);

                    if (matchingCase == null)
                    {
                        Error($"Union type '{ut}' does not have a case '{identPattern.Name}'",
                            pattern.Line, pattern.Column);
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
                if (valueType is UnionTypeInfo unionType)
                {
                    // Extract just the case name (after the last dot if qualified)
                    var caseName = unionPattern.CaseName.Contains('.')
                        ? unionPattern.CaseName.Substring(unionPattern.CaseName.LastIndexOf('.') + 1)
                        : unionPattern.CaseName;

                    var matchingCase = unionType.Declaration.Cases
                        .FirstOrDefault(c => c.Name == caseName);

                    if (matchingCase == null)
                    {
                        Error($"Union type '{unionType}' does not have a case '{unionPattern.CaseName}'",
                            pattern.Line, pattern.Column);
                    }
                    else if (unionPattern.Properties != null)
                    {
                        // Bind property patterns to their types
                        if (matchingCase.Properties == null)
                        {
                            Error($"Union case '{caseName}' has no properties (Properties is null)",
                                pattern.Line, pattern.Column);
                        }
                        else if (matchingCase.Properties.Count == 0)
                        {
                            Error($"Union case '{caseName}' has no properties (Properties is empty)",
                                pattern.Line, pattern.Column);
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
                                        DeclareSymbol(bindingName, propType, pattern.Line, pattern.Column);
                                    }
                                }
                                else
                                {
                                    Error($"Union case '{caseName}' does not have property '{propPattern.Name}'",
                                        pattern.Line, pattern.Column);
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
                    Error($"List pattern cannot be used with type '{valueType}' (must be array or collection)",
                        pattern.Line, pattern.Column);
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
                    propType = new ReflectionTypeInfo(prop.PropertyType);
                }
            }

            if (propType == null)
            {
                Error($"Type '{valueType}' does not have property '{propPattern.Name}'", line, column);
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
                DeclareSymbol(bindingName, propType, line, column);
            }
        }
    }

    private TypeInfo AnalyzeExpression(Expression expr)
    {
        var type = expr switch
        {
            IntLiteralExpression => BuiltInTypes.Int,
            FloatLiteralExpression => BuiltInTypes.Double,
            StringLiteralExpression strExpr => AnalyzeStringLiteral(strExpr),
            BoolLiteralExpression => BuiltInTypes.Bool,
            NullLiteralExpression => BuiltInTypes.Null,
            IdentifierExpression ident => ResolveIdentifier(ident.Name, ident.Line, ident.Column),
            BinaryExpression binary => AnalyzeBinaryExpression(binary),
            UnaryExpression unary => AnalyzeUnaryExpression(unary),
            MemberAccessExpression member => AnalyzeMemberAccess(member),
            CallExpression call => AnalyzeCall(call),
            AssignmentExpression assignment => AnalyzeAssignment(assignment),
            LambdaExpression lambda => AnalyzeLambda(lambda),
            TernaryExpression ternary => AnalyzeTernary(ternary),
            ArrayLiteralExpression array => AnalyzeArrayLiteral(array),
            NewExpression newExpr => AnalyzeNewExpression(newExpr),
            CastExpression cast => ResolveType(cast.TargetType),
            IsExpression isExpr => BuiltInTypes.Bool,
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
            _ => BuiltInTypes.Unknown
        };

        _semanticModel.RecordExpressionType(expr.Line, expr.Column, type);
        return type;
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
        return LookupType("System.Range") ?? BuiltInTypes.Unknown;
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

        // Declare the variable in the current scope
        DeclareSymbol(outVar.VariableName, varType, outVar.Line, outVar.Column);

        return varType;
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

    private static bool IsKeyword(string name) =>
        name is "true" or "false" or "null" or "this" or "base" or "new" or "typeof" or "nameof"
            // Built-in type names (used in casts inside interpolated strings)
            or "int" or "long" or "float" or "double" or "bool" or "string" or "object"
            or "byte" or "sbyte" or "short" or "ushort" or "uint" or "ulong" or "decimal" or "char" or "void";

    private TypeInfo AnalyzeBinaryExpression(BinaryExpression binary)
    {
        var leftType = AnalyzeExpression(binary.Left);
        var rightType = AnalyzeExpression(binary.Right);

        return binary.Operator switch
        {
            BinaryOperator.Add or BinaryOperator.Subtract or BinaryOperator.Multiply
                or BinaryOperator.Divide or BinaryOperator.Modulo => AnalyzeArithmeticOp(leftType, rightType, binary),
            BinaryOperator.Equal or BinaryOperator.NotEqual or BinaryOperator.Less
                or BinaryOperator.LessOrEqual or BinaryOperator.Greater or BinaryOperator.GreaterOrEqual => BuiltInTypes.Bool,
            BinaryOperator.And or BinaryOperator.Or => AnalyzeLogicalOp(leftType, rightType, binary),
            BinaryOperator.NullCoalesce => AnalyzeNullCoalesceOp(leftType, rightType, binary),
            BinaryOperator.Range => LookupType("System.Range") ?? BuiltInTypes.Unknown,
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
        if (left == BuiltInTypes.Unknown || right == BuiltInTypes.Unknown)
        {
            return BuiltInTypes.Unknown;
        }

        if (!IsNumericType(left) || !IsNumericType(right))
        {
            Error($"Operator '{expr.Operator}' cannot be applied to '{left}' and '{right}'",
                expr.Line, expr.Column);
            return BuiltInTypes.Unknown;
        }

        // Return wider type
        return GetWiderType(left, right);
    }

    private TypeInfo AnalyzeLogicalOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
        if (!IsBoolType(left) || !IsBoolType(right))
        {
            Error($"Logical operator '{expr.Operator}' requires boolean operands", expr.Line, expr.Column);
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
            UnaryOperator.IndexFromEnd => LookupType("System.Index") ?? BuiltInTypes.Unknown,
            _ => BuiltInTypes.Unknown
        };
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
                Error($"Symbol '{member.MemberName}' not found in imported alias '{aliasName}'", member.Line, member.Column);
                return BuiltInTypes.Unknown;
            }

            // Check namespace import aliases (handled by existing TryResolveExternalType)
        }

        var objectType = AnalyzeExpression(member.Object);
        TryRecordMemberBinding(objectType, member);

        // Resolve member on type
        return ResolveMember(objectType, member.MemberName);
    }

    private void TryRecordMemberBinding(TypeInfo objectType, MemberAccessExpression member)
    {
        if (TryFindMemberDeclaration(objectType, member.MemberName, out var declaration))
        {
            RecordMemberBinding(member, declaration);
        }
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

            case UnionTypeInfo unionType:
                var unionCase = unionType.Declaration.Cases.FirstOrDefault(unionCase => unionCase.Name == memberName);
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

    private string? GetDeclarationFileForType(TypeInfo typeInfo) => typeInfo switch
    {
        ClassTypeInfo classType => GetDeclarationFilePath(classType.Declaration.Name),
        StructTypeInfo structType => GetDeclarationFilePath(structType.Declaration.Name),
        RecordTypeInfo recordType => GetDeclarationFilePath(recordType.Declaration.Name),
        InterfaceTypeInfo interfaceType => GetDeclarationFilePath(interfaceType.Declaration.Name),
        EnumTypeInfo enumType => GetDeclarationFilePath(enumType.Declaration.Name),
        UnionTypeInfo unionType => GetDeclarationFilePath(unionType.Declaration.Name),
        _ => _currentFilePath
    };

    private string? GetDeclarationFilePath(string typeName)
    {
        return _typeDeclarationFiles.TryGetValue(typeName, out var filePath)
            ? filePath
            : _currentFilePath;
    }

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
        return new SymbolDeclaration(
            GetDeclarationName(declaration) ?? string.Empty,
            filePath,
            declaration.Line,
            declaration.Column,
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
        _ => "variable"
    };

    private TypeInfo ResolveMember(TypeInfo objectType, string memberName)
    {
        // Handle reflection-based types
        if (objectType is ReflectionTypeInfo reflectionType)
        {
            var type = reflectionType.Type;

            // Try property
            var property = type.GetProperty(memberName, BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
            if (property != null)
                return ConvertReflectionType(property.PropertyType);

            // Try field
            var field = type.GetField(memberName, BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
            if (field != null)
                return ConvertReflectionType(field.FieldType);

            // Try methods (get all matching methods to handle overloads)
            var methods = type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
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
            var member = classType.Declaration.Members.FirstOrDefault(m =>
                (m is FieldDeclaration fd && fd.Name == memberName) ||
                (m is PropertyDeclaration pd && pd.Name == memberName) ||
                (m is FunctionDeclaration func && func.Name == memberName));

            if (member is FieldDeclaration field)
                return field.Type != null ? ResolveType(field.Type) : BuiltInTypes.Unknown;
            if (member is PropertyDeclaration property)
                return ResolveType(property.Type);
            if (member is FunctionDeclaration func)
                return CreateFunctionTypeInfo(func);

            // If member not found, check base class
            if (classType.Declaration.BaseClass != null)
            {
                var baseType = ResolveType(classType.Declaration.BaseClass);
                var baseMember = ResolveMember(baseType, memberName);
                if (baseMember != BuiltInTypes.Unknown)
                    return baseMember;
            }
        }

        if (objectType is StructTypeInfo structType)
        {
            var member = structType.Declaration.Members.FirstOrDefault(m =>
                (m is FieldDeclaration fd && fd.Name == memberName) ||
                (m is PropertyDeclaration pd && pd.Name == memberName) ||
                (m is FunctionDeclaration func && func.Name == memberName));

            if (member is FieldDeclaration field)
                return field.Type != null ? ResolveType(field.Type) : BuiltInTypes.Unknown;
            if (member is PropertyDeclaration property)
                return ResolveType(property.Type);
            if (member is FunctionDeclaration func)
                return CreateFunctionTypeInfo(func);
        }

        if (objectType is RecordTypeInfo recordType)
        {
            var member = recordType.Declaration.Members.FirstOrDefault(m =>
                (m is FieldDeclaration fd && fd.Name == memberName) ||
                (m is PropertyDeclaration pd && pd.Name == memberName) ||
                (m is FunctionDeclaration func && func.Name == memberName));

            if (member is FieldDeclaration field)
                return field.Type != null ? ResolveType(field.Type) : BuiltInTypes.Unknown;
            if (member is PropertyDeclaration property)
                return ResolveType(property.Type);
            if (member is FunctionDeclaration func)
                return CreateFunctionTypeInfo(func);
        }

        if (objectType is InterfaceTypeInfo interfaceType)
        {
            var member = interfaceType.Declaration.Members.FirstOrDefault(m =>
                (m is PropertyDeclaration pd && pd.Name == memberName) ||
                (m is FunctionDeclaration func && func.Name == memberName));

            if (member is PropertyDeclaration property)
                return ResolveType(property.Type);
            if (member is FunctionDeclaration func)
                return CreateFunctionTypeInfo(func);
        }

        if (objectType is EnumTypeInfo)
        {
            return objectType;
        }

        if (objectType is UnionTypeInfo)
        {
            return objectType;
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

        // Multiple matches - return method group (for overload resolution)
        // For now, just return the first one
        // TODO: Implement proper method group resolution
        return CreateFunctionTypeInfo(applicableExtensions[0]);
    }

    private List<MethodInfo> FindExternalExtensionMethods(TypeInfo targetType, string methodName)
    {
        var targetClrType = TryConvertTypeInfoToClrType(targetType);
        if (targetClrType == null)
            return new List<MethodInfo>();

        var methods = new List<MethodInfo>();
        var assemblies = _referencedAssemblies
            .Concat(AppDomain.CurrentDomain.GetAssemblies())
            .Distinct()
            .ToList();

        foreach (var assembly in assemblies)
        {
            foreach (var type in GetLoadableTypes(assembly))
            {
                if (type.Namespace == null || !_usingNamespaces.Contains(type.Namespace))
                    continue;

                if (!(type.IsSealed && type.IsAbstract))
                    continue;

                foreach (var method in type.GetMethods(BindingFlags.Public | BindingFlags.Static))
                {
                    if (method.Name != methodName || !method.IsDefined(typeof(ExtensionAttribute), false))
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
        // Handle primitive types
        if (type == typeof(int)) return BuiltInTypes.Int;
        if (type == typeof(long)) return BuiltInTypes.Long;
        if (type == typeof(float)) return BuiltInTypes.Float;
        if (type == typeof(double)) return BuiltInTypes.Double;
        if (type == typeof(bool)) return BuiltInTypes.Bool;
        if (type == typeof(string)) return BuiltInTypes.String;
        if (type == typeof(void)) return BuiltInTypes.Void;
        if (type == typeof(object)) return BuiltInTypes.Object;

        // Handle arrays
        if (type.IsArray)
        {
            var elementType = ConvertReflectionType(type.GetElementType()!);
            return new ArrayTypeInfo(elementType);
        }

        // Handle generics
        if (type.IsGenericType)
        {
            var genericArgs = type.GetGenericArguments().Select(ConvertReflectionType).ToList();
            var genericName = type.Name.Substring(0, type.Name.IndexOf('`'));
            return new GenericTypeInfo(genericName, genericArgs);
        }

        // Default to reflection type
        return new ReflectionTypeInfo(type);
    }

    private static bool IsDelegateType(Type type)
    {
        return typeof(Delegate).IsAssignableFrom(type) && type != typeof(Delegate) && type != typeof(MulticastDelegate);
    }

    private FunctionTypeInfo CreateFunctionTypeInfoFromDelegate(Type delegateType)
    {
        if (delegateType.IsGenericType)
        {
            var genericDefinition = delegateType.GetGenericTypeDefinition();
            var typeArguments = delegateType.GetGenericArguments()
                .Select(ConvertReflectionType)
                .ToList();

            if (genericDefinition == typeof(Action<>)
                || genericDefinition == typeof(Action<,>)
                || genericDefinition == typeof(Action<,,>)
                || genericDefinition == typeof(Action<,,,>))
            {
                return new FunctionTypeInfo(null)
                {
                    ParameterTypes = typeArguments,
                    ReturnType = BuiltInTypes.Void
                };
            }

            if (genericDefinition == typeof(Func<>)
                || genericDefinition == typeof(Func<,>)
                || genericDefinition == typeof(Func<,,>)
                || genericDefinition == typeof(Func<,,,>)
                || genericDefinition == typeof(Func<,,,,>))
            {
                return new FunctionTypeInfo(null)
                {
                    ParameterTypes = typeArguments.Take(typeArguments.Count - 1).ToList(),
                    ReturnType = typeArguments[^1]
                };
            }
        }

        var invokeMethod = delegateType.GetMethod("Invoke");
        if (invokeMethod == null)
            return new FunctionTypeInfo(null) { ReturnType = BuiltInTypes.Unknown };

        return new FunctionTypeInfo(null)
        {
            ParameterTypes = invokeMethod.GetParameters()
                .Select(parameter => ConvertReflectionType(parameter.ParameterType))
                .ToList(),
            ReturnType = ConvertReflectionType(invokeMethod.ReturnType)
        };
    }

    private FunctionTypeInfo CreateFunctionTypeInfo(FunctionDeclaration func)
    {
        return new FunctionTypeInfo(func)
        {
            ParameterTypes = func.Parameters.Select(parameter => ResolveType(parameter.Type)).ToList(),
            ReturnType = func.ReturnType != null ? ResolveType(func.ReturnType) : BuiltInTypes.Void
        };
    }

    private Type? TryConvertTypeInfoToClrType(TypeInfo typeInfo)
    {
        var resolvedType = ResolveTypeAlias(typeInfo);

        return resolvedType switch
        {
            SimpleTypeInfo simple when simple == BuiltInTypes.Int => typeof(int),
            SimpleTypeInfo simple when simple == BuiltInTypes.Long => typeof(long),
            SimpleTypeInfo simple when simple == BuiltInTypes.Float => typeof(float),
            SimpleTypeInfo simple when simple == BuiltInTypes.Double => typeof(double),
            SimpleTypeInfo simple when simple == BuiltInTypes.Bool => typeof(bool),
            SimpleTypeInfo simple when simple == BuiltInTypes.String => typeof(string),
            SimpleTypeInfo simple when simple == BuiltInTypes.Void => typeof(void),
            SimpleTypeInfo simple when simple == BuiltInTypes.Object => typeof(object),
            ReflectionTypeInfo reflection => reflection.Type,
            ArrayTypeInfo array => TryConvertTypeInfoToClrType(array.ElementType)?.MakeArrayType(),
            NullableTypeInfo nullable => TryConvertNullableType(nullable.InnerType),
            GenericTypeInfo generic => TryConstructKnownGenericType(generic),
            FunctionTypeInfo function => TryConstructDelegateType(function),
            _ => null
        };
    }

    private Type? TryConvertNullableType(TypeInfo innerType)
    {
        var clrInnerType = TryConvertTypeInfoToClrType(innerType);
        if (clrInnerType == null)
            return null;

        return clrInnerType.IsValueType ? typeof(Nullable<>).MakeGenericType(clrInnerType) : clrInnerType;
    }

    private Type? TryConstructKnownGenericType(GenericTypeInfo genericType)
    {
        var typeDefinition = genericType.Name switch
        {
            "List" when genericType.TypeArguments.Count == 1 => typeof(List<>),
            "IEnumerable" when genericType.TypeArguments.Count == 1 => typeof(IEnumerable<>),
            "ICollection" when genericType.TypeArguments.Count == 1 => typeof(ICollection<>),
            "IList" when genericType.TypeArguments.Count == 1 => typeof(IList<>),
            "Dictionary" when genericType.TypeArguments.Count == 2 => typeof(Dictionary<,>),
            "IDictionary" when genericType.TypeArguments.Count == 2 => typeof(IDictionary<,>),
            "Task" when genericType.TypeArguments.Count == 1 => typeof(System.Threading.Tasks.Task<>),
            "ValueTask" when genericType.TypeArguments.Count == 1 => typeof(System.Threading.Tasks.ValueTask<>),
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
        if (functionType.ParameterTypes == null || functionType.ReturnType == null)
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

        if (clrReturnType == typeof(void))
        {
            return clrParameterTypes.Count switch
            {
                0 => typeof(Action),
                1 => typeof(Action<>).MakeGenericType(clrParameterTypes.ToArray()),
                2 => typeof(Action<,>).MakeGenericType(clrParameterTypes.ToArray()),
                3 => typeof(Action<,,>).MakeGenericType(clrParameterTypes.ToArray()),
                4 => typeof(Action<,,,>).MakeGenericType(clrParameterTypes.ToArray()),
                _ => null
            };
        }

        var funcTypes = clrParameterTypes.Concat(new[] { clrReturnType }).ToArray();
        return clrParameterTypes.Count switch
        {
            0 => typeof(Func<>).MakeGenericType(funcTypes),
            1 => typeof(Func<,>).MakeGenericType(funcTypes),
            2 => typeof(Func<,,>).MakeGenericType(funcTypes),
            3 => typeof(Func<,,,>).MakeGenericType(funcTypes),
            4 => typeof(Func<,,,,>).MakeGenericType(funcTypes),
            _ => null
        };
    }

    private TypeInfo AnalyzeCall(CallExpression call)
    {
        var calleeType = AnalyzeExpression(call.Callee);

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
            foreach (var arg in call.Arguments)
            {
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
                    // Use ErrorMessageBuilder for better error message
                    var sourceSnippet = _sourceLines != null && call.Line > 0 && call.Line <= _sourceLines.Length
                        ? _sourceLines[call.Line - 1]
                        : null;

                    if (sourceSnippet != null && _currentFilePath != null)
                    {
                        var error = ErrorMessageBuilder.WrongArgumentCount(
                            _currentFilePath,
                            call.Line,
                            call.Column,
                            sourceSnippet,
                            funcType.Declaration.Name.Length,
                            funcType.Declaration.Name,
                            minArgs,
                            argTypes.Count
                        );
                        _errors.Add(error);
                    }
                    else
                    {
                        Error($"Function '{funcType.Declaration.Name}' expects at least {minArgs} arguments but got {argTypes.Count}",
                            call.Line, call.Column);
                    }
                }
                else if (!hasParamsParameter && argTypes.Count > effectiveParamCount)
                {
                    // Use ErrorMessageBuilder for better error message
                    var sourceSnippet = _sourceLines != null && call.Line > 0 && call.Line <= _sourceLines.Length
                        ? _sourceLines[call.Line - 1]
                        : null;

                    if (sourceSnippet != null && _currentFilePath != null)
                    {
                        var error = ErrorMessageBuilder.WrongArgumentCount(
                            _currentFilePath,
                            call.Line,
                            call.Column,
                            sourceSnippet,
                            funcType.Declaration.Name.Length,
                            funcType.Declaration.Name,
                            effectiveParamCount,
                            argTypes.Count
                        );
                        _errors.Add(error);
                    }
                    else
                    {
                        Error($"Function '{funcType.Declaration.Name}' expects {effectiveParamCount} arguments but got {argTypes.Count}",
                            call.Line, call.Column);
                    }
                }
                else
                {
                    // Check each parameter type (non-params parameters)
                    int regularParamCount = hasParamsParameter ? effectiveParamCount - 1 : effectiveParamCount;
                    for (int i = 0; i < regularParamCount && i < argTypes.Count; i++)
                    {
                        // For extension methods, parameter index in declaration is i + paramStartIndex
                        int paramIndex = i + paramStartIndex;
                        var paramType = ResolveType(parameters[paramIndex].Type);
                        var argType = argTypes[i];

                        if (!IsAssignable(paramType, argType))
                        {
                            Error($"Argument {i + 1} of type '{argType}' is not assignable to parameter '{parameters[paramIndex].Name}' of type '{paramType}'",
                                call.Line, call.Column);
                        }
                    }

                    // Check params arguments (if any)
                    if (hasParamsParameter && argTypes.Count >= effectiveParamCount)
                    {
                        var paramsParam = parameters[^1];
                        var paramsArrayType = ResolveType(paramsParam.Type);

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
                                            Error($"Spread argument {i + 1} element type '{spreadArrayType.ElementType}' is not assignable to params array element type '{arrayType.ElementType}'",
                                                call.Line, call.Column);
                                        }
                                    }
                                    // If it's not an array type, it's an error
                                    else if (argType != BuiltInTypes.Unknown)
                                    {
                                        Error($"Spread argument {i + 1} must be an array or collection type, but got '{argType}'",
                                            call.Line, call.Column);
                                    }
                                }
                                else
                                {
                                    // Regular argument (not spread) - check element type directly
                                    if (!IsAssignable(arrayType.ElementType, argType))
                                    {
                                        Error($"Params argument {i + 1} of type '{argType}' is not assignable to params array element type '{arrayType.ElementType}'",
                                            call.Line, call.Column);
                                    }
                                }
                            }
                        }
                    }
                }

                // Return the declared return type
                if (funcType.Declaration.ReturnType != null)
                {
                    return ResolveType(funcType.Declaration.ReturnType);
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

            return ConvertReflectionType(methodInfo.Method.ReturnType);
        }

        // Handle method group (overloaded methods)
        if (calleeType is ReflectionMethodGroupInfo methodGroup)
        {
            var boundCall = BindReflectionCall(methodGroup, call);
            if (boundCall?.ReturnType != null)
                return boundCall.ReturnType;

            var compatibleMethods = methodGroup.Methods
                .Where(m => GetCallParameterCount(m, call) == call.Arguments.Count)
                .ToArray();

            if (compatibleMethods.Length > 0)
                return ConvertReflectionType(compatibleMethods[0].ReturnType);

            if (methodGroup.Methods.Length > 0)
                return ConvertReflectionType(methodGroup.Methods[0].ReturnType);
        }

        return BuiltInTypes.Unknown;
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

    private FunctionTypeInfo? BindReflectionCall(ReflectionMethodGroupInfo methodGroup, CallExpression call)
    {
        var receiverClrType = call.Callee is MemberAccessExpression memberAccess
            ? TryConvertTypeInfoToClrType(AnalyzeExpression(memberAccess.Object))
            : null;

        var analyzedNonLambdaArguments = new TypeInfo?[call.Arguments.Count];
        for (int i = 0; i < call.Arguments.Count; i++)
        {
            if (call.Arguments[i].Value is LambdaExpression)
                continue;

            analyzedNonLambdaArguments[i] = AnalyzeExpression(call.Arguments[i].Value);
        }

        (MethodInfo Method, Dictionary<Type, Type> Bindings, int Score)? selected = null;

        foreach (var method in methodGroup.Methods)
        {
            var candidate = PreBindReflectionMethod(method, call, receiverClrType, analyzedNonLambdaArguments);
            if (candidate == null)
                continue;

            if (selected == null || candidate.Value.Score > selected.Value.Score)
                selected = candidate;
        }

        if (selected == null)
            return null;

        return FinalizeBoundReflectionCall(selected.Value.Method, call, selected.Value.Bindings);
    }

    private FunctionTypeInfo? BindSingleReflectionMethod(MethodInfo method, CallExpression call)
    {
        var receiverClrType = call.Callee is MemberAccessExpression memberAccess
            ? TryConvertTypeInfoToClrType(AnalyzeExpression(memberAccess.Object))
            : null;

        var analyzedNonLambdaArguments = new TypeInfo?[call.Arguments.Count];
        for (int i = 0; i < call.Arguments.Count; i++)
        {
            if (call.Arguments[i].Value is LambdaExpression)
                continue;

            analyzedNonLambdaArguments[i] = AnalyzeExpression(call.Arguments[i].Value);
        }

        var preBound = PreBindReflectionMethod(method, call, receiverClrType, analyzedNonLambdaArguments);
        if (preBound == null)
            return null;

        return FinalizeBoundReflectionCall(preBound.Value.Method, call, preBound.Value.Bindings);
    }

    private (MethodInfo Method, Dictionary<Type, Type> Bindings, int Score)? PreBindReflectionMethod(
        MethodInfo method,
        CallExpression call,
        Type? receiverClrType,
        TypeInfo?[] analyzedNonLambdaArguments)
    {
        var bindings = new Dictionary<Type, Type>();
        var openMethod = method.IsGenericMethod ? method.GetGenericMethodDefinition() : method;
        var parameterOffset = IsExtensionMethodCall(openMethod, call) ? 1 : 0;
        var parameters = openMethod.GetParameters();

        if (parameterOffset == 1)
        {
            if (receiverClrType == null || !TryMatchReflectionParameter(parameters[0].ParameterType, receiverClrType, bindings))
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
                var typeArgument = TryConvertTypeInfoToClrType(ResolveType(call.TypeArguments[i]));
                if (typeArgument == null)
                    return null;

                bindings[genericParameters[i]] = typeArgument;
            }
        }

        if (!HasCompatibleReflectionArity(parameters, parameterOffset, call.Arguments.Count))
            return null;

        var score = parameterOffset == 1 ? 4 : 0;

        for (int i = 0; i < call.Arguments.Count; i++)
        {
            var parameter = GetReflectionParameterForArgument(parameters, parameterOffset, i);
            if (parameter == null)
                return null;

            var parameterType = parameter.ParameterType;
            if (call.Arguments[i].Value is LambdaExpression lambda)
            {
                var delegateType = ApplyReflectionBindings(parameterType, bindings);
                var signature = IsDelegateType(delegateType)
                    ? CreateFunctionTypeInfoFromDelegate(delegateType)
                    : null;

                if (signature?.ParameterTypes == null || signature.ParameterTypes.Count != lambda.Parameters.Count)
                    return null;

                score += 2 + signature.ParameterTypes.Count;
                continue;
            }

            var argumentType = analyzedNonLambdaArguments[i];
            if (argumentType == null)
                return null;

            var argumentClrType = TryConvertTypeInfoToClrType(argumentType);
            if (argumentClrType != null)
            {
                if (!TryMatchReflectionParameter(parameterType, argumentClrType, bindings))
                    return null;

                score += GetReflectionMatchScore(ApplyReflectionBindings(parameterType, bindings), argumentClrType);
                continue;
            }

            var expectedType = ConvertReflectionType(ApplyReflectionBindings(parameterType, bindings));
            if (!IsAssignable(expectedType, argumentType))
                return null;

            score += 1;
        }

        return (openMethod, bindings, score);
    }

    private FunctionTypeInfo? FinalizeBoundReflectionCall(MethodInfo method, CallExpression call, Dictionary<Type, Type> bindings)
    {
        var workingBindings = new Dictionary<Type, Type>(bindings);
        var parameterOffset = IsExtensionMethodCall(method, call) ? 1 : 0;
        var parameters = method.GetParameters();

        for (int i = 0; i < call.Arguments.Count; i++)
        {
            if (call.Arguments[i].Value is not LambdaExpression lambda)
                continue;

            var parameter = GetReflectionParameterForArgument(parameters, parameterOffset, i);
            if (parameter == null)
                return null;

            var delegateType = ApplyReflectionBindings(parameter.ParameterType, workingBindings);
            if (!IsDelegateType(delegateType))
                return null;

            var expectedSignature = CreateFunctionTypeInfoFromDelegate(delegateType);
            var lambdaType = AnalyzeLambda(lambda, expectedSignature);
            var lambdaDelegateType = TryConstructDelegateType(lambdaType);
            if (lambdaDelegateType != null)
                TryMatchReflectionParameter(parameter.ParameterType, lambdaDelegateType, workingBindings);

            var lambdaReturnClrType = lambdaType.ReturnType != null
                ? TryConvertTypeInfoToClrType(lambdaType.ReturnType)
                : null;
            if (lambdaReturnClrType != null && method.IsGenericMethodDefinition)
            {
                var remainingGenericArguments = method.GetGenericArguments()
                    .Where(argument => !workingBindings.ContainsKey(argument))
                    .ToList();

                if (remainingGenericArguments.Count == 1)
                    workingBindings[remainingGenericArguments[0]] = lambdaReturnClrType;
            }
        }

        if (method.IsGenericMethodDefinition)
        {
            var genericArguments = method.GetGenericArguments();
            if (genericArguments.Any(argument => !workingBindings.ContainsKey(argument)))
                return null;

            method = method.MakeGenericMethod(genericArguments.Select(argument => workingBindings[argument]).ToArray());
            parameters = method.GetParameters();
            parameterOffset = IsExtensionMethodCall(method, call) ? 1 : 0;
        }

        var parameterTypes = new List<TypeInfo>();
        var validatedArgumentTypes = new List<TypeInfo>();

        for (int i = 0; i < call.Arguments.Count; i++)
        {
            var parameter = GetReflectionParameterForArgument(parameters, parameterOffset, i);
            if (parameter == null)
                return null;

            var rawParameterType = parameter.ParameterType.IsArray && IsParamsParameter(parameter) && i >= parameters.Length - parameterOffset - 1
                ? parameter.ParameterType.GetElementType()!
                : parameter.ParameterType;

            if (call.Arguments[i].Value is LambdaExpression lambda && IsDelegateType(rawParameterType))
            {
                var expectedSignature = CreateFunctionTypeInfoFromDelegate(rawParameterType);
                parameterTypes.Add(expectedSignature);

                var lambdaArgumentType = AnalyzeLambda(lambda, expectedSignature);
                validatedArgumentTypes.Add(lambdaArgumentType);
                continue;
            }

            var expectedType = ConvertReflectionType(rawParameterType);
            parameterTypes.Add(expectedType);

            var argumentType = AnalyzeExpressionWithExpectedType(call.Arguments[i].Value, expectedType);
            validatedArgumentTypes.Add(argumentType);

            if (!IsAssignable(expectedType, argumentType))
                return null;
        }

        return new FunctionTypeInfo(null)
        {
            ParameterTypes = parameterTypes,
            ReturnType = ConvertReflectionType(method.ReturnType)
        };
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

    private static ParameterInfo? GetReflectionParameterForArgument(ParameterInfo[] parameters, int parameterOffset, int argumentIndex)
    {
        var effectiveParameters = parameters.Skip(parameterOffset).ToArray();
        if (effectiveParameters.Length == 0)
            return null;

        if (argumentIndex < effectiveParameters.Length)
            return effectiveParameters[argumentIndex];

        return IsParamsParameter(effectiveParameters[^1]) ? effectiveParameters[^1] : null;
    }

    private static bool IsParamsParameter(ParameterInfo parameter)
    {
        return parameter.GetCustomAttributes(typeof(ParamArrayAttribute), false).Length > 0;
    }

    private static bool IsExtensionMethodCall(MethodInfo method, CallExpression call)
    {
        return call.Callee is MemberAccessExpression && method.IsDefined(typeof(ExtensionAttribute), false);
    }

    private static int GetCallParameterCount(MethodInfo method, CallExpression call)
    {
        return Math.Max(0, method.GetParameters().Length - (IsExtensionMethodCall(method, call) ? 1 : 0));
    }

    private static int GetReflectionMatchScore(Type parameterType, Type argumentType)
    {
        if (parameterType == argumentType)
            return 8;

        if (parameterType.IsAssignableFrom(argumentType))
            return 4;

        return 2;
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
            return parameterType.IsAssignableFrom(argumentType);

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
        var targetType = AnalyzeExpression(assignment.Target);
        var valueType = AnalyzeExpression(assignment.Value);

        // Check for readonly field assignment outside constructor
        CheckReadonlyFieldAssignment(assignment.Target, assignment.Line, assignment.Column);

        if (!IsAssignable(targetType, valueType))
        {
            var sourceSnippet = _sourceLines != null && assignment.Line > 0 && assignment.Line <= _sourceLines.Length
                ? _sourceLines[assignment.Line - 1]
                : null;

            if (sourceSnippet != null && _currentFilePath != null)
            {
                var error = ErrorMessageBuilder.TypeMismatch(
                    _currentFilePath,
                    assignment.Line,
                    assignment.Column,
                    sourceSnippet,
                    1,
                    valueType.ToString(),
                    targetType.ToString()
                );
                _errors.Add(error);
            }
            else
            {
                Error($"Cannot assign '{valueType}' to '{targetType}'", assignment.Line, assignment.Column);
            }
        }

        return targetType;
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
                Error($"Cannot assign to readonly field '{fieldName}' outside of a constructor", line, column);
            }
        }
    }

    private FunctionTypeInfo AnalyzeLambda(LambdaExpression lambda, TypeInfo? expectedType = null)
    {
        var expectedSignature = GetFunctionSignature(expectedType);
        PushScope(new Scope(ScopeKind.Function));
        var parameterTypes = new List<TypeInfo>();

        foreach (var param in lambda.Parameters)
        {
            // Parser uses `var` as the placeholder type for untyped lambda parameters,
            // so only treat the parameter as explicit when it is something other than `var`.
            var paramIndex = parameterTypes.Count;
            var hasExplicitType = param.Type is not null
                && param.Type is not SimpleTypeReference { Name: "var" };

            var paramType = hasExplicitType
                ? ResolveType(param.Type)
                : expectedSignature?.ParameterTypes != null && paramIndex < expectedSignature.ParameterTypes.Count
                    ? expectedSignature.ParameterTypes[paramIndex]
                    : BuiltInTypes.Unknown;
            DeclareSymbol(param.Name, paramType, lambda.Line, lambda.Column);
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
            _currentReturnType = expectedSignature?.ReturnType;
            AnalyzeStatement(lambda.BlockBody);
            _currentReturnType = previousReturnType;
            returnType = expectedSignature?.ReturnType ?? BuiltInTypes.Void;
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

        return null;
    }

    private TypeInfo AnalyzeTernary(TernaryExpression ternary)
    {
        var condType = AnalyzeExpression(ternary.Condition);
        if (!IsBoolType(condType))
        {
            Error("Ternary condition must be boolean", ternary.Line, ternary.Column);
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
                Error($"Array element type mismatch", array.Line, array.Column);
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
                    if (baseType is UnionTypeInfo)
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
        return new ReflectionTypeInfo(typeof(Type));
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
            PushScope(new Scope(ScopeKind.Block));

            // Analyze pattern and bind variables
            AnalyzePattern(matchCase.Pattern, valueType);

            // Analyze guard expression if present
            if (matchCase.Guard != null)
            {
                var guardType = AnalyzeExpression(matchCase.Guard);
                if (!IsAssignable(BuiltInTypes.Bool, guardType))
                {
                    Error(ErrorCode.GuardNotBoolean, $"Guard expression must be of type 'bool', but got '{guardType}'",
                        matchCase.Guard.Line, matchCase.Guard.Column);
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
                Error($"Match case has incompatible type '{caseType}', expected '{resultType}'",
                    matchCase.Expression.Line, matchCase.Expression.Column);
            }

            PopScope();
        }

        // Check exhaustiveness for union types (after analyzing patterns to report specific errors first)
        // Note: Skip exhaustiveness check if any guards are present, as guards can make patterns conditional
        if (valueType is UnionTypeInfo unionType && !match.Cases.Any(c => c.Guard != null))
        {
            CheckMatchExhaustiveness(match, unionType);
        }

        return resultType ?? BuiltInTypes.Unknown;
    }

    private void CheckMatchExhaustiveness(MatchExpression match, UnionTypeInfo unionType)
    {
        // Collect all union case names that are covered in the match
        var coveredCases = new HashSet<string>();

        foreach (var matchCase in match.Cases)
        {
            if (matchCase.Pattern is UnionCasePattern unionPattern)
            {
                // Extract just the case name (after the last dot if qualified)
                var caseName = unionPattern.CaseName.Contains('.')
                    ? unionPattern.CaseName.Substring(unionPattern.CaseName.LastIndexOf('.') + 1)
                    : unionPattern.CaseName;
                coveredCases.Add(caseName);
            }
            else if (matchCase.Pattern is IdentifierPattern identPattern)
            {
                if (identPattern.Name == "_")
                {
                    // Wildcard pattern covers all remaining cases
                    return;
                }
                else if (identPattern.Name.Contains('.'))
                {
                    // Qualified union case name without properties
                    var caseName = identPattern.Name.Substring(identPattern.Name.LastIndexOf('.') + 1);
                    coveredCases.Add(caseName);
                }
            }
        }

        // Check if all union cases are covered
        var allCases = unionType.Declaration.Cases.Select(c => c.Name).ToHashSet();
        var missingCases = allCases.Except(coveredCases).ToList();

        if (missingCases.Any())
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
                Error(ErrorCode.NonExhaustiveMatch, $"Match expression is not exhaustive. Missing cases: {missingCasesStr}",
                    match.Line, match.Column, ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, missingCasesStr));
            }
        }
    }

    // Type resolution
    private TypeInfo ResolveType(TypeReference typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => ResolveSimpleType(simple.Name),
            GenericTypeReference generic => new GenericTypeInfo(generic.Name,
                generic.TypeArguments.Select(ResolveType).ToList()),
            ArrayTypeReference array => new ArrayTypeInfo(ResolveType(array.ElementType)),
            NullableTypeReference nullable => new NullableTypeInfo(ResolveType(nullable.InnerType)),
            TupleTypeReference tuple => new TupleTypeInfo(
                tuple.Elements.Select(e => (e.Name, ResolveType(e.Type))).ToList()),
            FunctionTypeReference function => new FunctionTypeInfo(null)
            {
                ParameterTypes = function.ParameterTypes.Select(ResolveType).ToList(),
                ReturnType = ResolveType(function.ReturnType)
            },
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo ResolveSimpleType(string name)
    {
        // Check built-in types
        var builtInType = name switch
        {
            "int" => BuiltInTypes.Int,
            "long" => BuiltInTypes.Long,
            "float" => BuiltInTypes.Float,
            "double" => BuiltInTypes.Double,
            "bool" => BuiltInTypes.Bool,
            "string" => BuiltInTypes.String,
            "void" => BuiltInTypes.Void,
            "object" => BuiltInTypes.Object,
            "var" => BuiltInTypes.Unknown, // Treat 'var' as unknown for type inference
            _ => null
        };

        if (builtInType != null)
            return builtInType;

        // Check local type declarations
        var localType = LookupType(name);
        if (localType != null)
            return localType;

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

        // Return unknown type (not an error - might be from C# library)
        return new ExternalTypeInfo(name);
    }

    private TypeInfo? TryResolveExternalType(string name)
    {
        // Check cache first
        if (_externalTypeCache.TryGetValue(name, out var cachedType))
            return new ReflectionTypeInfo(cachedType);

        // Try direct type lookup in common assemblies
        var type = Type.GetType(name);
        if (type != null)
        {
            _externalTypeCache[name] = type;
            return new ReflectionTypeInfo(type);
        }

        // Try with using namespaces
        foreach (var ns in _usingNamespaces)
        {
            var fullName = $"{ns}.{name}";

            // Check cache for full name
            if (_externalTypeCache.TryGetValue(fullName, out cachedType))
                return new ReflectionTypeInfo(cachedType);

            // Try core library
            type = Type.GetType($"{fullName}, System.Runtime");
            if (type != null)
            {
                _externalTypeCache[fullName] = type;
                return new ReflectionTypeInfo(type);
            }

            // Try System.Private.CoreLib
            type = Type.GetType($"{fullName}, System.Private.CoreLib");
            if (type != null)
            {
                _externalTypeCache[fullName] = type;
                return new ReflectionTypeInfo(type);
            }

            // Try without assembly qualification
            type = Type.GetType(fullName);
            if (type != null)
            {
                _externalTypeCache[fullName] = type;
                return new ReflectionTypeInfo(type);
            }

            // Try common assemblies
            var assemblies = new[]
            {
                Assembly.Load("System.Runtime"),
                Assembly.Load("System.Console"),
                Assembly.Load("System.Linq"),
                typeof(object).Assembly // mscorlib/System.Private.CoreLib
            };

            foreach (var assembly in assemblies)
            {
                type = assembly.GetType(fullName);
                if (type != null)
                {
                    _externalTypeCache[fullName] = type;
                    return new ReflectionTypeInfo(type);
                }
            }

            // Try referenced assemblies (NEW)
            foreach (var assembly in _referencedAssemblies)
            {
                try
                {
                    type = assembly.GetType(fullName);
                }
                catch
                {
                    continue;
                }
                if (type != null)
                {
                    _externalTypeCache[fullName] = type;
                    return new ReflectionTypeInfo(type);
                }
            }
        }

        // Try without namespace in referenced assemblies (NEW)
        foreach (var assembly in _referencedAssemblies)
        {
            // Search all exported types in the assembly
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
            catch
            {
                // Some assemblies may not expose all types
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

        // Try to resolve as external type (for static class access like Console)
        var externalType = TryResolveExternalType(name);
        if (externalType != null)
        {
            type = externalType;
            return true;
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
            if (memberType != BuiltInTypes.Unknown)
            {
                type = memberType;
                return true;
            }
        }

        type = BuiltInTypes.Unknown;
        return false;
    }

    private TypeInfo ResolveIdentifier(string name, int line, int column)
    {
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
            Error(ErrorCode.UndefinedVariable, $"Undefined identifier '{name}'", line, column);
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
        bool isPascalCase = char.IsUpper(name[0]);
        bool isCamelCase = char.IsLower(name[0]);

        bool hasExplicitVisibility = modifiers.HasFlag(Modifiers.Public)
            || modifiers.HasFlag(Modifiers.Private)
            || modifiers.HasFlag(Modifiers.Internal)
            || modifiers.HasFlag(Modifiers.Protected);

        // If explicit modifiers are present, don't check convention
        if (hasExplicitVisibility)
            return;

        // Check convention: PascalCase = public, camelCase = private
        if (isPascalCase)
        {
            // Should be public (convention)
        }
        else if (isCamelCase)
        {
            // Should be private (convention)
        }
        else
        {
            Warning($"Identifier '{name}' doesn't follow naming convention (PascalCase for public, camelCase for private)",
                line, column);
        }
    }

    // Type checking helpers
    private bool IsAssignable(TypeInfo target, TypeInfo source)
    {
        // Resolve type aliases
        var resolvedTarget = ResolveTypeAlias(target);
        var resolvedSource = ResolveTypeAlias(source);

        if (resolvedTarget == resolvedSource) return true;
        if (resolvedSource == BuiltInTypes.Null && resolvedTarget is NullableTypeInfo) return true;
        if (resolvedSource == BuiltInTypes.Never) return true;
        if (resolvedSource == BuiltInTypes.Unknown || resolvedTarget == BuiltInTypes.Unknown) return true;

        // Handle external types (assume compatible if we can't resolve)
        if (resolvedSource is ExternalTypeInfo || resolvedTarget is ExternalTypeInfo) return true;
        if (resolvedSource is ReflectionTypeInfo || resolvedTarget is ReflectionTypeInfo) return true;
        if (resolvedSource is ReflectionMethodInfo || resolvedTarget is ReflectionMethodInfo) return true;
        if (resolvedSource is ReflectionMethodGroupInfo || resolvedTarget is ReflectionMethodGroupInfo) return true;

        // Same type name
        if (resolvedTarget.ToString() == resolvedSource.ToString()) return true;

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

        // TODO: More sophisticated type compatibility checking
        return false;
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
        return type;
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
            || type == BuiltInTypes.Float || type == BuiltInTypes.Double;
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

    private TypeInfo GetWiderType(TypeInfo left, TypeInfo right)
    {
        if (left == BuiltInTypes.Double || right == BuiltInTypes.Double) return BuiltInTypes.Double;
        if (left == BuiltInTypes.Float || right == BuiltInTypes.Float) return BuiltInTypes.Float;
        if (left == BuiltInTypes.Long || right == BuiltInTypes.Long) return BuiltInTypes.Long;
        return BuiltInTypes.Int;
    }

    private TypeInfo GetCommonType(TypeInfo left, TypeInfo right)
    {
        if (left == right) return left;
        if (IsNumericType(left) && IsNumericType(right)) return GetWiderType(left, right);
        return BuiltInTypes.Unknown;
    }

    // Scope management
    private void PushScope(Scope scope)
    {
        _scopes.Push(scope);
    }

    private void PopScope()
    {
        _scopes.Pop();
    }

    private void DeclareSymbol(string name, TypeInfo type, int line, int column)
    {
        var currentScope = _scopes.Peek();
        if (currentScope.Symbols.ContainsKey(name))
        {
            Error($"Symbol '{name}' is already declared in this scope", line, column);
        }
        else
        {
            currentScope.Symbols[name] = type;

            // Record declaration in binding map for semantic references
            var kind = TypeInfoToDeclarationKind(type);
            var decl = new SymbolDeclaration(name, _currentFilePath, line, column, kind);
            _bindingMap.RecordDeclaration(decl);
            // Also record the declaration location in the scope for later lookup
            currentScope.RecordDeclarationLocation(name, _currentFilePath, line, column, kind);
        }
    }

    private void DeclareType(string name, TypeInfo type, int line, int column)
    {
        var currentScope = _scopes.Peek();
        if (currentScope.Types.ContainsKey(name))
        {
            Error($"Type '{name}' is already declared", line, column);
        }
        else
        {
            currentScope.Types[name] = type;
            if (!string.IsNullOrEmpty(_currentFilePath))
            {
                _typeDeclarationFiles[name] = _currentFilePath;
            }

            // Record type declaration in binding map
            var kind = TypeInfoToDeclarationKind(type);
            var decl = new SymbolDeclaration(name, _currentFilePath, line, column, kind);
            _bindingMap.RecordDeclaration(decl);
            currentScope.RecordDeclarationLocation(name, _currentFilePath, line, column, kind);
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
                // params must be last parameter
                if (i != parameters.Count - 1)
                {
                    Error("A params parameter must be the last parameter in a parameter list", line, column);
                }

                // C# 13: params can be array, Span<T>, ReadOnlySpan<T>, or collection types
                if (!IsValidParamsType(param.Type))
                {
                    Error($"A params parameter must be an array, Span<T>, ReadOnlySpan<T>, or a collection type (IEnumerable<T>, IList<T>, etc.), got '{TranspileTypeReference(param.Type)}'", line, column);
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
                    Error(ErrorCode.InvalidDefaultParameterValue,
                        $"Default parameter value for '{param.Name}' must be a compile-time constant (literal, null, or simple constant expression)",
                        line, column);
                }
            }
            else
            {
                // Required parameter found after optional parameter
                if (foundOptional)
                {
                    Error(ErrorCode.RequiredParameterAfterOptional,
                        $"Required parameter '{param.Name}' cannot appear after optional parameters",
                        line, column);
                }
            }
        }
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
            _ => typeRef.ToString() ?? "unknown"
        };
    }

    private void ValidateOperatorOverload(FunctionDeclaration func)
    {
        // Operator overloads must be static
        if (!func.Modifiers.HasFlag(Modifiers.Static))
        {
            Error("Operator overloads must be static", func.Line, func.Column);
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
            Error($"Unsupported operator '{func.OperatorSymbol}' for overloading", func.Line, func.Column);
            return;
        }

        // Note: +/- can be both unary and binary, so we allow 1 or 2 parameters
        if (func.OperatorSymbol is "+" or "-")
        {
            if (func.Parameters.Count != 1 && func.Parameters.Count != 2)
            {
                Error($"Operator '{func.OperatorSymbol}' must have 1 (unary) or 2 (binary) parameters", func.Line, func.Column);
            }
        }
        else if (func.Parameters.Count != expectedParams)
        {
            Error($"Operator '{func.OperatorSymbol}' must have {expectedParams} parameter(s), got {func.Parameters.Count}", func.Line, func.Column);
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
                Error($"Invalid package name: '{part}' is not a valid identifier", package.Line, package.Column);
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

        // Parse the imported file
        CompilationUnit? importedUnit = null;
        try
        {
            var source = System.IO.File.ReadAllText(resolvedPath);
            var lexer = new Lexer(source, resolvedPath);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, resolvedPath, source);  // Pass source code
            var parseResult = parser.ParseCompilationUnit();
            importedUnit = parseResult.CompilationUnit;

            // Report parse errors
            foreach (var error in parseResult.Errors)
            {
                Error($"Parse error in imported file '{import.Path}': {error.Message}", import.Line, import.Column);
            }

            if (importedUnit == null)
            {
                return;  // Can't continue without compilation unit
            }
        }
        catch (Exception ex)
        {
            Error($"Failed to parse imported file '{import.Path}': {ex.Message}", import.Line, import.Column);
            return;
        }

        // Extract public symbols from the imported file
        var symbols = ExtractPublicSymbols(importedUnit, resolvedPath);

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
                $"Cannot import type '{namespaceName}'; imports must target namespaces",
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
            $"Namespace '{namespaceName}' not found",
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

        var type = Type.GetType(fullName);
        if (type != null)
        {
            _externalTypeCache[fullName] = type;
            return type;
        }

        foreach (var assembly in GetExternalSearchAssemblies())
        {
            try
            {
                type = assembly.GetType(fullName, throwOnError: false, ignoreCase: false);
            }
            catch
            {
                continue;
            }

            if (type != null)
            {
                _externalTypeCache[fullName] = type;
                return type;
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

        foreach (var filePath in Directory.EnumerateFiles(projectRoot, "*.nl", SearchOption.AllDirectories))
        {
            if (IsBuildArtifactPath(filePath))
            {
                continue;
            }

            try
            {
                var source = File.ReadAllText(filePath);
                var lexer = new Lexer(source, filePath);
                var parser = new Parser(lexer.Tokenize(), filePath, source);
                var parseResult = parser.ParseCompilationUnit();
                var declaredNamespace = parseResult.CompilationUnit?.Namespace?.Name;
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

    private static bool IsBuildArtifactPath(string filePath)
    {
        return filePath.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal) ||
               filePath.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal);
    }

    private IEnumerable<Assembly> GetExternalSearchAssemblies()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            var assemblyName = assembly.FullName ?? assembly.GetName().Name;
            if (!string.IsNullOrEmpty(assemblyName) && seen.Add(assemblyName))
            {
                yield return assembly;
            }
        }

        foreach (var assembly in _referencedAssemblies)
        {
            var assemblyName = assembly.FullName ?? assembly.GetName().Name;
            if (!string.IsNullOrEmpty(assemblyName) && seen.Add(assemblyName))
            {
                yield return assembly;
            }
        }
    }

    private List<ImportedSymbolInfo> ExtractPublicSymbols(CompilationUnit unit, string filePath)
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
                FunctionDeclaration f => f.Name,
                _ => null
            };

            if (name != null && !string.IsNullOrEmpty(name) && char.IsUpper(name[0]))
            {
                // Only export PascalCase (public) symbols
                var typeInfo = decl switch
                {
                    ClassDeclaration c => new ClassTypeInfo(c) as TypeInfo,
                    StructDeclaration s => new StructTypeInfo(s),
                    RecordDeclaration r => new RecordTypeInfo(r),
                    InterfaceDeclaration i => new InterfaceTypeInfo(i),
                    UnionDeclaration u => new UnionTypeInfo(u),
                    EnumDeclaration e => new EnumTypeInfo(e),
                    TypeAliasDeclaration a => new AliasTypeInfo(a.Type),
                    FunctionDeclaration f => CreateFunctionTypeInfo(f),
                    _ => null
                };

                if (typeInfo != null)
                {
                    symbols.Add(new ImportedSymbolInfo(
                        name,
                        typeInfo,
                        new SymbolDeclaration(name, filePath, decl.Line, decl.Column, GetDeclarationKind(decl))));
                }
            }
        }

        return symbols;
    }

    private static bool IsTypeDeclarationKind(string kind) =>
        kind is "class" or "struct" or "record" or "interface" or "enum" or "union" or "typeAlias";

    private void CheckImportCollisions()
    {
        foreach (var (symbol, sources) in _importedSymbols)
        {
            if (sources.Count > 1)
            {
                Error($"Symbol '{symbol}' imported from multiple sources: {string.Join(", ", sources)}. Use aliasing to resolve the conflict.", 0, 0);
            }
        }
    }

    /// <summary>
    /// Load a .NET assembly by file path for type resolution
    /// </summary>
    public void LoadReferencedAssembly(string assemblyPath)
    {
        try
        {
            var assembly = Assembly.LoadFrom(assemblyPath);
            if (!_referencedAssemblies.Contains(assembly))
            {
                _referencedAssemblies.Add(assembly);
            }
        }
        catch (Exception ex)
        {
            // Log but don't fail - assembly might not be needed
            Console.Error.WriteLine($"Warning: Could not load assembly from {assemblyPath}: {ex.Message}");
        }
    }

    /// <summary>
    /// Load a .NET assembly by name (e.g., "System.Runtime") for type resolution
    /// </summary>
    public void LoadReferencedAssemblyByName(string assemblyName)
    {
        try
        {
            var assembly = Assembly.Load(assemblyName);
            if (!_referencedAssemblies.Contains(assembly))
            {
                _referencedAssemblies.Add(assembly);
            }
        }
        catch (FileNotFoundException)
        {
            // Try loading from ASP.NET Core shared framework
            if (TryLoadFromSharedFramework(assemblyName))
            {
                return;
            }
            // Assembly not found - this is expected for some references
        }
        catch (Exception)
        {
            // Try loading from shared framework for ANY exception
            if (TryLoadFromSharedFramework(assemblyName))
            {
                return;
            }
        }
    }

    /// <summary>
    /// Try to load an assembly from the .NET shared frameworks
    /// </summary>
    private bool TryLoadFromSharedFramework(string assemblyName)
    {
        try
        {
            // Get the runtime directory (where shared frameworks are installed)
            // RuntimeEnvironment.GetRuntimeDirectory() returns something like:
            // /opt/homebrew/Cellar/dotnet/9.0.8/libexec/shared/Microsoft.NETCore.App/9.0.8/
            var runtimeDir = System.Runtime.InteropServices.RuntimeEnvironment.GetRuntimeDirectory();

            // Navigate up to find the "shared" directory
            // runtimeDir ends in something like /Microsoft.NETCore.App/9.0.8/
            // We need to go up to /libexec/shared/
            var currentDir = runtimeDir;
            string? sharedFrameworksPath = null;

            // Go up the directory tree looking for a "shared" folder
            for (int i = 0; i < 5; i++)
            {
                currentDir = Path.GetDirectoryName(currentDir);
                if (currentDir == null) break;

                if (Path.GetFileName(currentDir) == "shared")
                {
                    sharedFrameworksPath = currentDir;
                    break;
                }
            }

            if (sharedFrameworksPath == null || !Directory.Exists(sharedFrameworksPath))
            {
                return false;
            }

            // Check both Microsoft.AspNetCore.App and Microsoft.NETCore.App
            var frameworkNames = new[] { "Microsoft.AspNetCore.App", "Microsoft.NETCore.App" };

            foreach (var frameworkName in frameworkNames)
            {
                var frameworkPath = Path.Combine(sharedFrameworksPath, frameworkName);
                if (!Directory.Exists(frameworkPath)) continue;

                // Get the latest version directory
                var versions = Directory.GetDirectories(frameworkPath)
                    .Select(Path.GetFileName)
                    .OrderByDescending(v => v)
                    .ToList();

                foreach (var version in versions)
                {
                    var assemblyPath = Path.Combine(frameworkPath, version!, $"{assemblyName}.dll");
                    if (File.Exists(assemblyPath))
                    {
                        LoadReferencedAssembly(assemblyPath);
                        return true;
                    }
                }
            }

            return false;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Load system assemblies that are commonly used
    /// </summary>
    public void LoadSystemAssemblies()
    {
        // Ensure the static assembly resolver is registered (idempotent, thread-safe)
        s_assemblyResolver.EnsureRegistered();

        var commonAssemblies = new[]
        {
            "System.Runtime",
            "System.Console",
            "System.Collections",
            "System.Linq",
            "System.Net.Http",
            "System.Text.Json",
            "System.Threading.Tasks"
        };

        foreach (var assemblyName in commonAssemblies)
        {
            LoadReferencedAssemblyByName(assemblyName);
        }
    }

    /// <summary>
    /// Static, process-singleton assembly resolver for transitive NuGet/framework dependencies.
    /// Registered once on AppDomain.CurrentDomain.AssemblyResolve and shared across all Analyzer instances.
    /// Uses a lock for thread-safe resolution and caches successful results only.
    /// </summary>
    internal sealed class AssemblyResolver
    {
        private static readonly string[] Tfms = { "net9.0", "net8.0", "net7.0", "net6.0", "netstandard2.1", "netstandard2.0" };
        private static readonly string[] FrameworkNames = { "Microsoft.AspNetCore.App", "Microsoft.NETCore.App" };

        // Successful resolutions only — misses are NOT cached so they can be retried after restore/install.
        private readonly System.Collections.Concurrent.ConcurrentDictionary<string, Assembly> _cache = new(StringComparer.OrdinalIgnoreCase);
        private readonly object _resolveLock = new();
        private readonly HashSet<string> _resolving = new(StringComparer.OrdinalIgnoreCase); // same-thread reentrancy guard (under lock)
        private bool _registered;

        public void EnsureRegistered()
        {
            // Lock ensures the handler is fully attached before any caller proceeds.
            lock (_resolveLock)
            {
                if (_registered) return;
                AppDomain.CurrentDomain.AssemblyResolve += OnAssemblyResolve;
                _registered = true;
            }
        }

        private Assembly? OnAssemblyResolve(object? sender, ResolveEventArgs args)
        {
            var asmName = new AssemblyName(args.Name);
            var simpleName = asmName.Name;
            if (simpleName == null) return null;

            // Fast path: return cached successful resolution
            if (_cache.TryGetValue(simpleName, out var cached))
                return cached;

            // Serialize resolution so concurrent threads wait rather than returning null.
            // The lock also protects the reentrancy guard set.
            lock (_resolveLock)
            {
                // Double-check after acquiring lock
                if (_cache.TryGetValue(simpleName, out cached))
                    return cached;

                // Reentrancy guard: if this thread is already resolving this name
                // (e.g. Assembly.LoadFrom triggered another AssemblyResolve for the same name),
                // return null to break the cycle.
                if (!_resolving.Add(simpleName))
                    return null;

                try
                {
                    var result = ResolveAssembly(simpleName);
                    if (result != null)
                        _cache[simpleName] = result;
                    return result;
                }
                finally
                {
                    _resolving.Remove(simpleName);
                }
            }
        }

        private static Assembly? ResolveAssembly(string simpleName)
        {
            // Check already-loaded assemblies in the AppDomain
            foreach (var loaded in AppDomain.CurrentDomain.GetAssemblies())
            {
                try
                {
                    if (string.Equals(loaded.GetName().Name, simpleName, StringComparison.OrdinalIgnoreCase))
                        return loaded;
                }
                catch { /* skip assemblies that can't report their name */ }
            }

            var nugetRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".nuget", "packages");

            // Try exact NuGet package match (assembly name == package name)
            var nugetExact = Path.Combine(nugetRoot, simpleName.ToLowerInvariant());
            var found = TryLoadFromNuGetPackageDir(nugetExact, simpleName);
            if (found != null) return found;

            // Fallback: search NuGet packages with matching prefix
            // (handles cases like Microsoft.CodeAnalysis in package microsoft.codeanalysis.common)
            if (Directory.Exists(nugetRoot))
            {
                try
                {
                    var prefix = simpleName.ToLowerInvariant();
                    foreach (var pkgDir in Directory.GetDirectories(nugetRoot))
                    {
                        var dirName = Path.GetFileName(pkgDir);
                        if (dirName == null || !dirName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                            continue;

                        var result = TryLoadFromNuGetPackageDir(pkgDir, simpleName);
                        if (result != null) return result;
                    }
                }
                catch { /* NuGet prefix search failed */ }
            }

            // Try shared framework directories
            return TryLoadFromSharedFrameworks(simpleName);
        }

        private static Assembly? TryLoadFromNuGetPackageDir(string packageDir, string simpleName)
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
                    try { return Assembly.LoadFrom(dllPath); }
                    catch { /* continue searching */ }
                }
            }
            return null;
        }

        private static Assembly? TryLoadFromSharedFrameworks(string simpleName)
        {
            try
            {
                var runtimeDir = System.Runtime.InteropServices.RuntimeEnvironment.GetRuntimeDirectory();
                var searchDir = runtimeDir;

                for (int i = 0; i < 5; i++)
                {
                    searchDir = Path.GetDirectoryName(searchDir);
                    if (searchDir == null) break;
                    if (Path.GetFileName(searchDir) == "shared")
                    {
                        foreach (var fw in FrameworkNames)
                        {
                            var fwPath = Path.Combine(searchDir, fw);
                            if (!Directory.Exists(fwPath)) continue;

                            foreach (var ver in Directory.GetDirectories(fwPath).OrderByDescending(d => d))
                            {
                                var dllPath = Path.Combine(ver, $"{simpleName}.dll");
                                if (File.Exists(dllPath))
                                {
                                    try { return Assembly.LoadFrom(dllPath); }
                                    catch { /* continue searching */ }
                                }
                            }
                        }
                        break;
                    }
                }
            }
            catch { /* shared framework search failed */ }
            return null;
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
                Console.Error.WriteLine($"Framework reference: {reference.Framework}");
                break;
        }
    }

    /// <summary>
    /// Load a NuGet package assembly
    /// </summary>
    private void LoadNuGetPackage(string packageName, string? version, string targetFramework, string projectDirectory)
    {
        // Try to find package in:
        // 1. bin/Debug/net9.0/ (after restore)
        // 2. ~/.nuget/packages/packagename/version/
        // 3. Load by name (runtime resolution)

        var binPath = Path.Combine(projectDirectory, "bin", "Debug", targetFramework, $"{packageName}.dll");
        if (File.Exists(binPath))
        {
            LoadReferencedAssembly(binPath);
            return;
        }

        // Try NuGet cache
        var nugetCache = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        nugetCache = Path.Combine(nugetCache, ".nuget", "packages", packageName.ToLowerInvariant());

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
}

// Supporting types - now in ErrorReporting.cs

public class Scope
{
    public ScopeKind Kind { get; }
    public Dictionary<string, TypeInfo> Symbols { get; } = new();
    public Dictionary<string, TypeInfo> Types { get; } = new();

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

internal sealed record ImportedSymbolInfo(string Name, TypeInfo Type, SymbolDeclaration Declaration);

// Type system
public abstract record TypeInfo
{
    public override string ToString() => GetType().Name;
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

public record TupleTypeInfo(List<(string? Name, TypeInfo Type)> Elements) : TypeInfo;

public record FunctionTypeInfo(FunctionDeclaration? Declaration) : TypeInfo
{
    public List<TypeInfo>? ParameterTypes { get; set; }
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

public record UnionTypeInfo(UnionDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record EnumTypeInfo(EnumDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record AliasTypeInfo(TypeReference AliasedType) : TypeInfo;

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
    public static readonly SimpleTypeInfo Bool = new("bool");
    public static readonly SimpleTypeInfo String = new("string");
    public static readonly SimpleTypeInfo Void = new("void");
    public static readonly SimpleTypeInfo Object = new("object");
    public static readonly SimpleTypeInfo Null = new("null");
    public static readonly SimpleTypeInfo Never = new("never");
    public static readonly SimpleTypeInfo Unknown = new("unknown");
}
