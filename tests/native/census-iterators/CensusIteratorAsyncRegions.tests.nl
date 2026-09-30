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

// EXECUTED PROOFS FOR AN `await` IN A HANDLER POSITION.
test "an awaiting finally runs once after the sequence ends" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in AwaitingFinally(trace) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == 1
    assert collected[1] == 2
    assert trace.Joined() == "released,after"
}

test "an awaiting finally runs when the consumer abandons the sequence" {
    trace := new CensusTrace()
    seen := 0
    await foreach v in AwaitingFinally(trace) {
        seen = seen + 1
        break
    }
    assert seen == 1
    assert trace.Joined() == "released"
}

test "an exception passes through an awaiting finally and reaches the consumer after it ran" {
    trace := new CensusTrace()
    collected := new List<int>()
    raised := false
    try {
        await foreach v in AwaitingFinallyOverRaise(trace) {
            collected.Add(v)
        }
    } catch ex: InvalidOperationException {
        raised = true
        assert ex.Message == "raised"
        assert ex.StackTrace != null
    }
    assert raised
    assert collected.Count == 1
    assert trace.Joined() == "released"
}

test "a yield break out of a region runs its awaiting finally first" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in AwaitingFinallyOverBreak(trace, 2) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == 0
    assert collected[1] == 1
    // "after" is NOT in the trace: `yield break` ends the sequence, so the recorded branch carries
    // past the handler to the body's end label rather than falling through to the next statement.
    assert trace.Joined() == "released"
}

test "nested awaiting finallys both run, innermost first" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in NestedAwaitingFinally(trace) {
        collected.Add(v)
    }
    assert collected.Count == 1
    assert trace.Joined() == "inner,outer"
}

// EXECUTED PROOFS FOR `await using` INSIDE AN ASYNC GENERATOR.
test "an await using resource is released asynchronously once at the end" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in AsyncScoped(trace) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert trace.Joined() == "acquire r,release r,after"
}

test "an await using resource is released when the consumer stops early" {
    trace := new CensusTrace()
    await foreach v in AsyncScoped(trace) {
        assert v == 1
        break
    }
    assert trace.Joined() == "acquire r,release r"
}

test "an await using resource is released before an exception reaches the consumer" {
    trace := new CensusTrace()
    raised := false
    try {
        await foreach v in AsyncScopedRaising(trace) {
            assert v == 1
        }
    } catch ex: InvalidOperationException {
        raised = true
        assert ex.Message == "raised"
    }
    assert raised
    assert trace.Joined() == "acquire r,release r"
}

// EXECUTED PROOFS FOR `await foreach` INSIDE AN ASYNC GENERATOR.
test "an async generator relays an await foreach to its own consumer" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in Relayed(trace, RecordedAsyncSource(trace, 3)) {
        collected.Add(v)
    }
    assert collected.Count == 3
    assert collected[0] == 0
    assert collected[1] == 2
    assert collected[2] == 4
    assert trace.Joined() == "source released,after"
}

test "abandoning the outer sequence releases the inner await foreach enumerator" {
    trace := new CensusTrace()
    seen := 0
    await foreach v in Relayed(trace, RecordedAsyncSource(trace, 5)) {
        seen = seen + 1
        break
    }
    assert seen == 1
    assert trace.Joined() == "source released"
}

test "an exception inside an await foreach body releases the inner enumerator first" {
    trace := new CensusTrace()
    collected := new List<int>()
    raised := false
    try {
        await foreach v in RelayedRaising(RecordedAsyncSource(trace, 4)) {
            collected.Add(v)
        }
    } catch ex: InvalidOperationException {
        raised = true
        assert ex.Message == "relay"
    }
    assert raised
    assert collected.Count == 2
    assert trace.Joined() == "source released"
}

test "an await using declaration guards the rest of its block" {
    trace := new CensusTrace()
    collected := new List<int>()
    await foreach v in AsyncScopedDeclaration(trace) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert trace.Joined() == "acquire d,release d"
}

test "a plain region nested inside an awaiting one unwinds innermost first" {
    trace := new CensusTrace()
    await foreach v in PlainInsideAwaiting(trace) {
        assert v == 1
    }
    assert trace.Joined() == "inner plain,outer awaiting"

    abandoned := new CensusTrace()
    await foreach v in PlainInsideAwaiting(abandoned) {
        break
    }
    assert abandoned.Joined() == "inner plain,outer awaiting"
}

test "an awaiting region nested inside a plain one unwinds innermost first" {
    trace := new CensusTrace()
    await foreach v in AwaitingInsidePlain(trace) {
        assert v == 1
    }
    assert trace.Joined() == "inner awaiting,outer plain"

    abandoned := new CensusTrace()
    await foreach v in AwaitingInsidePlain(abandoned) {
        break
    }
    assert abandoned.Joined() == "inner awaiting,outer plain"
}
