namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.IO

// THE DAEMON-FIRST CLI'S DECISIONS, CROSSED WITHOUT A SOCKET OR A PROCESS.
//
// `tests/native/daemon-exec` drives the same decisions through real `nlc` processes and a real
// server; these rows pin each decision on its own, including the edges a process test cannot reach
// cheaply (every switch combination, the hash's exact bytes, a truncated frame).

// ── Routing ─────────────────────────────────────────────────────────────────────────────────────
test "exactly the seven compiler-bound commands route, case-insensitively, and nothing else does" {
    for name in ["check", "build", "test", "run", "format", "lint", "fix", "CHECK", "Build"] {
        assert DaemonExecKernels.IsRoutedCommandName(name)
    }

    for name in ["query", "daemon", "watch", "new", "init", "publish", "pack", "restore", "clean", "env", "doctor", "help", "--version", "checks", ""] {
        assert !DaemonExecKernels.IsRoutedCommandName(name)
    }
}

test "routing is on by default and every switch turns it off" {
    args: string[] = ["check"]
    assert DaemonExecKernels.ShouldRoute(args, null, null, null, null)

    // NLC_NO_DAEMON: any value but empty or 0.
    assert !DaemonExecKernels.ShouldRoute(args, "1", null, null, null)
    assert !DaemonExecKernels.ShouldRoute(args, "true", null, null, null)
    assert DaemonExecKernels.ShouldRoute(args, "0", null, null, null)
    assert DaemonExecKernels.ShouldRoute(args, "", null, null, null)

    // NLC_DAEMON_CHILD: set by the server for everything it runs, and by `nlc test` for the tests.
    assert !DaemonExecKernels.ShouldRoute(args, null, "1", null, null)

    // CI turns it off unless NLC_DAEMON opts back in.
    assert !DaemonExecKernels.ShouldRoute(args, null, null, "true", null)
    assert !DaemonExecKernels.ShouldRoute(args, null, null, "1", null)
    assert DaemonExecKernels.ShouldRoute(args, null, null, "true", "1")
    assert DaemonExecKernels.ShouldRoute(args, null, null, "false", null)

    // The flag, and an empty or unrouted command line.
    assert !DaemonExecKernels.ShouldRoute(["check", "--no-daemon"], null, null, null, null)
    assert !DaemonExecKernels.ShouldRoute(new string[](0), null, null, null, null)
    assert !DaemonExecKernels.ShouldRoute(["query", "symbols"], null, null, null, null)
}

test "--no-daemon counts only before a -- separator and is stripped only there" {
    assert DaemonExecKernels.HasNoDaemonFlag(["build", "--no-daemon", "--release"])
    assert !DaemonExecKernels.HasNoDaemonFlag(["run", "--", "--no-daemon"])

    stripped := DaemonExecKernels.StripNoDaemonFlag(["build", "--no-daemon", "--release", "--", "--no-daemon"])
    assert String.Join(" ", stripped) == "build --release -- --no-daemon"

    untouched := DaemonExecKernels.StripNoDaemonFlag(["check", "--text"])
    assert String.Join(" ", untouched) == "check --text"
}

// ── The workspace ───────────────────────────────────────────────────────────────────────────────

func DekMarkers(markers: string[]): Func<string, bool> {
    set := new HashSet<string>(markers)
    return directory => set.Contains(directory)
}

test "the workspace is the nearest .git above, even past a nearer project.yml" {
    root := Path.Combine(Path.GetTempPath(), "dek-ws")
    project := Path.Combine(Path.Combine(root, "tests"), "proj")
    resolved := DaemonExecKernels.ResolveWorkspaceRoot(project, DekMarkers([root]), DekMarkers([project]), true)
    assert resolved == root
}

