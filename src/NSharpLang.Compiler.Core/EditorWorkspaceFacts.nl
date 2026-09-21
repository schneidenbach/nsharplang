namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO
import System.Text
import NSharpLang.Compiler

// WHY A SEMANTIC ANSWER IS UNAVAILABLE. The editor degrades rather than guesses, and when it does
// it says which of four things went wrong, which file was asked about, and what a reader can do
// about it. The words are the ones the language server has always logged.
enum EditorProjectSnapshotReason {
    NoSourceFiles,
    NoProjectRoot,
    OpenBufferOutsideProject,
    LoadFailed
}

// ONE REFUSAL, carrying everything the log line prints. A refusal is a row rather than an
// exception because the caller's answer to every one of them is the same: log it and answer
// "no snapshot" — the request still succeeds, with a less informed answer.
class EditorProjectSnapshotRefusal {
    projectRootValue: string
    reasonValue: EditorProjectSnapshotReason
    filePathValue: string?
    messageValue: string

    ProjectRoot: string => projectRootValue
    Reason: EditorProjectSnapshotReason => reasonValue
    FilePath: string? => filePathValue
    Message: string => messageValue

    constructor(ProjectRoot: string, Reason: EditorProjectSnapshotReason, FilePath: string?, Message: string) {
        projectRootValue = ProjectRoot
        reasonValue = Reason
        filePathValue = FilePath
        messageValue = Message
    }
}

// WHERE A FILE BELONGS, AND WHICH DIAGNOSTICS BELONG TO IT.
//
// The language server's document manager used to answer both questions itself, in a dozen private
// statics that no test could reach: which directory is a file's project root, whether a path sits
// under a root, whether two paths name the same file, when a cached project snapshot is stale, and
// which of a project-wide error list belongs to the file being published.
//
// NONE OF IT IS ABOUT THE PROTOCOL. A project root is discovered the same way the compiler
// discovers one, a stale snapshot is the same question `nlc build` asks of its inputs, and a
// duplicate diagnostic is a duplicate whoever is printing it. What stays on the editor's side is
// the state — which documents are open, which roots were scanned — and the `file://` conversion,
// which is the one step that needs a URI.
class EditorWorkspaceFacts {

    // ── Paths ────────────────────────────────────────────────────────────

    // SEPARATORS ARE NOT SIGNIFICANT when two paths are compared for identity. Windows accepts
    // both and the editor's URIs always carry the forward one.
    static func NormalizePath(path: string): string {
        return path.Replace('\\', '/')
    }

    // THE SAME FILE BY TWO NAMES. Full-path resolution first, because a relative name and an
    // absolute one are the common pair; a path the filesystem refuses to resolve still gets the
    // textual comparison rather than throwing, because a diagnostic naming an unresolvable file is
    // still a diagnostic and dropping it would silently lose it.
    static func PathsMatch(left: string, right: string): bool {
        try {
            normalizedLeft := NormalizePath(Path.GetFullPath(left))
            normalizedRight := NormalizePath(Path.GetFullPath(right))
            return string.Equals(normalizedLeft, normalizedRight, StringComparison.OrdinalIgnoreCase)
        } catch ex: Exception {
            return string.Equals(NormalizePath(left), NormalizePath(right), StringComparison.OrdinalIgnoreCase)
        }
    }

    // A DIRECTORY NAME WITHOUT ITS TRAILING SEPARATOR, in either of the two spellings a filesystem
    // accepts, so that a root and the same root with a slash are one name.
    static func TrimSeparators(path: string): string {
        separators: char[] = [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar]
        return path.TrimEnd(separators)
    }

    // UNDER A ROOT MEANS STRICTLY INSIDE IT: the root itself is not under itself, and a sibling
    // directory whose name merely starts with the root's name is not either — which is why the
    // separator is appended before the comparison. The comparison is ORDINAL while `PathsMatch` is
    // case-insensitive; that difference is the shipped behaviour and is preserved here.
    static func IsPathUnderProject(filePath: string, projectRoot: string): bool {
        fullFilePath := Path.GetFullPath(filePath)
        fullProjectRoot := TrimSeparators(Path.GetFullPath(projectRoot)) + Path.DirectorySeparatorChar

        return fullFilePath.StartsWith(fullProjectRoot, StringComparison.Ordinal)
    }

    static func IsFilesystemRoot(directory: string): bool {
        fullPath := TrimSeparators(Path.GetFullPath(directory))
        rootPath := TrimSeparators(Path.GetPathRoot(directory) ?? "")

        return string.Equals(fullPath, rootPath, StringComparison.OrdinalIgnoreCase)
    }

    // THE NEAREST DIRECTORY AT OR ABOVE A FILE THAT DECLARES A PROJECT. When nothing above it
    // does, the file's own directory is the answer — a loose buffer still has a place to stand.
    static func FindProjectRoot(filePath: string): string {
        directory := filePath
        if !Directory.Exists(filePath) {
            directory = Path.GetDirectoryName(filePath) ?? Environment.CurrentDirectory
        }

        current: DirectoryInfo? = new DirectoryInfo(directory)
        while current != null {
            if File.Exists(Path.Combine(current.FullName, "project.yml")) {
                return current.FullName
            }

            current = current.Parent
        }

        return Path.GetFullPath(directory)
    }

