using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for ProjectConfig.GetSourceFiles' post-enumeration filtering.
///
/// The current C# helper chains two <c>.Where(...).ToArray()</c> passes (test-file filter, then
/// exclude-pattern filter) and recompiles a regex for every (file, pattern) pair via
/// <c>MatchesPattern</c>. The N# candidate classifies every project-relative path in a single pass,
/// hand-matches the exclude globs without regex, and writes kept indices into a caller-owned int[]
/// (stable indexes, no intermediate array allocations).
///
/// Parity is asserted in <see cref="Setup"/>: the kept-index set produced by the N# kernel must be
/// identical to the C# baseline for every corpus.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceProjectSourceFilterBenchmarks
{
    private Func<string[], string[], int, int[], int> _nsharpKeptIndicesInto =
        (_, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _relativePaths = Array.Empty<string>();
    private string[] _excludePatterns = Array.Empty<string>();
    private int _includeTests;

    private int[] _csharpKept = Array.Empty<int>();
    private int[] _nsharpKept = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpKeptIndicesInto =
            NSharpCompiledMethod.Bind<Func<string[], string[], int, int[], int>>(
                DogfoodCompilerSources.ProjectSourceFilter,
                "ProjectSourceFilterKeptIndicesInto");

        (_relativePaths, _excludePatterns) = BuildCorpus(Corpus);
        _includeTests = 0;

        _csharpKept = new int[_relativePaths.Length];
        _nsharpKept = new int[_relativePaths.Length];

        var expected = CSharpKeptIndices();
        var actual = NSharpKeptIndices();

        if (!expected.SequenceEqual(actual))
        {
            var mismatch = FirstMismatch(expected, actual);
            throw new InvalidOperationException(
                $"N# project source filter mismatch for {Corpus} at slot {mismatch}: " +
                $"expected/actual kept sets differ (expected count {expected.Length}, actual {actual.Length}).");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpFilterSourceFiles()
    {
        var kept = CSharpKeptIndices();
        return Checksum(kept);
    }

    [Benchmark]
    public int NSharpFilterSourceFiles()
    {
        var kept = NSharpKeptIndices();
        return Checksum(kept);
    }

    /// <summary>
    /// Exact replica of ProjectConfig.GetSourceFiles' filtering over an in-memory relative-path list:
    /// two LINQ passes plus per-file regex via the production MatchesPattern logic. Returns kept
    /// original indices (the production method preserves enumeration order).
    /// </summary>
    private int[] CSharpKeptIndices()
    {
        var includeTests = _includeTests != 0;
        var paths = _relativePaths;

        var afterTests = includeTests
            ? Enumerable.Range(0, paths.Length).ToArray()
            : Enumerable.Range(0, paths.Length)
                .Where(i => !paths[i].EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase))
                .ToArray();

        if (_excludePatterns.Length == 0)
        {
            Array.Copy(afterTests, _csharpKept, afterTests.Length);
            return _csharpKept[..afterTests.Length];
        }

        var afterExclude = afterTests
            .Where(i => !_excludePatterns.Any(pattern => MatchesPattern(paths[i], pattern)))
            .ToArray();

        Array.Copy(afterExclude, _csharpKept, afterExclude.Length);
        return _csharpKept[..afterExclude.Length];
    }

    private int[] NSharpKeptIndices()
    {
        var count = _nsharpKeptIndicesInto(_relativePaths, _excludePatterns, _includeTests, _nsharpKept);
        return _nsharpKept[..count];
    }

    // Verbatim copy of ProjectConfig.MatchesPattern (per-file regex compilation).
    private static bool MatchesPattern(string path, string pattern)
    {
        path = path.Replace('\\', '/');
        pattern = pattern.Replace('\\', '/');

        var regexPattern = "^" + Regex.Escape(pattern)
            .Replace("\\*\\*/", ".*?/")
            .Replace("\\*\\*", ".*")
            .Replace("\\*", "[^/]*")
            .Replace("\\?", ".")
            + "$";

        return Regex.IsMatch(path, regexPattern);
    }

    private static int Checksum(int[] kept)
    {
        var checksum = kept.Length;
        for (var i = 0; i < kept.Length; i++)
        {
            checksum += (kept[i] + 1) * (i + 1) * 31;
        }

        return checksum;
    }

    private static int FirstMismatch(int[] expected, int[] actual)
    {
        var min = Math.Min(expected.Length, actual.Length);
        for (var i = 0; i < min; i++)
        {
            if (expected[i] != actual[i])
            {
                return i;
            }
        }

        return min;
    }

    private static (string[] paths, string[] excludePatterns) BuildCorpus(CompilerLexerCorpus corpus)
    {
        var fileCount = corpus == CompilerLexerCorpus.Representative ? 400 : 6000;

        // A realistic-but-stressful set of exclude globs exercising literal, "*", "**", "?",
        // and "**/...*" forms.
        var excludePatterns = new[]
        {
            "Generated/*.nl",
            "temp/**/*.nl",
            "**/snapshots/*.nl",
            "vendor/**",
            "scratch?.nl",
        };

        var directories = new[]
        {
            "",
            "Core/",
            "Core/Internal/",
            "Features/Auth/",
            "Features/Billing/",
            "Generated/",
            "temp/a/",
            "temp/a/b/",
            "vendor/pkg/",
            "tools/snapshots/",
            "Models/",
        };

        var paths = new List<string>(fileCount);
        for (var i = 0; i < fileCount; i++)
        {
            var dir = directories[i % directories.Length];
            string name;
            switch (i % 7)
            {
                case 0:
                    name = $"Service{i}.nl";
                    break;
                case 1:
                    name = $"Handler{i}.tests.nl";
                    break;
                case 2:
                    name = $"Model{i}.nl";
                    break;
                case 3:
                    name = $"scratch{i % 10}.nl";
                    break;
                case 4:
                    name = $"View{i}.nl";
                    break;
                case 5:
                    name = $"Repository{i}.nl";
                    break;
                default:
                    name = $"Controller{i}.nl";
                    break;
            }

            // Mix in a few Windows-separator paths to exercise normalization.
            var path = dir + name;
            if (i % 13 == 0)
            {
                path = path.Replace('/', '\\');
            }

            paths.Add(path);
        }

        return (paths.ToArray(), excludePatterns);
    }
}
