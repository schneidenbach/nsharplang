namespace NSharpLang.CensusExplicitInterfaceImplementation.Tests

import System.Collections
import System.Collections.Generic


// THE TYPES THE ROWS BESIDE THIS FILE EXERCISE.
//
// `Bag` IS THE ACCEPTANCE CASE and it is not an invented one: `IEnumerable<T>` inherits the
// non-generic `IEnumerable`, their two `GetEnumerator` slots differ ONLY in return type, and an
// ordinary member can fill exactly one of them. Before explicit implementation existed, no N# type
// could implement `IEnumerable<T>` at all — which is why a collection type written in N# could not be
// used in a `for … in`, could not be passed to LINQ, and could not be consumed by C#.
class Bag: IEnumerable<string> {
    items: List<string> = new List<string>()

    func Add(value: string) {
        items.Add(value)
    }

    // THE IMPLICIT MEMBER. It is a member of `Bag` AND it fills `IEnumerable<string>`'s slot, which is
    // the ordinary way a type implements an interface.
    func GetEnumerator(): IEnumerator<string> {
        generic: IEnumerable<string> = items
        return generic.GetEnumerator()
    }

    // THE EXPLICIT ONE, of the SAME simple name. Its key in every member table is the qualified
    // spelling, so it does not collide with the member above and is not reachable through `Bag`.
    func IEnumerable.GetEnumerator(): IEnumerator {
        untyped: IEnumerable = items
        return untyped.GetEnumerator()
    }
}

// TWO INTERFACES THAT DECLARE THE SAME MEMBER NAME, which is the other shape the feature is for: one
// type, two slots, two bodies, and no way to spell the second without a qualifier.
interface IReader {
    func Read(): string
}

interface IScanner {
    func Read(): string
}

class Duplex: IReader, IScanner {
    func IReader.Read(): string => "reader"

    func IScanner.Read(): string => "scanner"
}

// A VALUE MEMBER takes the same qualifier. Its accessor is named inside the qualification —
// `…ILabeled.get_Label` — which is what a C# compiler emits and what a C# consumer looks for.
interface ILabeled {
    Label: string
}

class Hidden: ILabeled {
    ILabeled.Label: string => "hidden"
}

// A GENERIC SOURCE INTERFACE, written CLOSED exactly as the implements list writes it.
interface IBox<T> {
    Item: T

    func Unwrap(): T
}

class StringBox: IBox<string> {
    IBox<string>.Item: string => "boxed"

    func IBox<string>.Unwrap(): string => "unwrapped"
}

// A TYPE WITH AN EXPLICIT MEMBER AND NOTHING ELSE OF THAT NAME. The interface reaches it; the type
// does not expose it. This is the control for the reachability rule.
interface ICounter {
    func Tick(): int
}

class Silent: ICounter {
    func ICounter.Tick(): int => 7

    func Describe(): string => "silent"
}
