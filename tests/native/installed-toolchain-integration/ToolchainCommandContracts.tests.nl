namespace NSharpLang.InstalledToolchainIntegration.Tests

import System
import System.Collections.Generic
import System.IO
import System.Text.RegularExpressions

// ─── WHAT A MACHINE WITH NO DOCKER CAN STILL PROVE ─────────────────────────────────────────────
//
// The twelve ported rows need a daemon, and on a machine without one they are reported `skipped`. A
// project whose whole content is skippable is a project that says nothing on most machines, so
// everything about the Docker half that is NOT the daemon is held to a row HERE, and these rows carry
// no gate: the argv of every `docker` invocation, the pack/publish command lines, the Dockerfile's
// description of the fresh machine, the quickstart document's parse and rewrites, and the gate's own
// three-state decision.
//
// This is what makes a skipped run honest rather than empty, and it is also where a flag that drifts
// is caught BEFORE CI: none of these claims needs a container, so none of them can hide behind one.

// ─── THE DOCKER ARGV ──────────────────────────────────────────────────────────────────────────
test "the daemon probe is the command the deleted DockerFactAttribute ran" {
    arguments := DockerInfoArguments()

    assert ToolchainJoinArguments(arguments) == "info --format {{json .ServerVersion}}", ToolchainJoinArguments(arguments)

    // THREE ARGV ENTRIES, not a command line: the Go template contains a space and braces, and a
    // shell re-split would turn it into two arguments and a probe that always fails.
    assert arguments.Count == 3, ToolchainJoinArguments(arguments)
    assert arguments[2] == "{{json .ServerVersion}}", arguments[2]

    // Ten seconds, the deleted attribute's ceiling, and the reason its timeout sentence can name it.
    assert ToolchainProbeTimeoutMilliseconds() == 10 * 1000
}

test "the image is built from the staged context with the Dockerfile the project keeps" {
    contextDirectory := Path.Combine(Path.GetTempPath(), "nsharp-integration-contract")
    arguments := DockerBuildArguments(contextDirectory)

    assert ToolchainJoinArguments(arguments) == "build --file " + Path.Combine(contextDirectory, "Dockerfile.toolchain") + " --tag " + DockerImageTag() + " " + contextDirectory, ToolchainJoinArguments(arguments)

    // `--file` is not optional: the file is `Dockerfile.toolchain`, so a build without it would pick
    // up a `Dockerfile` that does not exist. The deleted fixture said the same thing as
    // `WithDockerfile("Dockerfile.toolchain")`.
    assert arguments[1] == "--file", ToolchainJoinArguments(arguments)

    // The CONTEXT is the staged directory and not the repository: the Dockerfile `COPY`s `toolset/`
    // and `packages/`, which exist only there, and a repository-rooted context would send the whole
    // tree to the daemon.
    assert arguments[arguments.Count - 1] == contextDirectory, ToolchainJoinArguments(arguments)
}

test "the container is started detached, self-removing and time-bounded" {
    arguments := DockerRunArguments()

    assert ToolchainJoinArguments(arguments) == "run --detach --rm --name " + DockerContainerName() + " " + DockerImageTag() + " sleep " + ToolchainContainerLifetimeSeconds().ToString(), ToolchainJoinArguments(arguments)

    // `--rm` AND a bounded `sleep` together ARE the teardown. A `test` block has no per-project
    // teardown hook, so the container cannot be disposed the way the deleted `IAsyncLifetime` disposed
    // it; dropping either of these leaves a container running on the developer's machine forever.
    assert arguments.Contains("--rm"), ToolchainJoinArguments(arguments)
    assert arguments.Contains("sleep"), ToolchainJoinArguments(arguments)
    assert ToolchainContainerLifetimeSeconds() > 0
    assert ToolchainContainerLifetimeSeconds() <= 24 * 60 * 60, "an idle container must not outlive a working day"

    // The name is FIXED, which is what makes a stale container reclaimable rather than fatal.
    assert DockerContainerName() == "nsharp-installed-toolchain-integration", DockerContainerName()
    removal := DockerRemoveArguments()
    assert ToolchainJoinArguments(removal) == "rm --force " + DockerContainerName(), ToolchainJoinArguments(removal)
}

