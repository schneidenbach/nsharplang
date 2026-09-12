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
    // The positional arguments DECODED AS STRINGS. Empty unless every argument is a string literal,
    // because the blob writer only knows the string shapes; `IsStringArgumentList` is the witness.
    Arguments: string[]
    // Every argument EXACTLY AS WRITTEN, in source order, whatever its shape — an enum member access,
    // a `|` combination, a `Name = value` named argument. A pseudo-custom attribute's value never
    // reaches a blob, so this is where it is read from.
    ArgumentTexts: string[]
    // Is every argument a string literal? Only then can this attribute become a custom-attribute blob.
    IsStringArgumentList: bool

    constructor(name: string, arguments: string[], argumentTexts: string[]? = null, isStringArgumentList: bool = true) {
        Name = name
        Arguments = arguments
        ArgumentTexts = argumentTexts ?? arguments
        IsStringArgumentList = isStringArgumentList
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

        // EVERY argument is kept as source text; the STRING ones are also decoded. The split is on
        // top-level commas only, so a nested call, index or initializer inside an argument stays one
        // argument. An argument is a string argument when it is exactly one string-literal token.
        texts := new List<string>()
        allStrings := true
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
                if !AppendArgument(source, tokens, argumentStart, index, texts, arguments, ref allStrings) {
                    return null
                }
                argumentStart = index + 1
            }
            index += 1
        }
        if !AppendArgument(source, tokens, argumentStart, close, texts, arguments, ref allStrings) {
            return null
        }

        if !allStrings {
            arguments.Clear()
        }
        return new ColumnarSourceAttributeInput(name, arguments.ToArray(), texts.ToArray(), allStrings)
    }

    // One argument, from `start` up to (not including) `end`. False means the range is empty, which
    // is a malformed argument list rather than an argument this owner merely cannot decode.
    static func AppendArgument(source: string, tokens: ParserDeclarationTokenTable, start: int, end: int, texts: List<string>, arguments: List<string>, ref allStrings: bool): bool {
        if start >= end {
            return false
        }

        textStart := tokens.Starts[start]
        textEnd := tokens.Starts[end - 1] + tokens.ValueLengths[end - 1]
        texts.Add(source.Substring(textStart, textEnd - textStart))
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

    static func Bind(attribute: ColumnarSourceAttributeInput, resolution: ColumnarSemanticTypeResolution): ConstructorInfo? {
        // A PSEUDO-CUSTOM ATTRIBUTE HAS NO BLOB. `MethodImpl` is stored in the method definition
        // row's implementation flags (`ColumnarMethodImplAttributes`), exactly as the C# compiler
        // stores it, and writing it here as well would put a row in the CustomAttribute table that a
        // C#-compiled assembly does not have — visible to every `GetCustomAttributesData()` caller.
        if ColumnarMethodImplAttributes.IsMethodImplAttribute(attribute, resolution) {
            return null
        }

        // An argument this owner could not decode as a string is an argument it cannot write, and a
        // constructor chosen on arity alone would be handed the WRONG blob.
        if !attribute.IsStringArgumentList {
            return null
        }

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
