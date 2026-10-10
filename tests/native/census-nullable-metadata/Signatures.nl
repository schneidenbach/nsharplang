namespace Census.NullableMetadata

import System.Collections.Generic


// THE SURFACE WHOSE EMITTED METADATA THE TESTS READ BACK.
//
// Nothing here is called. Each member exists so that the assembly this project emits carries the
// signature position the test beside it reflects over — which is the only way to prove that the
// `?`s written in N# source SURVIVED into metadata. A same-compilation caller never notices: it
// binds against the source types. Only a reader coming in through reflection, as the analyzer does
// for a REFERENCED N# assembly, can see whether the annotation was written down.
class Signatures {
    Label: string?
    Plain: string
    Count: int

    constructor() {
        Label = null
        Plain = ""
        Count = 0
    }

    static func Take(values: Dictionary<string, object?>?): int {
        if values == null {
            return 0
        }

        return values.Count
    }

    static func Name(): string? {
        return null
    }

    static func Required(text: string): string {
        return text
    }

    static func Total(count: int): int {
        return count
    }

    static func Map(): Dictionary<string, object?> {
        return new Dictionary<string, object?>()
    }

    static func Ints(): List<int> {
        return new List<int>()
    }

    static func MaybeNames(): string[]? {
        return null
    }

    static func NamesWithHoles(): string?[] {
        return new string?[](0)
    }

    static func Pair(): (Min: int, Max: string?) {
        return (0, null)
    }
}

class SignatureInitOnly {
    init Tag: string?
    init Registry: Dictionary<string, object?>
    init Total: int
}

class SignatureProperties {
    Names: List<string?>
    Slot: string?

    constructor() {
        Names = new List<string?>()
        Slot = null
    }

    Lookup: Dictionary<string, object?> => new Dictionary<string, object?>()
    Tally: int => 0
}
