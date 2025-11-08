using System.Collections.Generic;

namespace NewCLILang.Compiler.Ast;

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

// Yield statement
public record YieldStatement(
    Expression Value,
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