test "without .git the nearest project.yml is the workspace" {
    root := Path.Combine(Path.GetTempPath(), "dek-ws2")
    project := Path.Combine(root, "app")
    inner := Path.Combine(project, "src")
    resolved := DaemonExecKernels.ResolveWorkspaceRoot(inner, DekMarkers(new string[](0)), DekMarkers([project, root]), true)
    assert resolved == project
}

test "with no marker routing declines but an explicit daemon request keeps its directory" {
    start := Path.Combine(Path.GetTempPath(), "dek-none")
    none := DekMarkers(new string[](0))
    assert DaemonExecKernels.ResolveWorkspaceRoot(start, none, none, true) == null
    assert DaemonExecKernels.ResolveWorkspaceRoot(start, none, none, false) == start
}

// ── Build identity ──────────────────────────────────────────────────────────────────────────────

test "the identity hash is FNV-1a 64 over UTF-16 code units, printed as 16 hex digits" {
    // The empty input is the offset basis itself.
    assert DaemonExecKernels.HashIdentity("") == "cbf29ce484222325"
    // A one-character input folds both bytes of the code unit, low byte first.
    assert DaemonExecKernels.HashIdentity("a") == "089be207b544f1e4"
    assert DaemonExecKernels.HashIdentity("a").Length == 16
    assert DaemonExecKernels.HashIdentity("nlc") != DaemonExecKernels.HashIdentity("nld")
}

test "every input of the identity moves it" {
    facts: string[] = ["Cli.dll|10|1"]
    vars: string[] = ["DOTNET_gcServer=1"]
    baseline := DaemonExecKernels.HashIdentity(DaemonExecKernels.ComposeIdentitySource("0.1.0+abc", "/opt/nlc/", "10.0.5", facts, vars))

    assert baseline != DaemonExecKernels.HashIdentity(DaemonExecKernels.ComposeIdentitySource("0.1.0+abd", "/opt/nlc/", "10.0.5", facts, vars))
    assert baseline != DaemonExecKernels.HashIdentity(DaemonExecKernels.ComposeIdentitySource("0.1.0+abc", "/opt/nlc2/", "10.0.5", facts, vars))
    assert baseline != DaemonExecKernels.HashIdentity(DaemonExecKernels.ComposeIdentitySource("0.1.0+abc", "/opt/nlc/", "10.0.6", facts, vars))
    assert baseline != DaemonExecKernels.HashIdentity(DaemonExecKernels.ComposeIdentitySource("0.1.0+abc", "/opt/nlc/", "10.0.5", ["Cli.dll|10|2"], vars))
    assert baseline != DaemonExecKernels.HashIdentity(DaemonExecKernels.ComposeIdentitySource("0.1.0+abc", "/opt/nlc/", "10.0.5", facts, new string[](0)))
    assert baseline == DaemonExecKernels.HashIdentity(DaemonExecKernels.ComposeIdentitySource("0.1.0+abc", "/opt/nlc/", "10.0.5", facts, vars))
}

test "only runtime-configuration variables are part of the identity" {
    assert DaemonExecKernels.IsRuntimeConfigurationVariable("DOTNET_TieredPGO")
    assert DaemonExecKernels.IsRuntimeConfigurationVariable("COMPlus_gcServer")
    assert !DaemonExecKernels.IsRuntimeConfigurationVariable("NUGET_PACKAGES")
    assert !DaemonExecKernels.IsRuntimeConfigurationVariable("dotnet_lowercase")
    assert !DaemonExecKernels.IsRuntimeConfigurationVariable("PATH")
}

// ── Launching ───────────────────────────────────────────────────────────────────────────────────

test "under the dotnet muxer the server is the muxer plus this CLI's entry assembly" {
    command := DaemonExecKernels.GetServerLaunchCommand("/usr/local/share/dotnet/dotnet", "/opt/nlc/Cli.dll", "/work/repo", true)
    assert String.Join("|", command) == "/usr/local/share/dotnet/dotnet|/opt/nlc/Cli.dll|daemon|run|--project|/work/repo|--background"
}

