namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR WHAT A PARSED FILE LOOKS LIKE AS JSON (task 019 slice 5). These assertions came out
// of `OutputFormatter.cs` with the members. They pin the five things the deleted C# decided: the
// shape of the `nlc query ast` envelope, how a path is written into it, how each leaf value is
// rendered, that a list becomes an array and a node becomes an object tagged with its concrete type
// name, and — the one a reader would never guess — that a node's members are ordered by metadata
// token, which puts BASE-class members before the node's own.
func AjUnits(filePath: string, unit: CompilationUnit): List<AstJsonUnit> {
    units := new List<AstJsonUnit>()
    units.Add(new AstJsonUnit(filePath, unit))
    return units
}

func AjEmptyUnit(): CompilationUnit {
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 1, 1)
}

// One compilation unit whose only declaration is a function whose body is a single expression
// statement. That is the shortest path from an envelope to an arbitrary expression leaf, so it is
// the shape every value contract below is written against.
func AjUnitWithExpression(expression: Expression): CompilationUnit {
    statements := new List<Statement>()
    statement: Statement = new ExpressionStatement(expression, 3, 5)
    statements.Add(statement)

    body := new BlockStatement(statements, 2, 1)
    declaration: Declaration = new FunctionDeclaration("Run", new List<Parameter>(), null, body, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 2, 1)

    declarations := new List<Declaration>()
    declarations.Add(declaration)
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
}

func AjRender(expression: Expression): string {
    return OutputFormatterAstJsonKernels.AstToJson(AjUnits("a.nl", AjUnitWithExpression(expression)))
}

test "the envelope is the versioned query.ast shape, indented, with the file list last" {
    json := OutputFormatterAstJsonKernels.AstToJson(AjUnits("a.nl", AjEmptyUnit()))

    assert json.StartsWith("{\n  \"schemaVersion\": 1,\n  \"command\": \"query.ast\",\n  \"ok\": true,\n  \"files\": [", StringComparison.Ordinal)
    assert json.Contains("\"file\": \"a.nl\"")
    assert json.Contains("\"ast\": {")
    assert json.EndsWith("}", StringComparison.Ordinal)
}

test "an empty unit list still produces the envelope with an empty file array" {
    json := OutputFormatterAstJsonKernels.AstToJson(new List<AstJsonUnit>())

    assert json.Contains("\"files\": []")
    assert json.Contains("\"ok\": true")
}

test "every unit gets its own entry, in the order it was handed over" {
    units := new List<AstJsonUnit>()
    units.Add(new AstJsonUnit("first.nl", AjEmptyUnit()))
    units.Add(new AstJsonUnit("second.nl", AjEmptyUnit()))

    json := OutputFormatterAstJsonKernels.AstToJson(units)

    assert json.IndexOf("first.nl", StringComparison.Ordinal) < json.IndexOf("second.nl", StringComparison.Ordinal)
    assert json.IndexOf("second.nl", StringComparison.Ordinal) > 0
}

test "the file path is normalized on the way in, so a windows path reads with forward slashes" {
    json := OutputFormatterAstJsonKernels.AstToJson(AjUnits("src\\app\\Program.nl", AjEmptyUnit()))

    assert json.Contains("\"file\": \"src/app/Program.nl\"")
    assert !json.Contains("\\\\")
}

test "a node is an object tagged with its concrete type name, and the tag comes first" {
    json := OutputFormatterAstJsonKernels.AstToJson(AjUnits("a.nl", AjEmptyUnit()))
    astAt := json.IndexOf("\"ast\": {", StringComparison.Ordinal)
    nodeAt := json.IndexOf("\"node\": \"CompilationUnit\"", StringComparison.Ordinal)

    assert astAt > 0
    assert nodeAt > astAt
    assert json.IndexOf("\"namespace\"", StringComparison.Ordinal) > nodeAt
}

// The single decision a reader would never guess from the output: `GetFields` hands back a derived
// type's own fields BEFORE its base type's, and the rendering re-orders them by metadata token, so
// `AstNode`'s line/column/endLine precede `IntLiteralExpression`'s own value.
test "a node's members are ordered by metadata token, which puts base-class members first" {
    json := AjRender(new IntLiteralExpression("42", 3, 5))

    lineAt := json.IndexOf("\"line\": 3", StringComparison.Ordinal)
    columnAt := json.IndexOf("\"column\": 5", StringComparison.Ordinal)
    endLineAt := json.IndexOf("\"endLine\": 3", StringComparison.Ordinal)
    valueAt := json.IndexOf("\"value\": \"42\"", StringComparison.Ordinal)

    assert lineAt > 0
    assert columnAt > lineAt
    assert endLineAt > columnAt
    assert valueAt > endLineAt
}

