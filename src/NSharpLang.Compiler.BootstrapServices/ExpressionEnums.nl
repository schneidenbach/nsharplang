namespace NSharpLang.Compiler.Ast

public enum BinaryOperator {
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
    Range,
}

public enum UnaryOperator {
    Negate,
    Not,
    BitwiseNot,
    PreIncrement,
    PreDecrement,
    PostIncrement,
    PostDecrement,
    IndexFromEnd
}

public enum ArgumentModifier {
    None,
    Ref,
    Out
}

public enum AssignmentOperator {
    Assign,
    AddAssign,
    SubtractAssign,
    MultiplyAssign,
    DivideAssign,
    NullCoalesceAssign
}

public enum CastKind {
    Hard,
    Safe
}
