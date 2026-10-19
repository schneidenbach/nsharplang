namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.IO

// A `dll:` DEPENDENCY BUILT BY `dotnet build` RUNS.
//
// The emit task reads `dll:` entries straight from project.yml, so `dotnet build` always COMPILED
// against them; but the SDK never told MSBuild about the assembly. It was not copied beside the
// output and not written into `.deps.json`, and the program the build reported as successful failed
// at its first use with "Could not load file or assembly". `nlc build` copied it all along. The row
// builds a real library with the standalone CLI, references the built file by a path relative to the
// consumer, and runs what `dotnet build` produced.
test "a project.yml dll dependency is copied beside the dotnet build output and the program runs" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "dll-reference")
    try {
        cliPath := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0"), "Cli.dll")
        if !File.Exists(cliPath) {
            throw new InvalidOperationException("The built CLI was not found at " + cliPath)
        }

        libraryDirectory := Path.Combine(scratch, "DllMath")
        Directory.CreateDirectory(libraryDirectory)
        File.WriteAllText(Path.Combine(libraryDirectory, "project.yml"), "name: DllMath\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        File.WriteAllText(Path.Combine(libraryDirectory, "Calc.nl"), "namespace DllMath\n\nclass Calc {\n    static func Add(a: int, b: int): int {\n        return a + b\n    }\n}\n")
        libraryBuild := SdkBoundaryRunDotnet(SdkBoundaryQuote(cliPath) + " build", libraryDirectory)
        SdkBoundaryRequireSuccess(libraryBuild, "standalone CLI build of the referenced library")
        Directory.CreateDirectory(Path.Combine(scratch, "libs"))
        File.Copy(IlSdkAssembly(libraryDirectory, "DllMath"), Path.Combine(Path.Combine(scratch, "libs"), "DllMath.dll"))

        sdkPackage := SdkBoundaryPreparePackage(root)
        projectDirectory := Path.Combine(scratch, "SdkDllRef")
        projectPath := IlSdkProject(
            projectDirectory,
            "SdkDllRef",
            "name: SdkDllRef\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - dll: ../libs/DllMath.dll\n",
            sdkPackage
        )
        File.WriteAllText(Path.Combine(projectDirectory, "Program.nl"), "import DllMath\n\nfunc main() {\n    print Calc.Add(2, 3).ToString()\n}\n")

        build := SdkBoundaryRunInCache("build " + SdkBoundaryQuote(projectPath) + " -v q --disable-build-servers", projectDirectory, IlSdkPackages(projectDirectory))
        SdkBoundaryRequireSuccess(build, "SDK build with a dll dependency")

        assemblyPath := IlSdkAssembly(projectDirectory, "SdkDllRef")
        outputDirectory := Path.GetDirectoryName(assemblyPath) ?? projectDirectory
        assert File.Exists(Path.Combine(outputDirectory, "DllMath.dll")), "dotnet build did not copy the dll dependency beside " + assemblyPath
        assert File.ReadAllText(Path.Combine(outputDirectory, "SdkDllRef.deps.json")).Contains("DllMath")

        run := SdkBoundaryRunDotnet(SdkBoundaryQuote(assemblyPath), projectDirectory)
        SdkBoundaryRequireSuccess(run, "SDK dll-reference output")
        assert run.Stdout.Trim() == "5", run.Stdout
    } finally {
        Directory.Delete(scratch, true)
    }
}
