namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// Closed generic member mechanics have one N# owner. The general MethodInfo rebinder serves every
// existing collection, iterator, await and source-interface caller. Source-interface signature
// closure deliberately retains its narrower historical policy: the original closed context maps
// generic parameters by ordinal, including parameters declared by another source owner.
class ColumnarClosedGenericMemberResolver {
    static func ResolveMethod(closedType: Type, openMethod: MethodInfo): MethodInfo {
        if ColumnarTypeOfPlanner.ContainsBuilderBoundType(closedType) {
            rebound := TypeBuilder.GetMethod(closedType, openMethod)
            return rebound
        }

        resolved := MethodBase.GetMethodFromHandle(openMethod.get_MethodHandle(), closedType.get_TypeHandle())
        resolvedObject: object? = resolved
        return (MethodInfo)resolvedObject
    }

    static func SubstituteInterfaceMemberType(memberType: Type, closedInterfaceType: Type): Type {
        if !closedInterfaceType.get_IsGenericType() || closedInterfaceType.get_IsGenericTypeDefinition() {
            return memberType
        }

        if memberType.get_IsGenericParameter() {
            closedArguments := closedInterfaceType.GetGenericArguments()
            position := memberType.get_GenericParameterPosition()
            if position >= 0 && position < closedArguments.Length {
                return closedArguments[position]
            }
            return memberType
        }

        if memberType.get_IsSZArray() {
            rawElementType := memberType.GetElementType()
            elementObject: object? = rawElementType
            elementType := (Type)elementObject
            return SubstituteInterfaceMemberType(elementType, closedInterfaceType).MakeArrayType()
        }

        if memberType.get_IsByRef() {
            rawElementType := memberType.GetElementType()
            elementObject: object? = rawElementType
            elementType := (Type)elementObject
            return SubstituteInterfaceMemberType(elementType, closedInterfaceType).MakeByRefType()
        }

        if memberType.get_IsGenericType() && memberType.get_ContainsGenericParameters() {
            arguments := memberType.GetGenericArguments()
            closedArguments := new Type[](arguments.Length)
            index := 0
            while index < arguments.Length {
                closedArguments[index] = SubstituteInterfaceMemberType(arguments[index], closedInterfaceType)
                index += 1
            }
            return memberType.GetGenericTypeDefinition().MakeGenericType(closedArguments)
        }

        return memberType
    }

    static func TryFindSourceInterfaceMethod(
        closedInterfaceType: Type,
        mappingOpenDefinition: ColumnarStructDef,
        memberName: string,
        returnType: Type,
        parameterTypes: Type[],
        table: ColumnarStructuralTypeReferenceTable,
        out binding: ColumnarClosedSourceInterfaceMethodBinding?
    ): bool {
        binding = null
        return TryFindSourceInterfaceMethodCore(
            closedInterfaceType,
            mappingOpenDefinition,
            mappingOpenDefinition,
            memberName,
            returnType,
            parameterTypes,
            table,
            out binding
        )
    }

    static func TryFindSourceInterfaceMethodCore(
        closedInterfaceType: Type,
        mappingOpenDefinition: ColumnarStructDef,
        candidateDefinition: ColumnarStructDef,
        memberName: string,
        returnType: Type,
        parameterTypes: Type[],
        table: ColumnarStructuralTypeReferenceTable,
        out binding: ColumnarClosedSourceInterfaceMethodBinding?
    ): bool {
        binding = null
        attempt := new ColumnarClosedSourceInterfaceMethodBinding(
            mappingOpenDefinition,
            candidateDefinition,
            memberName,
            closedInterfaceType,
            returnType,
            parameterTypes,
            table
        )
        if attempt.Matched {
            binding = attempt
            return true
        }

        for baseDefinition in candidateDefinition.InterfaceBases {
            if TryFindSourceInterfaceMethodCore(
                closedInterfaceType,
                mappingOpenDefinition,
                baseDefinition,
                memberName,
                returnType,
                parameterTypes,
                table,
                out binding
            ) {
                return true
            }
        }
        return false
    }

