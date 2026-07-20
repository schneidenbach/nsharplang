namespace NSharpLang.Iterators.Tests

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
