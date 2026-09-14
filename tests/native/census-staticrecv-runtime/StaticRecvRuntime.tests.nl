namespace NSharpLang.CensusStaticRecvRuntime.Tests

import System
import System.Diagnostics
import System.IO
import System.Text.Json
import NSharpLang.StaticRecvRuntime.Inline
import NSharpLang.StaticRecvRuntime.Typed

class StaticRecvShellRun {
    ExitCode: int
    TimedOut: bool

    constructor(exitCode: int, timedOut: bool) {
        ExitCode = exitCode
        TimedOut = timedOut
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

func StaticRecvIsUnix(): bool {
    return OperatingSystem.IsMacOS() || OperatingSystem.IsLinux()
}

func StaticRecvFixtureDll(directoryName: string, assemblyName: string): string {
    fixtures := Path.Combine(Path.Combine(StaticRecvRepositoryRoot(), "tests"), "fixtures")
    projectDirectory := Path.Combine(fixtures, directoryName)
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

func StaticRecvRunShellScript(scriptPath: string, workingDirectory: string, timeoutMilliseconds: int): StaticRecvShellRun {
    startInfo := new ProcessStartInfo { FileName: "/bin/sh", Arguments: "\"" + scriptPath + "\"" }
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

func StaticRecvLspScript(directory: string, serverDll: string): string {
    template := """
exec > /dev/null 2>&1
d="@DIRECTORY@"
mkfifo "$d/in" || exit 90
dotnet "@DLL@" < "$d/in" > "$d/out" 2> "$d/err" &
server=$!
cleanup() {
    if kill -0 "$server" 2>/dev/null; then
        kill "$server" 2>/dev/null
    fi
    wait "$server" 2>/dev/null
}
trap cleanup EXIT HUP INT TERM
exec 3> "$d/in"
message='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
printf 'Content-Length: %d\r\n\r\n%s' "${#message}" "$message" >&3
waited=0
while ! grep -q '"id":1' "$d/out" 2>/dev/null && [ "$waited" -lt 300 ]; do
    sleep 0.1
    waited=$((waited + 1))
done
grep -q '"id":1' "$d/out" 2>/dev/null || exit 92
message='{"jsonrpc":"2.0","method":"exit","params":null}'
printf 'Content-Length: %d\r\n\r\n%s' "${#message}" "$message" >&3
wait "$server"
rc=$?
exec 3>&-
trap - EXIT HUP INT TERM
exit "$rc"
"""
    return template.Replace("@DIRECTORY@", directory).Replace("@DLL@", serverDll)
}

func StaticRecvFailureText(directory: string): string {
    outputPath := Path.Combine(directory, "out")
    errorPath := Path.Combine(directory, "err")
    output := File.Exists(outputPath) ? File.ReadAllText(outputPath) : ""
    error := File.Exists(errorPath) ? File.ReadAllText(errorPath) : ""
    return output + error
}

func StaticRecvAssertInitializeResponse(directory: string, expectedAssemblyName: string) {
    responsePath := Path.Combine(directory, "out")
    response := File.ReadAllText(responsePath)
    headerEnd := response.IndexOf("\r\n\r\n", StringComparison.Ordinal)
    assert headerEnd >= 0, response

    document := JsonDocument.Parse(response.Substring(headerEnd + 4))
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

func StaticRecvAssertServerInitialize(directoryName: string, assemblyName: string) {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-staticrecv-runtime-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    scriptPath := Path.Combine(directory, "handshake.sh")
    try {
        serverDll := StaticRecvFixtureDll(directoryName, assemblyName)
        File.WriteAllText(scriptPath, StaticRecvLspScript(directory, serverDll))
        run := StaticRecvRunShellScript(scriptPath, directory, 45000)
        assert !run.TimedOut, "server did not finish its initialize/exit exchange: " + StaticRecvFailureText(directory)
        assert run.ExitCode == 0, "server handshake exited " + run.ExitCode.ToString() + ": " + StaticRecvFailureText(directory)
        StaticRecvAssertInitializeResponse(directory, assemblyName)
    } finally {
        Directory.Delete(directory, true)
    }
}

test "an inline reflected configuration delegate starts OmniSharp and answers initialize" {
    if StaticRecvIsUnix() {
        StaticRecvAssertServerInitialize("staticrecv-runtime-inline", "NSharpLang.StaticRecvRuntimeInline")
    }
}

test "a typed reflected configuration delegate starts OmniSharp and answers initialize" {
    if StaticRecvIsUnix() {
        StaticRecvAssertServerInitialize("staticrecv-runtime-typed", "NSharpLang.StaticRecvRuntimeTyped")
    }
}

test "custom and source-closed delegates execute through external static calls" {
    assert StaticRecvDelegateFacts.CustomDelegateOrder() == 321
    assert StaticRecvDelegateFacts.SourceClosedDelegateTotal() == 11
    assert typeof(StaticRecvTypedMarker).Assembly.GetName().Name == "NSharpLang.StaticRecvRuntimeTyped"
}
