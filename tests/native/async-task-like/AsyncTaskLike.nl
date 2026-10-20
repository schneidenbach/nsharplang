namespace NSharpLang.AsyncTaskLike.Tests

import System
import System.Collections.Generic
import System.IO
import System.Runtime.CompilerServices
import System.Threading
import System.Threading.Tasks

async func AwaitValue(source: Task<int>): Task<int> {
    return await source
}

async func ReturnTaskValue(value: int): Task<int> {
    await Task.CompletedTask
    return value
}

async func CreateDirectoryBeforeAwait(path: string?, gate: Task<int>): Task<int> {
    Directory.CreateDirectory(must path)
    return await gate
}

func IdentityDouble(value: double): double {
    return value
}

async func NegateCallAfterAwait(source: Task<double>): Task<double> {
    value := await source
    return -IdentityDouble(value)
}

async func AwaitTaskCallWithAwaitedArgument(source: Task<int>): Task<int> {
    return await ReturnTaskValue(await source)
}

async func AwaitTaskCallWithAwaitedArgumentStored(source: Task<int>): Task<int> {
    pending := ReturnTaskValue(await source)
    return await pending
}

func InterpolatedTask(value: string): Task<string> {
    return Task.FromResult(value)
}

async func AwaitInterpolatedArgument(source: Task<int>): Task<string> {
    value := await source
    return await InterpolatedTask($"value {value}")
}

class ContinuationCounter {
    Value: int

    func Mark() {
        Value += 1
    }

    func MarkAndReturn(value: int): int {
        Value += value
        return Value
    }
}

async func AwaitContinuationCallback(source: Task, gate: Task<int>, counter: ContinuationCounter): Task<int> {
    continuation := source.ContinueWith(completed => counter.Mark(), TaskScheduler.Default)
    await gate
    await continuation
    return counter.Value
}

async func AwaitAfterDiscardedTask(gate: Task<int>): Task<int> {
    _ = Task.FromResult(13)
    return await gate
}

async func AwaitDiscardedStreamContinuation(source: Stream, destination: Stream, copied: TaskCompletionSource<int>, gate: Task<int>): Task<int> {
    _ = source.CopyToAsync(destination).ContinueWith(pumped => copied.SetResult(1), TaskScheduler.Default)
    await copied.Task
    return await gate
}

async func AwaitVoidCompatibleExpressionLambda(gate: Task<int>, counter: ContinuationCounter): Task<int> {
    value := await gate
    values := new List<int>()
    values.Add(value)
    values.ForEach(item => counter.MarkAndReturn(item))
    return counter.Value
}

async func ReturnAfterBranch(skip: bool, gate: Task<int>): Task<int> {
    if skip {
        return 17
    }
    return await gate
}

async func ReturnFromUnitBranch(skip: bool, gate: Task): Task {
    if skip {
        return
    }
    await gate
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

async func SafeCastAfterAwait(value: object?, gate: Task): Task<string?> {
    await gate
    return value as string
}

async func SafeCastConditionAfterAwait(value: object?, gate: Task): Task<bool> {
    await gate
    castValue := value as string
    return castValue != null
}

async func IsNonNullAfterAwait(value: object?, gate: Task): Task<bool> {
    await gate
    return value != null
}

async func SafeCastLocalAfterAwait(value: object?, gate: Task): Task<string?> {
    await gate
    castValue := value as string
    return castValue
}

class AsyncService {
    Value: int

    constructor(value: int) {
        Value = value
    }

    public async func ClassRead(gate: Task): Task<int> {
        await gate
        return Value
    }

    public async func ClassWrite(gate: Task<int>): Task<int> {
        Value = await gate
        return Value
    }
}

async func IsSourceReferenceNonNullAfterAwait(value: AsyncService?, gate: Task): Task<bool> {
    await gate
    return value != null
}

async func IsSafeCastNonNullAfterAwait(value: object?, gate: Task): Task<bool> {
    await gate
    return (value as AsyncService) != null
}

class AsyncGenericService {
    async func Echo<T>(source: Task<T>): Task<T> {
        await Task.Yield()
        return await source
    }
}

class AsyncGenericContainer<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    async func GetAfter(gate: Task): T {
        await gate
        return Value
    }

    async func Echo<U>(source: Task<U>): U {
        await Task.Yield()
        return await source
    }
}

struct AsyncCounter {
    Value: int

    constructor(value: int) {
        Value = value
    }

