namespace NSharpLang.CensusPackagePrivateTypes.Tests


// CENSUS — A camelCase TYPE NAME IS PACKAGE-PRIVATE, AND THE CLR IS TOLD SO.
//
// N# decides visibility by casing: PascalCase exports, camelCase does not. That rule already reached
// CLR metadata for MEMBERS (a camelCase method is `assembly`) and for NESTED TYPES (`NestedAssembly`
// versus `NestedPublic`) — but a TOP-LEVEL type was emitted `public` whatever its name, so the package
// boundary was a compiler-only rule for types and a metadata one for everything else. It is now one
// rule: a camelCase top-level type is emitted `NotPublic`, which the CLR reads as assembly-only.
//
// THE PAIR IS THE POINT. Every row below has a PascalCase twin, because "camelCase is not public" is
// only meaningful beside "PascalCase is". A test that asserted one without the other would pass on an
// emitter that made everything internal.
//
// WHAT THIS DOES NOT CHANGE. Nested visibility is untouched — a nested type answers its own casing and
// always did. FIELDS are still emitted `public` whatever their casing; the package rule on a field is
// enforced by the compiler, and `tests/native/census-internals-visible-to` owns that claim.
class ExportedClass {
    Value: int = 1

    // A nested type, whose own casing decides — as it did before this change.
    class NestedExported {
        Value: int = 2
    }

    class nestedHidden {
        Value: int = 3
    }
}

class packagePrivateClass {
    Value: int = 4
}

struct ExportedStruct {
    Value: int
}

struct packagePrivateStruct {
    Value: int
}

record ExportedRecord {
    Value: int
}

record packagePrivateRecord {
    Value: int
}

interface IExported {
    func Read(): int
}

interface iPackagePrivate {
    func Read(): int
}

enum ExportedEnum {
    First,
    Second
}

enum packagePrivateEnum {
    First,
    Second
}

union ExportedUnion {
    Left
    Right
}

union packagePrivateUnion {
    Left
    Right
}

// A package-private type is fully usable from the package that declares it — the rule is about who may
// NAME it from outside, not about what this package may do with it. Every file of this namespace can,
// which is what `PackagePrivateUse.nl` beside this proves.
class PackagePrivateReach {
    static func BuildAndRead(): int {
        hidden := new packagePrivateClass()
        exported := new ExportedClass()
        return hidden.Value + exported.Value
    }

    static func ReadThroughPackagePrivateInterface(): int {
        probe: iPackagePrivate = new packagePrivateImplementation()
        return probe.Read()
    }
}

class packagePrivateImplementation: iPackagePrivate {
    func Read(): int {
        return 7
    }
}
