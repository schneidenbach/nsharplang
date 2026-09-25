namespace NSharpLang.PatternForeach.Tests

import System.Collections
import System.Collections.Generic
import System.Text.RegularExpressions


// A SOURCE COLLECTION WHOSE ENUMERATOR IS A CLASS, and whose elements are typed `object`. It is the
// user-written twin of the BCL's oldest sequences: nothing about it is generic, so a loop that wants
// the elements at their real type has to say so.
class LabelBag {
    labels: List<object>

    constructor() {
        labels = new List<object>()
    }

    func Add(label: object) {
        labels.Add(label)
    }

    func GetEnumerator(): LabelCursor {
        return new LabelCursor(labels)
    }
}

// The enumerator is a CLASS, so the loop holds it in a reference local and steps it through
// `callvirt` — the other half of the struct-enumerator rule the sibling shapes pin.
class LabelCursor {
    items: List<object>
    position: int

    constructor(items: List<object>) {
        this.items = items
        position = -1
    }

    Current: object => items[position]

    func MoveNext(): bool {
        position = position + 1
        return position < items.Count
    }
}

// A BASE AND A DERIVED CLASS, for the reference conversions an annotation performs: a DOWNCAST out
// of a sequence typed by the base, and an UPCAST out of one typed by the derived.
class Shape {
    Sides: int

    constructor(sides: int) {
        Sides = sides
    }
}

class Square: Shape {
    constructor(): base(4) {
    }
}

// EVERY CONVERSION AN ANNOTATED LOOP VARIABLE CAN PERFORM, one method apiece so the emitted IL for
// each is separately inspectable.
//
// C# defines `foreach (T x in e)` as an EXPLICIT conversion of each element to `T` — the conversion
// a cast performs — which is why a downcast and an unboxing are legal here while the same value
// would not be assignable to a `T` variable. Each method below is one of those conversions, and
// every one of them is asserted at RUNTIME rather than described.
class AnnotatedShapes {

    // A NON-GENERIC SEQUENCE, whose element type is `object`, read at the element's real type. This
    // is the shape the annotation exists for: `MatchCollection` is an `IEnumerable`, so without the
    // annotation the loop variable is an `object` and `.Length` cannot be spelled.
    func TotalMatchLength(text: string, pattern: string): int {
        total := 0
        for m: Match in Regex.Matches(text, pattern) {
            total = total + m.Length
        }

        return total
    }

    // AN `ArrayList`, the other non-generic sequence, downcast to `string`.
    func TotalLabelLength(labels: ArrayList): int {
        total := 0
        for label: string in labels {
            total = total + label.Length
        }

        return total
    }

    // AN UNBOXING. `List<object>` is an `IEnumerable<object>`, so each element arrives boxed and the
    // annotation unwraps it — `unbox.any`, not `castclass`.
    func SumBoxedNumbers(values: List<object>): int {
        total := 0
        for value: int in values {
            total = total + value
        }

        return total
    }

    // A NUMERIC WIDENING out of an `IEnumerable<int>`. Nothing about it is a reference conversion:
    // the element is an `int` on the stack and the annotation widens it in place.
    func SumAsLong(values: List<int>): long {
        total: long = 0
        for value: long in values {
            total = total + value
        }

        return total
    }

    // A NUMERIC NARROWING out of an array of `long`. It is legal for exactly the reason a cast is:
    // the conversion exists, and whether the value survives it is the author's business.
    func SumAsInt(values: long[]): int {
        total := 0
        for value: int in values {
            total = total + value
        }

        return total
    }

    // A `string`'s elements are `char`, widened to `int` by the annotation.
    func SumCharacterCodes(text: string): int {
        total := 0
        for code: int in text {
            total = total + code
        }

        return total
    }

    // A SOURCE CLASS ENUMERATOR whose `Current` is `object`, downcast to `string`.
    func TotalBagLength(bag: LabelBag): int {
        total := 0
        for label: string in bag {
            total = total + label.Length
        }

        return total
    }

    // A REFERENCE DOWNCAST out of a sequence typed by the BASE class.
    func CountSquareSides(shapes: List<Shape>): int {
        total := 0
        for square: Square in shapes {
            total = total + square.Sides
        }

        return total
    }

    // A REFERENCE UPCAST out of a sequence typed by the DERIVED class. Every implicit conversion is
    // also an explicit one, so the annotation accepts it and emits nothing for it.
    func CountShapeSides(squares: List<Square>): int {
        total := 0
        for shape: Shape in squares {
            total = total + shape.Sides
        }

        return total
    }

    // A BOXING conversion — the element widened to `object` — and read back through `ToString()`.
    func JoinAsObjects(values: List<int>): string {
        joined := ""
        for value: object in values {
            joined = joined + value.ToString()
        }

        return joined
    }

    // AN ANNOTATION THAT IS THE ELEMENT TYPE ITSELF. It converts nothing and must emit nothing.
    func SumExactly(values: List<int>): int {
        total := 0
        for value: int in values {
            total = total + value
        }

        return total
    }

    // AN ANNOTATED LOOP THAT LEAVES EARLY. `break` and the conversion are independent: the element
    // is converted on every iteration the loop actually reaches, and on no others.
    func FirstLongLabel(labels: ArrayList, minimum: int): string {
        found := ""
        for label: string in labels {
            if label.Length >= minimum {
                found = label
                break
            }
        }

        return found
    }

    // A CONVERSION THAT THE RUNTIME REFUSES. The check NL330 performs is about whether a conversion
    // could ever apply, not about whether every element satisfies it — so this compiles, and throws
    // exactly where the equivalent cast would.
    func TotalLabelLengthUnchecked(labels: ArrayList): int {
        total := 0
        for label: string in labels {
            total = total + label.Length
        }

        return total
    }
}
