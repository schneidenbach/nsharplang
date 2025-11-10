using System;
using System.Collections.Generic;
using System.Linq;
using NewCLILang.Compiler.Ast;

namespace NewCLILang.Compiler;

/// <summary>
/// Diagnostic severity levels
/// </summary>
public enum DiagnosticSeverity
{
    Warning,
    Error,
    Info
}

/// <summary>
/// Location information for a diagnostic
/// </summary>
public record Location(int Line, int Column, string? FilePath = null);

/// <summary>
/// Represents a linter diagnostic (warning, error, or info)
/// </summary>
public record Diagnostic(
    string Code,
    string Message,
    Location Location,
    DiagnosticSeverity Severity,
    string? Suggestion = null);

/// <summary>
/// Main linter class that analyzes code and returns diagnostics
/// </summary>
public class Linter
{
    public List<Diagnostic> Lint(CompilationUnit ast, string? filePath = null)
    {
        var visitor = new LintVisitor(filePath);
        visitor.Visit(ast);
        return visitor.Diagnostics;
    }
}

/// <summary>
/// AST visitor that performs linting checks
/// </summary>
internal class LintVisitor
{
    private readonly string? _filePath;
    private readonly List<Diagnostic> _diagnostics = new();
    private readonly Dictionary<string, (int Line, int Column, bool Used)> _declaredVariables = new();
    private readonly HashSet<string> _usedVariables = new();
    private readonly Stack<Dictionary<string, (int Line, int Column, bool Used)>> _scopeStack = new();
    private readonly List<string> _importedNamespaces = new();

    public List<Diagnostic> Diagnostics => _diagnostics;

    public LintVisitor(string? filePath = null)
    {
        _filePath = filePath;
    }

