using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Systems N# caller-buffer benchmarks. These exercise write-heavy hot paths where the caller
/// owns destination storage and the hot function reports bytes/items written instead of allocating.
/// </summary>
[MemoryDiagnoser]
public class SystemsCallerBufferBenchmarks
{
    private const string Source = """
[hot]
func copyPositive(src: int[], dst: int[]): int {
    written := 0
    len := src.Length
    for i := 0; i < len; i++ {
        value := src[i]
        if value >= 0 {
            dst[written] = value
            written = written + 1
        }
    }

    return written
}

[hot]
func writeFrame(src: int[], dst: int[]): int {
    len := src.Length
    if dst.Length < len + 4 {
        return -1
    }

    dst[0] = 78
    dst[1] = 35
    dst[2] = len
    dst[3] = 0

    for i := 0; i < len; i++ {
        dst[i + 4] = src[i]
    }

    return len + 4
}

[hot]
func transform(src: int[], dst: int[]): int {
    sum := 0
    len := src.Length
    for i := 0; i < len; i++ {
        value := (src[i] * 31) + 7
        dst[i] = value
        sum = sum + value
    }

    return sum
}

[hot]
func prefixSum(src: int[], dst: int[]): int {
    running := 0
    len := src.Length
    for i := 0; i < len; i++ {
        running = running + src[i]
        dst[i] = running
    }

    return running
}

[hot]
func compactEven(src: int[], dst: int[]): int {
    written := 0
    len := src.Length
    for i := 0; i < len; i++ {
        value := src[i]
        if (value & 1) == 0 {
            dst[written] = value
            written = written + 1
        }
    }

    return written
}

[hot]
func filterAndScale(src: int[], dst: int[]): int {
    written := 0
    checksum := 0
    len := src.Length
    for i := 0; i < len; i++ {
        value := src[i]
        if value > 0 {
            scaled := value * 2
            dst[written] = scaled
            written = written + 1
            checksum = checksum + scaled
        }
    }

    return checksum + written
}

[hot]
func pairSums(src: int[], dst: int[]): int {
    pairs := src.Length / 2
    if dst.Length < pairs {
        return -1
    }

    checksum := 0
    for i := 0; i < pairs; i++ {
        j := i * 2
        value := src[j] + src[j + 1]
        dst[i] = value
        checksum = checksum + value
    }

    return checksum
}
""";

    private int[] _source = Array.Empty<int>();
    private int[] _destination = Array.Empty<int>();
    private Func<int[], int[], int> _csharpCopyPositive = null!;
    private Func<int[], int[], int> _csharpWriteFrame = null!;
    private Func<int[], int[], int> _csharpTransform = null!;
    private Func<int[], int[], int> _csharpPrefixSum = null!;
    private Func<int[], int[], int> _csharpCompactEven = null!;
    private Func<int[], int[], int> _csharpFilterAndScale = null!;
    private Func<int[], int[], int> _csharpPairSums = null!;
    private Func<int[], int[], int> _copyPositive = null!;
    private Func<int[], int[], int> _writeFrame = null!;
    private Func<int[], int[], int> _transform = null!;
    private Func<int[], int[], int> _prefixSum = null!;
    private Func<int[], int[], int> _compactEven = null!;
    private Func<int[], int[], int> _filterAndScale = null!;
    private Func<int[], int[], int> _pairSums = null!;

    public enum CallerBufferWorkload
    {
        CopyPositive,
        WriteFrame,
        Transform,
        PrefixSum,
        CompactEven,
        FilterAndScale,
        PairSums,
    }

    [Params(
        CallerBufferWorkload.CopyPositive,
        CallerBufferWorkload.WriteFrame,
        CallerBufferWorkload.Transform,
        CallerBufferWorkload.PrefixSum,
        CallerBufferWorkload.CompactEven,
        CallerBufferWorkload.FilterAndScale,
        CallerBufferWorkload.PairSums)]
    public CallerBufferWorkload Workload { get; set; }

