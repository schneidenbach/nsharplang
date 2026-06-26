namespace NSharpLang.Compiler

import System
import System.Collections.Generic

public class Preprocessor {
    public static func Process(
        tokens: List<Token>,
        definedSymbols: IReadOnlySet<string>,
        fileName: string?,
        errors: List<CompilerError>): List<Token> {
        result := new List<Token>()
        stack := new Stack<Frame>()

        tokenIndex := 0
        while tokenIndex < tokens.Count {
            token: Token = tokens[tokenIndex]

            if token.Type == TokenType.Eof {
                if stack.Count > 0 {
                    Preprocessor.AddError(errors, fileName, token, "Unterminated '#if' directive: expected a matching '#endif'.")
                    stack.Clear()
                }

                result.Add(token)
                tokenIndex = tokenIndex + 1
                continue
            }

            if token.Type != TokenType.PreprocessorDirective {
                if IsEmitting(stack) {
                    result.Add(token)
                }

                tokenIndex = tokenIndex + 1
                continue
            }

            parts := SplitDirective(token.Value)
            if parts.Keyword == "if" {
                HandleIf(stack, parts.Argument, definedSymbols, token, fileName, errors)
            } else if parts.Keyword == "elif" {
                HandleElif(stack, parts.Argument, definedSymbols, token, fileName, errors)
            } else if parts.Keyword == "else" {
                HandleElse(stack, token, fileName, errors)
            } else if parts.Keyword == "endif" {
                HandleEndif(stack, token, fileName, errors)
            } else if IsEmitting(stack) {
                result.Add(token)
            }

            tokenIndex = tokenIndex + 1
        }

        return result
    }

    static func IsEmitting(stack: Stack<Frame>): bool {
        if stack.Count == 0 {
            return true
        }

        frame := stack.Peek()
        return frame.CurrentActive
    }

    static func HandleIf(
        stack: Stack<Frame>,
        condition: string,
        symbols: IReadOnlySet<string>,
        token: Token,
        fileName: string?,
        errors: List<CompilerError>) {
        parentActive := IsEmitting(stack)
        taken := false
        if parentActive {
            taken = EvaluateGuarded(condition, symbols, token, fileName, errors)
        }

        branchTaken := true
        if parentActive {
            branchTaken = taken
        }

        stack.Push(new Frame {
            ParentActive: parentActive,
            BranchTaken: branchTaken,
            CurrentActive: taken,
            SeenElse: false
        })
    }

    static func HandleElif(
        stack: Stack<Frame>,
        condition: string,
        symbols: IReadOnlySet<string>,
        token: Token,
        fileName: string?,
        errors: List<CompilerError>) {
        if stack.Count == 0 {
            Preprocessor.AddError(errors, fileName, token, "'#elif' directive without a matching '#if'.")
            return
        }

        frame := stack.Pop()
        if frame.SeenElse {
            Preprocessor.AddError(errors, fileName, token, "'#elif' directive cannot appear after '#else'.")
            stack.Push(frame)
            return
        }

        if !frame.ParentActive {
            frame.CurrentActive = false
        } else if frame.BranchTaken {
            frame.CurrentActive = false
        } else {
            taken := EvaluateGuarded(condition, symbols, token, fileName, errors)
            frame.CurrentActive = taken
            frame.BranchTaken = taken
        }

        stack.Push(frame)
    }

    static func HandleElse(
        stack: Stack<Frame>,
        token: Token,
        fileName: string?,
        errors: List<CompilerError>) {
        if stack.Count == 0 {
            Preprocessor.AddError(errors, fileName, token, "'#else' directive without a matching '#if'.")
            return
        }

        frame := stack.Pop()
        if frame.SeenElse {
            Preprocessor.AddError(errors, fileName, token, "Multiple '#else' directives for a single '#if'.")
            stack.Push(frame)
            return
        }

        frame.SeenElse = true
        if !frame.ParentActive {
            frame.CurrentActive = false
        } else {
            frame.CurrentActive = !frame.BranchTaken
            frame.BranchTaken = true
        }

        stack.Push(frame)
    }

    static func HandleEndif(
        stack: Stack<Frame>,
        token: Token,
        fileName: string?,
        errors: List<CompilerError>) {
        if stack.Count == 0 {
            Preprocessor.AddError(errors, fileName, token, "'#endif' directive without a matching '#if'.")
            return
        }

        stack.Pop()
    }

    static func EvaluateGuarded(
        condition: string,
        symbols: IReadOnlySet<string>,
        token: Token,
        fileName: string?,
        errors: List<CompilerError>): bool {
        value := false
        errorMessage := ""
        if ConditionEvaluator.TryEvaluate(condition, symbols, out value, out errorMessage) {
            return value
        }

        Preprocessor.AddError(errors, fileName, token, errorMessage)
        return false
    }

