using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Compiler;

/// <summary>Main linter class that analyzes code and returns diagnostics</summary>
public class Linter
{
    private readonly LinterConfig _config;

    public Linter(LinterConfig? config = null)
    {
        _config = config ?? LinterConfig.Default();
    }

    public List<Diagnostic> Lint(CompilationUnit ast, string? filePath = null, string? sourceText = null)
    {
        var visitor = new LintVisitor(filePath, sourceText, _config);
        visitor.Visit(ast);
        return visitor.Diagnostics;
    }

}

/// <summary>AST visitor that performs linting checks</summary>
internal class LintVisitor
{
    private readonly string? _filePath;
    private readonly LinterConfig _config;
    private readonly LinterSuppressionSet _suppressions;
    private readonly string? _sourceText;
    private readonly List<Diagnostic> _diagnostics = new();
    private Dictionary<string, (int Line, int Column, bool Used)> _declaredVariables = new();
    private readonly HashSet<string> _usedVariables = new();
    private readonly Stack<Dictionary<string, (int Line, int Column, bool Used)>> _scopeStack = new();
    private readonly List<string> _importedNamespaces = new();
    private readonly HashSet<string> _importedFileSymbols = new();
    private bool _hasAwaitInFunction = false;
    private bool _inAsyncFunction = false;
    private readonly HashSet<Expression> _visitingStack = new(ReferenceEqualityComparer.Instance);
    private int _recursionDepth = 0;
    private const int MAX_RECURSION_DEPTH = 100; // Lowered to detect infinite loops faster

    // NL010: Track imports and identifiers used in code for unused-import detection
    private readonly List<(string Namespace, int Line, int Column, int Length, bool IsFile, string? FilePath)> _allImports = new();
    private readonly HashSet<string> _allCodeIdentifiers = new();
    private readonly HashSet<string> _allMemberAccessNames = new();
    private readonly Stack<HashSet<string>> _typeMemberNameScopes = new();

    // NL012: Track parameters separately so we can report them without polluting the unused-variable check.
    // _currentFunctionParams/_currentFunctionParamUsages always refer to the innermost (current) function's frame.
    private List<(string Name, int Line, int Column)> _currentFunctionParams = new();
    private HashSet<string> _currentFunctionParamUsages = new();

    // NL012: A stack of parameter frames for every enclosing function. Reads inside a nested local function or lambda must be
    // able to credit a captured parameter of any *enclosing* function — not just the innermost one — or valid closures wrongly trip
    // the build-blocking "parameter never read". The last element is the innermost frame (mirrors _currentFunctionParams/_currentFunctionParamUsages).
    private readonly List<(List<(string Name, int Line, int Column)> Params, HashSet<string> Usages, Dictionary<string, (int Line, int Column, bool Used)>? Scope)> _paramFrames = new();

    public List<Diagnostic> Diagnostics => _diagnostics;

    public LintVisitor(string? filePath = null, string? sourceText = null, LinterConfig? config = null)
    {
        _filePath = filePath;
        _config = config ?? LinterConfig.Default();
        _suppressions = LinterSuppressionParser.BuildSuppressions(filePath, sourceText);
        _sourceText = sourceText;
    }

    public void Visit(CompilationUnit unit)
    {
        // Track imported namespaces for NL002 and NL010
        foreach (var import in unit.Imports)
        {
            _importedNamespaces.Add(import.Namespace);
            var span = LinterImportMetadata.ResolveNamespaceImportSpan(
                import.Column,
                import.Namespace,
                SourceLine(import.Line));
            _allImports.Add((import.Namespace, import.Line, span.Column, span.Length, false, null));
        }

        foreach (var fileImport in unit.FileImports.OfType<FileImport>())
        {
            var importedSymbol = LinterImportMetadata.ExtractFileImportSymbolName(fileImport.Path, fileImport.Alias);
            if (!string.IsNullOrWhiteSpace(importedSymbol))
            {
                _importedFileSymbols.Add(importedSymbol!);
                _allImports.Add((importedSymbol!, fileImport.Line, fileImport.DiagnosticColumn, fileImport.DiagnosticLength, true, fileImport.Path));
            }
        }

        // Push global scope
        PushScope();

        // Visit all declarations
        foreach (var declaration in unit.Declarations)
        {
            VisitDeclaration(declaration);
        }

        // Check for unused variables in global scope
        CheckUnusedVariables();
        PopScope();

        // NL010: Check for unused imports (after visiting the whole file)
        CheckUnusedImports();
    }

