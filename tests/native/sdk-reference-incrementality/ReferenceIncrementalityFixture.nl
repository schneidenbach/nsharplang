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

class IncrementalityFeed {
    static Root: string = ""
    static Version: string = ""
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

    if IncrementalityFeed.Root.Length > 0 {
        return
    }

    feed := Path.Combine(Path.Combine(root, "artifacts"), "sdk-reference-incrementality-feed-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(feed)
    on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
        if Directory.Exists(feed) {
            Directory.Delete(feed, true)
        }
    }
    version := "0.1.0-refincr" + Guid.NewGuid().ToString("N")
    runtimeProject := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Runtime"), "NSharpLang.Runtime.csproj")
    sdkProject := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Sdk"), "NSharpLang.Sdk.csproj")
    IncrementalityRequireSuccess(
        IncrementalityRunDotnet("pack " + IncrementalityQuote(runtimeProject) + " -o " + IncrementalityQuote(feed) + " -p:Version=0.1.0 --disable-build-servers -v q", root),
        "private Runtime package"
    )
    IncrementalityRequireSuccess(
        IncrementalityRunDotnet("pack " + IncrementalityQuote(sdkProject) + " -o " + IncrementalityQuote(feed) + " -p:Version=" + version + " --disable-build-servers -v q", root),
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
