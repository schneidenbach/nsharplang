namespace NSharpLang.Compiler.Ast

import System.Collections.Generic

// Base class for all AST nodes
public class AstNode {
    Line: int
    Column: int

    constructor(Line: int, Column: int) {
        this.Line = Line
        this.Column = Column
    }
}

// Base class for all expressions
public class Expression: AstNode {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Literals
public class IntLiteralExpression: Expression {
    Value: string

    constructor(Value: string, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
    }
}

public class FloatLiteralExpression: Expression {
    Value: string

    constructor(Value: string, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
    }
}

public class CharLiteralExpression: Expression {
    Value: string

    constructor(Value: string, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
    }
}

public class StringLiteralExpression: Expression {
    Value: string

    constructor(Value: string, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
    }
}

// Interpolated string: $"Hello, {name}!"
// Decomposed into text segments and expression holes for proper semantic analysis.
public class InterpolatedStringExpression: Expression {
    Parts: List<InterpolatedStringPart>
    IsRaw: bool

    constructor(Parts: List<InterpolatedStringPart>, Line: int, Column: int, IsRaw: bool = false): base(Line, Column) {
        this.Parts = Parts
        this.IsRaw = IsRaw
    }
}

public class InterpolatedStringPart: AstNode {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Literal text segment in an interpolated string
public class InterpolatedStringText: InterpolatedStringPart {
    Text: string

    constructor(Text: string, Line: int, Column: int): base(Line, Column) {
        this.Text = Text
    }
}

// Expression hole in an interpolated string: {expr} or {expr:format}
public class InterpolatedStringHole: InterpolatedStringPart {
    Expression: Expression
    FormatClause: string?

    constructor(Expression: Expression, FormatClause: string?, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
        this.FormatClause = FormatClause
    }
}

public class BoolLiteralExpression: Expression {
    Value: bool

    constructor(Value: bool, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
    }
}

public class NullLiteralExpression: Expression {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Identifier
public class IdentifierExpression: Expression {
    Name: string

    constructor(Name: string, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
    }
}

// Range expression (supports open-ended ranges: ..end, start.., start..end, ..)
public class RangeExpression: Expression {
    Start: Expression?
    End: Expression?

    constructor(Start: Expression?, End: Expression?, Line: int, Column: int): base(Line, Column) {
        this.Start = Start
        this.End = End
    }
}

// Binary operations
public class BinaryExpression: Expression {
    Left: Expression
    Operator: BinaryOperator
    Right: Expression

    constructor(Left: Expression, Operator: BinaryOperator, Right: Expression, Line: int, Column: int): base(Line, Column) {
        this.Left = Left
        this.Operator = Operator
        this.Right = Right
    }
}

// Unary operations
public class UnaryExpression: Expression {
    Operator: UnaryOperator
    Operand: Expression

    constructor(Operator: UnaryOperator, Operand: Expression, Line: int, Column: int): base(Line, Column) {
        this.Operator = Operator
        this.Operand = Operand
    }
}

// Explicit nullable unwrap: must value
public class MustExpression: Expression {
    Expression: Expression

    constructor(Expression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
    }
}

// Member access
public class MemberAccessExpression: Expression {
    Object: Expression
    MemberName: string
    IsNullConditional: bool

    constructor(Object: Expression, MemberName: string, IsNullConditional: bool, Line: int, Column: int): base(Line, Column) {
        this.Object = Object
        this.MemberName = MemberName
        this.IsNullConditional = IsNullConditional
    }
}

// Index access
public class IndexAccessExpression: Expression {
    Object: Expression
    Index: Expression
    IsNullConditional: bool

    constructor(Object: Expression, Index: Expression, IsNullConditional: bool, Line: int, Column: int): base(Line, Column) {
        this.Object = Object
        this.Index = Index
        this.IsNullConditional = IsNullConditional
    }
}

// Function call
public class CallExpression: Expression {
    Callee: Expression
    Arguments: List<Argument>
    TypeArguments: List<TypeReference>?
    IsResultFactory: bool?

    constructor(Callee: Expression, Arguments: List<Argument>, TypeArguments: List<TypeReference>?, Line: int, Column: int): base(Line, Column) {
        this.Callee = Callee
        this.Arguments = Arguments
        this.TypeArguments = TypeArguments
    }
}

public class Argument {
    Name: string?
    Value: Expression
    Modifier: ArgumentModifier

    constructor(Name: string?, Value: Expression, Modifier: ArgumentModifier = ArgumentModifier.None) {
        this.Name = Name
        this.Value = Value
        this.Modifier = Modifier
    }
}

// Assignment
public class AssignmentExpression: Expression {
    Target: Expression
    Operator: AssignmentOperator
    Value: Expression

    constructor(Target: Expression, Operator: AssignmentOperator, Value: Expression, Line: int, Column: int): base(Line, Column) {
        this.Target = Target
        this.Operator = Operator
        this.Value = Value
    }
}

// Lambda expression
public class LambdaExpression: Expression {
    Parameters: List<Parameter>
    ExpressionBody: Expression?
    BlockBody: BlockStatement?

