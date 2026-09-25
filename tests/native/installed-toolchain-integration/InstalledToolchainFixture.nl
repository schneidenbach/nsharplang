namespace NSharpLang.InstalledToolchainIntegration.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.IO.Compression
import System.Runtime.Loader
import System.Text
import System.Text.RegularExpressions

// ─── THE INSTALLED TOOLCHAIN, ON A MACHINE THAT HAS NOTHING BUT THE .NET SDK ───────────────────
//
// This project replaces `tests/NSharpLang.IntegrationTests/` — the last C# assertion project in the
// repository: `ToolchainTests.cs` (337 lines, 12 `[DockerFact]` rows), `ToolchainFixture.cs` (170)
// and `DockerFactAttribute.cs` (69). Not one of those rows asserted anything about C#. Every one of
// them packs this checkout, installs the result into a container that holds only
// `mcr.microsoft.com/dotnet/sdk:10.0`, and then reads what `dotnet new`, `nlc` and the launchers do
// there. The claims are about the SHIPPED toolchain, so they move to N# whole.
//
// WHAT THE ROWS PROVE, AND WHY A CONTAINER IS THE ONLY PLACE THEY CAN. A developer's machine has
// `~/.nuget`, a global.json, installed templates and a `nlc` on PATH already; a row that scaffolded
// there would pass on state the user's first command will not have. `Dockerfile.toolchain` — kept
// byte-for-byte from the deleted project — stages the packed packages and the published toolset at
// `/root/.nsharp`, the same install root `scripts/setup-local.sh` and the public installer write,
// registers `/packages` as a source, installs the template package and puts `/root/.nsharp/bin` on
// PATH. That is a FRESH MACHINE, and it is the only honest place to assert a first command.
//
// THE FIXTURE IS PACK-ONCE. The C# fixture was an `IClassFixture`, so xunit built the image and
// started the container once for all twelve rows. The static state below is the same contract: the
// build context (one `dotnet build`, one `dotnet pack` per release package and
// `scripts/publish-toolset.sh`) is produced once per process
// and the container is started once per process, whichever row arrives first.
//
// EVERY RUN OWNS ITS OWN IMAGE AND CONTAINER. Two runs of this project overlap on one machine as a
// matter of course — a product gate in its isolated /tmp tree beside an agent's native sweep, or two
// gates — and one daemon serves them both. A fixed tag and a fixed container name made them fight:
// the second run's `rm --force` killed the first run's container mid-row, and one tag rebuilt under
// another run's feet. So the tag and the name are derived from a per-run id
// (`nsharp-installed-toolchain-integration-<pid>-<utc>-<random>`), and both carry `nsharp.test`
// labels naming the run, its owning process (pid AND start time, so a recycled pid is not mistaken
// for the owner), the host and the creation time — which is what makes a leftover identifiable.
//
// TEARDOWN IS OWNED, NOT HOPED FOR. A `test` block has no per-project teardown hook, so the fixture
// registers one on the process (`ProcessExit`) and on its own load context (`Unloading`, which
// `nlc test` raises when it disposes the collectible scope the rows ran in); either removes the
// container and the per-run image, and a failed build or start removes them on the spot. What a
// SIGKILL still leaves behind is bounded twice over: the container runs a `sleep` that ends and
// `--rm` reaps it, and the next run's reclaim removes leftovers of THIS project whose owner is
// provably gone — never a live run's, whoever that run belongs to.
//
// THE DOCKER GATE IS IN `DockerGate.tests.nl`, and it is the reason a machine without Docker still
// reports these rows: they come back `skipped` with a named reason and a nonzero skip count, never
// silently absent and never green-because-empty.
class ToolchainRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    // What was running, and whether the ceiling killed it. A timeout is reported as exit 124 like
    // `timeout(1)`, but 124 alone with two empty streams told the reader nothing: the report below
    // names the command, the last build step it had started and the last lines it printed.
    CommandLine: string
    TimedOut: bool
    TimeoutMilliseconds: int

    // Every line of both streams in the order they ARRIVED, which is the order a reader of a
    // terminal would have seen them; a BuildKit build writes its progress to stderr and a hang is
    // only legible with stdout interleaved.
    Lines: List<string>

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
        CommandLine = ""
        TimedOut = false
        TimeoutMilliseconds = 0
        Lines = new List<string>()
    }

    // The failure text of the deleted `AssertSuccess`, verbatim: the exit code, then both streams
    // under their own banners, so a red row names the command AND what the container printed
    // without a second run. A run the ceiling killed is reported by `ToolchainTimeoutReport`
    // instead: its streams may be thirty minutes long, and what matters is where it stopped.
    func Report(context: string): string {
        if TimedOut {
            return ToolchainTimeoutReport(context, CommandLine, TimeoutMilliseconds, Lines)
        }

        return context + " failed (exit code " + ExitCode.ToString() + ")\n--- stdout ---\n" + Stdout + "\n--- stderr ---\n" + Stderr
    }
}

// How many trailing lines a timeout report quotes: enough to show the step that hung and what it
// last said, few enough that the report is read rather than scrolled.
func ToolchainTimeoutTailLineCount(): int {
    return 40
}

// The last build step a `docker build` log STARTED, in whichever of the two formats the CLI's
// builder writes — or "" when the log names none (a command that is not a build, or a build killed
// before its first step). BuildKit's plain progress says `#7 [4/5] RUN dotnet new install ...`; its
// `#7 DONE` / `#7 CACHED` / `#7 12.3 <output>` lines are not steps. The legacy builder says
// `Step 4/5 : RUN dotnet new install ...`. Both must read, because which builder runs is not this
// project's choice (see `ToolchainDockerLaunch`).
func ToolchainLastBuildStep(lines: List<string>): string {
    index := lines.Count - 1
    while index >= 0 {
        if Regex.IsMatch(lines[index], "^#[0-9]+ \\[[^\\]]+\\] ") || Regex.IsMatch(lines[index], "^Step [0-9]+/[0-9]+ : ") {
            return lines[index]
        }

        index = index - 1
    }

    return ""
}

func ToolchainTimeoutReport(context: string, commandLine: string, timeoutMilliseconds: int, lines: List<string>): string {
    report := context + " timed out after " + timeoutMilliseconds.ToString() + " ms (exit code 124) and was killed.\n"
    report = report + "--- command ---\n" + commandLine + "\n"
    step := ToolchainLastBuildStep(lines)
    if step != "" {
        report = report + "--- last build step started ---\n" + step + "\n"
    }

    if lines.Count == 0 {
        return report + "--- output ---\n(the command wrote nothing to stdout or stderr before it was killed)"
    }

    first := Math.Max(0, lines.Count - ToolchainTimeoutTailLineCount())
    report = report + "--- last " + (lines.Count - first).ToString() + " of " + lines.Count.ToString() + " output lines (stdout and stderr, in arrival order) ---\n"
    index := first
    while index < lines.Count {
        report = report + lines[index] + "\n"
        index = index + 1
    }

    return report
}

