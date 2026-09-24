namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Runtime.Loader
import Microsoft.Build.Framework
import NSharpLang.Cli

// The reference packs sit in `<dotnet root>/packs` beside the `shared` directory the running
// framework lives in. Counting parent directories off `GetRuntimeDirectory()` gets this wrong,
// because that path ends in a separator and the first `GetDirectoryName` only strips it -- which
// lands on `<dotnet root>/shared` and finds no packs at all on an installation whose root is not
// where the count assumed. The production kernel already locates the `shared` root for any layout,
// so ask it and take the directory holding it.
func RuntimePairingFindReferencePackAssembly(simpleName: string): string {
    sharedRoots := CompilationReferenceResolverKernels.GetDotnetSharedRootCandidates(RuntimeEnvironment.GetRuntimeDirectory())
    rootIndex := 0
    while rootIndex < sharedRoots.Length {
        dotnetRoot := Path.GetDirectoryName(sharedRoots[rootIndex])
        referencePackRoot := Path.Combine(Path.Combine(dotnetRoot ?? "", "packs"), "Microsoft.NETCore.App.Ref")
        if dotnetRoot != null && Directory.Exists(referencePackRoot) {
            versionDirectories := Directory.GetDirectories(referencePackRoot, "*", SearchOption.TopDirectoryOnly)
            index := 0
            while index < versionDirectories.Length {
                candidate := Path.Combine(Path.Combine(Path.Combine(versionDirectories[index], "ref"), "net10.0"), simpleName + ".dll")
                if File.Exists(candidate) {
                    return candidate
                }

                index = index + 1
            }
        }

        rootIndex = rootIndex + 1
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
    runtimeSourcePath := ExternalHostAssembly().get_Location()
    referenceSourcePath := ExternalHostReferenceImagePath()

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
        selected := ExternalAssemblyScan.SelectRuntimeAssemblyByMetadata(candidates, ExternalHostAssembly(), identity, referencePath)
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
    assert ExternalAssemblyScan.IsCompilerBoundRuntimeAssembly(compilerRuntime, identity)
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

func RuntimePairingInvokeHostedStatic(host: Assembly, methodName: string, arguments: object?[]): object? {
    hostedType := host.GetType("NSharpLang.Compiler.ExternalAssemblyScan")
    if hostedType == null {
        throw new InvalidOperationException("The hosted ExternalAssemblyScan type was not found.")
    }

    method := hostedType.GetMethod(methodName)
    if method == null {
        throw new InvalidOperationException("The hosted method '" + methodName + "' was not found.")
    }

    return method.Invoke(null, arguments)
}

func RuntimePairingSingle(only: object?): object?[] {
    arguments := new object?[](1)
    RuntimePairingSetObject(arguments, 0, only)
    return arguments
}

func RuntimePairingPair(first: object?, second: object?): object?[] {
    arguments := new object?[](2)
    RuntimePairingSetObject(arguments, 0, first)
    RuntimePairingSetObject(arguments, 1, second)
    return arguments
}

func RuntimePairingTriple(first: object?, second: object?, third: object?): object?[] {
    arguments := new object?[](3)
    RuntimePairingSetObject(arguments, 0, first)
    RuntimePairingSetObject(arguments, 1, second)
    RuntimePairingSetObject(arguments, 2, third)
    return arguments
}

// THE COMPILER RUNNING INSIDE ITS HOST, which is how it rebuilds itself. MSBuild loads the build
// task and this library into a load context of its own and keeps its own `Microsoft.Build.*`
// implementation in the context that one defers to. The package reference contract for
// `Microsoft.Build.Framework` therefore has to pair with a handle the compiler's context does not
// OWN but does BIND; a load-context object comparison answers no, the contract is left with no
// executable implementation, and the field type `ITaskItem[]` resolves to nothing.
//
// The topology is reproduced rather than modelled: a second copy of the compiler - Model, which
// owns this library, and Core, whose task MSBuild actually loads and whose references carry
// `Microsoft.Build.Framework` - is loaded into a context of its own, so inside that copy
// `CompilerLoadContext()` is that context while the host's `Microsoft.Build.Framework` stays in the
// context it defers to. Both the pairing decision and the reference-contract lookup that consumes it
// are then asked of the hosted copy.
test "a compiler hosted in a delegating load context pairs a package reference with its host implementation" {
    modelPath := typeof(ExternalAssemblyScan).get_Assembly().get_Location()
    assert modelPath.Length > 0 && File.Exists(modelPath)
    // Core is found the way the compiler finds its own slices, not by naming one of its types: this
    // row belongs to Model's estate, and a Model row that names a higher slice's type cannot build
    // once Model's estate is Model's own assembly.
    corePath := ""
    for slice in ExternalAssemblyScan.CompilerSliceAssemblies() {
        if slice.GetName().Name == "NSharpLang.Compiler.Core" {
            corePath = slice.get_Location()
        }
    }
    assert corePath.Length > 0 && File.Exists(corePath), "The compiler's load context carries its Core slice."
    assert corePath != modelPath, "Model and Core are separate assemblies of the compiler."

    referencePath := RuntimePairingFindNuGetReferenceAssembly("microsoft.build.framework", "Microsoft.Build.Framework")
    assert referencePath.Length > 0
    assert ExternalAssemblyScan.IsHostDependencyReferencePath(referencePath)
    assert ExternalAssemblyScan.HasUsableRuntimeContract(referencePath)

    hostRuntime := typeof(ITaskItem).get_Assembly()
    identity := hostRuntime.GetName().get_FullName()
    assert AssemblyName.GetAssemblyName(referencePath).get_FullName() == identity
    assert Path.GetFullPath(hostRuntime.get_Location()) != Path.GetFullPath(ExternalAssemblyScan.RuntimePathForReferenceContract(referencePath)), "The host implementation must come from a different file than the package's own runtime asset."

    hostedContext := RuntimePairingCreateNonCollectibleContext()
    hostedModel := RuntimePairingLoadAssembly(hostedContext, modelPath)
    hostedCore := RuntimePairingLoadAssembly(hostedContext, corePath)
    assert !Object.ReferenceEquals(hostedModel, typeof(ExternalAssemblyScan).get_Assembly()), "The hosted copy must be a distinct load of this library."
    assert Object.ReferenceEquals(AssemblyLoadContext.GetLoadContext(hostedCore), AssemblyLoadContext.GetLoadContext(hostedModel)), "Both slices of the hosted compiler share its context."
    assert !Object.ReferenceEquals(AssemblyLoadContext.GetLoadContext(hostedModel), AssemblyLoadContext.GetLoadContext(hostRuntime)), "A context-object comparison must answer no for this pair; only the binder question can answer yes."
    assert Convert.ToBoolean(
        RuntimePairingInvokeHostedStatic(hostedModel, "CompilerAssemblyReferencesIdentity", RuntimePairingSingle(identity))
    ), "The hosted compiler references the host dependency through Core, the slice that declares it."

    assert Convert.ToBoolean(
        RuntimePairingInvokeHostedStatic(hostedModel, "IsCompilerBoundRuntimeAssembly", RuntimePairingPair(hostRuntime, identity))
    ), "A compiler context that defers a name it does not carry binds the handle its host owns."

    byIdentity := new Dictionary<string, Assembly>(StringComparer.Ordinal)
    byIdentity[identity] = hostRuntime
    hostedSelection := RuntimePairingInvokeHostedStatic(hostedModel, "TryLoadExactRuntimeAssembly", RuntimePairingTriple(byIdentity, referencePath, identity)) as Assembly
    assert Object.ReferenceEquals(hostedSelection, hostRuntime), "The package reference contract must keep the implementation the hosted compiler executes against."

    foreignContext := RuntimePairingCreateNonCollectibleContext()
    foreignRuntime := RuntimePairingLoadAssembly(foreignContext, hostRuntime.get_Location())
    assert !Object.ReferenceEquals(foreignRuntime, hostRuntime)
    assert foreignRuntime.GetName().get_FullName() == identity
    assert !Convert.ToBoolean(
        RuntimePairingInvokeHostedStatic(hostedModel, "IsCompilerBoundRuntimeAssembly", RuntimePairingPair(foreignRuntime, identity))
    ), "A same-identity build loaded into an unrelated context is not what the hosted compiler binds."

    wrongIdentity := "Microsoft.Build.Framework, Version=0.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a"
    assert !Convert.ToBoolean(
        RuntimePairingInvokeHostedStatic(hostedModel, "IsCompilerBoundRuntimeAssembly", RuntimePairingPair(hostRuntime, wrongIdentity))
    ), "The binder question stays exact; a different identity cannot be satisfied."
}

test "the binder question refuses absent contexts, absent handles and unbindable identities" {
    hostRuntime := typeof(ITaskItem).get_Assembly()
    identity := hostRuntime.GetName().get_FullName()
    delegatingContext := RuntimePairingCreateNonCollectibleContext() as AssemblyLoadContext
    assert delegatingContext != null

    assert ExternalAssemblyScan.IsContextBoundRuntimeAssembly(delegatingContext, hostRuntime, identity)
    assert !ExternalAssemblyScan.IsContextBoundRuntimeAssembly(null, hostRuntime, identity)
    assert !ExternalAssemblyScan.IsContextBoundRuntimeAssembly(delegatingContext, null, identity)
    assert !ExternalAssemblyScan.IsContextBoundRuntimeAssembly(delegatingContext, hostRuntime, "")

    unbindable := RuntimePairingCreateAssembly("NSharpTests.NeverOnDisk, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null")
    assert !ExternalAssemblyScan.IsContextBoundRuntimeAssembly(delegatingContext, unbindable, unbindable.GetName().get_FullName()), "A name no context can bind is not an executable implementation."
}

// THE HOST'S OWN COPY OF A RESTORED PACKAGE. The SDK that hosts the compiler ships its own build of
// packages the project also restores -- `System.Reflection.MetadataLoadContext` and
// `Microsoft.NET.StringTools` are the ones the compiler meets while rebuilding itself -- so the
// implementation loaded for the contract's identity is a DIFFERENT FILE with a DIFFERENT MODULE
// IDENTITY. Requiring the module identities to agree discards that handle and leaves the reference
// with no runtime types at all, which is worse than the handle it refused: the process cannot hold a
// second assembly of one identity, so there is no other implementation to find.
test "a package contract keeps the host's own copy of its identity when the module identities differ" {
    hostRuntime := typeof(ExternalAssemblyScan).get_Assembly()
    identity := hostRuntime.GetName().get_FullName()
    contractPath := Path.Combine(Path.GetTempPath(), "nsharp-runtime-pairing-host-copy-" + Guid.NewGuid().ToString("N") + "/package/1.0.0/lib/net10.0/" + Path.GetFileName(hostRuntime.get_Location()))
    assert !ExternalAssemblyScan.IsProjectReferenceAssemblyPath(contractPath)
    assert !ExternalAssemblyScan.IsHostDependencyReferencePath(contractPath)

    otherBuild := RuntimePairingCreateAssembly(identity)
    assert otherBuild.GetName().get_FullName() == identity
    assert ExternalAssemblyScan.RuntimeAssemblyModuleVersionId(otherBuild) != ExternalAssemblyScan.RuntimeAssemblyModuleVersionId(hostRuntime), "The contract must describe a different build of the same identity."

    hostCandidates := new Assembly[](1)
    hostCandidates[0] = hostRuntime
    assert Object.ReferenceEquals(
        ExternalAssemblyScan.SelectRuntimeAssemblyByMetadata(hostCandidates, otherBuild, identity, contractPath),
        hostRuntime
    ), "The implementation the compiler binds for the identity is the contract's only executable handle."

    foreignContext := RuntimePairingCreateNonCollectibleContext()
    foreignRuntime := RuntimePairingLoadAssembly(foreignContext, hostRuntime.get_Location())
    assert !Object.ReferenceEquals(foreignRuntime, hostRuntime)
    foreignCandidates := new Assembly[](1)
    foreignCandidates[0] = foreignRuntime
    assert ExternalAssemblyScan.SelectRuntimeAssemblyByMetadata(foreignCandidates, otherBuild, identity, contractPath) == null, "A same-identity build in an unrelated context is still not the compiler's implementation."

    entries := new List<ExternalAssemblyCatalogEntry>()
    entry := new ExternalAssemblyCatalogEntry(hostRuntime.GetName(), identity, contractPath, hostRuntime, true)
    entry.AttachMetadataAssembly(otherBuild)
    entries.Add(entry)
    ExternalAssemblyScan.ReconcileRuntimeAssemblies(entries, ExternalAssemblyScan.LoadedForEmissionByIdentity())
    assert Object.ReferenceEquals(entries[0].RuntimeAssembly, hostRuntime), "Reconciliation must not discard the only implementation the contract can have."
}
