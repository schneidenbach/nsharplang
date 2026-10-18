namespace NSharpLang.ReferenceResolution.Tests

import System
import System.Collections.Generic
import System.IO
import System.Net.Http
import System.Reflection
import System.Reflection.Emit
import System.Text.Json
import NSharpLang.Cli
import NSharpLang.Compiler

func ResolverAssertPublicMethod(owner: Type, name: string, parameterTypes: Type[], returnType: Type): MethodInfo {
    method := owner.GetMethod(name, parameterTypes)
    if method == null {
        throw new InvalidOperationException("The public resolver method was not found: " + name)
    }
    assert method.get_IsPublic()
    assert method.get_IsStatic()
    assert method.get_ReturnType() == returnType
    return method
}

test "CompilationReferenceResolver has exactly the three cross assembly entries and keeps its HTTP state private" {
    owner := ResolverOwnerType()
    assert owner.get_Assembly().GetName().get_Name() == "NSharpLang.Compiler.Driver"
    assert Type.GetType("NSharpLang.Cli.CompilationReferenceResolver, NSharpLang.Cli") == null
    assert owner.get_IsPublic()
    assert owner.get_IsSealed()

    configType := typeof(ProjectConfig)
    optionsType := typeof(ReferenceResolutionOptions)
    addTypes := new Type[](3)
    addTypes[0] = typeof(string)
    addTypes[1] = configType
    addTypes[2] = optionsType
    add := ResolverAssertPublicMethod(owner, "AddResolvedDllReferences", addTypes, typeof(ReferenceResolutionResult))
    addParameters := add.GetParameters()
    assert addParameters[2].get_IsOptional()
    assert addParameters[2].get_DefaultValue() == null

    nameTypes := new Type[](2)
    nameTypes[0] = typeof(string)
    nameTypes[1] = configType
    ResolverAssertPublicMethod(owner, "GetProjectAssemblyName", nameTypes, typeof(string))
    ResolverAssertPublicMethod(owner, "ResolveFrameworkReferenceDirectories", nameTypes, typeof(IReadOnlyList<string>))

    publicMethods := owner.GetMethods(BindingFlags.Static | BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
    publicMethodCount := 0
    publicMethodIndex := 0
    while publicMethodIndex < publicMethods.Length {
        if !publicMethods[publicMethodIndex].get_IsSpecialName() {
            publicMethodCount = publicMethodCount + 1
        }
        publicMethodIndex = publicMethodIndex + 1
    }
    assert publicMethodCount == 3
    assert owner.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly).Length == 0
    privateConstructors := owner.GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
    assert privateConstructors.Length == 1
    assert privateConstructors[0].get_IsPrivate()
    assert owner.GetFields(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.DeclaredOnly).Length == 0

    privateMethods := owner.GetMethods(BindingFlags.Static | BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
    privateMethodCount := 0
    privateMethodIndex := 0
    while privateMethodIndex < privateMethods.Length {
        method := privateMethods[privateMethodIndex]
        if !method.get_IsSpecialName() {
            assert method.get_IsPrivate(), method.get_Name()
            assert method.get_IsStatic(), method.get_Name()
            privateMethodCount = privateMethodCount + 1
        }
        privateMethodIndex = privateMethodIndex + 1
    }
    assert privateMethodCount == 23
    expectedPrivateMethods := new string[](23)
    // Declaration order. `SelectNuGetPackageVersions` is the level-order pass that decides one
    // version per package id before `ResolveNuGetPackage` takes a single asset.
    expectedPrivateMethods[0] = "CreateHttpClient"
    expectedPrivateMethods[1] = "GetStableOutputDirectory"
    expectedPrivateMethods[2] = "ResolveProjectReferences"
    expectedPrivateMethods[3] = "AddImplicitNSharpRuntimeAsset"
    expectedPrivateMethods[4] = "BuildProjectReference"
    expectedPrivateMethods[5] = "LocateBuiltProjectReference"
    expectedPrivateMethods[6] = "FormatCompilerDiagnostics"
    expectedPrivateMethods[7] = "AddImplicitTestDependencies"
    expectedPrivateMethods[8] = "SelectNuGetPackageVersions"
    expectedPrivateMethods[9] = "ResolveNuGetPackage"
    expectedPrivateMethods[10] = "SelectedNuGetVersionsCacheKey"
    expectedPrivateMethods[11] = "EnsurePackageAvailable"
    expectedPrivateMethods[12] = "GetLatestPackageVersion"
    expectedPrivateMethods[13] = "ReadNuGetVersionStrings"
    expectedPrivateMethods[14] = "DownloadPackage"
    expectedPrivateMethods[15] = "TryDeleteDirectoryRecursively"
    expectedPrivateMethods[16] = "ReadPackageIdentity"
    expectedPrivateMethods[17] = "FindFirstElementByLocalName"
    expectedPrivateMethods[18] = "CollectElementsByLocalName"
    expectedPrivateMethods[19] = "ReadPackageDependencies"
    expectedPrivateMethods[20] = "SelectBestAssetAssemblies"
    expectedPrivateMethods[21] = "AddDllReference"
    expectedPrivateMethods[22] = "FindSharedFrameworkDirectory"
    expectedPrivateIndex := 0
    while expectedPrivateIndex < expectedPrivateMethods.Length {
        expectedPrivateMethod := owner.GetMethod(
            expectedPrivateMethods[expectedPrivateIndex],
            BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
        )
        assert expectedPrivateMethod != null, expectedPrivateMethods[expectedPrivateIndex]
        expectedPrivateIndex = expectedPrivateIndex + 1
    }

    fields := owner.GetFields(BindingFlags.Static | BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
    assert fields.Length == 1
    clientField := fields[0]
    assert clientField.get_Name() == "HttpClient"
    assert clientField.get_IsPrivate()
    assert clientField.get_IsStatic()
    assert clientField.get_IsInitOnly()
    assert clientField.get_FieldType() == typeof(HttpClient)
    firstClient := clientField.GetValue(null) as HttpClient
    secondClient := clientField.GetValue(null) as HttpClient
    if firstClient == null {
        throw new InvalidOperationException("The private shared HttpClient field was null.")
    }
    requiredClient: HttpClient = firstClient
    assert Object.ReferenceEquals(firstClient, secondClient)
    timeoutProperty := typeof(HttpClient).GetProperty(nameof(HttpClient.Timeout))
    if timeoutProperty == null {
        throw new InvalidOperationException("HttpClient.Timeout was not found.")
    }
    timeoutValue := timeoutProperty.GetValue(requiredClient)
    if timeoutValue == null {
        throw new InvalidOperationException("The private shared HttpClient Timeout was null.")
    }
    assert timeoutValue.ToString() == "00:02:00"
}

test "compiler diagnostic formatting uses the generic sequence, preserves order, and closes iteration" {
    first := new CompilerError(ErrorCode.InvalidSyntax, "generic first", 1, 1, ErrorSeverity.Error)
    second := new CompilerError(ErrorCode.InvalidSyntax, "generic second", 2, 1, ErrorSeverity.Error)
    successRows := ResolverFormattedDiagnosticRows(first, second)
    successEnumerator := successRows.GetEnumerator()
    successSequence := new ResolverGenericOnlyDiagnostics(successEnumerator)
    formatted := ResolverFormatCompilerDiagnostics(successSequence)
    assert formatted.get_Length() == 2
    firstFormatted := Convert.ToString(formatted.GetValue(0)) ?? ""
    secondFormatted := Convert.ToString(formatted.GetValue(1)) ?? ""
    assert firstFormatted.Contains("generic first", StringComparison.Ordinal)
    assert secondFormatted.Contains("generic second", StringComparison.Ordinal)
    successEnumeratorObject: object = successEnumerator
    assert ResolverDiagnosticIteratorState(successEnumeratorObject) == -2

    beforeFailure := new CompilerError(ErrorCode.InvalidSyntax, "before iteration failure", 1, 1, ErrorSeverity.Error)
    throwingRows := ResolverThrowingDiagnosticRows(beforeFailure)
    throwingEnumerator := throwingRows.GetEnumerator()
    throwingSequence := new ResolverGenericOnlyDiagnostics(throwingEnumerator)
    failure := ResolverCaptureDiagnosticFormattingFailure(throwingSequence)
    if failure == null {
        throw new InvalidOperationException("The throwing diagnostic iterator unexpectedly completed.")
    }
    requiredFailure: Exception = failure
    assert requiredFailure is InvalidOperationException
    assert requiredFailure.Message == "diagnostic iteration failed"
    throwingEnumeratorObject: object = throwingEnumerator
    assert ResolverDiagnosticIteratorState(throwingEnumeratorObject) == -2
}

test "project and local NuGet resolution mutates dependencies in package then project order and returns every runtime asset" {
    projectRoot := ResolverNewTempDirectory("direct-project-package")
    packagesRoot := Path.Combine(projectRoot, "packages")
    previousPackages := Environment.GetEnvironmentVariable("NUGET_PACKAGES")
    try {
        ResolverWriteNewtonsoftPackage(packagesRoot)
        ResolverWriteProjectReferenceFixture(projectRoot)

        config := ResolverParseProject(projectRoot)
        projectReference := config.Dependencies[0]
        assert projectReference.Project == "Shared/project.yml"
        assert config.Dependencies[1].Nuget == "Newtonsoft.Json"
        options := new ReferenceResolutionOptions()
        options.PackagesFolder = packagesRoot
        result := CompilationReferenceResolver.AddResolvedDllReferences(projectRoot, config, options)

        assert CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config) == "App"
        assert !ResolverContainsProjectIdentity(config, projectReference)
        assert ResolverContainsDll(config, "Newtonsoft.Json.dll")
        assert ResolverContainsDll(config, "SharedLib.dll")
        assert ResolverDllIndex(config, "Newtonsoft.Json.dll") < ResolverDllIndex(config, "SharedLib.dll")

        sharedOutput := Path.Combine(Path.Combine(Path.Combine(Path.Combine(projectRoot, "Shared"), "bin"), "Debug/net10.0"), "SharedLib.dll")
        newtonsoftRuntime := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(packagesRoot, "newtonsoft.json"), "13.0.3"), "lib"), "net6.0"), "Newtonsoft.Json.dll")
        assert File.Exists(sharedOutput)
        assert ResolverContainsPath(result.RuntimeAssets, sharedOutput)
        assert ResolverContainsPath(result.RuntimeAssets, newtonsoftRuntime)
        assert Directory.GetDirectories(packagesRoot).Length == 1, "The walk left the written package and fetched another."
        runtimeAssetFound := false
        for runtimeAsset in result.RuntimeAssets {
            if string.Equals(Path.GetFileName(runtimeAsset), "NSharpLang.Runtime.dll", StringComparison.OrdinalIgnoreCase) {
                runtimeAssetFound = true
            }
        }
        assert runtimeAssetFound
    } finally {
        Directory.Delete(projectRoot, true)
    }
    assert Environment.GetEnvironmentVariable("NUGET_PACKAGES") == previousPackages, "Resolving against a named packages folder must leave the process environment alone."
}

