namespace NSharpLang.CensusEmitShapes.Tests

import System.Collections.Generic


// A BARE STATIC MEMBER OF THE ENCLOSING TYPE IS A VALUE IN RECEIVER POSITION.
//
// A bare identifier in front of a `.` is one of two things — a value or a type name — and a static
// field of the enclosing type was classified as neither, so `Entries.Add(name)` was read as a call
// on a TYPE named `Entries`, found no such type, and declined the whole statement. The same name
// read as a value (`local := Entries`), and the same call written through that local, both emitted,
// which is what made the misclassification visible: nothing about the call was unsupported.
//
// A static member belongs to the TYPE, so it is in scope in every body the type owns — a static
// method, an instance method, and a static accessor alike; each spelling below is that one rule.
class Registry {
    static Entries: List<string> = new List<string>()
    static Tags: List<string> = new List<string>()

    static Spelled: List<string> => Tags

    static func Add(name: string) {
        Entries.Add(name)
    }

    static func Has(name: string): bool {
        return Entries.Contains(name)
    }

    static func Total(): int {
        return Entries.Count
    }

    static func Qualified(name: string) {
        Registry.Entries.Add(name)
    }

    static func Clear() {
        Entries.Clear()
        Tags.Clear()
    }

    // The same receiver named from an INSTANCE body, where `this` exists and the member still
    // belongs to the type rather than to the instance.
    func AddFromInstance(name: string) {
        Entries.Add(name)
    }

    // A static PROPERTY in the same position: the getter call produces the receiver value.
    static func Tag(name: string) {
        Spelled.Add(name)
    }

    static func TagCount(): int {
        return Spelled.Count
    }
}

// The same rule through an inheritance chain: a static member declared by the BASE is a member of
// the derived type's bodies too, and the chain walk that finds it is the one the bare read uses.
class BaseCounter {
    static Seen: List<int> = new List<int>()
}

class DerivedCounter: BaseCounter {
    static func Record(value: int) {
        Seen.Add(value)
    }

    static func SeenCount(): int {
        return Seen.Count
    }

    static func Reset() {
        Seen.Clear()
    }
}
