namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// External-interface matching keeps the declaration host's exact policy: interface list order,
// reflection GetMethods order, exact name, TypesEquivalent return, arity, then parameters from left
// to right. Matching and completeness do not filter static, generic or default members and do not
// recurse inherited interfaces. Structural capture starts only after a declaration match succeeds.
class ColumnarExternalInterfaceMethodMatchParameter {
    readonly parameterValue: ParameterInfo
    readonly runtimeTypeValue: Type

    Parameter: ParameterInfo => parameterValue
    RuntimeType: Type => runtimeTypeValue

    constructor(parameter: ParameterInfo, runtimeType: Type) {
        if parameter == null || runtimeType == null {
            throw new InvalidOperationException("An external-interface match parameter cannot be null.")
        }
        parameterValue = parameter
        runtimeTypeValue = runtimeType
    }
}

class ColumnarExternalInterfaceMethodMatch {
    readonly targetValue: MethodInfo
    readonly effectiveReturnRuntimeTypeValue: Type
    readonly parametersValue: IReadOnlyList<object>
    readonly parameterCountValue: int
    readonly matchedValue: bool

    Target: MethodInfo => targetValue
    EffectiveReturnRuntimeType: Type => effectiveReturnRuntimeTypeValue
    ParameterCount: int => parameterCountValue
    Matched: bool => matchedValue

    constructor(target: MethodInfo, name: string, returnType: Type, parameterTypes: Type[]): this(target, name, returnType, parameterTypes, EmptyTypeParameters()) {
    }

    // A GENERIC INTERFACE METHOD'S SLOT IS COMPARED THROUGH THE IMPLEMENTATION'S OWN TYPE PARAMETERS.
    //
    // `ILogger.Log<TState>` declares `TState` on the METHOD, so the slot's parameter list is written in
    // a type parameter that belongs to the interface's `MethodDef`; the class that fills it writes its
    // own `TState`, a different `GenericTypeParameterBuilder`. Comparing those two by identity is what
    // made `class CapturedLogger: ILogger` answer `does not implement 'ILogger.Log'` — a capturing test
    // logger was unwritable in N#. The CLR's rule is unification BY POSITION (ECMA-335 II.9.9): the two
    // lists are the same length and the Nth of one stands for the Nth of the other, exactly as the
    // builder-bound arm already substitutes a TYPE's arguments. So the slot's return and parameter
    // types are substituted with the implementation's parameters before they are compared.
    //
    // ARITY IS PART OF THE MATCH IN BOTH DIRECTIONS, and it was not checked at all before. A slot
    // `void Ping<T>()` and a declaration `func Ping()` agreed on every type there was to compare —
    // there are none — so the match said yes and the MethodImpl row it produced named a method the
    // class does not have. That type emits and then fails to LOAD.
    //
    // The stored parameter and return rows stay exactly what REFLECTION reports, unsubstituted: the
    // descriptor built from this match validates the interface's own open/effective signature pair, and
    // a row rewritten in the implementer's type parameters is not that pair.
    constructor(target: MethodInfo, name: string, returnType: Type, parameterTypes: Type[], implementationTypeParameters: Type[]) {
        effectiveReturn := typeof(object)
        parameters := new List<object>()
        matched := target.get_Name() == name && OpenMethodTypeParameterCount(target) == implementationTypeParameters.Length
        if matched {
            effectiveReturn = target.get_ReturnType()
            comparedReturn := SubstituteSlotType(effectiveReturn, implementationTypeParameters)
            matched = comparedReturn != null && ColumnarTypeEquivalenceFacts.TypesEquivalent(comparedReturn, returnType)
            if matched {
                reflectedParameters := target.GetParameters()
                matched = reflectedParameters.Length == parameterTypes.Length
                if matched {
                    index := 0
                    while index < reflectedParameters.Length {
                        reflectedParameter := reflectedParameters[index]
                        effectiveParameter := reflectedParameter.get_ParameterType()
                        comparedParameter := SubstituteSlotType(effectiveParameter, implementationTypeParameters)
                        if comparedParameter == null || !ColumnarTypeEquivalenceFacts.TypesEquivalent(comparedParameter, parameterTypes[index]) {
                            matched = false
                            break
                        }
                        parameters.Add(new ColumnarExternalInterfaceMethodMatchParameter(reflectedParameter, effectiveParameter))
                        index += 1
                    }
                }
            }
        }

        targetValue = target
        effectiveReturnRuntimeTypeValue = effectiveReturn
        parametersValue = parameters.AsReadOnly()
        parameterCountValue = parameters.Count
        matchedValue = matched
    }

    // The slot's own type as the implementer would have had to write it. With no method type
    // parameters in play the substitution is the identity, so the non-generic path is byte-identical to
    // what it was before this arm existed.
    static func SubstituteSlotType(slotType: Type, implementationTypeParameters: Type[]): Type? {
        if implementationTypeParameters.Length == 0 {
            return slotType
        }
        return ColumnarRuntimeGenericMethodResolver.SubstituteMethodTypeArguments(slotType, implementationTypeParameters)
    }

    // HOW MANY TYPE PARAMETERS THE SLOT'S SIGNATURE STILL LEAVES OPEN, which is how many the
    // implementation has to declare. A generic method DEFINITION leaves its own list open; a
    // CONSTRUCTED handle leaves none, because every one of them has already been substituted away.
    static func OpenMethodTypeParameterCount(target: MethodInfo): int {
        if !target.get_IsGenericMethodDefinition() {
            return 0
        }
        return target.GetGenericArguments().Length
    }

    static func EmptyTypeParameters(): Type[] {
        return new Type[](0)
    }

    func EffectiveParameter(index: int): ColumnarExternalInterfaceMethodMatchParameter {
        parameter := parametersValue.get_Item(index) as ColumnarExternalInterfaceMethodMatchParameter
        if parameter == null {
            throw new InvalidOperationException("External-interface match parameter storage is invalid.")
        }
        return parameter
    }
}

class ColumnarExternalMethodCustomModifierDescriptor {
    readonly typeValue: ColumnarSelectedTypeReference
    readonly runtimeTypeValue: Type

