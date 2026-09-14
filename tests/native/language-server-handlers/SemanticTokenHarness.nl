namespace NSharpLang.LanguageServerHandlers.Tests

import System
import System.Collections.Generic
import System.Reflection
import Microsoft.Extensions.Logging.Abstractions
import NSharpLang.Compiler
import NSharpLang.LanguageServer.Handlers
import NSharpLang.LanguageServer.Models
import NSharpLang.LanguageServer.Services

// ---------------------------------------------------------------------------
// Semantic token classification.
//
// SemanticTokensHandler exposes its classification helpers as `internal`
// members (the C# suite reached them through InternalsVisibleTo). N# cannot
// bind an internal member of a referenced assembly directly, so these rows
// drive the same members through reflection. They are still the handler's own
// classification surface, not private implementation detail of some other type.
// ---------------------------------------------------------------------------
func LshPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func LshSemanticHandler(docs: DocumentManager): SemanticTokensHandler {
    return new SemanticTokensHandler(docs, NullLogger<SemanticTokensHandler>.Instance)
}

func LshSemanticMethod(name: string, isStatic: bool): MethodInfo {
    flags := BindingFlags.Public | BindingFlags.NonPublic
    if isStatic {
        flags = flags | BindingFlags.Static
    } else {
        flags = flags | BindingFlags.Instance
    }
    method := typeof(SemanticTokensHandler).GetMethod(name, flags)
    if method == null {
        throw new InvalidOperationException("SemanticTokensHandler." + name + " was not found.")
    }
    return method
}

func LshSemanticStatic(name: string, doc: DocumentState): object {
    arguments := new object?[](1)
    LshPut(arguments, 0, doc)
    result := LshSemanticMethod(name, true).Invoke(null, arguments)
    if result == null {
        throw new InvalidOperationException("SemanticTokensHandler." + name + " returned null.")
    }
    return result
}

// The five name sets ClassifyToken consults, in the order it takes them.
func LshSemanticSets(doc: DocumentState): object?[] {
    sets := new object?[](5)
    LshPut(sets, 0, LshSemanticStatic("BuildTypeNameSet", doc))
    LshPut(sets, 1, LshSemanticStatic("BuildFunctionNameSet", doc))
    LshPut(sets, 2, LshSemanticStatic("BuildParameterNameSet", doc))
    LshPut(sets, 3, LshSemanticStatic("BuildPropertyNameSet", doc))
    LshPut(sets, 4, LshSemanticStatic("BuildEnumMemberNameSet", doc))
    return sets
}

func LshCatchResultBindings(doc: DocumentState): object {
    return LshSemanticStatic("BuildCatchResultBindingSet", doc)
}

func LshClassify(handler: SemanticTokensHandler, token: Token, doc: DocumentState, sets: object?[], bindings: object?): object? {
    arguments := new object?[](8)
    LshPut(arguments, 0, token)
    LshPut(arguments, 1, doc)
    LshPut(arguments, 2, sets[0])
    LshPut(arguments, 3, sets[1])
    LshPut(arguments, 4, sets[2])
    LshPut(arguments, 5, sets[3])
    LshPut(arguments, 6, sets[4])
    LshPut(arguments, 7, bindings)
    return LshSemanticMethod("ClassifyToken", false).Invoke(handler, arguments)
}

func LshTupleItem(classification: object, name: string): int {
    field := classification.GetType().GetField(name)
    if field == null {
        throw new InvalidOperationException("Classification tuple had no field " + name + ".")
    }
    value := field.GetValue(classification)
    if value == null {
        throw new InvalidOperationException("Classification tuple field " + name + " was null.")
    }
    return Convert.ToInt32(value)
}

func LshClassifiedTokenType(classification: object): int {
    return LshTupleItem(classification, "Item1")
}

func LshClassifiedModifiers(classification: object): int {
    return LshTupleItem(classification, "Item2")
}

func LshCatchResultModifierMask(): int {
    field := typeof(SemanticTokensHandler).GetField(
        "CatchResultModifierMask",
        BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic
    )
    if field == null {
        throw new InvalidOperationException("SemanticTokensHandler.CatchResultModifierMask was not found.")
    }
    value := field.GetValue(null)
    if value == null {
        throw new InvalidOperationException("SemanticTokensHandler.CatchResultModifierMask was null.")
    }
    return Convert.ToInt32(value)
}

func LshInterpolatedExpressionTokens(token: Token): List<Token> {
    arguments := new object?[](1)
    LshPut(arguments, 0, token)
    result := LshSemanticMethod("GetInterpolatedStringExpressionTokens", true).Invoke(null, arguments)
    if result == null {
        throw new InvalidOperationException("GetInterpolatedStringExpressionTokens returned null.")
    }
    items := result as IReadOnlyList<Token>
    if items == null {
        throw new InvalidOperationException("GetInterpolatedStringExpressionTokens did not return a token list.")
    }
    tokens := new List<Token>()
    index := 0
    while index < items.Count {
        tokens.Add(items[index])
        index = index + 1
    }
    return tokens
}

// ---------------------------------------------------------------------------
// Token helpers.
// ---------------------------------------------------------------------------

func LshDocumentTokens(doc: DocumentState): List<Token> {
    tokens := doc.Tokens
    if tokens == null {
        throw new InvalidOperationException("Document carried no token stream.")
    }
    return tokens
}

