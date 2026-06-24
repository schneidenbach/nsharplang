using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class CompletionEngineKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static CompletionItemGroupingScratch? t_completionItemGroupingScratch;
    [ThreadStatic]
    private static CompletionReceiverScratch? t_completionReceiverScratch;

    internal static (bool IsMemberAccess, string? Receiver) ClassifyCompletionReceiver(string beforeCursor)
    {
        var bindings = RequiredBindings;
        var scratch = t_completionReceiverScratch ??= new CompletionReceiverScratch();
        scratch.Prefixes[0] = beforeCursor;
        scratch.Contexts[0] = 0;
        scratch.Receivers[0] = string.Empty;

        try
        {
            var classified = bindings.CompletionReceivers(
                scratch.Prefixes,
                scratch.Contexts,
                scratch.Receivers);

            return (
                scratch.Contexts[0] != 0,
                scratch.Receivers[0].Length > 0 ? scratch.Receivers[0] : null);
        }
        finally
        {
            scratch.Prefixes[0] = string.Empty;
            scratch.Contexts[0] = 0;
            scratch.Receivers[0] = string.Empty;
        }
    }

    internal static void AddGroupedCompletionItemsByKind(
        IReadOnlyList<CompletionItem> items,
        Dictionary<string, List<CompletionItem>> completions)
    {
        var bindings = RequiredBindings;

        var count = items.Count;
        if (count == 0)
            return;

        var scratch = t_completionItemGroupingScratch ??= new CompletionItemGroupingScratch();
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetKindIds();
            for (var i = 0; i < count; i++)
            {
                scratch.KindIds[i] = scratch.GetKindId(items[i].Kind);
            }

            var groupCount = bindings.CompletionItemKindGroups(
                scratch.KindIds,
                scratch.KindCounts,
                scratch.KindOffsets,
                scratch.ResultKindIds,
                scratch.ResultStarts,
                scratch.ResultCounts,
                scratch.ResultIndices);

            var total = 0;
            for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
            {
                var start = scratch.ResultStarts[groupIndex];
                var itemCount = scratch.ResultCounts[groupIndex];
                total += itemCount;
            }

            for (var resultIndex = 0; resultIndex < count; resultIndex++)
            {
                var sourceIndex = scratch.ResultIndices[resultIndex];
            }

            for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
            {
                var kindId = scratch.ResultKindIds[groupIndex];
                var kind = scratch.GetKindName(kindId);
                var start = scratch.ResultStarts[groupIndex];
                var itemCount = scratch.ResultCounts[groupIndex];
                var groupItems = new List<CompletionItem>(itemCount);

                for (var itemIndex = 0; itemIndex < itemCount; itemIndex++)
                {
                    var sourceIndex = scratch.ResultIndices[start + itemIndex];
                    groupItems.Add(items[sourceIndex]);
                }

                completions[CompletionEngine.PluralizeCompletionKind(kind)] = groupItems;
            }
        }
        finally
        {
            scratch.ResetKindIds();
        }
    }

    private static Bindings RequiredBindings =>
        s_bindings.Value
        ?? throw new InvalidOperationException("N# completion engine kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CodeIntelligenceCompletionReceiversInto>(
                programType,
                "CodeIntelligenceCompletionReceiversInto"),
            DogfoodKernelLoader.CreateDelegate<CompletionItemKindGroupsInto>(
                programType,
                "CompletionItemKindGroupsInto"),
            DogfoodKernelLoader.CreateDelegate<CompletionMethodOverloadGroupsInto>(
                programType,
                "CompletionMethodOverloadGroupsInto")));

    private delegate int CodeIntelligenceCompletionReceiversInto(
        string[] prefixes,
        int[] resultContexts,
        string[] resultReceivers);

    private delegate int CompletionItemKindGroupsInto(
        int[] kindIds,
        int[] kindCounts,
        int[] kindOffsets,
        int[] resultKindIds,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultIndices);

    private delegate int CompletionMethodOverloadGroupsInto(
        int[] nameIds,
        int[] includeFlags,
        int[] nameCounts,
        int[] resultNameIds,
        int[] resultFirstIndices,
        int[] resultCounts);

    private sealed record Bindings(
        CodeIntelligenceCompletionReceiversInto CompletionReceivers,
        CompletionItemKindGroupsInto CompletionItemKindGroups,
        CompletionMethodOverloadGroupsInto CompletionMethodOverloadGroups);

    private sealed class CompletionReceiverScratch
    {
        public readonly int[] Contexts = new int[1];
        public readonly string[] Prefixes = new string[1];
        public readonly string[] Receivers = new string[1];

        public CompletionReceiverScratch()
        {
            Prefixes[0] = string.Empty;
            Receivers[0] = string.Empty;
        }
    }

    private sealed class CompletionItemGroupingScratch
    {
        private readonly Dictionary<string, int> _kindIds = new(StringComparer.Ordinal);

        public int[] KindCounts = Array.Empty<int>();
        public int[] KindIds = Array.Empty<int>();
        public string[] KindNames = Array.Empty<string>();
        public int[] KindOffsets = Array.Empty<int>();
        public int[] ResultCounts = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] ResultKindIds = Array.Empty<int>();
        public int[] ResultStarts = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
            {
                KindIds = new int[count];
                ResultKindIds = new int[count];
                ResultStarts = new int[count];
                ResultCounts = new int[count];
                ResultIndices = new int[count];
            }

            var bucketCapacity = count + 1;
            if (KindCounts.Length < bucketCapacity)
            {
                KindCounts = new int[bucketCapacity];
                KindOffsets = new int[bucketCapacity];
                KindNames = new string[bucketCapacity];
            }
        }

        public int GetKindId(string kind)
        {
            if (_kindIds.TryGetValue(kind, out var id))
                return id;

            id = _kindIds.Count + 1;
            _kindIds.Add(kind, id);
            KindNames[id] = kind;
            return id;
        }

        public string GetKindName(int id) =>
            id > 0 && id < KindNames.Length
                ? KindNames[id] ?? string.Empty
                : string.Empty;

        public void ResetKindIds()
        {
            if (_kindIds.Count > 0)
            {
                Array.Clear(KindNames, 1, _kindIds.Count);
                _kindIds.Clear();
            }
        }
    }

}
