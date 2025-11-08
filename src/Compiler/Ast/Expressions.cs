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

// Range expression (supports open-ended ranges: ..end, start.., start..end, ..)
public record RangeExpression(
    Expression? Start,  // null for open-ended start (..end, ..)
    Expression? End,    // null for open-ended end (start.., ..)
    int Line,
    int Column) : Expression(Line, Column);

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
    Negate, Not, BitwiseNot, PreIncrement, PreDecrement, PostIncrement, PostDecrement, IndexFromEnd
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

public enum ArgumentModifier
{
    None,
    Ref,
    Out
}

public record Argument(string? Name, Expression Value, ArgumentModifier Modifier = ArgumentModifier.None);

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
    TypeReference? Type,  // Nullable for target-typed new (C# 9)
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
// Property pattern for nested property matching
// Examples:
//   { Name: "John" }           -> Pattern = LiteralPattern("John"), BindingName = null
//   { Name: name }             -> Pattern = null, BindingName = "name"
//   { Address: { City: "NYC" } } -> Pattern = UnionCasePattern with nested properties
public record PropertyPattern(
    string Name,
    Pattern? Pattern,      // Nested pattern (literal, identifier, or nested properties)
    string? BindingName);  // Variable binding (if Pattern is null)

// Relational pattern (< value, >= value, etc.)
public record RelationalPattern(
    string Operator, // "<", ">", "<=", ">=", "==", "!="
    Expression Value,
    int Line,
    int Column) : Pattern(Line, Column);

// Logical patterns (and, or, not)
public record AndPattern(
    Pattern Left,
    Pattern Right,
    int Line,
    int Column) : Pattern(Line, Column);

public record OrPattern(
    Pattern Left,
    Pattern Right,
    int Line,
    int Column) : Pattern(Line, Column);

public record NotPattern(
    Pattern Pattern,
    int Line,
    int Column) : Pattern(Line, Column);

// Positional pattern for tuples/deconstructable types
public record PositionalPattern(
    List<Pattern> Patterns,
    int Line,
    int Column) : Pattern(Line, Column);

// Object property pattern for matching arbitrary types (not just unions)
// Example: { Address: { City: "NYC", State: "NY" } }
public record ObjectPattern(
    List<PropertyPattern> Properties,
    int Line,
    int Column) : Pattern(Line, Column);

// List pattern for array/list pattern matching (C# 11)
// Examples:
//   [1, 2, 3]           -> exact match with literal patterns
//   [var first, ..]     -> capture first element, rest ignored
//   [.., var last]      -> capture last element
//   [var x, .. var rest, var y]  -> slice pattern with middle capture
//   []                  -> empty list
public record ListPattern(
    List<Pattern> Elements,  // Element patterns (can include SlicePattern)
    int Line,
    int Column) : Pattern(Line, Column);

// Slice pattern for capturing remaining elements in list patterns
// Used in list patterns: [first, .. middle, last]
// The .. operator captures zero or more elements
public record SlicePattern(
    string? BindingName,  // Optional variable to bind the slice (null for discard ..)
    int Line,
    int Column) : Pattern(Line, Column);

// Type pattern for type checking and variable binding in match expressions
// Examples:
//   string s => ...         -> type check and bind
//   Person p => ...         -> type check and bind
//   IEnumerable<int> list when list.Any() => ...  -> with guard
public record TypePattern(
    TypeReference Type,      // The type to check against
    string? BindingName,     // Variable name to bind (optional)
    int Line,
    int Column) : Pattern(Line, Column);

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

// Nameof expression
public record NameofExpression(
    Expression Target,
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

// Out variable declaration expression (C# 7+)
// Used for inline variable declarations in out parameters
// Examples:
//   TryParse("123", out var result)    -> type inferred
//   TryParse("123", out int result)    -> explicit type
public record OutVariableDeclarationExpression(
    TypeReference? Type,     // null for 'var' (type inference)
    string VariableName,
    int Line,
    int Column) : Expression(Line, Column);
