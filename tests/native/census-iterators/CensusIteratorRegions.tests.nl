namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic
import System.Reflection


// EXECUTED PROOFS FOR A GENERATOR THAT SUSPENDS INSIDE A `try`/`finally`. Every assertion is over
// what the emitted state machine actually did: the values it produced, the order the handlers ran
// in, and the exception it let escape.
test "the finally runs once when the enumeration completes" {
    log := new List<string>()
    seen := new List<int>()
    for v in GuardedPair(log) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0] == 1
    assert seen[1] == 2
    assert String.Join(",", log) == "between,finally,after"
}

test "a suspension does not run the finally" {
    log := new List<string>()
    e := GuardedPair(log).GetEnumerator()
    assert e.MoveNext()
    assert e.Current == 1
    assert log.Count == 0
}

test "Dispose runs the finally when the consumer stops early" {
    log := new List<string>()
    e := GuardedPair(log).GetEnumerator()
    assert e.MoveNext()
    e.Dispose()
    assert String.Join(",", log) == "finally"
}

test "Dispose after a completed enumeration does not run the finally twice" {
    log := new List<string>()
    e := GuardedPair(log).GetEnumerator()
    while e.MoveNext() {
    }
    assert String.Join(",", log) == "between,finally,after"
    e.Dispose()
    assert String.Join(",", log) == "between,finally,after"
}

test "nested finallys unwind innermost first on early abandonment" {
    log := new List<string>()
    e := NestedRegions(log).GetEnumerator()
    assert e.MoveNext()
    assert e.Current == 1
    e.Dispose()
    assert String.Join(",", log) == "inner,outer"
}

test "nested finallys run in order on completion" {
    log := new List<string>()
    seen := new List<int>()
    for v in NestedRegions(log) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert String.Join(",", log) == "inner,outer"
}

test "an exception inside the region surfaces at MoveNext and still runs the finally" {
    log := new List<string>()
    e := GuardedThrow(log).GetEnumerator()
    assert e.MoveNext()
    assert log.Count == 0
    message := ""
    try {
        e.MoveNext()
    } catch failure: InvalidOperationException {
        message = failure.Message
    }
    assert message == "boom"
    assert String.Join(",", log) == "finally"
}

test "yield break inside the region runs the finally" {
    log := new List<string>()
    seen := new List<int>()
    for v in GuardedBreak(log, true) {
        seen.Add(v)
    }
    assert seen.Count == 1
    assert String.Join(",", log) == "finally"
}

test "a hoisted enumerator loop inside a region disposes and runs the finally" {
    log := new List<string>()
    source := new List<int>()
    source.Add(1)
    source.Add(2)
    e := GuardedEnumeration(source, log).GetEnumerator()
    assert e.MoveNext()
    assert e.Current == 2
    e.Dispose()
    assert String.Join(",", log) == "finally"
}

test "a region inside a loop runs its finally once per iteration" {
    log := new List<string>()
    source := new List<int>()
    source.Add(1)
    source.Add(2)
    seen := new List<int>()
    for v in RegionPerIteration(source, log) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert String.Join(",", log) == "f1,f2"
}

test "a region inside a loop unwinds only the open iteration on abandonment" {
    log := new List<string>()
    source := new List<int>()
    source.Add(1)
    source.Add(2)
    e := RegionPerIteration(source, log).GetEnumerator()
    assert e.MoveNext()
    e.Dispose()
    assert String.Join(",", log) == "f1"
}

test "a generic machine runs its finally on completion and on abandonment" {
    completed := new List<string>()
    seen := new List<string>()
    for v in GuardedGeneric<string>("a", "b", completed) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert String.Join(",", completed) == "finally"

    abandoned := new List<string>()
    e := GuardedGeneric<string>("a", "b", abandoned).GetEnumerator()
    assert e.MoveNext()
    e.Dispose()
    assert String.Join(",", abandoned) == "finally"
}

test "catch and finally without a suspension run inside a generator body" {
    seen := new List<int>()
    for v in CaughtInsideBody() {
        seen.Add(v)
    }
    assert seen.Count == 1
    assert seen[0] == 8
}

test "a machine that suspends inside a region carries a dispose flag and real EH clauses" {
    sequence: object = GuardedPair(new List<string>())
    machine := sequence.GetType()
    flag := machine.GetField("<>__disposing", BindingFlags.Public | BindingFlags.Instance)
    assert flag != null
    assert flag.FieldType == typeof(bool)

    moveNext := machine.GetMethod("MoveNext", BindingFlags.Public | BindingFlags.Instance)
    assert moveNext != null
    body := moveNext.GetMethodBody()
    assert body != null
    assert body.ExceptionHandlingClauses.Count == 1
    assert body.ExceptionHandlingClauses[0].Flags == ExceptionHandlingClauseOptions.Finally
}

test "a machine with no protected region carries no dispose flag" {
    plain: object = DoubledThrough(1)
    machine := plain.GetType()
    assert machine.GetField("<>__disposing", BindingFlags.Public | BindingFlags.Instance) == null
}

// EXECUTED PROOFS FOR A VALUE-TYPED `using` RESOURCE INSIDE A GENERATOR. Every assertion is over the
// recorder the struct itself writes to, so a release that ran on a boxed copy would show up as a
// MISSING entry rather than as a passing test.
test "a value-typed using resource is released when a generator completes" {
    log := new List<string>()
    collected := new List<int>()
    for v in ScopedValues(log) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == 1
    assert collected[1] == 2
    assert String.Join(",", log) == "between,disposed:a,after"
}

test "a value-typed using resource is released when the consumer stops early" {
    log := new List<string>()
    collected := new List<int>()
    for v in ScopedValues(log) {
        collected.Add(v)
        break
    }
    assert collected.Count == 1
    assert String.Join(",", log) == "disposed:a"
}

test "a value-typed using resource is not released at a suspension" {
    log := new List<string>()
    enumerator := ScopedValues(log).GetEnumerator()
    assert enumerator.MoveNext()
    assert log.Count == 0
    assert enumerator.MoveNext()
    assert String.Join(",", log) == "between"
    enumerator.Dispose()
    assert String.Join(",", log) == "between,disposed:a"
}

test "a value type that declares Dispose without the interface is released by a direct call" {
    log := new List<string>()
    collected := new List<int>()
    for v in ScopedPattern(log) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert String.Join(",", log) == "pattern-disposed"
}

test "nested value-typed using resources unwind innermost first" {
    log := new List<string>()
    collected := new List<int>()
    for v in NestedScopes(log) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert String.Join(",", log) == "disposed:inner,disposed:outer"
}
