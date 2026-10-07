namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// THE WORKSPACE SERVER'S INCREMENTAL SESSIONS: what makes a warm `nlc check` or `nlc build` after a
// body edit re-analyse only the files that edit can reach.
//
// A one-shot `nlc` has nothing to carry from one command to the next but its `obj/` stamp, which
// answers an UNCHANGED compilation and nothing else. The workspace server (`DaemonExecHost`) runs
// command after command in one process, so it can keep each compilation's
// `IncrementalCompilationState` -- the analyzer with its loaded reference closure, and every file's
// unit, semantic model and dependency record -- and hand it to the next compilation of the same
// project, which then re-analyses only what the edit invalidated (`IncrementalCompilationPlan`).
//
// One session per COMPILATION IDENTITY: the project, the assembly, whether test sources are
// included, AOT, and which command compiles it (a check analyses for diagnostics and validates the
// emission in memory; a build emits what it keeps). Anything else the analyses depend on -- the
// configuration, defines, references and their bytes -- is the state's own environment key, which
// resets the state when it moves, so a stale session can cost a full compilation but never a wrong
// one.
//
// Only a command the server runs for a client gets a session (`CliInvocationContext`); an ordinary
// process and the server's own warm-up compile exactly as before. The server runs one command at a
// time, so a session is never used by two compilations at once; `Acquire` still refuses a session
// that is in use rather than share it. The sessions register with `WarmStateRegistry`: a trim drops
// them all (the next command rebuilds), a path change needs nothing (the plan compares content), and
// `nlc daemon status` describes them.
class WarmIncrementalSessions {
    private static gate: object = new object()
    private static keys: List<string> = new List<string>()
    private static sessions: List<IncrementalProjectSession> = new List<IncrementalProjectSession>()
    private static busy: HashSet<string> = new HashSet<string>(StringComparer.Ordinal)
    private static registered: bool = false

    // The identity of one compilation's session.
    static func KeyFor(projectRoot: string, assemblyName: string, purpose: string, includeTests: bool, aot: bool): string {
        return Path.GetFullPath(projectRoot) + "|" + assemblyName + "|" + purpose + "|tests=" + includeTests.ToString() + "|aot=" + aot.ToString()
    }

    // Hands `compiler` the warm state for its identity when this command is running in the workspace
    // server; does nothing otherwise. Returns the key to `Release` after the compilation, or null
    // when no state was attached.
    static func Attach(compiler: MultiFileCompiler, projectRoot: string, assemblyName: string, purpose: string, includeTests: bool, aot: bool): string? {
        if !CliInvocationContext.IsRemoteInvocation() {
            return null
        }

        key := KeyFor(projectRoot, assemblyName, purpose, includeTests, aot)
        session := Acquire(key, projectRoot, assemblyName)
        if session == null {
            return null
        }

        compiler.IncrementalState = (session ?? new IncrementalProjectSession(projectRoot, assemblyName)).State
        return key
    }

    // The session for `key`, created on first use, or null while another compilation holds it.
    static func Acquire(key: string, projectRoot: string, assemblyName: string): IncrementalProjectSession? {
        // Outside the lock: the registry's `Describe` calls back into `Describe` here while holding
        // its own lock, so taking the two in the other order would be a deadlock.
        EnsureRegistered()
        lock WarmIncrementalSessions.gate {
            if WarmIncrementalSessions.busy.Contains(key) {
                return null
            }

            WarmIncrementalSessions.busy.Add(key)
            index := WarmIncrementalSessions.keys.IndexOf(key)
            if index >= 0 {
                return WarmIncrementalSessions.sessions[index]
            }

            created := new IncrementalProjectSession(projectRoot, assemblyName)
            WarmIncrementalSessions.keys.Add(key)
            WarmIncrementalSessions.sessions.Add(created)
            return created
        }
    }

    static func Release(key: string?) {
        if key == null {
            return
        }

        lock WarmIncrementalSessions.gate {
            WarmIncrementalSessions.busy.Remove(key ?? "")
        }
    }

    // A compilation that THREW may have left its state half-replaced: drop the session, so the next
    // compilation of that identity starts from nothing instead of from a state nobody committed.
    static func Discard(key: string?) {
        if key == null {
            return
        }

        lock WarmIncrementalSessions.gate {
            name := key ?? ""
            WarmIncrementalSessions.busy.Remove(name)
            index := WarmIncrementalSessions.keys.IndexOf(name)
            if index >= 0 {
                WarmIncrementalSessions.keys.RemoveAt(index)
                WarmIncrementalSessions.sessions.RemoveAt(index)
            }
        }
    }

    // Drops every session that is not in use; the next compilation of each project is a full one.
    static func Clear() {
        lock WarmIncrementalSessions.gate {
            index := WarmIncrementalSessions.keys.Count - 1
            while index >= 0 {
                if !WarmIncrementalSessions.busy.Contains(WarmIncrementalSessions.keys[index]) {
                    WarmIncrementalSessions.keys.RemoveAt(index)
                    WarmIncrementalSessions.sessions.RemoveAt(index)
                }
                index = index - 1
            }
        }
    }

    static func Count(): int {
        lock WarmIncrementalSessions.gate {
            return WarmIncrementalSessions.keys.Count
        }
    }

    static func Describe(): string {
        lock WarmIncrementalSessions.gate {
            files := 0
            for session in WarmIncrementalSessions.sessions {
                files = files + session.State.Files.Count
            }

            return WarmIncrementalSessions.keys.Count.ToString() + " compilations, " + files.ToString() + " files retained"
        }
    }

    static func EnsureRegistered() {
        if WarmIncrementalSessions.registered {
            return
        }

        WarmIncrementalSessions.registered = true
        WarmStateRegistry.Register(
            "incremental-compilations",
            path => {
            },
            () => WarmIncrementalSessions.Clear(),
            () => WarmIncrementalSessions.Describe()
        )
    }
}
