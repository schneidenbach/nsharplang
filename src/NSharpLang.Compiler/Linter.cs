using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

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
/// Linter configuration from .editorconfig
/// </summary>
public class LinterConfig
{
    public Dictionary<string, DiagnosticSeverity> RuleSeverities { get; set; } = new();

    public static LinterConfig Default()
    {
        return new LinterConfig
        {
            RuleSeverities = new Dictionary<string, DiagnosticSeverity>
            {
                { "NL001", DiagnosticSeverity.Warning }, // Unused variable
                { "NL002", DiagnosticSeverity.Error },   // Missing import
                { "NL003", DiagnosticSeverity.Warning }, // Unnecessary null check
                { "NL004", DiagnosticSeverity.Warning }, // Async without await
                { "NL005", DiagnosticSeverity.Info },    // Use pattern matching
            }
        };
    }

    public static LinterConfig FromEditorConfig(string directoryPath)
    {
        var config = Default();

        // Look for .editorconfig files starting from directoryPath and walking up
        var current = new DirectoryInfo(directoryPath);
        while (current != null)
        {
            var editorConfigPath = Path.Combine(current.FullName, ".editorconfig");
            if (File.Exists(editorConfigPath))
            {
                ParseEditorConfig(editorConfigPath, config);

                // Check for root=true
                var lines = File.ReadAllLines(editorConfigPath);
                if (lines.Any(l => l.Trim().Equals("root=true", StringComparison.OrdinalIgnoreCase) ||
                                   l.Trim().Equals("root = true", StringComparison.OrdinalIgnoreCase)))
                {
                    break; // Stop at root
                }
            }
            current = current.Parent;
        }

        return config;
    }

    private static void ParseEditorConfig(string path, LinterConfig config)
    {
        try
        {
            var lines = File.ReadAllLines(path);
            bool inNSharpSection = false;

            foreach (var line in lines)
            {
                var trimmed = line.Trim();

                // Check for [*.nl] section
                if (trimmed.StartsWith("[") && trimmed.EndsWith("]"))
                {
                    var pattern = trimmed[1..^1];
                    inNSharpSection = pattern.Contains("*.nl") || pattern.Contains(".nl");
                    continue;
                }

                // Parse rule severities in [*.nl] section
                if (inNSharpSection && trimmed.Contains("="))
                {
                    var parts = trimmed.Split('=', 2);
                    if (parts.Length == 2)
                    {
                        var key = parts[0].Trim();
                        var value = parts[1].Trim();

                        // Handle dotnet_diagnostic.NL001.severity = warning
                        if (key.StartsWith("dotnet_diagnostic.") && key.EndsWith(".severity"))
                        {
                            var ruleCode = key["dotnet_diagnostic.".Length..^".severity".Length];

                            var severity = value.ToLower() switch
                            {
                                "error" => DiagnosticSeverity.Error,
                                "warning" => DiagnosticSeverity.Warning,
                                "info" or "suggestion" => DiagnosticSeverity.Info,
                                _ => (DiagnosticSeverity?)null
                            };

                            if (severity.HasValue)
                            {
                                config.RuleSeverities[ruleCode] = severity.Value;
                            }
                        }
                    }
                }
            }
        }
        catch
        {
            // If parsing fails, use defaults
        }
    }

    public DiagnosticSeverity GetSeverity(string ruleCode)
    {
        return RuleSeverities.TryGetValue(ruleCode, out var severity)
            ? severity
            : DiagnosticSeverity.Warning;
    }
}

/// <summary>
/// Main linter class that analyzes code and returns diagnostics
/// </summary>
public class Linter
{
    private readonly LinterConfig _config;

    public Linter(LinterConfig? config = null)
    {
        _config = config ?? LinterConfig.Default();
    }

    public List<Diagnostic> Lint(CompilationUnit ast, string? filePath = null)
    {
        var visitor = new LintVisitor(filePath, _config);
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
    private readonly LinterConfig _config;
    private readonly List<Diagnostic> _diagnostics = new();
    private readonly Dictionary<string, (int Line, int Column, bool Used)> _declaredVariables = new();
    private readonly HashSet<string> _usedVariables = new();
    private readonly Stack<Dictionary<string, (int Line, int Column, bool Used)>> _scopeStack = new();
    private readonly List<string> _importedNamespaces = new();
    private bool _hasAwaitInFunction = false;
    private bool _inAsyncFunction = false;

    public List<Diagnostic> Diagnostics => _diagnostics;

    public LintVisitor(string? filePath = null, LinterConfig? config = null)
    {
        _filePath = filePath;
        _config = config ?? LinterConfig.Default();
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
                AddDiagnostic(
                    "NL001",
                    $"Unused variable '{varName}'",
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL001"));
            }
        }
    }

