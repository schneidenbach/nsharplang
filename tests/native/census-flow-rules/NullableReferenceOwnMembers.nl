namespace NSharpLang.CensusFlowRules.Tests


// CENSUS §FLOW5 — `Nullable<T>`'s SURFACE IS A VALUE-TYPE SURFACE, AND A REFERENCE `T?` HAS NONE.
//
// `Nullable<T>` is a STRUCT the CLR constructs over a non-nullable value type, and `Value`,
// `HasValue` and `GetValueOrDefault` are ITS members. A reference `T?` is nothing of the kind: its
// `?` is an ANNOTATION on one CLR type, `MarkupContent?` IS `MarkupContent`, and the names after the
// dot are whatever the CLASS declares.
//
// READING THEM AS THE UNWRAP IS WHAT THE CENSUS FOUND. `documentation.MarkupContent?.Value`, where
// `MarkupContent` is a class with its own `Value: string`, answered `MarkupContent` — the "unwrapped"
// nullable — warned NL907 about a `.Value` that "can throw", and then refused the `string?` the
// function was declared to return. Three diagnostics, all of them about a member the program never
// wrote.
//
// THE MAYBE-NULL RULES STILL APPLY, and that is the other half of the fix: on a reference `T?`,
// `.Value` is an ordinary dereference, so it is guarded with `?.` or a null check like any other —
// the estate pins the NL905 the unguarded form reports.
//
// A CLASS MAY DECLARE THE VERY NAMES `Nullable<T>` OWNS, and then they are the CLASS's. `Slot`
// below declares both `HasValue` and `GetValueOrDefault()` and every reader of them binds to the
// class's own members, with the class's own return types.
class MarkupContent {
    Value: string

    constructor(value: string) {
        Value = value
    }
}

class StringOrMarkupContent {
    HasMarkupContent: bool
    MarkupContent: MarkupContent?
    String: string?

    constructor(markup: MarkupContent?, text: string?) {
        MarkupContent = markup
        String = text
        HasMarkupContent = markup != null
    }
}

// The converted site, in the shape the census found it. `.Value` is `MarkupContent`'s own member and
// the `?.` lifts the CHAIN, so the result is the `string?` the signature declares.
func GetDocumentationText(documentation: StringOrMarkupContent?): string? {
    if documentation == null {
        return null
    }

    if documentation.HasMarkupContent {
        return documentation.MarkupContent?.Value
    }

    return documentation.String
}

// The same access behind an ordinary null check rather than a `?.`: the narrowing proves the
// receiver, and the member is still the class's own.
func MarkupTextOrNone(documentation: StringOrMarkupContent): string {
    markup := documentation.MarkupContent
    if markup == null {
        return "none"
    }

    return markup.Value
}

// `must` ON A REFERENCE `T?` IS THE NULL ASSERTION, unchanged: it proves the value present and hands
// back the same CLR type, and the member after it is the class's.
func MarkupTextOrThrow(documentation: StringOrMarkupContent): string {
    markup := must documentation.MarkupContent
    return markup.Value
}

// ── a class that declares the names `Nullable<T>` owns ─────────────────────────────────────────

class Slot {
    HasValue: bool
    payload: string

    constructor(hasValue: bool, payload: string) {
        HasValue = hasValue
        this.payload = payload
    }

    func GetValueOrDefault(): string {
        if HasValue {
            return payload
        }

        return "<empty>"
    }
}

// `slot?.HasValue` reads the CLASS's `bool` property through the chain, and the chain lifts it to
// `bool?` — which the lifted `== true` then decides.
func SlotIsFilled(slot: Slot?): bool {
    return slot?.HasValue == true
}

// `slot?.GetValueOrDefault()` calls the CLASS's own method. `Nullable<T>.GetValueOrDefault` returns
// `T`; this one returns `string`, which is what proves whose member bound.
func SlotText(slot: Slot?): string {
    return slot?.GetValueOrDefault() ?? "none"
}

// ── the value-type side, unchanged ─────────────────────────────────────────────────────────────

func CountHasValue(count: int?): bool {
    return count.HasValue
}

func CountOrDefault(count: int?): int {
    return count.GetValueOrDefault()
}

func CountText(count: int?): string {
    if count == null {
        return "none"
    }

    return count.Value.ToString()
}
