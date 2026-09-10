namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Runtime.Loader
import Microsoft.Build.Framework

func RuntimePairingFindReferencePackAssembly(simpleName: string): string {
    runtimeDirectory := RuntimeEnvironment.GetRuntimeDirectory()
    versionDirectory := Path.GetDirectoryName(runtimeDirectory)
    frameworkDirectory := Path.GetDirectoryName(versionDirectory ?? "")
    dotnetRoot := Path.GetDirectoryName(frameworkDirectory ?? "")
    if dotnetRoot == null {
        return ""
    }

    referencePackRoot := Path.Combine(Path.Combine(dotnetRoot, "packs"), "Microsoft.NETCore.App.Ref")
    versionDirectories := Directory.GetDirectories(referencePackRoot, "*", SearchOption.TopDirectoryOnly)
    index := 0
    while index < versionDirectories.Length {
        candidate := Path.Combine(Path.Combine(Path.Combine(versionDirectories[index], "ref"), "net10.0"), simpleName + ".dll")
        if File.Exists(candidate) {
            return candidate
        }

        index = index + 1
    }

    return ""
}

func RuntimePairingFindNuGetReferenceAssembly(packageName: string, simpleName: string): string {
    packagesRoot := CompilationReferenceResolverKernels.GetGlobalPackagesFolder(
        Environment.GetEnvironmentVariable("NUGET_PACKAGES"),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
    )
    packageDirectory := Path.Combine(packagesRoot, packageName.ToLowerInvariant())
    versionDirectories := Directory.GetDirectories(packageDirectory, "*", SearchOption.TopDirectoryOnly)
    versionIndex := 0
    while versionIndex < versionDirectories.Length {
        candidate := Path.Combine(Path.Combine(Path.Combine(versionDirectories[versionIndex], "ref"), "net10.0"), simpleName + ".dll")
        if File.Exists(candidate) {
            return candidate
        }

        versionIndex = versionIndex + 1
    }

    return ""
}

func RuntimePairingSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func RuntimePairingCreateNonCollectibleContext(): object {
    contextType := Type.GetType("System.Runtime.Loader.AssemblyLoadContext, System.Runtime.Loader")
    if contextType == null {
        throw new InvalidOperationException("AssemblyLoadContext was not loadable.")
    }

    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(bool)
    constructor := contextType.GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("AssemblyLoadContext(string, bool) was not found.")
    }

    arguments := new object?[](2)
    RuntimePairingSetObject(arguments, 0, "nsharp-emission-runtime-foreign-" + Guid.NewGuid().ToString("N"))
    RuntimePairingSetObject(arguments, 1, false)
    context := constructor.Invoke(arguments)
    if context == null {
        throw new InvalidOperationException("The noncollectible AssemblyLoadContext was not created.")
    }

    return context
}

func RuntimePairingLoadAssembly(context: object, assemblyPath: string): Assembly {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    loadMethod := context.GetType().GetMethod("LoadFromAssemblyPath", parameterTypes)
    if loadMethod == null {
        throw new InvalidOperationException("AssemblyLoadContext.LoadFromAssemblyPath(string) was not found.")
    }

    arguments := new object?[](1)
    RuntimePairingSetObject(arguments, 0, assemblyPath)
    loaded := loadMethod.Invoke(context, arguments) as Assembly
    if loaded == null {
        throw new InvalidOperationException("The foreign runtime assembly was not loaded.")
    }

    return loaded
}

func RuntimePairingCreateAssembly(identity: string): Assembly {
    assembly := AssemblyBuilder.DefineDynamicAssembly(
        new AssemblyName(identity),
        AssemblyBuilderAccess.Run
    )
    assembly.DefineDynamicModule("Main")
    return assembly
}