    // THE ROOT THE ANALYZER IS TOLD ABOUT when a single document is parsed. A directory that
    // declares a project is one; any other directory is still one, UNLESS it is the filesystem
    // root — analysing from `/` would walk the whole disk, so the analyzer is told nothing and
    // works from the file alone.
    static func AnalysisProjectRoot(projectDir: string): string? {
        fullProjectDir := Path.GetFullPath(projectDir)
        if File.Exists(Path.Combine(fullProjectDir, "project.yml")) {
            return fullProjectDir
        }

        if IsFilesystemRoot(fullProjectDir) {
            return null
        }

        return fullProjectDir
    }

    // THE DEEPEST SCANNED WORKSPACE ROOT CONTAINING A FILE. Deepest, because nested workspace
    // folders are legal and the inner one is the more specific answer.
    static func ContainingWorkspaceRoot(filePath: string, workspaceRoots: IEnumerable<string>): string? {
        best: string? = null
        bestLength := -1

        for root in workspaceRoots {
            if !IsPathUnderProject(filePath, root) {
                continue
            }

            length := Path.GetFullPath(root).Length
            if length > bestLength {
                best = root
                bestLength = length
            }
        }

        return best
    }

    // WHICH ROOT ANSWERS SEMANTIC QUESTIONS for a file: a discovered `project.yml` beats a scanned
    // workspace folder, and the discovered directory stands when neither applies.
    static func SemanticProjectRoot(filePath: string, workspaceRoots: IEnumerable<string>): string {
        discoveredRoot := FindProjectRoot(filePath)
        if File.Exists(Path.Combine(discoveredRoot, "project.yml")) {
            return discoveredRoot
        }

        return ContainingWorkspaceRoot(filePath, workspaceRoots) ?? discoveredRoot
    }

    // EVERY ROOT WHOSE CACHED SNAPSHOT A CHANGE TO THIS FILE COULD INVALIDATE. Both, when they
    // differ: the file's own project and the workspace folder it was scanned under.
    static func PossibleSemanticProjectRoots(filePath: string, workspaceRoots: IEnumerable<string>): List<string> {
        roots := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)

        discoveredRoot := FindProjectRoot(filePath)
        if seen.Add(discoveredRoot) {
            roots.Add(discoveredRoot)
        }

        workspaceRoot := ContainingWorkspaceRoot(filePath, workspaceRoots)
        if workspaceRoot != null && seen.Add(workspaceRoot) {
            roots.Add(workspaceRoot)
        }

