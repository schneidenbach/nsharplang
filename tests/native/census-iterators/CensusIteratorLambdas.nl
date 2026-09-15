namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks


// A LAMBDA INSIDE A GENERATOR BODY.
//
// A generator has already hoisted every parameter and every local of its body into a field of its own
// state machine, so the machine IS the closure's display: a lambda becomes a private instance method
// ON the machine, and the delegate is built from the machine the body is already running on. Nothing
// is copied, and an instance generator's enclosing members reach the same way they reach from the
// body itself — through the receiver it captured.

// Captures a hoisted local and a captured parameter.
func* ScaledByCapture(n: int): IEnumerable<int> {
    factor := 3
    scale: Func<int, int> = x => x * factor + n
    yield scale(2)
    yield scale(5)
}

// The delegate leaves the machine entirely: a BCL call takes it and invokes it many times.
func* MatchesAtLeast(items: List<string>, minimum: int): IEnumerable<int> {
    longEnough: Predicate<string> = s => s.Length >= minimum
    matches := items.FindAll(longEnough)
    yield matches.Count
}

// An INSTANCE generator's lambda, reading the enclosing type through the captured receiver.
class CensusTally {
    Base: int

    constructor(baseValue: int) {
        Base = baseValue
    }

    func* Scaled(values: List<int>): IEnumerable<int> {
        shift: Func<int, int> = v => v + Base
        for v in values {
            yield shift(v)
        }
    }
}

func AsyncIteratorFailure(): int {
    throw new InvalidOperationException("generator async lambda failure")
}

func AsyncIdentity(value: int): int {
    return value
}

func AwaitedAsyncIteratorFailure(): Task<int> {
    return Task.FromException<int>(new InvalidOperationException("awaited generator async lambda failure"))
}

// Control for the disabled recursive-plan capability: outside an iterator the established async
// lambda emitter retains this same nested-await call shape.
func OrdinaryAsyncCallback(seed: int): Func<Task<int>> {
    return async () => AsyncIdentity(await Task.FromResult(seed))
}

// Async lambdas use the same state-machine object as their closure. Their synchronous body follows
// the language's current blocking-await model, while success and failure are returned through Task.
func* AsyncCallbacks(seed: int): IEnumerable<Func<Task<int>>> {
    captured := seed
    yield async () => captured + 1
    yield async () => await Task.FromResult(captured + 2)
    yield async () => AsyncIteratorFailure()
    yield async () => {
        value := await Task.FromResult(captured + 3)
        return value
    }
    yield async () => captured + await new ValueTask<int>(2)
    yield async () => AsyncIdentity(await Task.FromResult(captured))
    yield async () => await AwaitedAsyncIteratorFailure()
}

func* AsyncUnitCallbacks(log: List<string>): IEnumerable<Func<Task>> {
    yield async () => {
        await Task.Delay(1)
        log.Add("task")
    }
}

func* AsyncValueTaskCallbacks(seed: int): IEnumerable<Func<ValueTask<int>>> {
    yield async () => await new ValueTask<int>(seed + 3)
    yield async () => AsyncIteratorFailure()
}

func* AsyncUnitValueTaskCallbacks(log: List<string>): IEnumerable<Func<ValueTask>> {
    yield async () => {
        await new ValueTask(Task.Delay(1))
        log.Add("value task")
    }
}
