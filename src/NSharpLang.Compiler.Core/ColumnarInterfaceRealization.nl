namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Threading.Tasks


// Owns the declaration-time realization of source interfaces: inheritance order, structural
// implementation registration, completeness, and base-before-derived metadata finalization.
class ColumnarInterfaceRealization {
    static func TryComputeInterfaceDepths(
        interfaceDefinitions: List<ColumnarStructDef>,
        out depths: int[]
    ): bool {
        depths = new int[](interfaceDefinitions.Count)
        memo := new Dictionary<ColumnarStructDef, int>()
        index := 0
        while index < interfaceDefinitions.Count {
            interfaceDefinition := interfaceDefinitions[index]
            visiting := new HashSet<ColumnarStructDef>()
            depth := InterfaceDepthOrMinusOne(interfaceDefinition, memo, visiting)
            if depth < 0 {
                return false
            }
            depths[index] = depth
            index = index + 1
        }
        return true
    }

    static func RegisterDuckInterfaces(
        structs: IReadOnlyList<ColumnarStructInput>,
        structDefinitions: ColumnarStructDef[],
        typeResolutions: ColumnarSemanticTypeResolution[],
        interfaceDefinitions: List<ColumnarStructDef>
    ) {
        structIndex := 0
        while structIndex < structs.Count {
            source := structs[structIndex]
            definition := structDefinitions[structIndex]
            typeResolution := typeResolutions[structIndex]
            implementedBuilders := new HashSet<TypeBuilder>()
            implementedEnumerator := definition.ImplementedInterfaces.GetEnumerator()
            try {
                while implementedEnumerator.MoveNext() {
                    AddInterfaceClosureBuilders(implementedEnumerator.get_Current(), implementedBuilders)
                }
            } finally {
                implementedEnumerator.Dispose()
            }

            interfaceEnumerator := interfaceDefinitions.GetEnumerator()
            try {
                while interfaceEnumerator.MoveNext() {
                    interfaceDefinition := interfaceEnumerator.get_Current()
                    if implementedBuilders.Contains(interfaceDefinition.Builder) {
                        continue
                    }
                    if !StructInputSatisfiesDuckInterface(
                        source,
                        definition,
                        interfaceDefinition,
                        typeResolution.Enums,
                        typeResolution.Structs,
                        typeResolution.Unions
                    ) {
                        continue
                    }

                    definition.ImplementedInterfaces.Add(interfaceDefinition)
                    AddDuckInterfaceClosure(definition, interfaceDefinition, implementedBuilders)
                }
            } finally {
                interfaceEnumerator.Dispose()
            }

            structIndex = structIndex + 1
        }
    }

    static func AddInterfaceClosureBuilders(
        interfaceDefinition: ColumnarStructDef,
        implementedBuilders: HashSet<TypeBuilder>
    ) {
        inheritedInterfaces := new List<ColumnarStructDef>()
        ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(interfaceDefinition, inheritedInterfaces)
        inheritedEnumerator := inheritedInterfaces.GetEnumerator()
        try {
            while inheritedEnumerator.MoveNext() {
                implementedBuilders.Add(inheritedEnumerator.get_Current().Builder)
            }
        } finally {
            inheritedEnumerator.Dispose()
        }
    }

    static func AddDuckInterfaceClosure(
        definition: ColumnarStructDef,
        interfaceDefinition: ColumnarStructDef,
        implementedBuilders: HashSet<TypeBuilder>
    ) {
        duckImplementedInterfaces := new List<ColumnarStructDef>()
        ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(interfaceDefinition, duckImplementedInterfaces)
        duckEnumerator := duckImplementedInterfaces.GetEnumerator()
        try {
            while duckEnumerator.MoveNext() {
                implemented := duckEnumerator.get_Current()
                if implementedBuilders.Add(implemented.Builder) {
                    definition.Builder.AddInterfaceImplementation(implemented.Builder)
                }
            }
        } finally {
            duckEnumerator.Dispose()
        }
    }

