namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

// CONTRACTS FOR WHERE A FILE BELONGS. These came out of `DocumentManager.cs`, where every one of
// them was a private static reachable only by standing up a language server and opening a file in
// it: the project-root walk, the two different path comparisons, the snapshot stamp that decides
// when a cached project answer is stale, and the diagnostic selection every publication runs.
func EwfTempRoot(label: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-ewf-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return Path.GetFullPath(root)
}

func EwfWrite(path: string, text: string) {
    directory := Path.GetDirectoryName(path)
    if directory != null {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(path, text)
}

func EwfRoots(roots: string[]): List<string> {
    list := new List<string>()
    for root in roots {
        list.Add(root)
    }
    return list
}

func EwfError(code: ErrorCode, message: string, fileName: string?, line: int, column: int): CompilerError {
    error := new CompilerError(code, message, line, column, ErrorSeverity.Error)
    error.FileName = fileName
    return error
}

func EwfErrors(errors: CompilerError[]): List<CompilerError> {
    list := new List<CompilerError>()
    for error in errors {
        list.Add(error)
    }
    return list
}

func EwfOverrides(paths: string[], texts: string[]): Dictionary<string, string> {
    map := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    for i := 0; i < paths.Length; i++ {
        map[paths[i]] = texts[i]
    }
    return map
}

test "EditorWorkspaceFacts normalizes separators without touching anything else" {
    assert EditorWorkspaceFacts.NormalizePath("a\\b\\c.nl") == "a/b/c.nl"
    assert EditorWorkspaceFacts.NormalizePath("a/b/c.nl") == "a/b/c.nl"
    assert EditorWorkspaceFacts.NormalizePath("") == ""
}

test "EditorWorkspaceFacts matches a relative and an absolute name for the same file" {
    root := EwfTempRoot("match")
    absolute := Path.Combine(root, "Program.nl")

    assert EditorWorkspaceFacts.PathsMatch(absolute, absolute)
    assert EditorWorkspaceFacts.PathsMatch(Path.Combine(root, "nested", "..", "Program.nl"), absolute)
    assert !EditorWorkspaceFacts.PathsMatch(Path.Combine(root, "Other.nl"), absolute)

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts reads a path under a root as strictly inside it" {
    root := EwfTempRoot("under")
    sibling := root + "-sibling"

    assert EditorWorkspaceFacts.IsPathUnderProject(Path.Combine(root, "Program.nl"), root)
    assert EditorWorkspaceFacts.IsPathUnderProject(Path.Combine(root, "src", "Program.nl"), root)
    assert !EditorWorkspaceFacts.IsPathUnderProject(root, root)
    assert !EditorWorkspaceFacts.IsPathUnderProject(Path.Combine(sibling, "Program.nl"), root)

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts names the filesystem root and nothing above a project" {
    root := EwfTempRoot("fsroot")

    assert EditorWorkspaceFacts.IsFilesystemRoot(Path.GetPathRoot(root) ?? "/")
    assert !EditorWorkspaceFacts.IsFilesystemRoot(root)

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts finds the nearest declared project above a file" {
    root := EwfTempRoot("discover")
    nested := Path.Combine(root, "src", "deep")
    Directory.CreateDirectory(nested)
    EwfWrite(Path.Combine(root, "project.yml"), "name: Probe\n")
    source := Path.Combine(nested, "Program.nl")
    EwfWrite(source, "namespace Probe\n")

    assert EditorWorkspaceFacts.FindProjectRoot(source) == root
    assert EditorWorkspaceFacts.FindProjectRoot(nested) == root

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts stands a loose buffer in its own directory" {
    root := EwfTempRoot("loose")
    source := Path.Combine(root, "Program.nl")
    EwfWrite(source, "namespace Probe\n")

    assert EditorWorkspaceFacts.FindProjectRoot(source) == root
    assert EditorWorkspaceFacts.AnalysisProjectRoot(root) == root

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts refuses to analyse from the filesystem root" {
    filesystemRoot := Path.GetPathRoot(Path.GetTempPath()) ?? "/"
    assert EditorWorkspaceFacts.AnalysisProjectRoot(filesystemRoot) == null
}

test "EditorWorkspaceFacts picks the deepest workspace root containing a file" {
    outer := EwfTempRoot("outer")
    inner := Path.Combine(outer, "inner")
    Directory.CreateDirectory(inner)
    source := Path.Combine(inner, "Program.nl")
    EwfWrite(source, "namespace Probe\n")

    roots := EwfRoots([outer, inner])
    assert EditorWorkspaceFacts.ContainingWorkspaceRoot(source, roots) == inner
    assert EditorWorkspaceFacts.ContainingWorkspaceRoot(Path.Combine(outer, "Top.nl"), roots) == outer
    assert EditorWorkspaceFacts.ContainingWorkspaceRoot(Path.Combine(Path.GetTempPath(), "elsewhere.nl"), roots) == null

    Directory.Delete(outer, true)
}

test "EditorWorkspaceFacts prefers a declared project over the workspace folder around it" {
    workspace := EwfTempRoot("semantic")
    project := Path.Combine(workspace, "app")
    Directory.CreateDirectory(project)
    EwfWrite(Path.Combine(project, "project.yml"), "name: App\n")
    declared := Path.Combine(project, "Program.nl")
    EwfWrite(declared, "namespace App\n")
    loose := Path.Combine(workspace, "Loose.nl")
    EwfWrite(loose, "namespace Loose\n")

    roots := EwfRoots([workspace])
    assert EditorWorkspaceFacts.SemanticProjectRoot(declared, roots) == project
    assert EditorWorkspaceFacts.SemanticProjectRoot(loose, roots) == workspace

    possible := EditorWorkspaceFacts.PossibleSemanticProjectRoots(declared, roots)
    assert possible.Count == 2
    assert possible[0] == project
    assert possible[1] == workspace

    Directory.Delete(workspace, true)
}

test "EditorWorkspaceFacts leaves a rooted result path exactly as the compiler wrote it" {
    root := EwfTempRoot("resolve")
    rooted := Path.Combine(root, "nested", "..", "Program.nl")

    assert EditorWorkspaceFacts.ProjectFilePath(root, rooted) == rooted
    assert EditorWorkspaceFacts.ProjectFilePath(root, "Program.nl") == Path.Combine(root, "Program.nl")

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts answers no stamp for a project with nothing to analyse" {
    root := EwfTempRoot("stamp-empty")
    empty := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)

    assert EditorWorkspaceFacts.ProjectSnapshotStamp(root, empty) == null

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts changes the stamp when an unsaved buffer changes" {
    root := EwfTempRoot("stamp-buffer")
    source := Path.Combine(root, "Program.nl")
    EwfWrite(source, "namespace Probe\n")

    empty := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    diskOnly := EditorWorkspaceFacts.ProjectSnapshotStamp(root, empty)
    assert diskOnly != null

    first := EditorWorkspaceFacts.ProjectSnapshotStamp(root, EwfOverrides([source], ["namespace Probe\n"]))
    second := EditorWorkspaceFacts.ProjectSnapshotStamp(root, EwfOverrides([source], ["namespace Probe\n\nfunc main() {}\n"]))

    assert first != null
    assert second != null
    assert first != second
    assert first != diskOnly
    assert first == EditorWorkspaceFacts.ProjectSnapshotStamp(root, EwfOverrides([source], ["namespace Probe\n"]))

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts refuses a buffer with no project and no workspace" {
    root := EwfTempRoot("refuse-none")
    source := Path.Combine(root, "Program.nl")
    EwfWrite(source, "namespace Probe\n")

    refusal := EditorWorkspaceFacts.SnapshotRefusal(source, root, EwfRoots([]))
    if refusal == null {
        throw new InvalidOperationException("expected a refusal for a buffer with no project")
    }

    assert refusal.Reason == EditorProjectSnapshotReason.NoProjectRoot
    assert refusal.FilePath == source
    assert refusal.Message == "Open buffer is not backed by a project.yml project or known workspace root"

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts refuses an untitled buffer outside the project it named" {
    root := EwfTempRoot("refuse-outside")
    EwfWrite(Path.Combine(root, "project.yml"), "name: App\n")
    untitled := Path.Combine(Path.GetTempPath(), "nsharp-ewf-untitled-" + Guid.NewGuid().ToString("N") + ".nl")

    refusal := EditorWorkspaceFacts.SnapshotRefusal(untitled, root, EwfRoots([]))
    if refusal == null {
        throw new InvalidOperationException("expected a refusal for a buffer outside its project")
    }

    assert refusal.Reason == EditorProjectSnapshotReason.OpenBufferOutsideProject
    assert refusal.Message == "Open buffer is not backed by a disk file, discovered project root, or known workspace root"

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts admits a buffer its project declares" {
    root := EwfTempRoot("admit")
    EwfWrite(Path.Combine(root, "project.yml"), "name: App\n")
    source := Path.Combine(root, "Program.nl")
    EwfWrite(source, "namespace App\n")

    assert EditorWorkspaceFacts.SnapshotRefusal(source, root, EwfRoots([])) == null

    Directory.Delete(root, true)
}

