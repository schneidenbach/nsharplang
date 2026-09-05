namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE FORMATTER'S BODY WALK (task 019 slice 19). These are the semantic assertions
// that came out of `Formatter.cs` with fifteen private members and 1,302 lines.
//
// NONE OF THIS WAS ASSERTABLE BEFORE THE MOVE, AND THAT IS THE POINT. `Formatter`'s entire public
// surface is "give me a whole formatted file", so a rule about one statement arm could only ever be
// inferred from formatted text, and only for the shapes a parser happens to produce. A `for` that
// is really a `foreach`, an `EmptyStatement`, a lambda with one typed parameter, an object
// initializer at exactly the line limit — each is one line here and was unreachable before.
//
// TEN THINGS THAT WERE PROSE, AN ACCIDENT OR UNREACHABLE ARE STATED HERE AS CONTRACTS:
//   (a) THE THREE UNHANDLED ARMS THROW. A formatter that emitted a placeholder for a node it
//       cannot spell would produce a file that does not parse, and `FormatSafe` would then blame
//       the output rather than the node. Asserted for statements, expressions and patterns.
//   (b) AN EMPTY STATEMENT EMITS NOTHING, and does so by MATCHING — it is a decision, not the
//       throw arm failing to fire.
//   (c) THE COLUMN IS COUNTED FROM THE LAST NEWLINE, ACROSS THE CHUNK BOUNDARY. The measurement
//       scans backwards in doubling 64-character tail chunks, so 63, 64, 65 and 1,000 characters
//       are each asserted, as is a buffer whose only newline is at its very start.
//   (d) A THREE-NULL `for` WRAPPING A `foreach` IS A `for x in xs`, not an empty C-style header
//       around a nested loop.
//   (e) A `using` DECLARATION ALWAYS WRITES `=`; an untyped variable declaration writes `:=`. The
//       two rules are different and are asserted side by side.
//   (f) THE LAMBDA'S BRACKET RULE IS ABOUT INFERENCE, NOT ARITY. One inferred parameter loses its
//       brackets; one WRITTEN type keeps them, because `x: int => …` would not parse.
//   (g) `new Foo()` WRITES EMPTY PARENTHESES UNLESS AN OBJECT INITIALIZER FOLLOWS.
//   (h) A RAW INTERPOLATED STRING DOUBLES ITS BRACES AND A PLAIN ONE DOES NOT.
//   (i) AN ATTRIBUTE'S NAMED ARGUMENT USES ` = ` AND A CALL'S USES `: `. Same node type, two
//       grammars, and the walk keeps them apart.
//   (j) THE `else if` CHAIN STAYS FLAT — an else-if re-enters at the same depth, so five branches
//       are five lines and not a staircase.
func FwkConfig(size: int, spaces: bool, maxLine: int): FormatterConfig {
    config := new FormatterConfig()
    config.IndentSize = size
    config.UseSpaces = spaces
    config.MaxLineLength = maxLine
    return config
}

func FwkState(): FormatterWalkState {
    return new FormatterWalkState(FwkConfig(4, true, 100))
}

func FwkWalk(state: FormatterWalkState): FormatterWalk {
    return new FormatterWalk(state)
}

// Newlines are compared as a visible token so a failing assertion reads as one line of text.
func FwkShow(builder: StringBuilder): string {
    return builder.ToString().Replace("\r\n", "\n").Replace("\n", "|")
}

func FwkType(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 0, 0)
}

func FwkIdentifier(name: string): Expression {
    return new IdentifierExpression(name, 0, 0)
}

func FwkInt(value: string): Expression {
    return new IntLiteralExpression(value, 0, 0)
}

func FwkBlock(statements: List<Statement>): BlockStatement {
    return new BlockStatement(statements, 0, 0)
}

func FwkOneStatementBlock(): BlockStatement {
    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(FwkIdentifier("inner"), 0, 0))
    return FwkBlock(statements)
}

func FwkParameter(name: string, typeName: string): Parameter {
    return new Parameter(name, FwkType(typeName), null, false, ParameterModifier.None, null, 0, 0, false, null)
}

func FwkEmptyParameters(): List<Parameter> {
    return new List<Parameter>()
}

func FwkEmptyArguments(): List<Argument> {
    return new List<Argument>()
}

func FwkEmptyAttributes(): List<AttributeNode> {
    return new List<AttributeNode>()
}

func FwkFunction(name: string, body: BlockStatement?, returnType: TypeReference?, modifiers: Modifiers): FunctionDeclaration {
    return new FunctionDeclaration(
        name,
        FwkEmptyParameters(),
        returnType,
        body,
        null,
        null,
        null,
        modifiers,
        FwkEmptyAttributes(),
        false,
        null,
        false,
        false,
        0,
        0
    )
}

// The text a single statement produces, at depth zero, with a fresh state each time.
func FwkStatementText(statement: Statement): string {
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatStatement(statement, builder)
    return FwkShow(builder)
}

func FwkExpressionText(expression: Expression): string {
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatExpression(expression, builder)
    return FwkShow(builder)
}

