namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.Loader

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