// A child process described declaratively. Arguments are carried as a LIST rather than a command
// line because `docker exec <container> bash -c "<whole script>"` must arrive as four argv entries:
// the script is ONE entry, and a single re-split by an intermediate shell would change what runs.
// `ProcessStartInfo.ArgumentList` is what guarantees that.
class ToolchainLaunch {
    FileName: string
    WorkingDirectory: string
    TimeoutMilliseconds: int
    Arguments: List<string>
    EnvironmentNames: List<string>
    EnvironmentValues: List<string>

    constructor(fileName: string, workingDirectory: string, timeoutMilliseconds: int) {
        FileName = fileName
        WorkingDirectory = workingDirectory
        TimeoutMilliseconds = timeoutMilliseconds
        Arguments = new List<string>()
        EnvironmentNames = new List<string>()
        EnvironmentValues = new List<string>()
    }

    func WithEnvironment(name: string, value: string) {
        EnvironmentNames.Add(name)
        EnvironmentValues.Add(value)
    }
}

// What `docker info` answered, and — when it did not — WHY, in the words the skip reason quotes.
class DockerProbe {
    Available: bool
    Reason: string

    constructor(available: bool, reason: string) {
        Available = available
        Reason = reason
    }
}

// The process's ONE fixture. The lock is held across the pack and the image build: rows of this
// project may run beside each other, and pack-once / start-once must hold for them too.
class ToolchainFixtureState {
    static BuildContextDirectory: string = ""
    static ContextPrepared: bool = false
    static Gate: object = new object()
    static Docker: ToolchainDockerFixture? = null
}

// ─── CEILINGS ─────────────────────────────────────────────────────────────────────────────────
//
// The deleted C# waited forever on `dotnet` and on `bash`, so a hung pack hung CI until the job
// timed out with no attribution. Each ceiling here is generous enough that hitting it means a hang
// rather than a slow machine: the pack step self-emits Compiler Core, and the image build restores
// the template package inside the container.

func ToolchainPackTimeoutMilliseconds(): int {
    return 30 * 60 * 1000
}

func ToolchainImageBuildTimeoutMilliseconds(): int {
    return 30 * 60 * 1000
}

// One container command. `nlc build` of `nsharp-webapi` restores packages inside the container, and
// the quickstart replay starts a web server and polls it for twenty seconds.
func ToolchainExecTimeoutMilliseconds(): int {
    return 15 * 60 * 1000
}

// The probe's own ceiling, kept at the deleted `DockerFactAttribute`'s ten seconds: a daemon that
// cannot answer `docker info` in ten seconds is unavailable for the purposes of these rows.
func ToolchainProbeTimeoutMilliseconds(): int {
    return 10 * 1000
}

// How long the idle container lives if nothing removes it. Long enough for the whole suite on a
// cold machine, short enough that a crashed run leaves nothing behind for the afternoon.
func ToolchainContainerLifetimeSeconds(): int {
    return 7200
}

// One `docker rm`, `docker image rm`, `docker ps` or `docker inspect`. These answer in a second on
// an idle daemon; a minute is what a daemon busy with another run's build may need.
func ToolchainDockerHousekeepingTimeoutMilliseconds(): int {
    return 60 * 1000
}

// A leftover whose owner this machine cannot ask about — it was labelled by a process on another
// host sharing the daemon, or its labels do not parse — is reclaimed only once it is this old. Its
// container stopped itself after `ToolchainContainerLifetimeSeconds`, so a day is generous: no run
// of this project is still using anything that old.
func ToolchainStaleLeftoverAgeSeconds(): long {
    return 24 * 60 * 60
}

// ─── THE PROCESS KERNEL ───────────────────────────────────────────────────────────────────────
//
// Start the child, drain BOTH pipes as tasks BEFORE waiting — that is what keeps a chatty `dotnet
// pack` or `docker build` from deadlocking against a full pipe buffer, and it is the reason the
// deleted fixture read its two streams concurrently — then wait under a ceiling. A timeout kills the
// whole process tree and reports exit 124, so a hung command becomes a failing row with its partial
// output rather than a hung gate.
func ToolchainRunProcess(launch: ToolchainLaunch): ToolchainRun {
    startInfo := new ProcessStartInfo { FileName: launch.FileName }
    startInfo.WorkingDirectory = launch.WorkingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    argumentIndex := 0
    while argumentIndex < launch.Arguments.Count {
        startInfo.ArgumentList.Add(launch.Arguments[argumentIndex])
        argumentIndex = argumentIndex + 1
    }

    environmentIndex := 0
    while environmentIndex < launch.EnvironmentNames.Count {
        startInfo.Environment[launch.EnvironmentNames[environmentIndex]] = launch.EnvironmentValues[environmentIndex]
        environmentIndex = environmentIndex + 1
    }

    capture := new ToolchainOutputCapture()
    process := new Process { StartInfo: startInfo }
    on process.OutputDataReceived (sender, received) => {
        capture.Append(received.Data, false)
    }
    on process.ErrorDataReceived (sender, received) => {
        capture.Append(received.Data, true)
    }

    process.Start()
    process.BeginOutputReadLine()
    process.BeginErrorReadLine()
    commandLine := launch.FileName + " " + ToolchainJoinArguments(launch.Arguments)
    if !process.WaitForExit(launch.TimeoutMilliseconds) {
        process.Kill(true)
        // BOUNDED even here: a grandchild that escaped the tree kill and still holds a pipe must not
        // turn a reported timeout back into a hang. What arrived before the kill is already captured.
        process.WaitForExit(ToolchainProbeTimeoutMilliseconds())
        process.Dispose()
        timedOut := capture.Snapshot(124, commandLine)
        timedOut.TimedOut = true
        timedOut.TimeoutMilliseconds = launch.TimeoutMilliseconds
        timedOut.Stderr = timedOut.Stderr + "\nTimed out after " + launch.TimeoutMilliseconds.ToString() + " ms."
        return timedOut
    }

    // The unbounded wait is what drains the asynchronous readers to end-of-stream once the process
    // has exited, exactly as reading both streams to the end did.
    process.WaitForExit()
    exitCode := process.ExitCode
    process.Dispose()
    return capture.Snapshot(exitCode, commandLine)
}

// Both pipes, drained line by line AS THEY ARRIVE rather than read to the end after the fact. That
// is the difference between a timeout that says where it stopped and one that says nothing: a
// `ReadToEndAsync` that has not completed when the ceiling fires has returned no text at all.
class ToolchainOutputCapture {
    gate: object
    stdout: StringBuilder
    stderr: StringBuilder
    lines: List<string>

    constructor() {
        gate = new object()
        stdout = new StringBuilder()
        stderr = new StringBuilder()
        lines = new List<string>()
    }

    // `null` is the reader's end-of-stream signal, not a line.
    func Append(line: string?, fromStderr: bool) {
        if line == null {
            return
        }

        text := line ?? ""
        lock gate {
            if fromStderr {
                stderr.Append(text).Append('\n')
            } else {
                stdout.Append(text).Append('\n')
            }

            lines.Add(text)
        }
    }