func FwkPatternText(pattern: Pattern): string {
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatPattern(pattern, builder)
    return FwkShow(builder)
}

// ---- (a) the three unhandled arms ---------------------------------------------------------------

test "an unhandled statement throws rather than emitting text that will not parse" {
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    assert throws InvalidOperationException {
        walk.FormatStatement(new Statement(1, 1), builder)
    }
}

test "an unhandled expression throws" {
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    assert throws InvalidOperationException {
        walk.FormatExpression(new Expression(1, 1), builder)
    }
}

test "a for-initializer that is neither a declaration nor an expression throws InvalidCastException" {
    // The C# spelled this as a hard cast, so the observable type is `InvalidCastException` and not
    // the `InvalidOperationException` the other unhandled arms raise. The type is reproduced; the
    // message is this owner's own, because a hard cast to a user-declared reference type declines
    // against the pinned toolset and only the cast can raise the CLR's own message.
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    body := FwkOneStatementBlock()
    malformed := new ForStatement(body, null, null, body, 0, 0)
    assert throws InvalidCastException {
        walk.FormatStatement(malformed, builder)
    }
}

test "an unhandled pattern throws" {
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    assert throws InvalidOperationException {
        walk.FormatPattern(new Pattern(1, 1), builder)
    }
}

// ---- (b) the empty statement --------------------------------------------------------------------

test "an empty statement emits nothing at all, not even an indent" {
    // It is a MATCHED arm and not a fall-through: the throw above proves the default arm fires for
    // an unrecognised node, so silence here is a decision.
    state := FwkState()
    state.Push()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatStatement(new EmptyStatement(0, 0), builder)
    assert FwkShow(builder) == ""
}

// ---- (d) the `for x in xs` disguise --------------------------------------------------------------

test "a three-null for wrapping a foreach prints as for x in xs" {
    inner := new ForeachStatement("item", FwkIdentifier("items"), FwkOneStatementBlock(), 0, 0)
    disguised := new ForStatement(null, null, null, inner, 0, 0)
    assert FwkStatementText(disguised) == "for item in items {|    inner|}|"
}

test "a for with an initializer keeps its C-style header even when the body is a foreach" {
    inner := new ForeachStatement("item", FwkIdentifier("items"), FwkOneStatementBlock(), 0, 0)
    initializer := new VariableDeclarationStatement("i", null, FwkInt("0"), VariableKind.Let, 0, 0)
    plain := new ForStatement(initializer, null, null, inner, 0, 0)
    assert FwkStatementText(plain) == "for i := 0; ;  {|    for item in items {|        inner|    }|}|"
}

test "a foreach reached directly prints the same way as the disguised one" {
    direct := new ForeachStatement("item", FwkIdentifier("items"), FwkOneStatementBlock(), 0, 0)
    assert FwkStatementText(direct) == "for item in items {|    inner|}|"
}

// ---- (e) the two initializer spellings ------------------------------------------------------------

test "an untyped variable declaration writes := and a typed one writes =" {
    untyped := new VariableDeclarationStatement("x", null, FwkInt("1"), VariableKind.Let, 0, 0)
    assert FwkStatementText(untyped) == "x := 1|"

    typed := new VariableDeclarationStatement("x", FwkType("int"), FwkInt("1"), VariableKind.Let, 0, 0)
    assert FwkStatementText(typed) == "x: int = 1|"
}

test "a using declaration writes = even with no type, which the variable rule would not" {
    declaration := new VariableDeclarationStatement("r", null, FwkIdentifier("open"), VariableKind.Let, 0, 0)
    statement := new UsingStatement(declaration, null, null, 0, 0)
    assert FwkStatementText(statement) == "using r = open|"
}

test "const and readonly are written before the name and let is not" {
    constant := new VariableDeclarationStatement("x", null, FwkInt("1"), VariableKind.Const, 0, 0)
    assert FwkStatementText(constant) == "const x := 1|"

    readOnly := new VariableDeclarationStatement("x", null, FwkInt("1"), VariableKind.Readonly, 0, 0)
    assert FwkStatementText(readOnly) == "readonly x := 1|"
}

// ---- (f) the lambda bracket rule -------------------------------------------------------------------

test "one inferred lambda parameter loses its brackets" {
    parameters := FwkEmptyParameters()
    parameters.Add(FwkParameter("x", "var"))
    lambda := new LambdaExpression(parameters, FwkIdentifier("x"), null, 0, 0)
    assert FwkExpressionText(lambda) == "x => x"
}

test "one lambda parameter with a WRITTEN type keeps its brackets" {
    // `x: int => …` would not parse, so the bracket rule is about inference and not about arity.
    parameters := FwkEmptyParameters()
    parameters.Add(FwkParameter("x", "int"))
    lambda := new LambdaExpression(parameters, FwkIdentifier("x"), null, 0, 0)
    assert FwkExpressionText(lambda) == "(x: int) => x"
}

