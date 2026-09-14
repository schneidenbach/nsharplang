namespace NSharpLang.CompilationBackend.Tests

import System
import System.Collections.Generic
import System.IO
import System.Linq
import System.Security.Cryptography
import System.Text
import System.Threading

// ─── THE PACKED SDK FEED THE SDK-ROUTED ROWS RESTORE FROM ─────────────────────────────────────
//
// A faithful port of the deleted `tests/TestSdkFeed.cs`. The rows that exercise SDK project
// references, `pack`, `publish` and `test --backend il` need an MSBuild SDK on a feed, and the
// repository's own `bootstrap/` seed must never be republished from a test. So the feed is built
// once into a CONTENT-KEYED cache under the temp directory and reused: the key is a SHA-256 over
// every input of the SDK, the runtime and the compiler, so a source change rebuilds it and an
// unchanged tree does not. The key computation is preserved byte-for-byte from the C# (sorted
// ordinal relative paths, each followed by its bytes and a zero separator, then the runtime
// version), so a tree that already has a warm cache keeps it.

class SdkFeedState {
    static FeedPath: string = ""
    static Version: string = ""
    static RuntimeVersion: string = ""
    static Built: bool = false
    static WarmedUp: bool = false
}

// One generous ceiling per feed step: the Build.Tasks step self-emits Compiler Core (~6m20s
// quiet, longer under gate load), so hitting it means a hang, not a slow build. A cache-lock
// waiter must outlast a peer through the WHOLE feed build.
func SdkFeedCommandTimeoutMilliseconds(): int {
    return 20 * 60 * 1000
}

func CacheLockTimeoutMilliseconds(): int {
    return 45 * 60 * 1000
}

func SdkFeedVersion(): string {
    EnsureSdkFeed()
    return SdkFeedState.Version
}

func SdkFeedPath(): string {
    EnsureSdkFeed()
    return SdkFeedState.FeedPath
}

func SdkRuntimeVersion(): string {
    EnsureSdkFeed()
    return SdkFeedState.RuntimeVersion
}

func EnsureSdkFeed() {
    if SdkFeedState.Built {
        return
    }

    BuildSdkFeed()
    SdkFeedState.Built = true
}

