namespace NSharpLang.Compiler

import System
import System.Reflection


// THE FRIEND GRANTS OF THE ASSEMBLY CURRENTLY BEING EMITTED, AS A THREAD-LOCAL SCOPE.
//
// The analyzer HOLDS an `InternalsVisibleToGrants` instance, because it owns the object graph that
// asks the question and knows the project it is analysing. The columnar back end does not: its
// accessibility filters (`ColumnarOrdinaryRuntimeDirectCallResolver.IsPublicCandidateForLookup`,
// `ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel`) are static functions reached
// from deep inside an emit walk, and the same functions are called by planner unit tests and by code
// intelligence, neither of which is emitting an assembly at all.
//
// So the grants reach the back end exactly the way its decline trace does — as a scope opened by the
// one function that knows the name of the assembly being emitted
// (`MultiFileCompiler.RunColumnarEmissionOnCurrentThread`) and closed when that emission ends.
// Emission runs on its own wide-stack thread and a language server can emit for two projects at
// once, so the scope is per-THREAD and never global.
//
// WHEN NO SCOPE IS OPEN NOTHING IS GRANTED. That is not an unknown answer, it is the right one: a
// caller with no assembly identity is not the friend of anything, and it is exactly the behaviour
// every one of these filters had before friends existed.
class InternalsVisibleToEmissionScope {
    [System.ThreadStatic]
    private static Current: InternalsVisibleToGrants?

    static func Begin(assemblyName: string?) {
        scope := new InternalsVisibleToGrants()
        scope.SetCompilingAssemblyName(assemblyName)
        InternalsVisibleToEmissionScope.Current = scope
    }

    static func End() {
        InternalsVisibleToEmissionScope.Current = null
    }

    static func CompilingAssemblyName(): string {
        scope := InternalsVisibleToEmissionScope.Current
        if scope == null {
            return ""
        }

        return scope.CompilingAssemblyName
    }

    // Does the assembly that DECLARES this member (or this type) make the assembly being emitted a
    // friend? This is the assembly half of `MemberAccessibility.IsAccessible` for every back-end
    // member filter.
    static func GrantsAccessToDeclarer(declaringType: Type?): bool {
        scope := InternalsVisibleToEmissionScope.Current
        if scope == null || declaringType == null {
            return false
        }

        return scope.GrantsAccessToAssemblyOf(declaringType)
    }

    static func GrantsAccessToDeclarerOf(member: MemberInfo?): bool {
        if member == null {
            return false
        }

        return GrantsAccessToDeclarer(member.get_DeclaringType())
    }

    static func GrantsAccess(assembly: Assembly?): bool {
        scope := InternalsVisibleToEmissionScope.Current
        if scope == null {
            return false
        }

        return scope.GrantsAccess(assembly)
    }

    // WHETHER AN ORDINARY READ MAY REACH A MEMBER AT THIS LEVEL, with no derivation relation in play:
    // `public` always, the three assembly-bound levels when the declaring assembly made this emission
    // a friend, and `protected`/`private` never. `MemberAccessibility` is the relation; this is the
    // back end's way of asking it when the only non-public reason it could succeed is friendship.
    static func ReachesLevel(level: int, declaringType: Type?): bool {
        return MemberAccessibility.IsAccessible(level, false, false, false, GrantsAccessToDeclarer(declaringType))
    }

    // Can the assembly being emitted SPELL this metadata type? The back-end counterpart of
    // `InternalsVisibleToGrants.IsNameableType`, which the analyzer asks through its own instance.
    static func CanNameType(candidate: Type?): bool {
        if candidate == null {
            return false
        }

        if candidate.get_IsVisible() {
            return true
        }

        scope := InternalsVisibleToEmissionScope.Current
        if scope == null {
            return false
        }

        return scope.IsNameableType(candidate)
    }
}