    static func SourceInterfaceMembersSatisfied(
        implementer: ColumnarStructDef,
        mappingOpenDefinition: ColumnarStructDef,
        closedInterfaceType: Type
    ): bool {
        requiredInterfaces := new List<ColumnarStructDef>()
        ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(mappingOpenDefinition, requiredInterfaces)
        for requiredInterface in requiredInterfaces {
            for memberPair in requiredInterface.Methods {
                memberName := memberPair.Key
                member := memberPair.Value
                if requiredInterface.DefaultInterfaceMethodNames.Contains(memberName) {
                    continue
                }
                implementation: ColumnarInstanceMethodDef = null
                if !implementer.Methods.TryGetValue(memberName, out implementation) {
                    return false
                }
                implementationObject: object? = implementation
                actualImplementation := (ColumnarInstanceMethodDef)implementationObject
                comparison := new ColumnarClosedSourceInterfaceMethodMatch(
                    closedInterfaceType,
                    member,
                    actualImplementation.ReturnType,
                    actualImplementation.ParamTypes
                )
                if !comparison.Matched {
                    return false
                }
            }
        }
        return true
    }
}

// A successful match is the immutable witness that ties the open declaration and original closed
// mapping context to the exact effective signature selected by the historical closure policy. The
// closure is performed once, in return-then-parameter order, before any structural capture.
class ColumnarClosedSourceInterfaceMethodMatch {
    readonly closedContextRuntimeTypeValue: Type
    readonly memberValue: ColumnarInstanceMethodDef
    readonly openReturnRuntimeTypeValue: Type
    readonly openParametersValue: IReadOnlyList<object>
    readonly openParameterCountValue: int
    readonly openParameterModifiersValue: IReadOnlyList<object>
    readonly openParameterModifierCountValue: int
    readonly openBuilderValue: MethodBuilder?
    readonly effectiveReturnRuntimeTypeValue: Type
    readonly effectiveParametersValue: IReadOnlyList<object>
    readonly effectiveParameterCountValue: int
    readonly matchedValue: bool

    ClosedContextRuntimeType: Type => closedContextRuntimeTypeValue
    Member: ColumnarInstanceMethodDef => memberValue
    OpenReturnRuntimeType: Type => openReturnRuntimeTypeValue
    OpenParameterCount: int => openParameterCountValue
    OpenParameterModifierCount: int => openParameterModifierCountValue
    OpenBuilder: MethodBuilder? => openBuilderValue
    EffectiveReturnRuntimeType: Type => effectiveReturnRuntimeTypeValue
    EffectiveParameterCount: int => effectiveParameterCountValue
    Matched: bool => matchedValue

    constructor(
        closedInterfaceType: Type,
        member: ColumnarInstanceMethodDef,
        returnType: Type,
        parameterTypes: Type[]
    ) {
        openReturnType := member.ReturnType
        effectiveReturn := ColumnarClosedGenericMemberResolver.SubstituteInterfaceMemberType(
            openReturnType,
            closedInterfaceType
        )
        openParameters := new List<object>()
        effectiveParameters := new List<object>()
        matched := ColumnarTypeEquivalenceFacts.TypesEquivalent(effectiveReturn, returnType)
        if matched {
            matched = member.ParamTypes.Length == parameterTypes.Length
            if matched {
                index := 0
                while index < parameterTypes.Length {
                    openParameter := member.ParamTypes[index]
                    effectiveParameter := ColumnarClosedGenericMemberResolver.SubstituteInterfaceMemberType(
                        openParameter,
                        closedInterfaceType
                    )
                    if !ColumnarTypeEquivalenceFacts.TypesEquivalent(effectiveParameter, parameterTypes[index]) {
                        matched = false
                        break
                    }
                    openParameters.Add(openParameter)
                    effectiveParameters.Add(effectiveParameter)
                    index += 1
                }
            }
        }

        openParameterModifiers := new List<object>()
        openBuilder: MethodBuilder? = null
        openParameterModifierCount := -1
        if matched {
            openBuilder = member.Builder
            modifiers := member.ParamModifierKinds
            if modifiers != null {
                openParameterModifierCount = modifiers.Length
                modifierIndex := 0
                while modifierIndex < modifiers.Length {
                    openParameterModifiers.Add(modifiers[modifierIndex])
                    modifierIndex += 1
                }
            }
        }

        closedContextRuntimeTypeValue = closedInterfaceType
        memberValue = member
        openReturnRuntimeTypeValue = openReturnType
        openParametersValue = openParameters.AsReadOnly()
        openParameterCountValue = openParameters.Count
        openParameterModifiersValue = openParameterModifiers.AsReadOnly()
        openParameterModifierCountValue = openParameterModifierCount
        openBuilderValue = openBuilder
        effectiveReturnRuntimeTypeValue = effectiveReturn
        effectiveParametersValue = effectiveParameters.AsReadOnly()
        effectiveParameterCountValue = effectiveParameters.Count
        matchedValue = matched
    }

