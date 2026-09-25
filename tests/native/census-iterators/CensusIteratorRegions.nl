namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// A GENERATOR THAT SUSPENDS INSIDE A PROTECTED REGION.
//
// A `try` whose only handler is a `finally` may contain a `yield`. The handler has to run on every
// way the enumeration can end — the body completing, an exception passing through, and a consumer
// that stops early and disposes the enumerator — and must NOT run when the machine merely suspends.
// Each generator below is enumerated for real beside this file so those four paths are observed
// rather than inspected.

// The plain shape: two suspensions inside one `try`, with a statement after the region.
func* GuardedPair(log: List<string>): IEnumerable<int> {
    try {
        yield 1
        log.Add("between")
        yield 2
    } finally {
        log.Add("finally")
    }
    log.Add("after")
}

// Nested regions: abandonment must unwind them innermost first.
func* NestedRegions(log: List<string>): IEnumerable<int> {
    try {
        try {
            yield 1
        } finally {
            log.Add("inner")
        }
        yield 2
    } finally {
        log.Add("outer")
    }
}

// An exception raised after a suspension: it surfaces at `MoveNext` and the handler still runs.
func* GuardedThrow(log: List<string>): IEnumerable<int> {
    try {
        yield 1
        throw new InvalidOperationException("boom")
    } finally {
        log.Add("finally")
    }
}

// `yield break` inside the region: a deliberate early end still runs the handler.
func* GuardedBreak(log: List<string>, stop: bool): IEnumerable<int> {
    try {
        yield 1
        if stop {
            yield break
        }
        yield 2
    } finally {
        log.Add("finally")
    }
}

// A hoisted-enumerator loop inside a user region: the machine's own fault handler (which disposes
// the enumerator) and the source's `finally` compose.
func* GuardedEnumeration(source: List<int>, log: List<string>): IEnumerable<int> {
    try {
        for v in source {
            yield v * 2
        }
    } finally {
        log.Add("finally")
    }
}

// A region INSIDE a loop: the handler runs once per iteration, and an abandonment runs only the
// iteration that was open.
func* RegionPerIteration(source: List<int>, log: List<string>): IEnumerable<int> {
    for v in source {
        try {
            yield v
        } finally {
            log.Add("f" + v.ToString())
        }
    }
}

// A generic machine suspending inside a region: the dispose-driven unwind goes through the member
// handles taken on the machine's own instantiation.
func* GuardedGeneric<T>(first: T, second: T, log: List<string>): IEnumerable<T> {
    try {
        yield first
        yield second
    } finally {
        log.Add("finally")
    }
}

// `catch` and `finally` WITHOUT a suspension: an ordinary protected region inside a generator body,
// which is what most error handling in a generator actually looks like.
func* CaughtInsideBody(): IEnumerable<int> {
    total := 0
    try {
        total = int.Parse("nope")
    } catch e: FormatException {
        total = 7
    } finally {
        total = total + 1
    }
    yield total
}

// A VALUE-TYPED `using` RESOURCE INSIDE A GENERATOR.
//
// The resource lives in one of the machine's own fields, so releasing it means reaching THROUGH that
// field: `ldflda` for the address, `constrained.` so the `Dispose` call runs on that storage rather
// than on a box of it. A box would release a COPY and the recorder below would never see the entry,
// which is exactly what these generators are enumerated to prove.
struct RecordingScope: IDisposable {
    Log: List<string>
    Tag: string

    constructor(log: List<string>, tag: string) {
        Log = log
        Tag = tag
    }

    func Dispose() {
        Log.Add("disposed:" + Tag)
    }
}

// A value type that declares `Dispose` WITHOUT naming the interface: the pattern shape, released by
// a direct call over the same address and with no slot to constrain to.
struct PatternScope {
    Log: List<string>

    constructor(log: List<string>) {
        Log = log
    }

    func Dispose() {
        Log.Add("pattern-disposed")
    }
}

func* ScopedValues(log: List<string>): IEnumerable<int> {
    using scope := new RecordingScope(log, "a") {
        yield 1
        log.Add("between")
        yield 2
    }
    log.Add("after")
}

func* ScopedPattern(log: List<string>): IEnumerable<int> {
    using scope := new PatternScope(log) {
        yield 1
        yield 2
    }
}

// Two value-typed resources nested, so the unwind order is observable.
func* NestedScopes(log: List<string>): IEnumerable<int> {
    using outer := new RecordingScope(log, "outer") {
        using inner := new RecordingScope(log, "inner") {
            yield 1
        }
        yield 2
    }
}
