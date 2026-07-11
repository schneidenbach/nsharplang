namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func SourceCallVoidType(): Type {
    result := Type.GetType("System.Void")
    if result == null {
        throw new InvalidOperationException("System.Void runtime type was not found.")
    }

    return result
}

func SourceCallAttributedBuilder(name: string, attributes: object): TypeBuilder {
    seed := TypeOfCreateBuilder(name + "Seed", "ColumnarSourceDirectCallTests." + name, 0)

    noParameters := new Type[](0)
    getModule := ExecutorRequiredMethod(typeof(TypeBuilder), "get_Module", noParameters)

    moduleValue := TypeOfRequiredInvocation(getModule, seed, new object[](0))

    moduleBuilderType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.ModuleBuilder")

    typeAttributesType := TypeOfRequiredRuntimeType(typeof(AssemblyName), "System.Reflection.TypeAttributes")

    defineParameterTypes := new Type[](2)
    defineParameterTypes[0] = typeof(string)
    defineParameterTypes[1] = typeAttributesType
    defineType := ExecutorRequiredMethod(moduleBuilderType, "DefineType", defineParameterTypes)

    defineArguments := new object[](2)
    ExecutorSetObject(defineArguments, 0, name)
    ExecutorSetObject(defineArguments, 1, attributes)
    value := TypeOfRequiredInvocation(defineType, moduleValue, defineArguments)

    builder := value as TypeBuilder
    if builder == null {
        throw new InvalidOperationException("The attributed source-call fixture did not produce a TypeBuilder.")
    }

    return builder
}

func SourceCallInterfaceDefinition(name: string): ColumnarStructDef {
    typeAttributesType := TypeOfRequiredRuntimeType(typeof(AssemblyName), "System.Reflection.TypeAttributes")

    parseParameterTypes := new Type[](2)
    parseParameterTypes[0] = typeof(Type)
    parseParameterTypes[1] = typeof(string)
    enumType := Type.GetType("System.Enum")
    if enumType == null {
        throw new InvalidOperationException("System.Enum runtime type was not found.")
    }

    parseAttributes := ExecutorRequiredMethod(enumType, "Parse", parseParameterTypes)

    parseArguments := new object[](2)
    ExecutorSetObject(parseArguments, 0, typeAttributesType)
    ExecutorSetObject(parseArguments, 1, "Public, Interface, Abstract")

    attributes := TypeOfRequiredInvocation(parseAttributes, null, parseArguments)

    builder := SourceCallAttributedBuilder(name, attributes)
    definition := new ColumnarStructDef(builder, new string[](0), new Dictionary<string, FieldBuilder>(StringComparer.Ordinal), true, false, false, name)

    definition.IsInterface = true
    return definition
}

func SourceCallDefinition(name: string, isReference: bool): ColumnarStructDef {
    builder := TypeOfCreateBuilder(name, "ColumnarSourceDirectCallTests." + name, 0)

    if !isReference {
        parameterTypes := new Type[](1)
        parameterTypes[0] = typeof(Type)
        setParent := ExecutorRequiredMethod(typeof(TypeBuilder), "SetParent", parameterTypes)

        wrapperParameters := new Type[](2)
        wrapperParameters[0] = typeof(TypeBuilder)
        wrapperParameters[1] = typeof(Type)
        wrapper := BoundDynamicMethod("SourceCallSetValueTypeParent", typeof(int), wrapperParameters)

        il := wrapper.GetILGenerator()
        il.Emit(OpCodes.Ldarg, (short)0)
        il.Emit(OpCodes.Ldarg, (short)1)
        il.Emit(OpCodes.Callvirt, setParent)
        il.Emit(OpCodes.Ldc_I4, 0)
        il.Emit(OpCodes.Ret)
        arguments := new object[](2)
        ExecutorSetObject(arguments, 0, builder)
        valueType := Type.GetType("System.ValueType")
        if valueType == null {
            throw new InvalidOperationException("System.ValueType runtime type was not found.")
        }

        ExecutorSetObject(arguments, 1, valueType)
        invocationTarget: object? = null
        value := wrapper.Invoke(invocationTarget, arguments)
        if value == null {
            throw new InvalidOperationException("The source-call value-type fixture did not run.")
        }
    }

    return new ColumnarStructDef(builder, new string[](0), new Dictionary<string, FieldBuilder>(StringComparer.Ordinal), isReference, false, false, name)
}

func SourceCallGenericDefinition(name: string): ColumnarStructDef {
    builder := TypeOfCreateBuilder(name, "ColumnarSourceDirectCallTests." + name, 1)

    return new ColumnarStructDef(builder, new string[](0), new Dictionary<string, FieldBuilder>(StringComparer.Ordinal), true, false, false, name)
}

func SourceCallDefinitions(definition: ColumnarStructDef): ColumnarStructDef[] {
    result := new ColumnarStructDef[](1)
    result[0] = definition
    return result
}

func SourceCallAddInstanceFact(owner: ColumnarStructDef, memberName: string, definition: ColumnarInstanceMethodDef) {
    overloads := new List<ColumnarInstanceMethodDef>()
    if !owner.MethodOverloads.TryGetValue(memberName, out overloads) {
        overloads = new List<ColumnarInstanceMethodDef>()
        owner.MethodOverloads[memberName] = overloads
    }

    overloads.Add(definition)
    if !owner.Methods.ContainsKey(memberName) {
        owner.Methods[memberName] = definition
    }
}

func SourceCallAddStaticFact(owner: ColumnarStructDef, memberName: string, definition: ColumnarStaticMethodDef) {
    overloads := new List<ColumnarStaticMethodDef>()
    if !owner.StaticMethods.TryGetValue(memberName, out overloads) {
        overloads = new List<ColumnarStaticMethodDef>()
        owner.StaticMethods[memberName] = overloads
    }

    overloads.Add(definition)
}

func SourceCallDefineInstance(owner: ColumnarStructDef, memberName: string, parameterTypes: Type[], modifierKinds: int[], returnType: Type, attributes: MethodAttributes): ColumnarInstanceMethodDef {
    method := owner.Builder.DefineMethod(memberName, attributes, returnType, parameterTypes)

    definition := new ColumnarInstanceMethodDef(method, parameterTypes, modifierKinds, returnType)

    SourceCallAddInstanceFact(owner, memberName, definition)
    return definition
}

func SourceCallConstructInstanceFact(method: MethodBuilder, parameterTypes: Type[], modifierKinds: int[], returnType: Type): ColumnarInstanceMethodDef {
    return new ColumnarInstanceMethodDef(method, parameterTypes, modifierKinds, returnType)
}