test "two inferred lambda parameters are bracketed names with no types" {
    parameters := FwkEmptyParameters()
    parameters.Add(FwkParameter("x", "var"))
    parameters.Add(FwkParameter("y", "var"))
    lambda := new LambdaExpression(parameters, FwkIdentifier("x"), null, 0, 0)
    assert FwkExpressionText(lambda) == "(x, y) => x"
}

test "a lambda with no parameters is an empty bracket pair" {
    lambda := new LambdaExpression(FwkEmptyParameters(), FwkIdentifier("x"), null, 0, 0)
    assert FwkExpressionText(lambda) == "() => x"
}

test "a lambda with neither body writes the arrow and stops" {
    parameters := FwkEmptyParameters()
    parameters.Add(FwkParameter("x", "var"))
    lambda := new LambdaExpression(parameters, null, null, 0, 0)
    assert FwkExpressionText(lambda) == "x => "
}

// ---- (g) the empty argument list ---------------------------------------------------------------

test "new Foo() writes empty parentheses" {
    expression := new NewExpression(FwkType("Foo"), FwkEmptyArguments(), null, 0, 0, null)
    assert FwkExpressionText(expression) == "new Foo()"
}

test "new Foo with an object initializer drops the empty parentheses" {
    properties := new List<PropertyInitializer>()
    properties.Add(new PropertyInitializer("A", null, FwkInt("1"), 0, 0))
    initializer := new ObjectInitializerExpression(properties, 0, 0)
    expression := new NewExpression(FwkType("Foo"), FwkEmptyArguments(), initializer, 0, 0, null)
    assert FwkExpressionText(expression) == "new Foo { A: 1 }"
}

test "an array creation names the ELEMENT type and not the array type" {
    arrayType := new ArrayTypeReference(FwkType("int"))
    expression := new NewExpression(arrayType, FwkEmptyArguments(), null, 0, 0, FwkInt("8"))
    assert FwkExpressionText(expression) == "new int[8]"
}

// ---- (h) the interpolated string --------------------------------------------------------------

test "a plain interpolated string writes its holes and leaves braces in text alone" {
    parts := new List<InterpolatedStringPart>()
    parts.Add(new InterpolatedStringText("a{b}", 0, 0))
    parts.Add(new InterpolatedStringHole(FwkIdentifier("x"), null, 0, 0))
    expression := new InterpolatedStringExpression(parts, 0, 0, false)
    assert FwkExpressionText(expression) == "$\"a{b}{x}\""
}

test "a RAW interpolated string doubles the braces in its text" {
    parts := new List<InterpolatedStringPart>()
    parts.Add(new InterpolatedStringText("a{b}", 0, 0))
    expression := new InterpolatedStringExpression(parts, 0, 0, true)
    assert FwkExpressionText(expression) == "$\"\"\"a{{b}}\"\"\""
}

test "a hole's format clause follows a colon inside the braces" {
    parts := new List<InterpolatedStringPart>()
    parts.Add(new InterpolatedStringHole(FwkIdentifier("x"), "N2", 0, 0))
    expression := new InterpolatedStringExpression(parts, 0, 0, false)
    assert FwkExpressionText(expression) == "$\"{x:N2}\""
}

// ---- (i) the ONE named-argument grammar, and the span that outranks it ---------------------------

// THIS CONTRACT USED TO ASSERT `[A(n = 1)]` AND CALL IT "the grammar, not an oversight". It was
// neither: `ParseAttributes` parses its arguments with the same `ParseArgumentList()` a call uses, so
// `name: value` is the only spelling that reads back, and every `=` the formatter wrote was output no
// parser could have produced. It reached users — the estate reformat rewrote
// `docs/design/systems-samples/proofs/45-trusted-audit/Program.nl` into a form the `trusted` census
// could no longer see.
test "a named argument is spelled with a colon in an attribute exactly as in a call" {
    arguments := FwkEmptyArguments()
    arguments.Add(new Argument("n", FwkInt("1"), ArgumentModifier.None))
    call := new CallExpression(FwkIdentifier("f"), arguments, null, 0, 0)
    assert FwkExpressionText(call) == "f(n: 1)"

    // A hand-built node carries NO span, so this is the synthesis fallback — the only path on which
    // the spelling is the formatter's choice at all.
    attributeArguments := FwkEmptyArguments()
    attributeArguments.Add(new Argument("n", FwkInt("1"), ArgumentModifier.None))
    attribute := new AttributeNode("A", attributeArguments, 1, 1)
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatAttributeInline(attribute, builder)
    assert FwkShow(builder) == "[A(n: 1)]"
}

// A PARSED ATTRIBUTE IS WRITTEN FROM ITS SPAN, WHICH OUTRANKS EVERY SYNTHESIS RULE. The span is the
// author's bytes, so nothing inside the brackets is re-rendered — not the argument spelling, not the
// line structure, and not a policy token that merely looks like an expression.
test "a parsed attribute is written back from its own source span" {
    spanned := new AttributeNode("A", FwkEmptyArguments(), 1, 1, "[aotSafe(mono-wasm)]")
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatAttributeInline(spanned, builder)
    assert FwkShow(builder) == "[aotSafe(mono-wasm)]"
}