test "EditorWorkspaceFacts carries the two refusals the caller builds itself" {
    empty := EditorWorkspaceFacts.NoSourceFilesRefusal("/tmp/app")
    assert empty.Reason == EditorProjectSnapshotReason.NoSourceFiles
    assert empty.ProjectRoot == "/tmp/app"
    assert empty.FilePath == null
    assert empty.Message == "Project has no source files or open buffers to analyze"

    failed := EditorWorkspaceFacts.LoadFailedRefusal("/tmp/app", "boom")
    assert failed.Reason == EditorProjectSnapshotReason.LoadFailed
    assert failed.FilePath == null
    assert failed.Message == "boom"
}

test "EditorWorkspaceFacts keeps the first of a repeated diagnostic" {
    first := EwfError(ErrorCode.InvalidSyntax, "bad", "Program.nl", 3, 5)
    duplicate := EwfError(ErrorCode.InvalidSyntax, "bad", "Program.nl", 3, 5)
    otherColumn := EwfError(ErrorCode.InvalidSyntax, "bad", "Program.nl", 3, 6)
    otherMessage := EwfError(ErrorCode.InvalidSyntax, "worse", "Program.nl", 3, 5)
    noFile := EwfError(ErrorCode.InvalidSyntax, "bad", null, 3, 5)

    deduplicated := EditorWorkspaceFacts.DeduplicateDiagnostics(EwfErrors([first, duplicate, otherColumn, otherMessage, noFile]))

    assert deduplicated.Count == 4
    assert Object.ReferenceEquals(deduplicated[0], first)
    assert Object.ReferenceEquals(deduplicated[1], otherColumn)
    assert Object.ReferenceEquals(deduplicated[2], otherMessage)
    assert Object.ReferenceEquals(deduplicated[3], noFile)
}

