namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Collections.Generic
import System.Reflection

// The N# type is the sole assembly-emission owner. Keep this lookup exact so the production
// witnesses cannot silently fall back to the deleted Compiler-assembly implementation.
func ColumnarIlEmitterType(): Type {
    owner := Type.GetType(
        "NSharpLang.Compiler.Columnar.ColumnarIlEmitter, NSharpLang.Compiler.Core"
    )
    if owner == null {
        throw new InvalidOperationException("Missing N# ColumnarIlEmitter")
    }
    return owner
}

func ColumnarIlEmitterPublicMethod(methodName: string, parameterCount: int): MethodInfo {
    methods := ColumnarIlEmitterType().GetMethods(
        BindingFlags.Static | BindingFlags.Public | BindingFlags.DeclaredOnly
    )
    for method in methods {
        if method.get_Name() == methodName && method.GetParameters().Length == parameterCount {
            return method
        }
    }
    throw new InvalidOperationException("Missing public N# ColumnarIlEmitter method " + methodName)
}

func ColumnarIlEmitterPrivateMethod(methodName: string, parameterCount: int): MethodInfo {
    methods := ColumnarIlEmitterType().GetMethods(
        BindingFlags.Static | BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
    )
    for method in methods {
        if method.get_Name() == methodName && method.GetParameters().Length == parameterCount {
            return method
        }
    }
    throw new InvalidOperationException("Missing private N# ColumnarIlEmitter method " + methodName)
}

func ColumnarIlEmitterPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func ColumnarIlEmitterExceptionTypeName(error: Exception): string {
    boxed: object = error
    errorType := boxed.GetType()
    fullName := errorType.get_FullName()
    if fullName == null {
        return errorType.get_Name()
    }
    return fullName
}

func ColumnarIlEmitterBootstrapType(name: string): Type {
    owner := Type.GetType(
        "NSharpLang.Compiler.Columnar." + name + ", NSharpLang.Compiler.Core"
    )
    if owner == null {
        throw new InvalidOperationException("Missing compiler-core type " + name)
    }
    return owner
}

func ColumnarIlEmitterEmptyList(elementTypeName: string): object {
    definition := typeof(List<int>).GetGenericTypeDefinition()
    typeArguments := new Type[](1)
    typeArguments[0] = ColumnarIlEmitterBootstrapType(elementTypeName)
    listType := definition.MakeGenericType(typeArguments)
    constructor := listType.GetConstructor(new Type[](0))
    if constructor == null {
        throw new InvalidOperationException("Missing empty-list constructor for " + elementTypeName)
    }
    list := constructor.Invoke(new object?[](0))
    if list == null {
        throw new InvalidOperationException("Could not create empty list for " + elementTypeName)
    }
    return list
}

func ColumnarIlEmitterEmptyProgram(): object {
    programType := ColumnarIlEmitterBootstrapType("ColumnarProgramInput")
    factories := programType.GetMethods(
        BindingFlags.Static | BindingFlags.Public | BindingFlags.DeclaredOnly
    )
    factory: MethodInfo? = null
    for candidate in factories {
        if candidate.get_Name() == "CreateSingleSource" && candidate.GetParameters().Length == 7 {
            factory = candidate
        }
    }
    if factory == null {
        throw new InvalidOperationException("Missing ColumnarProgramInput.CreateSingleSource")
    }

    arguments := new object?[](7)
    ColumnarIlEmitterPut(arguments, 0, "")
    ColumnarIlEmitterPut(arguments, 1, ColumnarIlEmitterEmptyList("ColumnarFunctionInput"))
    ColumnarIlEmitterPut(arguments, 2, ColumnarIlEmitterEmptyList("ColumnarEnumInput"))
    ColumnarIlEmitterPut(arguments, 3, ColumnarIlEmitterEmptyList("ColumnarStructInput"))
    ColumnarIlEmitterPut(arguments, 4, ColumnarIlEmitterEmptyList("ColumnarUnionInput"))
    ColumnarIlEmitterPut(arguments, 5, ColumnarIlEmitterEmptyList("ColumnarInterfaceInput"))
    ColumnarIlEmitterPut(arguments, 6, null)
    result := factory.Invoke(null, arguments)
    if result == null {
        throw new InvalidOperationException("ColumnarProgramInput.CreateSingleSource returned null")
    }
    return result
}

