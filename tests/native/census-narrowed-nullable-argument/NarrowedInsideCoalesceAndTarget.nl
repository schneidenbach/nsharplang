namespace NSharpLang.CensusNarrowedNullableArgument.Tests

// A NAME FLOW HAS PROVED PRESENT, READ INSIDE THE LEFT OPERAND OF `??` OR INSIDE A WRITE TARGET.
//
// Both positions keep the flow type of the operand ITSELF: `??` asks whether its left side can be
// null, and an assignment writes to the storage location's declared type. That preservation used to
// be in force for the whole walk of the operand, so a narrowed name read anywhere INSIDE it — an
// argument, a receiver, an index — was read as its declared `T?`, and `Take(n) ?? ""` inside
// `if n != null` was refused with an NL202 while `Take(n) == null` beside it compiled. Every
// subject below reported that NL202 before the preservation was narrowed to the operand node, so
// this file COMPILING is half the contract; the assertions are the other half.
class Animal {
}

class Dog: Animal {
    Name: string = "rex"

    constructor(name: string) {
        Name = name
    }
}

class Kennel {
    Resident: Dog? = null
    Slots: int[] = new int[4]
    Count: int? = null
}

class Narrowed {

    // The reported shape: a narrowed reference, passed where the base class is declared, inside the
    // operand of `??`.
    static func Describe(animal: Animal): string? {
        dog := animal as Dog
        if dog == null {
            return null
        }
        return dog.Name
    }

    static func DescribeOrEmpty(dog: Dog?): string {
        if dog != null {
            return Describe(dog) ?? ""
        }
        return "none"
    }

    // Parentheses around the operand, and a narrowed MEMBER PATH as the argument.
    static func ParenthesizedOrEmpty(dog: Dog?): string {
        if dog != null {
            return (Describe(dog)) ?? ""
        }
        return "none"
    }

    static func ResidentOrEmpty(kennel: Kennel): string {
        if kennel.Resident != null {
            return Describe(kennel.Resident) ?? ""
        }
        return "vacant"
    }

    // A narrowed VALUE nullable, passed where the bare `int` is declared.
    static func Halved(value: int): int? {
        if value % 2 != 0 {
            return null
        }
        return value / 2
    }

    static func HalvedOrMinusOne(value: int?): int {
        if value != null {
            return Halved(value) ?? -1
        }
        return -2
    }

    // CONTROL: the operand itself keeps its nullable, so `??` over the narrowed name is not dead.
    static func CountOrZero(kennel: Kennel): int {
        if kennel.Count != null {
            return kennel.Count ?? 0
        }
        return 0
    }

    // THE WRITE TARGET. The narrowed name is an index argument, then an argument inside the
    // target's RECEIVER, and the target itself can still be assigned `null`.
    static func Slot(dog: Dog): int {
        return dog.Name.Length - 1
    }

    static func MarkSlot(kennel: Kennel, dog: Dog?) {
        if dog != null {
            kennel.Slots[Slot(dog)] = 7
            kennel.Slots[Slot(dog)] += 1
        }
    }

    static func MarkResidentSlot(kennel: Kennel) {
        if kennel.Resident != null {
            kennel.Slots[Slot(kennel.Resident)] = 5
        }
    }

    static func MarkRow(grid: int[][], dog: Dog?) {
        if dog != null {
            grid[Slot(dog)][0] = 9
        }
    }

    static func Evict(kennel: Kennel) {
        if kennel.Resident != null {
            kennel.Resident = null
        }
    }

    // A narrowed `int?` used directly as an INDEX, not passed to a call: an index is a read of its
    // own value wherever the indexer sits, in a write target or in the left operand of `??`.
    static func MarkAt(kennel: Kennel, slot: int?) {
        if slot != null {
            kennel.Slots[slot] = 6
            kennel.Slots[slot] += 1
        }
    }

    static func NameAtOrEmpty(names: string?[], slot: int?): string {
        if slot != null {
            return names[slot] ?? ""
        }
        return "none"
    }

    // A VALUE-typed target is where keeping the nullable is visible: read as its narrowed `int`,
    // `kennel.Count = null` would be refused outright.
    static func ClearCount(kennel: Kennel) {
        if kennel.Count != null {
            kennel.Count = null
        }
    }
}
