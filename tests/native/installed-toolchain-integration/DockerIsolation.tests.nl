namespace NSharpLang.InstalledToolchainIntegration.Tests

import System
import System.Collections.Generic
import System.Text.RegularExpressions

// ─── TWO RUNS, ONE DAEMON ──────────────────────────────────────────────────────────────────────
//
// A product gate at b75070d46 shared this machine's daemon with another run of this project. Both
// used ONE image tag and ONE container name: the gate's `docker build` hit its thirty-minute ceiling
// with nothing on either stream to say where it stopped, every Docker row failed, and a container
// under the fixed name was left running with no process owning it. These rows hold the fix to its
// contract on any machine — they need no daemon, because the fixture reaches Docker only through
// `IToolchainDockerHost`, and a recording host stands in for it here.

// Records every `docker` argv it is asked to run and answers from a script: the first prefix that
// matches the joined argv supplies the result, and anything unscripted succeeds with no output.
class RecordingDockerHost: IToolchainDockerHost {
    Calls: List<string>
    Timeouts: List<int>
    LivePids: List<int>
    OwnerQueries: List<string>
    prefixes: List<string>
    answers: List<ToolchainRun>

    constructor() {
        Calls = new List<string>()
        Timeouts = new List<int>()
        LivePids = new List<int>()
        OwnerQueries = new List<string>()
        prefixes = new List<string>()
        answers = new List<ToolchainRun>()
    }

    func Answer(prefix: string, answer: ToolchainRun) {
        prefixes.Add(prefix)
        answers.Add(answer)
    }

    func Docker(arguments: List<string>, timeoutMilliseconds: int): ToolchainRun {
        line := ToolchainJoinArguments(arguments)
        Calls.Add(line)
        Timeouts.Add(timeoutMilliseconds)
        index := 0
        while index < prefixes.Count {
            if line.StartsWith(prefixes[index]) {
                return answers[index]
            }

            index = index + 1
        }

        return new ToolchainRun(0, "", "")
    }

    func OwnerAlive(pid: int, startedUnixSeconds: long): bool {
        OwnerQueries.Add(pid.ToString() + "@" + startedUnixSeconds.ToString())
        return LivePids.Contains(pid)
    }

    // The ceiling the first call starting with `prefix` ran under, or -1 when there was none.
    func TimeoutOfFirst(prefix: string): int {
        index := 0
        while index < Calls.Count {
            if Calls[index].StartsWith(prefix) {
                return Timeouts[index]
            }

            index = index + 1
        }

        return -1
    }

    func CountCalls(prefix: string): int {
        count := 0
        for call in Calls {
            if call.StartsWith(prefix) {
                count = count + 1
            }
        }

        return count
    }
}

func IsolationRun(runId: string, pid: int): ToolchainDockerRun {
    return new ToolchainDockerRun(runId, pid, 1790000000, "isolation-host", 1790000100)
}

// A build the ceiling killed, as `ToolchainRunProcess` reports one: exit 124, the command, and the
// lines that arrived before the kill.
func IsolationTimedOutBuild(): ToolchainRun {
    build := new ToolchainRun(124, "", "#5 [2/5] COPY toolset/ /root/.nsharp/\n#5 DONE 0.4s\n#7 [4/5] RUN dotnet new install /root/.nsharp/packages/NSharpLang.Templates.*.nupkg --force\n#7 12.3 Restoring templates\n")
    build.CommandLine = "docker build --progress plain"
    build.TimedOut = true
    build.TimeoutMilliseconds = 1800000
    build.Lines.Add("#5 [2/5] COPY toolset/ /root/.nsharp/")
    build.Lines.Add("#5 DONE 0.4s")
    build.Lines.Add("#7 [4/5] RUN dotnet new install /root/.nsharp/packages/NSharpLang.Templates.*.nupkg --force")
    build.Lines.Add("#7 12.3 Restoring templates")
    return build
}

func IsolationThrownMessage(fixture: ToolchainDockerFixture): string {
    try {
        fixture.Start("/tmp/nsharp-integration-isolation")
    } catch failure: InvalidOperationException {
        return failure.Message
    }

    return ""
}

