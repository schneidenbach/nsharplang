namespace NSharpLang.SdkReferenceIncrementality.Tests

import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

// THE COMPILER PAIRS EVERY REFERENCE IMAGE THIS TREE'S SDK WRITES WITH THE IMPLEMENTATION IT WRITES.
//
// A project reference arrives as the image in `obj/.../ref` or `refint`, and the compiler recovers the
// implementation it emits against from where the SDK put it. The SDK gives the tested project its own
// `obj/tests-included/` and `bin/tests-included/`, and the pairing counted a fixed three directories up
// to `obj`, so it knew only `obj/<configuration>/<tfm>/`: the tested project's own image paired with
// nothing. Compiler.Core's estate reads exactly that pairing for its own host, and because Core builds
// through the SEED's SDK the mismatch surfaced only when a reseed carried the new layout (ninth reseed,
// step 8, five rows). This row builds a library both ways with THIS tree's SDK, so the next layout
// change fails here, before any reseed.
func PairingImagePairs(library: string, tree: string): string {
    referencePath := Path.Combine(Path.Combine(Path.Combine(library, "obj"), tree), "refint/Lib.dll")
    runtimePath := Path.Combine(Path.Combine(Path.Combine(library, "bin"), tree), "Lib.dll")
    if !File.Exists(referencePath) || !File.Exists(runtimePath) {
        return tree + ": the SDK did not write " + referencePath + " and " + runtimePath
    }

    dependencies := new List<Reference>()
    reference := new Reference()
    reference.Dll = referencePath
    dependencies.Add(reference)

    paths := ExternalAssemblyScan.ResolveReferencePaths(library, dependencies)
    if paths.Count != 2 || paths[0] != Path.GetFullPath(referencePath) || paths[1] != Path.GetFullPath(runtimePath) {
        return tree + ": reference paths were [" + string.Join(", ", paths) + "], expected the image then " + runtimePath
    }

    runtimePaths := ExternalAssemblyScan.ResolveRuntimeAssetPaths(library, dependencies)
    if runtimePaths.Count != 1 || runtimePaths[0] != Path.GetFullPath(runtimePath) {
        return tree + ": runtime assets were [" + string.Join(", ", runtimePaths) + "], expected " + runtimePath
    }

    return ""
}

test "the compiler pairs the tested and the product reference images with their own implementations" {
    repositoryRoot := IncrementalityRepositoryRoot()
    IncrementalityPrepareFeed(repositoryRoot)
    scratch := IncrementalityScratch("tests-pairing")
    try {
        ScopeWriteResolution(scratch)
        OutputWriteLibrary(scratch)
        library := Path.Combine(scratch, "Lib")
        flags := " --disable-build-servers -nr:false -v q --nologo"

        IncrementalityRequireSuccess(IncrementalityRunDotnet("build Lib.csproj -p:NSharpExcludeTests=false --force" + flags, library), "tests-included build")
        IncrementalityRequireSuccess(IncrementalityRunDotnet("build Lib.csproj -p:NSharpExcludeTests=true --force" + flags, library), "product build")

        tested := PairingImagePairs(library, "tests-included/Debug/net10.0")
        assert tested == "", tested
        product := PairingImagePairs(library, "Debug/net10.0")
        assert product == "", product
    } finally {
        Directory.Delete(scratch, true)
    }
}
