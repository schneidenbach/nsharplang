using System.Collections.Generic;

namespace NSharpLang.Compiler.Ast;

// Base class for all statements
public abstract record Statement(int Line, int Column) : AstNode(Line, Column);

// Expression statement
public record ExpressionStatement(
    Expression Expression,
    int Line,
    int Column) : Statement(Line, Column);

// Variable declaration
public record VariableDeclarationStatement(
    string Name,
    TypeReference? Type,
    Expression? Initializer,
    VariableKind Kind,
    int Line,
    int Column) : Statement(Line, Column);

// Tuple deconstruction: (x, y) := GetPair()
public record TupleDeconstructionStatement(
    List<string> Names,  // Variable names (or "_" for discard)
    Expression Initializer,
    VariableKind Kind,
    int Line,
    int Column) : Statement(Line, Column);

public enum VariableKind
{
    Let,      // let or :=
    Const,    // const
    Readonly  // readonly
}

// Block statement
public record BlockStatement(
    List<Statement> Statements,
    int Line,
    int Column) : Statement(Line, Column);

// If statement
public record IfStatement(
    Expression Condition,
    Statement ThenStatement,
    Statement? ElseStatement,
    int Line,
    int Column) : Statement(Line, Column);

// For loop
public record ForStatement(
    Statement? Initializer,
    Expression? Condition,
    Expression? Iterator,
    Statement Body,
    int Line,
    int Column) : Statement(Line, Column);

// Foreach loop
public record ForeachStatement(
    string VariableName,
    Expression Collection,
    Statement Body,
    int Line,
    int Column) : Statement(Line, Column);

// Await foreach loop (async iteration - C# 8+)
public record AwaitForEachStatement(
    string VariableName,
    Expression Collection,
    Statement Body,
    int Line,
    int Column) : Statement(Line, Column);

// While loop
public record WhileStatement(
    Expression Condition,
    Statement Body,
    int Line,
    int Column) : Statement(Line, Column);

// Return statement
public record ReturnStatement(
    Expression? Value,
    int Line,
    int Column) : Statement(Line, Column);

// Yield statement (Value is null for "yield break")
public record YieldStatement(
    Expression? Value,
    int Line,
    int Column) : Statement(Line, Column);

// Break statement
public record BreakStatement(int Line, int Column) : Statement(Line, Column);

// Continue statement
public record ContinueStatement(int Line, int Column) : Statement(Line, Column);

// Throw statement
public record ThrowStatement(
    Expression Expression,
    int Line,
    int Column) : Statement(Line, Column);

// Try-catch-finally statement
public record TryStatement(
    BlockStatement TryBlock,
    List<CatchClause> CatchClauses,
    BlockStatement? FinallyBlock,
    int Line,
    int Column) : Statement(Line, Column);

public record CatchClause(
    TypeReference? ExceptionType,
    string? VariableName,
    BlockStatement Block);

// Using statement
public record UsingStatement(
    VariableDeclarationStatement? Declaration,
    Expression? Expression,
    Statement? Body,
    int Line,
    int Column) : Statement(Line, Column);

// Lock statement for thread synchronization
public record LockStatement(
    Expression LockObject,
    BlockStatement Body,
    int Line,
    int Column) : Statement(Line, Column);

// Switch statement (non-exhaustive)
public record SwitchStatement(
    Expression Value,
    List<SwitchCase> Cases,
    int Line,
    int Column) : Statement(Line, Column);

public record SwitchCase(
    Pattern? Pattern, // null for default case
    List<Statement> Statements);

// Empty statement
public record EmptyStatement(int Line, int Column) : Statement(Line, Column);

// Print statement
public record PrintStatement(
    Expression Value,
    int Line,
    int Column) : Statement(Line, Column);

// Preprocessor directive (pass-through to C#)
public record PreprocessorDirective(
    string Directive,  // Full directive text including # (e.g., "#if DEBUG", "#region Helpers")
    int Line,
    int Column) : Statement(Line, Column);

// File-based import: import "path/to/file" [as Alias]
public record FileImport(
    string Path,
    string? Alias,
    int Line,
    int Column) : Statement(Line, Column);

// Namespace import: import System.Collections.Generic [as Alias]
public record NamespaceImport(
    string Namespace,
    string? Alias,
    int Line,
    int Column) : Statement(Line, Column);

// Assert statement (for test files)
public record AssertStatement(
    Expression Condition,
    Expression? Message,
    int Line,
    int Column) : Statement(Line, Column);

// Assert throws statement (for test files) - assert throws ExceptionType { body }
public record AssertThrowsStatement(
    TypeReference ExceptionType,
    BlockStatement Body,
    int Line,
    int Column) : Statement(Line, Column);

// Local function statement (C# 7) - function declared inside another function
public record LocalFunctionStatement(
    FunctionDeclaration Function,
    int Line,
    int Column) : Statement(Line, Column);