    Type: ColumnarSelectedTypeReference => typeValue
    RuntimeType: Type => runtimeTypeValue

    constructor(selectedType: ColumnarSelectedTypeReference, runtimeType: Type) {
        if selectedType == null || runtimeType == null {
            throw new InvalidOperationException("An external method custom modifier requires structural type identity.")
        }
        typeValue = selectedType
        runtimeTypeValue = runtimeType
    }

    func Validate(expectedTable: ColumnarStructuralTypeReferenceTable): bool {
        return expectedTable != null && expectedTable.ValidatePair(typeValue, runtimeTypeValue)
    }
}

// One return or parameter signature node retains its exact runtime Type and the required/optional
// custom-modifier arrays exposed by reflection. Each array keeps its original order; reflection does
// not expose interleaving between the two arrays, which remains a metadata-writer fidelity boundary.
class ColumnarExternalMethodSignatureTypeDescriptor {
    readonly typeValue: ColumnarSelectedTypeReference
    readonly runtimeTypeValue: Type
    readonly requiredModifiersValue: IReadOnlyList<object>
    readonly requiredModifierCountValue: int
    readonly optionalModifiersValue: IReadOnlyList<object>
    readonly optionalModifierCountValue: int

    Type: ColumnarSelectedTypeReference => typeValue
    RuntimeType: Type => runtimeTypeValue
    RequiredModifierCount: int => requiredModifierCountValue
    OptionalModifierCount: int => optionalModifierCountValue

    constructor(
        table: ColumnarStructuralTypeReferenceTable,
        runtimeType: Type,
        requiredModifiers: Type[],
        optionalModifiers: Type[],
        openExternalSignature: bool
    ) {
        if table == null || runtimeType == null || requiredModifiers == null || optionalModifiers == null {
            throw new InvalidOperationException("An external method signature node requires complete type facts.")
        }
        selectedType := openExternalSignature ? table.SelectExternalSignatureType(runtimeType) : table.SelectRuntimeType(runtimeType)
        requiredModifierRows := new List<object>()
        index := 0
        while index < requiredModifiers.Length {
            modifierType := requiredModifiers[index]
            selectedModifier := openExternalSignature ? table.SelectExternalSignatureType(modifierType) : table.SelectRuntimeType(modifierType)
            requiredModifierRows.Add(new ColumnarExternalMethodCustomModifierDescriptor(selectedModifier, modifierType))
            index += 1
        }
        optionalModifierRows := new List<object>()
        index = 0
        while index < optionalModifiers.Length {
            modifierType := optionalModifiers[index]
            selectedModifier := openExternalSignature ? table.SelectExternalSignatureType(modifierType) : table.SelectRuntimeType(modifierType)
            optionalModifierRows.Add(new ColumnarExternalMethodCustomModifierDescriptor(selectedModifier, modifierType))
            index += 1
        }

        typeValue = selectedType
        runtimeTypeValue = runtimeType
        requiredModifiersValue = requiredModifierRows.AsReadOnly()
        requiredModifierCountValue = requiredModifiers.Length
        optionalModifiersValue = optionalModifierRows.AsReadOnly()
        optionalModifierCountValue = optionalModifiers.Length
    }

    func RequiredModifier(index: int): ColumnarExternalMethodCustomModifierDescriptor {
        modifier := requiredModifiersValue.get_Item(index) as ColumnarExternalMethodCustomModifierDescriptor
        if modifier == null {
            throw new InvalidOperationException("External required-modifier storage is invalid.")
        }
        return modifier
    }

    func OptionalModifier(index: int): ColumnarExternalMethodCustomModifierDescriptor {
        modifier := optionalModifiersValue.get_Item(index) as ColumnarExternalMethodCustomModifierDescriptor
        if modifier == null {
            throw new InvalidOperationException("External optional-modifier storage is invalid.")
        }
        return modifier
    }

    func Validate(expectedTable: ColumnarStructuralTypeReferenceTable): bool {
        if expectedTable == null || !expectedTable.ValidatePair(typeValue, runtimeTypeValue) {
            return false
        }
        index := 0
        while index < requiredModifierCountValue {
            if !RequiredModifier(index).Validate(expectedTable) {
                return false
            }
            index += 1
        }
        index = 0
        while index < optionalModifierCountValue {
            if !OptionalModifier(index).Validate(expectedTable) {
                return false
            }
            index += 1
        }
        return true
    }
}

class ColumnarExternalMethodParameterDescriptor {
    readonly openValue: ColumnarExternalMethodSignatureTypeDescriptor
    readonly effectiveValue: ColumnarExternalMethodSignatureTypeDescriptor

    Open: ColumnarExternalMethodSignatureTypeDescriptor => openValue
    Effective: ColumnarExternalMethodSignatureTypeDescriptor => effectiveValue

    constructor(openSignature: ColumnarExternalMethodSignatureTypeDescriptor, effectiveSignature: ColumnarExternalMethodSignatureTypeDescriptor) {
        if openSignature == null || effectiveSignature == null {
            throw new InvalidOperationException("An external method parameter requires open and effective signature facts.")
        }
        openValue = openSignature
        effectiveValue = effectiveSignature
    }
}

class ColumnarExternalMethodGenericParameterDescriptor {
    readonly openTypeValue: ColumnarSelectedTypeReference
    readonly openRuntimeTypeValue: Type
    readonly effectiveTypeValue: ColumnarSelectedTypeReference
    readonly effectiveRuntimeTypeValue: Type

    OpenType: ColumnarSelectedTypeReference => openTypeValue
    OpenRuntimeType: Type => openRuntimeTypeValue
    EffectiveType: ColumnarSelectedTypeReference => effectiveTypeValue
    EffectiveRuntimeType: Type => effectiveRuntimeTypeValue

    constructor(
        openType: ColumnarSelectedTypeReference,
        openRuntimeType: Type,
        effectiveType: ColumnarSelectedTypeReference,
        effectiveRuntimeType: Type
    ) {
        if openType == null || openRuntimeType == null || effectiveType == null || effectiveRuntimeType == null {
            throw new InvalidOperationException("An external method generic parameter requires open and effective identity.")
        }
        openTypeValue = openType
        openRuntimeTypeValue = openRuntimeType
        effectiveTypeValue = effectiveType
        effectiveRuntimeTypeValue = effectiveRuntimeType
    }
}

