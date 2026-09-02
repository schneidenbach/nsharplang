namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Cli

func ExternalCopyAsset(sourcePath: string, destinationPath: string) {
    directory := Path.GetDirectoryName(destinationPath)
    if directory != null {
        Directory.CreateDirectory(directory)
    }

    File.Copy(sourcePath, destinationPath, true)
}

func ExternalWriteAsset(destinationPath: string, content: string) {
    directory := Path.GetDirectoryName(destinationPath)
    if directory != null {
        Directory.CreateDirectory(directory)
    }

    File.WriteAllText(destinationPath, content)
}

func ExternalContainsPath(paths: IReadOnlyList<string>, expected: string): bool {
    index := 0
    while index < paths.Count {
        if string.Equals(paths[index], expected, StringComparison.OrdinalIgnoreCase) {
            return true
        }

        index = index + 1
    }

    return false
}

test "external assembly scan resolves common types through metadata with exact runtime handles" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        assert scan.Context != null
        assert scan.Entries.Length > 0

        exact := ExternalAssemblyScan.FindExactType(scan, "System.Environment")

        assert exact.Status == ExternalAssemblyTypeLookupStatus.Found
        assert exact.HasRuntimeType
        assert exact.RuntimeType.FullName == "System.Environment"
        assert ExternalAssemblyScan.SemanticIdentityMatches(exact.SemanticTypeIdentity, "System.Environment, System.Private.CoreLib")

        visible := ExternalAssemblyScan.FindFirstVisibleType(scan, "Environment")

        assert visible.Status == ExternalAssemblyTypeLookupStatus.Found
        assert visible.HasRuntimeType
        assert visible.RuntimeType.FullName == "System.Environment"
    } finally {
        scan.Dispose()
    }

    assert scan.Context == null
}

test "external assembly scan ignores host assemblies outside semantic slots" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        yaml := ExternalAssemblyScan.FindExactType(scan, "YamlDotNet.Serialization.NamingConventions.CamelCaseNamingConvention")

        assert yaml.Status == ExternalAssemblyTypeLookupStatus.Missing
        assert !yaml.HasRuntimeType
    } finally {
        scan.Dispose()
    }
}

test "external assembly scan resolves dotted source names for nested CLR types" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        exact := ExternalAssemblyScan.FindExactType(scan, "System.Environment.SpecialFolder")
        assert exact.Status == ExternalAssemblyTypeLookupStatus.Missing

        nested := ExternalAssemblyScan.FindExactOrNestedType(scan, "System.Environment.SpecialFolder")
        assert nested.Status == ExternalAssemblyTypeLookupStatus.Found
        assert nested.HasRuntimeType
        assert nested.RuntimeType.FullName == "System.Environment+SpecialFolder"
    } finally {
        scan.Dispose()
    }
}

test "external assembly scan stops before an unrelated broken reference" {
    paths := new List<string>()
    paths.Add("/nsharp/does-not-exist/unrelated-reference.dll")
    scan := ExternalAssemblyScan.OpenWithReferences(paths)
    try {
        environment := ExternalAssemblyScan.FindExactType(scan, "System.Environment")

        assert environment.Status == ExternalAssemblyTypeLookupStatus.Found
        assert environment.HasRuntimeType

        unknown := ExternalAssemblyScan.FindExactType(scan, "Missing.Namespace.Environment")

        assert unknown.Status == ExternalAssemblyTypeLookupStatus.Unknown
        assert !unknown.HasRuntimeType
    } finally {
        scan.Dispose()
    }
}

