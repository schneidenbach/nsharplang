using System;
using System.Buffers;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Boundary-to-hot benchmarks that rent a pooled buffer, copy already-materialized boundary data
/// into it, and hand that caller-owned storage to a hot N# function.
/// </summary>
[MemoryDiagnoser]
public class SystemsPooledBoundaryBenchmarks
{
    private const string Source = """
[hot]
func countNonZero(values: int[], len: int): int {
    count := 0
    for i := 0; i < len; i++ {
        if values[i] != 0 {
            count = count + 1
        }
    }

    return count
}

[hot]
func scorePooledFrame(values: int[], len: int): int {
    if len < 4 {
        return -1
    }

    score := values[0] + values[1] + values[2] + values[3]
    for i := 4; i < len; i++ {
        score = score + values[i]
    }

    return score
}

[hot]
func clampAndScore(values: int[], len: int): int {
    score := 0
    for i := 0; i < len; i++ {
        value := values[i]
        if value < 0 {
            value = 0
        }

        values[i] = value
        score = score + value
    }

    return score
}
""";

    private int[] _seed = Array.Empty<int>();
    private Func<int[], int, int> _countNonZero = null!;
    private Func<int[], int, int> _scorePooledFrame = null!;
    private Func<int[], int, int> _clampAndScore = null!;

    public enum PooledBoundaryWorkload
    {
        CountNonZero,
        ScorePooledFrame,
        ClampAndScore,
    }

    [Params(
        PooledBoundaryWorkload.CountNonZero,
        PooledBoundaryWorkload.ScorePooledFrame,
        PooledBoundaryWorkload.ClampAndScore)]
    public PooledBoundaryWorkload Workload { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _seed = new int[4096];
        for (var i = 0; i < _seed.Length; i++)
        {
            _seed[i] = i % 11 == 0 ? 0 : i - 64;
        }

        for (var i = 0; i < 8; i++)
        {
            var warm = ArrayPool<int>.Shared.Rent(_seed.Length);
            ArrayPool<int>.Shared.Return(warm);
        }

        _countNonZero = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "countNonZero");
        _scorePooledFrame = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "scorePooledFrame");
        _clampAndScore = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "clampAndScore");
    }

    [Benchmark(Baseline = true)]
    public int CSharp()
    {
        var buffer = ArrayPool<int>.Shared.Rent(_seed.Length);
        try
        {
            Array.Copy(_seed, buffer, _seed.Length);
            return Workload switch
            {
                PooledBoundaryWorkload.CountNonZero => CSharpCountNonZero(buffer, _seed.Length),
                PooledBoundaryWorkload.ScorePooledFrame => CSharpScorePooledFrame(buffer, _seed.Length),
                PooledBoundaryWorkload.ClampAndScore => CSharpClampAndScore(buffer, _seed.Length),
                _ => throw new InvalidOperationException()
            };
        }
        finally
        {
            ArrayPool<int>.Shared.Return(buffer);
        }
    }

    [Benchmark]
    public int NSharp()
    {
        var buffer = ArrayPool<int>.Shared.Rent(_seed.Length);
        try
        {
            Array.Copy(_seed, buffer, _seed.Length);
            return Workload switch
            {
                PooledBoundaryWorkload.CountNonZero => _countNonZero(buffer, _seed.Length),
                PooledBoundaryWorkload.ScorePooledFrame => _scorePooledFrame(buffer, _seed.Length),
                PooledBoundaryWorkload.ClampAndScore => _clampAndScore(buffer, _seed.Length),
                _ => throw new InvalidOperationException()
            };
        }
        finally
        {
            ArrayPool<int>.Shared.Return(buffer);
        }
    }

    private static int CSharpCountNonZero(int[] values, int len)
    {
        var count = 0;
        for (var i = 0; i < len; i++)
        {
            if (values[i] != 0)
            {
                count++;
            }
        }

        return count;
    }

    private static int CSharpScorePooledFrame(int[] values, int len)
    {
        if (len < 4)
        {
            return -1;
        }

        var score = values[0] + values[1] + values[2] + values[3];
        for (var i = 4; i < len; i++)
        {
            score += values[i];
        }

        return score;
    }

    private static int CSharpClampAndScore(int[] values, int len)
    {
        var score = 0;
        for (var i = 0; i < len; i++)
        {
            var value = values[i];
            if (value < 0)
            {
                value = 0;
            }

            values[i] = value;
            score += value;
        }

        return score;
    }
}
