namespace NSharpLang.SdkReferenceIncrementality.Tests

import System
import System.IO
import NSharpLang.Cli

// TWO N# PROJECTS, A -> B, IN A TEMP DIRECTORY, BUILT BY REAL MSBUILD AGAINST A PRIVATE FEED.
//
// Nothing here reaches the network: the feed holds this tree's `NSharpLang.Sdk` and
// `NSharpLang.Runtime`, the project directory carries its own `global.json` and `NuGet.config` with
// its own throwaway `globalPackagesFolder`, and the only package source is that feed plus the
// ordinary nuget.org entry the SDK's own dependencies would need if the cache were cold. The gate
// packs one feed for the whole sweep and exports it as `NSHARP_SDK_PROJECT_REFERENCE_FEED` /
// `NSHARP_SDK_PROJECT_REFERENCE_VERSION`; this project honours that first and packs its own only
// when nobody handed it one, exactly as `tests/native/sdk-project-reference-boundary` does.
class IncrementalityRun {
    ExitCode: int
    Stdout: string
    Stderr: string
    ElapsedMilliseconds: int

    constructor(exitCode: int, stdout: string, stderr: string, elapsedMilliseconds: int) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
        ElapsedMilliseconds = elapsedMilliseconds
    }
}

// ONE PACK PER PROCESS, UNDER A LOCK, OF A PRIVATE COPY. Every `.tests.nl` file here is its own
// test class and the classes run in parallel, so without the lock two rows that both find the cache
// empty pack at once. And the pack is of COPIES of the Runtime and the SDK project, exactly as
// `tests/native/sdk-project-reference-boundary` does and for the same reason: packing them in place
// writes `src/NSharpLang.Runtime/bin` and `obj`, which any other build of the Runtime running at the
// same moment also writes.
class IncrementalityFeed {
    static Root: string = ""
    static Version: string = ""
    static Gate: object = new object()
}

