namespace NSharpLang.CanonicalSourceOrder.Tests

import System
import System.Collections.Generic
import System.IO
import System.Text
import NSharpLang.Compiler

// ONE SMALL PROGRAM, WRITTEN OUT IN WHATEVER DIRECTORY SHAPE A ROW ASKS FOR.
//
// Six files over two namespaces: an interface and the class that implements it, an enum, a record,
// and free functions on BOTH namespaces' holders, all reaching each other across files. Every one
// of them contributes type, member or method rows, so a file that moved in the compilation order
// moves rows in the metadata tables - which is what makes the byte comparison a claim at all.
class LayoutFile {
    Name: string
    Source: string

    constructor(name: string, source: string) {
        Name = name
        Source = source
    }
}

class LayoutBuild {
    ImplementationPath: string
    ReferencePath: string

    constructor(implementationPath: string, referencePath: string) {
        ImplementationPath = implementationPath
        ReferencePath = referencePath
    }
}

func LayoutProgram(): List<LayoutFile> {
    files := new List<LayoutFile>()
    files.Add(new LayoutFile("Alpha.nl", "namespace Layout.Util\n\nfunc Twice(value: int): int {\n    return value * 2\n}\n"))
    files.Add(new LayoutFile("Colors.nl", "namespace Layout.Model\n\nenum Color {\n    Red = 1,\n    Green = 2,\n    Blue = 4\n}\n"))
    files.Add(new LayoutFile("Shapes.nl", "namespace Layout.Model\n\ninterface Shape {\n    func Area(): int\n}\n\nclass Square: Shape {\n    Side: int\n\n    constructor(side: int) {\n        Side = side\n    }\n\n    func Area(): int {\n        return Side * Side\n    }\n}\n"))
    files.Add(new LayoutFile("Helpers.nl", "namespace Layout.Util\n\nimport Layout.Model\n\nfunc Describe(color: Color): string {\n    return color.ToString() + \":\" + Twice((int)color).ToString()\n}\n\nfunc Measure(shape: Shape): int {\n    return Twice(shape.Area())\n}\n"))
    files.Add(new LayoutFile("Zeta.nl", "namespace Layout.Model\n\nimport Layout.Util\n\nrecord Reading {\n    Label: string\n    Value: int\n}\n\nfunc Sample(): Reading {\n    return new Reading { Label: Describe(Color.Green), Value: Measure(new Square(3)) }\n}\n"))
    files.Add(new LayoutFile("Mid.nl", "namespace Layout.Util\n\nclass Counter {\n    Total: int\n\n    constructor() {\n        Total = 0\n    }\n\n    func Add(value: int): int {\n        Total = Total + Twice(value)\n        return Total\n    }\n}\n"))
    return files
}

func LayoutScratch(label: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-canonical-source-order-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

// `placement[i]` is the directory (relative to the project root, "" for the root itself) that
// `files[i]` is written into. The project.yml is the same in every layout.
func LayoutWrite(projectDirectory: string, files: List<LayoutFile>, placement: string[]): List<string> {
    Directory.CreateDirectory(projectDirectory)
    File.WriteAllText(
        Path.Combine(projectDirectory, "project.yml"),
        "name: Layout\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    written := new List<string>()
    index := 0
    while index < files.Count {
        directory := projectDirectory
        if placement[index].Length > 0 {
            directory = Path.Combine(projectDirectory, placement[index])
        }
        Directory.CreateDirectory(directory)
        path := Path.Combine(directory, files[index].Name)
        File.WriteAllText(path, files[index].Source)
        written.Add(path)
        index = index + 1
    }
    return written
}

// THE CLI'S ENTRY: the compiler discovers the project's files itself, in its own directory walk.
func LayoutCompileDiscovered(projectDirectory: string, outputDirectory: string): LayoutBuild {
    config := ProjectFileParser.Parse(Path.Combine(projectDirectory, "project.yml"))
    return LayoutEmit(new MultiFileCompiler(projectDirectory, config), outputDirectory)
}

// THE SDK TASK'S ENTRY: an explicit list, in whatever order the caller's items happened to arrive.
func LayoutCompileListed(sourceFiles: List<string>, projectDirectory: string, outputDirectory: string): LayoutBuild {
    config := ProjectFileParser.Parse(Path.Combine(projectDirectory, "project.yml"))
    return LayoutEmit(new MultiFileCompiler(sourceFiles, projectDirectory, config), outputDirectory)
}

func LayoutEmit(compiler: MultiFileCompiler, outputDirectory: string): LayoutBuild {
    Directory.CreateDirectory(outputDirectory)
    outputPath := Path.Combine(outputDirectory, "Layout.dll")
    compiler.EmitReferenceAssembly = true
    result := compiler.CompileToIlAssembly("Layout", outputPath, false, false)
    if !result.Success {
        builder := new StringBuilder()
        for error in result.Errors {
            if error.Severity == ErrorSeverity.Error {
                builder.Append(error.FormatForMsBuild())
                builder.Append("; ")
            }
        }
        throw new InvalidOperationException("Compilation failed: " + builder.ToString())
    }
    return new LayoutBuild(outputPath, MultiFileCompiler.ReferenceAssemblyPathFor(outputPath))
}

func LayoutBytesEqual(leftPath: string, rightPath: string): bool {
    left := File.ReadAllBytes(leftPath)
    right := File.ReadAllBytes(rightPath)
    if left.Length != right.Length {
        return false
    }
    index := 0
    while index < left.Length {
        if left[index] != right[index] {
            return false
        }
        index = index + 1
    }
    return true
}

func LayoutRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "AGENTS.md")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the N# repository root from " + AppContext.BaseDirectory + ".")
}

// Every `.nl` file under a project directory, tests included, skipping the build's own output.
func LayoutSourceFiles(directory: string, files: List<string>) {
    for file in Directory.GetFiles(directory, "*.nl", SearchOption.TopDirectoryOnly) {
        files.Add(file)
    }
    for child in Directory.GetDirectories(directory) {
        name := Path.GetFileName(child)
        if name != "obj" && name != "bin" {
            LayoutSourceFiles(child, files)
        }
    }
}