test "member names are camelCased and a single leading capital is lowered" {
    json := AjRender(new IntLiteralExpression("1", 3, 5))

    assert json.Contains("\"node\": \"IntLiteralExpression\"")
    assert json.Contains("\"value\":")
    assert json.Contains("\"endLine\":")
    assert !json.Contains("\"Value\":")
    assert !json.Contains("\"EndLine\":")
}

test "a null member renders as JSON null rather than being dropped" {
    json := OutputFormatterAstJsonKernels.AstToJson(AjUnits("a.nl", AjEmptyUnit()))

    assert json.Contains("\"namespace\": null")
    assert json.Contains("\"package\": null")
}

test "an empty list member renders as an empty array" {
    json := OutputFormatterAstJsonKernels.AstToJson(AjUnits("a.nl", AjEmptyUnit()))

    assert json.Contains("\"imports\": []")
    assert json.Contains("\"declarations\": []")
}

test "a populated list renders its items in order, each as its own node object" {
    json := AjRender(new IntLiteralExpression("7", 3, 5))

    assert json.Contains("\"declarations\": [")
    assert json.Contains("\"node\": \"FunctionDeclaration\"")
    assert json.Contains("\"node\": \"ExpressionStatement\"")
    assert json.Contains("\"node\": \"IntLiteralExpression\"")
}

test "an int member is a JSON number and a string member is a quoted string" {
    json := AjRender(new IntLiteralExpression("42", 3, 5))

    assert json.Contains("\"line\": 3")
    assert json.Contains("\"value\": \"42\"")
    assert !json.Contains("\"line\": \"3\"")
}

test "a bool member is a JSON boolean" {
    json := AjRender(new IntLiteralExpression("1", 3, 5))

    assert json.Contains("\"isOperatorOverload\": false")
    assert !json.Contains("\"isOperatorOverload\": \"false\"")
}

test "an enum member renders as its name, not its numeric value" {
    json := AjRender(new IntLiteralExpression("1", 3, 5))

    assert json.Contains("\"modifiers\": \"None\"")
    assert !json.Contains("\"modifiers\": 0")
}

test "a unary operator enum renders by name too, so the kind survives the round trip" {
    operand: Expression = new IntLiteralExpression("1", 3, 9)
    json := AjRender(new UnaryExpression(UnaryOperator.Not, operand, 3, 5))

    assert json.Contains("\"node\": \"UnaryExpression\"")
    assert json.Contains("\"operator\": \"Not\"")
}

test "a nested expression recurses, so a child node appears inside its parent" {
    left: Expression = new IntLiteralExpression("1", 3, 5)
    right: Expression = new IntLiteralExpression("2", 3, 9)
    json := AjRender(new BinaryExpression(left, BinaryOperator.Add, right, 3, 7))

    binaryAt := json.IndexOf("\"node\": \"BinaryExpression\"", StringComparison.Ordinal)
    firstChildAt := json.IndexOf("\"node\": \"IntLiteralExpression\"", StringComparison.Ordinal)

    assert binaryAt > 0
    assert firstChildAt > binaryAt
    assert json.Contains("\"operator\": \"Add\"")
    assert json.Contains("\"value\": \"1\"")
    assert json.Contains("\"value\": \"2\"")
}

test "a string value is escaped by the serializer rather than pasted in raw" {
    json := AjRender(new StringLiteralExpression("a\"b", 3, 5))

    assert json.Contains("a\\u0022b")
    assert !json.Contains("\"value\": \"a\"b\"")
}

test "the same unit rendered twice is byte-identical, so the shape is stable" {
    first := OutputFormatterAstJsonKernels.AstToJson(AjUnits("a.nl", AjEmptyUnit()))
    second := OutputFormatterAstJsonKernels.AstToJson(AjUnits("a.nl", AjEmptyUnit()))

    assert first == second
    assert first.Length > 0
}

test "the envelope is written indented, two spaces per level" {
    json := OutputFormatterAstJsonKernels.AstToJson(AjUnits("a.nl", AjEmptyUnit()))

    assert json.Contains("\n  \"schemaVersion\": 1")
    assert json.Contains("\n      \"file\": \"a.nl\"")
}

// The depth allowance is pinned by rendering a tree that nests far past the serializer's DEFAULT of
// 64. Without the raised limit this throws instead of returning, so the contract fails loudly rather
// than silently accepting a shallower envelope.
test "a tree nested deeper than the serializer's default limit still renders" {
    expression: Expression = new IntLiteralExpression("1", 3, 5)
    depth := 0
    while depth < 100 {
        expression = new UnaryExpression(UnaryOperator.Not, expression, 3, 5)
        depth = depth + 1
    }

    json := AjRender(expression)

    assert json.Length > 0
    assert json.Contains("\"node\": \"IntLiteralExpression\"")
    assert json.Contains("\"operator\": \"Not\"")
}

test "a leaf value walks through the value renderer directly: null in, null out" {
    rendered := OutputFormatterAstJsonKernels.AstValueToJson(null)

    assert rendered == null
}