    private void PushScope()
    {
        // Save current scope to stack
        _scopeStack.Push(_declaredVariables);
        // Create new empty scope for child
        _declaredVariables = new Dictionary<string, (int Line, int Column, bool Used)>();
    }

    private void PopScope()
    {
        if (_scopeStack.Count > 0)
        {
            // Check current scope for unused variables
            CheckUnusedVariables();
            // Restore parent scope
            _declaredVariables = _scopeStack.Pop();
        }
    }

    private void CheckUnusedVariables()
    {
        foreach (var kvp in _declaredVariables)
        {
            var (varName, (line, column, used)) = (kvp.Key, kvp.Value);
            if (LinterBindingUsageCore.ShouldReportUnusedVariable(
                varName,
                used,
                _usedVariables.Contains(varName)))
            {
                AddDiagnostic(
                    "NL001",
                    LinterBindingUsageCore.UnusedVariableMessage(varName),
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL001"),
                    LinterBindingUsageCore.UnusedVariableSuggestion(varName),
                    varName.Length);
            }
        }
    }

    // Mechanical shell: an N# rule owner answers with a finding or with nothing, and a finding is
    // reported exactly as any other diagnostic. No rule decides anything here.
    private void Report(LinterRuleFinding? finding)
    {
        if (finding == null)
            return;

        AddDiagnostic(finding.Code, finding.Message, new Location(finding.Line, finding.Column, _filePath), finding.Severity, finding.Suggestion);
    }

    private void AddDiagnostic(string code, string message, Location location, DiagnosticSeverity severity, string? suggestion = null, int length = 0)
    {
        if (!_config.IsRuleEnabled(code))
            return;

        if (IsSuppressed(code, location.Line))
            return;

        var sourceLine = SourceLine(location.Line);
        var span = DiagnosticSpanResolver.Resolve(sourceLine, location.Column, length);
        var diagnosticLocation = span.Column == location.Column
            ? location
            : location with { Column = span.Column };

        _diagnostics.Add(new Diagnostic(code, message, diagnosticLocation, severity, suggestion, span.Length));
    }

    private string SourceLine(int oneBasedLine)
        => !string.IsNullOrEmpty(_sourceText) && oneBasedLine > 0
            ? CodeIntelligenceTextUtilities.GetSourceLine(_sourceText, oneBasedLine) ?? string.Empty
            : string.Empty;

    private int FindTokenColumn(int oneBasedLine, string token, int fallbackColumn)
    {
        if (string.IsNullOrWhiteSpace(token))
            return fallbackColumn;

        var sourceLine = SourceLine(oneBasedLine);
        var index = sourceLine.IndexOf(token, StringComparison.Ordinal);
        return index >= 0 ? index + 1 : fallbackColumn;
    }

    private bool IsSuppressed(string code, int line)
        => _suppressions.IsSuppressed(line, code);

