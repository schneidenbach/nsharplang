namespace NSharpLang.CensusAccessibility.Tests


// THE FOUR SPELLINGS OF A FREE FUNCTION'S VISIBILITY, side by side so one reflection sweep can read
// all of them off the same emitted type.
//
// The DEFAULT is the casing convention: PascalCase exports, camelCase does not. A written word
// OVERRIDES the casing, in both directions — `public exportedByWord` is exported despite its name,
// and `internal NotExportedByWord` is not despite its name.

// No word: the casing decides, and PascalCase means exported.
func VisibleByCasing(): int {
    return 1
}

// No word: the casing decides, and camelCase means package-private.
func hiddenByCasing(): int {
    return 2
}

// The word wins over a camelCase name.
public func exportedByWord(): int {
    return 3
}

// The word wins over a PascalCase name.
internal func InternalByWord(): int {
    return 4
}

// `private` at namespace scope is the same claim `internal` makes, because a free function has no
// containing user type for `private` to mean anything narrower about.
private func PrivateByWord(): int {
    return 5
}

// A CLASS OF THE SAME PACKAGE CALLING EVERY NON-EXPORTED SPELLING. This is the reason the emitted
// accessibility is `Assembly` and not `Private`: this class is a DIFFERENT CLR type from the type
// the free functions are emitted onto, so `Private` would make all three of these calls
// unverifiable IL.
class PackageCaller {
    func SumOfHiddenFunctions(): int {
        return hiddenByCasing() + InternalByWord() + PrivateByWord()
    }
}

// The same call from inside a LAMBDA, whose body is emitted onto a display class — a third CLR type
// again.
func SumOfHiddenFunctionsThroughLambda(): int {
    compute := () => hiddenByCasing() + InternalByWord() + PrivateByWord()
    return compute()
}
