namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `Lexer`, IN N#.
//
// These replace `tests/LexerTests.cs`, the last canonical C# assertion layer over `Lexer.nl` and
// the largest single cluster the 020 arc has migrated. The subject is the front door of the whole
// compiler: every `.nl` character reaches the parser only as a `Token` this file produced, so a
// silent change here is a silent change to the language itself.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. Every answer is a dependency-assembly
// `List<Token>` whose elements carry a dependency-assembly `TokenType`, the trivia answers are a
// `List<CommentTrivia>`, and three of the entry points are statics taking or returning a
// `TokenType`. A `tests/native` project is bounded to PRIMITIVE-argument subject calls, so none of
// that can cross; `Lexer.nl` is a file of THIS project, and the estate reaches it directly.
//
// WHAT THE PROBE MEASURED. Every risky shape in the deleted file was carried by one probe file
// before a line of contract was written -- the `List<Token>` indexer, every `Token` member, string
// data holding escaped quotes / backslashes / `$`-interpolations / triple quotes / char literals,
// `\r\n` pairs, `StartsWith`/`EndsWith`/`IndexOf` under `StringComparison.Ordinal`, the last
// element (which the deleted file spelled `tokens[^1]`), the `Comments` trivia property, and an
// indexed sweep over a `TokenType` table. **ZERO WALLS, in ONE round.** Every call here is
// nonetheless spelled at FULL ARITY, because omitting a defaulted parameter declines at
// `emit.local.initializer` -- so `new Lexer(source, "test.nl")` names the file even where the
// deleted file could have left it off.
//
// HOW THE SUCCESSOR IS STRICTLY STRONGER. The deleted file SAMPLED the keyword table: sixteen
// `[Fact]`s, one per keyword someone had once been burned by. This file CROSSES it. All 85
// keywords are lexed, and each is proved to answer its own `TokenType`, its own text and nothing
// else; all 85 are crossed through `KeywordTypeForText` and back through `KeywordTextForType`; all
// 63 remaining `TokenType` members are proved to be reserved by NEITHER; and the two tables are
// proved to partition the whole 148-member enum, so a keyword added to the lexer without a row
// here fails the partition rather than passing unnoticed.
//
// THE FIVE THINGS IT IS EASY TO GET WRONG:
//
// (1) A LITERAL'S `Value` IS ITS SOURCE TEXT, NOT ITS MEANING. A string literal keeps its quotes
// and keeps its escapes UNDECODED (`"escape\ntest"` is nine characters of text plus quotes, not a
// newline), because the parser -- not the lexer -- decides what an escape means. The two
// exceptions are deliberate and asserted: a triple-quote string DROPS its delimiters, and a number
// literal DROPS its underscores.
//
// (2) AN UNTERMINATED LITERAL IS STILL A LITERAL. An unterminated string, triple-quote string,
// interpolated raw string or char literal answers its own kind with `IsTerminated` FALSE -- never
// `Unknown`, and never an exception -- so the parser can still report a useful error. An
// unterminated multi-line comment is the one that vanishes entirely, because comments are trivia.
//
// (3) AN APOSTROPHE IS A CHAR LITERAL OR A LIFETIME, AND THE LEXER DECIDES BY CONTEXT. In a
// systems header (`<'a>`, `scoped 'a`, `returns 'a`) it is a `Lifetime`; a bare `'a` with no
// closing quote is an UNTERMINATED `CharLiteral`, not a lifetime.
//
// (4) COMMENTS LEAVE THE STREAM BUT NOT THE FILE. `//`, `/* */` and `///` are filtered out of the
// token list and preserved on `Comments` as `CommentTrivia`, with position and multi-line flag
// intact. A multi-line comment's trivia text keeps its `/*` and `*/`; the formatter depends on it.
//
// (5) A DIRECTIVE IS A TOKEN AND A NEWLINE IS A TOKEN. `#if`/`#endif`/`#region` reach the parser
// as `PreprocessorDirective` tokens carrying their whole text (the PREPROCESSOR resolves them
// later, not the lexer), and every line break is a `Newline` token whose value is NORMALISED to a
// single line feed even when the source spelled `\r\n`.

// ---- Helpers -----------------------------------------------------------------------------------
func LexerContractTokens(source: string): List<Token> {
    lexer := new Lexer(source, "test.nl")
    return lexer.Tokenize()
}

func LexerContractCountOfKind(tokens: List<Token>, kind: TokenType): int {
    total := 0
    for candidate in tokens {
        if candidate.Type == kind {
            total = total + 1
        }
    }

    return total
}

func LexerContractCountExcludingTwo(tokens: List<Token>, first: TokenType, second: TokenType): int {
    total := 0
    for candidate in tokens {
        if candidate.Type != first && candidate.Type != second {
            total = total + 1
        }
    }

    return total
}

func LexerContractHasKind(tokens: List<Token>, kind: TokenType): bool {
    return LexerContractCountOfKind(tokens, kind) > 0
}

func LexerContractNthOfKind(tokens: List<Token>, kind: TokenType, ordinal: int): Token? {
    seen := 0
    for candidate in tokens {
        if candidate.Type == kind {
            if seen == ordinal {
                return candidate
            }

            seen = seen + 1
        }
    }

    return null
}

// The sentinels below can only be reached when the matching count assertion has ALREADY failed --
// every declaration that reads an ordinal asserts the count of that kind first.
func LexerContractNthValue(tokens: List<Token>, kind: TokenType, ordinal: int): string {
    found := LexerContractNthOfKind(tokens, kind, ordinal)
    if found != null {
        return found.Value
    }

    return "<no such token>"
}

func LexerContractNthLine(tokens: List<Token>, kind: TokenType, ordinal: int): int {
    found := LexerContractNthOfKind(tokens, kind, ordinal)
    if found != null {
        return found.Line
    }

    return -1
}

func LexerContractNthColumn(tokens: List<Token>, kind: TokenType, ordinal: int): int {
    found := LexerContractNthOfKind(tokens, kind, ordinal)
    if found != null {
        return found.Column
    }

    return -1
}

func LexerContractNthTerminated(tokens: List<Token>, kind: TokenType, ordinal: int): bool {
    found := LexerContractNthOfKind(tokens, kind, ordinal)
    if found != null {
        return found.IsTerminated
    }

    return false
}

func LexerContractByValue(tokens: List<Token>, value: string): Token? {
    for candidate in tokens {
        if candidate.Value == value {
            return candidate
        }
    }

    return null
}

func LexerContractLineOfValue(tokens: List<Token>, value: string): int {
    found := LexerContractByValue(tokens, value)
    if found != null {
        return found.Line
    }

    return -1
}

func LexerContractColumnOfValue(tokens: List<Token>, value: string): int {
    found := LexerContractByValue(tokens, value)
    if found != null {
        return found.Column
    }

    return -1
}

// The trivia list is a SIDE EFFECT of the walk, so the walk has to run before it is read. The
// guard below is unreachable -- `Tokenize` always answers at least the `Eof` token -- and exists
// only so the token stream this family does not otherwise need is still consumed.
func LexerContractCommentTrivia(source: string): List<CommentTrivia> {
    lexer := new Lexer(source, "test.nl")
    tokens := lexer.Tokenize()
    if tokens.Count < 1 {
        return new List<CommentTrivia>()
    }

    return lexer.Comments
}

func LexerContractCommentCount(source: string): int {
    return LexerContractCommentTrivia(source).Count
}

func LexerContractCommentText(source: string, ordinal: int): string {
    trivia := LexerContractCommentTrivia(source)
    if ordinal < trivia.Count {
        return trivia[ordinal].Text
    }

    return "<no such comment>"
}

func LexerContractCommentLine(source: string, ordinal: int): int {
    trivia := LexerContractCommentTrivia(source)
    if ordinal < trivia.Count {
        return trivia[ordinal].Line
    }

    return -1
}

func LexerContractCommentColumn(source: string, ordinal: int): int {
    trivia := LexerContractCommentTrivia(source)
    if ordinal < trivia.Count {
        return trivia[ordinal].Column
    }

    return -1
}

