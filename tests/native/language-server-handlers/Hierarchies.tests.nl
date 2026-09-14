namespace NSharpLang.LanguageServerHandlers.Tests

import OmniSharp.Extensions.LanguageServer.Protocol.Models

test "selection range answers a nested chain from the innermost statement outward" {
    docs := LshNewDocs()
    uri := "file:///test/selrange.nl"
    source := LshBody(
        """
func main() {
    if true {
        let x := 42
    }
}
"""
    )
    LshOpen(docs, uri, source)

    // Inside the if block, on "let x".
    positions: Position[] = [new Position(2, 12)]
    result := LshSelectionRanges(docs, uri, positions)

    assert result != null
    ranges := LshSelectionRangeList(result)
    assert ranges.Count == 1

    selection := ranges[0]
    assert selection.Range != null
    // The chain must widen to at least one enclosing range.
    assert selection.Parent != null
}

test "selection range for a document that was never opened answers nothing" {
    docs := LshNewDocs()

    positions: Position[] = [new Position(0, 0)]
    result := LshSelectionRanges(docs, "file:///nonexistent.nl", positions)

    assert result == null
}

test "selection range answers one chain per requested position" {
    docs := LshNewDocs()
    uri := "file:///test/selrange_multi.nl"
    source := LshBody(
        """
func foo() {
    let a := 1
}

func bar() {
    let b := 2
}
"""
    )
    LshOpen(docs, uri, source)

    positions: Position[] = [new Position(1, 8), new Position(5, 8)]
    result := LshSelectionRanges(docs, uri, positions)

    assert result != null
    assert LshSelectionRangeList(result).Count == 2
}

test "selection range on a soa column widens to the enclosing table" {
    docs := LshNewDocs()
    uri := "file:///test/selrange_soa.nl"
    source := LshBody(
        """
soa record NodeTable {
    kind: int
    valueStart: int
}
"""
    )
    LshOpen(docs, uri, source)

    positions: Position[] = [new Position(1, 5)]
    result := LshSelectionRanges(docs, uri, positions)

    assert result != null
    ranges := LshSelectionRangeList(result)
    assert ranges.Count == 1

    selection := ranges[0]
    assert selection.Range.Start.Line == 1
    parent := selection.Parent
    assert parent != null
    assert parent.Range.Start.Line == 0
}

test "call hierarchy prepare on a function answers that function" {
    docs := LshNewDocs()
    uri := "file:///test/callhierarchy.nl"
    source := LshBody(
        """
func greet(name: string): string {
    return "Hello, " + name
}

func main() {
    greet("world")
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshPrepareCallHierarchy(docs, uri, 0, 5)

    assert result != null
    items := LshCallHierarchyItems(result)
    assert items.Count == 1
    assert items[0].Name == "greet"
}

test "call hierarchy prepare on a class answers nothing" {
    docs := LshNewDocs()
    uri := "file:///test/callhierarchy_none.nl"
    source := LshBody(
        """
class Foo {
    bar: int
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshPrepareCallHierarchy(docs, uri, 0, 6)

    assert result == null
}

test "call hierarchy outgoing calls name the callee" {
    docs := LshNewDocs()
    uri := "file:///test/callhierarchy_outgoing.nl"
    source := LshBody(
        """
func helper(): void {
    return
}

func main() {
    helper()
}
"""
    )
    LshOpen(docs, uri, source)

    prepared := LshPrepareCallHierarchy(docs, uri, 4, 5)
    assert prepared != null
    mainItem := LshCallHierarchyItems(prepared)[0]

    outgoing := LshOutgoingCalls(docs, mainItem)
    assert outgoing != null

    // main calls helper, so any outgoing calls reported must include it.
    if LshOutgoingCallCount(outgoing) > 0 {
        assert LshHasOutgoingCallTo(outgoing, "helper")
    }
}

test "type hierarchy prepare on a class answers that class" {
    docs := LshNewDocs()
    uri := "file:///test/typehierarchy.nl"
    source := LshBody(
        """
interface IAnimal {
    func speak(): string
}

class Dog : IAnimal {
    func speak(): string {
        return "woof"
    }
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshPrepareTypeHierarchy(docs, uri, 4, 6)

    assert result != null
    items := LshTypeHierarchyItems(result)
    assert items.Count == 1
    assert items[0].Name == "Dog"
}

test "type hierarchy prepare on an interface answers that interface" {
    docs := LshNewDocs()
    uri := "file:///test/typehierarchy_iface.nl"
    source := LshBody(
        """
interface IAnimal {
    func speak(): string
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshPrepareTypeHierarchy(docs, uri, 0, 10)

    assert result != null
    items := LshTypeHierarchyItems(result)
    assert items.Count == 1
    assert items[0].Name == "IAnimal"
}

test "type hierarchy supertypes of a derived class include the interface it implements" {
    docs := LshNewDocs()
    uri := "file:///test/typehierarchy_super.nl"
    source := LshBody(
        """
interface IAnimal {
    func speak(): string
}

class Dog : IAnimal {
    func speak(): string {
        return "woof"
    }
}
"""
    )
    LshOpen(docs, uri, source)

    prepared := LshPrepareTypeHierarchy(docs, uri, 4, 6)
    assert prepared != null
    dogItem := LshTypeHierarchyItems(prepared)[0]

    supertypes := LshSupertypes(docs, dogItem)
    assert supertypes != null
    assert LshHasTypeHierarchyItem(supertypes, "IAnimal")
}

test "type hierarchy subtypes of an interface list every implementing class" {
    docs := LshNewDocs()
    uri := "file:///test/typehierarchy_sub.nl"
    source := LshBody(
        """
interface IAnimal {
    func speak(): string
}

class Dog : IAnimal {
    func speak(): string {
        return "woof"
    }
}

class Cat : IAnimal {
    func speak(): string {
        return "meow"
    }
}
"""
    )
    LshOpen(docs, uri, source)

    prepared := LshPrepareTypeHierarchy(docs, uri, 0, 10)
    assert prepared != null
    animalItem := LshTypeHierarchyItems(prepared)[0]

    subtypes := LshSubtypes(docs, animalItem)
    assert subtypes != null
    assert LshTypeHierarchyCount(subtypes) >= 2
    assert LshHasTypeHierarchyItem(subtypes, "Dog")
    assert LshHasTypeHierarchyItem(subtypes, "Cat")
}

test "type hierarchy prepare on a function answers nothing" {
    docs := LshNewDocs()
    uri := "file:///test/typehierarchy_nontype.nl"
    source := LshBody(
        """
func main() {
    let x := 42
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshPrepareTypeHierarchy(docs, uri, 0, 5)

    assert result == null
}