test "external assembly scan resolves an MSBuild reference-only path to its project runtime output" {
    runtimeAssembly := typeof(ExternalAssemblyScan).get_Assembly()
    runtimePath := runtimeAssembly.get_Location()
    netDirectory := Path.GetDirectoryName(runtimePath)
    configurationDirectory := Path.GetDirectoryName(netDirectory)
    binDirectory := Path.GetDirectoryName(configurationDirectory)
    projectDirectory := Path.GetDirectoryName(binDirectory)
    assert projectDirectory != null
    configurationName := Path.GetFileName(configurationDirectory)
    targetFrameworkName := Path.GetFileName(netDirectory)
    referenceDirectory := Path.Combine(projectDirectory, "obj/" + configurationName + "/" + targetFrameworkName + "/refint")

    referencePath := Path.Combine(referenceDirectory, Path.GetFileName(runtimePath))

    assert File.Exists(referencePath)

    dependencies := new List<Reference>()
    reference := new Reference()
    reference.Dll = referencePath
    dependencies.Add(reference)
    paths := ExternalAssemblyScan.ResolveReferencePaths(projectDirectory, dependencies)

    assert paths.Count == 2
    assert paths[0] == Path.GetFullPath(referencePath)
    assert paths[1] == Path.GetFullPath(runtimePath)

    scan := ExternalAssemblyScan.OpenWithReferences(paths)
    try {
        resolved := ExternalAssemblyScan.FindExactType(scan, "NSharpLang.Compiler.ExternalAssemblyScan")

        assert resolved.Status == ExternalAssemblyTypeLookupStatus.Found
        assert resolved.HasRuntimeType
        assert resolved.RuntimeType == typeof(ExternalAssemblyScan)
        assert resolved.SemanticTypeIdentity == typeof(ExternalAssemblyScan).get_AssemblyQualifiedName()
    } finally {
        scan.Dispose()
    }
}

test "external reference paths select DLLs normalize project-relative paths and remove duplicates" {
    dependencies := new List<Reference>()
    packageReference := new Reference()
    packageReference.Nuget = "Ignored"
    packageReference.Version = "1.0.0"
    dependencies.Add(packageReference)
    dllReference := new Reference()
    dllReference.Dll = "lib/relative.dll"
    dependencies.Add(dllReference)
    duplicateReference := new Reference()
    duplicateReference.Dll = "/tmp/nsharp-project/lib/relative.dll"
    dependencies.Add(duplicateReference)
    blankReference := new Reference()
    blankReference.Dll = "   "
    dependencies.Add(blankReference)
    paths := ExternalAssemblyScan.ResolveReferencePaths("/tmp/nsharp-project", dependencies)

    assert paths.Count == 1
    assert paths[0] == Path.GetFullPath("/tmp/nsharp-project/lib/relative.dll")
}

test "external reference paths put NuGet metadata before its runtime implementation" {
    bootstrapRuntimePath := typeof(ExternalAssemblyScan).get_Assembly().get_Location()
    netDirectory := Path.GetDirectoryName(bootstrapRuntimePath)
    debugDirectory := Path.GetDirectoryName(netDirectory)
    binDirectory := Path.GetDirectoryName(debugDirectory)
    projectDirectory := Path.GetDirectoryName(binDirectory)
    assert projectDirectory != null
    bootstrapReferencePath := Path.Combine(projectDirectory, "obj/Debug/net10.0/refint/" + Path.GetFileName(bootstrapRuntimePath))

    assert File.Exists(bootstrapReferencePath)

    packageVersionDirectory := Path.GetFullPath("obj/nsharp-reference-pair-contract/package/1.0.0")

    referencePath := Path.Combine(packageVersionDirectory, "ref/net10.0/Paired.dll")

    runtimePath := Path.Combine(packageVersionDirectory, "lib/net10.0/Paired.dll")

    ExternalCopyAsset(bootstrapReferencePath, referencePath)
    ExternalCopyAsset(bootstrapRuntimePath, runtimePath)

    dependencies := new List<Reference>()
    runtimeReference := new Reference()
    runtimeReference.Dll = runtimePath
    dependencies.Add(runtimeReference)
    metadataReference := new Reference()
    metadataReference.Dll = referencePath
    dependencies.Add(metadataReference)

    paths := ExternalAssemblyScan.ResolveReferencePaths(packageVersionDirectory, dependencies)

    assert paths.Count == 2
    assert paths[0] == Path.GetFullPath(referencePath)
    assert paths[1] == Path.GetFullPath(runtimePath)
}