    static func InterfacesSatisfied(
        structs: IReadOnlyList<ColumnarStructInput>,
        structDefinitions: ColumnarStructDef[],
        structRegistry: Dictionary<string, ColumnarStructDef>
    ): bool {
        structIndex := 0
        while structIndex < structs.Count {
            definition := structDefinitions[structIndex]
            seenRequiredInterfaces := new HashSet<ColumnarStructDef>()
            if definition.ImplementedInterfaces.Count > 0 {
                implementedEnumerator := definition.ImplementedInterfaces.GetEnumerator()
                try {
                    while implementedEnumerator.MoveNext() {
                        implementedInterface := implementedEnumerator.get_Current()
                        hasClosedImplementations := false
                        if !TryValidateClosedImplementations(
                            definition,
                            implementedInterface,
                            structRegistry,
                            out hasClosedImplementations
                        ) {
                            return false
                        }
                        if hasClosedImplementations {
                            continue
                        }
                        if !OpenInterfaceRequirementsSatisfied(
                            definition,
                            implementedInterface,
                            seenRequiredInterfaces
                        ) {
                            return false
                        }
                    }
                } finally {
                    implementedEnumerator.Dispose()
                }
            }

            if !ColumnarExternalInterfaceMethodResolver.InterfacesSatisfied(definition, definition.ExternalInterfaces) {
                return false
            }
            structIndex = structIndex + 1
        }
        return true
    }

    static func TryValidateClosedImplementations(
        definition: ColumnarStructDef,
        implementedInterface: ColumnarStructDef,
        structRegistry: Dictionary<string, ColumnarStructDef>,
        out hasClosedImplementations: bool
    ): bool {
        hasClosedImplementations = false
        implementedTypeEnumerator := definition.ImplementedInterfaceTypes.GetEnumerator()
        try {
            while implementedTypeEnumerator.MoveNext() {
                implementedInterfaceType := implementedTypeEnumerator.get_Current()
                if implementedInterfaceType.get_IsGenericType() && !implementedInterfaceType.get_IsGenericTypeDefinition() {
                    closedInterfaceDefinition: ColumnarStructDef = null
                    if ColumnarSourceDefinitionResolver.TryResolveInterface(
                        implementedInterfaceType,
                        structRegistry.get_Values(),
                        out closedInterfaceDefinition
                    ) && Object.ReferenceEquals(closedInterfaceDefinition, implementedInterface) {
                        hasClosedImplementations = true
                        if !ColumnarClosedGenericMemberResolver.SourceInterfaceMembersSatisfied(
                            definition,
                            implementedInterface,
                            implementedInterfaceType
                        ) {
                            return false
                        }
                    }
                }
            }
        } finally {
            implementedTypeEnumerator.Dispose()
        }
        return true
    }

    static func OpenInterfaceRequirementsSatisfied(
        definition: ColumnarStructDef,
        implementedInterface: ColumnarStructDef,
        seenRequiredInterfaces: HashSet<ColumnarStructDef>
    ): bool {
        requiredInterfaces := new List<ColumnarStructDef>()
        ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(implementedInterface, requiredInterfaces)
        requiredEnumerator := requiredInterfaces.GetEnumerator()
        try {
            while requiredEnumerator.MoveNext() {
                requiredInterface := requiredEnumerator.get_Current()
                if !seenRequiredInterfaces.Add(requiredInterface) {
                    continue
                }
                if !RequiredInterfaceMembersSatisfied(definition, requiredInterface) {
                    return false
                }
            }
        } finally {
            requiredEnumerator.Dispose()
        }
        return true
    }

    static func RequiredInterfaceMembersSatisfied(
        definition: ColumnarStructDef,
        requiredInterface: ColumnarStructDef
    ): bool {
        memberEnumerator := requiredInterface.Methods.GetEnumerator()
        try {
            while memberEnumerator.MoveNext() {
                entry := memberEnumerator.get_Current()
                memberName := entry.get_Key()
                member := entry.get_Value()
                if requiredInterface.DefaultInterfaceMethodNames.Contains(memberName) {
                    continue
                }

                implementation: ColumnarInstanceMethodDef = null
                if !definition.Methods.TryGetValue(memberName, out implementation) || implementation.ReturnType != member.ReturnType || !ParamTypesMatch(member.ParamTypes, implementation.ParamTypes) {
                    return false
                }
            }
        } finally {
            memberEnumerator.Dispose()
        }
        return true
    }

    static func FinalizeInterfaces(
        interfaces: IReadOnlyList<ColumnarInterfaceInput>,
        interfaceDefinitions: List<ColumnarStructDef>,
        depths: int[]
    ) {
        depth := 0
        while depth <= interfaces.Count {
            index := 0
            while index < interfaceDefinitions.Count {
                if depths[index] == depth {
                    interfaceDefinitions[index].Builder.CreateType()
                }
                index = index + 1
            }
            depth = depth + 1
        }
    }