func SourceCallDefineStatic(owner: ColumnarStructDef, memberName: string, parameterTypes: Type[], modifierKinds: int[], returnType: Type, attributes: MethodAttributes): ColumnarStaticMethodDef {
    method := owner.Builder.DefineMethod(memberName, attributes, returnType, parameterTypes)

    definition := new ColumnarStaticMethodDef(method, parameterTypes, modifierKinds, returnType)

    SourceCallAddStaticFact(owner, memberName, definition)
    return definition
}

func SourceCallPublicInstance(owner: ColumnarStructDef, memberName: string, parameterTypes: Type[], returnType: Type): ColumnarInstanceMethodDef {
    return SourceCallDefineInstance(owner, memberName, parameterTypes, new int[](0), returnType, (MethodAttributes)6)
}

func SourceCallPublicStatic(owner: ColumnarStructDef, memberName: string, parameterTypes: Type[], returnType: Type): ColumnarStaticMethodDef {
    return SourceCallDefineStatic(owner, memberName, parameterTypes, new int[](0), returnType, (MethodAttributes)22)
}

func SourceCallMakeGeneric(method: MethodBuilder) {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string[])
    defineParameters := ExecutorRequiredMethod(typeof(MethodBuilder), "DefineGenericParameters", parameterTypes)

    names := new string[](1)
    names[0] = "TMethod"
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, names)
    TypeOfRequiredInvocation(defineParameters, method, arguments)
}

func SourceCallDefineVarArgsMethod(owner: ColumnarStructDef, memberName: string, returnType: Type, attributes: MethodAttributes): MethodBuilder {
    callingConventionsType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.Reflection.CallingConventions")

    parameterTypes := new Type[](5)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(MethodAttributes)
    parameterTypes[2] = callingConventionsType
    parameterTypes[3] = typeof(Type)
    parameterTypes[4] = typeof(Type[])
    defineMethod := ExecutorRequiredMethod(typeof(TypeBuilder), "DefineMethod", parameterTypes)

    noParameters := new Type[](0)
    arguments := new object[](5)
    ExecutorSetObject(arguments, 0, memberName)
    ExecutorSetObject(arguments, 1, attributes)
    varArgsConvention := TypeOfRequiredStaticField(callingConventionsType, "VarArgs")

    ExecutorSetObject(arguments, 2, varArgsConvention)
    ExecutorSetObject(arguments, 3, returnType)
    ExecutorSetObject(arguments, 4, noParameters)
    value := TypeOfRequiredInvocation(defineMethod, owner.Builder, arguments)
    method := value as MethodBuilder
    if method == null {
        throw new InvalidOperationException("The source-call varargs fixture did not produce a MethodBuilder.")
    }

    return method
}

func SourceCallDefineVarArgsStatic(owner: ColumnarStructDef, memberName: string, returnType: Type): ColumnarStaticMethodDef {
    method := SourceCallDefineVarArgsMethod(owner, memberName, returnType, (MethodAttributes)22)
    noParameters := new Type[](0)
    definition := new ColumnarStaticMethodDef(method, noParameters, new int[](0), returnType)

    SourceCallAddStaticFact(owner, memberName, definition)
    return definition
}

func SourceCallDefineVarArgsInstance(owner: ColumnarStructDef, memberName: string, returnType: Type): ColumnarInstanceMethodDef {
    method := SourceCallDefineVarArgsMethod(owner, memberName, returnType, (MethodAttributes)6)
    noParameters := new Type[](0)
    definition := new ColumnarInstanceMethodDef(method, noParameters, new int[](0), returnType)

    SourceCallAddInstanceFact(owner, memberName, definition)
    return definition
}

test "source direct-call resolver classifies terminal shadows and exact dispatch facts" {
    owner := SourceCallDefinition("SourceCallDispatchOwner", true)
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    instance := SourceCallPublicInstance(owner, "Measure", oneInt, typeof(string))

    _staticMethod := SourceCallPublicStatic(owner, "Create", oneInt, owner.Builder)

    noParameters := new Type[](0)
    _nothing := SourceCallPublicInstance(owner, "Reset", noParameters, SourceCallVoidType())

    definitions := SourceCallDefinitions(owner)
    ownerType: Type = owner.Builder

    explicitInstance := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "Measure", oneInt, definitions)

    assert explicitInstance.Status == ColumnarSourceDirectCallStatus.Selected
    assert explicitInstance.IsSourceType
    assert explicitInstance.IsSelected
    assert explicitInstance.Dispatch == ColumnarSourceDirectCallDispatch.CallVirtual
    assert explicitInstance.Method != null
    assert explicitInstance.DeclaringType == ownerType
    assert explicitInstance.ReceiverType == ownerType
    assert explicitInstance.ReturnType == typeof(string)
    assert explicitInstance.ParameterTypes.Length == 1
    assert explicitInstance.ParameterTypes[0] == typeof(int)
    assert instance.ParamTypes.Length == 1
    assert explicitInstance.ReceiverIsReference
    assert !explicitInstance.IsStatic
    assert !explicitInstance.IsAbstract

    implicitInstance := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(owner, ownerType, "Measure", oneInt)

    assert implicitInstance.Status == ColumnarSourceDirectCallStatus.Selected
    assert implicitInstance.Method != null

    explicitStatic := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "Create", oneInt, definitions)

    assert explicitStatic.Status == ColumnarSourceDirectCallStatus.Selected
    assert explicitStatic.Dispatch == ColumnarSourceDirectCallDispatch.Call
    assert explicitStatic.Method != null
    assert explicitStatic.IsStatic
    assert !explicitStatic.IsAbstract

    implicitStatic := ColumnarSourceDirectCallResolver.ResolveImplicitStatic(owner, ownerType, "Create", oneInt)

    assert implicitStatic.Status == ColumnarSourceDirectCallStatus.Selected
    assert implicitStatic.Method != null

    voidCall := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "Reset", noParameters, definitions)

    assert voidCall.Status == ColumnarSourceDirectCallStatus.Selected
    assert voidCall.Method != null
    assert voidCall.ReturnType.FullName == "System.Void"

    missing := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "Missing", noParameters, definitions)

    assert missing.Status == ColumnarSourceDirectCallStatus.Rejected
    assert missing.IsSourceType
    assert !missing.IsSelected
    assert missing.Method == null
    assert missing.Dispatch == ColumnarSourceDirectCallDispatch.None

    external := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(typeof(string), "Measure", oneInt, definitions)

    assert external.Status == ColumnarSourceDirectCallStatus.NotSourceType
    assert !external.IsSourceType
    assert !external.IsSelected
}

