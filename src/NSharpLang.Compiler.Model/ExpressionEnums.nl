namespace NSharpLang.Compiler.Ast

enum BinaryOperator {
    Add,
    Subtract,
    Multiply,
    Divide,
    Modulo,
    Equal,
    NotEqual,
    Less,
    LessOrEqual,
    Greater,
    GreaterOrEqual,
    And,
    Or,
    BitwiseAnd,
    BitwiseOr,
    BitwiseXor,
    LeftShift,
    RightShift,
    NullCoalesce,
    Range
}

enum UnaryOperator {
    Negate,
    Not,
    BitwiseNot,
    PreIncrement,
    PreDecrement,
    PostIncrement,
    PostDecrement,
    IndexFromEnd
}

// `In` is appended, so `Ref` and `Out` keep their ordinals. Unlike the other two, `In` is OPTIONAL at
// a call site: the callee's signature already says the argument is passed by read-only reference, and
// writing the word only makes that visible at the call.
enum ArgumentModifier {
    None,
    Ref,
    Out,
    In
}

enum AssignmentOperator {
    Assign,
    AddAssign,
    SubtractAssign,
    MultiplyAssign,
    DivideAssign,
    NullCoalesceAssign
}

enum CastKind {
    Hard,
    Safe
}
