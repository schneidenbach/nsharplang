namespace NSharpLang.SdkReferenceIncrementality.Tests

import System
import System.Collections.Generic
import System.IO
import System.Reflection.Metadata
import System.Reflection.PortableExecutable

// A TESTS-INCLUDED BUILD INCLUDES THE TESTS OF THE PROJECT BEING TESTED, AND NOBODY ELSE'S.
//
// `-p:NSharpExcludeTests=false` is a global property, and MSBuild passes global properties down the
// whole `ProjectReference` closure, restore walk included. So testing A used to build B tests-included
// as well: B's `.tests.nl` compiled into the `B.dll` A references, and B's test free functions got a
// `Program` holder of their own. Give A's and B's tests one namespace - which is exactly what the
// Compiler.Core slices will have, all of them testing in `NSharpLang.Compiler` - and A's compilation
// sees two `Shared.Checks.Program`s. The SDK now names the tested project (`_NSharpTestedProject`,
// Sdk.props) and every project that receives someone else's name builds product-only.
//
// Same pair of projects and the same private feed as the incrementality row beside this file, plus
// one `.tests.nl` in each, both declaring a free function in the SAME namespace.
func ScopeWritePair(root: string) {
    IncrementalityWritePair(root, "        return \"hello \" + Name\n", "")
    File.WriteAllText(
        Path.Combine(Path.Combine(root, "B"), "Library.tests.nl"),
        "namespace Shared.Checks\n" + "\n" + "import LabB\n" + "\n" + "func GreetingOf(name: string): string {\n" + "    return new Greeter(name).Greet()\n" + "}\n" + "\n" + "test \"B greets\" {\n" + "    assert GreetingOf(\"b\") == \"hello b\"\n" + "}\n"
    )
    File.WriteAllText(
        Path.Combine(Path.Combine(root, "A"), "Consumer.tests.nl"),
        "namespace Shared.Checks\n" + "\n" + "import LabA\n" + "\n" + "func RunOf(): string {\n" + "    return Caller.Run()\n" + "}\n" + "\n" + "test \"A runs\" {\n" + "    assert RunOf() == \"hello world\"\n" + "}\n"
    )
}

// The test framework packages a tests-included build restores come from the machine's own package
// cache before nuget.org - so the row does not depend on the network for packages the gate has
// already restored - and every `NSharpLang.*` package comes from the private feed ONLY: the cache
// holds the committed seed's `NSharpLang.Runtime 0.1.0` too, and two sources answering one identity
// would make the row's answer depend on which one replied first.
func ScopeWriteResolution(directory: string) {
    IncrementalityWriteResolution(directory)
    localCache := Environment.GetEnvironmentVariable("NUGET_PACKAGES") ?? ""
    if localCache.Length == 0 {
        localCache = Path.Combine(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget"), "packages")
    }
    File.WriteAllText(
        Path.Combine(directory, "NuGet.config"),
        "<configuration><config><add key=\"globalPackagesFolder\" value=\"" + IncrementalityPackages(directory) + "\" /></config>" + "<packageSources><clear /><add key=\"scope-private\" value=\"" + IncrementalityFeed.Root + "\" /><add key=\"scope-local-cache\" value=\"" + localCache + "\" /><add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" /></packageSources>" + "<packageSourceMapping><packageSource key=\"scope-private\"><package pattern=\"NSharpLang.*\" /></packageSource><packageSource key=\"scope-local-cache\"><package pattern=\"*\" /></packageSource><packageSource key=\"nuget.org\"><package pattern=\"*\" /></packageSource></packageSourceMapping></configuration>"
    )
}

func ScopeBuildTestsIncluded(root: string, project: string): IncrementalityRun {
    return IncrementalityRunInCache("build " + project + ".csproj -p:NSharpExcludeTests=false -v n --nologo --disable-build-servers", Path.Combine(root, project), IncrementalityPackages(root))
}

func ScopeObj(root: string, project: string, segments: string): string {
    path := Path.Combine(Path.Combine(root, project), "obj")
    for segment in segments.Split('/') {
        path = Path.Combine(path, segment)
    }
    return path
}

// Every type an assembly defines, as `Namespace.Name`, read from metadata so nothing is loaded.
func ScopeTypeNames(assemblyPath: string): List<string> {
    names := new List<string>()
    stream := File.OpenRead(assemblyPath)
    try {
        reader := new PEReader(stream)
        try {
            metadata := reader.GetMetadataReader()
            for handle in metadata.TypeDefinitions {
                typeDefinition := metadata.GetTypeDefinition(handle)
                names.Add(metadata.GetString(typeDefinition.Namespace) + "." + metadata.GetString(typeDefinition.Name))
            }
        } finally {
            reader.Dispose()
        }
    } finally {
        stream.Dispose()
    }
    return names
}

func ScopeNamesIn(names: List<string>, namespacePrefix: string): string {
    matching := new List<string>()
    for name in names {
        if name.StartsWith(namespacePrefix, StringComparison.Ordinal) {
            matching.Add(name)
        }
    }
    return string.Join(",", matching)
}

test "testing a project builds its project references product-only, so no referenced assembly carries tests or a second holder" {
    repositoryRoot := IncrementalityRepositoryRoot()
    IncrementalityPrepareFeed(repositoryRoot)
    scratch := IncrementalityScratch("tests-scope")
    try {
        ScopeWriteResolution(scratch)
        ScopeWritePair(scratch)

        tested := ScopeBuildTestsIncluded(scratch, "A")
        IncrementalityRequireSuccess(tested, "tests-included build of A")

        // A - the project the flag was given to - is tests-included, in its own intermediate tree.
        assert tested.Stdout.Contains("Emitting N# IL assembly to obj/tests-included/Debug/net10.0/A.dll"), tested.Stdout
        testedAssembly := Path.Combine(ScopeObj(scratch, "A", "tests-included/Debug/net10.0"), "A.dll")
        assert ScopeNamesIn(ScopeTypeNames(testedAssembly), "Shared.Checks.").Contains("Shared.Checks.Program"), ScopeNamesIn(ScopeTypeNames(testedAssembly), "Shared.Checks.")

        // B - its reference - is the product B, restored and emitted in the ordinary `obj/`.
        assert tested.Stdout.Contains("Emitting N# IL assembly to obj/Debug/net10.0/B.dll"), tested.Stdout
        assert !tested.Stdout.Contains("Emitting N# IL assembly to obj/tests-included/Debug/net10.0/B.dll"), tested.Stdout
        assert !Directory.Exists(ScopeObj(scratch, "B", "tests-included")), "B was restored or built tests-included"
        assert File.Exists(ScopeObj(scratch, "B", "project.assets.json")), "B's product-only restore is missing"

        // The B that A was compiled against and ships beside it - in A's own tests-included output
        // tree - declares nothing from B's tests.
        shippedLibrary := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(scratch, "A"), "bin"), "tests-included"), "Debug"), "net10.0"), "B.dll")
        libraryNames := ScopeTypeNames(shippedLibrary)
        assert libraryNames.Contains("LabB.Greeter"), string.Join(",", libraryNames)
        assert ScopeNamesIn(libraryNames, "Shared.Checks.") == "", ScopeNamesIn(libraryNames, "Shared.Checks.")

        // And across everything A's output directory holds, each holder is declared exactly once.
        holders := new HashSet<string>(StringComparer.Ordinal)
        duplicates := new List<string>()
        for assemblyPath in [Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(scratch, "A"), "bin"), "tests-included"), "Debug"), "net10.0"), "A.dll"), shippedLibrary] {
            for name in ScopeTypeNames(assemblyPath) {
                if name.EndsWith(".Program", StringComparison.Ordinal) || name.EndsWith(".<Program>", StringComparison.Ordinal) {
                    if !holders.Add(name) {
                        duplicates.Add(name)
                    }
                }
            }
        }
        assert duplicates.Count == 0, string.Join(",", duplicates)

        // THE CONTROL: the same B, given the flag itself, IS tests-included and DOES declare the
        // holder - so its absence above is the scoping, not a fixture whose tests emit nothing.
        control := ScopeBuildTestsIncluded(scratch, "B")
        IncrementalityRequireSuccess(control, "tests-included build of B")
        controlAssembly := Path.Combine(ScopeObj(scratch, "B", "tests-included/Debug/net10.0"), "B.dll")
        assert ScopeNamesIn(ScopeTypeNames(controlAssembly), "Shared.Checks.").Contains("Shared.Checks.Program"), ScopeNamesIn(ScopeTypeNames(controlAssembly), "Shared.Checks.")
    } finally {
        Directory.Delete(scratch, true)
    }
}