// Serializes COLD-START package extraction: concurrent first restores race to extract the same
// Sdk/Runtime nupkgs into a cold NUGET_PACKAGES and MSBuild's SDK resolver intermittently fails on
// that race. One warm-up restore runs first; later restores hit the cache.
func EnsureColdStartWarmup() {
    if SdkFeedState.WarmedUp {
        return
    }

    SdkFeedState.WarmedUp = true
    warmupDirectory := Path.Combine(Path.GetTempPath(), "nsharp-sdk-feed-warmup-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(warmupDirectory)
    try {
        File.WriteAllText(Path.Combine(warmupDirectory, "Warmup.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
        File.WriteAllText(Path.Combine(warmupDirectory, "project.yml"), "name: Warmup\noutputType: library\ntargetFramework: net10.0\n")
        WriteResolutionFilesCore(warmupDirectory)
        exitCode := RunDotnetNoCapture(warmupDirectory, "restore \"" + Path.Combine(warmupDirectory, "Warmup.csproj") + "\" -v q --disable-build-servers", SdkFeedCommandTimeoutMilliseconds())
        if exitCode != 0 {
            throw new InvalidOperationException("SDK feed warm-up restore failed.")
        }
    } finally {
        Directory.Delete(warmupDirectory, true)
    }
}

func WriteSdkResolutionFiles(projectDirectory: string) {
    EnsureColdStartWarmup()
    WriteResolutionFilesCore(projectDirectory)
}

func WriteResolutionFilesCore(projectDirectory: string) {
    File.WriteAllText(
        Path.Combine(projectDirectory, "global.json"),
        "{\n  \"sdk\": {\n    \"version\": \"10.0.100\",\n    \"rollForward\": \"latestFeature\"\n  },\n  \"msbuild-sdks\": {\n    \"NSharpLang.Sdk\": \"" + SdkFeedVersion() + "\"\n  }\n}\n"
    )

    File.WriteAllText(
        Path.Combine(projectDirectory, "NuGet.config"),
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<configuration>\n  <packageSources>\n    <clear />\n    <add key=\"local\" value=\"" + SdkFeedPath() + "\" />\n    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" />\n  </packageSources>\n</configuration>\n"
    )

    File.WriteAllText(
        Path.Combine(projectDirectory, "Directory.Build.props"),
        "<Project>\n  <PropertyGroup>\n    <NSharpLangRuntimeVersion>" + SdkRuntimeVersion() + "</NSharpLangRuntimeVersion>\n  </PropertyGroup>\n</Project>\n"
    )
}

func WriteVersionedSdkProject(projectDirectory: string, projectName: string) {
    File.WriteAllText(Path.Combine(projectDirectory, projectName + ".csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    WriteSdkResolutionFiles(projectDirectory)
}

func BuildSdkFeed() {
    repositoryRoot := RepositoryRoot()
    cacheKey := ComputeSdkFeedCacheKey(repositoryRoot)
    cacheRoot := Path.Combine(Path.GetTempPath(), "nsharp-sdk-feed-cache")
    feedDirectory := Path.Combine(cacheRoot, cacheKey)
    Directory.CreateDirectory(cacheRoot)

    cacheLock := AcquireCacheLock(Path.Combine(cacheRoot, cacheKey + ".lock"))
    try {
        if TryReadCachedSdkFeed(feedDirectory) {
            return
        }

        keyLength := 16
        if cacheKey.Length < keyLength {
            keyLength = cacheKey.Length
        }

        keySuffix := cacheKey.Substring(0, keyLength)
        version := "0.1.0-il" + keySuffix
        runtimeVersion := "0.1.0-runtime" + keySuffix
        temporaryFeedDirectory := Path.Combine(cacheRoot, cacheKey + ".tmp-" + Guid.NewGuid().ToString("N"))
        Directory.CreateDirectory(temporaryFeedDirectory)

        try {
            buildTasksExitCode := RunDotnetNoCapture(
                repositoryRoot,
                "build \"" + Path.Combine(Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Build.Tasks"), "NSharpLang.Build.Tasks.csproj") + "\" -c Release -v q --disable-build-servers",
                SdkFeedCommandTimeoutMilliseconds()
            )
            if buildTasksExitCode != 0 {
                throw new InvalidOperationException("Failed to build NSharp build tasks.")
            }

            runtimePackExitCode := RunDotnetNoCapture(
                repositoryRoot,
                "pack \"" + Path.Combine(Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Runtime"), "NSharpLang.Runtime.csproj") + "\" -c Release -o \"" + temporaryFeedDirectory + "\" -p:Version=" + runtimeVersion + " -v q --disable-build-servers",
                SdkFeedCommandTimeoutMilliseconds()
            )
            if runtimePackExitCode != 0 {
                throw new InvalidOperationException("Failed to pack NSharp runtime.")
            }

            packExitCode := RunDotnetNoCapture(
                repositoryRoot,
                "pack \"" + Path.Combine(Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Sdk"), "NSharpLang.Sdk.csproj") + "\" -c Release -o \"" + temporaryFeedDirectory + "\" -p:Version=" + version + " -v q --disable-build-servers",
                SdkFeedCommandTimeoutMilliseconds()
            )
            if packExitCode != 0 {
                throw new InvalidOperationException("Failed to pack NSharp SDK.")
            }

            WriteSdkFeedManifest(temporaryFeedDirectory, version, runtimeVersion)
            if Directory.Exists(feedDirectory) {
                Directory.Delete(feedDirectory, true)
            }

            Directory.Move(temporaryFeedDirectory, feedDirectory)
            SdkFeedState.FeedPath = feedDirectory
            SdkFeedState.Version = version
            SdkFeedState.RuntimeVersion = runtimeVersion
        } finally {
            if Directory.Exists(temporaryFeedDirectory) {
                Directory.Delete(temporaryFeedDirectory, true)
            }
        }
    } finally {
        cacheLock.Dispose()
    }
}

func AcquireCacheLock(lockPath: string): FileStream {
    stopwatch := System.Diagnostics.Stopwatch.StartNew()
    while true {
        try {
            return new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None)
        } catch (error: IOException) {
            if stopwatch.ElapsedMilliseconds >= CacheLockTimeoutMilliseconds() {
                throw new TimeoutException("Waited " + stopwatch.ElapsedMilliseconds.ToString() + " ms for the SDK feed cache lock at " + lockPath + ": " + error.Message)
            }

            Thread.Sleep(100)
        }
    }
}

func TryReadCachedSdkFeed(feedDirectory: string): bool {
    manifestPath := Path.Combine(feedDirectory, "nsharp-test-sdk-feed.txt")
    if !File.Exists(manifestPath) {
        return false
    }

    version := ""
    runtimeVersion := ""
    for line in File.ReadAllLines(manifestPath) {
        separator := line.IndexOf("=")
        if separator <= 0 {
            continue
        }

        key := line.Substring(0, separator)
        value := line.Substring(separator + 1)
        if key == "version" {
            version = value
        } else if key == "runtimeVersion" {
            runtimeVersion = value
        }
    }

    if version == "" || runtimeVersion == "" {
        return false
    }

    if !File.Exists(Path.Combine(feedDirectory, "NSharpLang.Sdk." + version + ".nupkg")) {
        return false
    }

    if !File.Exists(Path.Combine(feedDirectory, "NSharpLang.Runtime." + runtimeVersion + ".nupkg")) {
        return false
    }

    SdkFeedState.FeedPath = feedDirectory
    SdkFeedState.Version = version
    SdkFeedState.RuntimeVersion = runtimeVersion
    return true
}

func WriteSdkFeedManifest(feedDirectory: string, version: string, runtimeVersion: string) {
    File.WriteAllText(Path.Combine(feedDirectory, "nsharp-test-sdk-feed.txt"), "version=" + version + "\nruntimeVersion=" + runtimeVersion + "\n")
}

func ComputeSdkFeedCacheKey(repositoryRoot: string): string {
    sha := SHA256.Create()
    try {
        inputs := EnumerateSdkFeedInputs(repositoryRoot)
        for path in inputs.OrderBy(candidate => candidate, StringComparer.Ordinal) {
            relative := Path.GetRelativePath(repositoryRoot, path).Replace("\\", "/")
            UpdateHash(sha, relative)
            stream := File.OpenRead(path)
            try {
                buffer := new byte[64 * 1024]
                read := stream.Read(buffer, 0, buffer.Length)
                while read > 0 {
                    sha.TransformBlock(buffer, 0, read, null, 0)
                    read = stream.Read(buffer, 0, buffer.Length)
                }
            } finally {
                stream.Dispose()
            }

            separator: byte[] = [0]
            sha.TransformBlock(separator, 0, 1, null, 0)
        }

        UpdateHash(sha, Environment.Version.ToString())
        sha.TransformFinalBlock(new byte[0], 0, 0)
        return Convert.ToHexString(sha.Hash ?? new byte[0]).ToLowerInvariant()
    } finally {
        sha.Dispose()
    }
}

func UpdateHash(hash: HashAlgorithm, value: string) {
    bytes := Encoding.UTF8.GetBytes(value)
    hash.TransformBlock(bytes, 0, bytes.Length, null, 0)
    separator: byte[] = [0]
    hash.TransformBlock(separator, 0, 1, null, 0)
}

func EnumerateSdkFeedInputs(repositoryRoot: string): List<string> {
    sourceRoot := Path.Combine(repositoryRoot, "src")
    roots := [
        Path.Combine(sourceRoot, "NSharpLang.Compiler.Core"),
        Path.Combine(sourceRoot, "NSharpLang.Compiler"),
        Path.Combine(sourceRoot, "NSharpLang.Build.Tasks"),
        Path.Combine(sourceRoot, "NSharpLang.Runtime"),
        Path.Combine(sourceRoot, "NSharpLang.Sdk")
    ]
    rootFiles := [
        Path.Combine(repositoryRoot, "global.json"),
        Path.Combine(repositoryRoot, "Directory.Build.props"),
        Path.Combine(repositoryRoot, "Directory.Build.targets"),
        Path.Combine(repositoryRoot, "NuGet.config")
    ]

    inputs := new List<string>()
    for root in roots {
        if !Directory.Exists(root) {
            continue
        }

        for path in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories) {
            if !IsUnderBuildOutputDirectory(path) {
                inputs.Add(path)
            }
        }
    }

    for path in rootFiles {
        if File.Exists(path) {
            inputs.Add(path)
        }
    }

    return inputs
}

func IsUnderBuildOutputDirectory(path: string): bool {
    separators := [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar]
    for part in path.Split(separators) {
        if string.Equals(part, "bin", StringComparison.OrdinalIgnoreCase) || string.Equals(part, "obj", StringComparison.OrdinalIgnoreCase) {
            return true
        }
    }

    return false
}

func RunDotnetNoCapture(workingDirectory: string, arguments: string, timeoutMilliseconds: int): int {
    startInfo := new System.Diagnostics.ProcessStartInfo { FileName: "dotnet", Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = false
    startInfo.RedirectStandardError = false
    startInfo.UseShellExecute = false

    process := new System.Diagnostics.Process { StartInfo: startInfo }
    process.Start()
    if !process.WaitForExit(timeoutMilliseconds) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("Process 'dotnet " + arguments + "' did not complete within " + timeoutMilliseconds.ToString() + " ms.")
    }

    exitCode := process.ExitCode
    process.Dispose()
    return exitCode
}
