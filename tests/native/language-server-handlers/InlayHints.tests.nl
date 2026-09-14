namespace NSharpLang.LanguageServerHandlers.Tests

import System
import OmniSharp.Extensions.LanguageServer.Protocol.Models

test "inlay hint annotates an inferred string declaration" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_string.nl"
    source := LshBody(
        """
func main() {
    name := "hello"
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    collected := LshHints(hints)
    assert collected.Count == 1

    hint := collected[0]
    assert hint.Kind == InlayHintKind.Type
    assert hint.Position.Line == 1
    assert LshHintLabel(hint).Contains("string", StringComparison.Ordinal)
}

test "inlay hint annotates an inferred int declaration" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_int.nl"
    source := LshBody(
        """
func main() {
    count := 42
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    collected := LshHints(hints)
    assert collected.Count == 1

    hint := collected[0]
    assert hint.Kind == InlayHintKind.Type
    assert LshHintLabel(hint).Contains("int", StringComparison.Ordinal)
}

test "inlay hint is suppressed when the type is written out" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_explicit.nl"
    source := LshBody(
        """
func main() {
    let name: string = "hello"
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    assert LshHints(hints).Count == 0
}

test "inlay hints are produced for every inferred declaration in a block" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_multi.nl"
    source := LshBody(
        """
func main() {
    x := 1
    y := 2.5
    z := true
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    assert LshHints(hints).Count == 3

    lines := LshHintLines(hints)
    assert lines.Count == 3
    assert lines[0] == 1
    assert lines[1] == 2
    assert lines[2] == 3
}

test "inlay hints outside the requested range are filtered out" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_range.nl"
    source := LshBody(
        """
func main() {
    a := 1
    b := 2
    c := 3
    d := 4
}"""
    )
    LshOpen(docs, uri, source)

    // Only lines 2-3 (0-based) are visible, which hold b and c.
    hints := LshInlayHints(docs, uri, 2, 0, 3, 100)

    assert hints != null
    assert LshHints(hints).Count == 2

    lines := LshHintLines(hints)
    assert lines.Count == 2
    assert lines[0] == 2
    assert lines[1] == 3
}

test "inlay hint annotates an inferred bool declaration" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_bool.nl"
    source := LshBody(
        """
func main() {
    flag := false
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    collected := LshHints(hints)
    assert collected.Count == 1
    assert LshHintLabel(collected[0]).Contains("bool", StringComparison.Ordinal)
}

test "inlay hint sits on the line of the variable it annotates" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_position.nl"
    source := LshBody(
        """
func main() {
    name := "hello"
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    collected := LshHints(hints)
    assert collected.Count == 1
    assert collected[0].Position.Line == 1
}

test "inlay hints for an empty document are empty" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_empty.nl"
    LshOpen(docs, uri, "")

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    assert LshHints(hints).Count == 0
}

test "a declaration without an initializer gets no inlay hint" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_no_init.nl"
    source := LshBody(
        """
func main() {
    let x: int
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    assert LshHints(hints).Count == 0
}

test "inlay hint reaches declarations nested inside an if block" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_nested.nl"
    source := LshBody(
        """
func main() {
    if true {
        x := 42
    }
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    collected := LshHints(hints)
    assert collected.Count == 1
    assert LshHintLabel(collected[0]).Contains("int", StringComparison.Ordinal)
}

test "inlay hint labels read as a type annotation starting with a colon" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_format.nl"
    source := LshBody(
        """
func main() {
    x := 42
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    collected := LshHints(hints)
    assert collected.Count == 1
    assert LshHintLabel(collected[0]).StartsWith(": ", StringComparison.Ordinal)
}

test "inlay hint reaches declarations inside a class method" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_class.nl"
    source := LshBody(
        """
class Greeter {
    func greet() {
        msg := "hello"
    }
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    collected := LshHints(hints)
    assert collected.Count == 1
    assert LshHintLabel(collected[0]).Contains("string", StringComparison.Ordinal)
}

test "a const declaration with an inferred type still gets an inlay hint" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_const.nl"
    source := LshBody(
        """
func main() {
    const pi := 3.14
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    assert LshHints(hints).Count == 1
}

test "inlay hint annotates an inferred floating point declaration" {
    docs := LshNewDocs()
    uri := "file:///test/inlay_double.nl"
    source := LshBody(
        """
func main() {
    pi := 3.14
}"""
    )
    LshOpen(docs, uri, source)

    hints := LshInlayHints(docs, uri, 0, 0, 10, 0)

    assert hints != null
    collected := LshHints(hints)
    assert collected.Count == 1
    label := LshHintLabel(collected[0])
    assert label.Contains("double", StringComparison.Ordinal) || label.Contains("float", StringComparison.Ordinal)
}
