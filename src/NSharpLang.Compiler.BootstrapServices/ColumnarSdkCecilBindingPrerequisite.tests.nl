namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Runtime.InteropServices
import Microsoft.Build.Framework
import Mono.Cecil

func SmcRequiredType(valueType: Type?, description: string): Type {
    if valueType == null {
        throw new InvalidOperationException(description + " was not found.")
    }
    return valueType
}

func SmcBake(builder: TypeBuilder): Type {
    createType := ExecutorRequiredMethod(typeof(TypeBuilder), "CreateType", new Type[](0))
    baked := TypeOfRequiredInvocation(createType, builder, new object[](0)) as Type
    if baked == null {
        throw new InvalidOperationException("The foreign identity fixture did not bake.")
    }
    return baked
}

func SmcClosedEnumerable(elementType: Type): Type {
    arguments := new Type[](1)
    arguments[0] = elementType
    return typeof(IEnumerable<int>).GetGenericTypeDefinition().MakeGenericType(arguments)
}

func SmcEnumBuilder(fullName: string): Type {
    assemblyBuilderType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.AssemblyBuilder")
    assemblyBuilderAccessType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.AssemblyBuilderAccess")
    moduleBuilderType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.ModuleBuilder")
    typeAttributesType := TypeOfRequiredRuntimeType(typeof(AssemblyName), "System.Reflection.TypeAttributes")

    assemblyNameTypes := new Type[](1)
    assemblyNameTypes[0] = typeof(string)
    assemblyNameConstructor := ExecutorRequiredConstructor(typeof(AssemblyName), assemblyNameTypes)
    assemblyNameArguments := new object[](1)
    ExecutorSetObject(assemblyNameArguments, 0, "NSharpTests.ForeignEnumIdentity")
    assemblyName := TypeOfRequiredConstruction(assemblyNameConstructor, assemblyNameArguments)

    defineAssemblyTypes := new Type[](2)
    defineAssemblyTypes[0] = typeof(AssemblyName)
    defineAssemblyTypes[1] = assemblyBuilderAccessType
    defineAssembly := ExecutorRequiredMethod(assemblyBuilderType, "DefineDynamicAssembly", defineAssemblyTypes)
    defineAssemblyArguments := new object[](2)
    ExecutorSetObject(defineAssemblyArguments, 0, assemblyName)
    ExecutorSetObject(defineAssemblyArguments, 1, TypeOfRequiredStaticField(assemblyBuilderAccessType, "Run"))
    assemblyBuilder := TypeOfRequiredInvocation(defineAssembly, null, defineAssemblyArguments)

    defineModuleTypes := new Type[](1)
    defineModuleTypes[0] = typeof(string)
    defineModule := ExecutorRequiredMethod(assemblyBuilderType, "DefineDynamicModule", defineModuleTypes)
    defineModuleArguments := new object[](1)
    ExecutorSetObject(defineModuleArguments, 0, "NSharpTests.ForeignEnumIdentity")
    moduleBuilder := TypeOfRequiredInvocation(defineModule, assemblyBuilder, defineModuleArguments)

    defineEnumTypes := new Type[](3)
    defineEnumTypes[0] = typeof(string)
    defineEnumTypes[1] = typeAttributesType
    defineEnumTypes[2] = typeof(Type)
    defineEnum := ExecutorRequiredMethod(moduleBuilderType, "DefineEnum", defineEnumTypes)
    defineEnumArguments := new object[](3)
    ExecutorSetObject(defineEnumArguments, 0, fullName)
    ExecutorSetObject(defineEnumArguments, 1, TypeOfRequiredStaticField(typeAttributesType, "Public"))
    ExecutorSetObject(defineEnumArguments, 2, typeof(int))
    enumBuilder := TypeOfRequiredInvocation(defineEnum, moduleBuilder, defineEnumArguments) as Type
    if enumBuilder == null {
        throw new InvalidOperationException("The foreign EnumBuilder fixture was not created.")
    }
    return enumBuilder
}

func SmcMetadataContext(): MetadataLoadContext {
    runtimePaths := Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll")
    paths := new string[](runtimePaths.Length + 3)
    index := 0
    while index < runtimePaths.Length {
        paths[index] = runtimePaths[index]
        index += 1
    }
    paths[index] = typeof(ITaskItem).get_Assembly().get_Location()
    paths[index + 1] = typeof(Microsoft.Build.Utilities.Task).get_Assembly().get_Location()
    paths[index + 2] = typeof(ReaderParameters).get_Assembly().get_Location()
    resolver := new PathAssemblyResolver(paths)
    coreAssemblyName := AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName()
    context := new MetadataLoadContext(resolver, coreAssemblyName)
    return context
}

