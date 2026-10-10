namespace NSharpLang.LanguageServerHandlers.Tests

import System
import System.Collections.Generic
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// ---------------------------------------------------------------------------
// The protocol side of the handlers whose decisions now live in N# owners.
//
// The owners' own contracts are estate rows beside them in
// `src/NSharpLang.Compiler.Core/Editor*Facts.tests.nl`. These rows assert what
// estate rows CANNOT see: that the glue carries a row through to the OmniSharp
// shape unchanged, and the two things the glue itself still decides — the
// `System.Uri` canonicalisation of a document link's target, which the columnar
// backend cannot do, and the protocol invariant that a document symbol's range
// contains its own selection range.
// ---------------------------------------------------------------------------
func LshRangeContains(outer: OmniSharp.Extensions.LanguageServer.Protocol.Models.Range, inner: OmniSharp.Extensions.LanguageServer.Protocol.Models.Range): bool {
    if inner.Start.Line < outer.Start.Line || inner.End.Line > outer.End.Line {
        return false
    }
    if inner.Start.Line == outer.Start.Line && inner.Start.Character < outer.Start.Character {
        return false
    }
    if inner.End.Line == outer.End.Line && inner.End.Character > outer.End.Character {
        return false
    }
    return true
}

// A CHILDLESS SYMBOL CARRIES A NULL CHILD CONTAINER, not an empty one: the protocol asks for the
// key to be absent, and `LshChildren` treats null as an error because every other row that calls it
// is asserting about children that should be there.
func LshAssertSymbolContainment(symbols: List<DocumentSymbol>) {
    for symbol in symbols {
        assert LshRangeContains(symbol.Range, symbol.SelectionRange)
        if symbol.Children != null {
            LshAssertSymbolContainment(LshChildren(symbol))
        }
    }
}

func LshLinkLine(links: DocumentLinkContainer, fragment: string): int {
    for link in links {
        target := link.Target
        if target != null {
            text := target.ToString()
            if text != null && text.Contains(fragment, StringComparison.Ordinal) {
                return link.Range.Start.Line
            }
        }
    }
    return -1
}

func LshLinkStartCharacter(links: DocumentLinkContainer, fragment: string): int {
    for link in links {
        target := link.Target
        if target != null {
            text := target.ToString()
            if text != null && text.Contains(fragment, StringComparison.Ordinal) {
                return link.Range.Start.Character
            }
        }
    }
    return -1
}

// THE TARGET IS CANONICALISED BY `System.Uri`, WHICH IS WHY IT IS STILL C#. The owner reports the
// text the file spells; the handler turns it into the protocol's target, and that step lower-cases
// the host and supplies the empty path — neither of which the owner does or could.
test "a document link target is canonicalised even though the owner reports the raw text" {
    docs := LshNewDocs()
    uri := "file:///test/document_link_canonical.nl"
    source := LshBody(
        """
// see https://Example.COM
func main() {
    print "ok"
}
"""
    )
    LshOpen(docs, uri, source)

    links := LshDocumentLinks(docs, uri)
    assert links != null
    // The file says `Example.COM` with no trailing slash; the target says otherwise.
    assert LshHasLinkTargetContaining(links, "https://example.com/")
}

// A LINK ON A LATER LINE OF A BLOCK COMMENT REACHES THE EDITOR ON THAT LINE. The owner walks the
// comment text to find it; this row is what says the walk's answer survives the glue.
test "a document link inside a block comment reaches the editor on its own line" {
    docs := LshNewDocs()
    uri := "file:///test/document_link_block.nl"
    source := LshBody(
        """
/*
 * notes
 * follow https://n.example/deep for more
 */
func main() {
    print "ok"
}
"""
    )
    LshOpen(docs, uri, source)

    links := LshDocumentLinks(docs, uri)
    assert links != null
    assert LshLinkLine(links, "n.example/deep") == 2
    assert LshLinkStartCharacter(links, "n.example/deep") == 10
}

// THE PROTOCOL REQUIRES THAT A SYMBOL'S RANGE CONTAIN ITS SELECTION RANGE, at every level of the
// outline. A client is entitled to drop a symbol that breaks it, so nothing about a long name, a
// short line or a missing brace may produce one that does.
test "every document symbol's range contains its own selection range" {
    docs := LshNewDocs()
    uri := "file:///test/document_symbol_containment.nl"
    source := LshBody(
        """
enum Mood {
    Happy,
    Sad
}

class AVeryLongClassNameIndeed {
    Width: int
    Label: string

    func Area(): int {
        return Width
    }
}

func aVeryLongTopLevelFunctionName(): void {
    print "ok"
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    assert symbols.Count == 3
    LshAssertSymbolContainment(symbols)

    // A childless symbol says so by carrying NO child container at all.
    assert LshChildNamed(symbols, "aVeryLongTopLevelFunctionName").Children == null
    assert LshChildren(LshChildNamed(symbols, "Mood")).Count == 2
}

// EXPANDING THE SELECTION ALWAYS REACHES THE WHOLE FILE. The owner supplies that frame and the
// glue threads it in as the outermost parent, so following every `Parent` link from any position
// ends at the file.
test "the outermost selection range is always the whole file" {
    docs := LshNewDocs()
    uri := "file:///test/selection_range_root.nl"
    source := LshBody(
        """
class Box {
    func Area(): int {
        return 1
    }
}
"""
    )
    LshOpen(docs, uri, source)

    positions := new Position[](1)
    positions[0] = new Position(2, 15)

    ranges := LshSelectionRanges(docs, uri, positions)
    assert ranges != null

    chain := LshSelectionRangeList(ranges)
    assert chain.Count == 1

    // Walk out to the root, which must be the whole file and must contain every link below it.
    depth := 0
    current := chain[0]
    outermost := current
    while current.Parent != null {
        assert LshRangeContains(current.Parent.Range, current.Range)
        current = current.Parent
        outermost = current
        depth = depth + 1
    }

    assert depth > 0
    assert outermost.Range.Start.Line == 0
    assert outermost.Range.Start.Character == 0
    assert outermost.Range.End.Line == LshLines(source).Length - 1
}

// THE CLOSING-BRACE EDIT REPLACES THE WHOLE LINE, from its first character to its last, which is
// what lets the editor apply it as one undo step.
test "an on-type formatting edit replaces the whole line it re-indents" {
    docs := LshNewDocs()
    uri := "file:///test/on_type_whole_line.nl"
    source := LshBody(
        """
func main() {
    print "ok"
        }
"""
    )
    LshOpen(docs, uri, source)

    container := LshOnTypeFormatting(docs, uri, 2, 9, "}")
    assert container != null

    edits := LshTextEdits(container)
    assert edits.Count == 1
    assert edits[0].Range.Start.Line == 2
    assert edits[0].Range.Start.Character == 0
    assert edits[0].Range.End.Line == 2
    assert edits[0].Range.End.Character == LshLines(source)[2].Length
    assert edits[0].NewText == "}"
}