test "an apphost or native CLI is launched directly, and a foreground start has no background flag" {
    command := DaemonExecKernels.GetServerLaunchCommand("/opt/nlc/nlc", "/opt/nlc/Cli.dll", "/work/repo", false)
    assert String.Join("|", command) == "/opt/nlc/nlc|daemon|run|--project|/work/repo"

    native := DaemonExecKernels.GetSelfLaunchPrefix("/opt/nlc/nlc", null)
    assert native.Length == 1
    assert native[0] == "/opt/nlc/nlc"

    // A muxer with no entry assembly (a single-file or native host) cannot be relaunched as a muxer.
    muxerOnly := DaemonExecKernels.GetSelfLaunchPrefix("/usr/bin/dotnet", "")
    assert muxerOnly.Length == 1
    assert DaemonExecKernels.IsDotnetHost("/usr/share/dotnet/dotnet.exe")
    assert !DaemonExecKernels.IsDotnetHost("/opt/nlc/nlc")
}

// ── Limits and switches ─────────────────────────────────────────────────────────────────────────

test "the memory cap and idle timeout parse their variables and keep defaults on nonsense" {
    assert DaemonExecKernels.ParseMaxMemoryMegabytes(null) == 4096L
    assert DaemonExecKernels.ParseMaxMemoryMegabytes("512") == 512L
    assert DaemonExecKernels.ParseMaxMemoryMegabytes("-1") == 4096L
    assert DaemonExecKernels.ParseMaxMemoryMegabytes("lots") == 4096L

    assert DaemonExecKernels.ParseIdleTimeoutMilliseconds(null, 1800000L) == 1800000L
    assert DaemonExecKernels.ParseIdleTimeoutMilliseconds("90s", 1800000L) == 90000L
    assert DaemonExecKernels.ParseIdleTimeoutMilliseconds("2m", 1800000L) == 120000L
    assert DaemonExecKernels.ParseIdleTimeoutMilliseconds("soon", 1800000L) == 1800000L

    assert DaemonExecKernels.IsWarmupEnabled(null)
    assert DaemonExecKernels.IsWarmupEnabled("1")
    assert !DaemonExecKernels.IsWarmupEnabled("0")
}

test "the wire's frame kinds are distinct within each direction" {
    toServer := new HashSet<byte>()
    for kind in [DaemonExecKernels.FrameRequest(), DaemonExecKernels.FrameStdinData(), DaemonExecKernels.FrameStdinEnd(), DaemonExecKernels.FrameCancel(), DaemonExecKernels.FrameChildExit()] {
        assert toServer.Add(kind)
    }

    toClient := new HashSet<byte>()
    for kind in [DaemonExecKernels.FrameAccepted(), DaemonExecKernels.FrameStdout(), DaemonExecKernels.FrameStderr(), DaemonExecKernels.FrameStdinWanted(), DaemonExecKernels.FrameLaunch(), DaemonExecKernels.FrameKeepAlive(), DaemonExecKernels.FrameDone(), DaemonExecKernels.FrameBusy(), DaemonExecKernels.FrameMismatch()] {
        assert toClient.Add(kind)
    }

    // The exec magic cannot be mistaken for the JSON-RPC wire, which opens with `{`.
    assert DaemonExecKernels.GetExecMagic()[0] != (byte)123
    assert DaemonExecKernels.GetExecMagic().Length == 4
}

test "the one fallback note names both ways to skip the server" {
    note := DaemonExecKernels.GetServerLostNote()
    assert note.StartsWith("nlc: ")
    assert note.Contains("--no-daemon")
    assert note.Contains("NLC_NO_DAEMON=1")
    assert !note.Contains("\n")
}

// ── The wire ────────────────────────────────────────────────────────────────────────────────────

