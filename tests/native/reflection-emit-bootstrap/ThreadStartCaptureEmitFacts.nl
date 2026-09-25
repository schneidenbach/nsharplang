namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Runtime.ExceptionServices
import System.Threading

class ThreadStartCaptureState {
    Value: int
    Label: string
    Captured: ExceptionDispatchInfo?

    constructor() {
        Value = -1
        Label = ""
        Captured = null
    }
}

class ThreadStartCaptureEmitFacts {
    func Run(state: ThreadStartCaptureState, value: int, label: string, failure: Exception?) {
        work: ThreadStart = () => RunOnCurrentThread(state, value, label, failure)
        thread := new Thread(work, 4 * 1024 * 1024)
        thread.IsBackground = true
        thread.Name = "nsharp-thread-start-capture"
        thread.Start()
        thread.Join()
        captured := state.Captured
        if captured != null {
            captured.Throw()
        }
    }

    private func RunOnCurrentThread(state: ThreadStartCaptureState, value: int, label: string, failure: Exception?) {
        try {
            if failure != null {
                throw failure
            }
            state.Value = value
            state.Label = label
        } catch error: Exception {
            state.Captured = ExceptionDispatchInfo.Capture(error)
        }
    }

    func RunAction(state: ThreadStartCaptureState, value: int, label: string) {
        action: Action = () => RunOnCurrentThread(state, value, label, null)
        action()
    }

    func RunFunc(value: int, offset: int): int {
        read: Func<int> = () => AddCaptured(value, offset)
        return read()
    }

    private func AddCaptured(value: int, offset: int): int {
        return value + offset
    }
}