test "the N# columnar IL emitter owns its complete public and private metadata surface" {
    owner := ColumnarIlEmitterType()
    assert owner.get_IsPublic(), "the N# emitter must retain its public cross-assembly surface"
    assert owner.get_IsSealed(), "the N# emitter must retain sealed metadata"
    assert Object.ReferenceEquals(owner.get_Assembly(), ColumnarInputBuilderType().get_Assembly()),
        "the emitter and input builder must share the compiler-core assembly owner"
    assert Type.GetType("NSharpLang.Compiler.Columnar.ColumnarIlEmitter, Compiler") == null,
        "the deleted Compiler-assembly emitter must not remain as a second owner"

    publicConstructors := owner.GetConstructors(
        BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly
    )
    assert publicConstructors.Length == 0, "the emitter must not expose an instance constructor"
    privateConstructors := owner.GetConstructors(
        BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
    )
    assert privateConstructors.Length == 1, "the emitter must retain exactly one non-public constructor"
    assert privateConstructors[0].get_IsPrivate(), "the emitter constructor must remain private"

    publicMethods := owner.GetMethods(
        BindingFlags.Static | BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly
    )
    assert publicMethods.Length == 1, "only the assembly entry point may be public"
    entry := ColumnarIlEmitterPublicMethod("TryEmitColumnarAssembly", 7)
    assert entry.get_IsPublic()
    assert entry.get_IsStatic()
    assert entry.get_ReturnType() == typeof(bool)
    assert entry.get_DeclaringType() == owner

    parameters := entry.GetParameters()
    assert parameters[0].get_Name() == "assemblyName"
    assert parameters[0].get_ParameterType() == typeof(string)
    assert parameters[1].get_Name() == "typeName"
    assert parameters[1].get_ParameterType() == typeof(string)
    assert parameters[2].get_Name() == "program"
    assert parameters[2].get_ParameterType().get_FullName() == "NSharpLang.Compiler.Columnar.ColumnarProgramInput"
    assert Object.ReferenceEquals(parameters[2].get_ParameterType().get_Assembly(), owner.get_Assembly())
    assert parameters[3].get_Name() == "isExecutable"
    assert parameters[3].get_ParameterType() == typeof(bool)
    assert parameters[4].get_Name() == "assembly"
    assert parameters[4].get_IsOut()
    assert parameters[4].get_ParameterType().get_IsByRef()
    assert parameters[4].get_ParameterType().GetElementType() == typeof(byte[])
    assert parameters[5].get_Name() == "assemblyVersion"
    assert parameters[5].get_ParameterType() == typeof(Version)
    assert parameters[6].get_Name() == "referenceAssemblyPaths"
    assert parameters[6].get_ParameterType() == typeof(IReadOnlyList<string>)

    requiredIndex := 0
    while requiredIndex < 5 {
        assert !parameters[requiredIndex].get_IsOptional()
        assert !parameters[requiredIndex].get_HasDefaultValue()
        requiredIndex = requiredIndex + 1
    }
    assert parameters[5].get_IsOptional()
    assert parameters[5].get_HasDefaultValue()
    assert parameters[5].get_RawDefaultValue() == null
    assert parameters[6].get_IsOptional()
    assert parameters[6].get_HasDefaultValue()
    assert parameters[6].get_RawDefaultValue() == null

    iterator := ColumnarIlEmitterPrivateMethod("TryEmitIteratorStateMachine", 16)
    assert iterator.get_IsPrivate()
    assert iterator.get_IsStatic()
    initializer := ColumnarIlEmitterPrivateMethod("EmitSelectedInitializerStatements", 2)
    assert initializer.get_IsPrivate()
    assert !initializer.get_IsStatic()

    publicFields := owner.GetFields(
        BindingFlags.Static | BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly
    )
    assert publicFields.Length == 0, "emitter state must remain private"
}

