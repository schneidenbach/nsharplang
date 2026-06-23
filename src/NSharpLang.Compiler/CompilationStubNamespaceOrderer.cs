using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Compiler;

internal static class CompilationStubNamespaceOrderer
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    internal static string[] DistinctOrderOrdinal(IReadOnlyList<string> namespaceNames)
    {
        var count = namespaceNames.Count;
        if (count == 0)
            return Array.Empty<string>();

        var bindings = RequiredBindings;
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
                    throw new InvalidOperationException("N# compilation stub namespace ordering kernel rejected the namespace table.");
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
                throw new InvalidOperationException("N# compilation stub namespace ordering kernel rejected the namespace table.");

            var result = new string[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                var valueIndex = rank - 1;
                if (valueIndex < 0 || valueIndex >= scratch.UniqueValueCount)
                    throw new InvalidOperationException("N# compilation stub namespace ordering kernel rejected the namespace table.");

                result[i] = scratch.UniqueValues[valueIndex];
            }

            return result;
        }
        finally
        {
            scratch.ClearValues(count);
            scratch.ResetValues();
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<ReferenceFileSummaryRanksInto>(
                programType,
                "ReferenceFileSummaryRanksInto")));

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# compilation stub namespace ordering kernels are unavailable.");

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
