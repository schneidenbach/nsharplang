namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection

class ColumnarBaseMethodMatchParameter {
    readonly parameterValue: ParameterInfo
    readonly runtimeTypeValue: Type

    Parameter: ParameterInfo => parameterValue
    RuntimeType: Type => runtimeTypeValue

    constructor(parameter: ParameterInfo, runtimeType: Type) {
        if parameter == null || runtimeType == null {
            throw new InvalidOperationException("A base-method match parameter cannot be null.")
        }
        parameterValue = parameter
        runtimeTypeValue = runtimeType
    }
}

// One candidate signature comparison. Reflection reads retain the old order: parameters and arity,
// return type, then parameters from left to right. The successful row keeps the exact ParameterInfo
// and Type values that were compared; a losing row never acquires structural identity.
class ColumnarBaseMethodSignatureMatch {
    readonly targetValue: MethodInfo
    readonly effectiveReturnRuntimeTypeValue: Type
    readonly parametersValue: IReadOnlyList<object>
    readonly parameterCountValue: int
    readonly matchedValue: bool

    Target: MethodInfo => targetValue
    EffectiveReturnRuntimeType: Type => effectiveReturnRuntimeTypeValue
    ParameterCount: int => parameterCountValue
    Matched: bool => matchedValue

    constructor(target: MethodInfo, returnType: Type, parameterTypes: Type[]) {
        effectiveReturn := typeof(object)
        parameters := new List<object>()
        matched := false
        reflectedParameters := target.GetParameters()
        if reflectedParameters != null && reflectedParameters.Length == parameterTypes.Length {
            effectiveReturn = target.get_ReturnType()
            matched = ColumnarBaseMethodMatch.SameTypeIdentity(effectiveReturn, returnType)
            if matched {
                index := 0
                while index < reflectedParameters.Length {
                    parameter := reflectedParameters[index]
                    if parameter == null {
                        matched = false
                        break
                    }
                    effectiveParameter := parameter.get_ParameterType()
                    if !ColumnarBaseMethodMatch.SameTypeIdentity(effectiveParameter, parameterTypes[index]) {
                        matched = false
                        break
                    }
                    parameters.Add(new ColumnarBaseMethodMatchParameter(parameter, effectiveParameter))
                    index += 1
                }
            }
        }

        targetValue = target
        effectiveReturnRuntimeTypeValue = effectiveReturn
        parametersValue = parameters.AsReadOnly()
        parameterCountValue = parameters.Count
        matchedValue = matched
    }

    func EffectiveParameter(index: int): ColumnarBaseMethodMatchParameter {
        parameter := parametersValue.get_Item(index) as ColumnarBaseMethodMatchParameter
        if parameter == null {
            throw new InvalidOperationException("Base-method match parameter storage is invalid.")
        }
        return parameter
    }
}

// The deriving base lookup. It owns the complete policy once: null-base Object fallback, declared
// methods at each level, the public virtual/non-final/non-generic filter, and assembly-qualified-name
// signature equality. A successful attempt records the actual level that supplied the MethodInfo.
class ColumnarBaseMethodMatch {
    readonly targetValue: MethodInfo?
    readonly foundContextValue: Type?
    readonly signatureValue: ColumnarBaseMethodSignatureMatch?
    readonly matchedValue: bool

    Target: MethodInfo? => targetValue
    FoundContext: Type? => foundContextValue
    Signature: ColumnarBaseMethodSignatureMatch? => signatureValue
    Matched: bool => matchedValue

    constructor(baseType: Type?, name: string, returnType: Type, parameterTypes: Type[]) {
        target: MethodInfo? = null
        foundContext: Type? = null
        signature: ColumnarBaseMethodSignatureMatch? = null
        matched := false

        if name != null && name.Length > 0 && returnType != null && parameterTypes != null {
            current := baseType
            if current == null {
                current = typeof(object)
            }

            while current != null && !matched {
                candidates := DeclaredMethodsOrEmpty(current)
                index := 0
                while index < candidates.Length {
                    candidate := candidates[index]
                    if IsOverridableTarget(candidate, name) {
                        candidateSignature := new ColumnarBaseMethodSignatureMatch(candidate, returnType, parameterTypes)
                        if candidateSignature.Matched {
                            target = candidate
                            foundContext = current
                            signature = candidateSignature
                            matched = true
                            break
                        }
                    }
                    index += 1
                }

                if !matched {
                    current = BaseTypeOrNull(current)
                }
            }
        }

        targetValue = target
        foundContextValue = foundContext
        signatureValue = signature
        matchedValue = matched
    }