test "one container command is bash -c with the whole command as a single argv entry" {
    // The hardest command any row sends: nested quotes, a `$(...)`, a glob and `&&`. If anything
    // re-split it, `find` would receive `'*.csproj'` as several arguments and the shape assertion
    // would pass for the wrong reason.
    command := "test -z \"$(find /workspace/x -maxdepth 1 -name '*.csproj' -print -quit)\" && nlc build"
    arguments := DockerExecArguments(command)

    assert arguments.Count == 5, ToolchainJoinArguments(arguments)
    assert arguments[0] == "exec"
    assert arguments[1] == DockerContainerName()
    assert arguments[2] == "bash"
    assert arguments[3] == "-c"

    // ONE ENTRY, byte for byte, which is what `ProcessStartInfo.ArgumentList` guarantees and what the
    // deleted `ExecAsync(["bash", "-c", command])` guaranteed before it.
    assert arguments[4] == command, arguments[4]
}

// ─── THE PACK AND PUBLISH COMMAND LINES ───────────────────────────────────────────────────────

// The release path's own pack commands, as `DRY_RUN=1` prints them without running one: each
// `dotnet pack` line's project, mapped to whether the line carries the symbol repair. This is the
// release path EXECUTED, not grepped, so a predicate rewritten in any spelling is still held.
func ReleasePathPackedProjects(): Dictionary<string, bool> {
    launch := new ToolchainLaunch("bash", ToolchainRepositoryRoot(), 60 * 1000)
    launch.Arguments.Add("-c")
    launch.Arguments.Add("source scripts/lib/packages.sh && nsharp_pack_package_set /tmp/nsharp-integration-contract/packages q")
    launch.WithEnvironment("DRY_RUN", "1")
    run := ToolchainRunProcess(launch)
    ToolchainRequireSuccess(run, "DRY_RUN=1 nsharp_pack_package_set")

    packed := new Dictionary<string, bool>()
    for line in run.Stdout.Split('\n') {
        pack := Regex.Match(line, "dotnet pack .* (?<project>\\S+\\.csproj) ")
        if pack.Success {
            packed[pack.Groups["project"].Value] = line.Contains("-p:DebugSymbols=false -p:DebugType=None")
        }
    }

    return packed
}