test "source direct-call resolver selects exact overloads and rejects ambiguity arity and types" {
    owner := SourceCallDefinition("SourceCallOverloadOwner", true)
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    stringParameters := new Type[](1)
    stringParameters[0] = typeof(string)
    twoParameters := new Type[](2)
    twoParameters[0] = typeof(int)
    twoParameters[1] = typeof(int)

    _intMethod := SourceCallPublicInstance(owner, "Pick", intParameters, typeof(int))

    _stringMethod := SourceCallPublicInstance(owner, "Pick", stringParameters, typeof(string))

    SourceCallPublicInstance(owner, "Pair", twoParameters, typeof(int))

    firstAmbiguous := SourceCallPublicInstance(owner, "Ambiguous", intParameters, typeof(int))

    secondAmbiguous := SourceCallPublicInstance(owner, "Ambiguous", intParameters, typeof(string))

    staticInt := SourceCallPublicStatic(owner, "StaticPick", intParameters, typeof(int))

    staticString := SourceCallPublicStatic(owner, "StaticPick", stringParameters, typeof(string))

    SourceCallPublicStatic(owner, "StaticAmbiguous", intParameters, typeof(int))

    SourceCallPublicStatic(owner, "StaticAmbiguous", intParameters, typeof(string))

    definitions := SourceCallDefinitions(owner)
    ownerType: Type = owner.Builder

    selectedInt := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "Pick", intParameters, definitions)

    assert selectedInt.Status == ColumnarSourceDirectCallStatus.Selected
    assert selectedInt.Method != null
    assert selectedInt.ReturnType == typeof(int)

    selectedString := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "Pick", stringParameters, definitions)

    assert selectedString.Status == ColumnarSourceDirectCallStatus.Selected
    assert selectedString.Method != null
    assert selectedString.ReturnType == typeof(string)

    boolParameters := new Type[](1)
    boolParameters[0] = typeof(bool)
    badType := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "Pick", boolParameters, definitions)

    assert badType.Status == ColumnarSourceDirectCallStatus.Rejected

    noParameters := new Type[](0)
    badArity := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "Pair", noParameters, definitions)

    assert badArity.Status == ColumnarSourceDirectCallStatus.Rejected

    ambiguous := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "Ambiguous", intParameters, definitions)

    assert ambiguous.Status == ColumnarSourceDirectCallStatus.Rejected
    assert ambiguous.Method == null
    assert firstAmbiguous.ReturnType != secondAmbiguous.ReturnType

    selectedStaticInt := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "StaticPick", intParameters, definitions)

    assert selectedStaticInt.Status == ColumnarSourceDirectCallStatus.Selected
    assert selectedStaticInt.Method != null
    assert selectedStaticInt.ReturnType == staticInt.ReturnType

    selectedStaticString := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "StaticPick", stringParameters, definitions)

    assert selectedStaticString.Status == ColumnarSourceDirectCallStatus.Selected
    assert selectedStaticString.Method != null
    assert selectedStaticString.ReturnType == staticString.ReturnType

    staticAmbiguous := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "StaticAmbiguous", intParameters, definitions)

    assert staticAmbiguous.Status == ColumnarSourceDirectCallStatus.Rejected
}

test "source direct-call resolver limits excluded overload competition to live static and instance arities" {
    owner := SourceCallDefinition("SourceCallExcludedArityOwner", true)
    ownerType: Type = owner.Builder
    actualTypes := new Type[](1)
    actualTypes[0] = typeof(int)
    widenedTypes := new Type[](1)
    widenedTypes[0] = typeof(long)
    twoIntTypes := new Type[](2)
    twoIntTypes[0] = typeof(int)
    twoIntTypes[1] = typeof(int)

    paramsOutsideTypes := new Type[](3)
    paramsOutsideTypes[0] = typeof(int)
    paramsOutsideTypes[1] = typeof(int)
    paramsOutsideTypes[2] = typeof(int[])
    paramsOutsideKinds := new int[](3)
    paramsOutsideKinds[2] = 3

    paramsLiveTypes := new Type[](2)
    paramsLiveTypes[0] = typeof(int)
    paramsLiveTypes[1] = typeof(int[])
    paramsLiveKinds := new int[](2)
    paramsLiveKinds[1] = 3

    instanceWrongGenericFixed := SourceCallPublicInstance(owner, "InstanceWrongGeneric", widenedTypes, typeof(long))

    instanceWrongGeneric := SourceCallPublicInstance(owner, "InstanceWrongGeneric", twoIntTypes, typeof(int))

    SourceCallMakeGeneric(instanceWrongGeneric.Builder)
    instanceWrongParamsFixed := SourceCallPublicInstance(owner, "InstanceWrongParams", widenedTypes, typeof(long))

    _instanceWrongParams := SourceCallDefineInstance(owner, "InstanceWrongParams", paramsOutsideTypes, paramsOutsideKinds, typeof(int), (MethodAttributes)6)

    _instanceLiveGenericFixed := SourceCallPublicInstance(owner, "InstanceLiveGeneric", widenedTypes, typeof(long))

    instanceLiveGeneric := SourceCallPublicInstance(owner, "InstanceLiveGeneric", actualTypes, typeof(int))

    SourceCallMakeGeneric(instanceLiveGeneric.Builder)
    _instanceLiveParamsFixed := SourceCallPublicInstance(owner, "InstanceLiveParams", widenedTypes, typeof(long))

    _instanceLiveParams := SourceCallDefineInstance(owner, "InstanceLiveParams", paramsLiveTypes, paramsLiveKinds, typeof(int), (MethodAttributes)6)

    instanceExactFixed := SourceCallPublicInstance(owner, "InstanceExactMixed", actualTypes, typeof(int))

    instanceExactGeneric := SourceCallPublicInstance(owner, "InstanceExactMixed", actualTypes, typeof(string))

    SourceCallMakeGeneric(instanceExactGeneric.Builder)
    _instanceExactParams := SourceCallDefineInstance(owner, "InstanceExactMixed", paramsLiveTypes, paramsLiveKinds, typeof(bool), (MethodAttributes)6)

    staticWrongGenericFixed := SourceCallPublicStatic(owner, "StaticWrongGeneric", widenedTypes, typeof(long))

    staticWrongGeneric := SourceCallPublicStatic(owner, "StaticWrongGeneric", twoIntTypes, typeof(int))

    SourceCallMakeGeneric(staticWrongGeneric.Builder)
    staticWrongParamsFixed := SourceCallPublicStatic(owner, "StaticWrongParams", widenedTypes, typeof(long))

    _staticWrongParams := SourceCallDefineStatic(owner, "StaticWrongParams", paramsOutsideTypes, paramsOutsideKinds, typeof(int), (MethodAttributes)22)

    _staticLiveGenericFixed := SourceCallPublicStatic(owner, "StaticLiveGeneric", widenedTypes, typeof(long))

    staticLiveGeneric := SourceCallPublicStatic(owner, "StaticLiveGeneric", actualTypes, typeof(int))

    SourceCallMakeGeneric(staticLiveGeneric.Builder)
    _staticLiveParamsFixed := SourceCallPublicStatic(owner, "StaticLiveParams", widenedTypes, typeof(long))

    _staticLiveParams := SourceCallDefineStatic(owner, "StaticLiveParams", paramsLiveTypes, paramsLiveKinds, typeof(int), (MethodAttributes)22)

    staticExactFixed := SourceCallPublicStatic(owner, "StaticExactMixed", actualTypes, typeof(int))

    staticExactGeneric := SourceCallPublicStatic(owner, "StaticExactMixed", actualTypes, typeof(string))

    SourceCallMakeGeneric(staticExactGeneric.Builder)
    _staticExactParams := SourceCallDefineStatic(owner, "StaticExactMixed", paramsLiveTypes, paramsLiveKinds, typeof(bool), (MethodAttributes)22)

    definitions := SourceCallDefinitions(owner)

    instanceWrongGenericSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "InstanceWrongGeneric", actualTypes, definitions)

    assert instanceWrongGenericSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert instanceWrongGenericSelection.Method != null
    assert instanceWrongGenericSelection.ReturnType == instanceWrongGenericFixed.ReturnType

    instanceWrongParamsSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "InstanceWrongParams", actualTypes, definitions)

    assert instanceWrongParamsSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert instanceWrongParamsSelection.Method != null
    assert instanceWrongParamsSelection.ReturnType == instanceWrongParamsFixed.ReturnType

    instanceLiveGenericSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "InstanceLiveGeneric", actualTypes, definitions)

    assert instanceLiveGenericSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert instanceLiveGenericSelection.Method == null

    instanceLiveParamsSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "InstanceLiveParams", actualTypes, definitions)

    assert instanceLiveParamsSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert instanceLiveParamsSelection.Method == null

    instanceExactSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(ownerType, "InstanceExactMixed", actualTypes, definitions)

    assert instanceExactSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert instanceExactSelection.Method != null
    assert instanceExactSelection.ReturnType == instanceExactFixed.ReturnType

    staticWrongGenericSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "StaticWrongGeneric", actualTypes, definitions)

    assert staticWrongGenericSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert staticWrongGenericSelection.Method != null
    assert staticWrongGenericSelection.ReturnType == staticWrongGenericFixed.ReturnType

    staticWrongParamsSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "StaticWrongParams", actualTypes, definitions)

    assert staticWrongParamsSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert staticWrongParamsSelection.Method != null
    assert staticWrongParamsSelection.ReturnType == staticWrongParamsFixed.ReturnType

    staticLiveGenericSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "StaticLiveGeneric", actualTypes, definitions)

    assert staticLiveGenericSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert staticLiveGenericSelection.Method == null

    staticLiveParamsSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "StaticLiveParams", actualTypes, definitions)

    assert staticLiveParamsSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert staticLiveParamsSelection.Method == null

    staticExactSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "StaticExactMixed", actualTypes, definitions)

    assert staticExactSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert staticExactSelection.Method != null
    assert staticExactSelection.ReturnType == staticExactFixed.ReturnType
}

