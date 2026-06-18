using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class CodeIntelligenceSymbolKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static SymbolKindFilterScratch? t_symbolKindFilterScratch;

    internal static bool TryFilterSymbolsByKind(
        IReadOnlyList<SymbolResult> symbols,
        SymbolKind targetKind,
        out List<SymbolResult> filteredSymbols)
    {
        filteredSymbols = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var symbolCount = symbols.Count;
        if (symbolCount == 0)
            return true;

        var scratch = t_symbolKindFilterScratch ??= new SymbolKindFilterScratch();
        scratch.EnsureCapacity(symbolCount);

        try
        {
            for (var i = 0; i < symbolCount; i++)
            {
                scratch.KindIds[i] = (int)symbols[i].Kind;
            }

            var filteredCount = bindings.SymbolKindFilter(
                scratch.KindIds,
                (int)targetKind,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > symbolCount)
            {
                filteredSymbols = [];
                return false;
            }

            var results = new List<SymbolResult>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= symbolCount)
                {
                    filteredSymbols = [];
                    return false;
                }

                results.Add(symbols[sourceIndex]);
            }

            filteredSymbols = results;
            return true;
        }
        catch
        {
            filteredSymbols = [];
            return false;
        }
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
