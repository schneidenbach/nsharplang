namespace NSharpLang.Iterators.Tests

import System.Collections.Generic

// Executed in-project proofs: this test assembly's own `func*` definitions are lowered by the N#
// iterator planner and consumed directly below — no compiler-harness indirection. The positional
// accumulator (`acc * 10 + v`) pins both the CONTENTS and the ORDER of each sequence.

test "the counting iterator yields the full sequence in order" {
    count := 0
    positional := 0
    for v in CountTo(5) {
        positional = positional * 10 + v
        count = count + 1
    }
    assert count == 5
    assert positional == 1234
}

test "an infinite iterator terminates early through a consumer break" {
    // Termination is the proof: without lazy per-element resumption and a working loop exit
    // (the foreach lowering's dispose path), this enumeration would never end.
    taken := 0
    sum := 0
    for v in ArithmeticFrom(10, 3) {
        sum = sum + v
        taken = taken + 1
        if taken == 4 {
            break
        }
    }
    assert taken == 4
    assert sum == 58
}

test "re-enumerating the same sequence value restarts from a fresh machine" {
    sequence := CountTo(4)
    first := 0
    for a in sequence {
        first = first * 10 + a
    }
    second := 0
    for b in sequence {
        second = second * 10 + b
    }
    assert first == 123
    assert second == 123
}

test "a guard yield break produces an empty sequence and falls through otherwise" {
    empties := 0
    for v in UpToTwo(0) {
        empties = empties + v
    }
    assert empties == 0

    yielded := 0
    for w in UpToTwo(9) {
        yielded = yielded * 10 + w
    }
    assert yielded == 12
}

test "a zero-yield iterator is empty on every pass" {
    visits := 0
    for v in Nothing() {
        visits = visits + v
    }
    for w in Nothing() {
        visits = visits + w
    }
    assert visits == 0
}

test "if else branches inside the loop select each yielded value" {
    pattern := 0
    for v in EvenScaled(4) {
        pattern = pattern * 100 + v
    }
    assert pattern == 12003
}

test "an array iterator yields every element in order" {
    data: int[] = [3, 1, 4]
    count := 0
    positional := 0
    for v in Values(data) {
        positional = positional * 10 + v
        count = count + 1
    }
    assert count == 3
    assert positional == 314
}

test "a guard yield break inside the array loop stops mid-array" {
    data: int[] = [1, 2, -1, 9]
    positional := 0
    for v in UntilNegative(data) {
        positional = positional * 10 + v
    }
    assert positional == 12
}

test "an array iterator filters and transforms per element" {
    data: int[] = [1, 2, 3, 4, 5, 6]
    positional := 0
    for v in EvenSquares(data) {
        positional = positional * 100 + v
    }
    assert positional == 41636
}

test "the range iterator walks both directions through the shared slot" {
    ups := 0
    for v in RangeBy(0, 10, 2) {
        ups = ups * 100 + v
    }
    assert ups == 2040608

    downs := 0
    for w in RangeBy(10, 0, -3) {
        downs = downs * 100 + w
    }
    assert downs == 10070401
}

test "the range iterator raises its guard lazily on first advance" {
    hits := 0
    assert throws ArgumentException {
        for v in RangeBy(0, 5, 0) {
            hits = hits + 1
        }
    }
    assert hits == 0
}

test "the fibonacci iterator rotates its hoisted locals" {
    count := 0
    positional := 0
    for v in Fib(7) {
        positional = positional * 10 + v
        count = count + 1
    }
    assert count == 7
    assert positional == 112358
}

test "chained sequence iterators concatenate through hoisted enumerators" {
    data: int[] = [4, 5]
    positional := 0
    for v in Chained(CountTo(3), Values(data)) {
        positional = positional * 10 + v
    }
    assert positional == 1245
}

test "a nested iterator pipeline stays lazy end to end" {
    positional := 0
    for v in Doubled(CountTo(4)) {
        positional = positional * 10 + v
    }
    assert positional == 246
}

test "a list-driven iterator yields every element" {
    items := new List<int>()
    items.Add(7)
    items.Add(8)
    positional := 0
    for v in FromList(items) {
        positional = positional * 10 + v
    }
    assert positional == 78
}

test "an infinite source consumed through a nested iterator stops with the consumer" {
    taken := 0
    total := 0
    for v in Doubled(ArithmeticFrom(1, 1)) {
        total = total + v
        taken = taken + 1
        if taken == 3 {
            break
        }
    }
    assert total == 12
}

test "a generic iterator repeats values of any element type" {
    ints := 0
    for v in Repeat(9, 3) {
        ints = ints * 10 + v
    }
    assert ints == 999

    words := ""
    for w in Repeat("ha", 2) {
        words = words + w
    }
    assert words == "haha"
}
