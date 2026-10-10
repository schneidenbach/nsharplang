namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE GENERIC SLOT A RECEIVER ACTUALLY HAS. An extension declared on `IEnumerable<T>` can receive
// `List<int>` or `int[]`; inference must first read that receiver as `IEnumerable<int>`, then run the
// ordinary structural inference over the closed slot. Exact generic-definition matches win before
// this walk. A type that reaches the same definition at two different instantiations is ambiguous
// and contributes no candidate.
class AnalyzerGenericReceiverInference {
    typeResolver: AnalyzerTypeResolver
    declarationContext: AnalyzerDeclarationContext
    clrTypeConversion: AnalyzerClrTypeConversion

    constructor(resolver: AnalyzerTypeResolver, context: AnalyzerDeclarationContext, conversion: AnalyzerClrTypeConversion) {
        typeResolver = resolver
        declarationContext = context
        clrTypeConversion = conversion
    }

    func TryFindClosedImplementation(parameterReference: TypeReference, receiverType: TypeInfo, out implementation: TypeInfo): bool {
        implementation = BuiltInTypes.Unknown
        parameter := parameterReference as GenericTypeReference
        if parameter == null {
            return false
        }

        parameterType := typeResolver.ResolveType(parameter) as GenericTypeInfo
        if parameterType == null || parameterType.TypeArguments.Count != parameter.TypeArguments.Count {
            return false
        }

        receiverGeneric := receiverType as GenericTypeInfo
        if receiverGeneric != null && SameGenericDefinition(parameterType, receiverGeneric) {
            implementation = receiverType
            return true
        }

        arrayReceiver := receiverType as ArrayTypeInfo
        if arrayReceiver != null && TryGetArrayInterfaceImplementation(parameter, parameterType, arrayReceiver, out implementation) {
            return true
        }

        matches := new List<TypeInfo>()
        visited := new HashSet<object>()
        CollectImplementations(receiverType, parameterType, matches, visited, 0)
        if matches.Count != 1 {
            return false
        }

        implementation = matches[0]
        return true
    }

    func TryGetArrayInterfaceImplementation(
        parameter: GenericTypeReference,
        parameterType: GenericTypeInfo,
        receiver: ArrayTypeInfo,
        out implementation: TypeInfo
    ): bool {
        implementation = BuiltInTypes.Unknown
        if parameter.TypeArguments.Count != 1 {
            return false
        }

        definition := parameterType.GenericDefinition as ReflectionTypeInfo
        if definition == null || AnalyzerReflectionArgumentBinder.TryGetReflectionEnumerableElementParameter(definition.Type) == null {
            return false
        }

        arguments := new List<TypeInfo>()
        arguments.Add(receiver.ElementType)
        implementation = new GenericTypeInfo(parameterType.Name, arguments, parameterType.GenericDefinition)
        return true
    }

