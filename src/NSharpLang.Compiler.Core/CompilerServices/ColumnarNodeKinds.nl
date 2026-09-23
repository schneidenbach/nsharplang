namespace NSharpLang.Compiler.Columnar


// THE ONE LIVE EXPRESSION-NODE-KIND LEDGER.
//
// `ColumnarNodeTable` stores a node's kind as a bare `int`, and for most of this compiler's life
// nothing named those integers at the boundary: 1,355 comparisons were written against a raw
// literal, against 337 that used this table -- often in the same expression, as
// `Kind(node) == 5 || Kind(node) == ColumnarExpressionNodeKind.NullLiteralExpression`. The
// producers in `ColumnarParserKernels` and the consumers in the emitter and the planners agreed by
// coincidence of arithmetic. They agree by name now.
//
// EXPRESSION AND STATEMENT KINDS SHARE ONE INTEGER SPACE AND OVERLAP IN IT: 60, 61 and 62 are
// `NamedArgumentExpression` / `TypeBindingPattern` / `NameOfExpression` here and
// `AllowStatement` / `AssertStatement` / `AssertThrowsStatement` on `ColumnarStatementNodeKind`.
// Which table a site reads is decided by which table the NODE came out of, so a site that asks a
// statement node about kind 61 means `assert`, and one that asks an expression node means a type
// binding. That is exactly the distinction a bare `61` cannot carry.
class ColumnarExpressionNodeKind {

    // an `int` literal
    const IntLiteralExpression: int = 0
    // a `float` literal
    const FloatLiteralExpression: int = 1
    // a `char` literal
    const CharLiteralExpression: int = 2
    // a string literal, any spelling
    const StringLiteralExpression: int = 3
    // `true` / `false`
    const BoolLiteralExpression: int = 4
    // `null`
    const NullLiteralExpression: int = 5
    // a bare name
    const IdentifierExpression: int = 6
    // `( expr )`
    const ParenthesizedExpression: int = 7
    // `obj.member`, member name in the value span
    const MemberAccessExpression: int = 8
    // `callee(args)`, children [callee, arg0, ...]
    const CallExpression: int = 9
    // `obj[index]`, children [object, index]
    const IndexAccessExpression: int = 10
    // a PREFIX operator, the token in the value span
    const UnaryExpression: int = 11
    // `left OP right`, the operator in the value span
    const BinaryExpression: int = 12
    // `cond ? then : else`
    const TernaryExpression: int = 13
    // `target OP value` -- `=` and every compound form
    const AssignmentExpression: int = 14
    // `new <type>(args)` / `new <element>[length]`
    const NewExpression: int = 15
    // `(<type>) operand` -- the hard cast
    const CastExpression: int = 16
    // `( e0, e1, ... )` -- a tuple literal
    const TupleExpression: int = 17
    // `match value { pat => result, ... }`
    const MatchExpression: int = 18
    // `<pattern> when <guard>`
    const GuardedPattern: int = 19
    // `< <= > >=` against a constant, in pattern position
    const RelationalPattern: int = 32
    // `<pat> and <pat>`
    const AndPattern: int = 33
    // `<pat> or <pat>`
    const OrPattern: int = 34
    // `not <pat>`
    const NotPattern: int = 35
    // `new <type> { Field: value, ... }`
    const ObjectInitializerExpression: int = 36
    // `<Union.Case> { field, field: pat }` in pattern position
    const UnionCasePattern: int = 37
    // `callee<T1, T2>` immediately before a `(`
    const GenericCallee: int = 38
    // `x => …` and its parenthesised forms
    const Lambda: int = 39
    // `new <type>` with neither arguments nor initializers
    const BareNew: int = 42
    // `name: value` inside a NAMED tuple literal
    const NamedTupleElement: int = 43
    // `n++` / `n--`
    const PostfixUnary: int = 44
    // `must <operand>` -- the prefix null-assert
    const MustExpression: int = 45
    // `value is Type [name]`
    const IsExpression: int = 46
    // `value as Type`
    const AsExpression: int = 47
    // `expr with { Field: value, ... }`
    const WithExpression: int = 52
    // `await <expr>`
    const AwaitExpression: int = 53
    // `ref <expr>` / `out <expr>` in an argument list
    const RefOutArgument: int = 54
    // `typeof(Type)`
    const TypeOfExpression: int = 55
    // `checked(expr)` / `unchecked(expr)` -- lowered to a saved-and-restored overflow flag
    const CheckedContextExpression: int = 57
    // `[e0, e1, ...]`
    const ArrayLiteralExpression: int = 58
    // `new { Field: value, ... }`
    const AnonymousObjectInitializer: int = 59
    // `name: value` in ANY argument list
    const NamedArgumentExpression: int = 60
    // `Type name` inside a match arm
    const TypeBindingPattern: int = 61
    // `nameof(expr)`
    const NameOfExpression: int = 62
    // `new(args...)` with no written type
    const TargetTypedNewExpression: int = 63
    // `...expr` in an argument list
    const SpreadArgumentExpression: int = 64
    // `[pat0, .. rest, patN]`
    const ListPattern: int = 65
    // `..` / `.. name` inside a list pattern
    const SlicePattern: int = 66
    // `{ Prop, Prop: pat }`
    const ObjectPattern: int = 67
    // `Prop` / `Prop: pat`
    const PropertyPattern: int = 68
    // `start..end` and its open forms
    const RangeExpression: int = 69
    // `Name<T1, T2>` before a `.` -- a CONSTRUCTED GENERIC TYPE in receiver position
    const GenericTypeReceiverExpression: int = 70
    // `base.Member`
    const BaseMemberExpression: int = 71
    // `yield <value>` / `yield break`
    const YieldExpression: int = 72
    // `default` -- the target-typed zero
    const DefaultExpression: int = 74
    // the RECEIVER half of a `?.` access
    const NullGuardExpression: int = 75
    // `async x => …`
    const AsyncLambda: int = 78
    // `on <target>.<Event> <handler>`
    const OnSubscriptionExpression: int = 79
    // a bare `this`
    const ThisExpression: int = 82
    // `throw <exception>` in VALUE position
    const ThrowExpression: int = 83
    // `when <expr>` on a `catch` -- statement-space kind 84, named here because its callers already spell it here
    const CatchFilterClause: int = 84
}

