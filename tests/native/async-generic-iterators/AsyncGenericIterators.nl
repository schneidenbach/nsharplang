namespace NSharpLang.AsyncGenericIterators.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks

func ImmediateValue(events: List<int>, value: int): Task<int> {
    events.Add(value)
    return Task.FromResult(value)
}

func JoinValues(left: int, right: int): int {
    return left * 10 + right
}

class IteratorAwaitTarget {
    Events: List<int>

    constructor(events: List<int>) {
        Events = events
        Events.Add(0)
    }

    func Combine(value: int): int {
        Events.Add(2)
        return value + 10
    }
}

func CreateAwaitTarget(events: List<int>): IteratorAwaitTarget {
    events.Add(-1)
    return new IteratorAwaitTarget(events)
}

func ImmediateGate(events: List<int>, gate: object): Task<object> {
    events.Add(9)
    return Task.FromResult(gate)
}

async func* NestedAwaitArguments(events: List<int>): IAsyncEnumerable<int> {
    yield JoinValues(await ImmediateValue(events, 1), await ImmediateValue(events, 2))
}

async func* AwaitInstanceReceiver(events: List<int>): IAsyncEnumerable<int> {
    yield CreateAwaitTarget(events).Combine(await ImmediateValue(events, 1))
}

async func* NestedAwaitConditionAndBinary(events: List<int>): IAsyncEnumerable<int> {
    if 0 < await ImmediateValue(events, 3) {
        yield 5 + await ImmediateValue(events, 4)
    }
}

async func* NestedAwaitInterpolation(events: List<int>): IAsyncEnumerable<string> {
    yield $"{await ImmediateValue(events, 5)}:{await ImmediateValue(events, 6)}"
}

async func* LockWithoutSuspension(gate: object, events: List<int>): IAsyncEnumerable<int> {
    await Task.Delay(1)
    lock gate {
        events.Add(1)
    }
    yield events.Count
}

async func* LockOnAwaitedExpression(gate: object, events: List<int>): IAsyncEnumerable<int> {
    lock await ImmediateGate(events, gate) {
        events.Add(10)
    }
    yield events.Count
}

async func* AwaitFinallyWithCatch(events: List<int>): IAsyncEnumerable<int> {
    value := 0
    try {
        throw new InvalidOperationException()
    } catch ex: InvalidOperationException {
        value = 11
        events.Add(1)
    } finally {
        events.Add(2)
        await Task.Delay(1)
        events.Add(3)
    }
    yield value
}

async func* CatchWithAwait(events: List<int>): IAsyncEnumerable<int> {
    value := 0
    try {
        events.Add(6)
        throw new InvalidOperationException()
    } catch ex: InvalidOperationException {
        value = await ImmediateValue(events, 7)
        events.Add(8)
    }
    yield value
}

async func OrdinaryCatchAwait(): Task<int> {
    try {
        throw new InvalidOperationException()
    } catch ex: InvalidOperationException {
        return await Task.FromResult(12)
    }
}

async func* LocalPending<T>(value: T): IAsyncEnumerable<T> {
    await Task.Delay(1)
    yield value
    await Task.Delay(1)
    yield value
}

class GenericAsyncShelf<T> {
    Seed: T
    Label: string

    constructor(seed: T, label: string) {
        Seed = seed
        Label = label
    }

    async func* Values(): IAsyncEnumerable<T> {
        local := Seed
        await Task.Delay(1)
        yield local
        await Task.Delay(1)
        yield Seed
    }

    async func* Echo<U>(value: U): IAsyncEnumerable<U> {
        label := Label
        await Task.Delay(1)
        if label.Length > 0 {
            yield value
            await Task.Delay(1)
            yield value
        }
    }
}
