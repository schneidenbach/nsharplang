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
    private continuation: Action?
    private completed: bool
    TaskSource: Task<int>?
    Result: int

    constructor() {
        continuation = null
        completed = false
        TaskSource = null
        Result = 0
    }

    constructor(source: Task<int>) {
        continuation = null
        completed = false
        TaskSource = source
        Result = 0
    }

    func Register(registered: Action) {
        continuation = registered
    }

    func Complete(result: int) {
        Result = result
        completed = true
        registered := continuation
        if registered != null {
            registered()
        }
    }

    IsCompleted: bool {
        get {
            if TaskSource != null {
                return TaskSource.IsCompleted
            }
            return completed
        }
    }
}

class ReflectedGenericExtensionAwaiter<T>: INotifyCompletion {
    Source: ReflectedGenericExtensionBox<T>

    constructor(source: ReflectedGenericExtensionBox<T>) {
        Source = source
    }

    IsCompleted: bool {
        get { return Source.IsCompleted }
    }

    func GetResult(): int {
        if Source.TaskSource != null {
            return Source.TaskSource.GetAwaiter().GetResult()
        }
        return Source.Result
    }

    func OnCompleted(continuation: Action) {
        if Source.TaskSource != null {
            Source.TaskSource.GetAwaiter().OnCompleted(continuation)
            return
        }
        Source.Register(continuation)
    }

}

func GetAwaiter<T>(this value: ReflectedGenericExtensionBox<T>): ReflectedGenericExtensionAwaiter<T> {
    return new ReflectedGenericExtensionAwaiter<T>(value)
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
