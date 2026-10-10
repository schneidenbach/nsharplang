namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Runtime.InteropServices

// THE FILES A LONG-LIVED COMPILER HAS READ, AND WHETHER ANY OF THEM HAS CHANGED SINCE.
//
// A compiler that outlives one command keeps what it read: the workspace server's executable handles
// (`DaemonLoadedReferenceGuard`), the language server's analyzer with its metadata load context
// (`DocumentManager`). Neither can be told "that file changed" by the runtime -- a load context will
// not read a second file of an identity it holds -- so each records the version of every file it
// read and asks before answering again. A version is the file's length and last write time, a `stat`
// per file. Files under the runtime directory and the host's own directory are not recorded: they
// cannot change under a running process without the process itself being replaced.
class ReferenceFileVersions {
    versions: Dictionary<string, string>
    excludedRoots: string[]

    constructor() {
        versions = new Dictionary<string, string>(StringComparer.Ordinal)
        excludedRoots = [
            NormalizeRoot(RuntimeEnvironment.GetRuntimeDirectory()),
            NormalizeRoot(AppContext.BaseDirectory)
        ]
    }

    Count: int => versions.Count

    // Remembers the version of `location` unless it is already remembered or excluded.
    func Record(location: string) {
        if location == null || location == "" || versions.ContainsKey(location) || IsExcluded(location) {
            return
        }

        versions[location] = VersionOf(location)
    }

    // The first remembered file whose version on disk differs, or null.
    func FindChanged(): string? {
        for entry in versions {
            if VersionOf(entry.Key) != entry.Value {
                return entry.Key
            }
        }

        return null
    }

    func Clear() {
        versions.Clear()
    }

    func IsExcluded(location: string): bool {
        for root in excludedRoots {
            if root != "" && location.StartsWith(root, StringComparison.Ordinal) {
                return true
            }
        }

        return false
    }

    static func VersionOf(path: string): string {
        try {
            info := new FileInfo(path)
            if !info.Exists {
                return "missing"
            }

            return info.Length.ToString() + "|" + info.LastWriteTimeUtc.Ticks.ToString()
        } catch statFailure: Exception {
            return "unreadable"
        }
    }

    static func NormalizeRoot(directory: string): string {
        if directory == null || directory == "" {
            return ""
        }

        full := Path.GetFullPath(directory)
        if !full.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal) {
            full = full + Path.DirectorySeparatorChar.ToString()
        }

        return full
    }
}