test "the build context is packed the way the release path packs it, and the symbol repair reaches every N# package" {
    output := "/tmp/nsharp-integration-contract/packages"

    assert ToolchainJoinArguments(ToolchainBuildTasksArguments()) == "build src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -c Release --disable-build-servers -v q", ToolchainJoinArguments(ToolchainBuildTasksArguments())

    runtimePack := ToolchainPackArguments(ToolchainRuntimePackageProject(), output)
    assert ToolchainJoinArguments(runtimePack) == "pack src/NSharpLang.Runtime/NSharpLang.Runtime.csproj -c Release -o " + output + " --disable-build-servers -v q", ToolchainJoinArguments(runtimePack)

    // THE REPAIR IS LOAD-BEARING, AND THE DELETED FIXTURE APPLIED IT TO ONLY ONE OF THE TWO PROJECTS
    // THAT NEEDED IT. Direct N# IL emission writes no `.pdb`; the base SDK defaults `DebugType` to
    // `portable`; pack then demands the file, which is NU5026. `ToolchainFixture.cs` repaired
    // `NSharpLang.Compiler.Core` and not `NSharpLang.Compiler`, and CI run 35806417973 is that
    // omission: `error NU5026 ... Compiler.pdb`, thrown in the fixture before any row could run. Every
    // slice carved out of Core is an N# project too, so the repair reaches each of them.
    for compilerProject in ToolchainCompilerPackageProjects() {
        repaired := ToolchainPackCompilerPackageArguments(compilerProject, output)
        assert repaired.Contains("-p:DebugSymbols=false"), compilerProject + ": " + ToolchainJoinArguments(repaired)
        assert repaired.Contains("-p:DebugType=None"), compilerProject + ": " + ToolchainJoinArguments(repaired)
        assert repaired.Contains("--disable-build-servers"), compilerProject + ": " + ToolchainJoinArguments(repaired)
    }

    // And nowhere else, because a repair applied to every pack would hide the defect
    // `tests/native/sdk-pack-symbol-contract` exists to hold: that project packs N#-SDK projects with
    // a BARE `dotnet pack` precisely so the missing declaration stays visible.
    for plainProject in ToolchainPlainPackageProjects() {
        packArguments := ToolchainPackArguments(plainProject, output)
        assert !packArguments.Contains("-p:DebugSymbols=false"), plainProject + ": " + ToolchainJoinArguments(packArguments)
        assert !packArguments.Contains("-p:DebugType=None"), plainProject + ": " + ToolchainJoinArguments(packArguments)
    }

    // THE SET AND THE REPAIR ARE THE RELEASE PATH'S, TAKEN FROM THE RELEASE PATH RUNNING.
    // `scripts/lib/packages.sh` is what `scripts/pack-nuget.sh` — and therefore CI's `Pack unofficial
    // release` step — runs. Every project it packs, this fixture packs, with the same repair decision,
    // and nothing else: that is what stops the fixture drifting from the packages users install.
    releasePacked := ReleasePathPackedProjects()
    fixturePacked := new List<string>()
    for compilerProject in ToolchainCompilerPackageProjects() {
        fixturePacked.Add(compilerProject)
        assert releasePacked.ContainsKey(compilerProject), compilerProject + " is packed here but not by the release path: " + string.Join(", ", releasePacked.Keys)
        assert releasePacked[compilerProject], compilerProject + " is repaired here but packed plainly by the release path in scripts/lib/packages.sh"
    }
    for plainProject in ToolchainPlainPackageProjects() {
        fixturePacked.Add(plainProject)
        assert releasePacked.ContainsKey(plainProject), plainProject + " is packed here but not by the release path: " + string.Join(", ", releasePacked.Keys)
        assert !releasePacked[plainProject], plainProject + " is in the release path's repaired set but is packed plainly here"
    }
    for releaseProject in releasePacked.Keys {
        assert fixturePacked.Contains(releaseProject), releaseProject + " is packed by the release path but this fixture never packs it"
    }
    assert fixturePacked.Count == releasePacked.Count, string.Join(", ", fixturePacked)

    // Every command disables build servers: a leaked MSBuild node outlives the run, and the gate
    // forbids leaving one behind.
    assert ToolchainBuildTasksArguments().Contains("--disable-build-servers")
    assert runtimePack.Contains("--disable-build-servers")

    // The runtime is packed first and exactly once, and the templates the image installs are packed.
    assert ToolchainPlainPackageProjects()[0] == ToolchainRuntimePackageProject(), ToolchainJoinArguments(ToolchainPlainPackageProjects())
    assert ToolchainPlainPackageProjects().LastIndexOf(ToolchainRuntimePackageProject()) == 0, ToolchainJoinArguments(ToolchainPlainPackageProjects())
    assert ToolchainPlainPackageProjects().Contains("templates/NSharpLang.Templates.csproj"), ToolchainJoinArguments(ToolchainPlainPackageProjects())
}

// Every project directory `src/NSharpLang.Compiler/project.yml` reaches through `project:`,
// itself included: the facade and each compiler slice under it. `dotnet pack` writes each of those
// edges as a nuspec `<dependency>`, so this is the set a clean restore of `NSharpLang.Compiler` needs.
func CompilerFacadePackageClosure(): List<string> {
    directories := new List<string>()
    directories.Add("src/NSharpLang.Compiler")
    index := 0
    while index < directories.Count {
        projectDirectory := Path.Combine(ToolchainRepositoryRoot(), directories[index])
        yaml := File.ReadAllText(Path.Combine(projectDirectory, "project.yml"))
        references := Regex.Matches(yaml, "- project:\\s*(?<path>\\S+)")
        referenceIndex := 0
        while referenceIndex < references.Count {
            projectFile := Path.GetFullPath(Path.Combine(projectDirectory, references[referenceIndex].Groups["path"].Value))
            referenced := Path.GetRelativePath(ToolchainRepositoryRoot(), Path.GetDirectoryName(projectFile) ?? "").Replace('\\', '/')
            if !directories.Contains(referenced) {
                directories.Add(referenced)
            }

            referenceIndex = referenceIndex + 1
        }

        index = index + 1
    }

    return directories
}

