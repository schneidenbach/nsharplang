namespace NSharpLang.Compiler

import System
import System.Reflection
import System.Runtime.CompilerServices


// WHICH ASSEMBLIES ARRIVED ON DEMAND, AND WHO LOADS THE NEXT ONE.
//
// A `Microsoft.NETCore.App` assembly that is not in the preloaded common table is loaded when a file
// names one of its namespaces (`FrameworkNamespaceIndex`). Such an assembly must answer a name only
// through that namespace: an import of it, or a spelling qualified with it. It must NEVER answer a
// BARE name through the exported-name scan a simple spelling falls back to, because whether it is
// loaded at all depends on which other files were analysed first, by which worker, in which session
// -- and a bare name that resolved because another file imported `System.Numerics` would bind in one
// worker layout and not in another. C# resolves a simple name only through the file's own usings, and
// this is the same rule for the part of the reference set that is loaded lazily. So every on-demand
// load is MARKED here, and the bare-name scans (`AnalyzerExternalTypeProbe`'s exported-name index,
// `ExternalQualifiedTypeResolver.TryResolveBareName`, the any-namespace extension scan) skip a marked
// assembly.
//
// The mark is on the `Assembly` object, in a weak table: it dies with the load context that made the
// assembly, and the parallel analysis workers that share one context share its marks.
//
// THE LOADER REGISTRY IS KEYED BY THE ANALYZER'S ASSEMBLY LIST, held weakly. Several owners resolve
// fully-qualified spellings by sweeping that list themselves (`ExternalQualifiedTypeResolver`, called
// from the declaration context, the declaration policy and member access); registering the list's
// loader here lets each of them load the spelling's framework namespace on a miss without threading
// the load surface through every constructor.
class FrameworkOnDemandLoads {
    private static readonly marks: ConditionalWeakTable<Assembly, object> = new ConditionalWeakTable<Assembly, object>()
    private static readonly loaders: ConditionalWeakTable<object, Func<string, bool>> = new ConditionalWeakTable<object, Func<string, bool>>()
    private static readonly marker: object = new object()

    static func Mark(assembly: Assembly) {
        FrameworkOnDemandLoads.marks.AddOrUpdate(assembly, FrameworkOnDemandLoads.marker)
    }

    static func IsOnDemand(assembly: Assembly): bool {
        found: object? = null
        return FrameworkOnDemandLoads.marks.TryGetValue(assembly, out found)
    }

    // `loader` is the analyzer load surface's `LoadFrameworkNamespaceOfType`.
    static func RegisterLoader(assemblies: object, loader: Func<string, bool>) {
        FrameworkOnDemandLoads.loaders.AddOrUpdate(assemblies, loader)
    }

    // Loads the framework namespace of `fullName` for whoever owns `assemblies`; true when the list
    // grew, so a caller that missed knows a second sweep can answer differently.
    static func LoadFor(assemblies: object, fullName: string): bool {
        loader: Func<string, bool>? = null
        if assemblies == null || !FrameworkOnDemandLoads.loaders.TryGetValue(assemblies, out loader) || loader == null {
            return false
        }

        return loader(fullName)
    }
}
