namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic

func CollectInts(source: IEnumerable<int>): List<int> {
    collected := new List<int>()
    for value in source {
        collected.Add(value)
    }
    return collected
}

test "a continue in a counted loop runs the step and skips the element" {
    collected := CollectInts(LoopBranches.Evens(10, 100))
    assert collected.Count == 5
    assert collected[0] == 0
    assert collected[1] == 2
    assert collected[2] == 4
    assert collected[3] == 6
    assert collected[4] == 8
}

test "a break in a counted loop ends the sequence there" {
    collected := CollectInts(LoopBranches.Evens(10, 6))
    assert collected.Count == 3
    assert collected[0] == 0
    assert collected[1] == 2
    assert collected[2] == 4
}

test "a continue in a while targets the condition" {
    collected := CollectInts(LoopBranches.WhileSkipping([3, -1, 5, -2, 7]))
    assert collected.Count == 3
    assert collected[0] == 3
    assert collected[1] == 5
    assert collected[2] == 7
}

test "a break in a while ends the sequence there" {
    collected := CollectInts(LoopBranches.WhileSkipping([3, -1, 0, 9]))
    assert collected.Count == 1
    assert collected[0] == 3
}

test "an array for..in skips and stops" {
    collected := CollectInts(LoopBranches.ArraySkipping([4, 0, 5, 9, 6], 9))
    assert collected.Count == 2
    assert collected[0] == 4
    assert collected[1] == 5
}

test "a string comparison inside a generator is value equality" {
    collected := new List<string>()
    for value in NamedSkipping(["a", "", "b", "stop", "c"], "stop") {
        collected.Add(value)
    }
    assert collected.Count == 2
    assert collected[0] == "a"
    assert collected[1] == "b"
}

test "a break out of a sequence for..in still disposes the enumerator" {
    trace := new CensusTrace()
    source := TracedSource([1, -1, 2, 9, 3], trace)
    collected := CollectInts(LoopBranches.SequenceSkipping(source, 9))
    assert collected.Count == 2
    assert collected[0] == 1
    assert collected[1] == 2
    assert trace.Joined() == "disposed"
}

test "a sequence for..in that runs to the end disposes exactly once" {
    trace := new CensusTrace()
    source := TracedSource([1, -1, 2], trace)
    collected := CollectInts(LoopBranches.SequenceSkipping(source, 100))
    assert collected.Count == 2
    assert trace.Count() == 1
}

// THE BRANCH CROSSES A PROTECTED REGION, so it is a `leave` and the `finally` runs on the way out.
test "a continue out of a try runs its finally and keeps looping" {
    trace := new CensusTrace()
    collected := CollectInts(LoopBranches.GuardedSkipping([1, -1, 2], 100, trace))
    assert collected.Count == 2
    assert collected[0] == 1
    assert collected[1] == 2
    assert trace.Joined() == "try,finally,try,finally,try,finally,after"
}

test "a break out of a try runs its finally and ends the sequence" {
    trace := new CensusTrace()
    collected := CollectInts(LoopBranches.GuardedSkipping([1, 7, 2], 7, trace))
    assert collected.Count == 1
    assert collected[0] == 1
    // The `break` leaves the region, so its finally runs, and the statement after the loop runs too.
    assert trace.Joined() == "try,finally,try,finally,after"
}

test "a break in an inner loop leaves only the inner loop" {
    collected := CollectInts(LoopBranches.Pairs(2, 4, 2))
    assert collected.Count == 6
    assert collected[0] == 0
    assert collected[1] == 1
    assert collected[2] == 0
    assert collected[3] == 10
    assert collected[4] == 11
    assert collected[5] == 100
}

test "a loop body that never falls through still steps for its continue" {
    collected := CollectInts(LoopBranches.UntilSentinel([1, -1, 2, 0, 3], 0))
    assert collected.Count == 2
    assert collected[0] == 1
    assert collected[1] == 2
}

test "a loop body that never falls through and never breaks runs to the end" {
    collected := CollectInts(LoopBranches.UntilSentinel([1, -1, 2], 99))
    assert collected.Count == 2
    assert collected[0] == 1
    assert collected[1] == 2
}

// LAZINESS SURVIVES THE BRANCH. A generator is not run until it is read, and a consumer that stops
// early leaves the machine suspended at its own state rather than running the rest of the loop.
test "the sequence is still produced lazily around a break" {
    trace := new CensusTrace()
    source := TracedSource([1, 2, 3, 4], trace)
    taken := 0
    for value in LoopBranches.SequenceSkipping(source, 100) {
        taken = taken + value
        if taken >= 3 {
            break
        }
    }

    assert taken == 3
    assert trace.Joined() == "disposed"
}
