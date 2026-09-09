namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection

func EmitTaskRequiredType(assemblyQualifiedName: string): Type {
    value := Type.GetType(assemblyQualifiedName)
    if value == null {
        throw new InvalidOperationException("Required production or fixture type was not loadable: " + assemblyQualifiedName)
    }
    return value
}

func EmitTaskRequireType(value: Type?, description: string): Type {
    if value == null {
        throw new InvalidOperationException("Required type was not found: " + description)
    }
    return value
}

func EmitTaskRequiredObject(value: object?, description: string): object {
    if value == null {
        throw new InvalidOperationException("Required value was null: " + description)
    }
    return value
}

func EmitTaskRequiredString(value: string?, description: string): string {
    if value == null {
        throw new InvalidOperationException("Required string was null: " + description)
    }
    return value
}

func EmitTaskOwnerType(): Type {
    fixtureDirectory := Path.GetDirectoryName(typeof(SdkBoundaryRun).get_Assembly().get_Location()) ?? ""
    assemblyPath := Path.Combine(fixtureDirectory, "NSharpLang.Compiler.Core.dll")
    if !File.Exists(assemblyPath) {
        throw new InvalidOperationException("The Compiler Core fixture dependency was not found at " + assemblyPath)
    }
    assembly := Assembly.LoadFile(assemblyPath)
    return EmitTaskRequireType(assembly.GetType("NSharpLang.Build.Tasks.EmitIlAssembly"), "N# EmitIlAssembly owner")
}

func EmitTaskLegacyAssembly(): Assembly {
    ownerDirectory := Path.GetDirectoryName(EmitTaskOwnerType().get_Assembly().get_Location()) ?? ""
    path := Path.Combine(ownerDirectory, "NSharpLang.Build.Tasks.dll")
    if !File.Exists(path) {
        throw new InvalidOperationException("The built legacy task host assembly was not found at " + path)
    }
    return Assembly.LoadFile(path)
}

func EmitTaskOwnerAssemblyType(fullName: string): Type {
    return EmitTaskRequireType(EmitTaskOwnerType().get_Assembly().GetType(fullName), fullName)
}

func EmitTaskPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func EmitTaskRequiredConstructor(owner: Type, parameterTypes: Type[], description: string): ConstructorInfo {
    constructor := owner.GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("Required constructor was not found: " + description)
    }
    return constructor
}

func EmitTaskRequiredMethod(owner: Type, name: string, parameterTypes: Type[], description: string): MethodInfo {
    method := owner.GetMethod(name, parameterTypes)
    if method == null {
        throw new InvalidOperationException("Required method was not found: " + description)
    }
    return method
}

func EmitTaskRequiredPrivateMethod(name: string, parameterCount: int): MethodInfo {
    methods := EmitTaskOwnerType().GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
    selected: MethodInfo? = null
    matches := 0
    index := 0
    while index < methods.Length {
        method := methods[index]
        if method.get_Name() == name && method.GetParameters().Length == parameterCount {
            selected = method
            matches = matches + 1
        }
        index = index + 1
    }
    if selected == null || matches != 1 {
        throw new InvalidOperationException("Expected one private " + name + "/" + parameterCount.ToString() + " method.")
    }
    return selected
}

func EmitTaskRequiredProperty(owner: Type, name: string): PropertyInfo {
    property := owner.GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Required property was not found: " + name)
    }
    return property
}

func EmitTaskObjectProperty(value: object, name: string): object {
    property := value.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Required object property was not found: " + name)
    }
    result := property.GetValue(value)
    if result == null {
        throw new InvalidOperationException("Required object property returned null: " + name)
    }
    return result
}

func EmitTaskOptionalObjectProperty(value: object, name: string): object? {
    property := value.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Required object property was not found: " + name)
    }
    return property.GetValue(value)
}

func EmitTaskSetObjectProperty(value: object, name: string, propertyValue: object?) {
    property := value.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Required writable property was not found: " + name)
    }
    property.SetValue(value, propertyValue)
}

func EmitTaskObjectField(value: object, name: string): object? {
    field := value.GetType().GetField(name)
    if field == null {
        throw new InvalidOperationException("Required object field was not found: " + name)
    }
    return field.GetValue(value)
}

