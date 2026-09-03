namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection

// WHICH METHOD AN `override` OVERRIDES, FOUND BY WALKING THE BASE CHAIN.
//
// What stood here was a three-name list in the C# emit host — `ToString()`, `Equals(object)` and
// `GetHashCode()`, each looked up on `typeof(object)`. Any other override target returned false, and
// the caller returned false without recording a decline, so `override` on a method declared by a BASE
// CLASS failed with no site, no file and no reason. `class R : MetadataAssemblyResolver` overriding
// `Resolve`, and `class C : StringComparer` overriding `Compare`, both died that way — measured, and
// neither has anything to do with `System.Object`.
//
// The rule is the ordinary one: walk the declared base and its ancestors, take the first accessible
// virtual-or-abstract method whose name and signature match. Sealed (`Final`) slots, statics and
// generic methods are not override targets. `DeclaredOnly` is deliberate: each level is asked for its
// OWN methods so the walk decides the order, and an override target is attributed to the type that
// actually declares it rather than to the most-derived re-declaration.
//
// TYPE IDENTITY IS BY NAME, NEVER BY `==`. The base chain can be read from a different type universe
// than the signature types were resolved in, and two objects for one type compare unequal there — the
// mistake this task exists to remove.
class ColumnarOverrideTargetResolver {
    static func TryFindOverrideTarget(baseType: Type?, name: string, returnType: Type, parameterTypes: Type[], out target: MethodInfo?): bool {
        target = null
        if name == null || name.Length == 0 || returnType == null || parameterTypes == null {
            return false
        }

        current := baseType
        if current == null {
            current = typeof(object)
        }

        while current != null {
            candidates := DeclaredMethodsOrEmpty(current)
            index := 0
            while index < candidates.Length {
                candidate := candidates[index]
                if IsOverridableTarget(candidate, name) && SignatureMatches(candidate, returnType, parameterTypes) {
                    target = candidate
                    return true
                }

                index = index + 1
            }

            current = BaseTypeOrNull(current)
        }

        return false
    }

    // A builder-backed base is not asked: Reflection.Emit metadata is mutable and a partially populated
    // type would answer differently at a different phase. Source-declared overrides are wired by the
    // declaration host from its own registry, not from here.
    static func DeclaredMethodsOrEmpty(owner: Type): MethodInfo[] {
        if owner is TypeBuilder {
            return new MethodInfo[](0)
        }

        try {
            flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly
            methods := owner.GetMethods(flags)
            if methods == null {
                return new MethodInfo[](0)
            }

            return methods
        } catch {
            return new MethodInfo[](0)
        }
    }

    static func BaseTypeOrNull(owner: Type): Type? {
        try {
            return owner.get_BaseType()
        } catch {
            return null
        }
    }

    // Private slots are invisible to a derived type, so a private method of the same name is not a
    // target and must not stop the walk.
    //
    // PUBLIC ONLY, AND THE LIMIT IS DELIBERATE RATHER THAN OVERLOOKED. A protected (`family`) slot is
    // also a legitimate override target, but `MethodBase::get_IsFamily` is not on the modeled member
    // table, and adding the row AND using it in one commit cannot compile: the estate is built by the
    // packaged SDK, whose table would not yet carry it. Neither target this slice needs
    // (`MetadataAssemblyResolver.Resolve`, `StringComparer.Compare`) is protected, so the row and the
    // widening belong to a later, republish-gated commit.
    static func IsOverridableTarget(candidate: MethodInfo, name: string): bool {
        if candidate == null || candidate.get_Name() != name {
            return false
        }

        if candidate.get_IsStatic() || !candidate.get_IsVirtual() || candidate.get_IsFinal() {
            return false
        }

        if candidate.get_IsGenericMethod() || candidate.get_IsGenericMethodDefinition() {
            return false
        }

        return candidate.get_IsPublic()
    }

    static func SignatureMatches(candidate: MethodInfo, returnType: Type, parameterTypes: Type[]): bool {
        parameters := candidate.GetParameters()
        if parameters == null || parameters.Length != parameterTypes.Length {
            return false
        }

        if !SameTypeIdentity(candidate.get_ReturnType(), returnType) {
            return false
        }

        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null || !SameTypeIdentity(parameter.get_ParameterType(), parameterTypes[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // Reference equality first because it is free and correct within one universe; the assembly-qualified
    // name is the answer that survives crossing universes.
    static func SameTypeIdentity(left: Type, right: Type): bool {
        if left == null || right == null {
            return false
        }

        if Object.ReferenceEquals(left, right) {
            return true
        }

        leftName := left.get_AssemblyQualifiedName()
        rightName := right.get_AssemblyQualifiedName()
        return leftName != null && rightName != null && leftName == rightName
    }
}
