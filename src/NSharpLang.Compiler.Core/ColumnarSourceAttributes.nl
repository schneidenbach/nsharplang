namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler

// ONE ATTRIBUTE AS WRITTEN ON A DECLARATION.
//
// THE SAME ATTRIBUTE IS READ THREE WAYS AND ALL THREE ARE KEPT, because three different owners ask
// three different questions of it and no one answer serves all three.
//
// `ArgumentTexts` is every argument EXACTLY AS WRITTEN, in source order. A pseudo-custom attribute —
// `[MethodImpl]` — never becomes a blob at all; its value is written into the method definition
// row's implementation flags, and the owner that does that reads the text.
//
// `Arguments` is the positional arguments decoded as STRINGS, and `IsStringArgumentList` is the
// witness that every one of them was a string literal. This is the shape the compiler's own
// `[Trait]`/`[Fact]` rows are written from, where the constructor is known and the values are known
// to be strings.
//
// `ArgumentSyntax` is every argument as a CONSTANT SHAPE, and `IsDecodable` the witness that the whole
// list was readable. This is what an ordinary user-written attribute is bound and encoded from, where
// neither the constructor nor the argument types are known until the attribute type resolves.
class ColumnarSourceAttributeInput {
    Name: string
    Arguments: string[]
    ArgumentTexts: string[]
    IsStringArgumentList: bool
    ArgumentSyntax: List<ColumnarAttributeArgumentSyntax>
    IsDecodable: bool

    constructor(name: string, arguments: string[], argumentTexts: string[]? = null, isStringArgumentList: bool = true) {
        Name = name
        Arguments = arguments
        ArgumentTexts = argumentTexts ?? arguments
        IsStringArgumentList = isStringArgumentList
        ArgumentSyntax = new List<ColumnarAttributeArgumentSyntax>()
        IsDecodable = true
    }
}

class ColumnarSourceAttributes {
    static func Read(source: string, kinds: int[], starts: int[], lengths: int[], declarationIndex: int): ColumnarSourceAttributeInput[] {
        tokens := new ParserDeclarationTokenTable(kinds, starts, lengths)
        previous := TopLevelFunctionPreamblePreviousToken(tokens, declarationIndex - 1)
        result := new List<ColumnarSourceAttributeInput>()
        index := previous + 1
        while index < declarationIndex {
            if kinds[index] != (int)TokenType.LeftBracket {
                index += 1
                continue
            }
            close := index + 1
            depth := 1
            while close < declarationIndex && depth > 0 {
                if kinds[close] == (int)TokenType.LeftBracket {
                    depth += 1
                }
                if kinds[close] == (int)TokenType.RightBracket {
                    depth -= 1
                }
                close += 1
            }
            if depth != 0 {
                break
            }
            attribute := ReadOne(source, tokens, index + 1, close - 1)
            if attribute != null {
                result.Add(attribute)
            }
            index = close
        }
        return result.ToArray()
    }

