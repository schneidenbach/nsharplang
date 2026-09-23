namespace NSharpLang.CensusExplicitInterfaceImplementation.Tests

import System.Collections
import System.Linq


// WHAT AN EXPLICIT INTERFACE IMPLEMENTATION DOES AT RUN TIME.
//
// Every row here EXECUTES. A declared return type proves nothing on its own: what proves the right
// method was selected is which VALUE comes back, because the two members in play differ only in what
// they return.
test "a `for … in` over a source collection type reaches the generic slot" {
    bag := new Bag()
    bag.Add("a")
    bag.Add("bb")

    joined := ""
    for item in bag {
        joined = joined + item
    }

    assert joined == "abb"
}

test "the non-generic interface reaches the EXPLICIT member, and the type reaches the implicit one" {
    bag := new Bag()
    bag.Add("a")
    bag.Add("bb")

    // THROUGH THE TYPE: the ordinary member, whose enumerator is typed.
    typed := bag.GetEnumerator()
    assert typed.MoveNext()
    assert typed.Current == "a"

    // THROUGH THE INTERFACE: the explicit member. Its `Current` is `object`, which is exactly the
    // difference between the two slots — so this row could not pass if the wrong one were bound.
    untyped: IEnumerable = bag
    walker := untyped.GetEnumerator()
    assert walker.MoveNext()
    assert walker.Current.ToString() == "a"
    assert walker.MoveNext()
    assert walker.Current.ToString() == "bb"
    assert !walker.MoveNext()
}

test "LINQ sees the source collection type as the sequence it is" {
    bag := new Bag()
    bag.Add("a")
    bag.Add("bb")

    // THE STATIC SPELLING. `bag.Count()` — the extension-method spelling — does not bind yet, because
    // extension-receiver matching cannot read a SOURCE type's own interface list; that is a separate
    // defect this feature made reachable for the first time and it is recorded, not papered over.
    assert Enumerable.Count<string>(bag) == 2
    assert Enumerable.First<string>(bag) == "a"

    assert Enumerable.Last<string>(bag) == "bb"
}

test "two interfaces that declare one member name get one body each" {
    duplex := new Duplex()

    reader: IReader = duplex
    scanner: IScanner = duplex

    assert reader.Read() == "reader"
    assert scanner.Read() == "scanner"
}

test "a value member is reached through its interface" {
    hidden := new Hidden()
    labeled: ILabeled = hidden
    assert labeled.Label == "hidden"
}

test "a closed generic source interface reaches both of its explicit members" {
    box := new StringBox()
    view: IBox<string> = box
    assert view.Item == "boxed"
    assert view.Unwrap() == "unwrapped"
}

test "a type whose only implementation is explicit still dispatches through the interface" {
    silent := new Silent()
    counter: ICounter = silent
    assert counter.Tick() == 7

    // And the type's own surface is unchanged by it.
    assert silent.Describe() == "silent"
}
