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

async func* AwaitCatchAndFinallyNormal(events: List<int>): IAsyncEnumerable<int> {
    result := 0
    try {
        events.Add(1)
        _ignored := await ImmediateValue(events, 2)
        result = 3
        events.Add(4)
    } catch ex: InvalidOperationException {
        events.Add(5)
        _ignored := await ImmediateValue(events, 6)
    } finally {
        events.Add(7)
        _ignored := await ImmediateValue(events, 8)
        events.Add(9)
    }
    yield result
}

async func* AwaitCatchAndFinallyCaught(events: List<int>): IAsyncEnumerable<int> {
    result := 0
    try {
        events.Add(11)
        throw new InvalidOperationException()
    } catch ex: InvalidOperationException {
        events.Add(12)
        result = await ImmediateValue(events, 13)
        events.Add(14)
    } finally {
        events.Add(15)
        _ignored := await ImmediateValue(events, 16)
        events.Add(17)
    }
    yield result
}

async func* AwaitCatchAndFinallyRethrown(events: List<int>): IAsyncEnumerable<int> {
    try {
        events.Add(21)
        throw new InvalidOperationException()
    } catch ex: InvalidOperationException {
        events.Add(22)
        _ignored := await ImmediateValue(events, 23)
        events.Add(24)
        throw
    } finally {
        events.Add(25)
        _ignored := await ImmediateValue(events, 26)
        events.Add(27)
    }
}

async func* AwaitCatchAndFinallyYieldBreak(events: List<int>): IAsyncEnumerable<int> {
    try {
        events.Add(31)
        throw new InvalidOperationException()
    } catch ex: InvalidOperationException {
        events.Add(32)
        _ignored := await ImmediateValue(events, 33)
        events.Add(34)
        yield break
    } finally {
        events.Add(35)
        _ignored := await ImmediateValue(events, 36)
        events.Add(37)
    }
    yield 38
}

async func* AwaitCatchAndFinallyNested(events: List<int>): IAsyncEnumerable<int> {
    result := 0
    try {
        try {
            events.Add(41)
            throw new InvalidOperationException()
        } catch inner: InvalidOperationException {
            events.Add(42)
            result = await ImmediateValue(events, 43)
            events.Add(44)
        } finally {
            events.Add(45)
            _ignored := await ImmediateValue(events, 46)
            events.Add(47)
        }
        events.Add(48)
    } catch outer: InvalidOperationException {
        events.Add(49)
        _ignored := await ImmediateValue(events, 50)
        events.Add(51)
    } finally {
        events.Add(52)
        _ignored := await ImmediateValue(events, 53)
        events.Add(54)
    }
    yield result
}

async func* AwaitCatchAndFinallyEarlyDispose(events: List<int>): IAsyncEnumerable<int> {
    try {
        try {
            events.Add(61)
            throw new InvalidOperationException()
        } catch ex: InvalidOperationException {
            events.Add(63)
            _ignored := await ImmediateValue(events, 64)
            events.Add(65)
        } finally {
            events.Add(66)
            _ignored := await ImmediateValue(events, 67)
            events.Add(68)
        }
        events.Add(69)
        yield 70
        events.Add(71)
    } finally {
        events.Add(72)
        _ignored := await ImmediateValue(events, 73)
        events.Add(74)
    }
}

async func* AwaitCatchAndFinallyWhilePending(events: List<int>, gate: TaskCompletionSource<bool>): IAsyncEnumerable<int> {
    try {
        events.Add(75)
        await gate.Task
        events.Add(76)
    } catch ex: InvalidOperationException {
        events.Add(77)
        _ignored := await ImmediateValue(events, 78)
    } finally {
        events.Add(79)
        _ignored := await ImmediateValue(events, 80)
        events.Add(81)
    }
    yield 82
}

async func OrdinaryCatchAwait(): Task<int> {
    try {
        throw new InvalidOperationException()
    } catch ex: InvalidOperationException {
        return await Task.FromResult(12)
    }
}

async func OrdinaryAwaitCatchAndFinally(events: List<int>, shouldThrow: bool): Task<int> {
    result := 0
    try {
        events.Add(71)
        if shouldThrow {
            throw new InvalidOperationException()
        }
        result = await ImmediateValue(events, 72)
        events.Add(73)
    } catch ex: InvalidOperationException {
        events.Add(74)
        result = await ImmediateValue(events, 75)
        events.Add(76)
    } finally {
        events.Add(77)
        _ignored := await ImmediateValue(events, 78)
        events.Add(79)
    }
    return result
}

async func OrdinaryAwaitCatchAndFinallyRethrown(events: List<int>): Task {
    try {
        events.Add(81)
        throw new InvalidOperationException()
    } catch ex: InvalidOperationException {
        events.Add(82)
        _ignored := await ImmediateValue(events, 83)
        events.Add(84)
        throw
    } finally {
        events.Add(85)
        _ignored := await ImmediateValue(events, 86)
        events.Add(87)
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
