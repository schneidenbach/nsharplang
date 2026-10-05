namespace NSharpLang.Compiler

import System
import System.Collections.Generic
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
// THREADING: the table is a `ConditionalWeakTable`, safe for concurrent readers and writers and
// keyed by assembly identity without keeping a collectible load context alive. The name sets are
// never mutated after they are built. Two threads that miss the same assembly at once may both read
// its tables; the second `AddOrUpdate` stores an equal set.
class AssemblyTopLevelTypeNames {
    Names: HashSet<string>?

    constructor(names: HashSet<string>?) {
        Names = names
    }
}

class AssemblyTypeNameIndex {
    private static readonly namesByAssembly: ConditionalWeakTable<Assembly, AssemblyTopLevelTypeNames> = new ConditionalWeakTable<Assembly, AssemblyTopLevelTypeNames>()

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
            location = assembly.Location
        }
        read := new AssemblyTopLevelTypeNames(ExternalAssemblyScan.ReadTopLevelTypeNames(location))
        AssemblyTypeNameIndex.namesByAssembly.AddOrUpdate(assembly, read)
        return read.Names
    }
}
