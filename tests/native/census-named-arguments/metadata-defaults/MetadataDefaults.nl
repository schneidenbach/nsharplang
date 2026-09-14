namespace NSharpLang.CensusNamedArguments.MetadataDefaults

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
