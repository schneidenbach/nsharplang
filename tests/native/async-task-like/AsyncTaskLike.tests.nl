namespace NSharpLang.AsyncTaskLike.Tests

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