    static func IsSupportedParameterType(parameterType: Type): bool {
        return ColumnarTypeOfPlanner.IsSupportedType(parameterType) || (parameterType.get_IsByRef() && ColumnarCanonicalTypeResolver.IsSupportedByRefElementType(parameterType.GetElementType()))
    }

    static func TryComputeAsyncReturnShape(
        name: string,
        canonical: string,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out inner: Type,
        out wrapped: Type
    ): bool {
        inner = ColumnarTypeOfPlanner.RequiredVoidType()
        wrapped = null
        isEntryPoint := string.Equals(name, "main", StringComparison.OrdinalIgnoreCase)
        if canonical == "Task" {
            wrapped = typeof(Task)
            return true
        }
        if canonical == "ValueTask" {
            wrapped = typeof(ValueTask)
            return true
        }
        if canonical.StartsWith("Task<", StringComparison.Ordinal) && canonical[canonical.Length - 1] == '>' {
            if !ColumnarCanonicalTypeResolver.TryResolveType(
                canonical.Substring(5, canonical.Length - 6),
                enumRegistry,
                structRegistry,
                unionRegistry,
                out inner
            ) || !ColumnarTypeOfPlanner.IsSupportedType(inner) {
                return false
            }
            taskDefinition := typeof(Task<int>).GetGenericTypeDefinition()
            taskArguments := new Type[](1)
            taskArguments[0] = inner
            wrapped = taskDefinition.MakeGenericType(taskArguments)
            return true
        }
        if canonical.StartsWith("ValueTask<", StringComparison.Ordinal) && canonical[canonical.Length - 1] == '>' {
            if !ColumnarCanonicalTypeResolver.TryResolveType(
                canonical.Substring(10, canonical.Length - 11),
                enumRegistry,
                structRegistry,
                unionRegistry,
                out inner
            ) || !ColumnarTypeOfPlanner.IsSupportedType(inner) {
                return false
            }
            valueTaskDefinition := typeof(ValueTask<int>).GetGenericTypeDefinition()
            valueTaskArguments := new Type[](1)
            valueTaskArguments[0] = inner
            wrapped = valueTaskDefinition.MakeGenericType(valueTaskArguments)
            return true
        }
        if canonical == "void" {
            wrapped = isEntryPoint ? typeof(Task) : typeof(ValueTask)
            return true
        }
        if !ColumnarCanonicalTypeResolver.TryResolveType(
            canonical,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out inner
        ) || !ColumnarTypeOfPlanner.IsSupportedType(inner) {
            return false
        }
        inferredDefinition := (isEntryPoint ? typeof(Task<int>) : typeof(ValueTask<int>)).GetGenericTypeDefinition()
        inferredArguments := new Type[](1)
        inferredArguments[0] = inner
        wrapped = inferredDefinition.MakeGenericType(inferredArguments)
        return true
    }

    static func ParamTypesMatch(left: Type[], right: Type[]): bool {
        if left.Length != right.Length {
            return false
        }
        index := 0
        while index < left.Length {
            if left[index] != right[index] {
                return false
            }
            index = index + 1
        }
        return true
    }

    static func StructInputSatisfiesDuckInterface(
        source: ColumnarStructInput,
        sourceDefinition: ColumnarStructDef,
        interfaceDefinition: ColumnarStructDef,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>
    ): bool {
        requiredInterfaces := new List<ColumnarStructDef>()
        ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(interfaceDefinition, requiredInterfaces)
        requiredEnumerator := requiredInterfaces.GetEnumerator()
        try {
            while requiredEnumerator.MoveNext() {
                requiredInterface := requiredEnumerator.get_Current()
                if !RequiredDuckInterfaceSatisfied(
                    source,
                    sourceDefinition,
                    requiredInterface,
                    enumRegistry,
                    structRegistry,
                    unionRegistry
                ) {
                    return false
                }
            }
        } finally {
            requiredEnumerator.Dispose()
        }
        return true
    }

