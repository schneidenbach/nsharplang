using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Pattern 1: <c>foreach</c> over <c>T[]</c>. The N# side lowers to an allocation-free index loop
/// (no enumerator). IL ratchet: <c>Gate_ForeachOverArray_AllocatesNoEnumerator_AndDispatchesNothing</c>.
/// </summary>
[MemoryDiagnoser]
public class ForeachArrayBenchmarks
{
    private const string Source = """
func sumArray(numbers: int[]): int {
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}
""";

    private int[] _data = Array.Empty<int>();
    private Func<int[], int> _nsharp = null!;

    [GlobalSetup]
    public void Setup()
    {
        _data = new int[1024];
        for (var i = 0; i < _data.Length; i++)
        {
            _data[i] = i;
        }

        _nsharp = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "sumArray");
    }

    [Benchmark(Baseline = true)]
    public int CSharp()
    {
        var sum = 0;
        foreach (var n in _data)
        {
            sum += n;
        }

        return sum;
    }

    [Benchmark]
    public int NSharp() => _nsharp(_data);
}
