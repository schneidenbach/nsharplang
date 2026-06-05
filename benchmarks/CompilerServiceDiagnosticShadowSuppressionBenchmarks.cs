using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for suppressing linter shadowing diagnostics already covered by compiler
/// shadowing errors in <c>CodeIntelligenceService.GetDiagnostics</c>.
///
/// The C# baseline mirrors the previous service shape: a case-insensitive shadowed-file set and
/// LINQ list materialization. The N# candidate runs after the host has assigned compact code/file
/// ranks and marked shadowed file ranks in caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceDiagnosticShadowSuppressionBenchmarks
{
    private const int LargeDiagnosticCount = 8192;
    private const int RepresentativeDiagnosticCount = 1024;
    private const string ShadowingCode = "NL020";

    private int[] _codeIds = Array.Empty<int>();
    private int _csharpResultCount;
    private int[] _csharpResultIndices = Array.Empty<int>();
    private DiagnosticEntry[] _diagnostics = Array.Empty<DiagnosticEntry>();
    private int _diagnosticCount;
    private int[] _fileRanks = Array.Empty<int>();
    private Func<int[], int[], int, int[], int[], int> _nsharpDiagnosticShadowSuppressionChecksumInto =
        (_, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private HashSet<string> _shadowedFiles = new(StringComparer.OrdinalIgnoreCase);
    private int[] _shadowFileFlags = Array.Empty<int>();
    private int _targetCodeId;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _diagnosticCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDiagnosticCount
            : LargeDiagnosticCount;
        _nsharpDiagnosticShadowSuppressionChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int, int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticClusters,
                "DiagnosticShadowSuppressionChecksumInto");

        _diagnostics = BuildDiagnostics(_diagnosticCount);
        _codeIds = new int[_diagnosticCount];
        _fileRanks = new int[_diagnosticCount];
        _csharpResultIndices = new int[_diagnosticCount];
        _nsharpResultIndices = new int[_diagnosticCount];

        BuildRanksAndShadowFlags();

        var expectedChecksum = CSharpDiagnosticShadowSuppression_GetDiagnostics();
        var actualChecksum = NSharpDiagnosticShadowSuppression_GetDiagnostics();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# diagnostic shadow suppression checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < _csharpResultCount; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# diagnostic shadow suppression mismatch for {Corpus} at result {i}: " +
                    $"expected source index {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDiagnosticShadowSuppression_GetDiagnostics()
    {
        var filtered = _diagnostics
            .Where(diagnostic => diagnostic.Code != ShadowingCode || !_shadowedFiles.Contains(diagnostic.File))
            .ToList();

        _csharpResultCount = filtered.Count;
        var checksum = filtered.Count;
        for (var i = 0; i < filtered.Count; i++)
        {
            var index = filtered[i].Index;
            _csharpResultIndices[i] = index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + _codeIds[index] * 17 + _fileRanks[index] * 13;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpDiagnosticShadowSuppression_GetDiagnostics() =>
        _nsharpDiagnosticShadowSuppressionChecksumInto(
            _codeIds,
            _fileRanks,
            _targetCodeId,
            _shadowFileFlags,
            _nsharpResultIndices);

    private void BuildRanksAndShadowFlags()
    {
        var codeIds = new Dictionary<string, int>(StringComparer.Ordinal);
        var fileRanks = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var uniqueFiles = new List<string>();

        int GetCodeId(string code)
        {
            if (codeIds.TryGetValue(code, out var id))
                return id;

            id = codeIds.Count + 1;
            codeIds.Add(code, id);
            return id;
        }

        void AddFile(string file)
        {
            if (fileRanks.ContainsKey(file))
                return;

            fileRanks.Add(file, 0);
            uniqueFiles.Add(file);
        }

        _targetCodeId = GetCodeId(ShadowingCode);
        _shadowedFiles = BuildShadowedFiles(_diagnosticCount);

        foreach (var diagnostic in _diagnostics)
        {
            GetCodeId(diagnostic.Code);
            AddFile(diagnostic.File);
        }

        foreach (var file in _shadowedFiles)
        {
            AddFile(file);
        }

        uniqueFiles.Sort(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < uniqueFiles.Count; i++)
        {
            fileRanks[uniqueFiles[i]] = i + 1;
        }

        for (var i = 0; i < _diagnostics.Length; i++)
        {
            _codeIds[i] = codeIds[_diagnostics[i].Code];
            _fileRanks[i] = fileRanks[_diagnostics[i].File];
        }

        _shadowFileFlags = new int[uniqueFiles.Count + 1];
        foreach (var file in _shadowedFiles)
        {
            _shadowFileFlags[fileRanks[file]] = 1;
        }
    }

    private static DiagnosticEntry[] BuildDiagnostics(int count)
    {
        var codes = new[] { ShadowingCode, "NL001", "NL042", ShadowingCode, "NL017", "NL0200", "NL031" };
        var diagnostics = new DiagnosticEntry[count];
        var fileCount = Math.Max(16, count / 8);
        for (var i = 0; i < count; i++)
        {
            var code = codes[(i * 5 + i / 11) % codes.Length];
            var fileIndex = (i * 37 + i / 13) % fileCount;
            var file = fileIndex % 5 == 0
                ? $"SRC/Module{fileIndex:0000}.NL"
                : $"src/module{fileIndex:0000}.nl";
            diagnostics[i] = new DiagnosticEntry(i, code, file);
        }

        return diagnostics;
    }

    private static HashSet<string> BuildShadowedFiles(int diagnosticCount)
    {
        var shadowedFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var fileCount = Math.Max(16, diagnosticCount / 8);
        for (var i = 0; i < fileCount; i += 3)
        {
            shadowedFiles.Add($"src/module{i:0000}.nl");
        }

        return shadowedFiles;
    }

    private sealed record DiagnosticEntry(int Index, string Code, string File);
}
