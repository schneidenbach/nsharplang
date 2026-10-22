namespace NSharpLang.AsyncAwaitablePatternFixtures

import System
import System.Runtime.CompilerServices
import System.Threading.Tasks

class ReflectedLongBox {
    constructor(value: long) {
        if value != 1 {
            throw new Exception("constructor argument was not converted to long")
        }
    }
}

class ReflectedParamsBox {
    private values: int[]

    constructor(params values: int[]) {
        this.values = values
    }

    Count: int {
        get { return values.Length }
    }
}

class ReflectedConstructorShapes {
    private value: long
    private shape: int
    private marker: int

    constructor(value: int, label: string = "default") {
        this.value = value
        if label == "default" {
            this.shape = 1
        } else {
            this.shape = 2
        }
        this.marker = 0
    }

    constructor(value: long, marker: int) {
        this.value = value
        this.shape = 3
        this.marker = marker
    }

    func GetValue(): long {
        return value
    }

    func GetShape(): int {
        return shape
    }

    func GetMarker(): int {
        return marker
    }
}

class ReflectedOptionalExtensionBox {}

class ReflectedOptionalExtensionAwaiter: INotifyCompletion {
    IsCompleted: bool => true

    func GetResult(): int {
        return 81
    }

    func OnCompleted(continuation: Action) {
        continuation()
    }
}

func GetAwaiter(this _value: ReflectedOptionalExtensionBox? = null): ReflectedOptionalExtensionAwaiter {
    return new ReflectedOptionalExtensionAwaiter()
}

class ReflectedOptionalReceiverBase {}

class ReflectedOptionalReceiverDerived: ReflectedOptionalReceiverBase {}

func GetAwaiter(this _value: ReflectedOptionalReceiverBase): ReflectedOptionalExtensionAwaiter {
    return new ReflectedOptionalExtensionAwaiter()
}

func GetAwaiter(this _value: ReflectedOptionalReceiverDerived? = null): ReflectedOptionalExtensionAwaiter {
    return new ReflectedOptionalExtensionAwaiter()
}

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
