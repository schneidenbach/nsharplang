namespace NSharpLang.AsyncGenericMethods.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks

// A GENERIC `async` METHOD (issue #237). `async func Read<T>(): T` returns `Task<T>` (or the project's
// async family) with `T` carried on the method, exactly as in C#.

class Reader {
    Prefix: string

    static async func Echo<T>(value: T): T {
        await Task.Delay(1)
        return value
    }

    // A `T` local that lives across an await.
    static async func Twice<T>(value: T): List<T> {
        held := value
        await Task.Delay(1)
        list := new List<T>()
        list.Add(held)
        list.Add(value)
        return list
    }

    async func Tag<T>(value: T): string {
        await Task.Delay(1)
        return Prefix + ":" + value.ToString()
    }

    static async func Default<T>(): T {
        await Task.Delay(1)
        return default
    }

    static async func NonNull<T>(value: T?): T where T : class {
        await Task.Delay(1)
        return must value
    }

    // An explicitly written task type.
    static async func Boxed<T>(value: T): Task<T> {
        await Task.Delay(1)
        return value
    }

    static async func Fails<T>(): T {
        await Task.Delay(1)
        throw new InvalidOperationException("boom")
    }

    // A generic unit async method.
    static async func Touch<T>(sink: List<T>, value: T): Task {
        await Task.Delay(1)
        sink.Add(value)
    }
}

test "a static generic async method returns the awaited value, type argument inferred" {
    assert Reader.Echo(7).Result == 7
    assert Reader.Echo("seven").Result == "seven"
}

test "a static generic async method accepts written type arguments" {
    assert Reader.Echo<long>(5).Result == 5L
    assert Reader.Echo<string>("x").Result == "x"
}

test "the returned task is a Task of the type argument" {
    task: Task<int> = Reader.Echo<int>(3)
    assert task.Result == 3
}

test "a T local held across an await keeps its value" {
    list := Reader.Twice("a").Result
    assert list.Count == 2 && list[0] == "a" && list[1] == "a"
}

test "an instance generic async method sees the instance" {
    reader := new Reader()
    reader.Prefix = "p"
    assert reader.Tag(42).Result == "p:42"
    assert reader.Tag<string>("s").Result == "p:s"
}

test "a default of T works inside a generic async method" {
    assert Reader.Default<int>().Result == 0
    assert Reader.Default<string>().Result == null
}

test "a constrained generic async method keeps its constraint" {
    assert Reader.NonNull("kept").Result == "kept"
    assert Reader.NonNull<string>("x").Result == "x"
}

test "an explicit Task of T return on a generic async method works" {
    assert Reader.Boxed(11).Result == 11
}

test "an exception in a generic async method faults the task" {
    task := Reader.Fails<int>()
    faulted := false
    try {
        task.Wait()
    } catch error: AggregateException {
        faulted = error.InnerException is InvalidOperationException
    }
    assert faulted
}

test "a generic unit async method completes and has its effect" {
    sink := new List<int>()
    Reader.Touch(sink, 8).Wait()
    assert sink.Count == 1 && sink[0] == 8
}

test "a generic async method can be awaited from an async caller" {
    caller: Func<Task<int>> = async () => {
        a := await Reader.Echo(1)
        b := await Reader.Echo(2)
        return a + b
    }
    assert caller().Result == 3
}
