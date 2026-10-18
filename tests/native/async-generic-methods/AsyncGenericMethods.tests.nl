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

// A generic type's own parameter and a method's parameter in one signature.
class Box<T> {
    Item: T

    constructor(item: T) {
        Item = item
    }

    func GetValue(): T => Item

    // Declared and compiled; calling a generic method on a closed generic user type is a separate
    // limit of the emitter (`Specified method is not supported`), not an async one.
    async func Map<U>(f: Func<T, U>): U {
        await Task.Delay(1)
        return f(Item)
    }

    async func Get(): T {
        await Task.Delay(1)
        return Item
    }

}

// Open result shapes: an array and a generic type over the parameter.
class Shapes {
    static async func Twice<T>(value: T): T[] {
        await Task.Delay(1)
        arr := new T[](2)
        arr[0] = value
        arr[1] = value
        return arr
    }

    static async func Boxed<T>(box: Box<T>): Box<T> {
        await Task.Delay(1)
        return box
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

test "a generic type's async method returns the type's own parameter" {
    box := new Box<int>(21)
    assert box.Get().Result == 21
}

test "an async generic method returns an array of T" {
    arr := Shapes.Twice("t").Result
    assert arr.Length == 2 && arr[1] == "t"
}

test "an async generic method returns Box of T" {
    method := typeof(Shapes).GetMethod("Boxed")
    assert method != null
    methodArguments := new Type[](1)
    methodArguments[0] = typeof(int)
    closedMethod := method.MakeGenericMethod(methodArguments)
    arguments := new object?[](1)
    arguments[0] = new Box<int>(9)
    result := (Task<Box<int>>)closedMethod.Invoke(null, arguments)
    assert result.Result.GetValue() == 9
}
