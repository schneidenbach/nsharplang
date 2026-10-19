namespace NSharpLang.AsyncGenericMethodsDefault.Tests

import System
import System.Collections.Generic
import System.Text.Json
import System.Threading.Tasks

// GENERIC ASYNC METHODS UNDER THE DEFAULT CONFIGURATION (issue #237). The project default family is
// `ValueTask`, so `async func Read<T>(): T` returns `ValueTask<T>` — a generic struct instantiated over
// a method type parameter. Builder-bound generic instantiations cannot be queried with ordinary member
// reflection before the type is baked.

class Reader {
    static async func Read<T>(value: T): T {
        await Task.Delay(1)
        return value
    }

    async func ReadInstance<T>(value: T): T {
        await Task.Delay(1)
        return value
    }

    static async func Explicit<T>(value: T): ValueTask<T> {
        await Task.Delay(1)
        return value
    }

    static async func ExplicitTask<T>(value: T): Task<T> {
        await Task.Delay(1)
        return value
    }

    static async func Repeated<T>(value: T): T[] {
        await Task.Delay(1)
        values := new T[](2)
        values[0] = value
        values[1] = value
        return values
    }

    static async func Pair<T>(pair: (T, int)): (T, int) {
        await Task.Delay(1)
        return pair
    }

    static async func BoxedValue<T>(box: Box<T>): Box<T> {
        await Task.Delay(1)
        return box
    }

    static async func Unit<T>(sink: List<T>, value: T): ValueTask {
        await Task.Delay(1)
        sink.Add(value)
    }

    static async func Fails<T>(): T {
        await Task.Delay(1)
        throw new InvalidOperationException("boom")
    }

    // A generic async method awaiting another one.
    static async func Chained<T>(value: T): T {
        first := await Read(value)
        return await Explicit(first)
    }
}

class JsonReader {
    static async func Read<T>(text: string): T {
        await Task.Delay(1)
        return must JsonSerializer.Deserialize<T>(text, new JsonSerializerOptions())
    }
}

// Both parameter owners participate in the signature: `T` belongs to Box and `U` to Map.
class Box<T> {
    Item: T

    constructor(item: T) {
        Item = item
    }

    func Get(): T => Item

    async func Map<U>(f: Func<T, U>): U {
        await Task.Delay(1)
        return f(Item)
    }
}

test "an unannotated generic async method returns a ValueTask of T" {
    task: ValueTask<int> = Reader.Read<int>(4)
    assert task.AsTask().Result == 4
    assert Reader.Read("s").AsTask().Result == "s"
}

test "the generic JSON Read example works with the default ValueTask and Result" {
    assert JsonReader.Read<int>("5").Result == 5
    assert JsonReader.Read<string>("\"x\"").Result == "x"
}

test "an instance generic async method returns a ValueTask of T" {
    reader := new Reader()
    assert reader.ReadInstance(5).AsTask().Result == 5
}

test "an explicit ValueTask of T over a method type parameter works" {
    assert Reader.Explicit(6).AsTask().Result == 6
    assert Reader.Explicit<string>("v").AsTask().Result == "v"
}

test "a generic ValueTask result can be an array of T" {
    values := Reader.Repeated(5).AsTask().Result
    assert values.Length == 2 && values[0] == 5 && values[1] == 5, "ValueTask<T[]> result"
}

test "a generic ValueTask result can be a tuple containing T" {
    pairInput := new ValueTuple<string, int>("pair", 2)
    pair: ValueTuple<string, int> = Reader.Pair<string>(pairInput).AsTask().Result
    assert pair.Item1 == "pair" && pair.Item2 == 2, "ValueTask<(T, int)> result"
}

test "a generic ValueTask result can be Box of T" {
    method := typeof(Reader).GetMethod("BoxedValue")
    assert method != null
    methodArguments := new Type[](1)
    methodArguments[0] = typeof(int)
    closedMethod := method.MakeGenericMethod(methodArguments)
    box := new Box<int>(14)
    arguments := new object?[](1)
    arguments[0] = box
    result := (ValueTask<Box<int>>)closedMethod.Invoke(null, arguments)
    assert result.AsTask().Result.Get() == 14
}

test "a generic async method combines its declaring type and method parameters" {
    box := new Box<int>(21)
    mapDefinition := box.GetType().GetMethod("Map")
    assert mapDefinition != null
    methodArguments := new Type[](1)
    methodArguments[0] = typeof(string)
    map := mapDefinition.MakeGenericMethod(methodArguments)
    mapper: Func<int, string> = value => value.ToString()
    arguments := new object?[](1)
    arguments[0] = mapper
    mapped: ValueTask<string> = (ValueTask<string>)map.Invoke(box, arguments)
    assert mapped.AsTask().Result == "21"
}

test "an explicit Task of T keeps its family under the ValueTask default" {
    task: Task<int> = Reader.ExplicitTask(8)
    assert task.Result == 8
}

test "an explicit unit ValueTask on a generic method completes" {
    sink := new List<int>()
    Reader.Unit(sink, 3).AsTask().Wait()
    assert sink.Count == 1 && sink[0] == 3
}

test "an exception faults the ValueTask of T" {
    task := Reader.Fails<int>().AsTask()
    faulted := false
    try {
        task.Wait()
    } catch error: AggregateException {
        faulted = error.InnerException is InvalidOperationException
    }
    assert faulted
}

test "generic async methods await each other across both task families" {
    assert Reader.Chained(11).AsTask().Result == 11
}
