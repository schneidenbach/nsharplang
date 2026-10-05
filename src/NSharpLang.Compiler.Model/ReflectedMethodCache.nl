namespace NSharpLang.Compiler

import System
import System.Collections.Concurrent
import System.Reflection
import System.Runtime.CompilerServices


// A TYPE'S METHODS, READ ONCE PER BINDING-FLAGS SET.
//
// `Type.GetMethods(flags)` builds a new array every call -- on a `MetadataLoadContext` type it
// re-materialises every `MethodInfo` -- and the analyzer's member resolution and both ends of every
// user-defined-conversion question ask it of the same few hundred types over and over: 0.5 GB of
// arrays in one Compiler.Core build. The answer for a COMPLETE type never changes, so the first one
// is kept, per type and per flags.
//
// ONLY COMPLETE TYPES. A builder-bound type (`TypeInfoIdentityFacts.IsBuilderBound`: a
// `TypeBuilder`, a generic parameter builder, anything of a dynamic assembly) is still being given
// its members, so it is always asked afresh. The arrays handed out are SHARED: every caller only
// reads them. A `GetMethods` that throws is not kept, so the caller sees the same exception it did.
//
// THREADING: a `ConditionalWeakTable` of `ConcurrentDictionary`s -- safe under parallel analysis,
// and holding no type (or its load context) alive.
class ReflectedMethodSets {
    ByFlags: ConcurrentDictionary<int, MethodInfo[]>

    constructor() {
        ByFlags = new ConcurrentDictionary<int, MethodInfo[]>()
    }
}

class ReflectedMethodCache {
    private static readonly byType: ConditionalWeakTable<Type, ReflectedMethodSets> = new ConditionalWeakTable<Type, ReflectedMethodSets>()

    static func GetMethods(owner: Type, flags: BindingFlags): MethodInfo[] {
        if TypeInfoIdentityFacts.IsBuilderBound(owner) {
            return owner.GetMethods(flags)
        }

        sets: ReflectedMethodSets? = null
        if !ReflectedMethodCache.byType.TryGetValue(owner, out sets) || sets == null {
            created := new ReflectedMethodSets()
            ReflectedMethodCache.byType.AddOrUpdate(owner, created)
            sets = created
        }

        key := (int)flags
        cached: MethodInfo[]? = null
        if sets.ByFlags.TryGetValue(key, out cached) && cached != null {
            return cached
        }

        methods := owner.GetMethods(flags)
        sets.ByFlags.TryAdd(key, methods)
        return methods
    }
}
