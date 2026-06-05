using System;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc doc</c> symbol-page slug generation. The C# baseline mirrors the
/// previous production shape: lower-case the raw slug, map every non-letter/digit to a separator
/// with LINQ, allocate a char array/string, split on separators, then join the non-empty segments.
/// The N# candidate batches raw slugs through one growable char scratch buffer and writes only the
/// final lower-cased letter/digit characters.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliDocSlugBenchmarks
{
    private const int LargeSlugCount = 8192;
    private const int RepresentativeSlugCount = 1024;

    private Func<string[], string[], int> _nsharpCliDocSlugsInto =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _csharpSlugs = Array.Empty<string>();
    private string[] _nsharpSlugs = Array.Empty<string>();
    private string[] _rawSlugs = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var slugCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeSlugCount
            : LargeSlugCount;

        _nsharpCliDocSlugsInto =
            NSharpCompiledMethod.Bind<Func<string[], string[], int>>(
                DogfoodCompilerSources.CliDocOrdering,
                "CliDocSlugsInto");

        _rawSlugs = BuildRawSlugs(slugCount);
        _csharpSlugs = new string[slugCount];
        _nsharpSlugs = new string[slugCount];

        var expectedCount = CSharpCliDocSlugs_PageGeneration();
        var actualCount = NSharpCliDocSlugs_PageGeneration();
        if (expectedCount != actualCount)
        {
            throw new InvalidOperationException(
                $"N# CLI doc slug count mismatch for {Corpus}: expected {expectedCount}, got {actualCount}.");
        }

        if (!_csharpSlugs.SequenceEqual(_nsharpSlugs))
        {
            var mismatch = FirstMismatch();
            throw new InvalidOperationException(
                $"N# CLI doc slug mismatch for {Corpus} at item {mismatch}: " +
                $"raw {_rawSlugs[mismatch]}, expected {_csharpSlugs[mismatch]}, got {_nsharpSlugs[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCliDocSlugs_PageGeneration()
    {
        for (var i = 0; i < _rawSlugs.Length; i++)
        {
            var slug = CreateSlugWithLinq(_rawSlugs[i]);
            _csharpSlugs[i] = slug;
        }

        return _rawSlugs.Length;
    }

    [Benchmark]
    public int NSharpCliDocSlugs_PageGeneration() =>
        _nsharpCliDocSlugsInto(_rawSlugs, _nsharpSlugs);

    private static string CreateSlugWithLinq(string raw)
    {
        var chars = raw
            .ToLowerInvariant()
            .Select(ch => char.IsLetterOrDigit(ch) ? ch : '-')
            .ToArray();
        return string.Join(string.Empty, new string(chars).Split('-', StringSplitOptions.RemoveEmptyEntries));
    }

    private static string[] BuildRawSlugs(int count)
    {
        var slugs = new string[count];
        var kinds = new[]
        {
            "Class",
            "Constructor",
            "Enum",
            "Field",
            "Function",
            "Interface",
            "Method",
            "Property",
            "Record",
            "Struct",
            "Test",
            "TypeAlias",
            "Union"
        };
        var names = new[]
        {
            "Customer",
            "OrderState",
            "GetById",
            "HTTPClient2",
            "Result<T>",
            "Try_Parse_Value",
            "R\u00e9sum\u00e9_Count",
            "Create/Update",
            "User Profile",
            "Namespace.Qualified.Name",
            "Amount_Due_2026",
            "Value+Metadata"
        };
        var files = new[]
        {
            "Program.nl",
            "Service.Core.nl",
            "Models/Customer.nl",
            "Reports 2026.nl",
            "Feature.Flags.nl",
            "API.Client.nl",
            "types/result.nl",
            "Tests/Fixtures/Parser.nl"
        };

        for (var i = 0; i < count; i++)
        {
            var kind = kinds[i % kinds.Length];
            var name = names[(i * 7) % names.Length];
            var file = files[(i * 11) % files.Length];
            slugs[i] = $"{kind}-{name}-{file}-{i % 997}";
        }

        return slugs;
    }

    private int FirstMismatch()
    {
        for (var i = 0; i < _csharpSlugs.Length; i++)
        {
            if (_csharpSlugs[i] != _nsharpSlugs[i])
                return i;
        }

        return _csharpSlugs.Length;
    }
}
