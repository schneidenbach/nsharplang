namespace NSharpLang.Compiler

import System
import System.Reflection


// A PROPERTY READ BY NAME OFF A TYPE THE COMPILER DID NOT WRITE, WITH C#'S HIDING RULE.
//
// `Type.GetProperty(name)` answers ambiguity with an exception, and a real library hits it: a derived
// type that redeclares an inherited property with `new` and a different type
// (`DbContextOptionsBuilder<TContext>.Options` returns `DbContextOptions<TContext>` over the base
// class's non-generic `DbContextOptions`) leaves TWO instance properties of that name in the
// flattened set, and the binder refuses to choose. An exception escaping member lookup is a crashed
// build with no code and no position, and the language already has the answer: a member declared in
// a more derived type HIDES a same-named member of its bases (C# §12.5), so the most derived
// declaration IS the member.
//
// THE FAST PATH IS THE BINDER'S OWN, so every lookup that was never ambiguous answers exactly what it
// always did. Only the ambiguous case walks the declaration chain itself — `DeclaredOnly` from the
// type outward, the first declaration of the name wins — which is the same discipline
// `ForeachPatternFacts` uses for `GetEnumerator` and `Current`. An indexer is not a property read and
// is skipped, as the binder skips it for a name lookup with no index arguments.
//
// FIELDS AND EVENTS ARE NOT HERE BECAUSE THE RUNTIME DOES NOT THROW FOR THEM: `GetField` and
// `GetEvent` keep the most derived declaration of a hidden name and refuse only two members declared
// at the SAME level.
class ReflectedMemberLookup {
    static func FindProperty(owner: Type, name: string): PropertyInfo? {
        return FindProperty(owner, name, BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
    }

    static func FindProperty(owner: Type, name: string, flags: BindingFlags): PropertyInfo? {
        try {
            return owner.GetProperty(name, flags)
        } catch ex: AmbiguousMatchException {
            return FindMostDerivedProperty(owner, name, flags)
        }
    }

    static func FindMostDerivedProperty(owner: Type, name: string, flags: BindingFlags): PropertyInfo? {
        declaredFlags := flags | BindingFlags.DeclaredOnly
        current: Type? = owner
        while current != null {
            for candidate in current.GetProperties(declaredFlags) {
                if candidate.Name == name && candidate.GetIndexParameters().Length == 0 {
                    return candidate
                }
            }

            current = current.BaseType
        }

        return null
    }
}
