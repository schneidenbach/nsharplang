using System;
using System.Collections.Generic;
using System.IO;

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

    internal static bool TryDeduplicateStableStringsOrdinalIgnoreCase(
        IReadOnlyList<string> values,
        out string[] deduplicatedValues)
    {
        deduplicatedValues = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_stableDistinctStringScratch ??= new StableDistinctStringScratch();
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.Reset();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (value == null)
                {
                    deduplicatedValues = Array.Empty<string>();
                    return false;
                }

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

            if (resultCount < 0 || resultCount > valueCount || resultCount > scratch.ResultIndices.Length)
            {
                deduplicatedValues = Array.Empty<string>();
                return false;
            }

            var result = new string[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= valueCount)
                {
                    deduplicatedValues = Array.Empty<string>();
                    return false;
                }

                result[i] = values[sourceIndex];
            }

            deduplicatedValues = result;
            return true;
        }
        catch
        {
            deduplicatedValues = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.Reset();
        }
    }

    internal static bool TryDeduplicateStableTypes(
        IReadOnlyList<Type> values,
        out Type[] deduplicatedValues)
    {
        deduplicatedValues = Array.Empty<Type>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_stableDistinctTypeScratch ??= new StableDistinctTypeScratch();
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.Reset();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (value == null)
                {
                    deduplicatedValues = Array.Empty<Type>();
                    return false;
                }

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

            if (resultCount < 0 || resultCount > valueCount || resultCount > scratch.ResultIndices.Length)
            {
                deduplicatedValues = Array.Empty<Type>();
                return false;
            }

            var result = new Type[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= valueCount)
                {
                    deduplicatedValues = Array.Empty<Type>();
                    return false;
                }

                result[i] = values[sourceIndex];
            }

            deduplicatedValues = result;
            return true;
        }
        catch
        {
            deduplicatedValues = Array.Empty<Type>();
            return false;
        }
        finally
        {
            scratch.Reset();
        }
    }

    internal static bool TrySelectBestDocType(
        string query,
        Type[] candidates,
        Func<string, Type, int> scoreTypeMatch,
        out Type? selected)
    {
        selected = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var candidateCount = candidates.Length;
        if (candidateCount == 0)
            return true;

        var scratch = t_docQueryBestTypeScratch ??= new DocQueryBestTypeScratch();
        scratch.EnsureCapacity(candidateCount);

        try
        {
            for (var i = 0; i < candidateCount; i++)
            {
                var candidate = candidates[i];
                var fullName = candidate.FullName;
                if (fullName == null || !IsAscii(fullName))
                    return false;

                scratch.Scores[i] = scoreTypeMatch(query, candidate);
                scratch.NamespaceLengths[i] = candidate.Namespace?.Length ?? int.MaxValue;
                scratch.FullNames[i] = fullName;
            }

            var bestIndex = bindings.DocQueryBestTypeIndex(
                scratch.Scores,
                scratch.NamespaceLengths,
                scratch.FullNames,
                candidateCount);

            if (bestIndex < 0 || bestIndex >= candidateCount)
                return false;

            selected = candidates[bestIndex];
            return true;
        }
        catch
        {
            selected = null;
            return false;
        }
        finally
        {
            scratch.ClearFullNames(candidateCount);
        }
    }

    internal static bool TryOrderDocMembers(
        IReadOnlyList<DocMemberResult> members,
        out DocMemberResult[] orderedMembers)
    {
        orderedMembers = Array.Empty<DocMemberResult>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var memberCount = members.Count;
        if (memberCount == 0)
            return true;

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
                    return false;

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

            if (orderedCount != memberCount)
                return false;

            orderedMembers = new DocMemberResult[memberCount];
            for (var i = 0; i < memberCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= memberCount)
                {
                    orderedMembers = Array.Empty<DocMemberResult>();
                    return false;
                }

                orderedMembers[i] = members[sourceIndex];
            }

            return true;
        }
        catch
        {
            orderedMembers = Array.Empty<DocMemberResult>();
            return false;
        }
        finally
        {
            scratch.ResetNames();
        }
    }

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
                "DocQueryMemberOrderIndicesInto")));

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

    private static bool IsAscii(string value)
    {
        for (var i = 0; i < value.Length; i++)
        {
            if (value[i] > '\u007f')
                return false;
        }

        return true;
    }

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

    private sealed record Bindings(
        StableDistinctRankIndicesInto StableDistinctRankIndices,
        DocQueryBestTypeIndexInto DocQueryBestTypeIndex,
        DocQueryMemberOrderIndicesInto DocQueryMemberOrderIndices);

    private sealed class DocQueryBestTypeScratch
    {
        public string[] FullNames = Array.Empty<string>();
        public int[] NamespaceLengths = Array.Empty<int>();
        public int[] Scores = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (Scores.Length < count)
            {
                Scores = new int[count];
                NamespaceLengths = new int[count];
                FullNames = new string[count];
            }
        }

        public void ClearFullNames(int count)
        {
            if (count > 0)
            {
                Array.Clear(FullNames, 0, count);
            }
        }
    }

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
