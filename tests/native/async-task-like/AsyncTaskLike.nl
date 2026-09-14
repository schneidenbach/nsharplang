namespace NSharpLang.AsyncTaskLike.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks

// The async task-family return shapes whose CALL results must remain usable values. An
// `async func(): Task` used to crash `nlc check` the moment its call result was touched with a
// member access: the analyzer failed to recognise the declared bare `Task` as task-like when it
// resolved through the reference scan, wrapped the call type into `ValueTask<Task>`, and the
// mixed-context conversion of that shape poisoned every member lookup. The functions here and the
// consumers in the tests are the end-to-end pin that the whole family analyzes, emits and RUNS.
async func UnitWork(): Task {
    await Task.Delay(1)
}

async func CountedWork(): Task<int> {
    await Task.Delay(1)
    return 41
}

async func UnitValueWork(): ValueTask {
    await Task.Delay(1)
}

async func CountedValueWork(): ValueTask<int> {
    await Task.Delay(1)
    return 42
}

async func* CountUp(): IAsyncEnumerable<int> {
    yield 1
    await Task.Delay(1)
    yield 2
}

// The slice-36 census shape: an `await foreach` inside an async function returning the bare `Task`.
async func DrainAll(): Task {
    total := 0
    await foreach value in CountUp() {
        total = total + value
    }

    if total != 3 {
        throw new InvalidOperationException(
            "The async iterator drained to " + total.ToString() + " instead of 3."
        )
    }
}

async func SumCounted(): Task<int> {
    total := 0
    await foreach value in CountUp() {
        total = total + value
    }
    return total
}

// WHAT MAKES A VALUE AWAITABLE IS THE PATTERN, NOT ITS NAME: a parameterless `GetAwaiter()` whose
// result carries `IsCompleted` and `GetResult()`. `Task.Yield()` answers no task at all — it answers
// a `YieldAwaitable` — so `await Task.Yield()` declined at `emit.expression-statement.await` while
// the four task shapes beside it emitted. The blocking lowering the task shapes use is the one this
// pattern takes: take the awaiter, spill it, call `GetResult()` on it.
async func YieldingWork(): Task<int> {
    await Task.Yield()
    total := 1
    await Task.Yield()
    return total + 41
}

// A UNIT async body whose only statement is a bare `await Task.Yield()`.
async func YieldOnce(): Task {
    await Task.Yield()
}

// AN AWAITABLE A PROGRAM WRITES FOR ITSELF answers the same pattern and takes the same lowering —
// there is no list of names to be on.
class Immediate {
    Value: int

    constructor(value: int) {
        Value = value
    }

    func GetAwaiter(): ImmediateAwaiter {
        return new ImmediateAwaiter(Value)
    }
}

class ImmediateAwaiter: System.Runtime.CompilerServices.INotifyCompletion {
    Value: int

    constructor(value: int) {
        Value = value
    }

    IsCompleted: bool {
        get {
            return true
        }
    }

    func OnCompleted(continuation: Action) {
        continuation()
    }

    func GetResult(): int {
        return Value
    }
}

func AwaitCustom(value: int): int {
    return await new Immediate(value)
}