// Neutral external-method identity shared by this interface slice and later base/iterator slices.
// It is derived from the reflected winner, not from caller-supplied open/effective signature pairs.
class ColumnarExternalMethodDescriptor {
    readonly tableValue: ColumnarStructuralTypeReferenceTable
    readonly targetValue: MethodInfo
    readonly lookupContextValue: ColumnarSelectedTypeReference
    readonly lookupContextRuntimeTypeValue: Type
    readonly reflectedContextValue: ColumnarSelectedTypeReference
    readonly reflectedContextRuntimeTypeValue: Type
    readonly declaringContextValue: ColumnarSelectedTypeReference
    readonly declaringContextRuntimeTypeValue: Type
    readonly openDeclaringTypeValue: ColumnarSelectedTypeReference
    readonly openDeclaringRuntimeTypeValue: Type
    readonly openMethodValue: MethodInfo
    readonly moduleVersionIdValue: string
    readonly methodMetadataTokenValue: int
    readonly methodNameValue: string
    readonly methodGenericArityValue: int
    readonly methodCallingConventionValue: int
    readonly methodIsStaticValue: bool
    readonly openReturnValue: ColumnarExternalMethodSignatureTypeDescriptor
    readonly effectiveReturnValue: ColumnarExternalMethodSignatureTypeDescriptor
    readonly parametersValue: IReadOnlyList<object>
    readonly parameterCountValue: int
    readonly genericParametersValue: IReadOnlyList<object>
    readonly genericParameterCountValue: int

    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable => tableValue
    Target: MethodInfo => targetValue
    LookupContext: ColumnarSelectedTypeReference => lookupContextValue
    LookupContextRuntimeType: Type => lookupContextRuntimeTypeValue
    ReflectedContext: ColumnarSelectedTypeReference => reflectedContextValue
    ReflectedContextRuntimeType: Type => reflectedContextRuntimeTypeValue
    DeclaringContext: ColumnarSelectedTypeReference => declaringContextValue
    DeclaringContextRuntimeType: Type => declaringContextRuntimeTypeValue
    OpenDeclaringType: ColumnarSelectedTypeReference => openDeclaringTypeValue
    OpenDeclaringRuntimeType: Type => openDeclaringRuntimeTypeValue
    OpenMethod: MethodInfo => openMethodValue
    ModuleVersionId: string => moduleVersionIdValue
    MethodMetadataToken: int => methodMetadataTokenValue
    MethodName: string => methodNameValue
    MethodGenericArity: int => methodGenericArityValue
    MethodCallingConvention: int => methodCallingConventionValue
    MethodIsStatic: bool => methodIsStaticValue
    OpenReturn: ColumnarExternalMethodSignatureTypeDescriptor => openReturnValue
    EffectiveReturn: ColumnarExternalMethodSignatureTypeDescriptor => effectiveReturnValue
    ParameterCount: int => parameterCountValue
    GenericParameterCount: int => genericParameterCountValue

    constructor(
        lookupContext: Type,
        matchedSignature: ColumnarExternalInterfaceMethodMatch,
        table: ColumnarStructuralTypeReferenceTable
    ) {
        if lookupContext == null || matchedSignature == null || table == null || !matchedSignature.Matched {
            throw new InvalidOperationException("An external method descriptor requires its successful reflected lookup.")
        }
        target := matchedSignature.Target
        if target.get_IsGenericMethod() && !target.get_IsGenericMethodDefinition() {
            throw new InvalidOperationException("A constructed generic MethodInfo is not produced by external interface GetMethods lookup.")
        }
        reflectedContext := RequiredType(target.get_ReflectedType(), "reflected lookup context")
        if !ColumnarTypeEquivalenceFacts.TypesEquivalent(reflectedContext, lookupContext) {
            throw new InvalidOperationException("An external method target does not belong to its enumerated lookup context.")
        }
        declaringContext := RequiredType(target.get_DeclaringType(), "declaring context")
        openDeclaringType := declaringContext
        if declaringContext.get_IsGenericType() && !declaringContext.get_IsGenericTypeDefinition() {
            openDeclaringType = declaringContext.GetGenericTypeDefinition()
        }
        openMethod := RecoverOpenMethod(target, openDeclaringType)

        targetGenericArguments := target.GetGenericArguments()
        openGenericArguments := openMethod.GetGenericArguments()
        if targetGenericArguments.Length != openGenericArguments.Length || target.get_IsGenericMethod() != openMethod.get_IsGenericMethod() || target.get_IsGenericMethodDefinition() != openMethod.get_IsGenericMethodDefinition() || target.get_Name() != openMethod.get_Name() || target.get_IsStatic() != openMethod.get_IsStatic() || Convert.ToInt32(target.get_CallingConvention()) != Convert.ToInt32(openMethod.get_CallingConvention()) {
            throw new InvalidOperationException("An external method's open and effective metadata identity disagree.")
        }

        openParameters := openMethod.GetParameters()
        if openParameters.Length != matchedSignature.ParameterCount {
            throw new InvalidOperationException("An external method's open and effective parameter counts disagree.")
        }
        openReturnParameter := openMethod.get_ReturnParameter()
        effectiveReturnParameter := target.get_ReturnParameter()
        openReturn := new ColumnarExternalMethodSignatureTypeDescriptor(
            table,
            openMethod.get_ReturnType(),
            openReturnParameter.GetRequiredCustomModifiers(),
            openReturnParameter.GetOptionalCustomModifiers(),
            true
        )
        effectiveReturn := new ColumnarExternalMethodSignatureTypeDescriptor(
            table,
            matchedSignature.EffectiveReturnRuntimeType,
            effectiveReturnParameter.GetRequiredCustomModifiers(),
            effectiveReturnParameter.GetOptionalCustomModifiers(),
            false
        )

        parameters := new List<object>()
        index := 0
        while index < openParameters.Length {
            openParameter := openParameters[index]
            effectiveMatchParameter := matchedSignature.EffectiveParameter(index)
            effectiveParameter := effectiveMatchParameter.Parameter
            parameters.Add(new ColumnarExternalMethodParameterDescriptor(
                new ColumnarExternalMethodSignatureTypeDescriptor(
                    table,
                    openParameter.get_ParameterType(),
                    openParameter.GetRequiredCustomModifiers(),
                    openParameter.GetOptionalCustomModifiers(),
                    true
                ),
                new ColumnarExternalMethodSignatureTypeDescriptor(
                    table,
                    effectiveMatchParameter.RuntimeType,
                    effectiveParameter.GetRequiredCustomModifiers(),
                    effectiveParameter.GetOptionalCustomModifiers(),
                    false
                )
            ))
            index += 1
        }

        genericParameters := new List<object>()
        index = 0
        while index < openGenericArguments.Length {
            openGenericArgument := openGenericArguments[index]
            effectiveGenericArgument := targetGenericArguments[index]
            genericParameters.Add(new ColumnarExternalMethodGenericParameterDescriptor(
                table.SelectExternalSignatureType(openGenericArgument),
                openGenericArgument,
                table.SelectRuntimeType(effectiveGenericArgument),
                effectiveGenericArgument
            ))
            index += 1
        }

        tableValue = table
        targetValue = target
        lookupContextValue = table.SelectRuntimeType(lookupContext)
        lookupContextRuntimeTypeValue = lookupContext
        reflectedContextValue = table.SelectRuntimeType(reflectedContext)
        reflectedContextRuntimeTypeValue = reflectedContext
        declaringContextValue = table.SelectRuntimeType(declaringContext)
        declaringContextRuntimeTypeValue = declaringContext
        openDeclaringTypeValue = table.SelectRuntimeType(openDeclaringType)
        openDeclaringRuntimeTypeValue = openDeclaringType
        openMethodValue = openMethod
        moduleVersionIdValue = ReadModuleVersionId(openMethod)
        methodMetadataTokenValue = openMethod.get_MetadataToken()
        methodNameValue = openMethod.get_Name()
        methodGenericArityValue = openGenericArguments.Length
        methodCallingConventionValue = Convert.ToInt32(openMethod.get_CallingConvention())
        methodIsStaticValue = openMethod.get_IsStatic()
        openReturnValue = openReturn
        effectiveReturnValue = effectiveReturn
        parametersValue = parameters.AsReadOnly()
        parameterCountValue = parameters.Count
        genericParametersValue = genericParameters.AsReadOnly()
        genericParameterCountValue = genericParameters.Count
    }

