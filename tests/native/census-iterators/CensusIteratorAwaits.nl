namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic
import System.Threading.Tasks


// AN `await` WHOSE RESULT IS BOUND, INSIDE AN ASYNC GENERATOR.
//
// A suspension point marks a resume label and branches out of `MoveNextAsync`'s step core, and ECMA
// requires an empty evaluation stack at that branch. A bound await stores its result directly in the
// declaration, assignment or yield. Nested expression awaits are supported when the planner can spill
// earlier operands into iterator fields; unsupported expression shapes still decline explicitly.
//
// WHICH awaitable is awaited is not a list this compiler keeps: the operand's own type is asked for
// `GetAwaiter()`, and that awaiter for `IsCompleted`, `OnCompleted(Action)` and `GetResult()` — the
// same four members C# asks for. A `Task`, a `Task<T>`, a `ValueTask<T>` and a user-written awaitable
// all answer.

// A bound await of a `Task<T>`: the awaiter is `TaskAwaiter<T>` and its `GetResult()` is the value.
async func* BoundAwait(): IAsyncEnumerable<int> {
    v := await Task.FromResult(4)
    yield v
    yield v * 2
}

// A unit await of a `Task`: the awaiter is `TaskAwaiter` and its `GetResult()` is void.
async func* DelayThenYield(): IAsyncEnumerable<int> {
    await Task.Delay(1)
    yield 1
    await Task.Delay(1)
    yield 2
}

// The awaited value AS the yielded element.
async func* AwaitedYield(): IAsyncEnumerable<string> {
    yield await Task.FromResult("a")
    yield await Task.FromResult("b")
}

// A `ValueTask<T>` — a different awaitable with a different awaiter, resolved the same way.
async func* AwaitedValueTask(): IAsyncEnumerable<int> {
    v := await new ValueTask<int>(11)
    yield v
}

// Nested awaits spill values onto the iterator machine and preserve left-to-right evaluation.
async func* AwaitedBinaryExpression(first: Task<int>, second: Task<int>): IAsyncEnumerable<int> {
    yield (await first) + (await second)
}

// An awaited value ASSIGNED to a binding that already exists, and converted to its type on the way in.
async func* AwaitedAssignment(): IAsyncEnumerable<long> {
    total: long = 0
    total = await Task.FromResult(5)
    yield total
    total = await Task.FromResult(6)
    yield total
}

// A SEQUENCE SOURCE ENUMERATED BY AN ASYNC GENERATOR. The hoisted enumerator lives across every
// suspension the loop body performs; the async step core's catch releases it on the exceptional path
// and `DisposeAsync` releases it when a consumer stops part-way.
async func* DoubledAsync(items: IEnumerable<int>): IAsyncEnumerable<int> {
    for v in items {
        await Task.Delay(1)
        yield v * 2
    }
}

// A generator whose sequence source is abandoned by its consumer: the enumerator it hoisted is live
// at the suspension, and the machine has to release it.
async func* TaggedAsync(items: List<string>): IAsyncEnumerable<string> {
    prefix := await Task.FromResult("+")
    for v in items {
        yield prefix + v
    }
}
