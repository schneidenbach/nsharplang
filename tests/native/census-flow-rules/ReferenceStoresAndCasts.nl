namespace NSharpLang.CensusFlowRules.Tests

// CENSUS §7 — STORING A REFERENCE INTO AN `object[]` ELEMENT, AND §14 — A CAST INSIDE AN ARRAY
// LITERAL.
//
// Two spellings of one missing conversion. The widening that is free at a call site — a `string`
// into an `object` parameter, an `int` boxed into one — did not happen for an array ELEMENT STORE,
// and an explicit `(object)x` did not emit at all, so `[(object)x, y]` declined as well. The
// product's own hand translation of `NSharpEventSubscription.cs` worked around the first by routing
// the store through a method whose parameter is `object?`.
//
// Both now go through the one conversion funnel every other value-flow position uses, so the store
// boxes a value type, widens a reference one, and leaves an already-`object` value alone — and the
// tests read the stored elements back to prove which of those happened.
interface Named {
    func ReadName(): string
}

class Person: Named {
    nameValue: string

    constructor(name: string) {
        nameValue = name
    }

    func ReadName(): string {
        return nameValue
    }
}

// §7 — the census probe: a reference into an `object[]` element.
func StoreReferenceIntoObjectArray(text: string): object[] {
    values := new object[](2)
    values[0] = text
    values[1] = "literal"
    return values
}

// §7 — a VALUE into an `object[]` element boxes, which is the same funnel's other answer.
func StoreValueIntoObjectArray(number: int): object[] {
    values := new object[](2)
    values[0] = number
    values[1] = true
    return values
}

// §7 — a derived reference into a base-typed array element needs no opcode at all.
func StoreDerivedIntoInterfaceArray(name: string): Named[] {
    values := new Named[](1)
    values[0] = new Person(name)
    return values
}

// §7 — the exact-match store the funnel must not have disturbed.
func StoreIntoIntArray(number: int): int[] {
    values := new int[](2)
    values[0] = number
    values[1] = 65
    return values
}

// §14 — a cast to `object`, alone and inside an array literal.
func CastReferenceToObject(text: string): object {
    return (object)text
}

func CastInsideArrayLiteral(text: string): object[] {
    return [(object)text, text]
}

func CastValueToObjectInsideArrayLiteral(number: int): object[] {
    return [(object)number, (object)"tail"]
}

// §14 — a cast to an interface the source implements.
func CastToImplementedInterface(name: string): Named {
    return (Named)new Person(name)
}

// The existing downcast arm stays: `object` back to a reference type.
func CastObjectBackToString(value: object): string {
    return (string)value
}
