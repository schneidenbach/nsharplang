namespace NSharpLang.CensusStaticRecvRuntime.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text
import System.Text.Json
import NSharpLang.StaticRecvRuntime.Inline
import NSharpLang.StaticRecvRuntime.Typed
import Xunit

sealed class UnixLspFactAttribute: FactAttribute {
    public constructor() {
        if !OperatingSystem.IsMacOS() && !OperatingSystem.IsLinux() {
            Skip = "requires /bin/sh and mkfifo for a local stdio LSP exchange"
        }
    }
}

class StaticRecvShellRun {
    ExitCode: int
    TimedOut: bool

    constructor(exitCode: int, timedOut: bool) {
        ExitCode = exitCode
        TimedOut = timedOut
    }
}

class StaticRecvLspFrame {
    Body: string

    constructor(body: string) {
        Body = body
    }
}

func StaticRecvRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the repository root above this test tree.")
}

func StaticRecvFixtureDll(directoryName: string, assemblyName: string): string {
    fixtures := Path.Combine(Path.Combine(StaticRecvRepositoryRoot(), "tests"), "fixtures")
    projectDirectory := Path.Combine(fixtures, directoryName)
    // Project references build their own Debug/net10.0 outputs. Run that executable because its
    // adjacent runtimeconfig is the launch contract, rather than a copied test-side dependency.
    outputDirectory := Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), "net10.0")
    path := Path.Combine(outputDirectory, assemblyName + ".dll")
    if !File.Exists(path) {
        throw new InvalidOperationException("The project-referenced server executable was not built: " + path)
    }

    runtimeConfig := Path.Combine(Path.GetDirectoryName(path) ?? "", assemblyName + ".runtimeconfig.json")
    if !File.Exists(runtimeConfig) {
        throw new InvalidOperationException("The project-referenced server runtime config was not built: " + runtimeConfig)
    }

    return path
}

func StaticRecvRunShellScript(scriptPath: string, workingDirectory: string, serverDll: string, timeoutMilliseconds: int): StaticRecvShellRun {
    startInfo := new ProcessStartInfo { FileName: "/bin/sh" }
    // ArgumentList avoids reparsing filesystem paths in either the host or the generated shell.
    startInfo.ArgumentList.Add(scriptPath)
    startInfo.ArgumentList.Add(workingDirectory)
    startInfo.ArgumentList.Add(serverDll)
    startInfo.WorkingDirectory = workingDirectory
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()

    timedOut := false
    if !process.WaitForExit(timeoutMilliseconds) {
        timedOut = true
        process.Kill(true)
        process.WaitForExit()
    }

    exitCode := process.ExitCode
    process.Dispose()
    return new StaticRecvShellRun(exitCode, timedOut)
}

func StaticRecvLspScript(): string {
    return """
exec > /dev/null 2>&1
d=$1
dll=$2
mkfifo "$d/in" || exit 90
dotnet "$dll" < "$d/in" > "$d/out" 2> "$d/err" &
server=$!
cleanup() {
    if kill -0 "$server" 2>/dev/null; then
        kill "$server" 2>/dev/null
    fi
    wait "$server" 2>/dev/null
}
trap cleanup EXIT HUP INT TERM
exec 3> "$d/in"
send() { message=$1; printf 'Content-Length: %d\r\n\r\n%s' "${#message}" "$message" >&3; }
send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
waited=0
while ! grep -q '"id":1' "$d/out" 2>/dev/null && [ "$waited" -lt 300 ]; do
    sleep 0.1
    waited=$((waited + 1))
done
grep -q '"id":1' "$d/out" 2>/dev/null || exit 92
send '{"jsonrpc":"2.0","method":"initialized","params":{}}'
send '{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}'
waited=0
while ! grep -q '"id":2' "$d/out" 2>/dev/null && [ "$waited" -lt 300 ]; do
    sleep 0.1
    waited=$((waited + 1))
done
grep -q '"id":2' "$d/out" 2>/dev/null || exit 93
send '{"jsonrpc":"2.0","method":"exit","params":null}'
wait "$server"
rc=$?
exec 3>&-
trap - EXIT HUP INT TERM
exit "$rc"
"""
}

func StaticRecvHeaderEnd(bytes: byte[], start: int): int {
    index := start
    while index + 3 < bytes.Length {
        if bytes[index] == 13 && bytes[index + 1] == 10 && bytes[index + 2] == 13 && bytes[index + 3] == 10 {
            return index
        }
        index = index + 1
    }

    return -1
}

func StaticRecvContentLength(bytes: byte[], start: int, headerEnd: int): int {
    header := Encoding.UTF8.GetString(bytes, start, headerEnd - start)
    lines := header.Split("\r\n")
    index := 0
    while index < lines.Length {
        colon := lines[index].IndexOf(':')
        if colon > 0 && String.Compare(lines[index].Substring(0, colon).Trim(), "Content-Length", StringComparison.OrdinalIgnoreCase) == 0 {
            length := 0
            value := lines[index].Substring(colon + 1).Trim()
            if !int.TryParse(value, out length) || length < 0 {
                throw new InvalidOperationException("The LSP Content-Length header was invalid: " + lines[index])
            }
            return length
        }
        index = index + 1
    }

    throw new InvalidOperationException("The LSP frame did not contain a Content-Length header: " + header)
}

