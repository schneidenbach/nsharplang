namespace NSharpLang.AsyncTaskLike.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.Reflection
import System.Runtime.CompilerServices
import System.Threading
import System.Threading.Tasks

// Every test touches a MEMBER of an async call result — the exact move that used to crash
// `nlc check` for the bare-`Task` family before the task-identity fix.
test "an async unit Task call result is a value whose members resolve and run" {
    work := UnitWork()
    work.Wait()
    assert work.IsCompleted
}

test "an async Task of int call result carries its awaited result" {
    actual := CountedWork().Result
    assert actual == 41, "CountedWork returned " + actual.ToString()
}

test "an async unit ValueTask call result converts to a waitable task" {
    converted := UnitValueWork().AsTask()
    converted.Wait()
    assert converted.IsCompleted
}

test "an async ValueTask of int call result carries its awaited result" {
    assert CountedValueWork().AsTask().Result == 42
}

test "an await foreach inside a bare Task function drains and completes" {
    drained := DrainAll()
    drained.Wait()
    assert drained.IsCompleted
}

test "an await foreach inside a Task of int function accumulates the async iterator" {
    assert SumCounted().Result == 3
}

test "await reaches any value with the awaiter pattern, task or not" {
    counted := YieldingWork()
    countedValue := await counted
    assert countedValue == 42

    unit := YieldOnce()
    unit.Wait()
    assert unit.get_IsCompleted()

    assert (await AwaitCustom(7)) == 7
    assert (await AwaitCustom(0)) == 0
}

test "`GetAwaiter()` written out works on a generic task, not only on a unit one" {
    assert AwaitedSynchronously() == 41
    assert AwaiterThroughALocal() == 11
    assert UnitAwaitedSynchronously()
}

test "an async function returns while its awaited task is incomplete and resumes with its result" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitValue(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(5)
    assert pending.Result == 5
}

test "a generic async function has its own resumable state machine" {
    gate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := GenericAwait(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult("generic")
    assert pending.Result == "generic"
}

test "both async calls reach their awaits before either task is released" {
    firstGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    secondGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    started := new List<int>()
    first := TrackedValue(firstGate.Task, started, 1)
    second := TrackedValue(secondGate.Task, started, 2)

    assert started.Count == 2
    assert started[0] == 1 && started[1] == 2
    assert !first.IsCompleted && !second.IsCompleted

    secondGate.SetResult(20)
    firstGate.SetResult(10)
    assert first.Result == 11
    assert second.Result == 22
}

test "an incomplete await posts its continuation to the captured single-thread context" {
    context := new SingleThreadTestContext()
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    previous := SynchronizationContext.Current
    SynchronizationContext.SetSynchronizationContext(context)
    pending := ObserveContinuationContext(gate.Task, context)
    SynchronizationContext.SetSynchronizationContext(previous)

    assert !pending.IsCompleted
    gate.SetResult(1)
    context.PumpUntil(pending)
    assert pending.Result
}

test "exceptions before the first await fault the task instead of escaping the call" {
    expected := new InvalidOperationException("before first await")
    pending := ThrowBeforeFirstAwait(expected, true)
    assert pending.IsFaulted
    assert (must pending.Exception).InnerException == expected

    expectedNoThrow := ThrowBeforeFirstAwait(expected, false)
    assert expectedNoThrow.Result == 1
}

test "exceptions after an await fault the task with the original exception" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    expected := new InvalidOperationException("after await")
    pending := ThrowAfterAwait(gate.Task, expected)
    assert !pending.IsCompleted
    gate.SetResult(9)

    observed := false
    try {
        pending.Wait()
    } catch error: AggregateException {
        observed = error.InnerException == expected
    }
    assert observed
}

test "cancellation while awaiting completes the returned task as canceled" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := PropagateCancellation(gate.Task)
    assert !pending.IsCompleted

    gate.SetCanceled()
    canceled := false
    try {
        pending.Wait()
    } catch error: AggregateException {
        canceled = pending.IsCanceled && error.InnerException is TaskCanceledException
    }
    assert canceled
}

test "an instance async method captures its class receiver across suspension" {
    service := new AsyncService(37)
    pending := service.Read()
    assert !pending.IsCompleted
    assert pending.Result == 37
}

test "an instance async method copies its struct receiver across suspension" {
    counter := new AsyncCounter(53)
    pending := counter.Read()
    assert !pending.IsCompleted
    assert pending.Result == 53
}

test "an async kickoff exposes its generated value-type state machine metadata" {
    method := typeof(AsyncService).GetMethod("Read")
    assert method != null
    stateMachineAttribute := method.GetCustomAttribute<AsyncStateMachineAttribute>()
    assert stateMachineAttribute != null

    stateMachineType := stateMachineAttribute.StateMachineType
    assert stateMachineType.IsValueType
    assert typeof(IAsyncStateMachine).IsAssignableFrom(stateMachineType)
    assert stateMachineType.GetCustomAttribute<CompilerGeneratedAttribute>() != null
    assert method.GetCustomAttribute<DebuggerStepThroughAttribute>() != null
}

test "a synchronously completed await keeps the ValueTask fast path" {
    iterations := 10000
    for i := 0; i < 1000; i++ {
        NextValue(i).GetAwaiter().GetResult()
        TouchValue().GetAwaiter().GetResult()
        NextTask(i).GetAwaiter().GetResult()
    }

    before := GC.GetAllocatedBytesForCurrentThread()
    for i := 0; i < iterations; i++ {
        NextValue(i).GetAwaiter().GetResult()
        TouchValue().GetAwaiter().GetResult()
    }
    valueTaskBytes := GC.GetAllocatedBytesForCurrentThread() - before

    before = GC.GetAllocatedBytesForCurrentThread()
    for i := 0; i < iterations; i++ {
        NextTask(i).GetAwaiter().GetResult()
    }
    taskBytes := GC.GetAllocatedBytesForCurrentThread() - before

    // Fewer bytes than calls means no call allocated (the smallest object is 24 bytes); the Task
    // control shows the counter does see a per-call allocation when there is one.
    assert valueTaskBytes < iterations, "ValueTask async calls allocated " + valueTaskBytes.ToString() + " bytes"
    assert taskBytes >= iterations * 24, "Task async calls allocated only " + taskBytes.ToString() + " bytes"
}