func SmcMetadataType(context: MetadataLoadContext, assemblyPath: string, fullName: string): Type {
    assembly := context.LoadFromAssemblyPath(assemblyPath)
    return SmcRequiredType(assembly.GetType(fullName), fullName)
}

func SmcAssertSelectedProperty(receiverType: Type, member: string, expectedResultName: string): ColumnarRuntimeInstanceMemberSelection {
    selection := ColumnarRuntimeInstanceMemberSelection.Empty()
    if !ColumnarRuntimeInstanceMemberResolver.TrySelect(receiverType, member, out selection) {
        throw new InvalidOperationException((receiverType.FullName ?? "") + "." + member + " was not selected")
    }
    if selection.IsField {
        throw new InvalidOperationException((receiverType.FullName ?? "") + "." + member + " selected a field")
    }
    if selection.DeclaringType != receiverType && !selection.DeclaringType.IsAssignableFrom(receiverType) {
        throw new InvalidOperationException((receiverType.FullName ?? "") + "." + member + " selected " + (selection.DeclaringType.FullName ?? ""))
    }
    resultName := selection.ResultType.FullName ?? ""
    if selection.ResultType.get_IsGenericType() && !selection.ResultType.get_IsGenericTypeDefinition() {
        resultName = selection.ResultType.GetGenericTypeDefinition().FullName ?? ""
    }
    if resultName != expectedResultName {
        throw new InvalidOperationException((receiverType.FullName ?? "") + "." + member + " returned " + resultName)
    }
    if !selection.ReceiverIsReference {
        throw new InvalidOperationException((receiverType.FullName ?? "") + "." + member + " did not retain a reference receiver")
    }
    getter := selection.Getter
    if getter == null {
        throw new InvalidOperationException("The admitted property did not retain its getter.")
    }
    if getter.get_Name() != "get_" + member {
        throw new InvalidOperationException((receiverType.FullName ?? "") + "." + member + " retained " + getter.get_Name())
    }
    if getter.get_DeclaringType() != selection.DeclaringType {
        throw new InvalidOperationException((receiverType.FullName ?? "") + "." + member + " lost its exact declaring type")
    }
    if !getter.get_IsPublic() || getter.get_IsStatic() {
        throw new InvalidOperationException((receiverType.FullName ?? "") + "." + member + " retained a non-instance-public getter")
    }
    return selection
}

func SmcSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func SmcWritableProperty(receiverType: Type, member: string, seed: PropertyInfo?): object?[] {
    method := typeof(ColumnarIlEmitter).GetMethod("TryGetSupportedBclWritableProperty", BindingFlags.Static | BindingFlags.NonPublic)
    if method == null {
        throw new InvalidOperationException("The writable-property admission method was not found.")
    }
    arguments := new object?[](3)
    SmcSetObject(arguments, 0, receiverType)
    SmcSetObject(arguments, 1, member)
    SmcSetObject(arguments, 2, seed)
    supported := method.Invoke(null, arguments)
    result := new object?[](2)
    SmcSetObject(result, 0, supported)
    SmcSetObject(result, 1, arguments[2])
    return result
}

func SmcAssertWritable(receiverType: Type, member: string, expectedResultName: string): PropertyInfo {
    result := SmcWritableProperty(receiverType, member, null)
    assert Convert.ToBoolean(result[0])
    property := result[1] as PropertyInfo
    if property == null {
        throw new InvalidOperationException("The admitted writable property did not retain its metadata handle.")
    }
    assert property.get_DeclaringType() == receiverType
    assert property.get_Name() == member
    assert property.get_PropertyType().FullName == expectedResultName
    setter := property.get_SetMethod()
    if setter == null {
        throw new InvalidOperationException("The admitted writable property has no public setter.")
    }
    assert setter.get_IsPublic()
    assert !setter.get_IsStatic()
    return property
}

func SmcCallPlan(member: string, parameterNames: string[]): ColumnarExternalCallPlan {
    return ColumnarExternalBindingPlans.GetInstanceCallPlan("Microsoft.Build.Utilities.TaskLoggingHelper", member, parameterNames)
}

