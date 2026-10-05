namespace NSharpLang.DaemonExec.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Threading

// ═══ SOURCES THE ROWS COMPILE ═════════════════════════════════════════════════════════════════
func CleanProgram(): string {
    return "namespace DaemonExecProbe\n\nimport System\n\nfunc Twice(x: int): int => x * 2\n\nfunc main() {\n    print $\"twice: {Twice(21)}\"\n    line := Console.ReadLine()\n    print $\"read: {line}\"\n    Console.Error.WriteLine(\"to stderr\")\n    Environment.Exit(3)\n}\n"
}

func BrokenProgram(): string {
    return "namespace DaemonExecProbe\n\nfunc Add(a: int, b: int): int {\n    return a + b\n}\n\nfunc main() {\n    x: int = \"not a number\"\n    print Add(x, missing)\n}\n"
}

func MixedTests(): string {
    return "namespace DaemonExecProbe\n\nimport System\n\ntest \"twice doubles\" {\n    print \"hello from a passing test\"\n    assert Twice(2) == 4\n}\n\ntest \"twice is wrong on purpose\" {\n    Console.Error.WriteLine(\"stderr from a failing test\")\n    assert Twice(3) == 7\n}\n"
}

func UnformattedSource(): string {
    return "namespace DaemonExecProbe\n\nfunc   Messy( a:int ):int{\nreturn a+1\n}\n"
}

// ═══ ROUTING ══════════════════════════════════════════════════════════════════════════════════

test "the first routed command runs in-process and starts a server, and the next one runs in it" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        first := NlcWith(["check"], workspace, Traced(), null)
        assert first.ExitCode == 0
        assert first.Stderr.Contains("route=in-process")
        assert first.Stderr.Contains("no-server")

        assert WaitUntil(() => File.Exists(SocketPath(workspace)), 60000)
        WaitUntil(() => File.ReadAllText(Path.Combine(Path.Combine(workspace, ".nlc"), "daemon.log")).Contains("Warm-up"), 90000)

        second := NlcWith(["check"], workspace, Traced(), null)
        assert second.ExitCode == 0
        assert RoutedThroughServer(second.Stderr)
        assert second.Stdout == first.Stdout
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "--no-daemon, NLC_NO_DAEMON and CI keep a command in-process even with a server running" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        StartServer(workspace)
        servedBefore := StatusString(workspace, "servedRequests")

        flagged := NlcWith(["check", "--no-daemon"], workspace, Traced(), null)
        assert flagged.ExitCode == 0
        assert !flagged.Stderr.Contains("[nlc-daemon]")

        environment := Traced()
        environment["NLC_NO_DAEMON"] = "1"
        disabled := NlcWith(["check"], workspace, environment, null)
        assert !disabled.Stderr.Contains("[nlc-daemon]")

        ci := Traced()
        ci["CI"] = "true"
        onCi := NlcWith(["check"], workspace, ci, null)
        assert !onCi.Stderr.Contains("[nlc-daemon]")

        assert StatusString(workspace, "servedRequests") == servedBefore

        // The flag is the router's: the command never sees it.
        assert flagged.Stdout == disabled.Stdout
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "a directory in no workspace runs in-process and plants no .nlc directory" {
    directory := Path.Combine("/tmp", "nlc-" + Guid.NewGuid().ToString("N").Substring(0, 12))
    Directory.CreateDirectory(directory)
    try {
        run := NlcWith(["check", "--project", "/tmp/does-not-exist-nlc"], directory, Traced(), null)
        assert run.Stderr.Contains("no-workspace")
        assert !Directory.Exists(Path.Combine(directory, ".nlc"))
    } finally {
        Directory.Delete(directory, true)
    }
}

// ═══ PARITY ═══════════════════════════════════════════════════════════════════════════════════
//
// The same command, in-process and through the server: identical exit code, stdout and stderr
// (durations aside), over successes, compile errors, failing tests, JSON envelopes, stdin and `run`.

