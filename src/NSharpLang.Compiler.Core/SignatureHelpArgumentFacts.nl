namespace NSharpLang.Compiler

import System
import System.Collections.Generic

class SignatureHelpCallContext {
    ReceiverName: string?
    MethodName: string
    IsConstructor: bool
    ArgumentText: string

    constructor(receiverName: string?, methodName: string, isConstructor: bool, argumentText: string) {
        ReceiverName = receiverName
        MethodName = methodName
        IsConstructor = isConstructor
        ArgumentText = argumentText
    }
}

// Cursor placement inside a call's argument list. The language server supplies the current text
// and the selected signature's rendered parameter labels. Argument boundaries come from the N#
// lexer and the parser kernel's generic-call/type-receiver lookahead, so comments and every string
// form are single tokens and `<` is nested only when the language grammar reads type arguments.
class SignatureHelpArgumentFacts {
    static func DeclarationReceiverName(receiverName: string, currentNamespace: string?): string {
        if receiverName == null {
            return ""
        }

        lexer := new Lexer(receiverName, "<signature-help-receiver>")
        raw := lexer.Tokenize()
        segments := new List<string>()
        genericDepth := 0
        for token in raw {
            if token.Type == TokenType.Less {
                genericDepth += 1
            } else if token.Type == TokenType.Greater {
                genericDepth -= 1
            } else if token.Type == TokenType.RightShift {
                genericDepth -= 2
            } else if genericDepth == 0 && token.Type == TokenType.Identifier {
                segments.Add(token.Value)
            }
        }
        if genericDepth != 0 || segments.Count == 0 {
            return receiverName.Trim()
        }

        declarationName := string.Join(".", segments)
        if String.IsNullOrEmpty(currentNamespace) {
            return declarationName
        }
        namespacePrefix := currentNamespace + "."
        if !declarationName.StartsWith(namespacePrefix, StringComparison.Ordinal) {
            return declarationName
        }
        localName := declarationName.Substring(namespacePrefix.Length)
        if localName.IndexOf('.') >= 0 {
            return declarationName
        }
        return localName
    }

    static func ActiveCallAtPosition(source: string, zeroBasedLine: int, character: int): SignatureHelpCallContext? {
        prefixLength := PrefixLengthAtPosition(source, zeroBasedLine, character)
        if prefixLength < 0 {
            return null
        }
        prefix := source.Substring(0, prefixLength)
        lexer := new Lexer(prefix, "<signature-help>")
        raw := lexer.Tokenize()
        tokens := new List<Token>()
        for token in raw {
            if token.Type != TokenType.Newline && token.Type != TokenType.Eof {
                tokens.Add(token)
            }
        }

        openParens := new List<int>()
        index := 0
        while index < tokens.Count {
            kind := tokens[index].Type
            if kind == TokenType.LeftParen {
                openParens.Add(index)
            } else if kind == TokenType.RightParen && openParens.Count > 0 {
                openParens.RemoveAt(openParens.Count - 1)
            }
            index += 1
        }
        if openParens.Count == 0 {
            return null
        }

        openIndex := openParens[openParens.Count - 1]
        calleeIndex := CalleeIdentifierIndex(tokens, openIndex)
        if calleeIndex < 0 {
            return null
        }
        methodName := tokens[calleeIndex].Value
        argumentStart := TokenOffset(prefix, tokens[openIndex]) + 1
        if argumentStart < 0 || argumentStart > prefix.Length {
            return null
        }
        argumentText := prefix.Substring(argumentStart)

        if calleeIndex > 0 && tokens[calleeIndex - 1].Type == TokenType.New {
            return new SignatureHelpCallContext(null, methodName, true, argumentText)
        }
        if calleeIndex < 2 || tokens[calleeIndex - 1].Type != TokenType.Dot {
            return new SignatureHelpCallContext(null, methodName, false, argumentText)
        }

        receiverEnd := calleeIndex - 2
        receiverStart := ReceiverSegmentStart(tokens, receiverEnd)
        if receiverStart < 0 {
            return new SignatureHelpCallContext(null, methodName, false, argumentText)
        }
        while receiverStart >= 2 && tokens[receiverStart - 1].Type == TokenType.Dot {
            precedingStart := ReceiverSegmentStart(tokens, receiverStart - 2)
            if precedingStart < 0 {
                break
            }
            receiverStart = precedingStart
        }
        startOffset := TokenOffset(prefix, tokens[receiverStart])
        dotOffset := TokenOffset(prefix, tokens[calleeIndex - 1])
        if startOffset < 0 || dotOffset <= startOffset {
            return null
        }
        receiverName := prefix.Substring(startOffset, dotOffset - startOffset).Trim()
        return new SignatureHelpCallContext(receiverName, methodName, false, argumentText)
    }

    static func ReceiverSegmentStart(tokens: List<Token>, segmentEnd: int): int {
        if segmentEnd < 0 {
            return -1
        }
        if tokens[segmentEnd].Type == TokenType.Identifier {
            return segmentEnd
        }
        return CalleeIdentifierIndex(tokens, segmentEnd + 1)
    }