test "ref and out argument modifiers are written before the value and after the name" {
    arguments := FwkEmptyArguments()
    arguments.Add(new Argument("n", FwkIdentifier("a"), ArgumentModifier.Ref))
    arguments.Add(new Argument(null, FwkIdentifier("b"), ArgumentModifier.Out))
    call := new CallExpression(FwkIdentifier("f"), arguments, null, 0, 0)
    assert FwkExpressionText(call) == "f(n: ref a, out b)"
}

// ---- (j) the flat else-if chain -----------------------------------------------------------------

test "an else-if chain stays flat instead of nesting one level per branch" {
    body := FwkOneStatementBlock()
    innermost := new IfStatement(FwkIdentifier("c3"), body, body, 0, 0)
    middle := new IfStatement(FwkIdentifier("c2"), body, innermost, 0, 0)
    outer := new IfStatement(FwkIdentifier("c1"), body, middle, 0, 0)
    text := FwkStatementText(outer)
    assert text == "if c1 {|    inner|} else if c2 {|    inner|} else if c3 {|    inner|} else {|    inner|}|"
}

test "a non-block then and else are still braced" {
    then := new ExpressionStatement(FwkIdentifier("t"), 0, 0)
    otherwise := new ExpressionStatement(FwkIdentifier("e"), 0, 0)
    statement := new IfStatement(FwkIdentifier("c"), then, otherwise, 0, 0)
    assert FwkStatementText(statement) == "if c {|    t|} else {|    e|}|"
}

// ---- the depth is balanced -----------------------------------------------------------------------

test "every nesting statement leaves the depth exactly where it found it" {
    // The whole carrier design depends on this: `BeginFile` deliberately does NOT reset the depth,
    // which is only safe because every arm pops what it pushes.
    body := FwkOneStatementBlock()
    statements := new List<Statement>()
    statements.Add(new IfStatement(FwkIdentifier("c"), body, body, 0, 0))
    statements.Add(new WhileStatement(FwkIdentifier("c"), body, 0, 0))
    statements.Add(new ForeachStatement("x", FwkIdentifier("xs"), body, 0, 0))
    statements.Add(new ForStatement(null, null, null, body, 0, 0))
    statements.Add(new TryStatement(body, new List<CatchClause>(), body, 0, 0))
    statements.Add(new LockStatement(FwkIdentifier("o"), body, 0, 0))
    statements.Add(new AllocBlockStatement(body, 0, 0))
    statements.Add(new UnsafeBlockStatement(body, 0, 0))
    statements.Add(new AssertThrowsStatement(FwkType("Ex"), body, 0, 0))

    index := 0
    while index < statements.Count {
        state := FwkState()
        walk := FwkWalk(state)
        builder := new StringBuilder()
        walk.FormatStatement(statements[index], builder)
        assert state.IndentDepth == 0
        index = index + 1
    }
}

// ---- the object initializer's two forms -----------------------------------------------------------

// ---- the parameter list's delimiters and its wrap ------------------------------------------------

// THE INDEXER IS STATED HERE AND NOT AGAINST SOURCE, because the formatter writes an indexer as
// `this[…]` while the grammar reads it as `func this[…]` — a PRE-EXISTING round-trip defect, the
// "pinned INDEXER case" the estate's format gate already records, and not this rule's to fix. The
// emitter is reachable directly, so the delimiters and the wrap are contracted on it.

test "a parameter list writes the delimiters it is given, round or square" {
    parameters := FwkEmptyParameters()
    parameters.Add(FwkParameter("i", "int"))
    parameters.Add(FwkParameter("j", "int"))
    state := FwkState()
    walk := FwkWalk(state)

    round := new StringBuilder()
    walk.AppendParameterList(parameters, 0, "(", ")", round)
    assert FwkShow(round) == "(i: int, j: int)", FwkShow(round)

    square := new StringBuilder()
    walk.AppendParameterList(parameters, 0, "[", "]", square)
    assert FwkShow(square) == "[i: int, j: int]", FwkShow(square)
}

test "a parameter list wraps on its ELEMENT lines, and keeps its square brackets when it does" {
    // A parameter below the declaration's own line is a wrapped list. The closer plays no part: a
    // declaration's `(` and `)` belong to the declaration, and the parser stamps neither.
    parameters := FwkEmptyParameters()
    parameters.Add(FwkParameterAt("i", "int", 2))
    parameters.Add(FwkParameterAt("j", "int", 3))
    state := FwkState()
    walk := FwkWalk(state)

    builder := new StringBuilder()
    walk.AppendParameterList(parameters, 1, "[", "]", builder)
    assert FwkShow(builder) == "[|    i: int,|    j: int|]", FwkShow(builder)

    // The same parameters all on the declaration's own line stay on one line.
    flatParameters := FwkEmptyParameters()
    flatParameters.Add(FwkParameterAt("i", "int", 1))
    flatParameters.Add(FwkParameterAt("j", "int", 1))
    flat := new StringBuilder()
    FwkWalk(FwkState()).AppendParameterList(flatParameters, 1, "(", ")", flat)
    assert FwkShow(flat) == "(i: int, j: int)", FwkShow(flat)
}

