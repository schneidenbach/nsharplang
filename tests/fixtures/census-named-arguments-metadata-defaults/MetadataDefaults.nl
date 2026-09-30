namespace NSharpLang.CensusNamedArguments.MetadataDefaults

import System

class ReflectedOptionalSlots {
    Value: int

    constructor(first: int = 1, middle: int = 2, last: int = 3) {
        Value = first * 100 + middle * 10 + last
    }

    func Read(first: int = 1, middle: int = 2, last: int = 3): int {
        return first * 100 + middle * 10 + last
    }

    static func ReadStatic(first: int = 1, middle: int = 2, last: int = 3): int {
        return first * 100 + middle * 10 + last
    }
}

class ReflectedOptionalBase {
    func Pick(first: int = 1, second: int = 2): string {
        return first.ToString() + second.ToString() + "base"
    }
}

class ReflectedOptionalDerived: ReflectedOptionalBase {
    func Pick(first: int = 1, second: int = 2): string {
        return first.ToString() + second.ToString() + "derived"
    }
}

class ReflectedChainBase {
    Value: int

    constructor(first: int = 1, middle: int = 2, last: int = 3) {
        Value = first * 100 + middle * 10 + last
    }
}

class ReflectedSparseConstructorChoice {
    Kind: string

    constructor(value: object, omitted: int = 1) {
        Kind = "object"
    }

    constructor(value: IComparable, omitted: int = 1) {
        Kind = "comparable"
    }
}

class ReflectedSparseRefConstructor {
    Seen: int

    constructor(ref target: int, middle: int = 2, last: int = 3) {
        Seen = target * 100 + middle * 10 + last
        target = Seen
    }
}