// THE ONE LIVE STATEMENT-NODE-KIND LEDGER. See `ColumnarExpressionNodeKind` for why these two
// tables exist separately and where their integer spaces overlap.
class ColumnarStatementNodeKind {

    // `return [value]`
    const ReturnStatement: int = 20
    // `break`
    const BreakStatement: int = 21
    // `continue`
    const ContinueStatement: int = 22
    // `<expr>` as a statement
    const ExpressionStatement: int = 23
    // `name := init`, the name in the value span
    const VariableDeclarationStatement: int = 24
    // `{ stmt* }`
    const BlockStatement: int = 25
    // `while cond <body>`
    const WhileStatement: int = 26
    // `if cond <then> [else <else>]`
    const IfStatement: int = 27
    // `for <init>; <cond>; <incr> <body>`
    const ForStatement: int = 28
    // `for <var> in <coll>` / `foreach <var> in <coll>`
    const ForeachStatement: int = 29
    // `n0, n1, ... := <tuple>`
    const TupleDeconstructionStatement: int = 30
    // `[let] name: Type = init`
    const TypedLocalDeclaration: int = 40
    // `func name(...) { body }` written inside a body
    const LocalFunctionDeclaration: int = 41
    // `throw <expr>`
    const ThrowStatement: int = 48
    // `try` / `catch`… / `finally?`
    const TryStatement: int = 49
    // one `catch`, the exception TYPE name in the value span
    const CatchClause: int = 50
    // `lock <expr> { }`
    const LockStatement: int = 51
    // `print <expr>`
    const PrintStatement: int = 56
    // `allow(...) <body>`
    const AllowStatement: int = 60
    // `assert <cond> [, <msg>]`
    const AssertStatement: int = 61
    // `assert throws <TypeName> { body }`
    const AssertThrowsStatement: int = 62
    // `await foreach <var> in <coll> { body }`
    const AwaitForeachStatement: int = 73
    // `for <var>: <Type> in <coll>`
    const TypedForeachStatement: int = 76
    // `using <resource> { body }`
    const UsingStatement: int = 77
    // `off <handle>` -- the unsubscribe
    const OffStatement: int = 80
    // `await using <resource> { body }`
    const AwaitUsingStatement: int = 81
}
