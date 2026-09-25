namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Collections
import System.Collections.Generic

class SourceCollectionIdentityKey {
    Id: int

    constructor(id: int) {
        Id = id
    }
}

class SourceCollectionIdentityPair {
    FirstKey: string
    FirstValue: SourceCollectionIdentityKey
    SecondKey: string
    SecondValue: SourceCollectionIdentityKey

    constructor(
        firstKey: string,
        firstValue: SourceCollectionIdentityKey,
        secondKey: string,
        secondValue: SourceCollectionIdentityKey
    ) {
        FirstKey = firstKey
        FirstValue = firstValue
        SecondKey = secondKey
        SecondValue = secondValue
    }
}

class SourceCollectionIdentityEmitFacts {
    static func DictionaryIdentity(
        first: SourceCollectionIdentityKey,
        second: SourceCollectionIdentityKey
    ): bool {
        values := new Dictionary<SourceCollectionIdentityKey, int>()
        values[first] = 31
        values[second] = 37
        return values.get_Count() == 2 && values[first] == 31 && values[second] == 37
    }

    static func HashSetIdentity(
        first: SourceCollectionIdentityKey,
        second: SourceCollectionIdentityKey
    ): bool {
        values := new HashSet<SourceCollectionIdentityKey>()
        firstAdded := values.Add(first)
        secondAdded := values.Add(second)
        repeatedAdded := values.Add(first)
        return firstAdded && secondAdded && !repeatedAdded && values.get_Count() == 2 && values.Contains(first) && values.Contains(second)
    }

    static func FirstValue(
        values: IEnumerable<SourceCollectionIdentityKey>
    ): SourceCollectionIdentityKey {
        enumerator := values.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            if movement.MoveNext() {
                return enumerator.get_Current()
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        throw new InvalidOperationException("The value view was empty.")
    }

    static func FirstTwoEntries(
        values: Dictionary<string, SourceCollectionIdentityKey>
    ): SourceCollectionIdentityPair {
        enumerator := values.GetEnumerator()
        pair: SourceCollectionIdentityPair = null
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had no first entry.")
            }
            first := enumerator.get_Current()

            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had no second entry.")
            }
            second := enumerator.get_Current()

            if enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had an unexpected third entry.")
            }
            pair = new SourceCollectionIdentityPair(
                first.get_Key(),
                first.get_Value(),
                second.get_Key(),
                second.get_Value()
            )
        } finally {
            enumerator.Dispose()
        }
        if pair == null {
            throw new InvalidOperationException("The dictionary did not produce two entries.")
        }
        return pair
    }

    static func AdvanceEntryAfterAdding(
        values: Dictionary<string, SourceCollectionIdentityKey>
    ): bool {
        enumerator := values.GetEnumerator()
        advanced := false
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The dictionary had no initial entry.")
            }
            first := enumerator.get_Current()
            if first.get_Value() == null {
                throw new InvalidOperationException("The dictionary entry had a null value.")
            }
            values["late"] = new SourceCollectionIdentityKey(73)
            advanced = enumerator.MoveNext()
        } finally {
            enumerator.Dispose()
        }
        return advanced
    }
}

test "source reference keys retain Dictionary and HashSet identity semantics" {
    first := new SourceCollectionIdentityKey(5)
    second := new SourceCollectionIdentityKey(5)
    assert SourceCollectionIdentityEmitFacts.DictionaryIdentity(first, second)
    assert SourceCollectionIdentityEmitFacts.HashSetIdentity(first, second)
}

test "a Dictionary Values view flows directly to generic enumeration with source value identity" {
    values := new Dictionary<string, SourceCollectionIdentityKey>()
    liveView := values.get_Values()
    first := new SourceCollectionIdentityKey(11)
    values["first"] = first
    selected := SourceCollectionIdentityEmitFacts.FirstValue(liveView)
    selectedObject: object = selected
    firstObject: object = first
    assert Object.ReferenceEquals(selectedObject, firstObject)
}

test "the concrete Dictionary entry enumerator advances once in insertion order and invalidates on mutation" {
    values := new Dictionary<string, SourceCollectionIdentityKey>()
    first := new SourceCollectionIdentityKey(17)
    second := new SourceCollectionIdentityKey(23)
    values["first"] = first
    values["second"] = second

    pair := SourceCollectionIdentityEmitFacts.FirstTwoEntries(values)
    pairFirst: object = pair.FirstValue
    pairSecond: object = pair.SecondValue
    firstObject: object = first
    secondObject: object = second
    assert pair.FirstKey == "first"
    assert pair.SecondKey == "second"
    assert Object.ReferenceEquals(pairFirst, firstObject)
    assert Object.ReferenceEquals(pairSecond, secondObject)

    assert throws InvalidOperationException {
        SourceCollectionIdentityEmitFacts.AdvanceEntryAfterAdding(values)
    }
    assert values.get_Count() == 3
}
