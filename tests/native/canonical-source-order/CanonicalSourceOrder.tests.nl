namespace NSharpLang.CanonicalSourceOrder.Tests

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

// THE ORDER A COMPILATION READS ITS FILES IN IS A FUNCTION OF THE FILES, NOT OF WHERE THEY SIT.
//
// File ids are indices into the compiler's source list and emission walks them in that order, so
// the order is part of the emitted bytes. Nothing used to decide it: `nlc build` used its directory
// walk and the SDK used its glob's item order, so moving a file into another directory changed the
// assembly without changing a line - and splitting `NSharpLang.Compiler.Core` into slices is 1,026
// such moves. `CanonicalSourceOrder` (in `CompilerServices.nl`) now orders every compilation by the
// file's NAME, ordinal, with its path as the tie-break, at the one place both entry points pass
// through. These rows hold that to whole-file byte identity, which is only a meaningful claim since
// the module version id and the timestamp became functions of the content.
func FlatPlacement(): string[] {
    return ["", "", "", "", "", ""]
}

// Deliberately chosen so the directory walk disagrees with the name order: `Zeta.nl` is the only
// file at the root, so a walk that takes a directory's own files first reads it FIRST, and the
// subdirectories are named against their contents (`Aaa/` holds `Mid.nl`, `Util/` holds `Alpha.nl`).
func NestedPlacement(): string[] {
    return ["Util", "Model/Deep", "Model", "Util/Nested", "", "Aaa"]
}

func NamesInOrder(paths: IEnumerable<string>): string {
    names := new List<string>()
    for path in paths {
        names.Add(Path.GetFileName(path))
    }
    return string.Join(",", names)
}

