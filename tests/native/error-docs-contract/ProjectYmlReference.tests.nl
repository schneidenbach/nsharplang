namespace NSharpLang.ErrorDocsContract.Tests

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

// WHAT THE DOCS SAY A PROJECT SEES BY DEFAULT IS WHAT THE COMPILER GIVES IT.
//
// `website/docs/project-yml.md` lists, between two marker comments, types a project with no
// `dependencies:` can use and the namespace each is imported from -- the types issue #215 found
// missing when `nlc` compiled against a hand-picked list instead of all of `Microsoft.NETCore.App`.
// Every row is checked against the compiler's own answer: the namespace must be one the framework
// index (`FrameworkNamespaceIndex`) loads on import, and each type must be declared in that namespace
// by one of the assemblies the import loads. A row naming a type the default framework does not
// carry, or a namespace that would not import, fails here before it reaches a reader.
func ProjectYmlReferencePage(): string {
    return Path.Combine(Path.Combine(Path.Combine(EdcPaths.RepositoryRoot(), "website"), "docs"), "project-yml.md")
}

func DocumentedDefaultFrameworkRows(text: string): List<string[]> {
    startMarker := "<!-- default-framework-namespaces:start -->"
    endMarker := "<!-- default-framework-namespaces:end -->"
    start := text.IndexOf(startMarker, StringComparison.Ordinal)
    end := text.IndexOf(endMarker, StringComparison.Ordinal)
    if start < 0 || end < start {
        throw new InvalidOperationException("project-yml.md has no default-framework-namespaces marker pair.")
    }

    rows := new List<string[]>()
    block := text.Substring(start + startMarker.Length, end - start - startMarker.Length)
    for rawLine in block.Split('\n') {
        line := rawLine.Trim()
        if line.Length == 0 || line.StartsWith("| Type", StringComparison.Ordinal) || line.StartsWith("|---", StringComparison.Ordinal) {
            continue
        }

        cells := line.Trim('|').Split('|')
        if cells.Length != 2 {
            throw new InvalidOperationException("Unexpected row in the default-framework table: " + line)
        }

        rows.Add([cells[0].Trim(), cells[1].Trim().Trim('`')])
    }

    return rows
}

// `ImmutableDictionary<K, V>` -> `ImmutableDictionary`2`, the metadata name of the type a row names.
func DocumentedMetadataTypeName(spelled: string): string {
    open := spelled.IndexOf('<')
    if open < 0 {
        return spelled
    }

    arity := spelled.Split(',').Length
    return spelled.Substring(0, open) + "`" + arity.ToString()
}

test "every type project-yml.md says a project sees by default is imported from a framework namespace that declares it" {
    rows := DocumentedDefaultFrameworkRows(File.ReadAllText(ProjectYmlReferencePage()))
    assert rows.Count >= 9, "the default-framework table lost rows"
    index := FrameworkNamespaceIndex.ForHostRuntime()
    for row in rows {
        namespaceName := row[1]
        assemblies := index.AssembliesForNamespace(namespaceName)
        assert assemblies != null, "'" + namespaceName + "' is not a namespace of Microsoft.NETCore.App"
        for rawType in row[0].Split("`, `", StringSplitOptions.None) {
            typeName := DocumentedMetadataTypeName(rawType.Trim().Trim('`'))
            declared := false
            for assemblyName in assemblies {
                if Type.GetType(namespaceName + "." + typeName + ", " + assemblyName) != null {
                    declared = true
                }
            }

            assert declared, "'" + typeName + "' is not declared in '" + namespaceName + "' by " + string.Join(", ", assemblies)
        }
    }
}

test "project-yml.md documents every dependency kind project.yml accepts" {
    text := File.ReadAllText(ProjectYmlReferencePage())
    for kind in ["nuget", "framework", "project", "dll"] {
        assert text.Contains("(`" + kind + "`)"), "no section for the " + kind + " dependency kind"
    }
}
