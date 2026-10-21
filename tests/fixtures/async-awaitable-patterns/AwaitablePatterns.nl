namespace NSharpLang.AsyncAwaitablePatternFixtures

import System
import System.Runtime.CompilerServices
import System.Threading.Tasks

class ReflectedCompletionBase: INotifyCompletion {
    Source: Task<int>

    constructor(source: Task<int>) {
        Source = source
    }

    func OnCompleted(continuation: Action) {
        Source.GetAwaiter().OnCompleted(continuation)
    }
}

class ReflectedInheritedAwaiter: ReflectedCompletionBase {
    constructor(source: Task<int>): base(source) {}

    IsCompleted: bool {
        get { return Source.IsCompleted }
    }

    func GetResult(): int {
        return Source.GetAwaiter().GetResult()
    }
}

class ReflectedInheritedAwaitable {
    Source: Task<int>

    constructor(source: Task<int>) {
        Source = source
    }

    func GetAwaiter(): ReflectedInheritedAwaiter {
        return new ReflectedInheritedAwaiter(Source)
    }
}

class ReflectedGenericExtensionBox<T> {
    Source: Task<int>

    constructor(source: Task<int>) {
        Source = source
    }
}

class ReflectedGenericExtensionAwaiter: INotifyCompletion {
    Source: Task<int>

    constructor(source: Task<int>) {
        Source = source
    }

    IsCompleted: bool {
        get { return Source.IsCompleted }
    }

    func GetResult(): int {
        return Source.GetAwaiter().GetResult()
    }

    func OnCompleted(continuation: Action) {
        Source.GetAwaiter().OnCompleted(continuation)
    }

}

func GetAwaiter<T>(this value: ReflectedGenericExtensionBox<T>): ReflectedGenericExtensionAwaiter {
    return new ReflectedGenericExtensionAwaiter(value.Source)
}

class ReflectedDecoyAwaiterBase {
    func GetResult<T>(): int {
        return -1
    }
}

class ReflectedDecoyAwaiter: ReflectedDecoyAwaiterBase, INotifyCompletion {
    Source: Task<int>

    constructor(source: Task<int>) {
        Source = source
    }

    IsCompleted: bool {
        get { return Source.IsCompleted }
    }

    func GetResult(): int {
        return Source.GetAwaiter().GetResult()
    }

    func OnCompleted(_continuation: object) {}

    func OnCompleted(_continuation: Action) {}

    func INotifyCompletion.OnCompleted(continuation: Action) {
        Source.GetAwaiter().OnCompleted(continuation)
    }
}

class ReflectedDecoyAwaitable {
    Source: Task<int>

    constructor(source: Task<int>) {
        Source = source
    }

    func GetAwaiter(): ReflectedDecoyAwaiter {
        return new ReflectedDecoyAwaiter(Source)
    }
}
