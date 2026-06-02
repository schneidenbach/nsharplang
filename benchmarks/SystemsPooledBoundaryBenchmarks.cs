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
    private const int InnerOperations = 8;

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

[hot]
func findFirstZero(values: int[], len: int): int {
    for i := 0; i < len; i++ {
        if values[i] == 0 {
            return i
        }
    }

    return -1
}

[hot]
func clampWindow(values: int[], len: int): int {
    changed := 0
    for i := 0; i < len; i++ {
        value := values[i]
        if value < 0 {
            values[i] = 0
            changed = changed + 1
        } else if value > 1024 {
            values[i] = 1024
            changed = changed + 1
        }
    }

    return changed
}

[hot]
func sumPositive(values: int[], len: int): int {
    sum := 0
    for i := 0; i < len; i++ {
        value := values[i]
        if value > 0 {
            sum = sum + value
        }
    }

    return sum
}

[hot]
func zeroOdd(values: int[], len: int): int {
    cleared := 0
    for i := 0; i < len; i++ {
        if (values[i] & 1) != 0 {
            values[i] = 0
            cleared = cleared + 1
        }
    }

    return cleared
}

[hot]
func allPooled(values: int[], len: int): int {
    total := 0
    count := 0
    frameScore := 0
    for i := 0; i < len; i++ {
        value := values[i]
        if value != 0 {
            count = count + 1
        }

        frameScore = frameScore + value
    }

    total = total + count

    if len < 4 {
        total = total - 1
    } else {
        total = total + frameScore
    }

    score := 0
    found := -1
    for i := 0; i < len; i++ {
        value := values[i]
        if value < 0 {
            value = 0
        }

        values[i] = value
        score = score + value
        if found < 0 && value == 0 {
            found = i
        }
    }

    total = total + score
    total = total + found

    changed := 0
    sum := 0
    cleared := 0
    for i := 0; i < len; i++ {
        value := values[i]
        if value > 1024 {
            values[i] = 1024
            value = 1024
            changed = changed + 1
        }

        if value > 0 {
            sum = sum + value
        }

        if (value & 1) != 0 {
            values[i] = 0
            cleared = cleared + 1
        }
    }

    return total + changed + sum + cleared
}
""";

    private int[] _seed = Array.Empty<int>();
    private Func<int[], int, int> _csharpCountNonZero = null!;
    private Func<int[], int, int> _csharpScorePooledFrame = null!;
    private Func<int[], int, int> _csharpClampAndScore = null!;
    private Func<int[], int, int> _csharpFindFirstZero = null!;
    private Func<int[], int, int> _csharpClampWindow = null!;
    private Func<int[], int, int> _csharpSumPositive = null!;
    private Func<int[], int, int> _csharpZeroOdd = null!;
    private Func<int[], int, int> _countNonZero = null!;
    private Func<int[], int, int> _scorePooledFrame = null!;
    private Func<int[], int, int> _clampAndScore = null!;
    private Func<int[], int, int> _findFirstZero = null!;
    private Func<int[], int, int> _clampWindow = null!;
    private Func<int[], int, int> _sumPositive = null!;
    private Func<int[], int, int> _zeroOdd = null!;
    private Func<int[], int, int> _allPooled = null!;

    public enum PooledBoundaryWorkload
    {
        CountNonZero,
        ScorePooledFrame,
        ClampAndScore,
        FindFirstZero,
        ClampWindow,
        SumPositive,
        ZeroOdd,
    }

    [Params(
        PooledBoundaryWorkload.CountNonZero,
        PooledBoundaryWorkload.ScorePooledFrame,
        PooledBoundaryWorkload.ClampAndScore,
        PooledBoundaryWorkload.FindFirstZero,
        PooledBoundaryWorkload.ClampWindow,
        PooledBoundaryWorkload.SumPositive,
        PooledBoundaryWorkload.ZeroOdd)]
    public PooledBoundaryWorkload Workload { get; set; }

    [Params(64, 4096)]
    public int Size { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _seed = new int[Size];
        for (var i = 0; i < _seed.Length; i++)
        {
            _seed[i] = i % 11 == 0 ? 0 : i - 64;
        }

        for (var i = 0; i < 8; i++)
        {
            var warm = ArrayPool<int>.Shared.Rent(_seed.Length);
            ArrayPool<int>.Shared.Return(warm);
        }

        _csharpCountNonZero = CSharpCountNonZero;
        _csharpScorePooledFrame = CSharpScorePooledFrame;
        _csharpClampAndScore = CSharpClampAndScore;
        _csharpFindFirstZero = CSharpFindFirstZero;
        _csharpClampWindow = CSharpClampWindow;
        _csharpSumPositive = CSharpSumPositive;
        _csharpZeroOdd = CSharpZeroOdd;

        _countNonZero = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "countNonZero");
        _scorePooledFrame = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "scorePooledFrame");
        _clampAndScore = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "clampAndScore");
        _findFirstZero = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "findFirstZero");
        _clampWindow = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "clampWindow");
        _sumPositive = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "sumPositive");
        _zeroOdd = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "zeroOdd");
        _allPooled = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "allPooled");
    }

    public int CSharpAll() => All(useNSharp: false);

    public int NSharpAll() => All(useNSharp: true);

    [Benchmark(Baseline = true, OperationsPerInvoke = InnerOperations)]
    public int CSharp()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            var buffer = ArrayPool<int>.Shared.Rent(_seed.Length);
            try
            {
                Array.Copy(_seed, buffer, _seed.Length);
                total += Workload switch
                {
                    PooledBoundaryWorkload.CountNonZero => _csharpCountNonZero(buffer, _seed.Length),
                    PooledBoundaryWorkload.ScorePooledFrame => _csharpScorePooledFrame(buffer, _seed.Length),
                    PooledBoundaryWorkload.ClampAndScore => _csharpClampAndScore(buffer, _seed.Length),
                    PooledBoundaryWorkload.FindFirstZero => _csharpFindFirstZero(buffer, _seed.Length),
                    PooledBoundaryWorkload.ClampWindow => _csharpClampWindow(buffer, _seed.Length),
                    PooledBoundaryWorkload.SumPositive => _csharpSumPositive(buffer, _seed.Length),
                    PooledBoundaryWorkload.ZeroOdd => _csharpZeroOdd(buffer, _seed.Length),
                    _ => throw new InvalidOperationException()
                };
            }
            finally
            {
                ArrayPool<int>.Shared.Return(buffer);
            }
        }

        return total;
    }

    [Benchmark(OperationsPerInvoke = InnerOperations)]
    public int NSharp()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            var buffer = ArrayPool<int>.Shared.Rent(_seed.Length);
            try
            {
                Array.Copy(_seed, buffer, _seed.Length);
                total += Workload switch
                {
                    PooledBoundaryWorkload.CountNonZero => _countNonZero(buffer, _seed.Length),
                    PooledBoundaryWorkload.ScorePooledFrame => _scorePooledFrame(buffer, _seed.Length),
                    PooledBoundaryWorkload.ClampAndScore => _clampAndScore(buffer, _seed.Length),
                    PooledBoundaryWorkload.FindFirstZero => _findFirstZero(buffer, _seed.Length),
                    PooledBoundaryWorkload.ClampWindow => _clampWindow(buffer, _seed.Length),
                    PooledBoundaryWorkload.SumPositive => _sumPositive(buffer, _seed.Length),
                    PooledBoundaryWorkload.ZeroOdd => _zeroOdd(buffer, _seed.Length),
                    _ => throw new InvalidOperationException()
                };
            }
            finally
            {
                ArrayPool<int>.Shared.Return(buffer);
            }
        }

        return total;
    }

    private int All(bool useNSharp)
    {
        var buffer = ArrayPool<int>.Shared.Rent(_seed.Length);
        try
        {
            Array.Copy(_seed, buffer, _seed.Length);
            return useNSharp
                ? _allPooled(buffer, _seed.Length)
                : _csharpCountNonZero(buffer, _seed.Length)
                  + _csharpScorePooledFrame(buffer, _seed.Length)
                  + _csharpClampAndScore(buffer, _seed.Length)
                  + _csharpFindFirstZero(buffer, _seed.Length)
                  + _csharpClampWindow(buffer, _seed.Length)
                  + _csharpSumPositive(buffer, _seed.Length)
                  + _csharpZeroOdd(buffer, _seed.Length);
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

    private static int CSharpFindFirstZero(int[] values, int len)
    {
        for (var i = 0; i < len; i++)
        {
            if (values[i] == 0)
            {
                return i;
            }
        }

        return -1;
    }

    private static int CSharpClampWindow(int[] values, int len)
    {
        var changed = 0;
        for (var i = 0; i < len; i++)
        {
            var value = values[i];
            if (value < 0)
            {
                values[i] = 0;
                changed++;
            }
            else if (value > 1024)
            {
                values[i] = 1024;
                changed++;
            }
        }

        return changed;
    }

    private static int CSharpSumPositive(int[] values, int len)
    {
        var sum = 0;
        for (var i = 0; i < len; i++)
        {
            var value = values[i];
            if (value > 0)
            {
                sum += value;
            }
        }

        return sum;
    }

    private static int CSharpZeroOdd(int[] values, int len)
    {
        var cleared = 0;
        for (var i = 0; i < len; i++)
        {
            if ((values[i] & 1) != 0)
            {
                values[i] = 0;
                cleared++;
            }
        }

        return cleared;
    }
}
