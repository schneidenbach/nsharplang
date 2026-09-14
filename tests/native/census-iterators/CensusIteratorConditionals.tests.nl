namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// EXECUTED PROOFS FOR `??`, THE TERNARY AND `throw` AS AN EXPRESSION INSIDE A GENERATOR.
// Every assertion below is over values a real state machine produced, or over an exception a real
// `MoveNext` let escape.
test "a reference coalesce inside a generator yields the present value and the fallback" {
    collected := new List<string>()
    for v in CoalescedNames(["a", null, "c"]) {
        collected.Add(v)
    }
    assert collected.Count == 3
    assert collected[0] == "a"
    assert collected[1] == "(none)"
    assert collected[2] == "c"
}

test "a nullable coalesce inside a generator yields the element type" {
    collected := new List<int>()
    for v in CoalescedCounts([1, null, 3]) {
        collected.Add(v)
    }
    assert collected.Count == 3
    assert collected[0] == 1
    assert collected[1] == -1
    assert collected[2] == 3
}

test "a ternary inside a generator picks an arm per element" {
    collected := new List<string>()
    for v in Labelled([1, 0, 5]) {
        collected.Add(v)
    }
    assert collected.Count == 3
    assert collected[0] == "positive"
    assert collected[1] == "other"
    assert collected[2] == "positive"
}

test "a coalesce throw arm raises from the MoveNext that reaches the absent element" {
    produced := new List<string>()
    raised := ""
    try {
        for v in RequiredNames(["a", "b", null]) {
            produced.Add(v)
        }
    } catch ex: InvalidOperationException {
        raised = ex.Message
    }
    assert produced.Count == 2
    assert produced[0] == "a"
    assert produced[1] == "b"
    assert raised == "name 2 is absent"
}

test "a nullable coalesce throw arm raises only when the value is absent" {
    produced := new List<int>()
    raised := ""
    try {
        for v in RequiredCounts([7, null]) {
            produced.Add(v)
        }
    } catch ex: InvalidOperationException {
        raised = ex.Message
    }
    assert produced.Count == 1
    assert produced[0] == 7
    assert raised == "count 1 is absent"
}

test "a throwing conditional else arm raises and the earlier elements survive" {
    produced := new List<int>()
    raised := false
    try {
        for v in CheckedValues([3, 4, -1]) {
            produced.Add(v)
        }
    } catch ex: ArgumentOutOfRangeException {
        raised = true
    }
    assert produced.Count == 2
    assert produced[0] == 3
    assert produced[1] == 4
    assert raised
}

test "a throwing conditional then arm leaves the else arm as the whole value" {
    produced := new List<int>()
    raised := false
    try {
        for v in RejectedValues([2, 3, -4]) {
            produced.Add(v)
        }
    } catch ex: ArgumentOutOfRangeException {
        raised = true
    }
    assert produced.Count == 2
    assert produced[0] == 4
    assert produced[1] == 6
    assert raised
}

test "a chained coalesce takes the first present operand" {
    first := new List<string>()
    for v in FirstPresent("a", "b") {
        first.Add(v)
    }
    assert first.Count == 1
    assert first[0] == "a"

    second := new List<string>()
    for v in FirstPresent(null, "b") {
        second.Add(v)
    }
    assert second[0] == "b"

    neither := new List<string>()
    for v in FirstPresent(null, null) {
        neither.Add(v)
    }
    assert neither[0] == "(neither)"
}

test "a coalesce merged into a hoisted local survives the suspension" {
    collected := new List<string>()
    for v in MergedThroughLocal(null, null) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == "anonymous"
    assert collected[1] == "0"
}

test "a coalesce over a type parameter takes the left branch for every value instantiation" {
    numbers := new List<int>()
    for v in OrElse(0, 9) {
        numbers.Add(v)
    }
    assert numbers.Count == 1
    assert numbers[0] == 0

    present := new List<string>()
    for v in OrElse("a", "b") {
        present.Add(v)
    }
    assert present[0] == "a"

    let missing: string? = null
    absent := new List<string>()
    for v in OrElse(missing, "b") {
        absent.Add(v)
    }
    assert absent[0] == "b"
}

test "an async generator coalesces exactly as the synchronous machine does" {
    collected := new List<string>()
    await foreach v in CoalescedAsync(["a", null]) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == "a"
    assert collected[1] == "(none)"
}

test "an async coalesce throw arm raises from MoveNextAsync" {
    produced := new List<string>()
    raised := ""
    try {
        await foreach v in RequiredAsync(["a", null]) {
            produced.Add(v)
        }
    } catch ex: InvalidOperationException {
        raised = ex.Message
    }
    assert produced.Count == 1
    assert produced[0] == "a"
    assert raised == "absent"
}

test "an async conditional throw arm raises from MoveNextAsync" {
    produced := new List<string>()
    raised := false
    try {
        await foreach v in LabelledAsync([1, -1]) {
            produced.Add(v)
        }
    } catch ex: ArgumentOutOfRangeException {
        raised = true
    }
    assert produced.Count == 1
    assert produced[0] == "positive"
    assert raised
}

test "a plain body answers the same as the generator for every coalesce form" {
    assert PlainCoalesce("a") == "a"
    assert PlainCoalesce(null) == "(none)"
    assert PlainNullableCoalesce(4) == 4
    assert PlainNullableCoalesce(null) == -1
    assert PlainRequired("a") == "a"
    assert PlainCheckedTernary(3) == 3
    assert PlainCoalesceNull("a") == "a"
    assert PlainCoalesceNull(null) == null
}

test "a plain body coalesce throw arm raises for the absent value only" {
    raised := ""
    try {
        PlainRequired(null)
    } catch ex: InvalidOperationException {
        raised = ex.Message
    }
    assert raised == "absent"
}

test "a plain body conditional throw arm raises for the rejected value only" {
    raised := false
    try {
        PlainCheckedTernary(-1)
    } catch ex: ArgumentOutOfRangeException {
        raised = true
    }
    assert raised
}

test "the fallback of a coalesce runs only when the left is absent and only when enumerated" {
    lazyTrace := new CensusTrace()
    sequence := TracedCoalesce(lazyTrace, "a")
    assert lazyTrace.Count() == 0

    present := new List<string>()
    for v in sequence {
        present.Add(v)
    }
    assert present[0] == "a"
    assert lazyTrace.Joined() == "start,end"

    absentTrace := new CensusTrace()
    absent := new List<string>()
    for v in TracedCoalesce(absentTrace, null) {
        absent.Add(v)
    }
    assert absent[0] == "(computed)"
    assert absentTrace.Joined() == "start,fallback,end"
}
