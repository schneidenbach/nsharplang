namespace NSharpLang.IncrementalBuild.Tests

import System
import System.IO
import System.Text
import NSharpLang.Compiler

// A SMALL MULTI-FILE LIBRARY ON DISK, compiled the way `nlc build` compiles it: the project's own
// source walk, strict lint on, the up-to-date stamp enabled. Every row builds its own copy in its own
// scratch directory, so rows never share a stamp.
class IncrementalOutcome {
    Success: bool
    UpToDate: bool
    Diagnostics: string
    OutputHash: string

    constructor(success: bool, upToDate: bool, diagnostics: string, outputHash: string) {
        Success = success
        UpToDate = upToDate
        Diagnostics = diagnostics
        OutputHash = outputHash
    }
}

func IncrementalScratch(label: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-incremental-build-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func IncrementalProjectYml(): string {
    return "name: Lib\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
}

func IncrementalWriteProject(projectDirectory: string) {
    Directory.CreateDirectory(projectDirectory)
    File.WriteAllText(Path.Combine(projectDirectory, "project.yml"), IncrementalProjectYml())
    File.WriteAllText(Path.Combine(projectDirectory, "Shapes.nl"), "namespace Lib\n\nclass Square {\n    Side: int\n\n    constructor(side: int) {\n        Side = side\n    }\n\n    func Area(): int {\n        return Side * Side\n    }\n}\n")
    File.WriteAllText(Path.Combine(projectDirectory, "Math.nl"), "namespace Lib\n\nfunc Twice(value: int): int {\n    return value * 2\n}\n\nfunc Unwrap(value: int?): int {\n    return value.Value\n}\n")
    File.WriteAllText(Path.Combine(projectDirectory, "Report.nl"), "namespace Lib\n\nfunc Describe(side: int): string {\n    return \"area \" + Twice(new Square(side).Area()).ToString()\n}\n")
}

func IncrementalOutputPath(projectDirectory: string): string {
    return Path.Combine(projectDirectory, "bin", "Debug", "net10.0", "Lib.dll")
}

func IncrementalBuildConfigured(projectDirectory: string, configure: Action<ProjectConfig>?, incremental: bool): IncrementalOutcome {
    return IncrementalBuildWith(projectDirectory, configure, null, incremental)
}

func IncrementalBuildWith(projectDirectory: string, configure: Action<ProjectConfig>?, prepare: Action<MultiFileCompiler>?, incremental: bool): IncrementalOutcome {
    config := ProjectFileParser.Parse(Path.Combine(projectDirectory, "project.yml"))
    if configure != null {
        configure(config)
    }
    sourceFiles := config.GetSourceFiles(projectDirectory, false)
    compiler := new MultiFileCompiler(sourceFiles, projectDirectory, config)
    compiler.IncrementalBuild = incremental
    if prepare != null {
        prepare(compiler)
    }
    outputPath := IncrementalOutputPath(projectDirectory)
    Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? projectDirectory)
    result := compiler.CompileToIlAssembly("Lib", outputPath, true)
    rendered := new StringBuilder()
    for error in result.Errors {
        rendered.AppendLine(error.FormatForTooling(true, true))
    }
    outputHash := "-"
    if File.Exists(outputPath) {
        outputHash = ContentHash.OfBytes(File.ReadAllBytes(outputPath))
    }
    return new IncrementalOutcome(result.Success, compiler.WasUpToDate, rendered.ToString(), outputHash)
}

func IncrementalBuild(projectDirectory: string): IncrementalOutcome {
    return IncrementalBuildConfigured(projectDirectory, null, true)
}

func IncrementalStampPath(projectDirectory: string): string {
    return IncrementalBuildStamp.PathFor(projectDirectory, "Lib", IncrementalOutputPath(projectDirectory))
}

func IncrementalCleanup(directory: string) {
    try {
        Directory.Delete(directory, true)
    } catch ex: IOException {
        Console.Error.WriteLine("scratch directory left behind: " + directory + " (" + ex.Message + ")")
    }
}