test "two fixtures in one process get distinct, readable, labelled names" {
    first := ToolchainNewDockerRun()
    second := ToolchainNewDockerRun()

    assert first.RunId != second.RunId, first.RunId
    assert first.ContainerName != second.ContainerName, first.ContainerName
    assert first.ImageTag != second.ImageTag, first.ImageTag

    // Readable: the prefix, then the owning pid and the UTC second, then a random tail.
    namePattern := "^nsharp-installed-toolchain-integration-" + Environment.ProcessId.ToString() + "-[0-9]{8}t[0-9]{6}-[0-9a-f]{6}$"
    assert Regex.IsMatch(first.ContainerName, namePattern), first.ContainerName
    assert Regex.IsMatch(second.ContainerName, namePattern), second.ContainerName

    // An image repository must be lowercase; the tag is the container name plus `:local`.
    assert first.ImageTag == first.ContainerName + ":local", first.ImageTag
    assert first.ImageTag == first.ImageTag.ToLowerInvariant(), first.ImageTag

    // Both carry THIS process as their owner, by pid and by start time.
    assert first.OwnerPid == Environment.ProcessId
    assert ToolchainOwnerProcessAlive(first.OwnerPid, first.OwnerStartedUnixSeconds)
    assert first.OwnerHost == Environment.MachineName

    // And each fixture's every command names its own run and never the other's.
    firstHost := new RecordingDockerHost()
    secondHost := new RecordingDockerHost()
    firstFixture := new ToolchainDockerFixture(first, firstHost)
    secondFixture := new ToolchainDockerFixture(second, secondHost)
    firstFixture.Start("/tmp/nsharp-integration-first")
    secondFixture.Start("/tmp/nsharp-integration-second")
    firstFixture.Exec("true")
    secondFixture.Exec("true")
    firstFixture.Teardown()
    secondFixture.Teardown()

    for call in firstHost.Calls {
        assert !call.Contains(second.RunId), call
    }

    for call in secondHost.Calls {
        assert !call.Contains(first.RunId), call
    }

    assert firstHost.Calls.Contains("exec " + first.ContainerName + " bash -c true"), string.Join("\n", firstHost.Calls)
    assert secondHost.Calls.Contains("exec " + second.ContainerName + " bash -c true"), string.Join("\n", secondHost.Calls)
    assert firstHost.CountCalls("build --progress plain --file /tmp/nsharp-integration-first/Dockerfile.toolchain --tag " + first.ImageTag + " --label nsharp.test=installed-toolchain-integration --label nsharp.test.run=" + first.RunId + " ") == 1, string.Join("\n", firstHost.Calls)
    assert secondHost.CountCalls("run --detach --rm --name " + second.ContainerName + " --label nsharp.test=installed-toolchain-integration --label nsharp.test.run=" + second.RunId + " ") == 1, string.Join("\n", secondHost.Calls)
}

test "a build killed at its ceiling tears down the container and the image, says where it stopped, and is not retried" {
    host := new RecordingDockerHost()
    host.Answer("build ", IsolationTimedOutBuild())
    run := IsolationRun("1111-20260925t120000-aaaaaa", 1111)
    fixture := new ToolchainDockerFixture(run, host)

    message := IsolationThrownMessage(fixture)

    // The report names the ceiling, the command, the step it was on and the lines it last printed —
    // not `exit 124` over two empty streams.
    assert message.Contains("docker build of " + run.ImageTag + " timed out after 1800000 ms"), message
    assert message.Contains("--- command ---\ndocker build --progress plain"), message
    assert message.Contains("--- last build step started ---\n#7 [4/5] RUN dotnet new install"), message
    assert message.Contains("#7 12.3 Restoring templates"), message

    // BOTH halves removed, by this run's own names, the container first.
    containerRemoval := host.Calls.IndexOf("rm --force " + run.ContainerName)
    imageRemoval := host.Calls.IndexOf("image rm --force " + run.ImageTag)
    assert containerRemoval >= 0, string.Join("\n", host.Calls)
    assert imageRemoval > containerRemoval, string.Join("\n", host.Calls)
    assert host.CountCalls("run ") == 0, string.Join("\n", host.Calls)
    assert host.TimeoutOfFirst("build ") == ToolchainImageBuildTimeoutMilliseconds(), host.TimeoutOfFirst("build ").ToString()
    assert host.TimeoutOfFirst("rm --force ") == ToolchainDockerHousekeepingTimeoutMilliseconds(), host.TimeoutOfFirst("rm --force ").ToString()

    // The next row fails at once with the first failure's report, and builds nothing.
    again := IsolationThrownMessage(fixture)
    assert again.Contains("failed to start earlier and is not retried"), again
    assert again.Contains("#7 [4/5] RUN dotnet new install"), again
    assert host.CountCalls("build ") == 1, string.Join("\n", host.Calls)
    assert host.CountCalls("rm --force " + run.ContainerName) == 1, string.Join("\n", host.Calls)
}

test "a container that fails to start tears down the container and the image it was made from" {
    host := new RecordingDockerHost()
    host.Answer("run ", new ToolchainRun(125, "", "docker: Error response from daemon: Conflict."))
    run := IsolationRun("2222-20260925t120000-bbbbbb", 2222)
    fixture := new ToolchainDockerFixture(run, host)

    message := IsolationThrownMessage(fixture)

    assert message.Contains("docker run of " + run.ContainerName + " failed (exit code 125)"), message
    assert message.Contains("Conflict."), message
    assert host.Calls.Contains("rm --force " + run.ContainerName), string.Join("\n", host.Calls)
    assert host.Calls.Contains("image rm --force " + run.ImageTag), string.Join("\n", host.Calls)
    assert fixture.TornDown
    assert !fixture.Started
}

