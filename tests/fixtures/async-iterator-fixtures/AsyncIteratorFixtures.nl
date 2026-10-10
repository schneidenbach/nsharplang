namespace NSharpLang.AsyncIteratorFixtures

import System.Collections.Generic
import System.Threading.Tasks

class CrossAsyncShelf<T> {
    Seed: T
    Events: List<string>

    constructor(seed: T) {
        Seed = seed
        Events = new List<string>()
    }

    func UpdateSeed(value: T) {
        Seed = value
    }

    async func* Stream<U>(value: U): IAsyncEnumerable<U> {
        Events.Add("started")
        local := value
        try {
            await Task.Delay(1)
            yield local
            await Task.Delay(1)
            yield value
        } finally {
            await Task.Delay(1)
            Events.Add("closed")
        }
    }

    async func* Values(): IAsyncEnumerable<T> {
        local := Seed
        await Task.Delay(1)
        yield local
        await Task.Delay(1)
        yield Seed
    }
}

async func* CrossPending<T>(value: T): IAsyncEnumerable<T> {
    await Task.Delay(1)
    yield value
    await Task.Delay(1)
    yield value
}
