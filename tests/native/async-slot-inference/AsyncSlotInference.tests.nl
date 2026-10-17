namespace NSharpLang.AsyncSlotInference.Tests

import System
import System.IO
import System.Reflection
import System.Threading
import System.Threading.Tasks

// AN UNANNOTATED `async` MEMBER THAT FILLS A .NET SLOT TAKES THE SLOT'S TASK FAMILY.
//
// This project leaves `language.asyncDefaultType` unset, so a free `async func` returns `ValueTask`.
// Every member below that returns `Task` got it from the slot it fills — a referenced base class, a
// source interface, a source base — and the project only builds if the emitter agreed with the
// analyzer: a member wrapped in the wrong family takes no slot, and its declaration is refused. The
// asserts then read the emitted signatures and CALL through the slot. The ASP.NET shapes from issue
// #199 (`BackgroundService.ExecuteAsync`, middleware `InvokeAsync`) are compiled by
// `tests/native/async-default-type`, whose host can resolve the ASP.NET shared framework.

// A CoreLib base whose same-name overloads differ by arity: `FlushAsync()` and
// `FlushAsync(CancellationToken): Task`; the one-parameter slot is the one overridden.
class CountingStream: MemoryStream {
    Flushes: int

    override async func FlushAsync(_token: CancellationToken) {
        await Task.Delay(1)
        Flushes = Flushes + 1
    }
}

// A CoreLib interface: `IAsyncDisposable.DisposeAsync(): ValueTask`. The family matches the project
// default, and inference must not move it.
class Lease: IAsyncDisposable {
    Released: bool

    async func DisposeAsync() {
        await Task.Delay(1)
        Released = true
    }
}

interface IWorker {
    func RunAsync(seed: int): Task<int>
}

class Doubler: IWorker {
    async func RunAsync(seed: int): int {
        await Task.Delay(1)
        return seed * 2
    }
}

// An explicit implementation fills exactly the named interface's slot.
class Tripler: IWorker {
    async func IWorker.RunAsync(seed: int): int {
        await Task.Delay(1)
        return seed * 3
    }
}

class Greeter {
    virtual func GreetAsync(name: string): Task<string> {
        return Task.FromResult("hello " + name)
    }
}

// A source chain: the middle override infers `Task<string>` from `Greeter`, and the leaf infers it
// from the middle one, which wrote nothing at all.
class LoudGreeter: Greeter {
    override async func GreetAsync(name: string): string {
        await Task.Delay(1)
        return "HELLO " + name
    }
}

class LouderGreeter: LoudGreeter {
    override async func GreetAsync(name: string): string {
        await Task.Delay(1)
        return "HELLO " + name + "!"
    }
}

// Not a slot: the project default stands.
async func plainWork(): int {
    await Task.Delay(1)
    return 5
}

func ReturnTypeOf(owner: Type, name: string): Type {
    method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly)
    assert method != null, name
    return method.ReturnType
}

test "an override of a CoreLib Task slot is dispatched through the base type" {
    assert ReturnTypeOf(typeof(CountingStream), "FlushAsync") == typeof(Task)

    stream := new CountingStream()
    viaBase: Stream = stream
    viaBase.FlushAsync(CancellationToken.None).Wait()
    assert stream.Flushes == 1
}

test "a call on the derived type is typed with the inferred Task" {
    stream := new CountingStream()
    pending: Task = stream.FlushAsync(CancellationToken.None)
    pending.Wait()
    assert stream.Flushes == 1
}

test "a ValueTask interface slot keeps the ValueTask family" {
    assert ReturnTypeOf(typeof(Lease), "DisposeAsync") == typeof(ValueTask)

    lease := new Lease()
    disposable: IAsyncDisposable = lease
    disposable.DisposeAsync().AsTask().Wait()
    assert lease.Released
}

test "an implicit implementation of a source interface takes Task of T" {
    assert ReturnTypeOf(typeof(Doubler), "RunAsync") == typeof(Task<int>)

    worker: IWorker = new Doubler()
    assert worker.RunAsync(21).Result == 42

    direct: Task<int> = new Doubler().RunAsync(4)
    assert direct.Result == 8
}

test "an explicit implementation takes the named interface's Task of T" {
    worker: IWorker = new Tripler()
    assert worker.RunAsync(5).Result == 15
}

test "a chain of source overrides all take the family of the member at its root" {
    assert ReturnTypeOf(typeof(LoudGreeter), "GreetAsync") == typeof(Task<string>)
    assert ReturnTypeOf(typeof(LouderGreeter), "GreetAsync") == typeof(Task<string>)

    greeter: Greeter = new LouderGreeter()
    assert greeter.GreetAsync("n#").Result == "HELLO n#!"
}

test "a free async function still wraps in the project default" {
    pending: ValueTask<int> = plainWork()
    assert pending.AsTask().Result == 5
}
