using System;
using System.Linq;
using System.Text.RegularExpressions;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

public enum CliSymbolNameFilterPattern
{
    PrefixGlob,
    SuffixGlob,
    Substring
}

/// <summary>
/// Dogfood benchmark for <c>nlc query symbols --filter</c>. The C# baseline mirrors the
/// current CLI wildcard semantics: build a case-insensitive regex, filter names, stop at 200
/// matches, and materialize the result. The N# candidate keeps the accepted ASCII glob path in
/// systems code and returns source indices for host-side materialization.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliSymbolNameFilterBenchmarks
{
    private const int LargeSymbolCount = 8192;
    private const int Limit = 200;
    private const int RepresentativeSymbolCount = 1024;

    private Func<string[], string, int, int[], int> _nsharpCliSymbolNameGlobFilterIndicesInto =
        (_, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<string[], string, int, int[], int> _nsharpCliSymbolNameSubstringFilterIndicesInto =
        (_, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _csharpResult = Array.Empty<string>();
    private string[] _names = Array.Empty<string>();
    private int[] _nsharpIndices = Array.Empty<int>();
    private string[] _nsharpResult = Array.Empty<string>();
    private string _pattern = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        CliSymbolNameFilterPattern.PrefixGlob,
        CliSymbolNameFilterPattern.SuffixGlob,
        CliSymbolNameFilterPattern.Substring)]
    public CliSymbolNameFilterPattern Pattern { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var symbolCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeSymbolCount
            : LargeSymbolCount;
        _nsharpCliSymbolNameGlobFilterIndicesInto =
            NSharpCompiledMethod.Bind<Func<string[], string, int, int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliSymbolNameGlobFilterIndicesInto");
        _nsharpCliSymbolNameSubstringFilterIndicesInto =
            NSharpCompiledMethod.Bind<Func<string[], string, int, int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliSymbolNameSubstringFilterIndicesInto");

        _names = BuildSymbolNames(symbolCount);
        _nsharpIndices = new int[Math.Min(symbolCount, Limit)];
        _pattern = Pattern switch
        {
            CliSymbolNameFilterPattern.PrefixGlob => "User*",
            CliSymbolNameFilterPattern.SuffixGlob => "*Service",
            CliSymbolNameFilterPattern.Substring => "query",
            _ => throw new InvalidOperationException($"Unexpected pattern mode {Pattern}.")
        };

        var expectedChecksum = CSharpCliSymbolNameFilter_QuerySymbols();
        var actualChecksum = NSharpCliSymbolNameFilter_QuerySymbols();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# CLI symbol-name filter checksum mismatch for {Corpus}/{Pattern}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpResult.SequenceEqual(_nsharpResult))
        {
            var mismatch = FirstMismatch();
            throw new InvalidOperationException(
                $"N# CLI symbol-name filter mismatch for {Corpus}/{Pattern} at result {mismatch}: " +
                $"expected {FormatNameAt(_csharpResult, mismatch)}, got {FormatNameAt(_nsharpResult, mismatch)}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCliSymbolNameFilter_QuerySymbols()
    {
        var regex = BuildSymbolFilterRegex(_pattern);
        _csharpResult = _names
            .Where(name => regex.IsMatch(name))
            .Take(Limit)
            .ToArray();
        return ChecksumNames(_csharpResult);
    }

    [Benchmark]
    public int NSharpCliSymbolNameFilter_QuerySymbols()
    {
        var count = Pattern == CliSymbolNameFilterPattern.Substring
            ? _nsharpCliSymbolNameSubstringFilterIndicesInto(_names, _pattern, Limit, _nsharpIndices)
            : _nsharpCliSymbolNameGlobFilterIndicesInto(_names, _pattern, Limit, _nsharpIndices);
        if (count < 0 || count > _nsharpIndices.Length)
            throw new InvalidOperationException($"N# CLI symbol-name filter count out of range: {count}.");

        _nsharpResult = new string[count];
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = _nsharpIndices[i];
            if (sourceIndex < 0 || sourceIndex >= _names.Length)
                throw new InvalidOperationException($"N# CLI symbol-name filter index out of range: {sourceIndex}.");

            _nsharpResult[i] = _names[sourceIndex];
        }

        return ChecksumNames(_nsharpResult);
    }

    private static Regex BuildSymbolFilterRegex(string pattern)
    {
        if (pattern.Contains('*'))
        {
            var regexPattern = "^" + Regex.Escape(pattern).Replace("\\*", ".*") + "$";
            return new Regex(regexPattern, RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(200));
        }

        return new Regex(Regex.Escape(pattern), RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(200));
    }

    private static string[] BuildSymbolNames(int count)
    {
        var names = new string[count];
        var fillerPrefixes = new[]
        {
            "RenderPipeline",
            "BuildGraph",
            "TokenScanner",
            "DiagnosticCluster",
            "ProjectSnapshot",
            "CompletionReceiver",
            "ReferenceWalker",
            "TypeResolver"
        };

        for (var i = 0; i < count; i++)
        {
            if (i % 17 == 0)
            {
                names[i] = $"User{i}Service";
                continue;
            }

            if (i % 19 == 0)
            {
                names[i] = $"Order{i}Service";
                continue;
            }

            if (i % 23 == 0)
            {
                names[i] = $"User{i}Query";
                continue;
            }

            if (i % 29 == 0)
            {
                names[i] = $"Data{i}QuerySet";
                continue;
            }

            names[i] = $"{fillerPrefixes[i % fillerPrefixes.Length]}{i}Handler";
        }

        return names;
    }

    private int FirstMismatch()
    {
        var count = Math.Min(_csharpResult.Length, _nsharpResult.Length);
        for (var i = 0; i < count; i++)
        {
            if (_csharpResult[i] != _nsharpResult[i])
                return i;
        }

        return count;
    }

    private static int ChecksumNames(string[] names)
    {
        var checksum = names.Length;
        for (var i = 0; i < names.Length; i++)
        {
            var name = names[i];
            checksum += (i + 1) * 97 + name.Length * 31;
            if (name.Length > 0)
                checksum += name[0] * 17 + name[^1] * 13;
        }

        return checksum;
    }

    private static string FormatNameAt(string[] names, int index) =>
        index >= 0 && index < names.Length ? $"\"{names[index]}\"" : "<missing>";
}