    func Snapshot(exitCode: int, commandLine: string): ToolchainRun {
        lock gate {
            run := new ToolchainRun(exitCode, stdout.ToString(), stderr.ToString())
            run.CommandLine = commandLine
            run.Lines.AddRange(lines)
            return run
        }
    }
}

// ─── THE REPOSITORY ───────────────────────────────────────────────────────────────────────────
//
// `nlc test` hosts the emitted tests inside the CLI's own process, so `AppContext.BaseDirectory` is
// a directory inside the repository and the upward walk for `NSharpLang.sln` finds the root — the
// same anchor, and the same failure sentence, as the deleted `FindRepoRoot`.
func ToolchainRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "templates")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not find repository root (NSharpLang.sln). Searched upward from " + AppContext.BaseDirectory + ".")
}

// The Dockerfile kept from the deleted project, in its new home beside the rows that use it. It is
// the ONLY description of the fresh machine these rows assert against, so both the fixture that
// copies it into the build context and the row that reads its text name it from here.
func ToolchainDockerfilePath(): string {
    return Path.Combine(
        Path.Combine(Path.Combine(Path.Combine(ToolchainRepositoryRoot(), "tests"), "native"), "installed-toolchain-integration"),
        "Dockerfile.toolchain"
    )
}

func ToolchainQuote(value: string): string {
    return "\"" + value.Replace("\"", "\\\"") + "\""
}

func ToolchainJoinArguments(values: List<string>): string {
    return string.Join(" ", values)
}

// ─── THE DOCKER COMMAND LINES, AS VALUES ──────────────────────────────────────────────────────
//
// Every `docker` invocation this project makes is BUILT by one of the functions below and by nothing
// else, so the argv that reaches the daemon is a value a row can read. That is what lets a machine
// with no Docker still hold this project's Docker half to a contract: the rows in
// `ToolchainCommandContracts.tests.nl` assert these argument lists directly. A command line spelled
// inline at its call site would be unassertable, and the flags here are exactly the ones whose drift
// would be invisible until CI ran.

// `docker info --format {{json .ServerVersion}}` — the deleted `DockerFactAttribute.ProbeDocker`
// command, unchanged. The format argument makes the answer small; only the EXIT CODE is read.
func DockerInfoArguments(): List<string> {
    arguments := new List<string>()
    arguments.Add("info")
    arguments.Add("--format")
    arguments.Add("{{json .ServerVersion}}")
    return arguments
}

// ─── ONE RUN'S IDENTITY ────────────────────────────────────────────────────────────────────────
//
// Every image and container this project creates is named from this prefix and a run id, and is
// labelled `nsharp.test=installed-toolchain-integration`. The prefix is what a human reads in
// `docker ps`; the label is what the reclaim below trusts, because a NAME can be chosen by anyone.
func DockerResourcePrefix(): string {
    return "nsharp-installed-toolchain-integration-"
}

func DockerTestLabelKey(): string {
    return "nsharp.test"
}

func DockerTestLabelValue(): string {
    return "installed-toolchain-integration"
}

func DockerRunLabelKey(): string {
    return "nsharp.test.run"
}

func DockerOwnerPidLabelKey(): string {
    return "nsharp.test.owner-pid"
}

func DockerOwnerStartedLabelKey(): string {
    return "nsharp.test.owner-started"
}

func DockerOwnerHostLabelKey(): string {
    return "nsharp.test.owner-host"
}

func DockerCreatedLabelKey(): string {
    return "nsharp.test.created"
}

// Who owns one run's image and container. The OWNER is the process hosting the rows, named by pid
// AND by its start time: a pid alone is recycled, and a leftover whose pid now belongs to some
// unrelated process must still read as orphaned.
class ToolchainDockerRun {
    RunId: string
    OwnerPid: int
    OwnerStartedUnixSeconds: long
    OwnerHost: string
    CreatedUnixSeconds: long
    ContainerName: string
    ImageTag: string

    constructor(runId: string, ownerPid: int, ownerStartedUnixSeconds: long, ownerHost: string, createdUnixSeconds: long) {
        RunId = runId
        OwnerPid = ownerPid
        OwnerStartedUnixSeconds = ownerStartedUnixSeconds
        OwnerHost = ownerHost
        CreatedUnixSeconds = createdUnixSeconds
        ContainerName = DockerResourcePrefix() + runId
        ImageTag = ContainerName + ":local"
    }
}