    public void Visit(CompilationUnit unit)
    {
        // Track imported namespaces for NL002
        foreach (var import in unit.Imports)
        {
            _importedNamespaces.Add(import.Namespace);
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
    }

    private void PushScope()
    {
        _scopeStack.Push(new Dictionary<string, (int Line, int Column, bool Used)>(_declaredVariables));
    }

    private void PopScope()
    {
        if (_scopeStack.Count > 0)
        {
            CheckUnusedVariables();
            _declaredVariables.Clear();
            if (_scopeStack.Count > 0)
            {
                var parent = _scopeStack.Pop();
                foreach (var kvp in parent)
                {
                    _declaredVariables[kvp.Key] = kvp.Value;
                }
            }
        }
    }

    private void CheckUnusedVariables()
    {
        foreach (var kvp in _declaredVariables)
        {
            var (varName, (line, column, used)) = (kvp.Key, kvp.Value);
            if (!used && !_usedVariables.Contains(varName))
            {
                _diagnostics.Add(new Diagnostic(
                    "NL001",
                    $"Unused variable '{varName}'",
                    new Location(line, column, _filePath),
                    DiagnosticSeverity.Warning));
            }
        }
    }

    private void VisitDeclaration(Declaration declaration)
    {
        switch (declaration)
        {
            case FunctionDeclaration func:
                VisitFunction(func);
                break;
            case ClassDeclaration classDecl:
                VisitClass(classDecl);
                break;
            case StructDeclaration structDecl:
                VisitStruct(structDecl);
                break;
            case RecordDeclaration recordDecl:
                VisitRecord(recordDecl);
                break;
            case InterfaceDeclaration interfaceDecl:
                VisitInterface(interfaceDecl);
                break;
            case FieldDeclaration field:
                if (field.Initializer != null)
                    VisitExpression(field.Initializer);
                break;
            case PropertyDeclaration prop:
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
        }
    }

    private void VisitFunction(FunctionDeclaration func)
    {
        if (func.Body != null)
        {
            PushScope();

            // Add parameters to scope
            foreach (var param in func.Parameters)
            {
                DeclareVariable(param.Name, func.Line, func.Column);
                MarkVariableUsed(param.Name); // Parameters are considered used
            }

            VisitStatement(func.Body);
            PopScope();
        }
        else if (func.ExpressionBody != null)
        {
            PushScope();
            foreach (var param in func.Parameters)
            {
                DeclareVariable(param.Name, func.Line, func.Column);
                MarkVariableUsed(param.Name);
            }
            VisitExpression(func.ExpressionBody);
            PopScope();
        }
    }

    private void VisitClass(ClassDeclaration classDecl)
    {
        foreach (var member in classDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitStruct(StructDeclaration structDecl)
    {
        foreach (var member in structDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitRecord(RecordDeclaration recordDecl)
    {
        foreach (var member in recordDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitInterface(InterfaceDeclaration interfaceDecl)
    {
        foreach (var member in interfaceDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitStatement(Statement statement)
    {
        switch (statement)
        {
            case VariableDeclarationStatement varDecl:
                DeclareVariable(varDecl.Name, varDecl.Line, varDecl.Column);
                if (varDecl.Initializer != null)
                    VisitExpression(varDecl.Initializer);
                break;

            case BlockStatement block:
                PushScope();
                foreach (var stmt in block.Statements)
                {
                    VisitStatement(stmt);
                }
                PopScope();
                break;

            case IfStatement ifStmt:
                VisitExpression(ifStmt.Condition);
                // NL003: Check for unnecessary null checks on value types
                CheckUnnecessaryNullCheck(ifStmt.Condition);
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
                PushScope();
                DeclareVariable(foreachStmt.VariableName, foreachStmt.Line, foreachStmt.Column);
                MarkVariableUsed(foreachStmt.VariableName); // Loop variables are considered used
                VisitExpression(foreachStmt.Collection);
                VisitStatement(foreachStmt.Body);
                PopScope();
                break;

            case WhileStatement whileStmt:
                VisitExpression(whileStmt.Condition);
                CheckUnnecessaryNullCheck(whileStmt.Condition);
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
                    PushScope();
                    if (catchClause.VariableName != null)
                    {
                        DeclareVariable(catchClause.VariableName, catchClause.Block.Line, catchClause.Block.Column);
                        MarkVariableUsed(catchClause.VariableName); // Exception variables are considered used
                    }
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

            case LockStatement lockStmt:
                VisitExpression(lockStmt.LockObject);
                VisitStatement(lockStmt.Body);
                break;

            case YieldStatement yieldStmt:
                if (yieldStmt.Value != null)
                    VisitExpression(yieldStmt.Value);
                break;

            case TupleDeconstructionStatement tupleDecl:
                foreach (var name in tupleDecl.Names)
                {
                    if (name != "_") // Don't track discards
                        DeclareVariable(name, tupleDecl.Line, tupleDecl.Column);
                }
                VisitExpression(tupleDecl.Initializer);
                break;

            case AwaitForEachStatement awaitForeach:
                PushScope();
                DeclareVariable(awaitForeach.VariableName, awaitForeach.Line, awaitForeach.Column);
                MarkVariableUsed(awaitForeach.VariableName);
                VisitExpression(awaitForeach.Collection);
                VisitStatement(awaitForeach.Body);
                PopScope();
                break;
        }
    }

    private void CheckUnnecessaryNullCheck(Expression condition)
    {
        // NL003: Unnecessary Null Check
        // Check for patterns like: x != null or x == null where x is a value type
        if (condition is BinaryExpression binary)
        {
            if (binary.Operator == BinaryOperator.NotEqual || binary.Operator == BinaryOperator.Equal)
            {
                var isNullCheck = binary.Right is NullLiteralExpression || binary.Left is NullLiteralExpression;

                if (isNullCheck)
                {
                    var checkedExpr = binary.Right is NullLiteralExpression ? binary.Left : binary.Right;

                    // Check if it's comparing a value type against null
                    if (checkedExpr is IdentifierExpression ident)
                    {
                        // Check if we're comparing against known value types
                        var knownValueTypes = new[] { "int", "long", "short", "byte", "uint", "ulong", "ushort",
                            "float", "double", "decimal", "bool", "char", "sbyte" };

                        // Simple heuristic: if the identifier looks like a value type
                        // In a real implementation, this would use type information from the analyzer
                        // For now, we'll be conservative and only warn for obvious cases

                        // Check assignment patterns in the current scope
                        if (_declaredVariables.TryGetValue(ident.Name, out var varInfo))
                        {
                            // We would need type information here to be more accurate
                            // For now, we'll implement a basic version
                        }
                    }

                    // Check for direct type comparisons (e.g., comparing int literal)
                    if (checkedExpr is IntLiteralExpression ||
                        checkedExpr is FloatLiteralExpression ||
                        checkedExpr is BoolLiteralExpression)
                    {
                        var typeName = checkedExpr switch
                        {
                            IntLiteralExpression => "int",
                            FloatLiteralExpression => "float",
                            BoolLiteralExpression => "bool",
                            _ => "value type"
                        };

                        _diagnostics.Add(new Diagnostic(
                            "NL003",
                            $"Unnecessary null check: '{typeName}' is never null",
                            new Location(condition.Line, condition.Column, _filePath),
                            DiagnosticSeverity.Warning));
                    }
                }
            }
        }
    }

    private void VisitExpression(Expression expression)
    {
        switch (expression)
        {
            case IdentifierExpression ident:
                MarkVariableUsed(ident.Name);

                // NL002: Missing Import
                // Check if identifier looks like a type that might need an import
                CheckMissingImport(ident);
                break;

            case BinaryExpression binary:
                VisitExpression(binary.Left);
                VisitExpression(binary.Right);
                break;

            case UnaryExpression unary:
                VisitExpression(unary.Operand);
                break;

            case CallExpression call:
                VisitExpression(call.Callee);
                foreach (var arg in call.Arguments)
                {
                    VisitExpression(arg.Value);
                }
                break;

            case NewExpression newExpr:
                // Check if the type might need an import
                if (newExpr.Type != null)
                    CheckMissingImportForType(newExpr.Type, newExpr.Line, newExpr.Column);
                foreach (var arg in newExpr.ConstructorArguments)
                {
                    VisitExpression(arg.Value);
                }
                if (newExpr.Initializer != null)
                {
                    foreach (var init in newExpr.Initializer.Properties)
                    {
                        VisitExpression(init.Value);
                    }
                }
                break;

            case MemberAccessExpression member:
                VisitExpression(member.Object);
                break;

            case IndexAccessExpression index:
                VisitExpression(index.Object);
                VisitExpression(index.Index);
                break;

            case AssignmentExpression assignment:
                VisitExpression(assignment.Target);
                VisitExpression(assignment.Value);
                break;

            case TernaryExpression ternary:
                VisitExpression(ternary.Condition);
                VisitExpression(ternary.ThenExpression);
                VisitExpression(ternary.ElseExpression);
                break;

            case LambdaExpression lambda:
                PushScope();
                foreach (var param in lambda.Parameters)
                {
                    DeclareVariable(param.Name, lambda.Line, lambda.Column);
                    MarkVariableUsed(param.Name);
                }
                if (lambda.BlockBody != null)
                    VisitStatement(lambda.BlockBody);
                if (lambda.ExpressionBody != null)
                    VisitExpression(lambda.ExpressionBody);
                PopScope();
                break;

            case CastExpression cast:
                VisitExpression(cast.Expression);
                break;

            case IsExpression isExpr:
                VisitExpression(isExpr.Expression);
                break;

            case AwaitExpression awaitExpr:
                VisitExpression(awaitExpr.Expression);
                break;

            case ArrayLiteralExpression array:
                foreach (var element in array.Elements)
                {
                    VisitExpression(element);
                }
                break;

            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    VisitExpression(element.Value);
                }
                break;

            case RangeExpression range:
                if (range.Start != null)
                    VisitExpression(range.Start);
                if (range.End != null)
                    VisitExpression(range.End);
                break;

            case MatchExpression match:
                VisitExpression(match.Value);
                foreach (var matchCase in match.Cases)
                {
                    if (matchCase.Guard != null)
                        VisitExpression(matchCase.Guard);
                    VisitExpression(matchCase.Expression);
                }
                break;

            case WithExpression withExpr:
                VisitExpression(withExpr.Target);
                foreach (var prop in withExpr.Properties)
                {
                    VisitExpression(prop.Value);
                }
                break;

            case SpreadExpression spread:
                VisitExpression(spread.Expression);
                break;

            case ThrowExpression throwExpr:
                VisitExpression(throwExpr.Expression);
                break;

            case NameofExpression nameof:
                VisitExpression(nameof.Target);
                break;

            case CheckedExpression checkedExpr:
                VisitExpression(checkedExpr.Expression);
                break;

            case UncheckedExpression uncheckedExpr:
                VisitExpression(uncheckedExpr.Expression);
                break;
        }
    }

    private void DeclareVariable(string name, int line, int column)
    {
        _declaredVariables[name] = (line, column, false);
    }

    private void MarkVariableUsed(string name)
    {
        if (_declaredVariables.ContainsKey(name))
        {
            var (line, column, _) = _declaredVariables[name];
            _declaredVariables[name] = (line, column, true);
        }
        _usedVariables.Add(name);
    }

    private void CheckMissingImport(IdentifierExpression ident)
    {
        // NL002: Missing Import
        // Check for common types that might need imports
        var commonTypesMap = new Dictionary<string, string>
        {
            { "List", "System.Collections.Generic" },
            { "Dictionary", "System.Collections.Generic" },
            { "HashSet", "System.Collections.Generic" },
            { "Queue", "System.Collections.Generic" },
            { "Stack", "System.Collections.Generic" },
            { "LinkedList", "System.Collections.Generic" },
            { "StringBuilder", "System.Text" },
            { "Regex", "System.Text.RegularExpressions" },
            { "File", "System.IO" },
            { "Directory", "System.IO" },
            { "Path", "System.IO" },
            { "Stream", "System.IO" },
            { "HttpClient", "System.Net.Http" },
            { "JsonSerializer", "System.Text.Json" },
            { "Task", "System.Threading.Tasks" },
            { "CancellationToken", "System.Threading" },
            { "Encoding", "System.Text" },
            { "DateTime", "System" },
            { "TimeSpan", "System" },
            { "Guid", "System" },
            { "Uri", "System" },
            { "Tuple", "System" },
            { "Lazy", "System" },
            { "Action", "System" },
            { "Func", "System" },
        };

        if (commonTypesMap.TryGetValue(ident.Name, out var requiredNamespace))
        {
            // Check if the namespace is already imported
            if (!_importedNamespaces.Contains(requiredNamespace))
            {
                _diagnostics.Add(new Diagnostic(
                    "NL002",
                    $"'{ident.Name}' not found",
                    new Location(ident.Line, ident.Column, _filePath),
                    DiagnosticSeverity.Error,
                    $"Add 'import {requiredNamespace}'"));
            }
        }
    }

    private void CheckMissingImportForType(TypeReference type, int line, int column)
    {
        // Extract the base type name from the type reference
        var typeName = type switch
        {
            SimpleTypeReference simple => simple.Name,
            GenericTypeReference generic => generic.Name,
            NullableTypeReference nullable => GetBaseTypeName(nullable.InnerType),
            ArrayTypeReference array => GetBaseTypeName(array.ElementType),
            _ => null
        };

        if (typeName != null)
        {
            var commonTypesMap = new Dictionary<string, string>
            {
                { "List", "System.Collections.Generic" },
                { "Dictionary", "System.Collections.Generic" },
                { "HashSet", "System.Collections.Generic" },
                { "Queue", "System.Collections.Generic" },
                { "Stack", "System.Collections.Generic" },
                { "LinkedList", "System.Collections.Generic" },
                { "StringBuilder", "System.Text" },
                { "Regex", "System.Text.RegularExpressions" },
                { "File", "System.IO" },
                { "Directory", "System.IO" },
                { "Path", "System.IO" },
                { "Stream", "System.IO" },
                { "HttpClient", "System.Net.Http" },
                { "JsonSerializer", "System.Text.Json" },
                { "Task", "System.Threading.Tasks" },
                { "CancellationToken", "System.Threading" },
            };

            if (commonTypesMap.TryGetValue(typeName, out var requiredNamespace))
            {
                if (!_importedNamespaces.Contains(requiredNamespace))
                {
                    _diagnostics.Add(new Diagnostic(
                        "NL002",
                        $"'{typeName}' not found",
                        new Location(line, column, _filePath),
                        DiagnosticSeverity.Error,
                        $"Add 'import {requiredNamespace}'"));
                }
            }
        }
    }

    private string? GetBaseTypeName(TypeReference type)
    {
        return type switch
        {
            SimpleTypeReference simple => simple.Name,
            GenericTypeReference generic => generic.Name,
            NullableTypeReference nullable => GetBaseTypeName(nullable.InnerType),
            ArrayTypeReference array => GetBaseTypeName(array.ElementType),
            _ => null
        };
    }
}
