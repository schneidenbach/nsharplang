using BenchmarkDotNet.Attributes;
using NSharpLang.Runtime;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Systems N# Result ABI benchmark. The methods exercise both throughput and
/// allocation pressure for the blessed tagged-struct result shape.
/// </summary>
[MemoryDiagnoser]
public class SystemsResultBenchmarks
{
    private Result<int, int>[] _results = [];

    [GlobalSetup]
    public void Setup()
    {
        _results = new Result<int, int>[1024];
        for (var i = 0; i < _results.Length; i++)
        {
            _results[i] = (i & 1) == 0
                ? Result<int, int>.Ok(i)
                : Result<int, int>.Err(-i);
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTaggedStruct()
    {
        var sum = 0;
        foreach (var result in _results)
        {
            if (result.TryGetOk(out var value))
                sum += value;
        }

        return sum;
    }

    [Benchmark]
    public int MatchDelegate()
    {
        var sum = 0;
        foreach (var result in _results)
        {
            sum += result.Match(static value => value, static _ => 0);
        }

        return sum;
    }
}