    // Base-method capture starts from the deriving base walk's successful snapshot. It does not
    // manufacture an interface match or reread the effective return/parameter types that decided
    // the winner. Open MethodDef and modifier reflection begins only after the full base match.
    constructor(
        matchedBase: ColumnarBaseMethodMatch,
        table: ColumnarStructuralTypeReferenceTable
    ) {
        if matchedBase == null || table == null || !matchedBase.Matched {
            throw new InvalidOperationException("A base method descriptor requires its successful reflected lookup.")
        }
        target := matchedBase.RequiredTarget()
        lookupContext := matchedBase.RequiredFoundContext()
        matchedSignature := matchedBase.RequiredSignature()
        if !Object.ReferenceEquals(matchedSignature.Target, target) {
            throw new InvalidOperationException("A base method's target and observed signature disagree.")
        }
        reflectedContext := RequiredType(target.get_ReflectedType(), "reflected lookup context")
        if !ColumnarBaseMethodMatch.SameTypeIdentity(reflectedContext, lookupContext) {
            throw new InvalidOperationException("A base method target does not belong to its winning lookup context.")
        }
        declaringContext := RequiredType(target.get_DeclaringType(), "declaring context")
        openDeclaringType := declaringContext
        if declaringContext.get_IsGenericType() && !declaringContext.get_IsGenericTypeDefinition() {
            openDeclaringType = declaringContext.GetGenericTypeDefinition()
        }
        openMethod := RecoverOpenMethod(target, openDeclaringType)

        targetGenericArguments := target.GetGenericArguments()
        openGenericArguments := openMethod.GetGenericArguments()
        if targetGenericArguments.Length != 0 || openGenericArguments.Length != 0 || target.get_IsGenericMethod() || target.get_IsGenericMethodDefinition() || openMethod.get_IsGenericMethod() || openMethod.get_IsGenericMethodDefinition() || target.get_Name() != openMethod.get_Name() || target.get_IsStatic() != openMethod.get_IsStatic() || Convert.ToInt32(target.get_CallingConvention()) != Convert.ToInt32(openMethod.get_CallingConvention()) {
            throw new InvalidOperationException("A base method's open and effective metadata identity disagree.")
        }

        sameOpenTarget := Object.ReferenceEquals(openMethod, target)
        openParameters := new ParameterInfo[](matchedSignature.ParameterCount)
        if sameOpenTarget {
            snapshotIndex := 0
            while snapshotIndex < openParameters.Length {
                openParameters[snapshotIndex] = matchedSignature.EffectiveParameter(snapshotIndex).Parameter
                snapshotIndex += 1
            }
        } else {
            openParameters = openMethod.GetParameters()
        }
        if openParameters.Length != matchedSignature.ParameterCount {
            throw new InvalidOperationException("A base method's open and effective parameter counts disagree.")
        }
        openReturnParameter := openMethod.get_ReturnParameter()
        effectiveReturnParameter := target.get_ReturnParameter()
        openReturnRuntimeType := matchedSignature.EffectiveReturnRuntimeType
        if !sameOpenTarget {
            openReturnRuntimeType = openMethod.get_ReturnType()
        }
        openReturn := new ColumnarExternalMethodSignatureTypeDescriptor(
            table,
            openReturnRuntimeType,
            openReturnParameter.GetRequiredCustomModifiers(),
            openReturnParameter.GetOptionalCustomModifiers(),
            true
        )
        effectiveReturn := new ColumnarExternalMethodSignatureTypeDescriptor(
            table,
            matchedSignature.EffectiveReturnRuntimeType,
            effectiveReturnParameter.GetRequiredCustomModifiers(),
            effectiveReturnParameter.GetOptionalCustomModifiers(),
            false
        )

        parameters := new List<object>()
        index := 0
        while index < openParameters.Length {
            openParameter := openParameters[index]
            effectiveMatchParameter := matchedSignature.EffectiveParameter(index)
            effectiveParameter := effectiveMatchParameter.Parameter
            openParameterRuntimeType := effectiveMatchParameter.RuntimeType
            if !sameOpenTarget {
                openParameterRuntimeType = openParameter.get_ParameterType()
            }
            parameters.Add(new ColumnarExternalMethodParameterDescriptor(
                new ColumnarExternalMethodSignatureTypeDescriptor(
                    table,
                    openParameterRuntimeType,
                    openParameter.GetRequiredCustomModifiers(),
                    openParameter.GetOptionalCustomModifiers(),
                    true
                ),
                new ColumnarExternalMethodSignatureTypeDescriptor(
                    table,
                    effectiveMatchParameter.RuntimeType,
                    effectiveParameter.GetRequiredCustomModifiers(),
                    effectiveParameter.GetOptionalCustomModifiers(),
                    false
                )
            ))
            index += 1
        }

        tableValue = table
        targetValue = target
        lookupContextValue = table.SelectRuntimeType(lookupContext)
        lookupContextRuntimeTypeValue = lookupContext
        reflectedContextValue = table.SelectRuntimeType(reflectedContext)
        reflectedContextRuntimeTypeValue = reflectedContext
        declaringContextValue = table.SelectRuntimeType(declaringContext)
        declaringContextRuntimeTypeValue = declaringContext
        openDeclaringTypeValue = table.SelectRuntimeType(openDeclaringType)
        openDeclaringRuntimeTypeValue = openDeclaringType
        openMethodValue = openMethod
        moduleVersionIdValue = ReadModuleVersionId(openMethod)
        methodMetadataTokenValue = openMethod.get_MetadataToken()
        methodNameValue = openMethod.get_Name()
        methodGenericArityValue = 0
        methodCallingConventionValue = Convert.ToInt32(openMethod.get_CallingConvention())
        methodIsStaticValue = openMethod.get_IsStatic()
        openReturnValue = openReturn
        effectiveReturnValue = effectiveReturn
        parametersValue = parameters.AsReadOnly()
        parameterCountValue = parameters.Count
        genericParametersValue = new List<object>().AsReadOnly()
        genericParameterCountValue = 0
    }

