namespace NSharpLang.AsyncMemberIterators.Tests

import System.Collections.Generic
import System.Threading
import NSharpLang.AsyncIteratorFixtures

test "async instance iterator is lazy and captures its receiver, parameter, and local" {
    shelf := new LocalAsyncShelf(3)
    sequence := shelf.Values(2)
    assert shelf.Events.Count == 0

    shelf.UpdateSeed(4)
    values := new List<int>()
    await foreach value in sequence {
        values.Add(value)
        if values.Count == 1 {
            shelf.UpdateSeed(5)
        }
    }

    assert values.Count == 2
    assert values[0] == 8
    assert values[1] == 10
    assert shelf.Events.Count == 1
    assert shelf.Events[0] == "started"
}

test "two async member enumerators and repeated passes have independent state" {
    shelf := new LocalAsyncShelf(2)
    sequence := shelf.Values(3)
    first := sequence.GetAsyncEnumerator(CancellationToken.None)
    second := sequence.GetAsyncEnumerator(CancellationToken.None)
    try {
        assert await first.MoveNextAsync()
        assert await second.MoveNextAsync()
        assert first.Current == 6
        assert second.Current == 6
        shelf.UpdateSeed(4)
        assert await first.MoveNextAsync()
        assert await second.MoveNextAsync()
        assert first.Current == 12
        assert second.Current == 12
    } finally {
        await first.DisposeAsync()
        await second.DisposeAsync()
    }

    joined := 0
    await foreach value in sequence {
        joined = joined * 100 + value
    }
    assert joined == 1212
}

test "breaking await foreach asynchronously disposes the iterator and runs its finally" {
    shelf := new LocalAsyncShelf(0)
    count := 0
    await foreach value in shelf.Protected(5) {
        count = count + 1
        break
    }

    assert count == 1
    assert shelf.Events.Count == 1
    assert shelf.Events[0] == "closed"
}

test "an async instance iterator from a referenced assembly preserves laziness and disposal" {
    shelf := new CrossAsyncShelf<int>(7)
    sequence := shelf.Stream<string>("cross")
    assert shelf.Events.Count == 0

    values := new List<string>()
    await foreach value in sequence {
        values.Add(value)
        if values.Count == 1 {
            break
        }
    }

    assert values.Count == 1
    assert values[0] == "cross"
    assert shelf.Events.Count == 2
    assert shelf.Events[0] == "started"
    assert shelf.Events[1] == "closed"
}
