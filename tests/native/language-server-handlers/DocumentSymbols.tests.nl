namespace NSharpLang.LanguageServerHandlers.Tests

import OmniSharp.Extensions.LanguageServer.Protocol.Models

test "document symbols list top-level functions with their return types" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := LshBody(
        """
func greet(name: string): string
    return "Hello, " + name

func main(): void
    greet("world")
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    assert symbols.Count == 2

    assert symbols[0].Name == "greet"
    assert symbols[0].Kind == SymbolKind.Function
    assert symbols[0].Detail == "string"

    assert symbols[1].Name == "main"
    assert symbols[1].Kind == SymbolKind.Function
    assert symbols[1].Detail == "void"
}

test "document symbols nest class fields and methods under the class" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := LshBody(
        """
class Person {
    name: string
    age: int

    func greet(): string
        return "Hello, " + name
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    assert symbols.Count == 1

    person := symbols[0]
    assert person.Name == "Person"
    assert person.Kind == SymbolKind.Class
    assert person.Children != null

    children := LshChildren(person)
    assert LshHasChild(children, "name", SymbolKind.Field)
    assert LshHasChild(children, "age", SymbolKind.Field)
    assert LshHasChild(children, "greet", SymbolKind.Function)
}

test "document symbols report a struct and its fields" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := LshBody(
        """
struct Point {
    x: int
    y: int
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    assert symbols.Count == 1
    assert symbols[0].Name == "Point"
    assert symbols[0].Kind == SymbolKind.Struct
    assert symbols[0].Children != null
    assert LshChildren(symbols[0]).Count == 2
}

test "document symbols report a soa record and its typed columns" {
    docs := LshNewDocs()
    uri := "file:///test/soa_symbols.nl"
    source := LshBody(
        """
soa record NodeTable {
    kind: int
    text: string
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    assert symbols.Count == 1

    table := symbols[0]
    assert table.Name == "NodeTable"
    assert table.Kind == SymbolKind.Class
    assert table.Detail == "soa"
    assert table.Children != null

    columns := LshChildren(table)
    assert LshHasChildDetail(columns, "kind", SymbolKind.Field, "int")
    assert LshHasChildDetail(columns, "text", SymbolKind.Field, "string")
}

test "document symbols report an interface declaration" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := LshBody(
        """
interface Greeter {
    func greet(): string
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    assert symbols.Count == 1
    assert symbols[0].Name == "Greeter"
    assert symbols[0].Kind == SymbolKind.Interface
}

test "document symbols report enum members as enum members" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := LshBody(
        """
enum Color {
    Red,
    Green,
    Blue
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    assert symbols.Count == 1
    assert symbols[0].Name == "Color"
    assert symbols[0].Kind == SymbolKind.Enum
    assert symbols[0].Children != null

    members := LshChildren(symbols[0])
    assert members.Count == 3
    index := 0
    while index < members.Count {
        assert members[index].Kind == SymbolKind.EnumMember
        index = index + 1
    }
    assert LshHasChild(members, "Red", SymbolKind.EnumMember)
    assert LshHasChild(members, "Green", SymbolKind.EnumMember)
    assert LshHasChild(members, "Blue", SymbolKind.EnumMember)
}

test "document symbols for a document that was never opened answer nothing" {
    docs := LshNewDocs()

    result := LshDocumentSymbols(docs, "file:///empty.nl")

    assert result == null
}

test "document symbols keep declaration order across mixed declaration kinds" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := LshBody(
        """
enum Status {
    Active,
    Inactive
}

class User {
    name: string
    status: Status
}

func createUser(name: string): User
    return User()
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    assert symbols.Count == 3

    assert symbols[0].Name == "Status"
    assert symbols[0].Kind == SymbolKind.Enum

    assert symbols[1].Name == "User"
    assert symbols[1].Kind == SymbolKind.Class

    assert symbols[2].Name == "createUser"
    assert symbols[2].Kind == SymbolKind.Function
}

test "document symbol ranges are zero-based and never zero-width" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := LshBody(
        """
func hello(): void
    return
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    assert symbols.Count == 1

    // LSP lines are 0-based, so the first source line is line 0.
    assert symbols[0].Range.Start.Line == 0
    assert symbols[0].SelectionRange.Start.Line == 0

    // Range must not be zero-width when SelectionRange has content.
    assert symbols[0].Range.End.Character > 0 || symbols[0].Range.End.Line > symbols[0].Range.Start.Line
}

test "a document symbol range contains its own selection range" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := LshBody(
        """
class Foo {
    bar: int
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshDocumentSymbols(docs, uri)
    assert result != null

    symbols := LshSymbols(result)
    foo := symbols[0]

    assert foo.Range.End.Line >= foo.SelectionRange.End.Line
    assert foo.Range.End.Character >= foo.SelectionRange.End.Character || foo.Range.End.Line > foo.SelectionRange.End.Line

    bar := LshChildNamed(LshChildren(foo), "bar")
    assert bar.Range.End.Character >= bar.SelectionRange.End.Character || bar.Range.End.Line > bar.SelectionRange.End.Line
}
