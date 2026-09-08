namespace NSharpLang.ReferenceResolution.Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Cli
import NSharpLang.Compiler

func ResolverRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the N# repository root above the native test output.")
}

func ResolverNewTempDirectory(label: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-reference-resolution-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func ResolverWrite(path: string, contents: string) {
    parent := Path.GetDirectoryName(path)
    if parent != null && parent != "" {
        Directory.CreateDirectory(parent)
    }
    File.WriteAllText(path, contents)
}

func ResolverCopyDirectory(source: string, destination: string) {
    Directory.CreateDirectory(destination)
    files := Directory.GetFiles(source, "*", SearchOption.AllDirectories)
    index := 0
    while index < files.Length {
        sourcePath := files[index]
        relative := Path.GetRelativePath(source, sourcePath)
        destinationPath := Path.Combine(destination, relative)
        parent := Path.GetDirectoryName(destinationPath)
        if parent != null && parent != "" {
            Directory.CreateDirectory(parent)
        }
        File.Copy(sourcePath, destinationPath, true)
        index = index + 1
    }
}

func ResolverCandidatePackagesRoots(): string[] {
    roots := new List<string>()
    configured := Environment.GetEnvironmentVariable("NUGET_PACKAGES") ?? ""
    if configured != "" {
        roots.Add(configured)
    }

    profile := Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
    roots.Add(Path.Combine(Path.Combine(profile, ".nuget"), "packages"))
    roots.Add(Path.Combine(Path.Combine(profile, ".nsharp"), "packages"))
    return roots.ToArray()
}

func ResolverPrepareNewtonsoftCache(destinationRoot: string): string {
    roots := ResolverCandidatePackagesRoots()
    source: string? = null
    index := 0
    while index < roots.Length && source == null {
        candidate := Path.Combine(Path.Combine(roots[index], "newtonsoft.json"), "13.0.3")
        if Directory.Exists(candidate) && File.Exists(Path.Combine(Path.Combine(Path.Combine(candidate, "lib"), "net6.0"), "Newtonsoft.Json.dll")) {
            source = candidate
        }
        index = index + 1
    }

    if source == null {
        throw new InvalidOperationException("The installed Newtonsoft.Json 13.0.3 fixture was not found in a local package cache.")
    }

    destination := Path.Combine(Path.Combine(destinationRoot, "newtonsoft.json"), "13.0.3")
    ResolverCopyDirectory(source ?? "", destination)
    return destinationRoot
}

func ResolverWriteProjectReferenceFixture(projectRoot: string) {
    sharedDir := Path.Combine(projectRoot, "Shared")
    Directory.CreateDirectory(sharedDir)
    ResolverWrite(Path.Combine(sharedDir, "SharedLib.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    ResolverWrite(
        Path.Combine(sharedDir, "project.yml"),
        "name: SharedLib\noutputType: library\ntargetFramework: net10.0"
    )
    ResolverWrite(
        Path.Combine(sharedDir, "Shared.nl"),
        "func Greeting(): string {\n    return \"hello from shared\"\n}"
    )

    ResolverWrite(
        Path.Combine(projectRoot, "project.yml"),
        "name: App\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - project: Shared/project.yml\n  - nuget: Newtonsoft.Json\n    version: 13.0.3"
    )
    ResolverWrite(
        Path.Combine(projectRoot, "Program.nl"),
        "import Newtonsoft.Json\n\nfunc main() {\n    print JsonConvert.SerializeObject(Greeting())\n}"
    )
}

func ResolverWriteAotProjectFixture(projectRoot: string, rootOutputType: string) {
    sharedDir := Path.Combine(projectRoot, "Shared")
    Directory.CreateDirectory(sharedDir)
    ResolverWrite(Path.Combine(sharedDir, "SharedLib.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    ResolverWrite(
        Path.Combine(sharedDir, "project.yml"),
        "name: SharedLib\noutputType: library\ntargetFramework: net10.0"
    )
    ResolverWrite(
        Path.Combine(sharedDir, "Shared.nl"),
        "func CountChars(s: string): int {\n    n := 0\n    foreach c in s {\n        n = n + 1\n    }\n    return n\n}"
    )
    ResolverWrite(
        Path.Combine(projectRoot, "project.yml"),
        "name: App\noutputType: " + rootOutputType + "\ntargetFramework: net10.0\ndependencies:\n  - project: Shared/project.yml"
    )
    rootSource := "func Root(): int {\n    return 1\n}"
    if rootOutputType == "exe" {
        rootSource = "func main() {\n    print \"root\"\n}"
    }
    ResolverWrite(Path.Combine(projectRoot, "Program.nl"), rootSource)
}

func ResolverWriteWebFixture(projectRoot: string) {
    sourceRoot := Path.Combine(Path.Combine(ResolverRepositoryRoot(), "examples"), "14-minimal-api")
    File.Copy(Path.Combine(sourceRoot, "project.yml"), Path.Combine(projectRoot, "project.yml"), true)
    File.Copy(Path.Combine(sourceRoot, "Program.nl"), Path.Combine(projectRoot, "Program.nl"), true)
}

func ResolverParseProject(projectRoot: string): ProjectConfig {
    return ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"))
}

func ResolverContainsDll(config: ProjectConfig, fileName: string): bool {
    for reference in config.Dependencies {
        if reference.Dll != null && string.Equals(Path.GetFileName(reference.Dll ?? ""), fileName, StringComparison.OrdinalIgnoreCase) {
            return true
        }
    }
    return false
}

func ResolverDllIndex(config: ProjectConfig, fileName: string): int {
    index := 0
    for reference in config.Dependencies {
        if reference.Dll != null && string.Equals(Path.GetFileName(reference.Dll ?? ""), fileName, StringComparison.OrdinalIgnoreCase) {
            return index
        }
        index = index + 1
    }
    return -1
}

func ResolverContainsProjectIdentity(config: ProjectConfig, target: Reference): bool {
    for reference in config.Dependencies {
        if Object.ReferenceEquals(reference, target) {
            return true
        }
    }
    return false
}

func ResolverContainsPath(paths: IEnumerable<string>, target: string): bool {
    expected := Path.GetFullPath(target)
    for path in paths {
        if string.Equals(Path.GetFullPath(path), expected, StringComparison.OrdinalIgnoreCase) {
            return true
        }
    }
    return false
}

func ResolverOwnerType(): Type {
    owner := Type.GetType("NSharpLang.Cli.CompilationReferenceResolver, NSharpLang.Compiler.BootstrapServices")
    if owner == null {
        throw new InvalidOperationException("The N# CompilationReferenceResolver owner was not loadable from BootstrapServices.")
    }
    return owner
}

func ResolverPrivateMethod(name: string, parameterCount: int): MethodInfo {
    methods := ResolverOwnerType().GetMethods(BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
    found: MethodInfo? = null
    count := 0
    for method in methods {
        if method.get_Name() == name && method.GetParameters().Length == parameterCount {
            found = method
            count = count + 1
        }
    }
    if found == null || count != 1 {
        throw new InvalidOperationException("Expected exactly one private resolver method named " + name + ".")
    }
    return found
}

func ResolverSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func ResolverInvoke(method: MethodInfo, arguments: object?[]): object? {
    return method.Invoke(null, arguments)
}

func ResolverInnerException(captured: Exception?): Exception? {
    invocation := captured as TargetInvocationException
    if invocation == null {
        return captured
    }
    return invocation.get_InnerException()
}

func ResolverWritePackage(
    packagesRoot: string,
    packageId: string,
    version: string,
    nuspecBody: string,
    refAssembly: string?,
    runtimeAssembly: string?
): string {
    versionDirectory := Path.Combine(Path.Combine(packagesRoot, packageId.ToLowerInvariant()), version.ToLowerInvariant())
    Directory.CreateDirectory(versionDirectory)
    ResolverWrite(
        Path.Combine(versionDirectory, packageId.ToLowerInvariant() + ".nuspec"),
        "<package><metadata><id>" + packageId + "</id><version>" + version + "</version>" + nuspecBody + "</metadata></package>"
    )
    if refAssembly != null {
        refDirectory := Path.Combine(Path.Combine(versionDirectory, "ref"), "net10.0")
        Directory.CreateDirectory(refDirectory)
        File.Copy(refAssembly ?? "", Path.Combine(refDirectory, Path.GetFileName(refAssembly ?? "")), true)
    }
    if runtimeAssembly != null {
        runtimeDirectory := Path.Combine(Path.Combine(versionDirectory, "lib"), "net10.0")
        Directory.CreateDirectory(runtimeDirectory)
        File.Copy(runtimeAssembly ?? "", Path.Combine(runtimeDirectory, Path.GetFileName(runtimeAssembly ?? "")), true)
    }
    return versionDirectory
}

func ResolverFrameworkAssembly(name: string): string {
    runtimeDirectory := Path.GetDirectoryName(typeof(object).get_Assembly().get_Location()) ?? ""
    path := Path.Combine(runtimeDirectory, name)
    if !File.Exists(path) {
        throw new InvalidOperationException("Required framework assembly fixture was not found: " + path)
    }
    return path
}

func ResolverPackageAssets(packageName: string, version: string?, targetFramework: string, context: ResolutionContext): NuGetPackageAssets {
    method := ResolverPrivateMethod("ResolveNuGetPackage", 4)
    arguments := new object?[](4)
    ResolverSetObject(arguments, 0, packageName)
    ResolverSetObject(arguments, 1, version)
    ResolverSetObject(arguments, 2, targetFramework)
    ResolverSetObject(arguments, 3, context)
    result := ResolverInvoke(method, arguments) as NuGetPackageAssets
    if result == null {
        throw new InvalidOperationException("ResolveNuGetPackage returned no assets.")
    }
    return result
}

func ResolverEnsurePackage(packageName: string, version: string?): string {
    method := ResolverPrivateMethod("EnsurePackageAvailable", 2)
    arguments := new object?[](2)
    ResolverSetObject(arguments, 0, packageName)
    ResolverSetObject(arguments, 1, version)
    result := ResolverInvoke(method, arguments) as string
    if result == null {
        throw new InvalidOperationException("EnsurePackageAvailable returned no package directory.")
    }
    return result ?? ""
}

func ResolverBuildProject(
    projectRoot: string,
    config: ProjectConfig,
    options: ReferenceResolutionOptions,
    context: ResolutionContext
): object? {
    method := ResolverPrivateMethod("BuildProjectReference", 4)
    arguments := new object?[](4)
    ResolverSetObject(arguments, 0, projectRoot)
    ResolverSetObject(arguments, 1, config)
    ResolverSetObject(arguments, 2, options)
    ResolverSetObject(arguments, 3, context)
    return ResolverInvoke(method, arguments)
}

func ResolverCaptureProjectBuildFailure(
    projectRoot: string,
    config: ProjectConfig,
    options: ReferenceResolutionOptions,
    context: ResolutionContext
): Exception? {
    captured: Exception? = null
    try {
        ignored := ResolverBuildProject(projectRoot, config, options, context)
        _ = ignored
    } catch e: Exception {
        captured = e
    }
    return ResolverInnerException(captured)
}

func ResolverCaptureReferenceResolutionFailure(
    projectRoot: string,
    config: ProjectConfig,
    options: ReferenceResolutionOptions
): Exception? {
    captured: Exception? = null
    try {
        ignored := CompilationReferenceResolver.AddResolvedDllReferences(projectRoot, config, options)
        _ = ignored
    } catch e: Exception {
        captured = e
    }
    return captured
}

func* ResolverFormattedDiagnosticRows(
    first: CompilerError,
    second: CompilerError
): IEnumerable<CompilerError> {
    yield first
    yield second
}

func* ResolverThrowingDiagnosticRows(first: CompilerError): IEnumerable<CompilerError> {
    yield first
    throw new InvalidOperationException("diagnostic iteration failed")
}

func ResolverDistinctDiagnosticEnumerable(
    enumerator: IEnumerator<CompilerError>,
    typeName: string
): object {
    noParameters := new Type[](0)
    elementArguments := new Type[](1)
    elementArguments[0] = typeof(CompilerError)
    genericEnumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    genericEnumeratorDefinition := typeof(IEnumerator<int>).GetGenericTypeDefinition()
    genericEnumerable := genericEnumerableDefinition.MakeGenericType(elementArguments)
    genericEnumerator := genericEnumeratorDefinition.MakeGenericType(elementArguments)
    nongenericEnumerable := typeof(System.Collections.IEnumerable)

    owner := TypeOfCreateBuilder(
        typeName,
        "CompilationReferenceResolver.DiagnosticEnumerable." + typeName,
        0
    )
    owner.AddInterfaceImplementation(genericEnumerable)
    owner.AddInterfaceImplementation(nongenericEnumerable)
    enumeratorField := SourceDiscoveryTimingDefineField(owner, "Enumerator", genericEnumerator)

    constructor := owner.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        noParameters
    )
    constructorIl := constructor.GetILGenerator()
    objectConstructor := ExecutorRequiredConstructor(typeof(object), noParameters)
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Call, objectConstructor)
    constructorIl.Emit(OpCodes.Ret)

    genericGetEnumeratorTarget := ExecutorRequiredMethod(genericEnumerable, "GetEnumerator", noParameters)
    genericGetEnumerator := owner.DefineMethod(
        "GenericGetEnumerator",
        (MethodAttributes)481,
        genericEnumerator,
        noParameters
    )
    genericGetEnumeratorIl := TypeOfMethodBuilderIL(genericGetEnumerator)
    genericGetEnumeratorIl.Emit(OpCodes.Ldarg_0)
    genericGetEnumeratorIl.Emit(OpCodes.Ldfld, enumeratorField)
    genericGetEnumeratorIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(genericGetEnumerator, genericGetEnumeratorTarget)

    nongenericGetEnumeratorTarget := ExecutorRequiredMethod(
        nongenericEnumerable,
        "GetEnumerator",
        noParameters
    )
    nongenericGetEnumerator := owner.DefineMethod(
        "NongenericGetEnumerator",
        (MethodAttributes)481,
        typeof(System.Collections.IEnumerator),
        noParameters
    )
    nongenericGetEnumeratorIl := TypeOfMethodBuilderIL(nongenericGetEnumerator)
    exceptionParameters := new Type[](1)
    exceptionParameters[0] = typeof(string)
    exceptionConstructor := ExecutorRequiredConstructor(typeof(InvalidOperationException), exceptionParameters)
    nongenericGetEnumeratorIl.Emit(OpCodes.Ldstr, "nongeneric diagnostic enumeration reached")
    nongenericGetEnumeratorIl.Emit(OpCodes.Newobj, exceptionConstructor)
    nongenericGetEnumeratorIl.Emit(OpCodes.Throw)
    owner.DefineMethodOverride(nongenericGetEnumerator, nongenericGetEnumeratorTarget)

    baked := IdentityBake(owner)
    instanceConstructor := ExecutorRequiredConstructor(baked, noParameters)
    instance := instanceConstructor.Invoke(new object[](0))
    if instance == null {
        throw new InvalidOperationException("The diagnostic enumerable fixture was not constructed.")
    }
    bakedEnumeratorField := baked.GetField("Enumerator")
    if bakedEnumeratorField == null {
        throw new InvalidOperationException("The diagnostic enumerable fixture lost its Enumerator field.")
    }
    enumeratorObject: object = enumerator
    bakedEnumeratorField.SetValue(instance, enumeratorObject)
    return instance
}

func ResolverFormatCompilerDiagnostics(errors: object): Array {
    method := ResolverPrivateMethod("FormatCompilerDiagnostics", 1)
    arguments := new object?[](1)
    ResolverSetObject(arguments, 0, errors)
    rawResult := ResolverInvoke(method, arguments)
    result := rawResult as Array
    if result == null {
        throw new InvalidOperationException("FormatCompilerDiagnostics returned no rows.")
    }
    return result
}

func ResolverDiagnosticIteratorState(enumerator: object): int {
    field := enumerator.GetType().GetField("<>__state")
    if field == null {
        throw new InvalidOperationException("The diagnostic iterator state field was not found.")
    }
    return Convert.ToInt32(field.GetValue(enumerator))
}

func ResolverCaptureDiagnosticFormattingFailure(errors: object): Exception? {
    captured: Exception? = null
    try {
        ignored := ResolverFormatCompilerDiagnostics(errors)
        _ = ignored
    } catch e: Exception {
        captured = e
    }
    return ResolverInnerException(captured)
}
