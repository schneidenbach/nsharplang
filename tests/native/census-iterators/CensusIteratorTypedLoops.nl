namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic


// AN ANNOTATED LOOP VARIABLE INSIDE A GENERATOR.
//
// `for v: T in e` converts each element to `T` the way a cast does — a downcast out of `object`, an
// unboxing, a numeric widening or narrowing — once per iteration. The state machine changes nothing
// about that: the loop variable's hoisted field is defined from the type the author WROTE, and the
// element converts on its way into it. Each generator below is enumerated beside this file so the
// conversion is observed on real elements.

// Unboxing: a boxed `int` read at `int`.
func* UnboxedElements(values: object[]): IEnumerable<int> {
    for v: int in values {
        yield v * 2
    }
}

// A numeric WIDENING over an enumerated sequence.
func* WidenedElements(values: List<int>): IEnumerable<long> {
    for v: long in values {
        yield v * 3
    }
}

// A numeric NARROWING — the conversion an assignment would refuse and a cast performs.
func* NarrowedElements(values: List<long>): IEnumerable<int> {
    for v: int in values {
        yield v
    }
}

// A reference DOWNCAST out of `object`, which is the reason the annotated form exists.
func* DowncastElements(values: List<object>): IEnumerable<int> {
    for s: string in values {
        yield s.Length
    }
}

// The ARRAY index loop with an annotation: the element loads at the array's own type and converts.
func* WidenedArrayElements(values: int[]): IEnumerable<long> {
    for v: long in values {
        yield v + 1
    }
}

// A reference WIDENING over an array, which costs no opcode at all.
func* WidenedStringArray(values: string[]): IEnumerable<object> {
    for v: object in values {
        yield v
    }
}