test "package recursion caches before descent preserves identity and keeps aggregate ref preference" {
    scratch := ResolverNewTempDirectory("package-graph")
    packagesRoot := Path.Combine(scratch, "packages")
    try {
        rootRef := ResolverFrameworkAssembly("System.Text.Json.dll")
        rootRuntime := ResolverFrameworkAssembly("System.Xml.Linq.dll")
        leftRuntime := ResolverFrameworkAssembly("System.Net.Primitives.dll")
        sharedRuntime := ResolverFrameworkAssembly("System.Runtime.dll")
        rightRuntime := ResolverFrameworkAssembly("System.Collections.dll")
        ignoredRuntime := ResolverFrameworkAssembly("System.Console.dll")
        aggregateRuntime := ResolverFrameworkAssembly("System.Numerics.dll")

        ResolverWritePackage(
            packagesRoot,
            "Root.Pkg",
            "1.0.0",
            "<dependencies><group targetFramework=\"net8.0\"><dependency id=\"Ignored.Pkg\" version=\"[1.0.0]\" /></group><group targetFramework=\"net10.0\"><dependency id=\"Left.Pkg\" version=\"[1.0.0]\" /><dependency id=\"Right.Pkg\" version=\"[1.0.0]\" /></group></dependencies>",
            rootRef,
            rootRuntime
        )
        ResolverWritePackage(
            packagesRoot,
            "Left.Pkg",
            "1.0.0",
            "<dependencies><dependency id=\"Shared.Pkg\" version=\"[1.0.0]\" /><dependency id=\"Root.Pkg\" version=\"[1.0.0]\" /></dependencies>",
            null,
            leftRuntime
        )
        ResolverWritePackage(
            packagesRoot,
            "Right.Pkg",
            "1.0.0",
            "<dependencies><dependency id=\"Shared.Pkg\" version=\"[1.0.0]\" /></dependencies>",
            null,
            rightRuntime
        )
        ResolverWritePackage(packagesRoot, "Shared.Pkg", "1.0.0", "", null, sharedRuntime)
        ResolverWritePackage(packagesRoot, "Ignored.Pkg", "1.0.0", "", null, ignoredRuntime)
        libOnlyDirectory := ResolverWritePackage(packagesRoot, "Lib.Only", "1.0.0", "", null, rightRuntime)
        aggregateDirectory := ResolverWritePackage(
            packagesRoot,
            "Aggregate.Pkg",
            "1.0.0",
            "<dependencies><dependency id=\"Root.Pkg\" version=\"[1.0.0]\" /></dependencies>",
            null,
            aggregateRuntime
        )
        ResolverWritePackage(packagesRoot, "Versioned.Pkg", "1.0.0", "", null, null)
        ResolverWritePackage(packagesRoot, "Versioned.Pkg", "2.0.0", "", null, null)

        context := new ResolutionContext(packagesRoot)
        assert context.PackagesRoot == Path.GetFullPath(packagesRoot)
        assets := ResolverPackageAssets("Root.Pkg", "1.0.0", "net10.0", context)
        sameAssets := ResolverPackageAssets("ROOT.PKG", "1.0.0", "net10.0", context)
        assert Object.ReferenceEquals(assets, sameAssets)

        keys := new string[](context.PackageAssets.Count)
        keyIndex := 0
        for entry in context.PackageAssets {
            keys[keyIndex] = entry.Key
            keyIndex = keyIndex + 1
        }
        assert keys.Length == 4
        assert keys[0] == "Root.Pkg@1.0.0|net10.0|"
        assert keys[1] == "Left.Pkg@1.0.0|net10.0|"
        assert keys[2] == "Shared.Pkg@1.0.0|net10.0|"
        assert keys[3] == "Right.Pkg@1.0.0|net10.0|"
        assert !context.PackageAssets.ContainsKey("Ignored.Pkg@1.0.0|net10.0|")

        rootRefPath := Path.Combine(Path.Combine(Path.Combine(Path.Combine(packagesRoot, "root.pkg/1.0.0"), "ref"), "net10.0"), Path.GetFileName(rootRef))
        rootRuntimePath := Path.Combine(Path.Combine(Path.Combine(Path.Combine(packagesRoot, "root.pkg/1.0.0"), "lib"), "net10.0"), Path.GetFileName(rootRuntime))
        assert assets.CompileAssemblies.Contains(rootRefPath)
        assert !assets.CompileAssemblies.Contains(rootRuntimePath)
        assert assets.RuntimeAssemblies.Contains(rootRuntimePath)
        assert assets.CompileAssemblies.Contains(Path.Combine(Path.Combine(Path.Combine(Path.Combine(packagesRoot, "shared.pkg/1.0.0"), "lib"), "net10.0"), Path.GetFileName(sharedRuntime)))

        libOnly := ResolverPackageAssets("Lib.Only", "1.0.0", "net10.0", new ResolutionContext(packagesRoot))
        libOnlyPath := Path.Combine(Path.Combine(Path.Combine(libOnlyDirectory, "lib"), "net10.0"), Path.GetFileName(rightRuntime))
        assert libOnly.CompileAssemblies.Contains(libOnlyPath)
        assert libOnly.RuntimeAssemblies.Contains(libOnlyPath)

        aggregate := ResolverPackageAssets("Aggregate.Pkg", "1.0.0", "net10.0", new ResolutionContext(packagesRoot))
        aggregateRuntimePath := Path.Combine(Path.Combine(Path.Combine(aggregateDirectory, "lib"), "net10.0"), Path.GetFileName(aggregateRuntime))
        assert !aggregate.CompileAssemblies.Contains(aggregateRuntimePath)
        assert aggregate.RuntimeAssemblies.Contains(aggregateRuntimePath)
        assert aggregate.CompileAssemblies.Contains(rootRefPath)

        selectedLatest := ResolverEnsurePackage(context.PackagesRoot, "Versioned.Pkg", null)
        selectedExplicit := ResolverEnsurePackage(context.PackagesRoot, "Versioned.Pkg", "1.0.0")
        assert string.Equals(Path.GetFileName(selectedLatest), "2.0.0", StringComparison.Ordinal)
        assert string.Equals(Path.GetFileName(selectedExplicit), "1.0.0", StringComparison.Ordinal)
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "project stack cleanup survives failure and the same context then caches one successful output" {
    projectRoot := ResolverNewTempDirectory("project-stack")
    try {
        ResolverWrite(
            Path.Combine(projectRoot, "project.yml"),
            "name: StackChild\noutputType: library\ntargetFramework: net10.0"
        )
        ResolverWrite(Path.Combine(projectRoot, "Program.nl"), "func Broken(")
        config := ResolverParseProject(projectRoot)
        ResolverWrite(Path.Combine(projectRoot, "Ignored.tests.nl"), "func BrokenTest(")
        options := new ReferenceResolutionOptions("Release", true, true, true, false)
        context := new ResolutionContext()

        inner := ResolverCaptureProjectBuildFailure(projectRoot, config, options, context)
        if inner == null {
            throw new InvalidOperationException("The failed project build did not retain an exception.")
        }
        requiredInner: Exception = inner
        assert requiredInner is InvalidOperationException
        assert requiredInner.Message.Contains("Project reference '", StringComparison.Ordinal)
        assert requiredInner.Message.Contains("project.yml' failed to build:", StringComparison.Ordinal)
        assert context.ActiveProjectRoots.Count == 0
        assert context.ProjectOutputs.Count == 0

        ResolverWrite(Path.Combine(projectRoot, "Program.nl"), "func Value(): int {\n    return 7\n}")
        first := ResolverBuildProject(projectRoot, config, options, context)
        assert first != null
        assert context.ActiveProjectRoots.Count == 0
        assert context.ProjectOutputs.Count == 1
        outputPath := Path.Combine(Path.Combine(Path.Combine(projectRoot, "bin"), "Release/net10.0"), "StackChild.dll")
        assert File.Exists(outputPath)
        second := ResolverBuildProject(projectRoot, config, options, context)
        assert Object.ReferenceEquals(first, second)
        assert context.ActiveProjectRoots.Count == 0
        assert context.ProjectOutputs.Count == 1
    } finally {
        Directory.Delete(projectRoot, true)
    }
}

test "Web SDK framework resolution adds the runtime assemblies before analysis" {
    projectRoot := ResolverNewTempDirectory("web-framework")
    try {
        ResolverWriteWebFixture(projectRoot)
        config := ResolverParseProject(projectRoot)
        result := CompilationReferenceResolver.AddResolvedDllReferences(projectRoot, config, null)
        assert result != null
        assert ResolverContainsDll(config, "Microsoft.AspNetCore.dll")
        assert ResolverContainsDll(config, "Microsoft.Extensions.Hosting.dll")
    } finally {
        Directory.Delete(projectRoot, true)
    }
}

test "AOT project reference failure retains the source row and adds no child output" {
    scratch := ResolverNewTempDirectory("aot-child")
    try {
        directRoot := Path.Combine(scratch, "direct")
        Directory.CreateDirectory(directRoot)
        ResolverWriteAotProjectFixture(directRoot, "library")
        config := ResolverParseProject(directRoot)
        projectReference := config.Dependencies[0]
        options := new ReferenceResolutionOptions("Debug", false, true, false, true)
        captured := ResolverCaptureReferenceResolutionFailure(directRoot, config, options)
        if captured == null {
            throw new InvalidOperationException("The AOT project reference unexpectedly succeeded.")
        }
        requiredFailure: Exception = captured
        assert requiredFailure is InvalidOperationException
        assert requiredFailure.Message.Contains("AOT builds require successful N# columnar emission", StringComparison.Ordinal)
        assert ResolverContainsProjectIdentity(config, projectReference)
        assert !ResolverContainsDll(config, "SharedLib.dll")
        directOutput := Path.Combine(Path.Combine(Path.Combine(Path.Combine(directRoot, "Shared"), "bin"), "Debug/net10.0"), "SharedLib.dll")
        assert !File.Exists(directOutput)
    } finally {
        Directory.Delete(scratch, true)
    }
}

// THE PACKAGES FOLDER IS STATE OF ONE RESOLUTION, NOT OF THE PROCESS. A named folder is how a caller
// resolves against another cache; rewriting `NUGET_PACKAGES` instead leaked into every thread of the
// parallel estate. The default is decided exactly as NuGet decides it, and a project reference's
// options carry the named folder into the resolution it starts.
test "a resolution context decides its packages folder once and a named folder wins without touching the environment" {
    previousPackages := Environment.GetEnvironmentVariable("NUGET_PACKAGES")
    nugetRule := CompilationReferenceResolverKernels.GetGlobalPackagesFolder(
        previousPackages,
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
    )
    defaultContext := new ResolutionContext()
    unnamedContext := new ResolutionContext(null)
    blankContext := new ResolutionContext("  ")
    assert defaultContext.PackagesRoot == nugetRule
    assert unnamedContext.PackagesRoot == nugetRule
    assert blankContext.PackagesRoot == nugetRule

    namedFolder := Path.Combine(Path.GetTempPath(), "nsharp-reference-resolution-named-packages")
    namedContext := new ResolutionContext(namedFolder)
    assert namedContext.PackagesRoot == Path.GetFullPath(namedFolder)

    options := new ReferenceResolutionOptions()
    assert options.PackagesFolder == null
    options.PackagesFolder = namedFolder
    projectReferenceOptions := CompilationReferenceResolverKernels.GetProjectReferenceResolutionOptions(options)
    assert projectReferenceOptions.PackagesFolder == namedFolder
    assert !projectReferenceOptions.IncludeTests
    assert Environment.GetEnvironmentVariable("NUGET_PACKAGES") == previousPackages
}

// ── `UseBuiltProjectReferences`: a `project:` dependency read from its own build ─────────────────

// Base <- Mid <- App, each a library whose one function calls the one below it.
func ResolverWriteBuiltReferenceChain(root: string) {
    ResolverWrite(Path.Combine(Path.Combine(root, "Base"), "project.yml"), "name: BuiltBase\noutputType: library\ntargetFramework: net10.0")
    ResolverWrite(Path.Combine(Path.Combine(root, "Base"), "Base.nl"), "namespace Built\n\nfunc BaseValue(): int {\n    return 1\n}\n")
    ResolverWrite(Path.Combine(Path.Combine(root, "Mid"), "project.yml"), "name: BuiltMid\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../Base/project.yml")
    ResolverWrite(Path.Combine(Path.Combine(root, "Mid"), "Mid.nl"), "namespace Built\n\nfunc MidValue(): int {\n    return BaseValue() + 1\n}\n")
    ResolverWrite(Path.Combine(Path.Combine(root, "App"), "project.yml"), "name: BuiltApp\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../Mid/project.yml")
    ResolverWrite(Path.Combine(Path.Combine(root, "App"), "App.nl"), "namespace Built\n\nfunc AppValue(): int {\n    return MidValue() + 1\n}\n")
}

func ResolverBuiltOptions(): ReferenceResolutionOptions {
    options := new ReferenceResolutionOptions("Debug", false, true, true, false)
    options.UseBuiltProjectReferences = true
    return options
}

func ResolverBuiltAssembly(root: string, project: string, assemblyName: string): string {
    return Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, project), "bin"), "Debug"), "net10.0"), assemblyName + ".dll")
}

