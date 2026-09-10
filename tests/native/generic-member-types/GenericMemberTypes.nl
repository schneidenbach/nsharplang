namespace NSharpLang.GenericMemberTypes.Tests

import System.Collections.Generic


// AN EXTERNAL GENERIC CLOSED OVER THE DECLARING TYPE'S OWN TYPE PARAMETER.
//
// `List<T>` and `Dictionary<string, T>` already resolved as member types. Two shapes did not, and
// neither had anything to do with the family involved:
//
//   * A NULLABLE ANNOTATION. `List<T>?` declined where `List<T>` resolved, because the walk that
//     knows about type parameters had no `?` branch at all — the annotation was simply part of the
//     name. Every reference type in this language may be written `T?`, so the annotation must be
//     read wherever the type is.
//   * THE DELEGATE FAMILIES. `Action<T>` and `Func<T, TResult>` were handed to the walk that does
//     NOT know about type parameters, so `T` was an unknown name. They are ordinary constructed
//     external generics and now resolve on the same walk as everything else.
//
// Everything here is a member of a GENERIC type whose own parameter appears inside an external
// generic. The fields are read and written and the delegates are called, so a type that merely
// resolved without being storable or loadable would not survive these tests.
class Holder<T> {
    items: List<T>
    lookup: Dictionary<string, T>
    optionalItems: List<T>?
    onEach: Action<T>?
    readonly pick: Func<T, bool>

    constructor(items: List<T>, lookup: Dictionary<string, T>, pick: Func<T, bool>) {
        this.items = items
        this.lookup = lookup
        this.optionalItems = null
        this.onEach = null
        this.pick = pick
    }

    Items: List<T> => items
    Lookup: Dictionary<string, T> => lookup
    OptionalItems: List<T>? => optionalItems
    OnEach: Action<T>? => onEach
    Pick: Func<T, bool> => pick

    func Add(item: T) {
        items.Add(item)
    }

    func Adopt(more: List<T>?) {
        optionalItems = more
    }

    func Listen(listener: Action<T>?) {
        onEach = listener
    }

    // Calling a delegate closed over the declaring type's own parameter. The `Invoke` handle cannot
    // be asked for by name on a builder-bound instantiation, so it is rebound from the open
    // definition — and the signature is read from the instantiation's own generic arguments.
    func Announce(item: T): bool {
        current := onEach
        if current != null {
            current(item)
        }
        chooser := pick
        return chooser(item)
    }

    func Selected(): List<T> {
        chooser := pick
        chosen := new List<T>()
        for item in items {
            if chooser(item) {
                chosen.Add(item)
            }
        }
        return chosen
    }
}

// The same shapes as a PARAMETER, a LOCAL and a RETURN type of a generic free function, not just as
// fields, so the admissibility rule is proved where the type is spelled and not only where it is
// stored.
func FirstMatch<T>(items: List<T>, pick: Func<T, bool>, fallback: T): T {
    chooser: Func<T, bool> = pick
    for item in items {
        if chooser(item) {
            return item
        }
    }
    return fallback
}

func Sink<T>(items: List<T>, listener: Action<T>) {
    for item in items {
        listener(item)
    }
}