    func Parameter(index: int): ColumnarExternalMethodParameterDescriptor {
        parameter := parametersValue.get_Item(index) as ColumnarExternalMethodParameterDescriptor
        if parameter == null {
            throw new InvalidOperationException("External method parameter storage is invalid.")
        }
        return parameter
    }

    func GenericParameter(index: int): ColumnarExternalMethodGenericParameterDescriptor {
        parameter := genericParametersValue.get_Item(index) as ColumnarExternalMethodGenericParameterDescriptor
        if parameter == null {
            throw new InvalidOperationException("External method generic-parameter storage is invalid.")
        }
        return parameter
    }

    func Validate(expectedTable: ColumnarStructuralTypeReferenceTable): bool {
        if expectedTable == null || !Object.ReferenceEquals(tableValue, expectedTable) {
            return false
        }
        lookupKey := lookupContextValue.Key
        reflectedKey := reflectedContextValue.Key
        if lookupKey == null || reflectedKey == null {
            return false
        }
        if !expectedTable.ValidatePair(lookupContextValue, lookupContextRuntimeTypeValue) || !expectedTable.ValidatePair(reflectedContextValue, reflectedContextRuntimeTypeValue) || !expectedTable.ValidatePair(declaringContextValue, declaringContextRuntimeTypeValue) || !expectedTable.ValidatePair(openDeclaringTypeValue, openDeclaringRuntimeTypeValue) || !ColumnarStructuralTypeKeyFacts.KeysEqual(lookupKey, reflectedKey) {
            return false
        }
        if !ColumnarExternalMethodSignatureRelation.DeclaringContextMatchesOpenDefinition(openDeclaringTypeValue, declaringContextValue) || !openReturnValue.Validate(expectedTable) || !effectiveReturnValue.Validate(expectedTable) || !ColumnarExternalMethodSignatureRelation.SignatureTypesRelate(openReturnValue, effectiveReturnValue, openDeclaringTypeValue, declaringContextValue) {
            return false
        }
        index := 0
        while index < parameterCountValue {
            parameter := Parameter(index)
            if !parameter.Open.Validate(expectedTable) || !parameter.Effective.Validate(expectedTable) || !ColumnarExternalMethodSignatureRelation.SignatureTypesRelate(parameter.Open, parameter.Effective, openDeclaringTypeValue, declaringContextValue) {
                return false
            }
            index += 1
        }
        index = 0
        while index < genericParameterCountValue {
            parameter := GenericParameter(index)
            if !expectedTable.ValidatePair(parameter.OpenType, parameter.OpenRuntimeType) || !expectedTable.ValidatePair(parameter.EffectiveType, parameter.EffectiveRuntimeType) || !ColumnarExternalMethodSignatureRelation.KeysRelate(parameter.OpenType.Key, parameter.EffectiveType.Key, openDeclaringTypeValue.Key, declaringContextValue.Key) {
                return false
            }
            index += 1
        }
        return true
    }

    // THE OPEN `MethodDef` BEHIND A CLOSED HANDLE, matched by metadata token and module identity.
    //
    // The enumeration asks for the NON-PUBLIC members too, because the member being recovered is not
    // always a public one: a `protected virtual` extension point like `Collection<T>.SetItem` is
    // exactly what a derived type overrides, and a public-only sweep could not find its own target
    // again — "The external method's open MethodDef could not be recovered from its declaring type"
    // was the whole answer a program overriding one received.
    static func RecoverOpenMethod(target: MethodInfo, openDeclaringType: Type): MethodInfo {
        recovered: MethodInfo? = null
        if !TryRecoverOpenMethod(target, openDeclaringType, out recovered) || recovered == null {
            throw new InvalidOperationException("The external method's open MethodDef could not be recovered from its declaring type.")
        }
        return recovered
    }

