namespace NSharpLang.Compiler

import System
import System.IO

// BUILD OUTPUTS ARE REPLACED, NEVER REWRITTEN IN PLACE.
//
// A running process maps the assemblies it has loaded. `File.WriteAllBytes` and
// `File.Copy(…, overwrite: true)` truncate the existing file and write into the SAME inode, so a
// rebuild under a live `nlc run` server changed the bytes the process still had mapped: code that was
// already loaded kept working, and the next lazy load read new bytes through old metadata
// (`BadImageFormatException`). Writing a sibling temporary file and renaming it over the target gives
// the output a new inode; the running process keeps the old one until it exits, exactly as it does
// under `dotnet build`.
//
// Windows refuses to replace a file that is mapped. It does allow it to be RENAMED, so when the
// replace fails with an IO or permission error the fallback moves the old file aside, moves the new
// one into place (moving the old one back if that fails), and deletes the aside when it can. A
// leftover `<name>.replaced-<id>`, and a `<name>.<id>.tmp` from a build that was killed mid-write,
// are swept on the next write of that name.
class AtomicFile {
    static func WriteAllBytes(path: string, bytes: byte[]) {
        SweepLeftovers(path)
        tempPath := GetTemporaryPath(path)
        try {
            File.WriteAllBytes(tempPath, bytes)
            Replace(tempPath, path)
        } catch ex: Exception {
            TryDelete(tempPath)
            throw
        }
    }

    static func WriteAllText(path: string, text: string) {
        WriteAllBytes(path, new System.Text.UTF8Encoding(false).GetBytes(text))
    }

    // `File.Copy(source, destination, true)` with the same guarantee. The copy keeps the source's
    // last-write time, which the reference-assembly up-to-date check depends on.
    static func Copy(source: string, destination: string) {
        SweepLeftovers(destination)
        tempPath := GetTemporaryPath(destination)
        try {
            File.Copy(source, tempPath, true)
            Replace(tempPath, destination)
        } catch ex: Exception {
            TryDelete(tempPath)
            throw
        }
    }

    static func GetTemporaryPath(path: string): string {
        return path + "." + Guid.NewGuid().ToString("N") + ".tmp"
    }

    static func GetReplacedPrefix(path: string): string {
        return (Path.GetFileName(path) ?? path) + ".replaced-"
    }

    // A temporary file this young may belong to a build that is still writing it.
    static func GetStaleTemporaryAge(): TimeSpan {
        return TimeSpan.FromHours(1)
    }

    // The failure of a plain replace, or null when it succeeded. Only IO and permission errors count:
    // anything else is not a held file and is not retried.
    private static func TryReplace(tempPath: string, path: string): Exception? {
        failure: Exception? = null
        try {
            File.Move(tempPath, path, true)
        } catch ioFailure: IOException {
            failure = ioFailure
        } catch denied: UnauthorizedAccessException {
            failure = denied
        }

        return failure
    }

    private static func Replace(tempPath: string, path: string) {
        original := TryReplace(tempPath, path)
        if original == null {
            return
        }

        if !File.Exists(path) {
            throw original
        }

        // The target exists and could not be replaced: it is held open without delete sharing.
        aside := Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path)) ?? ".", GetReplacedPrefix(path) + Guid.NewGuid().ToString("N").Substring(0, 12))
        File.Move(path, aside)
        failure := TryMoveInto(tempPath, path, aside)
        if failure != null {
            throw failure
        }

        TryDelete(aside)
    }

    // Moves the new file into place; when that fails the previous output is moved back, so the
    // caller is left with the old file rather than none, and the failure is returned to report.
    private static func TryMoveInto(tempPath: string, path: string, aside: string): Exception? {
        failure: Exception? = null
        try {
            File.Move(tempPath, path)
        } catch moveFailure: Exception {
            failure = moveFailure
        }

        if failure != null {
            TryRestore(aside, path)
        }

        return failure
    }

    private static func TryRestore(aside: string, path: string) {
        try {
            File.Move(aside, path, true)
        } catch restoreFailure: Exception {
            return
        }
    }

    private static func SweepLeftovers(path: string) {
        directory := Path.GetDirectoryName(Path.GetFullPath(path)) ?? "."
        if !Directory.Exists(directory) {
            return
        }

        name := Path.GetFileName(path) ?? path
        try {
            for leftover in Directory.EnumerateFiles(directory, GetReplacedPrefix(path) + "*") {
                TryDelete(leftover)
            }

            cutoff := DateTime.UtcNow - GetStaleTemporaryAge()
            for stale in Directory.EnumerateFiles(directory, name + ".*.tmp") {
                if File.GetLastWriteTimeUtc(stale) < cutoff {
                    TryDelete(stale)
                }
            }
        } catch ex: Exception {
            return
        }
    }

    private static func TryDelete(path: string) {
        try {
            if File.Exists(path) {
                File.Delete(path)
            }
        } catch ex: Exception {
            return
        }
    }
}