    private void VisitDeclaration(Declaration declaration)
    {
        switch (declaration)
        {
            case FunctionDeclaration func:
                VisitFunction(func);
                break;
            case ClassDeclaration classDecl:
                TrackTypeReference(classDecl.BaseClass);
                foreach (var iface in classDecl.Interfaces) TrackTypeReference(iface);
                VisitClass(classDecl);
                break;
            case StructDeclaration structDecl:
                foreach (var iface in structDecl.Interfaces) TrackTypeReference(iface);
                VisitStruct(structDecl);
                break;
            case RecordDeclaration recordDecl:
                foreach (var iface in recordDecl.Interfaces) TrackTypeReference(iface);
                VisitRecord(recordDecl);
                break;
            case SoaRecordDeclaration soaRecordDecl:
                foreach (var column in soaRecordDecl.Columns)
                {
                    TrackTypeReference(column.Type);
                }
                break;
            case InterfaceDeclaration interfaceDecl:
                foreach (var iface in interfaceDecl.BaseInterfaces) TrackTypeReference(iface);
                VisitInterface(interfaceDecl);
                break;
            case UnionDeclaration unionDecl:
                break;
            case EnumDeclaration enumDecl:
                break;
            case FieldDeclaration field:
                TrackTypeReference(field.Type);
                if (field.Initializer != null)
                    VisitExpression(field.Initializer);
                break;
            case PropertyDeclaration prop:
                TrackTypeReference(prop.Type);
                if (prop.ExpressionBody != null)
                    VisitExpression(prop.ExpressionBody);
                if (prop.GetBody != null)
                    VisitStatement(prop.GetBody);
                if (prop.SetBody != null)
                    VisitStatement(prop.SetBody);
                break;
            case ConstructorDeclaration ctor:
                VisitStatement(ctor.Body);
                break;
            case TestDeclaration test:
                if (test.TableParameters != null)
                {
                    foreach (var param in test.TableParameters)
                        TrackTypeReference(param.Type);
                }
                if (test.TableCases != null)
                {
                    foreach (var row in test.TableCases)
                        foreach (var expr in row)
                            VisitExpression(expr);
                }
                VisitStatement(test.Body);
                break;
            case SetupDeclaration setup:
                VisitStatement(setup.Body);
                break;
            case TeardownDeclaration teardown:
                VisitStatement(teardown.Body);
                break;
        }
    }

    private void VisitFunction(FunctionDeclaration func)
    {
        // NL010: Track type references in function signature
        TrackTypeReference(func.ReturnType);
        foreach (var param in func.Parameters)
            TrackTypeReference(param.Type);

        // NL004: Check for async without await
        var wasInAsync = _inAsyncFunction;
        var hadAwait = _hasAwaitInFunction;
        _inAsyncFunction = func.Modifiers.HasFlag(Modifiers.Async);
        _hasAwaitInFunction = false;

        // Async functions implicitly use Task from System.Threading.Tasks
        if (_inAsyncFunction)
            _allCodeIdentifiers.Add("Task");

        // NL012: Save outer param tracking state and push a fresh frame for this function.
        var outerParams = _currentFunctionParams;
        var outerParamUsages = _currentFunctionParamUsages;
        _currentFunctionParams = new List<(string Name, int Line, int Column)>();
        _currentFunctionParamUsages = new HashSet<string>();
        _paramFrames.Add((_currentFunctionParams, _currentFunctionParamUsages, null));

        if (func.Body != null)
        {
            PushScope();

            // Add parameters to scope; track for NL012
            foreach (var param in func.Parameters)
            {
                var paramLine = param.Line > 0 ? param.Line : func.Line;
                var paramColumn = param.Column > 0 ? param.Column : func.Column;
                DeclareVariable(param.Name, paramLine, paramColumn);
                MarkVariableUsed(param.Name, creditEnclosingParameter: false); // Parameters exempt from NL001
                _currentFunctionParams.Add((param.Name, paramLine, paramColumn));
            }

            // NL012: record the scope that holds this function's parameters so a read can be attributed to the parameter it lexically resolves to (a shadowing local binds the name in a nearer scope and must not credit this parameter).
            _paramFrames[_paramFrames.Count - 1] = (_currentFunctionParams, _currentFunctionParamUsages, _declaredVariables);

            VisitStatement(func.Body);

            // NL012: Report unused parameters
            CheckUnusedParameters(func.Name);

            PopScope();
        }
        else if (func.ExpressionBody != null)
        {
            PushScope();
            foreach (var param in func.Parameters)
            {
                var paramLine = param.Line > 0 ? param.Line : func.Line;
                var paramColumn = param.Column > 0 ? param.Column : func.Column;
                DeclareVariable(param.Name, paramLine, paramColumn);
                MarkVariableUsed(param.Name, creditEnclosingParameter: false);
                _currentFunctionParams.Add((param.Name, paramLine, paramColumn));
            }
            // NL012: record the parameter scope (see the func.Body branch for rationale).
            _paramFrames[_paramFrames.Count - 1] = (_currentFunctionParams, _currentFunctionParamUsages, _declaredVariables);
            VisitExpression(func.ExpressionBody);

            // NL012: Report unused parameters
            CheckUnusedParameters(func.Name);

            PopScope();
        }

        // NL004: Async method without await
        if (_inAsyncFunction && !_hasAwaitInFunction && func.Body != null)
        {
            // Check if return type is Task or Task<T> (might need async for other reasons)
            var needsAwait = true;

            // If the function returns a Task synchronously (e.g., Task.CompletedTask), that's ok
            // For now, we'll warn on all async without await
            if (needsAwait)
            {
                AddDiagnostic(
                    "NL004",
                    $"Function '{func.Name}' is marked 'async' but never uses 'await' — it will run synchronously",
                    new Location(func.Line, FindTokenColumn(func.Line, func.Name, func.Column), _filePath),
                    _config.GetSeverity("NL004"),
                    $"Either add an 'await' expression inside '{func.Name}', or remove the 'async' modifier if this function doesn't need to be asynchronous");
            }
        }

        // Restore state
        _inAsyncFunction = wasInAsync;
        _hasAwaitInFunction = hadAwait;
        _paramFrames.RemoveAt(_paramFrames.Count - 1);
        _currentFunctionParams = outerParams;
        _currentFunctionParamUsages = outerParamUsages;
    }