    private void AddDiagnostic(string code, string message, Location location, DiagnosticSeverity severity, string? suggestion = null)
    {
        _diagnostics.Add(new Diagnostic(code, message, location, severity, suggestion));
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
        // NL004: Check for async without await
        var wasInAsync = _inAsyncFunction;
        var hadAwait = _hasAwaitInFunction;
        _inAsyncFunction = func.Modifiers.HasFlag(Modifiers.Async);
        _hasAwaitInFunction = false;

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
                    $"Async function '{func.Name}' does not use 'await'",
                    new Location(func.Line, func.Column, _filePath),
                    _config.GetSeverity("NL004"),
                    "Consider removing 'async' or use 'await' with async operations");
            }
        }

        // Restore state
        _inAsyncFunction = wasInAsync;
        _hasAwaitInFunction = hadAwait;
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
                VisitExpression(foreachStmt.Collection); // Visit collection in outer scope FIRST
                PushScope();
                DeclareVariable(foreachStmt.VariableName, foreachStmt.Line, foreachStmt.Column);
                MarkVariableUsed(foreachStmt.VariableName); // Loop variables are considered used
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

                        AddDiagnostic(
                            "NL003",
                            $"Unnecessary null check: '{typeName}' is never null",
                            new Location(condition.Line, condition.Column, _filePath),
                            _config.GetSeverity("NL003"));
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

            case StringLiteralExpression stringLiteral:
                // Handle string interpolation - mark variables used inside ${...} or {...}
                HandleStringInterpolation(stringLiteral.Value);
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
                _hasAwaitInFunction = true; // Track that we're using await
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
                AddDiagnostic(
                    "NL002",
                    $"'{ident.Name}' not found",
                    new Location(ident.Line, ident.Column, _filePath),
                    _config.GetSeverity("NL002"),
                    $"Add 'import {requiredNamespace}'");
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
                    AddDiagnostic(
                        "NL002",
                        $"'{typeName}' not found",
                        new Location(line, column, _filePath),
                        _config.GetSeverity("NL002"),
                        $"Add 'import {requiredNamespace}'");
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

    private void HandleStringInterpolation(string value)
    {
        // Check if this is an interpolated string ($"..." or $""\"...\""")
        if (!value.StartsWith("$"))
            return;

        // Extract interpolated expressions between { and }
        // Handle both $"..." and $"""...""" formats
        int i = 0;
        if (value.StartsWith("$\"\"\""))
        {
            i = 4; // Start after $"""
        }
        else if (value.StartsWith("$\""))
        {
            i = 2; // Start after $"
        }
        else
        {
            return; // Not an interpolated string
        }

        while (i < value.Length)
        {
            if (value[i] == '{')
            {
                // Found start of interpolation
                int braceDepth = 1;
                i++;
                int exprStart = i;

                // Find the matching closing brace
                while (i < value.Length && braceDepth > 0)
                {
                    if (value[i] == '{')
                        braceDepth++;
                    else if (value[i] == '}')
                        braceDepth--;
                    i++;
                }

                // Extract the expression between braces
                if (braceDepth == 0)
                {
                    string expr = value.Substring(exprStart, i - exprStart - 1).Trim();

                    // Extract identifier(s) from the expression
                    // Simple cases: {name}, {obj.Property}, {list[0]}
                    ExtractIdentifiersFromExpression(expr);
                }
            }
            else
            {
                i++;
            }
        }
    }

    private void ExtractIdentifiersFromExpression(string expr)
    {
        // Simple identifier extraction from interpolated expressions
        // Handles: name, obj.Property, obj?.Property, list[0], obj.Method()

        // Split by common operators and extract the first identifier
        var separators = new[] { '.', '?', '[', '(', ' ', '+', '-', '*', '/', '%', '&', '|', '^', '!', '=', '<', '>', ':', ',' };

        // Find the first identifier (before any operator)
        int firstSeparator = expr.Length;
        foreach (var sep in separators)
        {
            int index = expr.IndexOf(sep);
            if (index >= 0 && index < firstSeparator)
                firstSeparator = index;
        }

        string firstIdentifier = expr.Substring(0, firstSeparator).Trim();

        // Mark the first identifier as used (this is the variable being accessed)
        if (!string.IsNullOrEmpty(firstIdentifier) && IsValidIdentifier(firstIdentifier))
        {
            MarkVariableUsed(firstIdentifier);
        }
    }

    private bool IsValidIdentifier(string name)
    {
        if (string.IsNullOrEmpty(name))
            return false;

        // Must start with letter or underscore
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
}
