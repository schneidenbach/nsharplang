using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Compiler.Performance;

internal static class StructCopyInitOnlySelector
{

    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryAllInstanceFieldsAreInitOnly(
        IReadOnlyList<StructCopyAnalysis.StructFieldDescriptor> fields,
        out bool allInitOnly)
    {
        allInitOnly = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var fieldCount = fields.Count;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureFieldCapacity(fieldCount);

        try
        {
            for (var i = 0; i < fieldCount; i++)
            {
                var field = fields[i];
                scratch.FieldReadonlyFlags[i] = field.IsStatic || field.IsInitOnly ? 1 : 0;
            }

            var result = bindings.StructCopyAllInstanceFieldsInitOnly(
                scratch.FieldReadonlyFlags,
                fieldCount);
            if (result is not 0 and not 1)
                return false;

            allInitOnly = result != 0;
            return true;
        }
        catch
        {
            allInitOnly = false;
            return false;
        }
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var programType = DogfoodKernelLoader.TryGetProgramType();
            if (programType == null)
                return null;

            return new Bindings(
                DogfoodKernelLoader.CreateDelegate<StructCopyAllInstanceFieldsInitOnly>(
                    programType,
                    "StructCopyAllInstanceFieldsInitOnly"));
        }
        catch
        {
            return null;
        }
    }

    private delegate int StructCopyAllInstanceFieldsInitOnly(int[] fieldFlags, int count);

    private sealed record Bindings(StructCopyAllInstanceFieldsInitOnly StructCopyAllInstanceFieldsInitOnly);

    private sealed class Scratch
    {
        internal int[] FieldReadonlyFlags = Array.Empty<int>();

        internal void EnsureFieldCapacity(int fieldCount)
        {
            if (FieldReadonlyFlags.Length < fieldCount)
            {
                FieldReadonlyFlags = new int[fieldCount];
            }
        }
    }
}
