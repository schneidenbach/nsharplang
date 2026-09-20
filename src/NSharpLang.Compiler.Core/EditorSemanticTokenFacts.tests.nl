namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR WHAT THE EDITOR PAINTS. These came out of `SemanticTokensHandler.cs`, where they
// were reachable only by reflecting into `internal` members of a referenced assembly: the ORDER of
// the identifier rules, the icon a declared kind gets, the three reasons a classified token is
// still not emitted, the re-lexing of an interpolated literal's holes, and the token-stream count
// that finds the Go-style error capture.
func EstSet(values: string[]): HashSet<string> {
    set := new HashSet<string>()
    for value in values {
        set.Add(value)
    }
    return set
}

func EstKinds(names: string[], kinds: string[]): Dictionary<string, string> {
    map := new Dictionary<string, string>()
    index := 0
    while index < names.Length {
        map[names[index]] = kinds[index]
        index = index + 1
    }
    return map
}

func EstToken(kind: TokenType, value: string, line: int, column: int): Token {
    return new Token(kind, value, line, column, "Probe.nl", true)
}

func EstTokens(tokens: Token[]): List<Token> {
    list := new List<Token>()
    for token in tokens {
        list.Add(token)
    }
    return list
}

func EstIdentifier(name: string): Token {
    return EstToken(TokenType.Identifier, name, 1, 1)
}

func EstClassify(token: Token, typeNames: string[], kinds: Dictionary<string, string>, functionNames: string[], parameterNames: string[], propertyNames: string[], enumMemberNames: string[]): string? {
    return EditorSemanticTokenFacts.Classify(
        token,
        null,
        EstSet(typeNames),
        kinds,
        EstSet(functionNames),
        EstSet(parameterNames),
        EstSet(propertyNames),
        EstSet(enumMemberNames),
        new HashSet<string>()
    )
}

func EstEmptyKinds(): Dictionary<string, string> {
    return new Dictionary<string, string>()
}

// THE ORDER OF THE IDENTIFIER RULES IS THE ANSWER. A name that is in several sets at once is
// painted by the FIRST rule that matches, and this row pins that order: built-in spelling, enum
// member, declared type, function, parameter, property.
test "a semantic token's identifier rules are asked in one fixed order" {
    everywhere := ["shared"]
    assert EstClassify(EstIdentifier("shared"), everywhere, EstEmptyKinds(), everywhere, everywhere, everywhere, everywhere) == EditorSemanticTokenFacts.EnumMemberKind
    assert EstClassify(EstIdentifier("shared"), everywhere, EstEmptyKinds(), everywhere, everywhere, everywhere, []) == EditorSemanticTokenFacts.TypeKind
    assert EstClassify(EstIdentifier("shared"), [], EstEmptyKinds(), everywhere, everywhere, everywhere, []) == EditorSemanticTokenFacts.FunctionKind
    assert EstClassify(EstIdentifier("shared"), [], EstEmptyKinds(), [], everywhere, everywhere, []) == EditorSemanticTokenFacts.ParameterKind
    assert EstClassify(EstIdentifier("shared"), [], EstEmptyKinds(), [], [], everywhere, []) == EditorSemanticTokenFacts.PropertyKind

    // A BUILT-IN SPELLING BEATS EVERYTHING, and the membership is the analyzer's, not a copy.
    assert EstClassify(EstIdentifier("int"), everywhere, EstEmptyKinds(), everywhere, everywhere, everywhere, everywhere) == EditorSemanticTokenFacts.TypeKind
}

// AN IDENTIFIER NOTHING RECOGNISES IS NOT PAINTED. The grammar beneath keeps its colour; painting
// it "variable" would override that with a guess.
test "a semantic token is not emitted for an identifier nothing recognises" {
    assert EstClassify(EstIdentifier("mystery"), [], EstEmptyKinds(), [], [], [], []) == null
    assert EstClassify(EstToken(TokenType.LeftParen, "(", 1, 1), [], EstEmptyKinds(), [], [], [], []) == null
}

