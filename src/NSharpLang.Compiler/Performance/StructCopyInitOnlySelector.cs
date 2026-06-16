using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Compiler.Performance;

internal static class StructCopyInitOnlySelector
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

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
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<StructCopyAllInstanceFieldsInitOnly>(
                    programType,
                    "StructCopyAllInstanceFieldsInitOnly"));
        }
        catch
        {
            return null;
        }
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch
        {
            var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
            return File.Exists(assemblyPath)
                ? Assembly.LoadFrom(assemblyPath)
                : null;
        }
    }

    private static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
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