// A run id is `<pid>-<utc yyyymmddThhmmss>-<6 hex>`: the pid and the time make a leftover readable
// at a glance, and the random tail is what keeps two fixtures created by ONE process in the same
// second apart. Lowercase throughout, because an image repository name must be.
func ToolchainNewRunId(pid: int, utcNow: DateTime): string {
    return pid.ToString() + "-" + utcNow.ToString("yyyyMMdd't'HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 6)
}

func ToolchainUnixSeconds(instant: DateTime): long {
    return new DateTimeOffset(instant.ToUniversalTime()).ToUnixTimeSeconds()
}

// The run this process owns. The start time is read through the same API the liveness check reads
// it through, so the two agree to the second on the same process.
func ToolchainNewDockerRun(): ToolchainDockerRun {
    pid := Environment.ProcessId
    current := Process.GetCurrentProcess()
    started := ToolchainUnixSeconds(current.StartTime)
    current.Dispose()
    now := DateTime.UtcNow
    return new ToolchainDockerRun(ToolchainNewRunId(pid, now), pid, started, Environment.MachineName, ToolchainUnixSeconds(now))
}

// `--label key=value` for every ownership label, on the image AND on the container: the container
// would inherit the image's, but a container is what a reader lists first and it must not depend on
// how the image it came from was built.
func DockerLabelArguments(run: ToolchainDockerRun): List<string> {
    arguments := new List<string>()
    arguments.Add("--label")
    arguments.Add(DockerTestLabelKey() + "=" + DockerTestLabelValue())
    arguments.Add("--label")
    arguments.Add(DockerRunLabelKey() + "=" + run.RunId)
    arguments.Add("--label")
    arguments.Add(DockerOwnerPidLabelKey() + "=" + run.OwnerPid.ToString())
    arguments.Add("--label")
    arguments.Add(DockerOwnerStartedLabelKey() + "=" + run.OwnerStartedUnixSeconds.ToString())
    arguments.Add("--label")
    arguments.Add(DockerOwnerHostLabelKey() + "=" + run.OwnerHost)
    arguments.Add("--label")
    arguments.Add(DockerCreatedLabelKey() + "=" + run.CreatedUnixSeconds.ToString())
    return arguments
}

// `--file` is passed explicitly because the Dockerfile is named `Dockerfile.toolchain`, exactly as
// the deleted fixture's `WithDockerfile("Dockerfile.toolchain")` did, and the build context is the
// staged directory rather than the repository.
//
// EVERY FLAG HERE IS ONE BOTH BUILDERS ACCEPT. `docker build` is BuildKit only when the CLI finds
// its buildx plugin, which lives under `~/.docker/cli-plugins` — and the product gate runs with HOME
// pointed at a throwaway directory, where there is no plugin and the CLI falls back to the legacy
// builder. A `--progress plain` here made that builder refuse the whole command (`unknown flag`,
// exit 125) and failed every Docker row. The progress mode travels in the environment instead
// (`ToolchainDockerLaunch`), which BuildKit reads and the legacy builder ignores.
func DockerBuildArguments(run: ToolchainDockerRun, buildContextDirectory: string): List<string> {
    arguments := new List<string>()
    arguments.Add("build")
    arguments.Add("--file")
    arguments.Add(Path.Combine(buildContextDirectory, "Dockerfile.toolchain"))
    arguments.Add("--tag")
    arguments.Add(run.ImageTag)
    arguments.AddRange(DockerLabelArguments(run))
    arguments.Add(buildContextDirectory)
    return arguments
}

// `--detach --rm` plus a bounded `sleep` is the backstop teardown for a run that dies without its
// own. The `sleep` must REPLACE the image's entrypoint, not follow it: the Dockerfile's
// `ENTRYPOINT ["tail", "-f", "/dev/null"]` takes trailing arguments as more files to follow, so
// `<image> sleep 7200` ran `tail -f /dev/null sleep 7200` — forever — and the orphaned container a
// killed gate left behind never removed itself.
func DockerRunArguments(run: ToolchainDockerRun): List<string> {
    arguments := new List<string>()
    arguments.Add("run")
    arguments.Add("--detach")
    arguments.Add("--rm")
    arguments.Add("--name")
    arguments.Add(run.ContainerName)
    arguments.AddRange(DockerLabelArguments(run))
    arguments.Add("--entrypoint")
    arguments.Add("sleep")
    arguments.Add(run.ImageTag)
    arguments.Add(ToolchainContainerLifetimeSeconds().ToString())
    return arguments
}

// `docker exec <container> bash -c <command>` — the four argv entries the deleted
// `_fixture.Container.ExecAsync(["bash", "-c", command])` produced, with the command as ONE entry.
func DockerExecArguments(run: ToolchainDockerRun, command: string): List<string> {
    arguments := new List<string>()
    arguments.Add("exec")
    arguments.Add(run.ContainerName)
    arguments.Add("bash")
    arguments.Add("-c")
    arguments.Add(command)
    return arguments
}

// The two halves of a run's teardown, each by the run's OWN name, so neither can reach another run.
func DockerRemoveContainerArguments(containerReference: string): List<string> {
    arguments := new List<string>()
    arguments.Add("rm")
    arguments.Add("--force")
    arguments.Add(containerReference)
    return arguments
}

func DockerRemoveImageArguments(imageReference: string): List<string> {
    arguments := new List<string>()
    arguments.Add("image")
    arguments.Add("rm")
    arguments.Add("--force")
    arguments.Add(imageReference)
    return arguments
}

// Every container and every image carrying this project's label, by full id — running or not, this
// run's or another's. What to DO with each is `DockerReclaimDecisionFor`'s question, not the filter's.
func DockerListLabelledContainersArguments(): List<string> {
    arguments := new List<string>()
    arguments.Add("ps")
    arguments.Add("--all")
    arguments.Add("--quiet")
    arguments.Add("--no-trunc")
    arguments.Add("--filter")
    arguments.Add("label=" + DockerTestLabelKey() + "=" + DockerTestLabelValue())
    return arguments
}

func DockerListLabelledImagesArguments(): List<string> {
    arguments := new List<string>()
    arguments.Add("image")
    arguments.Add("ls")
    arguments.Add("--quiet")
    arguments.Add("--no-trunc")
    arguments.Add("--filter")
    arguments.Add("label=" + DockerTestLabelKey() + "=" + DockerTestLabelValue())
    return arguments
}

// One tab-separated line per object: its id, then the five ownership labels in a fixed order. Both
// `container inspect` and `image inspect` expose `.Config.Labels`, so one format reads both, and a
// label that is absent reads as an empty field rather than failing the template.
func DockerLeftoverInspectFormat(): string {
    return "{{.Id}}\t{{index .Config.Labels \"" + DockerRunLabelKey() + "\"}}\t{{index .Config.Labels \"" + DockerOwnerPidLabelKey() + "\"}}\t{{index .Config.Labels \"" + DockerOwnerStartedLabelKey() + "\"}}\t{{index .Config.Labels \"" + DockerOwnerHostLabelKey() + "\"}}\t{{index .Config.Labels \"" + DockerCreatedLabelKey() + "\"}}"
}

// `kind` is `container` or `image`.
func DockerInspectLeftoversArguments(kind: string, ids: List<string>): List<string> {
    arguments := new List<string>()
    arguments.Add(kind)
    arguments.Add("inspect")
    arguments.Add("--format")
    arguments.Add(DockerLeftoverInspectFormat())
    arguments.AddRange(ids)
    return arguments
}

// ─── THE BUILD-CONTEXT COMMAND LINES, AS VALUES ───────────────────────────────────────────────
//
// The pack/build commands of the deleted `ToolchainFixture.InitializeAsync`, in its order, over the
// package set the release path ships.
// `--disable-build-servers` is on every one because a leaked MSBuild node outlives the run and
// `-v q` is what keeps a 30-minute pack out of the test log.

func ToolchainBuildTasksArguments(): List<string> {
    arguments := new List<string>()
    arguments.Add("build")
    arguments.Add("src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj")
    arguments.Add("-c")
    arguments.Add("Release")
    arguments.Add("--disable-build-servers")
    arguments.Add("-v")
    arguments.Add("q")
    return arguments
}

func ToolchainPackArguments(projectPath: string, outputDirectory: string): List<string> {
    arguments := new List<string>()
    arguments.Add("pack")
    arguments.Add(projectPath)
    arguments.Add("-c")
    arguments.Add("Release")
    arguments.Add("-o")
    arguments.Add(outputDirectory)
    arguments.Add("--disable-build-servers")
    arguments.Add("-v")
    arguments.Add("q")
    return arguments
}

// THE SYMBOL REPAIR, AND THE DEFECT THE DELETED FIXTURE CARRIED. Direct N# IL emission writes no
// `.pdb`, but the base SDK defaults `DebugType` to `portable` and pack then demands the file the
// emitter never wrote — NU5026. `scripts/lib/packages.sh`, the release path CI's `pack-nuget.sh`
// runs, therefore passes these two flags for EVERY N# project it packs (the compiler facade and each
// slice carved out of Core) and for none of the others.
//
// `ToolchainFixture.cs` passed them for `NSharpLang.Compiler.Core` and NOT for
// `NSharpLang.Compiler`. That is the whole of CI run 35806417973: `error NU5026: The file
// '.../Compiler.pdb' to be packed was not found on disk`, thrown before any row ran, taking all
// twelve with it. Reproducing it was the first thing this row did on a machine with no Docker at
// all, so the port fixes it by AGREEING WITH THE RELEASE PATH rather than by carrying the deleted
// fixture's disagreement forward.
//
// Nothing is hidden by the repair: `tests/native/sdk-pack-symbol-contract` packs N#-SDK projects
// with a BARE `dotnet pack` and holds the declaration that will retire it, and the row in
// `ToolchainCommandContracts.tests.nl` reads the predicate out of `scripts/lib/packages.sh` and
// requires this set to equal it.
func ToolchainPackCompilerPackageArguments(projectPath: string, outputDirectory: string): List<string> {
    arguments := new List<string>()
    arguments.Add("pack")
    arguments.Add(projectPath)
    arguments.Add("-c")
    arguments.Add("Release")
    arguments.Add("-o")
    arguments.Add(outputDirectory)
    arguments.Add("--disable-build-servers")
    arguments.Add("-p:DebugSymbols=false")
    arguments.Add("-p:DebugType=None")
    arguments.Add("-v")
    arguments.Add("q")
    return arguments
}

// ─── THE RELEASE PACKAGE SET, READ FROM ITS ONE OWNER ─────────────────────────────────────────
//
// `NSHARP_PACKAGE_SPECS` in `scripts/lib/packages.sh` is the set `scripts/pack-nuget.sh`, CI's
// release step and `scripts/publish-toolset.sh` pack, and this fixture packs EXACTLY that set, read
// out of the script rather than restated here. It is not a formality: `dotnet pack` of an N# project
// turns every `project:` dependency into a nuspec `<dependency>`, so `NSharpLang.Compiler` requires
// `NSharpLang.Compiler.Core`, which requires every slice carved out of it. A fixture that kept its
// own list packed Core and Compiler only after the Model and Syntax carves, and the context it
// staged was a feed in which `NSharpLang.Compiler` does not restore. The row in
// `ToolchainCommandContracts.tests.nl` holds the owner itself to the compiler's `project:` graph.
class ToolchainPackageSpec {
    PackageId: string
    Project: string

    constructor(packageId: string, project: string) {
        PackageId = packageId
        Project = project
    }
}

// The release path's own set, read as text so this fixture cannot drift from it silently.
func ToolchainPackagesScriptPath(): string {
    return Path.Combine(Path.Combine(Path.Combine(ToolchainRepositoryRoot(), "scripts"), "lib"), "packages.sh")
}

func ToolchainReleasePackageSpecs(): List<ToolchainPackageSpec> {
    script := File.ReadAllText(ToolchainPackagesScriptPath())
    array := Regex.Match(script, "NSHARP_PACKAGE_SPECS=\\((?<body>[^)]*)\\)")
    if !array.Success {
        throw new InvalidOperationException("Could not find NSHARP_PACKAGE_SPECS in scripts/lib/packages.sh.")
    }

    specs := new List<ToolchainPackageSpec>()
    body := array.Groups["body"].Value
    entries := Regex.Matches(body, "\"(?<id>[^|\"]+)\\|[^|\"]*\\|(?<project>[^|\"]+)\"")
    index := 0
    while index < entries.Count {
        specs.Add(new ToolchainPackageSpec(entries[index].Groups["id"].Value, entries[index].Groups["project"].Value))
        index = index + 1
    }

    if specs.Count == 0 {
        throw new InvalidOperationException("NSHARP_PACKAGE_SPECS in scripts/lib/packages.sh names no package.")
    }

    return specs
}

func ToolchainReleasePackageIds(): List<string> {
    ids := new List<string>()
    for spec in ToolchainReleasePackageSpecs() {
        ids.Add(spec.PackageId)
    }

    return ids
}

// `nsharp_package_emits_no_symbols`, the release path's predicate: a project whose directory holds
// `project.yml` is an N# project, written by the emitter that has no symbol writer.
func ToolchainPackageEmitsNoSymbols(project: string): bool {
    projectDirectory := Path.GetDirectoryName(Path.Combine(ToolchainRepositoryRoot(), project)) ?? ""
    return File.Exists(Path.Combine(projectDirectory, "project.yml"))
}

// The runtime is packed FIRST, as the release path packs it (its "bootstrap package"), because the
// compiler packages declare it as a dependency.
func ToolchainRuntimePackageProject(): string {
    return "src/NSharpLang.Runtime/NSharpLang.Runtime.csproj"
}

// The N# projects of the release set, in its order (lowest slice first), each packed with the
// symbol repair.
func ToolchainCompilerPackageProjects(): List<string> {
    projects := new List<string>()
    for spec in ToolchainReleasePackageSpecs() {
        if ToolchainPackageEmitsNoSymbols(spec.Project) {
            projects.Add(spec.Project)
        }
    }

    return projects
}

// Every other project of the release set, packed with nothing on the command line: the runtime
// first, then the rest in the release set's order.
func ToolchainPlainPackageProjects(): List<string> {
    projects := new List<string>()
    projects.Add(ToolchainRuntimePackageProject())
    for spec in ToolchainReleasePackageSpecs() {
        if !ToolchainPackageEmitsNoSymbols(spec.Project) && spec.Project != ToolchainRuntimePackageProject() {
            projects.Add(spec.Project)
        }
    }

    return projects
}

// Every `NSharpLang.*` dependency a staged package's nuspec declares that the staged feed cannot
// satisfy, as `package -> dependency version`. A fresh machine restores through exactly these edges,
// so an empty answer is what "the feed is complete" means, whatever the set is called this week.
func ToolchainUnresolvedPackageDependencies(packagesDirectory: string): List<string> {
    unresolved := new List<string>()
    for packagePath in Directory.GetFiles(packagesDirectory, "*.nupkg") {
        archive := ZipFile.OpenRead(packagePath)
        nuspec := ""
        for entry in archive.Entries {
            if entry.FullName.EndsWith(".nuspec") {
                reader := new StreamReader(entry.Open())
                nuspec = reader.ReadToEnd()
                reader.Dispose()
            }
        }

        archive.Dispose()
        dependencies := Regex.Matches(nuspec, "<dependency id=\"(?<id>NSharpLang\\.[^\"]+)\" version=\"(?<version>[^\"]+)\"")
        index := 0
        while index < dependencies.Count {
            id := dependencies[index].Groups["id"].Value
            version := dependencies[index].Groups["version"].Value
            if !File.Exists(Path.Combine(packagesDirectory, id + "." + version + ".nupkg")) {
                unresolved.Add(Path.GetFileName(packagePath) + " -> " + id + " " + version)
            }

            index = index + 1
        }
    }

    return unresolved
}

// `--skip-packages` because the packs above already produced them, and `--skip-archive` because the
// container consumes a DIRECTORY rather than the tar.gz the release path ships.
func ToolchainPublishToolsetCommand(toolsetDirectory: string, packagesDirectory: string): string {
    return "./scripts/publish-toolset.sh --output " + ToolchainQuote(toolsetDirectory) + " --packages " + ToolchainQuote(packagesDirectory) + " --skip-packages --skip-archive"
}

// ─── RUNNING THEM ─────────────────────────────────────────────────────────────────────────────

func ToolchainRunDotnet(arguments: List<string>): ToolchainRun {
    launch := new ToolchainLaunch("dotnet", ToolchainRepositoryRoot(), ToolchainPackTimeoutMilliseconds())
    index := 0
    while index < arguments.Count {
        launch.Arguments.Add(arguments[index])
        index = index + 1
    }

    launch.WithEnvironment("DOTNET_NOLOGO", "1")
    return ToolchainRunProcess(launch)
}

// One `docker` invocation as a value. `BUILDKIT_PROGRESS=plain` is how a BuildKit build is told to
// log one line per event whatever the terminal — what the timeout report reads its last step out of
// — without a flag the legacy builder would refuse; every other command ignores it. The builder is
// deliberately NOT chosen here: which one `docker build` reaches depends on the CLI's plugins and
// `DOCKER_BUILDKIT`, and the argv above runs unchanged under either.
func ToolchainDockerLaunch(arguments: List<string>, timeoutMilliseconds: int): ToolchainLaunch {
    launch := new ToolchainLaunch("docker", ToolchainRepositoryRoot(), timeoutMilliseconds)
    launch.Arguments.AddRange(arguments)
    launch.WithEnvironment("BUILDKIT_PROGRESS", "plain")
    return launch
}

func ToolchainRunDocker(arguments: List<string>, timeoutMilliseconds: int): ToolchainRun {
    return ToolchainRunProcess(ToolchainDockerLaunch(arguments, timeoutMilliseconds))
}

func ToolchainRequireSuccess(result: ToolchainRun, context: string) {
    if result.ExitCode != 0 {
        throw new InvalidOperationException(result.Report(context))
    }
}

// ─── THE DOCKER PROBE ─────────────────────────────────────────────────────────────────────────
//
// A faithful port of `DockerFactAttribute.ProbeDocker`, including which failure says what: a missing
// CLI, a timeout and a nonzero exit are three different reasons and the skip message quotes the one
// that happened. The deleted C# caught `Win32Exception`/`InvalidOperationException` for "docker CLI
// not found"; the kernel above surfaces the same condition as a thrown start failure, so the catch
// here is what turns it into that reason.
func ProbeDocker(): DockerProbe {
    // The repository walk is OUTSIDE the try. It can throw for a reason that has nothing to do with
    // Docker, and reporting "docker CLI not found" for a checkout this assembly cannot locate would
    // send a reader looking in the wrong place.
    workingDirectory := ToolchainRepositoryRoot()
    try {
        launch := new ToolchainLaunch("docker", workingDirectory, ToolchainProbeTimeoutMilliseconds())
        index := 0
        arguments := DockerInfoArguments()
        while index < arguments.Count {
            launch.Arguments.Add(arguments[index])
            index = index + 1
        }

        result := ToolchainRunProcess(launch)
        if result.ExitCode == 124 {
            return new DockerProbe(false, "`docker info` timed out after 10 seconds")
        }

        if result.ExitCode == 0 {
            return new DockerProbe(true, "")
        }

        stderr := result.Stderr.Trim()
        if stderr == "" {
            return new DockerProbe(false, "`docker info` exited " + result.ExitCode.ToString())
        }

        return new DockerProbe(false, stderr)
    } catch startFailure: Exception {
        return new DockerProbe(false, "docker CLI not found or not executable")
    }
}

// ─── THE BUILD CONTEXT ────────────────────────────────────────────────────────────────────────

// The deleted fixture's directory prefix, kept, because the sweep below has to recognise contexts
// this project left behind before it was rewritten.
func ToolchainBuildContextPrefix(): string {
    return "nsharp-integration-"
}

// A context holds the release package set and a published toolset. The process that staged it
// removes it on exit, but a process that is KILLED runs no handler, so each run also sweeps the ones
// EARLIER runs left, which bounds that leak to what a day of killed runs leaves.
//
// ONLY DIRECTORIES A DAY OLD, and only best-effort. A newer one may belong to a run happening right
// now in another worktree — this project is serial within one gate, not across machines-worth of
// them — and deleting that would break a run rather than tidy after one. A directory that resists
// deletion is skipped for the same reason the container's reclaim ignores its own failure: cleanup
// must never turn a passing contract into a failing row.
// One directory, deleted if it can be. The catch RETURNS rather than sitting empty: an empty catch
// is NL011, and `nlc format` relocates a `// nlc:ignore` written above a `} catch` line to the end
// of the file, which would silently destroy the suppression.
func DeleteBuildContextDirectory(directory: string) {
    try {
        Directory.Delete(directory, true)
    } catch deleteFailure: Exception {
        return
    }
}

func SweepStaleBuildContexts() {
    try {
        cutoff := DateTime.UtcNow.AddDays(-1)
        candidates := Directory.GetDirectories(Path.GetTempPath(), ToolchainBuildContextPrefix() + "*")
        index := 0
        while index < candidates.Length {
            if Directory.GetLastWriteTimeUtc(candidates[index]) < cutoff {
                DeleteBuildContextDirectory(candidates[index])
            }

            index = index + 1
        }
    } catch sweepFailure: Exception {
        return
    }
}
//
// One `dotnet build`, one `dotnet pack` per release package and one `bash` command, into a throwaway
// directory holding `packages/`, `toolset/` and the Dockerfile. NOTHING here needs Docker, which is
// why it is a function of its own: the row that proves it runs on a machine with no daemon at all.
func ToolchainPrepareBuildContext(): string {
    lock ToolchainFixtureState.Gate {
        if !ToolchainFixtureState.ContextPrepared {
            ToolchainFixtureState.BuildContextDirectory = toolchainStageBuildContext()
            ToolchainFixtureState.ContextPrepared = true
        }

        return ToolchainFixtureState.BuildContextDirectory
    }
}

// The staging itself, run once per process under the fixture's lock. The directory is removed when
// the process exits, like the image made from it; the sweep above covers a process that could not.
func toolchainStageBuildContext(): string {
    repositoryRoot := ToolchainRepositoryRoot()
    SweepStaleBuildContexts()
    buildContextDirectory := Path.Combine(Path.GetTempPath(), ToolchainBuildContextPrefix() + Guid.NewGuid().ToString("N").Substring(0, 12))
    Directory.CreateDirectory(buildContextDirectory)
    on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
        DeleteBuildContextDirectory(buildContextDirectory)
    }

    packagesDirectory := Path.Combine(buildContextDirectory, "packages")
    Directory.CreateDirectory(packagesDirectory)

    // The tasks project first: the SDK pack depends on its output binaries.
    ToolchainRequireSuccess(ToolchainRunDotnet(ToolchainBuildTasksArguments()), "dotnet build of NSharpLang.Build.Tasks")

    // The deleted fixture's ORDER, preserved: the runtime, then the N# packages lowest slice first,
    // then the SDK and the templates. The SDK pack MSBuilds Build.Tasks for its `tools/` payload, so
    // it follows the explicit Build.Tasks build above rather than preceding it.
    ToolchainRequireSuccess(
        ToolchainRunDotnet(ToolchainPackArguments(ToolchainRuntimePackageProject(), packagesDirectory)),
        "dotnet pack of " + ToolchainRuntimePackageProject()
    )
    for compilerProject in ToolchainCompilerPackageProjects() {
        ToolchainRequireSuccess(
            ToolchainRunDotnet(ToolchainPackCompilerPackageArguments(compilerProject, packagesDirectory)),
            "dotnet pack of " + compilerProject
        )
    }

    for plainProject in ToolchainPlainPackageProjects() {
        if plainProject != ToolchainRuntimePackageProject() {
            ToolchainRequireSuccess(
                ToolchainRunDotnet(ToolchainPackArguments(plainProject, packagesDirectory)),
                "dotnet pack of " + plainProject
            )
        }
    }

    // `bash -lc`, a LOGIN shell, because the publisher sources profile files — the shell the deleted
    // fixture proved it under. `MSBUILDDISABLENODEREUSE=1` is load-bearing and not hygiene: a reused
    // MSBuild node inherits the redirected pipes and the stream reads never complete after the
    // publishing shell exits.
    toolsetDirectory := Path.Combine(buildContextDirectory, "toolset")
    publishLaunch := new ToolchainLaunch("bash", repositoryRoot, ToolchainPackTimeoutMilliseconds())
    publishLaunch.Arguments.Add("-lc")
    publishLaunch.Arguments.Add(ToolchainPublishToolsetCommand(toolsetDirectory, packagesDirectory))
    publishLaunch.WithEnvironment("MSBUILDDISABLENODEREUSE", "1")
    publishLaunch.WithEnvironment("DOTNET_NOLOGO", "1")
    ToolchainRequireSuccess(ToolchainRunProcess(publishLaunch), "scripts/publish-toolset.sh")

    File.Copy(ToolchainDockerfilePath(), Path.Combine(buildContextDirectory, "Dockerfile.toolchain"), true)
    return buildContextDirectory
}

