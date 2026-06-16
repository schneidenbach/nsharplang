using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Compiler;

internal static class CompilationStubNamespaceOrderer
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    internal static bool TryDistinctOrderOrdinal(
        IReadOnlyList<string> namespaceNames,
        out string[] orderedNamespaceNames)
    {
        orderedNamespaceNames = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = namespaceNames.Count;
        if (count == 0)
            return true;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetValues();
            for (var i = 0; i < count; i++)
            {
                var namespaceName = namespaceNames[i];
                if (namespaceName == null)
                {
                    orderedNamespaceNames = Array.Empty<string>();
                    return false;
                }

                scratch.Values[i] = namespaceName;
                scratch.AddValue(namespaceName);
            }

            scratch.BuildRanks();
            for (var i = 0; i < count; i++)
            {
                scratch.ValueRanks[i] = scratch.GetRank(scratch.Values[i]);
            }

            var orderedCount = bindings.ReferenceFileSummaryRanks(
                scratch.ValueRanks,
                scratch.UniqueValueCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (orderedCount < 0 || orderedCount > scratch.UniqueValueCount || orderedCount > scratch.ResultRanks.Length)
            {
                orderedNamespaceNames = Array.Empty<string>();
                return false;
            }

            var result = new string[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                var valueIndex = rank - 1;
                if (valueIndex < 0 || valueIndex >= scratch.UniqueValueCount)
                {
                    orderedNamespaceNames = Array.Empty<string>();
                    return false;
                }

                result[i] = scratch.UniqueValues[valueIndex];
            }

            orderedNamespaceNames = result;
            return true;
        }
        catch
        {
            orderedNamespaceNames = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearValues(count);
            scratch.ResetValues();
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
                CreateDelegate<ReferenceFileSummaryRanksInto>(
                    programType,
                    "ReferenceFileSummaryRanksInto"));
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

    private delegate int ReferenceFileSummaryRanksInto(
        int[] fileRanks,
        int uniqueFileCount,
        int[] countsByRank,
        int[] resultRanks);

    private sealed record Bindings(ReferenceFileSummaryRanksInto ReferenceFileSummaryRanks);

    private sealed class Scratch
    {
        private readonly Dictionary<string, int> _valueRanks = new(StringComparer.Ordinal);

        internal int[] CountsByRank = Array.Empty<int>();
        internal int[] ResultRanks = Array.Empty<int>();
        internal string[] UniqueValues = Array.Empty<string>();
        internal int[] ValueRanks = Array.Empty<int>();
        internal string[] Values = Array.Empty<string>();
        internal int UniqueValueCount;

        internal void EnsureCapacity(int count)
        {
            if (ValueRanks.Length != count)
            {
                ValueRanks = new int[count];
                Values = new string[count];
                ResultRanks = new int[count];
                UniqueValues = new string[count];
            }

            var rankCapacity = count + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
            }
        }

        internal void AddValue(string value)
        {
            if (_valueRanks.ContainsKey(value))
                return;

            _valueRanks.Add(value, 0);
            UniqueValues[UniqueValueCount] = value;
            UniqueValueCount++;
        }

        internal void BuildRanks()
        {
            Array.Sort(UniqueValues, 0, UniqueValueCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueValueCount; i++)
            {
                _valueRanks[UniqueValues[i]] = i + 1;
            }
        }

        internal int GetRank(string value) => _valueRanks[value];

        internal void ClearValues(int count) => Array.Clear(Values, 0, count);

        internal void ResetValues()
        {
            _valueRanks.Clear();
            if (UniqueValueCount > 0)
            {
                Array.Clear(UniqueValues, 0, UniqueValueCount);
                UniqueValueCount = 0;
            }
        }
    }
}