// Every file under `directory` stamped with one time, so a row decides what is newer than what.
func ResolverStampTree(directory: string, stamp: DateTime) {
    for path in Directory.GetFiles(directory, "*", SearchOption.AllDirectories) {
        File.SetLastWriteTimeUtc(path, stamp)
    }
}

test "a built project reference is read from its own build, transitively, and nothing is compiled or written" {
    root := ResolverNewTempDirectory("built-references")
    try {
        ResolverWriteBuiltReferenceChain(root)
        appRoot := Path.Combine(root, "App")

        // Nothing is built yet: the reference is refused by name, not compiled.
        missing := ResolverCaptureReferenceResolutionFailure(appRoot, ResolverParseProject(appRoot), ResolverBuiltOptions())
        assert missing != null
        missingMessage := missing?.Message ?? ""
        assert missingMessage.Contains("Mid" + Path.DirectorySeparatorChar + "project.yml' has no built assembly at '", StringComparison.Ordinal), missingMessage
        assert missingMessage.Contains("--use-built-references", StringComparison.Ordinal), missingMessage
        assert !File.Exists(ResolverBuiltAssembly(root, "Mid", "BuiltMid"))

        // A source resolution builds Mid and Base into their own stable output directories.
        CompilationReferenceResolver.AddResolvedDllReferences(appRoot, ResolverParseProject(appRoot), new ReferenceResolutionOptions("Debug", false, true, true, false))
        midDll := ResolverBuiltAssembly(root, "Mid", "BuiltMid")
        baseDll := ResolverBuiltAssembly(root, "Base", "BuiltBase")
        assert File.Exists(midDll) && File.Exists(baseDll)

        // Sources older than the assemblies: both references are current.
        ResolverStampTree(Path.Combine(root, "Base"), new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc))
        ResolverStampTree(Path.Combine(root, "Mid"), new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc))
        builtAt := new DateTime(2021, 1, 1, 0, 0, 0, DateTimeKind.Utc)
        File.SetLastWriteTimeUtc(midDll, builtAt)
        File.SetLastWriteTimeUtc(baseDll, builtAt)

        config := ResolverParseProject(appRoot)
        result := CompilationReferenceResolver.AddResolvedDllReferences(appRoot, config, ResolverBuiltOptions())
        assert ResolverContainsDll(config, "BuiltMid.dll")
        // Base's types reach App through Mid, as a source build's transitive closure gives them.
        assert ResolverContainsDll(config, "BuiltBase.dll")
        assert result.ProjectOutputAssemblies.Count == 2
        // Read where the builds left them, and not rewritten.
        assert File.GetLastWriteTimeUtc(midDll) == builtAt
        assert File.GetLastWriteTimeUtc(baseDll) == builtAt
    } finally {
        Directory.Delete(root, true)
    }
}

