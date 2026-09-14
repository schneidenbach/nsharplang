namespace NSharpLang.CensusLambdaInference.Tests

import System.Collections.Generic
import System.Threading.Tasks

test "`Task.Run` with a task-returning lambda answers the task's own result type, not a nested task" {
    // `NestedTaskRun` is DECLARED to return `Task<int>`, so the overload that answers `Task<Task<int>>`
    // cannot compile it at all — and the value it really hands back is a `Task<int>`, not the unwrap
    // promise's own concrete class, which is what `IsAssignableFrom` asks and `==` could not.
    task := NestedTaskRun()
    assert typeof(Task<int>).IsAssignableFrom(task.GetType())
    assert AwaitedNestedTaskRun() == 11
}

test "`Task.Run` with a value-returning lambda keeps the value" {
    task := ValueTaskRun()
    assert typeof(Task<int>).IsAssignableFrom(task.GetType())
    assert AwaitedValueTaskRun() == 11
}

test "an `async` lambda's result survives the same way" {
    task := AsyncValueTaskRun()
    assert typeof(Task<int>).IsAssignableFrom(task.GetType())
    assert AwaitedAsyncValueTaskRun() == 11
}

test "a unit-task lambda takes the overload it exactly matches, and a statement body takes `Action`" {
    unit := UnitTaskRun()
    unit.Wait()
    assert unit.IsCompleted

    sink := new List<int>()
    ran := ActionTaskRun(sink)
    ran.Wait()
    assert sink.Count == 1
    assert sink[0] == 7
}
