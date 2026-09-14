namespace NSharpLang.CensusInitRequired.Tests


// The shape the docs promise: an `init` member is set by an object initializer and is a PROPERTY in
// the emitted metadata, because the CLR's only way to say "settable while the object is being
// created" is a setter carrying `modreq(IsExternalInit)`.
class Configuration {
    init AppName: string
    init Version: string
    Notes: string = ""
}

// An `init` member with a written initializer: the value the declaration gives is the value an
// object initializer that says nothing about it keeps.
class Defaulted {
    init Label: string = "default"
    init Count: int = 7
}

// A constructor of the declaring type may write an init-only member; that is initialization.
class Seeded {
    init Name: string
    Extra: int = 0

    constructor(seed: string) {
        Name = seed
    }

    func Read(): string {
        return Name
    }
}

// A derived type's constructor may write the base's init-only member, for the same reason.
class SeededBase {
    init Tag: string
}

class SeededDerived: SeededBase {
    constructor(tag: string): base() {
        Tag = tag
    }

    func ReadTag(): string {
        return Tag
    }
}

// An init-only member on a value type: the backing field is the struct's own storage.
struct Measurement {
    init Amount: int
    Unit: int
}

// An init-only member typed by the declaration's own type parameter. It is written by the
// declaring type's OWN constructor, which references the open definition's setter directly: a
// MemberRef to a closed generic type's `init` setter cannot carry `modreq(IsExternalInit)` (see
// website/docs/types.md "Current limits"), so an object initializer over `Holder<string>` declines.
class Holder<T> {
    init Value: T
    Slot: int

    constructor(seed: T) {
        Value = seed
    }
}

// A record's synthesized equality compares init-only members, because they are part of what the
// record IS.
record Pair {
    init Left: int
    init Right: int
}

// An init-only member that is also `required`: the creation must name it, and nothing after the
// creation may write it.
class Credentials {
    required init User: string
    Realm: string = "local"
}

// A static init-only property, written with an explicit accessor pair rather than as an auto
// member, so the modreq is checked on a DECLARED setter too.
class Declared {
    storage: string = ""

    init Managed: string {
        get {
            return storage
        }
        set {
            storage = value
        }
    }
}
