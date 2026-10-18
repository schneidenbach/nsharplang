namespace NSharpLang.AsyncBareReturn.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks

// A BARE `return` IN A UNIT `async` FUNCTION COMPLETES THE TASK (issue #227). It is legal whether the
// unit-ness is implicit (`async func f()`) or written (`: Task` / `: ValueTask`), exactly as in C#:
// the task completes with no value and the body is left, running every enclosing `finally`.

func NewLog(): List<string> {
    return new List<string>()
}

async func BeforeAwait(log: List<string>, x: int): Task {
    if x == 0 {
        return
    }
    await Task.Delay(1)
    log.Add("after " + x.ToString())
}

async func AfterAwait(log: List<string>, x: int): Task {
    await Task.Delay(1)
    if x == 0 {
        return
    }
    log.Add("after " + x.ToString())
}

async func InLoop(log: List<string>, stop: int): Task {
    for i := 0; i < 10; i++ {
        await Task.Delay(1)
        if i == stop {
            return
        }
        log.Add("i" + i.ToString())
    }
    log.Add("loop done")
}

async func InTryFinally(log: List<string>, x: int): Task {
    try {
        await Task.Delay(1)
        if x == 0 {
            return
        }
        log.Add("body")
    } finally {
        log.Add("finally")
    }
    log.Add("tail")
}

async func InNestedTry(log: List<string>): Task {
    await Task.Delay(1)
    try {
        try {
            return
        } finally {
            log.Add("inner")
        }
    } finally {
        log.Add("outer")
    }
}

async func InCatch(log: List<string>, x: int): Task {
    try {
        await Task.Delay(1)
        if x == 0 {
            throw new InvalidOperationException("boom")
        }
        log.Add("no throw")
    } catch error: InvalidOperationException {
        log.Add("caught")
        return
    } finally {
        log.Add("finally")
    }
    log.Add("tail")
}

async func InLock(log: List<string>, gate: object, x: int): Task {
    await Task.Delay(1)
    lock gate {
        if x == 0 {
            return
        }
        log.Add("locked")
    }
    log.Add("tail")
}

async func InUsing(log: List<string>, x: int): Task {
    await Task.Delay(1)
    using resource := new Releaser(log) {
        if x == 0 {
            return
        }
        log.Add("used")
    }
    log.Add("tail")
}

class Releaser: IDisposable {
    Log: List<string>

    constructor(log: List<string>) {
        Log = log
    }

    func Dispose() {
        Log.Add("disposed")
    }
}

async func ValueTaskReturn(log: List<string>, x: int): ValueTask {
    if x == 0 {
        return
    }
    await Task.Delay(1)
    log.Add("vt " + x.ToString())
}

async func ImplicitUnit(log: List<string>, x: int) {
    if x == 0 {
        return
    }
    await Task.Delay(1)
    log.Add("implicit " + x.ToString())
}

class Worker {
    Log: List<string>

    async func Run(x: int): Task {
        if x == 0 {
            return
        }
        await Task.Delay(1)
        Log.Add("method " + x.ToString())
    }

    static async func RunStatic(log: List<string>, x: int): Task {
        if x == 0 {
            return
        }
        await Task.Delay(1)
        log.Add("static " + x.ToString())
    }
}

async func WithLocalFunction(log: List<string>, x: int): Task {
    async func inner(y: int): Task {
        if y == 0 {
            return
        }
        await Task.Delay(1)
        log.Add("local " + y.ToString())
    }
    await inner(x)
    log.Add("outer " + x.ToString())
}

test "a bare return before the first await completes the task without running the rest" {
    log := NewLog()
    BeforeAwait(log, 0).Wait()
    assert log.Count == 0
    BeforeAwait(log, 1).Wait()
    assert log.Count == 1 && log[0] == "after 1"
}

test "a bare return after an await completes the task" {
    log := NewLog()
    AfterAwait(log, 0).Wait()
    assert log.Count == 0
    AfterAwait(log, 2).Wait()
    assert log[0] == "after 2"
}

test "a bare return inside a loop leaves the loop and the function" {
    log := NewLog()
    InLoop(log, 2).Wait()
    assert string.Join(",", log) == "i0,i1"
    log2 := NewLog()
    InLoop(log2, 99).Wait()
    assert log2[log2.Count - 1] == "loop done"
}

test "a bare return inside try runs the finally and skips the rest" {
    log := NewLog()
    InTryFinally(log, 0).Wait()
    assert string.Join(",", log) == "finally"
    log2 := NewLog()
    InTryFinally(log2, 1).Wait()
    assert string.Join(",", log2) == "body,finally,tail"
}

test "a bare return through nested finally blocks runs them inside out" {
    log := NewLog()
    InNestedTry(log).Wait()
    assert string.Join(",", log) == "inner,outer"
}

test "a task returned by a bare return is completed, not faulted" {
    task := BeforeAwait(NewLog(), 0)
    task.Wait()
    assert task.IsCompleted && !task.IsFaulted
}

test "a bare return in a ValueTask function completes it" {
    log := NewLog()
    ValueTaskReturn(log, 0).AsTask().Wait()
    assert log.Count == 0
    ValueTaskReturn(log, 1).AsTask().Wait()
    assert log[0] == "vt 1"
}

test "a bare return in an unannotated unit async function still works" {
    log := NewLog()
    ImplicitUnit(log, 0).AsTask().Wait()
    assert log.Count == 0
    ImplicitUnit(log, 3).AsTask().Wait()
    assert log[0] == "implicit 3"
}

test "a bare return in async instance and static methods completes the task" {
    worker := new Worker()
    worker.Log = NewLog()
    worker.Run(0).Wait()
    assert worker.Log.Count == 0
    worker.Run(1).Wait()
    assert worker.Log[0] == "method 1"
    log := NewLog()
    Worker.RunStatic(log, 0).Wait()
    assert log.Count == 0
    Worker.RunStatic(log, 1).Wait()
    assert log[0] == "static 1"
}

test "a bare return in an async local function leaves only that function" {
    log := NewLog()
    WithLocalFunction(log, 0).Wait()
    assert string.Join(",", log) == "outer 0"
}

test "a bare return in an async lambda completes its task" {
    log := NewLog()
    run: Func<int, Task> = async x => {
        if x == 0 {
            return
        }
        await Task.Delay(1)
        log.Add("lambda " + x.ToString())
    }
    run(0).Wait()
    assert log.Count == 0
    run(4).Wait()
    assert log[0] == "lambda 4"
}

test "a bare return inside a catch handler completes the task after the finally" {
    log := NewLog()
    InCatch(log, 0).Wait()
    assert string.Join(",", log) == "caught,finally"
    log2 := NewLog()
    InCatch(log2, 1).Wait()
    assert string.Join(",", log2) == "no throw,finally,tail"
}

test "a bare return inside a lock leaves the lock and completes the task" {
    log := NewLog()
    gate := new object()
    InLock(log, gate, 0).Wait()
    assert log.Count == 0
    InLock(log, gate, 1).Wait()
    assert string.Join(",", log) == "locked,tail"
}

test "a bare return inside a using block disposes the resource" {
    log := NewLog()
    InUsing(log, 0).Wait()
    assert string.Join(",", log) == "disposed"
    log2 := NewLog()
    InUsing(log2, 1).Wait()
    assert string.Join(",", log2) == "used,disposed,tail"
}