test "the columnar IL emitter initializes the assembly output before an empty-program decline" {
    program := ColumnarIlEmitterEmptyProgram()

    sentinel := new byte[](1)
    sentinel[0] = 173
    sentinelObject: object = sentinel
    arguments := new object?[](7)
    ColumnarIlEmitterPut(arguments, 0, "EmptyProgramControl")
    ColumnarIlEmitterPut(arguments, 1, "Program")
    ColumnarIlEmitterPut(arguments, 2, program)
    ColumnarIlEmitterPut(arguments, 3, false)
    ColumnarIlEmitterPut(arguments, 4, sentinel)
    ColumnarIlEmitterPut(arguments, 5, null)
    ColumnarIlEmitterPut(arguments, 6, null)

    ColumnarInputBuilderTraceReset()
    emitted := Convert.ToBoolean(
        ColumnarIlEmitterPublicMethod("TryEmitColumnarAssembly", 7).Invoke(null, arguments)
    )
    snapshot := ColumnarInputBuilderTraceSnapshot()
    ColumnarInputBuilderTraceReset()

    assert !emitted, "an empty modeled program must decline assembly emission"
    image := arguments[4]
    if image == null {
        throw new InvalidOperationException("The empty-program decline did not initialize its out slot")
    }
    assert !Object.ReferenceEquals(image, sentinelObject), "the false return must overwrite the caller sentinel"
    assert Object.ReferenceEquals(image, EntryPointRealizationBclEmptyByteArray()),
        "the false return must expose the shared Array.Empty<byte>() instance"
    assert snapshot.Count == 1, "the empty program must record exactly one decline"
    traceRecord := ColumnarInputBuilderRequiredItem(snapshot, 0)
    assert ColumnarInputBuilderText(traceRecord, "SiteId") == "emit.program.empty", ColumnarInputBuilderText(traceRecord, "SiteId")
    assert ColumnarInputBuilderText(traceRecord, "Message") == "columnar program has no modeled declarations", ColumnarInputBuilderText(traceRecord, "Message")
}

// MethodInfo.Invoke does not copy a by-ref argument back when its target throws. This control pins
// that observable reflection boundary, the target exception, and the absence of a decline row. The
// entry IL review separately proves that the target assigned Array.Empty<byte>() before dereferencing
// its program argument.
test "reflection keeps the caller out sentinel when a null program throws from the columnar IL emitter" {
    sentinel := new byte[](1)
    sentinel[0] = 91
    sentinelObject: object = sentinel
    arguments := new object?[](7)
    ColumnarIlEmitterPut(arguments, 0, "NullProgramControl")
    ColumnarIlEmitterPut(arguments, 1, "Program")
    ColumnarIlEmitterPut(arguments, 2, null)
    ColumnarIlEmitterPut(arguments, 3, false)
    ColumnarIlEmitterPut(arguments, 4, sentinel)
    ColumnarIlEmitterPut(arguments, 5, null)
    ColumnarIlEmitterPut(arguments, 6, null)

    ColumnarInputBuilderTraceReset()
    failure: Exception? = null
    try {
        ignored := ColumnarIlEmitterPublicMethod("TryEmitColumnarAssembly", 7).Invoke(null, arguments)
        _ = ignored
    } catch error: Exception {
        failure = error
    }
    snapshot := ColumnarInputBuilderTraceSnapshot()
    ColumnarInputBuilderTraceReset()

    if failure == null {
        throw new InvalidOperationException("The null program did not fail the emitter entry point")
    }
    captured: Exception = failure
    assert ColumnarIlEmitterExceptionTypeName(captured) == "System.Reflection.TargetInvocationException",
        ColumnarIlEmitterExceptionTypeName(captured)
    innerBox: object? = captured.get_InnerException()
    inner := innerBox as Exception
    if inner == null {
        throw new InvalidOperationException("The emitter exception had no target exception")
    }
    assert ColumnarIlEmitterExceptionTypeName(inner) == "System.NullReferenceException",
        ColumnarIlEmitterExceptionTypeName(inner)
    assert Object.ReferenceEquals(arguments[4], sentinelObject),
        "MethodInfo.Invoke must not report a target out write when the target throws"
    assert snapshot.Count == 0, "a null-program exception must not record an ordinary decline"
}

func ColumnarIlEmitterRequiredRuntimeType(name: string): Type {
    resolved := Type.GetType(name)
    if resolved == null {
        throw new InvalidOperationException("Missing runtime type " + name)
    }
    return resolved
}

func ColumnarIlEmitterRequiredInvocation(method: MethodInfo, receiver: object?, arguments: object?[]): object {
    result := method.Invoke(receiver, arguments)
    if result == null {
        throw new InvalidOperationException("Reflection invocation unexpectedly returned null")
    }
    return result
}

