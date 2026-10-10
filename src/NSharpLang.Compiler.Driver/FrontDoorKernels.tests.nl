namespace NSharpLang.Cli

import System.Collections
import System.Collections.Generic
import System.IO

// THE NATIVE FRONT DOOR'S DECISIONS (`FrontDoorKernels`). The hand-off itself is proven as a
// process in `tests/native/cli-command-contracts/FrontDoorContracts.tests.nl`.

// ── what the front door answers itself ───────────────────────────────────────────────────────
test "the front door answers help and version and hands every other command to the host" {
    assert FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(new string[](0)))
    assert FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["--version"]))
    assert FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["-V"]))
    assert FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["help"]))
    assert FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["--help"]))
    assert FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["-h"]))

    assert !FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["check"]))
    assert !FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["build"]))
    assert !FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["test"]))
    assert !FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["run"]))
    assert !FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["format"]))
    // an unknown command's error text belongs to the host's dispatcher
    assert !FrontDoorKernels.AnswersInFrontDoor(ProgramCommandKernels.GetCommandKind(["no-such-command"]))
}

test "the force switch is on only for 1 or true" {
    assert FrontDoorKernels.ForceEnvironmentVariableName() == "NSHARP_FRONT_DOOR"
    assert FrontDoorKernels.IsForced("1")
    assert FrontDoorKernels.IsForced("true")
    assert FrontDoorKernels.IsForced("TRUE")
    assert !FrontDoorKernels.IsForced(null)
    assert !FrontDoorKernels.IsForced("")
    assert !FrontDoorKernels.IsForced("0")
    assert !FrontDoorKernels.IsForced("false")
}

// ── where the host is ────────────────────────────────────────────────────────────────────────
test "the host is looked for beside the front door, then in lib/nlc of the toolset root" {
    root := Path.Combine(Path.GetTempPath(), "nsharp-front-door")
    libNlc := Path.Combine(Path.Combine(root, "lib"), "nlc")
    bin := Path.Combine(root, "bin")
    directories := new List<string>()
    directories.Add(libNlc)
    directories.Add(bin)

    candidates := FrontDoorKernels.GetHostAssemblyCandidates(directories)

    assert candidates.Count == 3, string.Join("\n", candidates)
    assert candidates[0] == Path.Combine(libNlc, "Cli.dll")
    assert candidates[1] == Path.Combine(bin, "Cli.dll")
    // `bin/`'s parent is the root, whose lib/nlc is the first candidate again: listed once
    assert candidates[2] == Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "lib"), "lib"), "nlc"), "Cli.dll")
    assert FrontDoorKernels.HostAssemblyFileName() == "Cli.dll"
}

test "a trailing separator does not change where the toolset root is" {
    root := Path.Combine(Path.GetTempPath(), "nsharp-front-door-sep")
    bin := Path.Combine(root, "bin")
    directories := new List<string>()
    directories.Add(bin + Path.DirectorySeparatorChar)

    candidates := FrontDoorKernels.GetHostAssemblyCandidates(directories)

    assert candidates.Contains(Path.Combine(Path.Combine(Path.Combine(root, "lib"), "nlc"), "Cli.dll")), string.Join("\n", candidates)
}

// ── which .NET ───────────────────────────────────────────────────────────────────────────────
test "the architecture root variables are the ones the .NET host reads" {
    assert FrontDoorKernels.GetArchitectureRootVariable("Arm64") == "DOTNET_ROOT_ARM64"
    assert FrontDoorKernels.GetArchitectureRootVariable("X64") == "DOTNET_ROOT_X64"
    assert FrontDoorKernels.GetArchitectureRootVariable("X86") == "DOTNET_ROOT_X86"
    assert FrontDoorKernels.GetArchitectureRootVariable("Wasm") == null
    assert FrontDoorKernels.GetDotnetExecutableName(false) == "dotnet"
    assert FrontDoorKernels.GetDotnetExecutableName(true) == "dotnet.exe"
}

test "unix dotnet roots are searched in the launcher script's order" {
    candidates := FrontDoorKernels.GetDotnetRootCandidates("/arch", "/root", "/opt/homebrew/Cellar/dotnet/10.0.105/bin/dotnet", "/home/ada", false, null, null)

    expected := new List<string>()
    expected.Add("/arch")
    expected.Add("/root")
    expected.Add("/opt/homebrew/Cellar/dotnet/10.0.105/bin")
    expected.Add("/opt/homebrew/Cellar/dotnet/10.0.105/libexec")
    expected.Add("/opt/homebrew/Cellar/dotnet/10.0.105")
    expected.Add("/home/ada/.dotnet")
    expected.Add("/opt/homebrew/opt/dotnet/libexec")
    expected.Add("/usr/local/opt/dotnet/libexec")
    expected.Add("/usr/local/share/dotnet")
    expected.Add("/usr/share/dotnet")
    assert string.Join("|", candidates) == string.Join("|", expected), string.Join("\n", candidates)
}