test "a finished fixture removes its container and image exactly once, even when docker is gone" {
    host := new RecordingDockerHost()
    run := IsolationRun("3333-20260925t120000-cccccc", 3333)
    fixture := new ToolchainDockerFixture(run, host)
    fixture.Start("/tmp/nsharp-integration-finished")
    assert fixture.Started

    // Process exit and load-context unload both call it; the second call is a no-op.
    fixture.Teardown()
    fixture.Teardown()
    assert host.CountCalls("rm --force " + run.ContainerName) == 1, string.Join("\n", host.Calls)
    assert host.CountCalls("image rm --force " + run.ImageTag) == 1, string.Join("\n", host.Calls)

    // Teardown runs in exit handlers, so a failing daemon must not make it throw.
    failing := new RecordingDockerHost()
    failing.Answer("rm ", new ToolchainRun(1, "", "Cannot connect to the Docker daemon"))
    failing.Answer("image rm ", new ToolchainRun(1, "", "Cannot connect to the Docker daemon"))
    quiet := new ToolchainDockerFixture(IsolationRun("3334-20260925t120000-cccccd", 3334), failing)
    quiet.Teardown()
    assert quiet.TornDown
    assert failing.CountCalls("image rm --force ") == 1, string.Join("\n", failing.Calls)
}

test "reclaim removes only the leftovers whose owner is provably gone" {
    now: long = 1790090000
    host := new RecordingDockerHost()
    host.LivePids.Add(5001)
    run := IsolationRun("5000-20260925t120000-dddddd", 5000)

    host.Answer("ps --all --quiet --no-trunc --filter label=nsharp.test=installed-toolchain-integration", new ToolchainRun(0, "c-live\nc-dead\nc-foreign\nc-ancient\nc-self\nc-unlabelled\n", ""))
    host.Answer("container inspect ", new ToolchainRun(0, "c-live\trun-live\t5001\t1790000000\tisolation-host\t1790089000\nc-dead\trun-dead\t5002\t1790000000\tisolation-host\t1790089000\nc-foreign\trun-foreign\t5003\t1790000000\tother-host\t1790089000\nc-ancient\trun-ancient\t5004\t1790000000\tother-host\t1790000000\nc-self\t" + run.RunId + "\t5000\t1790000000\tisolation-host\t1790089000\nc-unlabelled\t\t\t\t\t\n", ""))
    host.Answer("image ls --quiet --no-trunc --filter label=nsharp.test=installed-toolchain-integration", new ToolchainRun(0, "sha256:live\nsha256:dead\nsha256:dead\n", ""))
    host.Answer("image inspect ", new ToolchainRun(0, "sha256:live\trun-live\t5001\t1790000000\tisolation-host\t1790089000\nsha256:dead\trun-dead\t5002\t1790000000\tisolation-host\t1790089000\n", ""))

    fixture := new ToolchainDockerFixture(run, host)
    fixture.ReclaimStale(now)
    calls := string.Join("\n", host.Calls)

    // A dead owner on this host, and anything past the age limit, are taken.
    assert host.Calls.Contains("rm --force c-dead"), calls
    assert host.Calls.Contains("rm --force c-ancient"), calls
    assert host.Calls.Contains("image rm --force sha256:dead"), calls

    // A LIVE owner's container and image are left alone — that is another run, mid-row.
    assert !host.Calls.Contains("rm --force c-live"), calls
    assert !host.Calls.Contains("image rm --force sha256:live"), calls

    // So are this run's own, an owner on another host that is still young, and labels that do not
    // say who owns them.
    assert !host.Calls.Contains("rm --force c-self"), calls
    assert !host.Calls.Contains("rm --force c-foreign"), calls
    assert !host.Calls.Contains("rm --force c-unlabelled"), calls

    // Only this host's owners are asked about; another host's pid means nothing here.
    assert string.Join(",", host.OwnerQueries) == "5001@1790000000,5002@1790000000,5000@1790000000,5001@1790000000,5002@1790000000", string.Join(",", host.OwnerQueries)

    // A duplicated id from `image ls` is inspected once, and every reclaim says why.
    assert host.CountCalls("image inspect --format ") == 1, calls
    assert host.Calls.Contains("image inspect --format " + DockerLeftoverInspectFormat() + " sha256:live sha256:dead"), calls
    assert fixture.Reclaimed.Count == 3, string.Join("\n", fixture.Reclaimed)
    assert fixture.Reclaimed.Contains("container c-dead (run run-dead): owner pid 5002 on isolation-host is no longer running"), string.Join("\n", fixture.Reclaimed)
}