    async func StructRead(gate: Task): Task<int> {
        await gate
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

    func GetAwaiter(_unused: int): ImmediateAwaiter {
        return new ImmediateAwaiter(Value)
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

    func GetResult(_unused: int): int {
        return Value
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

async func AwaitValueTask(source: ValueTask<int>): ValueTask<int> {
    return await source
}

func SumThree(first: int, second: int, third: int): int {
    return first + second + third
}

async func AwaitNestedArguments(first: Task<int>, second: Task<int>, third: Task<int>): Task<int> {
    return SumThree(await first, await second, await third)
}

async func AwaitNestedBinary(first: Task<int>, second: Task<int>): Task<int> {
    return (await first) + (await second)
}

async func AwaitIndexedValue(values: List<int>, index: Task<int>): Task<int> {
    return values[await index]
}

async func AwaitLoop(gate: Task<int>): Task<int> {
    total := 0
    for i := 0; i < 3; i++ {
        if i == 1 {
            total = total + await gate
        } else {
            await Task.CompletedTask
            total = total + i
        }
    }
    return total
}

async func AwaitHandlers(source: Task<int>, catchGate: Task, finallyGate: Task, trace: List<string>): Task<int> {
    try {
        await source
        throw new InvalidOperationException("enter catch")
    } catch error: InvalidOperationException {
        trace.Add("catch-start")
        await catchGate
        trace.Add("catch-end")
        return 73
    } finally {
        trace.Add("finally-start")
        await finallyGate
        trace.Add("finally-end")
    }
}

class AsyncReleaseResource: IAsyncDisposable {
    Gate: Task
    Trace: List<string>

    constructor(gate: Task, trace: List<string>) {
        Gate = gate
        Trace = trace
    }

    async func DisposeAsync(): ValueTask {
        await Gate
        Trace.Add("disposed")
    }
}

async func AwaitUsingResource(gate: Task, trace: List<string>): Task<int> {
    await using resource := new AsyncReleaseResource(gate, trace) {
        trace.Add("body")
    }
    trace.Add("tail")
    return 31
}

class SyncReleaseResource: IDisposable {
    Trace: List<string>

    constructor(trace: List<string>) {
        Trace = trace
    }

    func Dispose() {
        Trace.Add("disposed")
    }
}

async func AwaitInsideUsing(gate: Task<int>, trace: List<string>): Task<int> {
    using resource := new SyncReleaseResource(trace) {
        value := await gate
        trace.Add("body")
        return value
    }
}

async func* WaitAndYield(gate: Task<int>): IAsyncEnumerable<int> {
    value := await gate
    yield value
}

async func ConsumeWaitAndYield(gate: Task<int>): Task<int> {
    total := 0
    await foreach value in WaitAndYield(gate) {
        total = total + value
    }
    return total
}

async func ObserveConfiguredContext(gate: Task<int>, expected: SingleThreadTestContext): Task<bool> {
    await gate.ConfigureAwait(false)
    return !expected.IsCurrent()
}

class CriticalAwaitable {
    Source: Task<int>
    Trace: List<string>

    constructor(source: Task<int>, trace: List<string>) {
        Source = source
        Trace = trace
    }

    func GetAwaiter(): CriticalAwaiter {
        return new CriticalAwaiter(Source, Trace)
    }
}

class CriticalAwaiter: ICriticalNotifyCompletion {
    Source: Task<int>
    Trace: List<string>

    constructor(source: Task<int>, trace: List<string>) {
        Source = source
        Trace = trace
    }

    IsCompleted: bool {
        get {
            return Source.IsCompleted
        }
    }

    func GetResult(): int {
        return Source.GetAwaiter().GetResult()
    }

    func OnCompleted(continuation: Action) {
        Trace.Add("safe")
        Source.GetAwaiter().OnCompleted(continuation)
    }

    func UnsafeOnCompleted(continuation: Action) {
        Trace.Add("unsafe")
        Source.GetAwaiter().UnsafeOnCompleted(continuation)
    }
}

async func AwaitCritical(source: CriticalAwaitable): Task<int> {
    return await source
}

async func CaptureAsyncLambda(gate: Task): Task<int> {
    captured := 3
    read: Func<Task<int>> = async () => {
        await gate
        return captured
    }
    pending := read()
    captured = 9
    return await pending
}

async func CaptureSynchronousLambdaAcrossAwait(gate: Task): Task<int> {
    captured := 4
    read: Func<int> = () => captured
    await gate
    captured = 16
    return read()
}

async func CaptureAsyncLocalFunction(gate: Task): Task<int> {
    captured := 4
    async func ReadLocal(): Task<int> {
        await gate
        return captured
    }
    pending := ReadLocal()
    captured = 10
    return await pending
}

func StartCapturedAsyncLocalFunction(gate: Task): Task<int> {
    captured := 4
    async func ReadLocal(): Task<int> {
        await gate
        return captured
    }
    pending := ReadLocal()
    captured = 10
    return pending
}

func StartGenericAsyncLocalFunction(source: Task<string>): Task<string> {
    async func EchoLocal<T>(value: Task<T>): Task<T> {
        await Task.Yield()
        return await value
    }
    return EchoLocal(source)
}

class AsyncIlShapes {
    static async func ShapeRead(source: Task<int>): Task<int> {
        return await source
    }
}
