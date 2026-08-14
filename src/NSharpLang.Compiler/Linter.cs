using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

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
    // Every piece of per-file lint state, and every rule that reads it without walking, belongs to
    // the N# owner. What is left here is the walk.
    private readonly LinterWalkState _state;

    // The expression-recursion guard is this walker's own state, not the walk's shared state: nothing
    // outside VisitExpression touches it.
    private readonly HashSet<Expression> _visitingStack = new(ReferenceEqualityComparer.Instance);
    private int _recursionDepth = 0;
    private const int MAX_RECURSION_DEPTH = 100; // Lowered to detect infinite loops faster

    public List<Diagnostic> Diagnostics => _state.Diagnostics;

    public LintVisitor(string? filePath = null, string? sourceText = null, LinterConfig? config = null)
    {
        _state = new LinterWalkState(filePath, sourceText, config ?? LinterConfig.Default());
    }

    public void Visit(CompilationUnit unit)
    {
        // Track imported namespaces and file symbols for NL002 and NL010
        _state.RegisterImports(unit);

        // Push global scope
        _state.PushScope();

        // Visit all declarations
        foreach (var declaration in unit.Declarations)
        {
            VisitDeclaration(declaration);
        }

        // Check for unused variables in global scope
        _state.CheckUnusedVariables();
        _state.PopScope();

        // NL010: Check for unused imports (after visiting the whole file)
        _state.CheckUnusedImports();
    }

    private void VisitDeclaration(Declaration declaration)
    {
        switch (declaration)
        {
            case FunctionDeclaration func:
                VisitFunction(func);
                break;
            case ClassDeclaration classDecl:
                _state.TrackTypeReference(classDecl.BaseClass);
                foreach (var iface in classDecl.Interfaces) _state.TrackTypeReference(iface);
                VisitClass(classDecl);
                break;
            case StructDeclaration structDecl:
                foreach (var iface in structDecl.Interfaces) _state.TrackTypeReference(iface);
                VisitStruct(structDecl);
                break;
            case RecordDeclaration recordDecl:
                foreach (var iface in recordDecl.Interfaces) _state.TrackTypeReference(iface);
                VisitRecord(recordDecl);
                break;
            case SoaRecordDeclaration soaRecordDecl:
                foreach (var column in soaRecordDecl.Columns)
                {
                    _state.TrackTypeReference(column.Type);
                }
                break;
            case InterfaceDeclaration interfaceDecl:
                foreach (var iface in interfaceDecl.BaseInterfaces) _state.TrackTypeReference(iface);
                VisitInterface(interfaceDecl);
                break;
            case UnionDeclaration unionDecl:
                break;
            case EnumDeclaration enumDecl:
                break;
            case FieldDeclaration field:
                _state.TrackTypeReference(field.Type);
                if (field.Initializer != null)
                    VisitExpression(field.Initializer);
                break;
            case PropertyDeclaration prop:
                _state.TrackTypeReference(prop.Type);
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
                        _state.TrackTypeReference(param.Type);
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
        _state.TrackTypeReference(func.ReturnType);
        foreach (var param in func.Parameters)
            _state.TrackTypeReference(param.Type);

        // NL004/NL012: open this function's frame; the enclosing one is restored from the local below.
        var frame = _state.EnterFunction(func.Modifiers.HasFlag(Modifiers.Async));

        if (func.Body != null)
        {
            _state.PushScope();

            // Add parameters to scope; track for NL012
            foreach (var param in func.Parameters)
            {
                var paramLine = param.Line > 0 ? param.Line : func.Line;
                var paramColumn = param.Column > 0 ? param.Column : func.Column;
                _state.DeclareVariable(param.Name, paramLine, paramColumn);
                _state.MarkVariableUsed(param.Name, false); // Parameters exempt from NL001
                _state.AddParameter(param.Name, paramLine, paramColumn);
            }

            _state.RecordParameterScope();

            VisitStatement(func.Body);

            // NL012: Report unused parameters
            _state.CheckUnusedParameters(func.Name);

            _state.PopScope();
        }
        else if (func.ExpressionBody != null)
        {
            _state.PushScope();
            foreach (var param in func.Parameters)
            {
                var paramLine = param.Line > 0 ? param.Line : func.Line;
                var paramColumn = param.Column > 0 ? param.Column : func.Column;
                _state.DeclareVariable(param.Name, paramLine, paramColumn);
                _state.MarkVariableUsed(param.Name, false);
                _state.AddParameter(param.Name, paramLine, paramColumn);
            }
            _state.RecordParameterScope();
            VisitExpression(func.ExpressionBody);

            // NL012: Report unused parameters
            _state.CheckUnusedParameters(func.Name);

            _state.PopScope();
        }

        // NL004: Async method without await
        _state.CheckAsyncWithoutAwait(func);

        // Restore state
        _state.ExitFunction(frame);
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
        _state.PushTypeMemberScope(members, primaryConstructorParameters);
        try
        {
            visit();
        }
        finally
        {
            _state.PopTypeMemberScope();
        }
    }

    private void VisitStatement(Statement statement)
    {
        switch (statement)
        {
            case VariableDeclarationStatement varDecl:
                // NL010: Track type references in variable declarations
                _state.TrackTypeReference(varDecl.Type);
                var initializerHasParserError = varDecl.Initializer != null &&
                    AnalyzerParserErrorPlaceholders.ContainsInExpression(varDecl.Initializer);
                // VariableDeclarationStatement stores the identifier location, including
                // shorthand declarations like `name := value`.
                var nameColumn = varDecl.Column;
                if (!initializerHasParserError)
                {
                    _state.DeclareVariable(varDecl.Name, varDecl.Line, nameColumn);
                }

                if (varDecl.Initializer != null && !initializerHasParserError)
                {
                    VisitExpression(varDecl.Initializer);
                }
                break;

            case BlockStatement block:
                _state.PushScope();
                var unreachableReported = false;
                var restIsUnreachable = false;

                foreach (var stmt in block.Statements)
                {
                    if (restIsUnreachable)
                    {
                        if (!unreachableReported)
                        {
                            _state.ReportUnreachableCode(stmt.Line, stmt.Column);
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
                _state.PopScope();
                break;

            case IfStatement ifStmt:
                VisitExpression(ifStmt.Condition);
                // NL003: Check for unnecessary null checks on value types
                _state.CheckUnnecessaryNullCheck(ifStmt.Condition);
                // NL016: Redundant null check on always-non-null expressions
                _state.CheckRedundantNullCheck(ifStmt.Condition);
                VisitStatement(ifStmt.ThenStatement);
                if (ifStmt.ElseStatement != null)
                    VisitStatement(ifStmt.ElseStatement);
                break;

            case ForStatement forStmt:
                _state.PushScope();
                if (forStmt.Initializer != null)
                    VisitStatement(forStmt.Initializer);
                if (forStmt.Condition != null)
                    VisitExpression(forStmt.Condition);
                if (forStmt.Iterator != null)
                    VisitExpression(forStmt.Iterator);
                VisitStatement(forStmt.Body);
                _state.PopScope();
                break;

            case ForeachStatement foreachStmt:
                VisitExpression(foreachStmt.Collection); // Visit collection in outer scope FIRST
                _state.PushScope();
                _state.DeclareVariable(foreachStmt.VariableName, foreachStmt.Line, foreachStmt.Column);
                _state.MarkVariableUsed(foreachStmt.VariableName, false); // Loop variables are considered used
                VisitStatement(foreachStmt.Body);
                _state.PopScope();
                break;

            case WhileStatement whileStmt:
                VisitExpression(whileStmt.Condition);
                _state.CheckUnnecessaryNullCheck(whileStmt.Condition);
                // NL016: Redundant null check on always-non-null expressions
                _state.CheckRedundantNullCheck(whileStmt.Condition);
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
                        _state.ReportEmptyCatchBlock(catchClause.Block.Line, catchClause.Block.Column);
                    }

                    _state.PushScope();
                    if (catchClause.VariableName != null)
                    {
                        _state.DeclareVariable(catchClause.VariableName, catchClause.Block.Line, catchClause.Block.Column);
                        _state.MarkVariableUsed(catchClause.VariableName, false); // Exception variables are considered used
                    }
                    if (!catchBlockIsEmpty)
                        VisitStatement(catchClause.Block);
                    _state.PopScope();
                }
                if (tryStmt.FinallyBlock != null)
                    VisitStatement(tryStmt.FinallyBlock);
                break;

            case UsingStatement usingStmt:
                _state.PushScope();
                if (usingStmt.Declaration != null)
                    VisitStatement(usingStmt.Declaration);
                if (usingStmt.Expression != null)
                    VisitExpression(usingStmt.Expression);
                if (usingStmt.Body != null)
                    VisitStatement(usingStmt.Body);
                _state.PopScope();
                break;

            case SwitchStatement switchStmt:
                VisitExpression(switchStmt.Value);
                foreach (var caseStmt in switchStmt.Cases)
                {
                    _state.PushScope();
                    foreach (var stmt in caseStmt.Statements)
                    {
                        VisitStatement(stmt);
                    }
                    _state.PopScope();
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
                _state.TrackTypeReference(assertThrows.ExceptionType);
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
                        _state.DeclareVariable(name, tupleDecl.Line, tupleDecl.Column);
                }
                VisitExpression(tupleDecl.Initializer);
                break;

            case AwaitForEachStatement awaitForeach:
                // `await foreach` is a genuine await usage — record it so NL004 does not
                // misfire on async functions that only consume async streams.
                _state.NoteAwait();
                VisitExpression(awaitForeach.Collection); // Visit collection in outer scope FIRST
                _state.PushScope();
                _state.DeclareVariable(awaitForeach.VariableName, awaitForeach.Line, awaitForeach.Column);
                _state.MarkVariableUsed(awaitForeach.VariableName, false);
                VisitStatement(awaitForeach.Body);
                _state.PopScope();
                break;
        }
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
                _state.MarkVariableUsed(identExpr.Name, true);
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
                _state.MarkVariableUsed(ident.Name, true);
                // NL010: Track all identifiers used in code for unused-import detection
                _state.NoteCodeIdentifier(ident.Name);

                // NL002: Missing Import
                // Check if identifier looks like a type that might need an import
                _state.CheckMissingImport(ident);
                break;

            case StringLiteralExpression stringLiteral:
                // Handle string interpolation - mark variables used inside ${...} or {...}
                _state.HandleStringInterpolation(stringLiteral.Value);
                break;

            case NewExpression newExpr:
                // Check if the type might need an import
                if (newExpr.Type != null)
                {
                    _state.CheckMissingImportForType(newExpr.Type, newExpr.Line, newExpr.Column);
                    // NL010: Record the type name as a used identifier
                    var newTypeName = LinterTypeReferenceName.Base(newExpr.Type);
                    if (newTypeName != null)
                        _state.NoteCodeIdentifier(newTypeName);
                }
                VisitChildExpressions(newExpr);
                break;

            case MemberAccessExpression member:
                // NL010: Track member names for extension method detection
                _state.NoteMemberAccessName(member.MemberName);
                VisitChildExpressions(member);
                break;

            case AwaitExpression awaitExpr:
                _state.NoteAwait(); // Track that we're using await
                VisitChildExpressions(awaitExpr);
                break;

            case TypeOfExpression typeofExpr:
                // NL010: typeof's operand is a TypeReference, not an Expression child, so structural recursion never reaches it — track explicitly.
                _state.TrackTypeReference(typeofExpr.Type);
                break;

            case LambdaExpression lambda:
                _state.PushScope();
                foreach (var param in lambda.Parameters)
                {
                    _state.DeclareVariable(param.Name, lambda.Line, lambda.Column);
                    _state.MarkVariableUsed(param.Name, false);
                }
                if (lambda.BlockBody != null)
                    VisitStatement(lambda.BlockBody);
                if (lambda.ExpressionBody != null)
                    VisitExpression(lambda.ExpressionBody);
                _state.PopScope();
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

}
