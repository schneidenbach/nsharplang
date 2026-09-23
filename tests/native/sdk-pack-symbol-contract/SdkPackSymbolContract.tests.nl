namespace NSharpLang.SdkPackSymbolContract.Tests

import System
import System.IO

func PackLibraryProjectYml(): string {
    return """
name: PackLibrary
version: 1.2.3
backend: il
outputType: library
targetFramework: net10.0

package:
  id: NSharpLang.PackSymbolContract.Library
  author: N# Team
  description: a library packed by the SDK pack symbol contract
  license: MIT
"""
}

func PackLibraryProgram(): string {
    return """
namespace PackLibrary

class Greeting {
    static func Text(): string {
        return "packed"
    }
}
"""
}

// AN EXECUTABLE TOO, BECAUSE THE TWO ARE NOT THE SAME PROJECT TO THE BASE SDK. `OutputType` drives
// `_IsExecutable`, `HasRuntimeOutput` and the apphost, and `Release` is the configuration that
// produces the native launcher -- so an exe reaches parts of the output-group machinery a library
// never touches. `src/NSharpLang.Playground.Wasm`, `src/NSharpLang.LanguageServer` and
// `src/NSharpLang.TestHost` are all N#-SDK projects of this shape.
func PackApplicationProjectYml(): string {
    return """
name: PackApplication
version: 1.2.3
backend: il
outputType: exe
targetFramework: net10.0

package:
  id: NSharpLang.PackSymbolContract.Application
  author: N# Team
  description: an executable packed by the SDK pack symbol contract
  license: MIT
"""
}

func PackApplicationProgram(): string {
    return """
namespace PackApplication

func main() {
    print "packed"
}
"""
}

// The `debugType:` key spelled the way a project would spell it once the emitter can honor it.
// Nothing emits a `.pdb` today, so a project that CLAIMS one is a project whose pack must fail --
// which is precisely how this row reads the key back out of `project.yml`.
func PackPortableLibraryProjectYml(): string {
    return """
name: PackPortable
version: 1.2.3
backend: il
outputType: library
targetFramework: net10.0
debugType: portable

package:
  id: NSharpLang.PackSymbolContract.Portable
  author: N# Team
  description: a library that declares symbols the emitter does not write
  license: MIT
"""
}

func PackPortableProgram(): string {
    return """
namespace PackPortable

class Marker {
    static func Text(): string {
        return "portable"
    }
}
"""
}