func LexerContractCommentMultiLine(source: string, ordinal: int): bool {
    trivia := LexerContractCommentTrivia(source)
    if ordinal < trivia.Count {
        return trivia[ordinal].IsMultiLine
    }

    return false
}

func LexerContractTypeTableContains(candidates: TokenType[], kind: TokenType): bool {
    index := 0
    while index < candidates.Length {
        if candidates[index] == kind {
            return true
        }

        index = index + 1
    }

    return false
}

func LexerContractTablesAreDisjoint(left: TokenType[], right: TokenType[]): bool {
    index := 0
    while index < left.Length {
        if LexerContractTypeTableContains(right, left[index]) {
            return false
        }

        index = index + 1
    }

    return true
}

func LexerContractTablesCoverEveryTokenType(left: TokenType[], right: TokenType[]): bool {
    every := LexerContractAllTokenTypes()
    index := 0
    while index < every.Length {
        if !LexerContractTypeTableContains(left, every[index]) && !LexerContractTypeTableContains(right, every[index]) {
            return false
        }

        index = index + 1
    }

    return true
}

// ---- Tables ------------------------------------------------------------------------------------

// The 85 keyword texts of `Lexer.KeywordTypeForText`, in its own arm order.

func LexerContractKeywordTexts(): string[] {
    return [
        "func",
        "class",
        "struct",
        "interface",
        "duck",
        "union",
        "record",
        "enum",
        "namespace",
        "using",
        "import",
        "package",
        "let",
        "must",
        "const",
        "readonly",
        "if",
        "else",
        "for",
        "foreach",
        "while",
        "in",
        "return",
        "yield",
        "match",
        "switch",
        "case",
        "default",
        "break",
        "continue",
        "throw",
        "try",
        "catch",
        "finally",
        "new",
        "this",
        "base",
        "true",
        "false",
        "null",
        "is",
        "as",
        "typeof",
        "nameof",
        "sizeof",
        "print",
        "where",
        "when",
        "and",
        "or",
        "not",
        "virtual",
        "override",
        "abstract",
        "sealed",
        "partial",
        "static",
        "public",
        "private",
        "internal",
        "protected",
        "async",
        "await",
        "immutable",
        "with",
        "type",
        "assert",
        "operator",
        "required",
        "init",
        "ref",
        "out",
        "lock",
        "file",
        "params",
        "checked",
        "unchecked",
        "implicit",
        "explicit",
        "newtype",
        "alloc",
        "allow",
        "stackalloc",
        "unsafe",
        "scoped"
    ]
}

// The 85 keyword token types of `Lexer.KeywordTextForType`, in the same order.
func LexerContractKeywordTypes(): TokenType[] {
    return [
        TokenType.Func,
        TokenType.Class,
        TokenType.Struct,
        TokenType.Interface,
        TokenType.Duck,
        TokenType.Union,
        TokenType.Record,
        TokenType.Enum,
        TokenType.Namespace,
        TokenType.Using,
        TokenType.Import,
        TokenType.Package,
        TokenType.Let,
        TokenType.Must,
        TokenType.Const,
        TokenType.Readonly,
        TokenType.If,
        TokenType.Else,
        TokenType.For,
        TokenType.Foreach,
        TokenType.While,
        TokenType.In,
        TokenType.Return,
        TokenType.Yield,
        TokenType.Match,
        TokenType.Switch,
        TokenType.Case,
        TokenType.Default,
        TokenType.Break,
        TokenType.Continue,
        TokenType.Throw,
        TokenType.Try,
        TokenType.Catch,
        TokenType.Finally,
        TokenType.New,
        TokenType.This,
        TokenType.Base,
        TokenType.True,
        TokenType.False,
        TokenType.Null,
        TokenType.Is,
        TokenType.As,
        TokenType.Typeof,
        TokenType.Nameof,
        TokenType.Sizeof,
        TokenType.Print,
        TokenType.Where,
        TokenType.When,
        TokenType.AndKeyword,
        TokenType.OrKeyword,
        TokenType.NotKeyword,
        TokenType.Virtual,
        TokenType.Override,
        TokenType.Abstract,
        TokenType.Sealed,
        TokenType.Partial,
        TokenType.Static,
        TokenType.Public,
        TokenType.Private,
        TokenType.Internal,
        TokenType.Protected,
        TokenType.Async,
        TokenType.Await,
        TokenType.Immutable,
        TokenType.With,
        TokenType.Type,
        TokenType.Assert,
        TokenType.Operator,
        TokenType.Required,
        TokenType.Init,
        TokenType.Ref,
        TokenType.Out,
        TokenType.Lock,
        TokenType.File,
        TokenType.Params,
        TokenType.Checked,
        TokenType.Unchecked,
        TokenType.Implicit,
        TokenType.Explicit,
        TokenType.Newtype,
        TokenType.Alloc,
        TokenType.Allow,
        TokenType.Stackalloc,
        TokenType.Unsafe,
        TokenType.Scoped
    ]
}

// The 63 `TokenType` members that are NOT keywords: the seven literal kinds, every operator and
// delimiter, the stream markers (`Eof`, `Newline`, `Unknown`, `PreprocessorDirective`), the four
// trivia kinds, `Lifetime` -- and `Test`, which is the one WORD-SHAPED member here, because
// `TokenType.Test` exists but no keyword text reaches it and `test` lexes as an identifier.
func LexerContractNonKeywordTypes(): TokenType[] {
    return [
        TokenType.Identifier,
        TokenType.IntLiteral,
        TokenType.FloatLiteral,
        TokenType.CharLiteral,
        TokenType.StringLiteral,
        TokenType.TripleQuoteStringLiteral,
        TokenType.InterpolatedRawStringLiteral,
        TokenType.Test,
        TokenType.Plus,
        TokenType.Minus,
        TokenType.Star,
        TokenType.Slash,
        TokenType.Percent,
        TokenType.Assign,
        TokenType.PlusAssign,
        TokenType.MinusAssign,
        TokenType.StarAssign,
        TokenType.SlashAssign,
        TokenType.Equal,
        TokenType.NotEqual,
        TokenType.Less,
        TokenType.LessEqual,
        TokenType.Greater,
        TokenType.GreaterEqual,
        TokenType.And,
        TokenType.Or,
        TokenType.Not,
        TokenType.BitwiseAnd,
        TokenType.BitwiseOr,
        TokenType.BitwiseXor,
        TokenType.BitwiseNot,
        TokenType.LeftShift,
        TokenType.RightShift,
        TokenType.Increment,
        TokenType.Decrement,
        TokenType.Question,
        TokenType.QuestionQuestion,
        TokenType.QuestionQuestionAssign,
        TokenType.QuestionDot,
        TokenType.QuestionBracket,
        TokenType.Arrow,
        TokenType.ColonAssign,
        TokenType.Colon,
        TokenType.DoubleColon,
        TokenType.Dot,
        TokenType.DotDot,
        TokenType.DotDotDot,
        TokenType.LeftParen,
        TokenType.RightParen,
        TokenType.LeftBrace,
        TokenType.RightBrace,
        TokenType.LeftBracket,
        TokenType.RightBracket,
        TokenType.Semicolon,
        TokenType.Comma,
        TokenType.Eof,
        TokenType.Newline,
        TokenType.Unknown,
        TokenType.PreprocessorDirective,
        TokenType.Comment,
        TokenType.MultiLineComment,
        TokenType.XmlDocComment,
        TokenType.Lifetime
    ]
}