    [Params(64, 4096)]
    public int Size { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = new int[Size];
        _destination = new int[_source.Length + 8];
        for (var i = 0; i < _source.Length; i++)
        {
            _source[i] = (i & 1) == 0 ? i : -i;
        }

        _csharpCopyPositive = CSharpCopyPositive;
        _csharpWriteFrame = CSharpWriteFrame;
        _csharpTransform = CSharpTransform;
        _csharpPrefixSum = CSharpPrefixSum;
        _csharpCompactEven = CSharpCompactEven;
        _csharpFilterAndScale = CSharpFilterAndScale;
        _csharpPairSums = CSharpPairSums;

        _copyPositive = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "copyPositive");
        _writeFrame = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "writeFrame");
        _transform = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "transform");
        _prefixSum = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "prefixSum");
        _compactEven = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "compactEven");
        _filterAndScale = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "filterAndScale");
        _pairSums = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "pairSums");
    }

    [Benchmark(Baseline = true)]
    public int CSharp() => Workload switch
    {
        CallerBufferWorkload.CopyPositive => _csharpCopyPositive(_source, _destination),
        CallerBufferWorkload.WriteFrame => _csharpWriteFrame(_source, _destination),
        CallerBufferWorkload.Transform => _csharpTransform(_source, _destination),
        CallerBufferWorkload.PrefixSum => _csharpPrefixSum(_source, _destination),
        CallerBufferWorkload.CompactEven => _csharpCompactEven(_source, _destination),
        CallerBufferWorkload.FilterAndScale => _csharpFilterAndScale(_source, _destination),
        CallerBufferWorkload.PairSums => _csharpPairSums(_source, _destination),
        _ => throw new InvalidOperationException()
    };

    [Benchmark]
    public int NSharp() => Workload switch
    {
        CallerBufferWorkload.CopyPositive => _copyPositive(_source, _destination),
        CallerBufferWorkload.WriteFrame => _writeFrame(_source, _destination),
        CallerBufferWorkload.Transform => _transform(_source, _destination),
        CallerBufferWorkload.PrefixSum => _prefixSum(_source, _destination),
        CallerBufferWorkload.CompactEven => _compactEven(_source, _destination),
        CallerBufferWorkload.FilterAndScale => _filterAndScale(_source, _destination),
        CallerBufferWorkload.PairSums => _pairSums(_source, _destination),
        _ => throw new InvalidOperationException()
    };

    private static int CSharpCopyPositive(int[] source, int[] destination)
    {
        var written = 0;
        var len = source.Length;
        for (var i = 0; i < len; i++)
        {
            var value = source[i];
            if (value >= 0)
            {
                destination[written] = value;
                written++;
            }
        }

        return written;
    }

    private static int CSharpWriteFrame(int[] source, int[] destination)
    {
        var len = source.Length;
        if (destination.Length < len + 4)
        {
            return -1;
        }

        destination[0] = 78;
        destination[1] = 35;
        destination[2] = len;
        destination[3] = 0;

        for (var i = 0; i < len; i++)
        {
            destination[i + 4] = source[i];
        }

        return len + 4;
    }

    private static int CSharpTransform(int[] source, int[] destination)
    {
        var sum = 0;
        var len = source.Length;
        for (var i = 0; i < len; i++)
        {
            var value = (source[i] * 31) + 7;
            destination[i] = value;
            sum += value;
        }

        return sum;
    }

    private static int CSharpPrefixSum(int[] source, int[] destination)
    {
        var running = 0;
        var len = source.Length;
        for (var i = 0; i < len; i++)
        {
            running += source[i];
            destination[i] = running;
        }

        return running;
    }

    private static int CSharpCompactEven(int[] source, int[] destination)
    {
        var written = 0;
        var len = source.Length;
        for (var i = 0; i < len; i++)
        {
            var value = source[i];
            if ((value & 1) == 0)
            {
                destination[written] = value;
                written++;
            }
        }

        return written;
    }

    private static int CSharpFilterAndScale(int[] source, int[] destination)
    {
        var written = 0;
        var checksum = 0;
        var len = source.Length;
        for (var i = 0; i < len; i++)
        {
            var value = source[i];
            if (value > 0)
            {
                var scaled = value * 2;
                destination[written] = scaled;
                written++;
                checksum += scaled;
            }
        }

        return checksum + written;
    }

    private static int CSharpPairSums(int[] source, int[] destination)
    {
        var pairs = source.Length / 2;
        if (destination.Length < pairs)
        {
            return -1;
        }

        var checksum = 0;
        for (var i = 0; i < pairs; i++)
        {
            var j = i * 2;
            var value = source[j] + source[j + 1];
            destination[i] = value;
            checksum += value;
        }

        return checksum;
    }
}
