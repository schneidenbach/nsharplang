namespace NSharpLang.GenericInstanceIterators.Tests

import System.Collections.Generic
import NSharpLang.GenericInstanceIteratorFixtures

test "a generic class iterator captures this, parameters, and locals lazily across yields" {
    shelf := new GenericShelf<int>(3, "shelf")
    values := new List<int>()
    values.Add(2)
    values.Add(4)
    sequence := shelf.Stream(values)
    assert shelf.Events.Count == 0

    shelf.UpdateSeed(10)
    values.Add(6)
    enumerator := sequence.GetEnumerator()
    assert enumerator.MoveNext()
    assert enumerator.Current == 10
    shelf.UpdateSeed(11)
    assert enumerator.MoveNext()
    assert enumerator.Current == 11
    assert enumerator.MoveNext()
    assert enumerator.Current == 2
    assert enumerator.MoveNext()
    assert enumerator.Current == 10
    assert enumerator.MoveNext()
    assert enumerator.Current == 6
    assert !enumerator.MoveNext()
    assert shelf.Events.Count == 2
    assert shelf.Events[0] == "started"
    assert shelf.Events[1] == "closed"
}

test "a generic class iterator can be enumerated again with a fresh machine" {
    shelf := new GenericShelf<int>(5, "shelf")
    values := new List<int>()
    values.Add(7)
    sequence := shelf.Stream(values)

    first := 0
    for value in sequence {
        first = first * 10 + value
    }
    shelf.UpdateSeed(8)
    second := 0
    for value in sequence {
        second = second * 10 + value
    }

    assert first == 557
    assert second == 887
    assert shelf.Events.Count == 4
}

test "a generic class and generic method contribute both machine parameters" {
    shelf := new GenericShelf<int>(3, "x")
    sequence := shelf.Echo<string>("go", 2)
    boxedSequence: object = sequence
    arguments := boxedSequence.GetType().GetGenericArguments()
    assert arguments.Length == 2
    assert arguments[0] == typeof(int)
    assert arguments[1] == typeof(string)

    text := ""
    for value in sequence {
        text = text + value
    }
    assert text == "gogo"
}

test "a generic instance method on a non-generic class captures its method parameter" {
    cursor := new PlainCursor("cursor")
    sequence := cursor.Repeat<int>(12, 3)
    boxedSequence: object = sequence
    arguments := boxedSequence.GetType().GetGenericArguments()
    assert arguments.Length == 1
    assert arguments[0] == typeof(int)

    total := 0
    for value in sequence {
        total = total + value
    }
    assert total == 36
}

test "a generic struct iterator captures a copy of its receiver" {
    slot := new GenericSlot<int>(4)
    sequence := slot.Once()
    slot.UpdateValue(9)

    total := 0
    for value in sequence {
        total = total + value
    }
    assert total == 4
}

test "early break disposes a generic instance iterator and runs its finally" {
    shelf := new GenericShelf<int>(1, "shelf")
    values := new List<int>()
    values.Add(2)
    values.Add(3)
    for value in shelf.Stream(values) {
        assert value == 1
        break
    }
    assert shelf.Events.Count == 2
    assert shelf.Events[0] == "started"
    assert shelf.Events[1] == "closed"
}

test "a referenced assembly exposes generic instance iterator methods to consumers" {
    shelf := new CrossShelf<int>(6)
    values := new List<int>()
    values.Add(7)
    values.Add(8)
    sequence: IEnumerable<int> = shelf.Values(values)
    enumerator := sequence.GetEnumerator()
    total := 0
    while enumerator.MoveNext() {
        total = total * 10 + enumerator.Current
    }
    enumerator.Dispose()
    assert total == 678

    cursor := new CrossCursor()
    genericSequence: IEnumerable<string> = cursor.Repeat<string>("x", 2)
    joined := ""
    for value in genericSequence {
        joined = joined + value
    }
    assert joined == "xx"
}
