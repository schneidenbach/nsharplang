namespace NSharpLang.AsyncTaskLike.Tests

import System

// Every test touches a MEMBER of an async call result — the exact move that used to crash
// `nlc check` for the bare-`Task` family before the task-identity fix.
test "an async unit Task call result is a value whose members resolve and run" {
    work := UnitWork()
    work.Wait()
    assert work.IsCompleted
}

test "an async Task of int call result carries its awaited result" {
    assert CountedWork().Result == 41
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

    assert AwaitCustom(7) == 7
    assert AwaitCustom(0) == 0
}

test "`GetAwaiter()` written out works on a generic task, not only on a unit one" {
    assert AwaitedSynchronously() == 41
    assert AwaiterThroughALocal() == 11
    assert UnitAwaitedSynchronously()
}

// If async functions ever suspend, these two fail, and `language.pooledAsync` (refused by
// `ProjectFileParser` because there is nothing to pool) becomes a real question again.
test "an async ValueTask function has completed by the time it returns, even across a delay" {
    pending := SlowValue()
    assert pending.IsCompleted
    assert pending.Result == 5
}

test "an async ValueTask function allocates nothing per call, unlike a Task one" {
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
