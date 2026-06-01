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
""";

    private int[] _source = Array.Empty<int>();
    private int[] _destination = Array.Empty<int>();
    private Func<int[], int[], int> _copyPositive = null!;
    private Func<int[], int[], int> _writeFrame = null!;
    private Func<int[], int[], int> _transform = null!;

    public enum CallerBufferWorkload
    {
        CopyPositive,
        WriteFrame,
        Transform,
    }

    [Params(
        CallerBufferWorkload.CopyPositive,
        CallerBufferWorkload.WriteFrame,
        CallerBufferWorkload.Transform)]
    public CallerBufferWorkload Workload { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = new int[4096];
        _destination = new int[_source.Length + 8];
        for (var i = 0; i < _source.Length; i++)
        {
            _source[i] = (i & 1) == 0 ? i : -i;
        }

        _copyPositive = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "copyPositive");
        _writeFrame = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "writeFrame");
        _transform = NSharpCompiledMethod.Bind<Func<int[], int[], int>>(Source, "transform");
    }

    [Benchmark(Baseline = true)]
    public int CSharp() => Workload switch
    {
        CallerBufferWorkload.CopyPositive => CSharpCopyPositive(_source, _destination),
        CallerBufferWorkload.WriteFrame => CSharpWriteFrame(_source, _destination),
        CallerBufferWorkload.Transform => CSharpTransform(_source, _destination),
        _ => throw new InvalidOperationException()
    };

    [Benchmark]
    public int NSharp() => Workload switch
    {
        CallerBufferWorkload.CopyPositive => _copyPositive(_source, _destination),
        CallerBufferWorkload.WriteFrame => _writeFrame(_source, _destination),
        CallerBufferWorkload.Transform => _transform(_source, _destination),
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
}