// Every member of `TokenType`, in declaration order -- the estate's spelling of
// `Enum.GetValues<TokenType>()`, read out of `Token.nl` rather than out of either
// test side.
func LexerContractAllTokenTypes(): TokenType[] {
    return [
        TokenType.Identifier,
        TokenType.IntLiteral,
        TokenType.FloatLiteral,
        TokenType.CharLiteral,
        TokenType.StringLiteral,
        TokenType.TripleQuoteStringLiteral,
        TokenType.InterpolatedRawStringLiteral,
        TokenType.Func,
        TokenType.Class,
        TokenType.Struct,
        TokenType.Interface,
        TokenType.Duck,
        TokenType.Union,
        TokenType.Record,
        TokenType.Enum,
        TokenType.Namespace,
        TokenType.Using,
        TokenType.Import,
        TokenType.Package,
        TokenType.Let,
        TokenType.Must,
        TokenType.Const,
        TokenType.Readonly,
        TokenType.If,
        TokenType.Else,
        TokenType.For,
        TokenType.Foreach,
        TokenType.While,
        TokenType.In,
        TokenType.Return,
        TokenType.Yield,
        TokenType.Match,
        TokenType.Switch,
        TokenType.Case,
        TokenType.Default,
        TokenType.Break,
        TokenType.Continue,
        TokenType.Throw,
        TokenType.Try,
        TokenType.Catch,
        TokenType.Finally,
        TokenType.New,
        TokenType.This,
        TokenType.Base,
        TokenType.True,
        TokenType.False,
        TokenType.Null,
        TokenType.Is,
        TokenType.As,
        TokenType.Typeof,
        TokenType.Nameof,
        TokenType.Sizeof,
        TokenType.Print,
        TokenType.Where,
        TokenType.When,
        TokenType.AndKeyword,
        TokenType.OrKeyword,
        TokenType.NotKeyword,
        TokenType.Virtual,
        TokenType.Override,
        TokenType.Abstract,
        TokenType.Sealed,
        TokenType.Partial,
        TokenType.Static,
        TokenType.Public,
        TokenType.Private,
        TokenType.Internal,
        TokenType.Protected,
        TokenType.Async,
        TokenType.Await,
        TokenType.Immutable,
        TokenType.With,
        TokenType.Type,
        TokenType.Test,
        TokenType.Assert,
        TokenType.Operator,
        TokenType.Required,
        TokenType.Init,
        TokenType.Ref,
        TokenType.Out,
        TokenType.Lock,
        TokenType.File,
        TokenType.Params,
        TokenType.Checked,
        TokenType.Unchecked,
        TokenType.Implicit,
        TokenType.Explicit,
        TokenType.Newtype,
        TokenType.Plus,
        TokenType.Minus,
        TokenType.Star,
        TokenType.Slash,
        TokenType.Percent,
        TokenType.Assign,
        TokenType.PlusAssign,
        TokenType.MinusAssign,
        TokenType.StarAssign,
        TokenType.SlashAssign,
        TokenType.Equal,
        TokenType.NotEqual,
        TokenType.Less,
        TokenType.LessEqual,
        TokenType.Greater,
        TokenType.GreaterEqual,
        TokenType.And,
        TokenType.Or,
        TokenType.Not,
        TokenType.BitwiseAnd,
        TokenType.BitwiseOr,
        TokenType.BitwiseXor,
        TokenType.BitwiseNot,
        TokenType.LeftShift,
        TokenType.RightShift,
        TokenType.Increment,
        TokenType.Decrement,
        TokenType.Question,
        TokenType.QuestionQuestion,
        TokenType.QuestionQuestionAssign,
        TokenType.QuestionDot,
        TokenType.QuestionBracket,
        TokenType.Arrow,
        TokenType.ColonAssign,
        TokenType.Colon,
        TokenType.DoubleColon,
        TokenType.Dot,
        TokenType.DotDot,
        TokenType.DotDotDot,
        TokenType.LeftParen,
        TokenType.RightParen,
        TokenType.LeftBrace,
        TokenType.RightBrace,
        TokenType.LeftBracket,
        TokenType.RightBracket,
        TokenType.Semicolon,
        TokenType.Comma,
        TokenType.Eof,
        TokenType.Newline,
        TokenType.Unknown,
        TokenType.PreprocessorDirective,
        TokenType.Comment,
        TokenType.MultiLineComment,
        TokenType.XmlDocComment,
        TokenType.Lifetime,
        TokenType.Alloc,
        TokenType.Allow,
        TokenType.Stackalloc,
        TokenType.Unsafe,
        TokenType.Scoped
    ]
}

// Ten identifiers that LOOK like keywords and are not: the deleted file's `var`,
// plus prefixes, suffixes, capitalisations and an underscore lead.
func LexerContractKeywordLookalikes(): string[] {
    return [
        "var",
        "test",
        "iff",
        "funcy",
        "Func",
        "IF",
        "_func",
        "func2",
        "returns",
        "duckling"
    ]
}

// ---- The shape of the stream -------------------------------------------------------------------

// Successor to TestEmptyInput.
test "lexer answers one end of file token for empty input" {
    tokens := LexerContractTokens("")

    assert tokens.Count == 1
    assert tokens[0].Type == TokenType.Eof

    // NOT IN THE DELETED FILE: the end-of-file token is a REAL token with a real position, which
    // is what lets a parser report "unexpected end of file" at a place in the file.
    assert tokens[0].Value == ""
    assert tokens[0].Line == 1
    assert tokens[0].Column == 1
    assert tokens[0].IsTerminated
}

// Successor to TestKeywords.
test "lexer reads a line of ten keywords" {
    tokens := LexerContractTokens("func class struct interface union if else for while return")

    assert tokens.Count == 11
    assert tokens[0].Type == TokenType.Func
    assert tokens[1].Type == TokenType.Class
    assert tokens[2].Type == TokenType.Struct
    assert tokens[3].Type == TokenType.Interface
    assert tokens[4].Type == TokenType.Union
    assert tokens[5].Type == TokenType.If
    assert tokens[6].Type == TokenType.Else
    assert tokens[7].Type == TokenType.For
    assert tokens[8].Type == TokenType.While
    assert tokens[9].Type == TokenType.Return

    // NOT IN THE DELETED FILE: each keyword carries its own text, and the stream still ends.
    assert tokens[0].Value == "func"
    assert tokens[4].Value == "union"
    assert tokens[9].Value == "return"
    assert tokens[10].Type == TokenType.Eof
}

// Successor to TestIdentifiers.
test "lexer reads every identifier spelling" {
    tokens := LexerContractTokens("myVar _private MyPublic some_snake_case")

    assert tokens.Count == 5
    assert tokens[0].Type == TokenType.Identifier
    assert tokens[1].Type == TokenType.Identifier
    assert tokens[2].Type == TokenType.Identifier
    assert tokens[3].Type == TokenType.Identifier
    assert tokens[0].Value == "myVar"
    assert tokens[1].Value == "_private"
    assert tokens[2].Value == "MyPublic"
    assert tokens[3].Value == "some_snake_case"

    // NOT IN THE DELETED FILE: each identifier starts where the source says it does, and the
    // stream ends after the fourth.
    assert tokens[0].Column == 1
    assert tokens[1].Column == 7
    assert tokens[2].Column == 16
    assert tokens[3].Column == 25
    assert tokens[4].Type == TokenType.Eof
}

// ---- Literals ----------------------------------------------------------------------------------

// Successor to TestNumbers.
test "lexer reads the four number spellings and strips underscores" {
    tokens := LexerContractTokens("42 3.14 100_000 1.5_5")

    assert tokens.Count == 5
    assert tokens[0].Type == TokenType.IntLiteral
    assert tokens[0].Value == "42"
    assert tokens[1].Type == TokenType.FloatLiteral
    assert tokens[1].Value == "3.14"
    assert tokens[2].Type == TokenType.IntLiteral
    assert tokens[2].Value == "100000"
    assert tokens[3].Type == TokenType.FloatLiteral
    assert tokens[3].Value == "1.55"

    // NOT IN THE DELETED FILE: stripping the underscores does NOT move the following token, so a
    // diagnostic after a digit-separated literal still points at the right column.
    assert tokens[3].Column == 17
    assert tokens[4].Type == TokenType.Eof
}