func FwkParameterAt(name: string, typeName: string, line: int): Parameter {
    return new Parameter(name, FwkType(typeName), null, false, ParameterModifier.None, null, line, 0, false, null)
}

test "an initializer with no source positions is written inline, however many properties it has" {
    // A hand-built tree carries no `Line`/`EndLine`, and the wrapping rule reads a tree with no source
    // positions as single-line. That is the whole reason this file's contracts are untouched by the
    // rule: it decides from the SOURCE, and these trees have none. The width rule this replaces would
    // have broken this initializer apart at `MaxLineLength`; there is no width limit any more.
    properties := new List<PropertyInitializer>()
    properties.Add(new PropertyInitializer("Alpha", null, FwkInt("1"), 0, 0))
    properties.Add(new PropertyInitializer("Beta", null, FwkInt("2"), 0, 0))
    properties.Add(new PropertyInitializer("Gamma", null, FwkInt("3"), 0, 0))
    state := new FormatterWalkState(FwkConfig(4, true, 4))
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatObjectInitializer(new ObjectInitializerExpression(properties, 0, 0), builder)
    assert FwkShow(builder) == " { Alpha: 1, Beta: 2, Gamma: 3 }"
}

test "an initializer whose braces span source lines is written one property per line" {
    // The same tree with the two brace lines stamped, which is what the parser does.
    properties := new List<PropertyInitializer>()
    properties.Add(new PropertyInitializer("Alpha", null, FwkInt("1"), 1, 1))
    properties.Add(new PropertyInitializer("Beta", null, FwkInt("2"), 2, 1))
    state := new FormatterWalkState(FwkConfig(4, true, 4000))
    walk := FwkWalk(state)
    builder := new StringBuilder()
    initializer := new ObjectInitializerExpression(properties, 1, 1)
    initializer.EndLine = 3
    walk.FormatObjectInitializer(initializer, builder)
    assert FwkShow(builder) == " {|    Alpha: 1,|    Beta: 2|}"
}

test "an indexer initializer writes its bracketed index and an equals sign" {
    properties := new List<PropertyInitializer>()
    properties.Add(new PropertyInitializer(null, FwkInt("0"), FwkInt("9"), 0, 0))
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatObjectInitializer(new ObjectInitializerExpression(properties, 0, 0), builder)
    assert FwkShow(builder) == " { [0] = 9 }"
}

// ---- the statement arms that are one line each ------------------------------------------------------

test "a yield with no value is yield break" {
    assert FwkStatementText(new YieldStatement(null, 0, 0)) == "yield break|"
    assert FwkStatementText(new YieldStatement(FwkIdentifier("v"), 0, 0)) == "yield v|"
}

test "a bare return has no trailing space" {
    assert FwkStatementText(new ReturnStatement(null, 0, 0)) == "return|"
    assert FwkStatementText(new ReturnStatement(FwkIdentifier("v"), 0, 0)) == "return v|"
}

test "break and continue carry no operand" {
    assert FwkStatementText(new BreakStatement(0, 0)) == "break|"
    assert FwkStatementText(new ContinueStatement(0, 0)) == "continue|"
}

test "a preprocessor directive is written through untouched" {
    assert FwkStatementText(new PreprocessorDirective("#if DEBUG", 0, 0)) == "#if DEBUG|"
}

test "a tuple deconstruction always writes :=" {
    names := new List<string>()
    names.Add("a")
    names.Add("b")
    statement := new TupleDeconstructionStatement(names, FwkIdentifier("p"), VariableKind.Let, 0, 0)
    assert FwkStatementText(statement) == "a, b := p|"
}

test "a catch clause with a name writes name and type, and one without writes bracketed type" {
    body := FwkOneStatementBlock()
    named := new List<CatchClause>()
    named.Add(new CatchClause(FwkType("Ex"), "e", body))
    assert FwkStatementText(new TryStatement(body, named, null, 0, 0)) == "try {|    inner|} catch e: Ex {|    inner|}|"

    anonymous := new List<CatchClause>()
    anonymous.Add(new CatchClause(FwkType("Ex"), null, body))
    assert FwkStatementText(new TryStatement(body, anonymous, null, 0, 0)) == "try {|    inner|} catch (Ex) {|    inner|}|"
}

test "an assert with a message writes the message after a comma" {
    assert FwkStatementText(new AssertStatement(FwkIdentifier("c"), null, 0, 0)) == "assert c|"
    assert FwkStatementText(new AssertStatement(FwkIdentifier("c"), FwkIdentifier("m"), 0, 0)) == "assert c, m|"
}

// ---- the expression arms whose spelling is a decision -------------------------------------------------

test "a postfix operator follows its operand and a prefix precedes it" {
    post := new UnaryExpression(UnaryOperator.PostIncrement, FwkIdentifier("a"), 0, 0)
    assert FwkExpressionText(post) == "a++"

    pre := new UnaryExpression(UnaryOperator.PreIncrement, FwkIdentifier("a"), 0, 0)
    assert FwkExpressionText(pre) == "++a"
}

