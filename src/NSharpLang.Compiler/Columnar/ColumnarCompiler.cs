using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// Production-facing standalone columnar backend. This class owns whole-program assembly emission;
/// typed columnar inputs are built beside this backend from the accepted N# parser/service kernels.
/// </summary>
internal static class ColumnarCompiler
{
    internal static bool TryEmitProgram(
        string source,
        string assemblyName,
        string typeName,
        out byte[] assembly,
        out string emittedTypeName,
        out string[] methodNames,
        bool isExecutable = false)
    {
        ColumnarDeclineTrace.Reset();
        assembly = Array.Empty<byte>();
        emittedTypeName = string.Empty;
        methodNames = Array.Empty<string>();

        if (!ColumnarProgramInputBuilder.TryBuild(source, out var program))
            return false;

        // A modeled program may still decline through TryEmitColumnarAssembly returning false. Unexpected
        // emitter faults must surface; declines are hard NL103 errors.
        if (!ColumnarIlEmitter.TryEmitColumnarAssembly(assemblyName, typeName, program, isExecutable, out assembly))
            return false;

        emittedTypeName = typeName;
        methodNames = new string[program.Functions.Count];
        for (var i = 0; i < program.Functions.Count; i++)
            methodNames[i] = program.Functions[i].Name;
        return true;
    }

    internal static bool TryEmitProgramMultiFile(
        IReadOnlyList<string> sources,
        string assemblyName,
        string typeName,
        out byte[] assembly,
        out string emittedTypeName,
        out string[] methodNames,
        bool isExecutable = false)
    {
        assembly = Array.Empty<byte>();
        emittedTypeName = string.Empty;
        methodNames = Array.Empty<string>();

        var combined = ColumnarEmissionPlanner.BuildLegacyMergedSource(sources);
        if (combined == null)
            return false;

        return TryEmitProgram(combined, assemblyName, typeName, out assembly, out emittedTypeName, out methodNames, isExecutable);
    }
}
