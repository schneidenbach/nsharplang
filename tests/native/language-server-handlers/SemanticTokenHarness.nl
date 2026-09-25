namespace NSharpLang.LanguageServerHandlers.Tests

import System
import System.Collections.Generic
import System.Reflection
import Microsoft.Extensions.Logging.Abstractions
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Handlers
import NSharpLang.LanguageServer.Models
import NSharpLang.LanguageServer.Services

// ---------------------------------------------------------------------------
// Semantic token classification.
//
// The classification itself is `EditorSemanticTokenFacts`, which these rows
// bind directly, and so are the five symbol tables it consults -- the handler
// used to build those in C# out of the document's dictionaries, and they are
// now read off the same source the document was parsed from. What still needs
// reflection is the handler's own LEGEND -- the array whose ORDER is the
// promise the server made to the client, and which is `internal` -- so that a
// row can keep asserting the wire index a kind word lands on rather than only
// the word itself.
// ---------------------------------------------------------------------------
func LshPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func LshSemanticHandler(docs: DocumentManager): SemanticTokensHandler {
    return new SemanticTokensHandler(docs, NullLogger<SemanticTokensHandler>.Instance)
}

// The name sets and the kind map the classification consults. All six are the
// owner's now, read off the document's own compilation unit and text.
class LshNameSets {
    TypeNames: HashSet<string>
    TypeKinds: Dictionary<string, string>
    FunctionNames: HashSet<string>
    ParameterNames: HashSet<string>
    PropertyNames: HashSet<string>
    EnumMemberNames: HashSet<string>

    constructor(
        typeNames: HashSet<string>,
        typeKinds: Dictionary<string, string>,
        functionNames: HashSet<string>,
        parameterNames: HashSet<string>,
        propertyNames: HashSet<string>,
        enumMemberNames: HashSet<string>
    ) {
        TypeNames = typeNames
        TypeKinds = typeKinds
        FunctionNames = functionNames
        ParameterNames = parameterNames
        PropertyNames = propertyNames
        EnumMemberNames = enumMemberNames
    }
}

class LshClassification {
    TokenType: int
    Modifiers: int

    constructor(tokenType: int, modifiers: int) {
        TokenType = tokenType
        Modifiers = modifiers
    }
}

func LshSemanticSets(doc: DocumentState): LshNameSets {
    return new LshNameSets(
        EditorSemanticTokenFacts.SourceTypeNames(doc.CompilationUnit, doc.Text),
        EditorSemanticTokenFacts.SourceTypeKinds(doc.CompilationUnit, doc.Text),
        EditorSemanticTokenFacts.SourceFunctionNames(doc.CompilationUnit, doc.Text, doc.SemanticModel),
        EditorSemanticTokenFacts.ParameterNames(doc.CompilationUnit),
        EditorSemanticTokenFacts.SourcePropertyNames(doc.CompilationUnit, doc.Text),
        EditorSemanticTokenFacts.SourceEnumMemberNames(doc.CompilationUnit, doc.Text)
    )
}

func LshCatchResultBindings(doc: DocumentState): object {
    return EditorSemanticTokenFacts.CatchResultBindings(doc.CompilationUnit, LshDocumentTokens(doc))
}

func LshCatchResultSet(bindings: object?): HashSet<string> {
    resolved := bindings as HashSet<string>
    if resolved == null {
        return new HashSet<string>()
    }
    return resolved
}

// The kind word placed in the handler's legend -- the same lookup the handler
// itself does, so a row asserting an index is asserting the wire answer.
func LshLegendIndex(kind: string): int {
    field := typeof(SemanticTokensHandler).GetField(
        "TokenTypes",
        BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic
    )
    if field == null {
        throw new InvalidOperationException("SemanticTokensHandler.TokenTypes was not found.")
    }
    legend := field.GetValue(null) as string[]
    if legend == null {
        throw new InvalidOperationException("SemanticTokensHandler.TokenTypes was not a string array.")
    }
    index := 0
    while index < legend.Length {
        if legend[index] == kind {
            return index
        }
        index = index + 1
    }
    throw new InvalidOperationException("Kind '" + kind + "' is not in the legend.")
}

func LshClassify(token: Token, doc: DocumentState, sets: LshNameSets, bindings: object?): LshClassification? {
    catchResults := LshCatchResultSet(bindings)
    kind := EditorSemanticTokenFacts.Classify(
        token,
        doc.SemanticModel,
        sets.TypeNames,
        sets.TypeKinds,
        sets.FunctionNames,
        sets.ParameterNames,
        sets.PropertyNames,
        sets.EnumMemberNames,
        catchResults
    )
    if kind == null {
        return null
    }
    modifiers := 0
    if EditorSemanticTokenFacts.IsCatchResultBinding(token, catchResults) {
        modifiers = LshCatchResultModifierMask()
    }
    return new LshClassification(LshLegendIndex(kind), modifiers)
}

func LshClassifiedTokenType(classification: LshClassification): int {
    return classification.TokenType
}

func LshClassifiedModifiers(classification: LshClassification): int {
    return classification.Modifiers
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
    return EditorSemanticTokenFacts.InterpolationTokens(token)
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
// Catch-result binding set assertions.
//
// The owner keys a binding by WHERE it is written, so these read the set by the
// owner's own key rather than by reflecting over an element type.
// ---------------------------------------------------------------------------

func LshBindingCount(bindings: object): int {
    return LshCatchResultSet(bindings).Count
}

func LshBindingsContain(bindings: object, line: int, column: int, name: string): bool {
    return LshCatchResultSet(bindings).Contains(EditorSemanticTokenFacts.BindingKey(line, column, name))
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