    static func CalleeIdentifierIndex(tokens: List<Token>, openIndex: int): int {
        candidate := openIndex - 1
        if candidate >= 0 && tokens[candidate].Type == TokenType.Identifier {
            return candidate
        }
        if candidate < 0 || (tokens[candidate].Type != TokenType.Greater && tokens[candidate].Type != TokenType.RightShift) {
            return -1
        }

        parserTokens := ParserTokens(tokens)
        genericDepth := 0
        index := candidate
        while index >= 0 {
            kind := tokens[index].Type
            if kind == TokenType.Greater {
                genericDepth += 1
            } else if kind == TokenType.RightShift {
                genericDepth += 2
            } else if kind == TokenType.Less {
                genericDepth -= 1
                if genericDepth == 0 {
                    if index == 0 || tokens[index - 1].Type != TokenType.Identifier {
                        return -1
                    }
                    if !IsGenericCallTypeArgs(parserTokens, tokens.Count, index) && !IsGenericTypeReceiverArgs(parserTokens, tokens.Count, index) {
                        return -1
                    }
                    return index - 1
                }
            }
            index -= 1
        }
        return -1
    }

    static func PrefixLengthAtPosition(source: string, zeroBasedLine: int, character: int): int {
        if source == null || zeroBasedLine < 0 || character < 0 {
            return -1
        }
        line := 0
        lineStart := 0
        index := 0
        while index < source.Length && line < zeroBasedLine {
            if source[index] == '\n' {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        if line != zeroBasedLine {
            return -1
        }
        lineEnd := lineStart
        while lineEnd < source.Length && source[lineEnd] != '\n' {
            lineEnd += 1
        }
        return Math.Min(lineStart + character, lineEnd)
    }

    static func TokenOffset(source: string, token: Token): int {
        targetLine := token.Line
        line := 1
        lineStart := 0
        index := 0
        while index < source.Length && line < targetLine {
            if source[index] == '\n' {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        if line != targetLine {
            return -1
        }
        return lineStart + token.Column - 1
    }

    static func ActiveParameterIndex(argumentText: string, parameterLabels: string[]): int {
        tokens := LexArgumentTokens(argumentText)
        commaCount := 0
        lastComma := -1
        ScanTopLevelCommas(tokens, out commaCount, out lastComma)
        name := CurrentArgumentName(tokens, lastComma)
        if name == null {
            return commaCount
        }
        index := 0
        while index < parameterLabels.Length {
            label := parameterLabels[index]
            colon := label.IndexOf(':')
            candidate := colon >= 0 ? label.Substring(0, colon).Trim() : label.Trim()
            if String.Equals(candidate, name, StringComparison.Ordinal) {
                return index
            }
            index += 1
        }
        return commaCount
    }

    static func ArgumentCount(argumentText: string): int {
        if String.IsNullOrWhiteSpace(argumentText) {
            return 0
        }
        tokens := LexArgumentTokens(argumentText)
        count := 0
        last := -1
        ScanTopLevelCommas(tokens, out count, out last)
        return count + 1
    }

    static func LexArgumentTokens(argumentText: string): List<Token> {
        // The unmatched synthetic call paren keeps the lexer's indentation pass from inserting
        // block braces into a multi-line argument fragment. The two prefix tokens are skipped by
        // every consumer below.
        lexer := new Lexer("__signature(" + argumentText, "<signature-help>")
        raw := lexer.Tokenize()
        tokens := new List<Token>()
        index := 0
        while index < raw.Count {
            token := raw[index]
            if token.Type != TokenType.Newline && token.Type != TokenType.Eof {
                tokens.Add(token)
            }
            index += 1
        }
        return tokens
    }

    static func ParserTokens(tokens: List<Token>): ParserTokenTable {
        kinds := new int[](tokens.Count)
        starts := new int[](tokens.Count)
        lengths := new int[](tokens.Count)
        index := 0
        while index < tokens.Count {
            kinds[index] = Convert.ToInt32(tokens[index].Type)
            starts[index] = index
            lengths[index] = 1
            index += 1
        }
        return new ParserTokenTable(kinds, starts, lengths)
    }

    static func CurrentArgumentName(tokens: List<Token>, lastComma: int): string? {
        index := Math.Max(2, lastComma + 1)
        if index + 1 >= tokens.Count || tokens[index].Type != TokenType.Identifier || tokens[index + 1].Type != TokenType.Colon {
            return null
        }
        return tokens[index].Value
    }

    static func ScanTopLevelCommas(tokens: List<Token>, out count: int, out last: int) {
        count = 0
        last = -1
        parserTokens := ParserTokens(tokens)
        parenDepth := 0
        bracketDepth := 0
        braceDepth := 0
        genericDepth := 0
        index := 2
        while index < tokens.Count {
            kind := tokens[index].Type
            if kind == TokenType.Less && (IsGenericCallTypeArgs(parserTokens, tokens.Count, index) || IsGenericTypeReceiverArgs(parserTokens, tokens.Count, index)) {
                genericDepth += 1
            } else if kind == TokenType.Greater && genericDepth > 0 {
                genericDepth -= 1
            } else if kind == TokenType.RightShift && genericDepth > 0 {
                genericDepth = Math.Max(0, genericDepth - 2)
            } else if kind == TokenType.LeftParen {
                parenDepth += 1
            } else if kind == TokenType.RightParen && parenDepth > 0 {
                parenDepth -= 1
            } else if kind == TokenType.LeftBracket {
                bracketDepth += 1
            } else if kind == TokenType.RightBracket && bracketDepth > 0 {
                bracketDepth -= 1
            } else if kind == TokenType.LeftBrace {
                braceDepth += 1
            } else if kind == TokenType.RightBrace && braceDepth > 0 {
                braceDepth -= 1
            } else if kind == TokenType.Comma && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && genericDepth == 0 {
                count = count + 1
                last = index
            }
            index += 1
        }
    }
}