test "source direct-call resolver preserves keyed source shadows before runtime owner lookup" {
    sourceMath := SourceCallDefinition("Math", true)
    sourceMathType: Type = sourceMath.Builder
    runtimeMathType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.Math")

    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    definitions := SourceCallDefinitions(sourceMath)

    // Type-identity classification is intentionally insufficient after a runtime owner has won.
    identityOnly := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(runtimeMathType, "Abs", oneInt, definitions)

    assert identityOnly.Status == ColumnarSourceDirectCallStatus.NotSourceType

    // The binding layer's keyed source-name classification is terminal even though this source
    // Math declaration has no Abs method and System.Math does.
    classified := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(sourceMath, sourceMathType, "Abs", oneInt)

    assert classified.Status == ColumnarSourceDirectCallStatus.Rejected
    assert classified.IsSourceType

    noSource := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(null, runtimeMathType, "Abs", oneInt)

    assert noSource.Status == ColumnarSourceDirectCallStatus.NotSourceType
}

test "source direct-call resolver admits safe builder-bound BCL interface upcasts and ambiguity" {
    element := SourceCallDefinition("SourceCallUpcastElement", true)
    owner := SourceCallDefinition("SourceCallUpcastOwner", true)
    elementType: Type = element.Builder
    ownerType: Type = owner.Builder
    typeArguments := new Type[](1)
    typeArguments[0] = elementType
    listType := typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(typeArguments)

    readOnlyListType := typeof(IReadOnlyList<int>).GetGenericTypeDefinition().MakeGenericType(typeArguments)

    enumerableType := typeof(IEnumerable<int>).GetGenericTypeDefinition().MakeGenericType(typeArguments)

    readOnlyParameters := new Type[](1)
    readOnlyParameters[0] = readOnlyListType
    enumerableParameters := new Type[](1)
    enumerableParameters[0] = enumerableType
    actualList := new Type[](1)
    actualList[0] = listType
    selectedMethod := SourceCallPublicStatic(owner, "Consume", readOnlyParameters, typeof(int))

    SourceCallPublicStatic(owner, "AmbiguousUpcast", readOnlyParameters, typeof(int))

    SourceCallPublicStatic(owner, "AmbiguousUpcast", enumerableParameters, typeof(string))

    definitions := SourceCallDefinitions(owner)

    selected := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "Consume", actualList, definitions)

    assert selected.Status == ColumnarSourceDirectCallStatus.Selected
    assert selected.Method != null
    assert selected.ParameterTypes[0] == readOnlyListType
    assert selected.ReturnType == selectedMethod.ReturnType

    ambiguous := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "AmbiguousUpcast", actualList, definitions)

    assert ambiguous.Status == ColumnarSourceDirectCallStatus.Rejected
    assert ambiguous.Method == null

    stringArguments := new Type[](1)
    stringArguments[0] = typeof(string)
    wrongActual := new Type[](1)
    wrongActual[0] = typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(stringArguments)

    rejected := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "Consume", wrongActual, definitions)

    assert rejected.Status == ColumnarSourceDirectCallStatus.Rejected
}

