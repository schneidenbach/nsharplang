namespace NSharpLang.AsyncIteratorCancellation.Tests

import System
import System.Reflection
import System.Runtime.CompilerServices
import System.Threading
import NSharpLang.AsyncIteratorCancellationFixture

func RequiredCancellationIteratorMethod(name: string): MethodInfo {
    flags := BindingFlags.Public | BindingFlags.Static
    for owner in typeof(CancellationIteratorOwner).Assembly.GetTypes() {
        candidate := owner.GetMethod(name, flags)
        if candidate != null {
            return candidate
        }
    }
    throw new InvalidOperationException("The async iterator method '" + name + "' was not emitted.")
}

test "consumer cancellation reaches the sole iterator token" {
    consumer := new CancellationTokenSource()
    enumerator := Wait(CancellationToken.None).GetAsyncEnumerator(consumer.Token)
    pending := enumerator.MoveNextAsync()
    assert !pending.IsCompleted
    consumer.Cancel()
    cancelled := false
    try {
        _ignored := await pending
    } catch ex: OperationCanceledException {
        cancelled = true
    } finally {
        await enumerator.DisposeAsync()
    }
    assert cancelled
}

test "consumer cancellation reaches a member iterator token" {
    owner := new CancellationIteratorOwner()
    consumer := new CancellationTokenSource()
    enumerator := owner.WaitMember(CancellationToken.None).GetAsyncEnumerator(consumer.Token)
    pending := enumerator.MoveNextAsync()
    assert !pending.IsCompleted
    consumer.Cancel()
    cancelled := false
    try {
        _ignored := await pending
    } catch ex: OperationCanceledException {
        cancelled = true
    } finally {
        await enumerator.DisposeAsync()
    }
    assert cancelled
}

test "the iterator argument token remains effective without a consumer token" {
    argument := new CancellationTokenSource()
    enumerator := Wait(argument.Token).GetAsyncEnumerator(CancellationToken.None)
    pending := enumerator.MoveNextAsync()
    assert !pending.IsCompleted
    argument.Cancel()
    cancelled := false
    try {
        _ignored := await pending
    } catch ex: OperationCanceledException {
        cancelled = true
    } finally {
        await enumerator.DisposeAsync()
    }
    assert cancelled
}

test "both linked tokens can cancel the same async iterator" {
    argument := new CancellationTokenSource()
    consumer := new CancellationTokenSource()
    enumerator := Wait(argument.Token).GetAsyncEnumerator(consumer.Token)
    pending := enumerator.MoveNextAsync()
    assert !pending.IsCompleted
    argument.Cancel()
    argumentCancelled := false
    try {
        _ignored := await pending
    } catch ex: OperationCanceledException {
        argumentCancelled = true
    } finally {
        await enumerator.DisposeAsync()
    }
    assert argumentCancelled

    secondArgument := new CancellationTokenSource()
    secondConsumer := new CancellationTokenSource()
    secondEnumerator := Wait(secondArgument.Token).GetAsyncEnumerator(secondConsumer.Token)
    secondPending := secondEnumerator.MoveNextAsync()
    assert !secondPending.IsCompleted
    secondConsumer.Cancel()
    consumerCancelled := false
    try {
        _ignored := await secondPending
    } catch ex: OperationCanceledException {
        consumerCancelled = true
    } finally {
        await secondEnumerator.DisposeAsync()
    }
    assert consumerCancelled
}

test "default tokens pass through and the iterator completes normally" {
    neither := Observe(CancellationToken.None).GetAsyncEnumerator(CancellationToken.None)
    assert await neither.MoveNextAsync()
    assert !neither.Current
    assert !await neither.MoveNextAsync()
    await neither.DisposeAsync()

    consumer := new CancellationTokenSource()
    consumerOnly := Observe(CancellationToken.None).GetAsyncEnumerator(consumer.Token)
    assert await consumerOnly.MoveNextAsync()
    assert consumerOnly.Current
    await consumerOnly.DisposeAsync()

    argument := new CancellationTokenSource()
    argumentOnly := Observe(argument.Token).GetAsyncEnumerator(CancellationToken.None)
    assert await argumentOnly.MoveNextAsync()
    assert argumentOnly.Current
    await argumentOnly.DisposeAsync()
}

test "the marked token alone receives consumer cancellation when several are present" {
    unrelated := new CancellationTokenSource()
    consumer := new CancellationTokenSource()
    enumerator := WaitSelected(unrelated.Token, CancellationToken.None).GetAsyncEnumerator(consumer.Token)
    pending := enumerator.MoveNextAsync()
    assert !pending.IsCompleted
    unrelated.Cancel()
    assert !pending.IsCompleted
    consumer.Cancel()
    cancelled := false
    try {
        _ignored := await pending
    } catch ex: OperationCanceledException {
        cancelled = true
    } finally {
        await enumerator.DisposeAsync()
    }
    assert cancelled
}

test "DisposeAsync releases the linked cancellation source" {
    argument := new CancellationTokenSource()
    consumer := new CancellationTokenSource()
    enumerator := Wait(argument.Token).GetAsyncEnumerator(consumer.Token)
    boxedEnumerator: object = enumerator
    combinedSourceField := boxedEnumerator.GetType().GetField("<>__combinedTokens")
    assert combinedSourceField != null
    combinedSource := combinedSourceField.GetValue(enumerator) as CancellationTokenSource
    assert combinedSource != null

    await enumerator.DisposeAsync()
    assert combinedSourceField.GetValue(enumerator) == null
    disposed := false
    try {
        _token := combinedSource.Token
    } catch ex: ObjectDisposedException {
        disposed = true
    }
    assert disposed
}

test "a top-level async iterator automatically carries the BCL metadata marker" {
    method := RequiredCancellationIteratorMethod("Wait")
    assert method != null
    parameters := method.GetParameters()
    assert parameters.Length == 1
    assert parameters[0].GetCustomAttributes(typeof(EnumeratorCancellationAttribute), false).Length == 1
}

test "an instance async iterator automatically carries the BCL metadata marker" {
    method := typeof(CancellationIteratorOwner).GetMethod("WaitMember")
    assert method != null
    parameters := method.GetParameters()
    assert parameters.Length == 1
    assert parameters[0].GetCustomAttributes(typeof(EnumeratorCancellationAttribute), false).Length == 1
}

test "an explicitly selected BCL marker is emitted once" {
    method := RequiredCancellationIteratorMethod("WaitSelected")
    assert method != null
    parameters := method.GetParameters()
    assert parameters.Length == 2
    assert parameters[0].GetCustomAttributes(typeof(EnumeratorCancellationAttribute), false).Length == 0
    assert parameters[1].GetCustomAttributes(typeof(EnumeratorCancellationAttribute), false).Length == 1
}