// A RECORD IS A CLASS AND A UNION IS AN ENUM, because that is what they are to a reader. A kind
// the table does not describe, and a kind that is not a type at all, are painted as a plain type
// rather than mis-iconed.
test "a semantic token paints a record as a class and a union as an enum" {
    kinds := EstKinds(
        ["Greeter", "Options", "Pair", "Mood", "Shape", "IGreeter", "run"],
        ["Class", "Record", "Struct", "Enum", "Union", "Interface", "Function"]
    )
    names := ["Greeter", "Options", "Pair", "Mood", "Shape", "IGreeter", "run", "Unlisted"]

    assert EstClassify(EstIdentifier("Greeter"), names, kinds, [], [], [], []) == EditorSemanticTokenFacts.ClassKind
    assert EstClassify(EstIdentifier("Options"), names, kinds, [], [], [], []) == EditorSemanticTokenFacts.ClassKind
    assert EstClassify(EstIdentifier("Pair"), names, kinds, [], [], [], []) == EditorSemanticTokenFacts.StructKind
    assert EstClassify(EstIdentifier("Mood"), names, kinds, [], [], [], []) == EditorSemanticTokenFacts.EnumKind
    assert EstClassify(EstIdentifier("Shape"), names, kinds, [], [], [], []) == EditorSemanticTokenFacts.EnumKind
    assert EstClassify(EstIdentifier("IGreeter"), names, kinds, [], [], [], []) == EditorSemanticTokenFacts.InterfaceKind
    assert EstClassify(EstIdentifier("run"), names, kinds, [], [], [], []) == EditorSemanticTokenFacts.TypeKind
    assert EstClassify(EstIdentifier("Unlisted"), names, kinds, [], [], [], []) == EditorSemanticTokenFacts.TypeKind
}

// AN INTERPOLATED LITERAL IS NOT A STRING TO THIS FEATURE. Its holes are code, so the literal is
// skipped and the grammar beneath keeps the quotes.
test "a semantic token skips an interpolated literal and re-lexes its holes" {
    interpolated := EstToken(TokenType.StringLiteral, "$\"hi {name} and {count}\"", 3, 5)
    plain := EstToken(TokenType.StringLiteral, "\"hi\"", 3, 5)

    assert EstClassify(plain, [], EstEmptyKinds(), [], [], [], []) == EditorSemanticTokenFacts.StringKind
    assert EstClassify(interpolated, [], EstEmptyKinds(), [], [], [], []) == null
    assert EditorSemanticTokenFacts.IsInterpolatedStringLiteral(interpolated)
    assert !EditorSemanticTokenFacts.IsInterpolatedStringLiteral(plain)

    holes := EditorSemanticTokenFacts.InterpolationTokens(interpolated)
    assert holes.Count == 2
    assert holes[0].Value == "name"
    assert holes[0].Line == 3
    assert holes[1].Value == "count"
    assert holes[1].Line == 3
    assert holes[1].Column > holes[0].Column

    // A literal that is not interpolated has no holes to re-lex.
    assert EditorSemanticTokenFacts.InterpolationTokens(plain).Count == 0
}

// THREE THINGS KEEP A CLASSIFIED TOKEN OFF THE SCREEN: a position the lexer could not place, a
// zero-width token, and a token that spans lines — the protocol's semantic tokens cannot.
test "a semantic token row is withheld for an unplaced, empty or multi-line token" {
    tokens := EstTokens([
        EstToken(TokenType.Comment, "// fine", 2, 3),
        EstToken(TokenType.Comment, "// unplaced", 0, 3),
        EstToken(TokenType.Comment, "// unplaced", 2, 0),
        EstToken(TokenType.Comment, "", 4, 1),
        EstToken(TokenType.MultiLineComment, "/* two\nlines */", 5, 1)
    ])

    rows := EditorSemanticTokenFacts.TokenRows(tokens, null, null, EstSet([]), EstEmptyKinds(), EstSet([]), EstSet([]), EstSet([]))
    assert rows.Count == 1
    assert rows[0].Line == 1
    assert rows[0].Character == 2
    assert rows[0].Length == 7
    assert rows[0].Kind == EditorSemanticTokenFacts.CommentKind
    assert !rows[0].IsCatchResult

    assert EditorSemanticTokenFacts.TokenRows(null, null, null, EstSet([]), EstEmptyKinds(), EstSet([]), EstSet([]), EstSet([])).Count == 0
}

