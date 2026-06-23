using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class CodeIntelligenceSymbolKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static SymbolKindFilterScratch? t_symbolKindFilterScratch;

    internal static List<SymbolResult> FilterSymbolsByKind(
        IReadOnlyList<SymbolResult> symbols,
        SymbolKind targetKind)
    {
        var symbolCount = symbols.Count;
        if (symbolCount == 0)
            return [];

        var scratch = t_symbolKindFilterScratch ??= new SymbolKindFilterScratch();
        scratch.EnsureCapacity(symbolCount);

        for (var i = 0; i < symbolCount; i++)
        {
            scratch.KindIds[i] = (int)symbols[i].Kind;
        }

        var filteredCount = RequiredBindings.SymbolKindFilter(
            scratch.KindIds,
            (int)targetKind,
            scratch.ResultIndices);

        if (filteredCount < 0 || filteredCount > symbolCount)
            throw new InvalidOperationException("N# symbol kind filter kernel rejected the symbols.");

        var results = new List<SymbolResult>(filteredCount);
        for (var i = 0; i < filteredCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= symbolCount)
                throw new InvalidOperationException("N# symbol kind filter kernel returned an invalid index.");

            results.Add(symbols[sourceIndex]);
        }

        return results;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<SymbolKindFilterIndicesInto>(
                programType,
                "SymbolKindFilterIndicesInto")));

    private delegate int SymbolKindFilterIndicesInto(
        int[] kindIds,
        int targetKindId,
        int[] resultIndices);

    private sealed record Bindings(SymbolKindFilterIndicesInto SymbolKindFilter);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# symbol kind filter kernel is unavailable.");

    private sealed class SymbolKindFilterScratch
    {
        public int[] KindIds = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
            {
                KindIds = new int[count];
                ResultIndices = new int[count];
            }
        }
    }
}
