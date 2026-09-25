namespace NSharpLang.ReferenceResolution.Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection
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

// THE PACKAGE IS WRITTEN, NEVER COPIED FROM THE MACHINE'S CACHE. This row used to copy a real
// Newtonsoft.Json 13.0.3 out of `~/.nuget/packages`, so it passed only on a machine where something
// else had already restored that exact version, and failed on a clean one. The resolver reads only
// the nuspec and the asset folders' file names -- it never opens an asset -- so a framework assembly
// standing in as `Newtonsoft.Json.dll` exercises the same walk. The shape mirrors the real 13.0.3
// package: the net6.0 group has no dependencies, while the netstandard1.0 group has four that are
// NOT written here, so selecting the wrong group would fetch them and fail the row's
// packages-folder assertion instead of passing it.
func ResolverWriteNewtonsoftPackage(packagesRoot: string) {
    versionDirectory := Path.Combine(Path.Combine(packagesRoot, "newtonsoft.json"), "13.0.3")
    ResolverWrite(
        Path.Combine(versionDirectory, "newtonsoft.json.nuspec"),
        "<package><metadata><id>Newtonsoft.Json</id><version>13.0.3</version><dependencies><group targetFramework=\".NETFramework4.5\" /><group targetFramework=\".NETStandard1.0\"><dependency id=\"Microsoft.CSharp\" version=\"4.3.0\" /><dependency id=\"NETStandard.Library\" version=\"1.6.1\" /><dependency id=\"System.ComponentModel.TypeConverter\" version=\"4.3.0\" /><dependency id=\"System.Runtime.Serialization.Primitives\" version=\"4.3.0\" /></group><group targetFramework=\".NETStandard2.0\" /><group targetFramework=\"net6.0\" /></dependencies></metadata></package>"
    )
    standIn := ResolverFrameworkAssembly("System.Runtime.dll")
    libFrameworks := new string[](4)
    libFrameworks[0] = "net45"
    libFrameworks[1] = "netstandard1.0"
    libFrameworks[2] = "netstandard2.0"
    libFrameworks[3] = "net6.0"
    for libFramework in libFrameworks {
        libDirectory := Path.Combine(Path.Combine(versionDirectory, "lib"), libFramework)
        Directory.CreateDirectory(libDirectory)
        File.Copy(standIn, Path.Combine(libDirectory, "Newtonsoft.Json.dll"), true)
    }
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
    // THE SHARED SOURCE MUST BE A SHAPE THE COLUMNAR BACKEND DECLINES, because the failure this
    // fixture exists to produce is the AOT path's "requires successful N# columnar emission". It used
    // to be a `foreach` over a `string`, which the backend now emits as an index loop, then assigning
    // to a struct's own field from its own method, which emits since the call site loads an
    // addressable receiver by address, and then a bare STATIC FIELD as a call receiver, which emits
    // since a static member of the enclosing type is a value binding, and then an `await foreach`
    // inside a generator body. The remaining sentinel is a generic async iterator method: analysis
    // accepts it, while its generic state-machine context is not lowered yet. Replace it when that
    // capability lands rather than deleting this fixture.
    ResolverWrite(
        Path.Combine(sharedDir, "Shared.nl"),
        "import System.Collections.Generic\nimport System.Threading.Tasks\n\nasync func* Pending<T>(value: T): IAsyncEnumerable<T> {\n    await Task.Delay(1)\n    yield value\n}"
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
    owner := Type.GetType("NSharpLang.Cli.CompilationReferenceResolver, NSharpLang.Compiler.Driver")
    if owner == null {
        throw new InvalidOperationException("The N# CompilationReferenceResolver owner was not loadable from Compiler.Driver.")
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

// THE SELECTION MAP IS EMPTY ON PURPOSE. `ResolveNuGetPackage` is the ASSET walk, and the version
// each id resolves at is decided before it runs by `SelectNuGetPackageVersions`. Handing it an
// empty map is what makes the rows below measure the walk itself — descent order, the cache key,
// the aggregate ref/lib preference — against the versions each nuspec declares, unchanged by the
// nearest-wins pass. The rule itself is pinned by `ShouldSelectNuGetPackageCandidate`'s kernel rows
// and end to end by `tests/native/nuget-resolution-fidelity`.
func ResolverPackageAssets(packageName: string, version: string?, targetFramework: string, context: ResolutionContext): NuGetPackageAssets {
    method := ResolverPrivateMethod("ResolveNuGetPackage", 5)
    arguments := new object?[](5)
    ResolverSetObject(arguments, 0, packageName)
    ResolverSetObject(arguments, 1, version)
    ResolverSetObject(arguments, 2, targetFramework)
    ResolverSetObject(arguments, 3, context)
    ResolverSetObject(arguments, 4, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase))
    result := ResolverInvoke(method, arguments) as NuGetPackageAssets
    if result == null {
        throw new InvalidOperationException("ResolveNuGetPackage returned no assets.")
    }
    return result
}

func ResolverEnsurePackage(packagesRoot: string, packageName: string, version: string?): string {
    method := ResolverPrivateMethod("EnsurePackageAvailable", 3)
    arguments := new object?[](3)
    ResolverSetObject(arguments, 0, packagesRoot)
    ResolverSetObject(arguments, 1, packageName)
    ResolverSetObject(arguments, 2, version)
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

// A diagnostic sequence that answers ONLY through its generic slot: the untyped
// `IEnumerable.GetEnumerator` throws, so formatting that walks the sequence untyped fails the row
// instead of passing it. It hands out the enumerator it was given, so the row can read that
// enumerator's state afterwards and see whether formatting closed it.
class ResolverGenericOnlyDiagnostics: IEnumerable<CompilerError> {
    enumerator: IEnumerator<CompilerError>

    constructor(enumerator: IEnumerator<CompilerError>) {
        this.enumerator = enumerator
    }

    func GetEnumerator(): IEnumerator<CompilerError> => enumerator

    func IEnumerable.GetEnumerator(): IEnumerator {
        throw new InvalidOperationException("nongeneric diagnostic enumeration reached")
    }
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