test "a string value is returned as itself and a char is widened to a one-character string" {
    text: object = "abc"
    letter: object = 'x'

    renderedText := OutputFormatterAstJsonKernels.AstValueToJson(text)
    renderedLetter := OutputFormatterAstJsonKernels.AstValueToJson(letter)

    assert renderedText != null
    assert renderedText.ToString() == "abc"
    assert renderedLetter != null
    assert renderedLetter.ToString() == "x"
    assert renderedLetter as string != null
}

test "an int, a long and a double keep their own runtime type so they stay JSON numbers" {
    number: object = 7
    wide: object = 9L
    fraction: object = 1.5

    assert OutputFormatterAstJsonKernels.AstValueToJson(number).GetType() == typeof(int)
    assert OutputFormatterAstJsonKernels.AstValueToJson(wide).GetType() == typeof(long)
    assert OutputFormatterAstJsonKernels.AstValueToJson(fraction).GetType() == typeof(double)
}

test "a bool keeps its runtime type and an enum is flattened to its name" {
    flag: object = true
    kind: object = UnaryOperator.Negate

    assert OutputFormatterAstJsonKernels.AstValueToJson(flag).GetType() == typeof(bool)
    renderedKind := OutputFormatterAstJsonKernels.AstValueToJson(kind)
    assert renderedKind != null
    assert renderedKind.ToString() == "Negate"
    assert renderedKind as string != null
}

// Every other primitive goes through the invariant culture, so a float never renders with a comma
// separator on a machine whose locale uses one.
test "a primitive that is not one of the named cases is written through the invariant culture" {
    small: object = 3.5f

    rendered := OutputFormatterAstJsonKernels.AstValueToJson(small)

    assert rendered != null
    assert rendered as string != null
    assert rendered.ToString() == "3.5"
}

test "a list value becomes a list of rendered items and keeps their order" {
    source := new List<object?>()
    source.Add("first")
    source.Add(2)

    rendered := OutputFormatterAstJsonKernels.AstValueToJson(source)
    items := rendered as IList

    assert items != null
    assert items.Count == 2
    assert items[0].ToString() == "first"
    assert items[1].GetType() == typeof(int)
}

// THE MEMBER LIST IS THE AST-JSON SURFACE, so a field added to a node is a field added to
// `nlc query ast --json`. That is additive rather than breaking — a reader keys on names — but it is
// not invisible, and this contract is where it becomes visible. `Spelling` is the fifth member here:
// a numeric literal's source text, non-null only when digit separators make it differ from `Value`.
test "the member collection of a node reports base members before its own, already sorted" {
    node: object = new IntLiteralExpression("42", 3, 5)

    members := OutputFormatterAstJsonKernels.CollectMembers(node.GetType(), node)

    assert members.Count == 5
    assert members[0].Name == "Line"
    assert members[1].Name == "Column"
    assert members[2].Name == "EndLine"
    assert members[3].Name == "Value"
    assert members[4].Name == "Spelling"
    assert members[0].Token < members[3].Token

    // An unseparated numeral carries no spelling, so the added member is null on almost every node.
    assert members[4].Value == null
}

test "the collected member values are the node's own values, read through reflection" {
    node: object = new IntLiteralExpression("42", 3, 5)

    members := OutputFormatterAstJsonKernels.CollectMembers(node.GetType(), node)

    assert members[0].Value != null
    assert members[0].Value.ToString() == "3"
    assert members[3].Value != null
    assert members[3].Value.ToString() == "42"
}

test "the sort is a real sort: a reversed list of members comes back in token order" {
    members := new List<AstJsonMember>()
    members.Add(new AstJsonMember(30, "third", null))
    members.Add(new AstJsonMember(10, "first", null))
    members.Add(new AstJsonMember(20, "second", null))

    OutputFormatterAstJsonKernels.SortByToken(members)

    assert members[0].Name == "first"
    assert members[1].Name == "second"
    assert members[2].Name == "third"
}

test "sorting an empty or single-member list is a no-op rather than an error" {
    empty := new List<AstJsonMember>()
    OutputFormatterAstJsonKernels.SortByToken(empty)
    assert empty.Count == 0

    single := new List<AstJsonMember>()
    single.Add(new AstJsonMember(5, "only", null))
    OutputFormatterAstJsonKernels.SortByToken(single)
    assert single.Count == 1
    assert single[0].Name == "only"
}

test "an indexed property is skipped, so a type that has one is not rendered through its indexer" {
    text: object = "abc"

    members := OutputFormatterAstJsonKernels.CollectMembers(text.GetType(), text)

    assert members.Count == 1
    assert members[0].Name == "Length"
}

test "the pair the CLI hands over keeps the path it was read from beside the unit it parsed" {
    unit := AjEmptyUnit()
    pair := new AstJsonUnit("src/Program.nl", unit)

    assert pair.File == "src/Program.nl"
    assert pair.Unit == unit
}
