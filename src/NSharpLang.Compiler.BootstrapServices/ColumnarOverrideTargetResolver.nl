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
