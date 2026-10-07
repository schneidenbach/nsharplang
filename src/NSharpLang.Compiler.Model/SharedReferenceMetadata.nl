namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection

// ONE LOADED REFERENCE SET PER COMPILATION.
//
// A compilation reads its references' metadata through a `MetadataLoadContext`, and it used to open
// that context once per READER: the analyzer opened one, every parallel analysis worker opened its
// own (each re-reading the whole reference closure), and the IL back end opened a third for its
// external type scan (`ExternalAssemblyScan.OpenWithReferences`), reading the same files again. On
// the agent-loop `large` project that was 151 reference images for a 37-file closure.
//
// This object IS the one context, with the mutable state that travels with it: the directories its
// resolver probes, the package versions the project pinned, the resolver's failure table, and the
// GATE that serialises every write to them. The analyzer's load surface that opened the context owns
// it (`AnalyzerMetadataLoadSurface.Open`); every other reader of the compilation attaches to it
// (`AnalyzerMetadataLoadSurface.Attach`, `ExternalAssemblyScan.OpenWithReferences`) and never
// disposes it.
//
// WHY ONE CONTEXT CAN SERVE CONCURRENT READERS. `MetadataLoadContext` is built for it: its loaded-
// assembly and bind tables are `ConcurrentDictionary`s filled with `GetOrAdd` (a racing load of the
// same file keeps one winner and compares module ids), its type objects publish their lazily computed
// facts through volatile fields, and the metadata readers underneath are immutable once a file is
// loaded. It calls the assembly resolver WITHOUT holding a lock of its own, possibly from several
// threads at once, so the resolver's state is the compiler's to protect: every load the compiler
// asks for, every resolver probe and every write to the tables below happens under `Gate`. The gate is
// re-entrant (`lock`), and nothing waits on another thread while holding it.
//
// WHAT EACH READER STILL OWNS. An analyzer's registry of the assemblies it may resolve against, in the
// order its own loads registered them, stays the analyzer's: sharing the context shares the FILES
// read, not which of them an analysis can see, so a worker analyses a file against exactly the list
// it did before.
class SharedReferenceMetadata {
    Context: MetadataLoadContext
    Gate: object
    SearchDirectories: List<string>
    PinnedPackageVersions: Dictionary<string, string>
    ResolverFailures: Dictionary<string, string>

    constructor(context: MetadataLoadContext, gate: object, searchDirectories: List<string>, pinnedPackageVersions: Dictionary<string, string>, resolverFailures: Dictionary<string, string>) {
        Context = context
        Gate = gate
        SearchDirectories = searchDirectories
        PinnedPackageVersions = pinnedPackageVersions
        ResolverFailures = resolverFailures
    }

    // The assembly this context already read from exactly `path`, or null. The comparison is on the
    // full path, ordinally: a different file of the same identity is a different image.
    func LoadedFrom(path: string): Assembly? {
        if path == null || path.Length == 0 {
            return null
        }

        fullPath := Path.GetFullPath(path)
        for assembly in Context.GetAssemblies() {
            location := assembly.Location
            if location != null && location.Length > 0 && string.Equals(Path.GetFullPath(location), fullPath, StringComparison.Ordinal) {
                return assembly
            }
        }

        return null
    }

    // A copy of the resolver's failure table, taken under the gate, for a reader that reports it while
    // other readers may still be probing.
    func ResolverFailureSnapshot(): Dictionary<string, string> {
        lock Gate {
            return new Dictionary<string, string>(ResolverFailures, StringComparer.Ordinal)
        }
    }
}
