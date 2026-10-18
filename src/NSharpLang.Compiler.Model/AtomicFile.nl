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
// Windows refuses to replace a file that is mapped. It does allow it to be RENAMED, so the fallback
// moves the old file aside, moves the new one into place, and deletes the aside when it can; a
// leftover `<name>.replaced-<id>` is swept on the next replacement of that name.
class AtomicFile {
    static func WriteAllBytes(path: string, bytes: byte[]) {
        tempPath := GetTemporaryPath(path)
        try {
            File.WriteAllBytes(tempPath, bytes)
            Replace(tempPath, path)
        } catch ex: Exception {
            TryDelete(tempPath)
            throw
        }
    }

    // `File.Copy(source, destination, true)` with the same guarantee. The copy keeps the source's
    // last-write time, which the reference-assembly up-to-date check depends on.
    static func Copy(source: string, destination: string) {
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

    private static func Replace(tempPath: string, path: string) {
        try {
            File.Move(tempPath, path, true)
            return
        } catch ex: Exception {
            if !File.Exists(path) {
                throw
            }
        }

        // The target exists and could not be replaced: it is held open without delete sharing.
        SweepReplaced(path)
        aside := Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path)) ?? ".", GetReplacedPrefix(path) + Guid.NewGuid().ToString("N").Substring(0, 12))
        File.Move(path, aside)
        File.Move(tempPath, path)
        TryDelete(aside)
    }

    private static func SweepReplaced(path: string) {
        directory := Path.GetDirectoryName(Path.GetFullPath(path)) ?? "."
        try {
            for leftover in Directory.EnumerateFiles(directory, GetReplacedPrefix(path) + "*") {
                TryDelete(leftover)
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
