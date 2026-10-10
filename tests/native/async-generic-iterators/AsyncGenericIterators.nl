namespace NSharpLang.AsyncGenericIterators.Tests

import System.Collections.Generic
import System.Threading.Tasks

async func* LocalPending<T>(value: T): IAsyncEnumerable<T> {
    await Task.Delay(1)
    yield value
    await Task.Delay(1)
    yield value
}

class GenericAsyncShelf<T> {
    Seed: T
    Label: string

    constructor(seed: T, label: string) {
        Seed = seed
        Label = label
    }

    async func* Values(): IAsyncEnumerable<T> {
        local := Seed
        await Task.Delay(1)
        yield local
        await Task.Delay(1)
        yield Seed
    }

    async func* Echo<U>(value: U): IAsyncEnumerable<U> {
        label := Label
        await Task.Delay(1)
        if label.Length > 0 {
            yield value
            await Task.Delay(1)
            yield value
        }
    }
}
