namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Collections.Generic


// CENSUS §2 — A `return` INSIDE A `try` THAT HAS A `finally` IS A RETURN.
//
// The shape every converted C# `using (...) { ... return x }` produces, because `using` lowers to
// try/finally. The census found 7 of them in the converted CLI and 19 in the converted tests, and
// every one was told "not all code paths return a value". The sources below are the shapes the rule
// has to get right AND the IL has to execute: a `return` out of a protected region leaves the region
// through the handler, so the value has to survive the `finally` that runs on the way out.

// The census probe itself, reduced to something with an observable result.
func TryFinallyReturnsValue(log: List<string>): List<int> {
    values := new List<int>()
    values.Add(1)
    try {
        return values
    } finally {
        log.Add("finally")
    }
}

// The `finally` runs BEFORE the caller sees the value, and it cannot change the value that is already
// on its way out.
func FinallyRunsOnTheWayOut(log: List<string>): int {
    counter := 41
    try {
        counter = counter + 1
        return counter
    } finally {
        log.Add("finally")
        counter = 0
    }
}

// try/catch/finally: the guarded block returns, the handler returns, and the `finally` runs for both.
func TryCatchFinallyReturns(fail: bool, log: List<string>): string {
    try {
        if fail {
            throw new InvalidOperationException("boom")
        }

        return "guarded"
    } catch error: InvalidOperationException {
        return "handler:" + error.Message
    } finally {
        log.Add("finally")
    }
}

// NESTED protected regions, returning from the inner one. Both finallys run, innermost first.
func NestedTryFinallyReturns(log: List<string>): int {
    try {
        try {
            return 7
        } finally {
            log.Add("inner")
        }
    } finally {
        log.Add("outer")
    }
}

// A `finally` that LEAVES by itself settles the statement even when the guarded block falls through —
// C#'s end-point rule, and the one arm where the finally is the reason the function returns.
func FinallyThatThrowsSettlesIt(log: List<string>): int {
    try {
        log.Add("guarded")
    } finally {
        throw new InvalidOperationException("from finally")
    }
}

// A `using` written out by hand, which is what the converter produces: acquire, guard, dispose in a
// `finally`, and return from inside the guarded block.
class CountingResource: IDisposable {
    disposals: int
    text: string

    constructor(text: string) {
        this.text = text
        disposals = 0
    }

    Disposals: int => disposals

    func Read(): string {
        return text
    }

    func Dispose() {
        disposals = disposals + 1
    }
}

func UsingShapeReturns(resource: CountingResource): string {
    try {
        value := resource.Read()
        if value.Length == 0 {
            return "<empty>"
        }

        return value
    } finally {
        resource.Dispose()
    }
}

// The NEGATIVE half of the rule stays put: a guarded block that falls through does not return, so a
// function of this shape still needs the trailing return that is written here.
func GuardedBlockFallsThrough(log: List<string>): int {
    result := 0
    try {
        result = 5
    } finally {
        log.Add("finally")
    }

    return result
}
