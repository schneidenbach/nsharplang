namespace NSharpLang.GenericMemberTypes.Tests

import System.Collections.Generic


// A MEMBER SIGNATURE THAT NAMES THE DECLARING TYPE'S PARAMETER, ON A MEMBER WITH NONE OF ITS OWN.
//
// `Shelf<T>.Gather` has no type parameters, yet `IEnumerable<T>` in its signature is as open as any
// generic method's: it is a type only once an instantiation says what `T` is. A STATIC member used
// to decline exactly this — `static method return type 'List<T>' could not be resolved` — because
// its signature was resolved as if the member stood at file level, where no `T` is in scope. Every
// static and instance member below writes an open shape in a return or a parameter position, and
// each one is called on two instantiations beside this file, so a signature that resolved without
// being callable would not survive.
class Shelf<T> {
    Items: List<T>

    constructor() {
        Items = new List<T>()
    }

    // Static, open PARAMETER and a constructed-owner return.
    static func Gather(values: IEnumerable<T>): Shelf<T> {
        shelf := new Shelf<T>()
        for v in values {
            shelf.Items.Add(v)
        }
        return shelf
    }

    // Static, open RETURN over an external generic.
    static func Single(value: T): List<T> {
        items := new List<T>()
        items.Add(value)
        return items
    }

    // Static, the parameter nested one level down and a closed key beside it.
    static func Index(values: List<T>): Dictionary<int, T> {
        map := new Dictionary<int, T>()
        for i := 0; i < values.Count; i += 1 {
            map[i] = values[i]
        }
        return map
    }

    static func CountAll(groups: List<List<T>>): int {
        n := 0
        for group in groups {
            n += group.Count
        }
        return n
    }

    // Instance, the same shapes: an open parameter, an open return, and one nested in another.
    func AddAll(values: IEnumerable<T>): int {
        for v in values {
            Items.Add(v)
        }
        return Items.Count
    }

    func Snapshot(): List<T> {
        return new List<T>(Items)
    }

    func Grouped(): Dictionary<int, List<T>> {
        map := new Dictionary<int, List<T>>()
        map[Items.Count] = Items
        return map
    }
}
