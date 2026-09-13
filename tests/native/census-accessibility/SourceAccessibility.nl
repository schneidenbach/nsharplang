namespace NSharpLang.CensusAccessibility.Tests


// A SOURCE BASE THAT DECLARES ONE MEMBER AT EVERY ACCESSIBILITY, so the relation can be read off
// real emitted metadata and exercised at run time from each side of every boundary it draws.
class AccessBase {
    protected Seed: int = 3
    private secretCount: int = 9
    internal protected Shared: int = 5
    Open: int = 7

    // The one legal reader of a `private` member is the declaring type itself.
    func RevealSecret(): int {
        return secretCount
    }

    protected func ProtectedDouble(value: int): int {
        return value * 2
    }

    private func PrivateTriple(value: int): int {
        return value * 3
    }

    func TripleThroughPrivate(value: int): int {
        return PrivateTriple(value)
    }

    protected virtual func Describe(): string {
        return "base"
    }
}

// THE DERIVED SIDE, which may read everything the base declared `protected` — through `this`,
// through a bare name and through `base`.
class AccessDerived: AccessBase {
    func SeedThroughThis(): int {
        return this.Seed
    }

    func SeedThroughBareName(): int {
        return Seed
    }

    func SeedThroughBase(): int {
        return base.Seed
    }

    func DoubleThroughThis(value: int): int {
        return this.ProtectedDouble(value)
    }

    func DoubleThroughBareName(value: int): int {
        return ProtectedDouble(value)
    }

    func DoubleThroughBase(value: int): int {
        return base.ProtectedDouble(value)
    }

    // The RECEIVER half of the rule, satisfied: the receiver is another value of THIS type.
    func SeedOfSibling(other: AccessDerived): int {
        return other.Seed
    }

    func WriteSeed(value: int): int {
        this.Seed = value
        return Seed
    }

    func SharedThroughThis(): int {
        return this.Shared
    }
}

// A SECOND derived type, so the sibling-receiver rule is a claim about ONE derived type rather than
// about "any derived type": `AccessDerived` may not read `AccessOtherDerived`'s protected state.
class AccessOtherDerived: AccessBase {
    func SeedThroughThis(): int {
        return this.Seed + 100
    }
}

// `base.` IS A NON-VIRTUAL CALL, and an override that would otherwise win is how that is OBSERVED
// rather than asserted. `Counted.Describe` overrides the base's and appends to a log; `base.Describe()`
// must run the BASE body — if `base.` emitted `callvirt`, the override would re-enter and the count
// would climb.
class Counted: AccessBase {
    Calls: int = 0

    protected override func Describe(): string {
        Calls = Calls + 1
        return "counted"
    }

    func DescribeVirtually(): string {
        return Describe()
    }

    func DescribeThroughBase(): string {
        return base.Describe()
    }
}

// A DEEPER link, because `protected` follows the whole chain and not just one step.
class AccessGrandchild: AccessDerived {
    func SeedFromGrandchild(): int {
        return Seed + this.Seed + base.Seed
    }

    func DescribeFromGrandchild(): string {
        return base.Describe() + "/grandchild"
    }
}

// `protected internal` is reachable from anywhere in the assembly, derived or not, which is the one
// level that the package rule alone would not already have allowed.
func SharedFromOutsideEveryType(value: AccessBase): int {
    return value.Shared
}

func OpenFromOutsideEveryType(value: AccessBase): int {
    return value.Open
}
