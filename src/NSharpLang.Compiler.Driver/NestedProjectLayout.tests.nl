namespace NSharpLang.Compiler

import System
import System.IO


// A PROJECT UNDER TEST COMPILES ONLY ITS OWN SOURCE.
//
// A project compiles every `.nl` file under its root (`ProjectConfig.GetSourceFiles` walks every
// directory below it), including a directory that holds ANOTHER project's `project.yml`. A contract
// that emits a library and then compiles a consumer whose root CONTAINS the library's directory
// compiles the library's source into the consumer too: every "referenced-assembly" type it asserts on
// is a source type of the consumer, the reference is never consulted, and the cross-assembly lookup
// under test never runs. `ExternalLexicalLookup` and `AnalyzerImportAmbiguity` were both written that
// way and passed while proving nothing about metadata. A consumer belongs BESIDE its library, and the
// contracts that emit one call `AssertCompilesOnlyItsOwnSources` before they compile the consumer.

// The first source file the project at `root` would compile that sits below a directory, inside
// `root`, holding a `project.yml` of its own — or "" when every source file is the project's own.
func NestedProjectSourceUnder(root: string): string {
    fullRoot := Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)
    for file in ProjectConfig.EnumerateSourceFileArray(fullRoot) {
        directory := Path.GetDirectoryName(file)
        while directory != null && directory.Length > fullRoot.Length {
            if File.Exists(Path.Combine(directory, "project.yml")) {
                return file
            }
            directory = Path.GetDirectoryName(directory)
        }
    }
    return ""
}

func AssertCompilesOnlyItsOwnSources(root: string) {
    nested := NestedProjectSourceUnder(root)
    assert nested.Length == 0, "the project at " + root + " would compile " + nested + ", which belongs to a nested project: put the consumer beside the library, not above it"
}

func NestedLayoutWrite(root: string, relativePath: string, source: string) {
    path := Path.Combine(root, relativePath)
    directory := Path.GetDirectoryName(path)
    if directory != null {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(path, source)
}

test "a consumer above its library would compile the library's source, and one beside it would not" {
    workspace := Path.Combine(Path.GetTempPath(), "nsharp-nested-project-layout-" + Guid.NewGuid().ToString("N"))
    try {
        NestedLayoutWrite(workspace, "library/project.yml", "name: Lib\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        NestedLayoutWrite(workspace, "library/deep/Lib.nl", "namespace Lib\n\nclass Thing {\n}\n")
        NestedLayoutWrite(workspace, "consumer/project.yml", "name: Consumer\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        NestedLayoutWrite(workspace, "consumer/nested/Consumer.nl", "namespace Consumer\n\nclass Uses {\n}\n")
        NestedLayoutWrite(workspace, "project.yml", "name: Above\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        NestedLayoutWrite(workspace, "Above.nl", "namespace Above\n\nclass Uses {\n}\n")

        // The root's own file is its own; the library's file, however deep, belongs to the library.
        above := NestedProjectSourceUnder(workspace)
        assert above.EndsWith(Path.Combine("deep", "Lib.nl")) || above.EndsWith(Path.Combine("nested", "Consumer.nl")), above
        // A sibling's own subdirectories without a project.yml are still its own.
        assert NestedProjectSourceUnder(Path.Combine(workspace, "consumer")) == ""
        assert NestedProjectSourceUnder(Path.Combine(workspace, "library")) == ""
    } finally {
        if Directory.Exists(workspace) {
            Directory.Delete(workspace, true)
        }
    }
}