// Successor to TestNumberDotIdentifier_ParsesAsMemberAccess.
test "lexer splits a member access off an integer literal" {
    tokens := LexerContractTokens("5.ToString")

    assert tokens.Count == 4
    assert tokens[0].Type == TokenType.IntLiteral
    assert tokens[0].Value == "5"
    assert tokens[1].Type == TokenType.Dot
    assert tokens[2].Type == TokenType.Identifier
    assert tokens[2].Value == "ToString"

    // NOT IN THE DELETED FILE: the dot is one character wide and sits between the two.
    assert tokens[1].Value == "."
    assert tokens[1].Column == 2
    assert tokens[3].Type == TokenType.Eof
}

// Successor to TestFloatDotIdentifier_ParsesAsMemberAccess.
test "lexer splits a member access off a float literal" {
    tokens := LexerContractTokens("3.14.Negate")

    assert tokens.Count == 4
    assert tokens[0].Type == TokenType.FloatLiteral
    assert tokens[0].Value == "3.14"
    assert tokens[1].Type == TokenType.Dot
    assert tokens[2].Type == TokenType.Identifier
    assert tokens[2].Value == "Negate"

    // NOT IN THE DELETED FILE: the FIRST dot belongs to the literal and the second does not.
    assert tokens[1].Column == 5
    assert tokens[3].Type == TokenType.Eof
}

// Successor to TestStrings.
test "lexer keeps a string literal's quotes and escapes verbatim" {
    tokens := LexerContractTokens("\"hello\"\n\"world with spaces\"\n\"escape\\ntest\\t\\r\"")

    assert tokens.Count == 6
    assert LexerContractCountOfKind(tokens, TokenType.StringLiteral) == 3
    assert LexerContractNthValue(tokens, TokenType.StringLiteral, 0) == "\"hello\""
    assert LexerContractNthValue(tokens, TokenType.StringLiteral, 1) == "\"world with spaces\""
    assert LexerContractNthValue(tokens, TokenType.StringLiteral, 2) == "\"escape\\ntest\\t\\r\""

    // NOT IN THE DELETED FILE: the escapes are UNDECODED text, so the third literal is longer than
    // the characters it will eventually mean; each literal is terminated; and the two line breaks
    // between them are tokens of their own.
    assert LexerContractNthTerminated(tokens, TokenType.StringLiteral, 0)
    assert LexerContractNthTerminated(tokens, TokenType.StringLiteral, 2)
    assert LexerContractNthLine(tokens, TokenType.StringLiteral, 2) == 3
    assert LexerContractCountOfKind(tokens, TokenType.Newline) == 2
    assert LexerContractCountOfKind(tokens, TokenType.Eof) == 1
}

// Successor to TestInterpolatedString_WithNestedStringLiteralInInterpolation.
test "lexer keeps a nested literal inside an interpolation" {
    tokens := LexerContractTokens("$\"  Tags: {String.Join(\", \", tags)}\"")

    assert LexerContractCountOfKind(tokens, TokenType.StringLiteral) == 1
    assert LexerContractNthValue(tokens, TokenType.StringLiteral, 0) == "$\"  Tags: {String.Join(\", \", tags)}\""

    // NOT IN THE DELETED FILE: the quotes INSIDE the interpolation do not end the literal, so the
    // whole thing is ONE token and the stream holds nothing else.
    assert tokens.Count == 2
    assert LexerContractNthTerminated(tokens, TokenType.StringLiteral, 0)
    assert tokens[1].Type == TokenType.Eof
}

// Successor to TestTripleQuoteString.
test "lexer strips a triple quote string's delimiters" {
    tokens := LexerContractTokens("\"\"\"This is\na multi-line\nstring\"\"\"")

    assert LexerContractCountOfKind(tokens, TokenType.TripleQuoteStringLiteral) == 1
    assert LexerContractNthValue(tokens, TokenType.TripleQuoteStringLiteral, 0) == "This is\na multi-line\nstring"
    assert LexerContractNthTerminated(tokens, TokenType.TripleQuoteStringLiteral, 0)

    // NOT IN THE DELETED FILE: the line breaks INSIDE a raw string are content, not `Newline`
    // tokens -- this is the one place a line break does not reach the parser.
    assert tokens.Count == 2
    assert LexerContractCountOfKind(tokens, TokenType.Newline) == 0
    assert tokens[1].Line == 3
}

// ---- Operators and delimiters ------------------------------------------------------------------

// Successor to TestOperators.
test "lexer reads every operator" {
    tokens := LexerContractTokens("+ - * / % = == != < <= > >= && || ! ?: ?? ??= ?. => := :: . .. ...")

    assert tokens[0].Type == TokenType.Plus
    assert tokens[1].Type == TokenType.Minus
    assert tokens[2].Type == TokenType.Star
    assert tokens[3].Type == TokenType.Slash
    assert tokens[4].Type == TokenType.Percent
    assert tokens[5].Type == TokenType.Assign
    assert tokens[6].Type == TokenType.Equal
    assert tokens[7].Type == TokenType.NotEqual
    assert tokens[8].Type == TokenType.Less
    assert tokens[9].Type == TokenType.LessEqual
    assert tokens[10].Type == TokenType.Greater
    assert tokens[11].Type == TokenType.GreaterEqual
    assert tokens[12].Type == TokenType.And
    assert tokens[13].Type == TokenType.Or
    assert tokens[14].Type == TokenType.Not
    assert tokens[15].Type == TokenType.Question
    assert tokens[16].Type == TokenType.Colon
    assert tokens[17].Type == TokenType.QuestionQuestion
    assert tokens[18].Type == TokenType.QuestionQuestionAssign
    assert tokens[19].Type == TokenType.QuestionDot
    assert tokens[20].Type == TokenType.Arrow
    assert tokens[21].Type == TokenType.ColonAssign
    assert tokens[22].Type == TokenType.DoubleColon
    assert tokens[23].Type == TokenType.Dot
    assert tokens[24].Type == TokenType.DotDot
    assert tokens[25].Type == TokenType.DotDotDot

    // NOT IN THE DELETED FILE: every operator also carries its own SPELLING, which is what proves
    // the longest-match order rather than merely the kind -- `??=` before `??` before `?`, `...`
    // before `..` before `.`, `<=` before `<`, `:=` before `:`.
    assert tokens[6].Value == "=="
    assert tokens[15].Value == "?"
    assert tokens[16].Value == ":"
    assert tokens[17].Value == "??"
    assert tokens[18].Value == "??="
    assert tokens[19].Value == "?."
    assert tokens[20].Value == "=>"
    assert tokens[21].Value == ":="
    assert tokens[22].Value == "::"
    assert tokens[23].Value == "."
    assert tokens[24].Value == ".."
    assert tokens[25].Value == "..."
    assert tokens.Count == 27
    assert tokens[26].Type == TokenType.Eof
}

// Successor to TestCompoundAssignments.
test "lexer reads the four compound assignments" {
    tokens := LexerContractTokens("+= -= *= /=")

    assert tokens.Count == 5
    assert tokens[0].Type == TokenType.PlusAssign
    assert tokens[1].Type == TokenType.MinusAssign
    assert tokens[2].Type == TokenType.StarAssign
    assert tokens[3].Type == TokenType.SlashAssign

    // NOT IN THE DELETED FILE: each is TWO characters, not an operator followed by `=`.
    assert tokens[0].Value == "+="
    assert tokens[1].Value == "-="
    assert tokens[2].Value == "*="
    assert tokens[3].Value == "/="
    assert tokens[4].Type == TokenType.Eof
}

// Successor to TestIncrementDecrement.
test "lexer reads increment and decrement" {
    tokens := LexerContractTokens("++ --")

    assert tokens.Count == 3
    assert tokens[0].Type == TokenType.Increment
    assert tokens[1].Type == TokenType.Decrement

    // NOT IN THE DELETED FILE: `++` is one token, not two `+`.
    assert tokens[0].Value == "++"
    assert tokens[1].Value == "--"
    assert tokens[2].Type == TokenType.Eof
}

