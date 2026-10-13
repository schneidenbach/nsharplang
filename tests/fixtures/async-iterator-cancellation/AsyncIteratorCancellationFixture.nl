namespace NSharpLang.AsyncIteratorCancellationFixture

import System.Collections.Generic
import System.Runtime.CompilerServices
import System.Threading
import System.Threading.Tasks

class CancellationIteratorOwner {
    Value: int = 0

    async func* WaitMember(token: CancellationToken): IAsyncEnumerable<int> {
        await Task.Delay(Timeout.Infinite, token)
        yield Value
    }
}

async func* Wait(token: CancellationToken): IAsyncEnumerable<int> {
    await Task.Delay(Timeout.Infinite, token)
    yield 1
}

async func* Observe(token: CancellationToken): IAsyncEnumerable<bool> {
    await Task.Delay(1)
    yield token.CanBeCanceled
}

async func* WaitSelected(_unrelated: CancellationToken, [EnumeratorCancellation] selected: CancellationToken): IAsyncEnumerable<int> {
    await Task.Delay(Timeout.Infinite, selected)
    yield 1
}
