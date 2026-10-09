namespace NSharpLang.GenericInstanceIteratorFixtures

import System.Collections.Generic

class CrossShelf<T> {
    Seed: T

    constructor(seed: T) {
        Seed = seed
    }

    func* Values(values: List<T>): IEnumerable<T> {
        local := Seed
        yield local
        for value in values {
            yield value
        }
    }
}

class CrossCursor {
    func* Repeat<U>(value: U, count: int): IEnumerable<U> {
        index := 0
        while index < count {
            yield value
            index = index + 1
        }
    }
}