test "external reference paths reject a conventionally located runtime with a different assembly identity" {
    bootstrapRuntimePath := typeof(ExternalAssemblyScan).get_Assembly().get_Location()
    netDirectory := Path.GetDirectoryName(bootstrapRuntimePath)
    debugDirectory := Path.GetDirectoryName(netDirectory)
    binDirectory := Path.GetDirectoryName(debugDirectory)
    projectDirectory := Path.GetDirectoryName(binDirectory)
    assert projectDirectory != null
    bootstrapReferencePath := Path.Combine(projectDirectory, "obj/Debug/net10.0/refint/" + Path.GetFileName(bootstrapRuntimePath))

    assert File.Exists(bootstrapReferencePath)

    packageVersionDirectory := Path.GetFullPath("obj/nsharp-reference-mismatch-contract/package/1.0.0")
    referencePath := Path.Combine(packageVersionDirectory, "ref/net10.0/Mismatched.dll")
    runtimePath := Path.Combine(packageVersionDirectory, "lib/net10.0/Mismatched.dll")
    mismatchedRuntimePath := typeof(MetadataLoadContext).get_Assembly().get_Location()

    ExternalCopyAsset(bootstrapReferencePath, referencePath)
    ExternalCopyAsset(mismatchedRuntimePath, runtimePath)

    dependencies := new List<Reference>()
    metadataReference := new Reference()
    metadataReference.Dll = referencePath
    dependencies.Add(metadataReference)

    referencePaths := ExternalAssemblyScan.ResolveReferencePaths(packageVersionDirectory, dependencies)
    assert referencePaths.Count == 1
    assert referencePaths[0] == Path.GetFullPath(referencePath)

    runtimePaths := ExternalAssemblyScan.ResolveRuntimeAssetPaths(packageVersionDirectory, dependencies)
    assert runtimePaths.Count == 0
}

test "external assembly scan retains reference-only metadata without a runtime pair" {
    coreRuntimePath := typeof(object).get_Assembly().get_Location()
    runtimeVersionDirectory := Path.GetDirectoryName(coreRuntimePath)
    runtimeFrameworkDirectory := Path.GetDirectoryName(runtimeVersionDirectory)

    sharedDirectory := Path.GetDirectoryName(runtimeFrameworkDirectory)
    dotnetRoot := Path.GetDirectoryName(sharedDirectory)
    referencePackRoot := Path.Combine(Path.Combine(dotnetRoot, "packs"), "Microsoft.NETCore.App.Ref")

    runtimeVersion := Path.GetFileName(runtimeVersionDirectory)
    referencePath := Path.Combine(Path.Combine(Path.Combine(referencePackRoot, runtimeVersion), "ref/net10.0"), "System.Formats.Tar.dll")

    if !File.Exists(referencePath) {
        referencePath = ""
        versionDirectories := Directory.GetDirectories(referencePackRoot, "*", SearchOption.TopDirectoryOnly)

        versionIndex := 0
        while versionIndex < versionDirectories.Length {
            candidate := Path.Combine(Path.Combine(versionDirectories[versionIndex], "ref/net10.0"), "System.Formats.Tar.dll")

            if referencePath.Length == 0 && File.Exists(candidate) {
                referencePath = candidate
            }

            versionIndex = versionIndex + 1
        }
    }

    assert File.Exists(referencePath)

    dependencies := new List<Reference>()
    reference := new Reference()
    reference.Dll = referencePath
    dependencies.Add(reference)
    paths := ExternalAssemblyScan.ResolveReferencePaths(dotnetRoot, dependencies)

    assert paths.Count == 1
    assert paths[0] == Path.GetFullPath(referencePath)

    scan := ExternalAssemblyScan.OpenWithReferences(paths)
    try {
        resolved := ExternalAssemblyScan.FindExactType(scan, "System.Formats.Tar.TarEntry")

        assert resolved.Status == ExternalAssemblyTypeLookupStatus.Found
        assert resolved.SemanticTypeIdentity.StartsWith("System.Formats.Tar.TarEntry, System.Formats.Tar", StringComparison.Ordinal)
    } finally {
        scan.Dispose()
    }
}