    func CollectImplementations(
        candidate: TypeInfo,
        parameterType: GenericTypeInfo,
        matches: List<TypeInfo>,
        visited: HashSet<object>,
        depth: int
    ) {
        if depth >= 64 || !visited.Add(candidate) {
            return
        }

        resolvedCandidate := declarationContext.ResolveDeclaredAlias(candidate)
        generic := resolvedCandidate as GenericTypeInfo
        if generic != null {
            if SameGenericDefinition(parameterType, generic) {
                AddUniqueMatch(matches, resolvedCandidate)
            }

            definition := generic.GenericDefinition
            reflectedDefinition := definition as ReflectionTypeInfo
            if definition != null && reflectedDefinition == null {
                substitution := declarationContext.CreateGenericSubstitution(definition, generic.TypeArguments)
                CollectSourceDefinition(definition, substitution, parameterType, matches, visited, depth + 1)
                return
            }

            if reflectedDefinition != null {
                let metadataImplementation: TypeInfo? = null
                if TryFindMetadataImplementation(generic, parameterType, reflectedDefinition.Type, out metadataImplementation) && metadataImplementation != null {
                    AddUniqueMatch(matches, metadataImplementation)
                }
                return
            }
        }

        if CollectSourceDefinition(resolvedCandidate, null, parameterType, matches, visited, depth + 1) {
            return
        }

        clrType := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedCandidate)
        parameterDefinition := parameterType.GenericDefinition as ReflectionTypeInfo
        if clrType != null && parameterDefinition != null {
            let compatibleType: Type? = null
            if AnalyzerOverloadFacts.TryFindCompatibleGenericType(parameterDefinition.Type, clrType, out compatibleType) && compatibleType != null {
                AddUniqueMatch(matches, AnalyzerReflectionTypeConversion.ConvertReflectionType(compatibleType))
            }
        }
    }

    func TryFindMetadataImplementation(
        receiver: GenericTypeInfo,
        parameterType: GenericTypeInfo,
        receiverDefinition: Type,
        out implementation: TypeInfo?
    ): bool {
        implementation = null
        parameterDefinition := parameterType.GenericDefinition as ReflectionTypeInfo
        if parameterDefinition == null {
            return false
        }

        closedReceiver := clrTypeConversion.TryConvertTypeInfoToClrType(receiver)
        if closedReceiver != null {
            let compatibleType: Type? = null
            if !AnalyzerOverloadFacts.TryFindCompatibleGenericType(parameterDefinition.Type, closedReceiver, out compatibleType) || compatibleType == null {
                return false
            }

            implementation = AnalyzerReflectionTypeConversion.ConvertReflectionType(compatibleType)
            return true
        }

        // A metadata definition may be closed over a source type, which has no CLR Type yet. Read the
        // open interface/base from the definition and substitute this construction's TypeInfo
        // arguments through that reflected shape instead of manufacturing an object-based surrogate.
        openImplementation := AnalyzerReflectionArgumentBinder.FindOpenImplementation(receiverDefinition, parameterDefinition.Type)
        if openImplementation == null {
            return false
        }

        implementation = ConvertReceiverBoundImplementation(openImplementation, receiverDefinition, receiver)
        return true
    }

    static func ConvertReceiverBoundImplementation(clrType: Type, receiverDefinition: Type, receiver: GenericTypeInfo): TypeInfo {
        if clrType.IsGenericParameter {
            receiverParameters := receiverDefinition.GetGenericArguments()
            index := 0
            while index < receiverParameters.Length && index < receiver.TypeArguments.Count {
                if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(clrType, receiverParameters[index]) {
                    return receiver.TypeArguments[index]
                }

                index = index + 1
            }

            return new SimpleTypeInfo(clrType.Name)
        }

        if clrType.IsArray {
            elementType := clrType.GetElementType()
            if elementType != null {
                return new ArrayTypeInfo(ConvertReceiverBoundImplementation(elementType, receiverDefinition, receiver))
            }
        }

        if clrType.IsGenericType {
            typeArguments := clrType.GetGenericArguments()
            if clrType.FullName == "System.Nullable`1" && typeArguments.Length == 1 {
                return new NullableTypeInfo(ConvertReceiverBoundImplementation(typeArguments[0], receiverDefinition, receiver))
            }

            convertedArguments := new List<TypeInfo>()
            for typeArgument in typeArguments {
                convertedArguments.Add(ConvertReceiverBoundImplementation(typeArgument, receiverDefinition, receiver))
            }

            name := clrType.Name
            tick := name.IndexOf('`')
            if tick >= 0 {
                name = name.Substring(0, tick)
            }

            return ReflectionTypeInfoFactory.FromConstructedGeneric(name, convertedArguments, clrType)
        }

        return AnalyzerReflectionTypeConversion.ConvertReflectionType(clrType)
    }

    func CollectSourceDefinition(
        definition: TypeInfo,
        substitution: Dictionary<string, TypeInfo>?,
        parameterType: GenericTypeInfo,
        matches: List<TypeInfo>,
        visited: HashSet<object>,
        depth: int
    ): bool {
        classType := definition as ClassTypeInfo
        if classType != null {
            for implementedReference in classType.Interfaces {
                implemented := ResolveSourceReference(implementedReference, definition, substitution)
                CollectImplementations(implemented, parameterType, matches, visited, depth + 1)
            }

            baseReference := classType.BaseClass
            if baseReference != null {
                baseType := ResolveSourceReference(baseReference, definition, substitution)
                CollectImplementations(baseType, parameterType, matches, visited, depth + 1)
            }

            return true
        }

        structType := definition as StructTypeInfo
        if structType != null {
            for implementedReference in structType.Interfaces {
                implemented := ResolveSourceReference(implementedReference, definition, substitution)
                CollectImplementations(implemented, parameterType, matches, visited, depth + 1)
            }

            return true
        }

        recordType := definition as RecordTypeInfo
        if recordType != null {
            for implementedReference in recordType.Interfaces {
                implemented := ResolveSourceReference(implementedReference, definition, substitution)
                CollectImplementations(implemented, parameterType, matches, visited, depth + 1)
            }

            return true
        }

        interfaceType := definition as InterfaceTypeInfo
        if interfaceType != null {
            for inheritedReference in interfaceType.BaseInterfaces {
                inherited := ResolveSourceReference(inheritedReference, definition, substitution)
                CollectImplementations(inherited, parameterType, matches, visited, depth + 1)
            }

            return true
        }

        return false
    }

    func ResolveSourceReference(
        reference: TypeReference,
        owner: TypeInfo,
        substitution: Dictionary<string, TypeInfo>?
    ): TypeInfo {
        resolved: TypeInfo = BuiltInTypes.Unknown
        if declarationContext.TryResolveTypeForOwner(reference, owner, substitution, out resolved) {
            return declarationContext.ResolveDeclaredAlias(resolved)
        }

        return declarationContext.ResolveDeclaredAlias(typeResolver.ResolveType(reference))
    }

    static func AddUniqueMatch(matches: List<TypeInfo>, candidate: TypeInfo) {
        for existing in matches {
            if TypeInfoIdentityFacts.AreEqual(existing, candidate) {
                return
            }
        }

        matches.Add(candidate)
    }

    static func SameGenericDefinition(expected: GenericTypeInfo, candidate: GenericTypeInfo): bool {
        if expected.TypeArguments.Count != candidate.TypeArguments.Count {
            return false
        }

        expectedDefinition := expected.GenericDefinition
        candidateDefinition := candidate.GenericDefinition
        if expectedDefinition != null && candidateDefinition != null {
            if Object.ReferenceEquals(expectedDefinition, candidateDefinition) {
                return true
            }

            expectedReflection := expectedDefinition as ReflectionTypeInfo
            candidateReflection := candidateDefinition as ReflectionTypeInfo
            return expectedReflection != null && candidateReflection != null && TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(expectedReflection.Type, candidateReflection.Type)
        }

        return AnalyzerOverloadFacts.GenericNamesMatch(expected.Name, candidate.Name)
    }
}
