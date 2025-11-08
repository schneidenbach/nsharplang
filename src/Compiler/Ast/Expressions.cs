using System.Collections.Generic;

namespace NewCLILang.Compiler.Ast;

// Base class for all AST nodes
public abstract record AstNode(int Line, int Column);

// Base class for all expressions
public abstract record Expression(int Line, int Column) : AstNode(Line, Column);

// Literals
public record IntLiteralExpression(string Value, int Line, int Column) : Expression(Line, Column);
public record FloatLiteralExpression(string Value, int Line, int Column) : Expression(Line, Column);
public record StringLiteralExpression(string Value, int Line, int Column) : Expression(Line, Column);
public record BoolLiteralExpression(bool Value, int Line, int Column) : Expression(Line, Column);
public record NullLiteralExpression(int Line, int Column) : Expression(Line, Column);

// Identifier
public record IdentifierExpression(string Name, int Line, int Column) : Expression(Line, Column);

// Binary operations
public record BinaryExpression(
    Expression Left,
    BinaryOperator Operator,
    Expression Right,
    int Line,
    int Column) : Expression(Line, Column);

public enum BinaryOperator
{
    // Arithmetic
    Add, Subtract, Multiply, Divide, Modulo,
    // Comparison
    Equal, NotEqual, Less, LessOrEqual, Greater, GreaterOrEqual,
    // Logical
    And, Or,
    // Bitwise
    BitwiseAnd, BitwiseOr, BitwiseXor, LeftShift, RightShift,
    // Null coalescing
    NullCoalesce,
    // Range
    Range,
}

// Unary operations
public record UnaryExpression(
    UnaryOperator Operator,
    Expression Operand,
    int Line,
    int Column) : Expression(Line, Column);

public enum UnaryOperator
{
    Negate, Not, BitwiseNot, PreIncrement, PreDecrement, PostIncrement, PostDecrement
}

// Member access
public record MemberAccessExpression(
    Expression Object,
    string MemberName,
    bool IsNullConditional,
    int Line,
    int Column) : Expression(Line, Column);

// Index access
public record IndexAccessExpression(
    Expression Object,
    Expression Index,
    bool IsNullConditional,
    int Line,
    int Column) : Expression(Line, Column);

// Function call
public record CallExpression(
    Expression Callee,
    List<Argument> Arguments,
    int Line,
    int Column) : Expression(Line, Column);

public record Argument(string? Name, Expression Value);

// Assignment
public record AssignmentExpression(
    Expression Target,
    AssignmentOperator Operator,
    Expression Value,
    int Line,
    int Column) : Expression(Line, Column);

public enum AssignmentOperator
{
    Assign, AddAssign, SubtractAssign, MultiplyAssign, DivideAssign, NullCoalesceAssign
}

// Lambda expression
public record LambdaExpression(
    List<Parameter> Parameters,
    Expression? ExpressionBody,
    BlockStatement? BlockBody,
    int Line,
    int Column) : Expression(Line, Column);

// Ternary (conditional) expression
public record TernaryExpression(
    Expression Condition,
    Expression ThenExpression,
    Expression ElseExpression,
    int Line,
    int Column) : Expression(Line, Column);

// Array literal
public record ArrayLiteralExpression(
    List<Expression> Elements,
    bool IsImmutable,
    int Line,
    int Column) : Expression(Line, Column);

// Tuple expression
public record TupleExpression(
    List<TupleElement> Elements,
    int Line,
    int Column) : Expression(Line, Column);

public record TupleElement(string? Name, Expression Value);

// Object initializer (for new expressions)
public record ObjectInitializerExpression(
    List<PropertyInitializer> Properties,
    int Line,
    int Column) : Expression(Line, Column);

public record PropertyInitializer(string Name, Expression Value);

// New expression
public record NewExpression(
    TypeReference Type,
    List<Argument> ConstructorArguments,
    ObjectInitializerExpression? Initializer,
    int Line,
    int Column) : Expression(Line, Column);

// Type casting
public record CastExpression(
    Expression Expression,
    TypeReference TargetType,
    CastKind Kind,
    int Line,
    int Column) : Expression(Line, Column);

public enum CastKind
{
    Hard,    // (Type)expr
    Safe,    // expr as Type
}

// Type checking
public record IsExpression(
    Expression Expression,
    TypeReference Type,
    string? VariableName, // For pattern matching: if x is string s
    int Line,
    int Column) : Expression(Line, Column);

// Match expression
public record MatchExpression(
    Expression Value,
    List<MatchCase> Cases,
    int Line,
    int Column) : Expression(Line, Column);

public record MatchCase(Pattern Pattern, Expression? Guard, Expression Expression);

// Pattern base class
public abstract record Pattern(int Line, int Column);

public record IdentifierPattern(string Name, int Line, int Column) : Pattern(Line, Column);
public record LiteralPattern(Expression Literal, int Line, int Column) : Pattern(Line, Column);
public record UnionCasePattern(
    string CaseName,
    List<PropertyPattern>? Properties,
    int Line,
    int Column) : Pattern(Line, Column);
public record PropertyPattern(string Name, string? BindingName);

// Spread expression (for arrays and function calls)
public record SpreadExpression(
    Expression Expression,
    int Line,
    int Column) : Expression(Line, Column);

// With expression (for records)
public record WithExpression(
    Expression Target,
    List<PropertyInitializer> Properties,
    int Line,
    int Column) : Expression(Line, Column);

// Await expression
public record AwaitExpression(
    Expression Expression,
    int Line,
    int Column) : Expression(Line, Column);

// Throw expression
public record ThrowExpression(
    Expression Expression,
    int Line,
    int Column) : Expression(Line, Column);

// Typeof expression
public record TypeOfExpression(
    TypeReference Type,
    int Line,
    int Column) : Expression(Line, Column);

// Sizeof expression
public record SizeOfExpression(
    TypeReference Type,
    int Line,
    int Column) : Expression(Line, Column);

// This expression
public record ThisExpression(int Line, int Column) : Expression(Line, Column);

// Base expression
public record BaseExpression(int Line, int Column) : Expression(Line, Column);