    func EffectiveParameterRuntimeType(index: int): Type {
        parameter := effectiveParametersValue.get_Item(index) as Type
        parameterObject: object? = parameter
        return (Type)parameterObject
    }

    func OpenParameterRuntimeType(index: int): Type {
        parameter := openParametersValue.get_Item(index) as Type
        parameterObject: object? = parameter
        return (Type)parameterObject
    }

    func OpenParameterModifierKind(index: int): int {
        modifier := openParameterModifiersValue.get_Item(index)
        return Convert.ToInt32(modifier)
    }

    func SourceRowStillMatches(
        foundDefinition: ColumnarStructDef,
        memberName: string,
        member: ColumnarInstanceMethodDef
    ): bool {
        if !matchedValue || !Object.ReferenceEquals(memberValue, member) {
            return false
        }
        registered: ColumnarInstanceMethodDef = null
        if !foundDefinition.Methods.TryGetValue(memberName, out registered) || !Object.ReferenceEquals(registered, member) {
            return false
        }
        if !Object.ReferenceEquals(member.ReturnType, openReturnRuntimeTypeValue) || !Object.ReferenceEquals(member.Builder, openBuilderValue) {
            return false
        }
        parameterTypes := member.ParamTypes
        modifierKinds := member.ParamModifierKinds
        if parameterTypes == null || modifierKinds == null {
            return false
        }
        if parameterTypes.Length != openParameterCountValue || modifierKinds.Length != openParameterModifierCountValue {
            return false
        }
        index := 0
        while index < openParameterCountValue {
            if !Object.ReferenceEquals(parameterTypes[index], OpenParameterRuntimeType(index)) {
                return false
            }
            index += 1
        }
        index = 0
        while index < openParameterModifierCountValue {
            if modifierKinds[index] != OpenParameterModifierKind(index) {
                return false
            }
            index += 1
        }
        return true
    }
}

class ColumnarClosedSourceInterfaceMethodParameterDescriptor {
    readonly typeValue: ColumnarSelectedTypeReference
    readonly runtimeTypeValue: Type

    Type: ColumnarSelectedTypeReference => typeValue
    RuntimeType: Type => runtimeTypeValue

    constructor(selectedType: ColumnarSelectedTypeReference, runtimeType: Type) {
        if selectedType == null || runtimeType == null {
            throw new InvalidOperationException("A closed source-interface method parameter requires structural type identity.")
        }
        typeValue = selectedType
        runtimeTypeValue = runtimeType
    }
}