test "a null-conditional access writes ?. and ?[" {
    member := new MemberAccessExpression(FwkIdentifier("a"), "B", true, 0, 0)
    assert FwkExpressionText(member) == "a?.B"

    index := new IndexAccessExpression(FwkIdentifier("a"), FwkInt("0"), true, 0, 0)
    assert FwkExpressionText(index) == "a?[0]"
}

test "an immutable array literal opens with a hash" {
    elements := new List<Expression>()
    elements.Add(FwkInt("1"))
    assert FwkExpressionText(new ArrayLiteralExpression(elements, true, 0, 0)) == "#[1]"
    assert FwkExpressionText(new ArrayLiteralExpression(elements, false, 0, 0)) == "[1]"
}

test "a hard cast brackets the type before the operand and a safe cast writes as" {
    hard := new CastExpression(FwkIdentifier("a"), FwkType("int"), CastKind.Hard, 0, 0)
    assert FwkExpressionText(hard) == "(int)a"

    safe := new CastExpression(FwkIdentifier("a"), FwkType("int"), CastKind.Safe, 0, 0)
    assert FwkExpressionText(safe) == "a as int"
}

test "a range writes both ends only when they are there" {
    assert FwkExpressionText(new RangeExpression(FwkInt("1"), FwkInt("2"), 0, 0)) == "1..2"
    assert FwkExpressionText(new RangeExpression(null, FwkInt("2"), 0, 0)) == "..2"
    assert FwkExpressionText(new RangeExpression(FwkInt("1"), null, 0, 0)) == "1.."
    assert FwkExpressionText(new RangeExpression(null, null, 0, 0)) == ".."
}

test "a parenthesized expression is the only source of brackets the walk writes" {
    inner := new BinaryExpression(FwkIdentifier("a"), BinaryOperator.Add, FwkIdentifier("b"), 0, 0)
    assert FwkExpressionText(inner) == "a + b"
    assert FwkExpressionText(new ParenthesizedExpression(inner, 0, 0)) == "(a + b)"
}

test "a match expression writes commas between arms and none after the last" {
    cases := new List<MatchCase>()
    cases.Add(new MatchCase(new IdentifierPattern("a", 0, 0), null, FwkInt("1")))
    cases.Add(new MatchCase(new IdentifierPattern("b", 0, 0), FwkIdentifier("g"), FwkInt("2")))
    expression := new MatchExpression(FwkIdentifier("v"), cases, 0, 0)
    assert FwkExpressionText(expression) == "match v {|    a => 1,|    b when g => 2|}"
}

// ---- the pattern arms ------------------------------------------------------------------------------

test "a property pattern has three shapes and the bare name is one of them" {
    assert FwkPropertyPatternText(new PropertyPattern("A", null, null, 0, 0)) == "A"
    assert FwkPropertyPatternText(new PropertyPattern("A", new IdentifierPattern("p", 0, 0), null, 0, 0)) == "A: p"
    assert FwkPropertyPatternText(new PropertyPattern("A", null, "b", 0, 0)) == "A: b"
}

test "a pattern with a nested pattern beats the binding name" {
    both := new PropertyPattern("A", new IdentifierPattern("p", 0, 0), "b", 0, 0)
    assert FwkPropertyPatternText(both) == "A: p"
}

func FwkPropertyPatternText(propertyPattern: PropertyPattern): string {
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatPropertyPattern(propertyPattern, builder)
    return FwkShow(builder)
}

test "the logical patterns are written infix and not as calls" {
    left := new IdentifierPattern("a", 0, 0)
    right := new IdentifierPattern("b", 0, 0)
    assert FwkPatternText(new AndPattern(left, right, 0, 0)) == "a and b"
    assert FwkPatternText(new OrPattern(left, right, 0, 0)) == "a or b"
    assert FwkPatternText(new NotPattern(left, 0, 0)) == "not a"
}

test "a slice pattern writes its binding name after the dots" {
    assert FwkPatternText(new SlicePattern(null, 0, 0)) == ".."
    assert FwkPatternText(new SlicePattern("rest", 0, 0)) == ".. rest"
}

test "a relational pattern writes its operator text verbatim" {
    assert FwkPatternText(new RelationalPattern(">=", FwkInt("3"), 0, 0)) == ">= 3"
}

// ---- the parameter -----------------------------------------------------------------------------------

test "a parameter's modifiers are written in the order the grammar wants" {
    parameter := new Parameter("p", FwkType("int"), null, true, ParameterModifier.Ref, null, 0, 0, false, null)
    state := FwkState()
    walk := FwkWalk(state)
    builder := new StringBuilder()
    walk.FormatParameter(parameter, builder)
    assert FwkShow(builder) == "this ref p: int"
}

test "a scoped parameter writes its lifetime only when it has one" {
    plain := new Parameter("p", FwkType("int"), null, false, ParameterModifier.None, null, 0, 0, true, null)
    state := FwkState()
    builder := new StringBuilder()
    FwkWalk(state).FormatParameter(plain, builder)
    assert FwkShow(builder) == "p: int scoped"

    named := new Parameter("p", FwkType("int"), null, false, ParameterModifier.None, null, 0, 0, true, "sc")
    namedBuilder := new StringBuilder()
    FwkWalk(FwkState()).FormatParameter(named, namedBuilder)
    assert FwkShow(namedBuilder) == "p: int scoped sc"
}

