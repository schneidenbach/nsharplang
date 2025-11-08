namespace NewCLILang.Compiler;

public enum TokenType
{
    // Literals
    Identifier,
    IntLiteral,
    FloatLiteral,
    StringLiteral,
    TripleQuoteStringLiteral,

    // Keywords
    Func,
    Class,
    Struct,
    Interface,
    Duck,
    Union,
    Record,
    Enum,
    Namespace,
    Using,
    Let,
    Const,
    Readonly,
    If,
    Else,
    For,
    Foreach,
    While,
    In,
    Return,
    Yield,
    Match,
    Switch,
    Case,
    Default,
    Break,
    Continue,
    Throw,
    Try,
    Catch,
    Finally,
    New,
    This,
    Base,
    True,
    False,
    Null,
    Is,
    As,
    Typeof,
    Sizeof,
    Where,
    When,
    Virtual,
    Abstract,
    Sealed,
    Partial,
    Static,
    Internal,
    Protected,
    Async,
    Await,
    Immutable,
    With,
    Type,

    // Operators
    Plus,           // +
    Minus,          // -
    Star,           // *
    Slash,          // /
    Percent,        // %
    Assign,         // =
    PlusAssign,     // +=
    MinusAssign,    // -=
    StarAssign,     // *=
    SlashAssign,    // /=
    Equal,          // ==
    NotEqual,       // !=
    Less,           // <
    LessEqual,      // <=
    Greater,        // >
    GreaterEqual,   // >=
    And,            // &&
    Or,             // ||
    Not,            // !
    BitwiseAnd,     // &
    BitwiseOr,      // |
    BitwiseXor,     // ^
    BitwiseNot,     // ~
    LeftShift,      // <<
    RightShift,     // >>
    Increment,      // ++
    Decrement,      // --
    Question,       // ?
    QuestionQuestion, // ??
    QuestionQuestionAssign, // ??=
    QuestionDot,    // ?.
    QuestionBracket, // ?[
    Arrow,          // =>
    ColonAssign,    // :=
    Colon,          // :
    DoubleColon,    // ::
    Dot,            // .
    DotDot,         // ..
    DotDotDot,      // ...

    // Delimiters
    LeftParen,      // (
    RightParen,     // )
    LeftBrace,      // {
    RightBrace,     // }
    LeftBracket,    // [
    RightBracket,   // ]
    Semicolon,      // ;
    Comma,          // ,

    // Special
    Eof,
    Newline,

    // Preprocessor
    PreprocessorDirective,

    // Comments (usually ignored)
    Comment,
    MultiLineComment,
    XmlDocComment,
}

public record Token(
    TokenType Type,
    string Value,
    int Line,
    int Column,
    string? FileName = null)
{
    public override string ToString() =>
        $"{Type} '{Value}' at {FileName ?? "?"}:{Line}:{Column}";
}