test "a library and an executable N# project each pack with a plain dotnet pack and ship no symbol file" {
    root := PackRepositoryRoot()
    scratch := Path.Combine(Path.Combine(root, "artifacts"), "sdk-pack-symbol-contract-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(scratch)
    try {
        feed := PackPrepareFeed(root, scratch)
        packagesCache := Path.Combine(scratch, "packages")
        output := Path.Combine(scratch, "out")
        Directory.CreateDirectory(output)

        libraryDirectory := Path.Combine(scratch, "PackLibrary")
        PackWriteSample(libraryDirectory, "PackLibrary", PackLibraryProjectYml(), PackLibraryProgram())
        PackWriteResolution(libraryDirectory, feed, packagesCache)

        applicationDirectory := Path.Combine(scratch, "PackApplication")
        PackWriteSample(applicationDirectory, "PackApplication", PackApplicationProjectYml(), PackApplicationProgram())
        PackWriteResolution(applicationDirectory, feed, packagesCache)

        // ── THE LIBRARY ──────────────────────────────────────────────────────────────────────
        libraryPack := PackSample(libraryDirectory, "PackLibrary", output)
        assert !libraryPack.Output().Contains("NU5026"), libraryPack.Output()
        PackRequireSuccess(libraryPack, "plain dotnet pack of an N# library")

        libraryPackage := Path.Combine(output, "NSharpLang.PackSymbolContract.Library.1.2.3.nupkg")
        assert File.Exists(libraryPackage), "no package at " + libraryPackage
        libraryEntries := PackEntryNames(libraryPackage)
        assert libraryEntries.Contains("lib/net10.0/PackLibrary.dll"), PackJoin(libraryEntries)
        assert PackEntriesWithExtension(libraryEntries, ".pdb").Count == 0, PackJoin(libraryEntries)
        assert libraryEntries.Contains("NSharpLang.PackSymbolContract.Library.nuspec"), PackJoin(libraryEntries)

        // The assembly beside the package is the whole of what the project produced: a `.dll` and
        // no `.pdb`. That is the fact the `.csproj` now declares, so the row reads the disk too
        // rather than trusting pack's view of it alone.
        libraryBin := Path.Combine(Path.Combine(Path.Combine(libraryDirectory, "bin"), "Release"), "net10.0")
        assert File.Exists(Path.Combine(libraryBin, "PackLibrary.dll")), libraryBin
        assert Directory.GetFiles(libraryBin, "*.pdb").Length == 0, libraryBin

        // ── THE EXECUTABLE ───────────────────────────────────────────────────────────────────
        applicationPack := PackSample(applicationDirectory, "PackApplication", output)
        assert !applicationPack.Output().Contains("NU5026"), applicationPack.Output()
        PackRequireSuccess(applicationPack, "plain dotnet pack of an N# executable")

        applicationPackage := Path.Combine(output, "NSharpLang.PackSymbolContract.Application.1.2.3.nupkg")
        assert File.Exists(applicationPackage), "no package at " + applicationPackage
        applicationEntries := PackEntryNames(applicationPackage)
        assert applicationEntries.Contains("lib/net10.0/PackApplication.dll"), PackJoin(applicationEntries)
        assert PackEntriesWithExtension(applicationEntries, ".pdb").Count == 0, PackJoin(applicationEntries)

        applicationBin := Path.Combine(Path.Combine(Path.Combine(applicationDirectory, "bin"), "Release"), "net10.0")
        assert File.Exists(Path.Combine(applicationBin, "PackApplication.dll")), applicationBin
        assert Directory.GetFiles(applicationBin, "*.pdb").Length == 0, applicationBin

        // ── AND THE KEY THAT WILL RETIRE THE DEFAULT ─────────────────────────────────────────
        portableDirectory := Path.Combine(scratch, "PackPortable")
        PackWriteSample(portableDirectory, "PackPortable", PackPortableLibraryProjectYml(), PackPortableProgram())
        PackWriteResolution(portableDirectory, feed, packagesCache)

        // The key is read at EVALUATION time, so `portable` reaches pack's symbol computation and
        // pack asks for the `.pdb` the emitter cannot write. The failure IS the evidence: the
        // default is not hard-coded in the SDK, and the day a symbol writer exists a project can
        // say so without anyone editing MSBuild.
        portablePack := PackSample(portableDirectory, "PackPortable", output)
        assert portablePack.ExitCode != 0, portablePack.Output()
        assert portablePack.Output().Contains("NU5026"), portablePack.Output()
        assert portablePack.Output().Contains("PackPortable.pdb"), portablePack.Output()

        // And the same project, with the key removed, packs -- so the difference measured above is
        // the key and nothing else about this project.
        PackDeleteOutput(portableDirectory)
        File.WriteAllText(
            Path.Combine(portableDirectory, "project.yml"),
            PackPortableLibraryProjectYml().Replace("debugType: portable\n", "")
        )
        defaultedPack := PackSample(portableDirectory, "PackPortable", output)
        PackRequireSuccess(defaultedPack, "plain dotnet pack after removing debugType")
        portableEntries := PackEntryNames(Path.Combine(output, "NSharpLang.PackSymbolContract.Portable.1.2.3.nupkg"))
        assert portableEntries.Contains("lib/net10.0/PackPortable.dll"), PackJoin(portableEntries)
        assert PackEntriesWithExtension(portableEntries, ".pdb").Count == 0, PackJoin(portableEntries)
    } finally {
        Directory.Delete(scratch, true)
    }
}