// THE GUARD EVERY CARVE PASSES THROUGH. Carving a slice out of Core adds a `project:` edge, and with
// it a package the release set must ship; the Model and Syntax carves added the edges, the release
// set followed, and this fixture's own list did not. Now there is one list, and this row holds it to
// the graph: a carved slice missing from `NSHARP_PACKAGE_SPECS` fails HERE, on a machine with no
// Docker, rather than as a feed that cannot restore `NSharpLang.Compiler`.
test "the release package set ships every compiler slice the compiler package depends on" {
    specs := ToolchainReleasePackageSpecs()
    specDirectories := new List<string>()
    for spec in specs {
        specDirectories.Add((Path.GetDirectoryName(spec.Project) ?? "").Replace('\\', '/'))
    }

    closure := CompilerFacadePackageClosure()
    assert closure.Contains("src/NSharpLang.Compiler.Core"), string.Join(", ", closure)
    for projectDirectory in closure {
        assert specDirectories.Contains(projectDirectory), projectDirectory + " is a project the NSharpLang.Compiler package depends on, but NSHARP_PACKAGE_SPECS in scripts/lib/packages.sh does not ship it: " + string.Join(", ", specDirectories)
    }

    // The compiler's own name for its slices (`ExternalAssemblyScan.CompilerSliceAssemblyNames`, the
    // run-time owner) and the release set must agree: every slice is a package.
    ids := ToolchainReleasePackageIds()
    scanSource := File.ReadAllText(Path.Combine(Path.Combine(Path.Combine(ToolchainRepositoryRoot(), "src"), "NSharpLang.Compiler.Model"), "ExternalAssemblyScan.nl"))
    sliceNames := Regex.Match(scanSource, "func CompilerSliceAssemblyNames\\(\\): string\\[\\] \\{\\s*return \\[(?<names>[^\\]]*)\\]")
    assert sliceNames.Success, "Could not find ExternalAssemblyScan.CompilerSliceAssemblyNames in src/NSharpLang.Compiler.Model/ExternalAssemblyScan.nl."
    sliceList := sliceNames.Groups["names"].Value
    sliceMatches := Regex.Matches(sliceList, "\"(?<name>[^\"]+)\"")
    assert sliceMatches.Count > 0, sliceNames.Value
    sliceIndex := 0
    while sliceIndex < sliceMatches.Count {
        slice := sliceMatches[sliceIndex].Groups["name"].Value
        assert ids.Contains(slice), slice + " is a compiler slice (CompilerSliceAssemblyNames) that NSHARP_PACKAGE_SPECS does not ship: " + string.Join(", ", ids)
        sliceIndex = sliceIndex + 1
    }

    // The three the graph does not reach, and which a scaffolded project restores or installs.
    assert ids.Contains("NSharpLang.Sdk"), string.Join(", ", ids)
    assert ids.Contains("NSharpLang.Runtime"), string.Join(", ", ids)
    assert ids.Contains("NSharpLang.Templates"), string.Join(", ", ids)

    // And the release verifier checks the same set it is handed, not a second list that can lag it.
    verifier := File.ReadAllText(Path.Combine(Path.Combine(ToolchainRepositoryRoot(), "scripts"), "verify-release.py"))
    expected := Regex.Match(verifier, "expected = \\{(?<ids>[^}]*)\\}")
    assert expected.Success, "Could not find the expected package set in scripts/verify-release.py."
    verified := new List<string>()
    expectedIds := expected.Groups["ids"].Value
    verifiedMatches := Regex.Matches(expectedIds, "'(?<id>[^']+)'")
    verifiedIndex := 0
    while verifiedIndex < verifiedMatches.Count {
        verified.Add(verifiedMatches[verifiedIndex].Groups["id"].Value)
        verifiedIndex = verifiedIndex + 1
    }
    for id in ids {
        assert verified.Contains(id), id + " is shipped by NSHARP_PACKAGE_SPECS but scripts/verify-release.py does not expect it"
    }
    assert verified.Count == ids.Count, "scripts/verify-release.py expects a package NSHARP_PACKAGE_SPECS does not ship: " + string.Join(", ", verified)
}

