namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic
import System.Text


// EXECUTED PROOFS THAT AN ITERATOR BODY IS AN ORDINARY BODY. Every generator beside this file is
// lowered by the N# iterator planner and enumerated here for real: the assertions are over the
// VALUES the machine produced, the ORDER it produced them in, and the exceptions it let escape.
test "a body that builds a collection, calls into it and indexes it yields the built values" {
    positional := 0
    count := 0
    for v in DoubledThrough(4) {
        positional = positional * 10 + v
        count = count + 1
    }
    assert count == 4
    assert positional == 246
}

test "an object array row yields a boxed int, a string and a nested string array" {
    rows := new List<object[]>()
    for row in MemberRows() {
        rows.Add(row)
    }
    assert rows.Count == 2

    first := rows[0]
    assert first.Length == 3
    assert (first[0] as string) == "symbols"
    assert first[1].ToString() == "1"

    nested := first[2] as string[]
    assert nested != null
    assert nested.Length == 3
    assert nested[0] == "symbols"
    assert nested[2] == "examples"

    second := rows[1]
    assert (second[0] as string) == "outline"
    assert second[1].ToString() == "2"
    nestedSecond := second[2] as string[]
    assert nestedSecond.Length == 2
    assert nestedSecond[1] == "Program.nl"
}

test "a static call is the for..in source and an instance call transforms each element" {
    joined := ""
    for part in TrimmedParts(" a , b ,, c ") {
        joined = joined + part
    }
    assert joined == "abc"
}

test "a generator enumerates another generator" {
    total := 0
    seen := 0
    for v in DoubledRows(4) {
        total = total + v
        seen = seen + 1
    }
    assert seen == 4
    assert total == 16
}

test "a yielded value takes the same boxing conversion a return does" {
    values := new List<object>()
    for v in BoxedValues(3) {
        values.Add(v)
    }
    assert values.Count == 3
    assert values[0].ToString() == "0"
    assert values[2].ToString() == "2"
    assert values[1] is int
}

test "a yielded value takes the same reference conversion a return does" {
    values := new List<object>()
    for v in BuilderThenText() {
        values.Add(v)
    }
    assert values.Count == 2
    assert values[0] is StringBuilder
    assert values[1] is string
    assert (values[1] as string) == "ab"
}

test "an iterator body runs nothing until it is enumerated and pauses at each yield" {
    trace := new CensusTrace()
    sequence := Recorded(trace, 2)
    assert trace.Count() == 0

    enumerator := sequence.GetEnumerator()
    assert trace.Count() == 0

    assert enumerator.MoveNext()
    assert enumerator.Current == 0
    assert trace.Joined() == "start,before0"

    assert enumerator.MoveNext()
    assert enumerator.Current == 1
    assert trace.Joined() == "start,before0,after0,before1"

    assert !enumerator.MoveNext()
    assert trace.Joined() == "start,before0,after0,before1,after1,end"
}

test "an exception raised inside a body escapes from the MoveNext that reaches it" {
    enumerator := FailsAfterFirst("late").GetEnumerator()
    assert enumerator.MoveNext()
    assert enumerator.Current == 1

    message := ""
    try {
        enumerator.MoveNext()
    } catch ex: InvalidOperationException {
        message = ex.Message
    }
    assert message == "stopped: late"
}

test "a generic generator yields its own type parameter" {
    texts := ""
    for value in RepeatedPairs<string>("ab", 3) {
        texts = texts + value
    }
    assert texts == "ababab"

    total := 0
    for number in RepeatedPairs<int>(7, 2) {
        total = total + number
    }
    assert total == 14
}

test "a dictionary built inside the body is read through its own indexer" {
    keys: string[] = ["a", "z", "b", "a"]
    total := 0
    seen := 0
    for value in LookupValues(keys) {
        total = total + value
        seen = seen + 1
    }
    assert seen == 3
    assert total == 4
}

test "a for..in over a list the body built runs the hoisted-enumerator loop" {
    joined := ""
    for item in ListElements(3) {
        joined = joined + item + ";"
    }
    assert joined == "ITEM0;ITEM1;ITEM2;"
}

test "a sibling call is both the condition and the yielded value" {
    values: int[] = [1, 2, 3, 4]
    total := 0
    seen := 0
    for v in AboveThreshold(values, 6) {
        total = total + v
        seen = seen + 1
    }
    assert seen == 2
    assert total == 21
}

test "an early break disposes the machine and stops the body where it paused" {
    trace := new CensusTrace()
    taken := 0
    for v in Recorded(trace, 5) {
        taken = taken + 1
        if taken == 2 {
            break
        }
    }
    assert taken == 2
    assert trace.Joined() == "start,before0,after0,before1"
}

test "an async iterator lowers the same ordinary expressions as the synchronous machine" {
    positional := 0
    count := 0
    await foreach v in AsyncDoubled(4) {
        positional = positional * 10 + v
        count = count + 1
    }
    assert count == 4
    assert positional == 246
}

test "an async yielded value takes the same boxing conversion" {
    values := new List<object>()
    await foreach v in AsyncBoxed(3) {
        values.Add(v)
    }
    assert values.Count == 3
    assert values[0].ToString() == "0"
    assert values[2] is int
}

test "the synchronous machine implements the full enumerable surface it claims" {
    sequence := DoubledThrough(2)
    assert sequence is IEnumerable<int>

    machineValue: object = sequence
    machineType := machineValue.GetType()
    assert machineType.Name.StartsWith("<DoubledThrough>d__")

    enumerator := sequence.GetEnumerator()
    assert enumerator is IEnumerator<int>
    assert enumerator is IDisposable

    first := 0
    if enumerator.MoveNext() {
        first = enumerator.Current
    }
    assert first == 0
    enumerator.Dispose()
}

test "re-enumerating one sequence value restarts a fresh machine each time" {
    sequence := DoubledThrough(3)
    firstPass := 0
    for a in sequence {
        firstPass = firstPass * 10 + a
    }
    secondPass := 0
    for b in sequence {
        secondPass = secondPass * 10 + b
    }
    assert firstPass == 24
    assert secondPass == 24
}