    // THE SAME RECOVERY FOR A CALLER THAT HAS A FALLBACK. A rebinder asking whether a handle it is
    // about to hand to `TypeBuilder.GetMethod` has a definition-declared twin is asking a QUESTION,
    // not making a demand: it keeps the handle it already has when the answer is no. The throwing
    // form above is this one plus the demand, so the match rule has a single spelling.
    static func TryRecoverOpenMethod(target: MethodInfo, openDeclaringType: Type, out recovered: MethodInfo?): bool {
        recovered = null
        targetToken := target.get_MetadataToken()
        targetModuleVersionId := ReadModuleVersionId(target)
        for candidate in openDeclaringType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static) {
            if candidate.get_MetadataToken() == targetToken && ReadModuleVersionId(candidate) == targetModuleVersionId {
                recovered = candidate
                return true
            }
        }
        return false
    }

    static func ReadModuleVersionId(method: MethodInfo): string {
        module := method.get_Module()
        return module.get_ModuleVersionId().ToString()
    }

    static func RequiredType(value: Type?, role: string): Type {
        valueObject: object? = value
        if valueObject == null {
            throw new InvalidOperationException("An external method has no " + role + ".")
        }
        return (Type)valueObject
    }
}

class ColumnarExternalInterfaceMethodBinding {
    readonly descriptorValue: ColumnarExternalMethodDescriptor
    readonly targetValue: MethodInfo

    Descriptor: ColumnarExternalMethodDescriptor => descriptorValue
    Target: MethodInfo => targetValue

    constructor(
        lookupContext: Type,
        matchedSignature: ColumnarExternalInterfaceMethodMatch,
        table: ColumnarStructuralTypeReferenceTable
    ) {
        if matchedSignature == null || !matchedSignature.Matched {
            throw new InvalidOperationException("An external-interface binding requires a successful match.")
        }
        targetValue = matchedSignature.Target
        descriptorValue = new ColumnarExternalMethodDescriptor(lookupContext, matchedSignature, table)
    }

    func ValidatedTarget(expectedTable: ColumnarStructuralTypeReferenceTable): MethodInfo {
        if expectedTable == null || !descriptorValue.Validate(expectedTable) || !Object.ReferenceEquals(descriptorValue.Target, targetValue) {
            throw new InvalidOperationException("An external-interface member binding does not belong to the consuming emission.")
        }
        return targetValue
    }
}

class ColumnarExternalInterfaceMethodResolver {
    static func AddMatchingTargets(
        declaration: ColumnarMethodOverrideDeclaration,
        externalInterfaces: List<Type>,
        memberName: string,
        returnType: Type,
        parameterTypes: Type[],
        table: ColumnarStructuralTypeReferenceTable
    ) {
        AddMatchingTargets(declaration, externalInterfaces, memberName, returnType, parameterTypes, table, ColumnarExternalInterfaceMethodMatch.EmptyTypeParameters())
    }

    static func AddMatchingTargets(
        declaration: ColumnarMethodOverrideDeclaration,
        externalInterfaces: List<Type>,
        memberName: string,
        returnType: Type,
        parameterTypes: Type[],
        table: ColumnarStructuralTypeReferenceTable,
        implementationTypeParameters: Type[]
    ) {
        for declaredInterface in externalInterfaces {
            for externalInterface in InterfaceRequirementClosure(declaredInterface) {
                if ColumnarGenericTypeReceiverFacts.IsBuilderBoundConstruction(externalInterface) {
                    if implementationTypeParameters.Length == 0 {
                        AddBuilderBoundMatchingTargets(declaration, externalInterface, memberName, returnType, parameterTypes)
                    }
                    continue
                }
                for externalMethod in externalInterface.GetMethods() {
                    matchedSignature := new ColumnarExternalInterfaceMethodMatch(
                        externalMethod,
                        memberName,
                        returnType,
                        parameterTypes,
                        implementationTypeParameters
                    )
                    if matchedSignature.Matched {
                        declaration.AddExternalTarget(new ColumnarExternalInterfaceMethodBinding(
                            externalInterface,
                            matchedSignature,
                            table
                        ))
                    }
                }
            }
        }
    }

    // A BUILDER-BOUND CONSTRUCTED INTERFACE — `IEquatable<Outcome<TOk, TErr>>` on
    // `Outcome<TOk, TErr>`, `IComparable<Node<T>>` on `Node<T>`. Its instantiation answers no
    // reflection member query, so the members come from the runtime DEFINITION, the effective
    // signature is the definition's own signature substituted with the instantiation's arguments,
    // and the MethodImpl slot is that declaration rebound with `TypeBuilder.GetMethod`. The
    // structural descriptor is not built for these: it validates a reflected lookup context, and a
    // `TypeBuilderInstantiation` has none to report.
    static func AddBuilderBoundMatchingTargets(
        declaration: ColumnarMethodOverrideDeclaration,
        externalInterface: Type,
        memberName: string,
        returnType: Type,
        parameterTypes: Type[]
    ) {
        definition := externalInterface.GetGenericTypeDefinition()
        closedArguments := externalInterface.GetGenericArguments()
        for openMethod in definition.GetMethods() {
            if !BuilderBoundSignatureMatches(openMethod, closedArguments, memberName, returnType, parameterTypes) {
                continue
            }
            rebound := TypeBuilder.GetMethod(externalInterface, openMethod)
            if rebound == null {
                throw new InvalidOperationException("TypeBuilder.GetMethod returned no exact builder-bound interface method.")
            }
            reboundObject: object? = rebound
            declaration.AddExternalTarget((MethodInfo)reboundObject)
        }
    }

