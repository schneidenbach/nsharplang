namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// EXECUTED PROOFS FOR A PROTECTED REGION INSIDE AN `async func*`.
test "an async generator finally runs once after the sequence ends" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in Guarded(trace) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == 1
    assert collected[1] == 2
    assert trace.Joined() == "enter,finally,after"
}

test "an async generator finally runs when the consumer abandons the sequence" {
    trace := new CensusTrace()
    seen := 0
    await foreach v in Guarded(trace) {
        seen = seen + 1
        assert v == 1
        break
    }
    assert seen == 1
    assert trace.Joined() == "enter,finally"
}

test "an async generator catch handles an exception raised after a suspension" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in Caught(trace) {
        collected.Add(v)
    }
    assert collected.Count == 1
    assert collected[0] == 9
    assert trace.Joined() == "inner"
}

test "an exception from an async generator body reaches the consumer after the finally ran" {
    trace := new CensusTrace()
    collected := new List<int>()
    raised := false
    try {
        await foreach v in Raising(trace) {
            collected.Add(v)
        }
    } catch ex: InvalidOperationException {
        raised = true
        assert ex.Message == "raised"
    }
    assert raised
    assert collected.Count == 1
    assert trace.Joined() == "finally"
}

test "a using resource inside an async generator is released once at the end" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in Scoped(trace) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert trace.Joined() == "acquire r,release r"
}

test "a using resource inside an async generator is released when the consumer stops early" {
    trace := new CensusTrace()
    await foreach v in Scoped(trace) {
        assert v == 1
        break
    }
    assert trace.Joined() == "acquire r,release r"
}

test "nested async generator regions unwind innermost first" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in Nested(trace) {
        collected.Add(v)
    }
    assert collected.Count == 1
    assert trace.Joined() == "inner,outer"
}

test "a suspension numbered after an await still knows which region it stands in" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in InterleavedRegion(trace) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == 1
    assert collected[1] == 2
    assert trace.Joined() == "finally"

    abandonTrace := new CensusTrace()
    seen := 0
    await foreach v in InterleavedRegion(abandonTrace) {
        seen = seen + 1
        if v == 2 {
            break
        }
    }
    assert seen == 2
    assert abandonTrace.Joined() == "finally"
}
