using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class DocQueryKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static DocQueryBestTypeScratch? t_docQueryBestTypeScratch;
    [ThreadStatic]
    private static DocQueryMemberOrderScratch? t_docQueryMemberOrderScratch;
    [ThreadStatic]
    private static StableDistinctStringScratch? t_stableDistinctStringScratch;
    [ThreadStatic]
    private static StableDistinctTypeScratch? t_stableDistinctTypeScratch;

    internal static string[] DeduplicateStableStringsOrdinalIgnoreCase(IReadOnlyList<string> values)
    {
        var bindings = RequiredBindings;

        var valueCount = values.Count;
        if (valueCount == 0)
            return Array.Empty<string>();

        var scratch = t_stableDistinctStringScratch ??= new StableDistinctStringScratch();
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.Reset();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (!scratch.RanksByValue.TryGetValue(value, out var rank))
                {
                    rank = ++scratch.UniqueRankCount;
                    scratch.RanksByValue.Add(value, rank);
                }

                scratch.Ranks[i] = rank;
            }

            scratch.EnsureRankCapacity(scratch.UniqueRankCount);
            var resultCount = bindings.StableDistinctRankIndices(
                scratch.Ranks,
                scratch.UniqueRankCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            var result = new string[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                result[i] = values[sourceIndex];
            }

            return result;
        }
        finally
        {
            scratch.Reset();
        }
    }

    internal static Type[] DeduplicateStableTypes(IReadOnlyList<Type> values)
    {
        var bindings = RequiredBindings;

        var valueCount = values.Count;
        if (valueCount == 0)
            return Array.Empty<Type>();

        var scratch = t_stableDistinctTypeScratch ??= new StableDistinctTypeScratch();
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.Reset();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (!scratch.RanksByValue.TryGetValue(value, out var rank))
                {
                    rank = ++scratch.UniqueRankCount;
                    scratch.RanksByValue.Add(value, rank);
                }

                scratch.Ranks[i] = rank;
            }

            scratch.EnsureRankCapacity(scratch.UniqueRankCount);
            var resultCount = bindings.StableDistinctRankIndices(
                scratch.Ranks,
                scratch.UniqueRankCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            var result = new Type[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                result[i] = values[sourceIndex];
            }

            return result;
        }
        finally
        {
            scratch.Reset();
        }
    }

    internal static Type? SelectBestDocType(
        string query,
        Type[] candidates,
        Func<string, Type, int> scoreTypeMatch)
    {
        var bindings = RequiredBindings;

        var candidateCount = candidates.Length;
        if (candidateCount == 0)
            return null;

        var scratch = t_docQueryBestTypeScratch ??= new DocQueryBestTypeScratch();
        scratch.EnsureCapacity(candidateCount);

        try
        {
            for (var i = 0; i < candidateCount; i++)
            {
                var candidate = candidates[i];
                scratch.Scores[i] = scoreTypeMatch(query, candidate);
                scratch.NamespaceLengths[i] = candidate.Namespace?.Length ?? int.MaxValue;
                scratch.FullNames[i] = candidate.FullName!;
            }

            var bestIndex = bindings.DocQueryBestTypeIndex(
                scratch.Scores,
                scratch.NamespaceLengths,
                scratch.FullNames,
                candidateCount);

            return candidates[bestIndex];
        }
        finally
        {
            scratch.ClearFullNames(candidateCount);
        }
    }

    internal static DocMemberResult[] OrderDocMembers(IReadOnlyList<DocMemberResult> members)
    {
        var bindings = RequiredBindings;

        var memberCount = members.Count;
        if (memberCount == 0)
            return Array.Empty<DocMemberResult>();

        var scratch = t_docQueryMemberOrderScratch ??= new DocQueryMemberOrderScratch();
        scratch.EnsureCapacity(memberCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < memberCount; i++)
            {
                scratch.AddName(members[i].Name);
            }

            scratch.BuildSortedNameRanks();
            for (var i = 0; i < memberCount; i++)
            {
                var member = members[i];
                var kindRank = GetDocMemberKindRank(member.Kind);
                if (kindRank == 0)
                    throw new InvalidOperationException("N# doc query member ordering kernel rejected a member kind.");

                scratch.KindRanks[i] = kindRank;
                scratch.NameRanks[i] = scratch.GetNameRank(member.Name);
            }

            var orderedCount = bindings.DocQueryMemberOrderIndices(
                scratch.KindRanks,
                scratch.NameRanks,
                scratch.NameCounts,
                scratch.NameOffsets,
                scratch.KindCounts,
                scratch.KindOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            var orderedMembers = new DocMemberResult[memberCount];
            for (var i = 0; i < memberCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                orderedMembers[i] = members[sourceIndex];
            }

            return orderedMembers;
        }
        finally
        {
            scratch.ResetNames();
        }
    }

    internal static string StripGenericArity(string name)
        => RequiredBindings.DocQueryStripGenericArity(name);

    internal static int ScoreTypeMatch(
        string strippedQuery,
        string qualifiedName,
        string simpleName,
        string namespaceName,
        int isNested)
        => RequiredBindings.DocQueryTypeMatchScore(strippedQuery, qualifiedName, simpleName, namespaceName, isNested);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<StableDistinctRankIndicesInto>(
                programType,
                "CliStableDistinctRankIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<DocQueryBestTypeIndexInto>(
                programType,
                "DocQueryBestTypeIndex"),
            DogfoodKernelLoader.CreateDelegate<DocQueryMemberOrderIndicesInto>(
                programType,
                "DocQueryMemberOrderIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<DocQueryStripGenericArity>(
                programType,
                "DocQueryStripGenericArity"),
            DogfoodKernelLoader.CreateDelegate<DocQueryTypeMatchScore>(
                programType,
                "DocQueryTypeMatchScore")));

    private static int GetDocMemberKindRank(string kind) =>
        kind switch
        {
            "constructor" => 1,
            "event" => 2,
            "field" => 3,
            "method" => 4,
            "nested type" => 5,
            "property" => 6,
            _ => 0
        };

    private static Bindings RequiredBindings =>
        s_bindings.Value
        ?? throw new InvalidOperationException("N# doc query kernels are unavailable.");

    private delegate int StableDistinctRankIndicesInto(
        int[] valueRanks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);

    private delegate int DocQueryBestTypeIndexInto(
        int[] scores,
        int[] namespaceLengths,
        string[] fullNames,
        int count);

    private delegate int DocQueryMemberOrderIndicesInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private delegate string DocQueryStripGenericArity(string name);
    private delegate int DocQueryTypeMatchScore(
        string strippedQuery,
        string qualifiedName,
        string simpleName,
        string namespaceName,
        int isNested);

    private sealed record Bindings(
        StableDistinctRankIndicesInto StableDistinctRankIndices,
        DocQueryBestTypeIndexInto DocQueryBestTypeIndex,
        DocQueryMemberOrderIndicesInto DocQueryMemberOrderIndices,
        DocQueryStripGenericArity DocQueryStripGenericArity,
        DocQueryTypeMatchScore DocQueryTypeMatchScore);

    private sealed class DocQueryMemberOrderScratch
    {
        private readonly Dictionary<string, int> _nameRanks = new(StringComparer.OrdinalIgnoreCase);

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

        public void EnsureCapacity(int memberCount)
        {
            if (KindRanks.Length != memberCount)
            {
                KindRanks = new int[memberCount];
                NameRanks = new int[memberCount];
                TempIndices = new int[memberCount];
                ResultIndices = new int[memberCount];
                UniqueNames = new string[memberCount];
            }

            var nameRankCapacity = memberCount + 1;
            if (NameCounts.Length != nameRankCapacity)
            {
                NameCounts = new int[nameRankCapacity];
                NameOffsets = new int[nameRankCapacity];
            }

            if (KindCounts.Length != 16)
            {
                KindCounts = new int[16];
                KindOffsets = new int[16];
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
            Array.Sort(UniqueNames, 0, UniqueNameCount, StringComparer.OrdinalIgnoreCase);
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

    private sealed class StableDistinctStringScratch
    {
        public readonly Dictionary<string, int> RanksByValue = new(StringComparer.OrdinalIgnoreCase);
        public int[] Ranks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeenRanks = Array.Empty<int>();
        public int UniqueRankCount;

        public void EnsureCapacity(int count)
        {
            if (Ranks.Length != count)
            {
                Ranks = new int[count];
                ResultIndices = new int[count];
            }
        }

        public void EnsureRankCapacity(int uniqueRankCount)
        {
            var rankCapacity = uniqueRankCount + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        public void Reset()
        {
            RanksByValue.Clear();
            UniqueRankCount = 0;
        }
    }

    private sealed class StableDistinctTypeScratch
    {
        public readonly Dictionary<Type, int> RanksByValue = new();
        public int[] Ranks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeenRanks = Array.Empty<int>();
        public int UniqueRankCount;

        public void EnsureCapacity(int count)
        {
            if (Ranks.Length != count)
            {
                Ranks = new int[count];
                ResultIndices = new int[count];
            }
        }

        public void EnsureRankCapacity(int uniqueRankCount)
        {
            var rankCapacity = uniqueRankCount + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        public void Reset()
        {
            RanksByValue.Clear();
            UniqueRankCount = 0;
        }
    }
}