// The open source declaration and the closed mapping context are distinct. An inherited method
// keeps its actual declaring ancestor in OpenDefinition while MappingOpenDefinition and
// ClosedContext retain the original interface whose arguments were used for ordinal substitution.
class ColumnarClosedSourceInterfaceMethodDescriptor {
    readonly tableValue: ColumnarStructuralTypeReferenceTable
    readonly matchValue: ColumnarClosedSourceInterfaceMethodMatch
    readonly openDefinitionValue: ColumnarSourceInterfaceMethodDescriptor
    readonly mappingOpenDefinitionValue: ColumnarSelectedTypeReference
    readonly mappingOpenRuntimeTypeValue: Type
    readonly closedContextValue: ColumnarSelectedTypeReference
    readonly closedContextRuntimeTypeValue: Type
    readonly effectiveReturnTypeValue: ColumnarSelectedTypeReference
    readonly effectiveReturnRuntimeTypeValue: Type
    readonly effectiveParametersValue: IReadOnlyList<object>
    readonly effectiveParameterCountValue: int

    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable => tableValue
    OpenDefinition: ColumnarSourceInterfaceMethodDescriptor => openDefinitionValue
    MappingOpenDefinition: ColumnarSelectedTypeReference => mappingOpenDefinitionValue
    ClosedContext: ColumnarSelectedTypeReference => closedContextValue
    EffectiveReturnType: ColumnarSelectedTypeReference => effectiveReturnTypeValue
    EffectiveParameterCount: int => effectiveParameterCountValue

    constructor(
        mappingOpenDefinition: ColumnarStructDef,
        foundDefinition: ColumnarStructDef,
        memberName: string,
        member: ColumnarInstanceMethodDef,
        comparison: ColumnarClosedSourceInterfaceMethodMatch,
        table: ColumnarStructuralTypeReferenceTable
    ) {
        if mappingOpenDefinition == null || foundDefinition == null || memberName == null || member == null || comparison == null || table == null || !comparison.SourceRowStillMatches(foundDefinition, memberName, member) {
            throw new InvalidOperationException("A closed source-interface descriptor requires its open declaration, closed context and effective signature.")
        }

        tableValue = table
        matchValue = comparison
        openDefinitionValue = new ColumnarSourceInterfaceMethodDescriptor(foundDefinition, memberName, member, table)
        mappingOpenDefinitionValue = table.SelectSourceDefinition(mappingOpenDefinition.DeclaredTypeName, mappingOpenDefinition.Builder)
        mappingOpenRuntimeTypeValue = mappingOpenDefinition.Builder
        closedContextRuntimeTypeValue = comparison.ClosedContextRuntimeType
        closedContextValue = table.SelectRuntimeType(closedContextRuntimeTypeValue)
        effectiveReturnRuntimeTypeValue = comparison.EffectiveReturnRuntimeType
        effectiveReturnTypeValue = table.SelectRuntimeType(effectiveReturnRuntimeTypeValue)
        parameterCopy := new List<object>()
        index := 0
        while index < comparison.EffectiveParameterCount {
            effectiveParameterType := comparison.EffectiveParameterRuntimeType(index)
            parameterCopy.Add(new ColumnarClosedSourceInterfaceMethodParameterDescriptor(
                table.SelectRuntimeType(effectiveParameterType),
                effectiveParameterType
            ))
            index += 1
        }
        effectiveParametersValue = parameterCopy.AsReadOnly()
        effectiveParameterCountValue = comparison.EffectiveParameterCount
    }

    func EffectiveParameterType(index: int): ColumnarSelectedTypeReference {
        return EffectiveParameter(index).Type
    }

    func EffectiveParameter(index: int): ColumnarClosedSourceInterfaceMethodParameterDescriptor {
        parameter := effectiveParametersValue.get_Item(index) as ColumnarClosedSourceInterfaceMethodParameterDescriptor
        if parameter == null {
            throw new InvalidOperationException("Closed source-interface parameter storage is invalid.")
        }
        return parameter
    }

