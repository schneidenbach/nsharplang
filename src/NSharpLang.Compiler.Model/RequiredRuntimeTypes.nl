namespace NSharpLang.Compiler

import System
import System.Collections.Concurrent


// THE COMPILER'S OWN RUNTIME TYPES BY NAME, PARSED ONCE.
//
// The emitter and the analyzer name the runtime types they need as reflection handles -- `System.Void`,
// `System.Nullable`1`, the collection definitions and enumerators, `System.Console`, the N# runtime's
// `Union`2`/`Result`2` -- through `Type.GetType` with a constant name, because N# has no `typeof`
// spelling for some of them. Every such call parses the
// name and walks the resolution rules again; the emit walk asks for `System.Void` and
// `System.Nullable`1` thousands of times per method body, which was 3-5% of a large program's emit.
//
// The answer for a constant, core-library name never changes within a process, so the first
// successful lookup is kept. A name that does not resolve is never cached (`Find` answers null,
// `Get` throws the caller's own message), exactly as the uncached lookup did. Only `System.*` and
// assembly-qualified names come through here: an unqualified name is searched in the CALLER's assembly
// before the core library, and none of the compiler's assemblies declares a `System.*` type, while an
// assembly-qualified one resolves in the load context every compiler assembly shares -- so moving the
// call into this owner cannot change what it finds.
//
// THREADING: a `ConcurrentDictionary`; two threads that miss the same name at once both resolve it
// and store the same handle.
class RequiredRuntimeTypes {
    private static readonly cache: ConcurrentDictionary<string, Type> = new ConcurrentDictionary<string, Type>(StringComparer.Ordinal)

    // `Type.GetType(name)` for a constant name, kept once it has answered. A miss is not kept, so a
    // name whose assembly loads later is asked again, exactly as the uncached call was.
    static func Find(name: string): Type? {
        cached: Type? = null
        if RequiredRuntimeTypes.cache.TryGetValue(name, out cached) && cached != null {
            return cached
        }

        result := Type.GetType(name)
        if result != null {
            RequiredRuntimeTypes.cache.TryAdd(name, result)
        }
        return result
    }

    static func Get(name: string, missingMessage: string): Type {
        cached: Type? = null
        if RequiredRuntimeTypes.cache.TryGetValue(name, out cached) && cached != null {
            return cached
        }

        result := Type.GetType(name)
        if result == null {
            throw new InvalidOperationException(missingMessage)
        }

        RequiredRuntimeTypes.cache.TryAdd(name, result)
        return result
    }
}