test "the reclaim rule keeps what it cannot prove orphaned" {
    now: long = 1790090000
    day := ToolchainStaleLeftoverAgeSeconds()
    young := new DockerLeftover("container", "c", "run-x", 77, 1790000000, "here", now - 60)
    old := new DockerLeftover("container", "c", "run-x", 77, 1790000000, "elsewhere", now - day - 1)
    edge := new DockerLeftover("container", "c", "run-x", 77, 1790000000, "elsewhere", now - day)
    unparsed := new DockerLeftover("container", "c", "run-x", -1, -1, "here", -1)

    assert !DockerReclaimDecisionFor(young, "run-me", "here", true, now, day).Reclaim
    assert DockerReclaimDecisionFor(young, "run-me", "here", false, now, day).Reclaim
    assert !DockerReclaimDecisionFor(young, "run-x", "here", false, now, day).Reclaim, "a run never reclaims its own objects"

    // Another host's owner cannot be asked, so only age decides — and the limit itself is not past it.
    assert !DockerReclaimDecisionFor(young, "run-me", "elsewhere-too", false, now, day).Reclaim
    assert DockerReclaimDecisionFor(old, "run-me", "here", false, now, day).Reclaim
    assert !DockerReclaimDecisionFor(edge, "run-me", "here", false, now, day).Reclaim

    // Labels that do not parse never read as a dead owner.
    assert !DockerReclaimDecisionFor(unparsed, "run-me", "here", false, now, day).Reclaim
    assert ToolchainParseDockerLeftovers("image", "sha256:x\t\tnot-a-pid\t\there\t\n")[0].OwnerPid == -1
}

test "an owner is alive only while its pid still belongs to the process that started at the labelled time" {
    current := ToolchainNewDockerRun()
    assert ToolchainOwnerProcessAlive(current.OwnerPid, current.OwnerStartedUnixSeconds)

    // The same pid with a different start time is a recycled pid, not the owner.
    assert !ToolchainOwnerProcessAlive(current.OwnerPid, current.OwnerStartedUnixSeconds - 3600)

    // A process that has exited is not an owner.
    launch := new ToolchainLaunch("bash", Environment.CurrentDirectory, ToolchainProbeTimeoutMilliseconds())
    launch.Arguments.Add("-c")
    launch.Arguments.Add("echo $$")
    finished := ToolchainRunProcess(launch)
    finishedPid := int.Parse(finished.Stdout.Trim())
    assert !ToolchainOwnerProcessAlive(finishedPid, current.OwnerStartedUnixSeconds), finishedPid.ToString()
}

test "a command killed at its ceiling keeps what it printed and names what it was running" {
    launch := new ToolchainLaunch("bash", Environment.CurrentDirectory, 1500)
    launch.Arguments.Add("-c")
    launch.Arguments.Add("echo first-stdout-line; echo '#9 [3/5] RUN a step that hangs' >&2; sleep 30")
    run := ToolchainRunProcess(launch)

    assert run.ExitCode == 124, run.ExitCode.ToString()
    assert run.TimedOut
    assert run.Stdout.Contains("first-stdout-line"), run.Stdout
    assert run.Stderr.Contains("#9 [3/5] RUN a step that hangs"), run.Stderr
    assert run.Stderr.Contains("Timed out after 1500 ms."), run.Stderr

    report := run.Report("the hanging step")
    assert report.StartsWith("the hanging step timed out after 1500 ms (exit code 124) and was killed."), report
    assert report.Contains("--- command ---\nbash -c echo first-stdout-line;"), report
    assert report.Contains("--- last build step started ---\n#9 [3/5] RUN a step that hangs"), report
    assert report.Contains("first-stdout-line"), report

    // Silence is reported as silence, never as two empty banners.
    silent := new ToolchainLaunch("bash", Environment.CurrentDirectory, 1000)
    silent.Arguments.Add("-c")
    silent.Arguments.Add("sleep 30")
    quiet := ToolchainRunProcess(silent).Report("the silent step")
    assert quiet.Contains("(the command wrote nothing to stdout or stderr before it was killed)"), quiet
    assert !quiet.Contains("last build step started"), quiet

    // A command that finishes is reported exactly as before, streams intact.
    finished := new ToolchainLaunch("bash", Environment.CurrentDirectory, ToolchainProbeTimeoutMilliseconds())
    finished.Arguments.Add("-c")
    finished.Arguments.Add("echo out; echo err >&2; exit 3")
    result := ToolchainRunProcess(finished)
    assert !result.TimedOut
    assert result.ExitCode == 3
    assert result.Stdout == "out\n", result.Stdout
    assert result.Stderr == "err\n", result.Stderr
    assert result.Report("the failing step") == "the failing step failed (exit code 3)\n--- stdout ---\nout\n\n--- stderr ---\nerr\n", result.Report("the failing step")
}