    static func RequiredDuckInterfaceSatisfied(
        source: ColumnarStructInput,
        sourceDefinition: ColumnarStructDef,
        requiredInterface: ColumnarStructDef,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>
    ): bool {
        memberEnumerator := requiredInterface.Methods.GetEnumerator()
        try {
            while memberEnumerator.MoveNext() {
                entry := memberEnumerator.get_Current()
                memberName := entry.get_Key()
                member := entry.get_Value()
                if requiredInterface.DefaultInterfaceMethodNames.Contains(memberName) {
                    continue
                }
                if !StructInputHasDuckMethod(
                    source,
                    sourceDefinition,
                    memberName,
                    member.ReturnType,
                    member.ParamTypes,
                    enumRegistry,
                    structRegistry,
                    unionRegistry
                ) {
                    return false
                }
            }
        } finally {
            memberEnumerator.Dispose()
        }
        return true
    }

    static func StructInputHasDuckMethod(
        source: ColumnarStructInput,
        sourceDefinition: ColumnarStructDef,
        name: string,
        returnType: Type,
        parameterTypes: Type[],
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>
    ): bool {
        methodEnumerator := GetMethodEnumerator(source.Methods)
        movement := methodEnumerator as IEnumerator
        try {
            while movement.MoveNext() {
                method := methodEnumerator.get_Current()
                if method.IsStatic || method.Name != name || method.ParamCanonicals.Length != parameterTypes.Length || method.TypeParamNames.Length > 0 {
                    continue
                }

                candidateReturn: Type = null
                if method.IsAsync {
                    discardedInner: Type = null
                    if !TryComputeAsyncReturnShape(
                        method.Name,
                        method.ReturnCanonical,
                        enumRegistry,
                        structRegistry,
                        unionRegistry,
                        out discardedInner,
                        out candidateReturn
                    ) {
                        return false
                    }
                } else if method.ReturnCanonical == "void" {
                    candidateReturn = ColumnarTypeOfPlanner.RequiredVoidType()
                } else if !ColumnarCanonicalTypeResolver.TryResolveMemberType(
                    method.ReturnCanonical,
                    sourceDefinition,
                    enumRegistry,
                    structRegistry,
                    unionRegistry,
                    out candidateReturn
                ) || !ColumnarTypeOfPlanner.IsSupportedType(candidateReturn) {
                    return false
                }

                if !ColumnarTypeEquivalenceFacts.TypesEquivalent(candidateReturn, returnType) {
                    continue
                }

                parametersMatch := true
                parameterIndex := 0
                while parameterIndex < method.ParamCanonicals.Length {
                    candidateParameter: Type = null
                    if !ColumnarCanonicalTypeResolver.TryResolveMemberType(
                        method.ParamCanonicals[parameterIndex],
                        sourceDefinition,
                        enumRegistry,
                        structRegistry,
                        unionRegistry,
                        out candidateParameter
                    ) || !IsSupportedParameterType(candidateParameter) || !ColumnarTypeEquivalenceFacts.TypesEquivalent(candidateParameter, parameterTypes[parameterIndex]) {
                        parametersMatch = false
                        break
                    }
                    parameterIndex = parameterIndex + 1
                }
                if parametersMatch {
                    return true
                }
            }
        } finally {
            disposable := methodEnumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return false
    }

    static func InterfaceDepthOrMinusOne(
        interfaceDefinition: ColumnarStructDef,
        memo: Dictionary<ColumnarStructDef, int>,
        visiting: HashSet<ColumnarStructDef>
    ): int {
        cached := 0
        if memo.TryGetValue(interfaceDefinition, out cached) {
            return cached
        }
        if !visiting.Add(interfaceDefinition) {
            return -1
        }

        depth := 0
        baseEnumerator := interfaceDefinition.InterfaceBases.GetEnumerator()
        try {
            while baseEnumerator.MoveNext() {
                baseInterface := baseEnumerator.get_Current()
                baseDepth := InterfaceDepthOrMinusOne(baseInterface, memo, visiting)
                if baseDepth < 0 {
                    visiting.Remove(interfaceDefinition)
                    return -1
                }
                depth = Math.Max(depth, baseDepth + 1)
            }
        } finally {
            baseEnumerator.Dispose()
        }
        visiting.Remove(interfaceDefinition)
        memo[interfaceDefinition] = depth
        return depth
    }

    static func GetMethodEnumerator(methods: IEnumerable<ColumnarFunctionInput>): IEnumerator<ColumnarFunctionInput> {
        return methods.GetEnumerator()
    }
}
