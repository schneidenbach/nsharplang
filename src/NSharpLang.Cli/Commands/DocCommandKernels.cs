using System;
using System.Collections.Generic;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

internal readonly record struct DocOptionSummary(
    string? ProjectOption,
    string? OutputOption,
    bool Json,
    bool Open,
    bool ShowHelp);

internal static class DocCommandKernels
{
    [ThreadStatic]
    private static SymbolOrderScratch? t_symbolOrderScratch;
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out DocOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[5];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var outputOption))
            {
                summary = default;
                return false;
            }

            summary = new DocOptionSummary(
                projectOption,
                outputOption,
                resultIndices[2] != 0,
                resultIndices[3] != 0,
                resultIndices[4] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryOrderSymbolsForGeneration(
        IReadOnlyList<SymbolResult> symbols,
        out List<SymbolResult> orderedSymbols)
        => TryOrderEntriesForGeneration(symbols, includeAllKinds: false, out orderedSymbols);

    internal static bool TryOrderMembersForGeneration(
        IReadOnlyList<SymbolResult> members,
        out List<SymbolResult> orderedMembers)
        => TryOrderEntriesForGeneration(members, includeAllKinds: true, out orderedMembers);

    internal static bool TryCreateSlugs(string[] rawSlugs, out string[] slugs)
    {
        slugs = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var resultSlugs = new string[rawSlugs.Length];
            var count = bindings.DocSlugs(rawSlugs, resultSlugs);
            if (count != rawSlugs.Length)
                return false;

            slugs = resultSlugs;
            return true;
        }
        catch
        {
            slugs = Array.Empty<string>();
            return false;
        }
    }

    private static bool TryOrderEntriesForGeneration(
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

        var scratch = t_symbolOrderScratch ??= new SymbolOrderScratch();
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
                scratch.KindRanks[i] = GetSymbolKindRank(symbol.Kind);
                scratch.NameRanks[i] = scratch.GetNameRank(symbol.Name);
                scratch.IncludeFlags[i] = (includeAllKinds || IsDocumentedSymbolKind(symbol.Kind)) ? 1 : 0;
            }

            var orderedCount = bindings.SymbolOrderCountingIndices(
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
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliDocSymbolOrderCountingIndicesInto>(
                programType,
                "CliDocSymbolOrderCountingIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliDocSlugsInto>(
                programType,
                "CliDocSlugsInto"),
            DogfoodKernelLoader.CreateDelegate<CliDocOptionSummaryInto>(
                programType,
                "CliDocOptionSummaryInto")));

    private static bool IsDocumentedSymbolKind(SymbolKind kind) =>
        kind is not SymbolKind.Variable and not SymbolKind.Parameter;

    private static int GetSymbolKindRank(SymbolKind kind) =>
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

    private delegate int CliDocSlugsInto(string[] rawSlugs, string[] resultSlugs);

    private delegate int CliDocOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private sealed record Bindings(
        CliDocSymbolOrderCountingIndicesInto SymbolOrderCountingIndices,
        CliDocSlugsInto DocSlugs,
        CliDocOptionSummaryInto OptionSummary);

    private static bool TryGetOptionalArg(string[] args, int index, out string? value)
    {
        value = null;
        if (index == -1)
            return true;

        if (index < 0 || index >= args.Length)
            return false;

        value = args[index];
        return true;
    }

    private sealed class SymbolOrderScratch
    {
        private readonly Dictionary<string, int> _nameRanks = new(StringComparer.Ordinal);

        internal int[] IncludeFlags = Array.Empty<int>();
        internal int[] KindCounts = Array.Empty<int>();
        internal int[] KindOffsets = Array.Empty<int>();
        internal int[] KindRanks = Array.Empty<int>();
        internal int[] NameCounts = Array.Empty<int>();
        internal int[] NameOffsets = Array.Empty<int>();
        internal int[] NameRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] TempIndices = Array.Empty<int>();
        internal string[] UniqueNames = Array.Empty<string>();
        internal int UniqueNameCount;

        internal void EnsureCapacity(int symbolCount)
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

        internal void AddName(string name)
        {
            if (_nameRanks.ContainsKey(name))
                return;

            _nameRanks.Add(name, 0);
            UniqueNames[UniqueNameCount] = name;
            UniqueNameCount++;
        }

        internal void BuildSortedNameRanks()
        {
            Array.Sort(UniqueNames, 0, UniqueNameCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueNameCount; i++)
            {
                _nameRanks[UniqueNames[i]] = i + 1;
            }
        }

        internal int GetNameRank(string name) => _nameRanks[name];

        internal void ResetNames()
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
