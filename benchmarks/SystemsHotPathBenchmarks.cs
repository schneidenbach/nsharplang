using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Systems N# smoke benchmark: a hot-path style frame scorer over caller-owned memory.
/// BenchmarkDotNet measures both throughput and allocation pressure through
/// <see cref="MemoryDiagnoserAttribute"/>. The setup compiles N# once, then benchmark iterations
/// call the emitted method directly through a cached delegate.
/// </summary>
[MemoryDiagnoser]
public class SystemsHotPathBenchmarks
{
    private const string Source = """
[hot]
func scoreFrame(values: int[]): int {
    if values.Length < 4 {
        return -1
    }

    checksum := 0
    for i := 4; i < values.Length; i++ {
        checksum = checksum + values[i]
    }

    return checksum + values[0] + values[1] + values[2] + values[3]
}
""";

    private int[] _values = Array.Empty<int>();
    private Func<int[], int> _nsharp = null!;

    [GlobalSetup]
    public void Setup()
    {
        _values = new int[1024];
        for (var i = 0; i < _values.Length; i++)
        {
            _values[i] = i & 0xff;
        }

        _nsharp = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "scoreFrame");
    }

    [Benchmark(Baseline = true)]
    public int CSharp()
    {
        if (_values.Length < 4)
        {
            return -1;
        }

        var checksum = 0;
        for (var i = 4; i < _values.Length; i++)
        {
            checksum += _values[i];
        }

        return checksum + _values[0] + _values[1] + _values[2] + _values[3];
    }

    [Benchmark]
    public int NSharp() => _nsharp(_values);
}
