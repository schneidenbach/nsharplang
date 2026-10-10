namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic


// AN `assert` NARROWS EVERYTHING AFTER IT, because an assert that fails throws.
//
// `assert cond` is the guard clause `if !cond { throw }` written the other way round: the statement
// after it is reached only on the path where `cond` held. Without that rule every
// `found := items.FirstOrDefault(); assert found != null; found.Describe(…)` — the shape a test
// writes constantly — reports NL905 on the line the assert just proved safe, and the only way out is
// to write `must` twice.
//
// The extraction is the one every `if` uses, so all four shapes below reach it through the same
// vocabulary rather than through an assert-specific one. Each function here would not compile
// without the narrowing; `LengthWithoutAssert` is the negative and takes the value already narrowed
// by a guard, so the file proves the rule rather than the absence of the check.
class AssertEntry {
    labelValue: string

    Label: string => labelValue

    constructor(label: string) {
        labelValue = label
    }
}

// `x != null` — the shape the census's extension-call test uses.
func AssertedLength(text: string?): int {
    assert text != null
    return text.Length
}

// An `&&` CHAIN proves both halves.
func AssertedPairLength(left: string?, right: string?): int {
    assert left != null && right != null
    return left.Length + right.Length
}

// `x is T y` binds the pattern's name and narrows it, exactly as it does in an `if`.
func AssertedPatternLength(value: object): int {
    assert value is string text
    return text.Length
}

// A CALL'S OWN POSTCONDITION reaches the assert too: `Dictionary<K, V>.TryGetValue` is
// `[MaybeNullWhen(false)] out TValue`, so asserting the call proves the `out` variable present.
func AssertedLookupLabel(map: Dictionary<string, AssertEntry>, key: string): string {
    found: AssertEntry? = default
    assert map.TryGetValue(key, out found)
    return found.Label
}

// THE NEGATIVE, and it is not "no assert": a value narrowed by an ordinary guard is narrowed for the
// same reason, and the assert rule must not be the only way to reach it.
func LengthWithoutAssert(text: string?): int {
    if text == null {
        return 0
    }

    return text.Length
}

func AssertEntries(): Dictionary<string, AssertEntry> {
    map := new Dictionary<string, AssertEntry>()
    map["alpha"] = new AssertEntry("first")
    map["beta"] = new AssertEntry("second")
    return map
}

func MaybeText(present: bool): string? {
    if present {
        return "abcd"
    }

    return null
}

func MaybeObject(present: bool): object {
    if present {
        return "abcde"
    }

    return 7
}
