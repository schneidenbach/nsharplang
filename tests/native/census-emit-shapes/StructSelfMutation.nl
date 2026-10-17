namespace NSharpLang.CensusEmitShapes.Tests


// A STRUCT METHOD WRITES ITS OWN FIELDS, AND THE CALLER SEES IT. The write was never the problem —
// the receiver was: every call on a struct used to spill the receiver's VALUE into a temp and call
// through the temp's address, so a field assignment landed on a copy and the caller's variable never
// moved. The call site now loads an ADDRESSABLE receiver (a local, a parameter, a field of one) by
// address, exactly as C# does, so `this` is the caller's own storage.
struct Counter {
    value: int

    func Bump(): bool {
        value = value + 1
        return value < 3
    }

    func Reset() {
        this.value = 0
    }

    func Add(amount: int): int {
        value = value + amount
        return value
    }

    func Read(): int {
        return value
    }
}

// A struct held as a FIELD of a class: the field's own storage is addressable through `ldflda`. The
// member is camelCase because that is what makes it a field — an exported bare member of a class is
// an auto-property (`MemberStorageRules`).
class Holder {
    counter: Counter = new Counter()

    func BumpTwice(): int {
        counter.Bump()
        counter.Bump()
        return counter.Read()
    }
}

// THE SAME STRUCT HELD AS AN AUTO-PROPERTY IS READ AS A COPY. A property read yields a value, so a
// mutating call bumps that value and the storage never moves — C#'s rule, and exactly what a caller in
// another assembly sees through the getter. This assembly reaches the property's backing field
// directly, and that must not turn a read into an address.
class PropertyHolder {
    Counter: Counter = new Counter()

    func BumpTwice(): int {
        Counter.Bump()
        Counter.Bump()
        return Counter.Read()
    }
}

// A struct receiver reached through a PARAMETER. N# value parameters have value semantics, so the
// mutation is local to this frame — but it is a real mutation of THIS frame's variable.
func BumpParameter(counter: Counter): int {
    counter.Bump()
    counter.Bump()
    return counter.Read()
}