func EmitTaskSetObjectField(value: object, name: string, fieldValue: object?) {
    field := value.GetType().GetField(name)
    if field == null {
        throw new InvalidOperationException("Required writable field was not found: " + name)
    }
    field.SetValue(value, fieldValue)
}

func EmitTaskNew(owner: Type, parameterTypes: Type[], arguments: object?[], description: string): object {
    value := EmitTaskRequiredConstructor(owner, parameterTypes, description).Invoke(arguments)
    if value == null {
        throw new InvalidOperationException("Constructor returned null: " + description)
    }
    return value
}

func EmitTaskInvoke(receiver: object?, method: MethodInfo, arguments: object?[]): object? {
    return method.Invoke(receiver, arguments)
}

func EmitTaskInvokePrivate(receiver: object?, name: string, parameterCount: int, arguments: object?[]): object? {
    return EmitTaskInvoke(receiver, EmitTaskRequiredPrivateMethod(name, parameterCount), arguments)
}

func EmitTaskCollectionCount(collection: object): int {
    return Convert.ToInt32(EmitTaskObjectProperty(collection, "Count"))
}

func EmitTaskCollectionItem(collection: object, index: int): object {
    property := collection.GetType().GetProperty("Item")
    if property == null {
        throw new InvalidOperationException("Required collection indexer was not found.")
    }
    arguments := new object?[](1)
    EmitTaskPut(arguments, 0, index)
    result := property.GetValue(collection, arguments)
    if result == null {
        throw new InvalidOperationException("Collection item returned null at " + index.ToString() + ".")
    }
    return result
}

func EmitTaskCollectionAdd(collection: object, value: object) {
    methods := collection.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public)
    selected: MethodInfo? = null
    matches := 0
    index := 0
    while index < methods.Length {
        method := methods[index]
        if method.get_Name() == "Add" && method.GetParameters().Length == 1 {
            selected = method
            matches = matches + 1
        }
        index = index + 1
    }
    if selected == null || matches != 1 {
        throw new InvalidOperationException("Expected one public one-parameter Add method.")
    }
    arguments := new object?[](1)
    EmitTaskPut(arguments, 0, value)
    ignored := selected.Invoke(collection, arguments)
    _ = ignored
}

func EmitTaskNewInstance(owner: Type): object {
    parameterTypes := new Type[](0)
    arguments := new object?[](0)
    return EmitTaskNew(owner, parameterTypes, arguments, owner.get_FullName() ?? "instance")
}

func EmitTaskNewTask(): object {
    return EmitTaskNewInstance(EmitTaskOwnerType())
}

func EmitTaskNewTaskItem(itemSpec: string): object {
    owner := EmitTaskRequiredType("Microsoft.Build.Utilities.TaskItem, Microsoft.Build.Utilities.Core")
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    arguments := new object?[](1)
    EmitTaskPut(arguments, 0, itemSpec)
    return EmitTaskNew(owner, parameterTypes, arguments, "TaskItem(string)")
}

func EmitTaskItemArray(itemSpecs: string[]): Array {
    itemType := EmitTaskRequiredType("Microsoft.Build.Framework.ITaskItem, Microsoft.Build.Framework")
    items := Array.CreateInstance(itemType, itemSpecs.Length)
    index := 0
    while index < itemSpecs.Length {
        EmitTaskArraySet(items, index, EmitTaskNewTaskItem(itemSpecs[index]))
        index = index + 1
    }
    return items
}

func EmitTaskSetReferences(task: object, paths: string[]) {
    EmitTaskSetObjectProperty(task, "References", EmitTaskItemArray(paths))
}

func EmitTaskCreateConfig(): object {
    return EmitTaskNewInstance(EmitTaskOwnerAssemblyType("NSharpLang.Compiler.ProjectConfig"))
}

func EmitTaskConfigDependencies(config: object): object {
    return EmitTaskObjectProperty(config, "Dependencies")
}

func EmitTaskAddDllDependency(config: object, path: string) {
    reference := EmitTaskNewInstance(EmitTaskOwnerAssemblyType("NSharpLang.Compiler.Reference"))
    EmitTaskSetObjectField(reference, "Dll", path)
    EmitTaskCollectionAdd(EmitTaskConfigDependencies(config), reference)
}

func EmitTaskDllDependency(config: object, index: int): string {
    reference := EmitTaskCollectionItem(EmitTaskConfigDependencies(config), index)
    return Convert.ToString(EmitTaskObjectField(reference, "Dll")) ?? ""
}

