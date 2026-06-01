using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Systems N# hot-path benchmarks over caller-owned memory. The workloads cover direct loops,
/// guarded array indexing, sentinel scans, and simple parser-style classification.
/// </summary>
[MemoryDiagnoser]
public class SystemsHotPathBenchmarks
{
    private const string Source = """
[hot]
func checksum(values: int[]): int {
    sum := 0
    len := values.Length
    for i := 0; i < len; i++ {
        sum = sum + values[i]
    }

    return sum
}

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

[hot]
func scanTag(values: int[], tag: int): int {
    len := values.Length
    for i := 0; i < len; i++ {
        if values[i] == tag {
            return i
        }
    }

    return -1
}

[hot]
func countAscii(values: int[]): int {
    count := 0
    len := values.Length
    for i := 0; i < len; i++ {
        value := values[i]
        if value >= 32 {
            if value <= 126 {
                count = count + 1
            }
        }
    }

    return count
}
""";

    private int[] _values = Array.Empty<int>();
    private Func<int[], int> _checksum = null!;
    private Func<int[], int> _scoreFrame = null!;
    private Func<int[], int, int> _scanTag = null!;
    private Func<int[], int> _countAscii = null!;
    private int _tag;

    public enum HotPathWorkload
    {
        Checksum,
        ScoreFrame,
        ScanTag,
        CountAscii,
    }

    [Params(
        HotPathWorkload.Checksum,
        HotPathWorkload.ScoreFrame,
        HotPathWorkload.ScanTag,
        HotPathWorkload.CountAscii)]
    public HotPathWorkload Workload { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _values = new int[4096];
        for (var i = 0; i < _values.Length; i++)
        {
            _values[i] = ((i * 17) + 3) & 0x7f;
        }

        _tag = 100_003;
        _values[^17] = _tag;

        _checksum = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "checksum");
        _scoreFrame = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "scoreFrame");
        _scanTag = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "scanTag");
        _countAscii = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "countAscii");
    }

    [Benchmark(Baseline = true)]
    public int CSharp() => Workload switch
    {
        HotPathWorkload.Checksum => CSharpChecksum(_values),
        HotPathWorkload.ScoreFrame => CSharpScoreFrame(_values),
        HotPathWorkload.ScanTag => CSharpScanTag(_values, _tag),
        HotPathWorkload.CountAscii => CSharpCountAscii(_values),
        _ => throw new InvalidOperationException()
    };

    [Benchmark]
    public int NSharp() => Workload switch
    {
        HotPathWorkload.Checksum => _checksum(_values),
        HotPathWorkload.ScoreFrame => _scoreFrame(_values),
        HotPathWorkload.ScanTag => _scanTag(_values, _tag),
        HotPathWorkload.CountAscii => _countAscii(_values),
        _ => throw new InvalidOperationException()
    };

    private static int CSharpChecksum(int[] values)
    {
        var sum = 0;
        var len = values.Length;
        for (var i = 0; i < len; i++)
        {
            sum += values[i];
        }

        return sum;
    }

    private static int CSharpScoreFrame(int[] values)
    {
        if (values.Length < 4)
        {
            return -1;
        }

        var checksum = 0;
        for (var i = 4; i < values.Length; i++)
        {
            checksum += values[i];
        }

        return checksum + values[0] + values[1] + values[2] + values[3];
    }

    private static int CSharpScanTag(int[] values, int tag)
    {
        var len = values.Length;
        for (var i = 0; i < len; i++)
        {
            if (values[i] == tag)
            {
                return i;
            }
        }

        return -1;
    }

    private static int CSharpCountAscii(int[] values)
    {
        var count = 0;
        var len = values.Length;
        for (var i = 0; i < len; i++)
        {
            var value = values[i];
            if (value >= 32 && value <= 126)
            {
                count++;
            }
        }

        return count;
    }
}