test "a built project reference older than a product source is refused by name, and an edited row does not make it stale" {
    root := ResolverNewTempDirectory("built-references-stale")
    try {
        ResolverWriteBuiltReferenceChain(root)
        appRoot := Path.Combine(root, "App")
        CompilationReferenceResolver.AddResolvedDllReferences(appRoot, ResolverParseProject(appRoot), new ReferenceResolutionOptions("Debug", false, true, true, false))
        ResolverStampTree(Path.Combine(root, "Base"), new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc))
        ResolverStampTree(Path.Combine(root, "Mid"), new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc))
        builtAt := new DateTime(2021, 1, 1, 0, 0, 0, DateTimeKind.Utc)
        File.SetLastWriteTimeUtc(ResolverBuiltAssembly(root, "Mid", "BuiltMid"), builtAt)
        File.SetLastWriteTimeUtc(ResolverBuiltAssembly(root, "Base", "BuiltBase"), builtAt)

        // A row is not part of the product build a reference is.
        rowPath := Path.Combine(Path.Combine(root, "Base"), "Base.tests.nl")
        ResolverWrite(rowPath, "namespace Built\n\ntest \"base\" {\n    assert BaseValue() == 1\n}\n")
        File.SetLastWriteTimeUtc(rowPath, new DateTime(2022, 1, 1, 0, 0, 0, DateTimeKind.Utc))
        CompilationReferenceResolver.AddResolvedDllReferences(appRoot, ResolverParseProject(appRoot), ResolverBuiltOptions())

        // A product source edited after the build is, and the TRANSITIVE reference is checked too.
        basePath := Path.Combine(Path.Combine(root, "Base"), "Base.nl")
        File.SetLastWriteTimeUtc(basePath, new DateTime(2022, 1, 1, 0, 0, 0, DateTimeKind.Utc))
        stale := ResolverCaptureReferenceResolutionFailure(appRoot, ResolverParseProject(appRoot), ResolverBuiltOptions())
        assert stale != null
        staleMessage := stale?.Message ?? ""
        assert staleMessage.Contains("Base" + Path.DirectorySeparatorChar + "project.yml' is out of date: '" + basePath + "' is newer than its built assembly", StringComparison.Ordinal), staleMessage
    } finally {
        Directory.Delete(root, true)
    }
}