// Successor to TestDelimiters.
test "lexer reads every delimiter" {
    tokens := LexerContractTokens("( ) { } [ ] ; ,")

    assert tokens[0].Type == TokenType.LeftParen
    assert tokens[1].Type == TokenType.RightParen
    assert tokens[2].Type == TokenType.LeftBrace
    assert tokens[3].Type == TokenType.RightBrace
    assert tokens[4].Type == TokenType.LeftBracket
    assert tokens[5].Type == TokenType.RightBracket
    assert tokens[6].Type == TokenType.Semicolon
    assert tokens[7].Type == TokenType.Comma

    // NOT IN THE DELETED FILE: the braces here are the SOURCE's braces -- the indentation pass that
    // runs at the end of `Tokenize` adds none of its own to a single line.
    assert tokens.Count == 9
    assert tokens[2].Value == "{"
    assert tokens[3].Value == "}"
    assert tokens[8].Type == TokenType.Eof
}

// Successor to TestBitwiseOperators.
test "lexer reads every bitwise operator" {
    tokens := LexerContractTokens("& | ^ ~ << >>")

    assert tokens[0].Type == TokenType.BitwiseAnd
    assert tokens[1].Type == TokenType.BitwiseOr
    assert tokens[2].Type == TokenType.BitwiseXor
    assert tokens[3].Type == TokenType.BitwiseNot
    assert tokens[4].Type == TokenType.LeftShift
    assert tokens[5].Type == TokenType.RightShift

    // NOT IN THE DELETED FILE: the single-character forms are NOT the logical ones (`&` is
    // `BitwiseAnd`, `&&` is `And`), and the shifts arrive as ONE token each -- which is the token
    // the parser has to split again inside a generic argument list.
    assert tokens[0].Value == "&"
    assert tokens[4].Value == "<<"
    assert tokens[5].Value == ">>"
    assert tokens.Count == 7
    assert tokens[6].Type == TokenType.Eof
}

// ---- Trivia ------------------------------------------------------------------------------------

// Successor to TestComments.
test "lexer filters comments out of the token stream" {
    tokens := LexerContractTokens("// single line comment\nx := 42\n/* multi\n   line\n   comment */\ny := 10")

    assert LexerContractCountExcludingTwo(tokens, TokenType.Newline, TokenType.Eof) == 6

    // NOT IN THE DELETED FILE: no comment kind reaches the stream at all, and the line breaks that
    // ENDED the comments still do -- which is how a statement after a comment stays on its own line.
    assert LexerContractCountOfKind(tokens, TokenType.Comment) == 0
    assert LexerContractCountOfKind(tokens, TokenType.MultiLineComment) == 0
    assert LexerContractCountOfKind(tokens, TokenType.XmlDocComment) == 0
    assert LexerContractCountOfKind(tokens, TokenType.Newline) == 3
    assert LexerContractLineOfValue(tokens, "y") == 6
}

// NOT IN THE DELETED FILE, WHICH NEVER READ `Comments` AT ALL. A filtered comment is not a lost
// comment: it is trivia, positioned, and the formatter reproduces the file from it.
test "lexer keeps every comment as trivia" {
    source := "// single line comment\nx := 42\n/* multi\n   line\n   comment */\ny := 10"

    assert LexerContractCommentCount(source) == 2
    assert LexerContractCommentText(source, 0) == "// single line comment"
    assert LexerContractCommentLine(source, 0) == 1
    assert LexerContractCommentColumn(source, 0) == 1
    assert !LexerContractCommentMultiLine(source, 0)
    assert LexerContractCommentText(source, 1) == "/* multi\n   line\n   comment */"
    assert LexerContractCommentLine(source, 1) == 3
    assert LexerContractCommentColumn(source, 1) == 1
    assert LexerContractCommentMultiLine(source, 1)
}

// Successor to TestXmlDocComment.
test "lexer filters an xml doc comment out of the token stream" {
    source := "/// <summary>This is a doc comment</summary>\nfunc Test() {}"
    tokens := LexerContractTokens(source)

    assert LexerContractHasKind(tokens, TokenType.Func)

    // NOT IN THE DELETED FILE: the doc comment is kept as trivia like any other comment -- and it
    // is NOT multi-line, even though `///` is a third comment syntax.
    assert LexerContractCountOfKind(tokens, TokenType.XmlDocComment) == 0
    assert LexerContractCommentCount(source) == 1
    assert LexerContractCommentText(source, 0) == "/// <summary>This is a doc comment</summary>"
    assert !LexerContractCommentMultiLine(source, 0)
    assert LexerContractLineOfValue(tokens, "func") == 2
}

// Successor to TestUnterminatedMultiLineComment.
test "lexer survives an unterminated multi line comment" {
    source := "/* unterminated"
    tokens := LexerContractTokens(source)

    assert tokens[tokens.Count - 1].Type == TokenType.Eof
    assert tokens.Count == 1

    // NOT IN THE DELETED FILE: the unterminated comment is still RECORDED as trivia, and its text
    // is closed for it -- so a formatter round-trip does not lose the characters the file had.
    assert LexerContractCommentCount(source) == 1
    assert LexerContractCommentText(source, 0) == "/* unterminated*/"
    assert LexerContractCommentMultiLine(source, 0)
}

// ---- Directives and line breaks ----------------------------------------------------------------

// Successor to TestPreprocessorDirective.
test "lexer keeps preprocessor directives in the token stream" {
    tokens := LexerContractTokens("#if DEBUG\nx := 1\n#endif")

    assert LexerContractCountOfKind(tokens, TokenType.PreprocessorDirective) == 2
    assert LexerContractNthValue(tokens, TokenType.PreprocessorDirective, 0) == "#if DEBUG"
    assert LexerContractNthValue(tokens, TokenType.PreprocessorDirective, 1) == "#endif"

    // NOT IN THE DELETED FILE: a directive carries its WHOLE line as one token and starts at column
    // one, and the guarded body is lexed normally -- the lexer resolves nothing.
    assert LexerContractNthLine(tokens, TokenType.PreprocessorDirective, 0) == 1
    assert LexerContractNthColumn(tokens, TokenType.PreprocessorDirective, 0) == 1
    assert LexerContractNthLine(tokens, TokenType.PreprocessorDirective, 1) == 3
    assert LexerContractHasKind(tokens, TokenType.ColonAssign)
    assert tokens.Count == 8
}

// NOT IN THE DELETED FILE. `#region` is not a conditional, and the lexer treats it exactly like one
// -- it is the preprocessor, later, that tells them apart.
test "lexer passes an unrecognised directive through" {
    tokens := LexerContractTokens("#region Widgets\nx := 1\n#endregion")

    assert LexerContractCountOfKind(tokens, TokenType.PreprocessorDirective) == 2
    assert LexerContractNthValue(tokens, TokenType.PreprocessorDirective, 0) == "#region Widgets"
    assert LexerContractNthValue(tokens, TokenType.PreprocessorDirective, 1) == "#endregion"
    assert tokens.Count == 8
}

// Successor to TestNewlines.
test "lexer reads a newline between every line" {
    tokens := LexerContractTokens("a\nb\nc")

    assert tokens.Count == 6
    assert tokens[0].Type == TokenType.Identifier
    assert tokens[1].Type == TokenType.Newline
    assert tokens[2].Type == TokenType.Identifier
    assert tokens[3].Type == TokenType.Newline
    assert tokens[4].Type == TokenType.Identifier
    assert tokens[5].Type == TokenType.Eof

    // NOT IN THE DELETED FILE: the line counter moves with them, and the last line has no trailing
    // `Newline` -- so a file that does not end in a line break is not given one.
    assert tokens[2].Line == 2
    assert tokens[4].Line == 3
    assert tokens[5].Line == 3
}

// NOT IN THE DELETED FILE. A Windows line ending is ONE `Newline` token whose value is NORMALISED
// to a single line feed -- otherwise every downstream length and column would differ by platform.
test "lexer normalises a carriage return line feed pair" {
    tokens := LexerContractTokens("a\r\nb")

    assert tokens.Count == 4
    assert tokens[1].Type == TokenType.Newline
    assert tokens[1].Value == "\n"
    assert tokens[2].Line == 2
    assert tokens[2].Column == 1
}

