namespace NSharpLang.SdkReferenceIncrementality.Tests

import System
import System.IO

// A TESTS-INCLUDED BUILD WRITES ITS OWN OUTPUT TREE, NOT THE PRODUCT'S.
//
// The SDK gave the tests-included configuration its own `obj/tests-included/` and left both
// configurations copying into one `bin/Debug/net10.0/`. The files there are written by incremental
// targets that compare timestamps against each configuration's own inputs, so whichever
// configuration wrote last won: Compiler.Core's estate host aborted loading
// Microsoft.TestPlatform.CoreUtilities beside a product deps file after a product build, until a
// manual `rm -rf bin`, and in the other direction the product output carried the tests-included
// assembly and a deps file naming xunit.
//
// One library with one `test` block, built the way Compiler.Core is: product-only
// (`NSharpExcludeTests=true`, which Core's csproj sets) and tests-included (`=false`, which the
// estate passes), interleaved twice with no cleanup in between. Against the SDK without the output
// split this row fails: the product `Lib.dll` declares `LabLib.LibraryTests`.
func OutputWriteLibrary(root: string) {
    directory := Path.Combine(root, "Lib")
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "Lib.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    File.WriteAllText(
        Path.Combine(directory, "project.yml"),
        "name: Lib\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    File.WriteAllText(
        Path.Combine(directory, "Library.nl"),
        "namespace LabLib\n" + "\n" + "class Greeter {\n" + "    static func Greet(name: string): string {\n" + "        return \"hello \" + name\n" + "    }\n" + "}\n"
    )
    File.WriteAllText(
        Path.Combine(directory, "Library.tests.nl"),
        "namespace LabLib\n" + "\n" + "test \"the library greets\" {\n" + "    assert Greeter.Greet(\"lib\") == \"hello lib\"\n" + "}\n"
    )
}

func OutputAssembly(root: string, segments: string): string {
    path := Path.Combine(Path.Combine(root, "Lib"), "bin")
    for segment in segments.Split('/') {
        path = Path.Combine(path, segment)
    }
    return Path.Combine(path, "Lib.dll")
}

func OutputRequireOneTestPassed(result: IncrementalityRun, operation: string) {
    IncrementalityRequireSuccess(result, operation)
    if !result.Stdout.Contains("Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1") {
        throw new InvalidOperationException(operation + " did not report exactly one passing test:\n" + result.Stdout + result.Stderr)
    }
}

test "a product build between tests-included builds leaves the test run working and the product output free of tests" {
    repositoryRoot := IncrementalityRepositoryRoot()
    IncrementalityPrepareFeed(repositoryRoot)
    scratch := IncrementalityScratch("tests-output")
    try {
        ScopeWriteResolution(scratch)
        OutputWriteLibrary(scratch)
        library := Path.Combine(scratch, "Lib")
        flags := " --disable-build-servers -nr:false -v q --nologo"

        IncrementalityRequireSuccess(IncrementalityRunInCache("restore Lib.csproj -p:NSharpExcludeTests=false --force-evaluate" + flags, library, IncrementalityPackages(scratch)), "tests-included restore")
        // The product build RE-RESOLVES (`--force`), as a product build does whenever its inputs move,
        // so its deps file is written after the tests-included assets.
        round := 1
        while round <= 2 {
            label := " (round " + round.ToString() + ")"
            IncrementalityRequireSuccess(IncrementalityRunInCache("build Lib.csproj -p:NSharpExcludeTests=true --force" + flags, library, IncrementalityPackages(scratch)), "product build" + label)
            OutputRequireOneTestPassed(
                IncrementalityRunInCache("test Lib.csproj -p:NSharpExcludeTests=false --no-restore" + flags, library, IncrementalityPackages(scratch)),
                "tests-included test run" + label
            )
            round = round + 1
        }

        // After a test run, the product output still declares the library and nothing from its
        // tests, and its deps file names no test framework; the tests-included output, in its own
        // tree, declares both - so the absence is the separation, not a test block that lowered to
        // nothing.
        productNames := ScopeTypeNames(OutputAssembly(scratch, "Debug/net10.0"))
        assert productNames.Contains("LabLib.Greeter"), string.Join(",", productNames)
        assert !productNames.Contains("LabLib.LibraryTests"), string.Join(",", productNames)
        productDeps := File.ReadAllText(Path.Combine(Path.Combine(Path.Combine(Path.Combine(library, "bin"), "Debug"), "net10.0"), "Lib.deps.json"))
        assert !productDeps.Contains("xunit", StringComparison.OrdinalIgnoreCase), productDeps
        testNames := ScopeTypeNames(OutputAssembly(scratch, "tests-included/Debug/net10.0"))
        assert testNames.Contains("LabLib.Greeter"), string.Join(",", testNames)
        assert testNames.Contains("LabLib.LibraryTests"), string.Join(",", testNames)
    } finally {
        Directory.Delete(scratch, true)
    }
}