test "the toolset is published without repacking and without an archive" {
    command := ToolchainPublishToolsetCommand("/tmp/ctx/toolset", "/tmp/ctx/packages")

    assert command == "./scripts/publish-toolset.sh --output \"/tmp/ctx/toolset\" --packages \"/tmp/ctx/packages\" --skip-packages --skip-archive", command

    // `--skip-packages` because the packs above already produced them — publishing again would pack a
    // second time and could disagree with the feed the image stages. `--skip-archive` because the
    // image `COPY`s a DIRECTORY; the tar.gz is the release path's artifact, not this one's.
    assert command.Contains("--skip-packages"), command
    assert command.Contains("--skip-archive"), command
}

// ─── THE FRESH MACHINE THE DOCKERFILE DESCRIBES ───────────────────────────────────────────────

test "the Dockerfile stages the toolset at the install root the public installer writes" {
    dockerfile := File.ReadAllText(ToolchainDockerfilePath())

    // Only the .NET SDK. Anything else preinstalled would make these rows assert a machine no user has.
    assert dockerfile.Contains("FROM mcr.microsoft.com/dotnet/sdk:10.0"), dockerfile

    assert dockerfile.Contains("COPY toolset/ /root/.nsharp/"), dockerfile
    assert dockerfile.Contains("COPY packages/ /packages/"), dockerfile
    assert dockerfile.Contains("dotnet nuget add source /packages"), dockerfile

    // `NSHARP_INSTALL_DIR` is what the template `NuGet.config` files expand: they `<clear/>` their
    // sources and name `%NSHARP_INSTALL_DIR%/packages`, so the variable is the reason a scaffolded
    // project can restore at all. `scripts/setup-local.sh` defaults it to `$HOME/.nsharp`, which is
    // `/root/.nsharp` for this image's user.
    assert dockerfile.Contains("ENV NSHARP_INSTALL_DIR=\"/root/.nsharp\""), dockerfile
    assert dockerfile.Contains("dotnet new install /root/.nsharp/packages/NSharpLang.Templates.*.nupkg --force"), dockerfile

    // The launchers reach the rows through PATH, which is the only way `nlc` and `nsharp-lsp` are
    // spelled in any row above.
    assert dockerfile.Contains("ENV PATH=\"/root/.nsharp/bin:${PATH}\""), dockerfile

    // `/workspace` is the WORKDIR every scratch directory is created under.
    assert dockerfile.Contains("WORKDIR /workspace"), dockerfile
    assert ToolchainUniqueDir("row").StartsWith("/workspace/"), ToolchainUniqueDir("row")

    // Two calls never collide, which is what lets twelve rows share one container.
    assert ToolchainUniqueDir("row") != ToolchainUniqueDir("row")
}

// ─── THE QUICKSTART DOCUMENT ──────────────────────────────────────────────────────────────────

// THE SET AND THE SIZES, READ OFF THE SHIPPED DOCUMENT WITH NO CONTAINER. The gated replay asserts
// the same set before it runs anything; this row is what catches a deleted or renamed fence in the
// inner loop instead of in CI.
test "templates README declares exactly six quickstarts of one to four commands" {
    quickstarts := ReadTemplateQuickstartsFromDocs()

    assert string.Join(",", TemplateQuickstartNamesSorted(quickstarts)) == "console,library,systems-console,systems-library,test,webapi", string.Join(",", TemplateQuickstartNamesSorted(quickstarts))

    for quickstart in quickstarts {
        assert quickstart.Commands.Count >= 1 && quickstart.Commands.Count <= 4, quickstart.Name + " has " + quickstart.Commands.Count.ToString() + " commands"

        // A `#` comment line or a blank line is not a command, and a fence whose every line was
        // dropped would replay nothing and pass.
        for command in quickstart.Commands {
            assert command.Length > 0, quickstart.Name
            assert !command.StartsWith("#"), quickstart.Name + ": " + command
            assert command == command.Trim(), quickstart.Name + ": " + command
        }
    }
}