// ---- Real declarations -------------------------------------------------------------------------

// Successor to TestSimpleFunction.
test "lexer reads a function header" {
    tokens := LexerContractTokens("func Add(x: int, y: int): int {\n    return x + y\n}")

    assert tokens[0].Type == TokenType.Func
    assert tokens[1].Type == TokenType.Identifier
    assert tokens[1].Value == "Add"
    assert tokens[2].Type == TokenType.LeftParen

    // NOT IN THE DELETED FILE: the rest of the header, including the two `:` that separate a
    // parameter from its type and the one that opens the RETURN type, and the body's `return`.
    assert tokens[4].Type == TokenType.Colon
    assert tokens[5].Value == "int"
    assert tokens[6].Type == TokenType.Comma
    assert tokens[11].Type == TokenType.Colon
    assert tokens[13].Type == TokenType.LeftBrace
    assert tokens[15].Type == TokenType.Return
    assert tokens[17].Type == TokenType.Plus
    assert tokens[20].Type == TokenType.RightBrace
    assert tokens.Count == 22
}

// Successor to TestVariableDeclaration.
test "lexer reads a typed variable declaration" {
    tokens := LexerContractTokens("let name: string = \"John\"")

    assert tokens[0].Type == TokenType.Let
    assert tokens[1].Type == TokenType.Identifier
    assert tokens[1].Value == "name"
    assert tokens[2].Type == TokenType.Colon
    assert tokens[3].Type == TokenType.Identifier
    assert tokens[3].Value == "string"
    assert tokens[4].Type == TokenType.Assign
    assert tokens[5].Type == TokenType.StringLiteral
    assert tokens[5].Value == "\"John\""

    // NOT IN THE DELETED FILE: `string` is an ORDINARY identifier, not a keyword -- N# has no
    // built-in type keywords, and `KeywordTypeForText` proves it below.
    assert tokens.Count == 7
    assert tokens[6].Type == TokenType.Eof
}

// Successor to TestShorthandDeclaration.
test "lexer reads a shorthand declaration" {
    tokens := LexerContractTokens("x := 42")

    assert tokens[0].Type == TokenType.Identifier
    assert tokens[0].Value == "x"
    assert tokens[1].Type == TokenType.ColonAssign
    assert tokens[1].Value == ":="
    assert tokens[2].Type == TokenType.IntLiteral
    assert tokens[2].Value == "42"

    // NOT IN THE DELETED FILE: `:=` is ONE token, so the column of what follows is not the column
    // of a `:` plus one.
    assert tokens[2].Column == 6
    assert tokens.Count == 4
}

// Successor to TestLambda.
test "lexer reads a lambda arrow" {
    tokens := LexerContractTokens("x => x * 2")

    assert tokens[0].Type == TokenType.Identifier
    assert tokens[1].Type == TokenType.Arrow
    assert tokens[2].Type == TokenType.Identifier
    assert tokens[3].Type == TokenType.Star
    assert tokens[4].Type == TokenType.IntLiteral

    // NOT IN THE DELETED FILE: `=>` is not `=` followed by `>`.
    assert tokens[1].Value == "=>"
    assert tokens.Count == 6
}

// Successor to TestNullableOperators.
test "lexer reads the null conditional and coalescing operators" {
    tokens := LexerContractTokens("person?.Name ?? \"Unknown\"")

    assert tokens[0].Type == TokenType.Identifier
    assert tokens[1].Type == TokenType.QuestionDot
    assert tokens[2].Type == TokenType.Identifier
    assert tokens[3].Type == TokenType.QuestionQuestion
    assert tokens[4].Type == TokenType.StringLiteral

    // NOT IN THE DELETED FILE: neither `?` survives on its own.
    assert tokens[1].Value == "?."
    assert tokens[3].Value == "??"
    assert tokens[4].Value == "\"Unknown\""
    assert tokens.Count == 6
}

// Successor to TestNullConditionalIndexing at the TOKEN level. That C# test also asserted the
// parsed IndexAccessExpression, and that half moved in 020 slice 21 to
// `ColumnarParserCallAccess.tests.nl`; this contract owns only the single-token lexing.
test "lexer reads null conditional indexing as one token" {
    tokens := LexerContractTokens("arr?[0]")

    assert tokens[0].Type == TokenType.Identifier
    assert tokens[1].Type == TokenType.QuestionBracket
    assert tokens[2].Type == TokenType.IntLiteral
    assert tokens[3].Type == TokenType.RightBracket

    // NOT IN THE DELETED FILE: `?[` is ONE token, so the closing `]` has no matching `[` in the
    // stream -- the parser has to know that, and this is where it is decided.
    assert tokens[1].Value == "?["
    assert LexerContractCountOfKind(tokens, TokenType.LeftBracket) == 0
    assert tokens.Count == 5
}

// Successor to TestArrayLiteral.
test "lexer reads an array literal" {
    tokens := LexerContractTokens("[1, 2, 3]")

    assert tokens[0].Type == TokenType.LeftBracket
    assert tokens[1].Type == TokenType.IntLiteral
    assert tokens[2].Type == TokenType.Comma
    assert tokens[3].Type == TokenType.IntLiteral
    assert tokens[4].Type == TokenType.Comma
    assert tokens[5].Type == TokenType.IntLiteral
    assert tokens[6].Type == TokenType.RightBracket

    // NOT IN THE DELETED FILE: here `[` IS a `LeftBracket`, which is the negative half of the
    // `?[` contract above.
    assert tokens[0].Value == "["
    assert tokens[5].Value == "3"
    assert tokens.Count == 8
}

// Successor to TestSpreadOperator.
test "lexer reads the spread operator" {
    tokens := LexerContractTokens("...items")

    assert tokens[0].Type == TokenType.DotDotDot
    assert tokens[1].Type == TokenType.Identifier
    assert tokens[1].Value == "items"

    // NOT IN THE DELETED FILE: three dots are one token, not a range and a dot.
    assert tokens[0].Value == "..."
    assert tokens.Count == 3
}

// Successor to TestRangeOperatorVsDotDot.
test "lexer reads a range between two integers" {
    tokens := LexerContractTokens("1..10")

    assert tokens[0].Type == TokenType.IntLiteral
    assert tokens[1].Type == TokenType.DotDot
    assert tokens[2].Type == TokenType.IntLiteral

    // NOT IN THE DELETED FILE: the FIRST dot does not join the literal (which would have made
    // `1.` a float), and the second literal keeps both its digits.
    assert tokens[0].Value == "1"
    assert tokens[1].Value == ".."
    assert tokens[2].Value == "10"
    assert tokens.Count == 4
}

// Successor to TestLineAndColumnTracking.
test "lexer tracks the line and column of every token" {
    tokens := LexerContractTokens("func Test() {\n    x := 42\n}")

    assert tokens[0].Line == 1
    assert LexerContractLineOfValue(tokens, "x") == 2

    // NOT IN THE DELETED FILE: the COLUMN moves with the indentation, the line counter survives the
    // second break, and the closing brace lands at column one of the third line.
    assert tokens[0].Column == 1
    assert LexerContractColumnOfValue(tokens, "x") == 5
    assert tokens[10].Type == TokenType.RightBrace
    assert tokens[10].Line == 3
    assert tokens[10].Column == 1
}

// ---- Unterminated and unexpected ---------------------------------------------------------------

// Successor to TestUnterminatedString.
test "lexer reports an unterminated string" {
    tokens := LexerContractTokens("\"unterminated")

    assert tokens[0].Type == TokenType.StringLiteral
    assert tokens[0].Value == "\"unterminated"
    assert !tokens[0].IsTerminated

    // NOT IN THE DELETED FILE: the value keeps the OPENING quote and gains no closing one, and the
    // stream still ends properly -- an unterminated literal is a diagnostic, not a crash.
    assert tokens.Count == 2
    assert tokens[1].Type == TokenType.Eof
    assert tokens[1].IsTerminated
}

