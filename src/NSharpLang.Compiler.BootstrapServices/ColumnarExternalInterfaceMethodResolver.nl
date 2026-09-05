namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection

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

    constructor(target: MethodInfo, name: string, returnType: Type, parameterTypes: Type[]) {
        effectiveReturn := typeof(object)
        parameters := new List<object>()
        matched := target.get_Name() == name
        if matched {
            effectiveReturn = target.get_ReturnType()
            matched = ColumnarTypeEquivalenceFacts.TypesEquivalent(effectiveReturn, returnType)
            if matched {
                reflectedParameters := target.GetParameters()
                matched = reflectedParameters.Length == parameterTypes.Length
                if matched {
                    index := 0
                    while index < reflectedParameters.Length {
                        reflectedParameter := reflectedParameters[index]
                        effectiveParameter := reflectedParameter.get_ParameterType()
                        if !ColumnarTypeEquivalenceFacts.TypesEquivalent(effectiveParameter, parameterTypes[index]) {
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

    static func RecoverOpenMethod(target: MethodInfo, openDeclaringType: Type): MethodInfo {
        targetToken := target.get_MetadataToken()
        targetModuleVersionId := ReadModuleVersionId(target)
        for candidate in openDeclaringType.GetMethods() {
            if candidate.get_MetadataToken() == targetToken && ReadModuleVersionId(candidate) == targetModuleVersionId {
                return candidate
            }
        }
        throw new InvalidOperationException("The external method's open MethodDef could not be recovered from its declaring type.")
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
        for externalInterface in externalInterfaces {
            for externalMethod in externalInterface.GetMethods() {
                matchedSignature := new ColumnarExternalInterfaceMethodMatch(
                    externalMethod,
                    memberName,
                    returnType,
                    parameterTypes
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

    static func InterfacesSatisfied(implementer: ColumnarStructDef, externalInterfaces: List<Type>): bool {
        for externalInterface in externalInterfaces {
            for externalMethod in externalInterface.GetMethods() {
                implementation: ColumnarInstanceMethodDef = null
                externalName := externalMethod.get_Name()
                if !implementer.Methods.TryGetValue(externalName, out implementation) {
                    return false
                }
                implementationObject: object? = implementation
                actualImplementation := (ColumnarInstanceMethodDef)implementationObject
                matchedSignature := new ColumnarExternalInterfaceMethodMatch(
                    externalMethod,
                    externalMethod.get_Name(),
                    actualImplementation.ReturnType,
                    actualImplementation.ParamTypes
                )
                if !matchedSignature.Matched {
                    return false
                }
            }
        }
        return true
    }
}
