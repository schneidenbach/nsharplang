using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class FixApplicatorTextEditOrderer
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static TextEditOrderingScratch? t_textEditOrderingScratch;

    internal static bool TryOrderTextEdits(
        IReadOnlyCollection<TextEdit> edits,
        out List<TextEdit> sortedEdits)
    {
        sortedEdits = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = edits.Count;
        if (count == 0)
            return true;

        var editArray = edits as TextEdit[] ?? edits.ToArray();
        var scratch = t_textEditOrderingScratch ??= new TextEditOrderingScratch();
        scratch.EnsureCapacity(count);

        try
        {
            var startPositionRankCount = scratch.BuildRanks(
                editArray,
                count,
                TextEditOrderingPosition.Start,
                scratch.StartPositionRanks);
            var endPositionRankCount = scratch.BuildRanks(
                editArray,
                count,
                TextEditOrderingPosition.End,
                scratch.EndPositionRanks);

            var orderedCount = bindings.TextEditOrderIndices(
                scratch.StartPositionRanks,
                scratch.EndPositionRanks,
                startPositionRankCount,
                endPositionRankCount,
                scratch.BucketCounts,
                scratch.BucketOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount != count)
                return false;

            sortedEdits = new List<TextEdit>(count);
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= count)
                {
                    sortedEdits = [];
                    return false;
                }

                sortedEdits.Add(editArray[sourceIndex]);
            }

            return true;
        }
        catch
        {
            sortedEdits = [];
            return false;
        }
        finally
        {
            scratch.Reset();
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
                DogfoodKernelLoader.CreateDelegate<TextEditOrderIndicesInto>(
                    programType,
                    "TextEditOrderIndicesInto"));
        }
        catch
        {
            return null;
        }
    }

    private delegate int TextEditOrderIndicesInto(
        int[] startPositionRanks,
        int[] endPositionRanks,
        int startPositionRankCount,
        int endPositionRankCount,
        int[] bucketCounts,
        int[] bucketOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private sealed record Bindings(TextEditOrderIndicesInto TextEditOrderIndices);

    private enum TextEditOrderingPosition
    {
        Start,
        End
    }

    private sealed class TextEditOrderingScratch
    {
        private readonly Dictionary<(int Line, int Column), int> _rankMap = new();

        public int[] BucketCounts = Array.Empty<int>();
        public int[] BucketOffsets = Array.Empty<int>();
        public int[] EndPositionRanks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] StartPositionRanks = Array.Empty<int>();
        public int[] TempIndices = Array.Empty<int>();
        public (int Line, int Column)[] UniquePositions = Array.Empty<(int Line, int Column)>();

        public void EnsureCapacity(int count)
        {
            if (StartPositionRanks.Length != count)
            {
                StartPositionRanks = new int[count];
                EndPositionRanks = new int[count];
                TempIndices = new int[count];
                ResultIndices = new int[count];
                UniquePositions = new (int Line, int Column)[count];
            }

            var bucketCapacity = count + 1;
            if (BucketCounts.Length != bucketCapacity)
            {
                BucketCounts = new int[bucketCapacity];
                BucketOffsets = new int[bucketCapacity];
            }
        }

        public int BuildRanks(
            TextEdit[] edits,
            int count,
            TextEditOrderingPosition position,
            int[] ranks)
        {
            _rankMap.Clear();
            var uniqueCount = 0;
            for (var i = 0; i < count; i++)
            {
                var value = GetPosition(edits[i], position);
                if (_rankMap.ContainsKey(value))
                    continue;

                _rankMap.Add(value, 0);
                UniquePositions[uniqueCount] = value;
                uniqueCount++;
            }

            Array.Sort(UniquePositions, 0, uniqueCount);
            for (var i = 0; i < uniqueCount; i++)
            {
                _rankMap[UniquePositions[i]] = i + 1;
            }

            for (var i = 0; i < count; i++)
            {
                ranks[i] = _rankMap[GetPosition(edits[i], position)];
            }

            return uniqueCount;
        }

        public void Reset() => _rankMap.Clear();

        private static (int Line, int Column) GetPosition(TextEdit edit, TextEditOrderingPosition position) =>
            position switch
            {
                TextEditOrderingPosition.Start => (edit.StartLine, edit.StartColumn),
                TextEditOrderingPosition.End => (edit.EndLine, edit.EndColumn),
                _ => (0, 0)
            };
    }
}