// ─── THE HOST SEAM ────────────────────────────────────────────────────────────────────────────
//
// The fixture reaches the daemon and the process table through this and nothing else, so its
// lifecycle — reclaim, build, start, teardown on every path — is a contract a machine with no Docker
// can hold to rows (`DockerIsolation.tests.nl`) with a recording host in place of this one.
interface IToolchainDockerHost {
    func Docker(arguments: List<string>, timeoutMilliseconds: int): ToolchainRun

    func OwnerAlive(pid: int, startedUnixSeconds: long): bool
}

class ProcessDockerHost: IToolchainDockerHost {
    func Docker(arguments: List<string>, timeoutMilliseconds: int): ToolchainRun {
        return ToolchainRunDocker(arguments, timeoutMilliseconds)
    }

    func OwnerAlive(pid: int, startedUnixSeconds: long): bool {
        return ToolchainOwnerProcessAlive(pid, startedUnixSeconds)
    }
}

// Is the process that labelled a leftover still the process with that pid? No process with the pid
// is a NO. A process whose start time differs from the label's is a NO too — the pid was recycled.
// A process this user may not inspect is a YES: when ownership cannot be disproved, the leftover is
// someone's and stays.
func ToolchainOwnerProcessAlive(pid: int, startedUnixSeconds: long): bool {
    try {
        process := Process.GetProcessById(pid)
        try {
            return Math.Abs(ToolchainUnixSeconds(process.StartTime) - startedUnixSeconds) <= 2
        } finally {
            process.Dispose()
        }
    } catch missing: ArgumentException {
        return false
    } catch unknowable: Exception {
        return true
    }
}