    constructor(Parameters: List<Parameter>, ExpressionBody: Expression?, BlockBody: BlockStatement?, Line: int, Column: int): base(Line, Column) {
        this.Parameters = Parameters
        this.ExpressionBody = ExpressionBody
        this.BlockBody = BlockBody
    }
}

// Event subscription: `on target.Event (sender, args) => { ... }`
public class OnSubscriptionExpression: Expression {
    Target: Expression
    Handler: LambdaExpression

    constructor(Target: Expression, Handler: LambdaExpression, Line: int, Column: int): base(Line, Column) {
        this.Target = Target
        this.Handler = Handler
    }
}

// Ternary (conditional) expression
public class TernaryExpression: Expression {
    Condition: Expression
    ThenExpression: Expression
    ElseExpression: Expression

    constructor(Condition: Expression, ThenExpression: Expression, ElseExpression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Condition = Condition
        this.ThenExpression = ThenExpression
        this.ElseExpression = ElseExpression
    }
}

// Array literal
public class ArrayLiteralExpression: Expression {
    Elements: List<Expression>
    IsImmutable: bool

    constructor(Elements: List<Expression>, IsImmutable: bool, Line: int, Column: int): base(Line, Column) {
        this.Elements = Elements
        this.IsImmutable = IsImmutable
    }
}

// Tuple expression
public class TupleExpression: Expression {
    Elements: List<TupleElement>

    constructor(Elements: List<TupleElement>, Line: int, Column: int): base(Line, Column) {
        this.Elements = Elements
    }
}

public class TupleElement {
    Name: string?
    Value: Expression

    constructor(Name: string?, Value: Expression) {
        this.Name = Name
        this.Value = Value
    }
}

// Object initializer (for new expressions)
public class ObjectInitializerExpression: Expression {
    Properties: List<PropertyInitializer>

    constructor(Properties: List<PropertyInitializer>, Line: int, Column: int): base(Line, Column) {
        this.Properties = Properties
    }
}

// Property or indexer initializer
public class PropertyInitializer {
    Name: string?
    IndexExpression: Expression?
    Value: Expression
    NameLine: int
    NameColumn: int

    IsIndexerInitializer: bool => IndexExpression != null

    constructor(Name: string?, IndexExpression: Expression?, Value: Expression, NameLine: int = 0, NameColumn: int = 0) {
        this.Name = Name
        this.IndexExpression = IndexExpression
        this.Value = Value
        this.NameLine = NameLine
        this.NameColumn = NameColumn
    }
}

// New expression
public class NewExpression: Expression {
    Type: TypeReference?
    ConstructorArguments: List<Argument>
    Initializer: ObjectInitializerExpression?
    ArrayLengthExpression: Expression?

    constructor(Type: TypeReference?, ConstructorArguments: List<Argument>, Initializer: ObjectInitializerExpression?, Line: int, Column: int, ArrayLengthExpression: Expression? = null): base(Line, Column) {
        this.Type = Type
        this.ConstructorArguments = ConstructorArguments
        this.Initializer = Initializer
        this.ArrayLengthExpression = ArrayLengthExpression
    }
}

// Explicit systems allocation marker: alloc new Foo(), alloc [1, 2], alloc $"..."
public class AllocExpression: Expression {
    Expression: Expression

    constructor(Expression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
    }
}

// Safe systems stack allocation: stackalloc byte[64] -> Span<byte>.
public class StackAllocExpression: Expression {
    ElementType: TypeReference
    LengthExpression: Expression

    constructor(ElementType: TypeReference, LengthExpression: Expression, Line: int, Column: int): base(Line, Column) {
        this.ElementType = ElementType
        this.LengthExpression = LengthExpression
    }
}

// Type casting
public class CastExpression: Expression {
    Expression: Expression
    TargetType: TypeReference
    Kind: CastKind

    constructor(Expression: Expression, TargetType: TypeReference, Kind: CastKind, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
        this.TargetType = TargetType
        this.Kind = Kind
    }
}

// Type checking
public class IsExpression: Expression {
    Expression: Expression
    Type: TypeReference
    VariableName: string?

    constructor(Expression: Expression, Type: TypeReference, VariableName: string?, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
        this.Type = Type
        this.VariableName = VariableName
    }
}

// Match expression
public class MatchExpression: Expression {
    Value: Expression
    Cases: List<MatchCase>
    IsExhaustive: bool

    constructor(Value: Expression, Cases: List<MatchCase>, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
        this.Cases = Cases
    }
}

public class MatchCase {
    Pattern: Pattern
    Guard: Expression?
    Expression: Expression

    constructor(Pattern: Pattern, Guard: Expression?, Expression: Expression) {
        this.Pattern = Pattern
        this.Guard = Guard
        this.Expression = Expression
    }
}

// Pattern base class
public class Pattern {
    Line: int
    Column: int

    constructor(Line: int, Column: int) {
        this.Line = Line
        this.Column = Column
    }
}

public class IdentifierPattern: Pattern {
    Name: string

    constructor(Name: string, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
    }
}

public class LiteralPattern: Pattern {
    Literal: Expression

