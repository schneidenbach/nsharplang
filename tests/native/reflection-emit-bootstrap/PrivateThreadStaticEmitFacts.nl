namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System


// Both fields are deliberately private. The public methods expose behavior only; reflection tests
// below verify the metadata that the declaration path must retain for a private ThreadStatic field.
class PrivateThreadStaticEmitFacts {
    [System.ThreadStatic]
    private static Counter: int

    [System.ThreadStaticAttribute]
    private static Label: string?

    private static SharedCounter: int

    static func Reset() {
        PrivateThreadStaticEmitFacts.Counter = 0
        PrivateThreadStaticEmitFacts.Label = null
        PrivateThreadStaticEmitFacts.SharedCounter = 0
    }

    static func Set(counter: int, label: string?) {
        PrivateThreadStaticEmitFacts.Counter = counter
        PrivateThreadStaticEmitFacts.Label = label
    }

    static func CurrentCounter(): int {
        return PrivateThreadStaticEmitFacts.Counter
    }

    static func CurrentLabel(): string? {
        return PrivateThreadStaticEmitFacts.Label
    }

    static func SetSharedCounter(value: int) {
        PrivateThreadStaticEmitFacts.SharedCounter = value
    }

    static func CurrentSharedCounter(): int {
        return PrivateThreadStaticEmitFacts.SharedCounter
    }
}

class PrivateThreadStaticEmitThreadProbe {
    InitialCounter: int
    InitialLabel: string?
    Counter: int
    Label: string?
    InitialSharedCounter: int
    SharedCounter: int
    Error: string

    constructor() {
        InitialCounter = -1
        InitialLabel = null
        Counter = -1
        Label = null
        InitialSharedCounter = -1
        SharedCounter = -1
        Error = ""
    }

    func Run() {
        try {
            InitialCounter = PrivateThreadStaticEmitFacts.CurrentCounter()
            InitialLabel = PrivateThreadStaticEmitFacts.CurrentLabel()
            InitialSharedCounter = PrivateThreadStaticEmitFacts.CurrentSharedCounter()
            PrivateThreadStaticEmitFacts.Set(17, "worker")
            PrivateThreadStaticEmitFacts.SetSharedCounter(23)
            Counter = PrivateThreadStaticEmitFacts.CurrentCounter()
            Label = PrivateThreadStaticEmitFacts.CurrentLabel()
            SharedCounter = PrivateThreadStaticEmitFacts.CurrentSharedCounter()
        } catch error: Exception {
            Error = error.Message
        }
    }
}