    static func AddError(errors: List<CompilerError>, fileName: string?, token: Token, message: object) {
        messageText := ""
        if message != null {
            messageText = message.ToString() ?? ""
        }

        length := token.Value.Length
        if length < 1 {
            length = 1
        }

        errors.Add(new CompilerError(
            ErrorCode.InvalidPreprocessorDirective,
            messageText,
            token.Line,
            token.Column,
            ErrorSeverity.Error) {
            FileName: fileName,
            Length: length
        })
    }

    static func SplitDirective(raw: string): PreprocessorDirectiveParts {
        i := 0
        if i < raw.Length && raw[i] == '#' {
            i = i + 1
        }

        while i < raw.Length && char.IsWhiteSpace(raw[i]) {
            i = i + 1
        }

        keywordStart := i
        while i < raw.Length && char.IsLetter(raw[i]) {
            i = i + 1
        }

        keyword := raw.Substring(keywordStart, i - keywordStart)

        while i < raw.Length && char.IsWhiteSpace(raw[i]) {
            i = i + 1
        }

        argument := raw.Substring(i)
        commentIndex := argument.IndexOf("//", StringComparison.Ordinal)
        if commentIndex >= 0 {
            argument = argument.Substring(0, commentIndex)
        }

        return new PreprocessorDirectiveParts(keyword, argument.Trim())
    }
}

class PreprocessorDirectiveParts {
    Keyword: string
    Argument: string

    constructor(keyword: string, argument: string) {
        Keyword = keyword
        Argument = argument
    }
}

class ConditionEvaluator {
    text: string
    symbols: IReadOnlySet<string>
    position: int
    hasError: bool = false
    errorMessage: string = ""

    constructor(text: string, symbols: IReadOnlySet<string>) {
        this.text = text
        this.symbols = symbols
        position = 0
    }

    public static func TryEvaluate(condition: string, symbols: IReadOnlySet<string>, out value: bool, out errorMessage: string): bool {
        value = false
        errorMessage = ""

        if string.IsNullOrWhiteSpace(condition) {
            errorMessage = "Missing condition after '#if'/'#elif'. Expected a symbol such as 'DEBUG'."
            return false
        }

        evaluator := new ConditionEvaluator(condition, symbols)
        parsed := evaluator.ParseOr()
        if evaluator.hasError {
            errorMessage = evaluator.errorMessage
            return false
        }

        evaluator.SkipWhitespace()
        if evaluator.position < evaluator.text.Length {
            errorMessage = $"Unexpected character '{evaluator.text[evaluator.position]}' in preprocessor condition '{condition.Trim()}'."
            return false
        }

        value = parsed
        return true
    }

    func ParseOr(): bool {
        value := ParseAnd()
        while TryConsume("||") {
            rhs := ParseAnd()
            if hasError {
                return false
            }

            value = value || rhs
        }

        return value
    }

    func ParseAnd(): bool {
        value := ParseUnary()
        while TryConsume("&&") {
            rhs := ParseUnary()
            if hasError {
                return false
            }

            value = value && rhs
        }

        return value
    }

    func ParseUnary(): bool {
        SkipWhitespace()
        if hasError {
            return false
        }

        if position < text.Length && text[position] == '!' {
            position = position + 1
            return !ParseUnary()
        }

        return ParsePrimary()
    }

    func ParsePrimary(): bool {
        SkipWhitespace()
        if position >= text.Length {
            SetError("Unexpected end of preprocessor condition; expected a symbol.")
            return false
        }

        ch := text[position]
        if ch == '(' {
            position = position + 1
            value := ParseOr()
            if hasError {
                return false
            }

            SkipWhitespace()
            if position >= text.Length || text[position] != ')' {
                SetError("Missing ')' in preprocessor condition.")
                return false
            }

            position = position + 1
            return value
        }

        if char.IsLetter(ch) || ch == '_' {
            start := position
            while position < text.Length && (char.IsLetterOrDigit(text[position]) || text[position] == '_') {
                position = position + 1
            }

            name := text.Substring(start, position - start)
            if name == "true" {
                return true
            }

            if name == "false" {
                return false
            }

            return symbols.Contains(name)
        }

        SetError($"Unexpected character '{ch}' in preprocessor condition.")
        return false
    }

    func SkipWhitespace() {
        while position < text.Length && char.IsWhiteSpace(text[position]) {
            position = position + 1
        }
    }

    func TryConsume(op: string): bool {
        if hasError {
            return false
        }

        SkipWhitespace()
        if position + op.Length > text.Length {
            return false
        }

        index := 0
        while index < op.Length {
            if text[position + index] != op[index] {
                return false
            }

            index = index + 1
        }

        position = position + op.Length
        return true
    }

    func SetError(message: string) {
        if !hasError {
            hasError = true
            errorMessage = message
        }
    }
}