// ─── WHAT A LEFTOVER IS, AND WHEN IT MAY BE TAKEN ─────────────────────────────────────────────

// One labelled container or image, as `DockerLeftoverInspectFormat` prints it. A label that is
// absent or does not parse reads as `-1` / "", which `DockerReclaimDecisionFor` treats as "cannot
// prove the owner is gone".
class DockerLeftover {
    Kind: string
    Id: string
    RunId: string
    OwnerPid: int
    OwnerStartedUnixSeconds: long
    OwnerHost: string
    CreatedUnixSeconds: long

    constructor(kind: string, id: string, runId: string, ownerPid: int, ownerStartedUnixSeconds: long, ownerHost: string, createdUnixSeconds: long) {
        Kind = kind
        Id = id
        RunId = runId
        OwnerPid = ownerPid
        OwnerStartedUnixSeconds = ownerStartedUnixSeconds
        OwnerHost = ownerHost
        CreatedUnixSeconds = createdUnixSeconds
    }
}

func ToolchainParseLabelInt(value: string): int {
    parsed := 0
    if int.TryParse(value, out parsed) {
        return parsed
    }

    return -1
}

func ToolchainParseLabelLong(value: string): long {
    parsed: long = 0
    if long.TryParse(value, out parsed) {
        return parsed
    }

    return -1
}