    static func ReadOne(source: string, tokens: ParserDeclarationTokenTable, start: int, end: int): ColumnarSourceAttributeInput? {
        if start >= end || tokens.Kinds[start] != (int)TokenType.Identifier {
            return null
        }
        name := source.Substring(tokens.Starts[start], tokens.ValueLengths[start])
        index := start + 1
        while index + 1 < end && tokens.Kinds[index] == (int)TokenType.Dot && tokens.Kinds[index + 1] == (int)TokenType.Identifier {
            name += "." + source.Substring(tokens.Starts[index + 1], tokens.ValueLengths[index + 1])
            index += 2
        }
        arguments := new List<string>()
        if index == end {
            return new ColumnarSourceAttributeInput(name, arguments.ToArray())
        }
        if tokens.Kinds[index] != (int)TokenType.LeftParen || tokens.Kinds[end - 1] != (int)TokenType.RightParen {
            return null
        }

        open := index
        close := end - 1
        if open + 1 == close {
            return new ColumnarSourceAttributeInput(name, arguments.ToArray())
        }

        // EVERY argument is kept as source text; the STRING ones are also decoded, and every one is
        // read into a constant shape. The split is on top-level commas only, so a nested call, index
        // or initializer inside an argument stays one argument. An argument is a string argument when
        // it is exactly one string-literal token.
        texts := new List<string>()
        syntax := new List<ColumnarAttributeArgumentSyntax>()
        allStrings := true
        allDecodable := true
        argumentStart := open + 1
        depth := 0
        index = open + 1
        while index < close {
            kind := tokens.Kinds[index]
            if kind == (int)TokenType.LeftParen || kind == (int)TokenType.LeftBracket || kind == (int)TokenType.LeftBrace {
                depth += 1
            }
            if kind == (int)TokenType.RightParen || kind == (int)TokenType.RightBracket || kind == (int)TokenType.RightBrace {
                depth -= 1
            }
            if depth == 0 && kind == (int)TokenType.Comma {
                if !AppendArgument(source, tokens, argumentStart, index, texts, arguments, syntax, ref allStrings, ref allDecodable) {
                    return null
                }
                argumentStart = index + 1
            }
            index += 1
        }
        if !AppendArgument(source, tokens, argumentStart, close, texts, arguments, syntax, ref allStrings, ref allDecodable) {
            return null
        }

        if !allStrings {
            arguments.Clear()
        }
        input := new ColumnarSourceAttributeInput(name, arguments.ToArray(), texts.ToArray(), allStrings)
        input.ArgumentSyntax = syntax
        input.IsDecodable = allDecodable
        return input
    }

    // One argument, from `start` up to (not including) `end`. False means the range is empty, which
    // is a malformed argument list rather than an argument this owner merely cannot decode.
    static func AppendArgument(source: string, tokens: ParserDeclarationTokenTable, start: int, end: int, texts: List<string>, arguments: List<string>, syntax: List<ColumnarAttributeArgumentSyntax>, ref allStrings: bool, ref allDecodable: bool): bool {
        if start >= end {
            return false
        }

        textStart := tokens.Starts[start]
        textEnd := tokens.Starts[end - 1] + tokens.ValueLengths[end - 1]
        texts.Add(source.Substring(textStart, textEnd - textStart))
        parsed: ColumnarAttributeArgumentSyntax = null
        if ColumnarAttributeArgumentReader.TryRead(source, tokens, start, end, out parsed) {
            syntax.Add(parsed)
        } else {
            allDecodable = false
        }

        if end - start == 1 && tokens.Kinds[start] == (int)TokenType.StringLiteral {
            raw := source.Substring(tokens.Starts[start], tokens.ValueLengths[start])
            arguments.Add(StringLiteralDecoder.Decode(raw, false))
            return true
        }

        allStrings = false
        return true
    }

    static func ReadParameters(source: string, kinds: int[], starts: int[], lengths: int[], functionIndex: int, count: int): ColumnarSourceAttributeInput[][] {
        result := new ColumnarSourceAttributeInput[][](count)
        index := functionIndex + 1
        while index < kinds.Length && kinds[index] != (int)TokenType.LeftParen {
            index += 1
        }
        depth := 1
        brackets := 0
        parameter := 0
        index += 1
        while index < kinds.Length && depth > 0 && parameter < count {
            kind := kinds[index]
            if kind == (int)TokenType.LeftBracket {
                brackets += 1
            }
            if kind == (int)TokenType.RightBracket {
                brackets -= 1
            }
            if kind == (int)TokenType.LeftParen {
                depth += 1
            }
            if kind == (int)TokenType.RightParen {
                depth -= 1
            }
            if depth == 1 && brackets == 0 && kind == (int)TokenType.Identifier && index + 1 < kinds.Length && kinds[index + 1] == (int)TokenType.Colon {
                result[parameter] = Read(source, kinds, starts, lengths, index)
                parameter += 1
            }
            index += 1
        }
        return result
    }
}