    func RequiredTarget(): MethodInfo {
        target := targetValue
        if !matchedValue || target == null {
            throw new InvalidOperationException("A successful base-method match requires its target.")
        }
        return target
    }

    func RequiredFoundContext(): Type {
        context := foundContextValue
        if !matchedValue || context == null {
            throw new InvalidOperationException("A successful base-method match requires its found context.")
        }
        return context
    }

    func RequiredSignature(): ColumnarBaseMethodSignatureMatch {
        signature := signatureValue
        if !matchedValue || signature == null || !signature.Matched {
            throw new InvalidOperationException("A successful base-method match requires its observed signature.")
        }
        return signature
    }

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

// THE SOURCE-BASE OVERRIDE LOOKUP.
//
// `ColumnarBaseMethodMatch` reads the base chain through Reflection, and a base class that is being
// EMITTED IN THIS SAME ASSEMBLY has nothing to read: its `TypeBuilder` is unbaked, so
// `DeclaredMethodsOrEmpty` answers the empty array by design and every `override` of a member the
// program itself declares reported "no overridable base member matches". That is not a missing
// member; it is a missing DOOR. This is the door: the source base's own declaration table, whose
// `MethodBuilder` handles carry the same name, signature and virtual-ness the baked type would.
//
// IT PRODUCES NO `DefineMethodOverride` TARGET, AND THAT IS THE POINT. A class override of a class
// member is matched by the CLR from name and signature once the deriving method is `virtual` and
// does not take a new slot — which is exactly what C# emits, with no MethodImpl row. An explicit
// MethodImpl here would be a second, redundant statement of the same fact, and one that would have
// to name a member of a type that does not exist yet.
class ColumnarSourceBaseMethodMatch {
    readonly targetValue: MethodBuilder?
    readonly ownerValue: ColumnarStructDef?
    readonly matchedValue: bool
    readonly foundNameValue: bool

    Target: MethodBuilder? => targetValue
    Owner: ColumnarStructDef? => ownerValue
    Matched: bool => matchedValue

    // Whether some base level declared a member of this NAME even though none matched the
    // signature. It separates "you misspelled it" from "your signature does not line up", which the
    // analyzer reports for source-visible shapes and the emitter must not contradict.
    FoundName: bool => foundNameValue

    // `baseDefinition` is the overriding type's DIRECT source base — the walk starts AT it, not
    // past it, because the member being overridden is most often declared right there.
    constructor(baseDefinition: ColumnarStructDef?, name: string, returnType: Type, parameterTypes: Type[]) {
        target: MethodBuilder? = null
        owner: ColumnarStructDef? = null
        matched := false
        foundName := false

        if baseDefinition != null && name != null && name.Length > 0 && returnType != null && parameterTypes != null {
            current := baseDefinition
            guard := 0
            while current != null && !matched && guard <= 64 {
                overloads: List<ColumnarInstanceMethodDef>? = null
                if current.MethodOverloads.TryGetValue(name, out overloads) && overloads != null {
                    index := 0
                    while index < overloads.Count {
                        candidate := overloads[index]
                        foundName = true
                        if IsOverridableSourceTarget(candidate) && SameSignature(candidate, returnType, parameterTypes) {
                            target = candidate.Builder
                            owner = current
                            matched = true
                            break
                        }
                        index = index + 1
                    }
                }

                current = current.BaseDef
                guard = guard + 1
            }
        }

        targetValue = target
        ownerValue = owner
        matchedValue = matched
        foundNameValue = foundName
    }

    func RequiredTarget(): MethodBuilder {
        target := targetValue
        if !matchedValue || target == null {
            throw new InvalidOperationException("A successful source-base method match requires its target.")
        }
        return target
    }