test "emission runtime index replaces a foreign same identity handle with the compiler context handle" {
    compilerContext := AssemblyLoadContext.GetLoadContext(typeof(ExternalAssemblyScan).get_Assembly())
    if compilerContext == null {
        throw new InvalidOperationException("The compiler AssemblyLoadContext was not available.")
    }

    compilerRuntime := typeof(YamlDotNet.Serialization.DeserializerBuilder).get_Assembly()
    compilerRuntimeContext := AssemblyLoadContext.GetLoadContext(compilerRuntime)
    assert Object.ReferenceEquals(compilerRuntimeContext, compilerContext), "The test dependency must be loaded with the compiler assembly."

    runtimePath := compilerRuntime.get_Location()
    runtimeIdentity := compilerRuntime.GetName().get_FullName()
    assert ExternalAssemblyScan.CompilerAssemblyReferencesIdentity(runtimeIdentity)
    foreignContext := RuntimePairingCreateNonCollectibleContext()
    foreignRuntime := RuntimePairingLoadAssembly(foreignContext, runtimePath)
    foreignRuntimeContext := AssemblyLoadContext.GetLoadContext(foreignRuntime)

    assert !foreignRuntime.IsCollectible, "The collision must mirror a noncollectible production load context."
    assert foreignRuntime.GetName().get_FullName() == runtimeIdentity
    assert Path.GetFullPath(foreignRuntime.get_Location()) == Path.GetFullPath(runtimePath)
    assert !Object.ReferenceEquals(foreignRuntime, compilerRuntime)
    assert !Object.ReferenceEquals(foreignRuntimeContext, compilerRuntimeContext)

    byIdentity := new Dictionary<string, Assembly>(StringComparer.Ordinal)
    byIdentity[runtimeIdentity] = foreignRuntime
    unrelatedIdentity := "NSharpTests.Unrelated.Runtime, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null"
    assert !ExternalAssemblyScan.CompilerAssemblyReferencesIdentity(unrelatedIdentity)
    byIdentity[unrelatedIdentity] = foreignRuntime

    initialRuntime := byIdentity[runtimeIdentity]
    assert Object.ReferenceEquals(initialRuntime, foreignRuntime), "The supplied first winner must begin in the foreign context."
    preferred := ExternalAssemblyScan.PreferEmissionRuntimeAssemblies(byIdentity)

    assert Object.ReferenceEquals(preferred, byIdentity), "Emission normalization must mutate and return the supplied index."
    selectedRuntime := preferred[runtimeIdentity]
    assert Object.ReferenceEquals(selectedRuntime, compilerRuntime), "Exact identity collisions must select the compiler-context runtime handle."
    retainedRuntime := preferred[unrelatedIdentity]
    assert Object.ReferenceEquals(retainedRuntime, foreignRuntime), "An unrelated identity must retain its first winner."

    selected := ExternalAssemblyScan.TryLoadExactRuntimeAssembly(preferred, "does-not-exist.dll", runtimeIdentity)
    assert Object.ReferenceEquals(selected, compilerRuntime), "The downstream runtime lookup must receive the executable compiler-context handle."

    pathSelected := ExternalAssemblyScan.TryLoadExactRuntimeAssembly(preferred, runtimePath, runtimeIdentity)
    assert Object.ReferenceEquals(pathSelected, compilerRuntime), "A same-file duplicate must retain the compiler-context handle when the selected path is executable."

    copiedRuntimePath := Path.Combine(Path.GetTempPath(), "nsharp-runtime-pairing-copy-" + Guid.NewGuid().ToString("N") + ".dll")
    File.Copy(runtimePath, copiedRuntimePath, true)
    try {
        copiedForeignContext := RuntimePairingCreateNonCollectibleContext()
        copiedForeignRuntime := RuntimePairingLoadAssembly(copiedForeignContext, copiedRuntimePath)
        assert Path.GetFullPath(copiedForeignRuntime.get_Location()) == Path.GetFullPath(copiedRuntimePath)
        assert ExternalAssemblyScan.RuntimeAssemblyModuleVersionId(copiedForeignRuntime) == ExternalAssemblyScan.RuntimeAssemblyModuleVersionId(compilerRuntime)
        copiedPathSelected := ExternalAssemblyScan.TryLoadExactRuntimeAssembly(preferred, copiedRuntimePath, runtimeIdentity)
        assert Object.ReferenceEquals(copiedPathSelected, compilerRuntime), "A byte-identical copy must retain the compiler-context handle even when it was loaded from another path."
    } finally {
        File.Delete(copiedRuntimePath)
    }
}