test "missing variables are skipped and a repeated root is searched once" {
    candidates := FrontDoorKernels.GetDotnetRootCandidates(null, "/usr/share/dotnet", null, "", false, null, null)

    assert candidates[0] == "/usr/share/dotnet"
    assert candidates.Count == 4, string.Join("\n", candidates)
    assert !candidates.Contains("")
}

test "windows dotnet roots end in the Program Files installs" {
    candidates := FrontDoorKernels.GetDotnetRootCandidates(null, null, null, null, true, "PF", "PF86")

    assert candidates.Count == 2, string.Join("\n", candidates)
    assert candidates[0] == Path.Combine("PF", "dotnet")
    assert candidates[1] == Path.Combine("PF86", "dotnet")
}

test "a root is usable only when it carries a .NET 10 runtime" {
    assert FrontDoorKernels.HasRequiredRuntime(["9.0.4", "10.0.5"])
    assert FrontDoorKernels.HasRequiredRuntime(["10.0.0-rc.2.25502.107"])
    assert !FrontDoorKernels.HasRequiredRuntime(["9.0.4", "8.0.11"])
    assert !FrontDoorKernels.HasRequiredRuntime(["1.0.0", "100.0.0"])
    assert !FrontDoorKernels.HasRequiredRuntime(new string[](0))
}

// ── the hand-off ─────────────────────────────────────────────────────────────────────────────
test "the host argument vector is the muxer, the host and the arguments untouched" {
    vector := FrontDoorKernels.BuildHostArgumentVector("/dn/dotnet", "/t/lib/nlc/Cli.dll", ["check", "--file", "a b.nl", ""])

    assert vector.Length == 6
    assert vector[0] == "/dn/dotnet"
    assert vector[1] == "/t/lib/nlc/Cli.dll"
    assert vector[2] == "check"
    assert vector[3] == "--file"
    assert vector[4] == "a b.nl"
    assert vector[5] == ""
    assert FrontDoorKernels.BuildHostArgumentVector("d", "h", new string[](0)).Length == 2
}

test "the host environment points DOTNET_ROOT at the runtime found and drops the force switch" {
    current := new Hashtable()
    current["PATH"] = "/usr/bin"
    current["DOTNET_ROOT"] = "/somewhere/else"
    current["NSHARP_FRONT_DOOR"] = "1"
    current["EMPTY"] = ""

    environment := FrontDoorKernels.BuildHostEnvironment(current, "/dn", "DOTNET_ROOT_ARM64")

    assert string.Join("|", environment) == "DOTNET_ROOT=/dn|DOTNET_ROOT_ARM64=/dn|EMPTY=|PATH=/usr/bin", string.Join("|", environment)
}

test "an architecture root the caller already set is kept" {
    current := new Hashtable()
    current["DOTNET_ROOT_X64"] = "/x64"

    environment := FrontDoorKernels.BuildHostEnvironment(current, "/dn", "DOTNET_ROOT_X64")

    assert string.Join("|", environment) == "DOTNET_ROOT=/dn|DOTNET_ROOT_X64=/x64", string.Join("|", environment)
    assert string.Join("|", FrontDoorKernels.BuildHostEnvironment(new Hashtable(), "/dn", null)) == "DOTNET_ROOT=/dn"
}

test "start failures exit 127 with the launcher's messages" {
    assert FrontDoorKernels.GetStartFailureExitCode() == 127
    unix := FrontDoorKernels.GetMissingDotnetMessage(false)
    assert unix.StartsWith("Error: N# requires .NET 10, but no usable dotnet runtime was found.")
    assert unix.Contains("brew install dotnet")
    assert FrontDoorKernels.GetMissingDotnetMessage(true).Contains("winget install Microsoft.DotNet.SDK.10")
    hosts := new List<string>()
    hosts.Add("/t/lib/nlc/Cli.dll")
    assert FrontDoorKernels.GetMissingHostMessage(hosts) == "Error: N# installation is incomplete; missing nlc payload: /t/lib/nlc/Cli.dll"
    assert FrontDoorKernels.GetHostStartFailureMessage("/dn/dotnet", "No such file or directory") == "Error: could not start the N# compiler host with /dn/dotnet: No such file or directory"
}