func EmitTaskCecilType(name: string): Type {
    return EmitTaskRequiredType("Mono.Cecil." + name + ", Mono.Cecil")
}

func EmitTaskReadAssembly(path: string): object {
    owner := EmitTaskCecilType("AssemblyDefinition")
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    method := EmitTaskRequiredMethod(owner, "ReadAssembly", parameterTypes, "AssemblyDefinition.ReadAssembly(string)")
    arguments := new object?[](1)
    EmitTaskPut(arguments, 0, path)
    value := method.Invoke(null, arguments)
    if value == null {
        throw new InvalidOperationException("Cecil returned null while reading " + path)
    }
    return value
}

func EmitTaskWriteAssembly(assembly: object, path: string) {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    method := EmitTaskRequiredMethod(assembly.GetType(), "Write", parameterTypes, "AssemblyDefinition.Write(string)")
    arguments := new object?[](1)
    EmitTaskPut(arguments, 0, path)
    ignored := method.Invoke(assembly, arguments)
    _ = ignored
}

func EmitTaskDispose(value: object?) {
    disposable := value as IDisposable
    if disposable != null {
        disposable.Dispose()
    }
}

func EmitTaskSetAssemblyIdentity(assembly: object, name: string, version: Version, culture: string?, token: byte[]?) {
    identity := EmitTaskObjectProperty(assembly, "Name")
    EmitTaskSetObjectProperty(identity, "Name", name)
    EmitTaskSetObjectProperty(identity, "Version", version)
    EmitTaskSetObjectProperty(identity, "Culture", culture)
    EmitTaskSetObjectProperty(identity, "PublicKeyToken", token)
}

func EmitTaskNewAssemblyNameReference(name: string, version: Version, culture: string?, token: byte[]?): object {
    owner := EmitTaskCecilType("AssemblyNameReference")
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(Version)
    arguments := new object?[](2)
    EmitTaskPut(arguments, 0, name)
    EmitTaskPut(arguments, 1, version)
    reference := EmitTaskNew(owner, parameterTypes, arguments, "AssemblyNameReference(string, Version)")
    EmitTaskSetObjectProperty(reference, "Culture", culture)
    EmitTaskSetObjectProperty(reference, "PublicKeyToken", token)
    return reference
}

func EmitTaskNewAssemblyNameDefinition(name: string, version: Version, culture: string?, token: byte[]?): object {
    owner := EmitTaskCecilType("AssemblyNameDefinition")
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(Version)
    arguments := new object?[](2)
    EmitTaskPut(arguments, 0, name)
    EmitTaskPut(arguments, 1, version)
    definition := EmitTaskNew(owner, parameterTypes, arguments, "AssemblyNameDefinition(string, Version)")
    EmitTaskSetObjectProperty(definition, "Culture", culture)
    EmitTaskSetObjectProperty(definition, "PublicKeyToken", token)
    return definition
}

func EmitTaskNewCecilModule(name: string): object {
    owner := EmitTaskCecilType("ModuleDefinition")
    kindType := EmitTaskCecilType("ModuleKind")
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = kindType
    method := EmitTaskRequiredMethod(owner, "CreateModule", parameterTypes, "ModuleDefinition.CreateModule(string, ModuleKind)")
    arguments := new object?[](2)
    EmitTaskPut(arguments, 0, name)
    EmitTaskPut(arguments, 1, Enum.Parse(kindType, "Dll"))
    value := method.Invoke(null, arguments)
    if value == null {
        throw new InvalidOperationException("CreateModule returned null.")
    }
    return value
}

func EmitTaskAssemblyReferences(module: object): object {
    return EmitTaskObjectProperty(module, "AssemblyReferences")
}

func EmitTaskFindAssemblyReference(module: object, name: string): object? {
    references := EmitTaskAssemblyReferences(module)
    index := 0
    while index < EmitTaskCollectionCount(references) {
        reference := EmitTaskCollectionItem(references, index)
        if Convert.ToString(EmitTaskObjectProperty(reference, "Name")) == name {
            return reference
        }
        index = index + 1
    }
    return null
}