func StaticRecvReadFrames(path: string): List<StaticRecvLspFrame> {
    bytes := File.ReadAllBytes(path)
    frames := new List<StaticRecvLspFrame>()
    offset := 0
    while offset < bytes.Length {
        headerEnd := StaticRecvHeaderEnd(bytes, offset)
        if headerEnd < 0 {
            throw new InvalidOperationException("The LSP output ended in an incomplete header.")
        }

        length := StaticRecvContentLength(bytes, offset, headerEnd)
        bodyStart := headerEnd + 4
        if length > bytes.Length - bodyStart {
            throw new InvalidOperationException("The LSP output ended before the Content-Length body was complete.")
        }

        frames.Add(new StaticRecvLspFrame(Encoding.UTF8.GetString(bytes, bodyStart, length)))
        offset = bodyStart + length
    }

    return frames
}

func StaticRecvResponseBody(frames: List<StaticRecvLspFrame>, expectedId: int): string {
    response: string? = null
    index := 0
    while index < frames.Count {
        document := JsonDocument.Parse(frames[index].Body)
        try {
            properties := document.RootElement.EnumerateObject()
            while properties.MoveNext() {
                property := properties.Current
                if property.Name == "id" && property.Value.ValueKind == JsonValueKind.Number && property.Value.GetInt32() == expectedId {
                    assert response == null, "LSP emitted multiple responses for id " + expectedId.ToString()
                    response = frames[index].Body
                }
            }
        } finally {
            document.Dispose()
        }
        index = index + 1
    }

    if response == null {
        throw new InvalidOperationException("The LSP output did not contain a response for id " + expectedId.ToString())
    }

    return response ?? ""
}

func StaticRecvAssertInitializeResponse(frames: List<StaticRecvLspFrame>, expectedAssemblyName: string) {
    document := JsonDocument.Parse(StaticRecvResponseBody(frames, 1))
    try {
        root := document.RootElement
        assert root.GetProperty("id").GetInt32() == 1
        result := root.GetProperty("result")
        capabilities := result.GetProperty("capabilities")
        assert capabilities.ValueKind == JsonValueKind.Object
        assert capabilities.GetProperty("workspace").ValueKind == JsonValueKind.Object
        serverInfo := result.GetProperty("serverInfo")
        assert serverInfo.GetProperty("name").GetString() == expectedAssemblyName
    } finally {
        document.Dispose()
    }
}

func StaticRecvAssertShutdownResponse(frames: List<StaticRecvLspFrame>) {
    document := JsonDocument.Parse(StaticRecvResponseBody(frames, 2))
    try {
        root := document.RootElement
        assert root.GetProperty("id").GetInt32() == 2
        assert root.GetProperty("result").ValueKind == JsonValueKind.Null
    } finally {
        document.Dispose()
    }
}

func StaticRecvFailureText(directory: string): string {
    outputPath := Path.Combine(directory, "out")
    errorPath := Path.Combine(directory, "err")
    output := File.Exists(outputPath) ? File.ReadAllText(outputPath) : ""
    error := File.Exists(errorPath) ? File.ReadAllText(errorPath) : ""
    return output + error
}

func StaticRecvAssertServerInitialize(directoryName: string, assemblyName: string) {
    // Quotes and spaces exercise the ArgumentList boundary between this harness and /bin/sh.
    directory := Path.Combine(Path.GetTempPath(), "nsharp staticrecv runtime 'quoted' " + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    scriptPath := Path.Combine(directory, "handshake.sh")
    try {
        serverDll := StaticRecvFixtureDll(directoryName, assemblyName)
        File.WriteAllText(scriptPath, StaticRecvLspScript())
        run := StaticRecvRunShellScript(scriptPath, directory, serverDll, 45000)
        assert !run.TimedOut, "server did not finish its initialize/shutdown/exit exchange: " + StaticRecvFailureText(directory)
        assert run.ExitCode == 0, "server did not cleanly exit after shutdown/exit (" + run.ExitCode.ToString() + "): " + StaticRecvFailureText(directory)
        frames := StaticRecvReadFrames(Path.Combine(directory, "out"))
        StaticRecvAssertInitializeResponse(frames, assemblyName)
        StaticRecvAssertShutdownResponse(frames)
    } finally {
        Directory.Delete(directory, true)
    }
}

[UnixLspFact]
test "an inline reflected configuration delegate starts OmniSharp and answers initialize" {
    StaticRecvAssertServerInitialize("staticrecv-runtime-inline", "NSharpLang.StaticRecvRuntimeInline")
}

[UnixLspFact]
test "a typed reflected configuration delegate starts OmniSharp and answers initialize" {
    StaticRecvAssertServerInitialize("staticrecv-runtime-typed", "NSharpLang.StaticRecvRuntimeTyped")
}

test "custom and source-closed delegates execute through external static calls" {
    assert StaticRecvDelegateFacts.CustomDelegateOrder() == 321
    assert StaticRecvDelegateFacts.SourceClosedDelegateTotal() == 11
    assert typeof(StaticRecvTypedMarker).Assembly.GetName().Name == "NSharpLang.StaticRecvRuntimeTyped"
}
