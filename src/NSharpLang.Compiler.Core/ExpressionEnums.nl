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

enum ArgumentModifier {
    None,
    Ref,
    Out
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