test "source direct-call resolver preserves instance and static inheritance hiding order" {
    baseDefinition := SourceCallDefinition("SourceCallBaseOwner", true)
    derivedDefinition := SourceCallDefinition("SourceCallDerivedOwner", true)
    derivedDefinition.BaseDef = baseDefinition
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    stringParameters := new Type[](1)
    stringParameters[0] = typeof(string)
    noParameters := new Type[](0)

    _inheritedInstance := SourceCallPublicInstance(baseDefinition, "Inherited", intParameters, typeof(int))

    baseOnly := SourceCallPublicInstance(baseDefinition, "BaseOnly", noParameters, typeof(bool))

    SourceCallPublicInstance(derivedDefinition, "Inherited", stringParameters, typeof(string))

    _inheritedStatic := SourceCallPublicStatic(baseDefinition, "Build", intParameters, typeof(int))

    SourceCallPublicStatic(derivedDefinition, "Build", noParameters, typeof(string))

    derivedType: Type = derivedDefinition.Builder
    baseType: Type = baseDefinition.Builder
    assert ColumnarSourceDirectCallResolver.HasInstanceDeclarationAtArity(derivedDefinition, "Inherited", 1)

    assert !ColumnarSourceDirectCallResolver.HasInstanceDeclarationAtArity(derivedDefinition, "Inherited", 0)

    assert ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(derivedDefinition, "Build", 0)

    assert ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(derivedDefinition, "Build", 1)

    assert !ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(derivedDefinition, "Missing", 1)

    inheritedBaseInstance := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(derivedDefinition, derivedType, "BaseOnly", noParameters)

    assert inheritedBaseInstance.Status == ColumnarSourceDirectCallStatus.Selected
    assert inheritedBaseInstance.Method != null
    assert inheritedBaseInstance.DeclaringType == baseType
    assert inheritedBaseInstance.ReturnType == baseOnly.ReturnType

    instanceHidden := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(derivedDefinition, derivedType, "Inherited", intParameters)

    assert instanceHidden.Status == ColumnarSourceDirectCallStatus.Rejected
    assert instanceHidden.Method == null

    inheritedFromBase := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(derivedDefinition, derivedType, "Inherited", stringParameters)

    assert inheritedFromBase.Status == ColumnarSourceDirectCallStatus.Selected
    assert inheritedFromBase.DeclaringType == derivedType
    assert inheritedFromBase.ReturnType == typeof(string)
    assert inheritedFromBase.Method != null

    staticWrongArityDoesNotHide := ColumnarSourceDirectCallResolver.ResolveImplicitStatic(derivedDefinition, derivedType, "Build", intParameters)

    assert staticWrongArityDoesNotHide.Status == ColumnarSourceDirectCallStatus.Selected
    assert staticWrongArityDoesNotHide.Method != null
    assert staticWrongArityDoesNotHide.DeclaringType == baseType

    SourceCallPublicStatic(derivedDefinition, "Blocked", stringParameters, typeof(string))

    SourceCallPublicStatic(baseDefinition, "Blocked", intParameters, typeof(int))

    staticSameArityHides := ColumnarSourceDirectCallResolver.ResolveImplicitStatic(derivedDefinition, derivedType, "Blocked", intParameters)

    assert staticSameArityHides.Status == ColumnarSourceDirectCallStatus.Rejected
}

test "source direct-call resolver keeps invocable excluded derived shapes terminal before base fixed methods" {
    baseDefinition := SourceCallDefinition("SourceCallExcludedHierarchyBase", true)
    derivedDefinition := SourceCallDefinition("SourceCallExcludedHierarchyDerived", true)
    derivedDefinition.BaseDef = baseDefinition

    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    twoInts := new Type[](2)
    twoInts[0] = typeof(int)
    twoInts[1] = typeof(int)
    paramsTypes := new Type[](1)
    paramsTypes[0] = typeof(int[])
    paramsKinds := new int[](1)
    paramsKinds[0] = 3

    _baseInstanceParams := SourceCallPublicInstance(baseDefinition, "ExpandInstance", twoInts, typeof(int))

    derivedInstanceParams := SourceCallDefineInstance(derivedDefinition, "ExpandInstance", paramsTypes, paramsKinds, typeof(string), (MethodAttributes)6)

    _baseStaticParams := SourceCallPublicStatic(baseDefinition, "ExpandStatic", twoInts, typeof(int))

    derivedStaticParams := SourceCallDefineStatic(derivedDefinition, "ExpandStatic", paramsTypes, paramsKinds, typeof(string), (MethodAttributes)22)

    _baseInstanceVarArgs := SourceCallPublicInstance(baseDefinition, "VariableInstance", oneInt, typeof(int))

    derivedInstanceVarArgs := SourceCallDefineVarArgsInstance(derivedDefinition, "VariableInstance", typeof(string))

    _baseStaticVarArgs := SourceCallPublicStatic(baseDefinition, "VariableStatic", oneInt, typeof(int))

    derivedStaticVarArgs := SourceCallDefineVarArgsStatic(derivedDefinition, "VariableStatic", typeof(string))

    derivedType: Type = derivedDefinition.Builder
    assert ColumnarSourceDirectCallResolver.ExcludedInstanceDefinitionCanOwnArity(derivedInstanceParams, twoInts.Length)

    assert ColumnarSourceDirectCallResolver.ExcludedStaticDefinitionCanOwnArity(derivedStaticParams, twoInts.Length)

    assert ColumnarSourceDirectCallResolver.ExcludedInstanceDefinitionCanOwnArity(derivedInstanceVarArgs, oneInt.Length)

    assert ColumnarSourceDirectCallResolver.ExcludedStaticDefinitionCanOwnArity(derivedStaticVarArgs, oneInt.Length)

    instanceParams := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(derivedDefinition, derivedType, "ExpandInstance", twoInts)

    assert instanceParams.Status == ColumnarSourceDirectCallStatus.Rejected
    assert instanceParams.Method == null

    staticParams := ColumnarSourceDirectCallResolver.ResolveImplicitStatic(derivedDefinition, derivedType, "ExpandStatic", twoInts)

    assert staticParams.Status == ColumnarSourceDirectCallStatus.Rejected
    assert staticParams.Method == null

    instanceVarArgs := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(derivedDefinition, derivedType, "VariableInstance", oneInt)

    assert instanceVarArgs.Status == ColumnarSourceDirectCallStatus.Rejected
    assert instanceVarArgs.Method == null

    staticVarArgs := ColumnarSourceDirectCallResolver.ResolveImplicitStatic(derivedDefinition, derivedType, "VariableStatic", oneInt)

    assert staticVarArgs.Status == ColumnarSourceDirectCallStatus.Rejected
    assert staticVarArgs.Method == null
}