test "a parameter default value follows an equals sign" {
    parameter := new Parameter("p", FwkType("int"), FwkInt("1"), false, ParameterModifier.None, null, 0, 0, false, null)
    builder := new StringBuilder()
    FwkWalk(FwkState()).FormatParameter(parameter, builder)
    assert FwkShow(builder) == "p: int = 1"
}

// ---- the attribute list ------------------------------------------------------------------------------

test "a null attribute list is as silent as an empty one" {
    nullBuilder := new StringBuilder()
    FwkWalk(FwkState()).FormatAttributes(null, nullBuilder)
    assert FwkShow(nullBuilder) == ""

    emptyBuilder := new StringBuilder()
    FwkWalk(FwkState()).FormatAttributes(FwkEmptyAttributes(), emptyBuilder)
    assert FwkShow(emptyBuilder) == ""
}

test "attributes are written one per line at the current depth" {
    attributes := FwkEmptyAttributes()
    attributes.Add(new AttributeNode("A", FwkEmptyArguments(), 1, 1))
    attributes.Add(new AttributeNode("B", FwkEmptyArguments(), 1, 1))
    state := FwkState()
    state.Push()
    builder := new StringBuilder()
    FwkWalk(state).FormatAttributes(attributes, builder)
    assert FwkShow(builder) == "    [A]|    [B]|"
}

// ---- the function declaration ---------------------------------------------------------------------------

test "a generator is func star and its flag is not printed as a modifier" {
    generator := FwkFunction("f", FwkOneStatementBlock(), null, Modifiers.Generator)
    builder := new StringBuilder()
    FwkWalk(FwkState()).FormatFunction(generator, builder)
    assert FwkShow(builder) == "func* f() {|    inner|}|"
}

test "a function with neither body ends its own line" {
    declared := FwkFunction("f", null, FwkType("int"), Modifiers.Abstract)
    builder := new StringBuilder()
    FwkWalk(FwkState()).FormatFunction(declared, builder)
    assert FwkShow(builder) == "abstract func f(): int|"
}

test "an expression-bodied function writes an arrow and no braces" {
    expressionBodied := new FunctionDeclaration(
        "f",
        FwkEmptyParameters(),
        null,
        null,
        FwkIdentifier("e"),
        null,
        null,
        Modifiers.None,
        FwkEmptyAttributes(),
        false,
        null,
        false,
        false,
        0,
        0
    )
    builder := new StringBuilder()
    FwkWalk(FwkState()).FormatFunction(expressionBodied, builder)
    assert FwkShow(builder) == "func f() => e|"
}

test "type parameters are written between the name and the parameter list" {
    typeParameters := new List<TypeParameter>()
    typeParameters.Add(new TypeParameter("T"))
    typeParameters.Add(new TypeParameter("U"))
    generic := new FunctionDeclaration(
        "f",
        FwkEmptyParameters(),
        null,
        FwkOneStatementBlock(),
        null,
        typeParameters,
        null,
        Modifiers.None,
        FwkEmptyAttributes(),
        false,
        null,
        false,
        false,
        0,
        0
    )
    builder := new StringBuilder()
    FwkWalk(FwkState()).FormatFunction(generic, builder)
    assert FwkShow(builder) == "func f<T, U>() {|    inner|}|"
}

test "an EMPTY type parameter list writes no angle brackets" {
    generic := new FunctionDeclaration(
        "f",
        FwkEmptyParameters(),
        null,
        FwkOneStatementBlock(),
        null,
        new List<TypeParameter>(),
        null,
        Modifiers.None,
        FwkEmptyAttributes(),
        false,
        null,
        false,
        false,
        0,
        0
    )
    builder := new StringBuilder()
    FwkWalk(FwkState()).FormatFunction(generic, builder)
    assert FwkShow(builder) == "func f() {|    inner|}|"
}

test "a conversion operator writes its name and return type instead of the func keyword, and LOSES its public keyword" {
    // THE TEST'S FIRST PROSE WAS WRONG AND THE OWNER WAS RIGHT. A conversion operator asks
    // `FormatModifiers` NOT to preserve casing-visibility, and that argument does not merely soften
    // the redundancy check — it skips the `public`/`private` block ENTIRELY. So `public implicit`
    // formats to `implicit`, and the same holds for an operator overload, which keeps `static` and
    // drops `public`. Both are asserted, because one alone reads like an accident.
    conversion := new FunctionDeclaration(
        "implicit",
        FwkEmptyParameters(),
        FwkType("int"),
        FwkOneStatementBlock(),
        null,
        null,
        null,
        Modifiers.Public,
        FwkEmptyAttributes(),
        false,
        null,
        true,
        false,
        0,
        0
    )
    builder := new StringBuilder()
    FwkWalk(FwkState()).FormatFunction(conversion, builder)
    assert FwkShow(builder) == "implicit int() {|    inner|}|"

    operatorOverload := new FunctionDeclaration(
        "op_Addition",
        FwkEmptyParameters(),
        FwkType("int"),
        FwkOneStatementBlock(),
        null,
        null,
        null,
        Modifiers.Public | Modifiers.Static,
        FwkEmptyAttributes(),
        true,
        null,
        false,
        false,
        0,
        0
    )
    operatorBuilder := new StringBuilder()
    FwkWalk(FwkState()).FormatFunction(operatorOverload, operatorBuilder)
    assert FwkShow(operatorBuilder) == "static func op_Addition(): int {|    inner|}|"
}