test "an exec request survives the wire field for field" {
    request := new DaemonExecRequest(
        1,
        "0123456789abcdef",
        ["test", "--filter", "Ünïcode ✓"],
        ["/opt/nlc/Cli.dll", "test"],
        "/work/repo",
        ["HOME", "NUGET_PACKAGES"],
        ["/home/u", ""],
        "tr-TR",
        "en-US",
        true,
        false,
        true,
        4242
    )

    decoded := DaemonExecWire.DecodeRequest(DaemonExecWire.EncodeRequest(request))
    assert decoded.ProtocolVersion == 1
    assert decoded.Identity == "0123456789abcdef"
    assert String.Join("|", decoded.Args) == "test|--filter|Ünïcode ✓"
    assert String.Join("|", decoded.CommandLineArgs) == "/opt/nlc/Cli.dll|test"
    assert decoded.WorkingDirectory == "/work/repo"
    assert String.Join("|", decoded.EnvironmentNames) == "HOME|NUGET_PACKAGES"
    assert decoded.EnvironmentValues[1] == ""
    assert decoded.Culture == "tr-TR"
    assert decoded.UiCulture == "en-US"
    assert decoded.StdoutRedirected
    assert !decoded.StderrRedirected
    assert decoded.StdinRedirected
    assert decoded.ClientProcessId == 4242
}

test "frames round-trip in order, a clean end is null, and a torn frame throws" {
    using buffer := new MemoryStream()
    first := DaemonExecWire.EncodeString("héllo")
    DaemonExecWire.WriteFrame(buffer, DaemonExecKernels.FrameStdout(), first, 0, first.Length)
    DaemonExecWire.WriteFrame(buffer, DaemonExecKernels.FrameKeepAlive(), new byte[](0), 0, 0)
    exitBytes := DaemonExecWire.EncodeInt32(-2)
    DaemonExecWire.WriteFrame(buffer, DaemonExecKernels.FrameDone(), exitBytes, 0, exitBytes.Length)
    bytes := buffer.ToArray()

    using reader := new MemoryStream(bytes)
    one := must DaemonExecWire.ReadFrame(reader)
    assert one.Kind == DaemonExecKernels.FrameStdout()
    assert DaemonExecWire.DecodeString(one.Payload) == "héllo"
    two := must DaemonExecWire.ReadFrame(reader)
    assert two.Kind == DaemonExecKernels.FrameKeepAlive()
    assert two.Payload.Length == 0
    three := must DaemonExecWire.ReadFrame(reader)
    assert DaemonExecWire.DecodeInt32(three.Payload, 0) == -2
    assert DaemonExecWire.ReadFrame(reader) == null

    torn := new byte[](bytes.Length - 2)
    Array.Copy(bytes, torn, torn.Length)
    using tornReader := new MemoryStream(torn)
    DaemonExecWire.ReadFrame(tornReader)
    DaemonExecWire.ReadFrame(tornReader)
    threw := false
    try {
        DaemonExecWire.ReadFrame(tornReader)
    } catch endOfStream: EndOfStreamException {
        threw = true
    }

    assert threw
}

test "a frame header claiming more than the cap is corrupt, as is JSON read as a frame" {
    using json := new MemoryStream(DaemonExecWire.EncodeString("{\"jsonrpc\":\"2.0\",\"id\":0}"))
    threw := false
    try {
        DaemonExecWire.ReadFrame(json)
    } catch invalid: InvalidDataException {
        threw = true
    }

    assert threw
}

test "a launch directive carries the dotnet arguments and the working directory" {
    payload := DaemonExecWire.EncodeLaunch("\"/w/bin/App.dll\"", "/w")
    assert DaemonExecWire.DecodeLaunchArguments(payload) == "\"/w/bin/App.dll\""
    assert DaemonExecWire.DecodeLaunchWorkingDirectory(payload) == "/w"
    assert DaemonExecWire.DecodeLaunchWorkingDirectory(DaemonExecWire.EncodeLaunch("x", null)) == ""
}
