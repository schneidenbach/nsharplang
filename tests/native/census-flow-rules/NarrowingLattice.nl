namespace NSharpLang.CensusFlowRules.Tests


// CENSUS §FLOW2 — THE DEFINITE-STATE LATTICE A CONDITION INDUCES, RUN RATHER THAN ASSERTED ABOUT.
//
// The converted CLI could not compile four shapes the analyzer had no rule for: a parenthesised
// operand inside an `&&`, a negated guard (`if !(x != null) { return }`), a ternary whose condition
// narrows the arm that follows it, and a `?.` chain compared against null. Each of them is a
// position where C# knows something and N# did not, and each of them is a RUNTIME behaviour — the
// narrowed value is dereferenced, so a wrong answer is a NullReferenceException rather than a
// difference of opinion.
//
// THE SOUND DIRECTION IS PINNED BY THE ESTATE, NOT HERE. `a && b` proves nothing in its false
// branch, and the only way to observe that is a diagnostic; the contracts for it sit beside
// `AnalyzerFlowNarrowing`. What runs here is what the rule now ACCEPTS, which is the half a
// regression would silently take away.
func ParenthesisedOperandLength(first: string?, second: string?): int {
    if first != null && (second != null && first.Length > 0) {
        return second.Length
    }

    return -1
}

func NegatedGuardLength(value: string?): int {
    if !(value != null) {
        return -1
    }

    return value.Length
}

func DoubleNegatedGuardLength(value: string?): int {
    if !(!(value == null)) {
        return -1
    }

    return value.Length
}

func TernaryLength(value: string?): int {
    return value != null ? value.Length : -1
}

func TernaryElseArmLength(value: string?): int {
    return value == null ? -1 : value.Length
}

func TernaryNestedLength(first: string?, second: string?): int {
    return first != null && second != null ? first.Length + second.Length : -1
}

class Document {
    Text: string?

    constructor(text: string?) {
        Text = text
    }
}

// `doc?.Text == null` is false only when `doc` is not null AND `doc.Text` is not null, so the
// surviving flow knows BOTH.
func DocumentTextLength(doc: Document?): int {
    if doc?.Text == null {
        return -1
    }

    return doc.Text.Length
}

func DocumentTextLengthWhenPresent(doc: Document?): int {
    if doc?.Text != null {
        return doc.Text.Length
    }

    return -1
}

// A NULLABLE VALUE TYPE KEEPS ITS OWN MEMBERS. `Nullable<T>` declares `HasValue`, `Value` and both
// `GetValueOrDefault` overloads; binding a member on `int?` must find them whether or not the flow
// has narrowed the value, because unwrapping first and looking on `int` finds none of them.
func ParseLength(text: string?): int? {
    if text == null {
        return null
    }

    return text.Length
}

func LengthOrDefault(text: string?): int {
    return ParseLength(text).GetValueOrDefault()
}

func LengthOrFallback(text: string?, fallback: int): int {
    return ParseLength(text).GetValueOrDefault(fallback)
}

func LengthIsPresent(text: string?): bool {
    return ParseLength(text).HasValue
}

// The same members AFTER a sound narrowing: the value is known to be present, and the declared
// nullable surface is still the one that binds.
func NarrowedLengthValue(text: string?): int {
    parsed := ParseLength(text)
    if parsed == null {
        return -1
    }

    return parsed.GetValueOrDefault()
}

func NarrowedLengthUnwrapped(text: string?): int {
    parsed := ParseLength(text)
    if parsed == null {
        return -1
    }

    return must parsed
}

// The narrowed value used AS its inner type — the unwrap the emitter performs, spelled either way.
func NarrowedLengthPlusOne(text: string?): int {
    parsed := ParseLength(text)
    if parsed == null {
        return -1
    }

    return parsed.GetValueOrDefault() + 1
}

func NarrowedLengthUnwrappedPlusOne(text: string?): int {
    parsed := ParseLength(text)
    if parsed == null {
        return -1
    }

    unwrapped := must parsed
    return unwrapped + 1
}
