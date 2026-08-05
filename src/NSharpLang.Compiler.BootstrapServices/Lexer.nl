namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text

class Lexer {
    sourceText: string
    fileNameValue: string?
    position: int
    line: int
    column: int
    comments: List<CommentTrivia>

    Comments: List<CommentTrivia> => comments

    constructor(source: string, fileName: string? = null) {
        sourceText = source
        fileNameValue = fileName
        position = 0
        line = 1
        column = 1
        comments = new List<CommentTrivia>()
    }

    static func IsReservedKeyword(tokenType: TokenType): bool {
        return KeywordTextForType(tokenType).Length > 0
    }

    func Tokenize(): List<Token> {
        tokens := new List<Token>()

        while !IsAtEnd() {
            SkipWhitespaceExceptNewlines()

            if IsAtEnd() {
                break
            }

            token := NextToken()

            if token.Type == TokenType.Comment || token.Type == TokenType.MultiLineComment || token.Type == TokenType.XmlDocComment {
                commentText := token.Value
                if token.Type == TokenType.MultiLineComment {
                    commentText = "/*" + token.Value + "*/"
                }

                comments.Add(new CommentTrivia(token.Line, token.Column, commentText, token.Type == TokenType.MultiLineComment))
                continue
            }

            tokens.Add(token)
        }

        tokens.Add(new Token(TokenType.Eof, "", line, column, fileNameValue))
        return InsertIndentationBraces(tokens)
    }

    func InsertIndentationBraces(tokens: List<Token>): List<Token> {
        output := new List<Token>(tokens.Count)
        indentStack := new Stack<int>()
        indentStack.Push(0)

        atLineStart := true
        explicitBraceDepth := 0
        parenBracketDepth := 0
        hasBaseIndent := false
        baseIndent := 0

        for token in tokens {
            if token.Type == TokenType.Newline {
                output.Add(token)
                atLineStart = true
                continue
            }

            if token.Type == TokenType.Eof {
                while indentStack.Count > 1 {
                    indentStack.Pop()
                    output.Add(new Token(TokenType.RightBrace, "}", token.Line, 1, token.FileName))
                }

                output.Add(token)
                break
            }

            if atLineStart {
                rawIndent := Math.Max(0, token.Column - 1)

                if !hasBaseIndent {
                    if indentStack.Count == 1 {
                        baseIndent = rawIndent
                        hasBaseIndent = true
                    }
                }

                currentIndent := Math.Max(0, rawIndent - baseIndent)
                canIndent := parenBracketDepth == 0 && explicitBraceDepth == 0

                if canIndent {
                    previousIndent := indentStack.Peek()

                    if currentIndent > previousIndent {
                        indentStack.Push(currentIndent)
                        output.Add(new Token(TokenType.LeftBrace, "{", token.Line, 1, token.FileName))
                    } else if currentIndent < previousIndent {
                        while indentStack.Count > 1 && currentIndent < indentStack.Peek() {
                            indentStack.Pop()
                            output.Add(new Token(TokenType.RightBrace, "}", token.Line, 1, token.FileName))
                        }
                    }
                }

                atLineStart = false
            }

            if token.Type == TokenType.LeftBrace {
                explicitBraceDepth = explicitBraceDepth + 1
            } else if token.Type == TokenType.RightBrace {
                explicitBraceDepth = Math.Max(0, explicitBraceDepth - 1)
            } else if token.Type == TokenType.LeftParen || token.Type == TokenType.LeftBracket {
                parenBracketDepth = parenBracketDepth + 1
            } else if token.Type == TokenType.RightParen || token.Type == TokenType.RightBracket {
                parenBracketDepth = Math.Max(0, parenBracketDepth - 1)
            }

            output.Add(token)
        }

        return output
    }