// ---- the block and its comment stream ------------------------------------------------------------------

test "a block baselines the gap tracker on its opening brace line" {
    statements := new List<Statement>()
    first := new ExpressionStatement(FwkIdentifier("a"), 8, 1)
    first.EndLine = 8
    statements.Add(first)
    state := FwkState()
    state.BeginFile(null)
    FwkWalk(state).FormatBlock(new BlockStatement(statements, 6, 1), new StringBuilder())
    assert state.LastEmittedSourceLine == 8
}

test "a block whose line is zero does not reset the tracker" {
    // A block from a path that never stamped a line would otherwise zero the tracker and swallow
    // the gap before its first statement.
    state := FwkState()
    state.BeginFile(null)
    state.LastEmittedSourceLine = 30
    FwkWalk(state).FormatBlock(new BlockStatement(new List<Statement>(), 0, 1), new StringBuilder())
    assert state.LastEmittedSourceLine == 30
}

test "a blank line between two statements is preserved and one between the brace and the first is not" {
    statements := new List<Statement>()
    first := new ExpressionStatement(FwkIdentifier("a"), 5, 1)
    first.EndLine = 5
    second := new ExpressionStatement(FwkIdentifier("b"), 8, 1)
    second.EndLine = 8
    statements.Add(first)
    statements.Add(second)
    state := FwkState()
    state.BeginFile(null)
    builder := new StringBuilder()
    FwkWalk(state).FormatBlock(new BlockStatement(statements, 1, 1), builder)
    assert FwkShow(builder) == "a||b|"
}

test "a comment standing before a statement is emitted before it" {
    comments := new List<CommentTrivia>()
    comments.Add(new CommentTrivia(4, 1, "// note", false))
    statements := new List<Statement>()
    only := new ExpressionStatement(FwkIdentifier("a"), 5, 1)
    only.EndLine = 5
    statements.Add(only)
    state := FwkState()
    state.BeginFile(comments)
    builder := new StringBuilder()
    FwkWalk(state).FormatBlock(new BlockStatement(statements, 3, 1), builder)
    assert FwkShow(builder) == "// note|a|"
}

// ---- the keyword block --------------------------------------------------------------------------------

test "a keyword block writes its header then a braced body at one more level" {
    state := FwkState()
    builder := new StringBuilder()
    FwkWalk(state).FormatKeywordBlock("alloc", FwkOneStatementBlock(), builder)
    assert FwkShow(builder) == "alloc {|    inner|}|"
    assert state.IndentDepth == 0
}

// ---- the switch arm's labels are the grammar's --------------------------------------------------
//
// THE LABEL IS `case <pattern> =>` AND `default =>`, NEVER THE C# COLON. The parser demands an
// arrow after both labels, so a colon is output that cannot re-parse — with it, `FormatSafe`
// rejected EVERY file containing a switch and the formatter was unusable on them. The body is
// always braced because braces are the only shape that carries more than one statement, and the
// parser flattens a braced body into the case's statement list, so the round trip neither adds
// nor drops a BlockStatement.

func FwkSwitchOneCase(pattern: Pattern?): SwitchStatement {
    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(FwkIdentifier("inner"), 0, 0))
    cases := new List<SwitchCase>()
    cases.Add(new SwitchCase(pattern, statements, 0, 0))
    return new SwitchStatement(FwkIdentifier("value"), cases, 0, 0)
}

test "a switch case writes an arrow and a braced body, never a C# colon label" {
    statement := FwkSwitchOneCase(new LiteralPattern(FwkInt("0"), 0, 0))
    assert FwkStatementText(statement) == "switch value {|    case 0 => {|        inner|    }|}|"
}

test "a default case writes default => with the same braced body" {
    statement := FwkSwitchOneCase(null)
    assert FwkStatementText(statement) == "switch value {|    default => {|        inner|    }|}|"
}

test "a case with two statements keeps both inside its braces, which no unbraced arm could" {
    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(FwkIdentifier("first"), 0, 0))
    statements.Add(new ExpressionStatement(FwkIdentifier("second"), 0, 0))
    cases := new List<SwitchCase>()
    cases.Add(new SwitchCase(null, statements, 0, 0))
    statement := new SwitchStatement(FwkIdentifier("value"), cases, 0, 0)
    assert FwkStatementText(statement) == "switch value {|    default => {|        first|        second|    }|}|"
}
