namespace NSharpLang.AsyncMemberIterators.Tests

import System.Collections.Generic
import System.Threading.Tasks

class LocalAsyncShelf {
    Seed: int
    Events: List<string>

    constructor(seed: int) {
        Seed = seed
        Events = new List<string>()
    }

    func UpdateSeed(value: int) {
        Seed = value
    }

    async func* Values(multiplier: int): IAsyncEnumerable<int> {
        Events.Add("started")
        local := Seed * multiplier
        await Task.Delay(1)
        yield local
        await Task.Delay(1)
        yield Seed * multiplier
    }

    async func* Protected(count: int): IAsyncEnumerable<int> {
        try {
            i := 0
            while i < count {
                await Task.Delay(1)
                yield i
                i = i + 1
            }
        } finally {
            await Task.Delay(1)
            Events.Add("closed")
        }
    }
}