    func NextToken(): Token {
        startLine := line
        startColumn := column
        ch := Peek()

        if IsAtLineBreak() {
            ConsumeLineBreak()
            return new Token(TokenType.Newline, LineFeedText(), startLine, startColumn, fileNameValue)
        }

        if ch == '#' {
            return ReadPreprocessorDirective(startLine, startColumn)
        }

        if ch == '/' && PeekNext() == '/' {
            if PeekAhead(2) == '/' {
                return ReadXmlDocComment(startLine, startColumn)
            }

            return ReadSingleLineComment(startLine, startColumn)
        }

        if ch == '/' && PeekNext() == '*' {
            return ReadMultiLineComment(startLine, startColumn)
        }

        if ch == '$' && PeekNext() == '"' {
            Advance()
            if Peek() == '"' && PeekNext() == '"' && PeekAhead(2) == '"' {
                return ReadInterpolatedRawString(startLine, startColumn)
            }

            return ReadString(startLine, startColumn, true)
        }

        if ch == '"' {
            if PeekNext() == '"' && PeekAhead(2) == '"' {
                return ReadTripleQuoteString(startLine, startColumn)
            }

            return ReadString(startLine, startColumn, false)
        }

        if ch == '\'' {
            if IsLifetimeStart() {
                return ReadLifetime(startLine, startColumn)
            }

            return ReadCharLiteral(startLine, startColumn)
        }

        if char.IsDigit(ch) {
            return ReadNumber(startLine, startColumn)
        }

        if char.IsLetter(ch) || ch == '_' {
            return ReadIdentifier(startLine, startColumn)
        }

        if ch == ':' {
            Advance()
            if Peek() == '=' {
                Advance()
                return new Token(TokenType.ColonAssign, ":=", startLine, startColumn, fileNameValue)
            }

            if Peek() == ':' {
                Advance()
                return new Token(TokenType.DoubleColon, "::", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Colon, ":", startLine, startColumn, fileNameValue)
        }

        if ch == '=' {
            Advance()
            if Peek() == '=' {
                Advance()
                return new Token(TokenType.Equal, "==", startLine, startColumn, fileNameValue)
            }

            if Peek() == '>' {
                Advance()
                return new Token(TokenType.Arrow, "=>", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Assign, "=", startLine, startColumn, fileNameValue)
        }

        if ch == '!' {
            Advance()
            if Peek() == '=' {
                Advance()
                return new Token(TokenType.NotEqual, "!=", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Not, "!", startLine, startColumn, fileNameValue)
        }

        if ch == '<' {
            Advance()
            if Peek() == '=' {
                Advance()
                return new Token(TokenType.LessEqual, "<=", startLine, startColumn, fileNameValue)
            }

            if Peek() == '<' {
                Advance()
                return new Token(TokenType.LeftShift, "<<", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Less, "<", startLine, startColumn, fileNameValue)
        }

        if ch == '>' {
            Advance()
            if Peek() == '=' {
                Advance()
                return new Token(TokenType.GreaterEqual, ">=", startLine, startColumn, fileNameValue)
            }

            if Peek() == '>' {
                Advance()
                return new Token(TokenType.RightShift, ">>", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Greater, ">", startLine, startColumn, fileNameValue)
        }

        if ch == '&' {
            Advance()
            if Peek() == '&' {
                Advance()
                return new Token(TokenType.And, "&&", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.BitwiseAnd, "&", startLine, startColumn, fileNameValue)
        }

        if ch == '|' {
            Advance()
            if Peek() == '|' {
                Advance()
                return new Token(TokenType.Or, "||", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.BitwiseOr, "|", startLine, startColumn, fileNameValue)
        }

        if ch == '+' {
            Advance()
            if Peek() == '+' {
                Advance()
                return new Token(TokenType.Increment, "++", startLine, startColumn, fileNameValue)
            }

            if Peek() == '=' {
                Advance()
                return new Token(TokenType.PlusAssign, "+=", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Plus, "+", startLine, startColumn, fileNameValue)
        }

        if ch == '-' {
            Advance()
            if Peek() == '-' {
                Advance()
                return new Token(TokenType.Decrement, "--", startLine, startColumn, fileNameValue)
            }

            if Peek() == '=' {
                Advance()
                return new Token(TokenType.MinusAssign, "-=", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Minus, "-", startLine, startColumn, fileNameValue)
        }

        if ch == '*' {
            Advance()
            if Peek() == '=' {
                Advance()
                return new Token(TokenType.StarAssign, "*=", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Star, "*", startLine, startColumn, fileNameValue)
        }

        if ch == '/' {
            Advance()
            if Peek() == '=' {
                Advance()
                return new Token(TokenType.SlashAssign, "/=", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Slash, "/", startLine, startColumn, fileNameValue)
        }

        if ch == '?' {
            Advance()
            if Peek() == '?' {
                Advance()
                if Peek() == '=' {
                    Advance()
                    return new Token(TokenType.QuestionQuestionAssign, "??=", startLine, startColumn, fileNameValue)
                }

                return new Token(TokenType.QuestionQuestion, "??", startLine, startColumn, fileNameValue)
            }

            if Peek() == '.' {
                Advance()
                return new Token(TokenType.QuestionDot, "?.", startLine, startColumn, fileNameValue)
            }

            if Peek() == '[' {
                Advance()
                return new Token(TokenType.QuestionBracket, "?[", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Question, "?", startLine, startColumn, fileNameValue)
        }

        if ch == '.' {
            Advance()
            if Peek() == '.' {
                Advance()
                if Peek() == '.' {
                    Advance()
                    return new Token(TokenType.DotDotDot, "...", startLine, startColumn, fileNameValue)
                }

                return new Token(TokenType.DotDot, "..", startLine, startColumn, fileNameValue)
            }

            return new Token(TokenType.Dot, ".", startLine, startColumn, fileNameValue)
        }

        singleChar := ch
        Advance()

        if singleChar == '(' {
            return new Token(TokenType.LeftParen, "(", startLine, startColumn, fileNameValue)
        }

        if singleChar == ')' {
            return new Token(TokenType.RightParen, ")", startLine, startColumn, fileNameValue)
        }

        if singleChar == '{' {
            return new Token(TokenType.LeftBrace, "{", startLine, startColumn, fileNameValue)
        }

        if singleChar == '}' {
            return new Token(TokenType.RightBrace, "}", startLine, startColumn, fileNameValue)
        }

        if singleChar == '[' {
            return new Token(TokenType.LeftBracket, "[", startLine, startColumn, fileNameValue)
        }

        if singleChar == ']' {
            return new Token(TokenType.RightBracket, "]", startLine, startColumn, fileNameValue)
        }

        if singleChar == ';' {
            return new Token(TokenType.Semicolon, ";", startLine, startColumn, fileNameValue)
        }

        if singleChar == ',' {
            return new Token(TokenType.Comma, ",", startLine, startColumn, fileNameValue)
        }

        if singleChar == '%' {
            return new Token(TokenType.Percent, "%", startLine, startColumn, fileNameValue)
        }

        if singleChar == '^' {
            return new Token(TokenType.BitwiseXor, "^", startLine, startColumn, fileNameValue)
        }

        if singleChar == '~' {
            return new Token(TokenType.BitwiseNot, "~", startLine, startColumn, fileNameValue)
        }

        return new Token(TokenType.Unknown, singleChar.ToString(), startLine, startColumn, fileNameValue)
    }

    func ReadIdentifier(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()

        while !IsAtEnd() && IsIdentifierPart(Peek()) {
            builder.Append(Peek())
            Advance()
        }

        value := builder.ToString()
        return new Token(KeywordTypeForText(value), value, startLine, startColumn, fileNameValue)
    }

    func ReadNumber(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()
        isFloat := false

        if Peek() == '0' && (PeekNext() == 'x' || PeekNext() == 'X') {
            builder.Append(Peek())
            Advance()
            builder.Append(Peek())
            Advance()

            if IsAtEnd() || !IsHexDigit(Peek()) {
                return new Token(TokenType.Unknown, builder.ToString(), startLine, startColumn, fileNameValue)
            }

            while !IsAtEnd() && (IsHexDigit(Peek()) || Peek() == '_') {
                if Peek() == '_' {
                    Advance()
                    continue
                }

                builder.Append(Peek())
                Advance()
            }

            ConsumeIntegerSuffix(builder)
            return new Token(TokenType.IntLiteral, builder.ToString(), startLine, startColumn, fileNameValue)
        }

        if Peek() == '0' && (PeekNext() == 'b' || PeekNext() == 'B') {
            builder.Append(Peek())
            Advance()
            builder.Append(Peek())
            Advance()

            if IsAtEnd() || (Peek() != '0' && Peek() != '1') {
                return new Token(TokenType.Unknown, builder.ToString(), startLine, startColumn, fileNameValue)
            }

            while !IsAtEnd() && (Peek() == '0' || Peek() == '1' || Peek() == '_') {
                if Peek() == '_' {
                    Advance()
                    continue
                }

                builder.Append(Peek())
                Advance()
            }

            ConsumeIntegerSuffix(builder)
            return new Token(TokenType.IntLiteral, builder.ToString(), startLine, startColumn, fileNameValue)
        }

        while !IsAtEnd() && (char.IsDigit(Peek()) || Peek() == '.' || Peek() == '_') {
            if Peek() == '_' {
                Advance()
                continue
            }

            if Peek() == '.' {
                if PeekNext() == '.' {
                    break
                }

                if !char.IsDigit(PeekNext()) {
                    break
                }

                if isFloat {
                    while !IsAtEnd() && (char.IsDigit(Peek()) || Peek() == '.') {
                        builder.Append(Peek())
                        Advance()
                    }

                    return new Token(TokenType.Unknown, builder.ToString(), startLine, startColumn, fileNameValue)
                }

                isFloat = true
            }

            builder.Append(Peek())
            Advance()
        }

        if !IsAtEnd() && (Peek() == 'e' || Peek() == 'E') {
            isFloat = true
            builder.Append(Peek())
            Advance()

            if !IsAtEnd() && (Peek() == '+' || Peek() == '-') {
                builder.Append(Peek())
                Advance()
            }

            if IsAtEnd() || !char.IsDigit(Peek()) {
                return new Token(TokenType.Unknown, builder.ToString(), startLine, startColumn, fileNameValue)
            }

            while !IsAtEnd() && (char.IsDigit(Peek()) || Peek() == '_') {
                if Peek() == '_' {
                    Advance()
                    continue
                }

                builder.Append(Peek())
                Advance()
            }
        }

        if isFloat {
            ConsumeFloatSuffix(builder)
        } else if !IsAtEnd() && (Peek() == 'm' || Peek() == 'M') {
            builder.Append(Peek())
            Advance()
            isFloat = true
        } else {
            ConsumeIntegerSuffix(builder)
        }

        tokenType := TokenType.IntLiteral
        if isFloat {
            tokenType = TokenType.FloatLiteral
        }

        return new Token(tokenType, builder.ToString(), startLine, startColumn, fileNameValue)
    }

    func ConsumeFloatSuffix(builder: StringBuilder): void {
        if IsAtEnd() {
            return
        }

        ch := Peek()
        if ch == 'f' || ch == 'F' || ch == 'd' || ch == 'D' || ch == 'm' || ch == 'M' {
            builder.Append(ch)
            Advance()
        }
    }

    func ConsumeIntegerSuffix(builder: StringBuilder): void {
        if IsAtEnd() {
            return
        }

        ch := Peek()
        if ch == 'u' || ch == 'U' {
            builder.Append(ch)
            Advance()
            if !IsAtEnd() {
                if Peek() == 'l' || Peek() == 'L' {
                    builder.Append(Peek())
                    Advance()
                }
            }
        } else if ch == 'l' || ch == 'L' {
            builder.Append(ch)
            Advance()
            if !IsAtEnd() {
                if Peek() == 'u' || Peek() == 'U' {
                    builder.Append(Peek())
                    Advance()
                }
            }
        }
    }

    static func IsHexDigit(ch: char): bool {
        return char.IsDigit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
    }

    func ReadString(startLine: int, startColumn: int, isInterpolated: bool = false): Token {
        builder := new StringBuilder()
        interpolationDepth := 0
        nestedStringDepth := 0

        if isInterpolated {
            builder.Append('$')
        }

        builder.Append('"')
        Advance()

        while !IsAtEnd() {
            if IsAtLineBreak() {
                return new Token(TokenType.StringLiteral, builder.ToString(), startLine, startColumn, fileNameValue, false)
            }

            if isInterpolated {
                if nestedStringDepth > 0 {
                    if Peek() == '\\' {
                        builder.Append('\\')
                        Advance()
                        if IsAtEnd() {
                            return new Token(TokenType.StringLiteral, builder.ToString(), startLine, startColumn, fileNameValue, false)
                        }

                        builder.Append(Peek())
                        Advance()
                        continue
                    }

                    if Peek() == '"' {
                        nestedStringDepth = nestedStringDepth - 1
                    }

                    builder.Append(Peek())
                    Advance()
                    continue
                }

                if Peek() == '{' {
                    interpolationDepth = interpolationDepth + 1
                    builder.Append(Peek())
                    Advance()
                    continue
                }

                if Peek() == '}' && interpolationDepth > 0 {
                    interpolationDepth = interpolationDepth - 1
                    builder.Append(Peek())
                    Advance()
                    continue
                }

                if Peek() == '"' && interpolationDepth > 0 {
                    nestedStringDepth = nestedStringDepth + 1
                    builder.Append(Peek())
                    Advance()
                    continue
                }

                if Peek() == '"' && interpolationDepth == 0 {
                    break
                }
            } else if Peek() == '"' {
                break
            }

            if Peek() == '\\' {
                builder.Append('\\')
                Advance()
                if IsAtEnd() {
                    return new Token(TokenType.StringLiteral, builder.ToString(), startLine, startColumn, fileNameValue, false)
                }

                builder.Append(Peek())
                Advance()
            } else {
                builder.Append(Peek())
                Advance()
            }
        }

        if IsAtEnd() {
            return new Token(TokenType.StringLiteral, builder.ToString(), startLine, startColumn, fileNameValue, false)
        }

        builder.Append('"')
        Advance()

        return new Token(TokenType.StringLiteral, builder.ToString(), startLine, startColumn, fileNameValue)
    }

    func ReadCharLiteral(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()
        builder.Append('\'')
        Advance()

        if IsAtEnd() || IsAtLineBreak() {
            return new Token(TokenType.CharLiteral, builder.ToString(), startLine, startColumn, fileNameValue, false)
        }

        if Peek() == '\\' {
            builder.Append('\\')
            Advance()
            if !IsAtEnd() {
                if !IsAtLineBreak() {
                    builder.Append(Peek())
                    Advance()
                }
            }
        } else {
            builder.Append(Peek())
            Advance()
        }

        terminated := false
        if !IsAtEnd() {
            if Peek() == '\'' {
                builder.Append('\'')
                Advance()
                terminated = true
            }
        }

        return new Token(TokenType.CharLiteral, builder.ToString(), startLine, startColumn, fileNameValue, terminated)
    }

    func IsLifetimeStart(): bool {
        next := PeekNext()
        if !char.IsLetter(next) {
            if next != '_' {
                return false
            }
        }

        if PeekAhead(2) == '\'' {
            return false
        }

        return IsLifetimeContext()
    }

    func IsLifetimeContext(): bool {
        index := position - 1
        while index >= 0 && char.IsWhiteSpace(sourceText[index]) {
            index = index - 1
        }

        if index < 0 {
            return false
        }

        previous := sourceText[index]
        if previous == '<' || previous == ',' {
            return true
        }

        if !char.IsLetterOrDigit(previous) {
            if previous != '_' {
                return false
            }
        }

        end := index + 1
        while index >= 0 && IsIdentifierPart(sourceText[index]) {
            index = index - 1
        }

        word := sourceText.Substring(index + 1, end - index - 1)
        return word == "scoped" || word == "returns"
    }

    func ReadLifetime(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()
        builder.Append(Peek())
        Advance()

        while !IsAtEnd() {
            ch := Peek()
            if !IsIdentifierPart(ch) {
                break
            }

            builder.Append(ch)
            Advance()
        }

        return new Token(TokenType.Lifetime, builder.ToString(), startLine, startColumn, fileNameValue)
    }

    func ReadTripleQuoteString(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()
        Advance()
        Advance()
        Advance()

        while !IsAtEnd() {
            if Peek() == '"' && PeekNext() == '"' && PeekAhead(2) == '"' {
                Advance()
                Advance()
                Advance()
                return new Token(TokenType.TripleQuoteStringLiteral, builder.ToString(), startLine, startColumn, fileNameValue)
            }

            if IsAtLineBreak() {
                builder.Append(ConsumeLineBreak())
                continue
            }

            builder.Append(Peek())
            Advance()
        }

        return new Token(TokenType.TripleQuoteStringLiteral, builder.ToString(), startLine, startColumn, fileNameValue, false)
    }

    func ReadInterpolatedRawString(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()
        builder.Append('$')
        builder.Append('"')
        builder.Append('"')
        builder.Append('"')

        Advance()
        Advance()
        Advance()

        while !IsAtEnd() {
            if Peek() == '"' && PeekNext() == '"' && PeekAhead(2) == '"' {
                builder.Append('"')
                builder.Append('"')
                builder.Append('"')
                Advance()
                Advance()
                Advance()
                return new Token(TokenType.InterpolatedRawStringLiteral, builder.ToString(), startLine, startColumn, fileNameValue)
            }

            if IsAtLineBreak() {
                builder.Append(ConsumeLineBreak())
                continue
            }

            builder.Append(Peek())
            Advance()
        }

        return new Token(TokenType.InterpolatedRawStringLiteral, builder.ToString(), startLine, startColumn, fileNameValue, false)
    }

    func ReadSingleLineComment(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()

        while !IsAtEnd() && !IsAtLineBreak() {
            builder.Append(Peek())
            Advance()
        }

        return new Token(TokenType.Comment, builder.ToString(), startLine, startColumn, fileNameValue)
    }

    func ReadMultiLineComment(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()
        Advance()
        Advance()

        while !IsAtEnd() {
            if Peek() == '*' && PeekNext() == '/' {
                Advance()
                Advance()
                return new Token(TokenType.MultiLineComment, builder.ToString(), startLine, startColumn, fileNameValue)
            }

            if IsAtLineBreak() {
                builder.Append(ConsumeLineBreak())
                continue
            }

            builder.Append(Peek())
            Advance()
        }

        return new Token(TokenType.MultiLineComment, builder.ToString(), startLine, startColumn, fileNameValue)
    }

    func ReadXmlDocComment(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()

        while !IsAtEnd() && !IsAtLineBreak() {
            builder.Append(Peek())
            Advance()
        }

        return new Token(TokenType.XmlDocComment, builder.ToString(), startLine, startColumn, fileNameValue)
    }

    func ReadPreprocessorDirective(startLine: int, startColumn: int): Token {
        builder := new StringBuilder()

        while !IsAtEnd() && !IsAtLineBreak() {
            builder.Append(Peek())
            Advance()
        }

        return new Token(TokenType.PreprocessorDirective, builder.ToString(), startLine, startColumn, fileNameValue)
    }

    func SkipWhitespaceExceptNewlines(): void {
        while !IsAtEnd() && char.IsWhiteSpace(Peek()) && !IsAtLineBreak() {
            Advance()
        }
    }

    func IsAtLineBreak(): bool {
        if IsAtEnd() {
            return false
        }

        return Peek() == '\n' || Peek() == '\r'
    }

    func ConsumeLineBreak(): string {
        if Peek() == '\r' {
            Advance()
            if Peek() == '\n' {
                Advance()
                line = line + 1
                column = 1
                return CarriageReturnText() + LineFeedText()
            }

            line = line + 1
            column = 1
            return CarriageReturnText()
        }

        Advance()
        line = line + 1
        column = 1
        return LineFeedText()
    }

    func Peek(): char {
        if IsAtEnd() {
            return '\0'
        }

        return sourceText[position]
    }

    func PeekNext(): char {
        if position + 1 >= sourceText.Length {
            return '\0'
        }

        return sourceText[position + 1]
    }

    func PeekAhead(offset: int): char {
        if position + offset >= sourceText.Length {
            return '\0'
        }

        return sourceText[position + offset]
    }

    func Advance(): void {
        if !IsAtEnd() {
            position = position + 1
            column = column + 1
        }
    }

    func IsAtEnd(): bool {
        return position >= sourceText.Length
    }

    static func IsIdentifierPart(ch: char): bool {
        return char.IsLetterOrDigit(ch) || ch == '_'
    }

    static func LineFeedText(): string {
        return ((char)10).ToString()
    }

    static func CarriageReturnText(): string {
        return ((char)13).ToString()
    }

    static func KeywordTypeForText(value: string): TokenType {
        if value == "func" {
            return TokenType.Func
        }
        if value == "class" {
            return TokenType.Class
        }
        if value == "struct" {
            return TokenType.Struct
        }
        if value == "interface" {
            return TokenType.Interface
        }
        if value == "duck" {
            return TokenType.Duck
        }
        if value == "union" {
            return TokenType.Union
        }
        if value == "record" {
            return TokenType.Record
        }
        if value == "enum" {
            return TokenType.Enum
        }
        if value == "namespace" {
            return TokenType.Namespace
        }
        if value == "using" {
            return TokenType.Using
        }
        if value == "import" {
            return TokenType.Import
        }
        if value == "package" {
            return TokenType.Package
        }
        if value == "let" {
            return TokenType.Let
        }
        if value == "must" {
            return TokenType.Must
        }
        if value == "const" {
            return TokenType.Const
        }
        if value == "readonly" {
            return TokenType.Readonly
        }
        if value == "if" {
            return TokenType.If
        }
        if value == "else" {
            return TokenType.Else
        }
        if value == "for" {
            return TokenType.For
        }
        if value == "foreach" {
            return TokenType.Foreach
        }
        if value == "while" {
            return TokenType.While
        }
        if value == "in" {
            return TokenType.In
        }
        if value == "return" {
            return TokenType.Return
        }
        if value == "yield" {
            return TokenType.Yield
        }
        if value == "match" {
            return TokenType.Match
        }
        if value == "switch" {
            return TokenType.Switch
        }
        if value == "case" {
            return TokenType.Case
        }
        if value == "default" {
            return TokenType.Default
        }
        if value == "break" {
            return TokenType.Break
        }
        if value == "continue" {
            return TokenType.Continue
        }
        if value == "throw" {
            return TokenType.Throw
        }
        if value == "try" {
            return TokenType.Try
        }
        if value == "catch" {
            return TokenType.Catch
        }
        if value == "finally" {
            return TokenType.Finally
        }
        if value == "new" {
            return TokenType.New
        }
        if value == "this" {
            return TokenType.This
        }
        if value == "base" {
            return TokenType.Base
        }
        if value == "true" {
            return TokenType.True
        }
        if value == "false" {
            return TokenType.False
        }
        if value == "null" {
            return TokenType.Null
        }
        if value == "is" {
            return TokenType.Is
        }
        if value == "as" {
            return TokenType.As
        }
        if value == "typeof" {
            return TokenType.Typeof
        }
        if value == "nameof" {
            return TokenType.Nameof
        }
        if value == "sizeof" {
            return TokenType.Sizeof
        }
        if value == "print" {
            return TokenType.Print
        }
        if value == "where" {
            return TokenType.Where
        }
        if value == "when" {
            return TokenType.When
        }
        if value == "and" {
            return TokenType.AndKeyword
        }
        if value == "or" {
            return TokenType.OrKeyword
        }
        if value == "not" {
            return TokenType.NotKeyword
        }
        if value == "virtual" {
            return TokenType.Virtual
        }
        if value == "override" {
            return TokenType.Override
        }
        if value == "abstract" {
            return TokenType.Abstract
        }
        if value == "sealed" {
            return TokenType.Sealed
        }
        if value == "partial" {
            return TokenType.Partial
        }
        if value == "static" {
            return TokenType.Static
        }
        if value == "public" {
            return TokenType.Public
        }
        if value == "private" {
            return TokenType.Private
        }
        if value == "internal" {
            return TokenType.Internal
        }
        if value == "protected" {
            return TokenType.Protected
        }
        if value == "async" {
            return TokenType.Async
        }
        if value == "await" {
            return TokenType.Await
        }
        if value == "immutable" {
            return TokenType.Immutable
        }
        if value == "with" {
            return TokenType.With
        }
        if value == "type" {
            return TokenType.Type
        }
        if value == "assert" {
            return TokenType.Assert
        }
        if value == "operator" {
            return TokenType.Operator
        }
        if value == "required" {
            return TokenType.Required
        }
        if value == "init" {
            return TokenType.Init
        }
        if value == "ref" {
            return TokenType.Ref
        }
        if value == "out" {
            return TokenType.Out
        }
        if value == "lock" {
            return TokenType.Lock
        }
        if value == "file" {
            return TokenType.File
        }
        if value == "params" {
            return TokenType.Params
        }
        if value == "checked" {
            return TokenType.Checked
        }
        if value == "unchecked" {
            return TokenType.Unchecked
        }
        if value == "implicit" {
            return TokenType.Implicit
        }
        if value == "explicit" {
            return TokenType.Explicit
        }
        if value == "newtype" {
            return TokenType.Newtype
        }
        if value == "alloc" {
            return TokenType.Alloc
        }
        if value == "allow" {
            return TokenType.Allow
        }
        if value == "stackalloc" {
            return TokenType.Stackalloc
        }
        if value == "unsafe" {
            return TokenType.Unsafe
        }
        if value == "scoped" {
            return TokenType.Scoped
        }
        return TokenType.Identifier
    }

    static func KeywordTextForType(tokenType: TokenType): string {
        if tokenType == TokenType.Func {
            return "func"
        }
        if tokenType == TokenType.Class {
            return "class"
        }
        if tokenType == TokenType.Struct {
            return "struct"
        }
        if tokenType == TokenType.Interface {
            return "interface"
        }
        if tokenType == TokenType.Duck {
            return "duck"
        }
        if tokenType == TokenType.Union {
            return "union"
        }
        if tokenType == TokenType.Record {
            return "record"
        }
        if tokenType == TokenType.Enum {
            return "enum"
        }
        if tokenType == TokenType.Namespace {
            return "namespace"
        }
        if tokenType == TokenType.Using {
            return "using"
        }
        if tokenType == TokenType.Import {
            return "import"
        }
        if tokenType == TokenType.Package {
            return "package"
        }
        if tokenType == TokenType.Let {
            return "let"
        }
        if tokenType == TokenType.Must {
            return "must"
        }
        if tokenType == TokenType.Const {
            return "const"
        }
        if tokenType == TokenType.Readonly {
            return "readonly"
        }
        if tokenType == TokenType.If {
            return "if"
        }
        if tokenType == TokenType.Else {
            return "else"
        }
        if tokenType == TokenType.For {
            return "for"
        }
        if tokenType == TokenType.Foreach {
            return "foreach"
        }
        if tokenType == TokenType.While {
            return "while"
        }
        if tokenType == TokenType.In {
            return "in"
        }
        if tokenType == TokenType.Return {
            return "return"
        }
        if tokenType == TokenType.Yield {
            return "yield"
        }
        if tokenType == TokenType.Match {
            return "match"
        }
        if tokenType == TokenType.Switch {
            return "switch"
        }
        if tokenType == TokenType.Case {
            return "case"
        }
        if tokenType == TokenType.Default {
            return "default"
        }
        if tokenType == TokenType.Break {
            return "break"
        }
        if tokenType == TokenType.Continue {
            return "continue"
        }
        if tokenType == TokenType.Throw {
            return "throw"
        }
        if tokenType == TokenType.Try {
            return "try"
        }
        if tokenType == TokenType.Catch {
            return "catch"
        }
        if tokenType == TokenType.Finally {
            return "finally"
        }
        if tokenType == TokenType.New {
            return "new"
        }
        if tokenType == TokenType.This {
            return "this"
        }
        if tokenType == TokenType.Base {
            return "base"
        }
        if tokenType == TokenType.True {
            return "true"
        }
        if tokenType == TokenType.False {
            return "false"
        }
        if tokenType == TokenType.Null {
            return "null"
        }
        if tokenType == TokenType.Is {
            return "is"
        }
        if tokenType == TokenType.As {
            return "as"
        }
        if tokenType == TokenType.Typeof {
            return "typeof"
        }
        if tokenType == TokenType.Nameof {
            return "nameof"
        }
        if tokenType == TokenType.Sizeof {
            return "sizeof"
        }
        if tokenType == TokenType.Print {
            return "print"
        }
        if tokenType == TokenType.Where {
            return "where"
        }
        if tokenType == TokenType.When {
            return "when"
        }
        if tokenType == TokenType.AndKeyword {
            return "and"
        }
        if tokenType == TokenType.OrKeyword {
            return "or"
        }
        if tokenType == TokenType.NotKeyword {
            return "not"
        }
        if tokenType == TokenType.Virtual {
            return "virtual"
        }
        if tokenType == TokenType.Override {
            return "override"
        }
        if tokenType == TokenType.Abstract {
            return "abstract"
        }
        if tokenType == TokenType.Sealed {
            return "sealed"
        }
        if tokenType == TokenType.Partial {
            return "partial"
        }
        if tokenType == TokenType.Static {
            return "static"
        }
        if tokenType == TokenType.Public {
            return "public"
        }
        if tokenType == TokenType.Private {
            return "private"
        }
        if tokenType == TokenType.Internal {
            return "internal"
        }
        if tokenType == TokenType.Protected {
            return "protected"
        }
        if tokenType == TokenType.Async {
            return "async"
        }
        if tokenType == TokenType.Await {
            return "await"
        }
        if tokenType == TokenType.Immutable {
            return "immutable"
        }
        if tokenType == TokenType.With {
            return "with"
        }
        if tokenType == TokenType.Type {
            return "type"
        }
        if tokenType == TokenType.Assert {
            return "assert"
        }
        if tokenType == TokenType.Operator {
            return "operator"
        }
        if tokenType == TokenType.Required {
            return "required"
        }
        if tokenType == TokenType.Init {
            return "init"
        }
        if tokenType == TokenType.Ref {
            return "ref"
        }
        if tokenType == TokenType.Out {
            return "out"
        }
        if tokenType == TokenType.Lock {
            return "lock"
        }
        if tokenType == TokenType.File {
            return "file"
        }
        if tokenType == TokenType.Params {
            return "params"
        }
        if tokenType == TokenType.Checked {
            return "checked"
        }
        if tokenType == TokenType.Unchecked {
            return "unchecked"
        }
        if tokenType == TokenType.Implicit {
            return "implicit"
        }
        if tokenType == TokenType.Explicit {
            return "explicit"
        }
        if tokenType == TokenType.Newtype {
            return "newtype"
        }
        if tokenType == TokenType.Alloc {
            return "alloc"
        }
        if tokenType == TokenType.Allow {
            return "allow"
        }
        if tokenType == TokenType.Stackalloc {
            return "stackalloc"
        }
        if tokenType == TokenType.Unsafe {
            return "unsafe"
        }
        if tokenType == TokenType.Scoped {
            return "scoped"
        }
        return ""
    }
}
