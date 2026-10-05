namespace NSharpLang.Compiler

import System

// THE REMOTE-INVOCATION SCOPE: closed, every reading is the process's own; open, every reading is
// the client's. The workspace server opens it around each command it runs for a client.
//
// The scope is process-wide, so every row that opens it closes it in a `finally` and asserts the
// closed state again afterwards.

test "with no scope open every reading is the process's own and nothing launches remotely" {
    assert !CliInvocationContext.IsRemoteInvocation()
    assert String.Join("|", CliInvocationContext.GetCommandLineArgs()) == String.Join("|", Environment.GetCommandLineArgs())
    assert CliInvocationContext.IsStandardErrorRedirected() == Console.IsErrorRedirected

    exitCode := 99
    assert !CliInvocationContext.TryLaunchPassthrough("app.dll", null, out exitCode)
    assert exitCode == 0

    // Cancellation and termination are no-ops outside a scope.
    ran := false
    CliInvocationContext.RegisterCancellation(() => {
        ran = true
    })
    CliInvocationContext.Terminate(5)
    assert !ran
    assert !CliInvocationContext.IsTerminated()
    assert !CliInvocationContext.IsCancelled()
}

test "an open scope answers with the client's command line, stderr state and launcher" {
    launched := ""
    CliInvocationContext.Begin(["/client/Cli.dll", "check", "--color=always"], !Console.IsErrorRedirected, (arguments, directory) => {
        launched = arguments + "@" + (directory ?? "")
        return 42
    })
    try {
        assert CliInvocationContext.IsRemoteInvocation()
        assert String.Join("|", CliInvocationContext.GetCommandLineArgs()) == "/client/Cli.dll|check|--color=always"
        assert CliInvocationContext.IsStandardErrorRedirected() == !Console.IsErrorRedirected

        exitCode := 0
        assert CliInvocationContext.TryLaunchPassthrough("\"app.dll\"", "/w", out exitCode)
        assert exitCode == 42
        assert launched == "\"app.dll\"@/w"
    } finally {
        CliInvocationContext.End()
    }

    assert !CliInvocationContext.IsRemoteInvocation()
}

test "cancellation runs every registered callback once, and late registrations run at once" {
    calls := 0
    CliInvocationContext.Begin(["nlc"], true, null)
    try {
        CliInvocationContext.RegisterCancellation(() => {
            calls = calls + 1
        })
        CliInvocationContext.Cancel()
        CliInvocationContext.Cancel()
        assert calls == 1
        assert CliInvocationContext.IsCancelled()

        CliInvocationContext.RegisterCancellation(() => {
            calls = calls + 10
        })
        assert calls == 11
    } finally {
        CliInvocationContext.End()
    }

    assert !CliInvocationContext.IsCancelled()
}

test "termination records the exit code the client must end with, and End forgets it" {
    CliInvocationContext.Begin(["nlc"], true, null)
    try {
        exitCode := 0
        assert !CliInvocationContext.TryGetTerminatedExitCode(out exitCode)
        CliInvocationContext.Terminate(134)
        assert CliInvocationContext.IsTerminated()
        assert CliInvocationContext.TryGetTerminatedExitCode(out exitCode)
        assert exitCode == 134
    } finally {
        CliInvocationContext.End()
    }

    after := 0
    assert !CliInvocationContext.TryGetTerminatedExitCode(out after)
}