test "configured DLL runtime assets deploy implementations and retain metadata-only inputs" {
    root := Path.GetFullPath("obj/nsharp-runtime-assets-contract")
    output := Path.Combine(root, "output")
    normalPath := Path.Combine(root, "direct/Normal.dll")
    packageReferencePath := Path.Combine(root, "packages/sample/1.0.0/ref/net10.0/Package.dll")

    packageRuntimePath := Path.Combine(root, "packages/sample/1.0.0/lib/net10.0/Package.dll")

    projectReferencePath := Path.Combine(root, "project/obj/Debug/net10.0/refint/Project.dll")

    projectRuntimePath := Path.Combine(root, "project/bin/Debug/net10.0/Project.dll")

    metadataOnlyPath := Path.Combine(root, "packages/metadata/1.0.0/ref/net10.0/MetadataOnly.dll")

    bootstrapRuntimePath := typeof(ExternalAssemblyScan).get_Assembly().get_Location()
    netDirectory := Path.GetDirectoryName(bootstrapRuntimePath)
    debugDirectory := Path.GetDirectoryName(netDirectory)
    binDirectory := Path.GetDirectoryName(debugDirectory)
    projectDirectory := Path.GetDirectoryName(binDirectory)
    assert projectDirectory != null
    bootstrapReferencePath := Path.Combine(projectDirectory, "obj/Debug/net10.0/refint/" + Path.GetFileName(bootstrapRuntimePath))

    assert File.Exists(bootstrapReferencePath)

    ExternalCopyAsset(bootstrapRuntimePath, normalPath)
    ExternalCopyAsset(bootstrapReferencePath, packageReferencePath)
    ExternalCopyAsset(bootstrapRuntimePath, packageRuntimePath)
    ExternalCopyAsset(bootstrapReferencePath, projectReferencePath)
    ExternalCopyAsset(bootstrapRuntimePath, projectRuntimePath)
    ExternalCopyAsset(bootstrapReferencePath, metadataOnlyPath)

    dependencies := new List<Reference>()
    normal := new Reference()
    normal.Dll = Path.GetRelativePath(root, normalPath)
    dependencies.Add(normal)
    duplicate := new Reference()
    duplicate.Dll = normalPath
    dependencies.Add(duplicate)
    packageReference := new Reference()
    packageReference.Dll = packageReferencePath
    dependencies.Add(packageReference)
    projectReference := new Reference()
    projectReference.Dll = projectReferencePath
    dependencies.Add(projectReference)
    metadataOnly := new Reference()
    metadataOnly.Dll = metadataOnlyPath
    dependencies.Add(metadataOnly)

    runtimePaths := ExternalAssemblyScan.ResolveRuntimeAssetPaths(root, dependencies)

    assert runtimePaths.Count == 3
    assert ExternalContainsPath(runtimePaths, normalPath)
    assert ExternalContainsPath(runtimePaths, packageRuntimePath)
    assert ExternalContainsPath(runtimePaths, projectRuntimePath)
    assert !ExternalContainsPath(runtimePaths, packageReferencePath)
    assert !ExternalContainsPath(runtimePaths, projectReferencePath)
    assert !ExternalContainsPath(runtimePaths, metadataOnlyPath)

    result := ReferenceResolutionResult.Create(root, dependencies)
    assert result.RuntimeAssets.Count == 3
    result.CopyRuntimeAssets(output)
    assert File.Exists(Path.Combine(output, "Normal.dll"))
    assert File.Exists(Path.Combine(output, "Package.dll"))
    assert File.Exists(Path.Combine(output, "Project.dll"))
    assert !File.Exists(Path.Combine(output, "MetadataOnly.dll"))
}

test "runtime asset copy unifies same-filename sources to the highest package version" {
    root := Path.GetFullPath("obj/nsharp-runtime-asset-unify-contract")
    lowerPath := Path.Combine(root, "microsoft.openapi/1.6.17/lib/net9.0/Collision.dll")
    higherPath := Path.Combine(root, "microsoft.openapi/1.6.22/lib/net9.0/Collision.dll")
    output := Path.Combine(root, "output")

    ExternalWriteAsset(lowerPath, "lower-version-asset")
    ExternalWriteAsset(higherPath, "higher-version-asset")

    result := new ReferenceResolutionResult()
    result.AddRuntimeAsset(lowerPath)
    result.AddRuntimeAsset(higherPath)

    // A diamond dependency that flattens two versions of the same assembly name is unified to the
    // single highest version, exactly as NuGet resolves a version conflict, instead of throwing.
    assert result.RuntimeAssets.Count == 2
    result.CopyRuntimeAssets(output)

    copiedPath := Path.Combine(output, "Collision.dll")
    assert File.Exists(copiedPath)
    assert File.ReadAllText(copiedPath) == "higher-version-asset", "The higher package version must win a same-filename runtime-asset collision."
}

