namespace NSharpLang.Cli

import System.Collections.Generic
import System.Reflection
import System.Runtime.Loader

// THE ONE COLLECTIBLE LOAD CONTEXT `nlc test` OWNS.
//
// The reflection/NUnit runner loads the emitted test assembly HERE, and `RunReflectionTests`
// unloads it in a `finally`. `isCollectible: true` is the whole point: without it the emitted
// assembly would be pinned for the host process's lifetime, which is the leak
// `tests/native/test-assembly-load-contexts` records the contract for.
//
// Resolution order: the test output directory, then the shared-framework directories the project's
// `framework:` references resolved to (`TestCommandKernels.FindAssemblyCandidatePath`), then any
// assembly already present in the DEFAULT context, so the runner's own dependencies (and the BCL)
// are shared rather than re-loaded into a context that is about to be thrown away. A framework
// assembly loads HERE, not into the default context, so it is unloaded with the run.
class NativeTestLoadContext: AssemblyLoadContext {
    assemblyDirectoryValue: string
    frameworkDirectoriesValue: IReadOnlyList<string>

    constructor(assemblyDirectory: string, frameworkDirectories: IReadOnlyList<string>): base("NativeTestLoadContext", true) {
        assemblyDirectoryValue = assemblyDirectory
        frameworkDirectoriesValue = frameworkDirectories
    }

    protected override func Load(assemblyName: AssemblyName): Assembly? {
        candidatePath := TestCommandKernels.FindAssemblyCandidatePath(assemblyDirectoryValue, frameworkDirectoriesValue, assemblyName.Name)
        if candidatePath != null {
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