// The mechanism, pinned where it is written: the name is recorded BEFORE the intermediate-tree
// discriminator reads it (evaluation order is the whole point in a props file), both the discriminator
// and the test glob stand down for a reference, and the name rides BOTH walks - a build-only fix would
// leave the restore walk giving B a tests-included `obj/` its product build then cannot find.
test "the SDK records the tested project before its intermediate tree is chosen and passes the name down both reference walks" {
    sdkDirectory := Path.Combine(Path.Combine(Path.Combine(IncrementalityRepositoryRoot(), "src"), "NSharpLang.Sdk"), "Sdk")
    props := File.ReadAllText(Path.Combine(sdkDirectory, "Sdk.props"))
    targets := File.ReadAllText(Path.Combine(sdkDirectory, "Sdk.targets"))

    recorded := props.IndexOf("<_NSharpTestedProject>$(MSBuildProjectFullPath)</_NSharpTestedProject>", StringComparison.Ordinal)
    referenced := props.IndexOf("<_NSharpReferencedByTestedProject>true</_NSharpReferencedByTestedProject>", StringComparison.Ordinal)
    discriminator := props.IndexOf("<BaseIntermediateOutputPath>obj/tests-included/</BaseIntermediateOutputPath>", StringComparison.Ordinal)
    baseImport := props.IndexOf("<Import Project=\"Sdk.props\" Sdk=\"$(_NSharpBaseSdk)\" />", StringComparison.Ordinal)
    assert recorded > 0 && recorded < referenced && referenced < discriminator && discriminator < baseImport, props
    assert props.Contains("'$(NSharpExcludeTests)' == 'false' And '$(_NSharpReferencedByTestedProject)' != 'true' And '$(BaseIntermediateOutputPath)' == ''")

    assert targets.Contains("'$(NSharpExcludeTests)' != 'true' And '$(_NSharpReferencedByTestedProject)' != 'true'\">\n    <NSharpTestFiles Include=\"**/*.tests.nl\""), targets
    assert targets.Contains("<AdditionalProperties>%(AdditionalProperties);_NSharpTestedProject=$(_NSharpTestedProject)</AdditionalProperties>"), targets
    assert targets.Contains("<_GenerateRestoreGraphProjectEntryInputProperties>$(_GenerateRestoreGraphProjectEntryInputProperties);_NSharpTestedProject=$(_NSharpTestedProject)</_GenerateRestoreGraphProjectEntryInputProperties>"), targets
}