test "loaded assemblies index by identity covers the snapshot the walk it replaces would have scanned" {
    assemblies := ExternalAssemblyScan.Loaded()
    byIdentity := ExternalAssemblyScan.LoadedByIdentity()

    assert assemblies.Length > 0
    assert byIdentity.Count > 0
    assert byIdentity.Count <= assemblies.Length, "Indexing cannot invent an assembly the snapshot did not carry."

    // Every identity the linear walk could have matched is present, and the entry it answers really
    // carries that identity — which is the whole contract the walk provided.
    index := 0
    while index < assemblies.Length {
        identity := assemblies[index].GetName().get_FullName()
        assert byIdentity.ContainsKey(identity), "Every loaded assembly identity must be indexed."

        indexed := byIdentity[identity]
        assert indexed != null
        assert indexed.GetName().get_FullName() == identity, "An indexed entry must carry the identity it is keyed by."
        index = index + 1
    }
}

test "exact runtime assembly selection resolves an already-loaded identity through the index" {
    assemblies := ExternalAssemblyScan.Loaded()
    byIdentity := ExternalAssemblyScan.LoadedByIdentity()
    identity := assemblies[0].GetName().get_FullName()

    // The path argument is never consulted when the identity is already loaded, so a path that does
    // not exist still resolves — which is exactly what makes the index a pure lookup.
    resolved := ExternalAssemblyScan.TryLoadExactRuntimeAssembly(byIdentity, "does-not-exist.dll", identity)
    assert resolved != null, "An already-loaded identity resolves without touching the filesystem."
    assert resolved.GetName().get_FullName() == identity

    missingIdentity := "No.Such.Assembly, Version=9.9.9.9, Culture=neutral, PublicKeyToken=null"
    assert !byIdentity.ContainsKey(missingIdentity)
    absent := ExternalAssemblyScan.TryLoadExactRuntimeAssembly(byIdentity, "does-not-exist.dll", missingIdentity)
    assert absent == null, "An identity that is neither loaded nor loadable stays metadata-only."
}

test "a prepared external type catalog answers every file from one retained scan" {
    catalog := new ColumnarExternalTypeCatalog()

    // Before Prepare there is no scan and no answer — the catalog never opens one on demand.
    unpreparedResolution := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert !catalog.IsPrepared
    assert !catalog.TryGet(0, "Console", out unpreparedResolution)

    factsById := new Dictionary<int, ColumnarSourceBindingFacts>()
    firstFile := new ColumnarSourceBindingFacts()
    firstFile.UnaliasedNamespaceImports.Add("System")
    secondFile := new ColumnarSourceBindingFacts()
    secondFile.UnaliasedNamespaceImports.Add("System")
    factsById[0] = firstFile
    factsById[1] = secondFile

    catalog.Prepare(null, factsById)
    assert catalog.IsPrepared

    firstResolution := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    secondResolution := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert catalog.TryGet(0, "Console", out firstResolution)
    assert catalog.TryGet(1, "Console", out secondResolution)

    // Two files asking the same question of the same retained scan get the same answer. Before the
    // scan was retained each of these was a whole MetadataLoadContext over every referenced assembly.
    assert firstResolution.Status == ExternalAssemblyTypeLookupStatus.Found
    assert secondResolution.Status == ExternalAssemblyTypeLookupStatus.Found
    assert firstResolution.HasRuntimeType
    assert secondResolution.HasRuntimeType
    firstType := firstResolution.RuntimeType
    secondType := secondResolution.RuntimeType
    assert firstType.get_FullName() == "System.Console"
    assert secondType.get_FullName() == "System.Console"
    assert firstResolution.SemanticTypeIdentity == secondResolution.SemanticTypeIdentity

    // A repeat of an already-cached key is still the same answer, and a re-Prepare replaces the scan
    // without stranding the catalog.
    repeat := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert catalog.TryGet(0, "Console", out repeat)
    repeatType := repeat.RuntimeType
    assert repeatType.get_FullName() == "System.Console"

    catalog.Prepare(null, factsById)
    afterRePrepare := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert catalog.TryGet(0, "Console", out afterRePrepare)
    afterRePrepareType := afterRePrepare.RuntimeType
    assert afterRePrepareType.get_FullName() == "System.Console"

    // A name that resolves nowhere is still a recorded decline, not an exception.
    missing := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert catalog.TryGet(0, "NoSuchExternalOwnerName", out missing)
    assert missing.Status == ExternalAssemblyTypeLookupStatus.Missing
}