test "the same sources laid out in two directory structures emit byte-identical implementation and reference assemblies" {
    scratch := LayoutScratch("layouts")
    try {
        flatDirectory := Path.Combine(scratch, "flat")
        nestedDirectory := Path.Combine(scratch, "nested")
        LayoutWrite(flatDirectory, LayoutProgram(), FlatPlacement())
        LayoutWrite(nestedDirectory, LayoutProgram(), NestedPlacement())

        // The two walks genuinely disagree, so the identity below is the canonical order's doing
        // and not two file systems that happened to enumerate alike.
        flatWalk := NamesInOrder(ProjectFileParser.Parse(Path.Combine(flatDirectory, "project.yml")).GetSourceFiles(flatDirectory))
        nestedWalk := NamesInOrder(ProjectFileParser.Parse(Path.Combine(nestedDirectory, "project.yml")).GetSourceFiles(nestedDirectory))
        assert nestedWalk.StartsWith("Zeta.nl,"), nestedWalk
        assert flatWalk != nestedWalk, flatWalk + " | " + nestedWalk

        flat := LayoutCompileDiscovered(flatDirectory, Path.Combine(scratch, "out-flat"))
        nested := LayoutCompileDiscovered(nestedDirectory, Path.Combine(scratch, "out-nested"))

        assert LayoutBytesEqual(flat.ImplementationPath, nested.ImplementationPath)
        assert LayoutBytesEqual(flat.ReferencePath, nested.ReferencePath)
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "the compiler reads a project's files in name order whatever directories they sit in" {
    scratch := LayoutScratch("order")
    try {
        nestedDirectory := Path.Combine(scratch, "nested")
        LayoutWrite(nestedDirectory, LayoutProgram(), NestedPlacement())
        compiler := new MultiFileCompiler(nestedDirectory, ProjectFileParser.Parse(Path.Combine(nestedDirectory, "project.yml")))
        assert NamesInOrder(compiler.SourceFiles) == "Alpha.nl,Colors.nl,Helpers.nl,Mid.nl,Shapes.nl,Zeta.nl", NamesInOrder(compiler.SourceFiles)
    } finally {
        Directory.Delete(scratch, true)
    }
}

// THE CONTROL THAT KEEPS THE FIRST ROW HONEST. If the emitter did not depend on the order at all,
// two layouts would agree whether or not anything decided it. Renaming one file - same content,
// same directory - moves it from last to first in the name order, and the bytes must move with it.
test "renaming a file changes the bytes, so the order is load-bearing and the name is its key" {
    scratch := LayoutScratch("rename")
    try {
        originalDirectory := Path.Combine(scratch, "original")
        renamedDirectory := Path.Combine(scratch, "renamed")
        LayoutWrite(originalDirectory, LayoutProgram(), FlatPlacement())
        renamed := LayoutProgram()
        zeta := renamed[4]
        assert zeta.Name == "Zeta.nl"
        renamed[4] = new LayoutFile("Aardvark.nl", zeta.Source)
        LayoutWrite(renamedDirectory, renamed, FlatPlacement())

        original := LayoutCompileDiscovered(originalDirectory, Path.Combine(scratch, "out-original"))
        moved := LayoutCompileDiscovered(renamedDirectory, Path.Combine(scratch, "out-renamed"))

        assert !LayoutBytesEqual(original.ImplementationPath, moved.ImplementationPath)
    } finally {
        Directory.Delete(scratch, true)
    }
}

// BOTH ENTRY POINTS, ONE ORDER. The CLI discovers the files itself; the SDK task hands over its
// items in the order MSBuild's glob produced them. Both reach `MultiFileCompilerInputBuilder.Build`,
// so a list in ANY order must compile to exactly what discovery compiles to.
test "an explicit source list in any order emits what the discovered project emits" {
    scratch := LayoutScratch("entry-points")
    try {
        projectDirectory := Path.Combine(scratch, "project")
        written := LayoutWrite(projectDirectory, LayoutProgram(), NestedPlacement())
        discovered := LayoutCompileDiscovered(projectDirectory, Path.Combine(scratch, "out-discovered"))

        reversed := new List<string>(written)
        reversed.Reverse()
        listedReversed := LayoutCompileListed(reversed, projectDirectory, Path.Combine(scratch, "out-reversed"))

        rotated := new List<string>()
        index := 0
        while index < written.Count {
            rotated.Add(written[(index + 3) % written.Count])
            index = index + 1
        }
        listedRotated := LayoutCompileListed(rotated, projectDirectory, Path.Combine(scratch, "out-rotated"))

        assert LayoutBytesEqual(discovered.ImplementationPath, listedReversed.ImplementationPath)
        assert LayoutBytesEqual(discovered.ReferencePath, listedReversed.ReferencePath)
        assert LayoutBytesEqual(discovered.ImplementationPath, listedRotated.ImplementationPath)
        assert LayoutBytesEqual(discovered.ReferencePath, listedRotated.ReferencePath)
    } finally {
        Directory.Delete(scratch, true)
    }
}

// A SHARED NAME IS NOT AN ERROR; IT IS ORDERED BY WHERE EACH COPY SITS. Only a project whose names
// are unique is independent of its layout, and a repeated name still gets a total, deterministic
// order. Ordinal, not culture-aware: every capital sorts before every lowercase letter.
test "files that share a name are ordered by their paths, and names compare ordinally" {
    ordered := CanonicalSourceOrder.Sort([
        "/project/b/Same.nl",
        "/project/apple.nl",
        "/project/Zed.nl",
        "/project/a/Same.nl",
        "/project/c/Alpha.nl"
    ])

    assert string.Join("|", ordered) == "/project/c/Alpha.nl|/project/a/Same.nl|/project/b/Same.nl|/project/Zed.nl|/project/apple.nl", string.Join("|", ordered)
}

// THE COMPILER'S OWN PROJECTS ARE HELD TO UNIQUE NAMES, rather than assumed to have them. Moving
// `NSharpLang.Compiler.Core`'s files into slice directories is byte-identical only because no two of
// them share a name: two that did would be ordered by their paths, and a move would reorder them.
test "every N# project under src/ gives each of its source files a name no other file in it uses" {
    sourceRoot := Path.Combine(LayoutRepositoryRoot(), "src")
    duplicates := new List<string>()
    checkedProjects := 0
    for projectDirectory in Directory.GetDirectories(sourceRoot) {
        if !File.Exists(Path.Combine(projectDirectory, "project.yml")) {
            continue
        }
        checkedProjects = checkedProjects + 1
        files := new List<string>()
        LayoutSourceFiles(projectDirectory, files)
        seen := new Dictionary<string, string>(StringComparer.Ordinal)
        for file in files {
            name := Path.GetFileName(file)
            first: string? = null
            if seen.TryGetValue(name, out first) {
                duplicates.Add(Path.GetRelativePath(sourceRoot, first ?? "") + " and " + Path.GetRelativePath(sourceRoot, file))
            } else {
                seen[name] = file
            }
        }
    }

    assert checkedProjects >= 5, checkedProjects.ToString()
    assert duplicates.Count == 0, string.Join("; ", duplicates)
}
