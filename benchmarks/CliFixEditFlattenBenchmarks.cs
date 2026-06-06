using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for flattening safe <c>nlc fix</c> edit lists before validation.
/// The C# baseline mirrors the current CLI shape after safety filtering:
/// <c>safeActions.SelectMany(action => action.Edits).ToList()</c>. The N# candidate runs after
/// the host has projected each safe action's edit count and writes flattened action/edit indices
/// into caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliFixEditFlattenBenchmarks
{
    private const int LargeActionCount = 8192;
    private const int RepresentativeActionCount = 1024;

    private Func<int[], int[], int[], int> _nsharpCliFixEditFlattenChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpActionIndices = Array.Empty<int>();
    private int[] _csharpEditIndices = Array.Empty<int>();
    private int[] _editCounts = Array.Empty<int>();
    private int _flattenedEditCount;
    private int[] _nsharpActionIndices = Array.Empty<int>();
    private int[] _nsharpEditIndices = Array.Empty<int>();
    private BenchmarkFixAction[] _safeActions = Array.Empty<BenchmarkFixAction>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var actionCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeActionCount
            : LargeActionCount;
        _nsharpCliFixEditFlattenChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliFixEditFlattenChecksumInto");

        _safeActions = BuildSafeActions(actionCount);
        _editCounts = _safeActions.Select(action => action.Edits.Count).ToArray();
        _flattenedEditCount = _editCounts.Sum();
        _csharpActionIndices = new int[_flattenedEditCount];
        _csharpEditIndices = new int[_flattenedEditCount];
        _nsharpActionIndices = new int[_flattenedEditCount];
        _nsharpEditIndices = new int[_flattenedEditCount];

        var expectedChecksum = CSharpFixEditFlatten_Cli();
        var actualChecksum = NSharpFixEditFlatten_Cli();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# fix edit flatten checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < _flattenedEditCount; i++)
        {
            if (_csharpActionIndices[i] != _nsharpActionIndices[i]
                || _csharpEditIndices[i] != _nsharpEditIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# fix edit flatten mismatch for {Corpus} at result {i}: " +
                    $"expected ({_csharpActionIndices[i]}, {_csharpEditIndices[i]}), " +
                    $"got ({_nsharpActionIndices[i]}, {_nsharpEditIndices[i]}).");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpFixEditFlatten_Cli()
    {
        var edits = _safeActions
            .SelectMany(action => action.Edits)
            .ToList();

        var checksum = edits.Count;
        for (var i = 0; i < edits.Count; i++)
        {
            var edit = edits[i];
            _csharpActionIndices[i] = edit.ActionIndex;
            _csharpEditIndices[i] = edit.EditIndex;
            checksum += (i + 1) * 97
                + (edit.ActionIndex + 1) * 31
                + (edit.EditIndex + 1) * 17
                + _editCounts[edit.ActionIndex] * 13;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpFixEditFlatten_Cli() =>
        _nsharpCliFixEditFlattenChecksumInto(
            _editCounts,
            _nsharpActionIndices,
            _nsharpEditIndices);

    private static BenchmarkFixAction[] BuildSafeActions(int count)
    {
        var actions = new BenchmarkFixAction[count];
        for (var i = 0; i < count; i++)
        {
            var editCount = ((i * 17 + i / 23) % 8) + 1;
            var edits = new List<BenchmarkTextEdit>(editCount);
            for (var editIndex = 0; editIndex < editCount; editIndex++)
            {
                edits.Add(new BenchmarkTextEdit(i, editIndex));
            }

            actions[i] = new BenchmarkFixAction(edits);
        }

        return actions;
    }

    private sealed record BenchmarkFixAction(List<BenchmarkTextEdit> Edits);

    private sealed record BenchmarkTextEdit(int ActionIndex, int EditIndex);
}