test "a product source is a .nl outside bin and obj that is not a row" {
    assert CompilationReferenceResolverKernels.IsProductSourcePath("Program.nl")
    assert CompilationReferenceResolverKernels.IsProductSourcePath("Slice/Deep.nl")
    assert !CompilationReferenceResolverKernels.IsProductSourcePath("Program.tests.nl")
    assert !CompilationReferenceResolverKernels.IsProductSourcePath("bin/Debug/Generated.nl")
    assert !CompilationReferenceResolverKernels.IsProductSourcePath("obj/Generated.nl")
    assert !CompilationReferenceResolverKernels.IsProductSourcePath("notes.md")

    // The nested resolution a reference's own references take keeps the choice.
    options := ResolverBuiltOptions()
    assert CompilationReferenceResolverKernels.GetProjectReferenceResolutionOptions(options).UseBuiltProjectReferences
    assert !CompilationReferenceResolverKernels.GetProjectReferenceResolutionOptions(new ReferenceResolutionOptions()).UseBuiltProjectReferences
}

test "framework selection never picks a platform-specific group or folder for a platform-neutral target" {
    // Microsoft.EntityFrameworkCore.Sqlite's closure lists an Android group before the plain one;
    // both scored as `net8.0`, so the first (Android) won and the app shipped the Android native
    // package. NuGet's FrameworkReducer never reduces `net10.0` to `net8.0-android`.
    groups: string?[] = ["net8.0-android34.0", "net8.0-ios17.0", "net8.0", "netstandard2.0"]
    assert CompilationReferenceResolverKernels.SelectBestDependencyGroupIndex(groups, "net10.0") == 2

    withoutPlain: string?[] = ["net8.0-android34.0", "netstandard2.0"]
    assert CompilationReferenceResolverKernels.SelectBestDependencyGroupIndex(withoutPlain, "net10.0") == 1

    onlyPlatform: string?[] = ["net8.0-android34.0", "net9.0-ios18.0"]
    assert CompilationReferenceResolverKernels.SelectBestDependencyGroupIndex(onlyPlatform, "net10.0") == -1

    folders: string[] = ["net8.0-android34.0", "net9.0", "net8.0", "netstandard2.1", "net48"]
    assert CompilationReferenceResolverKernels.SelectBestAssetDirectoryIndex(folders, "net10.0") == 1

    // A platform target accepts its own platform and the neutral frameworks, nothing else.
    windowsFolders: string[] = ["net8.0-android34.0", "net8.0", "net10.0-windows7.0"]
    assert CompilationReferenceResolverKernels.SelectBestAssetDirectoryIndex(windowsFolders, "net10.0-windows7.0") == 2
    assert CompilationReferenceResolverKernels.SelectBestAssetDirectoryIndex(windowsFolders, "net10.0-windows") == 2
    androidFolders: string[] = ["net8.0-ios17.0", "net8.0-android34.0", "net8.0"]
    assert CompilationReferenceResolverKernels.SelectBestAssetDirectoryIndex(androidFolders, "net9.0-android35.0") == 1

    // The asset's platform version must not exceed the target's.
    versions: string[] = ["net8.0-android35.0", "net8.0-android33.0", "net8.0"]
    assert CompilationReferenceResolverKernels.SelectBestAssetDirectoryIndex(versions, "net9.0-android34.0") == 1
    assert CompilationReferenceResolverKernels.SelectBestAssetDirectoryIndex(versions, "net9.0-android") == 2

    // .NET Standard ends at 2.1; a framework with no version is compatible with nothing.
    standards: string[] = ["netstandard2.2", "netstandard3.0", "netstandard2.1"]
    assert CompilationReferenceResolverKernels.SelectBestAssetDirectoryIndex(standards, "net10.0") == 2
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("netstandard", "net10.0") == -1
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("net10.0", "net") == -1
}