func ToolchainParseDockerLeftovers(kind: string, inspectOutput: string): List<DockerLeftover> {
    leftovers := new List<DockerLeftover>()
    for line in inspectOutput.Split('\n') {
        fields := line.TrimEnd('\r').Split('\t')
        if fields.Length == 6 && fields[0].Trim() != "" {
            leftovers.Add(new DockerLeftover(
                kind,
                fields[0].Trim(),
                fields[1],
                ToolchainParseLabelInt(fields[2]),
                ToolchainParseLabelLong(fields[3]),
                fields[4],
                ToolchainParseLabelLong(fields[5])
            ))
        }
    }

    return leftovers
}

class DockerReclaimDecision {
    Reclaim: bool
    Reason: string

    constructor(reclaim: bool, reason: string) {
        Reclaim = reclaim
        Reason = reason
    }
}

// THE WHOLE RECLAIM RULE, as a function of values. A leftover is taken only when its owner is
// PROVABLY gone: labelled by a process on THIS host whose pid is no longer that process, or so old
// that no run of this project can still be using it. Everything else — this run's own objects, a
// live owner, an owner on another host sharing the daemon, labels that do not parse — stays.
// `ownerAlive` is the host's answer for the leftover's pid and start time; it is consulted only
// when the leftover names this host.
func DockerReclaimDecisionFor(leftover: DockerLeftover, currentRunId: string, localHost: string, ownerAlive: bool, nowUnixSeconds: long, maxAgeSeconds: long): DockerReclaimDecision {
    if leftover.RunId == currentRunId {
        return new DockerReclaimDecision(false, "belongs to this run")
    }

    ownerKnown := leftover.OwnerHost == localHost && leftover.OwnerPid > 0 && leftover.OwnerStartedUnixSeconds > 0
    if ownerKnown && ownerAlive {
        return new DockerReclaimDecision(false, "owner pid " + leftover.OwnerPid.ToString() + " is still running")
    }

    if ownerKnown {
        return new DockerReclaimDecision(true, "owner pid " + leftover.OwnerPid.ToString() + " on " + localHost + " is no longer running")
    }

    if leftover.CreatedUnixSeconds > 0 && nowUnixSeconds - leftover.CreatedUnixSeconds > maxAgeSeconds {
        return new DockerReclaimDecision(true, "created " + (nowUnixSeconds - leftover.CreatedUnixSeconds).ToString() + " s ago, past the " + maxAgeSeconds.ToString() + " s limit")
    }

    return new DockerReclaimDecision(false, "owner cannot be checked from this host and the leftover is not yet " + maxAgeSeconds.ToString() + " s old")
}

