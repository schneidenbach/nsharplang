namespace NSharpLang.CensusConversions.Tests

import System


// CENSUS §CONV/1 — AN ARRAY OF A REFERENCE TYPE IS AN ARRAY OF ITS BASE.
//
// `string[]` was refused everywhere `object[]` was expected — as a `yield` value of an
// `IEnumerable<object[]>` generator (46 sites in the converted tests, all xUnit `MemberData` rows),
// as a return value, as an argument and as an assignment — because the analyzer's only array arm
// demanded IDENTICAL element types. The relation is ECMA-335's: `S[]` converts to `T[]` when both
// element types are REFERENCE types and `S` converts to `T` by a reference conversion.
//
// THE FUNCTIONS BELOW ARE THE PROOF THAT IT REACHES EMISSION, not only analysis: they are compiled
// by the real columnar pipeline, and `Dog[]` to `Animal[]` is the case Reflection.Emit cannot answer
// for itself, because both element types are still unbaked `TypeBuilder`s while the method body is
// written. The tests beside them are the proof that the conversion is a VIEW rather than a copy.
class Animal {
    readonly name: string

    constructor(name: string) {
        this.name = name
    }

    Name: string => name
}

class Dog: Animal {
    constructor(name: string): base(name) {
    }
}

// The argument position.
func CountValues(values: object[]): int {
    return values.Length
}

func CountNames(names: string[]): int {
    return CountValues(names)
}

// The return position, over a BCL element type…
func NamesAsValues(names: string[]): object[] {
    return names
}

// …and over two element types this compilation is still emitting.
func PackAsAnimals(pack: Dog[]): Animal[] {
    return pack
}

// The assignment position, and the read back through it — a covariant view is the SAME object, so
// the element read through `object[]` is the element the `string[]` holds.
func FirstThroughValueView(names: string[]): object {
    view: object[] = names
    return view[0]
}

// Covariance composes: an array of arrays converts when its element arrays do.
func RowsAsValueRows(rows: string[][]): object[][] {
    return rows
}

// An interface the element type implements is a reference conversion too.
func NamesAsComparables(names: string[]): IComparable[] {
    return names
}

// THE STORE THROUGH THE WIDER VIEW. The CLR checks it, because the narrower name still describes the
// same object, and a `string[]` that held an `int` would be a hole in the type system. A store of a
// value the real element type accepts succeeds; one it does not throws.
func StoreThroughValueView(names: string[], value: object): string {
    view: object[] = names
    try {
        view[0] = value
    } catch ex: ArrayTypeMismatchException {
        return "mismatch"
    }

    return "stored"
}

// The same store, through a view of an array of a type this compilation emits.
func StoreThroughAnimalView(pack: Dog[], value: Animal): string {
    view: Animal[] = pack
    try {
        view[0] = value
    } catch ex: ArrayTypeMismatchException {
        return "mismatch"
    }

    return "stored"
}