    constructor(Literal: Expression, Line: int, Column: int): base(Line, Column) {
        this.Literal = Literal
    }
}

public class UnionCasePattern: Pattern {
    CaseName: string
    Properties: List<PropertyPattern>?

    constructor(CaseName: string, Properties: List<PropertyPattern>?, Line: int, Column: int): base(Line, Column) {
        this.CaseName = CaseName
        this.Properties = Properties
    }
}

// Property pattern for nested property matching
public class PropertyPattern {
    Name: string
    Pattern: Pattern?
    BindingName: string?
    Line: int
    Column: int

    constructor(Name: string, Pattern: Pattern?, BindingName: string?, Line: int = 0, Column: int = 0) {
        this.Name = Name
        this.Pattern = Pattern
        this.BindingName = BindingName
        this.Line = Line
        this.Column = Column
    }
}

// Relational pattern (< value, >= value, etc.)
public class RelationalPattern: Pattern {
    Operator: string
    Value: Expression

    constructor(Operator: string, Value: Expression, Line: int, Column: int): base(Line, Column) {
        this.Operator = Operator
        this.Value = Value
    }
}

// Logical patterns (and, or, not)
public class AndPattern: Pattern {
    Left: Pattern
    Right: Pattern

    constructor(Left: Pattern, Right: Pattern, Line: int, Column: int): base(Line, Column) {
        this.Left = Left
        this.Right = Right
    }
}

public class OrPattern: Pattern {
    Left: Pattern
    Right: Pattern

    constructor(Left: Pattern, Right: Pattern, Line: int, Column: int): base(Line, Column) {
        this.Left = Left
        this.Right = Right
    }
}

public class NotPattern: Pattern {
    Pattern: Pattern

    constructor(Pattern: Pattern, Line: int, Column: int): base(Line, Column) {
        this.Pattern = Pattern
    }
}

// Positional pattern for tuples/deconstructable types
public class PositionalPattern: Pattern {
    Patterns: List<Pattern>

    constructor(Patterns: List<Pattern>, Line: int, Column: int): base(Line, Column) {
        this.Patterns = Patterns
    }
}

// Object property pattern for matching arbitrary types (not just unions)
public class ObjectPattern: Pattern {
    Properties: List<PropertyPattern>

    constructor(Properties: List<PropertyPattern>, Line: int, Column: int): base(Line, Column) {
        this.Properties = Properties
    }
}

// List pattern for array/list pattern matching (C# 11)
public class ListPattern: Pattern {
    Elements: List<Pattern>

    constructor(Elements: List<Pattern>, Line: int, Column: int): base(Line, Column) {
        this.Elements = Elements
    }
}

// Slice pattern for capturing remaining elements in list patterns
public class SlicePattern: Pattern {
    BindingName: string?

    constructor(BindingName: string?, Line: int, Column: int): base(Line, Column) {
        this.BindingName = BindingName
    }
}

// Type pattern for type checking and variable binding in match expressions
public class TypePattern: Pattern {
    Type: TypeReference
    BindingName: string?

    constructor(Type: TypeReference, BindingName: string?, Line: int, Column: int): base(Line, Column) {
        this.Type = Type
        this.BindingName = BindingName
    }
}

// Spread expression (for arrays and function calls)
public class SpreadExpression: Expression {
    Expression: Expression

    constructor(Expression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
    }
}

// With expression (for records)
public class WithExpression: Expression {
    Target: Expression
    Properties: List<PropertyInitializer>

    constructor(Target: Expression, Properties: List<PropertyInitializer>, Line: int, Column: int): base(Line, Column) {
        this.Target = Target
        this.Properties = Properties
    }
}

// Await expression
public class AwaitExpression: Expression {
    Expression: Expression

    constructor(Expression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
    }
}

// Throw expression
public class ThrowExpression: Expression {
    Expression: Expression

    constructor(Expression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
    }
}

// Typeof expression
public class TypeOfExpression: Expression {
    Type: TypeReference

    constructor(Type: TypeReference, Line: int, Column: int): base(Line, Column) {
        this.Type = Type
    }
}

// Nameof expression
public class NameofExpression: Expression {
    Target: Expression

    constructor(Target: Expression, Line: int, Column: int): base(Line, Column) {
        this.Target = Target
    }
}

// Sizeof expression
public class SizeOfExpression: Expression {
    Type: TypeReference

    constructor(Type: TypeReference, Line: int, Column: int): base(Line, Column) {
        this.Type = Type
    }
}

// Checked expression - throws on arithmetic overflow
public class CheckedExpression: Expression {
    Expression: Expression

    constructor(Expression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
    }
}

// Unchecked expression - wraps on arithmetic overflow
public class UncheckedExpression: Expression {
    Expression: Expression

    constructor(Expression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
    }
}

// This expression
public class ThisExpression: Expression {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Base expression
public class BaseExpression: Expression {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Default expression: target-typed default value for any type
public class DefaultExpression: Expression {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Parenthesized expression: (expr)
public class ParenthesizedExpression: Expression {
    Inner: Expression

    constructor(Inner: Expression, Line: int, Column: int): base(Line, Column) {
        this.Inner = Inner
    }
}
