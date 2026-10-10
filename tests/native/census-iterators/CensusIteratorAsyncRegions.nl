namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks


// PROTECTED REGIONS INSIDE AN `async func*`.
//
// A `try` and a `using` are the same thing to a state machine — a region whose handler must run on
// every final way out — and the machinery that makes them work is the machinery a SYNCHRONOUS
// generator already had: a region ordinal, a region-entry label the dispatch hops through (a branch
// INTO a protected region is illegal IL), a handler guarded by `state < 0` so a suspension that
// merely leaves the region does not release anything, and a dispose flag that lets an abandoned
// machine walk back to where it stood and leave every region properly.
//
// The one thing an async machine adds is that its resume states INTERLEAVE `yield` and `await` in
// walk order, so the region table is keyed by the shared suspension counter rather than by the
// yield count alone.

// A `try`/`finally` whose body both suspends and yields. The handler runs once, after the sequence
// ends — not at either suspension.
async func* Guarded(trace: CensusTrace): IAsyncEnumerable<int> {
    try {
        trace.Add("enter")
        await Task.Delay(1)
        yield 1
        yield 2
    } finally {
        trace.Add("finally")
    }
    trace.Add("after")
}

// A `try`/`catch` around an awaiting body: the exception is caught inside the machine and the
// sequence continues. C# admits an `await` inside a `try` that declares a `catch` (only `yield`
// is refused there), and so does this.
async func* Caught(trace: CensusTrace): IAsyncEnumerable<int> {
    try {
        await Task.Delay(1)
        throw new InvalidOperationException("inner")
    } catch ex: InvalidOperationException {
        trace.Add(ex.Message)
    }
    yield 9
}

// A `try`/`finally` whose body RAISES after a suspension: the handler runs before the exception
// reaches the consumer.
async func* Raising(trace: CensusTrace): IAsyncEnumerable<int> {
    try {
        await Task.Delay(1)
        yield 1
        throw new InvalidOperationException("raised")
    } finally {
        trace.Add("finally")
    }
}

// A synchronous `using` resource inside an async generator: acquired once, released once, and NOT
// released at the suspension the consumer is about to come back to.
async func* Scoped(trace: CensusTrace): IAsyncEnumerable<int> {
    using r := new CensusRecordingResource(trace, "r") {
        await Task.Delay(1)
        yield 1
        yield 2
    }
}

// NESTED regions, so the unwind order is observable: the inner handler runs before the outer one.
async func* Nested(trace: CensusTrace): IAsyncEnumerable<int> {
    try {
        try {
            await Task.Delay(1)
            yield 1
        } finally {
            trace.Add("inner")
        }
    } finally {
        trace.Add("outer")
    }
}

// A SUSPENSION NUMBERED AFTER AN AWAIT, inside a region. The resume states of an async machine
// interleave `yield` and `await` in walk order under one counter, so the two yields below are
// states 3 and 4 while the awaits are 1 and 2. A region table keyed by the YIELD count alone would
// record the wrong region for both of them, and the abandonment below would unwind nothing.
async func* InterleavedRegion(trace: CensusTrace): IAsyncEnumerable<int> {
    await Task.Delay(1)
    try {
        await Task.Delay(1)
        yield 1
        yield 2
    } finally {
        trace.Add("finally")
    }
}

// A recording resource: an ordinary source class implementing IDisposable, so the release the
// machine performs is observable from the test.
class CensusRecordingResource: IDisposable {
    Trace: CensusTrace
    Name: string

    constructor(trace: CensusTrace, name: string) {
        Trace = trace
        Name = name
        trace.Add("acquire " + name)
    }

    func Dispose() {
        Trace.Add("release " + Name)
    }
}

// AN `await` INSIDE A `finally`. The handler cannot run inside the region it guards — a suspension
// leaves the method with an empty stack and comes back through the state dispatch, and a dispatch
// cannot branch INTO a protected region — so the handler body is HOISTED to the ordinary code just
// past the region, a catch-all parks the exception in flight, and a branch out of the statement
// records where it was going. This is Roslyn's lowering, and these are its observable contracts.
async func* AwaitingFinally(trace: CensusTrace): IAsyncEnumerable<int> {
    try {
        await Task.Delay(1)
        yield 1
        yield 2
    } finally {
        await Task.Delay(1)
        trace.Add("released")
    }
    trace.Add("after")
}

// The body RAISES: the parked exception is re-raised after the awaiting handler ran, through
// `ExceptionDispatchInfo` so the original stack trace survives the hoist.
async func* AwaitingFinallyOverRaise(trace: CensusTrace): IAsyncEnumerable<int> {
    try {
        yield 1
        await Task.Delay(1)
        throw new InvalidOperationException("raised")
    } finally {
        await Task.Delay(1)
        trace.Add("released")
    }
}