    static func BuilderBoundSignatureMatches(
        openMethod: MethodInfo,
        closedArguments: Type[],
        memberName: string,
        returnType: Type,
        parameterTypes: Type[]
    ): bool {
        // A builder-bound construction's slot is reached through `TypeBuilder.GetMethod`, which takes
        // no method type arguments, so a GENERIC slot on one is not a shape this arm can bind. It is
        // refused by arity rather than by failing to compare its own type parameters against the
        // implementer's — a comparison that answered `matched` for the empty signature `void Ping<T>()`.
        if openMethod.get_Name() != memberName || openMethod.GetGenericArguments().Length != 0 {
            return false
        }
        effectiveReturn := ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(openMethod.get_ReturnType(), closedArguments)
        if !ColumnarTypeEquivalenceFacts.TypesEquivalent(effectiveReturn, returnType) {
            return false
        }
        openParameters := openMethod.GetParameters()
        if openParameters.Length != parameterTypes.Length {
            return false
        }
        index := 0
        while index < openParameters.Length {
            effectiveParameter := ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(openParameters[index].get_ParameterType(), closedArguments)
            if !ColumnarTypeEquivalenceFacts.TypesEquivalent(effectiveParameter, parameterTypes[index]) {
                return false
            }
            index += 1
        }
        return true
    }

    // Whether `add_X` / `remove_X` on an external interface is answered by an event `X` the implementer
    // declares over the same delegate. The accessor's own single parameter IS the handler type, so the
    // two are compared without reading the `EventInfo` twice.
    static func EventAccessorSatisfied(implementer: ColumnarStructDef, interfaceType: Type, externalMethod: MethodInfo, externalName: string): bool {
        if !externalMethod.get_IsSpecialName() {
            return false
        }

        eventName := ""
        if externalName.StartsWith("add_", StringComparison.Ordinal) {
            eventName = externalName.Substring(4)
        } else if externalName.StartsWith("remove_", StringComparison.Ordinal) {
            eventName = externalName.Substring(7)
        } else {
            return false
        }

        declaredEvent: ColumnarEventDef = null
        if !implementer.Events.TryGetValue(eventName, out declaredEvent) || declaredEvent.IsStatic {
            return false
        }

        interfaceEvent := interfaceType.GetEvent(eventName)
        if interfaceEvent == null {
            return false
        }

        return interfaceEvent.get_EventHandlerType() == declaredEvent.HandlerType
    }

    // A PROPERTY SLOT IS NOT A METHOD THE IMPLEMENTER DECLARED, AND IT NEVER WILL BE.
    //
    // An interface's `Count: int` is one abstract `get_Count` row, and `Type.GetMethods()` hands it
    // back as an ordinary method — but the class that fills it wrote `Count`, so the method table
    // this walk searched had nothing of that name and the whole interface answered UNSATISFIED. That
    // is the entire reason `class Bag: IReadOnlyCollection<string>` could not be written: the walk was
    // asking the wrong table, not finding a missing member. (It is also why the symptom looked like
    // "external interfaces cannot be implemented at all" while `IDisposable`, `IEquatable<T>` and
    // `IComparable<T>` — every one of them method-only — already worked.)
    //
    // Two tables fill a value slot, exactly as the declaration walk fills it: a written PROPERTY
    // supplies its own accessors, and a plain FIELD of the slot's name and type gets a synthesized
    // reader. The slot's own signature decides in both cases, because the CLR matches an implicit
    // implementation by exact signature and a near-miss produces a type that will not load.
    static func PropertyAccessorSatisfied(
        implementer: ColumnarStructDef,
        externalMethod: MethodInfo,
        externalName: string,
        builderBound: bool,
        closedArguments: Type[]
    ): bool {
        if !externalMethod.get_IsSpecialName() {
            return false
        }
        isGetter := externalName.StartsWith("get_", StringComparison.Ordinal)
        isSetter := externalName.StartsWith("set_", StringComparison.Ordinal)
        if !isGetter && !isSetter {
            return false
        }
        memberName := externalName.Substring(4)
        if memberName.Length == 0 {
            return false
        }

        declaredProperty: ColumnarPropertyDef = null
        if implementer.Properties.TryGetValue(memberName, out declaredProperty) {
            if isSetter && declaredProperty.Setter == null {
                return false
            }
            if isGetter {
                return SignatureFills(externalMethod, externalName, builderBound, closedArguments, declaredProperty.PropertyType, new Type[](0))
            }
            setterParameters := new Type[](1)
            setterParameters[0] = declaredProperty.PropertyType
            return SignatureFills(externalMethod, externalName, builderBound, closedArguments, ColumnarTypeOfPlanner.RequiredVoidType(), setterParameters)
        }

        if !isGetter {
            return false
        }
        // The FIELD half. The reader over it is synthesized by the declaration walk under exactly the
        // same condition this asks about, so the two cannot disagree: a field of the slot's name whose
        // type IS the slot's type.
        backingField: System.Reflection.Emit.FieldBuilder = null
        if !implementer.Fields.TryGetValue(memberName, out backingField) {
            return false
        }
        return SignatureFills(externalMethod, externalName, builderBound, closedArguments, backingField.get_FieldType(), new Type[](0))
    }

    static func SignatureFills(
        externalMethod: MethodInfo,
        externalName: string,
        builderBound: bool,
        closedArguments: Type[],
        returnType: Type,
        parameterTypes: Type[]
    ): bool {
        if builderBound {
            return BuilderBoundSignatureMatches(externalMethod, closedArguments, externalName, returnType, parameterTypes)
        }
        return new ColumnarExternalInterfaceMethodMatch(externalMethod, externalName, returnType, parameterTypes).Matched
    }

    // WHICH MEMBER IS MISSING, NAMED. The whole check used to answer a bare `false`, and its one
    // caller turned that into a bare `return false` — so implementing an external interface wrongly
    // produced an NL103 with no `Declined at …` clause at all, the only decline in the backend that
    // could not say what it refused.
    // AN INTERFACE'S OWN ROWS ARE NOT ALL OF ITS REQUIREMENTS. `IReadOnlyCollection<T>` declares one
    // member — `Count` — and INHERITS `IEnumerable<T>.GetEnumerator` and
    // `IEnumerable.GetEnumerator`; `Type.GetMethods()` on an interface returns only its own rows, so
    // both the completeness question and the MethodImpl walk used to stop at the first level. A class
    // that stops there emits, and then fails to LOAD: the inherited slot has no implementation and the
    // CLR says so at the first use.
    //
    // The closure is the interface plus everything it inherits, deduplicated by runtime identity. A
    // BUILDER-BOUND construction is left alone: its instantiation answers no reflection query at all,
    // which is why its members already come from the generic definition.
    static func InterfaceRequirementClosure(externalInterface: Type): List<Type> {
        closure := new List<Type>()
        closure.Add(externalInterface)
        if ColumnarGenericTypeReceiverFacts.IsBuilderBoundConstruction(externalInterface) {
            return closure
        }
        for inherited in externalInterface.GetInterfaces() {
            if ColumnarGenericTypeReceiverFacts.IsBuilderBoundConstruction(inherited) {
                continue
            }
            alreadyPresent := false
            for seen in closure {
                if seen == inherited {
                    alreadyPresent = true
                }
            }
            if !alreadyPresent {
                closure.Add(inherited)
            }
        }
        return closure
    }

