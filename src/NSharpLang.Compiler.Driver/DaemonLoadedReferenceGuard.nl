namespace NSharpLang.Cli.Daemon

import System
import NSharpLang.Compiler

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
// directory (`ReferenceFileVersions`, which the language server's analyzer uses for the same reason),
// and before each command checks that none changed on disk. One that did means this process can no
// longer answer exactly as a fresh one would: the request is declined (the client runs it in-process)
// and the server retires, so the next command starts a fresh one. The check is a `stat` per loaded
// reference — a handful of files.
class DaemonLoadedReferenceGuard {
    versions: ReferenceFileVersions

    constructor() {
        versions = new ReferenceFileVersions()
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

            versions.Record(location)
        }
    }

    // The first remembered file whose version on disk differs, or null.
    func FindChanged(): string? {
        return versions.FindChanged()
    }
}
