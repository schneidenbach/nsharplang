namespace NSharpLang.CensusFlowRules.Tests

import System


// `==` AND `!=` BETWEEN A MAYBE-NULL REFERENCE AND ANOTHER REFERENCE.
//
// A reference `?` says the value may be the null reference; it is an annotation on the one CLR type,
// not a type of its own, so it does not change which equality applies. Two references compare by
// IDENTITY unless the type declares `operator ==`, and then the operator decides -- with or without
// the `?`, on either side. The analyzer refused `Tally? == Tally` and even `Entry? == Entry?` for a
// source class, while `string? == string` compared (its operator is declared over `string?`) and a
// REFERENCED class's operator already bound through its CLR type; `census-external-operands` holds
// that referenced half. The types carry an `Equality` prefix because the namespace is shared with
// the rest of this census.
class EqualityEntry {
    Key: string

    constructor(key: string) {
        Key = key
    }
}

class EqualitySpecialEntry: EqualityEntry {
    constructor(key: string): base(key) {
    }
}

class EqualityTally {
    Count: int

    constructor(count: int) {
        Count = count
    }

    static func operator ==(left: EqualityTally?, right: EqualityTally?): bool {
        if Object.ReferenceEquals(left, right) {
            return true
        }
        if left == null || right == null {
            return false
        }
        return left.Count == right.Count
    }

    static func operator !=(left: EqualityTally?, right: EqualityTally?): bool => !(left == right)
}

class EqualityMeasure {
    Size: int

    constructor(size: int) {
        Size = size
    }

    static func operator ==(left: EqualityMeasure, right: EqualityMeasure): bool => left.Size == right.Size

    static func operator !=(left: EqualityMeasure, right: EqualityMeasure): bool => left.Size != right.Size
}

func MaybeEqualsPlain(left: EqualityEntry?, right: EqualityEntry): bool => left == right

func PlainDiffersMaybe(left: EqualityEntry, right: EqualityEntry?): bool => left != right

func MaybeEqualsMaybe(left: EqualityEntry?, right: EqualityEntry?): bool => left == right

func MaybeEqualsDerived(left: EqualityEntry?, right: EqualitySpecialEntry): bool => left == right

func MaybeObjectEqualsPlain(left: object?, right: EqualityEntry): bool => left == right

func TallyMaybeEqualsPlain(left: EqualityTally?, right: EqualityTally): bool => left == right

func TallyMaybeDiffersMaybe(left: EqualityTally?, right: EqualityTally?): bool => left != right

func MeasureMaybeEqualsPlain(left: EqualityMeasure?, right: EqualityMeasure): bool => left == right
