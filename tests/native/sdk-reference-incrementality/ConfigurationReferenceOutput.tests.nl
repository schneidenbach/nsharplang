namespace NSharpLang.SdkReferenceIncrementality.Tests

import System.IO

// A RELEASE BUILD BINDS THE RELEASE OUTPUT OF THE PROJECT IT REFERENCES.
//
// The analysis reaches a bare `project:` entry by probing `bin/Debug/<tfm>`, whatever configuration
// is being built, and that probe used to win over the output MSBuild resolved and handed the emit
// task. So a Release build read whatever Debug build sat beside it: measured, `dotnet build -c
// Release` of `NSharpLang.TestHost` failed with NL301 on `CliError` because
// `src/NSharpLang.Compiler/bin/Debug` held a months-old `Compiler.dll`. The task now drops every
// `project:` entry MSBuild resolved (`SdkEmitTaskKernels.RemoveResolvedProjectReferences`).
//
// The row makes the Debug output STALE on purpose: A and B build in Debug, then B gains a public
// member that A starts calling, and only the Release build ever compiles that B.
func ConfigurationConsumerCallingRepeat(): string {
    return "namespace LabA\n" + "\n" + "import LabB\n" + "\n" + "class Caller {\n" + "    static func Run(): string {\n" + "        greeter := new Greeter(\"world\")\n" + "        return greeter.Repeat(2)\n" + "    }\n" + "}\n"
}

func ConfigurationOutputPath(root: string, project: string, configuration: string): string {
    return Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, project), "bin"), configuration), "net10.0"), project + ".dll")
}

test "a Release build binds a referenced project's Release output, never a stale Debug one" {
    repositoryRoot := IncrementalityRepositoryRoot()
    IncrementalityPrepareFeed(repositoryRoot)
    scratch := IncrementalityScratch("configuration")
    try {
        IncrementalityWriteResolution(scratch)
        IncrementalityWritePair(scratch, IncrementalityOriginalBody(), IncrementalityNoExtraMember())

        debug := IncrementalityBuildConsumer(scratch)
        IncrementalityRequireSuccess(debug, "Debug build of A")
        staleLibrary := ConfigurationOutputPath(scratch, "B", "Debug")
        assert File.Exists(staleLibrary)
        staleBytes := File.ReadAllBytes(staleLibrary)

        IncrementalityWriteLibrary(scratch, IncrementalityOriginalBody(), IncrementalityExtraMember())
        File.WriteAllText(Path.Combine(Path.Combine(scratch, "A"), "Consumer.nl"), ConfigurationConsumerCallingRepeat())

        release := IncrementalityRunInCache("build A.csproj -c Release -v n --nologo --disable-build-servers", Path.Combine(scratch, "A"), IncrementalityPackages(scratch))
        IncrementalityRequireSuccess(release, "Release build of A after B gained Repeat")
        assert File.Exists(ConfigurationOutputPath(scratch, "A", "Release"))

        // The Debug B is still the same bytes, so it still lacks `Repeat`, and the build above can
        // only have passed by binding the Release B that MSBuild resolved.
        currentBytes := File.ReadAllBytes(staleLibrary)
        assert currentBytes.Length == staleBytes.Length, "bin/Debug/B.dll was rebuilt"
        index := 0
        while index < staleBytes.Length {
            assert currentBytes[index] == staleBytes[index], "bin/Debug/B.dll changed at byte " + index.ToString()
            index = index + 1
        }
    } finally {
        Directory.Delete(scratch, true)
    }
}