    // A source base member is overridable on exactly the terms a runtime one is: an instance member
    // that owns a virtual slot and has not sealed it.
    static func IsOverridableSourceTarget(candidate: ColumnarInstanceMethodDef): bool {
        if candidate == null || candidate.Builder == null {
            return false
        }
        builder := candidate.Builder
        if builder.get_IsStatic() || !builder.get_IsVirtual() || builder.get_IsFinal() {
            return false
        }
        return !builder.get_IsGenericMethod() && !builder.get_IsGenericMethodDefinition()
    }

    static func SameSignature(candidate: ColumnarInstanceMethodDef, returnType: Type, parameterTypes: Type[]): bool {
        if candidate.ParamTypes.Length != parameterTypes.Length || !SameSourceTypeIdentity(candidate.ReturnType, returnType) {
            return false
        }
        index := 0
        while index < parameterTypes.Length {
            if !SameSourceTypeIdentity(candidate.ParamTypes[index], parameterTypes[index]) {
                return false
            }
            index = index + 1
        }
        return true
    }

    // A BUILDER HAS NO STABLE ASSEMBLY-QUALIFIED NAME TO COMPARE. Both sides of this comparison come
    // out of the same emission, so an unbaked `TypeBuilder` or a `GenericTypeParameterBuilder` is
    // the SAME type exactly when it is the same object; only complete external identities fall
    // through to the assembly-qualified rule the runtime chain uses.
    static func SameSourceTypeIdentity(left: Type, right: Type): bool {
        if left == null || right == null {
            return false
        }
        if Object.ReferenceEquals(left, right) {
            return true
        }
        if IsBuilderBound(left) || IsBuilderBound(right) {
            return false
        }
        return ColumnarBaseMethodMatch.SameTypeIdentity(left, right)
    }

    static func IsBuilderBound(candidate: Type): bool {
        if candidate is TypeBuilder || candidate.get_IsGenericParameter() {
            return true
        }
        if candidate.get_HasElementType() {
            element := candidate.GetElementType()
            return element != null && IsBuilderBound(element)
        }
        if !candidate.get_IsGenericType() || candidate.get_IsGenericTypeDefinition() {
            return false
        }
        arguments := candidate.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if IsBuilderBound(arguments[index]) {
                return true
            }
            index = index + 1
        }
        return false
    }
}

class ColumnarBaseMethodBinding {
    readonly descriptorValue: ColumnarExternalMethodDescriptor
    readonly targetValue: MethodInfo

    Descriptor: ColumnarExternalMethodDescriptor => descriptorValue
    Target: MethodInfo => targetValue

    constructor(matchedBase: ColumnarBaseMethodMatch, table: ColumnarStructuralTypeReferenceTable) {
        if matchedBase == null || table == null || !matchedBase.Matched {
            throw new InvalidOperationException("A base-method binding requires a successful lookup and emission table.")
        }
        target := matchedBase.RequiredTarget()
        descriptor := new ColumnarExternalMethodDescriptor(matchedBase, table)
        if !Object.ReferenceEquals(descriptor.Target, target) {
            throw new InvalidOperationException("A base-method descriptor changed its resolved target.")
        }
        descriptorValue = descriptor
        targetValue = target
    }

    func ValidatedTarget(expectedTable: ColumnarStructuralTypeReferenceTable): MethodInfo {
        if expectedTable == null || !descriptorValue.Validate(expectedTable) || !Object.ReferenceEquals(descriptorValue.Target, targetValue) {
            throw new InvalidOperationException("The base-method binding does not belong to this emission context.")
        }
        return targetValue
    }
}

class ColumnarOverrideTargetResolver {
    static func DeclaredMethodsOrEmpty(owner: Type): MethodInfo[] {
        return ColumnarBaseMethodMatch.DeclaredMethodsOrEmpty(owner)
    }

    static func SameTypeIdentity(left: Type, right: Type): bool {
        return ColumnarBaseMethodMatch.SameTypeIdentity(left, right)
    }

    static func TryFindOverrideTarget(baseType: Type?, name: string, returnType: Type, parameterTypes: Type[], out target: MethodInfo?): bool {
        target = null
        matchedBase := new ColumnarBaseMethodMatch(baseType, name, returnType, parameterTypes)
        if !matchedBase.Matched {
            return false
        }
        target = matchedBase.Target
        return target != null
    }
}
