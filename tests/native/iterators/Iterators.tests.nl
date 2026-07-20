namespace NSharpLang.Iterators.Tests

import System
import System.Collections.Generic
import System.Linq

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

test "a recursive instance iterator walks the tree depth first" {
    root := new TreeNode(1)
    childA := root.AddChild(2)
    childB := root.AddChild(3)
    childA.AddChild(4)
    childA.AddChild(5)
    childB.AddChild(6)
    positional := 0
    for v in root.DepthFirstTraversal() {
        positional = positional * 10 + v
    }
    assert positional == 124536
}

// Consumer-surface proofs (sub-slice 6c): generic-extension closure and the pinned generic
// String.Join<int> lowering over iterator results, arrays, and interpolated call holes.

test "take on an infinite iterator closes the generic extension by receiver inference" {
    positional := 0
    for v in ArithmeticFrom(1, 1).Take(4) {
        positional = positional * 10 + v
    }
    assert positional == 1234
}

test "string join closes its generic int overload over iterator array and hole arguments" {
    separator := ", "
    joined := String.Join(separator, CountTo(3))
    assert joined == "0, 1, 2"

    values: int[] = [4, 5, 6]
    arrayJoined := String.Join(separator, values)
    assert arrayJoined == "4, 5, 6"

    holed := $"[{String.Join(separator, values)}]"
    assert holed == "[4, 5, 6]"
}

test "a where select chain over an iterator materializes through the linq owners" {
    result := CountTo(10).Where(x => x % 2 == 0).Select(x => x * x).ToList()
    assert result.Count == 5
    joined := String.Join(", ", result)
    assert joined == "0, 4, 16, 36, 64"
}