// Token kinds are matched by enum name: the columnar backend declines a direct
// `TokenType.X` member reference, and the name is the same claim.
func LshTokenTypeName(token: Token): string {
    name := token.Type.ToString()
    if name == null {
        throw new InvalidOperationException("Token type rendered as null.")
    }
    return name
}

func LshFirstTokenOfType(doc: DocumentState, tokenTypeName: string): Token {
    tokens := LshDocumentTokens(doc)
    index := 0
    while index < tokens.Count {
        if LshTokenTypeName(tokens[index]) == tokenTypeName {
            return tokens[index]
        }
        index = index + 1
    }
    throw new InvalidOperationException("No " + tokenTypeName + " token was found.")
}

func LshFirstInterpolatedStringToken(doc: DocumentState): Token {
    tokens := LshDocumentTokens(doc)
    index := 0
    while index < tokens.Count {
        token := tokens[index]
        if LshTokenTypeName(token) == "StringLiteral" {
            if token.Value.StartsWith("$\"", StringComparison.Ordinal) {
                return token
            }
        }
        index = index + 1
    }
    throw new InvalidOperationException("No interpolated string token was found.")
}

func LshSingleIdentifier(tokens: List<Token>, name: string): Token {
    found: Token? = null
    count := 0
    index := 0
    while index < tokens.Count {
        token := tokens[index]
        if LshTokenTypeName(token) == "Identifier" {
            if token.Value == name {
                found = token
                count = count + 1
            }
        }
        index = index + 1
    }
    if found == null || count != 1 {
        throw new InvalidOperationException(
            "Expected exactly one identifier token named " + name + ", found " + count.ToString() + "."
        )
    }
    return found
}

func LshIdentifiersOnLine(doc: DocumentState, name: string, line: int): List<Token> {
    tokens := LshDocumentTokens(doc)
    matches := new List<Token>()
    index := 0
    while index < tokens.Count {
        token := tokens[index]
        if LshTokenTypeName(token) == "Identifier" {
            if token.Value == name && token.Line == line {
                matches.Add(token)
            }
        }
        index = index + 1
    }
    // Order by column so the rows can reason about the deconstruction order.
    outer := 0
    while outer < matches.Count {
        inner := outer + 1
        while inner < matches.Count {
            if matches[inner].Column < matches[outer].Column {
                swap := matches[outer]
                matches[outer] = matches[inner]
                matches[inner] = swap
            }
            inner = inner + 1
        }
        outer = outer + 1
    }
    return matches
}

func LshSingleIdentifierOnLine(doc: DocumentState, name: string, line: int): Token {
    matches := LshIdentifiersOnLine(doc, name, line)
    if matches.Count != 1 {
        throw new InvalidOperationException(
            "Expected exactly one '" + name + "' identifier on line " + line.ToString() + ", found " + matches.Count.ToString() + "."
        )
    }
    return matches[0]
}

// ---------------------------------------------------------------------------
// Catch-result binding set assertions (the element type is internal).
// ---------------------------------------------------------------------------

func LshBindingCount(bindings: object): int {
    items := bindings as System.Collections.IEnumerable
    if items == null {
        throw new InvalidOperationException("Catch-result binding set was not enumerable.")
    }
    count := 0
    for item in items {
        count = count + 1
    }
    return count
}

func LshIntProperty(value: object, name: string): int {
    property := value.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Binding had no property " + name + ".")
    }
    raw := property.GetValue(value)
    if raw == null {
        throw new InvalidOperationException("Binding property " + name + " was null.")
    }
    return Convert.ToInt32(raw)
}

func LshTextProperty(value: object, name: string): string {
    property := value.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Binding had no property " + name + ".")
    }
    raw := property.GetValue(value)
    if raw == null {
        throw new InvalidOperationException("Binding property " + name + " was null.")
    }
    text := raw.ToString()
    if text == null {
        throw new InvalidOperationException("Binding property " + name + " rendered as null.")
    }
    return text
}

func LshBindingsContain(bindings: object, line: int, column: int, name: string): bool {
    items := bindings as System.Collections.IEnumerable
    if items == null {
        throw new InvalidOperationException("Catch-result binding set was not enumerable.")
    }
    for item in items {
        if LshIntProperty(item, "Line") == line && LshIntProperty(item, "Column") == column {
            if LshTextProperty(item, "Name") == name {
                return true
            }
        }
    }
    return false
}

func LshSetContains(set: object, value: string): bool {
    items := set as IEnumerable<string>
    if items == null {
        throw new InvalidOperationException("Name set was not a string collection.")
    }
    for item in items {
        if item == value {
            return true
        }
    }
    return false
}

func LshHasUrlInCommentTokens(doc: DocumentState, fragment: string): bool {
    tokens := doc.Tokens
    if tokens == null {
        return false
    }
    index := 0
    while index < tokens.Count {
        token := tokens[index]
        if LshTokenTypeName(token) == "Comment" {
            if token.Value.Contains(fragment, StringComparison.Ordinal) {
                return true
            }
        }
        index = index + 1
    }
    return false
}

func LshHasUrlInCommentTrivia(doc: DocumentState, fragment: string): bool {
    comments := doc.Comments
    if comments == null {
        return false
    }
    index := 0
    while index < comments.Count {
        if comments[index].Text.Contains(fragment, StringComparison.Ordinal) {
            return true
        }
        index = index + 1
    }
    return false
}

func LshHasSymbol(doc: DocumentState, name: string): bool {
    symbols := doc.Symbols
    if symbols == null {
        return false
    }
    return symbols.ContainsKey(name)
}