    static func InterfacesSatisfied(implementer: ColumnarStructDef, externalInterfaces: List<Type>, out unsatisfiedMember: string): bool {
        unsatisfiedMember = ""
        for declaredInterface in externalInterfaces {
            for externalInterface in InterfaceRequirementClosure(declaredInterface) {
                builderBound := ColumnarGenericTypeReceiverFacts.IsBuilderBoundConstruction(externalInterface)
                lookupType := builderBound ? externalInterface.GetGenericTypeDefinition() : externalInterface
                closedArguments := builderBound ? externalInterface.GetGenericArguments() : new Type[](0)
                for externalMethod in lookupType.GetMethods() {
                    implementation: ColumnarInstanceMethodDef = null
                    externalName := externalMethod.get_Name()
                    if !implementer.Methods.TryGetValue(externalName, out implementation) {
                        // AN EVENT'S ACCESSORS ARE NOT IN THE METHOD TABLE, and they are exactly what an
                        // interface event's `add_X`/`remove_X` ask for. The implementer supplies them by
                        // DECLARING the event, which is the only way N# can write them; the handler type is
                        // measured, because a same-named event over another delegate fills nothing.
                        if EventAccessorSatisfied(implementer, lookupType, externalMethod, externalName) {
                            continue
                        }
                        if PropertyAccessorSatisfied(implementer, externalMethod, externalName, builderBound, closedArguments) {
                            continue
                        }
                        unsatisfiedMember = UnsatisfiedMemberName(externalInterface, externalName)
                        return false
                    }
                    implementationObject: object? = implementation
                    actualImplementation := (ColumnarInstanceMethodDef)implementationObject
                    implementationTypeParameters := ImplementationTypeParameters(actualImplementation)
                    if builderBound {
                        if !BuilderBoundSignatureMatches(
                            externalMethod,
                            closedArguments,
                            externalName,
                            actualImplementation.ReturnType,
                            actualImplementation.ParamTypes
                        ) {
                            unsatisfiedMember = UnsatisfiedMemberName(externalInterface, externalName)
                            return false
                        }
                        continue
                    }
                    matchedSignature := new ColumnarExternalInterfaceMethodMatch(
                        externalMethod,
                        externalMethod.get_Name(),
                        actualImplementation.ReturnType,
                        actualImplementation.ParamTypes,
                        implementationTypeParameters
                    )
                    if !matchedSignature.Matched {
                        unsatisfiedMember = UnsatisfiedMemberName(externalInterface, externalName)
                        return false
                    }
                }
            }
        }
        return true
    }

    // THE TYPE PARAMETERS A DECLARATION WROTE, or the empty list. `Generics` is null for every
    // non-generic member, which is the overwhelming majority, so the empty array is the identity
    // substitution the match above applies.
    static func ImplementationTypeParameters(implementation: ColumnarInstanceMethodDef): Type[] {
        generics := implementation.Generics
        if generics == null {
            return ColumnarExternalInterfaceMethodMatch.EmptyTypeParameters()
        }
        return generics.TypeParams
    }

    // WHETHER A GENERIC DECLARATION COULD FILL AN INTERFACE SLOT AT ALL, asked BEFORE its own
    // `MethodBuilder` exists.
    //
    // A method that implements an interface slot has to be declared `virtual newslot final`, and
    // Reflection.Emit fixes a method's attributes at `DefineMethod` — but a GENERIC method's signature
    // cannot be resolved until its type parameters are defined, which happens inside that same call. So
    // the full signature match cannot decide the attributes; this name-and-arity question can, and it
    // is a SUPERSET of the full match (a full match agrees on the name and on the generic arity), so
    // the bits are set whenever they are needed. When it answers yes and the full match then finds no
    // slot, the completeness walk reports the interface unsatisfied and the type declines — it does not
    // emit a type that cannot load.
    static func DeclaresGenericMethodSlot(externalInterfaces: List<Type>, memberName: string, typeParameterCount: int, parameterCount: int): bool {
        if typeParameterCount == 0 {
            return false
        }
        for declaredInterface in externalInterfaces {
            for externalInterface in InterfaceRequirementClosure(declaredInterface) {
                if ColumnarGenericTypeReceiverFacts.IsBuilderBoundConstruction(externalInterface) {
                    continue
                }
                for externalMethod in externalInterface.GetMethods() {
                    if externalMethod.get_Name() == memberName && ColumnarExternalInterfaceMethodMatch.OpenMethodTypeParameterCount(externalMethod) == typeParameterCount && externalMethod.GetParameters().Length == parameterCount {
                        return true
                    }
                }
            }
        }
        return false
    }

    // The slot as a reader would go looking for it: the interface's own name, then the member — and
    // an accessor is reported as the VALUE member it belongs to, because that is what the source
    // writes.
    static func UnsatisfiedMemberName(externalInterface: Type, externalName: string): string {
        memberName := externalName
        if memberName.StartsWith("get_", StringComparison.Ordinal) || memberName.StartsWith("set_", StringComparison.Ordinal) {
            memberName = memberName.Substring(4)
        } else if memberName.StartsWith("add_", StringComparison.Ordinal) {
            memberName = memberName.Substring(4)
        } else if memberName.StartsWith("remove_", StringComparison.Ordinal) {
            memberName = memberName.Substring(7)
        }
        return externalInterface.Name + "." + memberName
    }
}