func EmitTaskFindTypeReference(assembly: object, fullName: string): object? {
    module := EmitTaskObjectProperty(assembly, "MainModule")
    parameterTypes := new Type[](0)
    method := EmitTaskRequiredMethod(module.GetType(), "GetTypeReferences", parameterTypes, "ModuleDefinition.GetTypeReferences")
    arguments := new object?[](0)
    sequenceValue := method.Invoke(module, arguments)
    sequence := sequenceValue as IEnumerable
    if sequence == null {
        throw new InvalidOperationException("GetTypeReferences did not return IEnumerable.")
    }
    enumerator := sequence.GetEnumerator()
    try {
        while enumerator.MoveNext() {
            current := enumerator.get_Current()
            if current != null && Convert.ToString(EmitTaskObjectProperty(current, "FullName")) == fullName {
                return current
            }
        }
    } finally {
        EmitTaskDispose(enumerator)
    }
    return null
}

func EmitTaskTypeReferenceScopeName(typeReference: object): string? {
    scope := EmitTaskOptionalObjectProperty(typeReference, "Scope")
    if scope == null {
        return null
    }
    nameProperty := scope.GetType().GetProperty("Name")
    if nameProperty == null {
        return null
    }
    return Convert.ToString(nameProperty.GetValue(scope))
}

func EmitTaskCloneAssembly(source: string, destination: string, name: string, version: Version, culture: string?, token: byte[]?) {
    assembly := EmitTaskReadAssembly(source)
    try {
        EmitTaskSetAssemblyIdentity(assembly, name, version, culture, token)
        EmitTaskWriteAssembly(assembly, destination)
    } finally {
        EmitTaskDispose(assembly)
    }
}

func EmitTaskByteArray(values: int[]): byte[] {
    result := new byte[](values.Length)
    index := 0
    while index < values.Length {
        result[index] = (byte)values[index]
        index = index + 1
    }
    return result
}

