namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler


// HOW A `using` RELEASES ITS RESOURCE, decided once and emitted once.
//
// The question is not "is this type disposable?" — the analyzer already answered that at the front
// door (NL333) and refused the program if the answer was no. The question here is WHICH of the five
// release shapes the CLR requires for this particular type, and that depends on three facts the
// analyzer never had to care about: whether the value is a struct (a boxed `Dispose` would run on a
// COPY and release nothing the caller can observe), whether the release goes through the interface
// or through a member the type merely declares, and whether the static type is precise enough to
// know either answer at compile time.
//
// The five kinds are the `foreach` lowering's vocabulary, extended by one. `foreach` never meets a
// resource whose dispose is a declared member on a reference type — its by-ref-like arm covers the
// only pattern case it has — so kind 5 is new here and nothing else is.
//
//   1  CONSTRAINED CALL on a value type that implements the interface:
//        ldloca r; constrained. T; callvirt I::Dispose
//      The constrained prefix is the whole point — it calls T's own implementation WITHOUT boxing,
//      so a struct that counts its disposals observes exactly one.
//   2  NULL CHECK then INTERFACE CALL on a reference type that implements the interface:
//        ldloc r; brfalse skip; ldloc r; callvirt I::Dispose; skip:
//      The null check is C#'s, and it is why `using x := MightReturnNull()` is not a crash.
//   3  RUNTIME TEST on a reference type whose static type does not implement the interface but whose
//      RUNTIME type still might (an unsealed class):
//        ldloc r; isinst I; stloc d; ldloc d; brfalse skip; ldloc d; callvirt I::Dispose; skip:
//   4  DIRECT CALL on a VALUE type that declares the member without the interface:
//        ldloca r; call T::Dispose
//      A by-ref-like resource can reach no other shape, since it cannot be boxed or held as an
//      interface at all.
//   5  NULL CHECK then DIRECT CALL on a REFERENCE type that declares the member without the
//      interface. Same guard as kind 2, a non-virtual target instead of an interface slot.
//
// An EMITTED type answers from its own definition rather than from reflection: `Type.GetInterfaces()`
// on a `TypeBuilder` that has not been baked can throw or answer empty, and treating a disposable
// struct as non-disposable because the builder would not say so would silently drop its release. The
// definition is the same one the `foreach` lowering consults for exactly the same reason.
class ColumnarUsingDisposalPlan {
    Kind: int
    Method: MethodInfo
    InterfaceType: Type
    ResourceType: Type

    constructor(kind: int, method: MethodInfo, interfaceType: Type, resourceType: Type) {
        Kind = kind
        Method = method
        InterfaceType = interfaceType
        ResourceType = resourceType
    }
}

class ColumnarUsingResourcePlanner {
    static func DisposableName(): string {
        return "System.IDisposable"
    }

    static func AsyncDisposableName(): string {
        return "System.IAsyncDisposable"
    }

    static func InterfaceNameFor(isAsync: bool): string {
        if isAsync {
            return AsyncDisposableName()
        }

        return DisposableName()
    }

    static func MemberNameFor(isAsync: bool): string {
        if isAsync {
            return "DisposeAsync"
        }

        return "Dispose"
    }

    static func RequiredInterfaceType(isAsync: bool): Type {
        resolved := Type.GetType(InterfaceNameFor(isAsync))
        if resolved == null {
            throw new InvalidOperationException("The using lowering requires " + InterfaceNameFor(isAsync) + " in the compiler's own core library.")
        }

        return resolved
    }

    static func RequiredInterfaceMethod(isAsync: bool): MethodInfo {
        interfaceType := RequiredInterfaceType(isAsync)
        method := interfaceType.GetMethod(MemberNameFor(isAsync), Type.EmptyTypes)
        if method == null {
            throw new InvalidOperationException("The using lowering requires " + InterfaceNameFor(isAsync) + "." + MemberNameFor(isAsync) + ".")
        }

        return method
    }

    // THE DECLARED MEMBER, when the type carries one instead of the interface. Parameterless and
    // instance, exactly as the analyzer's structural test requires; the RETURN type is not re-checked
    // here, because the analyzer's front-door rule owns that sentence and a second opinion at emit
    // time could only disagree with it.
    static func FindPatternMethod(clrType: Type, isAsync: bool): MethodInfo? {
        if clrType == null {
            return null
        }

        try {
            candidate := clrType.GetMethod(MemberNameFor(isAsync), BindingFlags.Public | BindingFlags.Instance, null, Type.EmptyTypes, null)
            if candidate == null || candidate.get_IsStatic() {
                return null
            }

            return candidate
        } catch {
            return null
        }
    }