func SmcAssertRuntimeCall(member: string, parameterTypes: Type[]): MethodInfo {
    names := new string[](parameterTypes.Length)
    index := 0
    while index < parameterTypes.Length {
        names[index] = parameterTypes[index].FullName ?? ""
        index += 1
    }
    plan := SmcCallPlan(member, names)
    assert plan.IsSupported
    assert plan.Kind == ColumnarExternalCallKind.CallVirtual
    selection := ColumnarRuntimeDirectCallSelection.Empty()
    assert ColumnarRuntimeDirectCallResolver.TrySelect(plan, typeof(Microsoft.Build.Utilities.TaskLoggingHelper), false, out selection)
    method := selection.Method
    if method == null {
        throw new InvalidOperationException("The MSBuild call plan did not select a runtime method.")
    }
    assert selection.DeclaringType == typeof(Microsoft.Build.Utilities.TaskLoggingHelper)
    assert selection.ReturnType == ColumnarTypeOfPlanner.RequiredVoidType()
    assert selection.ReceiverIsReference
    assert selection.UsesCallVirtual
    parameters := method.GetParameters()
    assert parameters.Length == parameterTypes.Length
    index = 0
    while index < parameters.Length {
        assert parameters[index].get_ParameterType() == parameterTypes[index]
        index += 1
    }
    return method
}

class SmcTask: Microsoft.Build.Utilities.Task {
    override func Execute(): bool {
        return true
    }
}

class SmcOrder {
    Trace: string

    constructor() {
        Trace = ""
    }

    func Reset() {
        Trace = ""
    }

    func Text(marker: string): string {
        Trace = Trace + marker
        return marker
    }

    func Number(marker: string): int {
        Trace = Trace + marker
        return 1
    }

    func Importance(marker: string): MessageImportance {
        Trace = Trace + marker
        return MessageImportance.High
    }

    func Arguments(marker: string): object[] {
        Trace = Trace + marker
        return Array.Empty<object>()
    }

    func Error(marker: string): Exception {
        Trace = Trace + marker
        return new InvalidOperationException("probe")
    }
}

test "MSBuild and Cecil receivers require exact external identity in runtime and metadata load contexts" {
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedSdkTaskReceiver(typeof(ITaskItem))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedSdkTaskReceiver(typeof(Microsoft.Build.Utilities.Task))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedSdkTaskReceiver(typeof(Microsoft.Build.Utilities.TaskLoggingHelper))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedCecilReceiver(typeof(ReaderParameters))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedCecilReceiver(typeof(AssemblyDefinition))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedCecilReceiver(typeof(ModuleDefinition))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedCecilReceiver(typeof(TypeDefinition))

    SmcAssertSelectedProperty(typeof(ITaskItem), "ItemSpec", "System.String")
    SmcAssertSelectedProperty(typeof(Microsoft.Build.Utilities.Task), "Log", "Microsoft.Build.Utilities.TaskLoggingHelper")
    SmcAssertSelectedProperty(typeof(AssemblyDefinition), "MainModule", "Mono.Cecil.ModuleDefinition")
    SmcAssertSelectedProperty(typeof(ModuleDefinition), "Types", "Mono.Collections.Generic.Collection`1")
    SmcAssertSelectedProperty(typeof(TypeDefinition), "FullName", "System.String")

    context := SmcMetadataContext()
    try {
        metadataItem := SmcMetadataType(context, typeof(ITaskItem).get_Assembly().get_Location(), "Microsoft.Build.Framework.ITaskItem")
        metadataTask := SmcMetadataType(context, typeof(Microsoft.Build.Utilities.Task).get_Assembly().get_Location(), "Microsoft.Build.Utilities.Task")
        metadataModule := SmcMetadataType(context, typeof(ReaderParameters).get_Assembly().get_Location(), "Mono.Cecil.ModuleDefinition")
        assert ColumnarRuntimeInstanceMemberResolver.IsSupportedSdkTaskReceiver(metadataItem)
        assert ColumnarRuntimeInstanceMemberResolver.IsSupportedSdkTaskReceiver(metadataTask)
        assert ColumnarRuntimeInstanceMemberResolver.IsSupportedCecilReceiver(metadataModule)
        itemIdentity := typeof(ITaskItem).get_AssemblyQualifiedName()
        taskIdentity := typeof(Microsoft.Build.Utilities.Task).get_AssemblyQualifiedName()
        moduleIdentity := typeof(ModuleDefinition).get_AssemblyQualifiedName()
        assert itemIdentity != null
        assert taskIdentity != null
        assert moduleIdentity != null
        assert ExternalAssemblyScan.HasExactTypeIdentity(metadataItem, itemIdentity)
        assert ExternalAssemblyScan.HasExactTypeIdentity(metadataTask, taskIdentity)
        assert ExternalAssemblyScan.HasExactTypeIdentity(metadataModule, moduleIdentity)
    } finally {
        context.Dispose()
    }
}

