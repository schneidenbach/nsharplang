namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections.Generic

class ListEnumeratorEmitFactsRow {
    Id: int

    constructor(id: int) {
        Id = id
    }
}

class ListEnumeratorEmitFactsPair {
    First: ListEnumeratorEmitFactsRow
    Second: ListEnumeratorEmitFactsRow

    constructor(
        first: ListEnumeratorEmitFactsRow,
        second: ListEnumeratorEmitFactsRow
    ) {
        First = first
        Second = second
    }
}

class ListEnumeratorEmitFacts {

    // Keep the concrete List<T>.Enumerator unboxed. The early return must leave through the finally
    // handler so the same mutable receiver is disposed before its selected element escapes.
    static func First(
        values: List<ListEnumeratorEmitFactsRow>
    ): ListEnumeratorEmitFactsRow {
        enumerator := values.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                return enumerator.get_Current()
            }
        } finally {
            enumerator.Dispose()
        }
        throw new InvalidOperationException("The list had no first value.")
    }

    static func AdvanceAfterAdding(
        values: List<ListEnumeratorEmitFactsRow>
    ): bool {
        enumerator := values.GetEnumerator()
        advanced := false
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The list had no initial value.")
            }

            current := enumerator.get_Current()
            if current == null {
                throw new InvalidOperationException("The list enumerator returned null.")
            }

            values.Add(new ListEnumeratorEmitFactsRow(73))
            advanced = enumerator.MoveNext()
        } finally {
            enumerator.Dispose()
        }
        return advanced
    }

    static func FirstTwo(
        values: List<ListEnumeratorEmitFactsRow>
    ): ListEnumeratorEmitFactsPair {
        enumerator := values.GetEnumerator()
        pair: ListEnumeratorEmitFactsPair = null
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The list had no first value.")
            }
            first := enumerator.get_Current()

            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The list had no second value.")
            }
            second := enumerator.get_Current()

            if enumerator.MoveNext() {
                throw new InvalidOperationException("The list had an unexpected third value.")
            }
            pair = new ListEnumeratorEmitFactsPair(first, second)
        } finally {
            enumerator.Dispose()
        }
        if pair == null {
            throw new InvalidOperationException("The list did not produce two values.")
        }
        return pair
    }
}

test "List concrete enumerator preserves first identity through an early return and finally" {
    values := new List<ListEnumeratorEmitFactsRow>()
    first := new ListEnumeratorEmitFactsRow(41)
    values.Add(first)
    values.Add(new ListEnumeratorEmitFactsRow(59))

    selected := ListEnumeratorEmitFacts.First(values)
    firstObject: object = first
    selectedObject: object = selected
    assert Object.ReferenceEquals(firstObject, selectedObject)
    assert selected.Id == 41
}

test "List concrete enumerator advances one mutable struct receiver in insertion order" {
    values := new List<ListEnumeratorEmitFactsRow>()
    first := new ListEnumeratorEmitFactsRow(17)
    second := new ListEnumeratorEmitFactsRow(23)
    values.Add(first)
    values.Add(second)

    pair := ListEnumeratorEmitFacts.FirstTwo(values)
    firstObject: object = first
    secondObject: object = second
    selectedFirst: object = pair.First
    selectedSecond: object = pair.Second
    assert Object.ReferenceEquals(selectedFirst, firstObject)
    assert Object.ReferenceEquals(selectedSecond, secondObject)
    assert pair.First.Id == 17
    assert pair.Second.Id == 23
}

test "List concrete enumerator preserves mutation invalidation through finally" {
    values := new List<ListEnumeratorEmitFactsRow>()
    values.Add(new ListEnumeratorEmitFactsRow(11))
    values.Add(new ListEnumeratorEmitFactsRow(13))

    assert throws InvalidOperationException {
        ListEnumeratorEmitFacts.AdvanceAfterAdding(values)
    }
    assert values.get_Count() == 3
}