test "check, build, lint and format answer identically in-process and through the server" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        WriteSource(workspace, "Messy.nl", UnformattedSource())
        StartServer(workspace)

        assert RoutedThroughServer(AssertParity(workspace, ["check"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["check", "--text"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["check", "--text", "--color=always"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["build"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["build", "--release"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["lint"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["format", "--check"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["format", "--diff"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["check", "--help"], null))
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "compile errors answer identically in JSON and text, exit code included" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", BrokenProgram())
        StartServer(workspace)

        assert RoutedThroughServer(AssertParity(workspace, ["check"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["check", "--text"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["build"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["lint", "--json"], null))

        failing := Nlc(["check"], workspace)
        assert failing.ExitCode != 0
        assert failing.Stdout.Contains("\"schemaVersion\": 1")
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "test runs answer identically, failing tests, prints and JSON envelope included" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        WriteSource(workspace, "Program.tests.nl", MixedTests())
        StartServer(workspace)

        assert RoutedThroughServer(AssertParity(workspace, ["test"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["test", "--json"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["test", "--verbose"], null))
        assert RoutedThroughServer(AssertParity(workspace, ["test", "--filter", "doubles"], null))

        run := Nlc(["test"], workspace)
        assert run.ExitCode == 1
        assert run.Stdout.Contains("hello from a passing test")
        assert run.Stderr.Contains("stderr from a failing test")
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "stdin reaches a command that reads it, and run starts the program on the client's own streams" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        StartServer(workspace)

        assert RoutedThroughServer(AssertParity(workspace, ["format", "--stdin"], UnformattedSource()))
        assert RoutedThroughServer(AssertParity(workspace, ["run"], "typed by the user\n"))

        run := NlcWith(["run"], workspace, NoEnvironment(), "typed by the user\n")
        assert run.ExitCode == 3
        assert run.Stdout.Contains("twice: 42")
        assert run.Stdout.Contains("read: typed by the user")
        assert run.Stderr.Contains("to stderr")
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "each request gets its own environment and working directory, never the previous client's" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        WriteSource(workspace, "Probe.tests.nl", "namespace DaemonExecProbe\n\nimport System\nimport System.IO\n\ntest \"reports its environment\" {\n    value := Environment.GetEnvironmentVariable(\"NLC_PARITY_PROBE\") ?? \"<unset>\"\n    print $\"probe={value}\"\n    print $\"cwd={Directory.GetCurrentDirectory()}\"\n    child := Environment.GetEnvironmentVariable(\"NLC_DAEMON_CHILD\") ?? \"<unset>\"\n    print $\"child={child}\"\n    assert true\n}\n")
        StartServer(workspace)

        one := new Dictionary<string, string?>()
        one["NLC_PARITY_PROBE"] = "one"
        first := NlcWith(["test", "--verbose"], workspace, one, null)
        assert first.Stdout.Contains("probe=one")

        second := NlcWith(["test", "--verbose"], workspace, NoEnvironment(), null)
        assert second.Stdout.Contains("probe=<unset>")
        assert !second.Stdout.Contains("probe=one")

        // Run from a subdirectory with --project: the command's current directory is the client's.
        subdirectory := Path.Combine(workspace, "sub")
        Directory.CreateDirectory(subdirectory)
        fromSub := NlcWith(["test", "--verbose", "--project", workspace], subdirectory, NoEnvironment(), null)
        fromSubInProcess := NlcWith(["test", "--verbose", "--project", workspace], subdirectory, InProcess(), null)
        cwdLine := CwdLine(fromSubInProcess.Stdout)
        assert cwdLine.EndsWith("/sub")
        assert CwdLine(fromSub.Stdout) == cwdLine

        // Tests see the marker on both routes, so an `nlc` they start never starts a server.
        inProcess := NlcWith(["test", "--verbose"], workspace, InProcess(), null)
        assert inProcess.Stdout.Contains("child=1")
        assert second.Stdout.Contains("child=1")
    } finally {
        DeleteWorkspace(workspace)
    }
}

func CwdLine(output: string): string {
    for line in output.Split('\n') {
        if line.StartsWith("cwd=") {
            return line.Trim()
        }
    }

    return ""
}

// ═══ ISOLATION, FAILURE AND RECOVERY ══════════════════════════════════════════════════════════

test "a test that exits the process ends the request with its code and the server keeps serving" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        WriteSource(workspace, "Exit.tests.nl", "namespace DaemonExecProbe\n\nimport System\n\ntest \"exits\" {\n    print \"about to exit\"\n    Environment.Exit(7)\n}\n")
        pid := StartServer(workspace)

        trace := AssertParity(workspace, ["test"], null)
        assert RoutedThroughServer(trace)
        crashed := Nlc(["test"], workspace)
        assert crashed.ExitCode == 7

        assert IsProcessAlive(pid)
        after := NlcWith(["check"], workspace, Traced(), null)
        assert after.ExitCode == 0
        assert RoutedThroughServer(after.Stderr)
        assert ServerPid(workspace) == pid
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "a test that overflows its stack ends the request like an in-process run and the server survives" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", "namespace DaemonExecProbe\n\nfunc Recurse(n: int): int {\n    return Recurse(n + 1) + 1\n}\n\nfunc main() {\n    print \"app\"\n}\n")
        WriteSource(workspace, "Overflow.tests.nl", "namespace DaemonExecProbe\n\ntest \"overflows\" {\n    assert Recurse(0) > 0\n}\n")
        pid := StartServer(workspace)

        inProcess := NlcWith(["test"], workspace, InProcess(), null)
        routed := NlcWith(["test"], workspace, Traced(), null)
        assert RoutedThroughServer(routed.Stderr)
        assert routed.ExitCode == inProcess.ExitCode
        assert routed.ExitCode != 0
        assert routed.Stderr.Contains("Stack overflow")
        assert Normalized(routed.Stdout) == Normalized(inProcess.Stdout)

        assert IsProcessAlive(pid)
        assert Nlc(["check"], workspace).ExitCode == 0
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "a server killed mid-command makes the client rerun in-process with exactly one note" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        WriteSource(workspace, "Slow.tests.nl", "namespace DaemonExecProbe\n\nimport System.Threading\n\ntest \"takes a while\" {\n    Thread.Sleep(4000)\n    assert true\n}\n")
        pid := StartServer(workspace)

        process := new Process { StartInfo: NlcStartInfo(["test"], workspace, NoEnvironment()) }
        process.Start()
        // Kill the server while the test is sleeping inside it.
        Thread.Sleep(1500)
        server := Process.GetProcessById(pid)
        server.Kill(true)
        server.Dispose()
        run := Finish(process, null, 120000)

        assert run.ExitCode == 0
        assert CountOccurrences(run.Stderr, "nlc: the workspace server stopped responding; running in-process instead") == 1
        assert run.Stdout.Contains("Passed: 1")

        // The next command starts a replacement in the background and runs in-process meanwhile.
        assert Nlc(["check"], workspace).ExitCode == 0
        assert WaitUntil(() => ServerPid(workspace) != pid && IsProcessAlive(ServerPid(workspace)), 60000)
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "a server of another build is replaced, never reused" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        // A DOTNET_ variable is part of the build identity, so a server started under one is, to a
        // client without it, a different build.
        otherBuild := new Dictionary<string, string?>()
        otherBuild["DOTNET_NLC_DAEMON_TEST_BUILD"] = "other"
        started := NlcWith(["daemon", "start"], workspace, otherBuild, null)
        assert started.ExitCode == 0
        oldPid := ServerPid(workspace)
        oldIdentity := StatusString(workspace, "identity")
        assert IsProcessAlive(oldPid)

        mismatched := NlcWith(["check"], workspace, Traced(), null)
        assert mismatched.ExitCode == 0
        assert mismatched.Stderr.Contains("mismatch")
        assert mismatched.Stderr.Contains("route=in-process")
        assert WaitUntil(() => !IsProcessAlive(oldPid), 20000)

        assert WaitUntil(() => IsProcessAlive(ServerPid(workspace)) && ServerPid(workspace) != oldPid, 60000)
        WaitUntil(() => StatusString(workspace, "identity") != "", 30000)
        assert StatusString(workspace, "identity") != oldIdentity
        assert WaitUntil(() => RoutedThroughServer(NlcWith(["check"], workspace, Traced(), null).Stderr), 60000)
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "two clients at once both get the in-process answer" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        WriteSource(workspace, "Program.tests.nl", MixedTests())
        StartServer(workspace)
        expectedCheck := NlcWith(["check"], workspace, InProcess(), null)
        expectedTest := NlcWith(["test", "--json"], workspace, InProcess(), null)

        index := 0
        while index < 3 {
            checkProcess := new Process { StartInfo: NlcStartInfo(["check"], workspace, Traced()) }
            testProcess := new Process { StartInfo: NlcStartInfo(["test", "--json"], workspace, Traced()) }
            checkProcess.Start()
            testProcess.Start()
            checkRun := Finish(checkProcess, null, 180000)
            testRun := Finish(testProcess, null, 180000)

            assert checkRun.ExitCode == expectedCheck.ExitCode
            assert checkRun.Stdout == expectedCheck.Stdout
            assert testRun.ExitCode == expectedTest.ExitCode
            assert Normalized(testRun.Stdout) == Normalized(expectedTest.Stdout)
            index = index + 1
        }
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "cancelling a client stops its test run and leaves the server serving" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", "namespace DaemonExecProbe\n\nfunc Spin(): int {\n    count := 0\n    while true {\n        count = count + 1\n    }\n}\n\nfunc main() {\n    print \"app\"\n}\n")
        WriteSource(workspace, "Hang.tests.nl", "namespace DaemonExecProbe\n\ntest \"never finishes\" {\n    print \"spinning\"\n    assert Spin() > 0\n}\n")
        pid := StartServer(workspace)

        process := new Process { StartInfo: NlcStartInfo(["test"], workspace, NoEnvironment()) }
        process.Start()
        stdoutTask := process.StandardOutput.ReadToEndAsync()
        stderrTask := process.StandardError.ReadToEndAsync()
        Thread.Sleep(4000)
        // SIGTERM, the signal a supervisor (or a harness) sends; the client relays the cancel and
        // then ends exactly as an in-process run would.
        signal := Process.Start("kill", "-TERM " + process.Id.ToString())
        if signal != null {
            (signal ?? new Process()).WaitForExit()
        }

        assert process.WaitForExit(30000)
        assert process.ExitCode == 143
        stdoutTask.Wait()
        stderrTask.Wait()
        process.Dispose()

        logPath := Path.Combine(Path.Combine(workspace, ".nlc"), "daemon.log")
        assert WaitUntil(() => File.ReadAllText(logPath).Contains("exec test ->"), 30000)
        assert IsProcessAlive(pid)
        assert WaitUntil(() => RoutedThroughServer(NlcWith(["check"], workspace, Traced(), null).Stderr), 30000)
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "a referenced project rebuilt under a running server is never compiled against the stale build" {
    workspace := Path.Combine("/tmp", "nlc-" + Guid.NewGuid().ToString("N").Substring(0, 12))
    library := Path.Combine(workspace, "lib")
    application := Path.Combine(workspace, "app")
    Directory.CreateDirectory(Path.Combine(workspace, ".git"))
    Directory.CreateDirectory(library)
    Directory.CreateDirectory(application)
    try {
        File.WriteAllText(Path.Combine(library, "project.yml"), "name: Lib\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\n")
        File.WriteAllText(Path.Combine(library, "Lib.nl"), "namespace Lib\n\nclass Greeter {\n    static func Hello(): string => \"hello\"\n}\n")
        File.WriteAllText(Path.Combine(application, "project.yml"), "name: App\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - project: ../lib/project.yml\n")
        File.WriteAllText(Path.Combine(application, "Program.nl"), "namespace App\n\nimport Lib\n\nfunc main() {\n    print Greeter.Hello()\n}\n")

        Nlc(["build"], application)
        logPath := Path.Combine(Path.Combine(workspace, ".nlc"), "daemon.log")
        assert WaitUntil(() => File.Exists(logPath) && File.ReadAllText(logPath).Contains("Warm-up"), 90000)
        first := NlcWith(["run"], application, Traced(), null)
        assert RoutedThroughServer(first.Stderr)
        assert first.Stdout.Contains("hello")

        // The library gains a member and the application calls it.
        File.WriteAllText(Path.Combine(library, "Lib.nl"), "namespace Lib\n\nclass Greeter {\n    static func Hello(): string => \"hello\"\n    static func Bye(): string => \"bye\"\n}\n")
        File.WriteAllText(Path.Combine(application, "Program.nl"), "namespace App\n\nimport Lib\n\nfunc main() {\n    print Greeter.Hello()\n    print Greeter.Bye()\n}\n")
        expected := NlcWith(["run"], application, InProcess(), null)
        assert expected.ExitCode == 0
        assert expected.Stdout.Contains("bye")

        after := NlcWith(["run"], application, Traced(), null)
        assert after.ExitCode == 0
        assert Normalized(after.Stdout) == Normalized(expected.Stdout)

        // The stale server retired; a fresh one takes over and answers correctly.
        assert WaitUntil(
            () => {
                run := NlcWith(["run"], application, Traced(), null)
                return RoutedThroughServer(run.Stderr) && run.Stdout.Contains("bye")
            },
            120000
        )
    } finally {
        StopServer(workspace)
        Directory.Delete(workspace, true)
    }
}

test "nlc daemon start works outside any repository and never holds the caller's output open" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        clock := Stopwatch.StartNew()
        // `Finish` reads stdout and stderr to END-OF-FILE: a server that inherited either pipe would
        // keep this call waiting until the server's idle timeout.
        started := NlcWith(["daemon", "start"], workspace, NoEnvironment(), null)
        assert started.ExitCode == 0
        assert started.Stdout.Contains("Daemon started.")
        assert clock.ElapsedMilliseconds < 60000
        pid := ServerPid(workspace)
        assert IsProcessAlive(pid)

        // The same for the background start a routed command does.
        StopServer(workspace)
        routed := NlcWith(["check"], workspace, NoEnvironment(), null)
        assert routed.ExitCode == 0
        assert WaitUntil(() => IsProcessAlive(ServerPid(workspace)), 60000)
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "a launched server ignores the hang-up and Ctrl-C of the terminal it came from and stops on SIGTERM" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        assert NlcWith(["daemon", "start"], workspace, NoEnvironment(), null).ExitCode == 0
        pid := ServerPid(workspace)
        for signal in ["-HUP", "-INT"] {
            sender := Process.Start("kill", signal + " " + pid.ToString())
            if sender != null {
                (sender ?? new Process()).WaitForExit()
            }
        }

        Thread.Sleep(1000)
        assert IsProcessAlive(pid)
        assert StatusString(workspace, "pid") == pid.ToString()

        terminate := Process.Start("kill", "-TERM " + pid.ToString())
        if terminate != null {
            (terminate ?? new Process()).WaitForExit()
        }

        assert WaitUntil(() => !IsProcessAlive(pid), 20000)
        assert !File.Exists(SocketPath(workspace))
    } finally {
        DeleteWorkspace(workspace)
    }
}

// ═══ LIFECYCLE ════════════════════════════════════════════════════════════════════════════════

test "daemon status reports the build and its load, and daemon stop stops it" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        pid := StartServer(workspace)
        Nlc(["check"], workspace)

        assert StatusString(workspace, "pid") == pid.ToString()
        assert StatusString(workspace, "identity").Length == 16
        assert StatusString(workspace, "version").StartsWith("0.")
        assert Int32.Parse(StatusString(workspace, "servedRequests")) >= 1
        assert StatusString(workspace, "memoryCapMb") == "4096"

        stopped := Nlc(["daemon", "stop", "--project", workspace], workspace)
        assert stopped.ExitCode == 0
        assert stopped.Stdout.Contains("Daemon stopped.")
        assert WaitUntil(() => !IsProcessAlive(pid), 15000)
        assert !File.Exists(SocketPath(workspace))
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "an idle server exits after its idle timeout" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        environment := new Dictionary<string, string?>()
        environment["NLC_DAEMON_IDLE_TIMEOUT"] = "3s"
        NlcWith(["check"], workspace, environment, null)
        assert WaitUntil(() => IsProcessAlive(ServerPid(workspace)), 60000)
        pid := ServerPid(workspace)
        assert WaitUntil(() => !IsProcessAlive(pid), 60000)
        assert !File.Exists(SocketPath(workspace))
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "deleting a workspace retires its server" {
    workspace := NewWorkspace()
    WriteSource(workspace, "Program.nl", CleanProgram())
    pid := StartServer(workspace)
    try {
        Directory.Delete(workspace, true)
        assert WaitUntil(() => !IsProcessAlive(pid), 20000)
    } finally {
        if IsProcessAlive(pid) {
            Process.GetProcessById(pid).Kill(true)
        }
    }
}

test "a server over its memory cap retires after the request it was serving" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        environment := new Dictionary<string, string?>()
        environment["NLC_DAEMON_MAX_MEMORY_MB"] = "1"
        NlcWith(["check"], workspace, environment, null)
        // The warm-up's own request is not an exec, so the server is up until a command runs.
        assert WaitUntil(() => IsProcessAlive(ServerPid(workspace)), 60000)
        pid := ServerPid(workspace)
        WaitUntil(() => File.ReadAllText(Path.Combine(Path.Combine(workspace, ".nlc"), "daemon.log")).Contains("Warm-up"), 90000)
        run := NlcWith(["check"], workspace, Traced(), null)
        assert run.ExitCode == 0
        assert RoutedThroughServer(run.Stderr)
        assert WaitUntil(() => !IsProcessAlive(pid), 20000)
        assert File.ReadAllText(Path.Combine(Path.Combine(workspace, ".nlc"), "daemon.log")).Contains("cap")
    } finally {
        DeleteWorkspace(workspace)
    }
}

test "the socket is owner-only" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Program.nl", CleanProgram())
        StartServer(workspace)
        mode := File.GetUnixFileMode(SocketPath(workspace))
        assert mode == (UnixFileMode.UserRead | UnixFileMode.UserWrite)
    } finally {
        DeleteWorkspace(workspace)
    }
}
