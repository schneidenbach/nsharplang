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
        if value >= 32 && value <= 126 {
            count = count + 1
        }
    }

    return count
}

[hot]
func minMaxDelta(values: int[]): int {
    if values.Length == 0 {
        return 0
    }

    min := values[0]
    max := values[0]
    len := values.Length
    for i := 1; i < len; i++ {
        value := values[i]
        if value < min {
            min = value
        }

        if value > max {
            max = value
        }
    }

    return max - min
}

[hot]
func rollingHash(values: int[]): int {
    hash := 17
    len := values.Length
    for i := 0; i < len; i++ {
        hash = ((hash * 31) + values[i]) & 65535
    }

    return hash
}

[hot]
func parseEightDigits(values: int[]): int {
    if values.Length < 8 {
        return -1
    }

    parsed := 0
    for i := 0; i < 8; i++ {
        value := values[i]
        if value < 48 || value > 57 {
            return -1
        }

        parsed = parsed * 10 + (value - 48)
    }

    return parsed
}

[hot]
func countTransitions(values: int[]): int {
    if values.Length == 0 {
        return 0
    }

    transitions := 0
    previous := values[0]
    len := values.Length
    for i := 1; i < len; i++ {
        current := values[i]
        if current != previous {
            transitions = transitions + 1
        }

        previous = current
    }

    return transitions
}

