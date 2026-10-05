namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.IO
import System.Runtime.InteropServices

// A LONG-LIVED COMPILER MUST NOT OUTLIVE THE FILES IT LOADED.
//
// To emit, the compiler loads executable handles for a project's references (packages, and the
// BUILT OUTPUT of `project:` dependencies) into load contexts that live as long as the process
// (`ExternalAssemblyScan.TryLoadExactIdentityAssembly`), and the runtime cannot load a second file
// of the same identity into a context, nor unload one that is not collectible. In a one-shot `nlc`
// that is invisible. In the workspace server it is a stale compiler: rebuild a referenced library
// with a new member, and the next command's emitter still sees the OLD library — measured, the call to
// the new member declined at emit while an in-process run built and ran it.
//
// So the server records every assembly file it has loaded from outside the runtime and the CLI's own
// directory (those two are covered by the build identity), and before each command checks that none
// changed on disk. One that did means this process can no longer answer exactly as a fresh one would:
// the request is declined (the client runs it in-process) and the server retires, so the next command
// starts a fresh one. The check is a `stat` per loaded reference — a handful of files.
class DaemonLoadedReferenceGuard {
    versions: Dictionary<string, string>
    excludedRoots: string[]

    constructor() {
        versions = new Dictionary<string, string>(StringComparer.Ordinal)
        excludedRoots = [
            NormalizeRoot(RuntimeEnvironment.GetRuntimeDirectory()),
            NormalizeRoot(AppContext.BaseDirectory)
        ]
    }

    // Remember the version of every loaded assembly file not yet remembered.
    func Record() {
        for assembly in AppDomain.CurrentDomain.GetAssemblies() {
            location := ""
            try {
                if assembly.IsDynamic {
                    continue
                }

                location = assembly.Location
            } catch locationFailure: Exception {
                continue
            }

            if location == "" || versions.ContainsKey(location) || IsExcluded(location) {
                continue
            }

            versions[location] = VersionOf(location)
        }
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
