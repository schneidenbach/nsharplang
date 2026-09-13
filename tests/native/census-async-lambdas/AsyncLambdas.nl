namespace NSharpLang.CensusAsyncLambdas.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks


// AN `async` LAMBDA IN EVERY POSITION A LAMBDA IS ACCEPTED.
//
// The keyword changes what the body MEANS, not what it looks like: the body produces the RESULT the
// target delegate's task carries, the delegate's own signature is unchanged, and an exception the
// body raises lands on the returned TASK instead of on whoever built the delegate. These are the
// shapes; the contracts beside them assert the values, the faults and the captures at runtime.

// An EXPRESSION body against `Func<Task<T>>`: the body is `T`, the delegate returns `Task<T>`.
func expressionBodyFactory(): Func<Task<int>> {
    return async () => await Task.FromResult(7)
}

// ONE PARAMETER, contextually typed from the delegate exactly as an ordinary lambda's is.
func doublingFactory(): Func<int, Task<int>> {
    return async x => await Task.FromResult(x * 2)
}

// TWO PARAMETERS.
func addingFactory(): Func<int, int, Task<int>> {
    return async (a, b) => await Task.FromResult(a + b)
}

// A BLOCK body: its `return` is measured against the task's RESULT, not against the task.
func blockBodyFactory(): Func<Task<int>> {
    return async () => {
        v := await Task.FromResult(20)
        return v + 1
    }
}

// A UNIT task (`Func<Task>`): the body produces no value, and the completed task is what the caller
// gets. A bare `return` inside it is legal for the same reason it is legal in a unit `async func`.
func unitTaskFactory(log: List<string>): Func<Task> {
    return async () => {
        await Task.Delay(1)
        log.Add("ran")
    }
}

// THE `ValueTask` FAMILY. Which family the value is wrapped in is the TARGET's decision, not the
// body's — the same body serves `Task<T>` and `ValueTask<T>`.
func valueTaskFactory(): Func<ValueTask<int>> {
    return async () => await Task.FromResult(9)
}

func unitValueTaskFactory(log: List<string>): Func<ValueTask> {
    return async () => {
        await Task.Delay(1)
        log.Add("unit value task")
    }
}

// A CAPTURE. The display class an `async` lambda builds is the ordinary closure display: a captured
// local is read from it exactly as a synchronous lambda reads one.
func capturingFactory(seed: int): Func<Task<int>> {
    return async () => {
        v := await Task.FromResult(seed)
        return v + 1
    }
}

// PER-ITERATION CAPTURE. Each turn of the loop declares its own `seed`, so each lambda closes over a
// DIFFERENT variable and the three tasks answer three different values.
func perIterationFactories(): List<Func<Task<int>>> {
    factories := new List<Func<Task<int>>>()
    for i := 0; i < 3; i++ {
        seed := i
        factories.Add(async () => {
            await Task.Delay(1)
            return seed * 10
        })
    }

    return factories
}

// A FAULT. The exception does NOT reach the caller that built the delegate or the caller that
// invoked it — it is delivered through the task, which is the whole difference an `async` body makes.
func faultingFactory(): Func<Task<int>> {
    return async () => {
        await Task.Delay(1)
        throw new InvalidOperationException("async lambda boom")
    }
}

// A RETHROW INSIDE AN ASYNC LAMBDA. The handler is a real EH clause on the lambda's own method, so a
// bare `throw` re-raises with the original trace — and the async guard turns it into a faulted task.
func rethrowingFactory(): Func<Task<int>> {
    return async () => {
        try {
            return failInside(9)
        } catch e: InvalidOperationException {
            throw
        }
    }
}

// AN ARGUMENT POSITION, which is where the converter's census found them: `Task.Run` declares
// `Action` beside `Func<Task>`, and an `async` lambda is never the `Action`.
func runOnThreadPool(log: List<string>) {
    await Task.Run(async () => {
        await Task.Delay(1)
        log.Add("pool")
    })
}

// AN INSTANCE MEMBER'S LAMBDA capturing `this`: the lambda reads the enclosing instance's field
// through the display exactly as a synchronous one does.
class Counter {
    Start: int

    constructor(start: int) {
        Start = start
    }

    func NextFactory(): Func<Task<int>> {
        return async () => {
            v := await Task.FromResult(Start)
            return v + 1
        }
    }
}

// AN `async` LOCAL FUNCTION. It declares its INNER type exactly as a top-level `async func` does —
// `async func inner(): int` is a method returning `ValueTask<int>` — and its body is wrapped and
// guarded the same way, so an exception it raises lands on the task it returns.
func localAsyncDoubling(x: int): int {
    async func inner(value: int): int {
        await Task.Delay(1)
        return value * 2
    }

    return await inner(x)
}

// A CAPTURING one: the closure lowering is the ordinary local-function display, so the counter it
// mutates is shared with the enclosing body.
func localAsyncCounting(): int {
    total := 0
    async func bump() {
        await Task.Delay(1)
        total = total + 1
    }

    await bump()
    await bump()
    await bump()
    return total
}

// The fault contract, from a local function: the exception is on the returned task.
func localAsyncFaulting(): ValueTask<int> {
    async func inner(): int {
        await Task.Delay(1)
        throw new InvalidOperationException("local async boom")
    }

    return inner()
}
