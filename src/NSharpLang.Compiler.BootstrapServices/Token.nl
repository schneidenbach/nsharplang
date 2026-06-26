namespace NSharpLang.Compiler

import System

public enum TokenType {
    Identifier,
    IntLiteral,
    FloatLiteral,
    CharLiteral,
    StringLiteral,
    TripleQuoteStringLiteral,
    InterpolatedRawStringLiteral,
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
    AndKeyword,
    OrKeyword,
    NotKeyword,
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
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Assign,
    PlusAssign,
    MinusAssign,
    StarAssign,
    SlashAssign,
    Equal,
    NotEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    And,
    Or,
    Not,
    BitwiseAnd,
    BitwiseOr,
    BitwiseXor,
    BitwiseNot,
    LeftShift,
    RightShift,
    Increment,
    Decrement,
    Question,
    QuestionQuestion,
    QuestionQuestionAssign,
    QuestionDot,
    QuestionBracket,
    Arrow,
    ColonAssign,
    Colon,
    DoubleColon,
    Dot,
    DotDot,
    DotDotDot,
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    LeftBracket,
    RightBracket,
    Semicolon,
    Comma,
    Eof,
    Newline,
    Unknown,
    PreprocessorDirective,
    Comment,
    MultiLineComment,
    XmlDocComment,
    Lifetime,
    Alloc,
    Allow,
    Stackalloc,
    Unsafe,
    Scoped
}

public class Token {
    typeValue: TokenType
    valueText: string
    lineValue: int
    columnValue: int
    fileNameValue: string?
    isTerminatedValue: bool

    Type: TokenType => typeValue
    Value: string => valueText
    Line: int => lineValue
    Column: int => columnValue
    FileName: string? => fileNameValue
    IsTerminated: bool => isTerminatedValue

    constructor(
        Type: TokenType,
        Value: string,
        Line: int,
        Column: int,
        FileName: string? = null,
        IsTerminated: bool = true) {
        typeValue = Type
        valueText = Value
        lineValue = Line
        columnValue = Column
        fileNameValue = FileName
        isTerminatedValue = IsTerminated
    }

    override func ToString(): string {
        fileText := fileNameValue
        if fileText == null {
            fileText = "?"
        }

        typeText := Enum.GetName(typeof(TokenType), Convert.ToInt32(typeValue))
        if typeText == null {
            typeText = Convert.ToInt32(typeValue).ToString()
        }

        return typeText + " '" + valueText + "' at " + fileText + ":" + lineValue.ToString() + ":" + columnValue.ToString()
    }

    override func Equals(value: object): bool {
        other := value as Token
        if other == null {
            return false
        }

        return typeValue == other.Type
            && valueText == other.Value
            && lineValue == other.Line
            && columnValue == other.Column
            && fileNameValue == other.FileName
            && isTerminatedValue == other.IsTerminated
    }

    override func GetHashCode(): int {
        hash := 17
        hash = hash * 23 + Convert.ToInt32(typeValue)
        if valueText != null {
            hash = hash * 23 + valueText.GetHashCode()
        }
        hash = hash * 23 + lineValue
        hash = hash * 23 + columnValue
        if fileNameValue != null {
            hash = hash * 23 + fileNameValue.GetHashCode()
        }
        if isTerminatedValue {
            hash = hash * 23 + 1
        }
        return hash
    }
}

public class CommentTrivia {
    lineValue: int
    columnValue: int
    textValue: string
    isMultiLineValue: bool

    Line: int => lineValue
    Column: int => columnValue
    Text: string => textValue
    IsMultiLine: bool => isMultiLineValue

    constructor(Line: int, Column: int, Text: string, IsMultiLine: bool) {
        lineValue = Line
        columnValue = Column
        textValue = Text
        isMultiLineValue = IsMultiLine
    }

    override func Equals(value: object): bool {
        other := value as CommentTrivia
        if other == null {
            return false
        }

        return lineValue == other.Line
            && columnValue == other.Column
            && textValue == other.Text
            && isMultiLineValue == other.IsMultiLine
    }

    override func GetHashCode(): int {
        hash := 17
        hash = hash * 23 + lineValue
        hash = hash * 23 + columnValue
        if textValue != null {
            hash = hash * 23 + textValue.GetHashCode()
        }
        if isMultiLineValue {
            hash = hash * 23 + 1
        }
        return hash
    }
}
