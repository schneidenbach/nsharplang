namespace NSharpLang.InstalledToolchainIntegration.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO

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
// build context (one `dotnet build`, five `dotnet pack`s and `scripts/publish-toolset.sh`) is produced
// once per process
// and the container is started once per process, whichever row arrives first.
//
// THE CONTAINER REAPS ITSELF, because nothing here gets a teardown hook. `IAsyncLifetime.DisposeAsync`
// disposed the Testcontainers container; a `test` block has no per-project teardown, so the container
// is started with `--rm` and a BOUNDED `sleep` instead, and the fixture force-removes a stale
// container of the same name before it starts a new one. A crashed run therefore leaves at most one
// container that removes itself, and the next run reclaims the name regardless.
//
// THE DOCKER GATE IS IN `DockerGate.tests.nl`, and it is the reason a machine without Docker still
// reports these rows: they come back `skipped` with a named reason and a nonzero skip count, never
// silently absent and never green-because-empty.
class ToolchainRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }

    // The failure text of the deleted `AssertSuccess`, verbatim: the exit code, then both streams
    // under their own banners, so a red row names the command AND what the container printed
    // without a second run.
    func Report(context: string): string {
        return context + " failed (exit code " + ExitCode.ToString() + ")\n--- stdout ---\n" + Stdout + "\n--- stderr ---\n" + Stderr
    }
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

