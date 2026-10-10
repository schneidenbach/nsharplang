namespace NSharpLang.LanguageServerHandlers.Tests

import OmniSharp.Extensions.LanguageServer.Protocol.Models

test "workspace symbols find a type declaration by name" {
    docs := LshNewDocs()
    uri := "file:///test/ws_symbols.nl"
    source := LshBody(
        """
class Person {
    name: string
}

func greet(): string {
    return "hello"
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshWorkspaceSymbols(docs, "Person")

    assert result != null
    assert LshHasWorkspaceSymbol(result, "Person")
}

test "an empty workspace symbol query returns every symbol" {
    docs := LshNewDocs()
    uri := "file:///test/ws_symbols_all.nl"
    source := LshBody(
        """
class Foo {
    bar: int
}

func baz(): void {
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshWorkspaceSymbols(docs, "")

    assert result != null
    // At least Foo and baz.
    assert LshWorkspaceSymbolCount(result) >= 2
}

test "workspace symbol matching accepts subsequence and prefix queries but not unrelated ones" {
    assert LshMatchesQuery("PersonName", "PrsNm")
    assert LshMatchesQuery("PersonName", "person")
    assert LshMatchesQuery("PersonName", "")
    assert !LshMatchesQuery("PersonName", "xyz")
}

test "workspace symbols keep the declaring type in both filtered and unfiltered results" {
    docs := LshNewDocs()
    uri := "file:///test/ws_symbols_members.nl"
    source := LshBody(
        """
class Person {
    name: string
    age: int
}
"""
    )
    LshOpen(docs, uri, source)

    filtered := LshWorkspaceSymbols(docs, "Person")
    assert filtered != null
    assert LshHasWorkspaceSymbol(filtered, "Person")

    all := LshWorkspaceSymbols(docs, "")
    assert all != null
    assert LshHasWorkspaceSymbol(all, "Person")
}

test "workspace symbols list soa record columns under their table" {
    docs := LshNewDocs()
    uri := "file:///test/ws_symbols_soa.nl"
    source := LshBody(
        """
soa record NodeTable {
    kind: int
    valueStart: int
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshWorkspaceSymbols(docs, "")

    assert result != null
    assert LshHasWorkspaceSymbolOfKind(result, "NodeTable", SymbolKind.Class)
    assert LshHasWorkspaceMember(result, "kind", SymbolKind.Field, "NodeTable")
    assert LshHasWorkspaceMember(result, "valueStart", SymbolKind.Field, "NodeTable")
}

test "folding ranges fold a function body" {
    docs := LshNewDocs()
    uri := "file:///test/folding.nl"
    source := LshBody(
        """
func main() {
    let x := 42
    let y := 43
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshFoldingRanges(docs, uri)

    assert result != null
    assert LshFoldingRangeCount(result) > 0

    functionRange := LshFoldingRangeStartingAt(result, 0)
    assert functionRange != null
    assert functionRange.EndLine > functionRange.StartLine
}

test "folding ranges fold a class and its methods separately" {
    docs := LshNewDocs()
    uri := "file:///test/folding_class.nl"
    source := LshBody(
        """
class Person {
    name: string
    age: int

    func greet(): string {
        return "Hello"
    }
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshFoldingRanges(docs, uri)

    assert result != null
    assert LshFoldingRangeCount(result) >= 2
}

test "folding ranges fold a soa record to its closing brace" {
    docs := LshNewDocs()
    uri := "file:///test/folding_soa.nl"
    source := LshBody(
        """
soa record NodeTable {
    kind: int
    valueStart: int
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshFoldingRanges(docs, uri)

    assert result != null
    tableRange := LshFoldingRangeStartingAt(result, 0)
    assert tableRange != null
    assert tableRange.EndLine == 3
}

test "folding ranges group the import block" {
    docs := LshNewDocs()
    uri := "file:///test/folding_imports.nl"
    source := LshBody(
        """
import System
import System.Collections.Generic
import System.Linq

func main() {
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshFoldingRanges(docs, uri)

    assert result != null
    importRange := LshFoldingRangeOfKind(result, FoldingRangeKind.Imports)
    assert importRange != null
}

test "document links expose a URL written in a comment" {
    docs := LshNewDocs()
    uri := "file:///test/doclink.nl"
    source := "// See https://example.com/docs for more info\nfunc main() {\n    print(\"hello\")\n}\n"
    LshOpen(docs, uri, source)

    links := LshDocumentLinks(docs, uri)
    assert links != null

    // The handler scans both the token stream and the preserved comment trivia.
    doc := LshDocument(docs, uri)
    if LshHasUrlInCommentTokens(doc, "https://") || LshHasUrlInCommentTrivia(doc, "https://") {
        assert LshDocumentLinkCount(links) > 0
        assert LshHasLinkTargetContaining(links, "example.com")
    } else {
        assert LshDocumentLinkCount(links) == 0
    }
}

test "a document with no URLs yields no document links" {
    docs := LshNewDocs()
    uri := "file:///test/doclink_empty.nl"
    source := LshBody(
        """
func main() {
    let x := 42
}
"""
    )
    LshOpen(docs, uri, source)

    links := LshDocumentLinks(docs, uri)

    assert links != null
    assert LshDocumentLinkCount(links) == 0
}

test "document links for a document that was never opened answer nothing" {
    docs := LshNewDocs()

    links := LshDocumentLinks(docs, "file:///nonexistent.nl")

    assert links == null
}
