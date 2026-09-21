namespace NSharpLang.Cli

import System.IO
import System.Reflection
import System.Runtime.Loader

// THE ONE COLLECTIBLE LOAD CONTEXT `nlc test` OWNS.
//
// The reflection/NUnit runner loads the emitted test assembly HERE, and `RunReflectionTests`
// unloads it in a `finally`. `isCollectible: true` is the whole point: without it the emitted
// assembly would be pinned for the host process's lifetime, which is the leak
// `tests/native/test-assembly-load-contexts` records the contract for.
//
// Resolution order is the same one the C# owner had: the test output directory first, then any
// assembly already present in the DEFAULT context, so the runner's own dependencies (and the BCL)
// are shared rather than re-loaded into a context that is about to be thrown away.
class NativeTestLoadContext: AssemblyLoadContext {
    assemblyDirectoryValue: string

    constructor(assemblyDirectory: string): base("NativeTestLoadContext", true) {
        assemblyDirectoryValue = assemblyDirectory
    }

    protected override func Load(assemblyName: AssemblyName): Assembly? {
        candidatePath := TestCommandKernels.GetAssemblyCandidatePath(assemblyDirectoryValue, assemblyName.Name)
        if File.Exists(candidatePath) {
            return LoadFromAssemblyPath(candidatePath)
        }

        for assembly in AssemblyLoadContext.Default.Assemblies {
            if AssemblyName.ReferenceMatchesDefinition(assembly.GetName(), assemblyName) {
                return assembly
            }
        }

        return null
    }
}
