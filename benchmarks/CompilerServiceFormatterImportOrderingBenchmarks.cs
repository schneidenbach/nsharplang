using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <see cref="NSharpLang.Compiler.Formatter"/> import/using
/// ordering. The C# baseline mirrors the production LINQ shape used in
/// <c>Formatter.Format</c>:
/// <code>
/// ast.Imports
///     .OrderByDescending(i => i.Namespace.StartsWith("System"))
///     .ThenBy(i => i.Namespace)
///     .ToList();
/// </code>
/// LINQ <c>OrderBy</c>/<c>OrderByDescending</c> are stable, so identical namespaces
/// keep their input order. The N# candidate runs after the host compacts each import
/// to a dense ordinal namespace rank plus a System-prefix flag, and returns the
/// ordered source indices via a caller-owned int[].
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceFormatterImportOrderingBenchmarks
{
    private FormatterImportOrderChecksumInto _nsharpFormatterImportOrderChecksumInto =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _namespaces = Array.Empty<string>();
    private int[] _systemFlags = Array.Empty<int>();
    private int[] _nameRanks = Array.Empty<int>();
    private int[] _bucketCounts = Array.Empty<int>();
    private int[] _bucketOffsets = Array.Empty<int>();
    private int[] _tempIndices = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int _nameRankCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpFormatterImportOrderChecksumInto =
            NSharpCompiledMethod.Bind<FormatterImportOrderChecksumInto>(
                DogfoodCompilerSources.FormatterImportOrdering,
                "FormatterImportOrderChecksumInto");

        _namespaces = BuildNamespaces(Corpus);
        _systemFlags = new int[_namespaces.Length];
        _nameRanks = new int[_namespaces.Length];
        for (var i = 0; i < _namespaces.Length; i++)
        {
            _systemFlags[i] = _namespaces[i].StartsWith("System", StringComparison.Ordinal) ? 1 : 0;
        }

        _nameRankCount = BuildNameRanks(_namespaces, _nameRanks);
        _bucketCounts = new int[_nameRankCount + 1];
        _bucketOffsets = new int[_nameRankCount + 1];
        _tempIndices = new int[_namespaces.Length];
        _nsharpResultIndices = new int[_namespaces.Length];

        var expectedChecksum = CSharpImports_OrderForFormatting();
        var actualChecksum = NSharpImports_OrderForFormatting();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# import order checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expected = SortWithCSharp();
        for (var i = 0; i < expected.Count; i++)
        {
            if (_nsharpResultIndices[i] != expected[i])
            {
                throw new InvalidOperationException(
                    $"N# import order mismatch for {Corpus} at ordered item {i}: " +
                    $"expected source index {expected[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpImports_OrderForFormatting()
    {
        var ordered = SortWithCSharp();
        return ChecksumOrderedImports(ordered);
    }

    [Benchmark]
    public int NSharpImports_OrderForFormatting() =>
        _nsharpFormatterImportOrderChecksumInto(
            _systemFlags,
            _nameRanks,
            _nameRankCount,
            _bucketCounts,
            _bucketOffsets,
            _tempIndices,
            _nsharpResultIndices);

    private List<int> SortWithCSharp() =>
        _namespaces
            .Select((ns, index) => new { Namespace = ns, Index = index })
            .OrderByDescending(item => item.Namespace.StartsWith("System", StringComparison.Ordinal))
            .ThenBy(item => item.Namespace, StringComparer.Ordinal)
            .Select(item => item.Index)
            .ToList();

    private int ChecksumOrderedImports(IReadOnlyList<int> ordered)
    {
        var checksum = ordered.Count;
        for (var i = 0; i < ordered.Count; i++)
        {
            var index = ordered[i];
            checksum += (i + 1) * 97 + (index + 1) * 31;
            checksum += _systemFlags[index] * 17 + _nameRanks[index] * 13;
        }

        return checksum;
    }

    private static int BuildNameRanks(string[] namespaces, int[] ranks)
    {
        var unique = namespaces.Distinct(StringComparer.Ordinal).ToArray();
        Array.Sort(unique, StringComparer.Ordinal);

        var rankMap = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < unique.Length; i++)
        {
            rankMap[unique[i]] = i + 1;
        }

        for (var i = 0; i < namespaces.Length; i++)
        {
            ranks[i] = rankMap[namespaces[i]];
        }

        return unique.Length;
    }

    private static string[] BuildNamespaces(CompilerLexerCorpus corpus)
    {
        // Representative: a realistic single-file import set (~30 imports) mixing
        // System.* namespaces, third-party, and project-local namespaces with a few
        // duplicates to exercise stable ordering. Large: many such files concatenated
        // to stress the sort with a larger working set.
        var palette = new[]
        {
            "System",
            "System.Collections.Generic",
            "System.Collections.Immutable",
            "System.Linq",
            "System.Text",
            "System.Text.Json",
            "System.Threading",
            "System.Threading.Tasks",
            "System.IO",
            "System.Reflection",
            "System.Runtime.CompilerServices",
            "System.Diagnostics",
            "Microsoft.Extensions.Logging",
            "Microsoft.Extensions.DependencyInjection",
            "Microsoft.CodeAnalysis",
            "Newtonsoft.Json",
            "Serilog",
            "Xunit",
            "NSharpLang.Compiler",
            "NSharpLang.Compiler.CodeIntelligence",
            "NSharpLang.LanguageServer",
            "NSharpLang.Cli",
            "Acme.Widgets",
            "Acme.Widgets.Internal",
            "Zenith.Core",
            "Zenith.Core.Abstractions",
            "Contoso.Billing",
            "Contoso.Billing.Models",
            "System.Net.Http",
            "System.Globalization",
        };

        var fileCount = corpus == CompilerLexerCorpus.Representative ? 1 : 256;
        var result = new List<string>(palette.Length * fileCount);
        for (var f = 0; f < fileCount; f++)
        {
            // Deterministically permute and inject occasional duplicates per "file"
            // so the stable-sort tie path is exercised on both corpora.
            for (var i = 0; i < palette.Length; i++)
            {
                var pick = palette[(i * 7 + f * 13) % palette.Length];
                result.Add(pick);
                if ((i + f) % 11 == 0)
                {
                    result.Add(pick);
                }
            }
        }

        return result.ToArray();
    }

    private delegate int FormatterImportOrderChecksumInto(
        int[] systemFlags,
        int[] nameRanks,
        int nameRankCount,
        int[] bucketCounts,
        int[] bucketOffsets,
        int[] tempIndices,
        int[] resultIndices);
}