        return roots
    }

    // A NAME A COMPILER RESULT CARRIES, made absolute against the project it came from. An
    // already-rooted name is returned UNCHANGED — not normalised — because the compiler produced
    // it and the editor has no better opinion about it.
    static func ProjectFilePath(projectRoot: string, relativeOrAbsolutePath: string): string {
        if Path.IsPathRooted(relativeOrAbsolutePath) {
            return relativeOrAbsolutePath
        }

        return Path.GetFullPath(Path.Combine(projectRoot, relativeOrAbsolutePath))
    }

    // ── Snapshot freshness ───────────────────────────────────────────────

    // THE NEWEST WRITE TIME ACROSS A PROJECT'S SOURCES AND ITS PROJECT FILE. Zero means the
    // project has nothing on disk to compile.
    static func ProjectDiskStamp(projectRoot: string): long {
        latest: long = 0

        for sourceFile in ProjectConfig.EnumerateSourceFiles(projectRoot) {
            written := File.GetLastWriteTimeUtc(sourceFile)
            ticks: long = written.Ticks
            if ticks > latest {
                latest = ticks
            }
        }

        projectFile := Path.Combine(projectRoot, "project.yml")
        if File.Exists(projectFile) {
            projectWritten := File.GetLastWriteTimeUtc(projectFile)
            projectTicks: long = projectWritten.Ticks
            if projectTicks > latest {
                latest = projectTicks
            }
        }

        return latest
    }

    // WHETHER A CACHED SNAPSHOT IS STILL THE ONE THE EDITOR IS LOOKING AT. Disk alone is not
    // enough: an unsaved buffer changes what the project MEANS without changing any file's write
    // time, so every open buffer's path and text join the stamp. A project with neither sources nor
    // buffers has nothing to snapshot and answers null.
    static func ProjectSnapshotStamp(projectRoot: string, sourceTextOverrides: IReadOnlyDictionary<string, string>): string? {
        diskStamp := ProjectDiskStamp(projectRoot)

        keys := new List<string>()
        for entry in sourceTextOverrides {
            keys.Add(entry.Key)
        }
        keys.Sort(StringComparer.OrdinalIgnoreCase)

        hash := new HashCode()
        hash.Add(diskStamp)

        for key in keys {
            text := ""
            if !sourceTextOverrides.TryGetValue(key, out text) {
                text = ""
            }

            // CASE FOLDED RATHER THAN COMPARED case-insensitively: the seed's backend models
            // `HashCode.Add(value)` but not `HashCode.Add(value, comparer)`, and an invariant
            // upper-casing IS what an ordinal-ignore-case hash does to a path before hashing it.
            hash.Add(Path.GetFullPath(key).ToUpperInvariant())
            hash.Add(text)
        }

        if diskStamp == 0 && keys.Count == 0 {
            return null
        }

        return diskStamp.ToString() + ":" + keys.Count.ToString() + ":" + hash.ToHashCode().ToString()
    }

    // ── Refusals ─────────────────────────────────────────────────────────

    // THE TWO REASONS A BUFFER HAS NO PROJECT TO ASK, in the order they are asked. A buffer with
    // neither a project file above it nor a scanned workspace around it has no project at all; one
    // that has a workspace but sits outside it AND has no file on disk is a buffer the project
    // cannot see. Everything else proceeds, and null says so.
    static func SnapshotRefusal(requestedFilePath: string, projectRoot: string, workspaceRoots: IEnumerable<string>): EditorProjectSnapshotRefusal? {
        hasProjectFile := File.Exists(Path.Combine(projectRoot, "project.yml"))
        isUnderKnownWorkspace := ContainingWorkspaceRoot(requestedFilePath, workspaceRoots) != null

        if !hasProjectFile && !isUnderKnownWorkspace {
            return new EditorProjectSnapshotRefusal(projectRoot, EditorProjectSnapshotReason.NoProjectRoot, requestedFilePath, "Open buffer is not backed by a project.yml project or known workspace root")
        }

        if !File.Exists(requestedFilePath) && !IsPathUnderProject(requestedFilePath, projectRoot) && !isUnderKnownWorkspace {
            return new EditorProjectSnapshotRefusal(projectRoot, EditorProjectSnapshotReason.OpenBufferOutsideProject, requestedFilePath, "Open buffer is not backed by a disk file, discovered project root, or known workspace root")
        }

        return null
    }

    static func NoSourceFilesRefusal(projectRoot: string): EditorProjectSnapshotRefusal {
        return new EditorProjectSnapshotRefusal(projectRoot, EditorProjectSnapshotReason.NoSourceFiles, null, "Project has no source files or open buffers to analyze")
    }

    static func LoadFailedRefusal(projectRoot: string, message: string): EditorProjectSnapshotRefusal {
        return new EditorProjectSnapshotRefusal(projectRoot, EditorProjectSnapshotReason.LoadFailed, null, message)
    }

    // ── Diagnostics ──────────────────────────────────────────────────────

    // THE SAME DIAGNOSTIC REPORTED TWICE IS REPORTED ONCE. Two are the same when their code, file,
    // line, column and message all agree; the FIRST of a run wins, so the order the compiler chose
    // survives. A file name that is absent and one that is empty are NOT the same file, which is
    // why the key distinguishes them.
    static func DeduplicateDiagnostics(diagnostics: IEnumerable<CompilerError>): List<CompilerError> {
        results := new List<CompilerError>()
        seen := new HashSet<string>()

        for diagnostic in diagnostics {
            if seen.Add(DiagnosticIdentity(diagnostic)) {
                results.Add(diagnostic)
            }
        }

        return results
    }

    static func DiagnosticIdentity(diagnostic: CompilerError): string {
        codeValue: int = (int)diagnostic.Code
        fileName := diagnostic.FileName
        fileKey := ""
        if fileName != null {
            fileKey = fileName
        }

        builder := new StringBuilder()
        builder.Append(codeValue.ToString())
        builder.Append(" ")
        builder.Append(fileKey)
        builder.Append(" ")
        builder.Append(diagnostic.Line.ToString())
        builder.Append(" ")
        builder.Append(diagnostic.Column.ToString())
        builder.Append(" ")
        builder.Append(diagnostic.Message)
        return builder.ToString()
    }

    // WHICH OF A PROJECT'S ERRORS BELONG TO ONE FILE. A project compiles every file at once, so
    // publishing diagnostics for one document means selecting from the whole project's list by the
    // file each error names — resolved against the project root, because the compiler reports
    // relative names. An error naming no file at all belongs to no document and is dropped.
    static func DiagnosticsForFile(diagnostics: IEnumerable<CompilerError>, projectRoot: string, filePath: string): List<CompilerError> {
        results := new List<CompilerError>()

        for error in diagnostics {
            if string.IsNullOrWhiteSpace(error.FileName) {
                continue
            }

            errorFilePath := ProjectFilePath(projectRoot, error.FileName ?? "")
            if PathsMatch(errorFilePath, filePath) {
                results.Add(error)
            }
        }

        return DeduplicateDiagnostics(results)
    }
}