func ColumnarIlEmitterRequiredConstruction(constructor: ConstructorInfo, arguments: object?[]): object {
    result := constructor.Invoke(arguments)
    if result == null {
        throw new InvalidOperationException("Reflection construction unexpectedly returned null")
    }
    return result
}

func ColumnarIlEmitterDynamicIdentityType(assemblyLabel: string, typeName: string): Type {
    assemblyBuilderType := ColumnarIlEmitterRequiredRuntimeType("System.Reflection.Emit.AssemblyBuilder")
    accessType := ColumnarIlEmitterRequiredRuntimeType("System.Reflection.Emit.AssemblyBuilderAccess")
    defineAssemblyTypes := new Type[](2)
    defineAssemblyTypes[0] = typeof(AssemblyName)
    defineAssemblyTypes[1] = accessType
    defineAssembly := assemblyBuilderType.GetMethod("DefineDynamicAssembly", defineAssemblyTypes)
    if defineAssembly == null {
        throw new InvalidOperationException("Missing AssemblyBuilder.DefineDynamicAssembly")
    }
    runField := accessType.GetField("Run")
    if runField == null {
        throw new InvalidOperationException("Missing AssemblyBuilderAccess.Run")
    }
    runAccess := runField.GetValue(null)
    if runAccess == null {
        throw new InvalidOperationException("AssemblyBuilderAccess.Run was null")
    }
    assemblyArguments := new object?[](2)
    ColumnarIlEmitterPut(assemblyArguments, 0, new AssemblyName(assemblyLabel))
    ColumnarIlEmitterPut(assemblyArguments, 1, runAccess)
    assemblyBuilder := ColumnarIlEmitterRequiredInvocation(defineAssembly, null, assemblyArguments)

    defineModuleTypes := new Type[](1)
    defineModuleTypes[0] = typeof(string)
    defineModule := assemblyBuilderType.GetMethod("DefineDynamicModule", defineModuleTypes)
    if defineModule == null {
        throw new InvalidOperationException("Missing AssemblyBuilder.DefineDynamicModule")
    }
    moduleArguments := new object?[](1)
    ColumnarIlEmitterPut(moduleArguments, 0, assemblyLabel + "Module")
    moduleBuilder := ColumnarIlEmitterRequiredInvocation(defineModule, assemblyBuilder, moduleArguments)

    moduleBuilderType := ColumnarIlEmitterRequiredRuntimeType("System.Reflection.Emit.ModuleBuilder")
    defineType := moduleBuilderType.GetMethod("DefineType", defineModuleTypes)
    if defineType == null {
        throw new InvalidOperationException("Missing ModuleBuilder.DefineType(string)")
    }
    typeArguments := new object?[](1)
    ColumnarIlEmitterPut(typeArguments, 0, typeName)
    dynamicType := ColumnarIlEmitterRequiredInvocation(defineType, moduleBuilder, typeArguments) as Type
    if dynamicType == null {
        throw new InvalidOperationException("ModuleBuilder.DefineType did not return a Type")
    }
    return dynamicType
}

func ColumnarIlEmitterEnumDefinition(enumType: Type, stringBacked: bool): object {
    definitionType := ColumnarIlEmitterBootstrapType("ColumnarEnumDef")
    constructorTypes := new Type[](4)
    constructorTypes[0] = typeof(Type)
    constructorTypes[1] = typeof(Dictionary<string, int>)
    constructorTypes[2] = typeof(Dictionary<string, string>)
    constructorTypes[3] = typeof(string)
    constructor := definitionType.GetConstructor(constructorTypes)
    if constructor == null {
        throw new InvalidOperationException("Missing ColumnarEnumDef constructor")
    }
    arguments := new object?[](4)
    ColumnarIlEmitterPut(arguments, 0, enumType)
    ColumnarIlEmitterPut(arguments, 1, new Dictionary<string, int>())
    if stringBacked {
        ColumnarIlEmitterPut(arguments, 2, new Dictionary<string, string>())
    }
    else {
        ColumnarIlEmitterPut(arguments, 2, null)
    }
    ColumnarIlEmitterPut(arguments, 3, "")
    return ColumnarIlEmitterRequiredConstruction(constructor, arguments)
}

