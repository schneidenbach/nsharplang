using System;
using System.Collections.Generic;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

internal static class QuerySymbolNameFilter
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static List<SymbolResult> Filter(
        IReadOnlyList<SymbolResult> symbols,
        string pattern,
        int limit)
    {
        if (limit <= 0)
            return new List<SymbolResult>();

        var bindings = RequiredBindings;
        if (!bindings.CliSymbolNameIsAscii(pattern))
            throw new InvalidOperationException("N# query symbol-name filter kernel rejected the pattern.");

        var useGlob = pattern.Contains('*');
        var symbolCount = symbols.Count;
        var resultCapacity = Math.Min(symbolCount, limit);
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(symbolCount, resultCapacity);

        for (var i = 0; i < symbolCount; i++)
        {
            var name = symbols[i].Name;
            if (!bindings.CliSymbolNameIsAscii(name))
            {
                throw new InvalidOperationException("N# query symbol-name filter kernel rejected the pattern.");
            }

            scratch.Names[i] = name;
        }

        var filteredCount = useGlob
            ? bindings.CliSymbolNameGlobFilterIndices(
                scratch.Names,
                pattern,
                resultCapacity,
                scratch.ResultIndices)
            : bindings.CliSymbolNameSubstringFilterIndices(
                scratch.Names,
                pattern,
                resultCapacity,
                scratch.ResultIndices);

        if (filteredCount < 0 || filteredCount > resultCapacity || filteredCount > scratch.ResultIndices.Length)
            throw new InvalidOperationException("N# query symbol-name filter kernel rejected the pattern.");

        var filteredSymbols = new List<SymbolResult>(filteredCount);
        for (var i = 0; i < filteredCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= symbolCount)
                throw new InvalidOperationException("N# query symbol-name filter kernel rejected the pattern.");

            filteredSymbols.Add(symbols[sourceIndex]);
        }

        return filteredSymbols;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliSymbolNameGlobFilterIndicesInto>(programType, "CliSymbolNameGlobFilterIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliSymbolNameSubstringFilterIndicesInto>(programType, "CliSymbolNameSubstringFilterIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliSymbolNameIsAscii>(programType, "CliSymbolNameIsAscii")));

    private delegate int CliSymbolNameGlobFilterIndicesInto(
        string[] names,
        string pattern,
        int limit,
        int[] resultIndices);

    private delegate int CliSymbolNameSubstringFilterIndicesInto(
        string[] names,
        string pattern,
        int limit,
        int[] resultIndices);

    private delegate bool CliSymbolNameIsAscii(string value);

    private sealed record Bindings(
        CliSymbolNameGlobFilterIndicesInto CliSymbolNameGlobFilterIndices,
        CliSymbolNameSubstringFilterIndicesInto CliSymbolNameSubstringFilterIndices,
        CliSymbolNameIsAscii CliSymbolNameIsAscii);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# query symbol-name filter kernels are unavailable.");

    private sealed class Scratch
    {
        internal string[] Names = Array.Empty<string>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int symbolCount, int resultCapacity)
        {
            if (Names.Length != symbolCount)
                Names = new string[symbolCount];

            if (ResultIndices.Length != resultCapacity)
                ResultIndices = new int[resultCapacity];
        }
    }
}
