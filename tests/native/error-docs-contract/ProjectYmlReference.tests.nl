namespace NSharpLang.ErrorDocsContract.Tests

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

// THE IMPLICIT REFERENCE SET THE DOCS PUBLISH IS THE ONE THE COMPILER LOADS.
//
// `website/docs/project-yml.md` lists, between two marker comments, every assembly a project with no
// `dependencies:` compiles against. That list is the answer to "why can't I see this type?", so a
// name added to or removed from `ExternalAssemblyScan.CommonAssemblyNames` without the page changing
// would publish a wrong answer. The two are compared in order, in both directions, and the census of
// differences is the failure message.
func ProjectYmlReferencePage(): string {
    return Path.Combine(Path.Combine(Path.Combine(EdcPaths.RepositoryRoot(), "website"), "docs"), "project-yml.md")
}

func DocumentedImplicitAssemblies(text: string): List<string> {
    startMarker := "<!-- implicit-assemblies:start -->"
    endMarker := "<!-- implicit-assemblies:end -->"
    start := text.IndexOf(startMarker, StringComparison.Ordinal)
    end := text.IndexOf(endMarker, StringComparison.Ordinal)
    if start < 0 || end < start {
        throw new InvalidOperationException("project-yml.md has no implicit-assemblies marker pair.")
    }

    names := new List<string>()
    block := text.Substring(start + startMarker.Length, end - start - startMarker.Length)
    for rawLine in block.Split('\n') {
        line := rawLine.Trim()
        if line.Length == 0 {
            continue
        }

        if !line.StartsWith("- `", StringComparison.Ordinal) || !line.EndsWith("`", StringComparison.Ordinal) {
            throw new InvalidOperationException("Unexpected line in the implicit-assemblies list: " + line)
        }

        names.Add(line.Substring(3, line.Length - 4))
    }

    return names
}

test "project-yml.md lists exactly the assemblies a project with no dependencies compiles against" {
    documented := DocumentedImplicitAssemblies(File.ReadAllText(ProjectYmlReferencePage()))
    loaded := ExternalAssemblyScan.CommonAssemblyNames()

    missing := new List<string>()
    for name in loaded {
        if !documented.Contains(name) {
            missing.Add(name)
        }
    }

    extra := new List<string>()
    for name in documented {
        if Array.IndexOf(loaded, name) < 0 {
            extra.Add(name)
        }
    }

    assert string.Join(", ", missing) == "", "loaded but not documented: " + string.Join(", ", missing)
    assert string.Join(", ", extra) == "", "documented but not loaded: " + string.Join(", ", extra)
    assert string.Join("|", documented) == string.Join("|", loaded), "the page lists the assemblies in a different order"
}

test "project-yml.md documents every dependency kind project.yml accepts" {
    text := File.ReadAllText(ProjectYmlReferencePage())
    for kind in ["nuget", "framework", "project", "dll"] {
        assert text.Contains("(`" + kind + "`)"), "no section for the " + kind + " dependency kind"
    }
}
