namespace NSharpLang.ReflectionEmitBootstrap.Tests

test "ThreadStart captures execute on the exact wide-stack Thread overload" {
    owner := new ThreadStartCaptureEmitFacts()
    completed := new ThreadStartCaptureState()
    owner.Run(completed, 37, "captured", null)
    assert completed.Value == 37
    assert completed.Label == "captured"
    assert completed.Captured == null

    failed := new ThreadStartCaptureState()
    failure := new InvalidOperationException("thread-start-failure")
    let caught: Exception? = null
    try {
        owner.Run(failed, 99, "unwritten", failure)
    } catch error: Exception {
        caught = error
    }
    assert failed.Value == -1
    assert failed.Label == ""
    if caught == null {
        throw new InvalidOperationException("ThreadStart failure was not rethrown after Join")
    }
    assert Object.ReferenceEquals(caught, failure)
    assert caught.Message == "thread-start-failure"

    actionState := new ThreadStartCaptureState()
    owner.RunAction(actionState, 41, "action")
    assert actionState.Value == 41
    assert actionState.Label == "action"
    assert actionState.Captured == null

    assert owner.RunFunc(19, 23) == 42
}