    func Validate(expectedTable: ColumnarStructuralTypeReferenceTable): bool {
        if expectedTable == null || !Object.ReferenceEquals(tableValue, expectedTable) || !matchValue.Matched || !openDefinitionValue.Validate(expectedTable) {
            return false
        }
        if !Object.ReferenceEquals(matchValue.ClosedContextRuntimeType, closedContextRuntimeTypeValue) || !Object.ReferenceEquals(matchValue.EffectiveReturnRuntimeType, effectiveReturnRuntimeTypeValue) || matchValue.EffectiveParameterCount != effectiveParameterCountValue {
            return false
        }
        if !expectedTable.ValidatePair(mappingOpenDefinitionValue, mappingOpenRuntimeTypeValue) || !expectedTable.ValidatePair(closedContextValue, closedContextRuntimeTypeValue) || !expectedTable.ValidatePair(effectiveReturnTypeValue, effectiveReturnRuntimeTypeValue) {
            return false
        }

        mappingKey := mappingOpenDefinitionValue.Key
        closedKey := closedContextValue.Key
        if mappingKey == null || closedKey == null {
            return false
        }
        if closedKey.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric {
            if closedKey.ChildCount < 1 || !ColumnarStructuralTypeKeyFacts.KeysEqual(mappingKey, closedKey.Child(0)) {
                return false
            }
        } else if !ColumnarStructuralTypeKeyFacts.KeysEqual(mappingKey, closedKey) {
            return false
        }

        index := 0
        while index < effectiveParameterCountValue {
            parameter := EffectiveParameter(index)
            if !Object.ReferenceEquals(matchValue.EffectiveParameterRuntimeType(index), parameter.RuntimeType) || !expectedTable.ValidatePair(parameter.Type, parameter.RuntimeType) {
                return false
            }
            index += 1
        }
        return true
    }
}

// Target rebinding happens exactly once after a successful match, before structural descriptor
// capture. The target is therefore derived from the same authoritative Methods row and original
// closed context rather than accepted as an independently supplied handle.
class ColumnarClosedSourceInterfaceMethodBinding {
    readonly matchedValue: bool
    readonly descriptorValue: ColumnarClosedSourceInterfaceMethodDescriptor?
    readonly targetValue: MethodInfo?

    Matched: bool => matchedValue
    Descriptor: ColumnarClosedSourceInterfaceMethodDescriptor? => descriptorValue
    Target: MethodInfo? => targetValue

    constructor(
        mappingOpenDefinition: ColumnarStructDef,
        foundDefinition: ColumnarStructDef,
        memberName: string,
        closedInterfaceType: Type,
        returnType: Type,
        parameterTypes: Type[],
        table: ColumnarStructuralTypeReferenceTable
    ) {
        matched := false
        descriptor: ColumnarClosedSourceInterfaceMethodDescriptor? = null
        target: MethodInfo? = null
        member: ColumnarInstanceMethodDef = null
        if foundDefinition.Methods.TryGetValue(memberName, out member) {
            memberObject: object? = member
            authoritativeMember := (ColumnarInstanceMethodDef)memberObject
            comparison := new ColumnarClosedSourceInterfaceMethodMatch(
                closedInterfaceType,
                authoritativeMember,
                returnType,
                parameterTypes
            )
            if comparison.Matched {
                openBuilderObject: object? = comparison.OpenBuilder
                openBuilder := (MethodBuilder)openBuilderObject
                if closedInterfaceType.get_IsGenericType() && !closedInterfaceType.get_IsGenericTypeDefinition() {
                    target = ColumnarClosedGenericMemberResolver.ResolveMethod(closedInterfaceType, openBuilder)
                } else {
                    target = openBuilder
                }
                descriptor = new ColumnarClosedSourceInterfaceMethodDescriptor(
                    mappingOpenDefinition,
                    foundDefinition,
                    memberName,
                    authoritativeMember,
                    comparison,
                    table
                )
                matched = true
            }
        }
        matchedValue = matched
        descriptorValue = descriptor
        targetValue = target
    }

    func ValidatedTarget(expectedTable: ColumnarStructuralTypeReferenceTable): MethodInfo {
        if expectedTable == null || !matchedValue || descriptorValue == null || targetValue == null || !descriptorValue.Validate(expectedTable) {
            throw new InvalidOperationException("A closed source-interface member binding does not belong to the consuming emission.")
        }
        return targetValue
    }
}
