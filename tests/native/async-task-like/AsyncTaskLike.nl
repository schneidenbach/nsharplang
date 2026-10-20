namespace NSharpLang.AsyncTaskLike.Tests

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks

async func AwaitValue(source: Task<int>): Task<int> {
    return await source
}

async func GenericAwait<T>(source: Task<T>): Task<T> {
    return await source
}

async func TrackedValue(source: Task<int>, started: List<int>, id: int): Task<int> {
    started.Add(id)
    value := await source
    return value + id
}

async func ObserveContinuationContext(gate: Task<int>, expected: SingleThreadTestContext): Task<bool> {
    await gate
    return expected.IsCurrent()
}

async func ThrowBeforeFirstAwait(error: Exception, shouldThrow: bool): Task<int> {
    if shouldThrow {
        throw error
    }
    await Task.Yield()
    return 1
}

async func ThrowAfterAwait(source: Task<int>, error: Exception): Task<int> {
    await source
    throw error
}

async func PropagateCancellation(source: Task<int>): Task<int> {
    return await source
}

class AsyncService {
    Value: int

    constructor(value: int) {
        Value = value
    }

    async func Read(): Task<int> {
        await Task.Yield()
        return Value
    }
}

struct AsyncCounter {
    Value: int

    constructor(value: int) {
        Value = value
    }

    async func Read(): Task<int> {
        await Task.Yield()
        return Value
    }
}

class SingleThreadTestContext: SynchronizationContext {
    Pending: Queue<Action>

    constructor() {
        Pending = new Queue<Action>()
    }

    func IsCurrent(): bool {
        return SynchronizationContext.Current == this
    }

    override func Post(callback: SendOrPostCallback, state: object): void {
        Pending.Enqueue(() => callback(state))
    }

    func PumpUntil(task: Task<bool>) {
        while !task.IsCompleted {
            action := Pending.Dequeue()
            previous := SynchronizationContext.Current
            SynchronizationContext.SetSynchronizationContext(this)
            try {
                action()
            } finally {
                SynchronizationContext.SetSynchronizationContext(previous)
            }
        }
    }
}

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
// result carries `IsCompleted`, a continuation method, and `GetResult()`. `Task.Yield()` answers no
// task at all — it answers a `YieldAwaitable` — but the state machine handles it through that same
// pattern as Task, ValueTask, and user-defined awaitables.
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

// AN AWAITABLE A PROGRAM WRITES FOR ITSELF answers the same pattern and takes the same suspension
// path — there is no list of names to be on.
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

async func AwaitCustom(value: int): Task<int> {
    return await new Immediate(value)
}

// A HAND-WRITTEN `GetAwaiter()`, WHICH IS WHAT `await` LOWERS TO AND WHAT A SYNCHRONOUS WAIT SPELLS.
//
// `Task<TResult>` re-declares `GetAwaiter()` — it returns `TaskAwaiter<TResult>` where the base
// `Task`'s returns `TaskAwaiter` — so reflection hands back BOTH declarations for a `Task<int>`
// receiver and the two tied at zero arguments. That is not an ambiguity: a member declared in a more
// derived type HIDES one of the same signature in a base, and a return type is not part of a
// signature. Until the hiding relation was applied, `t.GetAwaiter()` on a `Task<int>` declined while
// the identical call on a non-generic `Task` bound.
func AwaitedSynchronously(): int {
    return CountedWork().GetAwaiter().GetResult()
}

func AwaiterThroughALocal(): int {
    task := Task.FromResult(11)
    awaiter := task.GetAwaiter()
    return awaiter.GetResult()
}

func UnitAwaitedSynchronously(): bool {
    work := UnitWork()
    work.GetAwaiter().GetResult()
    return work.IsCompleted
}

// A completed await takes the state machine's fast path. The ValueTask builder can return the result
// inline without allocating when every await has already completed; an actually suspended call keeps
// its continuation state until the awaited operation resumes it.
async func NextValue(seed: int): int {
    await Task.CompletedTask
    return seed + 1000
}

async func TouchValue() {
    await Task.CompletedTask
}

async func NextTask(seed: int): Task<int> {
    await Task.CompletedTask
    return seed + 1000
}

async func SlowValue(): int {
    await Task.Delay(20)
    return 5
}