class ToolchainFixtureState {
    static BuildContextDirectory: string = ""
    static ContextPrepared: bool = false
    static ContainerStarted: bool = false
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

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(launch.TimeoutMilliseconds) {
        process.Kill(true)
        process.WaitForExit()
        timedOutStdout := ""
        if stdoutTask.IsCompleted {
            timedOutStdout = stdoutTask.Result
        }

        timedOutStderr := ""
        if stderrTask.IsCompleted {
            timedOutStderr = stderrTask.Result
        }

        process.Dispose()
        return new ToolchainRun(124, timedOutStdout, timedOutStderr + "\nTimed out after " + launch.TimeoutMilliseconds.ToString() + " ms.")
    }

    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    exitCode := process.ExitCode
    process.Dispose()
    return new ToolchainRun(exitCode, stdout, stderr)
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

func DockerImageTag(): string {
    return "nsharp-installed-toolchain-integration:local"
}

// A FIXED name rather than a random one, which is what makes a stale container reclaimable: the
// fixture force-removes this name before it starts, so a previous crashed run can never make this
// one fail to start.
func DockerContainerName(): string {
    return "nsharp-installed-toolchain-integration"
}

// `--file` is passed explicitly because the Dockerfile is named `Dockerfile.toolchain`, exactly as
// the deleted fixture's `WithDockerfile("Dockerfile.toolchain")` did, and the build context is the
// staged directory rather than the repository.
func DockerBuildArguments(buildContextDirectory: string): List<string> {
    arguments := new List<string>()
    arguments.Add("build")
    arguments.Add("--file")
    arguments.Add(Path.Combine(buildContextDirectory, "Dockerfile.toolchain"))
    arguments.Add("--tag")
    arguments.Add(DockerImageTag())
    arguments.Add(buildContextDirectory)
    return arguments
}

// `--detach --rm` plus a bounded `sleep` IS the teardown. The deleted Dockerfile's
// `ENTRYPOINT ["tail", "-f", "/dev/null"]` keeps a container alive forever, which is correct when
// something disposes it; nothing here does, so the command overrides the entrypoint's argument with
// a `sleep` that ends and a `--rm` that reaps.
func DockerRunArguments(): List<string> {
    arguments := new List<string>()
    arguments.Add("run")
    arguments.Add("--detach")
    arguments.Add("--rm")
    arguments.Add("--name")
    arguments.Add(DockerContainerName())
    arguments.Add(DockerImageTag())
    arguments.Add("sleep")
    arguments.Add(ToolchainContainerLifetimeSeconds().ToString())
    return arguments
}

// `docker exec <container> bash -c <command>` — the four argv entries the deleted
// `_fixture.Container.ExecAsync(["bash", "-c", command])` produced, with the command as ONE entry.
func DockerExecArguments(command: string): List<string> {
    arguments := new List<string>()
    arguments.Add("exec")
    arguments.Add(DockerContainerName())
    arguments.Add("bash")
    arguments.Add("-c")
    arguments.Add(command)
    return arguments
}

func DockerRemoveArguments(): List<string> {
    arguments := new List<string>()
    arguments.Add("rm")
    arguments.Add("--force")
    arguments.Add(DockerContainerName())
    return arguments
}

// ─── THE BUILD-CONTEXT COMMAND LINES, AS VALUES ───────────────────────────────────────────────
//
// The six pack/build commands of the deleted `ToolchainFixture.InitializeAsync`, in its order.
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
// runs, therefore passes these two flags for BOTH compiler packages and for neither of the other
// three.
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

// The two projects whose output has no symbol file, exactly as `scripts/lib/packages.sh` names them.
func ToolchainCompilerPackageProjects(): List<string> {
    projects := new List<string>()
    projects.Add("src/NSharpLang.Compiler.Core/NSharpLang.Compiler.Core.csproj")
    projects.Add("src/NSharpLang.Compiler/Compiler.csproj")
    return projects
}

// The three packed with nothing on the command line, in the order the deleted fixture packed them.
func ToolchainPlainPackageProjects(): List<string> {
    projects := new List<string>()
    projects.Add("src/NSharpLang.Runtime/NSharpLang.Runtime.csproj")
    projects.Add("src/NSharpLang.Sdk/NSharpLang.Sdk.csproj")
    projects.Add("templates/NSharpLang.Templates.csproj")
    return projects
}

// The release path's own predicate, read as text so this fixture cannot drift from it silently.
func ToolchainPackagesScriptPath(): string {
    return Path.Combine(Path.Combine(Path.Combine(ToolchainRepositoryRoot(), "scripts"), "lib"), "packages.sh")
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

func ToolchainRunDocker(arguments: List<string>, timeoutMilliseconds: int): ToolchainRun {
    launch := new ToolchainLaunch("docker", ToolchainRepositoryRoot(), timeoutMilliseconds)
    index := 0
    while index < arguments.Count {
        launch.Arguments.Add(arguments[index])
        index = index + 1
    }

    return ToolchainRunProcess(launch)
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

// A context holds five packages and a published toolset, and — like the container — there is no
// teardown hook to delete it: `IAsyncLifetime.DisposeAsync` removed the C# fixture's, and a `test`
// block has no equivalent. So each run sweeps the ones EARLIER runs left, which bounds the leak to
// one context rather than one per gate run.
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
// Six `dotnet` commands and one `bash` command, in the deleted fixture's order, into a throwaway
// directory holding `packages/`, `toolset/` and the Dockerfile. NOTHING here needs Docker, which is
// why it is a function of its own: the row that proves it runs on a machine with no daemon at all.
func ToolchainPrepareBuildContext(): string {
    if ToolchainFixtureState.ContextPrepared {
        return ToolchainFixtureState.BuildContextDirectory
    }

    repositoryRoot := ToolchainRepositoryRoot()
    SweepStaleBuildContexts()
    buildContextDirectory := Path.Combine(Path.GetTempPath(), ToolchainBuildContextPrefix() + Guid.NewGuid().ToString("N").Substring(0, 12))
    Directory.CreateDirectory(buildContextDirectory)

    packagesDirectory := Path.Combine(buildContextDirectory, "packages")
    Directory.CreateDirectory(packagesDirectory)

    // The tasks project first: the SDK pack depends on its output binaries.
    ToolchainRequireSuccess(ToolchainRunDotnet(ToolchainBuildTasksArguments()), "dotnet build of NSharpLang.Build.Tasks")

    // The deleted fixture's ORDER, preserved: Runtime, then the two compiler packages, then the SDK
    // and the templates. The SDK pack MSBuilds Build.Tasks for its `tools/` payload, so it follows
    // the explicit Build.Tasks build above rather than preceding it.
    ToolchainRequireSuccess(
        ToolchainRunDotnet(ToolchainPackArguments("src/NSharpLang.Runtime/NSharpLang.Runtime.csproj", packagesDirectory)),
        "dotnet pack of NSharpLang.Runtime"
    )
    for compilerProject in ToolchainCompilerPackageProjects() {
        ToolchainRequireSuccess(
            ToolchainRunDotnet(ToolchainPackCompilerPackageArguments(compilerProject, packagesDirectory)),
            "dotnet pack of " + compilerProject
        )
    }

    ToolchainRequireSuccess(
        ToolchainRunDotnet(ToolchainPackArguments("src/NSharpLang.Sdk/NSharpLang.Sdk.csproj", packagesDirectory)),
        "dotnet pack of NSharpLang.Sdk"
    )
    ToolchainRequireSuccess(
        ToolchainRunDotnet(ToolchainPackArguments("templates/NSharpLang.Templates.csproj", packagesDirectory)),
        "dotnet pack of NSharpLang.Templates"
    )

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

    ToolchainFixtureState.BuildContextDirectory = buildContextDirectory
    ToolchainFixtureState.ContextPrepared = true
    return buildContextDirectory
}

// ─── THE CONTAINER ────────────────────────────────────────────────────────────────────────────

func ToolchainEnsureContainer() {
    if ToolchainFixtureState.ContainerStarted {
        return
    }

    buildContextDirectory := ToolchainPrepareBuildContext()
    ToolchainRequireSuccess(
        ToolchainRunDocker(DockerBuildArguments(buildContextDirectory), ToolchainImageBuildTimeoutMilliseconds()),
        "docker build of " + DockerImageTag()
    )

    // Reclaim the name before using it. A previous run that died between `run` and its `sleep`
    // expiry still owns it, and "name already in use" is not a product defect worth a red row.
    ToolchainRunDocker(DockerRemoveArguments(), ToolchainProbeTimeoutMilliseconds())
    ToolchainRequireSuccess(
        ToolchainRunDocker(DockerRunArguments(), ToolchainImageBuildTimeoutMilliseconds()),
        "docker run of " + DockerContainerName()
    )

    ToolchainFixtureState.ContainerStarted = true
}

// ONE CONTAINER COMMAND. Every row's assertions read the value this returns, exactly as the deleted
// `Bash` helper's `ExecResult` was read.
func ToolchainBash(command: string): ToolchainRun {
    ToolchainEnsureContainer()
    return ToolchainRunDocker(DockerExecArguments(command), ToolchainExecTimeoutMilliseconds())
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