// A PROJECT.YML CAN KEEP ITS OWN TESTS OUT OF THE PRODUCT BUILD. The same library, saying
// `excludeTests: true`, is built with NO flag -- the way every consumer's build reaches a compiler
// slice -- and must come out product-only: no test type, no test framework in its deps file, and
// still a library (the test SDK turns a tests-included project into an executable). The estate's
// explicit `-p:NSharpExcludeTests=false` must still bring its one row back. Against the SDK without
// the key the flagless build declares `LabLib.LibraryTests`.
test "a project.yml that says excludeTests builds product-only without a flag, and the estate's flag still runs its rows" {
    repositoryRoot := IncrementalityRepositoryRoot()
    IncrementalityPrepareFeed(repositoryRoot)
    scratch := IncrementalityScratch("tests-excluded")
    try {
        ScopeWriteResolution(scratch)
        OutputWriteLibrary(scratch)
        library := Path.Combine(scratch, "Lib")
        projectFile := Path.Combine(library, "project.yml")
        File.WriteAllText(projectFile, File.ReadAllText(projectFile) + "excludeTests: true\n")
        flags := " --disable-build-servers -nr:false -v q --nologo"

        IncrementalityRequireSuccess(IncrementalityRunInCache("build Lib.csproj" + flags, library, IncrementalityPackages(scratch)), "flagless build")
        productDirectory := Path.Combine(Path.Combine(Path.Combine(library, "bin"), "Debug"), "net10.0")
        productNames := ScopeTypeNames(OutputAssembly(scratch, "Debug/net10.0"))
        assert productNames.Contains("LabLib.Greeter"), string.Join(",", productNames)
        assert !productNames.Contains("LabLib.LibraryTests"), string.Join(",", productNames)
        productDeps := File.ReadAllText(Path.Combine(productDirectory, "Lib.deps.json"))
        assert !productDeps.Contains("xunit", StringComparison.OrdinalIgnoreCase), productDeps
        assert !File.Exists(Path.Combine(productDirectory, "Lib.runtimeconfig.json")), "a product-only library has no runtime configuration of its own"

        IncrementalityRequireSuccess(IncrementalityRunInCache("restore Lib.csproj -p:NSharpExcludeTests=false --force-evaluate" + flags, library, IncrementalityPackages(scratch)), "tests-included restore")
        OutputRequireOneTestPassed(
            IncrementalityRunInCache("test Lib.csproj -p:NSharpExcludeTests=false --no-restore" + flags, library, IncrementalityPackages(scratch)),
            "tests-included test run"
        )
    } finally {
        Directory.Delete(scratch, true)
    }
}

// The mechanism, pinned where it is written: the output root is chosen under exactly the condition the
// intermediate root is, and both before the base SDK's props decide the paths derived from them.
test "the SDK gives the tests-included configuration its own output root beside its own intermediate root" {
    props := File.ReadAllText(Path.Combine(Path.Combine(Path.Combine(Path.Combine(IncrementalityRepositoryRoot(), "src"), "NSharpLang.Sdk"), "Sdk"), "Sdk.props"))
    intermediate := props.IndexOf("<BaseIntermediateOutputPath>obj/tests-included/</BaseIntermediateOutputPath>", StringComparison.Ordinal)
    output := props.IndexOf("<BaseOutputPath>bin/tests-included/</BaseOutputPath>", StringComparison.Ordinal)
    baseImport := props.IndexOf("<Import Project=\"Sdk.props\" Sdk=\"$(_NSharpBaseSdk)\" />", StringComparison.Ordinal)
    assert intermediate > 0 && intermediate < output && output < baseImport, props
    assert props.Contains("'$(NSharpExcludeTests)' == 'false' And '$(_NSharpReferencedByTestedProject)' != 'true' And '$(BaseOutputPath)' == ''"), props
}