    private void CheckUnusedParameters(string functionName)
    {
        if (!_config.RuleSeverities.ContainsKey("NL012"))
            return;

        foreach (var (name, line, column) in _currentFunctionParams)
        {
            if (LinterBindingUsageCore.ShouldReportUnusedParameter(
                name,
                _currentFunctionParamUsages.Contains(name)))
            {
                AddDiagnostic(
                    "NL012",
                    LinterBindingUsageCore.UnusedParameterMessage(name, functionName),
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL012"),
                    LinterBindingUsageCore.UnusedParameterSuggestion(name));
            }
        }
    }

    private void VisitClass(ClassDeclaration classDecl)
    {
        VisitWithTypeMemberScope(classDecl.Members, classDecl.PrimaryConstructorParameters, () =>
        {
            foreach (var member in classDecl.Members)
            {
                VisitDeclaration(member);
            }
        });
    }

    private void VisitStruct(StructDeclaration structDecl)
    {
        VisitWithTypeMemberScope(structDecl.Members, structDecl.PrimaryConstructorParameters, () =>
        {
            foreach (var member in structDecl.Members)
            {
                VisitDeclaration(member);
            }
        });
    }

    private void VisitRecord(RecordDeclaration recordDecl)
    {
        VisitWithTypeMemberScope(recordDecl.Members, recordDecl.PrimaryConstructorParameters, () =>
        {
            foreach (var member in recordDecl.Members)
            {
                VisitDeclaration(member);
            }
        });
    }

