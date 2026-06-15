using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// Production-facing standalone columnar backend. This class owns whole-program assembly emission;
/// the remaining dogfood adapter boundary is limited to building typed columnar inputs from the
/// N# parser/service kernels until those kernels are routed directly.
/// </summary>
internal static class ColumnarCompiler
{
    internal static bool TryEmitProgram(
        string source,
        string assemblyName,
        string typeName,
        out byte[] assembly,
        out string emittedTypeName,
        out string[] methodNames)
    {
        assembly = Array.Empty<byte>();
        emittedTypeName = string.Empty;
        methodNames = Array.Empty<string>();

        if (!NSharpCompilerDogfoodAdapter.TryGetColumnarProgramInput(source, out var program))
            return false;

        // Columnar emit is a best-effort, DECLINE-on-failure backend: it must never throw a hard
        // error the authoritative C# fallback would not. Parity tests assert accepted programs do
        // not decline, so this catch does not hide routed-surface regressions.
        try
        {
            if (!ColumnarIlEmitter.TryEmitColumnarAssembly(assemblyName, typeName, program, out assembly))
                return false;
        }
        catch
        {
            assembly = Array.Empty<byte>();
            return false;
        }

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
        out string[] methodNames)
    {
        assembly = Array.Empty<byte>();
        emittedTypeName = string.Empty;
        methodNames = Array.Empty<string>();

        if (sources == null || sources.Count == 0)
            return false;

        var combined = string.Join("\n\n", sources);
        return TryEmitProgram(combined, assemblyName, typeName, out assembly, out emittedTypeName, out methodNames);
    }
}
