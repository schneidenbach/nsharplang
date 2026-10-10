namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections.Generic


// This fixture uses the exact value-collection path that the entry-point fallback needs.  It
// deliberately does not replace Values with an enumerable interface, a copied list, or a custom
// iterator: the local below is the closed BCL Dictionary<TKey,TValue>.ValueCollection.Enumerator
// value returned by Values.GetEnumerator().
class DictionaryValueEnumeratorEmitFactsRow {
    Id: int

    constructor(id: int) {
        Id = id
    }
}

class DictionaryValueEnumeratorEmitFactsPair {
    First: DictionaryValueEnumeratorEmitFactsRow
    Second: DictionaryValueEnumeratorEmitFactsRow

    constructor(
        first: DictionaryValueEnumeratorEmitFactsRow,
        second: DictionaryValueEnumeratorEmitFactsRow
    ) {
        First = first
        Second = second
    }
}

class DictionaryValueEnumeratorEmitFacts {
    static func First(
        values: Dictionary<string, DictionaryValueEnumeratorEmitFactsRow>
    ): DictionaryValueEnumeratorEmitFactsRow {
        enumerator := values.get_Values().GetEnumerator()
        selected: DictionaryValueEnumeratorEmitFactsRow = null
        try {
            while enumerator.MoveNext() {
                selected = enumerator.get_Current()
                break
            }
        } finally {
            enumerator.Dispose()
        }
        if selected == null {
            throw new InvalidOperationException("The dictionary had no first value.")
        }
        return selected
    }

    static func AdvanceAfterAdding(
        values: Dictionary<string, DictionaryValueEnumeratorEmitFactsRow>
    ): bool {
        enumerator := values.get_Values().GetEnumerator()
        advanced := false
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had no initial value.")
            }

            current := enumerator.get_Current()
            if current == null {
                throw new InvalidOperationException("The dictionary enumerator returned null.")
            }

            // Dictionary.Remove/Clear need not invalidate a current enumerator.  Adding a fresh
            // key is the BCL operation that makes the next MoveNext observe the version change.
            values["late"] = new DictionaryValueEnumeratorEmitFactsRow(73)
            advanced = enumerator.MoveNext()
        } finally {
            enumerator.Dispose()
        }
        return advanced
    }

    static func FirstTwo(
        values: Dictionary<string, DictionaryValueEnumeratorEmitFactsRow>
    ): DictionaryValueEnumeratorEmitFactsPair {
        enumerator := values.get_Values().GetEnumerator()
        pair: DictionaryValueEnumeratorEmitFactsPair = null
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had no first value.")
            }
            first := enumerator.get_Current()

            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had no second value.")
            }
            second := enumerator.get_Current()

            if enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had an unexpected third value.")
            }
            pair = new DictionaryValueEnumeratorEmitFactsPair(first, second)
        } finally {
            enumerator.Dispose()
        }
        if pair == null {
            throw new InvalidOperationException("The dictionary did not produce two values.")
        }
        return pair
    }
}

test "Dictionary Values concrete enumerator retains first-value identity and insertion order" {
    values := new Dictionary<string, DictionaryValueEnumeratorEmitFactsRow>()
    first := new DictionaryValueEnumeratorEmitFactsRow(41)
    second := new DictionaryValueEnumeratorEmitFactsRow(59)
    values["first"] = first
    values["second"] = second

    selected := DictionaryValueEnumeratorEmitFacts.First(values)
    firstObject: object = first
    selectedObject: object = selected
    assert Object.ReferenceEquals(firstObject, selectedObject)
    assert selected.Id == 41
}

test "Dictionary Values concrete enumerator advances one mutable struct receiver in insertion order" {
    values := new Dictionary<string, DictionaryValueEnumeratorEmitFactsRow>()
    first := new DictionaryValueEnumeratorEmitFactsRow(17)
    second := new DictionaryValueEnumeratorEmitFactsRow(23)
    values["first"] = first
    values["second"] = second

    pair := DictionaryValueEnumeratorEmitFacts.FirstTwo(values)
    firstObject: object = first
    secondObject: object = second
    selectedFirst: object = pair.First
    selectedSecond: object = pair.Second
    assert Object.ReferenceEquals(selectedFirst, firstObject)
    assert Object.ReferenceEquals(selectedSecond, secondObject)
    assert pair.First.Id == 17
    assert pair.Second.Id == 23
}

test "Dictionary Values concrete enumerator preserves the BCL mutation failure through cleanup" {
    values := new Dictionary<string, DictionaryValueEnumeratorEmitFactsRow>()
    values["first"] = new DictionaryValueEnumeratorEmitFactsRow(11)
    values["second"] = new DictionaryValueEnumeratorEmitFactsRow(13)

    assert throws InvalidOperationException {
        DictionaryValueEnumeratorEmitFacts.AdvanceAfterAdding(values)
    }
    assert values.get_Count() == 3
}
