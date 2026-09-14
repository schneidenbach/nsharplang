namespace NSharpLang.LanguageServerHandlers.Tests

test "semantic tokens classify N# keywords as keyword tokens" {
    docs := LshNewDocs()
    uri := "file:///test/semtokens.nl"
    source := LshBody(
        """
func main() {
    let x := 42
}
"""
    )
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    assert doc.Tokens != null

    handler := LshSemanticHandler(docs)
    sets := LshSemanticSets(doc)

    funcClassification := LshClassify(handler, LshFirstTokenOfType(doc, "Func"), doc, sets, null)
    assert funcClassification != null
    assert LshClassifiedTokenType(funcClassification) == 12

    letClassification := LshClassify(handler, LshFirstTokenOfType(doc, "Let"), doc, sets, null)
    assert letClassification != null
    assert LshClassifiedTokenType(letClassification) == 12
}

test "semantic tokens classify integer and floating literals as number tokens" {
    docs := LshNewDocs()
    uri := "file:///test/semtokens_num.nl"
    source := LshBody(
        """
func main() {
    let x := 42
    let y := 3.14
}
"""
    )
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    handler := LshSemanticHandler(docs)
    sets := LshSemanticSets(doc)

    intClassification := LshClassify(handler, LshFirstTokenOfType(doc, "IntLiteral"), doc, sets, null)
    assert intClassification != null
    assert LshClassifiedTokenType(intClassification) == 15

    floatClassification := LshClassify(handler, LshFirstTokenOfType(doc, "FloatLiteral"), doc, sets, null)
    assert floatClassification != null
    assert LshClassifiedTokenType(floatClassification) == 15
}

test "semantic tokens classify string literals as string tokens" {
    docs := LshNewDocs()
    uri := "file:///test/semtokens_str.nl"
    source := LshBody(
        """
func main() {
    let x := "hello"
}
"""
    )
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    handler := LshSemanticHandler(docs)
    sets := LshSemanticSets(doc)

    classification := LshClassify(handler, LshFirstTokenOfType(doc, "StringLiteral"), doc, sets, null)
    assert classification != null
    assert LshClassifiedTokenType(classification) == 14
}

test "an interpolated string is not classified as one flat string token" {
    docs := LshNewDocs()
    uri := "file:///test/semtokens_interpolated_str.nl"
    source := LshRaw(
        """
func main() {
    name := "Spencer"
    print $"Hello, {name}!"
}
"""
    )
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    handler := LshSemanticHandler(docs)
    sets := LshSemanticSets(doc)

    interpolated := LshFirstInterpolatedStringToken(doc)
    assert LshClassify(handler, interpolated, doc, sets, null) == null

    embedded := LshSingleIdentifier(LshInterpolatedExpressionTokens(interpolated), "name")
    assert embedded.Line == 3
    assert embedded.Column == 21

    classification := LshClassify(handler, embedded, doc, sets, null)
    assert classification != null
    assert LshClassifiedTokenType(classification) == 8
}

test "an interpolated raw string is not classified as one flat string token" {
    docs := LshNewDocs()
    uri := "file:///test/semtokens_interpolated_raw_str.nl"
    source := "func main() {\n    name := \"Spencer\"\n    print $\"\"\"Hello, {name}!\"\"\"\n}\n"
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    handler := LshSemanticHandler(docs)
    sets := LshSemanticSets(doc)

    interpolated := LshFirstTokenOfType(doc, "InterpolatedRawStringLiteral")
    assert LshClassify(handler, interpolated, doc, sets, null) == null

    embedded := LshSingleIdentifier(LshInterpolatedExpressionTokens(interpolated), "name")
    assert embedded.Line == 3
    assert embedded.Column == 23

    classification := LshClassify(handler, embedded, doc, sets, null)
    assert classification != null
    assert LshClassifiedTokenType(classification) == 8
}

test "semantic tokens collect declared type names" {
    docs := LshNewDocs()
    uri := "file:///test/semtokens_type.nl"
    source := LshBody(
        """
class Person {
    name: string
    age: int
}

func main() {
    let p := new Person()
}
"""
    )
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    assert LshSetContains(LshSemanticStatic("BuildTypeNameSet", doc), "Person")
}

test "semantic tokens collect declared function names" {
    docs := LshNewDocs()
    uri := "file:///test/semtokens_func.nl"
    source := LshBody(
        """
func greet(name: string): string {
    return "Hello " + name
}
"""
    )
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    assert LshSetContains(LshSemanticStatic("BuildFunctionNameSet", doc), "greet")
}

test "the error binding of a two-name capture carries the catch-result modifier" {
    docs := LshNewDocs()
    uri := "file:///test/semtokens_catch_result.nl"
    source := LshBody(
        """
func MightFail(): int {
    return 1
}

func main() {
    result, err := MightFail()
}
"""
    )
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    handler := LshSemanticHandler(docs)
    sets := LshSemanticSets(doc)
    bindings := LshCatchResultBindings(doc)

    errToken := LshSingleIdentifierOnLine(doc, "err", 6)
    assert LshBindingsContain(bindings, errToken.Line, errToken.Column, errToken.Value)

    classification := LshClassify(handler, errToken, doc, sets, bindings)
    assert classification != null
    assert LshClassifiedTokenType(classification) == 8
    assert LshClassifiedModifiers(classification) == LshCatchResultModifierMask()
}

test "a four-name deconstruction produces no catch-result binding at all" {
    docs := LshNewDocs()
    uri := "file:///test/semtokens_multi_catch_result.nl"
    source := LshBody(
        """
func GetValues(): (int, int, int) {
    return (1, 2, 3)
}

func main() {
    err, value, other, err := GetValues()
}
"""
    )
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    handler := LshSemanticHandler(docs)
    sets := LshSemanticSets(doc)
    bindings := LshCatchResultBindings(doc)

    errTokens := LshIdentifiersOnLine(doc, "err", 6)
    assert errTokens.Count == 2
    assert LshBindingCount(bindings) == 0

    index := 0
    while index < errTokens.Count {
        classification := LshClassify(handler, errTokens[index], doc, sets, bindings)
        assert classification != null
        assert LshClassifiedTokenType(classification) == 8
        assert LshClassifiedModifiers(classification) == 0
        index = index + 1
    }
}
