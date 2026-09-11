namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks

// The existing iterator binding controls inspect the T-only VAR/MVAR map. This paired runtime
// control proves two actual closed generic machines enumerate independently. The matching T[]
// capture is an emitted baseline decline below: its field type cannot be resolved in a generic
// iterator machine, so this file does not pretend its array element/body surface is admitted.
func* IteratorRealizationGenericValue<T>(value: T): IEnumerable<T> {
    yield value
}

// The two async shapes differ only after the shared first awaited yield. The completed twin proves
// the regular completion tail remains admitted; the faulting shape exposes actual prior consumer
// progress before its second await routes the exception to the caller.
async func* IteratorRealizationCompletedAfterAwait(): IAsyncEnumerable<int> {
    await Task.Delay(1)
    yield 7
    await Task.Delay(1)
    yield 8
}

async func* IteratorRealizationFaultAfterAwait(): IAsyncEnumerable<int> {
    await Task.Delay(1)
    yield 7
    await Task.Delay(1)
    throw new InvalidOperationException("Iterator realization fault")
}

class IteratorRealizationProgress {
    Value: int

    constructor() {
        Value = 0
    }
}

async func IteratorRealizationConsumeCompleted(progress: IteratorRealizationProgress): Task<int> {
    await foreach value in IteratorRealizationCompletedAfterAwait() {
        progress.Value = progress.Value * 10 + value
    }

    return progress.Value
}

async func IteratorRealizationConsumeFault(progress: IteratorRealizationProgress): Task<int> {
    await foreach value in IteratorRealizationFaultAfterAwait() {
        progress.Value = progress.Value * 10 + value
    }

    return progress.Value
}

test "a generic iterator realizes T while the paired T array capture reaches its exact emitter decline" {
    intSequence := IteratorRealizationGenericValue(1)
    intPattern := 0
    for value in intSequence {
        intPattern = intPattern * 10 + value
    }
    assert intPattern == 1

    stringSequence := IteratorRealizationGenericValue("alpha")
    joined := ""
    for value in stringSequence {
        joined = joined + "|" + value
    }
    assert joined == "|alpha"

    genericArraySource := "import System.Collections.Generic\n\nfunc* IteratorRealizationUnsupportedTArray<T>(value: T, _tail: T[]): IEnumerable<T> {\n    yield value\n}\n"
    outcome := IteratorBindingEmitOutcome(genericArraySource)
    assert outcome == "emit.iterator.field-type|iterator hoisted field type 'T[]' could not be resolved for 'IteratorRealizationUnsupportedTArray'|IteratorRealizationUnsupportedTArray"
}

test "an async iterator preserves earlier yielded progress before a post-await fault" {
    completed := new IteratorRealizationProgress()
    assert await IteratorRealizationConsumeCompleted(completed) == 78
    assert completed.Value == 78

    faulted := new IteratorRealizationProgress()
    caught := false
    try {
        _ = await IteratorRealizationConsumeFault(faulted)
    } catch error: InvalidOperationException {
        caught = true
        _ = error
    }
    assert caught
    assert faulted.Value == 7
}
