namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.CompilerServices


// THE ONE ANSWER TO "COULD THIS ASSEMBLY DECLARE THIS PLAIN TYPE NAME", READ ONCE PER ASSEMBLY.
//
// `Assembly.GetType(name)` finds a top-level type exactly when the name is one of the module's TYPE
// DEFINITIONS or one of its EXPORTED TYPES (a forwarder). The miss is the expensive half: on a
// `MetadataLoadContext` assembly the load context parses the name, takes its lock, and builds then
// discards a `TypeLoadException` with a localized message (~6 us). Name resolution is mostly misses —
// a simple name probed against every imported namespace, every enclosing namespace and every
// referenced assembly — so before this index the analyzer's probes (`AnalyzerExternalTypeProbe`,
// `ExternalQualifiedTypeResolver`, `AnalyzerDeclarationContext`) spent 35-60% of a build's CPU
// constructing exceptions nobody read, and the load context's lock made that time unparallelisable.
//
// The two metadata tables are read once per assembly (`ExternalAssemblyScan.ReadTopLevelTypeNames`)
// and a miss becomes a hash probe. An assembly whose tables cannot be read — in-memory, no
// `Location`, an unreadable file — answers "maybe", so `GetTypeOrNull` then asks `GetType` exactly as
// before; a spelling that is not a PLAIN name (generic arguments, assembly qualification, escapes) is
// always asked too. The answer is therefore identical to `Assembly.GetType(name)`, only cheaper.
//
// TWO LEVELS OF MEMORY. Per ASSEMBLY OBJECT (a `ConditionalWeakTable`, so the table dies with the
// load context that made the assembly): a resolver asks about the same handful of assemblies many
// thousands of times per analysis, and even a `stat` per question would cost more than the misses it
// saves. And per FILE VERSION (path, length and write time): every compilation opens its references
// in a new load context, so in a long-lived process -- the workspace server, the language server --
// the second compilation's assembly objects are new while their files are not, and the tables are
// read once per file version for the life of the process instead of once per compilation. That half
// registers with `WarmStateRegistry` ("reference-type-names"), so a trim drops it and
// `nlc daemon status` reports it.
//
// THREADING: the weak table is safe for concurrent readers and writers and keyed by assembly
// identity without keeping a collectible load context alive; the file-version table is behind one
// lock. The name sets are never mutated after they are built. Two threads that miss the same
// assembly at once may both read its tables; the second `AddOrUpdate` stores an equal set.
class AssemblyTopLevelTypeNames {
    Names: HashSet<string>?

    constructor(names: HashSet<string>?) {
        Names = names
    }
}

class AssemblyTypeNameIndex {
    private static readonly namesByAssembly: ConditionalWeakTable<Assembly, AssemblyTopLevelTypeNames> = new ConditionalWeakTable<Assembly, AssemblyTopLevelTypeNames>()
    private static gate: object = new object()
    private static versions: Dictionary<string, string> = new Dictionary<string, string>(StringComparer.Ordinal)
    private static namesByPath: Dictionary<string, HashSet<string>?> = new Dictionary<string, HashSet<string>?>(StringComparer.Ordinal)
    private static registered: bool = false

    // False only when the assembly's own tables prove it neither defines nor forwards this top-level
    // name (`Namespace.Name`, no nesting).
    static func MayDeclareTopLevelType(assembly: Assembly, topLevelName: string): bool {
        names := NamesOf(assembly)
        return names == null || names.Contains(topLevelName)
    }

    // `assembly.GetType(fullName)`, answered from the index when the index can prove a miss.
    static func GetTypeOrNull(assembly: Assembly, fullName: string): Type? {
        topLevelName := ExternalAssemblyScan.PlainTopLevelTypeName(fullName)
        if topLevelName.Length > 0 && !AssemblyTypeNameIndex.MayDeclareTopLevelType(assembly, topLevelName) {
            return null
        }

        return assembly.GetType(fullName)
    }

    private static func NamesOf(assembly: Assembly): HashSet<string>? {
        cached: AssemblyTopLevelTypeNames? = null
        if AssemblyTypeNameIndex.namesByAssembly.TryGetValue(assembly, out cached) && cached != null {
            return cached.Names
        }

        location := ""
        if !assembly.IsDynamic {
            try {
                location = assembly.Location
            } catch locationFailure: Exception {
                location = ""
            }
        }
        read := new AssemblyTopLevelTypeNames(TopLevelNamesAt(location))
        AssemblyTypeNameIndex.namesByAssembly.AddOrUpdate(assembly, read)
        return read.Names
    }

    // The top-level names the file at `path` defines or forwards, read once per file version; null
    // when it has no readable tables (no path, missing, not metadata).
    static func TopLevelNamesAt(path: string): HashSet<string>? {
        if string.IsNullOrEmpty(path) || !File.Exists(path) {
            return null
        }

        version := VersionOf(path)
        EnsureRegistered()
        lock AssemblyTypeNameIndex.gate {
            cachedVersion := ""
            if AssemblyTypeNameIndex.versions.TryGetValue(path, out cachedVersion) && cachedVersion == version {
                return AssemblyTypeNameIndex.namesByPath[path]
            }
        }

        read := ExternalAssemblyScan.ReadTopLevelTypeNames(path)
        lock AssemblyTypeNameIndex.gate {
            AssemblyTypeNameIndex.versions[path] = version
            AssemblyTypeNameIndex.namesByPath[path] = read
        }

        return read
    }

    static func VersionOf(path: string): string {
        info := new FileInfo(path)
        return info.Length.ToString() + "|" + info.LastWriteTimeUtc.Ticks.ToString()
    }

    static func FileCount(): int {
        lock AssemblyTypeNameIndex.gate {
            return AssemblyTypeNameIndex.versions.Count
        }
    }

    static func ClearFiles() {
        lock AssemblyTypeNameIndex.gate {
            AssemblyTypeNameIndex.versions.Clear()
            AssemblyTypeNameIndex.namesByPath.Clear()
        }
    }

    static func EnsureRegistered() {
        if AssemblyTypeNameIndex.registered {
            return
        }

        AssemblyTypeNameIndex.registered = true
        WarmStateRegistry.Register(
            "reference-type-names",
            path => {
            },
            () => AssemblyTypeNameIndex.ClearFiles(),
            () => AssemblyTypeNameIndex.FileCount().ToString() + " reference assemblies indexed"
        )
    }
}
