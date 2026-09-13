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