func EmitTaskBytesEqual(left: byte[], right: byte[]): bool {
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

func EmitTaskArrayLength(value: Array): int {
    property := value.GetType().GetProperty("Length")
    if property == null {
        throw new InvalidOperationException("Required array Length property was not found.")
    }
    return Convert.ToInt32(property.GetValue(value))
}

func EmitTaskArrayValue(value: Array, index: int): object? {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    method := EmitTaskRequiredMethod(typeof(Array), "GetValue", parameterTypes, "Array.GetValue(int)")
    arguments := new object?[](1)
    EmitTaskPut(arguments, 0, index)
    return method.Invoke(value, arguments)
}

func EmitTaskArraySet(value: Array, index: int, replacement: object?) {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(object)
    parameterTypes[1] = typeof(int)
    method := EmitTaskRequiredMethod(typeof(Array), "SetValue", parameterTypes, "Array.SetValue(object, int)")
    arguments := new object?[](2)
    EmitTaskPut(arguments, 0, replacement)
    EmitTaskPut(arguments, 1, index)
    ignored := method.Invoke(value, arguments)
    _ = ignored
}

func EmitTaskObjectBytesEqual(value: object?, expected: byte[]): bool {
    bytes := value as Array
    if bytes == null {
        return false
    }
    if EmitTaskArrayLength(bytes) != expected.Length {
        return false
    }
    index := 0
    while index < expected.Length {
        if Convert.ToByte(EmitTaskArrayValue(bytes, index)) != expected[index] {
            return false
        }
        index = index + 1
    }
    return true
}

func EmitTaskObjectByteArraysEqual(left: object?, right: object?): bool {
    leftBytes := left as Array
    rightBytes := right as Array
    if leftBytes == null || rightBytes == null {
        return leftBytes == null && rightBytes == null
    }
    if EmitTaskArrayLength(leftBytes) != EmitTaskArrayLength(rightBytes) {
        return false
    }
    index := 0
    while index < EmitTaskArrayLength(leftBytes) {
        if Convert.ToByte(EmitTaskArrayValue(leftBytes, index)) != Convert.ToByte(EmitTaskArrayValue(rightBytes, index)) {
            return false
        }
        index = index + 1
    }
    return true
}

func EmitTaskAssemblyIdentityProperty(path: string, name: string): object? {
    assembly := EmitTaskReadAssembly(path)
    result: object? = null
    try {
        identity := EmitTaskObjectProperty(assembly, "Name")
        result = EmitTaskOptionalObjectProperty(identity, name)
    } finally {
        EmitTaskDispose(assembly)
    }
    return result
}

func EmitTaskReferencePackDirectory(): string {
    objectType := typeof(object)
    objectAssemblyInfo := objectType.get_Assembly()
    objectAssembly := objectAssemblyInfo.get_Location()
    runtimeDirectory := Path.GetDirectoryName(objectAssembly) ?? ""
    dotnetRoot := Path.GetFullPath(Path.Combine(runtimeDirectory, "../../.."))
    packsRoot := Path.Combine(Path.Combine(dotnetRoot, "packs"), "Microsoft.NETCore.App.Ref")
    versions := Directory.GetDirectories(packsRoot)
    versionDirectory: string? = null
    versionIndex := 0
    while versionIndex < versions.Length {
        candidateReferenceDirectory := Path.Combine(Path.Combine(versions[versionIndex], "ref"), "net10.0")
        if versionDirectory == null && Directory.Exists(candidateReferenceDirectory) {
            versionDirectory = versions[versionIndex]
        }
        versionIndex = versionIndex + 1
    }
    if versionDirectory == null {
        throw new InvalidOperationException("The Microsoft.NETCore.App net10.0 reference pack was not found under " + packsRoot)
    }
    result := Path.Combine(Path.Combine(versionDirectory, "ref"), "net10.0")
    return result
}

func EmitTaskScratch(label: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-sdk-emit-task-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func EmitTaskRunProcess(fileName: string, arguments: string, workingDirectory: string): SdkBoundaryRun {
    runnerType := EmitTaskOwnerAssemblyType("NSharpLang.Cli.DotnetRunner")
    methods := runnerType.GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.DeclaredOnly)
    runProcess: MethodInfo? = null
    matches := 0
    index := 0
    while index < methods.Length {
        method := methods[index]
        if method.get_Name() == "RunProcess" && method.GetParameters().Length == 4 {
            runProcess = method
            matches = matches + 1
        }
        index = index + 1
    }
    if runProcess == null || matches != 1 {
        throw new InvalidOperationException("Expected one public four-parameter DotnetRunner.RunProcess method.")
    }

    invocationArguments := new object?[](4)
    EmitTaskPut(invocationArguments, 0, fileName)
    EmitTaskPut(invocationArguments, 1, arguments)
    EmitTaskPut(invocationArguments, 2, workingDirectory)
    EmitTaskPut(invocationArguments, 3, TimeSpan.FromMinutes(5))
    result := runProcess.Invoke(null, invocationArguments)
    if result == null {
        throw new InvalidOperationException("DotnetRunner.RunProcess returned null.")
    }

    exitCode := Convert.ToInt32(EmitTaskObjectField(result, "ExitCode"))
    stdout := Convert.ToString(EmitTaskObjectField(result, "Stdout")) ?? ""
    stderr := Convert.ToString(EmitTaskObjectField(result, "Stderr")) ?? ""
    return new SdkBoundaryRun(exitCode, stdout, stderr)
}

func EmitTaskOwnerAssemblyPath(): string {
    path := EmitTaskOwnerType().get_Assembly().get_Location()
    if !File.Exists(path) {
        throw new InvalidOperationException("The loaded EmitIlAssembly owner had no assembly file at " + path)
    }
    return path
}

func EmitTaskXmlAttribute(value: string): string {
    return value.Replace("&", "&amp;").Replace("\"", "&quot;").Replace("<", "&lt;").Replace(">", "&gt;")
}

func EmitTaskWriteDirectProject(
    path: string,
    sourcePath: string,
    projectFile: string,
    targetAssemblyPath: string,
    targetReferenceAssemblyPath: string
) {
    EmitTaskWriteDirectProjectCore(path, sourcePath, projectFile, targetAssemblyPath, targetReferenceAssemblyPath, null)
}

func EmitTaskWriteDirectProjectWithReference(
    path: string,
    sourcePath: string,
    projectFile: string,
    targetAssemblyPath: string,
    targetReferenceAssemblyPath: string,
    referencePath: string
) {
    EmitTaskWriteDirectProjectCore(path, sourcePath, projectFile, targetAssemblyPath, targetReferenceAssemblyPath, referencePath)
}

func EmitTaskWriteDirectProjectCore(
    path: string,
    sourcePath: string,
    projectFile: string,
    targetAssemblyPath: string,
    targetReferenceAssemblyPath: string,
    referencePath: string?
) {
    taskAssembly := EmitTaskXmlAttribute(EmitTaskOwnerAssemblyPath())
    source := EmitTaskXmlAttribute(sourcePath)
    project := EmitTaskXmlAttribute(projectFile)
    target := EmitTaskXmlAttribute(targetAssemblyPath)
    referenceTarget := EmitTaskXmlAttribute(targetReferenceAssemblyPath)
    referenceItem := ""
    referencesAttribute := ""
    if referencePath != null {
        referenceItem = "<TaskReference Include=\"" + EmitTaskXmlAttribute(referencePath) + "\" />"
        referencesAttribute = " References=\"@(TaskReference)\""
    }
    File.WriteAllText(
        path,
        "<Project>\n" + "  <UsingTask TaskName=\"NSharpLang.Build.Tasks.EmitIlAssembly\" AssemblyFile=\"" + taskAssembly + "\" />\n" + "  <ItemGroup><NSharpSource Include=\"" + source + "\" />" + referenceItem + "</ItemGroup>\n" + "  <Target Name=\"Run\">\n" + "    <EmitIlAssembly Sources=\"@(NSharpSource)\"" + referencesAttribute + " ProjectRoot=\"" + EmitTaskXmlAttribute(Path.GetDirectoryName(path) ?? "") + "\" ProjectFile=\"" + project + "\" TargetAssemblyPath=\"" + target + "\" TargetReferenceAssemblyPath=\"" + referenceTarget + "\" ValidateWithLegacyAnalysis=\"true\" />\n" + "  </Target>\n" + "</Project>\n"
    )
}

func EmitTaskRunDirectProject(path: string): SdkBoundaryRun {
    return EmitTaskRunProcess("dotnet", "msbuild " + SdkBoundaryQuote(path) + " -t:Run --disable-build-servers -v:m", Path.GetDirectoryName(path) ?? "")
}

func EmitTaskReferenceOwnersResolve(owners: object, fullName: string): string? {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    method := EmitTaskRequiredMethod(owners.GetType(), "Resolve", parameterTypes, "ReferenceTypeOwners.Resolve")
    arguments := new object?[](1)
    EmitTaskPut(arguments, 0, fullName)
    return method.Invoke(owners, arguments) as string
}

func EmitTaskDictionaryValue(dictionary: object, key: string): object? {
    lookup := dictionary as IDictionary
    if lookup == null {
        throw new InvalidOperationException("Expected an IDictionary owner-name map.")
    }
    property := typeof(IDictionary).GetProperty("Item")
    if property == null {
        throw new InvalidOperationException("IDictionary.Item was not found.")
    }
    arguments := new object?[](1)
    EmitTaskPut(arguments, 0, key)
    return property.GetValue(lookup, arguments)
}

func EmitTaskInnerException(error: Exception): Exception {
    invocation := error as TargetInvocationException
    if invocation != null {
        innerBox: object? = error.get_InnerException()
        inner := innerBox as Exception
        if inner != null {
            return inner
        }
    }
    return error
}

func EmitTaskCapturePrivateFailure(receiver: object?, name: string, parameterCount: int, arguments: object?[]): Exception? {
    try {
        _result := EmitTaskInvokePrivate(receiver, name, parameterCount, arguments)
    } catch error: Exception {
        return EmitTaskInnerException(error)
    }
    return null
}

func EmitTaskAssertRewriteOutput(path: string, ownerToken: object?) {
    output := EmitTaskReadAssembly(path)
    try {
        stringReference := EmitTaskFindTypeReference(output, "System.String")
        if stringReference == null {
            throw new InvalidOperationException("The emitted fixture contained no System.String TypeRef.")
        }
        assert EmitTaskTypeReferenceScopeName(stringReference) == "ReferenceOwner"
        module := EmitTaskObjectProperty(output, "MainModule")
        ownerReference := EmitTaskFindAssemblyReference(module, "ReferenceOwner")
        if ownerReference == null {
            throw new InvalidOperationException("The rewritten owner AssemblyRef was not added.")
        }
        assert Convert.ToString(EmitTaskObjectProperty(ownerReference, "Version")) == "6.5.4.3"
        assert Convert.ToString(EmitTaskObjectProperty(ownerReference, "Culture")) == "fr-FR"
        assert EmitTaskObjectByteArraysEqual(EmitTaskObjectProperty(ownerReference, "PublicKeyToken"), ownerToken)
    } finally {
        EmitTaskDispose(output)
    }
}