func IncrementalityRepositoryRoot(): string {
    current: string? = Path.GetFullPath(Environment.CurrentDirectory)
    while current != null {
        candidate := current ?? ""
        if File.Exists(Path.Combine(candidate, "AGENTS.md")) && Directory.Exists(Path.Combine(candidate, "src")) && Directory.Exists(Path.Combine(candidate, "tests")) {
            return candidate
        }

        parent := Path.GetDirectoryName(candidate)
        if parent == null || parent == "" || parent == candidate {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the N# repository root.")
}

func IncrementalityQuote(value: string): string {
    return "\"" + value.Replace("\"", "\\\"") + "\""
}

func IncrementalityRunDotnet(arguments: string, workingDirectory: string): IncrementalityRun {
    started := DateTime.UtcNow
    result := DotnetRunner.RunProcess("dotnet", arguments, workingDirectory, TimeSpan.FromMinutes(10))
    elapsed := DateTime.UtcNow - started
    return new IncrementalityRun(result.ExitCode, result.Stdout, result.Stderr, Convert.ToInt32(elapsed.TotalMilliseconds))
}

func IncrementalityRequireSuccess(result: IncrementalityRun, operation: string) {
    if result.ExitCode != 0 {
        throw new InvalidOperationException(operation + " failed with exit " + result.ExitCode.ToString() + ":\n" + result.Stdout + result.Stderr)
    }
}

func IncrementalityPrepareFeed(root: string) {
    suppliedFeed := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_FEED") ?? ""
    suppliedVersion := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_VERSION") ?? ""
    if suppliedFeed.Length > 0 && suppliedVersion.Length > 0 {
        IncrementalityFeed.Root = suppliedFeed
        IncrementalityFeed.Version = suppliedVersion
        return
    }

    lock IncrementalityFeed.Gate {
        if IncrementalityFeed.Root.Length == 0 {
            IncrementalityPackFeed(root)
        }
    }
}

func IncrementalityCopyTree(source: string, destination: string) {
    Directory.CreateDirectory(destination)
    for sourceFile in Directory.GetFiles(source, "*", SearchOption.AllDirectories) {
        target := Path.Combine(destination, Path.GetRelativePath(source, sourceFile))
        Directory.CreateDirectory(Path.GetDirectoryName(target) ?? destination)
        File.Copy(sourceFile, target, true)
    }
}

// The Runtime's sources and project, the SDK's project and `Sdk/` tree, and Build.Tasks' Release
// output as the SDK's `tools/` payload, copied under the system temp root and packed there; the SDK
// copy is packed with `NoBuild` so it takes the copied payload rather than rebuilding it. Build.Tasks
// is built in place first (Release, the configuration `dotnet pack` builds): that touches
// Build.Tasks, Compiler and Compiler.Core, never the Runtime project, and is a no-op when current.
func IncrementalityPackFeed(root: string) {
    stage := Path.Combine(Path.GetTempPath(), "nsharp-reference-incrementality-pack-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(stage)
    on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
        if Directory.Exists(stage) {
            Directory.Delete(stage, true)
        }
    }

    File.Copy(Path.Combine(root, "global.json"), Path.Combine(stage, "global.json"))
    File.WriteAllText(
        Path.Combine(stage, "NuGet.config"),
        "<configuration><packageSources><clear /><add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" /></packageSources></configuration>"
    )

    source := Path.Combine(root, "src")
    stagedSource := Path.Combine(stage, "src")
    stagedRuntime := Path.Combine(stagedSource, "NSharpLang.Runtime")
    Directory.CreateDirectory(stagedRuntime)
    for runtimeFile in Directory.GetFiles(Path.Combine(source, "NSharpLang.Runtime"), "*", SearchOption.TopDirectoryOnly) {
        extension := Path.GetExtension(runtimeFile)
        if extension == ".cs" || extension == ".csproj" {
            File.Copy(runtimeFile, Path.Combine(stagedRuntime, Path.GetFileName(runtimeFile)))
        }
    }
    stagedSdk := Path.Combine(stagedSource, "NSharpLang.Sdk")
    IncrementalityCopyTree(Path.Combine(Path.Combine(source, "NSharpLang.Sdk"), "Sdk"), Path.Combine(stagedSdk, "Sdk"))
    File.Copy(Path.Combine(Path.Combine(source, "NSharpLang.Sdk"), "NSharpLang.Sdk.csproj"), Path.Combine(stagedSdk, "NSharpLang.Sdk.csproj"))

    tasksDirectory := Path.Combine(source, "NSharpLang.Build.Tasks")
    IncrementalityRequireSuccess(
        IncrementalityRunDotnet("build " + IncrementalityQuote(Path.Combine(tasksDirectory, "NSharpLang.Build.Tasks.csproj")) + " -c Release --disable-build-servers -v q", root),
        "Build.Tasks payload for the private SDK package"
    )
    payload := Path.Combine(Path.Combine("bin", "Release"), "net10.0")
    IncrementalityCopyTree(Path.Combine(tasksDirectory, payload), Path.Combine(Path.Combine(stagedSource, "NSharpLang.Build.Tasks"), payload))

    feed := Path.Combine(stage, "feed")
    Directory.CreateDirectory(feed)
    version := "0.1.0-refincr" + Guid.NewGuid().ToString("N")
    IncrementalityRequireSuccess(
        IncrementalityRunDotnet("pack " + IncrementalityQuote(Path.Combine(stagedRuntime, "NSharpLang.Runtime.csproj")) + " -o " + IncrementalityQuote(feed) + " -p:Version=0.1.0 --disable-build-servers -v q", stage),
        "private Runtime package"
    )
    IncrementalityRequireSuccess(
        IncrementalityRunDotnet("pack " + IncrementalityQuote(Path.Combine(stagedSdk, "NSharpLang.Sdk.csproj")) + " -o " + IncrementalityQuote(feed) + " -p:Version=" + version + " -p:NoBuild=true --disable-build-servers -v q", stage),
        "private SDK package"
    )
    IncrementalityFeed.Root = feed
    IncrementalityFeed.Version = version
}

func IncrementalityScratch(label: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-reference-incrementality-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func IncrementalityWriteResolution(directory: string) {
    File.WriteAllText(
        Path.Combine(directory, "global.json"),
        "{\"sdk\":{\"version\":\"10.0.100\",\"rollForward\":\"latestFeature\"},\"msbuild-sdks\":{\"NSharpLang.Sdk\":\"" + IncrementalityFeed.Version + "\"}}"
    )
    File.WriteAllText(
        Path.Combine(directory, "NuGet.config"),
        "<configuration><config><add key=\"globalPackagesFolder\" value=\"" + Path.Combine(directory, "packages") + "\" /></config><packageSources><clear /><add key=\"reference-incrementality-private\" value=\"" + IncrementalityFeed.Root + "\" /><add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" /></packageSources></configuration>"
    )
}

// B declares a class with one method; A calls it. Both are ordinary N#-SDK projects and A names B
// through `project:`, which `LoadProjectReferences` turns into an MSBuild `ProjectReference`.
func IncrementalityWritePair(root: string, greetingBody: string, extraMember: string) {
    libraryDirectory := Path.Combine(root, "B")
    consumerDirectory := Path.Combine(root, "A")
    Directory.CreateDirectory(libraryDirectory)
    Directory.CreateDirectory(consumerDirectory)

    File.WriteAllText(Path.Combine(libraryDirectory, "B.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    File.WriteAllText(
        Path.Combine(libraryDirectory, "project.yml"),
        "name: B\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    IncrementalityWriteLibrary(root, greetingBody, extraMember)

    File.WriteAllText(Path.Combine(consumerDirectory, "A.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    File.WriteAllText(
        Path.Combine(consumerDirectory, "project.yml"),
        "name: A\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../B/B.csproj\n"
    )
    File.WriteAllText(
        Path.Combine(consumerDirectory, "Consumer.nl"),
        "namespace LabA\n" + "\n" + "import LabB\n" + "\n" + "class Caller {\n" + "    static func Run(): string {\n" + "        greeter := new Greeter(\"world\")\n" + "        return greeter.Greet()\n" + "    }\n" + "}\n"
    )
}

// ONLY B'S ONE SOURCE FILE. Every other file in the pair keeps its timestamp, because MSBuild's
// up-to-date check is a timestamp comparison and rewriting A's own sources would make A out of date
// for a reason that has nothing to do with the claim.
func IncrementalityWriteLibrary(root: string, greetingBody: string, extraMember: string) {
    libraryDirectory := Path.Combine(root, "B")
    File.WriteAllText(
        Path.Combine(libraryDirectory, "Library.nl"),
        "namespace LabB\n" + "\n" + "class Greeter {\n" + "    Name: string\n" + "\n" + "    constructor(name: string) {\n" + "        Name = name\n" + "    }\n" + "\n" + "    func Greet(): string {\n" + greetingBody + "    }\n" + extraMember + "}\n"
    )
}

// `-v n` prints one "Emitting N# IL assembly to …" line per project whose emit target actually ran.
// Counting those lines is the whole claim: a project whose emit was skipped prints nothing.
func IncrementalityEmitted(result: IncrementalityRun, assemblyName: string): bool {
    return result.Stdout.Contains("Emitting N# IL assembly to obj/Debug/net10.0/" + assemblyName + ".dll")
}

func IncrementalityBuildConsumer(root: string): IncrementalityRun {
    return IncrementalityRunDotnet("build A.csproj -v n --nologo --disable-build-servers", Path.Combine(root, "A"))
}
