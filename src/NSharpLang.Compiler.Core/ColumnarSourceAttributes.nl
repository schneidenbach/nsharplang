namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler

// Preserve the positional string/no-argument metadata slice independently of compiler markers.
// Names bind through the declaration's semantic scope; no framework or spelling whitelist.
class ColumnarSourceAttributeInput {
    Name: string
    Arguments: string[]

    constructor(name: string, arguments: string[]) {
        Name = name
        Arguments = arguments
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
        index += 1
        while index < end - 1 {
            if tokens.Kinds[index] != (int)TokenType.StringLiteral {
                return null
            }
            raw := source.Substring(tokens.Starts[index], tokens.ValueLengths[index])
            arguments.Add(StringLiteralDecoder.Decode(raw, false))
            index += 1
            if index == end - 1 {
                break
            }
            if tokens.Kinds[index] != (int)TokenType.Comma {
                return null
            }
            index += 1
        }
        return new ColumnarSourceAttributeInput(name, arguments.ToArray())
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

    static func Bind(attribute: ColumnarSourceAttributeInput, resolution: ColumnarSemanticTypeResolution): ConstructorInfo? {
        attributeType: Type = null
        for candidate in AnalyzerAttributeValidator.GetClrAttributeNameCandidates(attribute.Name) {
            resolved: Type = null
            if ColumnarCanonicalTypeResolver.TryResolveType(candidate, resolution.Enums, resolution.Structs, resolution.Unions, out resolved) && resolved != null && AnalyzerAttributeValidator.IsClrAttributeType(resolved) {
                attributeType = resolved
                break
            }
        }
        if attributeType == null {
            return null
        }
        for constructor in attributeType.GetConstructors() {
            parameters := constructor.GetParameters()
            if parameters.Length != attribute.Arguments.Length {
                continue
            }
            matches := true
            for parameter in parameters {
                if parameter.get_ParameterType() != typeof(string) {
                    matches = false
                }
            }
            if matches {
                return constructor
            }
        }
        return null
    }

    static func Blob(arguments: string[]): byte[] {
        bytes := new List<byte>()
        ColumnarAttributeBlobs.WritePrologue(bytes)
        for argument in arguments {
            ColumnarAttributeBlobs.WriteSerString(bytes, argument)
        }
        ColumnarAttributeBlobs.WriteNamedArgumentCount(bytes, 0)
        return bytes.ToArray()
    }

    static func ApplyType(target: TypeBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution) {
        if attributes == null {
            return
        }
        for attribute in attributes {
            constructor := Bind(attribute, resolution)
            if constructor != null {
                target.SetCustomAttribute(constructor, Blob(attribute.Arguments))
            }
        }
    }

    static func ApplyMethod(target: MethodBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution) {
        if attributes == null {
            return
        }
        for attribute in attributes {
            constructor := Bind(attribute, resolution)
            if constructor != null {
                target.SetCustomAttribute(constructor, Blob(attribute.Arguments))
            }
        }
    }

    static func ApplyParameter(target: ParameterBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution) {
        if attributes == null {
            return
        }
        for attribute in attributes {
            constructor := Bind(attribute, resolution)
            if constructor != null {
                target.SetCustomAttribute(constructor, Blob(attribute.Arguments))
            }
        }
    }
}
