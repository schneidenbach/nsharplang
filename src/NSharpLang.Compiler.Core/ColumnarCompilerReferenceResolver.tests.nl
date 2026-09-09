namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices


// The resolver owns the small reflection path that still decides which runtime Type the columnar
// emitter uses. These controls retain its observable selection order and false/throw boundaries.
func CompilerReferenceSelfAssemblyPath(): string {
    return typeof(ExternalAssemblyScan).get_Assembly().get_Location()
}

func CompilerReferenceAssemblyIn(assemblies: Assembly[], target: Assembly): bool {
    index := 0
    while index < assemblies.Length {
        if Object.ReferenceEquals(assemblies[index], target) {
            return true
        }
        index = index + 1
    }
    return false
}

func CompilerReferenceAspNetAssemblyPath(simpleName: string): string {
    runtimeDirectory := Path.TrimEndingDirectorySeparator(RuntimeEnvironment.GetRuntimeDirectory())
    sharedRoot := AnalyzerMetadataLoadPolicy.SharedRootFromRuntimeDirectory(runtimeDirectory)
    if sharedRoot == null {
        throw new InvalidOperationException("The runtime has no shared framework root.")
    }

    frameworkRoot := Path.Combine(sharedRoot, "Microsoft.AspNetCore.App")
    // Prefer the exact host runtime version. A machine may retain multiple shared-framework
    // directories, and picking an arbitrary first one can make the reference tier inconsistent
    // with the runtime that is executing this control.
    runtimeVersion := Path.GetFileName(runtimeDirectory)
    exactCandidate := Path.Combine(Path.Combine(frameworkRoot, runtimeVersion), simpleName + ".dll")
    if File.Exists(exactCandidate) {
        return exactCandidate
    }

    versionSeparator := runtimeVersion.IndexOf('.')
    runtimeMajor := runtimeVersion
    if versionSeparator > 0 {
        runtimeMajor = runtimeVersion.Substring(0, versionSeparator)
    }

    versions := Directory.GetDirectories(frameworkRoot)
    index := 0
    while index < versions.Length {
        candidateVersion := Path.GetFileName(versions[index])
        if candidateVersion.StartsWith(runtimeMajor + ".", StringComparison.Ordinal) {
            candidate := Path.Combine(versions[index], simpleName + ".dll")
            if File.Exists(candidate) {
                return candidate
            }
        }
        index = index + 1
    }

    throw new InvalidOperationException("The runtime has no ASP.NET assembly '" + simpleName + "'.")
}

test "compiler reference resolver filters exact reference names, continues after a matching load failure, and clears failed out types" {
    assemblyPath := CompilerReferenceSelfAssemblyPath()
    simpleName := Path.GetFileNameWithoutExtension(assemblyPath)
    fullTypeName := "NSharpLang.Compiler.ExternalAssemblyScan"

    paths := new List<string>()
    paths.Add(
        Path.Combine(
            Path.Combine(Path.GetTempPath(), "nsharp-reference-resolver-missing-" + Guid.NewGuid().ToString()),
            simpleName + ".dll"
        )
    )
    paths.Add(assemblyPath)

    resolved: Type = typeof(int)
    assert ColumnarCompilerReferenceResolver.TryResolveReferencedType(
        paths,
        simpleName.ToLowerInvariant(),
        fullTypeName,
        out resolved
    )
    assert resolved == typeof(ExternalAssemblyScan)

    // A valid path whose file name does not match is never loaded for this request.
    filtered: Type = typeof(int)
    assert !ColumnarCompilerReferenceResolver.TryResolveReferencedType(
        paths,
        simpleName + ".other",
        fullTypeName,
        out filtered
    )
    assert filtered == null

    missingType: Type = typeof(int)
    assert !ColumnarCompilerReferenceResolver.TryResolveReferencedType(
        paths,
        simpleName,
        fullTypeName + ".Missing",
        out missingType
    )
    assert missingType == null

    noPaths: Type = typeof(int)
    assert !ColumnarCompilerReferenceResolver.TryResolveReferencedType(
        null,
        simpleName,
        fullTypeName,
        out noPaths
    )
    assert noPaths == null
}

test "compiler reference resolver sees supported dynamic ASP.NET types in AppDomain while the semantic scan filters them" {
    fullTypeName := "Microsoft.AspNetCore.Builder.ReferenceResolverDynamic"
    dynamicBuilder := TypeOfCreateBuilder(
        fullTypeName,
        "ColumnarCompilerReferenceResolver.Dynamic",
        0
    )
    dynamicType := IdentityBake(dynamicBuilder)
    dynamicAssembly := dynamicType.get_Assembly()
    assert dynamicAssembly.get_IsDynamic()
    // `TypeOfCreateBuilder` returns an unfinished TypeBuilder. Confirm the runtime lookup sees
    // that same Type identity before using it to pin this resolver's AppDomain selection.
    dynamicAssemblyType := dynamicAssembly.GetType(fullTypeName)
    assert Object.ReferenceEquals(dynamicAssemblyType, dynamicType)

    // `ExternalAssemblyScan.Loaded` is the metadata catalog snapshot and deliberately excludes
    // dynamic assemblies. This resolver intentionally scans the unfiltered AppDomain instead.
    assert !CompilerReferenceAssemblyIn(ExternalAssemblyScan.Loaded(), dynamicAssembly)

    resolved: Type = typeof(int)
    assert ColumnarCompilerReferenceResolver.TryResolveLoadedExternalType(
        fullTypeName,
        out resolved
    )
    assert Object.ReferenceEquals(resolved, dynamicType)

    unsupportedBuilder := TypeOfCreateBuilder(
        "Contoso.ReferenceResolver.Unsupported",
        "ColumnarCompilerReferenceResolver.Unsupported",
        0
    )
    unsupportedType := IdentityBake(unsupportedBuilder)
    unsupported: Type = typeof(int)
    assert !ColumnarCompilerReferenceResolver.TryResolveLoadedExternalType(
        unsupportedType.get_FullName(),
        out unsupported
    )
    assert unsupported == null

    unqualified: Type = typeof(int)
    assert !ColumnarCompilerReferenceResolver.TryResolveLoadedExternalType(
        "ReferenceResolverDynamic",
        out unqualified
    )
    assert unqualified == null
}

