namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections.Generic


// The local in each helper is the exact mutable BCL
// Dictionary<TKey, TValue>.KeyCollection.Enumerator returned by Keys.GetEnumerator(). Keeping that
// struct in one local preserves its position and Dictionary version across MoveNext, Current, and
// Dispose; no interface conversion or copied iterator participates.
class DictionaryKeyEnumeratorEmitFactsPair {
    First: string
    Second: string

    constructor(first: string, second: string) {
        First = first
        Second = second
    }
}

class DictionaryKeyEnumeratorEmitFactsRow {
    Id: int

    constructor(id: int) {
        Id = id
    }
}

class DictionaryKeyEnumeratorEmitFacts {
    static func First(
        values: Dictionary<string, DictionaryKeyEnumeratorEmitFactsRow>
    ): string {
        enumerator := values.get_Keys().GetEnumerator()
        selected: string = null
        try {
            while enumerator.MoveNext() {
                selected = enumerator.get_Current()
                break
            }
        } finally {
            enumerator.Dispose()
        }
        if selected == null {
            throw new InvalidOperationException("The dictionary had no first key.")
        }
        return selected
    }

    static func FirstTwo(
        values: Dictionary<string, DictionaryKeyEnumeratorEmitFactsRow>
    ): DictionaryKeyEnumeratorEmitFactsPair {
        enumerator := values.get_Keys().GetEnumerator()
        pair: DictionaryKeyEnumeratorEmitFactsPair = null
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had no first key.")
            }
            first := enumerator.get_Current()

            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had no second key.")
            }
            second := enumerator.get_Current()

            if enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had an unexpected third key.")
            }
            pair = new DictionaryKeyEnumeratorEmitFactsPair(first, second)
        } finally {
            enumerator.Dispose()
        }
        if pair == null {
            throw new InvalidOperationException("The dictionary did not produce two keys.")
        }
        return pair
    }

    static func AdvanceAfterAdding(
        values: Dictionary<string, DictionaryKeyEnumeratorEmitFactsRow>
    ): bool {
        enumerator := values.get_Keys().GetEnumerator()
        advanced := false
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had no initial key.")
            }
            if enumerator.get_Current() != "first" {
                throw new InvalidOperationException("The dictionary enumerator returned the wrong first key.")
            }

            values["late"] = new DictionaryKeyEnumeratorEmitFactsRow(73)
            advanced = enumerator.MoveNext()
        } finally {
            enumerator.Dispose()
        }
        return advanced
    }
}

test "Dictionary Keys concrete enumerator retains first key and insertion order" {
    values := new Dictionary<string, DictionaryKeyEnumeratorEmitFactsRow>()
    values["first"] = new DictionaryKeyEnumeratorEmitFactsRow(41)
    values["second"] = new DictionaryKeyEnumeratorEmitFactsRow(59)

    assert DictionaryKeyEnumeratorEmitFacts.First(values) == "first"
    pair := DictionaryKeyEnumeratorEmitFacts.FirstTwo(values)
    assert pair.First == "first"
    assert pair.Second == "second"
}

test "Dictionary Keys concrete enumerator preserves BCL add-version failure through cleanup" {
    values := new Dictionary<string, DictionaryKeyEnumeratorEmitFactsRow>()
    values["first"] = new DictionaryKeyEnumeratorEmitFactsRow(11)
    values["second"] = new DictionaryKeyEnumeratorEmitFactsRow(13)

    assert throws InvalidOperationException {
        DictionaryKeyEnumeratorEmitFacts.AdvanceAfterAdding(values)
    }
    assert values.get_Count() == 3
}
