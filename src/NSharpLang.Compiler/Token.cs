namespace NSharpLang.Compiler;

public enum TokenType
{
    // Literals
    Identifier,
    IntLiteral,
    FloatLiteral,
    CharLiteral,
    StringLiteral,
    TripleQuoteStringLiteral,
    InterpolatedRawStringLiteral,

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
    Import,
    Package,
    Let,
    Must,
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
    Nameof,
    Sizeof,
    Print,
    Where,
    When,
    AndKeyword,  // 'and' keyword for pattern matching
    OrKeyword,   // 'or' keyword for pattern matching
    NotKeyword,  // 'not' keyword for pattern matching
    Virtual,
    Override,
    Abstract,
    Sealed,
    Partial,
    Static,
    Public,
    Private,
    Internal,
    Protected,
    Async,
    Await,
    Immutable,
    With,
    Type,
    Test,
    Assert,
    Operator,
    Required,
    Init,
    Ref,
    Out,
    Lock,
    File,
    Params,
    Checked,
    Unchecked,
    Implicit,
    Explicit,
    Newtype,

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
    BitwiseXor,     // ^ (bitwise XOR or index from end, context-dependent)
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
    Unknown,

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
    string? FileName = null,
    bool IsTerminated = true)
{
    public override string ToString() =>
        $"{Type} '{Value}' at {FileName ?? "?"}:{Line}:{Column}";
}

/// <summary>
/// A comment extracted from source code, preserved for the formatter.
/// </summary>
public record CommentTrivia(
    int Line,
    int Column,
    string Text,
    bool IsMultiLine);