test "same-named foreign types and live builders cannot enter the MSBuild or Cecil binding surface" {
    foreignItemBuilder := TypeOfCreateBuilder("Microsoft.Build.Framework.ITaskItem", "NSharpTests.ForeignMsBuild", 0)
    foreignReaderBuilder := TypeOfCreateBuilder("Mono.Cecil.ReaderParameters", "NSharpTests.ForeignCecil", 0)
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedSdkTaskReceiver(foreignItemBuilder)
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedCecilReceiver(foreignReaderBuilder)
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedSdkTaskReceiver(SmcBake(foreignItemBuilder))
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedCecilReceiver(SmcBake(foreignReaderBuilder))

    foreignEnum := SmcEnumBuilder("Mono.Cecil.ReaderParameters")
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedCecilReceiver(foreignEnum)
    rejected := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(foreignEnum, "InMemory", out rejected)
    assert rejected.Getter == null
}

test "Cecil writable properties retain exact metadata handles and reset failed selections" {
    SmcAssertWritable(typeof(ReaderParameters), "ReadingMode", "Mono.Cecil.ReadingMode")
    SmcAssertWritable(typeof(ReaderParameters), "InMemory", "System.Boolean")
    SmcAssertWritable(typeof(Mono.Cecil.TypeReference), "Scope", "Mono.Cecil.IMetadataScope")
    SmcAssertWritable(typeof(AssemblyNameReference), "Culture", "System.String")
    SmcAssertWritable(typeof(AssemblyNameReference), "PublicKeyToken", "System.Byte[]")

    sentinel := typeof(ReaderParameters).GetProperty("ReadingMode")
    adjacent := SmcWritableProperty(typeof(ReaderParameters), "ReadSymbols", sentinel)
    assert !Convert.ToBoolean(adjacent[0])
    assert adjacent[1] == null
    foreign := SmcWritableProperty(SmcBake(TypeOfCreateBuilder("Mono.Cecil.ReaderParameters", "NSharpTests.ForeignWritable", 0)), "InMemory", sentinel)
    assert !Convert.ToBoolean(foreign[0])
    assert foreign[1] == null
}

test "Cecil property assignments execute their real setters and preserve assigned identities" {
    parameters := new ReaderParameters()
    parameters.ReadingMode = ReadingMode.Immediate
    parameters.InMemory = true
    readingMode := typeof(ReaderParameters).GetProperty("ReadingMode")
    inMemory := typeof(ReaderParameters).GetProperty("InMemory")
    assert readingMode != null
    assert inMemory != null
    assert Object.Equals(readingMode.GetValue(parameters), ReadingMode.Immediate)
    assert Convert.ToBoolean(inMemory.GetValue(parameters))

    originalScope := new AssemblyNameReference("Original.Scope", new Version(1, 2, 3, 4))
    replacementScope := new AssemblyNameReference("Replacement.Scope", new Version(5, 6, 7, 8))
    constructorTypes := new Type[](4)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(string)
    constructorTypes[2] = typeof(ModuleDefinition)
    constructorTypes[3] = SmcRequiredType(Type.GetType("Mono.Cecil.IMetadataScope, Mono.Cecil"), "Mono.Cecil.IMetadataScope")
    constructor := ExecutorRequiredConstructor(typeof(Mono.Cecil.TypeReference), constructorTypes)
    constructorArguments := new object?[](4)
    SmcSetObject(constructorArguments, 0, "NSharpTests")
    SmcSetObject(constructorArguments, 1, "Probe")
    SmcSetObject(constructorArguments, 2, null)
    SmcSetObject(constructorArguments, 3, originalScope)
    reference := TypeOfRequiredConstruction(constructor, constructorArguments) as Mono.Cecil.TypeReference
    if reference == null {
        throw new InvalidOperationException("The Cecil TypeReference fixture was not constructed.")
    }
    reference.Scope = replacementScope
    scopeProperty := typeof(Mono.Cecil.TypeReference).GetProperty("Scope")
    assert scopeProperty != null
    observedScope := scopeProperty.GetValue(reference)
    expectedScope: object = replacementScope
    assert Object.ReferenceEquals(observedScope, expectedScope)

    assemblyReference := new AssemblyNameReference("NSharpTests.Assembly", new Version(1, 0, 0, 0))
    token := new byte[](4)
    token[0] = 1
    token[1] = 3
    token[2] = 5
    token[3] = 7
    assemblyReference.Culture = "fr-FR"
    assemblyReference.PublicKeyToken = token
    assert assemblyReference.Culture == "fr-FR"
    tokenProperty := typeof(AssemblyNameReference).GetProperty("PublicKeyToken")
    assert tokenProperty != null
    observedToken := tokenProperty.GetValue(assemblyReference)
    expectedToken: object = token
    assert Object.ReferenceEquals(observedToken, expectedToken)
}