test "the parser reads a fence's commands in order and ignores prose between fences" {
    markdown := "# Templates\n\nSome prose.\n\n<!-- quickstart:demo -->\n```bash\n# a comment\ndotnet new nsharp-console -o MyApp\n\ncd MyApp\nnlc run\n```\n\nMore prose, and a fence with no marker:\n\n```bash\nnot-a-quickstart\n```\n"
    quickstarts := ReadTemplateQuickstarts(markdown)

    assert quickstarts.Count == 1, quickstarts.Count.ToString()
    assert quickstarts[0].Name == "demo", quickstarts[0].Name
    assert string.Join(" ;; ", quickstarts[0].Commands) == "dotnet new nsharp-console -o MyApp ;; cd MyApp ;; nlc run", string.Join(" ;; ", quickstarts[0].Commands)
}

test "the rewrite points every documented directory at the scratch one" {
    commands := new List<string>()
    commands.Add("dotnet new nsharp-console -o MyApp")
    commands.Add("cd MyApp")
    commands.Add("nlc build")
    commands.Add("ASPNETCORE_URLS=http://127.0.0.1:5050 nlc run")

    rewritten := RewriteProjectName(commands, "/workspace/docs-console-abcd1234")

    assert rewritten[0] == "dotnet new nsharp-console -o /workspace/docs-console-abcd1234", rewritten[0]
    assert rewritten[1] == "cd /workspace/docs-console-abcd1234", rewritten[1]

    // A command that names no directory is untouched: the systems quickstarts' `nlc check
    // --systems-report` and `nlc build --perf-report` must reach the container exactly as documented.
    assert rewritten[2] == "nlc build", rewritten[2]
    assert rewritten[3] == "ASPNETCORE_URLS=http://127.0.0.1:5050 nlc run", rewritten[3]

    // The BARE project names the other fences use become the scratch leaf, so `nlc new MyLib` and
    // `-o MyTests` land in the same place their `cd` does.
    bare := new List<string>()
    bare.Add("dotnet new nsharp-library -o MyLib")
    bare.Add("dotnet new nsharp-test -o MyTests")
    bare.Add("dotnet new nsharp-webapi -o MyApi")
    bareRewritten := RewriteProjectName(bare, "/workspace/docs-x-1")
    assert bareRewritten[0] == "dotnet new nsharp-library -o /workspace/docs-x-1", bareRewritten[0]
    assert bareRewritten[1] == "dotnet new nsharp-test -o /workspace/docs-x-1", bareRewritten[1]
    assert bareRewritten[2] == "dotnet new nsharp-webapi -o /workspace/docs-x-1", bareRewritten[2]

    // And the systems fences, whose documented directories are not `MyApp`: the `-o` rewrite is what
    // catches `PacketTool` and `PacketCore`, not the name substitutions.
    systems := new List<string>()
    systems.Add("dotnet new nsharp-systems-cli -o PacketTool")
    systems.Add("cd PacketTool")
    systems.Add("nlc check --systems-report")
    systemsRewritten := RewriteProjectName(systems, "/workspace/docs-systems-console-2")
    assert systemsRewritten[0] == "dotnet new nsharp-systems-cli -o /workspace/docs-systems-console-2", systemsRewritten[0]
    assert systemsRewritten[1] == "cd /workspace/docs-systems-console-2", systemsRewritten[1]
    assert systemsRewritten[2] == "nlc check --systems-report", systemsRewritten[2]
}

// EACH COMMAND RUNS IN ITS OWN `bash -c`, so a documented `cd` must be carried forward by the harness
// or every command after it runs in the wrong directory and passes for the wrong reason.
test "the working directory is tracked across commands the way a reader's shell tracks it" {
    assert ApplyCd("/workspace", "cd MyApp") == "/workspace/MyApp"
    assert ApplyCd("/workspace/", "cd MyApp") == "/workspace/MyApp"
    assert ApplyCd("/workspace", "cd /workspace/docs-console-1") == "/workspace/docs-console-1"
    assert ApplyCd("/workspace/docs-console-1", "nlc build") == "/workspace/docs-console-1"
    assert ApplyCd("/workspace", "cd  MyApp  ") == "/workspace/MyApp"
}