    private void VisitInterface(InterfaceDeclaration interfaceDecl)
    {
        foreach (var member in interfaceDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitWithTypeMemberScope(
        List<Declaration> members,
        List<Parameter>? primaryConstructorParameters,
        Action visit)
    {
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (var member in members)
        {
            switch (member)
            {
                case FieldDeclaration field:
                    names.Add(field.Name);
                    break;
                case PropertyDeclaration property:
                    names.Add(property.Name);
                    break;
                case FunctionDeclaration function:
                    names.Add(function.Name);
                    break;
            }
        }

        if (primaryConstructorParameters != null)
        {
            foreach (var parameter in primaryConstructorParameters)
            {
                names.Add(parameter.Name);
                TrackTypeReference(parameter.Type); // NL010: a positional parameter's declared type is a real import usage.
            }
        }

        _typeMemberNameScopes.Push(names);
        try
        {
            visit();
        }
        finally
        {
            _typeMemberNameScopes.Pop();
        }
    }

    private void VisitStatement(Statement statement)
    {
        switch (statement)
        {
            case VariableDeclarationStatement varDecl:
                // NL010: Track type references in variable declarations
                TrackTypeReference(varDecl.Type);
                var initializerHasParserError = varDecl.Initializer != null &&
                    AnalyzerParserErrorPlaceholders.ContainsInExpression(varDecl.Initializer);
                // VariableDeclarationStatement stores the identifier location, including
                // shorthand declarations like `name := value`.
                var nameColumn = varDecl.Column;
                if (!initializerHasParserError)
                {
                    DeclareVariable(varDecl.Name, varDecl.Line, nameColumn);
                }

                if (varDecl.Initializer != null && !initializerHasParserError)
                {
                    VisitExpression(varDecl.Initializer);
                }
                break;

            case BlockStatement block:
                PushScope();
                var unreachableReported = false;
                var restIsUnreachable = false;

                foreach (var stmt in block.Statements)
                {
                    if (restIsUnreachable)
                    {
                        if (!unreachableReported)
                        {
                            AddDiagnostic(
                                "NL006",
                                "This code will never run — there's a 'return' or 'throw' above it",
                                new Location(stmt.Line, stmt.Column, _filePath),
                                _config.GetSeverity("NL006"),
                                "Remove the unreachable code, or move it before the return/throw if it should execute");
                            unreachableReported = true;
                        }

                        // Don't cascade other diagnostics/variable usage from unreachable statements.
                        continue;
                    }

                    VisitStatement(stmt);

                    if (stmt is ReturnStatement or ThrowStatement)
                    {
                        restIsUnreachable = true;
                    }
                }
                PopScope();
                break;

            case IfStatement ifStmt:
                VisitExpression(ifStmt.Condition);
                // NL003: Check for unnecessary null checks on value types
                CheckUnnecessaryNullCheck(ifStmt.Condition);
                // NL016: Redundant null check on always-non-null expressions
                CheckRedundantNullCheckOnNewOrLiteral(ifStmt.Condition);
                VisitStatement(ifStmt.ThenStatement);
                if (ifStmt.ElseStatement != null)
                    VisitStatement(ifStmt.ElseStatement);
                break;

            case ForStatement forStmt:
                PushScope();
                if (forStmt.Initializer != null)
                    VisitStatement(forStmt.Initializer);
                if (forStmt.Condition != null)
                    VisitExpression(forStmt.Condition);
                if (forStmt.Iterator != null)
                    VisitExpression(forStmt.Iterator);
                VisitStatement(forStmt.Body);
                PopScope();
                break;

            case ForeachStatement foreachStmt:
                VisitExpression(foreachStmt.Collection); // Visit collection in outer scope FIRST
                PushScope();
                DeclareVariable(foreachStmt.VariableName, foreachStmt.Line, foreachStmt.Column);
                MarkVariableUsed(foreachStmt.VariableName, creditEnclosingParameter: false); // Loop variables are considered used
                VisitStatement(foreachStmt.Body);
                PopScope();
                break;

            case WhileStatement whileStmt:
                VisitExpression(whileStmt.Condition);
                CheckUnnecessaryNullCheck(whileStmt.Condition);
                // NL016: Redundant null check on always-non-null expressions
                CheckRedundantNullCheckOnNewOrLiteral(whileStmt.Condition);
                VisitStatement(whileStmt.Body);
                break;

            case ReturnStatement returnStmt:
                if (returnStmt.Value != null)
                    VisitExpression(returnStmt.Value);
                break;

            case ExpressionStatement exprStmt:
                VisitExpression(exprStmt.Expression);
                break;

            case TryStatement tryStmt:
                VisitStatement(tryStmt.TryBlock);
                foreach (var catchClause in tryStmt.CatchClauses)
                {
                    var catchBlockIsEmpty = catchClause.Block.Statements.Count == 0;

                    // NL011: Empty catch block
                    if (catchBlockIsEmpty)
                    {
                        var span = LinterBlockOwnerSpanResolver.Resolve(
                            catchClause.Block.Line,
                            catchClause.Block.Column,
                            SourceLine(catchClause.Block.Line));
                        AddDiagnostic(
                            "NL011",
                            "This catch block is empty — exceptions will be silently swallowed",
                            new Location(span.Line, span.Column, _filePath),
                            _config.GetSeverity("NL011"),
                            "Log the error, handle it, or add a comment explaining why it's safe to ignore",
                            span.Length);
                    }

                    PushScope();
                    if (catchClause.VariableName != null)
                    {
                        DeclareVariable(catchClause.VariableName, catchClause.Block.Line, catchClause.Block.Column);
                        MarkVariableUsed(catchClause.VariableName, creditEnclosingParameter: false); // Exception variables are considered used
                    }
                    if (!catchBlockIsEmpty)
                        VisitStatement(catchClause.Block);
                    PopScope();
                }
                if (tryStmt.FinallyBlock != null)
                    VisitStatement(tryStmt.FinallyBlock);
                break;

            case UsingStatement usingStmt:
                PushScope();
                if (usingStmt.Declaration != null)
                    VisitStatement(usingStmt.Declaration);
                if (usingStmt.Expression != null)
                    VisitExpression(usingStmt.Expression);
                if (usingStmt.Body != null)
                    VisitStatement(usingStmt.Body);
                PopScope();
                break;

            case SwitchStatement switchStmt:
                VisitExpression(switchStmt.Value);
                foreach (var caseStmt in switchStmt.Cases)
                {
                    PushScope();
                    foreach (var stmt in caseStmt.Statements)
                    {
                        VisitStatement(stmt);
                    }
                    PopScope();
                }
                break;

            case ThrowStatement throwStmt:
                VisitExpression(throwStmt.Expression);
                break;

            case LocalFunctionStatement localFunc:
                VisitFunction(localFunc.Function);
                break;

            case PrintStatement printStmt:
                VisitExpression(printStmt.Value);
                break;

            case AssertStatement assertStmt:
                VisitExpression(assertStmt.Condition);
                if (assertStmt.Message != null)
                    VisitExpression(assertStmt.Message);
                break;

            case AssertThrowsStatement assertThrows:
                TrackTypeReference(assertThrows.ExceptionType);
                VisitStatement(assertThrows.Body);
                break;

            case LockStatement lockStmt:
                VisitExpression(lockStmt.LockObject);
                VisitStatement(lockStmt.Body);
                break;

            case YieldStatement yieldStmt:
                if (yieldStmt.Value != null)
                    VisitExpression(yieldStmt.Value);
                break;

            case TupleDeconstructionStatement tupleDecl:
                if (AnalyzerParserErrorPlaceholders.ContainsInExpression(tupleDecl.Initializer))
                    break;

                foreach (var name in tupleDecl.Names)
                {
                    if (name != "_") // Don't track discards
                        DeclareVariable(name, tupleDecl.Line, tupleDecl.Column);
                }
                VisitExpression(tupleDecl.Initializer);
                break;

            case AwaitForEachStatement awaitForeach:
                // `await foreach` is a genuine await usage — record it so NL004 does not
                // misfire on async functions that only consume async streams.
                _hasAwaitInFunction = true;
                VisitExpression(awaitForeach.Collection); // Visit collection in outer scope FIRST
                PushScope();
                DeclareVariable(awaitForeach.VariableName, awaitForeach.Line, awaitForeach.Column);
                MarkVariableUsed(awaitForeach.VariableName, creditEnclosingParameter: false);
                VisitStatement(awaitForeach.Body);
                PopScope();
                break;
        }
    }

    private void CheckUnnecessaryNullCheck(Expression condition)
    {
        Report(LinterNullCheckPolicy.UnnecessaryNullCheck(condition, _config));
    }

    private void VisitExpression(Expression expression)
    {
        // Guard against infinite recursion
        _recursionDepth++;
        if (_recursionDepth > MAX_RECURSION_DEPTH)
        {
            throw new InvalidOperationException($"Maximum recursion depth exceeded while visiting expression at line {expression.Line}, column {expression.Column}. Expression type: {expression.GetType().Name}");
        }

        // Guard against circular references by checking if this exact expression object
        // is currently on the call stack (not just visited before, but actively being visited)
        if (!_visitingStack.Add(expression))
        {
            // This expression is already on the visiting stack, indicating a circular reference
            // HACK: If it's an IdentifierExpression, still mark it as used even though we're skipping the visit
            // This ensures variables are properly tracked even in circular AST structures
            if (expression is IdentifierExpression identExpr)
            {
                MarkVariableUsed(identExpr.Name);
            }
            _recursionDepth--;
            return;
        }

        try
        {
            VisitExpressionInternal(expression);
        }
        finally
        {
            _recursionDepth--;
            _visitingStack.Remove(expression); // Remove from stack when done visiting
        }
    }

    private void VisitExpressionInternal(Expression expression)
    {
        switch (expression)
        {
            case IdentifierExpression ident:
                MarkVariableUsed(ident.Name);
                // NL010: Track all identifiers used in code for unused-import detection
                _allCodeIdentifiers.Add(ident.Name);

                // NL002: Missing Import
                // Check if identifier looks like a type that might need an import
                CheckMissingImport(ident);
                break;

            case StringLiteralExpression stringLiteral:
                // Handle string interpolation - mark variables used inside ${...} or {...}
                HandleStringInterpolation(stringLiteral.Value);
                break;

            case NewExpression newExpr:
                // Check if the type might need an import
                if (newExpr.Type != null)
                {
                    CheckMissingImportForType(newExpr.Type, newExpr.Line, newExpr.Column);
                    // NL010: Record the type name as a used identifier
                    var newTypeName = LinterTypeReferenceName.Base(newExpr.Type);
                    if (newTypeName != null)
                        _allCodeIdentifiers.Add(newTypeName);
                }
                VisitChildExpressions(newExpr);
                break;

            case MemberAccessExpression member:
                // NL010: Track member names for extension method detection
                _allMemberAccessNames.Add(member.MemberName);
                VisitChildExpressions(member);
                break;

            case AwaitExpression awaitExpr:
                _hasAwaitInFunction = true; // Track that we're using await
                VisitChildExpressions(awaitExpr);
                break;

            case TypeOfExpression typeofExpr:
                // NL010: typeof's operand is a TypeReference, not an Expression child, so structural recursion never reaches it — track explicitly.
                TrackTypeReference(typeofExpr.Type);
                break;

            case LambdaExpression lambda:
                PushScope();
                foreach (var param in lambda.Parameters)
                {
                    DeclareVariable(param.Name, lambda.Line, lambda.Column);
                    MarkVariableUsed(param.Name, creditEnclosingParameter: false);
                }
                if (lambda.BlockBody != null)
                    VisitStatement(lambda.BlockBody);
                if (lambda.ExpressionBody != null)
                    VisitExpression(lambda.ExpressionBody);
                PopScope();
                break;

            default:
                // Everything else is purely structural: visit every child expression. Routing through AstChildren
                // (instead of per-node child lists) keeps this fail-safe — a node or child slot missing here cannot
                // silently skip a subtree and produce false NL001/NL010-class diagnostics.
                VisitChildExpressions(expression);
                break;
        }
    }

    private void VisitChildExpressions(Expression expression)
    {
        foreach (var child in AstChildrenCore.Of(expression).Cast<Expression>())
        {
            VisitExpression(child);
        }
    }

    private void DeclareVariable(string name, int line, int column)
    {
        // NL020: Check if this name shadows a variable in an outer scope
        CheckShadowedVariable(name, line, column);

        _declaredVariables[name] = (line, column, false);
    }

    private void CheckShadowedVariable(string name, int line, int column)
    {
        Report(LinterShadowedVariable.ShadowedVariable(name, line, column, _scopeStack, _config));
    }

    private void MarkVariableUsed(string name, bool creditEnclosingParameter = true)
    {
        // NL012: Track parameter usages.
        if (creditEnclosingParameter)
        {
            // A genuine read of 'name' counts as a use of the parameter it lexically resolves to — including a parameter
            // captured by a nested local function or lambda. Resolve to the nearest scope that binds the name (innermost
            // first), then credit only the parameter frame whose dedicated parameter scope IS that resolved scope. This makes
            // captured-parameter reads count (fixing the build-blocking "parameter never read" false positive) while a shadowing
            // local/loop/catch/lambda binding — which lives in a nearer scope — correctly prevents the enclosing parameter from being marked read.
            Dictionary<string, (int Line, int Column, bool Used)>? resolvedScope =
                _declaredVariables.ContainsKey(name) ? _declaredVariables : null;
            if (resolvedScope == null)
            {
                foreach (var scope in _scopeStack)
                {
                    if (scope.ContainsKey(name))
                    {
                        resolvedScope = scope;
                        break;
                    }
                }
            }
            if (resolvedScope != null)
            {
                for (int i = _paramFrames.Count - 1; i >= 0; i--)
                {
                    if (ReferenceEquals(_paramFrames[i].Scope, resolvedScope)
                        && _paramFrames[i].Params.Any(p => p.Name == name))
                    {
                        _paramFrames[i].Usages.Add(name);
                        break;
                    }
                }
            }
        }
        else if (_currentFunctionParams.Any(p => p.Name == name))
        {
            // Binding/declaration site (a parameter, loop variable, catch variable, or lambda parameter being introduced). Preserve the original behavior of only consulting the current function's parameter table, so re-declaring a name never marks an enclosing parameter as read.
            _currentFunctionParamUsages.Add(name);
        }

        // Check current scope
        if (_declaredVariables.ContainsKey(name))
        {
            var (line, column, _) = _declaredVariables[name];
            _declaredVariables[name] = (line, column, true);
        }
        else
        {
            // Check parent scopes
            foreach (var scope in _scopeStack)
            {
                if (scope.ContainsKey(name))
                {
                    var (line, column, _) = scope[name];
                    scope[name] = (line, column, true);
                    break;
                }
            }
        }
        _usedVariables.Add(name);
    }

    // NL002: the whole decision — which namespace a bare name needs, and whether anything already
    // supplies it — belongs to `LinterMissingImport`; what is left here is the report.
    private void CheckMissingImport(IdentifierExpression ident)
    {
        var requiredNamespace = LinterMissingImport.MissingNamespaceForIdentifier(
            ident.Name, _typeMemberNameScopes, _importedFileSymbols, _importedNamespaces);
        if (requiredNamespace == null)
            return;

        AddDiagnostic(
            "NL002",
            LinterMissingImport.Message(ident.Name),
            new Location(ident.Line, ident.Column, _filePath),
            _config.GetSeverity("NL002"),
            LinterMissingImport.Suggestion(requiredNamespace));
    }

    private void CheckMissingImportForType(TypeReference type, int line, int column)
    {
        var typeName = LinterTypeReferenceName.Base(type);
        if (typeName == null)
            return;

        var requiredNamespace = LinterMissingImport.MissingNamespaceForTypeName(
            typeName, _importedFileSymbols, _importedNamespaces);
        if (requiredNamespace == null)
            return;

        AddDiagnostic(
            "NL002",
            LinterMissingImport.Message(typeName),
            new Location(line, column, _filePath),
            _config.GetSeverity("NL002"),
            LinterMissingImport.Suggestion(requiredNamespace));
    }

    /// <summary>
    /// NL010: Track every type name a written type reference mentions as a used code identifier.
    /// </summary>
    private void TrackTypeReference(TypeReference? type)
    {
        LinterTypeReferenceName.CollectMentionedNames(type, _allCodeIdentifiers);
    }

    private void HandleStringInterpolation(string value)
    {
        foreach (var name in LinterInterpolationScan.UsedIdentifiers(value))
        {
            MarkVariableUsed(name);
        }
    }

    // -------------------------------------------------------------------------
    // NL010: Unused Import
    // -------------------------------------------------------------------------

    private void CheckUnusedImports()
    {
        if (!_config.RuleSeverities.ContainsKey("NL010"))
            return;

        foreach (var (ns, line, column, length, isFile, filePath) in _allImports)
        {
            // A file import resolves to a file's exported symbols; a namespace import resolves to
            // the known-namespace table. Both arms are N#.
            var used = isFile
                ? LinterFileImportUsage.IsUsed(ns, filePath, _filePath, _allCodeIdentifiers)
                : LinterNamespaceImportUsage.IsUsed(ns, _allCodeIdentifiers, _allMemberAccessNames);

            if (!used)
            {
                var label = isFile ? $"import \"{filePath ?? ns}\"" : $"import {ns}";
                AddDiagnostic(
                    "NL010",
                    $"The import '{label}' is not used by any code in this file",
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL010"),
                    $"Remove '{label}' to keep your imports clean",
                    length);
            }
        }
    }

    // -------------------------------------------------------------------------
    // NL016: Redundant Null Check (conservative: only `new` / literal initialisers)
    // -------------------------------------------------------------------------
    private void CheckRedundantNullCheckOnNewOrLiteral(Expression condition)
    {
        Report(LinterNullCheckPolicy.RedundantNullCheck(condition, _config));
    }

}