[hot]
func allHot(values: int[], tag: int): int {
    total := 0
    len := values.Length
    sum := 0
    found := -1
    count := 0
    min := 0
    max := 0
    hash := 17
    parsed := 0
    parseOk := true
    transitions := 0
    previous := 0
    for i := 0; i < len; i++ {
        value := values[i]
        sum = sum + value
        if found < 0 && value == tag {
            found = i
        }

        if value >= 32 && value <= 126 {
            count = count + 1
        }

        if i == 0 {
            min = value
            max = value
        } else {
            if value < min {
                min = value
            }

            if value > max {
                max = value
            }

            if value != previous {
                transitions = transitions + 1
            }
        }

        previous = value
        hash = ((hash * 31) + value) & 65535

        if i < 8 {
            if value < 48 || value > 57 {
                parseOk = false
            }

            if parseOk {
                parsed = parsed * 10 + (value - 48)
            }
        }
    }

    total = total + sum

    if len < 4 {
        total = total - 1
    } else {
        total = total + sum
    }

    total = total + found
    total = total + count

    if len != 0 {
        total = total + max - min
    }

    total = total + hash

    if len >= 8 && parseOk {
        total = total + parsed
    } else {
        total = total - 1
    }

    total = total + transitions
    return total
}
""";

    private int[] _values = Array.Empty<int>();
    private Func<int[], int> _csharpChecksum = null!;
    private Func<int[], int> _csharpScoreFrame = null!;
    private Func<int[], int, int> _csharpScanTag = null!;
    private Func<int[], int> _csharpCountAscii = null!;
    private Func<int[], int> _csharpMinMaxDelta = null!;
    private Func<int[], int> _csharpRollingHash = null!;
    private Func<int[], int> _csharpParseEightDigits = null!;
    private Func<int[], int> _csharpCountTransitions = null!;
    private Func<int[], int, int> _csharpAllHot = null!;
    private Func<int[], int> _checksum = null!;
    private Func<int[], int> _scoreFrame = null!;
    private Func<int[], int, int> _scanTag = null!;
    private Func<int[], int> _countAscii = null!;
    private Func<int[], int> _minMaxDelta = null!;
    private Func<int[], int> _rollingHash = null!;
    private Func<int[], int> _parseEightDigits = null!;
    private Func<int[], int> _countTransitions = null!;
    private Func<int[], int, int> _allHot = null!;
    private int _tag;

    public enum HotPathWorkload
    {
        Checksum,
        ScoreFrame,
        ScanTag,
        CountAscii,
        MinMaxDelta,
        RollingHash,
        ParseEightDigits,
        CountTransitions,
    }

    [Params(
        HotPathWorkload.Checksum,
        HotPathWorkload.ScoreFrame,
        HotPathWorkload.ScanTag,
        HotPathWorkload.CountAscii,
        HotPathWorkload.MinMaxDelta,
        HotPathWorkload.RollingHash,
        HotPathWorkload.ParseEightDigits,
        HotPathWorkload.CountTransitions)]
    public HotPathWorkload Workload { get; set; }

    [Params(64, 4096)]
    public int Size { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _values = new int[Size];
        for (var i = 0; i < _values.Length; i++)
        {
            _values[i] = ((i * 17) + 3) & 0x7f;
        }

        _tag = 100_003;
        _values[^17] = _tag;
        for (var i = 0; i < Math.Min(8, _values.Length); i++)
        {
            _values[i] = 48 + (i % 10);
        }

        _csharpChecksum = CSharpChecksum;
        _csharpScoreFrame = CSharpScoreFrame;
        _csharpScanTag = CSharpScanTag;
        _csharpCountAscii = CSharpCountAscii;
        _csharpMinMaxDelta = CSharpMinMaxDelta;
        _csharpRollingHash = CSharpRollingHash;
        _csharpParseEightDigits = CSharpParseEightDigits;
        _csharpCountTransitions = CSharpCountTransitions;
        _csharpAllHot = CSharpAllHot;

        _checksum = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "checksum");
        _scoreFrame = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "scoreFrame");
        _scanTag = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "scanTag");
        _countAscii = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "countAscii");
        _minMaxDelta = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "minMaxDelta");
        _rollingHash = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "rollingHash");
        _parseEightDigits = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "parseEightDigits");
        _countTransitions = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "countTransitions");
        _allHot = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "allHot");
    }

    public int CSharpAll() => _csharpAllHot(_values, _tag);

    public int NSharpAll() => _allHot(_values, _tag);

    [Benchmark(Baseline = true)]
    public int CSharp() => Workload switch
    {
        HotPathWorkload.Checksum => _csharpChecksum(_values),
        HotPathWorkload.ScoreFrame => _csharpScoreFrame(_values),
        HotPathWorkload.ScanTag => _csharpScanTag(_values, _tag),
        HotPathWorkload.CountAscii => _csharpCountAscii(_values),
        HotPathWorkload.MinMaxDelta => _csharpMinMaxDelta(_values),
        HotPathWorkload.RollingHash => _csharpRollingHash(_values),
        HotPathWorkload.ParseEightDigits => _csharpParseEightDigits(_values),
        HotPathWorkload.CountTransitions => _csharpCountTransitions(_values),
        _ => throw new InvalidOperationException()
    };

    [Benchmark]
    public int NSharp() => Workload switch
    {
        HotPathWorkload.Checksum => _checksum(_values),
        HotPathWorkload.ScoreFrame => _scoreFrame(_values),
        HotPathWorkload.ScanTag => _scanTag(_values, _tag),
        HotPathWorkload.CountAscii => _countAscii(_values),
        HotPathWorkload.MinMaxDelta => _minMaxDelta(_values),
        HotPathWorkload.RollingHash => _rollingHash(_values),
        HotPathWorkload.ParseEightDigits => _parseEightDigits(_values),
        HotPathWorkload.CountTransitions => _countTransitions(_values),
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

    private static int CSharpMinMaxDelta(int[] values)
    {
        if (values.Length == 0)
        {
            return 0;
        }

        var min = values[0];
        var max = values[0];
        var len = values.Length;
        for (var i = 1; i < len; i++)
        {
            var value = values[i];
            if (value < min)
            {
                min = value;
            }

            if (value > max)
            {
                max = value;
            }
        }

        return max - min;
    }

    private static int CSharpRollingHash(int[] values)
    {
        var hash = 17;
        var len = values.Length;
        for (var i = 0; i < len; i++)
        {
            hash = ((hash * 31) + values[i]) & 65535;
        }

        return hash;
    }

    private static int CSharpParseEightDigits(int[] values)
    {
        if (values.Length < 8)
        {
            return -1;
        }

        var parsed = 0;
        for (var i = 0; i < 8; i++)
        {
            var value = values[i];
            if (value < 48 || value > 57)
            {
                return -1;
            }

            parsed = (parsed * 10) + (value - 48);
        }

        return parsed;
    }

    private static int CSharpCountTransitions(int[] values)
    {
        if (values.Length == 0)
        {
            return 0;
        }

        var transitions = 0;
        var previous = values[0];
        var len = values.Length;
        for (var i = 1; i < len; i++)
        {
            var current = values[i];
            if (current != previous)
            {
                transitions++;
            }

            previous = current;
        }

        return transitions;
    }

    private static int CSharpAllHot(int[] values, int tag)
        => CSharpChecksum(values)
           + CSharpScoreFrame(values)
           + CSharpScanTag(values, tag)
           + CSharpCountAscii(values)
           + CSharpMinMaxDelta(values)
           + CSharpRollingHash(values)
           + CSharpParseEightDigits(values)
           + CSharpCountTransitions(values);
}
