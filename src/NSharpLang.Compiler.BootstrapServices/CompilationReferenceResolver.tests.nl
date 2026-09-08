namespace NSharpLang.ReferenceResolution.Tests

import System
import System.Collections.Generic
import System.IO
import System.Net.Http
import System.Reflection
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

test "CompilationReferenceResolver has exactly the two cross assembly entries and keeps its HTTP state private" {
    owner := ResolverOwnerType()
    assert owner.get_Assembly().GetName().get_Name() == "NSharpLang.Compiler.BootstrapServices"
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

    publicMethods := owner.GetMethods(BindingFlags.Static | BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
    publicMethodCount := 0
    publicMethodIndex := 0
    while publicMethodIndex < publicMethods.Length {
        if !publicMethods[publicMethodIndex].get_IsSpecialName() {
            publicMethodCount = publicMethodCount + 1
        }
        publicMethodIndex = publicMethodIndex + 1
    }
    assert publicMethodCount == 2
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
    assert privateMethodCount == 22
    expectedPrivateMethods := new string[](22)
    expectedPrivateMethods[0] = "CreateHttpClient"
    expectedPrivateMethods[1] = "GetStableOutputDirectory"
    expectedPrivateMethods[2] = "ResolveProjectReferences"
    expectedPrivateMethods[3] = "AddImplicitNSharpRuntimeAsset"
    expectedPrivateMethods[4] = "BuildProjectReference"
    expectedPrivateMethods[5] = "FormatCompilerDiagnostics"
    expectedPrivateMethods[6] = "AddImplicitTestDependencies"
    expectedPrivateMethods[7] = "ResolveFrameworkReferenceDirectories"
    expectedPrivateMethods[8] = "ResolveNuGetPackage"
    expectedPrivateMethods[9] = "EnsurePackageAvailable"
    expectedPrivateMethods[10] = "GetLatestPackageVersion"
    expectedPrivateMethods[11] = "ReadNuGetVersionStrings"
    expectedPrivateMethods[12] = "DownloadPackage"
    expectedPrivateMethods[13] = "TryDeleteDirectoryRecursively"
    expectedPrivateMethods[14] = "ReadPackageIdentity"
    expectedPrivateMethods[15] = "FindFirstElementByLocalName"
    expectedPrivateMethods[16] = "CollectElementsByLocalName"
    expectedPrivateMethods[17] = "ReadPackageDependencies"
    expectedPrivateMethods[18] = "SelectBestAssetAssemblies"
    expectedPrivateMethods[19] = "AddDllReference"
    expectedPrivateMethods[20] = "GetGlobalPackagesFolder"
    expectedPrivateMethods[21] = "FindSharedFrameworkDirectory"
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
    successSequence := ResolverDistinctDiagnosticEnumerable(successEnumerator, "ResolverDiagnosticSuccess")
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
    throwingSequence := ResolverDistinctDiagnosticEnumerable(throwingEnumerator, "ResolverDiagnosticFailure")
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
        ResolverPrepareNewtonsoftCache(packagesRoot)
        Environment.SetEnvironmentVariable("NUGET_PACKAGES", packagesRoot)
        ResolverWriteProjectReferenceFixture(projectRoot)

        config := ResolverParseProject(projectRoot)
        projectReference := config.Dependencies[0]
        assert projectReference.Project == "Shared/project.yml"
        assert config.Dependencies[1].Nuget == "Newtonsoft.Json"
        result := CompilationReferenceResolver.AddResolvedDllReferences(projectRoot, config, null)

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
        runtimeAssetFound := false
        for runtimeAsset in result.RuntimeAssets {
            if string.Equals(Path.GetFileName(runtimeAsset), "NSharpLang.Runtime.dll", StringComparison.OrdinalIgnoreCase) {
                runtimeAssetFound = true
            }
        }
        assert runtimeAssetFound
    } finally {
        Environment.SetEnvironmentVariable("NUGET_PACKAGES", previousPackages)
        Directory.Delete(projectRoot, true)
    }
    assert Environment.GetEnvironmentVariable("NUGET_PACKAGES") == previousPackages
}

test "package recursion caches before descent preserves identity and keeps aggregate ref preference" {
    scratch := ResolverNewTempDirectory("package-graph")
    packagesRoot := Path.Combine(scratch, "packages")
    previousPackages := Environment.GetEnvironmentVariable("NUGET_PACKAGES")
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

        Environment.SetEnvironmentVariable("NUGET_PACKAGES", packagesRoot)
        context := new ResolutionContext()
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
        assert keys[0] == "Root.Pkg@1.0.0"
        assert keys[1] == "Left.Pkg@1.0.0"
        assert keys[2] == "Shared.Pkg@1.0.0"
        assert keys[3] == "Right.Pkg@1.0.0"
        assert !context.PackageAssets.ContainsKey("Ignored.Pkg@1.0.0")

        rootRefPath := Path.Combine(Path.Combine(Path.Combine(Path.Combine(packagesRoot, "root.pkg/1.0.0"), "ref"), "net10.0"), Path.GetFileName(rootRef))
        rootRuntimePath := Path.Combine(Path.Combine(Path.Combine(Path.Combine(packagesRoot, "root.pkg/1.0.0"), "lib"), "net10.0"), Path.GetFileName(rootRuntime))
        assert assets.CompileAssemblies.Contains(rootRefPath)
        assert !assets.CompileAssemblies.Contains(rootRuntimePath)
        assert assets.RuntimeAssemblies.Contains(rootRuntimePath)
        assert assets.CompileAssemblies.Contains(Path.Combine(Path.Combine(Path.Combine(Path.Combine(packagesRoot, "shared.pkg/1.0.0"), "lib"), "net10.0"), Path.GetFileName(sharedRuntime)))

        libOnly := ResolverPackageAssets("Lib.Only", "1.0.0", "net10.0", new ResolutionContext())
        libOnlyPath := Path.Combine(Path.Combine(Path.Combine(libOnlyDirectory, "lib"), "net10.0"), Path.GetFileName(rightRuntime))
        assert libOnly.CompileAssemblies.Contains(libOnlyPath)
        assert libOnly.RuntimeAssemblies.Contains(libOnlyPath)

        aggregate := ResolverPackageAssets("Aggregate.Pkg", "1.0.0", "net10.0", new ResolutionContext())
        aggregateRuntimePath := Path.Combine(Path.Combine(Path.Combine(aggregateDirectory, "lib"), "net10.0"), Path.GetFileName(aggregateRuntime))
        assert !aggregate.CompileAssemblies.Contains(aggregateRuntimePath)
        assert aggregate.RuntimeAssemblies.Contains(aggregateRuntimePath)
        assert aggregate.CompileAssemblies.Contains(rootRefPath)

        selectedLatest := ResolverEnsurePackage("Versioned.Pkg", null)
        selectedExplicit := ResolverEnsurePackage("Versioned.Pkg", "1.0.0")
        assert string.Equals(Path.GetFileName(selectedLatest), "2.0.0", StringComparison.Ordinal)
        assert string.Equals(Path.GetFileName(selectedExplicit), "1.0.0", StringComparison.Ordinal)
    } finally {
        Environment.SetEnvironmentVariable("NUGET_PACKAGES", previousPackages)
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