// A `yield break` OUT of the region: the recorded branch is what makes the handler run before the
// sequence ends, instead of the exit jumping straight past it.
async func* AwaitingFinallyOverBreak(trace: CensusTrace, stopAt: int): IAsyncEnumerable<int> {
    try {
        i := 0
        while i < 4 {
            if i == stopAt {
                yield break
            }
            yield i
            await Task.Delay(1)
            i = i + 1
        }
    } finally {
        await Task.Delay(1)
        trace.Add("released")
    }
    trace.Add("after")
}

// NESTED awaiting handlers: the inner branch has to hop through the outer one rather than jumping
// to the body's end label, so both handlers run and in the right order.
async func* NestedAwaitingFinally(trace: CensusTrace): IAsyncEnumerable<int> {
    try {
        try {
            yield 1
            yield break
        } finally {
            await Task.Delay(1)
            trace.Add("inner")
        }
    } finally {
        await Task.Delay(1)
        trace.Add("outer")
    }
}

// `await using` INSIDE AN ASYNC GENERATOR. The resource is acquired before the region entry — a
// resume branches straight to that label, so it never acquires a second one — the body keeps the
// region, and `DisposeAsync()` is awaited in the hoisted handler just past it.
class CensusAsyncRecordingResource: IAsyncDisposable {
    Trace: CensusTrace
    Name: string

    constructor(trace: CensusTrace, name: string) {
        Trace = trace
        Name = name
        trace.Add("acquire " + name)
    }

    async func DisposeAsync(): ValueTask {
        await Task.Delay(1)
        Trace.Add("release " + Name)
    }
}

async func* AsyncScoped(trace: CensusTrace): IAsyncEnumerable<int> {
    await using r := new CensusAsyncRecordingResource(trace, "r") {
        await Task.Delay(1)
        yield 1
        yield 2
    }
    trace.Add("after")
}

async func* AsyncScopedRaising(trace: CensusTrace): IAsyncEnumerable<int> {
    await using r := new CensusAsyncRecordingResource(trace, "r") {
        yield 1
        throw new InvalidOperationException("raised")
    }
}

// `await foreach` INSIDE AN `async func*` — two machines composed. The inner enumerator is acquired
// before the region entry and released by the hoisted handler on all three paths: the loop's normal
// exit, an exception passing through the body, and a consumer that abandons the OUTER enumeration.
async func* Relayed(trace: CensusTrace, source: IAsyncEnumerable<int>): IAsyncEnumerable<int> {
    await foreach v in source {
        yield v * 2
    }
    trace.Add("after")
}

async func* RelayedRaising(source: IAsyncEnumerable<int>): IAsyncEnumerable<int> {
    await foreach v in source {
        if v > 1 {
            throw new InvalidOperationException("relay")
        }
        yield v
    }
}

// A RECORDING ASYNC SEQUENCE, so the inner enumerator's own `DisposeAsync()` is observable from the
// test: this is what proves an abandoned outer consumer releases the inner enumeration.
async func* RecordedAsyncSource(trace: CensusTrace, count: int): IAsyncEnumerable<int> {
    try {
        i := 0
        while i < count {
            await Task.Delay(1)
            yield i
            i = i + 1
        }
    } finally {
        trace.Add("source released")
    }
}

// THE `await using` DECLARATION FORM guards the REST OF ITS BLOCK, exactly as the synchronous
// declaration does — the region is opened around the statements after it, not around the
// declaration, and both passes hand the remainder to the same region.
async func* AsyncScopedDeclaration(trace: CensusTrace): IAsyncEnumerable<int> {
    await using r := new CensusAsyncRecordingResource(trace, "d")
    await Task.Delay(1)
    yield 1
    yield 2
}

// A PLAIN region nested inside an AWAITING one: the inner `finally` is a real EH clause whose
// handler runs on the `leave`, and the outer one is hoisted past the region. Both orders are
// written below so neither nesting can silently lose a handler.
async func* PlainInsideAwaiting(trace: CensusTrace): IAsyncEnumerable<int> {
    try {
        try {
            yield 1
        } finally {
            trace.Add("inner plain")
        }
    } finally {
        await Task.Delay(1)
        trace.Add("outer awaiting")
    }
}

async func* AwaitingInsidePlain(trace: CensusTrace): IAsyncEnumerable<int> {
    try {
        try {
            yield 1
        } finally {
            await Task.Delay(1)
            trace.Add("inner awaiting")
        }
    } finally {
        trace.Add("outer plain")
    }
}
