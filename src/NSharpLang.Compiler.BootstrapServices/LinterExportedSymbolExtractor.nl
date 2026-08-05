namespace NSharpLang.Compiler

import System.Collections.Generic
import System.IO

class LinterExportedSymbolExtractor {
    static func Extract(filePath: string): List<string> {
        symbols := new List<string>()
        if string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath) {
            return symbols
        }

        try {
            source := File.ReadAllText(filePath)
            return ExtractFromSource(source, filePath)
        } catch {
            return symbols
        }
    }

    static func ExtractFromSource(source: string, filePath: string?): List<string> {
        symbols := new List<string>()
        tokens := new List<Token>()

        try {
            lexer := new Lexer(source, filePath)
            tokens = lexer.Tokenize()
        } catch {
            return symbols
        }

        braceDepth := 0
        index := 0
        while index < tokens.Count {
            token := tokens[index]

            if token.Type == TokenType.LeftBrace {
                braceDepth = braceDepth + 1
                index = index + 1
                continue
            }

            if token.Type == TokenType.RightBrace {
                if braceDepth > 0 {
                    braceDepth = braceDepth - 1
                }

                index = index + 1
                continue
            }

            if braceDepth == 0 && IsDeclarationKeyword(token.Type) {
                nameIndex := FindDeclaredNameIndex(tokens, index)
                if nameIndex >= 0 {
                    AddIfDistinct(symbols, tokens[nameIndex].Value)
                    index = nameIndex + 1
                    continue
                }
            }

            index = index + 1
        }

        return symbols
    }

    static func IsDeclarationKeyword(tokenType: TokenType): bool {
        return tokenType == TokenType.Class || tokenType == TokenType.Struct || tokenType == TokenType.Record || tokenType == TokenType.Interface || tokenType == TokenType.Enum || tokenType == TokenType.Union || tokenType == TokenType.Func || tokenType == TokenType.Type
    }

    static func FindDeclaredNameIndex(tokens: List<Token>, declarationIndex: int): int {
        declarationType := tokens[declarationIndex].Type
        scan := declarationIndex + 1

        while scan < tokens.Count {
            token := tokens[scan]
            if token.Type == TokenType.Newline {
                scan = scan + 1
                continue
            }

            if declarationType == TokenType.Record && token.Type == TokenType.Struct {
                scan = scan + 1
                continue
            }

            if declarationType == TokenType.Func {
                if token.Type == TokenType.Star {
                    scan = scan + 1
                    continue
                }

                if token.Type == TokenType.Operator {
                    return -1
                }
            }

            if token.Type == TokenType.Identifier {
                return scan
            }

            return -1
        }

        return -1
    }

    static func AddIfDistinct(symbols: List<string>, name: string) {
        if string.IsNullOrWhiteSpace(name) || name == "<error>" {
            return
        }

        if !symbols.Contains(name) {
            symbols.Add(name)
        }
    }
}