test "source direct-call resolver keeps excluded hierarchy competition arity aware and preserves exact fixed winners" {
    baseDefinition := SourceCallDefinition("SourceCallExcludedCompetitionBase", true)
    derivedDefinition := SourceCallDefinition("SourceCallExcludedCompetitionDerived", true)
    derivedDefinition.BaseDef = baseDefinition

    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    twoInts := new Type[](2)
    twoInts[0] = typeof(int)
    twoInts[1] = typeof(int)
    expandingParamsTypes := new Type[](1)
    expandingParamsTypes[0] = typeof(int[])
    expandingParamsKinds := new int[](1)
    expandingParamsKinds[0] = 3
    outsideParamsTypes := new Type[](3)
    outsideParamsTypes[0] = typeof(int)
    outsideParamsTypes[1] = typeof(int)
    outsideParamsTypes[2] = typeof(int[])
    outsideParamsKinds := new int[](3)
    outsideParamsKinds[2] = 3

    baseExactInstance := SourceCallPublicInstance(baseDefinition, "ExactInstance", twoInts, typeof(bool))

    derivedExactInstance := SourceCallPublicInstance(derivedDefinition, "ExactInstance", twoInts, typeof(int))

    _derivedExactInstanceParams := SourceCallDefineInstance(derivedDefinition, "ExactInstance", expandingParamsTypes, expandingParamsKinds, typeof(string), (MethodAttributes)6)

    baseExactStatic := SourceCallPublicStatic(baseDefinition, "ExactStatic", twoInts, typeof(bool))

    derivedExactStatic := SourceCallPublicStatic(derivedDefinition, "ExactStatic", twoInts, typeof(int))

    _derivedExactStaticParams := SourceCallDefineStatic(derivedDefinition, "ExactStatic", expandingParamsTypes, expandingParamsKinds, typeof(string), (MethodAttributes)22)

    baseOutsideInstance := SourceCallPublicInstance(baseDefinition, "OutsideInstance", oneInt, typeof(int))

    derivedOutsideInstance := SourceCallDefineInstance(derivedDefinition, "OutsideInstance", outsideParamsTypes, outsideParamsKinds, typeof(string), (MethodAttributes)6)

    baseOutsideStatic := SourceCallPublicStatic(baseDefinition, "OutsideStatic", oneInt, typeof(int))

    derivedOutsideStatic := SourceCallDefineStatic(derivedDefinition, "OutsideStatic", outsideParamsTypes, outsideParamsKinds, typeof(string), (MethodAttributes)22)

    derivedType: Type = derivedDefinition.Builder
    baseType: Type = baseDefinition.Builder

    assert !ColumnarSourceDirectCallResolver.ExcludedInstanceDefinitionCanOwnArity(derivedOutsideInstance, oneInt.Length)

    assert !ColumnarSourceDirectCallResolver.ExcludedStaticDefinitionCanOwnArity(derivedOutsideStatic, oneInt.Length)

    exactInstance := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(derivedDefinition, derivedType, "ExactInstance", twoInts)

    assert exactInstance.Status == ColumnarSourceDirectCallStatus.Selected
    assert exactInstance.Method != null
    assert exactInstance.ReturnType == derivedExactInstance.ReturnType
    assert exactInstance.ReturnType != baseExactInstance.ReturnType
    assert exactInstance.DeclaringType == derivedType

    exactStatic := ColumnarSourceDirectCallResolver.ResolveImplicitStatic(derivedDefinition, derivedType, "ExactStatic", twoInts)

    assert exactStatic.Status == ColumnarSourceDirectCallStatus.Selected
    assert exactStatic.Method != null
    assert exactStatic.ReturnType == derivedExactStatic.ReturnType
    assert exactStatic.ReturnType != baseExactStatic.ReturnType
    assert exactStatic.DeclaringType == derivedType

    outsideInstance := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(derivedDefinition, derivedType, "OutsideInstance", oneInt)

    assert outsideInstance.Status == ColumnarSourceDirectCallStatus.Selected
    assert outsideInstance.Method != null
    assert outsideInstance.ReturnType == baseOutsideInstance.ReturnType
    assert outsideInstance.DeclaringType == baseType

    outsideStatic := ColumnarSourceDirectCallResolver.ResolveImplicitStatic(derivedDefinition, derivedType, "OutsideStatic", oneInt)

    assert outsideStatic.Status == ColumnarSourceDirectCallStatus.Selected
    assert outsideStatic.Method != null
    assert outsideStatic.ReturnType == baseOutsideStatic.ReturnType
    assert outsideStatic.DeclaringType == baseType
}

test "source direct-call resolver walks inherited interface declarations in source order" {
    baseInterface := SourceCallInterfaceDefinition("SourceCallBaseInterface")
    derivedInterface := SourceCallInterfaceDefinition("SourceCallDerivedInterface")
    derivedInterface.InterfaceBases.Add(baseInterface)
    noParameters := new Type[](0)
    inherited := SourceCallDefineInstance(baseInterface, "Run", noParameters, new int[](0), typeof(int), (MethodAttributes)1478)

    derivedType: Type = derivedInterface.Builder
    baseType: Type = baseInterface.Builder

    assert ColumnarSourceDirectCallResolver.HasInstanceDeclarationAtArity(derivedInterface, "Run", 0)

    assert !ColumnarSourceDirectCallResolver.HasInstanceDeclarationAtArity(derivedInterface, "Run", 1)

    selection := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(derivedInterface, derivedType, "Run", noParameters)

    assert selection.Status == ColumnarSourceDirectCallStatus.Selected
    assert selection.Method != null
    assert selection.DeclaringType == baseType
    assert selection.IsAbstract
    assert inherited.ReturnType == typeof(int)
}

test "source direct-call resolver emits call facts for values and callvirt facts for abstract interfaces" {
    valueDefinition := SourceCallDefinition("SourceCallValueOwner", false)
    noParameters := new Type[](0)
    _valueMethod := SourceCallPublicInstance(valueDefinition, "Value", noParameters, typeof(int))

    SourceCallDefineInstance(valueDefinition, "AbstractValue", noParameters, new int[](0), typeof(int), (MethodAttributes)1478)

    SourceCallDefineStatic(valueDefinition, "AbstractStatic", noParameters, new int[](0), typeof(int), (MethodAttributes)1494)

    valueType: Type = valueDefinition.Builder

    valueSelection := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(valueDefinition, valueType, "Value", noParameters)

    assert valueType.get_IsValueType()
    assert valueSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert valueSelection.Method != null
    assert valueSelection.Dispatch == ColumnarSourceDirectCallDispatch.Call
    assert !valueSelection.ReceiverIsReference

    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveImplicitInstance(valueDefinition, valueType, "AbstractValue", noParameters)
    }

    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveImplicitStatic(valueDefinition, valueType, "AbstractStatic", noParameters)
    }

    interfaceDefinition := SourceCallInterfaceDefinition("SourceCallAbstractInterface")

    _abstractMethod := SourceCallDefineInstance(interfaceDefinition, "Run", noParameters, new int[](0), typeof(int), (MethodAttributes)1478)

    SourceCallDefineStatic(interfaceDefinition, "StaticAbstract", noParameters, new int[](0), typeof(int), (MethodAttributes)1494)

    interfaceType: Type = interfaceDefinition.Builder
    abstractSelection := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(interfaceDefinition, interfaceType, "Run", noParameters)

    assert abstractSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert abstractSelection.Method != null
    assert abstractSelection.Dispatch == ColumnarSourceDirectCallDispatch.CallVirtual
    assert abstractSelection.IsAbstract

    staticAbstract := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(interfaceDefinition, interfaceType, "StaticAbstract", noParameters)

    assert staticAbstract.Status == ColumnarSourceDirectCallStatus.Rejected
}