// THE SERVER COMMAND IS THE ONLY ONE WRAPPED, and the wrapper is what keeps "it started" from being
// mistaken for "it works".
test "only the web API quickstart's server command is wrapped, and the wrapper proves the route" {
    assert ReplayCommand("nlc build") == "nlc build"
    assert ReplayCommand("nlc run") == "nlc run"
    assert ReplayCommand("ASPNETCORE_URLS=http://127.0.0.1:5050 nlc build") == "ASPNETCORE_URLS=http://127.0.0.1:5050 nlc build"

    wrapped := ReplayCommand("ASPNETCORE_URLS=http://127.0.0.1:5050 nlc run")
    assert wrapped != "ASPNETCORE_URLS=http://127.0.0.1:5050 nlc run", wrapped

    // The server is started in the background and its pid kept, the documented route is polled, and a
    // success KILLS the server and prints the body: a row that left Kestrel running would hold the
    // container's port for every later row.
    assert wrapped.Contains("set -e"), wrapped
    assert wrapped.Contains("& pid=$!"), wrapped
    assert wrapped.Contains("curl -fsS http://127.0.0.1:5050/api/weather"), wrapped
    assert wrapped.Contains("kill $pid"), wrapped

    // A server that DIED is reported with its log rather than polled for twenty more seconds, and the
    // twenty-second budget is forty half-second attempts.
    assert wrapped.Contains("if ! kill -0 $pid 2>/dev/null; then cat /tmp/nsharp-webapi-quickstart.log; exit 1; fi"), wrapped
    assert wrapped.Contains("seq 1 40"), wrapped
    assert wrapped.Contains("sleep 0.5"), wrapped

    // Neither a response nor a dead server within the budget is a FAILURE, not a pass.
    assert wrapped.Contains("exit 1'"), wrapped
}

// ─── THE GATE'S OWN DECISION ──────────────────────────────────────────────────────────────────

test "the gate is forced by the one environment variable the workflows set" {
    // The name is quoted by both workflows and by the skip sentence, so it is spelled once and read
    // from there.
    assert DockerForceEnvironmentVariableName() == "NSHARP_RUN_DOCKER_INTEGRATION", DockerForceEnvironmentVariableName()

    // FORCED MEANS REQUIRED, NOT PREFERRED. CI sets this, so a CI machine whose daemon is missing
    // must FAIL these rows rather than skip them — which is the whole reason the workflow step
    // cannot go green on a runner with no Docker. The rule is asked of the SPELLINGS, not of a
    // rewritten process environment, which every other file of this project reads while it runs.
    assert DockerForcedBy("1")
    assert DockerGateSkipReasonGiven("1") == "", DockerGateSkipReasonGiven("1")

    assert DockerForcedBy("true")
    assert DockerGateSkipReasonGiven("true") == "", DockerGateSkipReasonGiven("true")

    assert DockerForcedBy("TRUE")

    // Anything else is not a force. `0`, `no`, an empty value and no value at all fall through to
    // the probe, exactly as the deleted attribute's two ordinal-ignore-case comparisons did.
    assert !DockerForcedBy("0")
    assert !DockerForcedBy("no")
    assert !DockerForcedBy("")
    assert !DockerForcedBy(null)

    // And the gate asks the rule of the variable itself, whatever this machine has it set to.
    assert DockerIntegrationForced() == DockerForcedBy(Environment.GetEnvironmentVariable("NSHARP_RUN_DOCKER_INTEGRATION"))
}

// THE SKIP IS NAMED, AND IT NAMES THE WAY OUT. This row states the relation between what the probe
// found and what a reader is told, on whichever machine it runs: a daemon means no skip, and no daemon
// means a reason that says which prerequisite was missing and how to demand the row anyway.
test "a machine without a daemon is told which prerequisite is missing and how to require the row" {
    probe := ProbeDocker()
    reason := DockerGateSkipReasonGiven(null)

    if probe.Available {
        assert reason == "", reason
        assert probe.Reason == "", probe.Reason
    } else {
        assert reason.Length > 0, "an unavailable daemon must produce a named skip reason"
        named := reason
        assert named.StartsWith("Docker integration prerequisite unavailable: "), named
        assert named.Contains(probe.Reason), named
        assert named.EndsWith("Set NSHARP_RUN_DOCKER_INTEGRATION=1 to require this test."), named

        // The reason is one of the three the probe distinguishes, never an empty sentence: a
        // missing CLI, a daemon that would not answer in ten seconds, and a daemon that answered
        // with a failure are three different things to tell a reader.
        assert probe.Reason.Length > 0, named
    }
}
