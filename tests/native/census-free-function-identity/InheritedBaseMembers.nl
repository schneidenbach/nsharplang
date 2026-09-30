namespace Census.FreeFunctionIdentity.Inherited

import System.Collections.Generic


// A BARE NAME INSIDE A TYPE THAT FINDS AN INHERITED MEMBER IS THAT MEMBER THROUGH `this`.
//
// When the member comes from a CLOSED EXTERNAL GENERIC base, what the base's `T` is lives in the `:`
// clause — `class Names: List<string>` — and the bare call had no receiver to read it off. So
// `ToArray()` typed as the open `T[]` (NL202 "returns T" on a function declared `string`) while
// `this.ToArray()` typed as `string[]`, and a lambda handed to `ConvertAll` had no parameter type.
// Both spellings now bind through the enclosing instance, and these rows EXECUTE the emitted calls.
//
// The backend had the matching hole: an inherited call whose argument is a LAMBDA is not one the
// direct-call planner can type ahead of its target, and the residual tiers it falls to never looked
// past the source chain — so `ConvertAll(s => s.Length)` declined in BOTH spellings, and a generic
// method's lambda-inferred type argument (`TOutput`) declined through an outside receiver as well.
class Names: List<string> {
    func FirstBare(): string => ToArray()[0]

    func FirstViaThis(): string => this.ToArray()[0]

    func LengthsBare(): List<int> => ConvertAll(s => s.Length)

    func LengthsViaThis(): List<int> => this.ConvertAll(s => s.Length)

    // The same call as an OPERAND: its result has to be typed before `.Count` can be read off it.
    func LengthCountBare(): int => ConvertAll(s => s.Length).Count

    // A NON-generic inherited method taking a lambda, in both spellings.
    func HasPairBare(): bool => Exists(s => s.Length == 2)

    func HasPairViaThis(): bool => this.Exists(s => s.Length == 2)

    func PositionBare(item: string): int => IndexOf(item)
}

// A SOURCE BASE BETWEEN the type and the external one. `Mid<U>`'s `U` is substituted on the way to
// `List<U>`, so `Deep`'s `T` is `string`; the walk used to stop at the generic middle link, which also
// left `deep.Add(...)` from OUTSIDE the type binding against nothing.
class Mid<U>: List<U> {
}

class Deep: Mid<string> {
    func FirstBare(): string => ToArray()[0]

    func FirstViaThis(): string => this.ToArray()[0]

    func ShoutBare(): string => ToArray()[0].ToUpper()
}

// THE SPELLED ARGUMENT'S NULLABILITY. The CLR cannot tell `List<string?>` from `List<string>`, so the
// element's `?` is read off the written base: the bare read is `string?`, and the null test is real.
class MaybeNames: List<string?> {
    func FirstOrEmptyBare(): string {
        first := ToArray()[0]
        if first == null {
            return "<none>"
        }

        return first
    }
}

// A STATIC member of the external generic base, named bare: `Comparer<T>.Create(Comparison<T>)`.
// The lambda's parameters are `string` because the base is `Comparer<string>`.
class ByLength: Comparer<string> {
    override func Compare(x: string?, y: string?): int {
        if x == null || y == null {
            return 0
        }

        return x.Length - y.Length
    }

    func LongestFirstBare(): Comparer<string> => Create((a, b) => b.Length - a.Length)
}

// A BASE CLOSED OVER A TYPE THIS COMPILATION IS WRITING. `List<Tag>` has no finished CLR form while
// `Tag` is being emitted, so the base is a builder instantiation; the member is still chosen on it by
// the same ordinary selection an outside `tags.Exists(...)` gets, and `this` is the receiver.
class Tag {
    Label: string

    constructor(label: string) {
        Label = label
    }
}

class Tags: List<Tag> {
    func FirstBare(): Tag => ToArray()[0]

    func AddBare(label: string) {
        Add(new Tag(label))
    }

    func HasBare(label: string): bool => Exists(tag => tag.Label == label)

    func HasViaThis(label: string): bool => this.Exists(tag => tag.Label == label)
}
