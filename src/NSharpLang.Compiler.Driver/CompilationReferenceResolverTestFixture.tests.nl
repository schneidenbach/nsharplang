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

// NEWTONSOFT.JSON 13.0.3 AS ITS PACKAGE LAYS IT OUT, WRITTEN BY THE FIXTURE. The row used to copy
// the package out of whichever NuGet cache on the machine already held it, so it passed only where
// some earlier build had happened to restore that version, and failed on a clean machine. The
// resolver never opens a package asset: it reads the nuspec and the framework folder NAMES under
// `lib/` and `ref/`, and hands the chosen paths on. So what is written is the real package's shape --
// its nuspec dependency groups and every `lib/` framework folder it ships -- and the row keeps its
// meaning: a net10.0 walk has to pick `lib/net6.0` out of eight, and the empty `net6.0` dependency
// group over the netstandard1.x groups, whose dependencies are absent here and would otherwise be
// downloaded into the packages folder.
//
// Each asset is a real assembly named `Newtonsoft.Json` at 13.0.3's assembly version, with no types:
// the row resolves the root project's references and never compiles it, so nothing binds a member.
func ResolverWriteNewtonsoftPackage(packagesRoot: string): string {
    versionDirectory := Path.Combine(Path.Combine(packagesRoot, "newtonsoft.json"), "13.0.3")
    Directory.CreateDirectory(versionDirectory)
    ResolverWrite(
        Path.Combine(versionDirectory, "newtonsoft.json.nuspec"),
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" + "<package xmlns=\"http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd\">\n" + "  <metadata minClientVersion=\"2.12\">\n" + "    <id>Newtonsoft.Json</id>\n" + "    <version>13.0.3</version>\n" + "    <dependencies>\n" + "      <group targetFramework=\".NETFramework2.0\" />\n" + "      <group targetFramework=\".NETFramework3.5\" />\n" + "      <group targetFramework=\".NETFramework4.0\" />\n" + "      <group targetFramework=\".NETFramework4.5\" />\n" + "      <group targetFramework=\".NETStandard1.0\">\n" + "        <dependency id=\"Microsoft.CSharp\" version=\"4.3.0\" exclude=\"Build,Analyzers\" />\n" + "        <dependency id=\"NETStandard.Library\" version=\"1.6.1\" exclude=\"Build,Analyzers\" />\n" + "        <dependency id=\"System.ComponentModel.TypeConverter\" version=\"4.3.0\" exclude=\"Build,Analyzers\" />\n" + "        <dependency id=\"System.Runtime.Serialization.Primitives\" version=\"4.3.0\" exclude=\"Build,Analyzers\" />\n" + "      </group>\n" + "      <group targetFramework=\".NETStandard1.3\">\n" + "        <dependency id=\"Microsoft.CSharp\" version=\"4.3.0\" exclude=\"Build,Analyzers\" />\n" + "        <dependency id=\"NETStandard.Library\" version=\"1.6.1\" exclude=\"Build,Analyzers\" />\n" + "        <dependency id=\"System.ComponentModel.TypeConverter\" version=\"4.3.0\" exclude=\"Build,Analyzers\" />\n" + "        <dependency id=\"System.Runtime.Serialization.Formatters\" version=\"4.3.0\" exclude=\"Build,Analyzers\" />\n" + "        <dependency id=\"System.Runtime.Serialization.Primitives\" version=\"4.3.0\" exclude=\"Build,Analyzers\" />\n" + "        <dependency id=\"System.Xml.XmlDocument\" version=\"4.3.0\" exclude=\"Build,Analyzers\" />\n" + "      </group>\n" + "      <group targetFramework=\"net6.0\" />\n" + "      <group targetFramework=\".NETStandard2.0\" />\n" + "    </dependencies>\n" + "  </metadata>\n" + "</package>\n"
    )

    assemblyPath := Path.Combine(versionDirectory, "Newtonsoft.Json.dll")
    assembly := new PersistedAssemblyBuilder(new AssemblyName("Newtonsoft.Json, Version=13.0.0.0"), typeof(object).get_Assembly())
    assembly.DefineDynamicModule("Newtonsoft.Json.dll")
    assembly.Save(assemblyPath)

    frameworks := ["net20", "net35", "net40", "net45", "net6.0", "netstandard1.0", "netstandard1.3", "netstandard2.0"]
    for framework in frameworks {
        frameworkDirectory := Path.Combine(Path.Combine(versionDirectory, "lib"), framework)
        Directory.CreateDirectory(frameworkDirectory)
        File.Copy(assemblyPath, Path.Combine(frameworkDirectory, "Newtonsoft.Json.dll"), true)
    }
    File.Delete(assemblyPath)
    return versionDirectory
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
    method := ResolverPrivateMethod("ResolveNuGetPackage", 6)
    arguments := new object?[](6)
    ResolverSetObject(arguments, 0, packageName)
    ResolverSetObject(arguments, 1, version)
    ResolverSetObject(arguments, 2, targetFramework)
    ResolverSetObject(arguments, 3, context)
    ResolverSetObject(arguments, 4, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase))
    ResolverSetObject(arguments, 5, "")
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