// ─── THE FIXTURE ──────────────────────────────────────────────────────────────────────────────

// One run's image and container, from reclaim to teardown. Every path out of `Start` that did not
// leave a running container removes what it made; `Teardown` is idempotent and never throws, because
// it runs from process-exit and unload handlers where a throw would be lost or fatal.
class ToolchainDockerFixture {
    Run: ToolchainDockerRun
    Host: IToolchainDockerHost
    Started: bool
    StartFailure: string
    TornDown: bool
    Reclaimed: List<string>
    gate: object

    constructor(run: ToolchainDockerRun, host: IToolchainDockerHost) {
        Run = run
        Host = host
        Started = false
        StartFailure = ""
        TornDown = false
        Reclaimed = new List<string>()
        gate = new object()
    }

    // A failed start is REMEMBERED, not retried: a thirty-minute build that timed out once would
    // time out again for each of the twelve rows behind it, and each row would report the same
    // cause. Every later row fails at once with the first failure's report.
    func Start(buildContextDirectory: string) {
        lock gate {
            if Started {
                return
            }

            if StartFailure != "" {
                throw new InvalidOperationException("the container for this run failed to start earlier and is not retried:\n" + StartFailure)
            }

            if TornDown {
                throw new InvalidOperationException("the Docker fixture for run " + Run.RunId + " was already torn down")
            }

            ReclaimStale(ToolchainUnixSeconds(DateTime.UtcNow))
            try {
                ToolchainRequireSuccess(
                    Host.Docker(DockerBuildArguments(Run, buildContextDirectory), ToolchainImageBuildTimeoutMilliseconds()),
                    "docker build of " + Run.ImageTag
                )
                ToolchainRequireSuccess(
                    Host.Docker(DockerRunArguments(Run), ToolchainImageBuildTimeoutMilliseconds()),
                    "docker run of " + Run.ContainerName
                )
                Started = true
            } catch startFailure: Exception {
                StartFailure = startFailure.Message
                Teardown()
                throw
            }
        }
    }

    func Exec(command: string): ToolchainRun {
        return Host.Docker(DockerExecArguments(Run, command), ToolchainExecTimeoutMilliseconds())
    }

    // The container first, because an image a container still uses cannot be removed.
    func Teardown() {
        lock gate {
            if TornDown {
                return
            }

            TornDown = true
            BestEffortDocker(DockerRemoveContainerArguments(Run.ContainerName))
            BestEffortDocker(DockerRemoveImageArguments(Run.ImageTag))
        }
    }

    // Remove every labelled leftover whose owner is provably gone, containers before images. Best
    // effort throughout: a reclaim that cannot list or remove is not a reason for this run to fail.
    func ReclaimStale(nowUnixSeconds: long) {
        ReclaimKind("container", DockerListLabelledContainersArguments(), nowUnixSeconds)
        ReclaimKind("image", DockerListLabelledImagesArguments(), nowUnixSeconds)
    }

    func ReclaimKind(kind: string, listArguments: List<string>, nowUnixSeconds: long) {
        listing := BestEffortDocker(listArguments)
        if listing.ExitCode != 0 {
            return
        }

        ids := new List<string>()
        for line in listing.Stdout.Split('\n') {
            id := line.Trim()
            if id != "" && !ids.Contains(id) {
                ids.Add(id)
            }
        }

        if ids.Count == 0 {
            return
        }

        inspected := BestEffortDocker(DockerInspectLeftoversArguments(kind, ids))
        if inspected.ExitCode != 0 {
            return
        }

        for leftover in ToolchainParseDockerLeftovers(kind, inspected.Stdout) {
            alive := true
            if leftover.OwnerHost == Run.OwnerHost && leftover.OwnerPid > 0 && leftover.OwnerStartedUnixSeconds > 0 {
                alive = Host.OwnerAlive(leftover.OwnerPid, leftover.OwnerStartedUnixSeconds)
            }

            decision := DockerReclaimDecisionFor(leftover, Run.RunId, Run.OwnerHost, alive, nowUnixSeconds, ToolchainStaleLeftoverAgeSeconds())
            if decision.Reclaim {
                if kind == "container" {
                    BestEffortDocker(DockerRemoveContainerArguments(leftover.Id))
                } else {
                    BestEffortDocker(DockerRemoveImageArguments(leftover.Id))
                }

                Reclaimed.Add(kind + " " + leftover.Id + " (run " + leftover.RunId + "): " + decision.Reason)
            }
        }
    }

    func BestEffortDocker(arguments: List<string>): ToolchainRun {
        try {
            return Host.Docker(arguments, ToolchainDockerHousekeepingTimeoutMilliseconds())
        } catch unavailable: Exception {
            return new ToolchainRun(127, "", unavailable.Message)
        }
    }
}

// The process's fixture, created on first use with its teardown already registered — BEFORE the
// build starts, so a run killed mid-build by its own ceiling still removes what it made.
func ToolchainDocker(): ToolchainDockerFixture {
    lock ToolchainFixtureState.Gate {
        existing := ToolchainFixtureState.Docker
        if existing != null {
            return existing
        }

        fixture := new ToolchainDockerFixture(ToolchainNewDockerRun(), new ProcessDockerHost())
        on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
            fixture.Teardown()
        }
        loadContext := AssemblyLoadContext.GetLoadContext(typeof(ToolchainDockerFixture).Assembly)
        if loadContext != null {
            on loadContext.Unloading unloading => {
                fixture.Teardown()
            }
        }

        ToolchainFixtureState.Docker = fixture
        return fixture
    }
}

func ToolchainEnsureContainer(): ToolchainDockerFixture {
    lock ToolchainFixtureState.Gate {
        fixture := ToolchainDocker()
        fixture.Start(ToolchainPrepareBuildContext())
        return fixture
    }
}

// ONE CONTAINER COMMAND. Every row's assertions read the value this returns, exactly as the deleted
// `Bash` helper's `ExecResult` was read.
func ToolchainBash(command: string): ToolchainRun {
    return ToolchainEnsureContainer().Exec(command)
}

func ToolchainAssertSuccess(result: ToolchainRun, context: string) {
    assert result.ExitCode == 0, result.Report(context)
}

// `/workspace` is the image's WORKDIR, and a fresh subdirectory per case is what keeps twelve rows
// sharing one container from scaffolding over each other.
func ToolchainUniqueDir(prefix: string): string {
    return "/workspace/" + prefix + "-" + Guid.NewGuid().ToString("N").Substring(0, 8)
}

func ToolchainInstallTemplates() {
    ToolchainAssertSuccess(ToolchainBash("dotnet new install NSharpLang.Templates --force"), "template installation")
}

func ToolchainInstallCli() {
    ToolchainAssertSuccess(ToolchainBash("nlc --version"), "CLI launcher availability")
}
