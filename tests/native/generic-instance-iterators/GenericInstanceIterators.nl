namespace NSharpLang.GenericInstanceIterators.Tests

import System.Collections.Generic

class GenericShelf<T> {
    Seed: T
    Label: string
    Events: List<string>

    constructor(seed: T, label: string) {
        Seed = seed
        Label = label
        Events = new List<string>()
    }

    func UpdateSeed(value: T) {
        Seed = value
    }

    func* Stream(values: List<T>): IEnumerable<T> {
        Events.Add("started")
        local := Seed
        try {
            yield local
            yield Seed
            index := 0
            while index < values.Count {
                if index % 2 == 0 {
                    yield values[index]
                } else {
                    yield local
                }
                index = index + 1
            }
        } finally {
            Events.Add("closed")
        }
    }

    func* Echo<U>(value: U, count: int): IEnumerable<U> {
        label := Label
        index := 0
        while index < count {
            if label.Length > 0 {
                yield value
            } else {
                yield break
            }
            index = index + 1
        }
    }
}

class PlainCursor {
    Label: string

    constructor(label: string) {
        Label = label
    }

    func* Repeat<U>(value: U, count: int): IEnumerable<U> {
        local := value
        index := 0
        while index < count {
            if Label.Length > 0 {
                yield local
            } else {
                yield break
            }
            index = index + 1
        }
    }
}

struct GenericSlot<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    func UpdateValue(value: T) {
        Value = value
    }

    func* Once(): IEnumerable<T> {
        yield Value
    }
}
