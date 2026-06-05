using System;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for the declared-field readonly gate in struct-copy analysis. The C#
/// baseline mirrors the old compiler-service shape: filter out static fields with LINQ,
/// materialize the instance-field list, then test whether every remaining field is init-only.
/// The N# candidate runs over compact static/init-only flags in caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceStructCopyFieldAnalysisBenchmarks
{
    private const int LargeFieldCount = 8192;
    private const int RepresentativeFieldCount = 1024;

    private Func<int[], int, int> _nsharpAllInstanceFieldsInitOnly =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private BenchmarkStructCopyField[] _fields = Array.Empty<BenchmarkStructCopyField>();
    private int[] _fieldReadonlyFlags = Array.Empty<int>();
    private int _fieldCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        StructCopyFieldShape.AllReadonly,
        StructCopyFieldShape.LastInstanceMutable)]
    public StructCopyFieldShape Shape { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _fieldCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeFieldCount
            : LargeFieldCount;
        _nsharpAllInstanceFieldsInitOnly =
            NSharpCompiledMethod.Bind<Func<int[], int, int>>(
                DogfoodCompilerSources.StructCopyAnalysis,
                "StructCopyAllInstanceFieldsInitOnly");

        _fields = BuildFields(_fieldCount, Shape);
        _fieldReadonlyFlags = new int[_fieldCount];
        BuildFieldReadonlyFlags();

        var expected = CSharpStructCopy_AllInstanceFieldsInitOnly();
        var actual = NSharpStructCopy_AllInstanceFieldsInitOnly();
        if (expected != actual)
        {
            throw new InvalidOperationException(
                $"N# struct-copy field analysis mismatch for {Corpus}/{Shape}: " +
                $"expected {expected}, got {actual}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpStructCopy_AllInstanceFieldsInitOnly()
    {
        var instanceFields = _fields
            .Where(field => !field.IsStatic)
            .ToList();

        return instanceFields.Count == 0 || instanceFields.All(field => field.IsInitOnly)
            ? 1
            : 0;
    }

    [Benchmark]
    public int NSharpStructCopy_AllInstanceFieldsInitOnly() =>
        _nsharpAllInstanceFieldsInitOnly(_fieldReadonlyFlags, _fieldCount);

    private void BuildFieldReadonlyFlags()
    {
        for (var i = 0; i < _fields.Length; i++)
        {
            _fieldReadonlyFlags[i] = _fields[i].IsStatic || _fields[i].IsInitOnly ? 1 : 0;
        }
    }

    private static BenchmarkStructCopyField[] BuildFields(int count, StructCopyFieldShape shape)
    {
        var fields = new BenchmarkStructCopyField[count];
        var lastInstanceIndex = -1;
        for (var i = 0; i < count; i++)
        {
            var isStatic = i % 7 == 0;
            if (!isStatic)
                lastInstanceIndex = i;

            fields[i] = new BenchmarkStructCopyField(
                i,
                isStatic,
                IsInitOnly: true);
        }

        if (shape == StructCopyFieldShape.LastInstanceMutable && lastInstanceIndex >= 0)
        {
            fields[lastInstanceIndex] = fields[lastInstanceIndex] with { IsInitOnly = false };
        }

        return fields;
    }
}

public enum StructCopyFieldShape
{
    AllReadonly,
    LastInstanceMutable
}

public readonly record struct BenchmarkStructCopyField(int Index, bool IsStatic, bool IsInitOnly);
