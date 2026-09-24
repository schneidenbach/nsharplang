namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// THE COMPILER'S OWN PROJECTS, READ THROUGH ITS SLICE LAYOUT.
//
// Compiler.Core is carved into slice projects lowest first (`src/NSharpLang.Compiler.Model` and
// `src/NSharpLang.Compiler.Syntax` are carved), and Core reaches every carved slice through the
// `project:` dependencies of its project.yml, transitively.
// A row that reads the compiler's own source or build output finds it by following that graph, never
// by assuming it sits under Core: a file carved into a slice project is still the compiler's, and a
// row that looks only under Core stops seeing it -- or, worse, reads a stale copy left behind.
func CompilerLayoutRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the repository root above the estate's output directory.")
}

// Compiler.Core's project directory first, then every project its project.yml reaches through a
// `project:` dependency, transitively, each once.
func CompilerProjectDirectories(): List<string> {
    core := Path.GetFullPath(Path.Combine(Path.Combine(CompilerLayoutRepositoryRoot(), "src"), "NSharpLang.Compiler.Core"))
    directories := new List<string>()
    directories.Add(core)
    index := 0
    while index < directories.Count {
        directory := directories[index]
        config := ProjectFileParser.Parse(Path.Combine(directory, "project.yml"))
        for dependency in config.Dependencies {
            projectFile := dependency.Project
            if dependency.Type != ReferenceType.Project || projectFile == null {
                continue
            }

            referenced := Path.GetDirectoryName(Path.GetFullPath(Path.Combine(directory, projectFile))) ?? ""
            if referenced.Length > 0 && !directories.Contains(referenced) {
                directories.Add(referenced)
            }
        }

        index = index + 1
    }

    return directories
}

// Every compiler source file matching `pattern` (`*.nl`, or one basename), in every compiler project,
// outside each project's `bin/` and `obj/`.
func CompilerSourceFiles(pattern: string): List<string> {
    found := new List<string>()
    for project in CompilerProjectDirectories() {
        for candidate in Directory.GetFiles(project, pattern, SearchOption.AllDirectories) {
            relative := Path.GetRelativePath(project, candidate).Replace('\\', '/')
            if !relative.StartsWith("bin/", StringComparison.Ordinal) && !relative.StartsWith("obj/", StringComparison.Ordinal) {
                found.Add(candidate)
            }
        }
    }

    return found
}
