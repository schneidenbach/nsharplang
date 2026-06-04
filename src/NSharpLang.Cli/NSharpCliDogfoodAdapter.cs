using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli;

internal static class NSharpCliDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    [ThreadStatic]
    private static BatchDuplicateIdScratch? t_batchDuplicateIdScratch;
    [ThreadStatic]
    private static DocSymbolOrderScratch? t_docSymbolOrderScratch;

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

    internal static bool TryOrderDocSymbolsForGeneration(
        IReadOnlyList<SymbolResult> symbols,
        out List<SymbolResult> orderedSymbols)
        => TryOrderDocEntriesForGeneration(symbols, includeAllKinds: false, out orderedSymbols);

    internal static bool TryOrderDocMembersForGeneration(
        IReadOnlyList<SymbolResult> members,
        out List<SymbolResult> orderedMembers)
        => TryOrderDocEntriesForGeneration(members, includeAllKinds: true, out orderedMembers);

    private static bool TryOrderDocEntriesForGeneration(
        IReadOnlyList<SymbolResult> symbols,
        bool includeAllKinds,
        out List<SymbolResult> orderedSymbols)
    {
        orderedSymbols = new List<SymbolResult>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var symbolCount = symbols.Count;
        if (symbolCount == 0)
            return true;

        var scratch = t_docSymbolOrderScratch ??= new DocSymbolOrderScratch();
        scratch.EnsureCapacity(symbolCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < symbolCount; i++)
            {
                scratch.AddName(symbols[i].Name);
            }

            scratch.BuildSortedNameRanks();
            for (var i = 0; i < symbolCount; i++)
            {
                var symbol = symbols[i];
                scratch.KindRanks[i] = GetDocSymbolKindRank(symbol.Kind);
                scratch.NameRanks[i] = scratch.GetNameRank(symbol.Name);
                scratch.IncludeFlags[i] = (includeAllKinds || IsDocumentedSymbolKind(symbol.Kind)) ? 1 : 0;
            }

            var orderedCount = bindings.CliDocSymbolOrderCountingIndices(
                scratch.KindRanks,
                scratch.NameRanks,
                scratch.IncludeFlags,
                scratch.NameCounts,
                scratch.NameOffsets,
                scratch.KindCounts,
                scratch.KindOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > symbolCount || orderedCount > scratch.ResultIndices.Length)
                return false;

            orderedSymbols = new List<SymbolResult>(orderedCount);
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= symbolCount)
                {
                    orderedSymbols = new List<SymbolResult>();
                    return false;
                }

                orderedSymbols.Add(symbols[sourceIndex]);
            }

            return true;
        }
        catch
        {
            orderedSymbols = new List<SymbolResult>();
            return false;
        }
        finally
        {
            scratch.ResetNames();
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
                CreateDelegate<CliBatchDuplicateIdRanksInto>(programType, "CliBatchDuplicateIdRanksInto"),
                CreateDelegate<CliDocSymbolOrderCountingIndicesInto>(programType, "CliDocSymbolOrderCountingIndicesInto"));
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

    private delegate int CliDocSymbolOrderCountingIndicesInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] includeFlags,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private sealed record Bindings(
        CliBatchDuplicateIdRanksInto CliBatchDuplicateIdRanks,
        CliDocSymbolOrderCountingIndicesInto CliDocSymbolOrderCountingIndices);

    private static bool IsDocumentedSymbolKind(SymbolKind kind) =>
        kind is not SymbolKind.Variable and not SymbolKind.Parameter;

    private static int GetDocSymbolKindRank(SymbolKind kind) =>
        kind switch
        {
            SymbolKind.Class => 1,
            SymbolKind.Constructor => 2,
            SymbolKind.Enum => 3,
            SymbolKind.EnumMember => 4,
            SymbolKind.Field => 5,
            SymbolKind.Function => 6,
            SymbolKind.Interface => 7,
            SymbolKind.Method => 8,
            SymbolKind.Parameter => 9,
            SymbolKind.Property => 10,
            SymbolKind.Record => 11,
            SymbolKind.Struct => 12,
            SymbolKind.Test => 13,
            SymbolKind.TypeAlias => 14,
            SymbolKind.Union => 15,
            SymbolKind.Variable => 16,
            _ => 100
        };

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

    private sealed class DocSymbolOrderScratch
    {
        private readonly Dictionary<string, int> _nameRanks = new(StringComparer.Ordinal);

        public int[] IncludeFlags = Array.Empty<int>();
        public int[] KindCounts = Array.Empty<int>();
        public int[] KindOffsets = Array.Empty<int>();
        public int[] KindRanks = Array.Empty<int>();
        public int[] NameCounts = Array.Empty<int>();
        public int[] NameOffsets = Array.Empty<int>();
        public int[] NameRanks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] TempIndices = Array.Empty<int>();
        public string[] UniqueNames = Array.Empty<string>();
        public int UniqueNameCount;

        public void EnsureCapacity(int symbolCount)
        {
            if (KindRanks.Length != symbolCount)
            {
                KindRanks = new int[symbolCount];
                NameRanks = new int[symbolCount];
                IncludeFlags = new int[symbolCount];
                TempIndices = new int[symbolCount];
                ResultIndices = new int[symbolCount];
                UniqueNames = new string[symbolCount];
            }

            var nameRankCapacity = symbolCount + 1;
            if (NameCounts.Length != nameRankCapacity)
            {
                NameCounts = new int[nameRankCapacity];
                NameOffsets = new int[nameRankCapacity];
            }

            if (KindCounts.Length != 32)
            {
                KindCounts = new int[32];
                KindOffsets = new int[32];
            }
        }

        public void AddName(string name)
        {
            if (_nameRanks.ContainsKey(name))
                return;

            _nameRanks.Add(name, 0);
            UniqueNames[UniqueNameCount] = name;
            UniqueNameCount++;
        }

        public void BuildSortedNameRanks()
        {
            Array.Sort(UniqueNames, 0, UniqueNameCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueNameCount; i++)
            {
                _nameRanks[UniqueNames[i]] = i + 1;
            }
        }

        public int GetNameRank(string name) => _nameRanks[name];

        public void ResetNames()
        {
            _nameRanks.Clear();
            if (UniqueNameCount > 0)
            {
                Array.Clear(UniqueNames, 0, UniqueNameCount);
                UniqueNameCount = 0;
            }
        }
    }
}
