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

public async func UnitWork(): Task {
    await Task.Delay(1)
}

public async func CountedWork(): Task<int> {
    await Task.Delay(1)
    return 41
}

public async func UnitValueWork(): ValueTask {
    await Task.Delay(1)
}

public async func CountedValueWork(): ValueTask<int> {
    await Task.Delay(1)
    return 42
}

public async func* CountUp(): IAsyncEnumerable<int> {
    yield 1
    await Task.Delay(1)
    yield 2
}

// The slice-36 census shape: an `await foreach` inside an async function returning the bare `Task`.
public async func DrainAll(): Task {
    total := 0
    await foreach value in CountUp() {
        total = total + value
    }

    if total != 3 {
        throw new InvalidOperationException(
            "The async iterator drained to " + total.ToString() + " instead of 3.")
    }
}

public async func SumCounted(): Task<int> {
    total := 0
    await foreach value in CountUp() {
        total = total + value
    }
    return total
}