    static func NamesInterface(clrType: Type, interfaceName: string): bool {
        if clrType == null {
            return false
        }

        if clrType.FullName == interfaceName {
            return true
        }

        interfaces := SafeGetInterfaces(clrType)
        index := 0
        while index < interfaces.Length {
            if interfaces[index].FullName == interfaceName {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func SafeGetInterfaces(clrType: Type): Type[] {
        if clrType == null {
            return new Type[](0)
        }

        try {
            resolved := clrType.GetInterfaces()
            if resolved == null {
                return new Type[](0)
            }

            return resolved
        } catch {
            return new Type[](0)
        }
    }

    // `IsValueType` over an unbaked builder can throw; a shape that cannot say is treated as a
    // reference, which is the answer for every shape that reaches this lowering through reflection.
    static func IsValueTypeResource(candidate: Type): bool {
        if candidate == null {
            return false
        }

        try {
            return candidate.get_IsValueType()
        } catch {
            return false
        }
    }

    static func IsByRefLikeResource(candidate: Type): bool {
        if candidate == null {
            return false
        }

        try {
            return candidate.get_IsByRefLike()
        } catch {
            return false
        }
    }

    static func DefinitionNamesInterface(definition: ColumnarStructDef, interfaceName: string): bool {
        index := 0
        while index < definition.ExternalInterfaces.Count {
            if definition.ExternalInterfaces[index].FullName == interfaceName {
                return true
            }

            index = index + 1
        }

        return false
    }

    // THE RELEASE, OR NULL WHEN THE TYPE CAN NAME NONE. A null answer is a DECLINE at the emit site,
    // never a silently skipped `Dispose`: the statement promised a release, so a lowering that cannot
    // spell one must refuse the body rather than emit a `try` whose `finally` does nothing.
    static func Plan(resourceType: Type, isAsync: bool, definition: ColumnarStructDef?): ColumnarUsingDisposalPlan? {
        if resourceType == null {
            return null
        }

        interfaceType := RequiredInterfaceType(isAsync)
        interfaceMethod := RequiredInterfaceMethod(isAsync)
        interfaceName := InterfaceNameFor(isAsync)

        // AN EMITTED TYPE ANSWERS FROM ITS DEFINITION. Its builder may not be able to.
        if definition != null {
            if !DefinitionNamesInterface(definition, interfaceName) {
                return null
            }

            if definition.IsReference {
                return new ColumnarUsingDisposalPlan(2, interfaceMethod, interfaceType, resourceType)
            }

            return new ColumnarUsingDisposalPlan(1, interfaceMethod, interfaceType, resourceType)
        }

        if NamesInterface(resourceType, interfaceName) {
            if IsValueTypeResource(resourceType) {
                return new ColumnarUsingDisposalPlan(1, interfaceMethod, interfaceType, resourceType)
            }

            return new ColumnarUsingDisposalPlan(2, interfaceMethod, interfaceType, resourceType)
        }

        patternMethod := FindPatternMethod(resourceType, isAsync)
        if patternMethod != null {
            if IsValueTypeResource(resourceType) {
                return new ColumnarUsingDisposalPlan(4, patternMethod, interfaceType, resourceType)
            }

            return new ColumnarUsingDisposalPlan(5, patternMethod, interfaceType, resourceType)
        }

        // A VALUE type has nowhere left to look: its run-time type IS its static type, and a by-ref-like
        // one cannot even be tested, because the test would have to box it.
        if IsByRefLikeResource(resourceType) || IsValueTypeResource(resourceType) {
            return null
        }

        // EVERY REMAINING REFERENCE TYPE CAN ANSWER AT RUN TIME, including a sealed one. The `foreach`
        // lowering stops at `sealed` because it is guessing whether an enumerator happens to be
        // disposable; this one is not guessing — the analyzer already PROVED the resource disposable
        // at the front door (NL333), so the only reason the static test failed is that the type is a
        // builder that would not answer, and the run-time test will.
        return new ColumnarUsingDisposalPlan(3, interfaceMethod, interfaceType, resourceType)
    }
}