// Successor to TestUnterminatedTripleQuoteString.
test "lexer reports an unterminated triple quote string" {
    tokens := LexerContractTokens("\"\"\"unterminated\nraw string")

    assert tokens[0].Type == TokenType.TripleQuoteStringLiteral
    assert tokens[0].Value == "unterminated\nraw string"
    assert !tokens[0].IsTerminated

    // NOT IN THE DELETED FILE: the OPENING delimiter is still stripped even though the closing one
    // never arrived, and the literal still swallowed its line break.
    assert tokens.Count == 2
    assert tokens[1].Line == 2
}

// Successor to TestUnterminatedInterpolatedRawString.
test "lexer reports an unterminated interpolated raw string" {
    tokens := LexerContractTokens("$\"\"\"Hello {name}")

    assert tokens[0].Type == TokenType.InterpolatedRawStringLiteral
    assert tokens[0].Value == "$\"\"\"Hello {name}"
    assert !tokens[0].IsTerminated

    // NOT IN THE DELETED FILE: the interpolated raw form keeps its delimiters where the plain raw
    // form drops them -- the two are not the same shape, and this is where they differ.
    assert tokens.Count == 2
    assert tokens[1].Type == TokenType.Eof
}

// Successor to TestUnexpectedCharacter.
test "lexer reports an unexpected character" {
    tokens := LexerContractTokens("@")

    assert tokens[0].Type == TokenType.Unknown
    assert tokens[0].Value == "@"

    // NOT IN THE DELETED FILE: an unknown character is ONE token and does not swallow the rest of
    // the file.
    assert tokens.Count == 2
    assert tokens[1].Type == TokenType.Eof
}

// ---- Apostrophes: char literals versus lifetimes -----------------------------------------------

// Successor to TestCharLiteral.
test "lexer reads a char literal" {
    tokens := LexerContractTokens("'|'")

    assert tokens[0].Type == TokenType.CharLiteral
    assert tokens[0].Value == "'|'"
    assert tokens[0].IsTerminated

    // NOT IN THE DELETED FILE: the quotes are part of the value, exactly as for a string.
    assert tokens.Count == 2
    assert tokens[0].Column == 1
}

// Successor to TestEscapedCharLiteral.
test "lexer keeps a char literal's escape verbatim" {
    tokens := LexerContractTokens("'\\n'")

    assert tokens[0].Type == TokenType.CharLiteral
    assert tokens[0].Value == "'\\n'"

    // NOT IN THE DELETED FILE: the escaped quote does NOT end the literal, so the token is
    // terminated and four characters wide.
    assert tokens[0].IsTerminated
    assert tokens.Count == 2
}

// Successor to TestUnterminatedCharLiteralIsNotLifetime.
test "lexer reads an unterminated char literal as a char literal" {
    tokens := LexerContractTokens("letter := 'a")

    assert LexerContractCountOfKind(tokens, TokenType.CharLiteral) == 1
    assert LexerContractNthValue(tokens, TokenType.CharLiteral, 0) == "'a"
    assert !LexerContractNthTerminated(tokens, TokenType.CharLiteral, 0)

    // NOT IN THE DELETED FILE: this is the NEGATIVE half of the lifetime contract -- outside a
    // systems header the same two characters are a broken char literal, not a lifetime.
    assert LexerContractCountOfKind(tokens, TokenType.Lifetime) == 0
    assert LexerContractNthColumn(tokens, TokenType.CharLiteral, 0) == 11
    assert tokens.Count == 4
}

// Successor to TestLifetimeTokenInSystemsContexts.
test "lexer reads lifetimes rather than char literals in a systems header" {
    tokens := LexerContractTokens("func Slice<'a>(buf: ReadOnlySpan<byte> scoped 'a): ReadOnlySpan<byte> returns 'a {}")

    assert LexerContractCountOfKind(tokens, TokenType.Lifetime) == 3
    assert LexerContractCountOfKind(tokens, TokenType.CharLiteral) == 0

    // NOT IN THE DELETED FILE: each of the three apostrophes carries its own text, they sit in the
    // three different positions the rule has to recognise (a generic parameter list, after
    // `scoped`, and after `returns`), and `scoped` itself is a KEYWORD while `returns` is not.
    assert LexerContractNthValue(tokens, TokenType.Lifetime, 0) == "'a"
    assert LexerContractNthValue(tokens, TokenType.Lifetime, 2) == "'a"
    assert LexerContractNthColumn(tokens, TokenType.Lifetime, 0) == 12
    assert LexerContractNthColumn(tokens, TokenType.Lifetime, 1) == 47
    assert LexerContractNthColumn(tokens, TokenType.Lifetime, 2) == 79
    assert tokens[12].Type == TokenType.Scoped
    assert tokens[20].Type == TokenType.Identifier
    assert tokens[20].Value == "returns"
}

// ---- Raw strings -------------------------------------------------------------------------------

// Successor to TestInterpolatedRawString.
test "lexer reads an interpolated raw string" {
    tokens := LexerContractTokens("$\"\"\"\nHello {name}\nWorld\n\"\"\"")

    assert tokens.Count == 2
    assert tokens[0].Type == TokenType.InterpolatedRawStringLiteral
    assert tokens[0].Value.StartsWith("$\"\"\"", StringComparison.Ordinal)
    assert tokens[0].Value.EndsWith("\"\"\"", StringComparison.Ordinal)
    assert tokens[0].Value.IndexOf("{name}", StringComparison.Ordinal) >= 0
    assert tokens[0].IsTerminated

    // NOT IN THE DELETED FILE, WHICH ONLY SAMPLED THE ENDS: the WHOLE value, delimiters and line
    // breaks included, and the line the stream reaches afterwards.
    assert tokens[0].Value == "$\"\"\"\nHello {name}\nWorld\n\"\"\""
    assert tokens[1].Line == 4
}

// ---- The keyword table, crossed rather than sampled ---------------------------------------------

// SUCCESSOR TO ALL SIXTEEN SINGLE-KEYWORD `[Fact]`s AT ONCE (when, print, nameof, must, import,
// required, init, ref, out, lock, file, params, checked, unchecked, implicit, explicit) -- and to
// the other SIXTY-NINE the deleted file never wrote. Each keyword is lexed on its own and must
// answer its own token type, its own text, and nothing else.
test "lexer lexes every keyword to its own token type" {
    texts := LexerContractKeywordTexts()
    kinds := LexerContractKeywordTypes()

    index := 0
    while index < texts.Length {
        tokens := LexerContractTokens(texts[index])
        assert tokens.Count == 2
        assert tokens[0].Type == kinds[index]
        assert tokens[0].Value == texts[index]
        assert tokens[1].Type == TokenType.Eof
        index = index + 1
    }
}

// SUCCESSOR TO TestVarIsIdentifier, plus nine spellings it never tried. A keyword is matched
// WHOLE and EXACTLY: a prefix, a suffix, a different case and an underscore lead are all ordinary
// identifiers.
test "lexer lexes a keyword lookalike as an identifier" {
    lookalikes := LexerContractKeywordLookalikes()

    index := 0
    while index < lookalikes.Length {
        tokens := LexerContractTokens(lookalikes[index])
        assert tokens.Count == 2
        assert tokens[0].Type == TokenType.Identifier
        assert tokens[0].Value == lookalikes[index]
        assert tokens[1].Type == TokenType.Eof
        index = index + 1
    }
}

// NOT IN THE DELETED FILE. The two keyword tables are each other's inverse, all 85 rows of it.
test "lexer maps every keyword text to its token type and back" {
    texts := LexerContractKeywordTexts()
    kinds := LexerContractKeywordTypes()

    index := 0
    while index < texts.Length {
        assert Lexer.KeywordTypeForText(texts[index]) == kinds[index]
        assert Lexer.KeywordTextForType(kinds[index]) == texts[index]
        assert Lexer.IsReservedKeyword(kinds[index])
        index = index + 1
    }
}