func ColumnarIlEmitterEnumRegistry(rows: object[]): object {
    definitionType := ColumnarIlEmitterBootstrapType("ColumnarEnumDef")
    registryTypeArguments := new Type[](2)
    registryTypeArguments[0] = typeof(string)
    registryTypeArguments[1] = definitionType
    registryType := typeof(Dictionary<string, int>).GetGenericTypeDefinition().MakeGenericType(registryTypeArguments)
    constructor := registryType.GetConstructor(new Type[](0))
    if constructor == null {
        throw new InvalidOperationException("Missing enum-registry constructor")
    }
    registry := ColumnarIlEmitterRequiredConstruction(constructor, new object?[](0))
    addTypes := new Type[](2)
    addTypes[0] = typeof(string)
    addTypes[1] = definitionType
    add := registryType.GetMethod("Add", addTypes)
    if add == null {
        throw new InvalidOperationException("Missing enum-registry Add")
    }
    index := 0
    while index < rows.Length {
        arguments := new object?[](2)
        ColumnarIlEmitterPut(arguments, 0, "row" + index.ToString())
        ColumnarIlEmitterPut(arguments, 1, rows[index])
        ignored := add.Invoke(registry, arguments)
        _ = ignored
        index = index + 1
    }
    return registry
}

func ColumnarIlEmitterUninitializedWithEnumRegistry(registry: object): object {
    runtimeHelpers := ColumnarIlEmitterRequiredRuntimeType("System.Runtime.CompilerServices.RuntimeHelpers")
    argumentTypes := new Type[](1)
    argumentTypes[0] = typeof(Type)
    getUninitializedObject := runtimeHelpers.GetMethod("GetUninitializedObject", argumentTypes)
    if getUninitializedObject == null {
        throw new InvalidOperationException("Missing RuntimeHelpers.GetUninitializedObject")
    }
    arguments := new object?[](1)
    ColumnarIlEmitterPut(arguments, 0, ColumnarIlEmitterType())
    emitter := ColumnarIlEmitterRequiredInvocation(getUninitializedObject, null, arguments)
    registryField := ColumnarIlEmitterType().GetField(
        "_enumRegistry",
        BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
    )
    if registryField == null {
        throw new InvalidOperationException("Missing ColumnarIlEmitter._enumRegistry")
    }
    registryField.SetValue(emitter, registry)
    return emitter
}

func ColumnarIlEmitterIsKnownEnum(emitter: object, candidate: Type): bool {
    arguments := new object?[](1)
    ColumnarIlEmitterPut(arguments, 0, candidate)
    return Convert.ToBoolean(ColumnarIlEmitterPrivateMethod("IsKnownEnumType", 1).Invoke(emitter, arguments))
}

test "the private enum predicate traverses populated registry values by exact identity and excludes string-backed rows" {
    decoy := ColumnarIlEmitterDynamicIdentityType("EmitterEnumDecoyAssembly", "EmitterEnumDecoy")
    target := ColumnarIlEmitterDynamicIdentityType("EmitterEnumTargetAssembly", "SharedEmitterEnumIdentity")
    sameNamePeer := ColumnarIlEmitterDynamicIdentityType("EmitterEnumPeerAssembly", "SharedEmitterEnumIdentity")
    stringBacked := ColumnarIlEmitterDynamicIdentityType("EmitterStringEnumAssembly", "EmitterStringEnum")

    targetObject: object = target
    peerObject: object = sameNamePeer
    assert target.get_FullName() == sameNamePeer.get_FullName()
    assert !Object.ReferenceEquals(targetObject, peerObject)

    rows := new object[](3)
    rows[0] = ColumnarIlEmitterEnumDefinition(decoy, false)
    rows[1] = ColumnarIlEmitterEnumDefinition(target, false)
    rows[2] = ColumnarIlEmitterEnumDefinition(stringBacked, true)
    emitter := ColumnarIlEmitterUninitializedWithEnumRegistry(ColumnarIlEmitterEnumRegistry(rows))

    assert ColumnarIlEmitterIsKnownEnum(emitter, target), "the numeric hit must advance to the second populated registry row"
    assert !ColumnarIlEmitterIsKnownEnum(emitter, sameNamePeer), "equal names from distinct assemblies must not replace Type identity"
    assert !ColumnarIlEmitterIsKnownEnum(emitter, stringBacked), "a string-backed source enum is not a CLR enum"
    assert !ColumnarIlEmitterIsKnownEnum(emitter, typeof(object)), "an absent type must miss the populated registry"
}
