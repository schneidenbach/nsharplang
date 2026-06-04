using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Cli;

internal static class NSharpCliDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    [ThreadStatic]
    private static BatchDuplicateIdScratch? t_batchDuplicateIdScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings);

    internal static bool IsAvailable => s_bindings.Value != null;

    internal static bool TryFindDuplicateBatchRequestIds(
        IReadOnlyList<BatchQueryRequest> requests,
        out string[] duplicateIds)
    {
        duplicateIds = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var requestCount = requests.Count;
        if (requestCount == 0)
            return true;

        var scratch = t_batchDuplicateIdScratch ??= new BatchDuplicateIdScratch();
        scratch.EnsureCapacity(requestCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < requestCount; i++)
            {
                var id = requests[i].Id;
                if (!string.IsNullOrWhiteSpace(id))
                {
                    scratch.AddId(id);
                }
            }

            if (scratch.UniqueIdCount == 0)
                return true;

            scratch.BuildSortedRanks();
            for (var i = 0; i < requestCount; i++)
            {
                var id = requests[i].Id;
                scratch.IdRanks[i] = string.IsNullOrWhiteSpace(id)
                    ? 0
                    : scratch.GetIdRank(id);
            }

            var duplicateCount = bindings.CliBatchDuplicateIdRanks(
                scratch.IdRanks,
                scratch.UniqueIdCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (duplicateCount < 0 ||
                duplicateCount > scratch.UniqueIdCount ||
                duplicateCount > scratch.ResultRanks.Length)
            {
                return false;
            }

            if (duplicateCount == 0)
                return true;

            duplicateIds = new string[duplicateCount];
            for (var i = 0; i < duplicateCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueIdCount)
                {
                    duplicateIds = Array.Empty<string>();
                    return false;
                }

                duplicateIds[i] = scratch.UniqueIds[rank - 1];
            }

            return true;
        }
        catch
        {
            duplicateIds = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ResetIds();
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
                CreateDelegate<CliBatchDuplicateIdRanksInto>(programType, "CliBatchDuplicateIdRanksInto"));
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

    private delegate int CliBatchDuplicateIdRanksInto(
        int[] idRanks,
        int uniqueIdCount,
        int[] countsByRank,
        int[] resultRanks);

    private sealed record Bindings(CliBatchDuplicateIdRanksInto CliBatchDuplicateIdRanks);

    private sealed class BatchDuplicateIdScratch
    {
        private readonly Dictionary<string, int> _idRanks = new(StringComparer.Ordinal);

        public int[] CountsByRank = Array.Empty<int>();
        public int[] IdRanks = Array.Empty<int>();
        public int[] ResultRanks = Array.Empty<int>();
        public string[] UniqueIds = Array.Empty<string>();
        public int UniqueIdCount;

        public void EnsureCapacity(int requestCount)
        {
            if (IdRanks.Length != requestCount)
            {
                IdRanks = new int[requestCount];
                ResultRanks = new int[requestCount];
                UniqueIds = new string[requestCount];
            }

            var rankCapacity = requestCount + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
            }
        }

        public void AddId(string id)
        {
            if (_idRanks.ContainsKey(id))
                return;

            _idRanks.Add(id, 0);
            UniqueIds[UniqueIdCount] = id;
            UniqueIdCount++;
        }

        public void BuildSortedRanks()
        {
            Array.Sort(UniqueIds, 0, UniqueIdCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueIdCount; i++)
            {
                _idRanks[UniqueIds[i]] = i + 1;
            }
        }

        public int GetIdRank(string id) => _idRanks[id];

        public void ResetIds()
        {
            _idRanks.Clear();
            if (UniqueIdCount > 0)
            {
                Array.Clear(UniqueIds, 0, UniqueIdCount);
                UniqueIdCount = 0;
            }
        }
    }
}