test "source direct-call resolver closes source generic signatures and exact handles" {
    genericDefinition := SourceCallGenericDefinition("SourceCallGenericOwner")

    genericOwnerType: Type = genericDefinition.Builder
    genericArguments := genericOwnerType.GetGenericArguments()
    assert genericArguments.Length == 1
    typeParameter := genericArguments[0]
    oneParameter := new Type[](1)
    oneParameter[0] = typeParameter
    instance := SourceCallPublicInstance(genericDefinition, "Echo", oneParameter, typeParameter)

    _staticMethod := SourceCallPublicStatic(genericDefinition, "Keep", oneParameter, typeParameter)

    openSelection := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(genericDefinition, genericOwnerType, "Echo", oneParameter)

    assert openSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert openSelection.Method != null
    assert openSelection.ParameterTypes[0] == typeParameter
    assert openSelection.ReturnType == typeParameter

    closedArguments := new Type[](1)
    closedArguments[0] = typeof(int)
    closedType := genericOwnerType.MakeGenericType(closedArguments)
    closedParameters := new Type[](1)
    closedParameters[0] = typeof(int)
    definitions := SourceCallDefinitions(genericDefinition)
    closedSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(closedType, "Echo", closedParameters, definitions)

    assert closedSelection.Status == ColumnarSourceDirectCallStatus.Selected
    assert closedSelection.Method != null
    assert closedSelection.DeclaringType == closedType
    assert closedSelection.ReceiverType == closedType
    assert closedSelection.ParameterTypes[0] == typeof(int)
    assert closedSelection.ReturnType == typeof(int)
    closedInstanceMethod := closedSelection.Method
    if closedInstanceMethod == null {
        throw new InvalidOperationException("The closed source instance selection lost its exact method handle.")
    }

    assert closedInstanceMethod.get_DeclaringType() == closedType
    assert closedInstanceMethod.get_Name() == "Echo"
    assert !closedInstanceMethod.get_IsStatic()

    closedStatic := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(closedType, "Keep", closedParameters, definitions)

    assert closedStatic.Status == ColumnarSourceDirectCallStatus.Selected
    assert closedStatic.Method != null
    assert closedStatic.DeclaringType == closedType
    assert closedStatic.ParameterTypes[0] == typeof(int)
    assert closedStatic.ReturnType == typeof(int)
    closedStaticMethod := closedStatic.Method
    if closedStaticMethod == null {
        throw new InvalidOperationException("The closed source static selection lost its exact method handle.")
    }

    assert closedStaticMethod.get_DeclaringType() == closedType
    assert closedStaticMethod.get_Name() == "Keep"
    assert closedStaticMethod.get_IsStatic()

    wrongClosedType := new Type[](1)
    wrongClosedType[0] = typeof(string)
    rejected := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(closedType, "Echo", wrongClosedType, definitions)

    assert rejected.Status == ColumnarSourceDirectCallStatus.Rejected
}

