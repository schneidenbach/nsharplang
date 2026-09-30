namespace NSharpLang.CensusAsyncLambdas.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks


// THE TWO WAYS TO RE-RAISE A CAUGHT EXCEPTION, side by side so a test can tell them apart at
// runtime. `throw` alone re-raises the exception the handler is running for and leaves its stack
// trace alone; `throw e` raises the same OBJECT again from the handler, which resets the trace to
// the handler's own frame. The difference is only visible from BELOW the handler, so every helper
// here throws from a callee the JIT will not inline away.
func failInside(seed: int): int {
    total := seed
    for i := 0; i < 4; i++ {
        total = total + i * 3
        if total > 1000000 {
            total = total - 1
        }
    }

    if total >= 0 {
        throw new InvalidOperationException("inner failure " + total.ToString())
    }

    return total
}

// A bare `throw` in a `catch` that names its exception.
func rethrowFromNamedCatch(): int {
    try {
        return failInside(1)
    } catch e: InvalidOperationException {
        throw
    }
}

// A bare `throw` in a `catch` that names NO exception — there is still exactly one exception in
// flight, and `rethrow` names it by standing in the handler.
func rethrowFromBareCatch(): int {
    try {
        return failInside(2)
    } catch {
        throw
    }
}

// The contrast: the same object, thrown again by name.
func throwCaughtByName(): int {
    try {
        return failInside(3)
    } catch e: InvalidOperationException {
        throw e
    }
}

// A bare `throw` inside a `try` nested in the handler: the rethrow still stands in the OUTER
// handler's funclet, so it re-raises the outer exception. The `finally` records that it ran on the
// way out, into a log the caller owns.
func rethrowFromNestedTry(log: List<string>): int {
    try {
        return failInside(4)
    } catch e: InvalidOperationException {
        try {
            throw
        } finally {
            log.Add("finally ran")
        }
    }
}

// A `finally` still runs on the way out of a rethrow, and the rethrown exception keeps travelling.
func rethrowThroughFinally(log: List<string>): int {
    try {
        try {
            return failInside(5)
        } catch e: InvalidOperationException {
            throw
        }
    } finally {
        log.Add("outer finally ran")
    }
}

// A bare `throw` in an INNER handler re-raises the INNER exception, not the outer one.
func rethrowInnerOfTwo(): string {
    try {
        try {
            throw new ArgumentException("inner")
        } catch inner: ArgumentException {
            throw
        }
    } catch outer: Exception {
        return outer.Message
    }
}

// The rethrown exception is the SAME object the handler caught, not a copy.
func rethrowPreservesIdentity(): bool {
    let caught: Exception? = null
    try {
        try {
            failInside(6)
        } catch e: InvalidOperationException {
            caught = e
            throw
        }
    } catch again: Exception {
        return object.ReferenceEquals(caught, again)
    }

    return false
}

// A rethrow inside an ASYNC body. An async body is lowered with its own fault guard around the whole
// method, so the user's handler nests inside it: the rethrown exception lands on the RETURNED TASK
// rather than on the caller's frame, and it keeps the trace it was first raised with.
async func rethrowFromAsync(): int {
    try {
        await Task.Delay(1)
        return failInside(7)
    } catch e: InvalidOperationException {
        throw
    }
}

// A rethrow inside a GENERATOR body. The handler is a real EH clause on the state machine's
// `MoveNext`, so `rethrow` stands in a handler of the same method exactly as it does in an ordinary
// body — the exception surfaces from the consumer's `for` loop.
func* rethrowFromGenerator(): IEnumerable<int> {
    yield 11
    try {
        failInside(8)
    } catch e: InvalidOperationException {
        throw
    }
}
