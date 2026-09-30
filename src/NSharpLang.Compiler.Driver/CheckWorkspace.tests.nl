namespace NSharpLang.Cli

import System
import System.IO

func CwsRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-check-workspace-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func CwsWrite(root: string, relativePath: string, text: string): void {
    path := Path.Combine(root, relativePath)
    parent := Path.GetDirectoryName(path)
    if parent != null {
        Directory.CreateDirectory(parent)
    }
    File.WriteAllText(path, text)
}

test "workspace discovery assigns loose sources to the root and nested sources to the nearest project" {
    root := CwsRoot("ownership")
    try {
        CwsWrite(root, "project.yml", "name: Root\noutputType: library\ntargetFramework: net10.0\n")
        CwsWrite(root, "Root.nl", "class Root {}\n")
        CwsWrite(root, Path.Combine("member", "project.yml"), "name: Member\noutputType: library\ntargetFramework: net10.0\n")
        CwsWrite(root, Path.Combine("member", "Member.nl"), "class Member {}\n")
        CwsWrite(root, Path.Combine("member", "nested", "project.yml"), "name: Nested\noutputType: library\ntargetFramework: net10.0\n")
        CwsWrite(root, Path.Combine("member", "nested", "Nested.nl"), "class Nested {}\n")

        plan := CheckWorkspacePlanner.Discover(root)

        assert plan.ConflictMessage == null
        assert plan.Projects.Count == 3
        assert plan.Projects[0].ProjectRoot == Path.GetFullPath(root)
        assert plan.Projects[0].SourceFiles.Length == 1
        assert Path.GetFileName(plan.Projects[0].SourceFiles[0]) == "Root.nl"
        assert plan.Projects[1].ProjectRoot == Path.GetFullPath(Path.Combine(root, "member"))
        assert plan.Projects[1].SourceFiles.Length == 1
        assert Path.GetFileName(plan.Projects[1].SourceFiles[0]) == "Member.nl"
        assert plan.Projects[2].ProjectRoot == Path.GetFullPath(Path.Combine(root, "member", "nested"))
        assert plan.Projects[2].SourceFiles.Length == 1
        assert Path.GetFileName(plan.Projects[2].SourceFiles[0]) == "Nested.nl"
    } finally {
        Directory.Delete(root, true)
    }
}

test "workspace planning applies each project's exclude rules to its owned files" {
    root := CwsRoot("exclude")
    try {
        CwsWrite(root, "project.yml", "name: Root\noutputType: library\nexclude:\n  - RootHidden.nl\n")
        CwsWrite(root, "Root.nl", "class Root {}\n")
        CwsWrite(root, "RootHidden.nl", "class RootHidden {}\n")
        CwsWrite(root, Path.Combine("member", "project.yml"), "name: Member\noutputType: library\nexclude:\n  - MemberHidden.nl\n")
        CwsWrite(root, Path.Combine("member", "Member.nl"), "class Member {}\n")
        CwsWrite(root, Path.Combine("member", "MemberHidden.nl"), "class MemberHidden {}\n")

        plan := CheckWorkspacePlanner.Discover(root)

        assert plan.Projects.Count == 2
        assert plan.Projects[0].SourceFiles.Length == 1
        assert Path.GetFileName(plan.Projects[0].SourceFiles[0]) == "Root.nl"
        assert plan.Projects[1].SourceFiles.Length == 1
        assert Path.GetFileName(plan.Projects[1].SourceFiles[0]) == "Member.nl"
    } finally {
        Directory.Delete(root, true)
    }
}

test "a malformed member project is retained as a member failure while sibling projects remain discoverable" {
    root := CwsRoot("malformed")
    try {
        CwsWrite(root, "project.yml", "name: Root\noutputType: library\n")
        CwsWrite(root, "Root.nl", "class Root {}\n")
        CwsWrite(root, Path.Combine("bad", "project.yml"), "name: [invalid\n")
        CwsWrite(root, Path.Combine("bad", "Bad.nl"), "class Bad {}\n")
        CwsWrite(root, Path.Combine("good", "project.yml"), "name: Good\noutputType: library\n")
        CwsWrite(root, Path.Combine("good", "Good.nl"), "class Good {}\n")

        plan := CheckWorkspacePlanner.Discover(root)

        assert plan.Projects.Count == 3
        assert plan.Projects[1].ConfigError != null
        assert plan.Projects[2].ConfigError == null
        assert plan.Projects[2].SourceFiles.Length == 1
    } finally {
        Directory.Delete(root, true)
    }
}