// NOT IN THE DELETED FILE. The other 63 `TokenType` members are reserved by NOTHING -- so a new
// keyword cannot be added to one table and forgotten in the other without failing here.
test "lexer reserves no token type outside the keyword table" {
    others := LexerContractNonKeywordTypes()

    index := 0
    while index < others.Length {
        assert Lexer.KeywordTextForType(others[index]) == ""
        assert !Lexer.IsReservedKeyword(others[index])
        index = index + 1
    }
}

// NOT IN THE DELETED FILE. The guard that makes the two sweeps above EXHAUSTIVE rather than merely
// long: the keyword table and the non-keyword table are disjoint and together they are the whole
// enum, so a `TokenType` member added to `Token.nl` and to neither table fails this contract.
test "lexer keyword tables partition the whole token type enum" {
    keywords := LexerContractKeywordTypes()
    others := LexerContractNonKeywordTypes()

    assert LexerContractKeywordTexts().Length == 85
    assert keywords.Length == 85
    assert others.Length == 63
    assert LexerContractAllTokenTypes().Length == 148
    assert LexerContractTablesAreDisjoint(keywords, others)
    assert LexerContractTablesCoverEveryTokenType(keywords, others)
}

// ---- Number literals ---------------------------------------------------------------------------

// Successor to TestHexLiteral, TestHexLiteralUppercase and TestHexLiteralWithUnderscores.
test "lexer reads hexadecimal integer literals" {
    lower := LexerContractTokens("0xFF")
    assert lower[0].Type == TokenType.IntLiteral
    assert lower[0].Value == "0xFF"

    upper := LexerContractTokens("0X1A2B")
    assert upper[0].Type == TokenType.IntLiteral
    assert upper[0].Value == "0X1A2B"

    separated := LexerContractTokens("0xFF_FF")
    assert separated[0].Type == TokenType.IntLiteral
    assert separated[0].Value == "0xFFFF"

    // NOT IN THE DELETED FILE: the PREFIX survives the underscore strip, so the value is still a
    // hex literal and not the decimal `0xFFFF` would be without it.
    assert separated.Count == 2
    assert separated[1].Type == TokenType.Eof
}

// Successor to TestBinaryLiteral and TestBinaryLiteralUppercase.
test "lexer reads binary integer literals" {
    lower := LexerContractTokens("0b1010")
    assert lower[0].Type == TokenType.IntLiteral
    assert lower[0].Value == "0b1010"

    upper := LexerContractTokens("0B1100_0011")
    assert upper[0].Type == TokenType.IntLiteral
    assert upper[0].Value == "0B11000011"

    // NOT IN THE DELETED FILE: the uppercase prefix is preserved as written.
    assert upper.Count == 2
}

// Successor to TestExponentNotation, TestExponentNotationNegative and TestExponentNotationPositive.
test "lexer reads exponent notation" {
    plain := LexerContractTokens("1.5e10")
    assert plain[0].Type == TokenType.FloatLiteral
    assert plain[0].Value == "1.5e10"

    negative := LexerContractTokens("2.5E-3")
    assert negative[0].Type == TokenType.FloatLiteral
    assert negative[0].Value == "2.5E-3"

    positive := LexerContractTokens("1e+5")
    assert positive[0].Type == TokenType.FloatLiteral
    assert positive[0].Value == "1e+5"

    // NOT IN THE DELETED FILE: the exponent's SIGN is part of the literal, not a following
    // operator -- otherwise `2.5E-3` would be a subtraction.
    assert negative.Count == 2
    assert positive.Count == 2
}

// Successor to TestFloatSuffix, TestDecimalSuffix, TestDecimalSuffixOnWholeNumber and
// TestDoubleSuffix.
test "lexer reads every float suffix" {
    single := LexerContractTokens("1.5f")
    assert single[0].Type == TokenType.FloatLiteral
    assert single[0].Value == "1.5f"

    money := LexerContractTokens("1.5m")
    assert money[0].Type == TokenType.FloatLiteral
    assert money[0].Value == "1.5m"

    whole := LexerContractTokens("0m")
    assert whole[0].Type == TokenType.FloatLiteral
    assert whole[0].Value == "0m"

    wide := LexerContractTokens("1.5d")
    assert wide[0].Type == TokenType.FloatLiteral
    assert wide[0].Value == "1.5d"

    // NOT IN THE DELETED FILE: the suffix does not become an identifier of its own.
    assert single.Count == 2
    assert whole.Count == 2
}

// Successor to TestLongSuffix, TestUnsignedLongSuffix and TestUnsignedSuffix.
test "lexer reads every integer suffix" {
    long := LexerContractTokens("42L")
    assert long[0].Type == TokenType.IntLiteral
    assert long[0].Value == "42L"

    unsignedLong := LexerContractTokens("100UL")
    assert unsignedLong[0].Type == TokenType.IntLiteral
    assert unsignedLong[0].Value == "100UL"

    unsigned := LexerContractTokens("42u")
    assert unsigned[0].Type == TokenType.IntLiteral
    assert unsigned[0].Value == "42u"

    // NOT IN THE DELETED FILE: a TWO-letter suffix is consumed whole.
    assert unsignedLong.Count == 2
    assert unsigned.Count == 2
}

// Successor to TestUnderscoresInLargeNumber.
test "lexer strips underscores from a large number" {
    tokens := LexerContractTokens("1_000_000")

    assert tokens[0].Type == TokenType.IntLiteral
    assert tokens[0].Value == "1000000"

    // NOT IN THE DELETED FILE: the token is still ONE token and the file still ends after it.
    assert tokens.Count == 2
    assert tokens[1].Type == TokenType.Eof
}

// Successor to TestInvalidHexLiteral_ProducesErrorToken,
// TestInvalidHexLiteral_LeadingUnderscore_ProducesErrorToken,
// TestInvalidBinaryLiteral_ProducesErrorToken and
// TestInvalidBinaryLiteral_LeadingUnderscore_ProducesErrorToken.
test "lexer refuses a radix prefix with no digits" {
    hex := LexerContractTokens("0x ")
    assert hex[0].Type == TokenType.Unknown

    hexUnderscore := LexerContractTokens("0x_ ")
    assert hexUnderscore[0].Type == TokenType.Unknown

    binary := LexerContractTokens("0b ")
    assert binary[0].Type == TokenType.Unknown

    binaryUnderscore := LexerContractTokens("0b_ ")
    assert binaryUnderscore[0].Type == TokenType.Unknown

    // NOT IN THE DELETED FILE: the refused token carries the PREFIX and nothing more, and the lone
    // underscore that followed it becomes an identifier of its own rather than being swallowed --
    // so the error is one character-range wide and the rest of the file still lexes.
    assert hex[0].Value == "0x"
    assert binary[0].Value == "0b"
    assert hex.Count == 2
    assert hexUnderscore.Count == 3
    assert hexUnderscore[1].Type == TokenType.Identifier
    assert hexUnderscore[1].Value == "_"
    assert binaryUnderscore.Count == 3
    assert binaryUnderscore[1].Value == "_"
}

// Successor to TestInvalidExponent_ProducesErrorToken.
test "lexer refuses an exponent with no digits" {
    tokens := LexerContractTokens("1e ")

    assert tokens[0].Type == TokenType.Unknown

    // NOT IN THE DELETED FILE: the refused token is the mantissa AND the `e`, so no stray `1`
    // reaches the parser.
    assert tokens[0].Value == "1e"
    assert tokens.Count == 2
}

// Successor to TestMultipleDecimalPoints_ProducesErrorToken.
test "lexer refuses a second decimal point" {
    tokens := LexerContractTokens("1.2.3")

    assert tokens[0].Type == TokenType.Unknown

    // NOT IN THE DELETED FILE: the WHOLE malformed literal is one `Unknown` token -- it does not
    // split into a valid float and a member access, which is the shape that would have made
    // `1.2.3` parse as something.
    assert tokens[0].Value == "1.2.3"
    assert tokens.Count == 2
}