test "EditorWorkspaceFacts selects one file's diagnostics from a project's whole list" {
    root := EwfTempRoot("select")
    program := Path.Combine(root, "Program.nl")

    mine := EwfError(ErrorCode.InvalidSyntax, "mine", "Program.nl", 1, 1)
    mineAgain := EwfError(ErrorCode.InvalidSyntax, "mine", "Program.nl", 1, 1)
    theirs := EwfError(ErrorCode.InvalidSyntax, "theirs", "Other.nl", 1, 1)
    nameless := EwfError(ErrorCode.InvalidSyntax, "nameless", "   ", 1, 1)

    selected := EditorWorkspaceFacts.DiagnosticsForFile(EwfErrors([mine, mineAgain, theirs, nameless]), root, program)

    assert selected.Count == 1
    assert Object.ReferenceEquals(selected[0], mine)

    Directory.Delete(root, true)
}

// ── `file://` ────────────────────────────────────────────────────────────

test "EditorWorkspaceFacts turns a file:// URI back into the path it names" {
    assert EditorWorkspaceFacts.UriToFilePath("file:///tmp/a.nl") == "/tmp/a.nl"
    assert EditorWorkspaceFacts.UriToFilePath("file:///tmp/a%20b.nl") == "/tmp/a b.nl"
    assert EditorWorkspaceFacts.UriToFilePath("file:///tmp/%23hash.nl") == "/tmp/#hash.nl"
}

// A BUFFER WITH NO URI IS STILL FINDABLE. The editor hands this owner plain paths too, and a name
// that is not a `file://` URI must come back exactly as it went in.
test "EditorWorkspaceFacts leaves a name that is not a file:// URI alone" {
    assert EditorWorkspaceFacts.UriToFilePath("/tmp/a.nl") == "/tmp/a.nl"
    assert EditorWorkspaceFacts.UriToFilePath("untitled:Untitled-1") == "untitled:Untitled-1"
    assert EditorWorkspaceFacts.UriToFilePath("") == ""
}

test "EditorWorkspaceFacts and the file:// conversion are inverses over a real path" {
    root := EwfTempRoot("uri")
    program := Path.Combine(root, "Program.nl")
    File.WriteAllText(program, "namespace A\n")

    uri := EditorWorkspaceFacts.FilePathToUri(program)
    assert uri.StartsWith("file://")

    roundTripped := EditorWorkspaceFacts.UriToFilePath(uri)
    assert EditorWorkspaceFacts.PathsMatch(roundTripped, program)

    Directory.Delete(root, true)
}

// ── the workspace root an `initialize` named ─────────────────────────────

test "EditorWorkspaceFacts prefers the first workspace folder over both deprecated fields" {
    chosen := EditorWorkspaceFacts.WorkspaceRootChoice("/folder", "/rootUri", "/rootPath")
    assert chosen == "/folder"
}

test "EditorWorkspaceFacts falls back to rootUri, then to rootPath" {
    assert EditorWorkspaceFacts.WorkspaceRootChoice(null, "/rootUri", "/rootPath") == "/rootUri"
    assert EditorWorkspaceFacts.WorkspaceRootChoice(null, null, "/rootPath") == "/rootPath"
}

// AN EMPTY `rootPath` IS NOT A ROOT. The shipped guard was `!string.IsNullOrEmpty`, so a client
// that sends the field empty gets the same answer as one that omits it: no scan, not a scan of "".
test "EditorWorkspaceFacts treats an empty rootPath as no root at all" {
    assert EditorWorkspaceFacts.WorkspaceRootChoice(null, null, "") == null
    assert EditorWorkspaceFacts.WorkspaceRootChoice(null, null, null) == null
}