// A KEYWORD, AN OPERATOR AND A NUMBER ARE ANSWERED BY THEIR OWNERS' MEMBERSHIPS, not by tables
// kept here that could drift from the lexer and the parser.
test "a semantic token asks the lexer and the parser what a token is" {
    assert EstClassify(EstToken(TokenType.Func, "func", 1, 1), [], EstEmptyKinds(), [], [], [], []) == EditorSemanticTokenFacts.KeywordKind
    assert EstClassify(EstToken(TokenType.IntLiteral, "42", 1, 1), [], EstEmptyKinds(), [], [], [], []) == EditorSemanticTokenFacts.NumberKind
    assert EstClassify(EstToken(TokenType.FloatLiteral, "4.2", 1, 1), [], EstEmptyKinds(), [], [], [], []) == EditorSemanticTokenFacts.NumberKind
    assert EstClassify(EstToken(TokenType.Plus, "+", 1, 1), [], EstEmptyKinds(), [], [], [], []) == EditorSemanticTokenFacts.OperatorKind
    assert EstClassify(EstToken(TokenType.XmlDocComment, "/// note", 1, 1), [], EstEmptyKinds(), [], [], [], []) == EditorSemanticTokenFacts.CommentKind
    assert EstClassify(EstToken(TokenType.TripleQuoteStringLiteral, "\"\"\"x\"\"\"", 1, 1), [], EstEmptyKinds(), [], [], [], []) == EditorSemanticTokenFacts.StringKind
}

// A PARAMETER IS A TOP-LEVEL FUNCTION'S PARAMETER AND NOTHING ELSE. A method's parameters are not
// collected, which is the shipped answer and the reason a method body paints its own parameters
// only when a top-level function happens to share the name.
test "a semantic token's parameter set holds only top-level function parameters" {
    parameters := new List<Parameter>()
    parameters.Add(new Parameter("amount", new SimpleTypeReference("int", 1, 1), null, false, ParameterModifier.None, new List<AttributeNode>(), 1, 1))
    topLevel: Declaration = new FunctionDeclaration("run", parameters, null, null, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 1, 1)

    methodParameters := new List<Parameter>()
    methodParameters.Add(new Parameter("hidden", new SimpleTypeReference("int", 1, 1), null, false, ParameterModifier.None, new List<AttributeNode>(), 5, 1))
    method: Declaration = new FunctionDeclaration("Area", methodParameters, null, null, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 5, 5)
    members := new List<Declaration>()
    members.Add(method)
    owner: Declaration = new ClassDeclaration("Box", null, null, new List<TypeReference>(), members, null, Modifiers.None, new List<AttributeNode>(), 4, 1)

    declarations := new List<Declaration>()
    declarations.Add(topLevel)
    declarations.Add(owner)
    unit := new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)

    names := EditorSemanticTokenFacts.ParameterNames(unit)
    assert names.Contains("amount")
    assert !names.Contains("hidden")
    assert EditorSemanticTokenFacts.ParameterNames(null).Count == 0
}

// A BINDING IS IDENTIFIED BY WHERE IT IS WRITTEN, not by its spelling — an ordinary local called
// `err` must not be painted as a captured error.
test "a semantic token marks a catch result by position and not by name" {
    marked := new HashSet<string>()
    marked.Add(EditorSemanticTokenFacts.BindingKey(7, 12, "err"))

    here := EstToken(TokenType.Identifier, "err", 7, 12)
    elsewhere := EstToken(TokenType.Identifier, "err", 9, 12)

    assert EditorSemanticTokenFacts.IsCatchResultBinding(here, marked)
    assert !EditorSemanticTokenFacts.IsCatchResultBinding(elsewhere, marked)

    assert EditorSemanticTokenFacts.Classify(here, null, EstSet([]), EstEmptyKinds(), EstSet([]), EstSet([]), EstSet([]), EstSet([]), marked) == EditorSemanticTokenFacts.VariableKindName
    assert EditorSemanticTokenFacts.Classify(elsewhere, null, EstSet([]), EstEmptyKinds(), EstSet([]), EstSet([]), EstSet([]), EstSet([]), marked) == null
}
