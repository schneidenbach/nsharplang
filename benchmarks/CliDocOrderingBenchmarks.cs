using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for ordering symbols before <c>nlc doc</c> page generation.
///
/// The C# baseline mirrors the current CLI command shape: filter variable/parameter symbols,
/// order by <see cref="SymbolKind.ToString" /> using ordinal string comparison, then by symbol
/// name, and materialize the ordered list. The N# candidate runs after the host has assigned
/// compact kind/name ranks and returns ordered source indices in a caller-owned buffer.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliDocOrderingBenchmarks
{
    private const int LargeSymbolCount = 8192;
    private const int RepresentativeSymbolCount = 1024;

    private CliDocSymbolOrderCountingChecksumInto _nsharpDocSymbolOrderChecksumInto =
        (_, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _includeFlags = Array.Empty<int>();
    private int[] _kindCounts = Array.Empty<int>();
    private int[] _kindOffsets = Array.Empty<int>();
    private int[] _kindRanks = Array.Empty<int>();
    private int[] _nameCounts = Array.Empty<int>();
    private int[] _nameOffsets = Array.Empty<int>();
    private int[] _nameRanks = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private DocSymbolEntry[] _symbols = Array.Empty<DocSymbolEntry>();
    private int _symbolCount;
    private int[] _tempIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _symbolCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeSymbolCount
            : LargeSymbolCount;
        _nsharpDocSymbolOrderChecksumInto =
            NSharpCompiledMethod.Bind<CliDocSymbolOrderCountingChecksumInto>(
                DogfoodCompilerSources.CliDocOrdering,
                "CliDocSymbolOrderCountingChecksumInto");

        _symbols = BuildSymbols(_symbolCount);
        _kindRanks = new int[_symbolCount];
        _nameRanks = new int[_symbolCount];
        _includeFlags = new int[_symbolCount];
        _nsharpResultIndices = new int[_symbolCount];
        _tempIndices = new int[_symbolCount];
        _nameCounts = new int[_symbolCount + 1];
        _nameOffsets = new int[_symbolCount + 1];
        _kindCounts = new int[32];
        _kindOffsets = new int[32];

        BuildCompactRanks();

        var expectedChecksum = CSharpCliDocSymbols_OrderForGeneration();
        var actualChecksum = NSharpCliDocSymbols_OrderForGeneration();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# CLI doc symbol-order checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expected = OrderSymbolsWithCSharp();
        for (var i = 0; i < expected.Count; i++)
        {
            if (_nsharpResultIndices[i] != expected[i].Index)
            {
                throw new InvalidOperationException(
                    $"N# CLI doc symbol-order mismatch for {Corpus} at ordered item {i}: " +
                    $"expected source index {expected[i].Index}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCliDocSymbols_OrderForGeneration()
    {
        var ordered = OrderSymbolsWithCSharp();
        return ChecksumOrderedSymbols(ordered);
    }

    [Benchmark]
    public int NSharpCliDocSymbols_OrderForGeneration() =>
        _nsharpDocSymbolOrderChecksumInto(
            _kindRanks,
            _nameRanks,
            _includeFlags,
            _nameCounts,
            _nameOffsets,
            _kindCounts,
            _kindOffsets,
            _tempIndices,
            _nsharpResultIndices);

    private void BuildCompactRanks()
    {
        var names = new string[_symbols.Length];
        for (var i = 0; i < _symbols.Length; i++)
        {
            var symbol = _symbols[i];
            _kindRanks[i] = GetDocSymbolKindRank(symbol.Kind);
            _includeFlags[i] = symbol.Kind is SymbolKind.Variable or SymbolKind.Parameter ? 0 : 1;
            names[i] = symbol.Name;
        }

        Array.Sort(names, StringComparer.Ordinal);
        var nameRanks = new Dictionary<string, int>(StringComparer.Ordinal);
        var rank = 1;
        foreach (var name in names)
        {
            if (nameRanks.ContainsKey(name))
                continue;

            nameRanks.Add(name, rank);
            rank++;
        }

        for (var i = 0; i < _symbols.Length; i++)
        {
            _nameRanks[i] = nameRanks[_symbols[i].Name];
        }
    }

    private List<DocSymbolEntry> OrderSymbolsWithCSharp() =>
        _symbols
            .Where(symbol => symbol.Kind is not SymbolKind.Variable and not SymbolKind.Parameter)
            .OrderBy(symbol => symbol.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(symbol => symbol.Name, StringComparer.Ordinal)
            .ToList();

    private int ChecksumOrderedSymbols(IReadOnlyList<DocSymbolEntry> ordered)
    {
        var checksum = ordered.Count;
        for (var i = 0; i < ordered.Count; i++)
        {
            var index = ordered[i].Index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + _kindRanks[index] * 17 + _nameRanks[index] * 13;
        }

        return checksum;
    }

    private static DocSymbolEntry[] BuildSymbols(int count)
    {
        var names = new[]
        {
            "Customer",
            "CustomerService",
            "CustomerRepository",
            "Order",
            "OrderTotal",
            "Invoice",
            "InvoiceNumber",
            "Inventory",
            "Product",
            "ProductPrice",
            "ProcessAsync",
            "ResolveSymbol",
            "LookupIdentifier",
            "DiagnosticCluster",
            "FormatMessage",
            "CompletionItem",
            "SourceContext",
            "LineMap",
            "ReferenceResult",
            "BindingMap",
            "SemanticScope",
            "VisibleVariable",
            "DocPage",
            "ProjectManifest"
        };
        var kinds = new[]
        {
            SymbolKind.Function,
            SymbolKind.Class,
            SymbolKind.Struct,
            SymbolKind.Record,
            SymbolKind.Interface,
            SymbolKind.Enum,
            SymbolKind.Union,
            SymbolKind.Property,
            SymbolKind.Field,
            SymbolKind.Method,
            SymbolKind.Variable,
            SymbolKind.Parameter,
            SymbolKind.Constructor,
            SymbolKind.EnumMember,
            SymbolKind.TypeAlias,
            SymbolKind.Test
        };

        var symbols = new DocSymbolEntry[count];
        for (var i = 0; i < count; i++)
        {
            var kind = kinds[(i * 7 + i / 11) % kinds.Length];
            var baseName = names[(i * 13 + i / 5) % names.Length];
            var name = i % 17 == 0
                ? baseName
                : $"{baseName}{i % 211}";
            symbols[i] = new DocSymbolEntry(i, name, kind);
        }

        return symbols;
    }

    internal static int GetDocSymbolKindRank(SymbolKind kind) =>
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

    private sealed record DocSymbolEntry(int Index, string Name, SymbolKind Kind);

    private delegate int CliDocSymbolOrderCountingChecksumInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] includeFlags,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] resultIndices);
}

/// <summary>
/// Dogfood benchmark for ordering members inside generated <c>nlc doc</c> symbol pages.
///
/// The C# baseline mirrors the current symbol-page member rendering shape: order every member by
/// <see cref="SymbolKind.ToString" /> using ordinal string comparison, then by member name, and
/// materialize the ordered list. The N# candidate reuses the compact kind/name rank counting-order
/// kernel with all include flags set.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliDocMemberOrderingBenchmarks
{
    private const int LargeMemberCount = 8192;
    private const int RepresentativeMemberCount = 1024;

    private CliDocSymbolOrderCountingChecksumInto _nsharpDocMemberOrderChecksumInto =
        (_, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _includeFlags = Array.Empty<int>();
    private int[] _kindCounts = Array.Empty<int>();
    private int[] _kindOffsets = Array.Empty<int>();
    private int[] _kindRanks = Array.Empty<int>();
    private DocMemberEntry[] _members = Array.Empty<DocMemberEntry>();
    private int _memberCount;
    private int[] _nameCounts = Array.Empty<int>();
    private int[] _nameOffsets = Array.Empty<int>();
    private int[] _nameRanks = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _tempIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _memberCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeMemberCount
            : LargeMemberCount;
        _nsharpDocMemberOrderChecksumInto =
            NSharpCompiledMethod.Bind<CliDocSymbolOrderCountingChecksumInto>(
                DogfoodCompilerSources.CliDocOrdering,
                "CliDocSymbolOrderCountingChecksumInto");

        _members = BuildMembers(_memberCount);
        _kindRanks = new int[_memberCount];
        _nameRanks = new int[_memberCount];
        _includeFlags = new int[_memberCount];
        _nsharpResultIndices = new int[_memberCount];
        _tempIndices = new int[_memberCount];
        _nameCounts = new int[_memberCount + 1];
        _nameOffsets = new int[_memberCount + 1];
        _kindCounts = new int[32];
        _kindOffsets = new int[32];

        BuildCompactRanks();

        var expectedChecksum = CSharpCliDocMembers_OrderForSymbolPage();
        var actualChecksum = NSharpCliDocMembers_OrderForSymbolPage();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# CLI doc member-order checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expected = OrderMembersWithCSharp();
        for (var i = 0; i < expected.Count; i++)
        {
            if (_nsharpResultIndices[i] != expected[i].Index)
            {
                throw new InvalidOperationException(
                    $"N# CLI doc member-order mismatch for {Corpus} at ordered item {i}: " +
                    $"expected source index {expected[i].Index}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCliDocMembers_OrderForSymbolPage()
    {
        var ordered = OrderMembersWithCSharp();
        return ChecksumOrderedMembers(ordered);
    }

    [Benchmark]
    public int NSharpCliDocMembers_OrderForSymbolPage() =>
        _nsharpDocMemberOrderChecksumInto(
            _kindRanks,
            _nameRanks,
            _includeFlags,
            _nameCounts,
            _nameOffsets,
            _kindCounts,
            _kindOffsets,
            _tempIndices,
            _nsharpResultIndices);

    private void BuildCompactRanks()
    {
        var names = new string[_members.Length];
        for (var i = 0; i < _members.Length; i++)
        {
            var member = _members[i];
            _kindRanks[i] = CliDocOrderingBenchmarks.GetDocSymbolKindRank(member.Kind);
            _includeFlags[i] = 1;
            names[i] = member.Name;
        }

        Array.Sort(names, StringComparer.Ordinal);
        var nameRanks = new Dictionary<string, int>(StringComparer.Ordinal);
        var rank = 1;
        foreach (var name in names)
        {
            if (nameRanks.ContainsKey(name))
                continue;

            nameRanks.Add(name, rank);
            rank++;
        }

        for (var i = 0; i < _members.Length; i++)
        {
            _nameRanks[i] = nameRanks[_members[i].Name];
        }
    }

    private List<DocMemberEntry> OrderMembersWithCSharp() =>
        _members
            .OrderBy(member => member.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(member => member.Name, StringComparer.Ordinal)
            .ToList();

    private int ChecksumOrderedMembers(IReadOnlyList<DocMemberEntry> ordered)
    {
        var checksum = ordered.Count;
        for (var i = 0; i < ordered.Count; i++)
        {
            var index = ordered[i].Index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + _kindRanks[index] * 17 + _nameRanks[index] * 13;
        }

        return checksum;
    }

    private static DocMemberEntry[] BuildMembers(int count)
    {
        var names = new[]
        {
            "Id",
            "Name",
            "Amount",
            "CreatedAt",
            "UpdatedAt",
            "Validate",
            "TryParse",
            "Serialize",
            "Deserialize",
            "Handle",
            "Execute",
            "Cancel",
            "Result",
            "Error",
            "Value",
            "Count",
            "Index",
            "Current",
            "MoveNext",
            "Dispose"
        };
        var kinds = new[]
        {
            SymbolKind.Property,
            SymbolKind.Field,
            SymbolKind.Method,
            SymbolKind.Constructor,
            SymbolKind.Function,
            SymbolKind.EnumMember,
            SymbolKind.Parameter,
            SymbolKind.Variable,
            SymbolKind.TypeAlias,
            SymbolKind.Class
        };

        var members = new DocMemberEntry[count];
        for (var i = 0; i < count; i++)
        {
            var kind = kinds[(i * 5 + i / 13) % kinds.Length];
            var baseName = names[(i * 11 + i / 7) % names.Length];
            var name = i % 19 == 0
                ? baseName
                : $"{baseName}{i % 257}";
            members[i] = new DocMemberEntry(i, name, kind);
        }

        return members;
    }

    private sealed record DocMemberEntry(int Index, string Name, SymbolKind Kind);

    private delegate int CliDocSymbolOrderCountingChecksumInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] includeFlags,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] resultIndices);
}
