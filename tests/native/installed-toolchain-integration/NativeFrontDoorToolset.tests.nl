namespace NSharpLang.InstalledToolchainIntegration.Tests

import System
import System.Collections.Generic
import System.IO
import System.Reflection.PortableExecutable

// ─── THE PER-RID TOOLSET THIS MACHINE PUBLISHES ───────────────────────────────────────────────
//
// The Docker rows install the PORTABLE toolset into a Linux container: that is the release archive,
// and it runs on every platform. A toolset published with `--rid` for THIS machine (what
// `scripts/setup-local.sh` installs) is a different product: `bin/nlc` is the NativeAOT front door
// (`src/NSharpLang.Compiler.Driver/FrontDoor.nl`) and `lib/nlc` is the ReadyToRun compiler host.
// NativeAOT cannot cross-compile to another OS, so these rows run on the host instead of in the
// container, against a real `publish-toolset.sh --rid host` output, and drive a project through
// the native executable exactly as a user's shell would.
class NativeToolsetState {
    static Directory: string = ""
    static Published: bool = false
}

// Published once per process, under the fixture's lock: the Docker staging packs and publishes the
// same projects, and two `dotnet publish` runs of one project must not share `obj/` at once.
func NativeToolset(): string {
    lock ToolchainFixtureState.Gate {
        if !NativeToolsetState.Published {
            root := Path.Combine(Path.GetTempPath(), "nsharp-native-toolset-" + Guid.NewGuid().ToString("N").Substring(0, 12))
            toolset := Path.Combine(root, "nsharp")
            launch := new ToolchainLaunch("bash", ToolchainRepositoryRoot(), ToolchainPackTimeoutMilliseconds())
            launch.Arguments.Add("-lc")
            launch.Arguments.Add("./scripts/publish-toolset.sh --rid host --output " + ToolchainQuote(toolset) + " --packages " + ToolchainQuote(Path.Combine(root, "packages")) + " --skip-packages --skip-archive")
            launch.WithEnvironment("MSBUILDDISABLENODEREUSE", "1")
            launch.WithEnvironment("DOTNET_NOLOGO", "1")
            ToolchainRequireSuccess(ToolchainRunProcess(launch), "scripts/publish-toolset.sh --rid host")
            on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
                try {
                    Directory.Delete(root, true)
                } catch {
                    // A temp directory that cannot be removed is left for the OS to reclaim.
                    return
                }
            }
            NativeToolsetState.Directory = toolset
            NativeToolsetState.Published = true
        }

        return NativeToolsetState.Directory
    }
}

func NativeNlc(toolset: string, arguments: List<string>, workingDirectory: string): ToolchainRun {
    launch := new ToolchainLaunch(Path.Combine(Path.Combine(toolset, "bin"), "nlc"), workingDirectory, ToolchainExecTimeoutMilliseconds())
    launch.Arguments.AddRange(arguments)
    launch.WithEnvironment("DOTNET_NOLOGO", "1")
    return ToolchainRunProcess(launch)
}

func NativeArguments(text: string): List<string> {
    arguments := new List<string>()
    for part in text.Split(' ', StringSplitOptions.RemoveEmptyEntries) {
        arguments.Add(part)
    }

    return arguments
}

func IsReadyToRun(assemblyPath: string): bool {
    stream := File.OpenRead(assemblyPath)
    try {
        reader := new PEReader(stream)
        try {
            corHeader := reader.PEHeaders.CorHeader
            return corHeader != null && corHeader.ManagedNativeHeaderDirectory.Size > 0
        } finally {
            reader.Dispose()
        }
    } finally {
        stream.Dispose()
    }
}

test "a host-RID toolset ships nlc as the NativeAOT front door over a ReadyToRun compiler host" {
    toolset := NativeToolset()
    version := File.ReadAllText(Path.Combine(toolset, "VERSION"))
    assert version.Contains("\nnlc=native\n"), version
    assert !version.Contains("rid=portable"), version

    // A launcher script starts with `#!`; the front door is a native executable.
    nlc := Path.Combine(Path.Combine(toolset, "bin"), "nlc")
    head := new byte[](2)
    stream := File.OpenRead(nlc)
    try {
        assert stream.Read(head, 0, 2) == 2
    } finally {
        stream.Dispose()
    }
    assert !(head[0] == 35 && head[1] == 33), "bin/nlc is still a script"

    host := Path.Combine(Path.Combine(Path.Combine(toolset, "lib"), "nlc"), "Cli.dll")
    assert IsReadyToRun(host), host + " is not ReadyToRun-compiled"
    // The language server ships ReadyToRun as well; it keeps its launcher script.
    assert IsReadyToRun(Path.Combine(Path.Combine(Path.Combine(toolset, "lib"), "nsharp-lsp"), "LanguageServer.dll"))
}

test "the native front door reports the host's version and drives check, build, run and test" {
    toolset := NativeToolset()
    version := NativeNlc(toolset, NativeArguments("--version"), Path.GetTempPath())
    ToolchainAssertSuccess(version, "nlc --version")
    host := ToolchainRunDotnet(NativeArguments(Path.Combine(Path.Combine(Path.Combine(toolset, "lib"), "nlc"), "Cli.dll") + " --version"))
    ToolchainAssertSuccess(host, "dotnet lib/nlc/Cli.dll --version")
    assert version.Stdout == host.Stdout, version.Stdout + " vs " + host.Stdout

    project := Path.Combine(Path.GetTempPath(), "nsharp-native-front-door-" + Guid.NewGuid().ToString("N").Substring(0, 8))
    Directory.CreateDirectory(project)
    try {
        File.WriteAllText(Path.Combine(project, "project.yml"), "name: NativeFrontDoor\nversion: 0.1.0\ntargetFramework: net10.0\noutputType: exe\nentry: Program.nl\n")
        File.WriteAllText(Path.Combine(project, "Program.nl"), "namespace NativeFrontDoor\n\nfunc Twice(value: int): int => value * 2\n\nfunc main(): int {\n    print $\"twice={Twice(21)}\"\n    return 3\n}\n")
        File.WriteAllText(Path.Combine(project, "Program.tests.nl"), "namespace NativeFrontDoor\n\ntest \"twice doubles\" {\n    assert Twice(4) == 8\n}\n")

        check := NativeNlc(toolset, NativeArguments("check"), project)
        ToolchainAssertSuccess(check, "nlc check")
        assert check.Stdout.Contains("\"ok\": true"), check.Stdout

        ToolchainAssertSuccess(NativeNlc(toolset, NativeArguments("build"), project), "nlc build")

        run := NativeNlc(toolset, NativeArguments("run"), project)
        assert run.ExitCode == 3, run.Report("nlc run")
        assert run.Stdout.Contains("twice=42"), run.Stdout

        tests := NativeNlc(toolset, NativeArguments("test --no-cache"), project)
        ToolchainAssertSuccess(tests, "nlc test")
        assert tests.Stdout.Contains("Passed: 1, Failed: 0"), tests.Stdout

        unknown := NativeNlc(toolset, NativeArguments("no-such-command"), project)
        assert unknown.ExitCode == 1, unknown.Report("nlc no-such-command")
        assert unknown.Stderr.Contains("Unknown command: no-such-command"), unknown.Stderr
    } finally {
        Directory.Delete(project, true)
    }
}