test "compiler reference resolver uses loaded test attributes, excludes filtered dynamic test assemblies, and retains terminal errors after ignored failures" {
    loadedFact := ColumnarCompilerReferenceResolver.ResolveTestFrameworkType(
        "Xunit.FactAttribute",
        null,
        new string[](0)
    )
    assert loadedFact.get_FullName() == "Xunit.FactAttribute"

    dynamicTestFrameworkBuilder := TypeOfCreateBuilder(
        "Xunit.ReferenceResolverDynamicFact",
        "ColumnarCompilerReferenceResolver.DynamicTestFramework",
        0
    )
    dynamicTestFrameworkType := IdentityBake(dynamicTestFrameworkBuilder)
    assert dynamicTestFrameworkType.get_Assembly().get_IsDynamic()
    assert !CompilerReferenceAssemblyIn(ExternalAssemblyScan.Loaded(), dynamicTestFrameworkType.get_Assembly())

    filteredDynamicCaught := false
    try {
        ColumnarCompilerReferenceResolver.ResolveTestFrameworkType(
            dynamicTestFrameworkType.get_FullName(),
            null,
            new string[](0)
        )
    } catch error: InvalidOperationException {
        filteredDynamicCaught = true
        assert error.Message == "Could not resolve required test framework type " + dynamicTestFrameworkType.get_FullName()
    }
    assert filteredDynamicCaught

    invalidReferences := new List<string>()
    invalidReferences.Add(
        Path.Combine(
            Path.Combine(Path.GetTempPath(), "nsharp-test-framework-missing-" + Guid.NewGuid().ToString()),
            "xunit.core.dll"
        )
    )
    invalidNames := new string[](1)
    invalidNames[0] = "NSharp.ReferenceResolver.DoesNotExist"
    caught := false
    try {
        ColumnarCompilerReferenceResolver.ResolveTestFrameworkType(
            "NSharp.ReferenceResolver.MissingAttribute",
            invalidReferences,
            invalidNames
        )
    } catch error: InvalidOperationException {
        caught = true
        assert error.Message == "Could not resolve required test framework type NSharp.ReferenceResolver.MissingAttribute"
    }
    assert caught
}

test "compiler reference resolver resolves ASP.NET reference tiers before loaded aliases" {
    fullTypeName := "Microsoft.AspNetCore.Http.HttpContext"
    httpPath := CompilerReferenceAspNetAssemblyPath("Microsoft.AspNetCore.Http")
    abstractionsPath := CompilerReferenceAspNetAssemblyPath("Microsoft.AspNetCore.Http.Abstractions")

    paths := new List<string>()
    // The other tier comes first in the input list. The first wrapper tier must filter for
    // Abstractions by name rather than consuming the first physically supplied path.
    paths.Add(httpPath)
    paths.Add(abstractionsPath)

    httpOnly := new List<string>()
    httpOnly.Add(httpPath)
    httpOnlyResult: Type = typeof(int)
    assert !ColumnarCompilerReferenceResolver.TryResolveReferencedType(
        httpOnly,
        "Microsoft.AspNetCore.Http",
        fullTypeName,
        out httpOnlyResult
    )
    assert httpOnlyResult == null

    referenced: Type = typeof(int)
    assert ColumnarCompilerReferenceResolver.TryResolveReferencedType(
        paths,
        "Microsoft.AspNetCore.Http.Abstractions",
        fullTypeName,
        out referenced
    )
    assert referenced.get_Assembly().GetName().get_Name() == "Microsoft.AspNetCore.Http.Abstractions"

    tiered: Type = typeof(int)
    assert ColumnarCompilerReferenceResolver.TryResolveAspNetReferencedType(
        paths,
        "Microsoft.AspNetCore.Http.Abstractions",
        fullTypeName,
        out tiered
    )
    assert Object.ReferenceEquals(tiered, referenced)

    context: Type = typeof(int)
    assert ColumnarCompilerReferenceResolver.TryResolveAspNetHttpContextType(paths, out context)
    assert Object.ReferenceEquals(context, referenced)

    // This alias enters the loaded-assembly arm only after the reference tier has established the
    // exact runtime type. It validates the canonical HttpContext spelling independently of paths.
    alias: Type = typeof(int)
    assert ColumnarCompilerReferenceResolver.TryResolveLoadedExternalType("HttpContext", out alias)
    assert Object.ReferenceEquals(alias, referenced)
}