test "an empty winning dependency group means no dependencies, not the next group's" {
    scratch := ResolverNewTempDirectory("empty-group")
    packagesRoot := Path.Combine(scratch, "packages")
    try {
        ResolverWritePackage(
            packagesRoot,
            "Grouped.Pkg",
            "1.0.0",
            "<dependencies><group targetFramework=\"net10.0\" /><group targetFramework=\"netstandard2.0\"><dependency id=\"Never.Restored\" version=\"[1.0.0]\" /></group></dependencies>",
            null,
            ResolverFrameworkAssembly("System.Collections.dll")
        )
        assets := ResolverPackageAssets("Grouped.Pkg", "1.0.0", "net10.0", new ResolutionContext(packagesRoot))
        assert assets.RuntimeFiles.Count == 1
        assert Directory.GetDirectories(packagesRoot).Length == 1, "The empty net10.0 group fell through to netstandard2.0 and fetched its dependency."
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "the runtime identifier fallback walks from the exact RID to any" {
    macOs := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("osx-arm64")
    assert string.Join(",", macOs) == "osx-arm64,osx,unix-arm64,unix,any"

    versionedMac := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("osx.14-arm64")
    assert string.Join(",", versionedMac) == "osx.14-arm64,osx.14,osx-arm64,osx,unix-arm64,unix,any"

    ubuntu := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("ubuntu.22.04-x64")
    assert string.Join(",", ubuntu) == "ubuntu.22.04-x64,ubuntu.22.04,ubuntu-x64,ubuntu,debian-x64,debian,linux-x64,linux,unix-x64,unix,any"

    alpine := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("linux-musl-arm64")
    assert string.Join(",", alpine) == "linux-musl-arm64,linux-musl,linux-arm64,linux,unix-arm64,unix,any"

    windows := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("win10-x64")
    assert string.Join(",", windows) == "win10-x64,win10,win81-x64,win81,win8-x64,win8,win7-x64,win7,win-x64,win,any"

    linux := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("linux-x64")
    assert string.Join(",", linux) == "linux-x64,linux,unix-x64,unix,any"

    osx := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("osx-x64")
    assert string.Join(",", osx) == "osx-x64,osx,unix-x64,unix,any"

    win := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("win-x64")
    assert string.Join(",", win) == "win-x64,win,any"

    debian := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("debian.12-x64")
    assert string.Join(",", debian) == "debian.12-x64,debian.12,debian-x64,debian,linux-x64,linux,unix-x64,unix,any"

    rhelFamily := CompilationReferenceResolverKernels.GetRuntimeIdentifierFallbacks("rocky.9-x64")
    assert string.Join(",", rhelFamily) == "rocky.9-x64,rocky.9,rocky-x64,rocky,rhel-x64,rhel,linux-x64,linux,unix-x64,unix,any"

    assert CompilationReferenceResolverKernels.GetDependencyManifestTargetName("net10.0") == ".NETCoreApp,Version=v10.0"
    assert CompilationReferenceResolverKernels.GetDependencyManifestTargetName("net9.0-windows") == ".NETCoreApp,Version=v9.0"
    assert CompilationReferenceResolverKernels.GetDependencyManifestTargetName("netcoreapp3.1") == ".NETCoreApp,Version=v3.1"
    assert CompilationReferenceResolverKernels.GetDependencyManifestTargetName("netstandard2.0") == ".NETStandard,Version=v2.0"
    assert CompilationReferenceResolverKernels.GetDependencyManifestTargetName("net48") == ".NETFramework,Version=v4.8"
}

test "a native library is found beside the assemblies, then by the RID fallback order" {
    scratch := ResolverNewTempDirectory("native-probe")
    try {
        isWindows := OperatingSystem.IsWindows()
        isMacOS := OperatingSystem.IsMacOS()
        fileName := CompilationReferenceResolverKernels.GetNativeLibraryFileNames("probe", isWindows, isMacOS)[1]
        family := "unix"
        runtimeIdentifier := "linux-x64"
        if isWindows {
            family = "win"
            runtimeIdentifier = "win-x64"
        } else if isMacOS {
            runtimeIdentifier = "osx-arm64"
        }

        decoy := Path.Combine(scratch, "runtimes/any/native/" + fileName)
        expected := Path.Combine(scratch, "runtimes/" + family + "/native/" + fileName)
        ResolverWrite(decoy, "any")
        assert TestCommandKernels.FindNativeLibraryPath(scratch, "probe", runtimeIdentifier) == decoy
        ResolverWrite(expected, "family")
        assert TestCommandKernels.FindNativeLibraryPath(scratch, "probe", runtimeIdentifier) == expected
        beside := Path.Combine(scratch, fileName)
        ResolverWrite(beside, "beside")
        assert TestCommandKernels.FindNativeLibraryPath(scratch, "probe", runtimeIdentifier) == beside
        assert TestCommandKernels.FindNativeLibraryPath(scratch, "missing", runtimeIdentifier) == null
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "a package's runtimes layout is copied beside the output and named by deps.json runtimeTargets rows" {
    scratch := ResolverNewTempDirectory("runtime-targets")
    packagesRoot := Path.Combine(scratch, "packages")
    try {
        versionDirectory := ResolverWritePackage(packagesRoot, "Native.Pkg", "1.2.3", "", null, ResolverFrameworkAssembly("System.Text.Json.dll"))
        ResolverWrite(Path.Combine(versionDirectory, "native.pkg.1.2.3.nupkg.sha512"), "abc==\n")
        ResolverWrite(Path.Combine(versionDirectory, "runtimes/osx-arm64/native/libnative.dylib"), "mac")
        ResolverWrite(Path.Combine(versionDirectory, "runtimes/linux-x64/native/libnative.so"), "linux")
        ResolverWrite(Path.Combine(versionDirectory, "runtimes/linux-x64/native/_._"), "")
        ResolverWrite(Path.Combine(versionDirectory, "runtimes/win-x64/native/native.dll"), "windows")
        windowsOnly := Path.Combine(versionDirectory, "runtimes/win/lib/net8.0")
        Directory.CreateDirectory(windowsOnly)
        File.Copy(ResolverFrameworkAssembly("System.Collections.dll"), Path.Combine(windowsOnly, "Win.Only.dll"), true)
        ResolverWrite(Path.Combine(versionDirectory, "runtimes/linux-x64/native/nested/libdeep.so"), "deep")
        ResolverWrite(Path.Combine(versionDirectory, "runtimes/win10-x64/nativeassets/uap10.0/uap.dll"), "uap")
        ResolverWrite(Path.Combine(versionDirectory, "runtimes/win10-x64/nativeassets/net8.0/better.dll"), "better")
        olderWindows := Path.Combine(versionDirectory, "runtimes/win/lib/netstandard2.0")
        Directory.CreateDirectory(olderWindows)
        File.Copy(ResolverFrameworkAssembly("System.Collections.dll"), Path.Combine(olderWindows, "Win.Older.dll"), true)

        assets := ResolverPackageAssets("Native.Pkg", "1.2.3", "net10.0", new ResolutionContext(packagesRoot))
        assert assets.RuntimeFiles.Count == 7
        relativePaths := new List<string>()
        for runtimeFile in assets.RuntimeFiles {
            relativePaths.Add(runtimeFile.RelativePath)
        }
        assert relativePaths.Contains("lib/net10.0/System.Text.Json.dll")
        assert relativePaths.Contains("runtimes/osx-arm64/native/libnative.dylib")
        assert relativePaths.Contains("runtimes/linux-x64/native/libnative.so")
        assert relativePaths.Contains("runtimes/win-x64/native/native.dll")
        assert relativePaths.Contains("runtimes/win/lib/net8.0/Win.Only.dll")
        assert relativePaths.Contains("runtimes/linux-x64/native/nested/libdeep.so")
        assert relativePaths.Contains("runtimes/win10-x64/nativeassets/net8.0/better.dll")
        assert !relativePaths.Contains("runtimes/win10-x64/nativeassets/uap10.0/uap.dll")
        assert !relativePaths.Contains("runtimes/win/lib/netstandard2.0/Win.Older.dll")
        assert !relativePaths.Contains("runtimes/linux-x64/native/_._")

        outputDirectory := Path.Combine(scratch, "out")
        Directory.CreateDirectory(outputDirectory)
        result := new ReferenceResolutionResult()
        for runtimeFile in assets.RuntimeFiles {
            result.AddPackageFile(runtimeFile)
        }
        for runtimeAssembly in assets.RuntimeAssemblies {
            result.AddRuntimeAsset(runtimeAssembly)
        }
        result.CopyRuntimeAssets(outputDirectory)
        assert File.Exists(Path.Combine(outputDirectory, "System.Text.Json.dll"))
        assert File.Exists(Path.Combine(outputDirectory, "runtimes/osx-arm64/native/libnative.dylib"))
        assert File.Exists(Path.Combine(outputDirectory, "runtimes/linux-x64/native/libnative.so"))
        assert File.Exists(Path.Combine(outputDirectory, "runtimes/win/lib/net8.0/Win.Only.dll"))

        ResolverWrite(Path.Combine(scratch, "project.yml"), "name: App\nversion: 2.0.0\noutputType: exe\ntargetFramework: net10.0")
        config := ResolverParseProject(scratch)
        assemblyPath := Path.Combine(outputDirectory, "App.dll")
        File.Copy(ResolverFrameworkAssembly("System.Runtime.dll"), assemblyPath, true)
        DependencyManifestWriter.Write(config, result, assemblyPath)

        manifestPath := Path.Combine(outputDirectory, "App.deps.json")
        assert File.Exists(manifestPath)
        using manifest := JsonDocument.Parse(File.ReadAllText(manifestPath))
        root := manifest.RootElement
        targetName := ".NETCoreApp,Version=v10.0"
        assert root.GetProperty("runtimeTarget").GetProperty("name").GetString() == targetName
        target := root.GetProperty("targets").GetProperty(targetName)
        assert target.GetProperty("App/2.0.0").GetProperty("runtime").GetProperty("App.dll").ValueKind == JsonValueKind.Object
        packageNode := target.GetProperty("Native.Pkg/1.2.3")
        assert packageNode.GetProperty("runtime").GetProperty("lib/net10.0/System.Text.Json.dll").ValueKind == JsonValueKind.Object
        mac := packageNode.GetProperty("runtimeTargets").GetProperty("runtimes/osx-arm64/native/libnative.dylib")
        assert mac.GetProperty("rid").GetString() == "osx-arm64"
        assert mac.GetProperty("assetType").GetString() == "native"
        windowsManaged := packageNode.GetProperty("runtimeTargets").GetProperty("runtimes/win/lib/net8.0/Win.Only.dll")
        assert windowsManaged.GetProperty("rid").GetString() == "win"
        assert windowsManaged.GetProperty("assetType").GetString() == "runtime"
        libraries := root.GetProperty("libraries")
        assert libraries.GetProperty("App/2.0.0").GetProperty("type").GetString() == "project"
        library := libraries.GetProperty("Native.Pkg/1.2.3")
        assert library.GetProperty("type").GetString() == "package"
        assert library.GetProperty("sha512").GetString() == "sha512-abc=="
        assert library.GetProperty("path").GetString() == "native.pkg/1.2.3"
        assert library.GetProperty("hashPath").GetString() == "native.pkg.1.2.3.nupkg.sha512"
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "a project reference flows the packages and frameworks only it declares into the referencing project" {
    projectRoot := ResolverNewTempDirectory("transitive-package")
    packagesRoot := Path.Combine(projectRoot, "packages")
    try {
        ResolverWriteNewtonsoftPackage(packagesRoot)
        ResolverWrite(
            Path.Combine(projectRoot, "lib/project.yml"),
            "name: CLib\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\nsdk: Microsoft.NET.Sdk.Web\ndependencies:\n  - framework: Microsoft.AspNetCore.App\n  - nuget: Newtonsoft.Json\n    version: 13.0.3"
        )
        ResolverWrite(Path.Combine(projectRoot, "lib/Lib.nl"), "func Greeting(): string {\n    return \"hello\"\n}")
        ResolverWrite(
            Path.Combine(projectRoot, "tests/project.yml"),
            "name: CTests\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../lib/project.yml"
        )
        testsRoot := Path.Combine(projectRoot, "tests")
        config := ResolverParseProject(testsRoot)
        options := new ReferenceResolutionOptions()
        options.PackagesFolder = packagesRoot
        result := CompilationReferenceResolver.AddResolvedDllReferences(testsRoot, config, options)

        assert ResolverContainsDll(config, "Newtonsoft.Json.dll"), "The referenced project's package did not reach the referencing project's compilation."
        assert ResolverContainsDll(config, "CLib.dll")
        newtonsoftRuntime := Path.Combine(packagesRoot, "newtonsoft.json/13.0.3/lib/net6.0/Newtonsoft.Json.dll")
        assert ResolverContainsPath(result.RuntimeAssets, newtonsoftRuntime)
        assert ResolverContainsPath(result.CompileReferences, newtonsoftRuntime)
        frameworks := CompilationReferenceResolverKernels.GetFrameworkReferenceNames(config.Sdk, config.Dependencies)
        assert string.Join(",", frameworks) == "Microsoft.AspNetCore.App"
        assert ResolverContainsDll(config, "Microsoft.AspNetCore.dll")
    } finally {
        Directory.Delete(projectRoot, true)
    }
}

test "a test project that hosts an application in-process receives the application's deps.json" {
    projectRoot := ResolverNewTempDirectory("mvc-testing")
    packagesRoot := Path.Combine(projectRoot, "packages")
    try {
        ResolverWritePackage(packagesRoot, "Microsoft.AspNetCore.Mvc.Testing", "1.0.0", "", null, null)
        ResolverWrite(Path.Combine(projectRoot, "app/project.yml"), "name: N6App\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0")
        ResolverWrite(Path.Combine(projectRoot, "app/Program.nl"), "func main() {\n    print \"hello\"\n}")
        ResolverWrite(
            Path.Combine(projectRoot, "tests/project.yml"),
            "name: N6Tests\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../app/project.yml\n  - nuget: Microsoft.AspNetCore.Mvc.Testing\n    version: 1.0.0"
        )
        ResolverWrite(
            Path.Combine(projectRoot, "plain/project.yml"),
            "name: PlainTests\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../app/project.yml"
        )
        options := new ReferenceResolutionOptions()
        options.PackagesFolder = packagesRoot

        testsRoot := Path.Combine(projectRoot, "tests")
        result := CompilationReferenceResolver.AddResolvedDllReferences(testsRoot, ResolverParseProject(testsRoot), options)
        appManifest := Path.Combine(projectRoot, "app/bin/Debug/net10.0/N6App.deps.json")
        assert File.Exists(appManifest)
        assert File.ReadAllText(appManifest).Contains("N6App/1.0.0")
        assert ResolverContainsPath(result.RuntimeAssets, appManifest)

        appRoot := Path.GetFullPath(Path.Combine(projectRoot, "app"))
        assert result.ContentRoots.Count == 1
        outputDirectory := Path.Combine(projectRoot, "tests-out")
        result.CopyRuntimeAssets(outputDirectory)
        assert File.Exists(Path.Combine(outputDirectory, "N6App.deps.json"))
        assert TestCommandKernels.HostsApplications(outputDirectory)
        assert File.ReadAllText(Path.Combine(outputDirectory, "MvcTestingAppManifest.json")).Contains(appRoot.Replace("\\", "\\\\"))

        plainRoot := Path.Combine(projectRoot, "plain")
        plain := CompilationReferenceResolver.AddResolvedDllReferences(plainRoot, ResolverParseProject(plainRoot), options)
        assert !ResolverContainsPath(plain.RuntimeAssets, appManifest), "Only a project that hosts the application in-process needs its deps.json."
        assert plain.ContentRoots.Count == 0
    } finally {
        Directory.Delete(projectRoot, true)
    }
}

// A Newtonsoft.Json package of the given version whose assembly carries that version, with the one
// `net6.0` folder and no dependencies: what the diamond rows need to tell two versions apart.
func ResolverWriteNewtonsoftVersion(packagesRoot: string, version: string, assemblyVersion: string) {
    versionDirectory := Path.Combine(Path.Combine(packagesRoot, "newtonsoft.json"), version)
    Directory.CreateDirectory(versionDirectory)
    ResolverWrite(
        Path.Combine(versionDirectory, "newtonsoft.json.nuspec"),
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<package xmlns=\"http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd\"><metadata><id>Newtonsoft.Json</id><version>" + version + "</version><dependencies><group targetFramework=\"net6.0\" /></dependencies></metadata></package>"
    )
    stagingPath := Path.Combine(versionDirectory, "staging.dll")
    assembly := new PersistedAssemblyBuilder(new AssemblyName("Newtonsoft.Json, Version=" + assemblyVersion), typeof(object).get_Assembly())
    assembly.DefineDynamicModule("Newtonsoft.Json.dll")
    assembly.Save(stagingPath)
    libraryDirectory := Path.Combine(Path.Combine(versionDirectory, "lib"), "net6.0")
    Directory.CreateDirectory(libraryDirectory)
    File.Move(stagingPath, Path.Combine(libraryDirectory, "Newtonsoft.Json.dll"), true)
}

func ResolverWriteLibraryProject(root: string, name: string, dependencies: string) {
    ResolverWrite(
        Path.Combine(root, name + "/project.yml"),
        "name: " + name + "\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\ndependencies:\n" + dependencies
    )
    ResolverWrite(Path.Combine(root, name + "/" + name + ".nl"), "func " + name + "Greeting(): string {\n    return \"hello\"\n}")
}

func ResolverNewtonsoftPaths(config: ProjectConfig): List<string> {
    paths := new List<string>()
    for reference in config.Dependencies {
        if reference.Dll != null && string.Equals(Path.GetFileName(reference.Dll ?? ""), "Newtonsoft.Json.dll", StringComparison.OrdinalIgnoreCase) {
            paths.Add(Path.GetFullPath(reference.Dll ?? "").Replace('\\', '/'))
        }
    }
    return paths
}

test "a flowed compile reference never duplicates an assembly: the project's own wins, otherwise the highest version" {
    projectRoot := ResolverNewTempDirectory("flow-diamond")
    packagesRoot := Path.Combine(projectRoot, "packages")
    try {
        ResolverWriteNewtonsoftVersion(packagesRoot, "12.0.3", "12.0.0.0")
        ResolverWriteNewtonsoftVersion(packagesRoot, "13.0.3", "13.0.0.0")
        newtonsoft12 := "  - nuget: Newtonsoft.Json\n    version: 12.0.3\n"
        newtonsoft13 := "  - nuget: Newtonsoft.Json\n    version: 13.0.3\n"
        ResolverWriteLibraryProject(projectRoot, "ThirteenLib", newtonsoft13)
        ResolverWriteLibraryProject(projectRoot, "TwelveLib", newtonsoft12)

        // The project's own Newtonsoft.Json 12 against a referenced project's 13.
        ResolverWrite(
            Path.Combine(projectRoot, "own/project.yml"),
            "name: Own\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\ndependencies:\n" + newtonsoft12 + "  - project: ../ThirteenLib/project.yml\n"
        )
        options := new ReferenceResolutionOptions()
        options.PackagesFolder = packagesRoot
        ownRoot := Path.Combine(projectRoot, "own")
        ownConfig := ResolverParseProject(ownRoot)
        CompilationReferenceResolver.AddResolvedDllReferences(ownRoot, ownConfig, options)
        ownPaths := ResolverNewtonsoftPaths(ownConfig)
        assert ownPaths.Count == 1, string.Join(",", ownPaths)
        assert ownPaths[0].Contains("/12.0.3/")

        // Two referenced projects that disagree: the higher version, whichever is listed first.
        ResolverWrite(
            Path.Combine(projectRoot, "both/project.yml"),
            "name: Both\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../TwelveLib/project.yml\n  - project: ../ThirteenLib/project.yml\n"
        )
        bothRoot := Path.Combine(projectRoot, "both")
        bothConfig := ResolverParseProject(bothRoot)
        CompilationReferenceResolver.AddResolvedDllReferences(bothRoot, bothConfig, options)
        bothPaths := ResolverNewtonsoftPaths(bothConfig)
        assert bothPaths.Count == 1, string.Join(",", bothPaths)
        assert bothPaths[0].Contains("/13.0.3/")
    } finally {
        Directory.Delete(projectRoot, true)
    }
}

test "a package only the end of a project reference chain declares reaches the first project" {
    projectRoot := ResolverNewTempDirectory("flow-chain")
    packagesRoot := Path.Combine(projectRoot, "packages")
    try {
        ResolverWriteNewtonsoftPackage(packagesRoot)
        ResolverWriteLibraryProject(projectRoot, "ChainC", "  - nuget: Newtonsoft.Json\n    version: 13.0.3\n")
        ResolverWriteLibraryProject(projectRoot, "ChainB", "  - project: ../ChainC/project.yml\n")
        ResolverWriteLibraryProject(projectRoot, "ChainA", "  - project: ../ChainB/project.yml\n")
        options := new ReferenceResolutionOptions()
        options.PackagesFolder = packagesRoot
        chainRoot := Path.Combine(projectRoot, "ChainA")
        config := ResolverParseProject(chainRoot)
        result := CompilationReferenceResolver.AddResolvedDllReferences(chainRoot, config, options)
        assert ResolverNewtonsoftPaths(config).Count == 1
        assert ResolverContainsDll(config, "ChainB.dll")
        assert ResolverContainsDll(config, "ChainC.dll")
        assert ResolverContainsPath(result.RuntimeAssets, Path.Combine(packagesRoot, "newtonsoft.json/13.0.3/lib/net6.0/Newtonsoft.Json.dll"))
    } finally {
        Directory.Delete(projectRoot, true)
    }
}

test "a malformed referenced project.yml is reported as the project reference failure" {
    projectRoot := ResolverNewTempDirectory("flow-malformed")
    try {
        ResolverWrite(Path.Combine(projectRoot, "bad/project.yml"), "name: [unterminated\n  - : :")
        ResolverWrite(Path.Combine(projectRoot, "app/project.yml"), "name: App\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../bad/project.yml\n")
        appRoot := Path.Combine(projectRoot, "app")
        failure: Exception? = null
        try {
            CompilationReferenceResolver.AddResolvedDllReferences(appRoot, ResolverParseProject(appRoot), new ReferenceResolutionOptions())
        } catch captured: Exception {
            failure = captured
        }
        assert failure != null
    } finally {
        Directory.Delete(projectRoot, true)
    }
}
