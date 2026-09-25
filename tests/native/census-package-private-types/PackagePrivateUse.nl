namespace NSharpLang.CensusPackagePrivateTypes.Tests


// THE SECOND FILE OF THE SAME NAMESPACE, and the whole reason N# has no file-private tier: a
// package-private type is visible to EVERY file that declares its namespace. Nothing here imports or
// qualifies anything — the names below are declared in `PackagePrivateTypes.nl` and are reachable
// because this file is part of the same package.
class SecondFileReach {
    static func ReadHiddenClass(): int {
        hidden := new packagePrivateClass()
        return hidden.Value
    }

    static func ReadHiddenStruct(): int {
        hidden := new packagePrivateStruct { Value: 11 }
        return hidden.Value
    }

    static func ReadHiddenRecord(): int {
        hidden := new packagePrivateRecord { Value: 12 }
        return hidden.Value
    }
}