test "source direct-call resolver rejects inaccessible and unsupported declaration forms" {
    owner := SourceCallDefinition("SourceCallExcludedOwner", true)
    ownerType: Type = owner.Builder
    noParameters := new Type[](0)
    _privateMethod := SourceCallDefineInstance(owner, "Private", noParameters, new int[](0), typeof(int), (MethodAttributes)1)

    paramsTypes := new Type[](1)
    paramsTypes[0] = typeof(int[])
    paramsKinds := new int[](1)
    paramsKinds[0] = 3
    paramsMethod := SourceCallDefineInstance(owner, "Params", paramsTypes, paramsKinds, typeof(int), (MethodAttributes)6)

    refTypes := new Type[](1)
    refTypes[0] = InstanceByRefType("RuntimeValue")
    refKinds := new int[](1)
    refKinds[0] = 1
    refMethod := SourceCallDefineInstance(owner, "Ref", refTypes, refKinds, typeof(int), (MethodAttributes)6)

    outKinds := new int[](1)
    outKinds[0] = 2
    outMethod := SourceCallDefineInstance(owner, "Out", refTypes, outKinds, typeof(int), (MethodAttributes)6)

    privateStatic := SourceCallDefineStatic(owner, "PrivateStatic", noParameters, new int[](0), typeof(int), (MethodAttributes)17)

    staticParams := SourceCallDefineStatic(owner, "StaticParams", paramsTypes, paramsKinds, typeof(int), (MethodAttributes)22)

    genericMethod := SourceCallPublicStatic(owner, "Generic", noParameters, typeof(int))

    SourceCallMakeGeneric(genericMethod.Builder)
    varargsMethod := SourceCallDefineVarArgsStatic(owner, "VarArgs", typeof(int))

    thisTypes := new Type[](1)
    thisTypes[0] = ownerType
    thisKinds := new int[](1)
    thisKinds[0] = 4
    extensionMethod := SourceCallDefineStatic(owner, "Extension", thisTypes, thisKinds, typeof(int), (MethodAttributes)22)

    definitions := SourceCallDefinitions(owner)

    assert ColumnarSourceDirectCallResolver.HasInstanceDeclarationAtArity(owner, "Private", 0)

    assert ColumnarSourceDirectCallResolver.HasInstanceDeclarationAtArity(owner, "Params", 1)

    assert ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(owner, "Generic", 0)

    assert ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(owner, "VarArgs", 0)

    assert ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(owner, "PrivateStatic", 0)

    assert ColumnarSourceDirectCallResolver.HasExcludedInstanceDeclaration(owner, "Params")

    assert ColumnarSourceDirectCallResolver.HasExcludedInstanceDeclaration(owner, "Ref")

    assert ColumnarSourceDirectCallResolver.HasExcludedInstanceDeclaration(owner, "Out")

    assert !ColumnarSourceDirectCallResolver.HasExcludedInstanceDeclaration(owner, "Private")

    assert ColumnarSourceDirectCallResolver.HasExcludedStaticDeclaration(owner, "StaticParams")

    assert ColumnarSourceDirectCallResolver.HasExcludedStaticDeclaration(owner, "Generic")

    assert ColumnarSourceDirectCallResolver.HasExcludedStaticDeclaration(owner, "VarArgs")

    assert ColumnarSourceDirectCallResolver.HasExcludedStaticDeclaration(owner, "Extension")

    assert !ColumnarSourceDirectCallResolver.HasExcludedStaticDeclaration(owner, "PrivateStatic")

    assert !ColumnarSourceDirectCallResolver.IsExcludedInstanceDefinition(_privateMethod)

    assert ColumnarSourceDirectCallResolver.IsExcludedInstanceDefinition(paramsMethod)

    assert ColumnarSourceDirectCallResolver.IsExcludedInstanceDefinition(refMethod)

    assert ColumnarSourceDirectCallResolver.IsExcludedInstanceDefinition(outMethod)

    assert !ColumnarSourceDirectCallResolver.IsExcludedStaticDefinition(privateStatic)

    assert ColumnarSourceDirectCallResolver.IsExcludedStaticDefinition(staticParams)

    assert ColumnarSourceDirectCallResolver.IsExcludedStaticDefinition(genericMethod)

    assert ColumnarSourceDirectCallResolver.IsExcludedStaticDefinition(varargsMethod)

    assert ColumnarSourceDirectCallResolver.IsExcludedStaticDefinition(extensionMethod)

    privateSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(owner.Builder, "Private", noParameters, definitions)

    assert privateSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert privateSelection.Method == null

    paramsSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(owner.Builder, "Params", paramsTypes, definitions)

    assert paramsSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert paramsMethod.ParamModifierKinds[0] == 3

    refSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(owner.Builder, "Ref", refTypes, definitions)

    assert refSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert refMethod.ParamModifierKinds[0] == 1

    outSelection := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(owner.Builder, "Out", refTypes, definitions)

    assert outSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert outMethod.ParamModifierKinds[0] == 2

    privateStaticSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "PrivateStatic", noParameters, definitions)

    assert privateStaticSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert privateStatic.ReturnType == typeof(int)

    staticParamsSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "StaticParams", paramsTypes, definitions)

    assert staticParamsSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert staticParams.ParamModifierKinds[0] == 3

    genericSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "Generic", noParameters, definitions)

    assert genericSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    genericMethodInfo: MethodInfo = genericMethod.Builder
    assert genericMethodInfo.get_IsGenericMethod()

    varargsSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "VarArgs", noParameters, definitions)

    assert varargsSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    varargsMethodInfo: MethodInfo = varargsMethod.Builder
    assert ((int)varargsMethodInfo.get_CallingConvention() & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0

    extensionSelection := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "Extension", thisTypes, definitions)

    assert extensionSelection.Status == ColumnarSourceDirectCallStatus.Rejected
    assert extensionMethod.ParamModifierKinds[0] == 4
}

test "source direct-call resolver validates malformed exact facts and hierarchy cycles" {
    owner := SourceCallDefinition("SourceCallMalformedOwner", true)
    foreign := SourceCallDefinition("SourceCallForeignOwner", true)
    noParameters := new Type[](0)
    foreignMethod := SourceCallPublicInstance(foreign, "Broken", noParameters, typeof(int))

    SourceCallAddInstanceFact(owner, "Broken", foreignMethod)
    definitions := SourceCallDefinitions(owner)

    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveExplicitInstance(owner.Builder, "Broken", noParameters, definitions)
    }

    wrongNameBuilder := owner.Builder.DefineMethod("ActualName", (MethodAttributes)6, typeof(int), noParameters)

    wrongNameFact := new ColumnarInstanceMethodDef(wrongNameBuilder, noParameters, typeof(int))

    SourceCallAddInstanceFact(owner, "AliasName", wrongNameFact)
    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveExplicitInstance(owner.Builder, "AliasName", noParameters, definitions)
    }

    staticOwner := SourceCallDefinition("SourceCallStaticMalformedOwner", true)
    instanceBuilder := staticOwner.Builder.DefineMethod("WrongStaticMap", (MethodAttributes)6, typeof(int), noParameters)

    wrongStatic := new ColumnarStaticMethodDef(instanceBuilder, noParameters, new int[](0), typeof(int))

    SourceCallAddStaticFact(staticOwner, "WrongStaticMap", wrongStatic)
    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveImplicitStatic(staticOwner, staticOwner.Builder, "WrongStaticMap", noParameters)
    }

    cycleA := SourceCallDefinition("SourceCallCycleA", true)
    cycleB := SourceCallDefinition("SourceCallCycleB", true)
    cycleA.BaseDef = cycleB
    cycleB.BaseDef = cycleA
    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveImplicitInstance(cycleA, cycleA.Builder, "Missing", noParameters)
    }

    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    method := owner.Builder.DefineMethod("ModifierLength", (MethodAttributes)6, typeof(int), parameterTypes)

    badModifiers := new int[](2)
    assert throws InvalidOperationException {
        SourceCallConstructInstanceFact(method, parameterTypes, badModifiers, typeof(int))
    }
}

test "source direct-call resolver selection is repeatable and does not mutate declaration facts" {
    owner := SourceCallDefinition("SourceCallPureOwner", true)
    parameters := new Type[](1)
    parameters[0] = typeof(int)
    method := SourceCallPublicInstance(owner, "Stable", parameters, typeof(int))

    definitions := SourceCallDefinitions(owner)
    originalMethodCount := owner.MethodOverloads.Count
    originalOverloadCount := owner.MethodOverloads["Stable"].Count
    originalParameter := method.ParamTypes[0]

    first := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(owner.Builder, "Stable", parameters, definitions)

    second := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(owner.Builder, "Stable", parameters, definitions)

    assert first.Status == ColumnarSourceDirectCallStatus.Selected
    assert second.Status == ColumnarSourceDirectCallStatus.Selected
    assert first.Method != null
    assert second.Method != null
    assert first.Dispatch == second.Dispatch
    assert first.ReturnType == second.ReturnType
    assert first.ParameterTypes.Length == 1
    assert second.ParameterTypes.Length == 1
    assert first.ParameterTypes[0] == second.ParameterTypes[0]
    assert owner.MethodOverloads.Count == originalMethodCount
    assert owner.MethodOverloads["Stable"].Count == originalOverloadCount
    assert method.ParamTypes[0] == originalParameter
}
