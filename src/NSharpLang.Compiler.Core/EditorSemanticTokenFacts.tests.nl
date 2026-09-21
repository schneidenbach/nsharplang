namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

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

// ── The tables the classification consults, read off the source ──────────
//
// The editor used to build these five in C#, out of the dictionaries it keeps per document. They
// are the same walk over the same symbol table, so they belong beside the classification that
// reads them — and unlike the handler's copies they can be asserted here.
func EstSourceUnit(source: string): CompilationUnit? {
    return ColumnarParserRecovery.ParseFileAst(source, "paint.nl").CompilationUnit
}

test "the source type-name table names every declared type and the analyzer's catalog" {
    source := "namespace P\n\nclass Box {\n}\n\nstruct Vec {\n}\n\nrecord Point(X: int) {\n}\n\ninterface IShape {\n}\n\nenum Color {\n    Red\n}\n\nfunc Free(): int {\n    return 1\n}\n"
    names := EditorSemanticTokenFacts.SourceTypeNames(EstSourceUnit(source), source)

    assert names.Contains("Box")
    assert names.Contains("Vec")
    assert names.Contains("Point")
    assert names.Contains("IShape")
    assert names.Contains("Color")
    assert !names.Contains("Free")
}

test "the source kind map spells the editor's own kind words" {
    source := "namespace P\n\nclass Box {\n}\n\nenum Color {\n    Red\n}\n\nfunc Free(): int {\n    return 1\n}\n"
    kinds := EditorSemanticTokenFacts.SourceTypeKinds(EstSourceUnit(source), source)

    declared: string? = null
    assert kinds.TryGetValue("Box", out declared)
    assert declared == "Class"
    assert kinds.TryGetValue("Color", out declared)
    assert declared == "Enum"
    assert kinds.TryGetValue("Free", out declared)
    assert declared == "Function"

    assert EditorSemanticTokenFacts.KindName(EditorSymbolTableKind.Record) == "Record"
    assert EditorSemanticTokenFacts.KindName(EditorSymbolTableKind.Union) == "Union"
    assert EditorSemanticTokenFacts.KindName(EditorSymbolTableKind.Constructor) == "Constructor"
}

// A METHOD IS NOT IN THE FUNCTION TABLE. The symbol table lists a type's methods as that type's
// MEMBERS, and this table reads only its top-level entries — so inside a class a method name is
// painted as a function only when a top-level function or a bound model happens to share it. That
// is the shipped answer, pinned here rather than quietly widened.
test "the source function table holds top-level functions and not a type's methods" {
    source := "namespace P\n\nclass Box {\n    func Open(): int {\n        return 1\n    }\n}\n\nfunc Free(): int {\n    inner := 1\n    func Nested(): int {\n        return inner\n    }\n    return Nested()\n}\n"
    names := EditorSemanticTokenFacts.SourceFunctionNames(EstSourceUnit(source), source, null)

    assert names.Contains("Free")
    assert names.Contains("Nested")
    assert !names.Contains("Open")
    assert !names.Contains("Box")
}

test "the source member tables reach one level into a type" {
    source := "namespace P\n\nclass Box {\n    widthValue: int\n    Width: int => widthValue\n}\n\nenum Color {\n    Red,\n    Green\n}\n"
    unit := EstSourceUnit(source)

    properties := EditorSemanticTokenFacts.SourcePropertyNames(unit, source)
    members := EditorSemanticTokenFacts.SourceEnumMemberNames(unit, source)

    assert properties.Contains("Width")
    assert !properties.Contains("widthValue")
    assert members.Contains("Red")
    assert members.Contains("Green")
    assert !members.Contains("Width")
}

// THE SOURCE-DERIVED ROWS ARE THE SAME ROWS. The five tables the handler used to build by hand and
// the five this owner reads off the symbol table paint identically, token for token.
test "painting from the source alone agrees with painting from handed-in tables" {
    source := "namespace P\n\nclass Box {\n    Width: int\n}\n\nfunc Free(box: Box): int {\n    return box.Width\n}\n"
    unit := EstSourceUnit(source)
    tokens := new Lexer(source, "paint.nl").Tokenize()

    handed := EditorSemanticTokenFacts.TokenRows(
        tokens,
        unit,
        null,
        EditorSemanticTokenFacts.SourceTypeNames(unit, source),
        EditorSemanticTokenFacts.SourceTypeKinds(unit, source),
        EditorSemanticTokenFacts.SourceFunctionNames(unit, source, null),
        EditorSemanticTokenFacts.SourcePropertyNames(unit, source),
        EditorSemanticTokenFacts.SourceEnumMemberNames(unit, source)
    )
    derived := EditorSemanticTokenFacts.SourceTokenRows(tokens, unit, null, source)

    assert derived.Count == handed.Count
    assert derived.Count > 0

    index := 0
    while index < derived.Count {
        assert derived[index].Line == handed[index].Line
        assert derived[index].Character == handed[index].Character
        assert derived[index].Length == handed[index].Length
        assert derived[index].Kind == handed[index].Kind
        assert derived[index].IsCatchResult == handed[index].IsCatchResult
        index = index + 1
    }
}