test "metadata module version selects the matching same-identity build" {
    firstBuild := RuntimePairingCreateAssembly("NSharpTests.SameIdentityBuild, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null")
    secondBuild := RuntimePairingCreateAssembly("NSharpTests.SameIdentityBuild, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null")
    identity := secondBuild.GetName().get_FullName()
    firstModuleVersionId := ExternalAssemblyScan.RuntimeAssemblyModuleVersionId(firstBuild)
    secondModuleVersionId := ExternalAssemblyScan.RuntimeAssemblyModuleVersionId(secondBuild)

    assert firstBuild.GetName().get_FullName() == identity
    assert firstModuleVersionId.Length > 0
    assert secondModuleVersionId.Length > 0
    assert firstModuleVersionId != secondModuleVersionId, "Two separately generated builds must not collapse to one module identity."

    candidates := new Assembly[](2)
    candidates[0] = firstBuild
    candidates[1] = secondBuild
    selected := ExternalAssemblyScan.SelectRuntimeAssemblyByMetadata(candidates, secondBuild, identity, "")

    assert selected != null
    assert Object.ReferenceEquals(selected, secondBuild), "Runtime selection must follow the selected metadata MVID, not the first same-AQN candidate."
}

test "exact NuGet ref and lib pairing wins before host dependency preservation" {
    runtimeSourcePath := typeof(ExternalAssemblyScan).get_Assembly().get_Location()
    netDirectory := Path.GetDirectoryName(runtimeSourcePath)
    configurationDirectory := Path.GetDirectoryName(netDirectory)
    binDirectory := Path.GetDirectoryName(configurationDirectory)
    projectDirectory := Path.GetDirectoryName(binDirectory)
    assert projectDirectory != null
    referenceSourcePath := Path.Combine(projectDirectory, "obj/" + Path.GetFileName(configurationDirectory) + "/" + Path.GetFileName(netDirectory) + "/refint/" + Path.GetFileName(runtimeSourcePath))
    assert File.Exists(referenceSourcePath)

    root := Path.Combine(Path.GetTempPath(), "nsharp-runtime-pairing-paired-" + Guid.NewGuid().ToString("N"))
    referencePath := Path.Combine(root, "package/1.0.0/ref/net10.0/Paired.dll")
    runtimePath := Path.Combine(root, "package/1.0.0/lib/net10.0/Paired.dll")
    ExternalCopyAsset(referenceSourcePath, referencePath)
    ExternalCopyAsset(runtimeSourcePath, runtimePath)
    try {
        foreignContext := RuntimePairingCreateNonCollectibleContext()
        foreignRuntime := RuntimePairingLoadAssembly(foreignContext, runtimePath)
        identity := AssemblyName.GetAssemblyName(referencePath).get_FullName()
        candidates := new Assembly[](1)
        candidates[0] = foreignRuntime
        selected := ExternalAssemblyScan.SelectRuntimeAssemblyByMetadata(candidates, typeof(ExternalAssemblyScan).get_Assembly(), identity, referencePath)
        assert Object.ReferenceEquals(selected, foreignRuntime)
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

test "emission runtime preference retains wrong identity refusal" {
    preferred := ExternalAssemblyScan.PreferEmissionRuntimeAssemblies(
        new Dictionary<string, Assembly>(StringComparer.Ordinal)
    )
    compilerRuntime := typeof(YamlDotNet.Serialization.DeserializerBuilder).get_Assembly()
    runtimePath := compilerRuntime.get_Location()
    wrongIdentity := "YamlDotNet, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"

    assert !preferred.ContainsKey(wrongIdentity)
    wrong := ExternalAssemblyScan.TryLoadExactRuntimeAssembly(preferred, runtimePath, wrongIdentity)
    assert wrong == null, "A loadable path cannot satisfy a different assembly identity."
}

test "framework pack metadata resolves its exact shared runtime implementation" {
    referencePath := RuntimePairingFindReferencePackAssembly("System.IO.Compression.ZipFile")
    assert referencePath.Length > 0
    assert ExternalAssemblyScan.IsFrameworkPackReferencePath(referencePath)

    runtimePath := ExternalAssemblyScan.FrameworkRuntimePathForReference(referencePath)
    assert runtimePath.Length > 0
    assert File.Exists(runtimePath)
    assert runtimePath != referencePath

    identity := AssemblyName.GetAssemblyName(referencePath).get_FullName()
    runtimeIdentity := AssemblyName.GetAssemblyName(runtimePath).get_FullName()
    assert identity == runtimeIdentity

    byIdentity := new Dictionary<string, Assembly>(StringComparer.Ordinal)
    selected := ExternalAssemblyScan.TryLoadExactRuntimeAssembly(byIdentity, referencePath, identity)
    assert selected != null
    assert selected.GetName().get_FullName() == identity
    assert Path.GetFullPath(selected.get_Location()) == Path.GetFullPath(runtimePath)
}

test "MSBuild NuGet reference retains the exact compiler-context dependency" {
    referencePath := RuntimePairingFindNuGetReferenceAssembly("microsoft.build.framework", "Microsoft.Build.Framework")
    assert referencePath.Length > 0
    assert ExternalAssemblyScan.IsHostDependencyReferencePath(referencePath)

    compilerRuntime := typeof(ITaskItem).get_Assembly()
    identity := AssemblyName.GetAssemblyName(referencePath).get_FullName()
    assert compilerRuntime.GetName().get_FullName() == identity
    assert ExternalAssemblyScan.HasUsableRuntimeContract(referencePath)

    byIdentity := new Dictionary<string, Assembly>(StringComparer.Ordinal)
    byIdentity[identity] = compilerRuntime
    selected := ExternalAssemblyScan.TryLoadExactRuntimeAssembly(byIdentity, referencePath, identity)
    assert selected != null
    assert Object.ReferenceEquals(selected, compilerRuntime)

    paths := new List<string>()
    paths.Add(referencePath)
    scan := ExternalAssemblyScan.OpenWithReferences(paths)
    try {
        resolved := ExternalAssemblyScan.FindExactType(scan, "Microsoft.Build.Framework.ITaskItem")
        assert resolved.Status == ExternalAssemblyTypeLookupStatus.Found
        assert resolved.HasRuntimeType
        assert resolved.RuntimeType.get_AssemblyQualifiedName() == typeof(ITaskItem).get_AssemblyQualifiedName()
    } finally {
        scan.Dispose()
    }
}

test "unrelated compiler-context assemblies cannot satisfy a NuGet reference contract" {
    referencePackPath := RuntimePairingFindReferencePackAssembly("System.Drawing.Primitives")
    assert referencePackPath.Length > 0
    runtimePath := ExternalAssemblyScan.FrameworkRuntimePathForReference(referencePackPath)
    assert runtimePath.Length > 0

    compilerContext := AssemblyLoadContext.GetLoadContext(typeof(ExternalAssemblyScan).get_Assembly())
    if compilerContext == null {
        throw new InvalidOperationException("The compiler AssemblyLoadContext was not available.")
    }

    compilerRuntime := RuntimePairingLoadAssembly(compilerContext, runtimePath)
    identity := compilerRuntime.GetName().get_FullName()
    assert ExternalAssemblyScan.IsCompilerContextRuntimeAssembly(compilerRuntime)
    assert !ExternalAssemblyScan.CompilerAssemblyReferencesIdentity(identity)

    root := Path.Combine(Path.GetTempPath(), "nsharp-runtime-pairing-unrelated-" + Guid.NewGuid().ToString("N"))
    referencePath := Path.Combine(root, "package/1.0.0/ref/net10.0/Unrelated.dll")
    pairedRuntimePath := Path.Combine(root, "package/1.0.0/lib/net10.0/Unrelated.dll")
    ExternalCopyAsset(referencePackPath, referencePath)
    ExternalCopyAsset(runtimePath, pairedRuntimePath)
    try {
        assert ExternalAssemblyScan.HasUsableRuntimeContract(referencePath)
        byIdentity := new Dictionary<string, Assembly>(StringComparer.Ordinal)
        byIdentity[identity] = compilerRuntime
        selected := ExternalAssemblyScan.TryLoadExactRuntimeAssembly(byIdentity, referencePath, identity)
        assert selected == null
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}