test "MSBuild params-array plans select their exact virtual runtime methods" {
    messageTypes := new Type[](3)
    messageTypes[0] = typeof(MessageImportance)
    messageTypes[1] = typeof(string)
    messageTypes[2] = typeof(object[])
    SmcAssertRuntimeCall("LogMessage", messageTypes)

    exceptionTypes := new Type[](4)
    exceptionTypes[0] = typeof(Exception)
    exceptionTypes[1] = typeof(bool)
    exceptionTypes[2] = typeof(bool)
    exceptionTypes[3] = typeof(string)
    SmcAssertRuntimeCall("LogErrorFromException", exceptionTypes)

    diagnosticTypes := new Type[](10)
    diagnosticTypes[0] = typeof(string)
    diagnosticTypes[1] = typeof(string)
    diagnosticTypes[2] = typeof(string)
    diagnosticTypes[3] = typeof(string)
    diagnosticTypes[4] = typeof(int)
    diagnosticTypes[5] = typeof(int)
    diagnosticTypes[6] = typeof(int)
    diagnosticTypes[7] = typeof(int)
    diagnosticTypes[8] = typeof(string)
    diagnosticTypes[9] = typeof(object[])
    SmcAssertRuntimeCall("LogError", diagnosticTypes)
    SmcAssertRuntimeCall("LogWarning", diagnosticTypes)

    wrongMessageTypes := new string[](3)
    wrongMessageTypes[0] = "Microsoft.Build.Framework.MessageImportance"
    wrongMessageTypes[1] = "System.String"
    wrongMessageTypes[2] = "System.String[]"
    assert !SmcCallPlan("LogMessage", wrongMessageTypes).IsSupported
    assert !SmcCallPlan("LogCriticalMessage", new string[](0)).IsSupported
}

test "MSBuild logging calls evaluate every explicit argument in lexical order before CLR failure" {
    task := new SmcTask()
    logger: Microsoft.Build.Utilities.TaskLoggingHelper = task.get_Log()
    order := new SmcOrder()

    messageFailed := false
    try {
        logger.LogMessage(order.Importance("A"), order.Text("B"), order.Arguments("C"))
    } catch error: InvalidOperationException {
        assert error != null
        messageFailed = true
    }
    assert messageFailed
    assert order.Trace == "ABC"

    order.Reset()
    exceptionFailed := false
    try {
        logger.LogErrorFromException(order.Error("A"), order.Number("B") == 1, order.Number("C") == 1, order.Text("D"))
    } catch error: InvalidOperationException {
        assert error != null
        exceptionFailed = true
    }
    assert exceptionFailed
    assert order.Trace == "ABCD"

    order.Reset()
    errorFailed := false
    try {
        logger.LogError(order.Text("A"), order.Text("B"), order.Text("C"), order.Text("D"), order.Number("E"), order.Number("F"), order.Number("G"), order.Number("H"), order.Text("I"), order.Arguments("J"))
    } catch error: InvalidOperationException {
        assert error != null
        errorFailed = true
    }
    assert errorFailed
    assert order.Trace == "ABCDEFGHIJ"

    order.Reset()
    warningFailed := false
    try {
        logger.LogWarning(order.Text("A"), order.Text("B"), order.Text("C"), order.Text("D"), order.Number("E"), order.Number("F"), order.Number("G"), order.Number("H"), order.Text("I"), order.Arguments("J"))
    } catch error: InvalidOperationException {
        assert error != null
        warningFailed = true
    }
    assert warningFailed
    assert order.Trace == "ABCDEFGHIJ"
}

test "Array Empty object executes the exact shared BCL singleton closure" {
    first := Array.Empty<object>()
    second := Array.Empty<object>()
    assert first.Length == 0
    assert first.GetType() == typeof(object[])
    assert Object.ReferenceEquals(first, second)

    typeArguments := new string[](1)
    typeArguments[0] = "System.Object"
    plan := ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan("Array", "Empty", typeArguments, new string[](0))
    assert plan.IsSupported
    selection := ColumnarRuntimeDirectCallSelection.Empty()
    assert ColumnarRuntimeDirectCallResolver.TrySelect(plan, typeof(Array), true, out selection)
    assert selection.ReturnType == typeof(object[])
    assert selection.Method != null
}
